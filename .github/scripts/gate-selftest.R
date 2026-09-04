#!/usr/bin/env Rscript
# ── Gate self-test ────────────────────────────────────────────────────────────
# A gate that cannot fail is decoration. This injects each defect the gate is
# supposed to catch into a scratch copy of the outputs and asserts the gate
# fails on it. Borrowed from mufflyt/mysterymaps' ci-selftest job.

OUT <- "mysterycall_outputs"
gate <- normalizePath(".github/scripts/scientific-gate.R")
root <- normalizePath(".")
stopifnot(file.exists(file.path(OUT, "labubu_cleaned_analysis.csv")))

run_gate <- function(dir) {
  old <- setwd(dir); on.exit(setwd(old))
  status <- system2("Rscript", gate, stdout = FALSE, stderr = FALSE)
  status != 0L
}

mutate_and_test <- function(label, mutate) {
  tmp <- file.path(tempdir(), paste0("selftest-", gsub("[^a-z]", "", tolower(label))))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  file.copy(c("PROVENANCE.md", "labubu_mysterycall_manuscript.Rmd"), tmp)
  file.copy(OUT, tmp, recursive = TRUE)
  exports <- list.files(root, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE)
  if (length(exports)) file.copy(exports, tmp)
  mutate(tmp)
  failed <- run_gate(tmp)
  cat(sprintf("%-42s %s\n", label, if (failed) "PASS (gate caught it)" else "FAIL (gate missed it)"))
  failed
}

clean_of <- function(dir) file.path(dir, OUT, "labubu_cleaned_analysis.csv")

ok <- c(
  mutate_and_test("detects outcome aliased to inclusion", function(dir) {
    d <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    d$contact_office <- d$analytic_inclusion          # the original defect
    d$appt_offered   <- ifelse(d$analytic_inclusion %in% c(TRUE, "TRUE"), 1L, NA_integer_)
    write.csv(d, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects unmapped exclusion reason", function(dir) {
    d <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    i <- which(!is.na(d$exclusion_reason))[1]
    d$exclusion_reason[i] <- "Brand new reason nobody mapped"
    d$exclusion_code[i]   <- NA
    write.csv(d, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects log-scale wait mislabelled as days", function(dir) {
    f <- file.path(dir, OUT, "mysterycall_evaluation.md")
    t <- readLines(f, warn = FALSE)
    t <- gsub("GEOMETRIC MEAN RATIO", "mean difference", t)
    t <- gsub("GMR", "Est_business_days", t)
    writeLines(c(t, "Estimates are mean difference in business days vs. Straight couple"), f)
  }),

  mutate_and_test("detects hardcoded statistic in manuscript", function(dir) {
    f <- file.path(dir, "labubu_mysterycall_manuscript.Rmd")
    writeLines(c(readLines(f, warn = FALSE),
                 "The odds of an offer were OR 1.08 (95% CI 0.33-3.49) for lesbian couples."), f)
  }),

  mutate_and_test("detects stale provenance MD5", function(dir) {
    f <- file.path(dir, "PROVENANCE.md")
    writeLines(sub("`[0-9a-f]{16}`", "`deadbeefdeadbeef`", readLines(f, warn = FALSE)), f)
  }),

  mutate_and_test("detects unresolved near-duplicate names", function(dir) {
    write.csv(data.frame(key_a = "A Clinic", key_b = "A Clinc",
                         edit_distance = 1L, norm_distance = 0.05),
              file.path(dir, OUT, "practice_name_review_nearduplicates.csv"), row.names = FALSE)
  })
)

cat("\n", strrep("-", 60), "\n", sep = "")
if (all(ok)) { cat("Gate self-test: all", length(ok), "injected defects were caught.\n"); quit(status = 0) }
cat("Gate self-test FAILED:", sum(!ok), "injected defect(s) went undetected.\n")
quit(status = 1)
