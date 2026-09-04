#!/usr/bin/env Rscript
# ── Pipeline completion receipt ───────────────────────────────────────────────
# Exit code 0 is not proof that the study ran. A script can exit cleanly having
# skipped work, and committed outputs from a previous run look identical to
# freshly generated ones. This writes a receipt describing what THIS run
# produced, and records the denominator cascade in a reviewable form.
#
# Run immediately after evaluate_labubu_mysterycall.R, in the same session.

suppressWarnings(suppressMessages({
  library(dplyr)
}))

output_dir   <- "mysterycall_outputs"
ci_dir       <- "ci-results"
cleaned_path <- file.path(output_dir, "labubu_cleaned_analysis.csv")
dir.create(ci_dir, showWarnings = FALSE)

fail <- function(category, msg) {
  cat(sprintf("::error title=%s::%s\n", category, msg))
  base::message("\n", category, ": ", msg)
  quit(status = 1)
}

if (!file.exists(cleaned_path))
  fail("PIPELINE FAILURE",
       paste0(cleaned_path, " absent after the pipeline ran; the analysis did ",
              "not produce its primary output"))

call_records <- readr::read_csv(cleaned_path, show_col_types = FALSE,
                                progress = FALSE)

is_true <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")

# ── Denominator audit (Phase 9) ───────────────────────────────────────────────
# Derived here independently of the report, so a reviewer can see the cohort
# without reading a workflow log or trusting the narrative.
coverage_path <- file.path(output_dir, "practice_scenario_coverage.csv")
n_triads <- if (file.exists(coverage_path)) {
  sum(readr::read_csv(coverage_path, show_col_types = FALSE,
                      progress = FALSE)$n_scenarios == 3)
} else NA_integer_

denominator_audit <- tibble::tibble(
  denominator = c("all_calls", "reached", "offer_eligible", "offered",
                  "not_offered", "historical_inclusion", "wait_eligible",
                  "complete_triads"),
  n = c(
    nrow(call_records),
    sum(is_true(call_records$reached)),
    sum(is_true(call_records$in_offer_den)),
    sum(call_records$appt_offered == 1L, na.rm = TRUE),
    sum(call_records$appt_offered == 0L, na.rm = TRUE),
    sum(is_true(call_records$analytic_inclusion)),
    sum(!is.na(call_records$biz_wait)),
    n_triads
  ),
  definition = c(
    "every row in the REDCap export",
    "a live office answered (exclusion codes 0, 2, 7, 9, 10)",
    "eligible for the offer model (codes 0, 7, 9, 10)",
    "appt_offered == 1 (strict: appointment date obtained)",
    "appt_offered == 0 (includes stated refusals)",
    "legacy inclusion flag (code 0 only)",
    "business-day wait observed",
    "practices called for all three scenarios"
  )
)
readr::write_csv(denominator_audit, file.path(ci_dir, "denominator-audit.csv"))

# ── Logical nesting, asserted rather than assumed ─────────────────────────────
pull_n <- function(id) denominator_audit$n[denominator_audit$denominator == id]
nesting_violations <- character(0)
if (pull_n("reached") > pull_n("all_calls"))
  nesting_violations <- c(nesting_violations, "reached > all_calls")
if (pull_n("offer_eligible") > pull_n("reached"))
  nesting_violations <- c(nesting_violations, "offer_eligible > reached")
if (pull_n("offered") + pull_n("not_offered") > pull_n("offer_eligible"))
  nesting_violations <- c(nesting_violations,
                          "offered + not_offered > offer_eligible")
if (length(nesting_violations))
  fail("SCIENTIFIC INVARIANT FAILURE",
       paste("denominator nesting violated:",
             paste(nesting_violations, collapse = "; ")))

# ── Expected artifacts, all of which must exist and be non-empty ──────────────
expected_artifacts <- c(
  "labubu_cleaned_analysis.csv", "mysterycall_evaluation.md",
  "mysterycall_access_cascade_by_scenario.csv", "mysterycall_offer_by_scenario.csv",
  "mysterycall_service_prevalence.csv", "mysterycall_paired_acceptance_mcnemar.csv",
  "practice_scenario_coverage.csv", "caller_dominance_by_scenario.csv"
)
artifact_paths <- file.path(output_dir, expected_artifacts)
absent  <- expected_artifacts[!file.exists(artifact_paths)]
empty   <- expected_artifacts[file.exists(artifact_paths) &
                              file.size(artifact_paths) == 0]
if (length(absent))
  fail("PIPELINE FAILURE",
       paste("expected outputs not produced:", paste(absent, collapse = ", ")))
if (length(empty))
  fail("PIPELINE FAILURE",
       paste("expected outputs are empty:", paste(empty, collapse = ", ")))

source_export <- list.files(".", pattern = "^LABUBU_DATA_LABELS_.*\\.csv$")
sha_file <- ".github/mysterycall-sha.txt"

receipt <- list(
  generated_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  git_sha         = Sys.getenv("GITHUB_SHA", unset = NA_character_),
  r_version       = as.character(getRversion()),
  mysterycall_sha = if (file.exists(sha_file))
    trimws(readLines(sha_file, warn = FALSE)[1]) else NA_character_,
  mysterycall_version = as.character(utils::packageVersion("mysterycall")),
  source_export   = if (length(source_export)) source_export[1] else NA_character_,
  source_sha256   = if (length(source_export))
    paste(as.character(openssl::sha256(file(source_export[1], "rb"))),
          collapse = "") else NA_character_,
  denominators    = stats::setNames(as.list(denominator_audit$n),
                                    denominator_audit$denominator),
  artifacts       = stats::setNames(
    as.list(unname(tools::md5sum(artifact_paths))), expected_artifacts)
)
jsonlite::write_json(receipt, file.path(ci_dir, "pipeline-complete.json"),
                     auto_unbox = TRUE, pretty = TRUE, null = "null")

base::message("PIPELINE        PASS")
base::message("  receipt: ", file.path(ci_dir, "pipeline-complete.json"))
print(as.data.frame(denominator_audit[, c("denominator", "n")]), row.names = FALSE)
