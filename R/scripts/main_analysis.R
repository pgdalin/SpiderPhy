# -------------------------------------------------------------------------

cat("Pipeline starting...")

# -------------------------------------------------------------------------

# This script has as a goal to perform the concatenation of all stimuli files and left_join() of the physiologic data with them.

library(tidyverse) # Bestest library ever <3
library(janitor)

# -------------------------------------------------------------------------

PATH_STIMULI <- "../osf_files/rating_data/" 
PATH_PHYSIO  <- "../Python/output/processed_physio.csv" 
OUTPUT_FINAL <- "output/final_consolidated_data.csv" 

# -------------------------------------------------------------------------


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

stimuli_files <- list.files(path = PATH_STIMULI, pattern = "^ID_.*\\.csv$", full.names = TRUE, recursive = FALSE) 

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
  )

# -------------------------------------------------------------------------

write_csv(final_dataset, OUTPUT_FINAL)

cat("Success: Pipeline terminé.", nrow(final_dataset), "lignes traitées.\n") 