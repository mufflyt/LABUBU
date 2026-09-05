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
# Stable pseudonyms that are MUTUALLY DISTANT. The pipeline flags practice
# names as near-duplicates at edit distance <= 4 or normalised distance
# <= 0.15, to catch a spelling variant fragmenting a practice. Combinatorial
# names ("Alder FertilityCare (CO)" vs "Alder FertilityCare (FL)") differ by
# two characters and tripped that detector 178 times on the first fixture.
# Select greedily so no two pseudonyms are close enough to trip it.
pseudonym_pool <- as.vector(outer(
  c("Alder", "Birchwood", "Cedarcrest", "Dovetail", "Elmgrove", "Fernbank",
    "Goldleaf", "Harborview", "Ironwood", "Juniper", "Kestrel", "Larkspur",
    "Meadowlark", "Northgate", "Oakhollow", "Pinecrest", "Quarrystone",
    "Rosewater", "Stonebridge", "Thistledown", "Umberfield", "Violetbrook",
    "Westmarch", "Yarrowfield", "Zephyrhill", "Amberton", "Bramblewick",
    "Clearspring", "Duskwillow", "Everglade", "Foxglove", "Greenhollow",
    "Hazelmere", "Inglewood", "Jasperfield", "Kingsbarrow", "Lambswood",
    "Marshlight", "Nettlebed", "Orchardgate", "Pemberly", "Quillhaven",
    "Ravenscroft", "Silverbrook", "Tallowmere", "Underhill", "Vinecliff",
    "Wrenfield", "Yewbank", "Zinnia"),
  c("Fertility Associates", "Womens Health Center",
    "Reproductive Care Clinic", "Family Medicine Group",
    "Restorative Health Practice"),
  paste))

pool_distance <- adist(pseudonym_pool)
kept <- 1L
for (candidate in seq_along(pseudonym_pool)[-1]) {
  edit_d <- pool_distance[candidate, kept]
  norm_d <- edit_d / pmax(nchar(pseudonym_pool[candidate]),
                          nchar(pseudonym_pool[kept]))
  if (all(edit_d > 4) && all(norm_d > 0.15)) kept <- c(kept, candidate)
}
pseudonym_pool <- pseudonym_pool[kept]

# Map on the NORMALISED key, not the raw string. The pipeline collapses
# spelling variants via normalize_practice(); pseudonymising raw names first
# gives every variant its own pseudonym, fragmenting practices and destroying
# the triad structure the study is built on (48 triads became 14). Pull the
# real function out of the pipeline so the fixture collapses identically.
pipeline_src <- readLines("evaluate_labubu_mysterycall.R", warn = FALSE)
fn_start <- grep("^PHONE_RE <-", pipeline_src)[1]
fn_end   <- fn_start - 1 + grep("^\\}$", pipeline_src[fn_start:length(pipeline_src)])[1]
eval(parse(text = paste(pipeline_src[fn_start:fn_end], collapse = "\n")))

raw_names <- raw_export[[practice_col]]
normalised <- ifelse(is.na(raw_names) | raw_names == "", NA_character_,
                     normalize_practice(raw_names))
real_practices <- sort(unique(normalised[!is.na(normalised)]))
if (length(pseudonym_pool) < length(real_practices))
  stop("pseudonym pool holds ", length(pseudonym_pool), " mutually distant ",
       "names but ", length(real_practices), " practices need one; widen the ",
       "word lists rather than letting near-duplicates into the fixture")
pseudonyms <- stats::setNames(pseudonym_pool[seq_along(real_practices)],
                              real_practices)

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
