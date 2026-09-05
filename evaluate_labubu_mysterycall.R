library(mysterycall)

# Several tests in the pipeline are Monte Carlo (Fisher exact with
# simulate.p.value, Freeman-Halton). Unseeded they return a slightly different
# p on every run, which made the nightly report drift when nothing had changed.
# Seed once here so a rerun on identical data is bit-identical.
set.seed(20260904L)

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
col_completer <- "Name of person completing form.  THANK YOU!"
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

# REDCap encodes checkbox fields differently depending on the export route,
# and the two are not interchangeable:
#
#   browser "labels" export : "Checked" / "Unchecked"
#   API export (label mode) : the option's own label when ticked, "" when not
#                             e.g. "cycle tracking" / ""
#
# Matching only "Checked" silently turned every service and restriction
# variable FALSE the first time the pipeline ran against an API pull, which
# zeroed the study's headline result (cycle tracking 95%) without any error.
# Treat anything non-empty that is not an explicit negative as ticked.
checkbox <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x)] <- ""
  nzchar(x) & !(x %in% c("Unchecked", "0", "FALSE", "No"))
}


# Reshape long -> wide by scenario, one row per practice.
#
# SELECTING A CALL WHEN A PRACTICE-SCENARIO CELL HOLDS MORE THAN ONE
#
# The design is one call per practice per scenario, but eight cells hold two.
# This previously resolved with match(), which returns the FIRST matching row --
# an undocumented software accident, not a methodology, and one that could let
# a voicemail outrank the completed call that followed it.
#
# PI decision (2026-09-05, docs/OPEN-DECISIONS.md):
#
#   Shape A -- a failed attempt followed by a successful call. Voicemail, wrong
#     numbers and abandoned/over-long holds are contact ATTEMPTS, not completed
#     mystery calls. Use the first protocol-valid completed contact; keep the
#     failed attempts in the call-level data as audit trail.
#
#   Shape B -- two protocol-valid completed calls. A protocol deviation. The
#     cell is EXCLUDED from the primary paired analysis rather than resolved by
#     arbitrarily preferring first or last, either of which would amount to
#     choosing the observation that gives the preferred answer. Both calls stay
#     in the call-level dataset, and first-vs-last is reported as sensitivity.
#
# `rule` selects among protocol-valid calls: "primary" excludes Shape B cells,
# "first"/"last" force a choice for the sensitivity analyses.
#
# A protocol-valid completed call is one eligible for the offer model
# (exclusion codes 0, 7, 9, 10) -- staff engaged and the call ran to a
# disposition. Codes 2, 3, 5, 6, 8 are attempts that never became a call.
make_wide <- function(df, value_col,
                      scenarios = c("Straight couple", "Lesbian couple", "Single mother"),
                      rule = c("primary", "first", "last")) {
  rule <- match.arg(rule)
  ids  <- sort(unique(df$practice_id[!is.na(df$practice_id)]))
  wide <- data.frame(practice_id = ids)
  for (s in scenarios) {
    sub <- df[!is.na(df$scenario) & as.character(df$scenario) == s, ]
    col <- gsub(" ", "_", s)
    wide[[col]] <- vapply(wide$practice_id, function(pid) {
      cell <- sub[sub$practice_id %in% pid, ]
      if (!nrow(cell)) return(NA)
      valid <- cell[cell$in_offer_den %in% TRUE, ]
      # No completed call: fall back to the attempts, which is what a
      # reachability outcome legitimately describes.
      if (!nrow(valid)) valid <- cell
      if (nrow(valid) > 1) {
        if (rule == "primary") return(NA)          # Shape B: excluded
        ord   <- order(valid$call_date, valid$record_id, na.last = TRUE)
        valid <- valid[if (rule == "first") ord[1] else ord[length(ord)], ]
      }
      valid[[value_col]][1]
    }, FUN.VALUE = df[[value_col]][NA_integer_])
  }
  wide
}

# Cells excluded from the primary paired analysis under the Shape B rule.
protocol_deviation_cells <- function(df,
                                     scenarios = c("Straight couple", "Lesbian couple", "Single mother")) {
  out <- df[!is.na(df$scenario) & !is.na(df$practice_id) & df$in_offer_den %in% TRUE, ]
  if (!nrow(out)) return(out[0, c("practice_id", "scenario"), drop = FALSE])
  counts <- aggregate(list(n_completed = out$record_id),
                      by = list(practice_id = out$practice_id,
                                scenario = as.character(out$scenario)),
                      FUN = length)
  counts[counts$n_completed > 1, ]
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
  caller_raw             = trimws(raw[[col_completer]]),
  stringsAsFactors       = FALSE
)

# ── Derived variables ─────────────────────────────────────────────────────────
dat$scenario[dat$scenario == ""] <- NA_character_
dat$exclusion_code     <- exclusion_code_map[dat$exclusion_reason]
dat$analytic_inclusion <- !is.na(dat$exclusion_reason) & dat$exclusion_reason == included_value
dat$form_finalized     <- !is.na(dat$complete) & dat$complete == "Complete"
dat$wait_days          <- as.numeric(dat$first_appt_date - dat$call_date)

# ── Caller identity (for the confounding diagnostics) ─────────────────────────
# REDCap free-texts the form completer; collapse casing/spelling variants so the
# caller-by-scenario crosstab is not fragmented across the same person.
dat$caller <- dat$caller_raw
dat$caller[is.na(dat$caller) | dat$caller == ""] <- "Unrecorded"
dat$caller <- sub("^Mufflly$", "Muffly", dat$caller)
dat$caller <- sub("^sr$",      "SR",     dat$caller)
dat$caller <- sub("^sofie$",   "Sofie",  dat$caller)
# "Sam" and "SR" are the same person (Sam Raine), recorded two ways -- same
# class of variant as Mufflly/Muffly. Both entries are straight-couple calls
# only, which is consistent. Left unmerged they inflate the caller count and
# split one person's 17 calls into 16 and 1.
dat$caller <- sub("^Sam$",     "SR",     dat$caller)

# De-identify. The caller-confounding analysis needs caller STRATA, not caller
# identities: "Caller A placed 53/77 straight-couple calls" carries exactly the
# scientific content of the named version. Study staff are human subjects of
# this measurement even though they are also its authors, so their names do not
# belong in a committed analysis artifact unless disclosure is intended.
#
# The mapping is alphabetical on the normalised name, so it is stable across
# runs and reproducible from the raw export, but the crosswalk lives only in
# the gitignored export -- never in the repo.
caller_people <- sort(setdiff(unique(dat$caller), "Unrecorded"))
caller_labels <- stats::setNames(
  paste("Caller", LETTERS[seq_along(caller_people)]), caller_people)
dat$caller <- ifelse(dat$caller %in% names(caller_labels),
                     unname(caller_labels[dat$caller]), dat$caller)
dat$caller_raw <- NULL   # never written to a committed artifact

# ── Outcome architecture: REACHED is not OFFERED ──────────────────────────────
# mysterycall_exclusion_crosswalk() is the package's canonical mapping and keeps
# three distinct concepts apart. Collapsing them (the previous
# `contact_office <- analytic_inclusion`) made the "appointment offered" outcome
# identical to the analytic-inclusion filter, so acceptance was 100% inside the
# analytic sample by construction and the only true refusals were thrown away.
#
#   reached      a human answered and engaged                     (codes 0,2,7,9,10)
#   in_logistic  eligible for the appointment-offer model         (codes 0,7,9,10)
#   label_included  the historical "included" flag                (code 0)
#
# Code 9 ("Not accepting new patients") is a REACHED REFUSAL: the only
# unambiguous offered = 0 events in the study. They were previously excluded.
exclusion_xw <- as.data.frame(mysterycall_exclusion_crosswalk())
xw_i <- match(dat$exclusion_code, exclusion_xw$code)
na_false <- function(x) { x[is.na(x)] <- FALSE; x }
dat$reached          <- na_false(exclusion_xw$reached[xw_i])
dat$in_offer_den     <- na_false(exclusion_xw$in_logistic[xw_i])
dat$explicit_refusal <- !is.na(dat$exclusion_code) & dat$exclusion_code == 9L

# `contact_office` now carries its honest meaning (a live office was reached),
# NOT "an appointment was offered". Downstream code that wants the offer
# outcome must use `appt_offered`.
dat$contact_office <- dat$reached
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

# ── The appointment-offer outcome ─────────────────────────────────────────────
# The REDCap instrument has no "did they agree to schedule you?" item, so the
# offer outcome has to be derived. mysterycall_appointment_obtained() builds the
# binary indicator and the business-day wait together and, critically, keeps
# same-day appointments as wait = 0 instead of dropping them to NA (which would
# silently recode the strongest-access calls as "not obtained").
dat <- tryCatch(
  mysterycall_appointment_obtained(
    dat,
    call_col     = "call_date",
    appt_col     = "first_appt_date",
    obtained_col = "appt_obtained",
    wait_col     = "biz_wait",
    add_wait     = TRUE
  ),
  error = function(e) { dat$appt_obtained <- NA_integer_; dat$biz_wait <- NA_real_; dat }
)

# STRICT definition (primary): among calls eligible for the offer model, a
# concrete appointment date was obtained. An explicit "not accepting new
# patients" is a hard 0 regardless of dates.
dat$appt_offered <- NA_integer_
den <- dat$in_offer_den
dat$appt_offered[den] <- ifelse(dat$explicit_refusal[den], 0L, dat$appt_obtained[den])

# BROAD definition (sensitivity): a date OR a concrete scheduling timeframe
# ("Less than 1 mo" / "1-2 mo" / "3+ mo"). Ten reached calls gave a timeframe but
# no date; the strict definition scores those as refusals, which is arguably too
# harsh, so both are reported.
dat$scheduling_timeframe_given <- !is.na(dat$wait_category) & dat$wait_category != ""
dat$appt_offered_broad <- dat$appt_offered
dat$appt_offered_broad[den & !dat$explicit_refusal &
                       dat$scheduling_timeframe_given &
                       (is.na(dat$appt_offered) | dat$appt_offered == 0L)] <- 1L

dat$call_placed        <- TRUE
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
# A practice name that is (or contains) a phone number is a data-entry error:
# the caller typed contact details into the identity field. That both leaks
# contact information into every committed artifact -- bypassing the .gitignore
# rule that keeps raw exports out -- and creates a phantom singleton practice.
# Redact the digits and treat the practice as unidentified; the affected
# records are written out for repair in REDCap.
PHONE_RE <- "\\(?[0-9]{3}\\)?[-. ] ?[0-9]{3}[-. ][0-9]{4}"

redact_phone <- function(x) trimws(gsub(PHONE_RE, "[redacted]", x))

normalize_practice <- function(x) {
  # Test emptiness on the string with the phone REMOVED, not on the redacted
  # form: "[redacted]" contains letters and would always look like a name.
  without_phone <- trimws(gsub(PHONE_RE, "", x))
  x <- redact_phone(x)
  # Nothing identifying survived -> we genuinely do not know the practice.
  x[gsub("[^A-Za-z]", "", without_phone) == ""] <- NA_character_
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

dat$practice <- redact_phone(dat$practice)
dat$practice_key <- ifelse(
  is.na(dat$practice) | dat$practice == "",
  NA_character_,
  normalize_practice(dat$practice)
)
practice_levels <- sort(unique(dat$practice_key[!is.na(dat$practice_key) & dat$practice_key != ""]))
dat$practice_id <- match(dat$practice_key, practice_levels)

# Preflight health check via mysterycall package
if (exists("mysterycall_preflight_check", where = "package:mysterycall")) {
  dat_chk <- dat; dat_chk$first <- dat_chk$practice; dat_chk$last <- dat_chk$practice
  preflight_res <- tryCatch(mysterycall_preflight_check(dat_chk, output_dir = out_dir), error = function(e) NULL)
  if (!is.null(preflight_res)) {
    message("✔ [mysterycall] Preflight health check completed successfully.")
  }
}

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
phone_only_records <- dat[is.na(dat$practice_key) & !is.na(dat$scenario),
                          c("record_id", "scenario", "practice")]
write.csv(phone_only_records,
          file.path(out_dir, "practice_name_review_phone_only.csv"), row.names = FALSE)
if (nrow(phone_only_records) > 0)
  message("PRIVACY: ", nrow(phone_only_records), " record(s) had contact details ",
          "in the practice-name field. Digits redacted and the practice treated as ",
          "unidentified; fix these in REDCap (see practice_name_review_phone_only.csv).")

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
reached_calls     <- dat[dat$reached, ]                       # a live office answered
offer_den         <- dat[dat$in_offer_den, ]                  # eligible for the offer model
offer_analytic    <- dat[dat$in_offer_den & !is.na(dat$appt_offered) &
                         !is.na(dat$scenario), ]

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

# Reachability by scenario (denominator = every call placed). This is what the
# old "acceptance_all" table reported; it is now named for what it measures.
reach_all <- mysterycall_acceptance_rate(
  dat[!is.na(dat$scenario), ],
  accepted_col = "reached",
  group_by     = "scenario"
)

# Appointment-offer rate by scenario (denominator = offer-eligible calls).
offer_by_scenario <- tryCatch(
  mysterycall_acceptance_rate(
    offer_analytic,
    accepted_col = "appt_offered",
    group_by     = "scenario"
  ), error = function(e) NULL)

offer_by_scenario_broad <- tryCatch(
  mysterycall_acceptance_rate(
    dat[dat$in_offer_den & !is.na(dat$appt_offered_broad) & !is.na(dat$scenario), ],
    accepted_col = "appt_offered_broad",
    group_by     = "scenario"
  ), error = function(e) NULL)

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

# ── ACCESS CASCADE — reachability and offer are separate stages ──────────────
# Replaces the single "acceptance" number, which silently mixed "nobody picked
# up" with "they picked up and said no".
cascade <- tryCatch(
  mysterycall_access_cascade(
    dat,
    list(
      mysterycall_cascade_stage("Calls placed",              "call_placed",   TRUE),
      mysterycall_cascade_stage("Reached a live office",     "reached",       TRUE,
                                denominator = "previous"),
      mysterycall_cascade_stage("Eligible for offer model",  "in_offer_den",  TRUE,
                                denominator = "previous"),
      mysterycall_cascade_stage("Appointment offered",       "appt_offered",  1L,
                                denominator = "previous")
    )
  ),
  error = function(e) structure(list(error = conditionMessage(e)), class = "cascade_error")
)

# By-scenario version of the same cascade (counts, not a model).
cascade_by_scenario <- local({
  sc <- levels(dat$scenario)
  do.call(rbind, lapply(sc, function(s) {
    x  <- dat[!is.na(dat$scenario) & dat$scenario == s, ]
    ob <- x$appt_offered_broad
    data.frame(
      scenario              = s,
      calls_placed          = nrow(x),
      reached               = sum(x$reached),
      offer_eligible        = sum(x$in_offer_den),
      offered_strict        = sum(x$appt_offered == 1L, na.rm = TRUE),
      offered_broad         = sum(ob == 1L, na.rm = TRUE),
      pct_offered_strict    = round(100 * mean(x$appt_offered == 1L, na.rm = TRUE), 1),
      pct_offered_broad     = round(100 * mean(ob == 1L, na.rm = TRUE), 1),
      stringsAsFactors = FALSE
    )
  }))
})

# ── CALLER CONFOUNDING DIAGNOSTICS ───────────────────────────────────────────
# Scenario was not randomised across callers. If one caller placed most of one
# scenario's calls, a "scenario effect" and a "caller effect" are the same
# number and no amount of within-practice pairing separates them.
caller_scenario_tab <- table(dat$caller, dat$scenario)

caller_scenario_test <- tryCatch(
  mysterycall_test_categorical(dat[!is.na(dat$scenario), ],
                               row_var = "caller", col_var = "scenario",
                               method = "auto"),
  error = function(e) NULL
)

caller_rates <- local({
  cs <- sort(unique(dat$caller))
  do.call(rbind, lapply(cs, function(cc) {
    x <- dat[dat$caller == cc, ]
    data.frame(
      caller         = cc,
      n_calls        = nrow(x),
      pct_reached    = round(100 * mean(x$reached), 1),
      n_offer_eligible = sum(x$in_offer_den),
      pct_offered    = round(100 * mean(x$appt_offered == 1L, na.rm = TRUE), 1),
      stringsAsFactors = FALSE
    )
  }))
})

# Largest share any single caller holds of a scenario's calls — the headline
# number for the limitations paragraph.
caller_dominance <- local({
  m <- as.matrix(caller_scenario_tab)
  do.call(rbind, lapply(colnames(m), function(s) {
    col <- m[, s]; top <- which.max(col)
    data.frame(scenario = s, n_calls = sum(col),
               top_caller = rownames(m)[top], top_caller_n = col[top],
               top_caller_pct = round(100 * col[top] / sum(col), 1),
               stringsAsFactors = FALSE)
  }))
})

# Can scenario and caller be separated in one model? Fit both and compare.
caller_adjusted_glmer <- tryCatch({
  dd <- offer_analytic[!is.na(offer_analytic$practice_id), ]
  dd$caller <- factor(dd$caller)
  if (nlevels(dd$caller) < 2) stop("only one caller level in the offer sample")
  fit <- lme4::glmer(appt_offered ~ scenario + caller + (1 | practice_id),
                     data = dd, family = binomial)
  list(ok = TRUE, fit = fit,
       text = paste(capture.output(print(summary(fit)$coefficients)), collapse = "\n"))
}, error = function(e) list(ok = FALSE, text = conditionMessage(e)))

drift <- tryCatch({
  dd <- offer_analytic
  dd$offered <- dd$appt_offered
  mysterycall_caller_drift(dd, outcome_col = "offered", date_col = "call_date",
                           caller_col = "caller", plot = FALSE)
}, error = function(e) NULL)

# ── CALLER OVERLAP — which contrasts are estimable within caller ──────────────
# Caller-scenario confounding is not uniform. A contrast can only be separated
# from caller effects where the SAME caller placed calls under BOTH scenarios.
# Where no caller did, the scenario column and that caller's column are the
# same numbers, and no adjustment recovers the difference.
caller_overlap <- local({
  eligible <- dat[dat$in_offer_den & !is.na(dat$appt_offered) &
                  !is.na(dat$scenario), ]
  counts <- table(eligible$caller, eligible$scenario)
  contrasts <- list(c("Straight couple", "Lesbian couple"),
                    c("Straight couple", "Single mother"),
                    c("Lesbian couple",  "Single mother"))
  do.call(rbind, lapply(contrasts, function(cc) {
    shared <- rownames(counts)[counts[, cc[1]] >= 3 & counts[, cc[2]] >= 3]
    data.frame(contrast = paste(cc, collapse = " vs "),
               n_callers_with_both = length(shared),
               callers = if (length(shared)) paste(shared, collapse = ", ") else "none",
               n_calls = if (length(shared)) sum(counts[shared, cc]) else 0L,
               stringsAsFactors = FALSE)
  }))
})

# Where overlap exists, estimate the contrast stratified by caller
# (Mantel-Haenszel). This is a diagnostic, not a rescue analysis: it says
# whether the crude contrast survives holding caller fixed.
caller_stratified <- local({
  row <- caller_overlap[caller_overlap$n_callers_with_both > 0, ]
  if (!nrow(row)) return(NULL)
  scen <- strsplit(row$contrast[1], " vs ")[[1]]
  shared <- strsplit(row$callers[1], ", ")[[1]]
  sub <- dat[dat$in_offer_den & !is.na(dat$appt_offered) &
             dat$scenario %in% scen & dat$caller %in% shared, ]
  sub$scenario <- droplevels(factor(sub$scenario, levels = scen))
  tabs <- table(sub$scenario, sub$appt_offered, sub$caller)
  mh <- tryCatch(mantelhaen.test(tabs, exact = FALSE), error = function(e) NULL)
  if (is.null(mh)) return(NULL)
  data.frame(contrast = row$contrast[1], n = nrow(sub),
             mh_or = unname(mh$estimate),
             ci_lo = mh$conf.int[1], ci_hi = mh$conf.int[2],
             p_value = mh$p.value, stringsAsFactors = FALSE)
})

# ── SERVICE MENU — Wilson CIs via the package ────────────────────────────────
service_vars <- c("service_cycle_tracking", "service_hormonal_timing",
                  "service_ovulation_induction", "service_iui", "service_ivf")
included$services_multi <- apply(included[service_vars], 1, function(r)
  paste(sub("^service_", "", service_vars)[as.logical(r)], collapse = ";"))
service_prev <- tryCatch(
  as.data.frame(mysterycall_multiresponse_tabulate(included, var = "services_multi",
                                                   sep = ";")$prevalence),
  error = function(e) NULL)
donor_prev <- tryCatch(
  as.data.frame(mysterycall_prevalence_ci(included, var = "donor_sperm_yes")),
  error = function(e) NULL)

# The three "restrictions to the individuals you would provide care to"
# checkboxes are the only directly measured discrimination item. Their coding is
# ambiguous (the straight-couple box is ticked on straight-couple calls), so they
# are tabulated for adjudication, not analysed.
restrict_vars <- c("restrict_lesbian", "restrict_straight", "restrict_single_mother")
restrict_tab <- do.call(rbind, lapply(restrict_vars, function(v)
  data.frame(item = v,
             checked_all = sum(dat[[v]]),
             checked_included = sum(included[[v]]),
             paste(paste0(levels(dat$scenario), "=",
                          tapply(included[[v]], included$scenario, sum)[levels(dat$scenario)]),
                   collapse = ", "),
             stringsAsFactors = FALSE)))
names(restrict_tab)[4] <- "by_scenario_included"

# ── MISSINGNESS — Little's MCAR instead of an asserted MAR ───────────────────
mcar <- tryCatch(
  build_missingness_mcar_table(
    included,
    item_vars = c("first_appt_date", "wait_category", "insurance",
                  "cost_estimate", "pregnancy_time")
  ),
  error = function(e) NULL)

# ── QC: wait-time contamination and inclusion/outcome discrepancies ──────────
qc <- local({
  dq <- dat
  dq$business_days_until_appointment <- dq$business_days
  dq$reason_for_exclusions <- ifelse(dq$analytic_inclusion, "Able to contact",
                                     dq$exclusion_reason)
  dq$physician_information <- dq$practice
  dq$id_number             <- dq$record_id
  dq$notes                 <- ""
  guard <- tryCatch(
    { mysterycall_guard_contaminated_wait(dq, wait_col = "business_days_until_appointment",
        appointment_col = "first_appt_date", exclusion_col = "reason_for_exclusions",
        action = "warn"); "clean" },
    error = function(e) paste("CONTAMINATED:", conditionMessage(e)))
  inc_na  <- tryCatch(nrow(mysterycall_flag_included_na_appointments(dq, output_dir = out_dir)),
                      error = function(e) NA_integer_)
  exc_ap  <- tryCatch(nrow(mysterycall_flag_excluded_with_appointments(dq, output_dir = out_dir)),
                      error = function(e) NA_integer_)
  list(guard = guard, included_na_appt = inc_na, excluded_with_appt = exc_ap)
})

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

# PRIMARY: appointment offered, among calls that reached an office and are
# eligible for the offer model. This is the outcome the protocol describes.
glmer_offer <- tryCatch(
  mysterycall_logistic_model(
    data             = offer_analytic[!is.na(offer_analytic$practice_id), ],
    outcome          = "appt_offered",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

glmer_offer_triads <- tryCatch(
  mysterycall_logistic_model(
    data             = offer_analytic[!is.na(offer_analytic$practice_id) &
                                      offer_analytic$practice_id %in% triad_practice_ids, ],
    outcome          = "appt_offered",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

# Sensitivity: broad offer definition (date OR a concrete scheduling timeframe).
glmer_offer_broad <- tryCatch(
  mysterycall_logistic_model(
    data             = dat[dat$in_offer_den & !is.na(dat$appt_offered_broad) &
                           !is.na(dat$scenario) & !is.na(dat$practice_id), ],
    outcome          = "appt_offered_broad",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

# SECONDARY (relabelled, not removed): reachability. This is what the previous
# "acceptance" model actually estimated — whether a live office answered — and
# it is a legitimate access outcome in its own right, just not "was an
# appointment offered".
glmer_reached <- tryCatch(
  mysterycall_logistic_model(
    data             = dat[!is.na(dat$practice_id) & !is.na(dat$scenario), ],
    outcome          = "reached",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

glmer_reached_triads <- tryCatch(
  mysterycall_logistic_model(
    data             = dat[!is.na(dat$practice_id) & dat$practice_id %in% triad_practice_ids & !is.na(dat$scenario), ],
    outcome          = "reached",
    predictors       = "scenario",
    random_intercept = "practice_id"
  ),
  error = function(e) structure(list(error = conditionMessage(e)),
                                class = "mysterycall_logistic_model_error")
)

# ── Two-part (hurdle) model — offer and wait estimated jointly ────────────────
# The complete-case LMM below conditions on having an appointment date, and that
# missingness is strongly scenario-dependent. The hurdle model estimates the
# obtainment step and the wait-given-obtained step together instead of
# discarding the first.
hurdle_fit <- tryCatch({
  hd <- offer_analytic[!is.na(offer_analytic$practice_id), ]
  hd$obtained <- hd$appt_offered
  mysterycall_hurdle_wait(hd, obtained_col = "obtained", wait_col = "biz_wait",
                          predictors = "scenario", random_intercept = "practice_id")
}, error = function(e) structure(list(error = conditionMessage(e)), class = "hurdle_error"))

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
      "Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. ",
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

  # mysterycall_lmm(auto_log = TRUE) log-transforms a right-skewed outcome and
  # returns coefficients on the LOG scale, with the back-transform in
  # $gmr_table. Labelling $coef_table as "business days" (the previous
  # behaviour) misreported an intercept of 2.9 log-units as 2.9 days.
  logged <- isTRUE(res$log_transformed)
  if (logged && !is.null(res$gmr_table)) {
    gt <- as.data.frame(res$gmr_table)
    ct_fmt <- data.frame(
      Term  = gt$term,
      GMR   = round(gt$GMR,    2),
      CI_lo = round(gt$GMR_lo, 2),
      CI_hi = round(gt$GMR_hi, 2),
      p     = gt$p_value_fmt,
      stringsAsFactors = FALSE
    )
  } else {
    ct <- as.data.frame(res$coef_table)
    ct_fmt <- data.frame(
      Term              = ct$term,
      Est_business_days = round(ct$estimate, 1),
      CI_lo             = round(ct$ci_lower, 1),
      CI_hi             = round(ct$ci_upper, 1),
      p                 = ct$p_value_fmt,
      stringsAsFactors  = FALSE
    )
  }

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
      "mysterycall_lmm() [lme4::lmer]. Outcome: ", res$outcome_used, ". ",
      if (logged)
        paste0("auto_log applied log1p() to the right-skewed wait; the table is ",
               "the back-transformed GEOMETRIC MEAN RATIO from $gmr_table. The ",
               "intercept is the reference group's geometric-mean wait in ",
               "business days; each scenario row is a multiplicative ratio vs. ",
               "Straight couple (GMR < 1 = shorter wait). These are NOT ",
               "differences in days. ")
      else
        paste0("Estimates are mean difference in business days vs. Straight ",
               "couple (reference); negative = shorter wait. "),
      "n = ", res$n, " records with observed appointment date. ",
      norm_flag, " ",
      "Marginal R² = ", round(res$r_squared$marginal, 3), ", ",
      "Conditional R² = ", round(res$r_squared$conditional, 3), "."
    ),
    n = res$n
  )
}

offer_fmt         <- fmt_glmer_result(glmer_offer)
offer_fmt_triads  <- fmt_glmer_result(glmer_offer_triads)
offer_fmt_broad   <- fmt_glmer_result(glmer_offer_broad)
reached_fmt       <- fmt_glmer_result(glmer_reached)
reached_fmt_triads<- fmt_glmer_result(glmer_reached_triads)
lmm_fmt           <- fmt_lmm_result(lmer_wait)

# ── Sensitivity analysis: GEE ─────────────────────────────────────────────────
# Population-average model (vs. the subject-specific glmer). Uses all records
# including singletons and dyads; exchangeable correlation within practice.
wide_acc     <- make_wide(dat, "appt_offered")   # PRIMARY: appointment offered
wide_reached <- make_wide(dat, "reached")        # SECONDARY: a live office answered
wide_wait    <- make_wide(dat, "wait_days")

gee_output <- tryCatch({
  if (!has_geepack) stop("geepack not installed; run install.packages('geepack')")
  dat_gee          <- offer_analytic[!is.na(offer_analytic$practice_id), ]
  dat_gee          <- dat_gee[order(dat_gee$practice_id), ]
  dat_gee$scenario <- relevel(droplevels(dat_gee$scenario), ref = "Straight couple")
  fit <- geepack::geeglm(
    as.integer(appt_offered) ~ scenario,
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

paired_mcnemar <- function(wide) {
  do.call(rbind, lapply(paired_contrasts, function(cc) {
    a <- as.logical(wide[[cc[1]]]); b <- as.logical(wide[[cc[2]]])
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
}

# PRIMARY paired contrast: appointment offered, within practice. Shape B cells
# are excluded (rule = "primary"), so `n_paired` here is smaller than the raw
# count of practices called for both scenarios -- deliberately.
paired_acc_df     <- paired_mcnemar(wide_acc)
# SECONDARY: reachability, within practice (what the old table reported).
paired_reached_df <- paired_mcnemar(wide_reached)

# SENSITIVITY to the Shape B rule. If first-successful and last-successful give
# the same substantive answer, the excluded cells were not load-bearing; if
# they diverge, that is itself the finding and belongs in the manuscript.
paired_acc_first <- paired_mcnemar(make_wide(dat, "appt_offered", rule = "first"))
paired_acc_last  <- paired_mcnemar(make_wide(dat, "appt_offered", rule = "last"))
paired_sensitivity <- data.frame(
  contrast        = paired_acc_df$contrast,
  primary_n       = paired_acc_df$n_paired,
  primary_disc    = paired_acc_df$discordant,
  primary_p       = paired_acc_df$mcnemar_p,
  first_n         = paired_acc_first$n_paired,
  first_disc      = paired_acc_first$discordant,
  first_p         = paired_acc_first$mcnemar_p,
  last_n          = paired_acc_last$n_paired,
  last_disc       = paired_acc_last$discordant,
  last_p          = paired_acc_last$mcnemar_p,
  stringsAsFactors = FALSE
)

deviation_cells <- protocol_deviation_cells(dat)
deviation_cells$practice_key <- practice_levels[deviation_cells$practice_id]

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
write.csv(reach_all$summary,            file.path(out_dir, "mysterycall_reach_by_scenario.csv"),                       row.names = FALSE)
if (!is.null(offer_by_scenario))
  write.csv(offer_by_scenario$summary,  file.path(out_dir, "mysterycall_offer_by_scenario.csv"),                       row.names = FALSE)
if (!is.null(offer_by_scenario_broad))
  write.csv(offer_by_scenario_broad$summary, file.path(out_dir, "mysterycall_offer_by_scenario_broad.csv"),            row.names = FALSE)
write.csv(cascade_by_scenario,          file.path(out_dir, "mysterycall_access_cascade_by_scenario.csv"),              row.names = FALSE)
if (!inherits(cascade, "cascade_error"))
  write.csv(as.data.frame(cascade$table), file.path(out_dir, "mysterycall_access_cascade.csv"),                        row.names = FALSE)
write.csv(paired_reached_df,            file.path(out_dir, "mysterycall_paired_reached_mcnemar.csv"),                  row.names = FALSE)
write.csv(paired_sensitivity,           file.path(out_dir, "mysterycall_paired_offer_sensitivity.csv"),                row.names = FALSE)
write.csv(deviation_cells,              file.path(out_dir, "protocol_deviation_cells.csv"),                            row.names = FALSE)
write.csv(as.data.frame.matrix(caller_scenario_tab),
                                        file.path(out_dir, "caller_by_scenario.csv"))
write.csv(caller_rates,                 file.path(out_dir, "caller_rates.csv"),                                        row.names = FALSE)
write.csv(caller_dominance,             file.path(out_dir, "caller_dominance_by_scenario.csv"),                         row.names = FALSE)
write.csv(caller_overlap,               file.path(out_dir, "caller_overlap_by_contrast.csv"),                          row.names = FALSE)
if (!is.null(caller_stratified))
  write.csv(caller_stratified,          file.path(out_dir, "caller_stratified_contrast.csv"),                          row.names = FALSE)
write.csv(exclusion_xw,                 file.path(out_dir, "exclusion_crosswalk.csv"),                                  row.names = FALSE)
write.csv(restrict_tab,                 file.path(out_dir, "restriction_checkbox_review.csv"),                          row.names = FALSE)
if (!is.null(service_prev))
  write.csv(service_prev,               file.path(out_dir, "mysterycall_service_prevalence.csv"),                       row.names = FALSE)
if (!is.null(mcar) && !is.null(mcar$missingness))
  write.csv(as.data.frame(mcar$missingness), file.path(out_dir, "mysterycall_missingness_mcar.csv"),                    row.names = FALSE)
write.csv(wide_reached,                 file.path(out_dir, "matched_reached_wide.csv"),                                 row.names = FALSE)
write.csv(wait_included$summary,        file.path(out_dir, "mysterycall_wait_by_scenario_included.csv"),                  row.names = FALSE)
write.csv(wait_included_complete$summary, file.path(out_dir, "mysterycall_wait_by_scenario_included_complete.csv"),       row.names = FALSE)
write.csv(missing_appt$summary,         file.path(out_dir, "mysterycall_missing_appt_summary.csv"),                       row.names = FALSE)
write.csv(table1$table,                 file.path(out_dir, "mysterycall_table1_included_complete.csv"),                   row.names = FALSE)
write.csv(scenario_counts,              file.path(out_dir, "scenario_counts_by_completion.csv"),                          row.names = FALSE)
write.csv(inclusion_counts,             file.path(out_dir, "scenario_counts_by_inclusion.csv"),                           row.names = FALSE)
write.csv(coverage_df,                  file.path(out_dir, "practice_scenario_coverage.csv"),                             row.names = FALSE)
write.csv(wide_acc,                     file.path(out_dir, "matched_acceptance_wide.csv"),                                row.names = FALSE)
write.csv(wide_wait,                    file.path(out_dir, "matched_wait_wide.csv"),                                      row.names = FALSE)

# ── STROBE flow diagram (Green Journal requires one) ──────────────────────────
fig_dir <- file.path(out_dir, "figures")
dir.create(fig_dir, showWarnings = FALSE)
strobe <- tryCatch(
  mysterycall_strobe_flow(
    n_total     = nrow(dat),
    n_calldate  = sum(!is.na(dat$call_date)),
    n_included  = sum(dat$reached),
    n_logistic  = nrow(offer_analytic),
    n_waittime  = sum(!is.na(dat$biz_wait)),
    excl_no_calldate = sum(is.na(dat$call_date)),
    # Named by exclusion CODE (as character), which is what the function's
    # internal code_labels lookup keys on; naming by free-text reason silently
    # renders an "Excluded (n = ...)" box with no breakdown.
    excl_detail = local({
      not_reached <- dat$exclusion_code[!dat$reached & !is.na(dat$call_date)]
      tb <- table(ifelse(is.na(not_reached), "NA", as.character(not_reached)))
      setNames(as.integer(tb), names(tb))
    }),
    label_included = "Reached a live office\n(exclusion codes 0, 2, 7, 9, 10)",
    label_logistic = "Offer analysis\nOutcome: appointment offered (yes/no)",
    label_waittime = "Wait-time analysis\nBusiness days to first appointment",
    title       = "LABUBU STROBE Flow - RRM Mystery-Caller Study",
    output_path = file.path(fig_dir, "fig0_strobe_flow.png")
  ),
  error = function(e) { message("STROBE flow not drawn: ", conditionMessage(e)); NULL })

# Paint the STROBE figure onto white.
#
# mysterycall_strobe_flow() builds on theme_void(), which leaves the plot
# background blank; ggsave() honours that and writes an alpha channel, so the
# PNG came out 72% fully transparent. The diagram is black text and black box
# outlines, so it renders correctly on a white page and disappears against any
# dark viewer or dark-mode PDF reader -- it looks fine right up until it does
# not.
#
# Fixed upstream in mufflyt/mysterycall#260. This re-save keeps LABUBU correct
# at the currently pinned SHA and is harmless once that lands; the
# figures/opaque-background gate check is what actually holds the line.
if (!is.null(strobe) && inherits(strobe, "ggplot")) {
  strobe_white <- strobe +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA))
  for (ext in c("png", "tiff")) {
    target <- file.path(fig_dir, paste0("fig0_strobe_flow.", ext))
    # `compression` is a TIFF-only argument; passing it as NULL to the PNG
    # device is still passing it, and ggsave() rejects it outright.
    save_args <- list(filename = target, plot = strobe_white,
                      width = 9, height = 11, dpi = 300, bg = "white")
    if (ext == "tiff") save_args$compression <- "lzw"
    tryCatch(do.call(ggplot2::ggsave, save_args),
             error = function(e) message("STROBE re-save failed for ", ext, ": ",
                                         conditionMessage(e)))
  }
}

# ── STROBE flow, split by caller scenario ─────────────────────────────────────
# The combined diagram shows the cohort, which is what STROBE asks for, but it
# hides that the three arms attrit differently: 82% of reached straight-couple
# calls yielded an appointment date versus 42% and 48% for the other two. A
# per-scenario panel makes that visible in the figure rather than only in the
# missingness table.
#
# Scenario labels follow the protocol and the manuscript ("Lesbian couple"),
# not a synonym, so figure and text cannot drift apart.
strobe_panels <- lapply(levels(dat$scenario), function(scen) {
  arm <- dat[!is.na(dat$scenario) & dat$scenario == scen, ]
  not_reached <- arm$exclusion_code[!arm$reached & !is.na(arm$call_date)]
  detail <- table(ifelse(is.na(not_reached), "NA", as.character(not_reached)))
  tryCatch(
    mysterycall_strobe_flow(
      n_total          = nrow(arm),
      n_calldate       = sum(!is.na(arm$call_date)),
      n_included       = sum(arm$reached),
      n_logistic       = sum(!is.na(arm$appt_offered)),
      n_waittime       = sum(!is.na(arm$biz_wait)),
      excl_no_calldate = sum(is.na(arm$call_date)),
      excl_detail      = stats::setNames(as.integer(detail), names(detail)),
      label_included   = "Reached a live office",
      label_logistic   = "Offer analysis",
      label_waittime   = "Wait-time analysis",
      title            = scen),
    error = function(e) NULL)
})
names(strobe_panels) <- levels(dat$scenario)

if (all(vapply(strobe_panels, inherits, logical(1), "ggplot")) &&
    requireNamespace("patchwork", quietly = TRUE)) {
  panel <- patchwork::wrap_plots(strobe_panels, nrow = 1) +
    patchwork::plot_annotation(
      title = "LABUBU STROBE Flow by Caller Scenario",
      theme = ggplot2::theme(
        plot.title = ggplot2::element_text(hjust = 0.5, size = 15, face = "bold"),
        plot.background = ggplot2::element_rect(fill = "white", colour = NA)))
  for (ext in c("png", "tiff")) {
    target <- file.path(fig_dir, paste0("fig0b_strobe_flow_by_scenario.", ext))
    save_args <- list(filename = target, plot = panel, width = 20, height = 11,
                      dpi = 300, bg = "white", limitsize = FALSE)
    if (ext == "tiff") save_args$compression <- "lzw"
    tryCatch(do.call(ggplot2::ggsave, save_args),
             error = function(e) message("STROBE panel save failed for ", ext,
                                         ": ", conditionMessage(e)))
  }
  message("Saved: ", file.path(fig_dir, "fig0b_strobe_flow_by_scenario.png"))
} else {
  message("STROBE per-scenario panel not drawn (patchwork or a panel missing).")
}

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
  "Each analysis uses a different denominator. Quote none of these without its rule.",
  "",
  paste0("- Calls placed (all records): ", nrow(dat)),
  paste0("- Reached a live office (codes 0, 2, 7, 9, 10): ", nrow(reached_calls)),
  paste0("- Eligible for the offer model (codes 0, 7, 9, 10): ", nrow(offer_den)),
  paste0("- Offer model analytic sample (eligible, scenario + outcome present): ", nrow(offer_analytic)),
  paste0("- Historical 'analytic inclusion' flag (code 0 only): ", nrow(included)),
  paste0("- Historical inclusion AND finalized form: ", nrow(included_complete)),
  paste0("- Wait-time subset (appointment date observed): ", sum(!is.na(dat$biz_wait))),
  "",
  paste0("> Note on a corrected definition: `contact_office` previously aliased the ",
         "analytic-inclusion flag, which made 'appointment offered' the same ",
         "variable as 'was this call included'. Acceptance was therefore 100% ",
         "inside the analytic sample by construction, and the ",
         sum(dat$reached & !dat$analytic_inclusion), " reached-but-declined calls ",
         "(", paste(sort(unique(dat$exclusion_reason[dat$reached & !dat$analytic_inclusion])), collapse = "; "),
         ") were discarded — the only unambiguous 'offered = 0' events in the study. ",
         "`contact_office` now means 'a live office answered'; the offer outcome ",
         "is `appt_offered`."),
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
         "mixed-effects logistic regression on the appointment-offer outcome with a practice random intercept (lme4::glmer). ",
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

  # ── ACCESS CASCADE ──────────────────────────────────────────────────────────
  "## ACCESS CASCADE — reachability and offer are different things",
  "",
  paste0("Every stage has its own denominator (each nested in the previous). ",
         "The single 'acceptance rate' this replaces mixed 'nobody picked up the ",
         "phone' with 'someone picked up and said no'."),
  "",
  if (!inherits(cascade, "cascade_error"))
    c("```", capture(cascade), "```")
  else paste0("cascade not run: ", cascade$error),
  "",
  "By scenario (strict offer = appointment date obtained; broad = date OR a concrete scheduling timeframe):",
  "",
  "```",
  capture(cascade_by_scenario),
  "```",
  "",
  "### Appointment-offer rate by scenario",
  "",
  if (!is.null(offer_by_scenario))
    c("```", capture(offer_by_scenario$summary), "```", "",
      paste0("- Unmatched test (descriptive only): ", offer_by_scenario$test_name,
             "; p = ", fmt_p(offer_by_scenario$p_value)))
  else "offer rate by scenario not computed",
  "",
  "Sensitivity — broad offer definition:",
  "",
  if (!is.null(offer_by_scenario_broad))
    c("```", capture(offer_by_scenario_broad$summary), "```")
  else "broad offer rate not computed",
  "",
  paste0("> **The offer outcome is a derived proxy, and this is the study's ",
         "principal measurement limitation.** The REDCap instrument has no ",
         "'did the practice agree to schedule you?' item. 'Offered' is therefore ",
         "read off the appointment date (strict) or the date plus a concrete ",
         "scheduling timeframe (broad), with an explicit 'not accepting new ",
         "patients' scored as a refusal. A call where staff offered an ",
         "appointment but the caller recorded no date is misclassified as a ",
         "refusal. Adding an explicit offer field to REDCap is the single ",
         "highest-value fix to the instrument."),
  "",

  # ── Reachability (relabelled, still reported) ───────────────────────────────
  "### Reachability by scenario (secondary — a live office answered)",
  "",
  "```",
  capture(reach_all$summary),
  "```",
  "",
  paste0("- Descriptive test only: ", reach_all$test_name, "; p = ", fmt_p(reach_all$p_value)),
  "",

  # ── CALLER CONFOUNDING ──────────────────────────────────────────────────────
  "## CALLER CONFOUNDING — read this before interpreting any scenario contrast",
  "",
  paste0("Scenario was not randomised across callers. Where one caller placed ",
         "most of a scenario's calls, 'scenario effect' and 'caller effect' are ",
         "the same number, and within-practice pairing does NOT separate them: ",
         "the pair compares two scenarios dialled by two different people."),
  "",
  "Calls by caller and scenario:",
  "",
  "```",
  capture(caller_scenario_tab),
  "```",
  "",
  if (!is.null(caller_scenario_test))
    paste0("- Caller x scenario association: ", caller_scenario_test$method,
           ", p = ", fmt_p(caller_scenario_test$p_value),
           ", Cramer's V = ", round(caller_scenario_test$cramers_v, 3),
           " (", caller_scenario_test$effect_size, ").")
  else "- Caller x scenario association test not run.",
  "",
  "Single-caller dominance of each scenario:",
  "",
  "```",
  capture(caller_dominance),
  "```",
  "",
  "Per-caller reach and offer rates (callers differ substantially, which is the mechanism):",
  "",
  "```",
  capture(caller_rates),
  "```",
  "",
  if (caller_adjusted_glmer$ok)
    c("Offer model adjusted for caller (scenario + caller + practice random intercept):",
      "", "```", caller_adjusted_glmer$text, "```", "",
      paste0("> Inspect the standard errors above. Where they are very large, ",
             "scenario and caller are not jointly identifiable and the adjusted ",
             "estimate should not be reported as a corrected effect — it is ",
             "evidence that the design cannot separate the two."))
  else paste0("Caller-adjusted model not estimable: ", caller_adjusted_glmer$text,
              " — which is itself the finding: scenario and caller are confounded."),
  "",
  if (!is.null(drift))
    c("Drift checks (a distinct threat: rates changing over the study period or over a caller's call sequence):",
      "",
      paste0("- Calendar: ", if (!is.null(drift$calendar)) drift$calendar$sentence else "not computed"),
      paste0("- Sequence: ", if (!is.null(drift$sequence)) drift$sequence$sentence else "not computed"))
  else "- Drift checks not run.",
  "",

  # ── MATCHED: within-practice paired acceptance (McNemar) ─────────────────────
  "## MATCHED ANALYSIS — Within-Practice Paired Appointment Offer (exact McNemar)",
  "",
  paste0("Each contrast uses only practices called for BOTH scenarios; only ",
         "DISCORDANT practices (different answer to the two callers) carry ",
         "information, so effective n = the discordant count. Concordant practices ",
         "(same answer to both) are the substantive majority — most practices do ",
         "not differentiate — but contribute nothing to the test. ",
         "Outcome = `appt_offered`. Caller confounding (above) is NOT removed by ",
         "this pairing."),
  "",
  "```",
  capture(paired_acc_df),
  "```",
  "",
  paste0("**Duplicate-call rule (PI decision, 2026-09-05).** A practice-scenario ",
         "cell holding two protocol-valid completed calls is a protocol ",
         "deviation and is EXCLUDED from this primary analysis rather than ",
         "resolved by preferring first or last -- either of which would mean ",
         "choosing the observation that gives the preferred answer. ",
         nrow(deviation_cells), " cell(s) excluded (see ",
         "protocol_deviation_cells.csv). Failed attempts -- voicemail, wrong ",
         "number, over-long hold -- never determine a cell; the completed call ",
         "does."),
  "",
  "Sensitivity to that rule (first-successful vs last-successful):",
  "",
  "```",
  capture(paired_sensitivity),
  "```",
  "",
  "Secondary — same pairing on reachability (a live office answered):",
  "",
  "```",
  capture(paired_reached_df),
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
  "## PRIMARY ANALYSIS — Appointment Offered (mixed-effects logistic regression)",
  "",
  paste0("Outcome: `appt_offered` among offer-eligible calls. ",
         "Random intercept for practice accounts for within-practice correlation ",
         "across the scenario calls. Read every estimate below alongside the ",
         "caller-confounding section."),
  "",
  paste0("### Complete Practice Triads Only (n = ", offer_fmt_triads$n, " records)"),
  "Restricted to practices called for ALL 3 scenarios, removing practice-selection dialing bias (but not caller confounding).",
  "",
  if (offer_fmt_triads$ok) {
    c("```", offer_fmt_triads$text, "```", "", paste0("Note: ", offer_fmt_triads$note))
  } else {
    paste0("glmer triads not run: ", offer_fmt_triads$text)
  },
  "",
  paste0("### Full Offer Sample (n = ", offer_fmt$n, " records)"),
  "> Includes unbalanced singletons/dyads, so practice selection is not removed. The triad model above is the primary estimate.",
  "",
  if (offer_fmt$ok) {
    c("```", offer_fmt$text, "```", "", paste0("Note: ", offer_fmt$note))
  } else {
    paste0("glmer not run: ", offer_fmt$text)
  },
  "",
  paste0("### Sensitivity — Broad Offer Definition (n = ", offer_fmt_broad$n, " records)"),
  "Offer = appointment date OR a concrete scheduling timeframe. Tests whether the strict definition drives the result.",
  "",
  if (offer_fmt_broad$ok) {
    c("```", offer_fmt_broad$text, "```", "", paste0("Note: ", offer_fmt_broad$note))
  } else {
    paste0("broad glmer not run: ", offer_fmt_broad$text)
  },
  "",

  # ── Reachability model (relabelled) ─────────────────────────────────────────
  "## SECONDARY ANALYSIS — Reachability (a live office answered)",
  "",
  paste0("This is the model the pipeline previously reported as 'acceptance'. ",
         "It is a real access outcome — whether the phone gets answered — but it ",
         "is not the appointment-offer outcome the protocol specifies."),
  "",
  paste0("### Complete Practice Triads Only (n = ", reached_fmt_triads$n, " records)"),
  "",
  if (reached_fmt_triads$ok) {
    c("```", reached_fmt_triads$text, "```", "", paste0("Note: ", reached_fmt_triads$note))
  } else {
    paste0("reachability triad glmer not run: ", reached_fmt_triads$text)
  },
  "",
  paste0("### Full Sample (n = ", reached_fmt$n, " records)"),
  "",
  if (reached_fmt$ok) {
    c("```", reached_fmt$text, "```", "", paste0("Note: ", reached_fmt$note))
  } else {
    paste0("reachability glmer not run: ", reached_fmt$text)
  },
  "",

  # ── Hurdle model ────────────────────────────────────────────────────────────
  "## TWO-PART (HURDLE) MODEL — offer and wait estimated jointly",
  "",
  paste0("The complete-case wait model below conditions on having an appointment ",
         "date, and that missingness is strongly scenario-dependent — so it ",
         "silently drops the selection step that carries most of the signal. ",
         "mysterycall_hurdle_wait() estimates both parts: obtainment (odds ratios) ",
         "and wait-given-obtained (incidence rate ratios)."),
  "",
  if (!inherits(hurdle_fit, "hurdle_error"))
    c("```", capture(hurdle_fit), "```", "",
      paste0("> Check the confidence intervals on the hurdle part. Extremely wide ",
             "intervals indicate near-separation with this sample size: the ",
             "direction is informative, the magnitude is not."))
  else paste0("hurdle model not run: ", hurdle_fit$error),
  "",

  # ── SECONDARY: LMM wait time ────────────────────────────────────────────────
  "## WAIT TIME — Mixed-Effects Linear Model (complete cases)",
  "",
  paste0("Via mysterycall_lmm(). The wait is right-skewed, so the package's ",
         "auto_log applies log1p() and the table below is the back-transformed ",
         "GEOMETRIC MEAN RATIO (GMR), not a difference in days. The intercept is ",
         "the reference group's geometric-mean wait in business days; scenario ",
         "rows are multiplicative (GMR < 1 = shorter wait). ",
         "n = ", lmm_fmt$n, " records with an observed appointment date. ",
         "Complete-case only — see the hurdle model above for the version that ",
         "keeps the selection step."),
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

  # ── Synthesis ───────────────────────────────────────────────────────────────
  "## HOW TO READ THE OFFER RESULT",
  "",
  paste0("The appointment-offer contrast is the study's headline candidate, and ",
         "it is fragile in three specific ways. State all three or do not report ",
         "the effect."),
  "",
  paste0("1. **Outcome definition.** Strict (appointment date) and broad (date or ",
         "a scheduling timeframe) give materially different answers. Compare the ",
         "triad/full-sample models with the broad sensitivity model above. If the ",
         "effect survives only under the strict definition, what is being measured ",
         "may be whether the caller wrote a date down."),
  paste0("2. **Caller.** Cramer's V for caller x scenario is ",
         if (!is.null(caller_scenario_test)) round(caller_scenario_test$cramers_v, 2) else NA,
         ". In the caller-adjusted model the scenario standard errors inflate, ",
         "which means the design cannot attribute the difference to caller ",
         "identity rather than to scenario."),
  paste0("3. **Separation.** The practice random-intercept variance is large and ",
         "several intervals span orders of magnitude. Odds-ratio magnitudes are ",
         "not interpretable at this sample size; only direction is."),
  "",
  paste0("The well-powered, unconfounded results are the service-menu ",
         "prevalences and the access cascade. Those do not depend on the derived ",
         "offer outcome, on caller identity, or on the matched design."),
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
  "## SERVICE MENU — the well-powered descriptive result",
  "",
  paste0("Denominator: ", nrow(included), " calls that reached staff and were asked ",
         "the service questions. Wilson intervals via the package."),
  "",
  if (!is.null(service_prev)) c("```", capture(service_prev), "```")
  else "service prevalence not computed",
  "",
  if (!is.null(donor_prev)) c("Works with donor sperm:", "", "```", capture(donor_prev), "```")
  else "",
  "",
  paste0("> IUI and IVF are each a single practice. Report the proportion with ",
         "its interval and say so explicitly; do not describe a 1/", nrow(included),
         " count as a rate estimate."),
  "",
  "### Restriction checkboxes — needs adjudication before use",
  "",
  paste0("The only directly measured discrimination item. Currently unanalysable ",
         "because the coding is ambiguous: the straight-couple box is ticked on ",
         "straight-couple calls, so 'checked' may mean 'restricted' or 'served'. ",
         "Resolve against the REDCap codebook, then this becomes a candidate ",
         "primary outcome."),
  "",
  "```",
  capture(restrict_tab),
  "```",
  "",

  "## Missing Appointment Date Analysis",
  "",
  "```",
  capture(missing_appt$summary),
  "```",
  "",
  missing_appt$interpretation,
  "",
  "### Little's MCAR test",
  "",
  if (!is.null(mcar)) c(
    "```", capture(as.data.frame(mcar$missingness)), "```", "",
    if (!is.null(mcar$interpretation)) paste0("- ", paste(mcar$interpretation, collapse = " ")) else ""
  ) else "MCAR table not computed",
  "",
  "## Data-Quality Guards",
  "",
  paste0("- Wait-time contamination guard (mysterycall_guard_contaminated_wait): ", qc$guard),
  paste0("- Reached but no appointment date recorded: ", qc$included_na_appt, " calls ",
         "(these are the rows the strict offer definition scores as refusals)"),
  paste0("- Excluded but carrying an appointment date: ", qc$excluded_with_appt, " calls"),
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
  "- `mysterycall_access_cascade.csv`",
  "- `mysterycall_access_cascade_by_scenario.csv`",
  "- `mysterycall_reach_by_scenario.csv`",
  "- `mysterycall_offer_by_scenario.csv`",
  "- `mysterycall_offer_by_scenario_broad.csv`",
  "- `mysterycall_paired_reached_mcnemar.csv`",
  "- `mysterycall_service_prevalence.csv`",
  "- `mysterycall_missingness_mcar.csv`",
  "- `caller_by_scenario.csv`",
  "- `caller_rates.csv`",
  "- `caller_dominance_by_scenario.csv`",
  "- `exclusion_crosswalk.csv`",
  "- `restriction_checkbox_review.csv`",
  "- `matched_reached_wide.csv`",
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
