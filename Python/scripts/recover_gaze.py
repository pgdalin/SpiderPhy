"""
Gaze Data Extraction and Drift Correction Pipeline

Processes .mat files containing LSL-recorded eye-tracking and event marker
streams. For each stimulus trial, computes a drift-correction offset from
the preceding fixation period and applies it to the gaze samples.

Input:  .mat files from <MAT_FILES_DIR>
Output: consolidated CSV of corrected gaze data to <OUTPUT_PATH>
"""

import os
import time

import numpy as np
import pandas as pd
from scipy.io import loadmat

# ----- Configuration -----
WORKING_DIRECTORY = os.path.abspath("../../")
MAT_FILES_DIR = os.path.join(WORKING_DIRECTORY, "osf_files/lsl_physio_data/")
OUTPUT_PATH = os.path.join(WORKING_DIRECTORY, "Python/output/", "gaze_data.csv")


def retrieve_gaze_data(FILE_NAME):
    """
    Extract and correct gaze data from a single participant's .mat file.

    Loads LSL streams (eye-tracking + event markers), then for each stimulus
    trial computes a drift-correction offset from the preceding fixation
    period and applies it to the stimulus gaze samples.

    Parameters
    ----------
    FILE_NAME : str
        Name of the .mat file (e.g. 'ID_001_lsl_data.mat').

    Returns
    -------
    pd.DataFrame
        Drift-corrected gaze samples for all valid trials, with columns:
        'time', 'x', 'y', 'confidence', 'trial_index', 'participant_id'.
        Returns an empty DataFrame if no valid trials are found.
    """
    path = os.path.join(MAT_FILES_DIR, FILE_NAME)
    raw_mat = loadmat(path, squeeze_me=True, struct_as_record=False)

    # --- Retrieve LSL streams ---
    # 'pupil_capture': gaze positions (x, y) and confidence
    # 'fear_stream': event markers (0 = fixation onset, 1 = stimulus onset)
    eye_stream = next(c for c in raw_mat["lsl_data"] if c.info.name == "pupil_capture")
    marker_stream = next(c for c in raw_mat["lsl_data"] if c.info.name == "fear_stream")

    # --- Build eye-tracking DataFrame ---
    eye_labels = [c.label for c in eye_stream.info.desc.channels.channel]
    idx_x = eye_labels.index("norm_pos_x")
    idx_y = eye_labels.index("norm_pos_y")
    idx_conf = eye_labels.index("confidence")

    df_eye_raw = pd.DataFrame(
        {
            "time": eye_stream.time_stamps,
            "x": eye_stream.time_series[idx_x],
            "y": eye_stream.time_series[idx_y],
            "confidence": eye_stream.time_series[idx_conf],
        }
    )

    # --- Build event markers DataFrame ---
    df_events = pd.DataFrame(
        {"time": marker_stream.time_stamps, "code": marker_stream.time_series}
    )

    all_trials_gaze = []

    # --- Process each stimulus trial (code == 1) ---
    df_stimuli = df_events[df_events["code"] == 1].copy()

    for i, stim_row in df_stimuli.iterrows():
        stim_start = stim_row["time"]

        # Find the most recent fixation marker (code == 0) before this stimulus
        potential_baselines = df_events[
            (df_events["code"] == 0) & (df_events["time"] < stim_start)
        ]

        if potential_baselines.empty:
            continue  # No preceding fixation available for drift correction

        # Extract gaze samples from the last 1 s of the fixation period
        mask_fix = (df_eye_raw["time"] >= (stim_start - 1.0)) & (
            df_eye_raw["time"] < stim_start
        )
        fix_seg = df_eye_raw[mask_fix].copy()
        fix_seg = fix_seg[fix_seg["confidence"] >= 0.6]

        if fix_seg.empty or len(fix_seg) < 10:
            continue  # Too few reliable samples to estimate offset

        # Compute drift offset relative to screen centre (0.5, 0.5)
        offset_x = fix_seg["x"].mean() - 0.5
        offset_y = fix_seg["y"].mean() - 0.5

        # Extract stimulus gaze samples (5 s window)
        mask_stim = (df_eye_raw["time"] >= stim_start) & (
            df_eye_raw["time"] <= stim_start + 5.0
        )
        stim_seg = df_eye_raw[mask_stim].copy()
        stim_seg = stim_seg[stim_seg["confidence"] >= 0.6]

        if not stim_seg.empty:
            # Apply drift correction
            stim_seg["x"] = stim_seg["x"] - offset_x
            stim_seg["y"] = stim_seg["y"] - offset_y

            stim_seg["trial_index"] = i
            all_trials_gaze.append(stim_seg)

    # --- Consolidate all trials ---
    if all_trials_gaze:
        result = pd.concat(all_trials_gaze, ignore_index=True)
        # Participant ID extracted from filename (e.g. 'ID_001_...' -> '001')
        result["participant_id"] = FILE_NAME.split("_")[1]
    else:
        result = pd.DataFrame()

    return result


# ----- Main execution -----

if __name__ == "__main__":
    TEST_FILE = None  # Set to a filename to run it.

    if not os.path.exists(MAT_FILES_DIR):
        print(f"Error: Directory not found -> {MAT_FILES_DIR}")
    else:
        if TEST_FILE:
            files = [TEST_FILE]
            print(f"--- TEST MODE: Processing {TEST_FILE} ---")
        else:
            files = [f for f in os.listdir(MAT_FILES_DIR) if f.endswith(".mat")]
            print(f"Starting processing of {len(files)} file(s)...")

        all_data = []
        total_start = time.time()

        for f in files:
            try:
                file_start = time.time()
                res = retrieve_gaze_data(f)
                all_data.append(res)
                file_elapsed = time.time() - file_start
                print(f"Success for {f}! ({file_elapsed:.2f}s)")
            except Exception as e:
                print(f"Failed for {f}! Error: {e}")

        total_elapsed = time.time() - total_start
        print(f"\nTotal time: {total_elapsed:.2f}s for {len(files)} file(s).")

        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            output_name = os.path.join(
                os.path.dirname(OUTPUT_PATH),
                f"test_gaze_{TEST_FILE.replace('.mat', '.csv')}"
                if TEST_FILE
                else OUTPUT_PATH,
            )
            final_df.to_csv(output_name, index=False)
            print(f"\nProcessing complete. File saved: {output_name}")
