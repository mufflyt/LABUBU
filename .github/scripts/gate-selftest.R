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

# The name PROVENANCE.md declares. These cases must not depend on a real export
# being present -- CI checks out a repo where exports are gitignored -- so they
# synthesize whatever file they need.
declared_export <- function(dir) {
  pv  <- readLines(file.path(dir, "PROVENANCE.md"), warn = FALSE)
  row <- grep("REDCap export \\(labels\\)", pv, value = TRUE)
  sub(".*`([^`]+)`.*", "\\1", row[1])
}
set_declared_md5 <- function(dir, md5) {
  f <- file.path(dir, "PROVENANCE.md")
  writeLines(sub("(MD5 \\(first 16\\)[^`]*)`[0-9a-f]{16}`", paste0("\\1`", md5, "`"),
                 readLines(f, warn = FALSE)), f)
}

# Same harness, but asserts the gate PASSES while recording a SKIP. A skip that
# silently turns into a pass, or into a failure, is equally wrong.
expect_skip <- function(label, check_id, mutate) {
  tmp <- file.path(tempdir(), paste0("selftest-skip-", gsub("[^a-z]", "", tolower(label))))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  file.copy(c("PROVENANCE.md", "labubu_mysterycall_manuscript.Rmd"), tmp)
  file.copy(OUT, tmp, recursive = TRUE)
  exports <- list.files(root, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE)
  if (length(exports)) file.copy(exports, tmp)
  mutate(tmp)
  failed <- run_gate(tmp)
  tsv <- file.path(tmp, "ci-results", "scientific-gate.tsv")
  skipped <- FALSE
  if (file.exists(tsv)) {
    rows <- strsplit(readLines(tsv, warn = FALSE), "\t")
    skipped <- any(vapply(rows, function(r) length(r) >= 2 && r[1] == check_id &&
                                            r[2] == "skip", logical(1)))
  }
  good <- skipped && !failed
  cat(sprintf("%-42s %s\n", label,
              if (good) "PASS (skipped, gate still green)"
              else if (failed) "FAIL (skip became a failure)"
              else "FAIL (precondition absent but not recorded as skip)"))
  good
}

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
    # Synthesize the declared export so the check has something to hash, then
    # point provenance at a hash that cannot match it.
    unlink(list.files(dir, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE))
    writeLines("Record ID,Scenario\n1,Straight couple",
               file.path(dir, declared_export(dir)))
    set_declared_md5(dir, "deadbeefdeadbeef")
  }),

  mutate_and_test("detects unresolved near-duplicate names", function(dir) {
    write.csv(data.frame(key_a = "A Clinic", key_b = "A Clinc",
                         edit_distance = 1L, norm_distance = 0.05),
              file.path(dir, OUT, "practice_name_review_nearduplicates.csv"), row.names = FALSE)
  }),

  # The defect an API pull introduced: checkbox columns parsed against the
  # wrong encoding, zeroing every service and restriction variable.
  mutate_and_test("detects zeroed checkbox parse", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    for (v in c("service_cycle_tracking", "service_hormonal_timing",
                "service_ovulation_induction", "service_iui", "service_ivf",
                "restrict_lesbian", "restrict_straight", "restrict_single_mother"))
      if (v %in% names(dd)) dd[[v]] <- FALSE
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  # A model quietly dropped from the report (a missing optional dependency)
  # must fail rather than be committed over the good version.
  mutate_and_test("detects model dropped from report", function(dir) {
    f <- file.path(dir, OUT, "mysterycall_evaluation.md")
    writeLines(c(readLines(f, warn = FALSE),
                 "hurdle model not run: there is no package called 'glmmTMB'"), f)
  }),

  # The skip must not swallow real drift: provenance naming an export that is
  # not the one actually present is a FAILURE, not a skip.
  mutate_and_test("detects provenance naming wrong export", function(dir) {
    # An export is present, but not the one provenance declares. This is the
    # case the SKIP must never swallow.
    unlink(list.files(dir, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE))
    writeLines("Record ID,Scenario\n1,Straight couple",
               file.path(dir, "LABUBU_DATA_LABELS_9999-01-01_0000.csv"))
  }),

  # And the skip must actually fire when there is genuinely nothing to hash.
  expect_skip("skips cleanly when no export present",
              "provenance/md5-matches-repo-export", function(dir) {
    unlink(list.files(dir, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE))
  })
)

cat("\n", strrep("-", 60), "\n", sep = "")
if (all(ok)) { cat("Gate self-test: all", length(ok), "injected defects were caught.\n"); quit(status = 0) }
cat("Gate self-test FAILED:", sum(!ok), "injected defect(s) went undetected.\n")
quit(status = 1)
