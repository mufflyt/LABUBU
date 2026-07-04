#!/usr/bin/env Rscript
# call_progress.R — quick single-mother call completion status.
# Reads the last analysis output; does NOT re-run anything. Use mid-effort to
# check how many single-mother calls remain against Sofie's returned sheets.
#
#     Rscript call_progress.R

cov_path <- "mysterycall_outputs/practice_scenario_coverage.csv"
if (!file.exists(cov_path))
  stop("No coverage file yet — run Rscript refresh.R first.")

cov <- read.csv(cov_path, stringsAsFactors = FALSE)
tf  <- function(x) x %in% c(TRUE, "TRUE", "True")

n        <- nrow(cov)
have_sm  <- sum(tf(cov$has_sm))
triads   <- sum(cov$n_scenarios == 3)
prio1    <- sum(tf(cov$has_straight) & tf(cov$has_lesbian) & !tf(cov$has_sm))
pct      <- function(x) sprintf("%.0f%%", 100 * x / n)

cat("── LABUBU single-mother call progress ──\n")
cat(sprintf("  Total practices:             %d\n", n))
cat(sprintf("  Single-mother calls done:    %d / %d  (%s)  — %d remaining\n",
            have_sm, n, pct(have_sm), n - have_sm))
cat(sprintf("  Complete triads:             %d / %d  (%s)\n", triads, n, pct(triads)))
cat(sprintf("  Priority-1 calls remaining:  %d  (practice has straight + lesbian, needs SM)\n", prio1))
if (n - have_sm == 0)
  cat("\n  All single-mother calls are in. Run `Rscript refresh.R`, then re-check the\n",
      "  within-practice paired analysis and whether it clears the power floor.\n")
