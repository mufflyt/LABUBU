library(mysterycall)

# Default export. refresh.R sets `input_file` before sourcing this script to
# point at the newest export; the guard lets it override this default.
if (!exists("input_file")) input_file <- "LABUBU_DATA_LABELS_2026-07-04_1551.csv"
out_dir    <- "mysterycall_outputs"
dir.create(out_dir, showWarnings = FALSE)

has_geepack <- requireNamespace("geepack", quietly = TRUE)

# ── Import ────────────────────────────────────────────────────────────────────
raw <- as.data.frame(
  readr::read_csv(input_file, show_col_types = FALSE,
                  locale = readr::locale(encoding = "UTF-8")),
  stringsAsFactors = FALSE
)

# ── Column name constants ─────────────────────────────────────────────────────
col_record    <- "Record ID"
col_scenario  <- "Scenario"
col_practice  <- "Physician Information, practice name"
col_contact   <- "Able to contact office on first call?"
col_attempts  <- "Number of attempts to contact"
col_call_date <- "Date and Time of FIRST Phone Call.  NB:  To call during business hours from 0800 to 1700 local time with exclusion of 1200 to 1300."
col_central   <- "Central number (e.g. appointment center)?"
col_transfers <- "Number of Transfers (phone call transferred from one person or answering service to the next)"
col_call_time <- "Call Time (in seconds, round to nearest whole second)"
col_hold_time <- "Hold Time (in seconds, round to nearest whole second)"
col_appt_date <- "Date of first available appointment."
col_reason    <- "Reason for exclusions"
col_wait_cat  <- "How long will it take for me to get scheduled?"
col_insurance <- "Does this practice accept Insurance?"
col_pregnancy <- "How long does it typically take for people to get pregnant?"
col_cost      <- "How much do these services typically cost?"
col_rei       <- "Do you refer to an REI if we aren't successful?"
col_donor     <- "Do you work with donor sperm?"
col_notes     <- "notes"
col_complete  <- "Complete?"

# ── Helper functions ──────────────────────────────────────────────────────────
parse_date <- function(x) {
  x <- trimws(x)
  x[x == ""] <- NA_character_
  as.Date(substr(x, 1, 10))
}

parse_number <- function(x) {
  x <- trimws(x)
  x[x == ""] <- NA_character_
  suppressWarnings(as.numeric(x))
}

parse_transfers <- function(x) {
  x0  <- trimws(tolower(x))
  out <- rep(NA_real_, length(x0))
  out[x0 %in% c("no transfers", "no transfer", "none", "0")] <- 0
  numeric_hit <- grepl("[0-9]+", x0)
  out[numeric_hit] <- suppressWarnings(
    as.numeric(sub(".*?([0-9]+).*", "\\1", x0[numeric_hit]))
  )
  out
}

checkbox <- function(x) trimws(x) == "Checked"


# Reshape long -> wide by scenario, one row per practice.
# Returns practice_id + one column per scenario level.
make_wide <- function(df, value_col,
                      scenarios = c("Straight couple", "Lesbian couple", "Single mother")) {
  ids  <- sort(unique(df$practice_id[!is.na(df$practice_id)]))
  wide <- data.frame(practice_id = ids)
  for (s in scenarios) {
    sub <- df[!is.na(df$scenario) & as.character(df$scenario) == s, ]
    col <- gsub(" ", "_", s)
    m   <- match(wide$practice_id, sub$practice_id)
    wide[[col]] <- sub[[value_col]][m]
  }
  wide
}

included_value <- "Included where physician was able to be contacted"

# ── Exclusion code mapping ────────────────────────────────────────────────────
# Maps LABUBU free-text exclusion reasons to the integer codes expected by
# mysterycall_prepare_calls() (0 = included; see package docs for full table).
exclusion_code_map <- c(
  "Included where physician was able to be contacted"               = 0L,
  "Closed medical system (e.g. Kaiser or military hospital)"        = 1L,
  "Greater than 5 minutes on hold"                                  = 2L,
  "Number contacted did not correspond to expected office/specialty" = 3L,
  "Phone not answered or busy signal on repeat calls"               = 5L,
  "Physician's personal phone"                                      = 6L,
  "Went to voicemail"                                               = 8L,
  "Not accepting new patients"                                      = 9L
)

# ── Build analysis data frame ─────────────────────────────────────────────────
dat <- data.frame(
  record_id              = raw[[col_record]],
  scenario               = trimws(raw[[col_scenario]]),
  practice               = trimws(raw[[col_practice]]),
  contact_first_call     = trimws(raw[[col_contact]]),
  attempts               = trimws(raw[[col_attempts]]),
  call_date              = parse_date(raw[[col_call_date]]),
  central_number         = trimws(raw[[col_central]]),
  transfers_n            = parse_transfers(raw[[col_transfers]]),
  call_time_sec          = parse_number(raw[[col_call_time]]),
  hold_time_sec          = parse_number(raw[[col_hold_time]]),
  first_appt_date        = parse_date(raw[[col_appt_date]]),
  exclusion_reason       = trimws(raw[[col_reason]]),
  wait_category          = trimws(raw[[col_wait_cat]]),
  insurance              = trimws(raw[[col_insurance]]),
  pregnancy_time         = trimws(raw[[col_pregnancy]]),
  cost_estimate          = trimws(raw[[col_cost]]),
  refer_rei              = trimws(raw[[col_rei]]),
  donor_sperm            = trimws(raw[[col_donor]]),
  complete               = trimws(raw[[col_complete]]),
  service_cycle_tracking      = checkbox(raw[["What type of services do you typically offer? (choice=cycle tracking)"]]),
  service_hormonal_timing     = checkbox(raw[["What type of services do you typically offer? (choice=hormonal labs and fertility timing)"]]),
  service_ovulation_induction = checkbox(raw[["What type of services do you typically offer? (choice=ovulation induction)"]]),
  service_iui                 = checkbox(raw[["What type of services do you typically offer? (choice=Intrauterine insemination)"]]),
  service_ivf                 = checkbox(raw[["What type of services do you typically offer? (choice=In vitro fertilization)"]]),
  restrict_lesbian       = checkbox(raw[["Are there any restrictions to the individuals you would provide care to?  (choice=Lesbian couple)"]]),
  restrict_straight      = checkbox(raw[["Are there any restrictions to the individuals you would provide care to?  (choice=Straight couple)"]]),
  restrict_single_mother = checkbox(raw[["Are there any restrictions to the individuals you would provide care to?  (choice=Single mother)"]]),
  notes_present          = !is.na(raw[[col_notes]]) & trimws(raw[[col_notes]]) != "",
  stringsAsFactors       = FALSE
)

# ── Derived variables ─────────────────────────────────────────────────────────
dat$scenario[dat$scenario == ""] <- NA_character_
dat$exclusion_code     <- exclusion_code_map[dat$exclusion_reason]
dat$analytic_inclusion <- !is.na(dat$exclusion_reason) & dat$exclusion_reason == included_value
dat$form_finalized     <- !is.na(dat$complete) & dat$complete == "Complete"
dat$contact_office     <- dat$analytic_inclusion
dat$wait_days          <- as.numeric(dat$first_appt_date - dat$call_date)
# Business days (Mon–Fri, excluding US federal holidays) via the package helper.
# Falls back to calendar days if bizdays is not installed.
dat <- tryCatch(
  mysterycall_business_days(
    dat,
    call_col   = "call_date",
    appt_col   = "first_appt_date",
    result_col = "business_days"
  ),
  error = function(e) { dat$business_days <- dat$wait_days; dat }
)
dat$first_appt_missing <- is.na(dat$first_appt_date)
dat$insurance_accepts  <- !is.na(dat$insurance) & dat$insurance == "Yes they accept insurance"
dat$blue_cross_bcbs_response <- dat$insurance
dat$cost_provided      <- !is.na(dat$cost_estimate) & dat$cost_estimate != "" &
                          !grepl("unable", dat$cost_estimate, ignore.case = TRUE)
dat$pregnancy_answered <- !(is.na(dat$pregnancy_time) | dat$pregnancy_time %in% c("", "Unable to answer"))
dat$donor_sperm_yes    <- !is.na(dat$donor_sperm) & dat$donor_sperm == "yes"
dat$scenario           <- factor(dat$scenario,
                                 levels = c("Straight couple", "Lesbian couple", "Single mother"))

# ── Practice matching ─────────────────────────────────────────────────────────
# Normalise practice name so minor entry variants collapse to one canonical key:
#   1. strip trailing call-list number  (" 37", ", 95", etc.)
#   2. fix known typos that can't easily be corrected in REDCap
normalize_practice <- function(x) {
  x <- trimws(x)
  x <- sub(",?\\s+\\d+$", "", x)                          # trailing call-list number
  x <- gsub("Costal FertilityCare", "Coastal FertilityCare", x)  # Lisa Cote typo
  # Records entered as center name only — expand to practitioner canonical form
  x <- sub("^Coastal FertilityCare \\(NH\\)$",
           "Lisa Cote, FCP Coastal FertilityCare (NH)", x)
  x <- sub("^Bluebonnet FertilityCare \\(TX\\)$",
           "Stephanie Gavin BSN, RN, FCP (Bluebonnet FertilityCare TX)", x)
  x <- sub("^Boudreau, MD \\(MA\\).*$",
           "Nicole Boudreau, MD (MA)", x)
  # Patrick Beeman straight record omits practice name
  x <- sub("^(Patrick Beeman, MD) \\(OH\\)$",
           "\\1 Veranova Health (OH)", x)
  # Mary Anderson single-mother record uses full address instead of city/state
  x <- sub("^Mary Anderson, MD,? Vieux Care.*$",
           "Mary Anderson, MD (LA, CA)", x)
  # Michelle Chambers: lesbian record has extra parens around center name
  x <- sub("^(Michelle Chambers, FCP) \\(Creighton", "\\1 Creighton", x)
  x <- sub("LLC NE\\)$", "LLC (NE)", x)
  # Stephanie Gavin: comma placement differs across records
  x <- sub("^Stephanie Gavin, BSN, RN FCP",
           "Stephanie Gavin BSN, RN, FCP", x)
  # Wendy Imm: missing comma after name
  x <- sub("^Wendy Imm RN,", "Wendy Imm, RN,", x)
  # Edward J. Fleming: period in middle initial
  x <- sub("Edward J\\. Fleming", "Edward J Fleming", x)
  # Nicholas Kongoasa: missing comma between MD and FACOG
  x <- sub("Kongoasa, MD FACOG", "Kongoasa, MD, FACOG", x)
  # FertilityCare Center of Colorado Springs state tag
  x <- sub("^FertilityCare Center of Colorado Springs$", "FertilityCare Center of Colorado Springs (CO)", x)
  trimws(x)
}

dat$practice_key <- ifelse(
  is.na(dat$practice) | dat$practice == "",
  NA_character_,
  normalize_practice(dat$practice)
)
practice_levels <- sort(unique(dat$practice_key[!is.na(dat$practice_key) & dat$practice_key != ""]))
dat$practice_id <- match(dat$practice_key, practice_levels)

# Per-practice scenario coverage
cov_raw <- tapply(as.character(dat$scenario), dat$practice_id, function(x) {
  x <- x[!is.na(x)]
  c(has_straight = "Straight couple" %in% x,
    has_lesbian  = "Lesbian couple"  %in% x,
    has_sm       = "Single mother"   %in% x)
}, simplify = FALSE)

coverage_df <- data.frame(
  practice_id  = as.integer(names(cov_raw)),
  practice_key = practice_levels[as.integer(names(cov_raw))],
  has_straight = sapply(cov_raw, `[`, "has_straight"),
  has_lesbian  = sapply(cov_raw, `[`, "has_lesbian"),
  has_sm       = sapply(cov_raw, `[`, "has_sm"),
  stringsAsFactors = FALSE
)
coverage_df$n_scenarios <- with(coverage_df, has_straight + has_lesbian + has_sm)

n_practices        <- nrow(coverage_df)
n_complete_triads  <- sum(coverage_df$n_scenarios == 3)
n_dyads            <- sum(coverage_df$n_scenarios == 2)
n_singletons       <- sum(coverage_df$n_scenarios == 1)
n_missing_straight <- sum(!coverage_df$has_straight)
n_missing_lesbian  <- sum(!coverage_df$has_lesbian)
n_missing_sm       <- sum(!coverage_df$has_sm)

# ── Practice-name normalization safety net ────────────────────────────────────
# New exports bring new practices and spelling variants; an unmatched variant
# silently becomes a singleton and deflates the triad count. Surface (a) pairs of
# practice keys that are near-duplicates (likely the same practice mis-typed) and
# (b) all singleton practices, so mismatches are loud instead of silent.
name_near_dupes <- local({
  keys <- practice_levels
  n    <- length(keys)
  hits <- list()
  if (n >= 2) {
    dm <- adist(keys)
    for (i in seq_len(n - 1)) for (j in (i + 1):n) {
      d  <- dm[i, j]
      nd <- d / max(nchar(keys[i]), nchar(keys[j]))
      if (d <= 4 || nd <= 0.15)
        hits[[length(hits) + 1]] <- data.frame(
          key_a = keys[i], key_b = keys[j],
          edit_distance = d, norm_distance = round(nd, 3),
          stringsAsFactors = FALSE)
    }
  }
  if (length(hits)) do.call(rbind, hits)
  else data.frame(key_a = character(), key_b = character(),
                  edit_distance = integer(), norm_distance = numeric())
})
singleton_practices <- coverage_df[coverage_df$n_scenarios == 1,
  c("practice_id", "practice_key", "has_straight", "has_lesbian", "has_sm")]
write.csv(name_near_dupes,     file.path(out_dir, "practice_name_review_nearduplicates.csv"), row.names = FALSE)
write.csv(singleton_practices, file.path(out_dir, "practice_name_review_singletons.csv"),     row.names = FALSE)
if (nrow(name_near_dupes) > 0)
  message("SAFETY NET: ", nrow(name_near_dupes),
          " near-duplicate practice-name pair(s) found. Review ",
          "mysterycall_outputs/practice_name_review_nearduplicates.csv; if any are the ",
          "same practice, add a rule to normalize_practice() so their calls collapse into one triad.")

# ── Analytic subsets ──────────────────────────────────────────────────────────
included          <- dat[dat$analytic_inclusion, ]
included_complete <- dat[dat$analytic_inclusion & dat$form_finalized, ]

# ── Required columns for completeness check ───────────────────────────────────
required_cols <- c(
  "record_id", "scenario", "practice", "contact_first_call", "attempts",
  "call_date", "exclusion_reason", "wait_category",
  "insurance", "pregnancy_time", "cost_estimate", "refer_rei", "donor_sperm"
)

# ── Unmatched descriptive analyses (preliminary — independent groups) ──────────
completeness <- mysterycall_check_data_completeness(
  dat, required = required_cols, id_cols = "record_id"
)

quality <- mysterycall_assess_data_quality(
  dat,
  required_columns = c("record_id", "scenario", "practice", "exclusion_reason", "complete")
)

acceptance_all <- mysterycall_acceptance_rate(
  dat[!is.na(dat$scenario), ],
  accepted_col = "contact_office",
  group_by     = "scenario"
)

acceptance_finalized <- mysterycall_acceptance_rate(
  dat[dat$analytic_inclusion & dat$form_finalized & !is.na(dat$scenario), ],
  accepted_col = "contact_office",
  group_by     = "scenario"
)

wait_included          <- mysterycall_wait_time_summary(included,          wait_col = "wait_days", group_by = "scenario")
wait_included_complete <- mysterycall_wait_time_summary(included_complete, wait_col = "wait_days", group_by = "scenario")

missing_appt <- mysterycall_missing_data_analysis(
  included_complete,
  outcome_col    = "first_appt_date",
  group_col      = "scenario",
  covariate_cols = c("contact_first_call", "attempts", "insurance", "cost_estimate")
)

table1 <- mysterycall_table1(
  included_complete,
  covariates = c(
    "contact_first_call", "attempts", "call_time_sec", "hold_time_sec",
    "wait_days", "insurance", "cost_estimate", "pregnancy_time", "refer_rei",
    "donor_sperm", "service_cycle_tracking", "service_hormonal_timing",
    "service_ovulation_induction", "service_iui", "service_ivf",
    "restrict_lesbian", "restrict_straight", "restrict_single_mother"
  ),
  stratify_by     = "scenario",
  include_overall = TRUE
)

scenario_counts <- as.data.frame.matrix(table(dat$scenario, dat$complete, useNA = "ifany"))
scenario_counts$scenario <- rownames(scenario_counts)
rownames(scenario_counts) <- NULL
scenario_counts <- scenario_counts[, c("scenario", setdiff(names(scenario_counts), "scenario"))]

inclusion_counts <- aggregate(
  cbind(n = rep(1, nrow(dat)), included = dat$analytic_inclusion, finalized = dat$form_finalized) ~ scenario,
  data      = dat,
  FUN       = sum,
  na.action = na.pass
)

fmt_p <- function(p) if (is.na(p)) "NA" else if (p < 0.001) "< 0.001" else signif(p, 3)

# Complete triad practice IDs (for unconfounded paired GLMER)
triad_practice_ids <- coverage_df$practice_id[coverage_df$n_scenarios == 3]

glmer_acceptance <- tryCatch(
  mysterycall_logistic_model(
    data             = dat[!is.na(dat$practice_id) & !is.na(dat$scenario), ],
    outcome          = "contact_office",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

# Unconfounded GLMER (restricted to practices with all 3 scenarios complete)
glmer_acceptance_triads <- tryCatch(
  mysterycall_logistic_model(
    data             = dat[!is.na(dat$practice_id) & dat$practice_id %in% triad_practice_ids & !is.na(dat$scenario), ],
    outcome          = "contact_office",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

# ── Secondary analysis: mysterycall_lmm() ────────────────────────────────────
# Linear mixed model for wait time (days); same random-intercept structure.
lmer_wait <- tryCatch(
  mysterycall_lmm(
    data             = dat[!is.na(dat$business_days) & !is.na(dat$practice_id) & !is.na(dat$scenario), ],
    outcome          = "business_days",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_lmm_error")
)

# ── Helpers to format package model results for the report ────────────────────
fmt_glmer_result <- function(res) {
  if (inherits(res, "mysterycall_logistic_model_error"))
    return(list(ok = FALSE, text = res$error, note = "", n = 0L))

  ot <- as.data.frame(res$or_table)
  ot_fmt <- data.frame(
    Term    = ot$term,
    OR      = round(ot$or,       3),
    CI_lo   = round(ot$ci_lower, 3),
    CI_hi   = round(ot$ci_upper, 3),
    p       = ot$p_value_fmt,
    stringsAsFactors = FALSE
  )

  re_var    <- res$random_effects$vcov[1]
  conv      <- res$convergence
  sep_terms <- ot$term[abs(ot$estimate) > 10]
  sep_note  <- if (length(sep_terms) > 0)
    paste0("WARNING: complete separation for: ", paste(sep_terms, collapse = ", "),
           ". OR not interpretable; consider Firth penalized regression.")
  else ""

  list(
    ok   = TRUE,
    text = paste(capture.output(print(ot_fmt, row.names = FALSE)), collapse = "\n"),
    note = paste0(
      "mysterycall_logistic_model() [lme4::glmer]. ",
      "Reference: Straight couple. OR < 1 = lower odds of appointment offer. ",
      "n = ", res$n, " records across ", res$n_clusters, " practices. ",
      "Practice random-intercept variance: ", round(re_var, 3), ". ",
      if (!conv$converged) "WARNING: convergence issue — interpret cautiously. " else "",
      if (conv$singular)   "NOTE: singular fit (random-effect variance ~0). " else "",
      sep_note
    ),
    n = res$n
  )
}

fmt_lmm_result <- function(res) {
  if (inherits(res, "mysterycall_lmm_error"))
    return(list(ok = FALSE, text = res$error, note = "", n = 0L))

  ct <- as.data.frame(res$coef_table)
  ct_fmt <- data.frame(
    Term               = ct$term,
    Est_business_days  = round(ct$estimate,  1),
    CI_lo              = round(ct$ci_lower,  1),
    CI_hi              = round(ct$ci_upper,  1),
    p                  = ct$p_value_fmt,
    stringsAsFactors   = FALSE
  )

  sw_p      <- res$normality$p_value
  sw_str    <- fmt_p(sw_p)
  norm_flag <- if (!is.na(sw_p) && sw_p < 0.05)
    paste0("NORMALITY CAVEAT: Shapiro-Wilk p = ", sw_str,
           " — residuals are right-skewed (expected for wait-time data). ",
           "LMM point estimates remain unbiased but 95% CIs may be slightly ",
           "anti-conservative with this sample size. A Poisson/negative-binomial ",
           "GLMM sensitivity analysis is recommended to confirm inference.")
  else
    paste0("Shapiro-Wilk on residuals: p = ", sw_str, " (normality satisfied).")

  list(
    ok   = TRUE,
    text = paste(capture.output(print(ct_fmt, row.names = FALSE)), collapse = "\n"),
    note = paste0(
      "mysterycall_lmm() [lme4::lmer]. Outcome: business days until appointment ",
      "(Mon-Fri, excluding US federal holidays). ",
      "Estimates are mean difference in business days vs. Straight couple (reference); ",
      "negative = shorter wait. ",
      "n = ", res$n, " records with observed appointment date. ",
      norm_flag, " ",
      "Marginal R² = ", round(res$r_squared$marginal, 3), ", ",
      "Conditional R² = ", round(res$r_squared$conditional, 3), "."
    ),
    n = res$n
  )
}

glmer_fmt        <- fmt_glmer_result(glmer_acceptance)
glmer_fmt_triads <- fmt_glmer_result(glmer_acceptance_triads)
lmm_fmt          <- fmt_lmm_result(lmer_wait)

# ── Sensitivity analysis: GEE ─────────────────────────────────────────────────
# Population-average model (vs. the subject-specific glmer). Uses all records
# including singletons and dyads; exchangeable correlation within practice.
wide_acc  <- make_wide(dat, "contact_office")
wide_wait <- make_wide(dat, "wait_days")

gee_output <- tryCatch({
  if (!has_geepack) stop("geepack not installed; run install.packages('geepack')")
  dat_gee          <- dat[!is.na(dat$practice_id) & !is.na(dat$scenario), ]
  dat_gee          <- dat_gee[order(dat_gee$practice_id), ]
  dat_gee$scenario <- relevel(dat_gee$scenario, ref = "Straight couple")
  fit <- geepack::geeglm(
    as.integer(contact_office) ~ scenario,
    data   = dat_gee,
    family = binomial(link = "logit"),
    id     = practice_id,
    corstr = "exchangeable"
  )
  s    <- summary(fit)
  coef <- s$coefficients
  separated <- rownames(coef)[abs(coef[, "Estimate"]) > 10]
  sep_note  <- if (length(separated) > 0)
    paste0("WARNING: complete separation for: ", paste(separated, collapse = ", "), ".")
  else ""
  list(ok   = TRUE,
       text = paste(capture.output(print(coef)), collapse = "\n"),
       note = paste0("GEE (sensitivity). Coefficients are log-ORs vs. Straight couple. ", sep_note))
}, error = function(e) {
  list(ok = FALSE, text = conditionMessage(e), note = "")
})

# ── Within-practice PAIRED analyses (the matched, unconfounded comparison) ────
# Rationale: the unmatched chi-square is confounded because the three scenarios
# were NOT called at the same set of practices (single-mother calls landed
# disproportionately at high-acceptance practices). A within-practice comparison
# removes each practice's baseline generosity. Only practices called for BOTH
# scenarios contribute, and for the binary outcome only DISCORDANT practices
# (different answer to the two callers) carry any information about a scenario
# effect — so effective n is the discordant count, not the paired count.
paired_contrasts <- list(
  c("Straight_couple", "Single_mother"),
  c("Lesbian_couple",  "Single_mother"),
  c("Straight_couple", "Lesbian_couple")
)

# Exact-McNemar minimum detectable effect: smallest one-way discordant split
# (expressed as an odds ratio) that yields 80% power at alpha = 0.05.
mcnemar_mde_or <- function(n_d) {
  if (is.na(n_d) || n_d < 1) return(NA_real_)
  crit <- qbinom(0.025, n_d, 0.5)
  for (psi in seq(0.50, 0.99, 0.01)) {
    k   <- 0:n_d
    rej <- (k <= crit) | (k >= n_d - crit)
    if (sum(dbinom(k[rej], n_d, psi)) >= 0.80) return(psi / (1 - psi))
  }
  NA_real_
}

paired_acc_df <- do.call(rbind, lapply(paired_contrasts, function(cc) {
  a <- wide_acc[[cc[1]]]; b <- wide_acc[[cc[2]]]
  ok <- !is.na(a) & !is.na(b); a <- a[ok]; b <- b[ok]
  yn <- sum(a & !b); ny <- sum(!a & b); disc <- yn + ny
  data.frame(
    contrast       = paste(gsub("_", " ", cc), collapse = " vs "),
    n_paired       = length(a),
    concordant     = sum(a == b),
    discordant     = disc,
    disc_favor_A   = yn,   # yes to 1st scenario, no to 2nd
    disc_favor_B   = ny,   # no to 1st scenario, yes to 2nd
    mcnemar_p      = if (disc > 0) round(binom.test(min(yn, ny), disc)$p.value, 3) else NA_real_,
    mde_or_80power = round(mcnemar_mde_or(disc), 1),
    stringsAsFactors = FALSE
  )
}))

paired_wait_df <- do.call(rbind, lapply(paired_contrasts, function(cc) {
  a <- wide_wait[[cc[1]]]; b <- wide_wait[[cc[2]]]
  ok <- !is.na(a) & !is.na(b); a <- a[ok]; b <- b[ok]; d <- a - b
  n <- length(d)
  data.frame(
    contrast        = paste(gsub("_", " ", cc), collapse = " vs "),
    n_paired        = n,
    mean_diff_days  = if (n >= 1) round(mean(d), 1) else NA_real_,
    sd_diff         = if (n >= 2) round(sd(d), 1) else NA_real_,
    paired_t_p      = if (n >= 3) round(tryCatch(t.test(a, b, paired = TRUE)$p.value, error = function(e) NA_real_), 3) else NA_real_,
    wilcoxon_p      = if (n >= 3) round(suppressWarnings(tryCatch(wilcox.test(a, b, paired = TRUE)$p.value, error = function(e) NA_real_)), 3) else NA_real_,
    mde_days_80power= if (n >= 3 && sd(d) > 0) round(tryCatch(power.t.test(n = n, sd = sd(d), power = 0.80, type = "paired")$delta, error = function(e) NA_real_), 1) else NA_real_,
    stringsAsFactors = FALSE
  )
}))

# ── Write output CSVs ─────────────────────────────────────────────────────────
write.csv(dat,                          file.path(out_dir, "labubu_cleaned_analysis.csv"),                                 row.names = FALSE)
write.csv(paired_acc_df,                file.path(out_dir, "mysterycall_paired_acceptance_mcnemar.csv"),                   row.names = FALSE)
write.csv(paired_wait_df,               file.path(out_dir, "mysterycall_paired_wait_within_practice.csv"),                 row.names = FALSE)
write.csv(completeness$summary,         file.path(out_dir, "mysterycall_completeness.csv"),                               row.names = FALSE)
write.csv(acceptance_all$summary,       file.path(out_dir, "mysterycall_acceptance_by_scenario_all_records.csv"),         row.names = FALSE)
write.csv(acceptance_finalized$summary, file.path(out_dir, "mysterycall_acceptance_by_scenario_finalized_records.csv"),   row.names = FALSE)
write.csv(wait_included$summary,        file.path(out_dir, "mysterycall_wait_by_scenario_included.csv"),                  row.names = FALSE)
write.csv(wait_included_complete$summary, file.path(out_dir, "mysterycall_wait_by_scenario_included_complete.csv"),       row.names = FALSE)
write.csv(missing_appt$summary,         file.path(out_dir, "mysterycall_missing_appt_summary.csv"),                       row.names = FALSE)
write.csv(table1$table,                 file.path(out_dir, "mysterycall_table1_included_complete.csv"),                   row.names = FALSE)
write.csv(scenario_counts,              file.path(out_dir, "scenario_counts_by_completion.csv"),                          row.names = FALSE)
write.csv(inclusion_counts,             file.path(out_dir, "scenario_counts_by_inclusion.csv"),                           row.names = FALSE)
write.csv(coverage_df,                  file.path(out_dir, "practice_scenario_coverage.csv"),                             row.names = FALSE)
write.csv(wide_acc,                     file.path(out_dir, "matched_acceptance_wide.csv"),                                row.names = FALSE)
write.csv(wide_wait,                    file.path(out_dir, "matched_wait_wide.csv"),                                      row.names = FALSE)

# ── Issue IDs ─────────────────────────────────────────────────────────────────
issue_ids <- list(
  missing_scenario                    = dat$record_id[is.na(dat$scenario)],
  included_incomplete                 = dat$record_id[dat$analytic_inclusion & !dat$form_finalized],
  complete_excluded                   = dat$record_id[dat$form_finalized & !is.na(dat$exclusion_reason) &
                                                       dat$exclusion_reason != "" & !dat$analytic_inclusion],
  included_complete_missing_call_time = dat$record_id[dat$analytic_inclusion & dat$form_finalized & is.na(dat$call_time_sec)],
  included_complete_missing_appt_date = dat$record_id[dat$analytic_inclusion & dat$form_finalized & is.na(dat$first_appt_date)],
  negative_wait_days                  = dat$record_id[!is.na(dat$wait_days) & dat$wait_days < 0],
  wait_days_gt_180                    = dat$record_id[!is.na(dat$wait_days) & dat$wait_days > 180]
)

capture <- function(x) paste(capture.output(print(x)), collapse = "\n")

# ── Report ────────────────────────────────────────────────────────────────────

report <- c(
  "# LABUBU Mysterycall Evaluation",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Package",
  "",
  paste0("- mysterycall version: ", as.character(packageVersion("mysterycall"))),
  "",
  "## Denominators",
  "",
  paste0("- All records: ", nrow(dat)),
  paste0("- Analytic inclusion (exclusion field): ", nrow(included)),
  paste0("- Analytic inclusion AND finalized form: ", nrow(included_complete)),
  "",
  "## Data Quality",
  "",
  paste0("- Completeness quality tier: ", completeness$quality),
  paste0("- Completeness score: ", round(completeness$score, 3)),
  paste0("- General quality score: ", round(quality$score, 3)),
  "",

  # ── Data collection status ──────────────────────────────────────────────────
  "## Data Collection Status",
  "",
  paste0("Study design: each RRM practice called once per scenario (straight couple, ",
         "lesbian couple, single mother using donor sperm). Primary analysis: ",
         "mixed-effects logistic regression with practice random intercept (lme4::glmer). ",
         "Note: REI comparison arm removed from scope; analysis is within-RRM only."),
  "",
  paste0("- Total unique practices: ", n_practices),
  paste0("- Complete triads (all 3 scenarios): ", n_complete_triads),
  paste0("- Dyads (2 of 3 scenarios): ", n_dyads),
  paste0("- Singletons (1 scenario only): ", n_singletons),
  "",
  "Missing calls by scenario:",
  paste0("  - Missing straight-couple call: ", n_missing_straight, " practices"),
  paste0("  - Missing lesbian-couple call:  ", n_missing_lesbian,  " practices"),
  paste0("  - Missing single-mother call:   ", n_missing_sm,       " practices"),
  "",

  # ── Unmatched acceptance (descriptive) ──────────────────────────────────────
  "## Acceptance Rate by Scenario — Descriptive (unmatched)",
  "",
  "`accepted` = analytic inclusion flag (practice successfully scheduled the caller).",
  "",
  "```",
  capture(acceptance_all$summary),
  "```",
  "",
  paste0("- Chi-square (independent groups, descriptive only): ",
         acceptance_all$test_name, "; p = ", fmt_p(acceptance_all$p_value)),
  "",
  paste0("> **CONFOUNDING CAUTION — do not report this chi-square as a result.** ",
         "The three scenarios were not called at the same practices: single-mother ",
         "calls landed disproportionately at high-acceptance practices (practices ",
         "that received a single-mother call accept ~70% of *all* callers vs ~14% ",
         "at practices that did not). The marginal rate therefore reflects *which ",
         "practices were dialed*, not how callers were treated. Use the within-",
         "practice paired analysis below."),
  "",

  # ── MATCHED: within-practice paired acceptance (McNemar) ─────────────────────
  "## MATCHED ANALYSIS — Within-Practice Paired Acceptance (exact McNemar)",
  "",
  paste0("Each contrast uses only practices called for BOTH scenarios; only ",
         "DISCORDANT practices (different answer to the two callers) carry ",
         "information, so effective n = the discordant count. Concordant practices ",
         "(same answer to both) are the substantive majority — most practices do ",
         "not differentiate — but contribute nothing to the test."),
  "",
  "```",
  capture(paired_acc_df),
  "```",
  "",
  paste0("**Power / precision:** discordant practices number only ",
         paste(paired_acc_df$discordant, collapse = ", "),
         " across the three contrasts. At 80% power (alpha 0.05, exact McNemar) the ",
         "smallest detectable effect is an odds ratio of roughly ",
         paste(paired_acc_df$mde_or_80power, collapse = "/"),
         ". Plausible audit-study effects (OR ~1.5-2.5) are well below this floor: ",
         "the matched data can rule out a LARGE differential but is underpowered for ",
         "small-to-moderate effects. Report as estimation with this precision ",
         "statement, not as a null hypothesis test."),
  "",

  # ── PRIMARY: GLMER ──────────────────────────────────────────────────────────
  "## PRIMARY ANALYSIS — Mixed-Effects Logistic Regression (glmer)",
  "",
  paste0("Protocol-specified analysis via mysterycall_logistic_model(). ",
         "Random intercept for practice accounts for within-practice correlation ",
         "across the scenario calls."),
  "",
  "### Unconfounded Model — Complete Practice Triads Only (n = ", glmer_fmt_triads$n, " records)",
  "Restricted to practices called for ALL 3 scenarios to eliminate practice-selection dialing bias.",
  "",
  if (glmer_fmt_triads$ok) {
    c("```", glmer_fmt_triads$text, "```", "", paste0("Note: ", glmer_fmt_triads$note))
  } else {
    paste0("glmer triads not run: ", glmer_fmt_triads$text)
  },
  "",
  "### Full-Sample Model — All Records (n = ", glmer_fmt$n, " records)",
  "> **CONFOUNDING WARNING:** Includes unbalanced singletons/dyads. Single-mother calls landed ",
  "> disproportionately at high-acceptance practices, causing this full-sample GLMER to reflect ",
  "> practice selection rather than scenario effects. Use the complete-triads model above.",
  "",
  if (glmer_fmt$ok) {
    c("```", glmer_fmt$text, "```", "", paste0("Note: ", glmer_fmt$note))
  } else {
    paste0("glmer not run: ", glmer_fmt$text)
  },
  "",

  # ── SECONDARY: LMM wait time ────────────────────────────────────────────────
  "## SECONDARY ANALYSIS — Mixed-Effects Linear Model for Wait Time in Business Days (lmm)",
  "",
  paste0("Via mysterycall_lmm(). Outcome: business days (Mon–Fri, US federal holidays excluded). ",
         "Estimates report the mean difference in business days relative to straight-couple callers ",
         "(reference). n = ", lmm_fmt$n, " records with an observed appointment date. ",
         "Note: wait-time distributions are typically right-skewed; ",
         "see normality caveat in the model note below."),
  "",
  if (lmm_fmt$ok) {
    c("```", lmm_fmt$text, "```", "", paste0("Note: ", lmm_fmt$note))
  } else {
    paste0("lmm not run: ", lmm_fmt$text)
  },
  "",

  # ── Wait time descriptive ────────────────────────────────────────────────────
  "## Wait Time by Scenario — Descriptive (unmatched)",
  "",
  "```",
  capture(wait_included$summary),
  "```",
  "",
  paste0("- Unmatched test (descriptive only): ", wait_included$test_name,
         "; p = ", fmt_p(wait_included$p_value)),
  "",

  # ── MATCHED: within-practice paired wait time ────────────────────────────────
  "## MATCHED ANALYSIS — Within-Practice Paired Wait Time (paired t / Wilcoxon)",
  "",
  paste0("Practices with an observed appointment date for BOTH scenarios. ",
         "Even scarcer than the acceptance pairs because most included calls lack ",
         "an appointment date (~40% missing)."),
  "",
  "```",
  capture(paired_wait_df),
  "```",
  "",
  paste0("**Power / precision:** only ",
         paste(paired_wait_df$n_paired, collapse = ", "),
         " practices have both dates. The minimum detectable mean difference at ",
         "80% power is ~",
         paste(paired_wait_df$mde_days_80power, collapse = "/"),
         " business days — far larger than any clinically meaningful gap. The ",
         "paired wait-time comparison is the least-powered analysis in the study ",
         "and should be reported as descriptive only."),
  "",

  # ── SENSITIVITY: GEE ────────────────────────────────────────────────────────
  "## SENSITIVITY ANALYSIS — GEE (exchangeable correlation, logit link)",
  "",
  paste0("Population-average model; uses all records including singletons and dyads. ",
         "Complements glmer (which is subject-specific/conditional). ",
         "Exchangeable correlation within practice."),
  "",
  if (gee_output$ok) {
    c("```", gee_output$text, "```", "", paste0("Note: ", gee_output$note))
  } else {
    paste0("GEE not run: ", gee_output$text)
  },
  "",

  # ── Missing data ─────────────────────────────────────────────────────────────
  "## Missing Appointment Date Analysis",
  "",
  "```",
  capture(missing_appt$summary),
  "```",
  "",
  missing_appt$interpretation,
  "",

  # ── Record IDs for review ────────────────────────────────────────────────────
  "## Key Record IDs for Manual Review",
  "",
  paste0("- Missing scenario: ",                         paste(issue_ids$missing_scenario,                    collapse = ", ")),
  paste0("- Included but incomplete: ",                  paste(issue_ids$included_incomplete,                 collapse = ", ")),
  paste0("- Complete but excluded: ",                    paste(issue_ids$complete_excluded,                   collapse = ", ")),
  paste0("- Included/finalized but missing call time: ", paste(issue_ids$included_complete_missing_call_time, collapse = ", ")),
  paste0("- Included/finalized but missing appt date: ", paste(issue_ids$included_complete_missing_appt_date, collapse = ", ")),
  paste0("- Negative wait days: ",                       paste(issue_ids$negative_wait_days,                  collapse = ", ")),
  paste0("- Wait days > 180: ",                          paste(issue_ids$wait_days_gt_180,                    collapse = ", ")),
  "",

  # ── Output files ─────────────────────────────────────────────────────────────
  "## Output Files",
  "",
  "- `labubu_cleaned_analysis.csv`",
  "- `mysterycall_paired_acceptance_mcnemar.csv`",
  "- `mysterycall_paired_wait_within_practice.csv`",
  "- `practice_name_review_nearduplicates.csv`",
  "- `practice_name_review_singletons.csv`",
  "- `mysterycall_completeness.csv`",
  "- `mysterycall_acceptance_by_scenario_all_records.csv`",
  "- `mysterycall_acceptance_by_scenario_finalized_records.csv`",
  "- `mysterycall_wait_by_scenario_included.csv`",
  "- `mysterycall_wait_by_scenario_included_complete.csv`",
  "- `mysterycall_missing_appt_summary.csv`",
  "- `mysterycall_table1_included_complete.csv`",
  "- `scenario_counts_by_completion.csv`",
  "- `scenario_counts_by_inclusion.csv`",
  "- `practice_scenario_coverage.csv`",
  "- `matched_acceptance_wide.csv`",
  "- `matched_wait_wide.csv`"
)

writeLines(report, file.path(out_dir, "mysterycall_evaluation.md"))
cat(paste(report, collapse = "\n"))
