"""
inspect_lsl_streams.py
──────────────────────
Affiche un résumé lisible de chaque flux LSL contenu dans un fichier .mat.
Pour chaque flux : nom, type, dimensions, fréquence estimée, plage de valeurs,
et un aperçu des premières/dernières valeurs.

Usage :
    python inspect_lsl_streams.py chemin/vers/fichier.mat
"""

import sys
import numpy as np
from scipy.io import loadmat


def estimate_sampling_rate(timestamps):
    """Estime la fréquence d'échantillonnage à partir des écarts entre timestamps."""
    ts = np.array(timestamps).flatten()
    if len(ts) < 2:
        return None
    diffs = np.diff(ts)
    median_diff = np.median(diffs)
    if median_diff == 0:
        return None
    return 1.0 / median_diff


def describe_stream(stream, index):
    """Construit un résumé textuel d'un flux LSL."""
    # --- Métadonnées ---
    name = getattr(stream.info, 'name', '???')
    stream_type = getattr(stream.info, 'type', '???')

    # --- Données ---
    series = np.array(stream.time_series)
    stamps = np.array(stream.time_stamps).flatten()

    # --- Dimensions ---
    if series.ndim == 1:
        n_channels = 1
        n_samples = len(series)
    else:
        n_channels = series.shape[0]
        n_samples = series.shape[1]

    # --- Fréquence estimée ---
    fs = estimate_sampling_rate(stamps)

    # --- Durée totale ---
    duration_s = stamps[-1] - stamps[0] if len(stamps) > 1 else 0
    duration_min = duration_s / 60

    # --- Stats par canal ---
    channel_stats = []
    for ch in range(n_channels):
        if series.ndim == 1:
            ch_data = series
        else:
            ch_data = series[ch, :]

        # Conversion en float pour gérer les NaN proprement
        ch_float = ch_data.astype(float)
        n_nan = int(np.sum(np.isnan(ch_float)))
        valid = ch_float[~np.isnan(ch_float)]

        stats = {
            'canal': ch,
            'min': f"{np.min(valid):.4f}" if len(valid) > 0 else 'N/A',
            'max': f"{np.max(valid):.4f}" if len(valid) > 0 else 'N/A',
            'mean': f"{np.mean(valid):.4f}" if len(valid) > 0 else 'N/A',
            'nan_count': n_nan,
        }
        channel_stats.append(stats)

    # --- Aperçu des données (5 premières + 5 dernières valeurs) ---
    if series.ndim == 1:
        preview_start = series[:5]
        preview_end = series[-5:]
    else:
        preview_start = series[:, :5]
        preview_end = series[:, -5:]

    # --- Affichage ---
    separator = "═" * 65
    print(f"\n{separator}")
    print(f"  FLUX {index} : {name}")
    print(f"{separator}")
    print(f"  Type LSL        : {stream_type}")
    print(f"  Canaux           : {n_channels}")
    print(f"  Échantillons     : {n_samples:,}")
    print(f"  Fréq. estimée    : {fs:,.1f} Hz" if fs else "  Fréq. estimée    : variable (marqueurs événementiels)")
    print(f"  Durée            : {duration_s:,.1f}s  ({duration_min:.1f} min)")
    print(f"  Timestamps       : [{stamps[0]:.2f}  →  {stamps[-1]:.2f}]")

    print(f"\n  {'Canal':<8} {'Min':>12} {'Max':>12} {'Moyenne':>12} {'NaN':>8}")
    print(f"  {'─'*8} {'─'*12} {'─'*12} {'─'*12} {'─'*8}")
    for s in channel_stats:
        print(f"  {s['canal']:<8} {s['min']:>12} {s['max']:>12} {s['mean']:>12} {s['nan_count']:>8}")

    print(f"\n  Aperçu (5 premiers échantillons) :")
    if series.ndim == 1:
        print(f"    {preview_start}")
    else:
        for ch in range(min(n_channels, 6)):  # On limite à 6 canaux pour la lisibilité
            print(f"    Canal {ch}: {preview_start[ch]}")

    print(f"\n  Aperçu (5 derniers échantillons) :")
    if series.ndim == 1:
        print(f"    {preview_end}")
    else:
        for ch in range(min(n_channels, 6)):
            print(f"    Canal {ch}: {preview_end[ch]}")


def main():
    if len(sys.argv) < 2:
        print("Usage : python inspect_lsl_streams.py <fichier.mat>")
        sys.exit(1)

    filepath = sys.argv[1]
    print(f"\nChargement de : {filepath}")

    data = loadmat(filepath, squeeze_me=True, struct_as_record=False)

    streams = data.get('lsl_data', [])
    n_streams = len(streams)
    print(f"Nombre de flux détectés : {n_streams}")

    for i, stream in enumerate(streams):
        try:
            describe_stream(stream, i)
        except Exception as e:
            print(f"\n⚠ Erreur sur le flux {i} : {e}")

    print("\n" + "═" * 65)
    print("  Inspection terminée.")
    print("═" * 65 + "\n")


if __name__ == "__main__":
    main()