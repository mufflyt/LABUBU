#!/usr/bin/env Rscript
# ── Meaningful-drift detector ─────────────────────────────────────────────────
# Decides whether a nightly refresh actually changed the study, or merely
# reran it.
#
# Several artifacts differ on every run regardless of the data: PROVENANCE.md
# and mysterycall_evaluation.md stamp a generation time and the current git
# SHA, and ggplot re-renders PNG/TIFF with different bytes each time. Treating
# those as drift would open a pull request every night forever, which trains
# reviewers to ignore nightly PRs -- the opposite of the point.
#
# Exit 0 = meaningful drift (open a PR). Exit 1 = cosmetic only (do nothing).

volatile_line <- function(x) {
  grepl("^Generated:", x) |
  grepl("^Analysis repo:", x) |
  grepl("^- mysterycall version:", x) |
  grepl("^Package repo:", x) |
  # The API writes a new timestamped export filename on every pull, so the
  # filename churns even when the MD5 and row count are identical. The MD5 is
  # the identity that matters and is compared on its own line.
  grepl("LABUBU_DATA(_LABELS)?_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\\.csv", x) |
  # per-run identifiers: the analysis commit changes on every commit, so it
  # differs on every nightly regardless of whether any result moved
  grepl("\"(labubu_commit|analysis_commit|git_sha|generated_at|created)\"", x) |
  # provenance table rows carry a per-run "Created" timestamp
  grepl("[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}", x)
}

# WHAT COUNTS AS A RESULT
#
# Three rounds of patching volatile patterns -- timestamps, commit SHAs, export
# filenames, the package banner, then the platform triple -- kept missing new
# ones, because the premise was wrong. A nightly runs on a Linux runner and
# compares against artifacts generated on a maintainer's Mac, so environment
# metadata differs BY CONSTRUCTION and no pattern list will ever be complete:
# x86_64-apple-darwin20 vs x86_64-pc-linux-gnu, different package sets in
# session info, R's print() widening a column when a number gains a digit.
#
# The question is not "which lines are volatile" but "where do results live".
# They live in two places, and both are compared:
#
#   the analytic CSVs   the numbers the study reports
#   estimands.csv       judged by estimand-diff.R, which knows interval bounds
#                       are less stable than point estimates
#
# Everything else -- narrative, figures, provenance metadata -- is regenerated
# from those inputs plus the machine that ran it. A real change shows up in a
# CSV or an estimand. If it shows up ONLY in prose, that is the machine
# talking, not the data.
result_path <- function(path) {
  grepl("^mysterycall_outputs/.*\\.csv$", path) &
    # estimands.csv and manuscript_claims.csv are both judged by
    # estimand-diff.R. The claims table is DERIVED from the estimands and
    # carries the same interval bounds, so comparing it here applies the tight
    # point-estimate tolerance to bounds that legitimately move with the
    # optimiser -- which is the noise this whole line of work is removing.
    !grepl("(estimands|manuscript_claims)\\.csv$", path) &
    # per-run review lists, not results
    !grepl("(practice_name_review|duplicate_practice_scenario)", path)
}

changed_paths <- system2("git", c("diff", "--staged", "--name-only"),
                         stdout = TRUE)
changed_paths <- changed_paths[nzchar(changed_paths)]

if (!length(changed_paths)) {
  base::message("DRIFT: none (no staged changes)")
  quit(status = 1)
}

normalise <- function(lines) {
  lines <- lines[!volatile_line(lines)]
  lines[nzchar(trimws(lines))]
}

# Two lines that differ only in the low-order digits of their numbers are the
# same result computed on a different machine. A BLAS or optimiser difference
# moved a caller-adjusted coefficient in the sixth decimal and opened a
# pull request over it; the estimands were byte-identical.
NUMERIC_RE <- "-?[0-9]+\\.?[0-9]*([eE][-+]?[0-9]+)?"
REL_TOLERANCE <- 1e-4

numerically_equivalent <- function(a, b) {
  if (identical(a, b)) return(TRUE)
  # The non-numeric skeleton must match exactly; only digits may differ.
  if (!identical(gsub(NUMERIC_RE, "#", a), gsub(NUMERIC_RE, "#", b)))
    return(FALSE)
  a_nums <- suppressWarnings(as.numeric(
    regmatches(a, gregexpr(NUMERIC_RE, a))[[1]]))
  b_nums <- suppressWarnings(as.numeric(
    regmatches(b, gregexpr(NUMERIC_RE, b))[[1]]))
  if (length(a_nums) != length(b_nums)) return(FALSE)
  if (!length(a_nums)) return(TRUE)
  both_na <- is.na(a_nums) & is.na(b_nums)
  if (any(is.na(a_nums) != is.na(b_nums))) return(FALSE)
  a_nums <- a_nums[!both_na]; b_nums <- b_nums[!both_na]
  if (!length(a_nums)) return(TRUE)
  denominator <- pmax(abs(a_nums), .Machine$double.eps)
  all(abs(a_nums - b_nums) / denominator <= REL_TOLERANCE)
}

content_equivalent <- function(previous, current) {
  if (length(previous) != length(current)) return(FALSE)
  all(mapply(numerically_equivalent, previous, current))
}

meaningful <- character(0)
for (path in changed_paths) {
  if (!result_path(path)) next
  previous <- suppressWarnings(
    system2("git", c("show", paste0("HEAD:", path)), stdout = TRUE,
            stderr = FALSE))
  current <- if (file.exists(path)) readLines(path, warn = FALSE) else character(0)
  if (!content_equivalent(normalise(previous), normalise(current)))
    meaningful <- c(meaningful, path)
}

if (!length(meaningful)) {
  base::message("DRIFT: no result changed (", length(changed_paths),
                " file(s) differ: narrative, figures and environment metadata ",
                "only; analytic CSVs identical within ",
                format(REL_TOLERANCE), " relative tolerance)")
  base::message("  no pull request needed")
  quit(status = 1)
}

base::message("DRIFT: meaningful, in ", length(meaningful), " file(s)")
for (path in meaningful) base::message("  ", path)
quit(status = 0)
