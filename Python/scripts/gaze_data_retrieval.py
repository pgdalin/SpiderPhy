import os
import pandas as pd
import numpy as np
import time
from scipy.io import loadmat

# Configuration des chemins
WORKING_DIRECTORY = os.path.abspath('../../')
MAT_FILES_DIR = os.path.join(WORKING_DIRECTORY, "osf_files/lsl_physio_data/")
OUTPUT_PATH = os.path.join(WORKING_DIRECTORY, "Python/output/", "gaze_data.csv")

def retrieve_gaze_data(FILE_NAME):
    path = os.path.join(MAT_FILES_DIR, FILE_NAME)
    raw_mat = loadmat(path, squeeze_me=True, struct_as_record=False)

    # 1. Récupérer les flux LSL
    # 'pupil_capture' contient les positions (x, y) et la confiance [cite: 1, 282]
    # 'fear_stream' contient les marqueurs d'événements (0=fixation, 1=stimulus) [cite: 1, 4]
    eye_stream = next(c for c in raw_mat['lsl_data'] if c.info.name == "pupil_capture")
    marker_stream = next(c for c in raw_mat['lsl_data'] if c.info.name == "fear_stream")

    # 2. Préparation des données oculométriques
    eye_labels = [c.label for c in eye_stream.info.desc.channels.channel]
    idx_x = eye_labels.index('norm_pos_x')
    idx_y = eye_labels.index('norm_pos_y')
    idx_conf = eye_labels.index('confidence')

    df_eye_raw = pd.DataFrame({
        'time': eye_stream.time_stamps,
        'x': eye_stream.time_series[idx_x],
        'y': eye_stream.time_series[idx_y],
        'confidence': eye_stream.time_series[idx_conf]
    })

    # 3. Préparation des événements
    df_events = pd.DataFrame({
        'time': marker_stream.time_stamps,
        'code': marker_stream.time_series
    })

    all_trials_gaze = []

    # 4. Boucle de traitement par Stimulus (code 1) [cite: 4]
    df_stimuli = df_events[df_events['code'] == 1].copy()

    for i, stim_row in df_stimuli.iterrows():
        stim_start = stim_row['time']
        
        # --- CALCUL DE L'OFFSET (Recalage) ---
        # On cherche la fixation (code 0) précédant immédiatement ce stimulus [cite: 4, 150]
        potential_baselines = df_events[(df_events['code'] == 0) & (df_events['time'] < stim_start)]
        
        if potential_baselines.empty:
            continue # Impossible de recaler sans baseline précédente
            
        # On sélectionne la fixation la plus proche (la dernière de la liste filtrée)
        # On analyse la dernière seconde de cette fixation pour la stabilité 
        mask_fix = (df_eye_raw['time'] >= (stim_start - 1.0)) & (df_eye_raw['time'] < stim_start)
        fix_seg = df_eye_raw[mask_fix].copy()
        fix_seg = fix_seg[fix_seg['confidence'] >= 0.6] # Seuil de confiance recommandé 

        if fix_seg.empty or len(fix_seg) < 10:
            continue # Données insuffisantes pour calculer un offset fiable

        # Calcul de l'écart par rapport au centre théorique (0.5, 0.5)
        offset_x = fix_seg['x'].mean() - 0.5
        offset_y = fix_seg['y'].mean() - 0.5

        # --- EXTRACTION ET CORRECTION DU STIMULUS ---
        # Durée du stimulus : 5 secondes 
        mask_stim = (df_eye_raw['time'] >= stim_start) & (df_eye_raw['time'] <= stim_start + 5.0)
        stim_seg = df_eye_raw[mask_stim].copy()
        stim_seg = stim_seg[stim_seg['confidence'] >= 0.6]
        
        if not stim_seg.empty:
            # Application de la correction (Soustraire l'erreur pour recentrer)
            stim_seg['x'] = stim_seg['x'] - offset_x
            stim_seg['y'] = stim_seg['y'] - offset_y
            
            stim_seg['trial_index'] = i
            all_trials_gaze.append(stim_seg)

    # 5. Consolidation des résultats
    if all_trials_gaze:
        result = pd.concat(all_trials_gaze, ignore_index=True)
        # Ajout de l'identifiant participant [cite: 279]
        result['participant_id'] = FILE_NAME.split('_')[1]
    else:
        result = pd.DataFrame()

    return result

# --- SCRIPT D'EXÉCUTION ---

if __name__ == "__main__":
    TEST_FILE = None # "ID_001_lsl_data.mat"

    if not os.path.exists(MAT_FILES_DIR):
        print(f"Erreur : Dossier non trouvé -> {MAT_FILES_DIR}")
    else:
        if TEST_FILE:
            files = [TEST_FILE]
            print(f"--- MODE TEST : Traitement de {TEST_FILE} ---")
        else:
            files = [f for f in os.listdir(MAT_FILES_DIR) if f.endswith(".mat")]
            print(f"Début du traitement de {len(files)} fichiers...")

        all_data = []
        total_start = time.time()

        for f in files:
            try:
                file_start = time.time()
                res = retrieve_gaze_data(f)
                all_data.append(res)
                file_elapsed = time.time() - file_start
                print(f"Succès pour {f}! ({file_elapsed:.2f}s)")
            except Exception as e:
                print(f"Échec pour {f}! Erreur: {e}")

        total_elapsed = time.time() - total_start
        print(f"\nTemps total : {total_elapsed:.2f}s pour {len(files)} fichier(s).")

        if all_data:
            final_df = pd.concat(all_data, ignore_index=True)
            output_name = os.path.join(os.path.dirname(OUTPUT_PATH), 
                                      f"test_gaze_{TEST_FILE.replace('.mat', '.csv')}" if TEST_FILE else OUTPUT_PATH)
            final_df.to_csv(output_name, index=False)
            print(f"\nTraitement terminé. Fichier sauvegardé : {output_name}")