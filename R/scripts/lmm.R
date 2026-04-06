# -------------------------------------------------------------------------

# This script has as a goal to analyse using a mixed models effet, the role of
# each dependant variable on independant variables computed by process_mat.py.

library(tidyverse)
library(lmerTest)
library(broom.mixed)

# -------------------------------------------------------------------------

data <- read.csv("../R/output/final_consolidated_data.csv")

# -------------------------------------------------------------------------

# We divide each picture in 4 quartiles using fear ratings. We will compare each
# expecting a linear tendency.

data <- data |> 
  group_by(participant_id) |> 
  mutate(fear_rating_per_p = ntile(x = rating, 4))

data <- data |> 
  mutate(fear_rating_global = ntile(x = rating, 4))

# Checking cor between global fear and per participants.

cor(data$fear_rating_per_p, data$fear_rating_global, use = "complete.obs", method = "pearson")

# 1 is crazy high, but hey that's has good has it gets.

# -------------------------------------------------------------------------

# Those are all the dependant variables we computed in process_mat.py.

vds <- c("bpm_ecg", "rmssd", "cardiac_deceleration", "scr_amplitude",
         "resp_std", "pupil_diam_raw", "pupil_dilation_speed", "gaze_dispersion")

# This function runs a linear mixed model, returns à df.

run_lmm <- function(vd_name, df) {
  formula <- glue::glue("{vd_name} ~ as.factor(fear_rating_per_p) + (1 | participant_id) + (1 | picture_id)")
  
  lmer(as.formula(formula), data = df) |>
    tidy(conf.int = TRUE) |>
    filter(effect == "fixed", term != "(Intercept)") |>
    mutate(dependent_var = vd_name) |>
    select(dependent_var, term, estimate, std.error, statistic, p.value, conf.low, conf.high)
}

# We iterate the function run_lmm on each dependant variable of the dataset
# using map().

stats_summary <- tibble(vd = vds) |>
  mutate(results = map(vd, run_lmm, df = data)) |>
  unnest(results) |>
  select(-vd) |>
  arrange(dependent_var, term) |> 
  mutate(across(where(is.numeric),
                \(x) round(x, digits = 3)))

# print(stats_summary, n = Inf)

# Writing the results in a CSV.

write.csv(stats_summary, file = "../R/output/mixted_effect_model.csv")
