"""
Physiological Data Processing Pipeline
======================================
Loads LSL-recorded .mat files containing ECG, GSR, respiration,
and pupillometry data. Extracts per-trial summary statistics
(heart rate, HRV, skin conductance responses, pupil dilation, etc.)
and exports a single CSV.
"""

import os
import time

import neurokit2 as nk
import numpy as np
import pandas as pd
from scipy.io import loadmat
from scipy.signal import butter, find_peaks, sosfiltfilt

# ── Configuration ────────────────────────────────────────────────────────────

WORKING_DIRECTORY = os.path.abspath("../../")
FILES_DIRECTORY = os.path.join(WORKING_DIRECTORY, "osf_files/lsl_physio_data/")
OUTPUT_PATH = os.path.join(WORKING_DIRECTORY, "Python/output/", "processed_physio.csv")
SAMPLING_RATE = 5000


# ── Signal Processing ───────────────────────────────────────────────────────


def apply_butterworth_filter(data, low, high, sampling_rate, order):
    """Apply a zero-phase Butterworth bandpass filter.

    Uses a forward-backward (sosfiltfilt) pass to avoid phase distortion.
    """
    nyquist = 0.5 * sampling_rate
    sos = butter(order, [low / nyquist, high / nyquist], btype="band", output="sos")
    return sosfiltfilt(sos, data)


# ── Trial-Level Feature Extraction ──────────────────────────────────────────


def extract_trial_stats(df_physio, df_eye, markers_struct):
    """Compute physiological and oculomotor features for each trial.

    Parameters
    ----------
    df_physio : pd.DataFrame
        Timestamped physio channels (ECG, Pulse, GSR, Resp).
    df_eye : pd.DataFrame
        Timestamped pupillometry / gaze data.
    markers_struct : object
        LSL marker stream with .time_series (event codes) and .time_stamps.

    Returns
    -------
    pd.DataFrame
        One row per event (baseline or stimulus) with extracted features.
    """
    codes = np.array(markers_struct.time_series).flatten()
    times = np.array(markers_struct.time_stamps).flatten()
    df_events = pd.DataFrame({"events": codes, "time": times})

    # 0 are baselines & 1 trial events.
    events_to_process = df_events[df_events["events"].isin([0, 1])].copy()

    trial_results = []
    last_baseline_pupil = np.nan

    for i, row in events_to_process.iterrows():
        start_t = row["time"]
        end_t = start_t + 5.0  # Each trial is 5 second in duration.
        is_stimulus = row["events"] == 1

        # ── Segment the data ────────────────────────────────────────────

        mask_physio = (df_physio["time"] >= start_t) & (df_physio["time"] <= end_t)
        seg_physio = df_physio[mask_physio]

        mask_eye = (df_eye["time"] >= start_t) & (df_eye["time"] <= end_t)
        seg_eye = df_eye[mask_eye].copy()

        if len(seg_physio) == 0:
            continue

        actual_duration = seg_physio["time"].iloc[-1] - seg_physio["time"].iloc[0]

        # ── Heart rate from Pulse channel ───────────────────────────────

        peaks_pulse, _ = find_peaks(
            seg_physio["Pulse"], distance=0.7 * SAMPLING_RATE, prominence=0.5
        )
        bpm = (
            (len(peaks_pulse) / actual_duration) * 60 if actual_duration > 0 else np.nan
        )

        # ── ECG: R-peaks, HRV (RMSSD), cardiac deceleration ────────────

        ecg_signal = seg_physio["ECG"].values
        ecg_rpeaks, _ = find_peaks(
            ecg_signal,
            distance=0.5 * SAMPLING_RATE,
            height=0.3 * np.max(np.abs(ecg_signal)),
        )
        rr_intervals = np.diff(ecg_rpeaks) / SAMPLING_RATE * 1000  # ms

        ecg_bpm = np.nan
        rmssd = np.nan
        cardiac_deceleration = np.nan

        if len(ecg_rpeaks) >= 2 and actual_duration > 0:
            ecg_bpm = (len(ecg_rpeaks) / actual_duration) * 60

        if len(rr_intervals) >= 2:
            # Root mean square of successive R-R differences (vagal tone index).
            rmssd = np.sqrt(np.mean(np.diff(rr_intervals) ** 2))

        if len(rr_intervals) >= 3:
            # Cardiac deceleration: second-half mean R-R minus first-half mean R-R.
            # Positive values indicate deceleration (orienting response to threat).
            midpoint = len(rr_intervals) // 2
            cardiac_deceleration = np.mean(rr_intervals[midpoint:]) - np.mean(
                rr_intervals[:midpoint]
            )

        # ── GSR: phasic SCR extraction (neurokit2) ─────────────────────

        gsr_signal = seg_physio["GSR_MR_100_xx"].values
        try:
            eda_decomposed = nk.eda_phasic(
                nk.standardize(gsr_signal), sampling_rate=SAMPLING_RATE
            )
            scr_phasic = eda_decomposed["EDA_Phasic"].values
            scr_amplitude = np.max(scr_phasic) - np.min(scr_phasic)
            scr_peak = np.max(scr_phasic)
        except Exception:
            scr_amplitude = np.nan
            scr_peak = np.nan

        # ── Build result row ────────────────────────────────────────────

        res = {
            "trial_index": i,
            "marker_code": row["events"],
            "is_baseline": int(row["events"] == 0),
            "bpm_pulse": bpm,
            "bpm_ecg": ecg_bpm,
            "rmssd": rmssd,
            "cardiac_deceleration": cardiac_deceleration,
            "scr_amplitude": scr_amplitude,
            "scr_peak": scr_peak,
            "resp_std": seg_physio["Resp"].std(),
        }

        # ── Eye-tracking metrics ────────────────────────────────────────

        if len(seg_eye) > 0:
            valid_eye = seg_eye[seg_eye["confidence"] > 0.6]

            if len(valid_eye) > 10:
                current_pupil = (
                    valid_eye[["diameter0_3d", "diameter1_3d"]].mean().mean()
                )
                res["pupil_diam_raw"] = current_pupil

                if is_stimulus:
                    # Change in pupil diameter relative to preceding baseline.
                    res["pupil_dilation_speed"] = current_pupil - last_baseline_pupil

                    # Gaze dispersion (RMS distance from centroid), skipping
                    # the first second to isolate the orienting response.
                    # NOTE: assumes stimuli are screen-centered. If stimulus
                    # position varies, compute dispersion relative to the
                    # stimulus location instead.
                    stable_eye = valid_eye[valid_eye["time"] >= (start_t + 1.0)]
                    if len(stable_eye) > 5:
                        centroid_x = stable_eye["norm_pos_x"].mean()
                        centroid_y = stable_eye["norm_pos_y"].mean()
                        distances = np.sqrt(
                            (stable_eye["norm_pos_x"] - centroid_x) ** 2
                            + (stable_eye["norm_pos_y"] - centroid_y) ** 2
                        )
                        res["gaze_dispersion"] = np.sqrt(np.mean(distances**2))
                    else:
                        res["gaze_dispersion"] = np.nan
                else:
                    # Baseline epoch: store pupil size for later comparison.
                    last_baseline_pupil = current_pupil
                    res["pupil_dilation_speed"] = np.nan
                    res["gaze_dispersion"] = np.nan

                res["eye_conf_mean"] = valid_eye["confidence"].mean()
            else:
                res["pupil_diam_raw"] = np.nan
                res["pupil_dilation_speed"] = np.nan
                res["gaze_dispersion"] = np.nan
                res["eye_conf_mean"] = np.nan

        trial_results.append(res)

    return pd.DataFrame(trial_results)


# ── Per-Participant Processing ───────────────────────────────────────────────


def process_participant(file_name):
    """Load a single .mat file and return a summary DataFrame."""
    full_path = os.path.join(FILES_DIRECTORY, file_name)
    raw_mat = loadmat(full_path, squeeze_me=True, struct_as_record=False)

    # Identify each LSL stream by name.
    physio_struct = None
    eye_struct = None
    markers_struct = None

    for stream in raw_mat["lsl_data"]:
        name = stream.info.name
        if name == "BrainVision RDA":
            physio_struct = stream
        elif name == "fear_stream":
            markers_struct = stream
        elif name == "pupil_capture":
            eye_struct = stream

    # Build physio DataFrame and bandpass-filter the ECG channel.
    labels_p = [ch.label for ch in physio_struct.info.desc.channels.channel]
    df_physio = pd.DataFrame(physio_struct.time_series.T, columns=labels_p)
    df_physio["time"] = physio_struct.time_stamps
    df_physio["ECG"] = apply_butterworth_filter(
        df_physio["ECG"], 0.5, 40, SAMPLING_RATE, 4
    )

    # Build eye-tracking DataFrame.
    labels_e = [ch.label for ch in eye_struct.info.desc.channels.channel]
    df_eye = pd.DataFrame(eye_struct.time_series.T, columns=labels_e)
    df_eye["time"] = eye_struct.time_stamps

    summary = extract_trial_stats(df_physio, df_eye, markers_struct)
    summary["participant_id"] = file_name.split("_")[1]

    return summary


# ── Main ─────────────────────────────────────────────────────────────────────


if __name__ == "__main__":
    TEST_FILE = None  # Set to file name to run individual files.

    if not os.path.exists(FILES_DIRECTORY):
        print(f"Error: folder not found --> {FILES_DIRECTORY}")
    else:
        if TEST_FILE:
            files = [TEST_FILE]
            print(f"--- TEST MODE: processing {TEST_FILE} ---")
        else:
            files = [f for f in os.listdir(FILES_DIRECTORY) if f.endswith(".mat")]
            print(f"Starting processing of {len(files)} file(s)...")

        all_data = []
        total_start = time.time()

        for f in files:
            file_start = time.time()
            try:
                res = process_participant(f)
                all_data.append(res)
                print(f"Success for {f}  ({time.time() - file_start:.2f}s)")
            except Exception as e:
                print(f"Failure for {f}  ({time.time() - file_start:.2f}s) — {e}")

        print(f"\nTotal: {time.time() - total_start:.2f}s for {len(files)} file(s).")

        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            output_dir = os.path.dirname(OUTPUT_PATH)

            if TEST_FILE:
                output_name = os.path.join(
                    output_dir, f"test_eye_{TEST_FILE.replace('.mat', '.csv')}"
                )
            else:
                output_name = OUTPUT_PATH

            final_df.to_csv(output_name, index=False)
            print(f"Saved {output_name}")
            print(f"Columns: {list(final_df.columns)}")
