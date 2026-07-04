#!/usr/bin/env Rscript
# refresh.R — one-command LABUBU analysis refresh.
#
# Finds the newest REDCap LABELS export (in ~/Downloads or this repo), brings it
# into the repo, archives older exports to Old_redcap/, re-runs the analysis and
# the wait-time figures, then prints a before/after delta so you can see what
# changed. Run from the repo root:
#
#     Rscript refresh.R                 # auto-detect newest export
#     Rscript refresh.R /path/to.csv    # use a specific LABELS export
#
# Raw exports stay gitignored; only regenerated outputs are tracked.

repo      <- normalizePath(".")
downloads <- path.expand("~/Downloads")
out_dir   <- file.path(repo, "mysterycall_outputs")
archive   <- file.path(repo, "Old_redcap")
dir.create(archive, showWarnings = FALSE)
args <- commandArgs(trailingOnly = TRUE)

newest <- function(dir, pattern) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (!length(f)) return(NA_character_)
  f[which.max(file.mtime(f))]
}

# ── 1. Locate the export to use ───────────────────────────────────────────────
labels <- if (length(args) >= 1 && file.exists(args[1])) {
  normalizePath(args[1])
} else {
  cand <- c(newest(downloads, "^LABUBU_DATA_LABELS_.*\\.csv$"),
            newest(repo,      "^LABUBU_DATA_LABELS_.*\\.csv$"))
  cand <- cand[!is.na(cand)]
  if (!length(cand)) stop("No LABUBU_DATA_LABELS_*.csv found in ~/Downloads or the repo.")
  normalizePath(cand[which.max(file.mtime(cand))])
}
cat("── LABUBU refresh ──\nUsing export:", basename(labels), "\n\n")

# ── 2. Snapshot 'before' from existing outputs ────────────────────────────────
tf   <- function(x) x %in% c(TRUE, "TRUE", "True")
snap <- function(cov_path, pair_path) {
  if (!file.exists(cov_path)) return(NULL)
  cov  <- read.csv(cov_path, stringsAsFactors = FALSE)
  pair <- if (file.exists(pair_path)) read.csv(pair_path, stringsAsFactors = FALSE) else NULL
  list(practices  = nrow(cov),
       triads     = sum(cov$n_scenarios == 3),
       missing_sm = sum(!tf(cov$has_sm)),
       discordant = if (!is.null(pair)) paste(pair$discordant, collapse = "/") else "—")
}
before <- snap(file.path(out_dir, "practice_scenario_coverage.csv"),
               file.path(out_dir, "mysterycall_paired_acceptance_mcnemar.csv"))

# ── 3. Bring the chosen export into the repo; archive the rest ─────────────────
keep      <- basename(labels)
keep_twin <- sub("^LABUBU_DATA_LABELS_", "LABUBU_DATA_", keep)
if (dirname(labels) != repo) {
  file.copy(labels, file.path(repo, keep), overwrite = TRUE)
  twin_src <- file.path(dirname(labels), keep_twin)
  if (file.exists(twin_src)) file.copy(twin_src, file.path(repo, keep_twin), overwrite = TRUE)
}
for (f in list.files(repo, "^LABUBU_DATA_.*\\.csv$", full.names = TRUE)) {
  if (!basename(f) %in% c(keep, keep_twin)) {
    file.rename(f, file.path(archive, basename(f)))
    cat("Archived", basename(f), "-> Old_redcap/\n")
  }
}

# ── 4. Re-run analysis + figures ──────────────────────────────────────────────
input_file <- keep                       # honored by the guard in evaluate_*.R
cat("\nRunning evaluate_labubu_mysterycall.R ...\n")
invisible(capture.output(source(file.path(repo, "evaluate_labubu_mysterycall.R"))))
cat("Running figures_wait_time.R ...\n")
tryCatch(invisible(capture.output(source(file.path(repo, "figures_wait_time.R")))),
         error = function(e) cat("  (figures skipped:", conditionMessage(e), ")\n"))

# ── 5. Before/after delta ─────────────────────────────────────────────────────
after <- snap(file.path("mysterycall_outputs", "practice_scenario_coverage.csv"),
              file.path("mysterycall_outputs", "mysterycall_paired_acceptance_mcnemar.csv"))
row <- function(lbl, b, a) cat(sprintf("  %-34s %8s -> %-8s\n", lbl, b, a))
cat("\n================ WHAT CHANGED ================\n")
if (is.null(before)) cat("  (no prior outputs to compare — first run)\n") else {
  row("Practices",                    before$practices,  after$practices)
  row("Complete triads",              before$triads,     after$triads)
  row("Practices missing SM call",    before$missing_sm, after$missing_sm)
  row("Discordant pairs (S/L/SL)",    before$discordant, after$discordant)
}
nd_path <- file.path("mysterycall_outputs", "practice_name_review_nearduplicates.csv")
if (file.exists(nd_path)) {
  nd <- read.csv(nd_path, stringsAsFactors = FALSE)
  if (nrow(nd) > 0)
    cat(sprintf("\n  !! %d near-duplicate practice-name pair(s) — review %s\n", nrow(nd), nd_path))
}
cat("\nDone. Full report: mysterycall_outputs/mysterycall_evaluation.md\n")
