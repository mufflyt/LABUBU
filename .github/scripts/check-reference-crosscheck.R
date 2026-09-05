#!/usr/bin/env Rscript
# check-reference-crosscheck.R
#
# Recompute the manuscript's reported quantities from independent reference
# implementations and require agreement. Pattern borrowed from
# mufflyt/isochrones-ci ("test-statistics-crosscheck.R"), whose argument is:
#
#   "Every reference here is written from the formula, not delegated to the R
#    function production also calls."
#
# LABUBU's other twenty invariants are structural. This one is numeric, and it
# is the only check in the repository that does not call `mysterycall`.
#
# It found the MDE defect on its first run: the package reports a minimum
# detectable odds ratio computed by normal approximation, which at two to eight
# discordant pairs delivers roughly 44% power rather than 80%.

suppressWarnings(suppressPackageStartupMessages({ library(stats) }))
source("tools/reference_implementations.R")

OUT <- "mysterycall_outputs"
rd  <- function(f) utils::read.csv(file.path(OUT, f), stringsAsFactors = FALSE)

fail <- 0L; n_ok <- 0L
report <- function(id, ok, detail) {
  cat(sprintf("%-46s %s  -- %s\n", id, if (ok) "PASS" else "FAIL", detail))
  if (!ok) {
    cat(sprintf("::error title=%s::%s\n", id, detail))
    fail <<- fail + 1L
  } else n_ok <<- n_ok + 1L
}

# ── Wilson intervals on the service prevalences ───────────────────────────────
sv <- rd("mysterycall_service_prevalence.csv")
bad <- character(0)
for (i in seq_len(nrow(sv))) {
  r <- ref_wilson_ci(sv$n[i], sv$total[i])
  if (abs(r[["lower"]] - sv$ci_lower[i]) > 5e-4 ||
      abs(r[["upper"]] - sv$ci_upper[i]) > 5e-4 ||
      abs(r[["estimate"]] - sv$prevalence[i]) > 5e-4)
    bad <- c(bad, sprintf("%s: reported %.4f (%.4f-%.4f), reference %.4f (%.4f-%.4f)",
                          sv$option[i], sv$prevalence[i], sv$ci_lower[i], sv$ci_upper[i],
                          r[["estimate"]], r[["lower"]], r[["upper"]]))
}
report("crosscheck/wilson-intervals", length(bad) == 0,
       if (length(bad)) paste(bad, collapse = "; ")
       else sprintf("%d service prevalences match the Wilson formula", nrow(sv)))

# ── Exact McNemar p-values ────────────────────────────────────────────────────
mc  <- rd("mysterycall_paired_acceptance_mcnemar.csv")
bad <- character(0)
for (i in seq_len(nrow(mc))) {
  p <- ref_mcnemar_exact_p(mc$disc_favor_A[i], mc$disc_favor_B[i])
  # The CSV stores p to three decimals, so compare at that precision rather
  # than demanding equality with a value that was rounded on the way to disk.
  if (abs(p - mc$mcnemar_p[i]) > 5e-4)
    bad <- c(bad, sprintf("%s: reported p=%.6f, reference p=%.6f",
                          mc$contrast[i], mc$mcnemar_p[i], p))
}
report("crosscheck/mcnemar-exact-p", length(bad) == 0,
       if (length(bad)) paste(bad, collapse = "; ")
       else sprintf("%d paired contrasts match the exact binomial", nrow(mc)))

# ── Minimum detectable odds ratio ─────────────────────────────────────────────
# The reported MDE must actually deliver the power it claims. A contrast whose
# discordant count admits NO rejection region at alpha has no MDE at all, and
# reporting a finite number for it asserts detectability that does not exist.
bad <- character(0)
for (i in seq_len(nrow(mc))) {
  d   <- mc$discordant[i]
  ref <- ref_mde_or_paired(d)
  rep <- mc$mde_or_80power[i]
  if (is.na(ref)) {
    if (!is.na(rep))
      bad <- c(bad, sprintf("%s: %d discordant pairs admit no rejection region at alpha=.05, so no effect size reaches 80%% power, but MDE OR %.1f is reported",
                            mc$contrast[i], d, rep))
    next
  }
  if (is.na(rep) || abs(ref - rep) / ref > 0.05) {
    # Quantify the consequence rather than just the disagreement.
    pw <- if (!is.na(rep)) {
      ks <- 0:d
      rj <- ks[vapply(ks, function(k) stats::binom.test(k, d, 0.5)$p.value <= 0.05, logical(1))]
      p  <- rep / (1 + rep)
      sum(stats::dbinom(rj, d, p))
    } else NA_real_
    bad <- c(bad, sprintf("%s: reported MDE OR %.1f delivers %.0f%% power at %d discordant pairs, not 80%%; reference MDE is %.1f",
                          mc$contrast[i], rep, 100 * pw, d, ref))
  }
}
report("crosscheck/mde-attains-claimed-power", length(bad) == 0,
       if (length(bad)) paste(bad, collapse = "; ")
       else sprintf("%d MDEs attain 80%% power under the exact test", nrow(mc)))

# ── Business-day waits ────────────────────────────────────────────────────────
d <- rd("labubu_cleaned_analysis.csv")
has <- !is.na(d$call_date) & !is.na(d$first_appt_date) & !is.na(d$business_days)
if (any(has)) {
  ref <- ref_business_days(d$call_date[has], d$first_appt_date[has])
  bad <- which(abs(ref - d$business_days[has]) > 0)
  report("crosscheck/business-days", length(bad) == 0,
         if (length(bad))
           sprintf("%d of %d waits disagree with the reference calendar (first: reported %s, reference %s)",
                   length(bad), sum(has), d$business_days[has][bad[1]], ref[bad[1]])
         else sprintf("%d business-day waits match the reference calendar", sum(has)))
} else {
  report("crosscheck/business-days", FALSE, "no rows with both dates; check cannot evaluate")
}

cat(sprintf("\nREFERENCE CROSSCHECK  %d passed, %d failed\n", n_ok, fail))
quit(status = if (fail) 1L else 0L)
