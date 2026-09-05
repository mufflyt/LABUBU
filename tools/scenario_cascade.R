#!/usr/bin/env Rscript
# Print the access cascade for each caller scenario.
#
# The per-scenario STROBE panel (fig0b) draws these numbers; this prints them,
# which is what you want when checking a figure against the data or answering
# "how many lesbian-couple calls actually reached the wait analysis".
#
#   Rscript tools/scenario_cascade.R

cleaned <- "mysterycall_outputs/labubu_cleaned_analysis.csv"
if (!file.exists(cleaned)) stop(cleaned, " not found; run the pipeline first")

call_records <- read.csv(cleaned, stringsAsFactors = FALSE)
is_true <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")

cat(sprintf("  %-16s %6s %9s %8s %7s %6s %8s\n",
            "scenario", "placed", "calldate", "reached", "offer", "wait", "no date"))
for (s in c("Straight couple", "Lesbian couple", "Single mother")) {
  arm <- call_records[!is.na(call_records$scenario) & call_records$scenario == s, ]
  cat(sprintf("  %-16s %6d %9d %8d %7d %6d %8d\n", s,
              nrow(arm), sum(!is.na(arm$call_date)), sum(is_true(arm$reached)),
              sum(!is.na(arm$appt_offered)), sum(!is.na(arm$biz_wait)),
              sum(is.na(arm$call_date))))
}
