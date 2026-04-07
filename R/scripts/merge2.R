# -------------------------------------------------------------------------
# merge.R
# Consolidation des données physiologiques, comportementales et psychométriques
# -------------------------------------------------------------------------

cat("Pipeline starting...\n")

library(tidyverse)
library(janitor)
library(readxl)

# ── Chemins ───────────────────────────────────────────────────────────────────

PATH_STIMULI    <- "../osf_files/rating_data/"
PATH_PHYSIO     <- "../Python/output/processed_physio.csv"
PATH_PSY        <- "../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx"
OUTPUT_FINAL    <- "output/final_consolidated_data.csv"

# ── 1. Données physiologiques ─────────────────────────────────────────────────

physio_raw <- read_csv(PATH_PHYSIO) |>
  mutate(participant_id = as.double(participant_id)) |>
  group_by(participant_id) |>
  filter(
    !(marker_code == 0 & lead(marker_code) == 0),
    !(row_number() == n() & marker_code == 0)
  ) |>
  mutate(trial_number = cumsum(is_baseline)) |>
  filter(marker_code == 1) |>
  ungroup() |>
  relocate(trial_number, .before = 4)

# ── 2. Données de rating (stimuli) ───────────────────────────────────────────

stimuli_files <- list.files(
  path = PATH_STIMULI, pattern = "^ID_.*\\.csv$",
  full.names = TRUE, recursive = FALSE
)

all_stimuli <- stimuli_files |>
  map_dfr(function(file) {
    p_id <- as.numeric(str_extract(basename(file), "(?<=ID_)\\d+"))
    read.csv2(file, fileEncoding = "latin1") |>
      clean_names() |>
      filter(str_detect(picture_id, "\\.jpg|\\.JPG")) |>
      mutate(
        participant_id = p_id,
        trial_seq_id   = row_number()
      )
  })

# ── 3. Merge physio + stimuli ─────────────────────────────────────────────────

final_dataset <- all_stimuli |>
  left_join(physio_raw, by = c("participant_id", "trial_seq_id" = "trial_number")) |>
  mutate(
    condition_code = str_extract(picture_id, "(?<=_)[A-Za-z]+(?=_)"),
    condition = case_when(
      condition_code == "Sp"                    ~ "Spider",
      condition_code == "Ne"                    ~ "Neutral",
      condition_code %in% c("CR", "CL", "SX")  ~ "Control_Spider",
      TRUE                                      ~ "Unknown"
    )
  ) |>
  filter(condition_code == "Sp")

# Correction des typos dans picture_id
final_dataset <- final_dataset |>
  mutate(
    picture_id = str_replace(picture_id, ".JPG$", ".jpg"),
    picture_id = str_replace(picture_id, "^p",    "Sp"),
    picture_id = str_replace(picture_id, " ",     "")
  )

# Quartile de peur intra-participant
final_dataset <- final_dataset |>
  group_by(participant_id) |>
  mutate(fear_rating_per_p = ntile(rating, n = 4)) |>
  ungroup()

# ── 4. Données psychométriques ────────────────────────────────────────────────
# Une valeur par participant — sera répétée sur tous les essais après le join.
# On extrait uniquement les échelles pertinentes et on harmonise l'identifiant.
#
# Échelles retenues :
#   FSQ_pre  — Fear of Spiders Questionnaire (avant exposition)
#   SAS_pre  — Spider Anxiety Scale (avant exposition)
#   SPQ      — Spider Phobia Questionnaire
#   STAI     — State-Trait Anxiety Inventory
#
# On utilise les versions "pre" pour éviter la contamination par l'exposition.
# FSQ_post et SAS_post sont conservées séparément pour analyses de changement.

psychometrics <- read_excel(PATH_PSY, sheet = "data") |>
  filter(grepl("^ID", ID)) |>
  mutate(
    # "ID_001" → 1  (harmonisation avec participant_id numérique du reste)
    participant_id = as.numeric(str_extract(ID, "\\d+"))
  ) |>
  select(participant_id, FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI)

# ── 5. Merge final ────────────────────────────────────────────────────────────
# left_join : tous les essais sont conservés.
# Les participants sans données psychométriques auront des NA.

final_dataset <- final_dataset |>
  left_join(psychometrics, by = "participant_id")

# Vérification : signale les participants sans psychométriques
missing_psy <- final_dataset |>
  filter(is.na(FSQ_pre)) |>
  distinct(participant_id) |>
  pull()

if (length(missing_psy) > 0) {
  warning(
    length(missing_psy), " participant(s) sans données psychométriques : ",
    paste(missing_psy, collapse = ", ")
  )
} else {
  cat("Merge psychométriques : OK — aucune donnée manquante.\n")
}

# ── 6. Export ─────────────────────────────────────────────────────────────────

write_csv(final_dataset, OUTPUT_FINAL)

cat(
  "Success: Pipeline terminé.", nrow(final_dataset), "lignes traitées.\n",
  "Colonnes psychométriques ajoutées : FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI\n"
)
