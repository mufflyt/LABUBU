# LABUBU — Mystery-Caller Study of Restorative Reproductive Medicine Practices

[![COMIRB 25-2596](https://img.shields.io/badge/IRB-COMIRB_25--2596-blue.svg)](https://comirb.ucdenver.edu)
[![REDCap PID 39546](https://img.shields.io/badge/REDCap-PID_39546-red.svg)](https://redcap.ucdenver.edu)
[![R 4.4+](https://img.shields.io/badge/R-4.4%2B-276DC3.svg)](https://www.r-project.org/)
[![Package mysterycall](https://img.shields.io/badge/Package-mysterycall_v1.6.3-green.svg)](https://github.com/mufflyt/mysterycall)
[![Provenance Generated](https://img.shields.io/badge/Provenance-Auto--Generated-orange.svg)](PROVENANCE.md)

Secret-shopper (audit) study of Restorative Reproductive Medicine (RRM) practices across the United States. Each practice is called once per **scenario** — *straight couple*, *lesbian couple*, *single mother using donor sperm* — to evaluate whether willingness to schedule (appointment acceptance) and business-day wait times differ systematically by caller identity.

- **Study Design:** Within-practice paired comparison (practice entered as random intercept).
- **Principal Investigator:** Dr. Tyler Muffly, MD (Denver Health / University of Colorado).
- **Data Source:** REDCap project **pid 39546** (`redcap.ucdenver.edu`).
- **Modeling Engine:** [`mysterycall`](https://github.com/mufflyt/mysterycall) R package (external statistical engine).

---

## ⚡ Quick Start (One-Command Refresh)

The primary entry point for this repository is **`refresh.R`**. When a new export lands or prior to running reports, execute a single command from the repository root:

```sh
# Option A: Auto-detect newest export in ~/Downloads or repo root
Rscript refresh.R

# Option B: Pull directly from REDCap API (requires REDCAP_LABUBU_TOKEN in ~/.Renviron)
Rscript refresh.R --pull
```

`refresh.R` automatically:
1. Copies the latest REDCap LABELS export into the repository root.
2. Archives superseded raw exports to `Old_redcap/`.
3. Executes full cleaning and statistical modeling via `evaluate_labubu_mysterycall.R`.
4. Renders all 5 high-resolution wait-time figures via `figures_wait_time.R`.
5. Updates cryptographic fingerprints and audit trail in `PROVENANCE.md` via `provenance.R`.
6. Prints a concise before/after delta of records, completed triads, missing calls, and name warnings.

To check call progress without triggering a full model re-run:
```sh
Rscript call_progress.R
```

---

## 📊 Provenance & Denominator Cascade

> [!IMPORTANT]
> Every figure, table, and report in `mysterycall_outputs/` is cryptographically fingerprinted in **[`PROVENANCE.md`](PROVENANCE.md)** — including input file MD5 checksums, git commit hashes, package versions, creation timestamps, and exact sample sizes. `PROVENANCE.md` is **generated automatically by `provenance.R` and must never be edited manually**.

Before quoting sample sizes (*n*) in a manuscript, abstract, or presentation, consult the **Denominator Cascade**:

| Level | Rule / Inclusion Criteria | Primary Usage |
|---|---|---|
| `all_records` | Every row present in the REDCap export | Gross export record counts only |
| `analytic_inclusion` | Contacted & eligible calls (`Reason for exclusions == "Included..."`) | Acceptance models, service mix descriptives |
| `wait_subset` | Included **and** achieved an observed, valid appointment date | Wait-time distributions (Figs 1–3, LMM model) |
| `within_practice_pairs` | Wait subset restricted to practices called under $\ge 2$ scenarios | Within-practice paired analyses (Fig 4) |

> [!WARNING]
> **No figure uses the total record count.** Quoting the total record count under a wait-time figure overstates that figure's effective sample by approximately **4x**. Live values are maintained in `PROVENANCE.md`.

---

## 🔄 End-to-End Pipeline Architecture

```
                       ┌─────────────────────────┐
                       │  REDCap PID 39546 API   │
                       └────────────┬────────────┘
                                    │ redcap_pull.R (or manual CSV export)
                                    ▼
                       ┌─────────────────────────┐
                       │ LABUBU_DATA_LABELS_*.csv│  (gitignored)
                       └────────────┬────────────┘
                                    │
                                    │ refresh.R
                                    ▼
                  ┌───────────────────────────────────┐
                  │ evaluate_labubu_mysterycall.R     │ (uses mysterycall R pkg)
                  └─────────────────┬─────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
┌─────────────────────────┐┌──────────────────┐┌─────────────────────────────────┐
│ mysterycall_outputs/    ││ figures_wait_    ││ mysterycall_evaluation.md       │
│ labubu_cleaned_analysis ││ time.R           ││ (Full Markdown evaluation)      │
│ + 15 result CSVs        │└────────┬─────────┘└─────────────────────────────────┘
└────────┬────────────────┘         │
         │                          ▼
         │                 ┌──────────────────┐
         │                 │ figures/*.png    │ (5 publication PNGs)
         │                 └────────┬─────────┘
         │                          │
         └──────────────────────────┼──────────────────────────┐
                                    ▼                          ▼
                           ┌──────────────────┐       ┌─────────────────┐
                           │ provenance.R     │       │ manuscript.Rmd  │
                           └────────┬─────────┘       └────────┬────────┘
                                    ▼                          ▼
                           ┌──────────────────┐       ┌─────────────────┐
                           │ PROVENANCE.md    │       │ manuscript.html │
                           │ provenance.json  │       └─────────────────┘
                           └──────────────────┘
```

---

## 🛠️ Repository Scripts & Tools

| Script | Purpose & Description |
|---|---|
| [`refresh.R`](file:///Users/tylermuffly/labubu/refresh.R) | **One-command master orchestrator.** Handles export ingestion, archiving, execution, and delta reporting. |
| [`redcap_pull.R`](file:///Users/tylermuffly/labubu/redcap_pull.R) | Downloads labelled and raw exports directly from the REDCap API token. |
| [`evaluate_labubu_mysterycall.R`](file:///Users/tylermuffly/labubu/evaluate_labubu_mysterycall.R) | Core data cleaning, normalization, GLMER/LMM modeling, McNemar tests, and report generation. |
| [`figures_wait_time.R`](file:///Users/tylermuffly/labubu/figures_wait_time.R) | Generates publication-ready figures (raincloud, ridge plot, ECDF, within-practice pairs, 2x2 panel). |
| [`provenance.R`](file:///Users/tylermuffly/labubu/provenance.R) | Computes MD5 checksums, Git state, package versions, and denominator levels into `PROVENANCE.md`. |
| [`call_progress.R`](file:///Users/tylermuffly/labubu/call_progress.R) | Lightweight progress utility to count remaining single-mother calls and complete practice triads. |
| [`app.R`](file:///Users/tylermuffly/labubu/app.R) | Interactive Shiny application for exploring practice-level data and scheduling distributions. |
| [`labubu_mysterycall_manuscript.Rmd`](file:///Users/tylermuffly/labubu/labubu_mysterycall_manuscript.Rmd) | Reproducible IMRaD manuscript template rendering directly to `labubu_mysterycall_manuscript.html`. |

---

## 📈 Statistical Models & Analytical Framework

- **Primary Acceptance Model:** Mixed-effects logistic regression (`lme4::glmer`):
  $$\text{Appointment Offered} \sim \text{Scenario} + (1 \mid \text{Practice})$$
- **Secondary Wait-Time Model:** Linear mixed model on log-transformed business days:
  $$\log(1 + \text{Business Days}) \sim \text{Scenario} + (1 \mid \text{Practice})$$
- **Unconfounded Matched Inference:** Exact McNemar tests (acceptance) and paired $t$-tests / Wilcoxon signed-rank tests (wait times), reported alongside Minimum Detectable Effect (MDE) power floors.
- **Sensitivity Analysis:** Generalized Estimating Equations (`geepack::geeglm`).

---

## 📌 Settled Analytical Directives

> [!CAUTION]
> 1. **Do not report the unmatched marginal acceptance comparison.**
>    Single-mother calls disproportionately landed at high-acceptance practices (~70% acceptance rate vs ~14% at practices never called for single mothers), artificially inflating unmatched single-mother acceptance (64%). Within-practice paired analyses show single mothers actually face slightly lower acceptance (~7 percentage points lower). Report **only** paired analyses.
> 2. **Acknowledge statistical power limits explicitly.**
>    With ~11–13 discordant practices per contrast, scenario comparisons are underpowered to detect subtle odds ratios. Frame scenario contrasts as exploratory with explicit MDE floors.
> 3. **Lead with well-powered descriptive findings.**
>    Highlight practice service mix (e.g., cycle tracking ~94%, IUI 1%, IVF 1%, donor sperm 3%), overall appointment offer rate (~45%), and practice scenario concordance (69–77%).
> 4. **Prioritize completion of single-mother calls.**
>    Completing remaining single-mother calls eliminates residual confounding and maximizes paired sample efficiency. Targeted call lists: `mysterycall_outputs/single_mother_calls_priority1_triads.csv` and `..._priority2_pairs.csv`.

---

## 💡 Practical Gotchas & Safety Controls

- **Practice-Name Normalization:** Practice spelling variations can deflate triad counts by creating false singletons. Every refresh execution writes:
  - `mysterycall_outputs/practice_name_review_nearduplicates.csv`
  - `mysterycall_outputs/practice_name_review_singletons.csv`
  Skim these files after a refresh and add matching rules in `normalize_practice()` if duplicates exist. Phone numbers used as practice names must be resolved in REDCap.
- **Analytic Inclusion Criteria:** Use `Reason for exclusions == "Included where physician was able to be contacted"`. Do **not** filter on the REDCap `Complete?` field (which is marked complete for all records).
- **Security & API Tokens:** Raw REDCap exports (`LABUBU_DATA_*.csv`) contain practice contact details and are gitignored. The REDCap API token must reside in `~/.Renviron` as `REDCAP_LABUBU_TOKEN`, **never** committed to git.

---

## 📁 Repository Directory Structure

```
.
├── README.md                                   ← Repository overview and guide
├── CLAUDE.md                                   ← Key architectural & project context
├── PROVENANCE.md                               ← Auto-generated data audit trail
├── data_review.md                              ← Data quality audit of latest export
├── refresh.R                                   ← Master one-command refresh script
├── redcap_pull.R                               │ API retrieval script
├── evaluate_labubu_mysterycall.R               │ Cleaning & modeling engine
├── figures_wait_time.R                         │ Figure generator
├── provenance.R                                │ Audit trail generator
├── call_progress.R                             │ Call tracking utility
├── app.R                                       │ Interactive Shiny dashboard
├── labubu_mysterycall_manuscript.Rmd           │ Reproducible manuscript template
├── labubu_mysterycall_manuscript.html          │ Self-contained HTML manuscript
├── 25-2596 LABUBU Protocol.docx                │ IRB protocol document
├── 25-2596 LABUBU Debrief Letter.docx         │ IRB debrief documentation
├── Old_redcap/                                 ← Archived prior REDCap exports (gitignored)
└── mysterycall_outputs/                        ← Tracked model outputs & artifacts
    ├── labubu_cleaned_analysis.csv             │ Master analytic dataset
    ├── mysterycall_evaluation.md               │ Comprehensive Markdown evaluation report
    ├── matched_acceptance_wide.csv             │ Paired acceptance matrix
    ├── matched_wait_wide.csv                   │ Paired wait-time matrix
    ├── mysterycall_paired_acceptance_mcnemar.csv│ McNemar test results
    ├── mysterycall_paired_wait_within_practice.csv│ Paired wait-time comparisons
    ├── practice_scenario_coverage.csv          │ Practice triad completion tracking
    └── figures/                                └── Publication PNGs (figs 1-4 & panel)
```

---

## 🖥️ System Requirements & R Dependencies

- **R Version:** $\ge 4.4.0$
- **Required Packages:**
  ```r
  install.packages(c(
    "dplyr", "ggplot2", "ggbeeswarm", "ggridges", "patchwork",
    "scales", "forcats", "lme4", "geepack", "knitr", "rmarkdown"
  ))
  
  # External modeling package:
  remotes::install_github("mufflyt/mysterycall")
  ```

---

*For regulatory questions regarding COMIRB 25-2596, contact Dr. Tyler Muffly (PI).*
