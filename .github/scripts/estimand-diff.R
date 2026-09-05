#!/usr/bin/env Rscript
# ── Estimand drift report ─────────────────────────────────────────────────────
# Compares this run's estimands against the committed baseline and CLASSIFIES
# each change, because "the answer changed" and "the analysis became invalid"
# are different statements and must not be conflated.
#
#   unchanged       bit-identical
#   negligible      within tolerance -- floating point, BLAS, optimiser
#   substantial     moved enough that a human should look
#   new / removed   the estimand set itself changed; a delta would be
#                   meaningless, so it is reported as non-comparable
#
# Exit 0 = nothing substantial. Exit 2 = substantial drift.
# It never fails on negligible drift; that is the whole point.

output_dir    <- "mysterycall_outputs"
ci_dir        <- "ci-results"
estimand_path <- file.path(output_dir, "estimands.csv")
dir.create(ci_dir, showWarnings = FALSE)

# Relative tolerance for "same number, different machine". Cross-platform BLAS
# and optimiser differences land around 1e-7; 1e-4 leaves headroom without
# hiding a real shift (an OR moving 0.04 -> 0.31 is ~7e0).
REL_TOLERANCE <- 1e-4
ABS_TOLERANCE <- 1e-8
# Interval bounds come from profile/Wald computations whose optimiser path
# differs across platforms far more than the point estimate does: an observed
# nightly moved a wait-GMR lower bound 0.468526 -> 0.475872 (1.6%) while the
# estimate itself was bit-identical. Bounds therefore get their own, looser
# tolerance; a real shift in an interval is accompanied by a shift in the
# estimate, which is still held to 1e-4.
BOUND_REL_TOLERANCE <- 5e-2

if (!file.exists(estimand_path)) {
  cat("::error title=ESTIMAND REPORT MISSING::",
      estimand_path, " was not generated\n", sep = "")
  quit(status = 1)
}
current <- readr::read_csv(estimand_path, show_col_types = FALSE, progress = FALSE)

baseline_raw <- suppressWarnings(system2(
  "git", c("show", paste0("HEAD:", estimand_path)), stdout = TRUE, stderr = FALSE))
if (!length(baseline_raw)) {
  base::message("No committed baseline yet; recording this run as the baseline.")
  readr::write_csv(current, file.path(ci_dir, "estimand-diff.csv"))
  quit(status = 0)
}
baseline <- readr::read_csv(I(paste(baseline_raw, collapse = "\n")),
                            show_col_types = FALSE, progress = FALSE)

classify_with <- function(base_value, new_value, rel_tolerance) {
  if (is.na(base_value) && is.na(new_value)) return("unchanged")
  if (is.na(base_value) || is.na(new_value))  return("non-comparable")
  if (identical(base_value, new_value))       return("unchanged")
  absolute <- abs(new_value - base_value)
  relative <- if (abs(base_value) > 0) absolute / abs(base_value) else Inf
  if (absolute <= ABS_TOLERANCE || relative <= rel_tolerance) "negligible"
  else "substantial"
}

classify <- function(base_value, new_value) {
  if (is.na(base_value) && is.na(new_value)) return("unchanged")
  if (is.na(base_value) || is.na(new_value))  return("non-comparable")
  if (identical(base_value, new_value))       return("unchanged")
  absolute <- abs(new_value - base_value)
  relative <- if (abs(base_value) > 0) absolute / abs(base_value) else Inf
  if (absolute <= ABS_TOLERANCE || relative <= REL_TOLERANCE) "negligible"
  else "substantial"
}

all_ids <- union(baseline$estimand_id, current$estimand_id)
comparison <- do.call(rbind, lapply(all_ids, function(id) {
  base_row <- baseline[baseline$estimand_id == id, ]
  new_row  <- current[current$estimand_id == id, ]
  if (!nrow(base_row))
    return(data.frame(estimand_id = id, estimand = new_row$estimand[1],
                      base = NA_real_, current = new_row$estimate[1],
                      absolute_change = NA_real_, relative_change = NA_real_,
                      status = "new", stringsAsFactors = FALSE))
  if (!nrow(new_row))
    return(data.frame(estimand_id = id, estimand = base_row$estimand[1],
                      base = base_row$estimate[1], current = NA_real_,
                      absolute_change = NA_real_, relative_change = NA_real_,
                      status = "removed", stringsAsFactors = FALSE))
  base_value <- base_row$estimate[1]; new_value <- new_row$estimate[1]
  status <- classify(base_value, new_value)
  # A bound that moved while the estimate did not is optimiser noise.
  if (status == "unchanged") {
    bound_status <- c(
      classify_with(base_row$lower[1],  new_row$lower[1],  BOUND_REL_TOLERANCE),
      classify_with(base_row$upper[1],  new_row$upper[1],  BOUND_REL_TOLERANCE))
    if (any(bound_status == "substantial")) status <- "substantial"
    else if (any(bound_status == "negligible")) status <- "negligible"
  }
  data.frame(
    estimand_id = id, estimand = new_row$estimand[1],
    base = base_value, current = new_value,
    absolute_change = if (is.na(base_value) || is.na(new_value)) NA_real_
                      else round(new_value - base_value, 8),
    relative_change = if (is.na(base_value) || is.na(new_value) || base_value == 0)
                      NA_real_ else round((new_value - base_value) / abs(base_value), 6),
    status = status, stringsAsFactors = FALSE)
}))

readr::write_csv(comparison, file.path(ci_dir, "estimand-diff.csv"))

tally <- table(factor(comparison$status,
                      levels = c("unchanged", "negligible", "substantial",
                                 "new", "removed", "non-comparable")))
base::message("ESTIMAND DRIFT  ",
              paste(sprintf("%s=%d", names(tally), as.integer(tally)),
                    collapse = "  "))

notable <- comparison[comparison$status %in%
                        c("substantial", "new", "removed", "non-comparable"), ]
if (nrow(notable)) {
  base::message("")
  print(notable[, c("estimand_id", "base", "current",
                    "relative_change", "status")], row.names = FALSE)
}

substantial <- comparison[comparison$status == "substantial", ]
if (nrow(substantial)) {
  for (i in seq_len(nrow(substantial)))
    cat(sprintf("::warning title=Estimand moved::%s: %s -> %s (%.1f%%)\n",
                substantial$estimand_id[i], substantial$base[i],
                substantial$current[i], 100 * substantial$relative_change[i]))
  quit(status = 2)
}
quit(status = 0)
