import os
import pandas as pd
import numpy as np
from scipy.io import loadmat
from scipy.signal import butter, sosfiltfilt

# --- CONFIGURATION ---
# Utilisation de chemins absolus pour éviter les erreurs de dossier
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.abspath(os.path.join(BASE_DIR, "../../osf_files/lsl_physio_data/"))
OUTPUT_FILE = "spider_phy_processed_data.csv"
SAMPLING_RATE = 5000 

def apply_butterworth_filter(data, lowcut, highcut, fs, order=4):
    nyquist = 0.5 * fs
    low = lowcut / nyquist
    high = highcut / nyquist
    sos = butter(order, [low, high], btype='band', output='sos')
    return sosfiltfilt(sos, data)

def extract_trial_stats(ecg_data, timestamps, markers_struct):
    """Extraction robuste des segments de 5 secondes."""
    codes = np.array(markers_struct.time_series).flatten()
    times = np.array(markers_struct.time_stamps).flatten()
    
    df_events = pd.DataFrame({
        'code': codes,
        'time': times
    })
    
    df_events['duration'] = df_events['time'].diff().shift(-1)
    stimuli = df_events[df_events['duration'].round(1) == 5.0]
    
    trial_results = []
    for i, row in stimuli.iterrows():
        start_t = row['time']
        end_t = start_t + 5.0
        
        mask = (timestamps >= start_t) & (timestamps <= end_t)
        segment = ecg_data[mask]
        
        if len(segment) > 0:
            trial_results.append({
                'trial_index': i,
                'marker_code': row['code'],
                'ecg_variance': np.var(segment),
                'ecg_mean': np.mean(segment)
            })
            
    return pd.DataFrame(trial_results)

def process_participant(file_name):
    full_path = os.path.join(DATA_PATH, file_name)
    data = loadmat(full_path, squeeze_me=True, struct_as_record=False)
    
    # On initialise nos variables à None
    physio_struct = None
    markers_struct = None
    
    # On scanne les flux pour trouver les bons, quel que soit leur index
    for stream in data['lsl_data']:
        name = stream.info.name
        if name == 'BrainVision RDA':
            physio_struct = stream
        elif name == 'fear_stream':
            markers_struct = stream
            
    if physio_struct is None or markers_struct is None:
        raise ValueError(f"Flux manquants dans le fichier {file_name}")
    
    signals = physio_struct.time_series
    # SÉCURITÉ : Gestion de la dimension du signal
    if signals.ndim == 2:
        ecg_raw = signals[0, :] # On prend le premier canal (ECG)
    else:
        ecg_raw = signals
        
    timestamps = np.array(physio_struct.time_stamps).flatten()
    
    ecg_clean = apply_butterworth_filter(ecg_raw, 8, 20, SAMPLING_RATE)
    summary = extract_trial_stats(ecg_clean, timestamps, markers_struct)
    
    summary['participant_id'] = file_name.split('_')[1]
    return summary

if __name__ == "__main__":
    if not os.path.exists(DATA_PATH):
        print(f"Erreur : Dossier introuvable -> {DATA_PATH}")
    else:
        files = [f for f in os.listdir(DATA_PATH) if f.endswith('.mat')]
        all_data = []
        
        print(f"Début du traitement pour {len(files)} fichiers...")
        for f in files:
            try:
                res = process_participant(f)
                all_data.append(res)
                print(f"Succès : {f}")
            except Exception as e:
                print(f"Échec sur {f} : {e}")
        
        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            final_df.to_csv(OUTPUT_FILE, index=False)
            print(f"\nTraitement terminé. Fichier sauvegardé : {OUTPUT_FILE}")