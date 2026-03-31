import os # Allow for generalisation of paths.
import pandas as pd # Allows to use pandas df.
import numpy as np # Allows to use arrays and mathematical functions.
import time # Allows to measure processing time.
from scipy.signal import sosfiltfilt, butter # Allow to use EEG/ECG filters.
from scipy.io import loadmat # Allows to load .mat files into Python.
from scipy.signal import find_peaks # Allows to find the heartrate 

# Setting paths.

WORKING_DIRECTORY = os.path.abspath('../../') # Setting our work directory.
FILES_DIRECTORY = os.path.join(WORKING_DIRECTORY, "osf_files/lsl_physio_data/") # Setting the directory of the lsl data.
SAMPLING_RATE = 5000 # Sampling rate of the ECG.
OUTPUT_PATH = os.path.join(WORKING_DIRECTORY, "Python/output/", "processed_physio.csv") # Where to output the files.

# This function will allow for the passing of a filter on the ECG data.

def apply_butterworth_filter(DATA, LOW, HIGH, SAMPLING_RATE, ORDER):

    nyquist = 0.5 * SAMPLING_RATE
    low = LOW / nyquist
    high = HIGH / nyquist
    sos = butter(ORDER, [low, high], btype="band", output="sos") # We define the filter.

    return sosfiltfilt(sos, DATA) # We apply a double pass to preserve temporality.

# This function will allow to gather the data specific to trials.

def extract_trial_stats(DF_PHYSIO, DF_EYE, MARKERS_STRUCT):
    
    codes = np.array(MARKERS_STRUCT.time_series).flatten() # Flattening to prevent dimension errors.
    times = np.array(MARKERS_STRUCT.time_stamps).flatten()
    df_events = pd.DataFrame({'events': codes, 'time': times})
    
    events_to_process = df_events[df_events['events'].isin([0, 1])].copy() # We'll only keep events that are either a baseline or a trial.

    trial_results = [] # Initiating a list to append results.
    
    last_baseline_pupil = np.nan # Initiating a variable to keep the baseline pupil value and compare it to trial.

    for i, row in events_to_process.iterrows():
        start_t = row['time'] # for each event (0 or 1), this is the start time.
        end_t = start_t + 5.0 # The end time is whatever it was + 5 seconds.
        is_stimulus = (row['events'] == 1) # If 1 then it's the stimulus.

        # --- DÉCOUPAGE ---
        mask_physio = (DF_PHYSIO['time'] >= start_t) & (DF_PHYSIO['time'] <= end_t) # Creating a mask for each events with this temporal window.
        seg_physio = DF_PHYSIO[mask_physio] # Applying the mask on ECG data.

        mask_eye = (DF_EYE['time'] >= start_t) & (DF_EYE['time'] <= end_t) # Same process, but for eye data.
        seg_eye = DF_EYE[mask_eye].copy()

        if len(seg_physio) > 0:

            peaks, _ = find_peaks(seg_physio['Pulse'], distance=0.7*SAMPLING_RATE, prominence=0.5) # Finding the peaks.
            
            res = {
                'trial_index': i, # Trial index.
                'marker_code': row['events'], # The code (0 or 1)
                'is_baseline': 1 if row['events'] == 0 else 0, # Basically the same as previous one.
                'bpm': (len(peaks)/5) * 60, # The heartrate.
                'gsr_phasic': seg_physio['GSR_MR_100_xx'].max() - seg_physio['GSR_MR_100_xx'].min(), # The difference between highest and lowest skin conductance.
                'resp_std': seg_physio['Resp'].std() # std deviation of respiration.
            }

            if len(seg_eye) > 0:
                valid_eye = seg_eye[seg_eye['confidence'] > 0.6] # We exclude rows that are blinks or where the instrument lost track.
                
                if len(valid_eye) > 10: 

                    current_pupil = valid_eye[['diameter0_3d', 'diameter1_3d']].mean().mean() # mean diameter of the pupil.
                    res['pupil_diam_raw'] = current_pupil # 
                    
                    if is_stimulus:

                        res['pupil_dilation_speed'] = current_pupil - last_baseline_pupil # Difference between baseline and current pupil size.
                        
                        stable_eye = valid_eye[valid_eye['time'] >= (start_t + 1.0)] # We exclude first sec, because spiders aren't at the center everytime.
                        if len(stable_eye) > 5: # Enough data_points.
                            res['gaze_dispersion'] = np.sqrt(stable_eye['norm_pos_x'].std()**2 + 
                                                             stable_eye['norm_pos_y'].std()**2) # Formula for gaze dispertion.
                        else:
                            res['gaze_dispersion'] = np.nan # If not enough data points then NA.
                    else:
                        last_baseline_pupil = current_pupil # If baseline then we just append this value to last_baseline_pupil for later comparison.
                        res['pupil_dilation_speed'] = np.nan
                        res['gaze_dispersion'] = np.nan
                    
                    res['eye_conf_mean'] = valid_eye['confidence'].mean() # 
                else:
                    res['pupil_diam_raw'] = np.nan # If there's not enough values then NA everywhere.
                    res['pupil_dilation_speed'] = np.nan
                    res['gaze_dispersion'] = np.nan
                    res['eye_conf_mean'] = np.nan

            trial_results.append(res)
            
    return pd.DataFrame(trial_results)

def process_participants(FILE_NAME):
    full_path = os.path.join(FILES_DIRECTORY, FILE_NAME)
    raw_mat = loadmat(full_path, squeeze_me=True, struct_as_record=False)

    PHYSIO_STRUCT = None
    EYE_STRUCT = None
    MARKERS_STRUCT = None

    for stream in raw_mat['lsl_data']:
        name = stream.info.name
        if name == "BrainVision RDA":
            PHYSIO_STRUCT = stream
        elif name == "fear_stream":
            MARKERS_STRUCT = stream
        elif name == "pupil_capture": 
            EYE_STRUCT = stream

    labels_p = [c.label for c in PHYSIO_STRUCT.info.desc.channels.channel]
    df_physio = pd.DataFrame(PHYSIO_STRUCT.time_series.T, columns=labels_p)
    df_physio['time'] = PHYSIO_STRUCT.time_stamps
    df_physio['ECG'] = apply_butterworth_filter(df_physio['ECG'], 0.5, 40, 5000, 4)

    labels_e = [c.label for c in EYE_STRUCT.info.desc.channels.channel]
    
    df_eye = pd.DataFrame(EYE_STRUCT.time_series.T, columns=labels_e)
    df_eye['time'] = EYE_STRUCT.time_stamps

    summary = extract_trial_stats(df_physio, df_eye, MARKERS_STRUCT)
    summary['participant_id'] = FILE_NAME.split('_')[1]

    return summary

# Calling the script.

if __name__ == "__main__":

    TEST_FILE = None # "ID_001_lsl_data.mat" 

    if not os.path.exists(FILES_DIRECTORY):
        print(f"Error : Folder not found -> {FILES_DIRECTORY}")
    else:

        if TEST_FILE: 
            files = [TEST_FILE]
            print(f"--- TEST MODE : treating {TEST_FILE} ---")
        else:
            files = [f for f in os.listdir(FILES_DIRECTORY) if f.endswith(".mat")]
            print(f"Starting processing of {len(files)} files...")

        all_data = []
        total_start = time.time() # Start the total timer before the loop.

        for f in files:
            try:
                file_start = time.time() # Start the per-file timer.
                res = process_participants(f) 
                file_elapsed = time.time() - file_start # Compute elapsed time for this file.
                all_data.append(res)
                print(f"Success for {f}! (processed in {file_elapsed:.2f}s)")
            except Exception as e:
                file_elapsed = time.time() - file_start # Still report time even on failure.
                print(f"Failure for {f}! Error: {e} (failed after {file_elapsed:.2f}s)")

        total_elapsed = time.time() - total_start # Compute total elapsed time.
        print(f"\nTotal processing time: {total_elapsed:.2f}s for {len(files)} file(s).")

        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            output_dir = os.path.dirname(OUTPUT_PATH)
            
            if TEST_FILE:
                file_name = f"test_eye_{TEST_FILE.replace('.mat', '.csv')}"
                output_name = os.path.join(output_dir, file_name)
            else:
                output_name = OUTPUT_PATH
                
            final_df.to_csv(output_name, index=False)
            print(f"\nProcessing done. File {output_name} saved.")
            print(f"Columns exported: {list(final_df.columns)}")