# -------------------------------------------------------------------------

cat("Pipeline starting...")

# -------------------------------------------------------------------------

# This script has as a goal to perform the concatenation of all stimuli files and left_join() of the physiologic data with them.

library(tidyverse) # Bestest library ever <3
library(janitor) # Just for clean_names() basically.

# -------------------------------------------------------------------------

PATH_STIMULI <- "../osf_files/rating_data/" # Path towards the rating files.
PATH_PHYSIO  <- "../Python/output/processed_physio.csv" # Rating towards the file processed by 02_process_participants.py
OUTPUT_FINAL <- "output/final_consolidated_data.csv" # Output path of this script.

# -------------------------------------------------------------------------

# We're processing the file outputted by the Python script.

physio_raw <- read_csv(PATH_PHYSIO) |>
  mutate(participant_id = as.double(participant_id)) |> # make sure participant id is double, not chr.
  group_by(participant_id) |> # grouping by ID to perform operations.
  
  filter(
    !(marker_code == 0 & lead(marker_code) == 0), # Excludes the first of two consecutive baselines.
    !(row_number() == n() & marker_code == 0)    # Exclude last row if baseline.
  ) |>
  
  mutate(trial_number = cumsum(is_baseline)) |> # Calculating trial number by incrementing for each baseline.
  
  filter(marker_code == 1) |> # We only keep the trial rows.
  
  ungroup() |> # Ungrouping to avoid grouped operation later.
  relocate(trial_number, .before = 4)

# -------------------------------------------------------------------------

# Now we're treating each stimuli files. So, we first must build a variable with all the file names.

stimuli_files <- list.files(path = PATH_STIMULI, pattern = "^ID_.*\\.csv$", full.names = TRUE, recursive = FALSE) # Lists all the files within the directory, we add recursive = FALSE to avoid breaking the fun if anything is added into the directory later.

all_stimuli <- stimuli_files |>
  map_dfr(function(file) { # Iterating with a map() returning dataframes.
    
    p_id <- as.numeric(str_extract(basename(file), "(?<=ID_)\\d+")) # We extract the participant ID to add it as a col and later do the left_join() on it.
    
    read.csv2(file, fileEncoding = "latin1") |> # Opening the file, encoding is important as there are special characters in header.
      clean_names() |> # snake_case the names.
      
      filter(str_detect(picture_id, "\\.jpg|\\.JPG")) |> # filtering that way, could've used picture_id == "Pause".
      mutate(
        participant_id = p_id,
        trial_seq_id = row_number() # Both cols on which the left_join() will be performed.
      )
  })

# -------------------------------------------------------------------------

# We can now proceed to perform the left_join.

final_dataset <- all_stimuli |>
  left_join(physio_raw, by = c("participant_id", "trial_seq_id" = "trial_number")) |> # Joining per participant ID and also by trial number.
  mutate(
    condition_code = str_extract(picture_id, "(?<=_)[A-Za-z]+(?=_)"), # We extract the ID of the picture.
    condition = case_when(
      condition_code == "Sp" ~ "Spider", # if "Sp", then "Spider"
      condition_code == "Ne" ~ "Neutral", # if "Ne", then Neutral
      condition_code %in% c("CR", "CL", "SX") ~ "Control_Spider", # I'm not sure what that is honestly.
      TRUE ~ "Unknown" # We'll have to check later if there are unknowns.
    )
  )

# -------------------------------------------------------------------------

write_csv(final_dataset, OUTPUT_FINAL) # Write the output to CSV format.

cat("Success: Pipeline terminé.", nrow(final_dataset), "lignes traitées.\n") # Display message if success.

# Let's not forget that I'm supposed to treat the occulometric data... I'm not sure if it's good practice to separate it.