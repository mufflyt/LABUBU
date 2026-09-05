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

covered <- character(0)

mutate_and_test <- function(label, covers, mutate) {
  covered <<- c(covered, covers)
  tmp <- file.path(tempdir(), paste0("selftest-", gsub("[^a-z]", "", tolower(label))))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  # restriction/excluded-from-inference reads the pipeline source, so the
  # scratch copy must mirror the real environment rather than the check having
  # to tolerate its absence.
  file.copy(c("PROVENANCE.md", "labubu_mysterycall_manuscript.Rmd",
              "evaluate_labubu_mysterycall.R"), tmp)
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
  covered <<- c(covered, check_id)
  tmp <- file.path(tempdir(), paste0("selftest-skip-", gsub("[^a-z]", "", tolower(label))))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  # restriction/excluded-from-inference reads the pipeline source, so the
  # scratch copy must mirror the real environment rather than the check having
  # to tolerate its absence.
  file.copy(c("PROVENANCE.md", "labubu_mysterycall_manuscript.Rmd",
              "evaluate_labubu_mysterycall.R"), tmp)
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
  mutate_and_test("detects outcome aliased to inclusion",
                  "outcome/offer-not-aliased-to-inclusion", function(dir) {
    d <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    d$contact_office <- d$analytic_inclusion          # the original defect
    d$appt_offered   <- ifelse(d$analytic_inclusion %in% c(TRUE, "TRUE"), 1L, NA_integer_)
    write.csv(d, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects unmapped exclusion reason",
                  "data/all-exclusion-reasons-mapped", function(dir) {
    d <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    i <- which(!is.na(d$exclusion_reason))[1]
    d$exclusion_reason[i] <- "Brand new reason nobody mapped"
    d$exclusion_code[i]   <- NA
    write.csv(d, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects log-scale wait mislabelled as days",
                  "report/wait-reported-as-gmr-not-days", function(dir) {
    f <- file.path(dir, OUT, "mysterycall_evaluation.md")
    t <- readLines(f, warn = FALSE)
    t <- gsub("GEOMETRIC MEAN RATIO", "mean difference", t)
    t <- gsub("GMR", "Est_business_days", t)
    writeLines(c(t, "Estimates are mean difference in business days vs. Straight couple"), f)
  }),

  mutate_and_test("detects hardcoded statistic in manuscript",
                  "manuscript/no-hardcoded-statistics", function(dir) {
    f <- file.path(dir, "labubu_mysterycall_manuscript.Rmd")
    writeLines(c(readLines(f, warn = FALSE),
                 "The odds of an offer were OR 1.08 (95% CI 0.33-3.49) for lesbian couples."), f)
  }),

  mutate_and_test("detects stale provenance MD5",
                  "provenance/md5-matches-repo-export", function(dir) {
    # Synthesize the declared export so the check has something to hash, then
    # point provenance at a hash that cannot match it.
    unlink(list.files(dir, pattern = "^LABUBU_DATA_LABELS_.*\\.csv$", full.names = TRUE))
    writeLines("Record ID,Scenario\n1,Straight couple",
               file.path(dir, declared_export(dir)))
    set_declared_md5(dir, "deadbeefdeadbeef")
  }),

  mutate_and_test("detects unresolved near-duplicate names",
                  "data/no-unresolved-near-duplicate-practices", function(dir) {
    write.csv(data.frame(key_a = "A Clinic", key_b = "A Clinc",
                         edit_distance = 1L, norm_distance = 0.05),
              file.path(dir, OUT, "practice_name_review_nearduplicates.csv"), row.names = FALSE)
  }),

  # The defect an API pull introduced: checkbox columns parsed against the
  # wrong encoding, zeroing every service and restriction variable.
  mutate_and_test("detects zeroed checkbox parse",
                  "data/checkbox-encoding-parsed", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    for (v in c("service_cycle_tracking", "service_hormonal_timing",
                "service_ovulation_induction", "service_iui", "service_ivf",
                "restrict_lesbian", "restrict_straight", "restrict_single_mother"))
      if (v %in% names(dd)) dd[[v]] <- FALSE
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  # A model quietly dropped from the report (a missing optional dependency)
  # must fail rather than be committed over the good version.
  mutate_and_test("detects model dropped from report",
                  "report/models-present", function(dir) {
    f <- file.path(dir, OUT, "mysterycall_evaluation.md")
    writeLines(c(readLines(f, warn = FALSE),
                 "hurdle model not run: there is no package called 'glmmTMB'"), f)
  }),

  # ---- Negative controls for the five checks that previously had none --------
  # "gate has a self-test" is not the same as "every gate is tested". These
  # close the gap the coverage audit below now enforces.

  mutate_and_test("detects offer outcome with no negatives",
                  "outcome/offer-has-negative-events", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    dd$appt_offered[dd$appt_offered %in% 0L] <- 1L   # acceptance 100% by construction
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects refusals dropped from denominator",
                  "outcome/reached-refusals-retained", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    ref <- dd$exclusion_reason %in% "Not accepting new patients"
    dd$in_offer_den[ref] <- FALSE                    # the original defect
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects impossible access cascade",
                  "cascade/monotonic", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    dd$in_offer_den <- TRUE                          # eligible > reached
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects caller confounding suppressed",
                  "report/caller-confounding-reported", function(dir) {
    f <- file.path(dir, OUT, "mysterycall_evaluation.md")
    writeLines(gsub("CALLER CONFOUNDING", "Caller notes",
                    readLines(f, warn = FALSE), fixed = TRUE), f)
  }),

  mutate_and_test("detects collapsed denominators",
                  "denominators/distinct-levels", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    dd$reached <- dd$analytic_inclusion              # reached collapses onto inclusion
    dd$reached[dd$exclusion_reason %in%
               c("Not accepting new patients",
                 "Greater than 5 minutes on hold")] <- FALSE
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects real staff name in artifact",
                  "privacy/callers-de-identified", function(dir) {
    dd <- read.csv(clean_of(dir), stringsAsFactors = FALSE)
    dd$caller[1] <- "Jordan Reyes"      # a name, not a stratum label
    write.csv(dd, clean_of(dir), row.names = FALSE)
  }),

  mutate_and_test("detects contact details in artifact",
                  "privacy/no-contact-details-in-artifacts", function(dir) {
    writeLines("practice,phone\nExample Clinic,303-555-0142",
               file.path(dir, OUT, "leaky_artifact.csv"))
  }),

  mutate_and_test("detects manuscript claim losing its estimand",
                  "manuscript/claims-resolve", function(dir) {
    f <- file.path(dir, OUT, "manuscript_claims.csv")
    cc <- read.csv(f, stringsAsFactors = FALSE)
    cc$estimand_id[1] <- "an_estimand_that_no_longer_exists"
    write.csv(cc, f, row.names = FALSE)
  }),

  mutate_and_test("detects restriction var entering inference",
                  "restriction/excluded-from-inference", function(dir) {
    f <- file.path(dir, OUT, "estimands.csv")
    ee <- read.csv(f, stringsAsFactors = FALSE)
    ee$estimand_id[1] <- "restrict_lesbian_or"
    write.csv(ee, f, row.names = FALSE)
  }),

  # The skip must not swallow real drift: provenance naming an export that is
  # not the one actually present is a FAILURE, not a skip.
  mutate_and_test("detects provenance naming wrong export",
                  "provenance/md5-matches-repo-export", function(dir) {
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

# ── Coverage audit ────────────────────────────────────────────────────────────
# A gate that only demonstrates its happy path is not sufficient, and neither is
# a self-test suite that happens to cover some checks. Enumerate the gate's own
# check IDs from the run it just performed, and require a negative control for
# every one that is not explicitly exempted with a reason.
EXEMPT <- c(
  # Structural precondition: absence of the export is already exercised by the
  # "skips cleanly" case, and there is no mutation that makes a *present*,
  # matching export look wrong beyond the two cases above.
)

# Gate check IDs come from the gate's SOURCE, not from an artifact of a
# previous run. Reading ci-results/scientific-gate.tsv made this audit depend
# on the gate having already executed -- which it has not, because the
# self-test deliberately runs first ("did the gate work" before "did the study
# pass"). Locally it only passed because a stale tsv was on disk, which is the
# same stale-artifact trap the gate exists to prevent.
gate_ids <- local({
  src <- readLines(file.path(root, ".github", "scripts", "scientific-gate.R"),
                   warn = FALSE)
  m <- regmatches(src, regexpr('try_check\\("[^"]+"', src))
  unique(sub('try_check\\("', "", sub('"$', "", m)))
})

# If a run of the gate happens to be present, cross-check it against the
# source: a check defined but never reached at runtime is also a coverage hole.
local({
  tsv <- file.path(root, "ci-results", "scientific-gate.tsv")
  if (!file.exists(tsv)) return(invisible(NULL))
  ran <- vapply(strsplit(readLines(tsv, warn = FALSE), "\t"), `[`,
                character(1), 1L)
  defined_not_run <- setdiff(gate_ids, ran)
  if (length(defined_not_run))
    cat(sprintf("::error title=Check never executed::%s is defined but did not run\n",
                defined_not_run))
})

cat("\n", strrep("-", 60), "\n", sep = "")
coverage_ok <- TRUE
if (!length(gate_ids)) {
  cat("COVERAGE AUDIT: could not read ci-results/scientific-gate.tsv;\n",
      "  run scientific-gate.R first so coverage can be verified.\n", sep = "")
  coverage_ok <- FALSE
} else {
  uncovered <- setdiff(setdiff(gate_ids, unique(covered)), EXEMPT)
  cat(sprintf("COVERAGE AUDIT: %d gate checks, %d with negative controls, %d exempt\n",
              length(gate_ids), length(intersect(gate_ids, unique(covered))), length(EXEMPT)))
  if (length(uncovered)) {
    coverage_ok <- FALSE
    for (u in uncovered)
      cat(sprintf("::error title=No negative control::%s has no self-test; ",
                  u), "add one or add it to EXEMPT with a reason\n", sep = "")
  }
}

cat(strrep("-", 60), "\n", sep = "")
if (all(ok) && coverage_ok) {
  cat("Gate self-test: all", length(ok), "injected defects were caught; coverage complete.\n")
  quit(status = 0)
}
if (!all(ok)) cat("Gate self-test FAILED:", sum(!ok), "injected defect(s) went undetected.\n")
if (!coverage_ok) cat("Gate self-test FAILED: incomplete negative-control coverage.\n")
quit(status = 1)
