library(tidyverse)

# -------------------------------------------------------------------------

rating_data <- read.csv2("../osf_files/rating_data/ID_001_2019_Nov_20_1442.csv", fileEncoding = "latin1")

# -------------------------------------------------------------------------

glimpse(rating_data)

# Ugly names, but it will do for now, we'll use janitor in the main script to join each file.

# -------------------------------------------------------------------------

# So, I notice the "Pause" I guess we'll have to filter this out.
# What's a bit worrying is wether or not the stimuli were presented in the same order for all participants, maybe it was randomized idk. I could iterate on each files and figure that out.

rating_data |> 
  filter(picture.ID == "Pause") |> 
  summarize(count = n())
