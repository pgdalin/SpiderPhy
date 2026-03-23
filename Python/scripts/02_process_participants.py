import os # Allow for generalisation of paths.
import pandas as pd # Allows to use pandas df.
import numpy as np # Allows to use arrays and mathematical functions.
from scipy.signal import sosfiltfilt, butter # Allow to use EEG/ECG filters.
from scipy.io import loadmat # Allows to load .mat files into Python.
from scipy.signal import find_peaks # Allows to find the heartrate 

# Setting paths.

WORKING_DIRECTORY = os.path.abspath('../../')
FILES_DIRECTORY = os.path.join(WORKING_DIRECTORY, "osf_files/lsl_physio_data/")
SAMPLING_RATE = 5000
OUTPUT_PATH = os.path.join(WORKING_DIRECTORY, "Python/output/", "processed_physio.csv")

# This function will allow for the passing of a filter on the ECG data.

def apply_butterworth_filter(DATA, LOW, HIGH, SAMPLING_RATE, ORDER):

    nyquist = 0.5 * SAMPLING_RATE
    low = LOW / nyquist
    high = HIGH / nyquist
    sos = butter(ORDER, [low, high], btype="band", output="sos")

    return sosfiltfilt(sos, DATA)

# This function will allow to gather the data specific to trials.

def extract_trial_stats(ECG_DATA, TIME_STAMP, MARKERS_STRUCT):

    codes = np.array(MARKERS_STRUCT.time_series).flatten() # Gathering the events IDs.
    times = np.array(MARKERS_STRUCT.time_stamps).flatten() # Gathering the timestamps for those IDs.

    df_events = pd.DataFrame({
        'events': codes,
        'time': times
    })

    events_to_process = df_events[df_events['events'].isin([0, 1])].copy()

    trial_results = [] # We initiate a list to append the results at each iteration.

    for i, row in events_to_process.iterrows(): # We iteration on each rows of the new df with only the datapoints of trials.

        start_t = row['time'] # We define the starting time of the time window.
        end_t = start_t + 5.0 # From the latter, we define the ending time.

        mask = (TIME_STAMP >= start_t) & (TIME_STAMP <= end_t) # We build a mask to keep only the data of the trial.

        segment = ECG_DATA[mask] # We apply the mask on the data.

        if len(segment) > 0:

            peaks, _ = find_peaks(segment['ECG'], distance = 0.7 * SAMPLING_RATE, prominence = 0.5) # We retrieve the peaks of the ECG for the trial.
            n_peaks = len(peaks) # len() provides us with the number of heart pulsation for a 5s trial.

            trial_results.append({

                # Index and events

                'trial_index': i,
                'marker_code': row['events'], 
                'is_baseline': 1 if row['events'] == 0 else 0,

                # ECG variables

                'ecg_amplitude': segment['ECG'].std(), 

                # GSR variables

                'gsr_tonic_level': segment['GSR_MR_100_xx'].mean(), # Average conductance of the skin.
                'gsr_phasic_response': segment['GSR_MR_100_xx'].max() - segment['GSR_MR_100_xx'].min(), # Difference between the highest and lowest conductance during trial.

                # Respiratory variables

                'resp_intensity': segment['Resp'].std(), # Variability of breathing frequency.

                # Pulse variables

                'n_peaks': n_peaks/5 * 60

            })
            
    return pd.DataFrame(trial_results) # We return the df once we've iterated on all the trials.

def process_participants(FILE_NAME):

    full_path = os.path.join(WORKING_DIRECTORY, FILES_DIRECTORY, FILE_NAME)
    raw_mat = loadmat(full_path, squeeze_me=True, struct_as_record=False)

    PHYSIO_STRUCT = None
    MARKERS_STRUCT = None

    for stream in raw_mat['lsl_data']:
        if stream.info.name == "BrainVision RDA":
            PHYSIO_STRUCT = stream
        elif stream.info.name == "fear_stream":
            MARKERS_STRUCT = stream

    if PHYSIO_STRUCT is None or MARKERS_STRUCT is None:
        raise ValueError(f"Missing stream in the file {FILE_NAME}")

    labels = [c.label for c in PHYSIO_STRUCT.info.desc.channels.channel] # We gather the names of the channels to assign them dynamically.
    
    df = pd.DataFrame(PHYSIO_STRUCT.time_series.T, columns=labels) # Creation of the df pandas with dynamic labels.
    
    df['time'] = PHYSIO_STRUCT.time_stamps.flatten() # We anticipate N dim > 1 errors

    df['ECG'] = apply_butterworth_filter(df['ECG'], 0.5, 40, 5000, 4) # We filter the ECG signal.

    summary = extract_trial_stats(df, df['time'], MARKERS_STRUCT) # We gather the epochs after the filtering.
    
    summary['participant_id'] = FILE_NAME.split('_')[1] # We create a col with the ID of the participants.

    return summary # returning the results.

# Calling the script.

if __name__ == "__main__":

    # To test on only one selected file, add file name here.
    TEST_FILE = "ID_001_lsl_data.mat" # "ID_001_lsl_data.mat"

    if not os.path.exists(FILES_DIRECTORY):
        print(f"Error : Folder not found -> {FILES_DIRECTORY}") # the path towards the files doesn't exist.
    else:

        if TEST_FILE: # If a TEST_FILE was entered, then we use the TEST MODE.
            files = [TEST_FILE]
            print(f"--- TEST MODE : treating {TEST_FILE} ---")
        else:
            files = [f for f in os.listdir(FILES_DIRECTORY) if f.endswith(".mat")] # Just proceed as intended.
            print(f"Starting processing of {len(files)} files...")

        all_data = []

        for f in files: # Iterate on the files, concatenate, etc.
            try:
                res = process_participants(f)
                all_data.append(res)
                print(f"Success for {f}!")
            except Exception as e:
                # C'est ici que tu verras tes erreurs s'il y en a
                print(f"Failure for {f}! Error: {e}")

        # Exportation
        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            output_dir = os.path.dirname(OUTPUT_PATH)
            
            if TEST_FILE:
                file_name = f"test_{TEST_FILE.replace('.mat', '.csv')}"
                output_name = os.path.join(output_dir, file_name)
                
            else:
                output_name = OUTPUT_PATH
                
            final_df.to_csv(output_name, index=False)
            print(f"\nProcessing done. File {output_name} saved.")