library(tidyverse)
library(lmerTest)
library(broom.mixed)
library(glue)


# -------------------------------------------------------------------------

data <- read.csv("./output/final_consolidated_data.csv")

# -------------------------------------------------------------------------

select_best_model <- function(m_simple, m_pente, m_full) {
  p_pente <- anova(m_simple, m_pente)[["Pr(>Chisq)"]][2]
  
  if (is.na(p_pente) || p_pente >= 0.05) {
    return(list(formula = formula(m_simple), type = "Simple (intercepts only)"))
  }
  
  p_corr <- anova(m_pente, m_full)[["Pr(>Chisq)"]][2]
  
  if (!is.na(p_corr) && p_corr < 0.05) {
    list(formula = formula(m_full), type = "Full (intercept + pente + corr)")
  } else {
    list(formula = formula(m_pente), type = "Pente (intercept + pente, sans corr)")
  }
}

run_parsimonious_lmm <- function(vd_name, df) {
  
  make_formula <- function(random) {
    as.formula(glue("{vd_name} ~ fear_rating_per_p + {random}"))
  }
  
  f_simple <- make_formula("(1 | participant_id) + (1 | picture_id)")
  f_pente  <- make_formula("(1 | picture_id) + (0 + fear_rating_per_p | participant_id)")
  f_full   <- make_formula("(1 | picture_id) + (1 + fear_rating_per_p | participant_id)")
  
  fit <- function(f) lmer(f, data = df, REML = FALSE)
  
  best <- select_best_model(fit(f_simple), fit(f_pente), fit(f_full))
  
  # ✅ Refit avec REML = TRUE en utilisant la formule extraite
  best_reml <- lmer(best$formula, data = df, REML = TRUE)
  
  best_reml |>
    tidy(conf.int = TRUE) |>
    filter(effect == "fixed", term != "(Intercept)") |>
    mutate(
      dependent_var      = vd_name,
      selected_structure = best$type
    ) |>
    select(dependent_var, selected_structure, term, estimate, std.error, p.value, conf.low, conf.high)
}

# -------------------------------------------------------------------------

vds <- c("bpm_ecg", "rmssd", "cardiac_deceleration", "scr_amplitude",
         "resp_std", "pupil_diam_raw", "pupil_dilation_speed", "gaze_dispersion")

# -------------------------------------------------------------------------

stats_finales <- tibble(vd = vds) |>
  mutate(results = map(vd, run_parsimonious_lmm, df = data)) |>
  unnest(results) |>
  select(-vd) |>
  mutate(across(where(is.numeric), ~round(.x, 3))) |>
  arrange(dependent_var, term)

# -------------------------------------------------------------------------

stats_finales |>
  distinct(dependent_var, selected_structure) |>
  print()

# -------------------------------------------------------------------------

# Résultats complets
print(stats_finales)