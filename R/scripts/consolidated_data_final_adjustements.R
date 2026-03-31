library(tidyverse)

# -------------------------------------------------------------------------

consolidated_data <- read.csv("./output/final_consolidated_data.csv")

OUTPUT_FINAL <- "output/final_consolidated_data.csv"

# -------------------------------------------------------------------------

consolidated_data <- consolidated_data |> 
mutate(picture_id = str_replace(picture_id, ".JPG$", ".jpg"),
       picture_id = str_replace(picture_id, "^p", "Sp"),
       picture_id = str_replace(picture_id, " ", ""))

write_csv(consolidated_data, OUTPUT_FINAL)