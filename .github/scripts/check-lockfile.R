#!/usr/bin/env Rscript
# ── Lockfile drift ────────────────────────────────────────────────────────────
# Compares the versions this run actually loaded against config/dependencies.lock.csv
# and reports what moved. A package version change is a legitimate reason for a
# result to shift, and when one does, this is the record that says so.
#
# Reports rather than fails. A runner will not match a laptop package-for-package,
# and failing on that would make the lockfile an obstacle instead of evidence.
# Two cases DO fail, because they mean the analysis could not have run as
# declared: a package the analysis requires is absent, or mysterycall is not at
# the pinned SHA.

lockfile_path <- "config/dependencies.lock.csv"
ci_dir        <- "ci-results"
dir.create(ci_dir, showWarnings = FALSE)

if (!file.exists(lockfile_path)) {
  cat("::error title=LOCKFILE MISSING::", lockfile_path, " is absent\n", sep = "")
  quit(status = 1)
}
lock <- readr::read_csv(lockfile_path, show_col_types = FALSE, progress = FALSE)

current_version <- function(pkg)
  if (requireNamespace(pkg, quietly = TRUE))
    as.character(utils::packageVersion(pkg)) else NA_character_

comparison <- lock
comparison$installed <- vapply(lock$package, current_version, character(1))
comparison$status <- ifelse(
  is.na(comparison$installed), "absent",
  ifelse(comparison$installed == comparison$version, "match", "drifted"))
readr::write_csv(comparison, file.path(ci_dir, "lockfile-audit.csv"))

# Packages without which the protocol models silently disappear.
essential <- c("mysterycall", "lme4", "glmmTMB", "geepack", "readr", "dplyr",
               "rmarkdown", "knitr")
absent_essential <- comparison$package[comparison$status == "absent" &
                                       comparison$package %in% essential]

drifted <- comparison[comparison$status == "drifted", ]
tally <- table(factor(comparison$status, levels = c("match", "drifted", "absent")))
base::message("LOCKFILE        ",
              paste(sprintf("%s=%d", names(tally), as.integer(tally)),
                    collapse = "  "))
if (nrow(drifted)) {
  base::message("")
  print(as.data.frame(drifted[, c("package", "version", "installed")]),
        row.names = FALSE)
  for (i in seq_len(nrow(drifted)))
    cat(sprintf("::warning title=Package version drift::%s locked %s, running %s\n",
                drifted$package[i], drifted$version[i], drifted$installed[i]))
}

if (length(absent_essential)) {
  for (pkg in absent_essential)
    cat(sprintf("::error title=ENVIRONMENT FAILURE::%s is in the lockfile but not installed\n",
                pkg))
  quit(status = 1)
}

sha_file <- ".github/mysterycall-sha.txt"
if (file.exists(sha_file) && nzchar(Sys.getenv("CI"))) {
  pinned  <- trimws(readLines(sha_file, warn = FALSE)[1])
  running <- tryCatch(utils::packageDescription("mysterycall")$RemoteSha,
                      error = function(e) NA_character_)
  if (!is.null(running) && !is.na(running) &&
      !identical(substr(running, 1, 40), substr(pinned, 1, 40))) {
    cat(sprintf("::error title=ENVIRONMENT FAILURE::mysterycall running %s, pinned %s\n",
                substr(running, 1, 12), substr(pinned, 1, 12)))
    quit(status = 1)
  }
}
