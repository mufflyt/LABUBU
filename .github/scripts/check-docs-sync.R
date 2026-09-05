#!/usr/bin/env Rscript
# ── Documentation sync ────────────────────────────────────────────────────────
# docs/CI.md is the file a collaborator reads to decide whether a green check
# means anything. It had drifted to describing 13 invariants when there were
# 16, and omitted eight scripts entirely -- so it was quietly answering that
# question wrong.
#
# Documentation that silently falls behind the thing it documents is worse than
# no documentation, because it is trusted. This asserts that every gate check
# and every CI script is named in docs/CI.md.

docs_path <- "docs/CI.md"
if (!file.exists(docs_path)) {
  cat("::error title=DOCS MISSING::", docs_path, " is absent\n", sep = "")
  quit(status = 1)
}
docs_text <- paste(readLines(docs_path, warn = FALSE), collapse = "\n")

gate_source <- readLines(".github/scripts/scientific-gate.R", warn = FALSE)
gate_checks <- unique(sub('try_check\\("', "",
  sub('"$', "", regmatches(gate_source,
                           regexpr('try_check\\("[^"]+"', gate_source)))))

ci_scripts <- basename(list.files(".github/scripts", pattern = "\\.R$"))

undocumented_checks  <- gate_checks[!vapply(gate_checks,
  function(id) grepl(id, docs_text, fixed = TRUE), logical(1))]
undocumented_scripts <- ci_scripts[!vapply(ci_scripts,
  function(f) grepl(f, docs_text, fixed = TRUE), logical(1))]

problems <- character(0)
if (length(undocumented_checks))
  problems <- c(problems, paste("gate checks absent from docs/CI.md:",
                                paste(undocumented_checks, collapse = ", ")))
if (length(undocumented_scripts))
  problems <- c(problems, paste("CI scripts absent from docs/CI.md:",
                                paste(undocumented_scripts, collapse = ", ")))

# A stated count that has fallen behind is the specific way this file went
# wrong before.
stated_counts <- as.integer(unlist(regmatches(
  docs_text, gregexpr("(?<=\\b)[0-9]+(?= (?:scientific )?invariants)",
                      docs_text, perl = TRUE))))
if (length(stated_counts) && !all(stated_counts == length(gate_checks)))
  problems <- c(problems, sprintf(
    "docs/CI.md states %s invariants; the gate implements %d",
    paste(unique(stated_counts), collapse = "/"), length(gate_checks)))

if (length(problems)) {
  for (problem in problems)
    cat(sprintf("::error title=Docs out of sync::%s\n", problem))
  base::message("\nDOCS SYNC       FAIL (", length(problems), " problem(s))")
  quit(status = 1)
}
base::message("DOCS SYNC       PASS (", length(gate_checks), " checks, ",
              length(ci_scripts), " scripts documented)")
