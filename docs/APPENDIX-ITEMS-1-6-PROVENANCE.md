# Appendix: provenance audit of the six analytic corrections

**Question asked:** are all six of the mystery-call analytic corrections
actually present in committed, active, reproducible code, or only claimed?

**Answer:** all six are `COMMITTED_AND_ACTIVE`. Every headline value reproduces
exactly from a clean clone. Audit run 2026-09-09 against `main` at `eca5f10`.

This document exists because "the work is done" is a claim, and a claim about
code should be checkable. `tools/verify_reported_values.R` is the runnable half
of it.

---

## Method

A fresh `git clone --local` of `main`, the pinned REDCap export copied in, and
the pipeline plus `estimand-report.R` run from scratch. Nothing was read from
prior terminal output or from the working tree.

## The six items

| Item | Where | Verdict |
|---|---|---|
| 1. Three distinct denominators; `contact_office` means reached | `evaluate_labubu_mysterycall.R:281-291` | `COMMITTED_AND_ACTIVE` |
| 2. Strict `appt_offered` and `appt_offered_broad` | `:326-338` | `COMMITTED_AND_ACTIVE` |
| 3. Hurdle model on the live analysis path | `:1013-1018` | `COMMITTED_AND_ACTIVE` |
| 4. MCAR, contamination guard, caller diagnostics | `:657, :899, :916` | `COMMITTED_AND_ACTIVE` |
| 5. Analysis and manuscript outputs | 30 estimands, 20 claims | `COMMITTED_AND_ACTIVE` |
| 6. CI gate and invariants | `.github/scripts/scientific-gate.R` | `COMMITTED_AND_ACTIVE` |

### Item 1 — denominators

```r
dat$reached      <- na_false(exclusion_xw$reached[xw_i])
dat$in_offer_den <- na_false(exclusion_xw$in_logistic[xw_i])
dat$contact_office <- dat$reached   # NOT "an appointment was offered"
```

Three levels from `mysterycall_exclusion_crosswalk()`. Guarded by
`outcome/offer-not-aliased-to-inclusion`, `cascade/monotonic` and
`denominators/distinct-levels`.

### Item 2 — strict and broad offer

Strict scores an explicit "not accepting new patients" as a hard 0 regardless
of dates. Broad additionally credits a concrete scheduling timeframe. Guarded
by `outcome/offer-has-negative-events` (43 events) and
`outcome/reached-refusals-retained` (4 rows).

### Items 3 and 4 — wiring, not just presence

Presence in source is not enough; the question is whether the generated outputs
use it. The hurdle model appears five times in
`mysterycall_evaluation.md` and MCAR twice, so both are on the live path rather
than dead code. Five caller artifacts are generated and non-empty.

## Values reproduced from the clean clone

| quantity | asserted | reproduced |
|---|---|---|
| reached / eligible / inclusion | 108 / 102 / 98 | **108 / 102 / 98** |
| strict offer, straight / lesbian / single mother | 75.7 / 42.4 / 50.0 | **75.68 / 42.42 / 50.00** |
| OR triad, lesbian | 0.04 (0.01-0.28) | **0.04 (0.01-0.28)** |
| OR triad, single mother | 0.09 (0.01-0.65) | **0.09 (0.01-0.65)** |
| OR broad, lesbian | 0.31 (0.08-1.25) | **0.31 (0.08-1.25)** |
| OR broad, single mother | 0.29 (0.06-1.27) | **0.29 (0.06-1.27)** |
| Cramer's V | 0.66 | **0.664** |

`30 checks, 30 passed, 0 failed, 0 skipped` on the clean clone.

## What the audit did not find, and why that matters

**No missing work, and therefore no commit.** The instruction that prompted this
audit asked for a commit containing the six items. Producing one would have
meant an empty or fabricated commit. `git status` was clean, `main` in sync with
origin, and the code demonstrably present. The correct output of an audit that
finds nothing wrong is a report, not a commit.

**Two premises in the request were wrong and are recorded here so the confusion
is not repeated.** PR #750 and `stash@{0}` belong to `mufflyt/isochrones`, a
different repository; LABUBU has no open PRs and no stash entry. Carrying
context between repositories is easy to do and produces instructions that cannot
be satisfied.

## One limitation of the history

All six items landed in a single commit, `38afacc` ("Separate reached from
offered; add scientific gate to CI (#1)"), with later refinements in `1ce2832`
(five borrowed validation techniques) and `eca5f10` (practitioner
stratification). That is accurate, but it means the history cannot attribute
individual items more finely than "one commit did items 1 through 6". If
per-item attribution is ever needed, this appendix is the record.

## Reproducing the audit

```
Rscript evaluate_labubu_mysterycall.R
Rscript .github/scripts/estimand-report.R
Rscript tools/verify_reported_values.R     # 14 assertions, exits non-zero on any drift
Rscript .github/scripts/scientific-gate.R  # 30 invariants
```
