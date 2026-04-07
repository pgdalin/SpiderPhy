# -------------------------------------------------------------------------
# lmm.R
# Modèles linéaires à effets mixtes — physiologie ~ peur × arachnophobie
# -------------------------------------------------------------------------

library(tidyverse)
library(lmerTest)
library(broom.mixed)
library(glue)
library(writexl)

data <- read.csv("./output/final_consolidated_data.csv")

# ── Variables dépendantes ─────────────────────────────────────────────────────

vds <- c(
  "bpm_ecg", "rmssd", "cardiac_deceleration",
  "scr_amplitude", "resp_std",
  "pupil_diam_raw", "pupil_dilation_speed", "gaze_dispersion"
)

# ── Centrage des prédicteurs ──────────────────────────────────────────────────
# Les psychométriques sont centrées sur la grande moyenne (niveau participant).
# fear_rating_per_p est centré intra-participant (group-mean centering) pour
# séparer proprement les effets de niveau 1 et niveau 2.

data <- data |>
  group_by(participant_id) |>
  mutate(fear_rating_cwc = fear_rating_per_p - mean(fear_rating_per_p, na.rm = TRUE)) |>
  ungroup() |>
  mutate(across(c(FSQ_pre, SAS_pre, SPQ, STAI), 
                ~ scale(.x)[, 1],
                .names = "{.col}_z"))

# ── Sélection parcimonieuse de la structure aléatoire ────────────────────────
# Inchangée — on compare intercept seul, pente seule, pente + corrélation.

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

# ── Étape 1 : effet principal des psychométriques (niveau participant) ────────
# Question : les personnes plus arachnophobes ont-elles une réponse
# physiologique globalement différente, indépendamment de l'essai ?
#
# Modèle : vd ~ fear_rating_cwc + PSY_z + (structure aléatoire)
# PSY_z = FSQ_pre, SAS_pre, SPQ ou STAI (testés séparément)

run_lmm_main_effect <- function(vd_name, psy_name, df) {

  make_formula <- function(random) {
    as.formula(glue("{vd_name} ~ fear_rating_cwc + {psy_name} + {random}"))
  }

  f_simple <- make_formula("(1 | participant_id) + (1 | picture_id)")
  f_pente  <- make_formula("(1 | picture_id) + (0 + fear_rating_cwc | participant_id)")
  f_full   <- make_formula("(1 | picture_id) + (1 + fear_rating_cwc | participant_id)")

  fit <- function(f) lmer(f, data = df, REML = FALSE)

  best      <- select_best_model(fit(f_simple), fit(f_pente), fit(f_full))
  best_reml <- lmer(best$formula, data = df, REML = TRUE)

  best_reml |>
    tidy(conf.int = TRUE) |>
    filter(effect == "fixed", term != "(Intercept)") |>
    mutate(
      dependent_var      = vd_name,
      psychometric       = psy_name,
      model_type         = "main_effect",
      selected_structure = best$type
    ) |>
    select(dependent_var, psychometric, model_type, selected_structure,
           term, estimate, std.error, p.value, conf.low, conf.high)
}

# ── Étape 2 : modération (interaction niveau 1 × niveau 2) ───────────────────
# Question : l'effet de la peur essai par essai sur la physiologie est-il
# plus fort chez les personnes très arachnophobes ?
#
# Modèle : vd ~ fear_rating_cwc * PSY_z + (structure aléatoire)

run_lmm_interaction <- function(vd_name, psy_name, df) {

  make_formula <- function(random) {
    as.formula(glue("{vd_name} ~ fear_rating_cwc * {psy_name} + {random}"))
  }

  f_simple <- make_formula("(1 | participant_id) + (1 | picture_id)")
  f_pente  <- make_formula("(1 | picture_id) + (0 + fear_rating_cwc | participant_id)")
  f_full   <- make_formula("(1 | picture_id) + (1 + fear_rating_cwc | participant_id)")

  fit <- function(f) lmer(f, data = df, REML = FALSE)

  best      <- select_best_model(fit(f_simple), fit(f_pente), fit(f_full))
  best_reml <- lmer(best$formula, data = df, REML = TRUE)

  best_reml |>
    tidy(conf.int = TRUE) |>
    filter(effect == "fixed", term != "(Intercept)") |>
    mutate(
      dependent_var      = vd_name,
      psychometric       = psy_name,
      model_type         = "interaction",
      selected_structure = best$type
    ) |>
    select(dependent_var, psychometric, model_type, selected_structure,
           term, estimate, std.error, p.value, conf.low, conf.high)
}

# ── Exécution ─────────────────────────────────────────────────────────────────

psy_scales <- c("FSQ_pre_z", "SAS_pre_z", "SPQ_z", "STAI_z")

# Toutes les combinaisons VD × échelle psychométrique
combinations <- expand_grid(vd = vds, psy = psy_scales)

# Étape 1 — effets principaux
results_main <- combinations |>
  mutate(results = map2(vd, psy, run_lmm_main_effect, df = data)) |>
  unnest(results) |>
  select(-vd, -psy) |> 
  mutate(across(where(is.numeric),
                \(x) round(x, digits = 3)))

# Étape 2 — interactions
results_interaction <- combinations |>
  mutate(results = map2(vd, psy, run_lmm_interaction, df = data)) |>
  unnest(results) |>
  select(-vd, -psy) |> 
  mutate(across(where(is.numeric),
                \(x) round(x, digits = 3)))

# Consolidation
stats_finales <- bind_rows(results_main, results_interaction) |>
  mutate(across(where(is.numeric), ~ round(.x, 3))) |>
  arrange(model_type, dependent_var, psychometric, term) |> 
  mutate(across(where(is.numeric),
                \(x) round(x, digits = 3)))

# ── Affichage ─────────────────────────────────────────────────────────────────

cat("\n── Structures aléatoires sélectionnées ──\n")
stats_finales |>
  distinct(dependent_var, psychometric, model_type, selected_structure) |>
  print(n = Inf)

cat("\n── Résultats complets ──\n")
print(stats_finales, n = Inf)

# ── Étape 3 : comparaison des psychométriques comme prédicteurs ───────────────
# Pour chaque VD, quel instrument prédit le mieux la réponse physiologique ?
# On regarde la taille d'effet (estimate standardisé) et la significativité
# de l'effet principal de chaque échelle.

cat("\n── Comparaison des psychométriques par VD ──\n")
stats_finales |>
  filter(
    model_type == "main_effect",
    term %in% psy_scales
  ) |>
  select(dependent_var, psychometric, estimate, std.error, p.value) |>
  arrange(dependent_var, p.value) |>
  print(n = Inf)

# -------------------------------------------------------------------------

results <- list(
  "stats_finales" = stats_finales,
  "results_main" = results_main,
  "results_interaction" = results_interaction
)

writexl::write_xlsx(x = results, path = "./output/lmm.xlsx")

