# -------------------------------------------------------------------------

# This script has as a goal to add to the analysis the psychometrics gathered
# on the degree of arachnophobia of each participants.

library(tidyverse)
library(readxl)

# -------------------------------------------------------------------------

psychometrics <- read_excel("../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx")
