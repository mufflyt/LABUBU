#!/usr/bin/env Rscript
# ── Row-level data contract ───────────────────────────────────────────────────
# Structural assertions about the cleaned call-level dataset, reported WITH the
# offending record ids. "1 assertion failed" is not actionable; "records 43, 57,
# 90 have a wait but no appointment date" is.
#
# These are contract violations -- states the data should never be able to reach
# -- not scientific findings. A violation means the pipeline produced something
# incoherent, so every check fails closed: a column that cannot be evaluated is
# a failure, never a skip.

suppressWarnings(suppressMessages(library(dplyr)))

output_dir   <- "mysterycall_outputs"
ci_dir       <- "ci-results"
cleaned_path <- file.path(output_dir, "labubu_cleaned_analysis.csv")
dir.create(ci_dir, showWarnings = FALSE)

if (!file.exists(cleaned_path)) {
  cat("::error title=DATA CONTRACT FAILURE::", cleaned_path, " is absent\n", sep = "")
  quit(status = 1)
}
call_records <- readr::read_csv(cleaned_path, show_col_types = FALSE,
                                progress = FALSE)

violations <- list()
record_check <- function(id, description, offending_ids, detail = "") {
  offending_ids <- offending_ids[!is.na(offending_ids)]
  passed <- length(offending_ids) == 0
  violations[[length(violations) + 1]] <<- tibble::tibble(
    check = id, status = if (passed) "pass" else "fail",
    n_offending = length(offending_ids),
    record_ids = paste(utils::head(offending_ids, 20), collapse = " "),
    detail = detail)
  cat(sprintf("%-42s %s%s\n", id, if (passed) "PASS" else "FAIL",
              if (passed) (if (nzchar(detail)) paste0("  -- ", detail) else "")
              else sprintf("  -- %d record(s): %s", length(offending_ids),
                           paste(utils::head(offending_ids, 8), collapse = ", "))))
}

is_true  <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")
is_bool  <- function(x) is.logical(x) | x %in% c("TRUE", "FALSE", NA, "")
ids      <- call_records$record_id

# ── Schema ────────────────────────────────────────────────────────────────────
required_columns <- c("record_id", "scenario", "practice", "practice_id",
                      "caller", "exclusion_reason", "exclusion_code",
                      "reached", "in_offer_den", "appt_offered",
                      "appt_offered_broad", "analytic_inclusion",
                      "biz_wait", "business_days", "call_date",
                      "first_appt_date")
missing_columns <- setdiff(required_columns, names(call_records))
if (length(missing_columns)) {
  cat(sprintf("::error title=DATA CONTRACT FAILURE::required columns absent: %s\n",
              paste(missing_columns, collapse = ", ")))
  quit(status = 1)
}

# ── Identity and grain ────────────────────────────────────────────────────────
record_check("grain/record-id-unique", "one row per call",
             ids[duplicated(ids)],
             sprintf("%d rows, %d distinct ids", nrow(call_records),
                     dplyr::n_distinct(ids)))
record_check("grain/record-id-present", "record id never missing",
             which(is.na(ids)))

# ── Categorical domains ───────────────────────────────────────────────────────
allowed_scenarios <- c("Straight couple", "Lesbian couple", "Single mother")
record_check("domain/scenario-values", "scenario in the protocol set",
             ids[!is.na(call_records$scenario) &
                 !call_records$scenario %in% allowed_scenarios])

allowed_codes <- c(0L, 1L, 2L, 3L, 5L, 6L, 7L, 8L, 9L, 10L)
record_check("domain/exclusion-code-known", "exclusion code in the crosswalk",
             ids[!is.na(call_records$exclusion_code) &
                 !call_records$exclusion_code %in% allowed_codes])

record_check("domain/caller-de-identified", "caller is a stratum label",
             ids[!grepl("^(Caller [A-Z]|Unrecorded)$", call_records$caller)])

for (flag in c("reached", "in_offer_den", "analytic_inclusion")) {
  record_check(paste0("domain/", flag, "-boolean"), "boolean-valued",
               ids[!is_bool(call_records[[flag]])])
}

# ── Dates ─────────────────────────────────────────────────────────────────────
call_date <- suppressWarnings(as.Date(call_records$call_date))
appt_date <- suppressWarnings(as.Date(call_records$first_appt_date))
record_check("dates/call-date-parses", "call date parses where present",
             ids[!is.na(call_records$call_date) &
                 nzchar(as.character(call_records$call_date)) & is.na(call_date)])
record_check("dates/no-implausible-dates", "dates within the study window",
             ids[(!is.na(call_date) & (call_date < as.Date("2024-01-01") |
                                       call_date > Sys.Date() + 1)) |
                 (!is.na(appt_date) & (appt_date < as.Date("2024-01-01") |
                                       appt_date > Sys.Date() + 3650))])

# ── Outcome coherence ─────────────────────────────────────────────────────────
# The defects this study actually had, expressed as states the data must not
# reach.
record_check("coherence/offer-eligible-implies-reached",
             "offer-eligible calls were reached",
             ids[is_true(call_records$in_offer_den) & !is_true(call_records$reached)])

record_check("coherence/offer-only-where-eligible",
             "appt_offered populated only for eligible calls",
             ids[!is.na(call_records$appt_offered) &
                 !is_true(call_records$in_offer_den)])

record_check("coherence/offer-values-binary", "appt_offered is 0/1/NA",
             ids[!is.na(call_records$appt_offered) &
                 !call_records$appt_offered %in% c(0L, 1L)])

record_check("coherence/broad-implies-strict",
             "every strict offer is also a broad offer",
             ids[!is.na(call_records$appt_offered) &
                 call_records$appt_offered == 1L &
                 !is.na(call_records$appt_offered_broad) &
                 call_records$appt_offered_broad != 1L])

record_check("coherence/wait-only-when-obtained",
             "a wait exists only where an appointment was obtained",
             ids[!is.na(call_records$biz_wait) &
                 (is.na(call_records$appt_offered) |
                  call_records$appt_offered != 1L)])

record_check("coherence/no-negative-wait", "wait is never negative",
             ids[!is.na(call_records$biz_wait) & call_records$biz_wait < 0])

record_check("coherence/inclusion-implies-reached",
             "the legacy inclusion flag implies reached",
             ids[is_true(call_records$analytic_inclusion) &
                 !is_true(call_records$reached)])

# ── Practice structure ────────────────────────────────────────────────────────
practice_scenarios <- call_records |>
  dplyr::filter(!is.na(practice_id), !is.na(scenario)) |>
  dplyr::count(practice_id, scenario, name = "n_calls")
# Duplicate practice-scenario cells are REAL and need a methods decision, not a
# guess, so this reports rather than blocks. Two shapes exist: a retry after a
# failed contact (unambiguous -- the successful call is the datum) and two
# successful contacts (ambiguous -- make_wide() currently takes whichever row
# comes first, silently dropping the other). See docs/OPEN-DECISIONS.md.
duplicate_cells <- dplyr::filter(practice_scenarios, n_calls > 1)
duplicate_records <- call_records |>
  dplyr::semi_join(duplicate_cells, by = c("practice_id", "scenario")) |>
  dplyr::arrange(practice_id, scenario, record_id) |>
  dplyr::mutate(both_included = NA) |>
  dplyr::select(record_id, practice_key, scenario, call_date,
                exclusion_reason, analytic_inclusion)
readr::write_csv(duplicate_records,
                 file.path(output_dir, "duplicate_practice_scenario_calls.csv"))

ambiguous <- duplicate_records |>
  dplyr::filter(is_true(analytic_inclusion)) |>
  dplyr::count(practice_key, scenario, name = "n_included") |>
  dplyr::filter(n_included > 1)

violations[[length(violations) + 1]] <- tibble::tibble(
  check = "practice/one-call-per-scenario", status = "review",
  n_offending = nrow(duplicate_cells),
  record_ids = paste(duplicate_records$record_id, collapse = " "),
  detail = sprintf("%d cells with >1 call; %d with >1 ANALYSED call",
                   nrow(duplicate_cells), nrow(ambiguous)))
cat(sprintf("%-42s %s  -- %d cell(s), %d with >1 analysed call\n",
            "practice/one-call-per-scenario", "REVIEW",
            nrow(duplicate_cells), nrow(ambiguous)))
if (nrow(duplicate_cells))
  cat(sprintf(paste0("::warning title=Duplicate practice-scenario calls::",
                     "%d cell(s) hold more than one call, %d of them more than ",
                     "one ANALYSED call. make_wide() keeps whichever row comes ",
                     "first. See mysterycall_outputs/duplicate_practice_scenario_calls.csv ",
                     "and docs/OPEN-DECISIONS.md\n"),
              nrow(duplicate_cells), nrow(ambiguous)))

contract_table <- dplyr::bind_rows(violations)
readr::write_tsv(contract_table, file.path(ci_dir, "data-contract.tsv"))

failed   <- dplyr::filter(contract_table, status == "fail")
reviewed <- dplyr::filter(contract_table, status == "review")
cat("\n", strrep("-", 72), "\n", sep = "")
cat(sprintf("LABUBU data contract: %d checks, %d failed, %d for review\n",
            nrow(contract_table), nrow(failed), nrow(reviewed)))
if (nrow(failed)) {
  for (i in seq_len(nrow(failed)))
    cat(sprintf("::error title=DATA CONTRACT FAILURE::%s -- %d record(s): %s\n",
                failed$check[i], failed$n_offending[i], failed$record_ids[i]))
  quit(status = 1)
}
