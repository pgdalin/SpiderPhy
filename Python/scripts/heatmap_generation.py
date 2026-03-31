import os
import time
import pandas as pd
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
from scipy.ndimage import gaussian_filter

# --- CONFIGURATION DES CHEMINS ---
GAZE_DATA_PATH = os.path.abspath("../output/gaze_data.csv")
CONSOLIDATED_PATH = os.path.abspath("../../R/output/final_consolidated_data.csv")
IMAGES_PATH = os.path.abspath("../../osf_files/spiderPhy_luminance_corrected/spiderPhy_luminance_corrected/")
OUTPUT_PATH = os.path.abspath("../output/heatmaps/")

# --- CONFIGURATION DU SCALING ---
# Un facteur de 2.0 signifie que l'on étire les points de 200% autour du centre.
# Cela compense le fait que l'écran ne remplit qu'une partie du champ de la caméra.
SCALING_FACTOR = 4

# --- CONFIGURATION DU FILTRAGE TEMPOREL ---
# Fenêtre de 0.5s à 1.5s pour capturer le mouvement vers l'araignée
# (on ignore les 500 premières ms de fixation initiale)
TIME_WINDOW_START = 1.5
TIME_WINDOW_END = 2.5


def process_heatmaps():
    if not os.path.exists(OUTPUT_PATH):
        os.makedirs(OUTPUT_PATH)

    # 1. Charger les points de regard bruts
    print("Chargement des données... (cela peut prendre un moment)")
    df_gaze = pd.read_csv(GAZE_DATA_PATH)

    # 2. Charger la correspondance Image <-> Essai
    df_map = pd.read_csv(CONSOLIDATED_PATH)
    df_map = df_map[['participant_id', 'trial_index', 'picture_id']]

    # 3. FUSION : on lie chaque point (x, y) au nom de l'image correspondante
    print("Fusion des datasets...")
    df = pd.merge(df_gaze, df_map, on=['participant_id', 'trial_index'])

    # 4. FILTRAGE TEMPOREL
    print("Calcul des offsets temporels...")
    df['time_offset'] = df.groupby(['participant_id', 'trial_index'])['time'].transform(
        lambda x: x - x.min()
    )
    df_heat = df[
        (df['time_offset'] >= TIME_WINDOW_START) & (df['time_offset'] <= TIME_WINDOW_END)
    ].copy()

    # 5. Suppression des points de fixation centrale (croix de fixation)
    df_heat = df_heat[~((df_heat['x'] == 0.5) & (df_heat['y'] == 0.5))]

    # 6. BOUCLE PAR IMAGE
    unique_images = df_heat['picture_id'].unique()
    print(f"Début de la génération pour {len(unique_images)} images...")
    total_start = time.time()

    for img_name in unique_images:
        img_start = time.time()

        # 6a. Récupération des points
        points = df_heat[df_heat['picture_id'] == img_name][['x', 'y']].values
        points = points[~np.isnan(points).any(axis=1)]

        if len(points) < 10:
            continue

        # 6b. Application du scaling (zoom)
        # On écarte les points du centre (0.5) pour les "projeter" plus loin sur l'image
        points[:, 0] = (points[:, 0] - 0.5) * SCALING_FACTOR + 0.5
        points[:, 1] = (points[:, 1] - 0.5) * SCALING_FACTOR + 0.5

        # 6c. Filtrage des points hors-cadre (après le zoom, certains sortent de [0, 1])
        mask = (
            (points[:, 0] >= 0) & (points[:, 0] <= 1) &
            (points[:, 1] >= 0) & (points[:, 1] <= 1)
        )
        points = points[mask]

        if len(points) < 5:
            continue

        # 6d. Génération de la heatmap
        img_full_path = os.path.join(IMAGES_PATH, img_name)
        try:
            with Image.open(img_full_path) as im:
                width, height = im.size

                res_scale = 10
                heatmap, _, _ = np.histogram2d(
                    1 - points[:, 1], points[:, 0],  # Inversion Y : 0 en haut
                    bins=[height // res_scale, width // res_scale],
                    range=[[0, 1], [0, 1]]
                )

                heatmap = gaussian_filter(heatmap, sigma=5)

                # 6e. Dessin et sauvegarde
                plt.figure(figsize=(10, 6))
                plt.imshow(im)
                plt.imshow(
                    heatmap,
                    extent=[0, width, height, 0],
                    cmap='jet',
                    alpha=0.5,
                    interpolation='bilinear'
                )
                plt.axis('off')

                save_name = f"heatmap_{img_name.replace('.jpg', '.png')}"
                plt.savefig(
                    os.path.join(OUTPUT_PATH, save_name),
                    bbox_inches='tight',
                    pad_inches=0
                )
                plt.close()

                print(f"Succès : {img_name} ({time.time() - img_start:.2f}s)")

        except FileNotFoundError:
            print(f"Image manquante : {img_name}")

    print(f"\nTerminé ! Temps total : {time.time() - total_start:.1f}s")


if __name__ == "__main__":
    process_heatmaps()