# LABUBU — Mystery-Caller Study of RRM Practices

Secret-shopper study of Restorative Reproductive Medicine (RRM) practices. Each
practice is called once per **scenario** — *straight couple*, *lesbian couple*,
*single mother (donor sperm)* — to test whether willingness to schedule and wait
time differ by caller identity. Within-practice design (practice = random
intercept). Private repo: `github.com/mufflyt/LABUBU`.

## Refresh with a new REDCap export (the common task)

When a new export lands in `~/Downloads` (files named
`LABUBU_DATA_LABELS_<date>.csv` and `LABUBU_DATA_<date>.csv`):

```r
Rscript refresh.R          # auto-detects newest export, runs everything, prints a before/after delta
```

`refresh.R` copies the newest LABELS export into the repo, archives older
exports to `Old_redcap/`, runs the analysis + figures, and reports what changed
(records, triads, missing single-mother calls, discordant pairs, near-duplicate
name warnings). To check call progress without a full re-run:

```r
Rscript call_progress.R    # how many single-mother calls remain / triads complete
```

## Pipeline

- **`evaluate_labubu_mysterycall.R`** — cleans the LABELS export and runs the
  models via the `mysterycall` package. Reads the file named in `input_file`
  (guarded: `refresh.R` overrides it; otherwise a default filename is used).
  Writes ~15 CSVs + `mysterycall_outputs/mysterycall_evaluation.md`.
  - Access cascade: `mysterycall_access_cascade()`, stage-by-stage denominators.
  - Primary: mixed-effects logistic regression (`glmer`), `appt_offered` ~
    scenario, on complete triads; plus a broad-definition sensitivity model.
  - Secondary: the same model on `reached` (what the pipeline used to call
    "acceptance").
  - Two-part: `mysterycall_hurdle_wait()` — offer and wait estimated jointly,
    instead of a complete-case wait model that conditions on scenario-dependent
    missingness.
  - Wait: LMM reported as geometric mean ratios (`$gmr_table`).
  - Matched: exact McNemar on the offer outcome and on reachability, each with a
    power/MDE statement. These remove practice selection but **not** caller
    confounding.
  - Caller diagnostics: caller x scenario crosstab, Cramér's V, per-caller
    rates, caller-adjusted model, `mysterycall_caller_drift()`.
  - Sensitivity: GEE. QC: `mysterycall_guard_contaminated_wait()`,
    Little's MCAR, `mysterycall_flag_*()`.
  - Figure: `mysterycall_strobe_flow()` -> `figures/fig0_strobe_flow.png`.
- **`figures_wait_time.R`** — raincloud / ridge / ECDF / within-practice-pair plots.
- **`app.R`** — Shiny explorer over `mysterycall_outputs/labubu_cleaned_analysis.csv`.

## Settled analytical decisions (don't relitigate)

1. **REACHED is not OFFERED — never collapse them.** `contact_office` used to
   alias `analytic_inclusion`, which made the "appointment offered" outcome the
   same variable as the inclusion filter: acceptance was 100% inside the
   analytic sample by construction, and the 10 reached-but-declined calls (the
   only unambiguous offered = 0 events) were discarded. The pipeline now uses
   `mysterycall_exclusion_crosswalk()` to keep three denominators apart —
   `reached` (108), `in_offer_den` (102), `analytic_inclusion` (98) — and
   reports them as an access cascade. `contact_office` now means "a live office
   answered".
2. **The offer outcome is a derived proxy, and that is the study's biggest
   measurement limitation.** REDCap has no "did they agree to schedule you?"
   item. `appt_offered` (strict) = an appointment date was recorded, with
   "Not accepting new patients" scored 0. `appt_offered_broad` (sensitivity)
   also credits a concrete scheduling timeframe. The strict/broad gap is large
   (triad OR 0.04 vs 0.31 for lesbian couples), so always report both.
   **Adding an explicit offer field to REDCap is the highest-value fix.**
3. **Caller is confounded with scenario and within-practice pairing does NOT
   fix it.** Cramér's V = 0.66; one caller placed 53/77 straight-couple calls
   and zero single-mother calls. Paired calls were dialled by different people,
   so a scenario contrast is also a caller contrast. Adjusting for caller
   inflates the scenario SEs to non-identifiability — report that as the
   evidence, not as a corrected estimate. **Randomize or block caller across
   scenarios in the next wave.**
4. **Scenario comparisons are underpowered** (2–8 discordant practices on the
   offer outcome; MDE OR 8.1–9.0). Frame as exploratory with an explicit power
   floor.
5. **Lead the paper with the well-powered descriptives:** IUI 1%, IVF 1%, donor
   sperm 3%, cycle tracking 95%, reach rate 46%. These rest on directly observed
   responses, not on the derived outcome, and are unaffected by caller
   assignment. IUI and IVF are each a single practice — say so.
6. **Wait-time estimates are geometric mean ratios, not days.**
   `mysterycall_lmm(auto_log = TRUE)` log-transforms a right-skewed outcome and
   returns log-scale coefficients; the back-transform is in `$gmr_table`. An
   intercept of 2.9 is 2.9 log-units (≈18 business days), not 2.9 days.
7. **The `restrictions` checkbox is unusable and the question is closed.**
   The codebook (`LABUBU_DataDictionary_2026-09-05.csv`) says a ticked box
   means a restriction applies to that group, with no note, branching logic or
   annotation. The data contradict it: one caller ticked all three boxes on 19
   of her 24 entries (= "serves nobody" under the label, plainly meaning the
   inverse), and every other caller only ever ticked the box matching the
   scenario they called as, which is a scenario echo carrying no information.
   Two incompatible conventions, keyed to caller, with 25% of calls recording
   no caller. **Do not attempt to recode or rescue it, and do not poll the
   callers** — see `docs/PI-QUERY-restriction-checkbox.md`. Fix the instrument
   next wave, not the analysis.
8. **Finishing the single-mother arm remains worthwhile** but does not fix
   items 1–3 (targeted lists:
   `mysterycall_outputs/single_mother_calls_priority1_triads.csv` and
   `..._priority2_pairs.csv`).

## Gotchas

- **Practice-name normalization** (`normalize_practice()` in the eval script) is
  the sneakiest failure mode: a new spelling variant silently becomes a singleton
  and deflates the triad count. Every run writes
  `practice_name_review_nearduplicates.csv` / `_singletons.csv` and prints a
  warning — after a refresh, skim these and add a rule if two keys are the same
  practice.
- Raw exports are gitignored (contact info). Keep them out of commits.
- Analytic inclusion = `Reason for exclusions == "Included where physician was
  able to be contacted"`, **not** the `Complete?` field.
