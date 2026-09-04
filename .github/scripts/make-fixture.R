#!/usr/bin/env Rscript
# ── Build the CI fixture export ───────────────────────────────────────────────
# Raw REDCap exports are gitignored because they carry practice contact
# information, which leaves CI with no data and therefore no way to prove the
# pipeline actually runs. This derives a committed, de-identified export with
# the same schema and the same analytic structure.
#
# De-identified here means: practice identities and staff names are replaced,
# and free-text notes are dropped. Scenario, exclusion reason, dates, checkbox
# responses and service answers are preserved, because those ARE the analysis.
#
# Regenerate deliberately with: Rscript .github/scripts/make-fixture.R

source_export <- list.files(".", pattern = "^LABUBU_DATA_LABELS_.*\\.csv$")
if (!length(source_export))
  stop("no LABUBU_DATA_LABELS_*.csv in the working tree to derive a fixture from")

raw_export <- readr::read_csv(source_export[1], show_col_types = FALSE,
                              progress = FALSE)

practice_col <- "Physician Information, practice name"
caller_col   <- "Name of person completing form.  THANK YOU!"
notes_col    <- "notes"

# Stable, distinct pseudonyms. Deliberately not "Practice 001/002": near-
# duplicate detection keys on edit distance, and sequential numbering would
# trip it on every run.
clinic_words <- c("Alder", "Birchwood", "Cedarcrest", "Dovetail", "Elmgrove",
                  "Fernbank", "Goldleaf", "Harborview", "Ironwood", "Juniper",
                  "Kestrel", "Larkspur", "Meadowlark", "Northgate", "Oakhollow",
                  "Pinecrest", "Quarrystone", "Rosewater", "Stonebridge",
                  "Thistledown", "Umberfield", "Violetbrook", "Westmarch",
                  "Yarrowfield", "Zephyrhill")
state_tags <- c("AL", "CO", "FL", "GA", "IA", "KS", "MI", "MN", "NE", "OH",
                "PA", "TX", "VA", "WI")

# Map on the NORMALISED key, not the raw string. The pipeline collapses
# spelling variants via normalize_practice(); pseudonymising raw names first
# gives every variant its own pseudonym, fragmenting practices and destroying
# the triad structure the study is built on (48 triads became 14). Pull the
# real function out of the pipeline so the fixture collapses identically.
pipeline_src <- readLines("evaluate_labubu_mysterycall.R", warn = FALSE)
fn_start <- grep("^normalize_practice <- function", pipeline_src)[1]
fn_end   <- fn_start - 1 + grep("^\\}$", pipeline_src[fn_start:length(pipeline_src)])[1]
eval(parse(text = paste(pipeline_src[fn_start:fn_end], collapse = "\n")))

raw_names <- raw_export[[practice_col]]
normalised <- ifelse(is.na(raw_names) | raw_names == "", NA_character_,
                     normalize_practice(raw_names))
real_practices <- sort(unique(normalised[!is.na(normalised)]))
pseudonyms <- vapply(seq_along(real_practices), function(i) {
  sprintf("%s FertilityCare (%s)",
          clinic_words[((i - 1) %% length(clinic_words)) + 1],
          state_tags[((i - 1) %/% length(clinic_words)) %% length(state_tags) + 1])
}, character(1))
# Guarantee uniqueness when the roster exceeds the word list.
pseudonyms <- make.unique(pseudonyms, sep = " Annex ")
names(pseudonyms) <- real_practices

fixture <- raw_export
fixture[[practice_col]] <- unname(pseudonyms[normalised])

real_callers <- sort(unique(trimws(fixture[[caller_col]])))
real_callers <- real_callers[nzchar(real_callers) & !is.na(real_callers)]
caller_labels <- stats::setNames(
  paste("Caller", LETTERS[seq_along(real_callers)]), real_callers)
fixture[[caller_col]] <- ifelse(
  trimws(fixture[[caller_col]]) %in% names(caller_labels),
  unname(caller_labels[trimws(fixture[[caller_col]])]),
  fixture[[caller_col]])

if (notes_col %in% names(fixture)) fixture[[notes_col]] <- NA_character_

fixture_path <- "tests/fixtures/LABUBU_DATA_LABELS_fixture.csv"
readr::write_csv(fixture, fixture_path, na = "")

base::message("Fixture written: ", fixture_path)
base::message("  rows: ", nrow(fixture),
              " | practices pseudonymised: ", length(real_practices),
              " | callers relabelled: ", length(real_callers))
base::message("  notes column cleared: ", notes_col %in% names(fixture))
