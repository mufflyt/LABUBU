#!/usr/bin/env Rscript
# ── CI contract coverage ──────────────────────────────────────────────────────
# Verifies that config/ci_contract.yml and the implementation agree in BOTH
# directions:
#
#   declared but not implemented -> a check that exists only on paper
#   implemented but not declared -> a check that has escaped review
#
# A scientific test that exists but is never executed does not protect the
# study; a check nobody declared has not been agreed to. Both are failures.

contract_path <- "config/ci_contract.yml"
if (!file.exists(contract_path)) {
  cat("::error title=CI CONTRACT MISSING::", contract_path, " is absent\n", sep = "")
  quit(status = 1)
}
contract <- yaml::read_yaml(contract_path)

declared <- unlist(lapply(contract$layers, function(layer)
  vapply(layer, function(entry) entry$id, character(1))), use.names = FALSE)
advisory <- vapply(contract$advisory %||% list(),
                   function(entry) entry$id, character(1))
`%||%` <- function(a, b) if (is.null(a)) b else a

# Checks the gate actually implements, read from its source.
gate_source <- readLines(".github/scripts/scientific-gate.R", warn = FALSE)
implemented <- unique(sub('try_check\\("', "",
  sub('"$', "", regmatches(gate_source,
                           regexpr('try_check\\("[^"]+"', gate_source)))))

# Scripts named by the contract must exist and be referenced by a workflow.
scripts_declared <- unique(unlist(lapply(contract$layers, function(layer)
  vapply(layer, function(entry) entry$script %||% NA_character_, character(1)))))
scripts_declared <- scripts_declared[!is.na(scripts_declared)]
scripts_declared <- c(scripts_declared, contract$defaults$script)

workflow_text <- paste(unlist(lapply(
  list.files(".github/workflows", pattern = "\\.ya?ml$", full.names = TRUE),
  readLines, warn = FALSE)), collapse = "\n")

problems <- character(0)

gate_declared <- intersect(declared, implemented)
declared_missing <- setdiff(
  setdiff(declared, implemented),
  # entries that name their own script are not gate checks
  unlist(lapply(contract$layers, function(layer)
    vapply(layer, function(entry)
      if (!is.null(entry$script)) entry$id else NA_character_, character(1)))))
declared_missing <- declared_missing[!is.na(declared_missing)]
if (length(declared_missing))
  problems <- c(problems, paste("declared but not implemented in the gate:",
                                paste(declared_missing, collapse = ", ")))

undeclared <- setdiff(implemented, c(declared, advisory))
if (length(undeclared))
  problems <- c(problems, paste("implemented but not declared in the contract:",
                                paste(undeclared, collapse = ", ")))

for (script in unique(scripts_declared)) {
  if (!file.exists(script))
    problems <- c(problems, paste("declared script does not exist:", script))
  else if (!grepl(basename(script), workflow_text, fixed = TRUE))
    problems <- c(problems, paste("declared script is never run by a workflow:",
                                  script))
}

if (length(problems)) {
  for (problem in problems)
    cat(sprintf("::error title=CI contract::%s\n", problem))
  base::message("\nCI CONTRACT     FAIL (", length(problems), " problem(s))")
  quit(status = 1)
}

base::message("CI CONTRACT     PASS (", length(declared), " declared, ",
              length(gate_declared), " gate checks matched, ",
              length(advisory), " advisory)")
