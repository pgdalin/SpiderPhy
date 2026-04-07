"""
Gaze Data Extraction and Drift Correction Pipeline
====================================================

Processes .mat files containing LSL-recorded eye-tracking and event marker
streams. For each stimulus trial, computes a drift-correction offset from
the preceding fixation period and applies it to the gaze samples.

Input:  .mat files from a configurable directory
Output: consolidated CSV of corrected gaze data

Usage:
    python gaze_extraction.py                           # process all .mat files
    python gaze_extraction.py --file ID_001_lsl_data.mat  # single file
    python gaze_extraction.py --input-dir ./data --output ./out/gaze.csv
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
from scipy.io import loadmat

# ──────────────────────────────────────────────
#  Configuration
# ──────────────────────────────────────────────

WORKING_DIRECTORY = Path(__file__).resolve().parents[1]
DEFAULT_INPUT_DIR = WORKING_DIRECTORY / "osf_files" / "lsl_physio_data"
DEFAULT_OUTPUT_PATH = WORKING_DIRECTORY / "Python" / "output" / "gaze_data.csv"

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PipelineConfig:
    """Centralised, immutable parameters for the extraction pipeline."""

    confidence_threshold: float = 0.6
    fixation_window_sec: float = 1.0
    stimulus_window_sec: float = 5.0
    screen_centre: tuple[float, float] = (0.5, 0.5)
    min_fixation_samples: int = 10
    fixation_marker_code: int = 0
    stimulus_marker_code: int = 1
    eye_stream_name: str = "pupil_capture"
    marker_stream_name: str = "fear_stream"
    required_eye_channels: tuple[str, ...] = ("norm_pos_x", "norm_pos_y", "confidence")


# ──────────────────────────────────────────────
#  Custom exceptions
# ──────────────────────────────────────────────

class GazeExtractionError(Exception):
    """Base exception for this module."""


class StreamNotFoundError(GazeExtractionError):
    """A required LSL stream is missing from the .mat file."""


class ChannelNotFoundError(GazeExtractionError):
    """A required channel label is missing from an LSL stream."""


class MalformedMatFileError(GazeExtractionError):
    """The .mat file structure does not match expectations."""


# ──────────────────────────────────────────────
#  Data-loading helpers
# ──────────────────────────────────────────────

def _load_mat_file(filepath: Path) -> dict:
    """Load a .mat file and return its raw contents.

    Raises
    ------
    FileNotFoundError
        If *filepath* does not exist.
    MalformedMatFileError
        If the file cannot be read or lacks an ``lsl_data`` key.
    """
    if not filepath.is_file():
        raise FileNotFoundError(f"File not found: {filepath}")

    try:
        raw = loadmat(str(filepath), squeeze_me=True, struct_as_record=False)
    except Exception as exc:
        raise MalformedMatFileError(f"Cannot read .mat file {filepath}: {exc}") from exc

    if "lsl_data" not in raw:
        raise MalformedMatFileError(f"Missing 'lsl_data' key in {filepath}")

    return raw


def _find_stream(lsl_data, stream_name: str):
    """Return the first LSL stream whose ``info.name`` matches *stream_name*.

    Raises
    ------
    StreamNotFoundError
        If no matching stream exists.
    """
    for stream in lsl_data:
        try:
            if stream.info.name == stream_name:
                return stream
        except AttributeError:
            continue
    raise StreamNotFoundError(f"Stream '{stream_name}' not found in lsl_data")


def _build_eye_dataframe(
    eye_stream,
    required_channels: tuple[str, ...],
) -> pd.DataFrame:
    """Convert an LSL eye-tracking stream to a tidy DataFrame.

    Parameters
    ----------
    eye_stream
        LSL stream object with ``time_stamps``, ``time_series`` and
        ``info.desc.channels.channel`` attributes.
    required_channels
        Channel labels that must be present (e.g. ``norm_pos_x``).

    Returns
    -------
    pd.DataFrame
        Columns: ``time``, ``x``, ``y``, ``confidence``.

    Raises
    ------
    ChannelNotFoundError
        If any required channel label is missing.
    """
    try:
        labels = [ch.label for ch in eye_stream.info.desc.channels.channel]
    except AttributeError as exc:
        raise MalformedMatFileError(
            "Eye stream lacks expected channel metadata"
        ) from exc

    missing = set(required_channels) - set(labels)
    if missing:
        raise ChannelNotFoundError(f"Missing eye-stream channels: {missing}")

    idx_x = labels.index("norm_pos_x")
    idx_y = labels.index("norm_pos_y")
    idx_conf = labels.index("confidence")

    return pd.DataFrame({
        "time": eye_stream.time_stamps,
        "x": eye_stream.time_series[idx_x],
        "y": eye_stream.time_series[idx_y],
        "confidence": eye_stream.time_series[idx_conf],
    })


def _build_marker_dataframe(marker_stream) -> pd.DataFrame:
    """Convert an LSL event-marker stream to a tidy DataFrame.

    Returns
    -------
    pd.DataFrame
        Columns: ``time``, ``code``.
    """
    return pd.DataFrame({
        "time": marker_stream.time_stamps,
        "code": marker_stream.time_series,
    })


# ──────────────────────────────────────────────
#  Drift correction
# ──────────────────────────────────────────────

def _compute_drift_offset(
    fixation_segment: pd.DataFrame,
    screen_centre: tuple[float, float],
) -> tuple[float, float]:
    """Return (offset_x, offset_y) from *screen_centre*.

    Parameters
    ----------
    fixation_segment
        Gaze samples during the fixation period (must contain ``x`` and ``y``).
    screen_centre
        Expected gaze position during fixation.

    Returns
    -------
    tuple[float, float]
    """
    return (
        fixation_segment["x"].mean() - screen_centre[0],
        fixation_segment["y"].mean() - screen_centre[1],
    )


def _apply_drift_correction(
    stimulus_segment: pd.DataFrame,
    offset_x: float,
    offset_y: float,
) -> pd.DataFrame:
    """Return a copy of *stimulus_segment* with drift correction applied."""
    corrected = stimulus_segment.copy()
    corrected["x"] -= offset_x
    corrected["y"] -= offset_y
    return corrected


# ──────────────────────────────────────────────
#  Single-trial extraction
# ──────────────────────────────────────────────

def _extract_trial(
    stim_time: float,
    trial_index: int,
    df_eye: pd.DataFrame,
    df_events: pd.DataFrame,
    cfg: PipelineConfig,
) -> Optional[pd.DataFrame]:
    """Process a single stimulus trial, returning corrected gaze or None.

    Steps:
        1. Check that a preceding fixation marker exists.
        2. Extract fixation-period samples and filter by confidence.
        3. Compute drift offset from fixation samples.
        4. Extract stimulus-period samples and apply correction.

    Returns
    -------
    pd.DataFrame or None
        Corrected gaze samples with ``trial_index`` column, or ``None`` if
        the trial could not be processed.
    """
    # 1) Preceding fixation marker
    baselines = df_events[
        (df_events["code"] == cfg.fixation_marker_code)
        & (df_events["time"] < stim_time)
    ]
    if baselines.empty:
        logger.debug("Trial %d: no preceding fixation marker — skipped", trial_index)
        return None

    # 2) Fixation-period gaze (last N seconds before stimulus)
    fix_start = stim_time - cfg.fixation_window_sec
    fix_mask = (df_eye["time"] >= fix_start) & (df_eye["time"] < stim_time)
    fix_seg = df_eye.loc[fix_mask]
    fix_seg = fix_seg[fix_seg["confidence"] >= cfg.confidence_threshold]

    if len(fix_seg) < cfg.min_fixation_samples:
        logger.debug(
            "Trial %d: only %d fixation samples (need %d) — skipped",
            trial_index, len(fix_seg), cfg.min_fixation_samples,
        )
        return None

    # 3) Drift offset
    offset_x, offset_y = _compute_drift_offset(fix_seg, cfg.screen_centre)

    # 4) Stimulus-period gaze
    stim_end = stim_time + cfg.stimulus_window_sec
    stim_mask = (df_eye["time"] >= stim_time) & (df_eye["time"] <= stim_end)
    stim_seg = df_eye.loc[stim_mask]
    stim_seg = stim_seg[stim_seg["confidence"] >= cfg.confidence_threshold]

    if stim_seg.empty:
        logger.debug("Trial %d: no stimulus samples above confidence threshold", trial_index)
        return None

    corrected = _apply_drift_correction(stim_seg, offset_x, offset_y)
    corrected["trial_index"] = trial_index
    return corrected


# ──────────────────────────────────────────────
#  Per-participant extraction
# ──────────────────────────────────────────────

def _extract_participant_id(filename: str) -> str:
    """Derive a participant identifier from the .mat filename.

    Expects the pattern ``ID_<NNN>_…``.  Falls back to the full stem if
    the pattern does not match.
    """
    parts = filename.split("_")
    if len(parts) >= 2:
        return parts[1]
    return Path(filename).stem


def retrieve_gaze_data(
    filepath: Path,
    cfg: PipelineConfig | None = None,
) -> pd.DataFrame:
    """Extract and drift-correct gaze data for a single participant.

    Parameters
    ----------
    filepath
        Full path to the participant's .mat file.
    cfg
        Pipeline parameters.  Uses defaults when omitted.

    Returns
    -------
    pd.DataFrame
        Columns: ``time``, ``x``, ``y``, ``confidence``, ``trial_index``,
        ``participant_id``.  Empty if no valid trials are found.

    Raises
    ------
    GazeExtractionError (or subclass)
        For structural / data issues that prevent processing.
    """
    if cfg is None:
        cfg = PipelineConfig()

    raw_mat = _load_mat_file(filepath)

    eye_stream = _find_stream(raw_mat["lsl_data"], cfg.eye_stream_name)
    marker_stream = _find_stream(raw_mat["lsl_data"], cfg.marker_stream_name)

    df_eye = _build_eye_dataframe(eye_stream, cfg.required_eye_channels)
    df_events = _build_marker_dataframe(marker_stream)

    stimuli = df_events[df_events["code"] == cfg.stimulus_marker_code]
    logger.info(
        "%s — %d stimulus events found", filepath.name, len(stimuli),
    )

    trial_frames: list[pd.DataFrame] = []
    for trial_idx, (_, stim_row) in enumerate(stimuli.iterrows()):
        result = _extract_trial(stim_row["time"], trial_idx, df_eye, df_events, cfg)
        if result is not None:
            trial_frames.append(result)

    if not trial_frames:
        logger.warning("%s — no valid trials produced", filepath.name)
        return pd.DataFrame()

    combined = pd.concat(trial_frames, ignore_index=True)
    combined["participant_id"] = _extract_participant_id(filepath.name)

    logger.info(
        "%s — %d trials, %d samples retained",
        filepath.name, len(trial_frames), len(combined),
    )
    return combined


# ──────────────────────────────────────────────
#  Batch orchestration
# ──────────────────────────────────────────────

def process_batch(
    input_dir: Path,
    output_path: Path,
    single_file: str | None = None,
    cfg: PipelineConfig | None = None,
) -> Path | None:
    """Run the pipeline over one or many .mat files and write a CSV.

    Parameters
    ----------
    input_dir
        Directory containing .mat files.
    output_path
        Destination CSV path.
    single_file
        If given, process only this filename instead of the full directory.
    cfg
        Pipeline parameters.

    Returns
    -------
    Path or None
        The path to the written CSV, or ``None`` if nothing was produced.
    """
    if cfg is None:
        cfg = PipelineConfig()

    if not input_dir.is_dir():
        logger.error("Input directory not found: %s", input_dir)
        return None

    if single_file:
        mat_files = [single_file]
        logger.info("Single-file mode: %s", single_file)
    else:
        mat_files = sorted(f for f in os.listdir(input_dir) if f.endswith(".mat"))
        logger.info("Found %d .mat file(s) in %s", len(mat_files), input_dir)

    if not mat_files:
        logger.warning("No .mat files to process")
        return None

    all_data: list[pd.DataFrame] = []
    successes = 0
    failures = 0
    t_start = time.perf_counter()

    for filename in mat_files:
        filepath = input_dir / filename
        t_file = time.perf_counter()
        try:
            df = retrieve_gaze_data(filepath, cfg)
            if not df.empty:
                all_data.append(df)
            successes += 1
            logger.info("%s processed in %.2fs", filename, time.perf_counter() - t_file)
        except GazeExtractionError as exc:
            failures += 1
            logger.error("%s — extraction error: %s", filename, exc)
        except Exception:
            failures += 1
            logger.exception("%s — unexpected error", filename)

    elapsed = time.perf_counter() - t_start
    logger.info(
        "Batch complete: %d succeeded, %d failed, %.2fs total",
        successes, failures, elapsed,
    )

    if not all_data:
        logger.warning("No data produced — CSV not written")
        return None

    final_df = pd.concat(all_data, ignore_index=True)

    # Determine output path
    if single_file:
        csv_name = single_file.replace(".mat", ".csv")
        dest = output_path.parent / f"test_gaze_{csv_name}"
    else:
        dest = output_path

    dest.parent.mkdir(parents=True, exist_ok=True)
    final_df.to_csv(dest, index=False)
    logger.info("CSV written to %s (%d rows)", dest, len(final_df))
    return dest


# ──────────────────────────────────────────────
#  CLI
# ──────────────────────────────────────────────

def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract drift-corrected gaze data from LSL .mat files.",
    )
    parser.add_argument(
        "--input-dir", type=Path, default=DEFAULT_INPUT_DIR,
        help="Directory containing .mat files (default: %(default)s)",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT_PATH,
        help="Output CSV path (default: %(default)s)",
    )
    parser.add_argument(
        "--file", type=str, default=None,
        help="Process a single .mat file instead of the whole directory",
    )
    parser.add_argument(
        "--confidence", type=float, default=0.6,
        help="Minimum gaze confidence to keep a sample (default: 0.6)",
    )
    parser.add_argument(
        "--fixation-window", type=float, default=1.0,
        help="Seconds before stimulus used for drift estimation (default: 1.0)",
    )
    parser.add_argument(
        "--stimulus-window", type=float, default=5.0,
        help="Seconds after stimulus onset to extract (default: 5.0)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable DEBUG-level logging",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Entry point. Returns 0 on success, 1 on failure."""
    args = _parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%H:%M:%S",
    )

    cfg = PipelineConfig(
        confidence_threshold=args.confidence,
        fixation_window_sec=args.fixation_window,
        stimulus_window_sec=args.stimulus_window,
    )

    result = process_batch(
        input_dir=args.input_dir,
        output_path=args.output,
        single_file=args.file,
        cfg=cfg,
    )

    return 0 if result is not None else 1


if __name__ == "__main__":
    sys.exit(main())
