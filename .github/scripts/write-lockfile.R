#!/usr/bin/env Rscript
# ── Dependency lockfile ───────────────────────────────────────────────────────
# One authoritative record of what the analysis was run with.
#
# renv is deliberately not used: it would need to own the project library on
# every machine, and this repo's CI installs a source-built Deriv and a
# GitHub-pinned mysterycall that renv restore handles awkwardly. What actually
# matters for a research repository is knowing exactly which versions produced
# a result, and being told when that set changes -- which is what this records.
#
# Regenerate deliberately: Rscript .github/scripts/write-lockfile.R

lockfile_path <- "config/dependencies.lock.csv"
dir.create("config", showWarnings = FALSE)

analysis_packages <- c(
  "mysterycall", "lme4", "glmmTMB", "geepack", "Deriv", "doBy", "pbkrtest",
  "dplyr", "readr", "tibble", "ggplot2", "ggbeeswarm", "ggridges", "patchwork",
  "scales", "forcats", "knitr", "rmarkdown", "survival", "jsonlite", "openssl",
  "yaml", "png", "Matrix", "TMB")

installed <- vapply(analysis_packages, function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE))
    as.character(utils::packageVersion(pkg)) else NA_character_
}, character(1))

# mysterycall is pinned by SHA elsewhere; record it here too so one file
# answers "what produced this result".
sha_file <- ".github/mysterycall-sha.txt"
mysterycall_sha <- if (file.exists(sha_file))
  trimws(readLines(sha_file, warn = FALSE)[1]) else NA_character_

lock <- tibble::tibble(
  package = names(installed),
  version = unname(installed),
  source  = ifelse(names(installed) == "mysterycall",
                   paste0("github:mufflyt/mysterycall@", substr(mysterycall_sha, 1, 12)),
                   ifelse(names(installed) == "Deriv",
                          "cran-archive:Deriv_4.2.0.tar.gz", "cran")))
lock <- lock[order(lock$package), ]

readr::write_csv(lock, lockfile_path)
base::message("LOCKFILE        ", sum(!is.na(lock$version)), " packages recorded in ",
              lockfile_path)
missing <- lock$package[is.na(lock$version)]
if (length(missing))
  base::message("  not installed here: ", paste(missing, collapse = ", "))
