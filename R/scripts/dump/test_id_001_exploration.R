library(tidyverse)

# -------------------------------------------------------------------------

lsl_data <- read.csv("../Python/output/test_ID_001_lsl_data.csv", fileEncoding = "latin1")

# -------------------------------------------------------------------------

glimpse(lsl_data)

# -------------------------------------------------------------------------

lsl_data |> 
  filter(is_baseline == 0) |> 
  summarise(count = n())

# Okay, so we're missing some here... Should be 228, not 224.
# I can't just go ahead a do a left_join(). I have to check in the .mat, using Python, if there are only 224 events recorded with the marker "1"...
# Indeed, there are only 4. I'm not sure how to proceed.
# I'll have to take a look at the stimuli files see what's going on there.
# I've started the file 02_stimuli_id_001_exploration.R to do that.
