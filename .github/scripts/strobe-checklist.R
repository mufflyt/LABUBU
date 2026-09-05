#!/usr/bin/env Rscript
# ── STROBE checklist (cross-sectional) ────────────────────────────────────────
# Obstetrics & Gynecology requires a completed STROBE checklist; the prior
# mystery-caller submission from this group (mufflyt/mystery_shopper,
# ONG-S-19-02390) carried one in its bundle.
#
# mysterycall_strobe_checklist() is not used here: it accepts only Poisson or
# negative-binomial model objects, and this study's primary outcome is a set of
# service prevalences rather than a count model. Rather than force an
# ill-fitting object through it, the checklist is generated here with the
# study's own answers, leaving only page numbers for the author to add.

output_dir <- "mysterycall_outputs"
cleaned    <- file.path(output_dir, "labubu_cleaned_analysis.csv")
if (!file.exists(cleaned)) stop(cleaned, " not found; run the pipeline first")

call_records <- readr::read_csv(cleaned, show_col_types = FALSE, progress = FALSE)
is_true <- function(x) x %in% c(TRUE, "TRUE", "True", 1, "1")
n_calls   <- nrow(call_records)
n_reached <- sum(is_true(call_records$reached))
n_service <- sum(is_true(call_records$analytic_inclusion))

item <- function(no, section, recommendation, response)
  tibble::tibble(item = no, section = section,
                 recommendation = recommendation, study_response = response,
                 page = "")

checklist <- dplyr::bind_rows(
  item("1a", "Title and abstract", "Indicate the design in the title or abstract",
       "Title and abstract identify this as a national secret-shopper (audit) study."),
  item("1b", "Title and abstract", "Balanced summary of what was done and found",
       "Structured abstract reports the service menu as primary and states that the access comparison was uninformative."),
  item("2", "Introduction", "Scientific background and rationale",
       "RRM service scope determines which patients can be served; national data were previously absent."),
  item("3", "Introduction", "State specific objectives and any prespecified hypotheses",
       "Primary: define the service menu. Secondary and exploratory: access by caller scenario. No power analysis was prespecified in the protocol; achieved precision is reported instead."),
  item("4", "Methods", "Present key elements of study design early",
       "Cross-sectional audit; each practice eligible for one call per scenario."),
  item("5", "Methods", "Setting, locations, and relevant dates",
       "United States, 2025-2026; RRM practices compiled from professional directories."),
  item("6", "Methods", "Eligibility criteria and selection",
       "National roster of RRM practices; call dispositions mapped to standard access-audit exclusion codes."),
  item("7", "Methods", "Define all outcomes, exposures, predictors, confounders",
       "Primary outcome: reported service menu. Secondary: appointment availability inferred from call documentation, strict and broad definitions. Reached and offer-eligible are distinct denominators."),
  item("8", "Methods", "Sources of data and measurement",
       "Trained callers using standardized scripts; responses entered in REDCap (pid 39546)."),
  item("9", "Methods", "Describe any efforts to address potential sources of bias",
       "Within-practice matched design for the secondary outcome; caller-overlap analysis reports which contrasts can be separated from caller effects; duplicate practice-scenario cells handled by a prespecified rule with first-vs-last sensitivity."),
  item("10", "Methods", "Explain how the study size was arrived at",
       "No a priori sample-size calculation was performed. The achievable sample was the national roster of RRM practices. Minimum detectable effects are reported for every paired contrast."),
  item("11", "Methods", "Explain how quantitative variables were handled",
       "Proportions with 95% Wilson or Clopper-Pearson intervals; wait time in business days, log-transformed and reported as geometric mean ratios."),
  item("12", "Methods", "Statistical methods, subgroups, missing data, sensitivity",
       "Exact McNemar for matched contrasts; mixed-effects logistic regression with practice random intercept; two-part hurdle model for wait; Mantel-Haenszel stratification where caller overlap permits. Missingness by arm reported in Appendix Table S2."),
  item("13", "Results", "Report numbers at each stage",
       sprintf("%d calls placed, %d reached a live office, %d completed the service interview; Figures 2 and 3.", n_calls, n_reached, n_service)),
  item("14", "Results", "Characteristics of study participants",
       "Practice-level characteristics and per-scenario cascade in Table 1 and Figure 3."),
  item("15", "Results", "Report numbers of outcome events or summary measures",
       "Service prevalences in Figure 1 and Appendix Table S3."),
  item("16", "Results", "Give unadjusted and, if applicable, adjusted estimates with precision",
       "All estimates reported with 95% confidence intervals. P-values are not reported for the exploratory access contrasts, with the reason stated in the text."),
  item("17", "Results", "Report other analyses done",
       "Strict vs broad availability, first-vs-last duplicate-call sensitivity, caller-stratified Mantel-Haenszel estimate."),
  item("18", "Discussion", "Summarise key results with reference to objectives",
       "Primary finding is the structural absence of donor-gamete and ART services."),
  item("19", "Discussion", "Discuss limitations, including bias and imprecision",
       "Derived availability outcome; caller-scenario confounding with no within-caller information for two of three contrasts; documentation completeness differing by arm; low reachability; single call per scenario."),
  item("20", "Discussion", "Cautious overall interpretation",
       "The service finding is stated as structural; the access comparison is stated as uninformative rather than null."),
  item("21", "Discussion", "Generalisability",
       "Findings describe the reachable subset of RRM practices nationally."),
  item("22", "Other", "Give the source of funding",
       "No external funding; COMIRB 25-2596."))

readr::write_csv(checklist, file.path(output_dir, "strobe_checklist.csv"))
base::message("STROBE          ", nrow(checklist), " items written to ",
              file.path(output_dir, "strobe_checklist.csv"))
base::message("  Page numbers are intentionally blank for the author to complete.")
