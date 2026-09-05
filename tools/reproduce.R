#!/usr/bin/env Rscript
# reproduce.R — rebuild every committed artifact from the export PROVENANCE names.
#
# `refresh.R` pulls the NEWEST export and is what you want when new data lands.
# This is the other question: does the current code, run against the export the
# committed results claim to come from, reproduce those results exactly?
#
# That distinction matters because a green check on a working tree proves less
# than people assume. docs/APPENDIX-lessons.md records three separate occasions
# where work that passed on one machine was wrong in the repository. The
# discipline is: clone clean, run this, and read the drift line.
#
#     Rscript tools/reproduce.R
#
# Exits non-zero if any estimand moved. A run that reproduces prints
# "unchanged=N substantial=0" and nothing else of interest, which is the point.

root <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), ".."),
                      mustWork = FALSE)
if (!dir.exists(file.path(root, "mysterycall_outputs"))) root <- getwd()
setwd(root)

`%||%` <- function(a, b) if (is.null(a)) b else a

prov <- file.path("mysterycall_outputs", "provenance.json")
if (!file.exists(prov))
  stop("mysterycall_outputs/provenance.json absent; nothing declares which export to use.",
       call. = FALSE)

declared <- local({
  txt <- paste(readLines(prov, warn = FALSE), collapse = " ")
  m <- regmatches(txt, regexpr('"labels_file"\\s*:\\s*"[^"]+"', txt))
  if (!length(m)) stop("provenance.json names no labels_file", call. = FALSE)
  sub('.*"labels_file"\\s*:\\s*"([^"]+)".*', "\\1", m)
})

if (!file.exists(declared)) {
  cat("The declared export is not in the working tree:\n  ", declared, "\n\n",
      "Raw exports are gitignored because they carry contact details. Either\n",
      "restore it, or run `Rscript redcap_pull.R` with REDCAP_LABUBU_TOKEN set\n",
      "and confirm the pull reports it unchanged.\n", sep = "")
  quit(status = 2L)
}

cat("Reproducing from the declared export:", declared, "\n\n")
input_file <- declared            # the same override refresh.R performs
source("evaluate_labubu_mysterycall.R", echo = FALSE)

cat("\n-- estimand drift against the committed baseline --\n")
st <- system2("Rscript", ".github/scripts/estimand-diff.R")
quit(status = if (identical(st, 0L)) 0L else 1L)
