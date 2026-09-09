#!/usr/bin/env Rscript
# verify_reported_values.R
#
# Reproduce, from committed outputs, every headline value the manuscript and
# README assert. Rescued from an ad-hoc audit so the claims are reproducible
# rather than remembered.
#
# The failure this prevents: a number quoted in prose that no longer matches
# the analysis. docs/APPENDIX-ITEMS-1-6-PROVENANCE.md records an audit that
# used exactly these comparisons; this script is that audit, made runnable.
#
#     Rscript tools/verify_reported_values.R
#
# Exits non-zero if any value disagrees. Reads only; writes nothing.

OUT <- "mysterycall_outputs"
rd  <- function(f) utils::read.csv(file.path(OUT, f), stringsAsFactors = FALSE)
fail <- 0L
chk <- function(label, got, want, tol = 0.005) {
  ok <- isTRUE(all(abs(as.numeric(got) - as.numeric(want)) <= tol))
  cat(sprintf("  %-42s %-22s %s\n", label,
              paste(sprintf("%.4g", got), collapse = " / "),
              if (ok) "ok" else sprintf("MISMATCH (expected %s)",
                                        paste(want, collapse = " / "))))
  if (!ok) fail <<- fail + 1L
}

cat("=== denominators ===\n")
ca <- rd("mysterycall_access_cascade.csv")
d  <- rd("labubu_cleaned_analysis.csv")
tf <- function(x) x %in% c(TRUE, "TRUE", 1, "1")
chk("reached a live office",      ca$n[ca$measure == "Reached a live office"], 108)
chk("eligible for offer model",   ca$n[ca$measure == "Eligible for offer model"], 102)
chk("historical inclusion",       sum(tf(d$analytic_inclusion)), 98)

cat("\n=== strict offer rates by scenario ===\n")
os <- rd("mysterycall_offer_by_scenario.csv")
g  <- function(s) 100 * os$rate[os$scenario == s]
chk("straight couple",  g("Straight couple"), 75.68, 0.05)
chk("lesbian couple",   g("Lesbian couple"),  42.42, 0.05)
chk("single mother",    g("Single mother"),   50.00, 0.05)

cat("\n=== triad odds ratios ===\n")
ep <- file.path(OUT, "estimands.csv")
if (!file.exists(ep)) {
  cat("  estimands.csv absent; run .github/scripts/estimand-report.R first\n")
  fail <- fail + 1L
} else {
  e <- rd("estimands.csv")
  or <- function(id) { r <- e[e$estimand_id == id, ]; c(r$estimate, r$lower, r$upper) }
  chk("OR triad lesbian (est, lo, hi)",       or("or_triad_lesbian_couple"), c(0.04, 0.01, 0.28), 0.01)
  chk("OR triad single mother (est, lo, hi)", or("or_triad_single_mother"),  c(0.09, 0.01, 0.65), 0.01)
  chk("OR broad lesbian (est, lo, hi)",       or("or_broad_lesbian_couple"), c(0.31, 0.08, 1.25), 0.01)
  chk("OR broad single mother (est, lo, hi)", or("or_broad_single_mother"),  c(0.29, 0.06, 1.27), 0.01)
}

cat("\n=== caller confounding ===\n")
mc <- rd("manuscript_claims.csv")
chk("Cramer's V", mc$estimate[mc$claim_id == "caller_cramers_v"], 0.664, 0.005)

cat("\n=== practitioner stratification ===\n")
sp <- rd("service_prevalence_by_practitioner.csv")
row <- function(s, col) sp[[col]][sp$service == s]
chk("IUI, physician-led (%)",        row("Intrauterine insemination (IUI)", "phys_pct"), 2.56, 0.05)
chk("IUI, FertilityCare (%)",        row("Intrauterine insemination (IUI)", "fc_pct"),   0.00, 0.05)
chk("hormonal labs, physician (%)",  row("Hormonal labs / fertility timing", "phys_pct"), 87.18, 0.05)
chk("hormonal labs, FertilityCare (%)", row("Hormonal labs / fertility timing", "fc_pct"), 47.46, 0.05)

cat(sprintf("\n%d value(s) disagree\n", fail))
quit(status = if (fail) 1L else 0L)
