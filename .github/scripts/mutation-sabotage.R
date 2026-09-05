#!/usr/bin/env Rscript
# mutation-sabotage.R
#
# Prove the validation suite can actually go red, by breaking the ANALYSIS CODE
# rather than its outputs.
#
# Borrowed from mufflyt/isochrones-ci ("test-mutation-sabotage.R"). Two ideas
# are taken directly. First, what makes a mutant worth having:
#
#   "The mutants are plausible mistakes, not nonsense. 'Return 42' proves
#    nothing; '`<` where the specification says `<=`' is the edit that passes
#    review, moves a headline number by a fraction of a point, and never
#    crashes."
#
# Second, that a surviving mutant is a reported hole rather than a tolerated
# one: every mutant must name the check expected to kill it, and a mutant that
# nothing catches fails this script.
#
# This is distinct from gate-selftest.R, which injects defects into committed
# ARTIFACTS. That answers "would we notice a corrupted output?". This answers
# "would we notice a wrong analysis?" -- the failure mode where every artifact
# is internally consistent and quietly wrong.
#
# Each mutant runs the pipeline from scratch, so this is slow by construction
# and belongs in the nightly rather than on every push.

suppressWarnings(suppressPackageStartupMessages({ library(readr) }))

EXPORT <- rev(sort(Sys.glob("LABUBU_DATA_LABELS_*.csv")))[1]
if (is.na(EXPORT)) stop("no export present; sabotage run cannot evaluate")

PIPELINE <- "evaluate_labubu_mysterycall.R"

# ── The mutant registry ───────────────────────────────────────────────────────
# `killer` names the check that SHOULD catch each mutant. It is documentation
# and an accountability record: adding a mutant forces someone to decide which
# check is responsible for it.
MUTANTS <- list(
  list(id = "mde-alpha-loosened",
       why = "MDE computed at alpha = .50 instead of .05, inflating apparent power",
       killer = "crosscheck/mde-attains-claimed-power",
       file = PIPELINE,
       fix = function(t) sub("mcnemar_mde_or <- function(n_d, power = 0.80, alpha = 0.05",
                             "mcnemar_mde_or <- function(n_d, power = 0.80, alpha = 0.50",
                             t, fixed = TRUE)),

  list(id = "mde-normal-approximation",
       why = "the pre-2026-09 rejection region: qbinom rather than the exact test",
       killer = "crosscheck/mde-attains-claimed-power",
       file = PIPELINE,
       fix = function(t) sub("  rej  <- k[p_h0 <= alpha]",
                             "  rej  <- k[k <= qbinom(alpha/2, n_d, 0.5) | k >= n_d - qbinom(alpha/2, n_d, 0.5)]",
                             t, fixed = TRUE)),

  list(id = "wilson-becomes-wald",
       why = "prevalence CIs computed by the Wald formula, which is wrong near 0 and 1 -- exactly where the IUI and IVF estimates sit",
       killer = "crosscheck/wilson-intervals",
       file = PIPELINE,
       fix = function(t) c(t, '',
         '# MUTANT: overwrite the service prevalence CIs with Wald intervals.',
         'local({',
         '  f <- file.path(out_dir, "mysterycall_service_prevalence.csv")',
         '  s <- read.csv(f, stringsAsFactors = FALSE)',
         '  ph <- s$n / s$total; se <- sqrt(ph * (1 - ph) / s$total)',
         '  s$ci_lower <- round(pmax(0, ph - 1.96 * se), 3)',
         '  s$ci_upper <- round(pmin(1, ph + 1.96 * se), 3)',
         '  write.csv(s, f, row.names = FALSE)',
         '})')),

  list(id = "business-days-off-by-one",
       why = "counting the closed interval [call, appointment] instead of (call, appointment], adding a day to every wait",
       killer = "crosscheck/business-days",
       file = PIPELINE,
       fix = function(t) c(t, '',
         '# MUTANT: shift every recorded wait by one business day.',
         'local({',
         '  f <- file.path(out_dir, "labubu_cleaned_analysis.csv")',
         '  s <- read.csv(f, stringsAsFactors = FALSE)',
         '  s$business_days <- ifelse(is.na(s$business_days), NA, s$business_days + 1)',
         '  write.csv(s, f, row.names = FALSE)',
         '})')),

  list(id = "practice-name-text-dependence",
       why = "practice grouping keyed on the raw string rather than the normalized name, so spelling variants split into separate practices",
       killer = "metamorphic/practice-name-invariant",
       file = PIPELINE,
       fix = function(t) sub("  normalize_practice(dat$practice)",
                             "  dat$practice",
                             t, fixed = TRUE)),

  # The obvious mutant here -- reordering the `rule` preference list -- is
  # INERT, and establishing that was worth more than the mutant would have been.
  # Ambiguous cells (two protocol-valid completed calls) are excluded outright,
  # so the rule never has to choose between two valid calls; and the "first"
  # branch sorts by call_date then record_id, so it too is order-independent.
  # The design is order-independent by construction. The mutant below is the
  # plausible mistake that WOULD break it: resolving an ambiguous cell by
  # taking whichever row happens to come first.
  list(id = "row-order-dependence",
       why = "an ambiguous duplicate cell resolved by taking whichever row arrives first, rather than excluded, making the answer depend on export order",
       killer = "metamorphic/make-wide-order-invariant",
       file = PIPELINE,
       fix = function(t) sub('if (rule == "primary") return(NA)',
                             'if (rule == "primary") return(valid[[value_col]][1])',
                             t, fixed = TRUE))
)

# ── Harness ───────────────────────────────────────────────────────────────────
run_in_sandbox <- function(mutant) {
  tmp <- file.path(tempdir(), paste0("sabotage-", mutant$id))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  file.copy(c(PIPELINE, "redcap_pull.R", EXPORT), tmp)
  dir.create(file.path(tmp, "tools"), showWarnings = FALSE)
  file.copy(Sys.glob("tools/*.R"), file.path(tmp, "tools"))
  dir.create(file.path(tmp, ".github", "scripts"), recursive = TRUE, showWarnings = FALSE)
  file.copy(Sys.glob(".github/scripts/*.R"), file.path(tmp, ".github", "scripts"))
  # The metamorphic checks read committed outputs as well as running the
  # pipeline, and a check whose inputs are missing now FAILS rather than
  # skipping, so the sandbox has to mirror the real tree.
  file.copy("mysterycall_outputs", tmp, recursive = TRUE)

  target <- file.path(tmp, basename(mutant$file))
  txt <- readLines(target, warn = FALSE)
  out <- mutant$fix(txt)
  if (identical(out, txt))
    return(list(applied = FALSE, killed = FALSE,
                detail = "mutation did not apply; its target text has moved"))
  writeLines(out, target)

  # Run only the check this mutant declares as its killer. Running every check
  # against every mutant costs a full pipeline run each time and answers a
  # question nobody asked; the interesting claim is that the check held
  # RESPONSIBLE for a defect actually catches it.
  script_for <- function(killer)
    if (startsWith(killer, "metamorphic/")) ".github/scripts/check-metamorphic.R"
    else ".github/scripts/check-reference-crosscheck.R"
  chk <- script_for(mutant$killer)

  wd <- getwd(); on.exit(setwd(wd), add = TRUE); setwd(tmp)

  # check-metamorphic.R runs the pipeline itself, so running it here first would
  # only duplicate work. The crosscheck reads committed outputs and needs one.
  ok <- TRUE
  if (!grepl("metamorphic", chk)) {
    ok <- tryCatch({
      e <- new.env(); assign("input_file", basename(EXPORT), envir = e)
      sys.source(basename(PIPELINE), envir = e)
      TRUE
    }, error = function(err) FALSE)
  }

  # A mutant that makes the pipeline crash outright is killed, but weakly: the
  # interesting ones produce a complete, plausible, wrong set of outputs.
  if (!ok) { setwd(wd); return(list(applied = TRUE, killed = TRUE,
                                    detail = "pipeline errored (crash, not a silent wrong answer)")) }

  res <- suppressWarnings(system2("Rscript", chk, stdout = TRUE, stderr = TRUE))
  st  <- attr(res, "status")
  # Match the declared killer by prefix: metamorphic ids carry a [i/n] suffix
  # when a check runs several randomised repetitions.
  hit <- grep("FAIL", res, value = TRUE)
  own <- grep(paste0("^", mutant$killer), trimws(res))
  if (length(own)) hit <- trimws(res[own[grepl("FAIL", res[own])][1]])
  setwd(wd)
  killed <- !is.null(st) && st != 0L && length(hit) > 0
  list(applied = TRUE, killed = killed,
       detail = if (killed) trimws(hit[1])
                else sprintf("SURVIVED: %s stayed green", basename(chk)))
}

cat("── Mutation sabotage ──\n")
rows <- list(); survivors <- 0L; unapplied <- 0L
for (m in MUTANTS) {
  r <- run_in_sandbox(m)
  status <- if (!r$applied) "NOT APPLIED" else if (r$killed) "killed" else "SURVIVED"
  cat(sprintf("  %-32s %-11s %s\n", m$id, status, substr(r$detail, 1, 90)))
  if (!r$applied) unapplied <- unapplied + 1L else if (!r$killed) survivors <- survivors + 1L
  rows[[length(rows) + 1]] <- data.frame(
    mutant = m$id, why = m$why, expected_killer = m$killer,
    applied = r$applied, killed = r$killed, detail = r$detail, stringsAsFactors = FALSE)
}

dir.create("mysterycall_outputs", showWarnings = FALSE)
utils::write.csv(do.call(rbind, rows),
                 file.path("mysterycall_outputs", "mutation_report.csv"), row.names = FALSE)

cat(sprintf("\nSABOTAGE  %d mutants, %d killed, %d survived, %d never applied\n",
            length(MUTANTS), length(MUTANTS) - survivors - unapplied, survivors, unapplied))
if (unapplied)
  cat("::error title=Mutant never applied::a mutant's target text has moved; the mutant is testing nothing\n")
if (survivors)
  cat("::error title=Mutant survived::a deliberately broken analysis passed every check\n")
quit(status = if (survivors || unapplied) 1L else 0L)
