# -------------------------------------------------------------------------
# Psychometric analyses — fiabilité et validité convergente
# -------------------------------------------------------------------------

library(tidyverse)
library(psych)
library(readxl)

# ---- 1. Import ----

psychometrics <- read_excel(
  "../osf_files/psychometric_data/spiderPhy_beh_psy.xlsx",
  sheet = "data"
) |> 
  filter(grepl("^ID", ID))

# ---- 2. Statistiques descriptives des échelles composites ----
# Note : FSQ, SAS, SPQ et STAI ne sont disponibles qu'en scores totaux.
# La fiabilité interne (α/ω) de ces instruments n'est donc pas calculable
# ici — on s'appuie sur les valeurs publiées dans leurs validations respectives.

composite_scales <- psychometrics |>
  select(FSQ_pre, FSQ_post, SAS_pre, SAS_post, SPQ, STAI)

describe(composite_scales) |>
  select(n, mean, sd, median, min, max, skew, kurtosis, se)

# ---- 3. Validité convergente entre échelles ----
# FSQ, SAS et SPQ mesurent tous la phobie des araignées — on s'attend
# à des corrélations élevées (validité convergente).
# STAI mesure l'anxiété générale — corrélations modérées attendues.

cor_matrix <- cor(composite_scales, use = "complete.obs", method = "pearson")
print(round(cor_matrix, 2))

# Significativité des corrélations
corr.test(composite_scales, use = "complete")

# ---- 4. Fiabilité des ratings de break (α et ω) ----
# Les 4 runs fournissent 4 mesures répétées de chaque dimension émotionnelle.
# On peut traiter ces répétitions comme 4 indicateurs d'un construit latent
# stable à travers l'expérience — ce qui est défendable pour Fear et Disgust,
# dont on n'attend pas de tendance directionnelle systématique entre les runs.
#
# On EXCLUT :
#   - Exhaustion : augmente structurellement avec le temps → non-stationnaire
#   - Boredom    : idem, tendance directionnelle attendue
#   - Excitement : direction théorique ambiguë dans un paradigme de phobie

# Extraction des items par dimension
fear_items <- psychometrics |> select(B1F, B2F, B3F, B4F)
disgust_items <- psychometrics |> select(B1D, B2D, B3D, B4D)

# ---- 4. Fiabilité des ratings de break ----
# Avec un seul facteur, ωh = ωt par construction → on rapporte uniquement α,
# accompagné de l'inter-item r moyen comme indicateur de redondance.

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
  
  # Tableau item-total pour détecter les items problématiques
  print(alpha_res$item.stats |> 
          select(r.cor, r.drop) |> 
          round(3))
}

reliability_report(fear_items,    "Fear — cohérence inter-runs (B1F à B4F)")
reliability_report(disgust_items, "Disgust — cohérence inter-runs (B1D à B4D)")

# ---- 5. Vérification de la stationnarité (justification de l'exclusion) ----
# On vérifie visuellement que Fear et Disgust n'ont pas de tendance
# directionnelle, contrairement à Exhaustion et Boredom.

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
  summarise(M = mean(rating, na.rm = TRUE),
            SE = sd(rating, na.rm = TRUE) / sqrt(n()),
            .groups = "drop") |>
  ggplot(aes(x = run, y = M, color = dimension, group = dimension)) +
  geom_line() +
  geom_errorbar(aes(ymin = M - SE, ymax = M + SE), width = 0.1) +
  geom_point(size = 2) +
  labs(title = "Évolution des ratings émotionnels par run",
       subtitle = "Justification de l'inclusion/exclusion pour les analyses de fiabilité",
       x = "Run", y = "Moyenne (± SE)", color = "Dimension") +
  theme_minimal()

# Décisions d'inclusion révisées après inspection visuelle (étape 5) :
#
#   Inclus  : Disgust  (stable, pente ≈ 0)
#             Fear     (légère pente, SE larges — à mentionner en limitation)
#             Excitement (stable empiriquement, arousal cohérent avec la phobie)
#
#   Exclus  : Exhaustion (tendance croissante forte, non-stationnaire)
#             Boredom    (tendance croissante modérée, non-stationnaire)

excitement_items <- psychometrics |> select(B1E, B2E, B3E, B4E)

reliability_report(excitement_items, "Excitement — cohérence inter-runs (B1E à B4E)")
