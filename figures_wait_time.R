library(ggplot2)
library(ggbeeswarm)
library(ggridges)
library(patchwork)
library(dplyr)
library(scales)
library(forcats)

fig_dir <- file.path("mysterycall_outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

dat_all <- read.csv(
  file.path("mysterycall_outputs", "labubu_cleaned_analysis.csv"),
  stringsAsFactors = FALSE
)

# Wait-time subset: analytic inclusions with an observed appointment
dat_wait <- dat_all |>
  filter(analytic_inclusion == TRUE, !is.na(business_days), business_days >= 0) |>
  mutate(
    scenario = factor(scenario,
                      levels = c("Straight couple", "Lesbian couple", "Single mother"))
  )

# Colour palette — colorblind-safe
pal <- c(
  "Straight couple" = "#2166AC",
  "Lesbian couple"  = "#D6604D",
  "Single mother"   = "#4DAC26"
)

scenario_labels <- c(
  "Straight couple" = "Straight\ncouple",
  "Lesbian couple"  = "Lesbian\ncouple",
  "Single mother"   = "Single\nmother"
)

# ── Figure 1: Raincloud (violin + boxplot + beeswarm) ─────────────────────────
medians <- dat_wait |>
  group_by(scenario) |>
  summarise(med = median(business_days, na.rm = TRUE),
            n   = n(),
            .groups = "drop")

p1 <- ggplot(dat_wait, aes(x = scenario, y = business_days, fill = scenario, colour = scenario)) +
  geom_violin(alpha = 0.25, linewidth = 0.4, width = 0.9, trim = FALSE) +
  geom_boxplot(width = 0.18, alpha = 0.6, outlier.shape = NA, linewidth = 0.5,
               colour = "grey30", fill = "white") +
  geom_beeswarm(size = 2.2, cex = 2.5, alpha = 0.85, shape = 21,
                stroke = 0.4, colour = "white", aes(fill = scenario)) +
  geom_text(data = medians,
            aes(x = scenario, y = med, label = paste0("Mdn=", round(med, 0))),
            vjust = -0.7, hjust = -0.05, size = 3, colour = "grey30",
            inherit.aes = FALSE) +
  scale_x_discrete(labels = scenario_labels) +
  scale_fill_manual(values = pal, guide = "none") +
  scale_colour_manual(values = pal, guide = "none") +
  scale_y_continuous(breaks = seq(0, 180, 30), limits = c(-5, 185)) +
  labs(
    title    = "Wait Time to Appointment by Caller Scenario",
    subtitle = "Restorative Reproductive Medicine practices — LABUBU audit",
    x        = NULL,
    y        = "Business days until first appointment",
    caption  = paste0(
      "n = ", nrow(dat_wait), " calls with observed appointment date. ",
      "Violin = distribution; box = IQR/median; points = individual observations.\n",
      "Business days exclude weekends and US federal holidays."
    )
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(colour = "grey50", size = 11),
    plot.caption  = element_text(colour = "grey55", size = 8.5, hjust = 0),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    axis.text.x  = element_text(size = 12)
  )

ggsave(file.path(fig_dir, "fig1_raincloud_wait_by_scenario.png"),
       p1, width = 7, height = 5.5, dpi = 300, bg = "white")

# ── Figure 2: Ridge density plot ──────────────────────────────────────────────
p2 <- ggplot(dat_wait,
             aes(x = business_days, y = fct_rev(scenario),
                 fill = scenario, colour = scenario)) +
  geom_density_ridges(
    alpha        = 0.55,
    linewidth    = 0.5,
    jittered_points = TRUE,
    point_size   = 1.8,
    point_alpha  = 0.7,
    position     = position_raincloud(adjust_vlines = TRUE)
  ) +
  geom_vline(data = medians,
             aes(xintercept = med, colour = scenario),
             linetype = "dashed", linewidth = 0.7, show.legend = FALSE) +
  scale_y_discrete(labels = rev(c("Straight\ncouple", "Lesbian\ncouple", "Single\nmother"))) +
  scale_x_continuous(breaks = seq(0, 180, 30), limits = c(-5, 190)) +
  scale_fill_manual(values = pal, guide = "none") +
  scale_colour_manual(values = pal, guide = "none") +
  labs(
    title    = "Distribution of Wait Times by Scenario",
    subtitle = "Dashed line = median per scenario",
    x        = "Business days until first appointment",
    y        = NULL,
    caption  = paste0("n = ", nrow(dat_wait), " calls. All distributions right-skewed.")
  ) +
  theme_ridges(font_size = 13, grid = FALSE) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(colour = "grey50", size = 11),
    plot.caption  = element_text(colour = "grey55", size = 8.5, hjust = 0)
  )

ggsave(file.path(fig_dir, "fig2_ridgeplot_wait_by_scenario.png"),
       p2, width = 7, height = 5, dpi = 300, bg = "white")

# ── Figure 3: Empirical CDF ───────────────────────────────────────────────────
ref_days <- c(10, 20, 30, 60)

p3 <- ggplot(dat_wait, aes(x = business_days, colour = scenario)) +
  stat_ecdf(linewidth = 1.1, pad = FALSE) +
  geom_vline(xintercept = ref_days, linetype = "dotted",
             colour = "grey70", linewidth = 0.5) +
  annotate("text", x = ref_days, y = 0.02,
           label = paste0(ref_days, "d"), size = 3, colour = "grey55",
           angle = 90, vjust = -0.4, hjust = 0) +
  scale_x_continuous(breaks = seq(0, 180, 30), limits = c(0, 185)) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     breaks = seq(0, 1, 0.25)) +
  scale_colour_manual(values = pal, name = NULL) +
  labs(
    title    = "Cumulative Appointment Access by Scenario",
    subtitle = "Proportion of callers offered an appointment within X business days",
    x        = "Business days until first appointment",
    y        = "Cumulative proportion",
    caption  = paste0("n = ", nrow(dat_wait), " calls. ECDF per scenario.")
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(colour = "grey50", size = 11),
    plot.caption  = element_text(colour = "grey55", size = 8.5, hjust = 0),
    legend.position   = "bottom",
    panel.grid.minor  = element_blank()
  )

ggsave(file.path(fig_dir, "fig3_ecdf_wait_by_scenario.png"),
       p3, width = 7, height = 5, dpi = 300, bg = "white")

# ── Figure 4: Within-practice paired dot plot ─────────────────────────────────
# Practices with ≥2 scenarios observed in the wait-time subset
multi <- dat_wait |>
  group_by(practice_id) |>
  filter(n_distinct(scenario) >= 2) |>
  ungroup()

p4 <- ggplot(multi, aes(x = scenario, y = business_days,
                         group = practice_id, colour = scenario)) +
  geom_line(aes(group = practice_id), colour = "grey75", linewidth = 0.5, alpha = 0.7) +
  geom_point(size = 3, alpha = 0.85) +
  scale_x_discrete(labels = scenario_labels) +
  scale_colour_manual(values = pal, guide = "none") +
  scale_y_continuous(breaks = seq(0, 180, 30), limits = c(-5, 185)) +
  labs(
    title    = "Within-Practice Wait Times Across Scenarios",
    subtitle = paste0("Practices with ≥2 scenarios observed (n = ",
                      n_distinct(multi$practice_id), " practices)"),
    x        = NULL,
    y        = "Business days until first appointment",
    caption  = "Lines connect calls to the same practice. Illustrates within-practice scheduling variation."
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(colour = "grey50", size = 11),
    plot.caption  = element_text(colour = "grey55", size = 8.5, hjust = 0),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(fig_dir, "fig4_within_practice_pairs.png"),
       p4, width = 7, height = 5.5, dpi = 300, bg = "white")

# ── Combined panel (patchwork) ────────────────────────────────────────────────
panel <- (p1 | p3) / (p2 | p4) +
  plot_annotation(
    title   = "LABUBU Audit — Wait Time Analyses",
    caption = "COMIRB 25-2596 · PI: Dr. Tyler Muffly, Denver Health",
    theme   = theme(
      plot.title   = element_text(face = "bold", size = 16),
      plot.caption = element_text(colour = "grey55", size = 9)
    )
  )

ggsave(file.path(fig_dir, "fig_panel_wait_times.png"),
       panel, width = 14, height = 11, dpi = 300, bg = "white")

cat("Figures written to", fig_dir, "\n")
cat("  fig1_raincloud_wait_by_scenario.png\n")
cat("  fig2_ridgeplot_wait_by_scenario.png\n")
cat("  fig3_ecdf_wait_by_scenario.png\n")
cat("  fig4_within_practice_pairs.png\n")
cat("  fig_panel_wait_times.png  (combined 2x2 panel)\n")
