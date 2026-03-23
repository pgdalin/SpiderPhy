# packages ----------------------------------------------------------------

library(tidyverse)

# data --------------------------------------------------------------------

pre_processed <- read.csv("../Python/output/processed_physio.csv")
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

# marker_code count
# <dbl> <int>
#   1           0   312
# 2           1 11872
# 3           2    21
# 4          12     3
# 
# A bit confused by this...

# pre_processed |> 
#   select(peaks) |> 
#   summarize(mean = mean(peaks, na.rm = TRUE))
# 
# > pre_processed |> 
#   +   select(peaks) |> 
#   +   summarize(mean = mean(peaks, na.rm = TRUE))
# mean
# 1 160.5758
# 
# Must have been terrifying spiders. Something is wrong with my Python script.
# 
# Let's check if there are some participants causing the problem tho.

# Changed the Python script to use Pulse instead of ECG.

pre_processed |> 
  summarise(mean = mean(n_peaks, na.rm = TRUE))

# > pre_processed |> 
#   +   summarise(mean = mean(n_peaks, na.rm = TRUE))
# mean
# 1 71.88401
# 
# Works now I guess.

pre_processed |> 
  filter(participant_id == 44) |> 
  summarise(count = n())
# 
# > pre_processed |> 
#   +   filter(participant_id == 1) |> 
#   +   summarise(count = n())
# count
# 1   232
# > ratings_01 |>
#   +   summarise(count = n())
# count
# 1   228
# 
# Okay, so we definitively have some kind of issue here I guess.

test_file <- read.csv("../Python/scripts/test_ID_001_lsl_data.csv")

test_file |> 
  filter(marker_code == 1) |> 
  summarise(count = n())

check_sync <- test_file |>
  filter(marker_code == 1) |>
  mutate(order_found = row_number())
