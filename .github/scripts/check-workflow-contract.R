#!/usr/bin/env Rscript
# ── Workflow contract ─────────────────────────────────────────────────────────
# Static assertions about the workflows themselves. A scientific test that no
# workflow reaches does not protect the study, and a required job that can go
# green while skipping the science is worse than no job at all.

workflow_dir <- ".github/workflows"
sha_file     <- ".github/mysterycall-sha.txt"
canonical_sha <- trimws(readLines(sha_file, warn = FALSE)[1])

violations <- character(0)
note <- function(...) violations <<- c(violations, paste0(...))

workflow_files <- list.files(workflow_dir, pattern = "\\.ya?ml$",
                             full.names = TRUE)
if (!length(workflow_files)) note("no workflows found in ", workflow_dir)

for (path in workflow_files) {
  lines <- readLines(path, warn = FALSE)
  body  <- paste(lines, collapse = "\n")
  name  <- basename(path)

  # One source of truth for the pinned analytical dependency. A SHA copied by
  # hand into three files drifts, and a drifted SHA silently changes results.
  inline_shas <- unique(regmatches(
    body, gregexpr("\\b[0-9a-f]{40}\\b", body))[[1]])
  stray <- setdiff(inline_shas, canonical_sha)
  if (length(stray))
    note(name, ": hard-codes SHA(s) not in ", sha_file, ": ",
         paste(substr(stray, 1, 12), collapse = ", "))

  if (grepl("mysterycall", body) && !grepl("MYSTERYCALL_SHA", body))
    note(name, ": installs mysterycall without referencing MYSTERYCALL_SHA")

  if (!grepl("timeout-minutes:", body))
    note(name, ": no timeout-minutes; a hung job burns the 6h default")

  if (!grepl("concurrency:", body))
    note(name, ": no concurrency group")

  if (!grepl("permissions:", body))
    note(name, ": no explicit permissions block")

  # continue-on-error must never sit on a job that carries a scientific gate.
  if (grepl("continue-on-error:\\s*true", body) &&
      grepl("scientific-gate\\.R", body))
    note(name, ": continue-on-error alongside the scientific gate")

  # A workflow that commits must run the gate BEFORE it commits, not after.
  if (grepl("git push", body) && grepl("scientific-gate\\.R", body)) {
    gate_at   <- grep("scientific-gate\\.R", lines)[1]
    commit_at <- grep("git commit", lines)[1]
    if (!is.na(gate_at) && !is.na(commit_at) && gate_at > commit_at)
      note(name, ": commits before running the scientific gate")
  }
  if (grepl("git push", body) && !grepl("scientific-gate\\.R", body))
    note(name, ": pushes to the repo without running the scientific gate")

  # A scheduled job must never rewrite main because a run produced different
  # numbers. Drift belongs in a reviewable pull request.
  if (grepl("git push\\s+origin\\s+main", body))
    note(name, ": pushes directly to main; open a review PR instead")
}

# Every file a workflow reads must actually be committed. .gitignore's privacy
# rule `LABUBU_DATA_*.csv` is unanchored, so it silently swallowed
# tests/fixtures/LABUBU_DATA_LABELS_fixture.csv; `git add -A` skipped it, the
# commit claimed to add it, and CI failed on a file that was never there.
tracked_files <- system2("git", c("ls-files"), stdout = TRUE)
for (path in workflow_files) {
  body <- paste(readLines(path, warn = FALSE), collapse = "\n")
  referenced <- unique(unlist(regmatches(
    body,
    gregexpr("(\\.github/scripts/[A-Za-z0-9_.-]+\\.R|tests/fixtures/[A-Za-z0-9_.-]+)",
             body))))
  untracked <- setdiff(referenced, tracked_files)
  if (length(untracked))
    note(basename(path), ": references file(s) not tracked by git: ",
         paste(untracked, collapse = ", "))
}

# Every gate check must be reachable by a workflow that runs the gate.
if (!any(vapply(workflow_files,
                function(f) grepl("scientific-gate\\.R",
                                  paste(readLines(f, warn = FALSE),
                                        collapse = "\n")),
                logical(1))))
  note("no workflow runs scientific-gate.R")

if (length(violations)) {
  for (v in violations)
    cat(sprintf("::error title=Workflow contract::%s\n", v))
  base::message("\nWORKFLOW CONTRACT  FAIL (", length(violations), " violation(s))")
  quit(status = 1)
}
base::message("WORKFLOW CONTRACT  PASS (", length(workflow_files),
              " workflows checked)")
