
# -------------------------------------------------------------------------

library(tidyverse)
library(readxl)

# -------------------------------------------------------------------------

psychometrics <- read_excel(path = "../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx") # Loading the file.

# -------------------------------------------------------------------------

psychometrics <- psychometrics |> 
  filter(str_detect(ID, pattern = "^ID")) # Getting rid of mean and other stuff.
