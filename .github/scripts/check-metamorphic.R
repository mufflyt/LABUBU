#!/usr/bin/env Rscript
# check-metamorphic.R
#
# Transformations that must NOT change the scientific answer.
#
# Borrowed from mufflyt/isochrones-ci ("test-metamorphic.R"), whose rationale
# is the reason this class needs its own check:
#
#   "These catch a class that fixed expected values cannot: hidden dependence
#    on input order, on identifier text, on chunking, or on how many workers
#    happen to be running. Such bugs produce a *plausible* number every time,
#    so no golden comparison flags them -- only invariance under a
#    transformation does."
#
# LABUBU is exposed to exactly this. CLAUDE.md already names practice-name
# normalization "the sneakiest failure mode": a new spelling variant silently
# becomes a singleton and deflates the triad count, producing a plausible
# number with no error. A golden-value check cannot see it. Reordering the
# export, or relabelling every practice, can.
#
# The pipeline is re-run under each transformation and the resulting estimands
# compared. Comparison is BY NAME, never by position: comparing positionally
# would let a reordering bug pass by construction.

suppressWarnings(suppressPackageStartupMessages({ library(readr) }))

# Prefer a real export; fall back to the committed fixture. The raw exports are
# gitignored (they carry contact details), so CI never has one and the
# structural properties checked here hold on any dataset. Failing when neither
# exists rather than skipping: a check that cannot evaluate its condition must
# fail (docs/APPENDIX-lessons.md).
resolve_export <- function() {
  real <- Sys.glob("LABUBU_DATA_LABELS_*.csv")
  real <- real[order(real, decreasing = TRUE)]
  if (length(real)) return(real[1])
  fx <- file.path("tests", "fixtures", "LABUBU_DATA_LABELS_fixture.csv")
  if (file.exists(fx)) return(fx)
  stop("no LABUBU_DATA_LABELS_*.csv and no tests/fixtures fixture; ",
       "the check cannot evaluate its condition", call. = FALSE)
}

EXPORT <- resolve_export()
cat("using export:", EXPORT, "\n")

fail <- 0L; n_ok <- 0L
report <- function(id, ok, detail) {
  cat(sprintf("%-42s %s  -- %s\n", id, if (ok) "PASS" else "FAIL", detail))
  if (!ok) { cat(sprintf("::error title=%s::%s\n", id, detail)); fail <<- fail + 1L }
  else n_ok <<- n_ok + 1L
}

# Run the pipeline in a scratch directory on a transformed export and return
# its estimands keyed by id.
run_pipeline <- function(transform, label) {
  tmp <- file.path(tempdir(), paste0("meta-", label))
  unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
  file.copy(c("evaluate_labubu_mysterycall.R", "redcap_pull.R"), tmp)
  dir.create(file.path(tmp, "tools"), showWarnings = FALSE)
  file.copy(Sys.glob("tools/*.R"), file.path(tmp, "tools"))
  # estimands.csv is produced by estimand-report.R, not by the pipeline, so the
  # scratch copy needs it too.
  dir.create(file.path(tmp, ".github", "scripts"), recursive = TRUE, showWarnings = FALSE)
  file.copy(".github/scripts/estimand-report.R", file.path(tmp, ".github", "scripts"))

  raw <- readr::read_csv(EXPORT, show_col_types = FALSE,
                         locale = readr::locale(encoding = "UTF-8"))
  raw <- transform(raw)
  dest <- file.path(tmp, basename(EXPORT))
  readr::write_csv(raw, dest)

  wd <- getwd(); on.exit(setwd(wd), add = TRUE); setwd(tmp)
  ok <- tryCatch({
    e <- new.env()
    assign("input_file", basename(EXPORT), envir = e)
    sys.source("evaluate_labubu_mysterycall.R", envir = e)
    sys.source(".github/scripts/estimand-report.R", envir = new.env())
    TRUE
  }, error = function(err) { message("  pipeline error (", label, "): ",
                                     conditionMessage(err)); FALSE })
  setwd(wd)
  f <- file.path(tmp, "mysterycall_outputs", "estimands.csv")
  if (!ok || !file.exists(f)) return(NULL)
  e <- utils::read.csv(f, stringsAsFactors = FALSE)
  stats::setNames(e$estimate, e$estimand_id)
}

baseline <- run_pipeline(identity, "baseline")
if (is.null(baseline)) {
  report("metamorphic/baseline-runs", FALSE,
         "the pipeline did not produce estimands on the unmodified export")
  cat("\nMETAMORPHIC  0 passed, 1 failed\n"); quit(status = 1L)
}
report("metamorphic/baseline-runs", TRUE,
       sprintf("%d estimands from the unmodified export", length(baseline)))

compare <- function(id, got, tol = 1e-8) {
  if (is.null(got)) return(report(id, FALSE, "transformed run produced no estimands"))
  shared <- intersect(names(baseline), names(got))
  missing <- setdiff(names(baseline), names(got))
  # Compare BY NAME. Positional comparison would let a reordering bug pass by
  # construction, which is the very thing this check exists to catch.
  d <- abs(got[shared] - baseline[shared])
  d <- d[!is.na(d) & d > tol]
  bad <- c(if (length(missing)) sprintf("estimands vanished: %s",
                                        paste(head(missing, 3), collapse = ", ")),
           if (length(d)) sprintf("%d estimand(s) moved, worst %s by %.3g",
                                  length(d), names(which.max(d)), max(d)))
  report(id, length(bad) == 0,
         if (length(bad)) paste(bad, collapse = "; ")
         else sprintf("all %d estimands identical", length(shared)))
}

set.seed(20260905L)

# ── ROW ORDER ─────────────────────────────────────────────────────────────────
# The export arrives in record_id order. Nothing in the science depends on that,
# so shuffling it must change nothing. A duplicate-resolution rule that takes
# "whichever row comes first" would fail here, which is precisely the bug the
# duplicate-call adjudication was written to remove.
#
# Several permutations, not one. The order-dependence this is meant to catch
# lives in a handful of duplicate cells, and a single shuffle has roughly a
# one-in-four chance of leaving those particular pairs in their original
# relative order and reporting a clean bill of health. isochrones-ci runs
# max(3L, n_random_worlds()) worlds for the same reason. A sabotage mutant that
# genuinely introduced order dependence survived a single-shuffle version of
# this check, which is how the weakness was found.
N_SHUFFLES <- as.integer(Sys.getenv("METAMORPHIC_SHUFFLES", "3"))
for (i in seq_len(max(1L, N_SHUFFLES))) {
  set.seed(20260905L + i)
  compare(sprintf("metamorphic/row-order-invariant [%d/%d]", i, N_SHUFFLES),
          run_pipeline(function(d) d[sample.int(nrow(d)), , drop = FALSE],
                       paste0("shuffle", i)))
}

# ── PRACTICE IDENTIFIER RENAMING ──────────────────────────────────────────────
# Relabelling every practice with an opaque token must not move a single
# estimand. If it does, some quantity depends on the TEXT of a practice name --
# alphabetical ordering, a normalization rule matching a substring, a factor
# level ordering -- rather than on the grouping the name denotes.
#
# The relabelling is keyed on the NORMALIZED name, not the raw string.
# normalize_practice() deliberately collapses spelling variants onto one
# practice, so mapping raw strings one-to-one would split practices that ought
# to merge and destroy the very grouping this test holds fixed. The first draft
# of this check did exactly that and reported 47 lost triads as a pipeline bug;
# the repository's fixture builder made the identical mistake earlier. The
# property under test is "nothing downstream depends on the name text, given
# the grouping". Whether normalization ITSELF is robust is a different
# question, answered by practice_name_review_nearduplicates.csv.
compare("metamorphic/practice-name-invariant",
        run_pipeline(function(d) {
          col <- grep("practice name", names(d), ignore.case = TRUE, value = TRUE)[1]
          if (is.na(col)) return(d)
          src <- readLines("evaluate_labubu_mysterycall.R", warn = FALSE)
          env <- new.env()
          # Lift PHONE_RE and normalize_practice verbatim. Take each definition
          # up to the first line that is exactly "}" AFTER its opening line, so
          # a one-line helper is not swallowed along with the function below it.
          take <- function(pat, is_fn) {
            i <- grep(pat, src)[1]
            j <- if (is_fn) i + which(src[(i + 1):length(src)] == "}")[1] else i
            paste(src[i:j], collapse = "\n")
          }
          eval(parse(text = take("^PHONE_RE", FALSE)), envir = env)
          eval(parse(text = take("^redact_phone <- function", FALSE)), envir = env)
          eval(parse(text = take("^normalize_practice <- function", TRUE)), envir = env)

          key <- env$normalize_practice(d[[col]])
          u   <- unique(key[!is.na(key)])

          # Tokens must be FIXED POINTS of normalize_practice, or the pipeline
          # renormalizes them into a different grouping and the test measures
          # its own transformation instead of the pipeline. Letters only: the
          # normalizer strips a trailing number as a call-list index, which
          # collapsed every "Practice 0001" onto the single name "Practice".
          tok <- vapply(seq_along(u), function(i) {
            n <- i - 1L; a <- character(0)
            repeat { a <- c(LETTERS[(n %% 26) + 1L], a); n <- n %/% 26
                     if (n == 0L) break }
            paste0("Practice ", paste(a, collapse = ""))
          }, character(1))
          stopifnot(identical(env$normalize_practice(tok), tok))

          map <- stats::setNames(tok, u)
          out <- unname(map[key])
          d[[col]] <- ifelse(is.na(key), d[[col]], out)
          d
        }, "rename"))

# ── ROW ORDER INSIDE make_wide ────────────────────────────────────────────────
# The whole-pipeline shuffle above cannot reach this. `dat` passes through
# mysterycall_business_days() and mysterycall_appointment_obtained() before
# make_wide() sees it, and those normalize row order, so permuting the EXPORT
# is invisible by the time the duplicate-resolution rule runs.
#
# That was established the hard way: a sabotage mutant which makes make_wide
# resolve an ambiguous cell by taking whichever row comes first is a genuine
# order dependence -- verified directly, it changes practice 65's lesbian-couple
# cell under row reversal -- and it survived the pipeline-level check three
# shuffles running. A test that cannot fail for a defect it names is worse than
# no test, so the property is checked where it actually lives: on the function.
local({
  analysis <- file.path("mysterycall_outputs", "labubu_cleaned_analysis.csv")
  if (!file.exists("evaluate_labubu_mysterycall.R") || !file.exists(analysis))
    return(report("metamorphic/make-wide-order-invariant", FALSE,
                  "pipeline source or labubu_cleaned_analysis.csv absent; the check cannot evaluate its condition, which is a failure and not a skip"))

  src  <- readLines("evaluate_labubu_mysterycall.R", warn = FALSE)
  i    <- grep("^make_wide <- function", src)[1]
  j    <- i + which(src[(i + 1):length(src)] == "}")[1]
  env  <- new.env()
  eval(parse(text = paste(src[i:j], collapse = "\n")), envir = env)

  d <- utils::read.csv(file.path("mysterycall_outputs", "labubu_cleaned_analysis.csv"),
                       stringsAsFactors = FALSE)
  d$in_offer_den <- d$in_offer_den %in% c(TRUE, "TRUE", 1, "1")
  d$scenario <- factor(d$scenario,
                       levels = c("Straight couple", "Lesbian couple", "Single mother"))
  rev_d <- d[rev(seq_len(nrow(d))), , drop = FALSE]

  bad <- character(0)
  for (vc in c("appt_offered", "reached", "wait_days")) {
    if (!vc %in% names(d)) next
    a <- env$make_wide(d, vc)
    b <- env$make_wide(rev_d, vc)
    b <- b[match(a$practice_id, b$practice_id), , drop = FALSE]
    same <- isTRUE(all.equal(a, b, check.attributes = FALSE))
    if (!same) {
      cols <- setdiff(names(a), "practice_id")
      moved <- unlist(lapply(cols, function(cl)
        a$practice_id[!mapply(identical, a[[cl]], b[[cl]])]))
      bad <- c(bad, sprintf("%s differs at practice %s", vc,
                            paste(unique(moved), collapse = ", ")))
    }
  }
  report("metamorphic/make-wide-order-invariant", length(bad) == 0,
         if (length(bad)) paste(bad, collapse = "; ")
         else "make_wide is identical under row reversal for every outcome")
})

cat(sprintf("\nMETAMORPHIC  %d passed, %d failed\n", n_ok, fail))
quit(status = if (fail) 1L else 0L)
