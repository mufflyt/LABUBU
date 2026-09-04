#!/usr/bin/env Rscript
# redcap_pull.R — download a fresh LABUBU export straight from the REDCap API.
#
# Replaces the manual "log in -> Data Exports -> download two CSVs" dance. Writes
# LABUBU_DATA_LABELS_<date>_<time>.csv (labels; the file the analysis reads) and
# LABUBU_DATA_<date>_<time>.csv (raw) into the repo root, then refresh.R picks the
# newest one up exactly as it would a hand-downloaded export.
#
#     Rscript redcap_pull.R            # download only
#     Rscript refresh.R --pull         # download, then re-run the analysis
#
# Needs a project API token in ~/.Renviron (never commit it):
#
#     REDCAP_LABUBU_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#
# Token comes from REDCap: project 39546 -> Applications -> API -> "Generate
# token". The URL can be overridden with REDCAP_URL if the instance ever moves.

redcap_pull <- function(dest_dir = ".",
                        token = Sys.getenv("REDCAP_LABUBU_TOKEN"),
                        url   = Sys.getenv("REDCAP_URL",
                                           "https://redcap.ucdenver.edu/api/")) {
  if (!nzchar(token))
    stop("No REDCap token found. Add REDCAP_LABUBU_TOKEN=<token> to ~/.Renviron ",
         "and restart R (or run: readRenviron('~/.Renviron')).", call. = FALSE)

  stamp <- format(Sys.time(), "%Y-%m-%d_%H%M")

  # The two flavors REDCap's UI calls "Labels" and "Raw". The analysis keys off
  # field *labels* as column names, so rawOrLabelHeaders matters as much as
  # rawOrLabel — getting one but not the other yields unreadable columns.
  flavors <- list(
    labels = list(file = sprintf("LABUBU_DATA_LABELS_%s.csv", stamp),
                  args = list(rawOrLabel = "label", rawOrLabelHeaders = "label",
                              exportCheckboxLabel = "true")),
    raw    = list(file = sprintf("LABUBU_DATA_%s.csv", stamp),
                  args = list(rawOrLabel = "raw", rawOrLabelHeaders = "raw",
                              exportCheckboxLabel = "false"))
  )

  written <- character(0)
  for (nm in names(flavors)) {
    f <- flavors[[nm]]
    body <- c(list(token = token, content = "record", format = "csv",
                   type = "flat", returnFormat = "json"), f$args)

    resp <- httr::POST(url, body = body, encode = "form",
                       httr::timeout(300))

    if (httr::status_code(resp) != 200)
      stop(sprintf("REDCap API returned HTTP %d for the %s export: %s",
                   httr::status_code(resp), nm,
                   substr(httr::content(resp, "text", encoding = "UTF-8"), 1, 300)),
           call. = FALSE)

    txt <- httr::content(resp, "text", encoding = "UTF-8")

    # A bad token / revoked rights comes back as HTTP 200 with a JSON error body,
    # so check the payload actually looks like the CSV we asked for.
    if (grepl('^\\s*\\{\\s*"error"', txt))
      stop("REDCap API error on the ", nm, " export: ", substr(txt, 1, 300),
           call. = FALSE)
    if (!nzchar(trimws(txt)))
      stop("REDCap returned an empty ", nm, " export.", call. = FALSE)

    path <- file.path(dest_dir, f$file)
    writeLines(txt, path, useBytes = TRUE)

    # Parse the CSV rather than counting lines: `notes` and several headers
    # contain embedded newlines, which made a line count over-report (235 for
    # a 234-record export).
    n <- tryCatch(nrow(readr::read_csv(path, show_col_types = FALSE,
                                       progress = FALSE)),
                  error = function(e) max(0L, length(readLines(path, warn = FALSE)) - 1L))
    cat(sprintf("  %-7s %s  (%d data rows)\n", nm, f$file, n))
    written[nm] <- path
  }

  invisible(written)
}

# Run the pull when invoked directly; stay a plain function definition when
# refresh.R sources this file.
if (sys.nframe() == 0L) {
  cat("── Pulling LABUBU export from REDCap ──\n")
  redcap_pull(".")
  cat("\nDone. Run `Rscript refresh.R` to re-run the analysis on it.\n")
}
