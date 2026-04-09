# -------------------------------------------------------------------------
# merge2.R
# 
# The purpose of this script is to merge three data sources:
# 
# - preprocessed physiological stimulis (process_mat.py's output)
# - ratings of stimuli by participants ("../osf_files/rating_data/*")
# - participant psychometric results ("../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx)
#
# Output:
# 
# - output/final_consolidated_data.csv
# -------------------------------------------------------------------------

cat("Pipeline starting...\n")

library(tidyverse)  # bestest library <3
library(janitor)    # clean_names()
library(readxl)     # read_excel()


# Paths -------------------------------------------------------------------

# The paths are linked to the root project, can be used as is.

PATH_STIMULI  <- "../osf_files/rating_data/"
PATH_PHYSIO   <- "../Python/output/processed_physio.csv"
PATH_PSY      <- "../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx"
OUTPUT_FINAL  <- "output/final_consolidated_data.csv"



# Physiological data ------------------------------------------------------

# Ensures proper cols attributes;
# Removes baselines not followed by a trial;
# Adds trial_number by counting the number of baselines;
# Keeps only trials.

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



# Stimulus Rating Data ----------------------------------------------------

# Creating a variable with all stimuli files names.

stimuli_files <- list.files(
  path      = PATH_STIMULI,
  pattern   = "^ID_.*\\.csv$",
  full.names = TRUE,
  recursive  = FALSE
)

# Iterate on each files doing the following:
# 
# - Adds participant's ID in a col;
# - Standardizes names using snake_case;
# - Keeps only the pictures

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



# Merge: Physiology + Stimulus Ratings ------------------------------------

# Merges stimuli ratings with physiological data using the previously created
#   variables such as participant_id and trial_seq_id.
#   
# Separates each elements forming the picture's names into separate columns. We
#   only keep pictures of spiders for analysis.

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



# picture_id Normalization ------------------------------------------------

# While running heatmaps_generation.py, I found out some picture names were 
#   incorrect in the physiological data. Names are restaured using regex 
#   patterns. Manual check confirmed the fix to be effective.

final_dataset <- final_dataset |>
  mutate(
    picture_id = str_replace(picture_id, "\\.JPG$", ".jpg"),
    picture_id = str_replace(picture_id, "^p",      "Sp"),
    picture_id = str_replace(picture_id, " ",       "")
  )



# Within-Person Fear Rating Quartiles -------------------------------------

# Separation of stimuli per fear_rating along 4 quartiles. Surprisingly,
#   grouping per participants had no effect on the assignations. Correlation
#   between both vectors is of 1. This indicates that participants rated the
#   pictures of spiders in an incredibly consistently similar fashion; to the
#   point I wonder if I made some mistake.

final_dataset <- final_dataset |>
  group_by(participant_id) |>
  mutate(fear_rating_per_p = ntile(rating, n = 4)) |>
  ungroup()



# Psychometric Data -------------------------------------------------------

# Formating and trimming psychometric data.
# Psychometric scales are explained in "../é"
# Pre-exposure versions are used to avoid contamination by the experimental
# manipulation. Post-exposure versions (FSQ_post, SAS_post) are retained
# to support future change-score analyses.

psychometrics <- read_excel(PATH_PSY, sheet = "data") |>
  filter(grepl("^ID", ID)) |> 
  mutate(
    participant_id = as.numeric(str_extract(ID, "\\d+"))  # "ID_001" → 1
  ) |>
  select(participant_id, FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI)



# Final Merge: Add Psychometrics ------------------------------------------

# left_join preserves all trials; participants missing psychometric data
#   receive NA values and are flagged by the validation check below.
#   
# /i\ currently returns nothing.

final_dataset <- final_dataset |>
  left_join(psychometrics, by = "participant_id")

missing_psy <- final_dataset |>
  filter(is.na(FSQ_pre)) |>
  distinct(participant_id) |>
  pull()

if (length(missing_psy) > 0) {
  warning(
    length(missing_psy), " participant(s) missing psychometric data: ",
    paste(missing_psy, collapse = ", ")
  )
} else {
  cat("Psychometric merge: OK — no missing data.\n")
}



# Export ------------------------------------------------------------------

write_csv(final_dataset, OUTPUT_FINAL)



# Closing -----------------------------------------------------------------

cat(
  "Success: Pipeline complete.", nrow(final_dataset), "rows written.\n",
  "Psychometric columns added: FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI\n"
)
