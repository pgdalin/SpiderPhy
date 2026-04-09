"""
Gaze Heatmap Generation Pipeline
================================
Loads raw gaze data and trial-to-image mappings, applies temporal filtering
and spatial scaling, then generates per-image heatmaps overlaid on the
original stimulus pictures. Outputs are saved as PNG files.
"""

import os
import time

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image
from scipy.ndimage import gaussian_filter

# ── Path Configuration ────────────────────────────────────────────────────────

GAZE_DATA_PATH = os.path.abspath("../output/gaze_data.csv")
CONSOLIDATED_PATH = os.path.abspath("../../R/output/final_consolidated_data.csv")
IMAGES_PATH = os.path.abspath(
    "../../osf_files/spiderPhy_luminance_corrected/spiderPhy_luminance_corrected/"
)
OUTPUT_PATH = os.path.abspath("../output/heatmaps/")

# ── Spatial Scaling Configuration ─────────────────────────────────────────────

# A factor of 2.0 stretches gaze points by 200% around the screen center.
# This compensates for the camera field of view being larger than the display area,
#   effectively "zooming in" gaze coordinates to match the stimulus boundaries.
# The correct value for this dataset is 4, determined through successive iterations,
#   until the heatmaps were aligned with visible spiders.
SCALING_FACTOR = 4

# ── Temporal Filtering Configuration ─────────────────────────────────────────

# Retain only gaze samples between 1.5 s and 2.5 s after trial onset.
# The first 1.5 s are discarded to skip the initial fixation cross period
#   and capture the orienting response toward the spider stimulus.
TIME_WINDOW_START = 2.5
TIME_WINDOW_END = 5


# ── Main Pipeline ─────────────────────────────────────────────────────────────


def process_heatmaps():
    """Run the full heatmap generation pipeline.

    Steps
    -----
    1. Load raw gaze data and trial-to-image mapping.
    2. Merge datasets to associate each gaze point with a stimulus image.
    3. Filter samples to the analysis time window.
    4. Remove fixation-cross artefacts (gaze locked at screen center).
    5. For each stimulus image:
       a. Reject outlier gaze points via IQR.
       b. Apply spatial scaling around the screen center.
       c. Discard out-of-bounds points after scaling.
       d. Bin gaze points into a 2-D histogram and smooth with a Gaussian kernel.
       e. Overlay the heatmap on the stimulus image and save as PNG.
    """
    if not os.path.exists(OUTPUT_PATH):
        os.makedirs(OUTPUT_PATH)

    # ── Load Data ─────────────────────────────────────────────────────────────

    print("Loading data... (this may take a moment)")
    df_gaze = pd.read_csv(GAZE_DATA_PATH)

    # Retain only the columns needed for the image–trial mapping.
    df_map = pd.read_csv(CONSOLIDATED_PATH)
    df_map = df_map[["participant_id", "trial_index", "picture_id"]]

    # ── Merge: link each (x, y) gaze point to its corresponding image ─────────

    print("Merging datasets...")
    df = pd.merge(df_gaze, df_map, on=["participant_id", "trial_index"])

    # ── Temporal Filtering ────────────────────────────────────────────────────

    print("Computing temporal offsets...")
    # Compute each sample's time relative to the start of its trial.
    df["time_offset"] = df.groupby(["participant_id", "trial_index"])["time"].transform(
        lambda x: x - x.min()
    )
    # Keep only samples that fall within the analysis window.
    df_heat = df[
        (df["time_offset"] >= TIME_WINDOW_START)
        & (df["time_offset"] <= TIME_WINDOW_END)
    ].copy()

    # ── Remove Fixation-Cross Samples ─────────────────────────────────────────

    # Gaze locked exactly at (0.5, 0.5) indicates a fixation cross artefact,
    #   not a true look toward the stimulus.
    df_heat = df_heat[~((df_heat["x"] == 0.5) & (df_heat["y"] == 0.5))]

    # ── Per-Image Heatmap Generation ──────────────────────────────────────────

    unique_images = df_heat["picture_id"].unique()
    print(f"Starting generation for {len(unique_images)} images...")
    total_start = time.time()

    for img_name in unique_images:
        img_start = time.time()

        # Collect all gaze points associated with this stimulus image.
        points = df_heat[df_heat["picture_id"] == img_name][["x", "y"]].values
        # Drop rows containing NaN coordinates.
        points = points[~np.isnan(points).any(axis=1)]

        if len(points) < 10:
            # Too few samples to produce a meaningful heatmap.
            continue

        # ── Outlier Rejection (IQR Method) ────────────────────────────────────

        # Remove extreme saccades or tracker artefacts along each axis
        #   using 1.5 * IQR fences (equivalent to Tukey's boxplot rule).
        for axis in [0, 1]:
            q1, q3 = np.percentile(points[:, axis], [25, 75])
            iqr = q3 - q1
            lower, upper = q1 - 1.5 * iqr, q3 + 1.5 * iqr
            points = points[(points[:, axis] >= lower) & (points[:, axis] <= upper)]

        if len(points) < 10:
            continue

        # ── Spatial Scaling ────────────────────────────────────────────────────

        # Expand gaze coordinates outward from the screen center (0.5, 0.5).
        # This corrects for the mismatch between the camera field of view and
        #   the actual display area, spreading points across the full image extent.
        points[:, 0] = (points[:, 0] - 0.5) * SCALING_FACTOR + 0.5
        points[:, 1] = (points[:, 1] - 0.5) * SCALING_FACTOR + 0.5

        # ── Out-of-Bounds Filtering ────────────────────────────────────────────

        # After scaling, some points may fall outside the [0, 1] normalised range;
        #   discard them to avoid wrapping artefacts in the histogram.
        mask = (
            (points[:, 0] >= 0)
            & (points[:, 0] <= 1)
            & (points[:, 1] >= 0)
            & (points[:, 1] <= 1)
        )
        points = points[mask]

        if len(points) < 5:
            continue

        # ── Heatmap Computation and Rendering ─────────────────────────────────

        img_full_path = os.path.join(IMAGES_PATH, img_name)
        try:
            with Image.open(img_full_path) as im:
                width, height = im.size

                # Downsample the histogram grid relative to the image resolution
                #   to smooth out sparse gaze distributions.
                res_scale = 10
                heatmap, _, _ = np.histogram2d(
                    1 - points[:, 1],  # Y-axis flipped: 0 at top, 1 at bottom.
                    points[:, 0],
                    bins=[height // res_scale, width // res_scale],
                    range=[[0, 1], [0, 1]],
                )

                # Apply Gaussian smoothing to produce continuous density blobs
                #   rather than hard-edged histogram bins.
                heatmap = gaussian_filter(heatmap, sigma=5)

                # Overlay the heatmap (jet colormap, semi-transparent) on the
                #   original stimulus image and save the result.
                plt.figure(figsize=(10, 6))
                plt.imshow(im)
                plt.imshow(
                    heatmap,
                    extent=[0, width, height, 0],
                    cmap="jet",
                    alpha=0.5,
                    interpolation="bilinear",
                )
                plt.axis("off")

                img_stem = os.path.splitext(img_name)[0]
                save_name = f"heatmap_{img_stem}_2_5_5_0.png"
                plt.savefig(
                    os.path.join(OUTPUT_PATH, save_name),
                    bbox_inches="tight",
                    pad_inches=0,
                )
                plt.close()

                print(f"Success: {img_name} ({time.time() - img_start:.2f}s)")

        except FileNotFoundError:
            print(f"Missing image: {img_name}")

    print(f"\nDone! Total time: {time.time() - total_start:.1f}s")


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    process_heatmaps()
