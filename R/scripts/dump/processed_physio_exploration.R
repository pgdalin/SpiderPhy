# packages ----------------------------------------------------------------

library(tidyverse)

# data --------------------------------------------------------------------

pre_processed <- read.csv("../Python/output/test_ID_044_lsl_data.csv")
glimpse(pre_processed)

# -------------------------------------------------------------------------

pre_processed |> 
  summarise(across(everything(),
                   \(x) sum(is.na(x)),
                   .names = "{col}_na_count"))

# No missing values.
# 
# We should check counts for each trial_index I guess.

pre_processed |> 
  group_by(marker_code) |> 
  summarise(count = n())

# # A tibble: 2 × 2
# marker_code count
# <dbl> <int>
# 1           0   228
# 2           1   224
# 
# A bit confused by this... We shouldn't be missing any code 1 here...
# 
# Let's check on the entire processed file to anticipate a broad modification of the script.

pre_processed |> 
  summarise(mean = mean(n_peaks, na.rm = TRUE))

# > pre_processed |> 
# +   summarise(mean = mean(n_peaks, na.rm = TRUE))
# mean
# 1 74.60177
# 
# Plausible avg heartrate I guess.
# 
# We need to go back to that missing trial issue here...

pre_processed |> 
  select(trial_index, marker_code, is_baseline) |> 
  mutate(next_code = lead(marker_code),
         is_broken = marker_code == 0 & next_code != 1) |> 
  filter(is_broken)

pre_processed |> 
  select(trial_index, marker_code, is_baseline) |>
  tail()

# > pre_processed |> 
# +   select(trial_index, marker_code, is_baseline) |> 
# +   mutate(next_code = lead(marker_code),
# +          is_broken = marker_code == 0 & # next_code != 1) |> 
# +   filter(is_broken)
# trial_index marker_code is_baseline next_code is_broken
# 1         341           0           1         0      TRUE
# 2         685           0           1         0      TRUE
# 3        1029           0           1         0      TRUE
# > pre_processed |> 
# +   select(trial_index, marker_code, is_baseline) |>
# +   tail()
# trial_index marker_code is_baseline
# 447        1357           1           0
# 448        1361           0           1
# 449        1363           1           0
# 450        1367           0           1
# 451        1369           1           0
# 452        1373           0           1
# 
# # Yeah so there are a few missing values here and there actually... We'll have to build a function that binds everything together and making sure we associate each items with each other correctly.
# 
# I guess we'll just have to count baselines and use lead to get trial number

pre_processed <- pre_processed |> 
  
  filter(
    
    !(marker_code == 0 & lead(marker_code) == 0), # We're exluding baselines not followed by a stimulus.
    
    !(row_number() == n() & marker_code == 0) # If last row is a baseline, we're excluding it.
    
  ) |> 
  
  mutate(
    
    trial_number = cumsum(is_baseline) # Provides us with the trial number.
    
  ) |> 
  
  relocate(
    
    trial_number, .before = 4 # Just relocating it to use View() and check.
    
  ) # |> 
  
  # View()
  
# This must be performed on all of the data, it'll just require a group_by I guess. Now we need to check the structure of the stimulus CSVs to figure out how to join all of this.
  
pre_processed |> 
  group_by(is_baseline) |> 
  summarise(count = n())

  
