library(tidyverse)

# -------------------------------------------------------------------------

consolidated_data <- read.csv("./output/final_consolidated_data.csv")

# -------------------------------------------------------------------------

glimpse(consolidated_data)

# -------------------------------------------------------------------------

consolidated_data |> 
  summarise(across(everything(),
                   \(x) sum(is.na(x)),
                   .names = "{.col}_na_count"))

# More than a few NAs here... 

consolidated_data |>
  group_by(picture_id) |> 
  summarize(count = n())
  # View()

# I just noticed while running heatmap_generation.py that some file names have issues like ending with .JPG or missing the "S" at the beginning of "Spider"

consolidated_data <- consolidated_data |> 
  mutate(picture_id = str_replace(picture_id, ".JPG$", ".jpg"),
         picture_id = str_replace(picture_id, "^p", "Sp"),
         picture_id = str_replace(picture_id, " ", ""))

OUTPUT_FINAL <- "output/final_consolidated_data.csv"

write_csv(consolidated_data, OUTPUT_FINAL)
