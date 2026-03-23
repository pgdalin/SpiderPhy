library(tidyverse)

# -------------------------------------------------------------------------

rating_data <- read.csv2("../osf_files/rating_data/ID_001_2019_Nov_20_1442.csv", fileEncoding = "latin1")

# -------------------------------------------------------------------------

glimpse(data)

# Ugly names, but it will do for now, we'll use janitor in the main script to join each file.

# -------------------------------------------------------------------------

# I just viewed the file, there are no time_stamps to figure out what's going on.
