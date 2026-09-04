#!/usr/bin/env Rscript
# ── Environment preflight ─────────────────────────────────────────────────────
# Fails in seconds, BEFORE the pipeline writes anything, when the environment
# cannot support the full analysis.
#
# This exists because of a specific failure: glmmTMB went missing in CI, every
# model call is wrapped in tryCatch, so the hurdle model silently vanished from
# the report and the nightly committed the thinned version over the good one.
# report/models-present catches that after the fact; this catches it before the
# run starts, and says ENVIRONMENT rather than leaving a scientist to infer it.

required_pkgs <- c(
  mysterycall = "the entire pipeline",
  lme4        = "primary + secondary mixed-effects models",
  glmmTMB     = "two-part hurdle model (mysterycall_hurdle_wait)",
  geepack     = "GEE sensitivity analysis",
  readr       = "REDCap export parsing",
  dplyr       = "data preparation",
  rmarkdown   = "manuscript render",
  knitr       = "manuscript render"
)

missing_pkgs <- names(required_pkgs)[
  !vapply(names(required_pkgs),
          function(p) requireNamespace(p, quietly = TRUE), logical(1))
]

sha_file <- ".github/mysterycall-sha.txt"
expected_sha <- if (file.exists(sha_file))
  trimws(readLines(sha_file, warn = FALSE)[1]) else NA_character_

base::message("── LABUBU environment preflight ──")
base::message("R ", as.character(getRversion()))
for (pkg in names(required_pkgs)) {
  installed <- requireNamespace(pkg, quietly = TRUE)
  base::message(sprintf("  %-12s %-9s %s", pkg,
                        if (installed) "OK" else "MISSING",
                        if (installed)
                          as.character(utils::packageVersion(pkg)) else
                          required_pkgs[[pkg]]))
}

if (length(missing_pkgs)) {
  for (pkg in missing_pkgs)
    cat(sprintf("::error title=ENVIRONMENT FAILURE::%s is not installed; %s ",
                pkg, required_pkgs[[pkg]]),
        "would be silently dropped from the report\n", sep = "")
  base::message("\nENVIRONMENT     FAIL")
  base::message("STUDY NOT EXECUTED - no scientific assertion has run.")
  quit(status = 1)
}

# The pinned revision is a scientific input, so a mismatch is reported rather
# than tolerated. Only enforced in CI, where the install is scripted.
if (!is.na(expected_sha) && nzchar(Sys.getenv("CI"))) {
  desc_sha <- tryCatch(
    utils::packageDescription("mysterycall")$RemoteSha, error = function(e) NA)
  if (!is.null(desc_sha) && !is.na(desc_sha) &&
      !identical(substr(desc_sha, 1, 40), substr(expected_sha, 1, 40))) {
    cat(sprintf(
      "::error title=ENVIRONMENT FAILURE::mysterycall is %s but %s pins %s\n",
      substr(desc_sha, 1, 12), sha_file, substr(expected_sha, 1, 12)))
    quit(status = 1)
  }
}

base::message("\nENVIRONMENT     PASS")
