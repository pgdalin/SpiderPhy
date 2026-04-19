# -------------------------------------------------------------------------
# plots.R
# Data Visualizations -- Forest Plot, Interaction Plot, Caterpillar Plot
#
# Input:
#   - ./output/lmm.xlsx
#   - ./output/final_consolidated_data.csv
#
# Output:
#   - ./output/plots/forest_plot.png
#   - ./output/plots/interaction_rmssd.png
#   - ./output/plots/caterpillar.png
# -------------------------------------------------------------------------

library(tidyverse)
library(readxl)

OUTPUT_DIR <- "./output/plots/"
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)



# Shared theme for all plots in this document.
# 
theme_spiderphy <- function() {
  theme_minimal(base_size = 12) +
    theme(
      panel.grid.minor  = element_blank(),
      panel.grid.major.y = element_blank(),
      axis.text         = element_text(color = "grey30"),
      plot.title        = element_text(face = "bold", size = 13),
      plot.subtitle     = element_text(color = "grey40", size = 10),
      legend.position   = "none"
    )
}

COL_SIG   <- "#2C7BB6"
COL_NOM   <- "#ABD9E9"
COL_NULL  <- "grey70" 




# Forest plot -------------------------------------------------------------

results <- read_excel("./output/lmm.xlsx", sheet = "results_main")

# Readable labels for dependent variables.
dv_labels <- c(
  "bpm_ecg"              = "Heart Rate (BPM)",
  "cardiac_deceleration" = "Cardiac Deceleration",
  "resp_std"             = "Respiratory Variability",
  "pupil_dilation_speed" = "Pupil Dilation Speed",
  "pupil_diam_raw"       = "Pupil Diameter (raw)",
  "rmssd"                = "RMSSD",
  "scr_amplitude"        = "SCR Amplitude",
  "gaze_dispersion"      = "Gaze Dispersion"
)

# Retain only the rating_cwc_z term, one row per DV (averaged across
# psychometric scale specs, estimate is identical across all four).
forest_data <- results |>
  filter(term == "rating_cwc_z") |>
  distinct(dependent_var, .keep_all = TRUE) |>
  mutate(
    label = dv_labels[dependent_var],
    label = fct_reorder(label, estimate),
    significance = case_when(
      p_fdr < .05  ~ "FDR significant",
      p.value < .05 ~ "Nominal only",
      TRUE          ~ "n.s."
    )
  )

forest_plot <- ggplot(forest_data,
                      aes(x = estimate, y = label, color = significance)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high),
                 height = 0.25, linewidth = 0.7) +
  geom_point(size = 3.5) +
  scale_color_manual(
    values = c(
      "FDR significant" = COL_SIG,
      "Nominal only"    = COL_NOM,
      "n.s."            = COL_NULL
    ),
    name = NULL
  ) +
  labs(
    title    = "Within-Person Effect of Fear Rating on Physiological Response",
    subtitle = "Standardized estimates (rating_cwc_z) with 95% CI, random intercepts model",
    x        = "Standardized estimate (β)",
    y        = NULL
  ) +
  theme_spiderphy() +
  theme(legend.position = "right")

ggsave(
  filename = file.path(OUTPUT_DIR, "forest_plot.png"),
  plot     = forest_plot,
  width    = 8, height = 5, dpi = 300
)

cat("Forest plot saved.\n")


# Interaction Plot, RMSSD * Phobia Severity -------------------------------
# 
# We use FSQ_pre_z as the moderator.
# The plot shows predicted RMSSD as a function of within-person fear rating,
# separately for low vs high phobia (-1 SD and +1 SD on FSQ_pre_z).

library(lme4)
library(lmerTest)

data <- read.csv("./output/final_consolidated_data.csv") |>
  group_by(participant_id) |>
  mutate(
    rating_cwc = rating - mean(rating, na.rm = TRUE),
    rating_pm  = mean(rating, na.rm = TRUE)
  ) |>
  ungroup() |>
  mutate(
    rating_cwc_z = as.numeric(scale(rating_cwc)),
    rating_pm_z  = as.numeric(scale(rating_pm)),
    FSQ_pre_z    = as.numeric(scale(FSQ_pre))
  )

# Refit the RMSSD interaction model.
m_rmssd <- lmer(
  rmssd ~ rating_cwc * FSQ_pre_z + rating_pm_z +
    (1 | participant_id) + (1 | picture_id),
  data = data, REML = TRUE
)

# Build a prediction grid: rating_cwc across its observed range,
# FSQ at -1 SD and +1 SD.
rating_seq <- seq(
  min(data$rating_cwc, na.rm = TRUE),
  max(data$rating_cwc, na.rm = TRUE),
  length.out = 100
)

pred_grid <- expand_grid(
  rating_cwc  = rating_seq,
  FSQ_pre_z   = c(-1, 1),
  rating_pm_z = 0
)

pred_grid$rmssd <- predict(m_rmssd, newdata = pred_grid, re.form = NA)

pred_grid <- pred_grid |>
  mutate(
    phobia_level = if_else(FSQ_pre_z == -1, "Low phobia (-1 SD)", "High phobia (+1 SD)"),
    phobia_level = factor(phobia_level,
                          levels = c("Low phobia (-1 SD)", "High phobia (+1 SD)"))
  )

interaction_plot <- ggplot(pred_grid, 
                           aes(x = rating_cwc, 
                               y = rmssd,
                               color = phobia_level, 
                               fill = phobia_level)) +
  geom_line(linewidth = 1.2) +
  scale_color_manual(values = c("Low phobia (-1 SD)" = COL_NOM,
                                "High phobia (+1 SD)" = COL_SIG)) +
  labs(
    title    = "RMSSD as a Function of Fear Rating and Phobia Severity",
    subtitle = "Predicted values from LMM, FSQ_pre as moderator (+/-1 SD)",
    x        = "Within-person fear rating (centered)",
    y        = "Predicted RMSSD (ms)",
    color    = NULL
  ) +
  theme_spiderphy() +
  theme(legend.position = "right")

ggsave(
  filename = file.path(OUTPUT_DIR, "interaction_rmssd.png"),
  plot     = interaction_plot,
  width    = 8, height = 5, dpi = 300
)

cat("Interaction plot saved.\n")

# ── 3. Caterpillar Plot, Random Intercepts by Participant ─────────────────

# Shows between-participant variability in baseline cardiac deceleration,
#   justifying the use of random intercepts in the LMM.
# Each point is one participant's random intercept estimate (BLUP),
#   sorted by magnitude, with 95% credible intervals.

library(lattice)

m_caterpillar <- lmer(
  cardiac_deceleration ~ rating_cwc_z + rating_pm_z +
    (1 | participant_id) + (1 | picture_id),
  data = data, REML = TRUE
)

# Extract random effects with conditional variances.
re <- ranef(m_caterpillar, condVar = TRUE)

caterpillar_data <- as.data.frame(re$participant_id) |>
  rownames_to_column("participant_id") |>
  rename(intercept = `(Intercept)`) |>
  mutate(
    se = sqrt(attr(re$participant_id, "postVar")[1, 1, ]),
    ci_low  = intercept - 1.96 * se,
    ci_high = intercept + 1.96 * se,
    participant_id = fct_reorder(participant_id, intercept),
    significant = if_else(ci_low > 0 | ci_high < 0, "yes", "no")
  )

caterpillar_plot <- ggplot(caterpillar_data,
                           aes(x = intercept, y = participant_id,
                               color = significant)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  geom_errorbarh(aes(xmin = ci_low, xmax = ci_high),
                 height = 0.4, linewidth = 0.5) +
  geom_point(size = 2) +
  scale_color_manual(values = c("yes" = COL_SIG, "no" = COL_NULL)) +
  labs(
    title    = "Between-Participant Variability in Cardiac Deceleration",
    subtitle = "Random intercept estimates (BLUPs) with 95% CI, sorted by magnitude",
    x        = "Random intercept (ms)",
    y        = "Participant"
  ) +
  theme_spiderphy() +
  theme(
    axis.text.y  = element_text(size = 7),
    legend.position = "none"
  )

ggsave(
  filename = file.path(OUTPUT_DIR, "caterpillar.png"),
  plot     = caterpillar_plot,
  width    = 7, height = 9, dpi = 300
)

cat("Caterpillar plot saved.\n")



# Correlation Matrix, Physiological DVs -----------------------------------

library(ggcorrplot)

dvs <- c(
  "bpm_ecg", "cardiac_deceleration", "rmssd", "scr_amplitude",
  "resp_std", "pupil_diam_raw", "pupil_dilation_speed", "gaze_dispersion"
)

dv_labels_short <- c(
  "bpm_ecg"              = "BPM",
  "cardiac_deceleration" = "Card. Decel.",
  "rmssd"                = "RMSSD",
  "scr_amplitude"        = "SCR Amp.",
  "resp_std"             = "Resp. Var.",
  "pupil_diam_raw"       = "Pupil Diam.",
  "pupil_dilation_speed" = "Pupil Dil.",
  "gaze_dispersion"      = "Gaze Disp."
)

cor_data <- data |>
  select(all_of(dvs)) |>
  cor(use = "pairwise.complete.obs")

# Remplace les noms de lignes et colonnes après le calcul.
rownames(cor_data) <- dv_labels_short[rownames(cor_data)]
colnames(cor_data) <- dv_labels_short[colnames(cor_data)]

corr_plot <- ggcorrplot(
  cor_data,
  method   = "circle",
  type     = "lower",
  lab      = TRUE,
  lab_size = 3,
  colors   = c(COL_SIG, "white", "#D7191C"),
  outline.color = "white",
  tl.cex   = 10
) +
  labs(
    title    = "Correlations Among Physiological Dependent Variables",
    subtitle = "Pairwise complete observations, lower triangle"
  ) +
  theme_spiderphy() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "right"
  )

ggsave(
  filename = file.path(OUTPUT_DIR, "correlation_matrix.png"),
  plot     = corr_plot,
  width    = 8, height = 7, dpi = 300
)

cat("Correlation matrix saved.\n")




# Violin Plot, Fear Ratings by Participant --------------------------------

violin_data <- data |>
  mutate(participant_id = factor(participant_id)) |>
  group_by(participant_id) |>
  mutate(mean_rating = mean(rating, na.rm = TRUE)) |>
  ungroup() |>
  mutate(participant_id = fct_reorder(participant_id, mean_rating))

violin_plot <- ggplot(violin_data,
                      aes(x = participant_id, y = rating)) +
  geom_violin(fill = COL_NOM, color = NA, alpha = 0.7) +
  geom_point(aes(y = mean_rating), color = COL_SIG,
             size = 1.5, alpha = 0.9) +
  labs(
    title    = "Distribution of Fear Ratings per Participant",
    subtitle = "Sorted by individual mean, dot indicates mean rating",
    x        = "Participant (sorted by mean rating)",
    y        = "Fear rating (0-100)"
  ) +
  theme_spiderphy() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1, size = 7)
  )

ggsave(
  filename = file.path(OUTPUT_DIR, "violin_ratings.png"),
  plot     = violin_plot,
  width    = 12, height = 5, dpi = 300
)

cat("Violin plot saved.\n")



# Figure 2 Replication, Physiological Response by Fear Quartile -----------

# Reproduces the within-subject quartile comparison from Lor et al.
# For each DV, computes the mean response per fear quartile per participant,
# then plots the group distribution as a violin + individual points.

quartile_labels <- c("1" = "Q1\n(Low)", "2" = "Q2", "3" = "Q3", "4" = "Q4\n(High)")

dvs_fig2 <- c(
  "bpm_ecg", "cardiac_deceleration", "scr_amplitude", "resp_std"
)

dv_labels_fig2 <- c(
  "bpm_ecg"              = "Heart Rate (BPM)",
  "cardiac_deceleration" = "Cardiac Deceleration (ms)",
  "scr_amplitude"        = "SCR Amplitude",
  "resp_std"             = "Respiration Amplitude"
)

# Within-person fear quartile (1-4) based on raw rating.
fig2_data <- data |>
  group_by(participant_id) |>
  mutate(fear_q = ntile(rating, 4)) |>
  ungroup() |>
  select(participant_id, fear_q, all_of(dvs_fig2)) |>
  pivot_longer(
    cols      = all_of(dvs_fig2),
    names_to  = "dv",
    values_to = "value"
  ) |>
  group_by(participant_id, fear_q, dv) |>
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
  mutate(
    fear_q = factor(fear_q),
    dv     = factor(dv, levels = dvs_fig2, labels = dv_labels_fig2)
  )

fig2_plot <- ggplot(fig2_data,
                    aes(x = fear_q, y = value)) +
  geom_violin(fill = COL_NOM, color = NA, alpha = 0.6) +
  geom_point(alpha = 0.4, size = 1, color = "grey40",
             position = position_jitter(width = 0.05)) +
  stat_summary(fun = mean, geom = "point",
               size = 3.5, color = COL_SIG) +
  stat_summary(fun = mean, geom = "line",
               aes(group = 1), color = COL_SIG, linewidth = 1) +
  scale_x_discrete(labels = quartile_labels) +
  facet_wrap(~ dv, scales = "free_y", nrow = 1) +
  labs(
    title    = "Physiological Responses Across Fear Quartiles",
    subtitle = "Replication of Lor et al. Figure 2, mean +/- individual data points",
    x        = "Fear quartile (within-person)",
    y        = "Mean response"
  ) +
  theme_spiderphy() +
  theme(
    strip.text = element_text(size = 9, face = "bold"),
    panel.spacing = unit(1.2, "lines")
  )

ggsave(
  filename = file.path(OUTPUT_DIR, "figure2_replication.png"),
  plot     = fig2_plot,
  width    = 14, height = 5, dpi = 300
)

cat("Figure 2 replication saved.\n")