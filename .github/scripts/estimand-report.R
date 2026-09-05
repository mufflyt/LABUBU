#!/usr/bin/env Rscript
# ── Estimand report ───────────────────────────────────────────────────────────
# Writes the study's headline estimands to one small, diffable table, each with
# an explicit ID. Two purposes:
#
#   * a reviewer can see every reported quantity in one place, and
#   * drift can be judged on the ESTIMANDS rather than on report text, so a
#     BLAS difference in the sixth decimal of an unrelated table does not read
#     as "the study changed".
#
# Values are computed from the generated outputs, not re-derived by hand, so
# this cannot disagree with the analysis it summarises.

suppressWarnings(suppressMessages({
  library(dplyr); library(mysterycall)
}))

output_dir    <- "mysterycall_outputs"
estimand_path <- file.path(output_dir, "estimands.csv")
read_out <- function(f) readr::read_csv(file.path(output_dir, f),
                                        show_col_types = FALSE, progress = FALSE)

call_records <- read_out("labubu_cleaned_analysis.csv")
is_true <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")
call_records$scenario <- factor(
  call_records$scenario,
  levels = c("Straight couple", "Lesbian couple", "Single mother"))

row_for <- function(id, estimand, estimate, lower = NA_real_,
                    upper = NA_real_, n = NA_integer_)
  tibble::tibble(estimand_id = id, estimand = estimand,
                 estimate = estimate, lower = lower, upper = upper, n = n)

coverage <- read_out("practice_scenario_coverage.csv")
cascade  <- read_out("mysterycall_access_cascade_by_scenario.csv")
services <- read_out("mysterycall_service_prevalence.csv")

estimand_rows <- list(
  row_for("n_all_calls",       "calls placed",            nrow(call_records)),
  row_for("n_reached",         "reached a live office",   sum(is_true(call_records$reached))),
  row_for("n_offer_eligible",  "offer-eligible calls",    sum(is_true(call_records$in_offer_den))),
  row_for("n_offered",         "appointments offered",    sum(call_records$appt_offered == 1L, na.rm = TRUE)),
  row_for("n_wait_eligible",   "wait observed",           sum(!is.na(call_records$biz_wait))),
  row_for("n_complete_triads", "practices with 3 scenarios", sum(coverage$n_scenarios == 3))
)

for (i in seq_len(nrow(cascade))) {
  scen <- gsub("[^a-z]", "_", tolower(cascade$scenario[i]))
  estimand_rows <- c(estimand_rows, list(
    row_for(paste0("offer_strict_", scen),
            paste("strict offer prevalence -", cascade$scenario[i]),
            cascade$pct_offered_strict[i], n = cascade$offer_eligible[i]),
    row_for(paste0("offer_broad_", scen),
            paste("broad offer prevalence -", cascade$scenario[i]),
            cascade$pct_offered_broad[i], n = cascade$offer_eligible[i])))
}

for (i in seq_len(nrow(services)))
  estimand_rows <- c(estimand_rows, list(
    row_for(paste0("service_", services$option[i]),
            paste("service offered -", services$option[i]),
            100 * services$prevalence[i],
            100 * services$ci_lower[i], 100 * services$ci_upper[i],
            services$total[i])))

# Model-based estimands, refitted so they cannot drift from the report.
offer_analytic <- call_records |>
  dplyr::filter(is_true(in_offer_den), !is.na(appt_offered),
                !is.na(scenario), !is.na(practice_id))
triad_ids <- coverage$practice_id[coverage$n_scenarios == 3]

add_model_terms <- function(rows, fit, prefix, label) {
  if (is.null(fit)) return(rows)
  or_table <- as.data.frame(fit$or_table)
  for (i in seq_len(nrow(or_table))) {
    term <- or_table$term[i]
    if (term == "(Intercept)") next
    key <- gsub("[^a-z]", "_", tolower(sub("^scenario", "", term)))
    rows <- c(rows, list(row_for(paste0(prefix, key), paste(label, term),
                                 or_table$or[i], or_table$ci_lower[i],
                                 or_table$ci_upper[i], fit$n)))
  }
  rows
}

fit_triad <- tryCatch(mysterycall_logistic_model(
  dplyr::filter(offer_analytic, practice_id %in% triad_ids),
  outcome = "appt_offered", predictors = "scenario",
  random_intercept = "practice_id"), error = function(e) NULL)
estimand_rows <- add_model_terms(estimand_rows, fit_triad, "or_triad_",
                                 "triad offer OR")

fit_broad <- tryCatch(mysterycall_logistic_model(
  dplyr::filter(call_records, is_true(in_offer_den), !is.na(appt_offered_broad),
                !is.na(scenario), !is.na(practice_id)),
  outcome = "appt_offered_broad", predictors = "scenario",
  random_intercept = "practice_id"), error = function(e) NULL)
estimand_rows <- add_model_terms(estimand_rows, fit_broad, "or_broad_",
                                 "broad-definition offer OR")

fit_wait <- tryCatch(mysterycall_lmm(
  dplyr::filter(call_records, !is.na(business_days), !is.na(practice_id),
                !is.na(scenario)),
  outcome = "business_days", predictors = "scenario",
  random_intercept = "practice_id"), error = function(e) NULL)
if (!is.null(fit_wait) && !is.null(fit_wait$gmr_table)) {
  gmr <- as.data.frame(fit_wait$gmr_table)
  for (i in seq_len(nrow(gmr))) {
    if (gmr$term[i] == "(Intercept)") next
    key <- gsub("[^a-z]", "_", tolower(sub("^scenario", "", gmr$term[i])))
    estimand_rows <- c(estimand_rows, list(
      row_for(paste0("gmr_wait_", key), paste("wait GMR", gmr$term[i]),
              gmr$GMR[i], gmr$GMR_lo[i], gmr$GMR_hi[i], fit_wait$n)))
  }
}

cramers <- tryCatch(
  mysterycall_test_categorical(dplyr::filter(call_records, !is.na(scenario)),
                               row_var = "caller", col_var = "scenario")$cramers_v,
  error = function(e) NA_real_)
estimand_rows <- c(estimand_rows, list(
  row_for("caller_scenario_cramers_v", "caller x scenario association", cramers)))

estimand_table <- dplyr::bind_rows(estimand_rows) |>
  dplyr::mutate(dplyr::across(c(estimate, lower, upper), ~ round(.x, 6)))
readr::write_csv(estimand_table, estimand_path)

base::message("ESTIMANDS       ", nrow(estimand_table), " written to ", estimand_path)
