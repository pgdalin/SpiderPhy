# -------------------------------------------------------------------------

cat("Pipeline starting...")

# -------------------------------------------------------------------------

# This script has as a goal to perform the concatenation of all stimuli files and left_join() of the physiologic data with them.

library(tidyverse) # Bestest library ever <3
library(janitor)

# -------------------------------------------------------------------------

# rating_data contains a file per participants rating the stimuli on several
# scales.
# processed_physio.csv is the result of running process_mat.py.

PATH_STIMULI <- "../osf_files/rating_data/" 
PATH_PHYSIO  <- "../Python/output/processed_physio.csv" 
OUTPUT_FINAL <- "output/final_consolidated_data.csv" 

# -------------------------------------------------------------------------

# Deleting baselines not followed by trials.
# Deleting baselines if last row.
# Creating trial_number variable to help merge with ratings.

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

# -------------------------------------------------------------------------

# Gathering all file names in the directory.

stimuli_files <- list.files(path = PATH_STIMULI, pattern = "^ID_.*\\.csv$", full.names = TRUE, recursive = FALSE) 

# For all rating files:
# We clean the names.
# We create cols to merge with physio data.

all_stimuli <- stimuli_files |>
  map_dfr(function(file) { 
    p_id <- as.numeric(str_extract(basename(file), "(?<=ID_)\\d+")) 
    read.csv2(file, fileEncoding = "latin1") |> 
      clean_names() |> 
      filter(str_detect(picture_id, "\\.jpg|\\.JPG")) |> 
      mutate(
        participant_id = p_id,
        trial_seq_id = row_number() 
      )
  })

# -------------------------------------------------------------------------

# We merge the files and create cols separating elements from picture_id to have
# conditions.
# Also, we only need to keep the Spider pictures.

final_dataset <- all_stimuli |>
  left_join(physio_raw, by = c("participant_id", "trial_seq_id" = "trial_number")) |> 
  mutate(
    condition_code = str_extract(picture_id, "(?<=_)[A-Za-z]+(?=_)"), 
    condition = case_when(
      condition_code == "Sp" ~ "Spider", 
      condition_code == "Ne" ~ "Neutral", 
      condition_code %in% c("CR", "CL", "SX") ~ "Control_Spider", 
      TRUE ~ "Unknown" 
    )
  ) |> 
  filter(
    condition_code == "Sp"
  )

# -------------------------------------------------------------------------

# Running heatmaps.py indicated several typos in the picture_id col. Fix:

final_dataset <- final_dataset |> 
  mutate(picture_id = str_replace(picture_id, ".JPG$", ".jpg"),
         picture_id = str_replace(picture_id, "^p", "Sp"),
         picture_id = str_replace(picture_id, " ", ""))

# -------------------------------------------------------------------------

# We need to add the quartile for fear_rating.

final_dataset <- final_dataset |> 
  group_by(participant_id) |> 
  mutate(fear_rating_per_p = ntile(rating, n = 4))

# -------------------------------------------------------------------------

write_csv(final_dataset, OUTPUT_FINAL)

cat("Success: Pipeline terminé.", nrow(final_dataset), "lignes traitées.\n") 