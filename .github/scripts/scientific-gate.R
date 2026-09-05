#!/usr/bin/env Rscript
# ── LABUBU scientific gate ────────────────────────────────────────────────────
# Structural invariants the analysis must satisfy. These are NOT unit tests of
# the package; they are assertions about THIS study's outputs that would have
# caught the defects found in the 2026-09 review.
#
# Design rules, borrowed from mufflyt/isochrones-ci and mufflyt/mysterymaps:
#   * "did it finish" and "did it pass" are separate signals — the sentinel file
#     is written last, and a run without it is a failure regardless of exit code
#   * every check reports PASS/FAIL individually; the gate fails on ANY failure
#     rather than stopping at the first, so one run shows every problem
#   * a check that cannot be evaluated is a FAILURE, never a silent skip

OUT <- "mysterycall_outputs"
res <- list()

# A check may PASS, FAIL, or SKIP. SKIP exists only for a check whose
# PRECONDITION is legitimately absent in this environment -- not for a check
# that errored, and never as a way to make red go green. Skips are printed,
# recorded in the TSV, and counted in the summary so they cannot hide.
SKIP <- function(detail) structure("skip", class = "gate_skip", detail = detail)

check <- function(id, ok, detail = "") {
  if (inherits(ok, "gate_skip")) {
    res[[length(res) + 1]] <<- list(id = id, status = "skip",
                                    detail = attr(ok, "detail"))
    cat(sprintf("%-46s %s  -- %s\n", id, "SKIP", attr(ok, "detail")))
    return(invisible(NULL))
  }
  ok <- isTRUE(ok)
  res[[length(res) + 1]] <<- list(id = id, status = if (ok) "pass" else "fail",
                                  detail = detail)
  cat(sprintf("%-46s %s%s\n", id, if (ok) "PASS" else "FAIL",
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}
# The check body is turned into a real zero-argument function before it runs.
# Evaluating it directly inside tryCatch() puts `return()` at top level, where
# R raises "no function to return from" -- which then surfaced as a spurious
# FAIL the first time any early-return branch was taken.
try_check <- function(id, expr) {
  fn <- as.function(c(alist(), substitute(expr)), envir = parent.frame())
  r  <- tryCatch(fn(), error = function(e) structure(FALSE, detail = conditionMessage(e)))
  if (inherits(r, "gate_skip")) return(check(id, r))
  check(id, r, if (!is.null(attr(r, "detail"))) attr(r, "detail") else "")
}

clean_path <- file.path(OUT, "labubu_cleaned_analysis.csv")
if (!file.exists(clean_path)) {
  cat("FATAL: ", clean_path, " not found; the pipeline did not produce output.\n", sep = "")
  quit(status = 1)
}
d  <- read.csv(clean_path, stringsAsFactors = FALSE)
tf <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")

# ── 1. The outcome-collapse regression ────────────────────────────────────────
# `contact_office <- analytic_inclusion` made "appointment offered" the same
# variable as the inclusion filter. Acceptance was then 100% inside the analytic
# sample by construction. This must never come back.
try_check("outcome/offer-not-aliased-to-inclusion", {
  stopifnot("appt_offered" %in% names(d))
  !identical(tf(d$contact_office), tf(d$analytic_inclusion))
})

try_check("outcome/offer-has-negative-events", {
  n0 <- sum(d$appt_offered == 0L, na.rm = TRUE)
  structure(n0 > 0, detail = paste0(n0, " offered=0 events"))
})

try_check("outcome/reached-refusals-retained", {
  # "Not accepting new patients" is a reached refusal and must be IN the offer
  # denominator, not excluded.
  ref <- d$exclusion_reason %in% "Not accepting new patients"
  structure(!any(ref) || all(tf(d$in_offer_den[ref])),
            detail = paste0(sum(ref), " refusal rows"))
})

# ── 2. Cascade monotonicity ───────────────────────────────────────────────────
try_check("cascade/monotonic", {
  n_call <- nrow(d); n_rch <- sum(tf(d$reached)); n_den <- sum(tf(d$in_offer_den))
  n_off  <- sum(d$appt_offered == 1L, na.rm = TRUE)
  structure(n_off <= n_den && n_den <= n_rch && n_rch <= n_call,
            detail = sprintf("%d calls >= %d reached >= %d eligible >= %d offered",
                             n_call, n_rch, n_den, n_off))
})

# ── 3. Exclusion-reason coverage ──────────────────────────────────────────────
# A new free-text reason that the code map does not know becomes NA, silently
# drops out of `reached`, and shrinks every denominator without any error.
try_check("data/all-exclusion-reasons-mapped", {
  unmapped <- unique(d$exclusion_reason[is.na(d$exclusion_code) &
                                        !is.na(d$exclusion_reason) &
                                        d$exclusion_reason != ""])
  structure(length(unmapped) == 0,
            detail = if (length(unmapped)) paste(unmapped, collapse = " | ") else "none")
})

# ── 3b. Checkbox encoding ─────────────────────────────────────────────────────
# REDCap writes checkboxes as "Checked"/"Unchecked" from the browser export but
# as the option label / "" from the API. A parser that knows only one encoding
# turns every service and restriction variable FALSE against the other, which
# silently zeroes the study's headline descriptive with no error anywhere.
# Cycle tracking is near-universal (~95%), so a zero here means a parse failure,
# not a finding.
try_check("data/checkbox-encoding-parsed", {
  svc <- c("service_cycle_tracking", "service_hormonal_timing",
           "service_ovulation_induction", "service_iui", "service_ivf")
  rst <- c("restrict_lesbian", "restrict_straight", "restrict_single_mother")
  missing <- setdiff(c(svc, rst), names(d))
  if (length(missing))
    return(structure(FALSE, detail = paste("columns absent:", paste(missing, collapse = ", "))))
  inc <- d[tf(d$analytic_inclusion), ]
  n_ct  <- sum(tf(inc$service_cycle_tracking))
  n_svc <- sum(vapply(svc, function(v) sum(tf(inc[[v]])), integer(1)))
  n_rst <- sum(vapply(rst, function(v) sum(tf(d[[v]])),   integer(1)))
  ok <- n_ct > 0 && n_svc > 0 && n_rst > 0
  structure(ok, detail = sprintf(
    "cycle tracking %d/%d, all services %d ticks, restrictions %d ticks%s",
    n_ct, nrow(inc), n_svc, n_rst,
    if (!ok) " -- looks like a checkbox-encoding mismatch" else ""))
})

# ── 4. Practice-name normalization ────────────────────────────────────────────
# A new spelling variant silently becomes a singleton and deflates the triad
# count. The old CI only printed a warning; unresolved pairs now fail.
try_check("data/no-unresolved-near-duplicate-practices", {
  f <- file.path(OUT, "practice_name_review_nearduplicates.csv")
  if (!file.exists(f)) return(structure(FALSE, detail = "review file missing"))
  n <- nrow(read.csv(f, stringsAsFactors = FALSE))
  structure(n == 0, detail = paste0(n, " near-duplicate pair(s); add a rule to normalize_practice()"))
})

# ── 5. Wait-time scale reporting ──────────────────────────────────────────────
# mysterycall_lmm(auto_log = TRUE) returns LOG-scale coefficients. Labelling
# them "business days" reported an intercept of 2.9 log-units as 2.9 days.
try_check("report/wait-reported-as-gmr-not-days", {
  f <- file.path(OUT, "mysterycall_evaluation.md")
  if (!file.exists(f)) return(structure(FALSE, detail = "evaluation.md missing"))
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  logged <- grepl("GEOMETRIC MEAN RATIO|GMR", txt)
  bad    <- grepl("mean difference in business days vs", txt)
  structure(logged && !bad,
            detail = if (bad) "still labels log-scale estimates as day differences" else "GMR reported")
})

# ── 5b. Models that are supposed to be in the report are in the report ────────
# Every model is wrapped in tryCatch so a missing optional dependency degrades
# instead of failing the build. That is right for build survival and wrong for
# an artifact the nightly commits over the good version: when glmmTMB went
# missing in CI, the two-part model silently vanished from the committed report
# and nothing complained. Absence must be loud.
try_check("report/models-present", {
  f <- file.path(OUT, "mysterycall_evaluation.md")
  if (!file.exists(f)) return(structure(FALSE, detail = "evaluation.md missing"))
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  missing <- character(0)
  if (grepl("hurdle model not run", txt))       missing <- c(missing, "hurdle (glmmTMB)")
  if (grepl("glmer triads not run", txt))       missing <- c(missing, "offer GLMER (triads)")
  if (grepl("glmer not run", txt))              missing <- c(missing, "offer GLMER (full)")
  if (grepl("broad glmer not run", txt))        missing <- c(missing, "broad-definition GLMER")
  if (grepl("lmm not run", txt))                missing <- c(missing, "wait LMM")
  structure(length(missing) == 0,
            detail = if (length(missing))
              paste0("silently dropped: ", paste(missing, collapse = ", "))
            else "all protocol models present")
})

# ── 5c. No identifiable people in committed analysis artifacts ────────────────
# Study staff are human subjects of this measurement even though they are also
# its authors. The caller-confounding analysis needs caller STRATA, not caller
# identities, so committed artifacts carry stable de-identified labels.
#
# Asserted positively -- every caller value must MATCH the de-identified form --
# rather than by a denylist of real names, because a denylist would itself have
# to contain the names it is protecting.
try_check("privacy/callers-de-identified", {
  if (!"caller" %in% names(d))
    return(structure(FALSE, detail = "caller column absent"))
  if ("caller_raw" %in% names(d))
    return(structure(FALSE, detail = "caller_raw is present in a committed artifact"))
  allowed <- grepl("^(Caller [A-Z]|Unrecorded)$", d$caller)
  offenders <- unique(d$caller[!allowed])
  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste0(length(offenders), " non-de-identified caller value(s)")
            else paste0(length(unique(d$caller)), " de-identified caller labels"))
})

try_check("privacy/no-contact-details-in-artifacts", {
  artifact_files <- list.files(OUT, pattern = "\\.(csv|md)$", full.names = TRUE)
  phone_re <- "\\(?[0-9]{3}\\)?[-. ][0-9]{3}[-. ][0-9]{4}"
  email_re <- "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
  offenders <- character(0)
  for (f in artifact_files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    if (grepl(phone_re, txt) || grepl(email_re, txt))
      offenders <- c(offenders, basename(f))
  }
  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste("contact details in:", paste(offenders, collapse = ", "))
            else paste(length(artifact_files), "artifacts clean"))
})

# ── 5d. Manuscript claims resolve to the analysis ─────────────────────────────
# The manuscript looks its headline numbers up by claim id. If the claims table
# is missing, or a claim no longer resolves to an estimand, the paper and the
# analysis have silently diverged -- which is the failure the claims table
# exists to make impossible.
try_check("manuscript/claims-resolve", {
  claims_file    <- file.path(OUT, "manuscript_claims.csv")
  estimand_file  <- file.path(OUT, "estimands.csv")
  if (!file.exists(claims_file))
    return(structure(FALSE, detail = "manuscript_claims.csv absent"))
  if (!file.exists(estimand_file))
    return(structure(FALSE, detail = "estimands.csv absent"))
  claims    <- read.csv(claims_file, stringsAsFactors = FALSE)
  estimands <- read.csv(estimand_file, stringsAsFactors = FALSE)
  unresolved <- claims$claim_id[!claims$estimand_id %in% estimands$estimand_id]
  empty      <- claims$claim_id[is.na(claims$estimate)]
  offenders  <- unique(c(unresolved, empty))
  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste("claims not backed by an estimand:",
                    paste(offenders, collapse = ", "))
            else paste(nrow(claims), "claims resolve"))
})

# ── 5e. The restriction checkboxes stay out of inferential analysis ───────────
# Their semantics are unresolved: the REDCap label reads as marking a
# RESTRICTED group, while the response pattern (straight 37 > lesbian 27 >
# single mother 19) is what marking groups SERVED would produce. Deciding
# between those readings from the frequencies would be reverse-coding on
# intuition, and it is the one reading that would flip the direction of a
# discrimination finding.
#
# Excluding them by convention is not enough -- a future model specification
# could pull them in without anyone noticing. This fails the build if a
# restriction variable is used as a model outcome or predictor, or appears as a
# reported estimand or manuscript claim. Descriptive tabulation for review
# (restriction_checkbox_review.csv, table1) stays allowed: the point is that
# they must not become evidence.
try_check("restriction/excluded-from-inference", {
  restriction_vars <- c("restrict_lesbian", "restrict_straight",
                        "restrict_single_mother")
  offenders <- character(0)

  pipeline_src <- readLines("evaluate_labubu_mysterycall.R", warn = FALSE)
  model_lines <- grep(
    "mysterycall_(logistic_model|lmm|gee|hurdle_wait|poisson_model)\\(|glmer\\(|geeglm\\(|lmer\\(",
    pipeline_src)
  # A model call spans several lines; inspect each call and the lines that
  # follow it up to the closing paren.
  # Search the whole window rather than truncating at the first ")": a
  # mysterycall_*() call opens its paren on the first line and the arguments
  # follow, so truncating there cut the window off before `outcome =` and the
  # check silently saw nothing. Over-capturing a few lines is the safe error.
  for (start in model_lines) {
    window <- pipeline_src[start:min(start + 12L, length(pipeline_src))]
    text   <- paste(window, collapse = " ")
    for (v in restriction_vars)
      if (grepl(v, text, fixed = TRUE))
        offenders <- c(offenders, paste0(v, " near a model call at line ", start))
  }

  for (f in c("estimands.csv", "manuscript_claims.csv")) {
    path <- file.path(OUT, f)
    if (!file.exists(path)) next
    txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
    for (v in restriction_vars)
      if (grepl(v, txt, fixed = TRUE))
        offenders <- c(offenders, paste0(v, " reported in ", f))
  }

  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste("restriction variables entered inference:",
                    paste(offenders, collapse = "; "))
            else "3 restriction variables held out of inference")
})

# ── 5f. Committed figures are opaque ──────────────────────────────────────────
# theme_void() leaves the plot background blank and ggsave() honours that,
# writing an alpha channel. A figure of black text and black outlines then
# renders correctly on a white page and disappears against any dark viewer,
# dark-mode PDF reader or journal proofing tool. It looks fine right up until
# it does not, which is why this needs a check rather than an eye.
try_check("figures/opaque-background", {
  figure_dir <- file.path(OUT, "figures")
  if (!dir.exists(figure_dir))
    return(structure(FALSE, detail = "figures directory absent"))
  if (!requireNamespace("png", quietly = TRUE))
    return(structure(FALSE, detail = "png package unavailable; cannot verify"))
  figures <- list.files(figure_dir, pattern = "[.]png$", full.names = TRUE)
  if (!length(figures))
    return(structure(FALSE, detail = "no PNG figures found"))
  offenders <- character(0)
  for (f in figures) {
    img <- png::readPNG(f)
    if (length(dim(img)) == 3 && dim(img)[3] == 4) {
      transparent <- mean(img[, , 4] == 0)
      if (transparent > 0.01)
        offenders <- c(offenders, sprintf("%s (%.0f%% transparent)",
                                          basename(f), 100 * transparent))
    }
  }
  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste("transparent background:", paste(offenders, collapse = ", "))
            else paste(length(figures), "figures opaque"))
})

# ── 6. Caller confounding must be surfaced ────────────────────────────────────
try_check("report/caller-confounding-reported", {
  f <- file.path(OUT, "caller_dominance_by_scenario.csv")
  if (!file.exists(f)) return(structure(FALSE, detail = "caller_dominance CSV missing"))
  cd <- read.csv(f, stringsAsFactors = FALSE)
  txt <- paste(readLines(file.path(OUT, "mysterycall_evaluation.md"), warn = FALSE), collapse = "\n")
  structure(nrow(cd) > 0 && grepl("CALLER CONFOUNDING", txt),
            detail = sprintf("max single-caller share %.1f%%", max(cd$top_caller_pct)))
})

# ── 7. No hardcoded statistics in the manuscript prose ────────────────────────
# Every number in the Rmd must come from an inline R expression. Literal
# statistics drift silently away from the data, which is how the manuscript
# came to report ORs and medians from a superseded export.
# A Vancouver reference list has three failure modes that no renderer catches:
# a citation with no matching entry, an entry nothing cites, and numbering that
# is not in order of first appearance. All three reached a submission-ready
# draft here (SAMPL cited as the source for a Wilson interval, a housing-
# discrimination study cited for an RRM clinical menu, and 8-9 appearing before
# 3), so they are checked rather than trusted to proofreading.
try_check("manuscript/references-consistent", {
  f <- "labubu_mysterycall_manuscript.Rmd"
  if (!file.exists(f))
    return(structure(FALSE, detail = paste(f, "absent")))
  lines <- readLines(f, warn = FALSE)

  intro <- grep("^## INTRODUCTION", lines)
  refs  <- grep("^## REFERENCES",   lines)
  if (!length(intro) || !length(refs))
    return(structure(FALSE, detail = "INTRODUCTION or REFERENCES heading absent"))

  body <- paste(lines[intro[1]:(refs[1] - 1)], collapse = "\n")
  listed <- as.integer(sub("^([0-9]+)\\..*$", "\\1",
                grep("^[0-9]+\\. [A-Z]", lines[refs[1]:length(lines)], value = TRUE)))
  if (!length(listed))
    return(structure(FALSE, detail = "no reference entries parsed"))

  # Expand [4-9] and [3,13-15] into the integers they cite, in order.
  groups <- regmatches(body, gregexpr("\\[[0-9]+(?:[,\u2013-][0-9]+)*\\]", body))[[1]]
  cited  <- unlist(lapply(groups, function(g) {
    unlist(lapply(strsplit(gsub("\\[|\\]", "", g), ",")[[1]], function(part) {
      ends <- as.integer(strsplit(part, "[\u2013-]")[[1]])
      if (length(ends) == 2) seq(ends[1], ends[2]) else ends
    }))
  }))
  if (!length(cited))
    return(structure(FALSE, detail = "no citations parsed from body"))

  first    <- cited[!duplicated(cited)]
  dangling <- setdiff(cited,  listed)   # cited, never listed
  orphan   <- setdiff(listed, cited)    # listed, never cited
  unsorted <- !identical(first, sort(first))

  problems <- c(
    if (length(dangling)) paste("cited but not listed:", paste(sort(dangling), collapse = ", ")),
    if (length(orphan))   paste("listed but never cited:", paste(sort(orphan), collapse = ", ")),
    if (unsorted)         paste("not in order of first appearance:",
                                paste(first, collapse = ", ")))

  structure(length(problems) == 0,
            detail = if (length(problems)) paste(problems, collapse = "; ")
                     else paste(length(listed), "references, all cited, in order"))
})

try_check("manuscript/no-hardcoded-statistics", {
  f <- "labubu_mysterycall_manuscript.Rmd"
  if (!file.exists(f)) return(structure(FALSE, detail = "Rmd missing"))
  lines <- readLines(f, warn = FALSE)
  body  <- lines[!grepl("^\\s*(#|/\\*|\\.|[a-z_]+ *(<-|=))", lines)]
  body  <- gsub("`r [^`]*`", "", body)          # strip inline R
  hits  <- grep("\\bOR [0-9]|[0-9]+\\.[0-9]% |95% CI [0-9]", body, value = TRUE)
  hits  <- hits[!grepl("^\\s*(- |[0-9]+\\. )?\\*\\*", hits)]
  structure(length(hits) == 0,
            detail = if (length(hits)) paste0(length(hits), " literal stat(s): ",
                                              substr(hits[1], 1, 70)) else "none")
})

# ── 8. Provenance matches the export actually present ─────────────────────────
# Raw exports are gitignored (they carry practice contact information), so a
# CI runner checking out this repo has no export to hash. That is a missing
# PRECONDITION, not a passing check and not a failure -- so it skips, loudly.
# It still FAILS if an export IS present and disagrees with PROVENANCE.md,
# which is the case the check exists for.
try_check("provenance/md5-matches-repo-export", {
  if (!file.exists("PROVENANCE.md"))
    return(structure(FALSE, detail = "PROVENANCE.md missing"))
  pv  <- readLines("PROVENANCE.md", warn = FALSE)
  row <- grep("REDCap export \\(labels\\)", pv, value = TRUE)
  md5 <- grep("MD5 \\(first 16\\)", pv, value = TRUE)
  if (!length(row) || !length(md5))
    return(structure(FALSE, detail = "provenance rows missing or malformed"))
  named <- sub(".*`([^`]+)`.*", "\\1", row[1])
  want  <- sub(".*`([^`]+)`.*", "\\1", md5[1])

  present <- list.files(".", pattern = "^LABUBU_DATA_LABELS_.*\\.csv$")
  if (!file.exists(named)) {
    # No export at all -> precondition absent -> skip.
    if (length(present) == 0)
      return(SKIP(paste0("no export in working tree (gitignored); provenance names ", named)))
    # An export IS present but is not the one provenance names -> real drift.
    return(structure(FALSE,
      detail = paste0("provenance names ", named, " but working tree has ",
                      paste(present, collapse = ", "))))
  }
  got <- substr(tools::md5sum(named)[[1]], 1, 16)
  structure(identical(got, want), detail = paste0(named, ": ", got, " vs ", want))
})

# ── 9. Denominators are not silently equal ────────────────────────────────────
try_check("denominators/distinct-levels", {
  n_rch <- sum(tf(d$reached)); n_inc <- sum(tf(d$analytic_inclusion))
  structure(n_rch >= n_inc, detail = sprintf("reached=%d, analytic_inclusion=%d", n_rch, n_inc))
})

# ── Gate ──────────────────────────────────────────────────────────────────────
fails <- Filter(function(x) x$status == "fail", res)
skips <- Filter(function(x) x$status == "skip", res)
cat("\n", strrep("-", 72), "\n", sep = "")
cat(sprintf("LABUBU scientific gate: %d checks, %d passed, %d failed, %d skipped\n",
            length(res), length(res) - length(fails) - length(skips),
            length(fails), length(skips)))
for (s_ in skips) cat(sprintf("  SKIPPED: %s (%s)\n", s_$id, s_$detail))

dir.create("ci-results", showWarnings = FALSE)
writeLines(vapply(res, function(x) sprintf("%s\t%s\t%s", x$id, x$status, x$detail),
                  character(1)),
           "ci-results/scientific-gate.tsv")

if (length(fails)) {
  for (f in fails)
    cat(sprintf("::error title=%s::%s\n", f$id, if (nzchar(f$detail)) f$detail else "failed"))
  # Sentinel is still written: the run FINISHED, it just did not PASS.
  writeLines("complete", "ci-results/gate.sentinel")
  quit(status = 1)
}
writeLines("complete", "ci-results/gate.sentinel")
cat("All checks passed.\n")
