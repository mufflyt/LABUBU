#!/usr/bin/env Rscript
# ── LABUBU scientific gate ────────────────────────────────────────────────────
# Structural invariants the analysis must satisfy. These are NOT unit tests of
# the package; they are assertions about THIS study's outputs that would have
# caught the defects found in the 2026-09 review.
#
# Design rules, borrowed from mufflyt/isochrones-ci and mufflyt/mysterymaps:
#   * "did it finish" and "did it pass" are separate signals — the sentinel file
#     is written last, and a run without it is a failure regardless of exit code
#   * every check reports PASS/FAIL individually; the gate fails on ANY failure
#     rather than stopping at the first, so one run shows every problem
#   * a check that cannot be evaluated is a FAILURE, never a silent skip

OUT <- "mysterycall_outputs"
res <- list()
check <- function(id, ok, detail = "") {
  ok <- isTRUE(ok)
  res[[length(res) + 1]] <<- list(id = id, ok = ok, detail = detail)
  cat(sprintf("%-46s %s%s\n", id, if (ok) "PASS" else "FAIL",
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}
try_check <- function(id, expr) {
  r <- tryCatch(expr, error = function(e) structure(FALSE, detail = conditionMessage(e)))
  check(id, r, if (!is.null(attr(r, "detail"))) attr(r, "detail") else "")
}

clean_path <- file.path(OUT, "labubu_cleaned_analysis.csv")
if (!file.exists(clean_path)) {
  cat("FATAL: ", clean_path, " not found; the pipeline did not produce output.\n", sep = "")
  quit(status = 1)
}
d  <- read.csv(clean_path, stringsAsFactors = FALSE)
tf <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")

# ── 1. The outcome-collapse regression ────────────────────────────────────────
# `contact_office <- analytic_inclusion` made "appointment offered" the same
# variable as the inclusion filter. Acceptance was then 100% inside the analytic
# sample by construction. This must never come back.
try_check("outcome/offer-not-aliased-to-inclusion", {
  stopifnot("appt_offered" %in% names(d))
  !identical(tf(d$contact_office), tf(d$analytic_inclusion))
})

try_check("outcome/offer-has-negative-events", {
  n0 <- sum(d$appt_offered == 0L, na.rm = TRUE)
  structure(n0 > 0, detail = paste0(n0, " offered=0 events"))
})

try_check("outcome/reached-refusals-retained", {
  # "Not accepting new patients" is a reached refusal and must be IN the offer
  # denominator, not excluded.
  ref <- d$exclusion_reason %in% "Not accepting new patients"
  structure(!any(ref) || all(tf(d$in_offer_den[ref])),
            detail = paste0(sum(ref), " refusal rows"))
})

# ── 2. Cascade monotonicity ───────────────────────────────────────────────────
try_check("cascade/monotonic", {
  n_call <- nrow(d); n_rch <- sum(tf(d$reached)); n_den <- sum(tf(d$in_offer_den))
  n_off  <- sum(d$appt_offered == 1L, na.rm = TRUE)
  structure(n_off <= n_den && n_den <= n_rch && n_rch <= n_call,
            detail = sprintf("%d calls >= %d reached >= %d eligible >= %d offered",
                             n_call, n_rch, n_den, n_off))
})

# ── 3. Exclusion-reason coverage ──────────────────────────────────────────────
# A new free-text reason that the code map does not know becomes NA, silently
# drops out of `reached`, and shrinks every denominator without any error.
try_check("data/all-exclusion-reasons-mapped", {
  unmapped <- unique(d$exclusion_reason[is.na(d$exclusion_code) &
                                        !is.na(d$exclusion_reason) &
                                        d$exclusion_reason != ""])
  structure(length(unmapped) == 0,
            detail = if (length(unmapped)) paste(unmapped, collapse = " | ") else "none")
})

# ── 4. Practice-name normalization ────────────────────────────────────────────
# A new spelling variant silently becomes a singleton and deflates the triad
# count. The old CI only printed a warning; unresolved pairs now fail.
try_check("data/no-unresolved-near-duplicate-practices", {
  f <- file.path(OUT, "practice_name_review_nearduplicates.csv")
  if (!file.exists(f)) return(structure(FALSE, detail = "review file missing"))
  n <- nrow(read.csv(f, stringsAsFactors = FALSE))
  structure(n == 0, detail = paste0(n, " near-duplicate pair(s); add a rule to normalize_practice()"))
})

# ── 5. Wait-time scale reporting ──────────────────────────────────────────────
# mysterycall_lmm(auto_log = TRUE) returns LOG-scale coefficients. Labelling
# them "business days" reported an intercept of 2.9 log-units as 2.9 days.
try_check("report/wait-reported-as-gmr-not-days", {
  f <- file.path(OUT, "mysterycall_evaluation.md")
  if (!file.exists(f)) return(structure(FALSE, detail = "evaluation.md missing"))
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  logged <- grepl("GEOMETRIC MEAN RATIO|GMR", txt)
  bad    <- grepl("mean difference in business days vs", txt)
  structure(logged && !bad,
            detail = if (bad) "still labels log-scale estimates as day differences" else "GMR reported")
})

# ── 6. Caller confounding must be surfaced ────────────────────────────────────
try_check("report/caller-confounding-reported", {
  f <- file.path(OUT, "caller_dominance_by_scenario.csv")
  if (!file.exists(f)) return(structure(FALSE, detail = "caller_dominance CSV missing"))
  cd <- read.csv(f, stringsAsFactors = FALSE)
  txt <- paste(readLines(file.path(OUT, "mysterycall_evaluation.md"), warn = FALSE), collapse = "\n")
  structure(nrow(cd) > 0 && grepl("CALLER CONFOUNDING", txt),
            detail = sprintf("max single-caller share %.1f%%", max(cd$top_caller_pct)))
})

# ── 7. No hardcoded statistics in the manuscript prose ────────────────────────
# Every number in the Rmd must come from an inline R expression. Literal
# statistics drift silently away from the data, which is how the manuscript
# came to report ORs and medians from a superseded export.
try_check("manuscript/no-hardcoded-statistics", {
  f <- "labubu_mysterycall_manuscript.Rmd"
  if (!file.exists(f)) return(structure(FALSE, detail = "Rmd missing"))
  lines <- readLines(f, warn = FALSE)
  body  <- lines[!grepl("^\\s*(#|/\\*|\\.|[a-z_]+ *(<-|=))", lines)]
  body  <- gsub("`r [^`]*`", "", body)          # strip inline R
  hits  <- grep("\\bOR [0-9]|[0-9]+\\.[0-9]% |95% CI [0-9]", body, value = TRUE)
  hits  <- hits[!grepl("^\\s*(- |[0-9]+\\. )?\\*\\*", hits)]
  structure(length(hits) == 0,
            detail = if (length(hits)) paste0(length(hits), " literal stat(s): ",
                                              substr(hits[1], 1, 70)) else "none")
})

# ── 8. Provenance matches the export actually present ─────────────────────────
try_check("provenance/md5-matches-repo-export", {
  if (!file.exists("PROVENANCE.md")) return(structure(FALSE, detail = "PROVENANCE.md missing"))
  pv  <- readLines("PROVENANCE.md", warn = FALSE)
  row <- grep("REDCap export \\(labels\\)", pv, value = TRUE)
  md5 <- grep("MD5 \\(first 16\\)", pv, value = TRUE)
  if (!length(row) || !length(md5)) return(structure(FALSE, detail = "provenance rows missing"))
  named <- sub(".*`([^`]+)`.*", "\\1", row[1])
  want  <- sub(".*`([^`]+)`.*", "\\1", md5[1])
  if (!file.exists(named)) return(structure(FALSE, detail = paste("export not in repo:", named)))
  got <- substr(tools::md5sum(named)[[1]], 1, 16)
  structure(identical(got, want), detail = paste0(named, ": ", got, " vs ", want))
})

# ── 9. Denominators are not silently equal ────────────────────────────────────
try_check("denominators/distinct-levels", {
  n_rch <- sum(tf(d$reached)); n_inc <- sum(tf(d$analytic_inclusion))
  structure(n_rch >= n_inc, detail = sprintf("reached=%d, analytic_inclusion=%d", n_rch, n_inc))
})

# ── Gate ──────────────────────────────────────────────────────────────────────
fails <- Filter(function(x) !x$ok, res)
cat("\n", strrep("-", 72), "\n", sep = "")
cat(sprintf("LABUBU scientific gate: %d checks, %d failed\n", length(res), length(fails)))

dir.create("ci-results", showWarnings = FALSE)
writeLines(vapply(res, function(x) sprintf("%s\t%s\t%s", x$id,
                  if (x$ok) "pass" else "fail", x$detail), character(1)),
           "ci-results/scientific-gate.tsv")

if (length(fails)) {
  for (f in fails)
    cat(sprintf("::error title=%s::%s\n", f$id, if (nzchar(f$detail)) f$detail else "failed"))
  # Sentinel is still written: the run FINISHED, it just did not PASS.
  writeLines("complete", "ci-results/gate.sentinel")
  quit(status = 1)
}
writeLines("complete", "ci-results/gate.sentinel")
cat("All checks passed.\n")
