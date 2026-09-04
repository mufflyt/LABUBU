#!/usr/bin/env Rscript
# provenance.R — emit a provenance record for every analysis artifact.
#
# Writes PROVENANCE.md (human) and mysterycall_outputs/provenance.json (machine)
# describing, for each figure and table: which script produced it, from which
# input, on what date, at what git commit, under which package versions, and —
# critically — over which denominator.
#
# Every value here is COMPUTED FROM THE FILES AT RUN TIME. Nothing is typed in by
# hand, so the record cannot drift away from the artifacts the way prose numbers
# do. If you find yourself about to hardcode a count into a document, put it here
# instead and cite it.
#
#     Rscript provenance.R      # regenerate (refresh.R does this automatically)

suppressMessages({
  library(dplyr)
})

repo    <- normalizePath(".")
out_dir <- file.path(repo, "mysterycall_outputs")
fig_dir <- file.path(out_dir, "figures")

# ── Helpers ───────────────────────────────────────────────────────────────────
sha16 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  substr(tools::md5sum(path)[[1]], 1, 16)
}
mtime <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  format(file.mtime(path), "%Y-%m-%d %H:%M:%S %Z")
}
n_rows <- function(path) {
  if (!file.exists(path)) return(NA_integer_)
  nrow(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
}
git_val <- function(args, dir = repo) {
  v <- suppressWarnings(system2("git", c("-C", dir, args), stdout = TRUE, stderr = FALSE))
  if (!length(v)) NA_character_ else v[1]
}
pkg_v <- function(p) tryCatch(as.character(packageVersion(p)),
                              error = function(e) NA_character_)

# ── 1. Environment ────────────────────────────────────────────────────────────
env <- list(
  generated_at    = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  r_version       = R.version.string,
  platform        = R.version$platform,
  labubu_commit   = git_val("rev-parse --short HEAD"),
  labubu_branch   = git_val("rev-parse --abbrev-ref HEAD"),
  labubu_dirty    = nzchar(paste(git_val("status --porcelain"), collapse = "")),
  packages        = sapply(c("mysterycall", "lme4", "geepack", "ggplot2", "dplyr",
                             "readr", "ggridges", "patchwork", "ggbeeswarm"), pkg_v,
                           simplify = FALSE)
)

# The mysterycall package does the modeling, so its commit is part of provenance.
mc_repo <- path.expand("~/mysterycall")
if (dir.exists(file.path(mc_repo, ".git"))) {
  env$mysterycall_commit <- git_val("rev-parse --short HEAD", mc_repo)
  env$mysterycall_branch <- git_val("rev-parse --abbrev-ref HEAD", mc_repo)
}

# ── 2. Source export ──────────────────────────────────────────────────────────
labels <- list.files(repo, "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE)
labels <- if (length(labels)) labels[which.max(file.mtime(labels))] else NA_character_
raw    <- sub("LABUBU_DATA_LABELS_", "LABUBU_DATA_", labels)

source_export <- list(
  labels_file = basename(labels), labels_md5 = sha16(labels),
  labels_rows = n_rows(labels),   labels_mtime = mtime(labels),
  raw_file    = if (file.exists(raw)) basename(raw) else NA_character_,
  raw_md5     = sha16(raw)
)

# ── 3. Denominator cascade ────────────────────────────────────────────────────
# The single most dangerous number in this study: each artifact is built on a
# DIFFERENT subset, and none of the figure denominators equals the record count.
# Quoting "n = 201" under a wait-time figure would be wrong by ~4x.
clean_path <- file.path(out_dir, "labubu_cleaned_analysis.csv")
den <- list()
if (file.exists(clean_path)) {
  d <- read.csv(clean_path, stringsAsFactors = FALSE)
  w <- d |> filter(analytic_inclusion == TRUE, !is.na(business_days), business_days >= 0)
  m <- w |> group_by(practice_id) |> filter(n_distinct(scenario) >= 2) |> ungroup()
  tfp <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")
  offer <- d[tfp(d$in_offer_den) & !is.na(d$appt_offered), ]
  den <- list(
    all_records = list(
      n = nrow(d), practices = n_distinct(d$practice_id),
      rule = "every row in the REDCap export"),
    reached = list(
      n = sum(tfp(d$reached)), practices = n_distinct(d$practice_id[tfp(d$reached)]),
      rule = "a live office answered (exclusion codes 0, 2, 7, 9, 10)"),
    offer_analytic = list(
      n = nrow(offer), practices = n_distinct(offer$practice_id),
      rule = "offer-eligible (codes 0, 7, 9, 10) with a derived appt_offered value"),
    analytic_inclusion = list(
      n = sum(d$analytic_inclusion == TRUE, na.rm = TRUE),
      practices = n_distinct(d$practice_id[d$analytic_inclusion == TRUE]),
      rule = "Reason for exclusions == 'Included where physician was able to be contacted' (code 0 only)"),
    wait_subset = list(
      n = nrow(w), practices = n_distinct(w$practice_id),
      rule = "analytic_inclusion & non-missing, non-negative business_days"),
    within_practice_pairs = list(
      n = nrow(m), practices = n_distinct(m$practice_id),
      rule = "wait_subset restricted to practices with >= 2 distinct scenarios")
  )
}

# ── 4. Artifact lineage ───────────────────────────────────────────────────────
# script  = what wrote it;  input = what it read;  denom = which cascade level.
fig_meta <- list(
  fig1_raincloud_wait_by_scenario.png = "wait_subset",
  fig2_ridgeplot_wait_by_scenario.png = "wait_subset",
  fig3_ecdf_wait_by_scenario.png      = "wait_subset",
  fig4_within_practice_pairs.png      = "within_practice_pairs",
  fig_panel_wait_times.png            = "wait_subset + within_practice_pairs (composite of figs 1-4)"
)

figures <- lapply(names(fig_meta), function(f) {
  p <- file.path(fig_dir, f)
  list(artifact = file.path("mysterycall_outputs/figures", f),
       script   = "figures_wait_time.R",
       input    = "mysterycall_outputs/labubu_cleaned_analysis.csv",
       denominator = fig_meta[[f]],
       md5      = sha16(p), created = mtime(p))
})

tables <- lapply(sort(list.files(out_dir, "\\.csv$")), function(f) {
  p <- file.path(out_dir, f)
  # The call-list CSVs are targeting aids emitted alongside the analysis.
  list(artifact = file.path("mysterycall_outputs", f),
       script   = "evaluate_labubu_mysterycall.R",
       input    = source_export$labels_file,
       rows     = n_rows(p), md5 = sha16(p), created = mtime(p))
})

reports <- list(
  list(artifact = "mysterycall_outputs/mysterycall_evaluation.md",
       script = "evaluate_labubu_mysterycall.R", input = source_export$labels_file,
       md5 = sha16(file.path(out_dir, "mysterycall_evaluation.md")),
       created = mtime(file.path(out_dir, "mysterycall_evaluation.md"))),
  list(artifact = "data_review.md", script = "hand-written, numbers verified against export",
       input = source_export$labels_file, md5 = sha16(file.path(repo, "data_review.md")),
       created = mtime(file.path(repo, "data_review.md")))
)

# ── 5. Write JSON ─────────────────────────────────────────────────────────────
manifest <- list(environment = env, source_export = source_export,
                 denominators = den, figures = figures,
                 tables = tables, reports = reports)

if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(manifest, file.path(out_dir, "provenance.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")
}

# ── 6. Write PROVENANCE.md ────────────────────────────────────────────────────
z <- function(x) if (is.null(x) || is.na(x)) "—" else as.character(x)
L <- c(
  "# PROVENANCE — LABUBU mystery-caller analysis",
  "",
  "<!-- GENERATED BY provenance.R — DO NOT EDIT BY HAND. -->",
  "<!-- Every number below is computed from the artifacts at run time. -->",
  "",
  sprintf("Generated: **%s**", z(env$generated_at)),
  sprintf("Analysis repo: `%s` @ `%s`%s", z(env$labubu_branch), z(env$labubu_commit),
          if (isTRUE(env$labubu_dirty)) " *(uncommitted changes present)*" else ""),
  if (!is.null(env$mysterycall_commit))
    sprintf("Package repo: `mysterycall` `%s` @ `%s` (installed v%s)",
            z(env$mysterycall_branch), z(env$mysterycall_commit), z(env$packages$mysterycall)),
  "",
  "## 1. Source data",
  "",
  "| Field | Value |",
  "|---|---|",
  sprintf("| REDCap export (labels) | `%s` |", z(source_export$labels_file)),
  sprintf("| MD5 (first 16) | `%s` |", z(source_export$labels_md5)),
  sprintf("| Rows | %s |", z(source_export$labels_rows)),
  sprintf("| Downloaded | %s |", z(source_export$labels_mtime)),
  sprintf("| REDCap project | pid 39546, redcap.ucdenver.edu |"),
  "",
  "Raw exports are gitignored (they carry practice contact information), so the",
  "MD5 above is how you verify which export a result came from.",
  "",
  "## 2. Denominator cascade — READ THIS BEFORE QUOTING ANY *n*",
  "",
  "Each artifact is built on a different subset. **No figure uses the record count.**",
  "",
  "| Level | n calls | practices | Rule |",
  "|---|---|---|---|"
)
for (k in names(den)) {
  x <- den[[k]]
  L <- c(L, sprintf("| `%s` | %s | %s | %s |", k, z(x$n), z(x$practices), x$rule))
}
L <- c(L, "",
  "`reached` and `offer_analytic` are the outcome denominators; `analytic_inclusion`",
  "is the narrower historical flag (code 0 only) that the figures still use.",
  "The gap between levels is not attrition to be explained away: `analytic_inclusion`",
  "drops non-contacts, and the wait subset additionally requires an observed",
  "appointment date, which most included calls never produced.",
  "",
  "## 3. Figures",
  "",
  "All five figures come from **one script, one input, one run.**",
  "",
  "| Figure | Script | Input | Denominator | MD5 | Created |",
  "|---|---|---|---|---|---|")
for (f in figures)
  L <- c(L, sprintf("| `%s` | `%s` | `%s` | `%s` | `%s` | %s |",
                    basename(f$artifact), f$script, basename(f$input),
                    f$denominator, z(f$md5), z(f$created)))
L <- c(L, "",
  "## 4. Tables and derived CSVs",
  "",
  "| Artifact | Script | Rows | MD5 | Created |",
  "|---|---|---|---|---|")
for (t in tables)
  L <- c(L, sprintf("| `%s` | `%s` | %s | `%s` | %s |",
                    basename(t$artifact), t$script, z(t$rows), z(t$md5), z(t$created)))
L <- c(L, "",
  "## 5. Reports",
  "",
  "| Artifact | Origin | MD5 | Created |",
  "|---|---|---|---|")
for (r in reports)
  L <- c(L, sprintf("| `%s` | %s | `%s` | %s |",
                    r$artifact, r$script, z(r$md5), z(r$created)))
L <- c(L, "",
  "## 6. Environment",
  "",
  sprintf("- %s on `%s`", z(env$r_version), z(env$platform)),
  paste0("- Packages: ",
         paste(sprintf("`%s` %s", names(env$packages), unlist(lapply(env$packages, z))),
               collapse = ", ")),
  "",
  "## 7. How to reproduce",
  "",
  "```sh",
  "Rscript refresh.R          # export -> analysis -> figures -> this file",
  "```",
  "",
  "`refresh.R` regenerates every artifact listed above and rewrites this file.",
  "A changed MD5 with an unchanged export means the code changed; a changed export",
  "MD5 means the data changed. Both should be explainable before you publish a number.",
  ""
)
writeLines(L[!vapply(L, is.null, logical(1))], file.path(repo, "PROVENANCE.md"))

# ── 7. Sidecar in figures/ ────────────────────────────────────────────────────
# Figures get copied into slide decks and manuscripts on their own; a sidecar in
# the same directory means their origin travels with them.
if (dir.exists(fig_dir)) {
  S <- c(
    "# Figure provenance",
    "",
    "<!-- GENERATED BY provenance.R — DO NOT EDIT BY HAND. -->",
    "",
    sprintf("All figures in this directory were produced by `figures_wait_time.R`"),
    sprintf("from `mysterycall_outputs/labubu_cleaned_analysis.csv`, which was derived by"),
    sprintf("`evaluate_labubu_mysterycall.R` from REDCap export `%s`", z(source_export$labels_file)),
    sprintf("(MD5 `%s`, %s rows, downloaded %s).",
            z(source_export$labels_md5), z(source_export$labels_rows), z(source_export$labels_mtime)),
    "",
    sprintf("Generated %s at commit `%s` using mysterycall v%s and %s.",
            z(env$generated_at), z(env$labubu_commit), z(env$packages$mysterycall), z(env$r_version)),
    "",
    "## Denominators — do not quote the record count under these figures",
    "",
    "| Figure | n calls | practices | Subset |",
    "|---|---|---|---|"
  )
  for (f in figures) {
    lvl <- den[[f$denominator]]
    S <- c(S, sprintf("| `%s` | %s | %s | %s |", basename(f$artifact),
                      if (is.null(lvl)) "see below" else z(lvl$n),
                      if (is.null(lvl)) "see below" else z(lvl$practices),
                      f$denominator))
  }
  S <- c(S, "",
    sprintf("`fig_panel_wait_times.png` is a patchwork composite of figures 1-4 and"),
    "therefore carries both denominators; label its sub-panels individually.",
    "",
    "Full record: [`../../PROVENANCE.md`](../../PROVENANCE.md)", "")
  writeLines(S, file.path(fig_dir, "README.md"))
}

cat("Wrote PROVENANCE.md, mysterycall_outputs/provenance.json,",
    "and mysterycall_outputs/figures/README.md\n")
