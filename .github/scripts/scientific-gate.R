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

# This is a secret-shopper study. The practices and individual clinicians who
# were called did not consent to being named, and practice_key holds real names
# with credentials and state ("Armando Garza, MD (TX)"). Rendered manuscripts,
# supplements and cover letters are the documents that leave the private repo,
# so no practice key may appear in one. Caught here after a draft supplement
# printed four clinician names in a protocol-deviation table.
try_check("privacy/no-practice-names-in-submission-artifacts", {
  analysis <- file.path(OUT, "labubu_cleaned_analysis.csv")
  if (!file.exists(analysis))
    return(structure(FALSE, detail = "labubu_cleaned_analysis.csv absent"))
  keys <- unique(read.csv(analysis, stringsAsFactors = FALSE)$practice_key)
  keys <- keys[!is.na(keys) & nzchar(keys) & keys != "[redacted]"]
  if (!length(keys))
    return(structure(FALSE, detail = "no practice keys parsed; check cannot evaluate"))

  # Named explicitly rather than globbed. Internal working documents (the call
  # worklists emailed to co-investigators) legitimately carry practice names;
  # these three are the files that leave the study team.
  submission <- c("labubu_mysterycall_manuscript", "supplemental_digital_content",
                  "cover_letter_GREEN_JOURNAL")
  artifacts <- unlist(lapply(submission, function(b) Sys.glob(paste0(b, c(".html", ".docx")))))
  rendered  <- unique(sub("\\.(html|docx)$", "", basename(artifacts)))
  missing   <- setdiff(submission, rendered)
  if (length(missing))
    return(structure(FALSE,
      detail = paste("submission artifact never rendered, so it cannot be screened:",
                     paste(missing, collapse = ", "))))

  offenders <- character(0)
  for (f in artifacts) {
    txt <- tryCatch(paste(readLines(f, warn = FALSE), collapse = "\n"),
                    error = function(e) "")
    hit <- keys[vapply(keys, function(k) grepl(k, txt, fixed = TRUE), logical(1))]
    if (length(hit))
      offenders <- c(offenders, sprintf("%s (%s)", basename(f), hit[1]))
  }
  structure(length(offenders) == 0,
            detail = if (length(offenders))
              paste("practice names in:", paste(offenders, collapse = "; "))
            else paste(length(artifacts), "rendered artifacts carry no practice name"))
})

# ─────────────────────────────────────────────────────────────────────────────
# Regression invariants: one per mistake actually made in this repository.
# Each names the incident it exists to prevent, so nobody deletes it later
# wondering what it was for.
# ─────────────────────────────────────────────────────────────────────────────

# INCIDENT: Figure 1 computed its six proportions with binom.test(), which is
# Clopper-Pearson, while Appendix Table S3 -- captioned "numeric detail
# underlying Figure 1" -- computed the same six with the Wilson formula. The
# figure and its own table printed different intervals (donor sperm 0.6-8.7
# against 1.0-8.6) and every one of the other invariants passed, because all of
# them read CSVs and none had ever looked at what a figure plots.
#
# The rule this enforces is the one manuscript_claims.csv already enforces for
# text: a number appears in exactly one place in the code. A figure must publish
# the data it drew so that data can be checked against the table, rather than
# being an opaque PNG nobody can audit.
try_check("figures/plotted-values-match-tables", {
  fd <- file.path(OUT, "fig5_service_forest_data.csv")
  sv <- file.path(OUT, "mysterycall_service_prevalence.csv")
  if (!file.exists(fd))
    return(structure(FALSE, detail = paste(basename(fd),
      "absent: a figure that does not publish its data cannot be checked against the table it duplicates")))
  if (!file.exists(sv))
    return(structure(FALSE, detail = "mysterycall_service_prevalence.csv absent"))
  f <- read.csv(fd, stringsAsFactors = FALSE)
  t <- read.csv(sv, stringsAsFactors = FALSE)
  bad <- character(0)

  # (a) Completeness. Six services, or the figure is not the figure described.
  if (nrow(f) != 6)
    bad <- c(bad, sprintf("figure has %d rows, expected 6 services", nrow(f)))

  # (b) Internal coherence: the point must lie inside its own interval, the
  #     interval must not be inverted, and everything must be a percentage.
  if (any(f$lo > f$hi))
    bad <- c(bad, "an interval is inverted (lower above upper)")
  if (any(f$pct < f$lo - 1e-6 | f$pct > f$hi + 1e-6))
    bad <- c(bad, "a point estimate lies outside its own confidence interval")
  if (any(f$lo < 0 | f$hi > 100 | f$pct < 0 | f$pct > 100))
    bad <- c(bad, "a plotted value falls outside 0 to 100 percent")

  # (c) The count and the percentage must describe the same denominator.
  #     k/n printed beside a percentage computed from something else is the
  #     failure a reader can actually see.
  n_inc <- nrow(read.csv(file.path(OUT, "labubu_cleaned_analysis.csv"),
                         stringsAsFactors = FALSE))
  # recover n from the first row rather than assuming it
  n_fig <- round(f$k[which.max(f$pct)] / (f$pct[which.max(f$pct)] / 100))
  if (any(abs(100 * f$k / n_fig - f$pct) > 0.05))
    bad <- c(bad, sprintf("plotted percentages disagree with their own counts over n = %d", n_fig))

  # (d) Colour grouping must come from CLINICAL CATEGORY, not from the observed
  #     percentage. Deriving it from the data once mislabelled ovulation
  #     induction, which is a fertility treatment but not a service donor
  #     conception depends on, and the figure asserted the opposite.
  required <- c("Works with donor sperm", "Intrauterine insemination (IUI)",
                "In vitro fertilization (IVF)")
  if ("grp" %in% names(f)) {
    lab_req <- "Required to conceive without a male partner"
    got <- sort(f$service[f$grp == lab_req])
    if (!identical(got, sort(required)))
      bad <- c(bad, sprintf("colour grouping is wrong: '%s' contains %s",
                            lab_req, paste(got, collapse = ", ")))
  } else {
    bad <- c(bad, "figure data carries no grouping column; the colour split cannot be checked")
  }

  # (e) Agreement with the table captioned as this figure's numeric detail.
  map <- c("Cycle tracking" = "cycle_tracking",
           "Hormonal labs / fertility timing" = "hormonal_timing",
           "Ovulation induction" = "ovulation_induction",
           "Intrauterine insemination (IUI)" = "iui",
           "In vitro fertilization (IVF)" = "ivf")
  checked <- 0L
  for (i in seq_len(nrow(f))) {
    key <- unname(map[f$service[i]])          # single bracket: NA, not an error
    if (is.na(key)) next                      # donor sperm has no row in that table
    r <- t[t$option == key, ]
    if (!nrow(r)) { bad <- c(bad, paste("no table row for", f$service[i])); next }
    checked <- checked + 1L
    if (abs(f$lo[i]  - 100 * r$ci_lower[1])  > 0.05 ||
        abs(f$hi[i]  - 100 * r$ci_upper[1])  > 0.05 ||
        abs(f$pct[i] - 100 * r$prevalence[1]) > 0.05)
      bad <- c(bad, sprintf("%s: figure %.1f (%.1f-%.1f) vs table %.1f (%.1f-%.1f)",
                            f$service[i], f$pct[i], f$lo[i], f$hi[i],
                            100 * r$prevalence[1], 100 * r$ci_lower[1], 100 * r$ci_upper[1]))
  }
  if (checked == 0)
    bad <- c(bad, "no figure row matched the table; the comparison could not evaluate")

  structure(length(bad) == 0,
            detail = if (length(bad)) paste(bad, collapse = "; ")
                     else sprintf("6 services, %d cross-checked against the table, grouping and intervals coherent",
                                  checked))
})

# INCIDENT: the manuscript listed six supplemental items and the supplement did
# not exist. Three of the six were printed inline in the main text while being
# listed as supplemental; the other three had no home at all.
try_check("manuscript/sdc-items-resolve", {
  rmd <- "labubu_mysterycall_manuscript.Rmd"
  sdc <- "supplemental_digital_content.Rmd"
  if (!file.exists(rmd) || !file.exists(sdc))
    return(structure(FALSE, detail = "manuscript or supplement source absent"))
  m <- paste(readLines(rmd, warn = FALSE), collapse = "\n")
  d <- paste(readLines(sdc, warn = FALSE), collapse = "\n")
  # Sub-items (S1a, S5b) roll up to their parent item.
  roll <- function(x) unique(sub("([0-9]+)[a-z]$", "\\1", x))
  promised <- roll(gsub("[^0-9A-Za-z]", "",
    regmatches(m, gregexpr("Appendix (Table|Figure) S[0-9]+[a-z]?", m))[[1]]))
  present  <- roll(gsub("[^0-9A-Za-z]", "",
    regmatches(d, gregexpr("(Table|Figure) S[0-9]+[a-z]?\\.", d))[[1]]))
  present  <- sub("^", "Appendix", present)
  if (!length(promised))
    return(structure(FALSE, detail = "no supplemental items promised; check cannot evaluate"))
  missing <- setdiff(promised, present)
  extra   <- setdiff(present, promised)
  problems <- c(
    if (length(missing)) paste("promised but not in the supplement:",
                               paste(sort(missing), collapse = ", ")),
    if (length(extra))   paste("in the supplement but never listed:",
                               paste(sort(extra), collapse = ", ")))
  structure(length(problems) == 0,
            detail = if (length(problems)) paste(problems, collapse = "; ")
                     else sprintf("%d supplemental items promised and present", length(promised)))
})

# INCIDENT: after a restructure the manuscript carried two Table 1s, with the
# service menu appearing twice; later, three appendix tables printed in BOTH the
# main text and the supplement, shipping the same table twice in one package.
try_check("manuscript/no-duplicate-tables", {
  rmd <- "labubu_mysterycall_manuscript.Rmd"
  sdc <- "supplemental_digital_content.Rmd"
  if (!file.exists(rmd))
    return(structure(FALSE, detail = "manuscript source absent"))
  m <- paste(readLines(rmd, warn = FALSE), collapse = "\n")
  nums <- regmatches(m, gregexpr('caption = "Table [0-9]+\\.', m))[[1]]
  nums <- gsub("[^0-9]", "", nums)
  dup_main <- unique(nums[duplicated(nums)])

  shared <- character(0)
  if (file.exists(sdc)) {
    d <- paste(readLines(sdc, warn = FALSE), collapse = "\n")
    in_main <- gsub("[^0-9A-Za-z]", "",
      regmatches(m, gregexpr("Appendix Table S[0-9]+[a-z]?\\. [A-Z]", m))[[1]])
    # An appendix table is "printed" in the main text only if the main text
    # actually builds it, i.e. carries a kable caption for it.
    printed <- gsub("[^0-9A-Za-z]", "",
      regmatches(m, gregexpr('caption = (sprintf\\()?"Appendix Table S[0-9]+[a-z]?', m))[[1]])
    also <- gsub("[^0-9A-Za-z]", "",
      regmatches(d, gregexpr('caption = (sprintf\\()?"Table S[0-9]+[a-z]?', d))[[1]])
    shared <- intersect(sub("^captionsprintfAppendix", "", printed),
                        sub("^captionsprintf", "", also))
  }
  problems <- c(
    if (length(dup_main)) paste("duplicate Table number(s) in the manuscript:",
                                paste(dup_main, collapse = ", ")),
    if (length(shared))   paste("table printed in BOTH the manuscript and the supplement:",
                                paste(shared, collapse = ", ")))
  structure(length(problems) == 0,
            detail = if (length(problems)) paste(problems, collapse = "; ")
                     else sprintf("%d main-text tables, none duplicated or shared with the supplement",
                                  length(unique(nums))))
})

# INCIDENT: the abstract and precis both had to be cut by hand to meet the
# journal's limits. A limit that is only ever checked by a person is a limit
# that drifts.
try_check("manuscript/abstract-and-precis-within-limits", {
  rmd <- "labubu_mysterycall_manuscript.Rmd"
  if (!file.exists(rmd))
    return(structure(FALSE, detail = "manuscript source absent"))
  lines <- readLines(rmd, warn = FALSE)
  wc <- function(x) length(strsplit(trimws(gsub("`r [^`]*`", "X", paste(x, collapse = " "))), "\\s+")[[1]])

  a0 <- grep("^## ABSTRACT", lines)
  a1 <- grep("^## INTRODUCTION", lines)
  if (!length(a0) || !length(a1))
    return(structure(FALSE, detail = "ABSTRACT or INTRODUCTION heading absent; cannot evaluate"))
  abstract_words <- wc(lines[(a0[1] + 1):(a1[1] - 1)])

  p0 <- grep('class="precis-title"', lines)
  if (!length(p0))
    return(structure(FALSE, detail = "precis block absent; cannot evaluate"))
  precis_words <- wc(sub("</div>.*$", "", lines[p0[1] + 1]))

  problems <- c(
    if (abstract_words > 300) sprintf("abstract is %d words (limit 300)", abstract_words),
    if (precis_words  >  25)  sprintf("precis is %d words (limit 25)",  precis_words))
  structure(length(problems) == 0,
            detail = if (length(problems)) paste(problems, collapse = "; ")
                     else sprintf("abstract %d/300 words, precis %d/25", abstract_words, precis_words))
})

# INCIDENT: the pipeline's default input_file named an export that had been
# archived to Old_redcap/, so running the script on its own failed outright
# with "does not exist in current working directory".
try_check("pipeline/default-export-resolvable", {
  f <- "evaluate_labubu_mysterycall.R"
  if (!file.exists(f))
    return(structure(FALSE, detail = "pipeline source absent"))
  src <- readLines(f, warn = FALSE)
  block <- grep('if \\(!exists\\("input_file"\\)\\)', src)
  if (!length(block))
    return(structure(FALSE, detail = "input_file default block not found; cannot evaluate"))
  # A bare literal filename as the default is the defect: it rots the moment
  # that export is archived. The default must be resolved at run time.
  lit <- regmatches(src, gregexpr('input_file <- "LABUBU_DATA_LABELS_[^"]*\\.csv"', src))
  lit <- unlist(lit)
  structure(length(lit) == 0,
            detail = if (length(lit))
              paste("pipeline hardcodes a default export filename, which rots when it is archived:",
                    paste(lit, collapse = ", "))
            else "the default export is resolved at run time, not hardcoded")
})

# INCIDENT: a newly added check wrapped its body in try(), so when its input was
# missing in the sandbox it printed an error and passed anyway. This is the rule
# docs/APPENDIX-lessons.md exists to enforce: a check that cannot evaluate its
# condition must FAIL, never skip.
try_check("ci/checks-cannot-silently-skip", {
  scripts <- Sys.glob(".github/scripts/*.R")
  if (!length(scripts))
    return(structure(FALSE, detail = "no check scripts found; cannot evaluate"))
  offenders <- character(0)
  for (f in scripts) {
    txt <- readLines(f, warn = FALSE)
    # try({ ... }) around a block that reports: an error inside is swallowed and
    # the check never reports FALSE.
    bad <- grep("^\\s*try\\(\\{", txt)
    if (length(bad))
      offenders <- c(offenders, sprintf("%s:%d try({...}) can swallow a failure",
                                        basename(f), bad[1]))
    # suppressWarnings/silent=TRUE wrapped directly around a report call.
    bad2 <- grep("try\\(.*report\\(", txt)
    if (length(bad2))
      offenders <- c(offenders, sprintf("%s:%d report() inside try()",
                                        basename(f), bad2[1]))
  }
  structure(length(offenders) == 0,
            detail = if (length(offenders)) paste(offenders, collapse = "; ")
                     else sprintf("%d check scripts, none can swallow a failure", length(scripts)))
})

# INCIDENT: the same script was registered in config/ci_contract.yml twice,
# under an umbrella id and again under four granular ids, because two people
# added it independently.
try_check("ci/no-duplicate-script-registration", {
  f <- "config/ci_contract.yml"
  if (!file.exists(f))
    return(structure(FALSE, detail = "ci_contract.yml absent"))
  txt <- readLines(f, warn = FALSE)
  # Advisory entries are excluded: one script legitimately produces both a
  # required check and an advisory one (data-contract.R does). The defect is a
  # script enforced twice, which is what happened when an umbrella id and a set
  # of granular ids for the same script were added independently.
  adv <- grep("^advisory:", txt)
  if (length(adv)) txt <- txt[seq_len(adv[1] - 1)]
  sc  <- trimws(sub("^\\s*script:\\s*", "", grep("^\\s*script:", txt, value = TRUE)))
  if (!length(sc))
    return(structure(FALSE, detail = "no script: entries parsed; cannot evaluate"))
  dup <- unique(sc[duplicated(sc)])

  # Duplicate IDS, not just duplicate scripts. Two agents working the same tree
  # each registered the same seven check ids, and every contract check passed
  # anyway, because nothing compared ids to each other. That is the defect this
  # half exists for.
  ids <- trimws(sub("^\\s*-\\s*id:\\s*", "", grep("^\\s*-\\s*id:", txt, value = TRUE)))
  dup_id <- unique(ids[duplicated(ids)])

  problems <- c(
    if (length(dup))    paste("script registered more than once:", paste(dup, collapse = ", ")),
    if (length(dup_id)) paste("check id declared more than once:", paste(dup_id, collapse = ", ")))
  structure(length(problems) == 0,
            detail = if (length(problems)) paste(problems, collapse = "; ")
                     else sprintf("%d scripts and %d ids registered, none twice",
                                  length(unique(sc)), length(unique(ids))))
})

# INCIDENT: the fixture builder pseudonymised RAW practice names before
# normalize_practice() collapsed spelling variants, splitting practices apart
# and destroying 34 of the fixture's complete triads. The fixture then certified
# a pipeline that could no longer see triads at all.
try_check("fixture/preserves-practice-structure", {
  fx <- file.path("tests", "fixtures", "LABUBU_DATA_LABELS_fixture.csv")
  pl <- "evaluate_labubu_mysterycall.R"
  if (!file.exists(fx) || !file.exists(pl))
    return(structure(FALSE, detail = "fixture or pipeline source absent"))
  src <- readLines(pl, warn = FALSE)
  take <- function(pat, fn) {
    i <- grep(pat, src)[1]
    j <- if (fn) i + which(src[(i + 1):length(src)] == "}")[1] else i
    paste(src[i:j], collapse = "\n")
  }
  env <- new.env()
  eval(parse(text = take("^PHONE_RE", FALSE)), envir = env)
  eval(parse(text = take("^redact_phone <- function", FALSE)), envir = env)
  eval(parse(text = take("^normalize_practice <- function", TRUE)), envir = env)

  f <- utils::read.csv(fx, stringsAsFactors = FALSE, check.names = FALSE)
  col <- grep("practice name", names(f), ignore.case = TRUE, value = TRUE)[1]
  sc  <- grep("^Scenario$", names(f), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(col) || is.na(sc))
    return(structure(FALSE, detail = "fixture lacks a practice-name or Scenario column"))
  key <- env$normalize_practice(f[[col]])
  tab <- table(key, f[[sc]])
  triads <- sum(rowSums(tab > 0) == 3)
  # The fixture exists to exercise the paired analysis. With no complete triad
  # it certifies nothing about the primary model.
  structure(triads > 0,
            detail = if (triads > 0)
              sprintf("fixture holds %d complete triads across %d practices",
                      triads, length(unique(key[!is.na(key)])))
            else "fixture has NO complete triads; pseudonymisation has split practices apart")
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
  lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
  lines <- enc2utf8(lines)

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
  groups <- regmatches(body, gregexpr("\\[[0-9]+(?:[,\u2013-][0-9]+)*\\]", body, perl = TRUE))[[1]]
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
