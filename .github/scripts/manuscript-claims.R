#!/usr/bin/env Rscript
# ── Manuscript claims ─────────────────────────────────────────────────────────
# Every headline claim the manuscript makes, with an explicit id, derived from
# ONE source: the estimand table the pipeline already produced.
#
# The risk this addresses is two scripts computing superficially similar
# statistics with different denominators -- an offer rate over "included calls"
# in one place and over "offer-eligible calls" in another, both plausible, both
# labelled "offer rate". Routing the manuscript through named claim ids makes
# that divergence impossible to express silently: a claim either resolves to a
# row here or the render fails.

output_dir    <- "mysterycall_outputs"
estimand_path <- file.path(output_dir, "estimands.csv")
claims_path   <- file.path(output_dir, "manuscript_claims.csv")

if (!file.exists(estimand_path))
  stop("estimands.csv is absent; run .github/scripts/estimand-report.R first")

estimands <- readr::read_csv(estimand_path, show_col_types = FALSE,
                             progress = FALSE)

value_of <- function(id, field = "estimate") {
  row <- estimands[estimands$estimand_id == id, ]
  if (!nrow(row)) NA_real_ else row[[field]][1]
}

# claim_id -> the estimand it draws on. The mapping is explicit so a reader can
# see exactly which quantity backs each sentence in the paper.
claim_map <- tibble::tribble(
  ~claim_id,                 ~estimand_id,                    ~claim,
  "offer_straight",          "offer_strict_straight_couple",  "strict offer prevalence, straight couple",
  "offer_lesbian",           "offer_strict_lesbian_couple",   "strict offer prevalence, lesbian couple",
  "offer_single_mother",     "offer_strict_single_mother",    "strict offer prevalence, single mother",
  "offer_broad_straight",    "offer_broad_straight_couple",   "broad offer prevalence, straight couple",
  "offer_broad_lesbian",     "offer_broad_lesbian_couple",    "broad offer prevalence, lesbian couple",
  "offer_broad_single",      "offer_broad_single_mother",     "broad offer prevalence, single mother",
  "or_triad_lesbian",        "or_triad_lesbian_couple",       "triad offer OR, lesbian vs straight",
  "or_triad_single_mother",  "or_triad_single_mother",        "triad offer OR, single mother vs straight",
  "or_broad_lesbian",        "or_broad_lesbian_couple",       "broad-definition OR, lesbian vs straight",
  "or_broad_single_mother",  "or_broad_single_mother",        "broad-definition OR, single mother vs straight",
  "gmr_wait_lesbian",        "gmr_wait_lesbian_couple",       "wait GMR, lesbian vs straight",
  "gmr_wait_single_mother",  "gmr_wait_single_mother",        "wait GMR, single mother vs straight",
  "service_cycle_tracking",  "service_cycle_tracking",        "cycle tracking offered",
  "service_iui",             "service_iui",                   "IUI offered",
  "service_ivf",             "service_ivf",                   "IVF offered",
  "n_calls",                 "n_all_calls",                   "calls placed",
  "n_reached",               "n_reached",                     "calls reaching a live office",
  "n_offer_eligible",        "n_offer_eligible",              "offer-eligible calls",
  "n_complete_triads",       "n_complete_triads",             "practices with all three scenarios",
  "caller_cramers_v",        "caller_scenario_cramers_v",     "caller x scenario association"
)

claims <- claim_map
claims$estimate <- vapply(claims$estimand_id, value_of, numeric(1))
claims$lower    <- vapply(claims$estimand_id, value_of, numeric(1), field = "lower")
claims$upper    <- vapply(claims$estimand_id, value_of, numeric(1), field = "upper")
claims$n        <- vapply(claims$estimand_id, function(id) {
  row <- estimands[estimands$estimand_id == id, ]
  if (!nrow(row)) NA_real_ else as.numeric(row$n[1])
}, numeric(1))

unresolved <- claims$claim_id[is.na(claims$estimate)]
if (length(unresolved))
  stop("claims resolve to no estimand: ", paste(unresolved, collapse = ", "),
       " -- estimands.csv and the claim map have diverged")

readr::write_csv(claims[, c("claim_id", "claim", "estimand_id",
                            "estimate", "lower", "upper", "n")], claims_path)
base::message("CLAIMS          ", nrow(claims), " written to ", claims_path)
