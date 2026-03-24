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

# More than a few NAs here... We have to investigate. Let's build a mask and only keep rows where there's an NA.

consolidated_data |> 
  filter(if_any(everything(), is.na)) |> 
  View()

# There is actually quite a lot of NAs there... It's not only one participant but several. I'm not sure I should waste time figuring out what's going on now.