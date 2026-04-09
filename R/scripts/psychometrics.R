# -------------------------------------------------------------------------
# psychometrics.R
# Psychometric Analyses -- Internal Reliability and Convergent Validity
#
# Purpose:
#
#   - Assess the psychometric properties of the questionnaires and break
#     ratings used in the study:
#   - Descriptive statistics for composite scales (FSQ, SAS, SPQ, STAI);
#   - Convergent validity via inter-scale correlations;
#   - Internal reliability (Cronbach's alpha) for break ratings (Fear, Disgust,
#     Excitement) across the four experimental runs;
#   - Stationarity check to justify inclusion/exclusion of dimensions.
#
# Note:
#
#   FSQ, SAS, SPQ and STAI are only available as total scores. Internal
#     reliability (alpha/omega) cannot be computed here -- published validation 
#     values are used instead.
# -------------------------------------------------------------------------

library(tidyverse)
library(psych)
library(readxl)



# Data Import -------------------------------------------------------------

# Reads psychometric data and retains only valid participant rows
#   (rows whose ID starts with "ID").

psychometrics <- read_excel(
  "../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx",
  sheet = "data"
) |>
  filter(grepl("^ID", ID))



# Descriptive Statistics --------------------------------------------------

# Computes descriptive statistics for composite scales.
#
# FSQ, SAS, SPQ and STAI are available as total scores only -- internal
#   reliability cannot be estimated from item-level data. Published alpha values
#   from each instrument's validation study are used instead.

composite_scales <- psychometrics |>
  select(FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI)

describe(composite_scales) |>
  select(n, mean, sd, median, min, max, skew, kurtosis, se)



# Convergent Validity -----------------------------------------------------

# FSQ, SAS and SPQ all measure spider phobia -- high inter-scale correlations
#   are expected (convergent validity).
#
# STAI measures trait anxiety -- moderate correlations are anticipated,
#   given the conceptual overlap with phobia-related distress.

cor_matrix <- cor(composite_scales, use = "complete.obs", method = "pearson")
print(round(cor_matrix, 2))

corr.test(composite_scales, use = "complete")



# Break Rating Reliability ------------------------------------------------

# The four experimental runs provide four repeated measures of each
#   emotional dimension. These repetitions are treated as indicators of a
#   latent construct stable across the session -- defensible for Fear and
#   Disgust, which are not expected to show a systematic directional trend.
#
# Excluded dimensions:
#
#   - Exhaustion: structurally increases over time -> non-stationary;
#   - Boredom: same directional trend expected;
#   - Excitement: theoretically ambiguous direction in a phobia paradigm
#                   (resolved after visual inspection; see Stationarity Check).
#
# With a single factor, omega-h = omega-t by construction -- only alpha is 
#   reported, accompanied by the mean inter-item r as a redundancy indicator.

reliability_report <- function(items, label) {
  cat("\n", rep("=", 50), "\n", label, "\n", rep("=", 50), "\n", sep = "")
  
  alpha_res <- alpha(items)
  
  cat("\nAlpha de Cronbach :", round(alpha_res$total$raw_alpha, 3))
  cat("\n95% CI : [",
      round(alpha_res$total$raw_alpha - 1.96 * alpha_res$total$ase, 3), "-",
      round(alpha_res$total$raw_alpha + 1.96 * alpha_res$total$ase, 3), "]")
  cat("\nAlpha standardisé   :", round(alpha_res$total$std.alpha, 3))
  cat("\nInter-item r moyen  :", round(alpha_res$total$average_r, 3))
  cat("\n")
  
  print(alpha_res$item.stats |>
          select(r.cor, r.drop) |>
          round(3))
}

fear_items    <- psychometrics |> select(B1F, B2F, B3F, B4F)
disgust_items <- psychometrics |> select(B1D, B2D, B3D, B4D)

reliability_report(fear_items, "Fear -- cohérence inter-runs (B1F à B4F)")
reliability_report(disgust_items, "Disgust -- cohérence inter-runs (B1D à B4D)")



# Stationarity Check ------------------------------------------------------

# Plots the mean rating per run and dimension to verify that Fear and Disgust
#   do not exhibit a directional trend across runs -- unlike Exhaustion and
#   Boredom, whose exclusion is justified by this visual inspection.

psychometrics |>
  select(ID, starts_with("B")) |>
  pivot_longer(-ID,
               names_to  = c("run", "dimension"),
               names_pattern = "B(\\d)(.*)",
               values_to = "rating") |>
  mutate(
    run = as.integer(run),
    dimension = recode(dimension,
                       "F"  = "Fear",
                       "E"  = "Excitement",
                       "D"  = "Disgust",
                       "B"  = "Boredom",
                       "Ex" = "Exhaustion"
    )
  ) |>
  group_by(run, dimension) |>
  summarise(M  = mean(rating, na.rm = TRUE),
            SE = sd(rating, na.rm = TRUE) / sqrt(n()),
            .groups = "drop") |>
  ggplot(aes(x = run, y = M, color = dimension, group = dimension)) +
  geom_line() +
  geom_errorbar(aes(ymin = M - SE, ymax = M + SE), width = 0.1) +
  geom_point(size = 2) +
  labs(title    = "Évolution des ratings émotionnels par run",
       subtitle = "Justification de l'inclusion/exclusion pour les analyses de fiabilité",
       x        = "Run",
       y        = "Moyenne (+/- SE)",
       color    = "Dimension") +
  theme_minimal()

# Inclusion decisions after visual inspection:
#
#   Included : 
#   
#   - Disgust: (stable, slope =~ 0)
#   - Fear: (slight slope, wide SE -- to be noted as a limitation)
#   - Excitement: (empirically stable, arousal consistent with phobia)
#
#   Excluded : 
#   
#   - Exhaustion: (strong upward trend, non-stationary)
#   - Boredom: (moderate upward trend, non-stationary)



# Excitement Reliability --------------------------------------------------

# Excitement is included following the stationarity check above, which
#   confirmed empirical stability across runs.

excitement_items <- psychometrics |> select(B1E, B2E, B3E, B4E)

reliability_report(excitement_items, "Excitement -- cohérence inter-runs (B1E à B4E)")