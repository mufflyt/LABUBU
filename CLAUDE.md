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
  - Primary: mixed-effects logistic regression (`glmer`), acceptance ~ scenario.
  - Secondary: LMM, business-days wait ~ scenario.
  - Matched: exact McNemar (acceptance) + paired t/Wilcoxon (wait), each with a
    power/MDE statement — these are the **unconfounded** comparisons.
  - Sensitivity: GEE.
- **`figures_wait_time.R`** — raincloud / ridge / ECDF / within-practice-pair plots.
- **`app.R`** — Shiny explorer over `mysterycall_outputs/labubu_cleaned_analysis.csv`.

## Settled analytical decisions (don't relitigate)

1. **The unmatched marginal acceptance comparison is confounded — do not report
   it.** Single-mother calls landed disproportionately at high-acceptance
   practices (~70% accept-everyone vs ~14% at practices never called for SM),
   inflating single-mother acceptance to a misleading 64%. Within-practice,
   single mothers do slightly *worse* (~7 pts). Report only the paired analysis.
2. **Scenario comparisons are underpowered** (9–11 discordant practices; only a
   ~5–6× OR is detectable). Frame as exploratory with an explicit power floor.
3. **Lead the paper with the well-powered descriptives:** IUI 1%, IVF 1%, donor
   sperm 3%, cycle tracking 94%, overall offer rate 45%, concordance 69–77%.
4. **Finishing the single-mother arm is the highest-value action** — it
   de-confounds the comparison and roughly doubles the effective sample
   (targeted lists: `mysterycall_outputs/single_mother_calls_priority1_triads.csv`
   and `..._priority2_pairs.csv`).

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
