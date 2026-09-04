# LABUBU CI

What a green check actually means, and what it does not.

The job of CI here is not "did the R script exit successfully". It is: did the
intended study execute on the intended data, produce fresh outputs, preserve
the study's scientific definitions, keep the manuscript synchronised with those
outputs, and leave evidence that all of that happened.

## On every pull request

Three jobs run.

| Job | What it proves | Needs data? |
|---|---|---|
| `scientific gate` | The committed outputs satisfy 13 scientific invariants, and the gate is provably able to fail | No — base R only |
| `pipeline execution` | The analysis code runs and *regenerates* its outputs from scratch | Committed fixture |
| `re-derive from REDCap` | Full run against live REDCap | Manual dispatch only |

`scientific gate` installs nothing. It reads committed CSVs with base R, so an
unrelated CRAN outage cannot take down the study's validation. (This is not
hypothetical: `Deriv` was archived from CRAN mid-project and took `glmmTMB`
down with it.)

`pipeline execution` deletes `mysterycall_outputs/` before running. That is
deliberate — the dangerous failure is code changing, the analysis silently not
running, and CI validating last week's CSVs. Wiping first makes a stale file
unable to masquerade as a fresh one.

## Nightly

Pulls from REDCap, re-derives everything, runs the gate — and if the outputs
differ from `main`, **opens a pull request**. It does not commit to `main`.

It used to. On 2026-09-04 it auto-committed `f1b3fb6`, which silently removed
the two-part hurdle model from the report because `glmmTMB` was missing from
the runner. The gate passed, because at that time no invariant covered "a model
vanished". A scheduled job must not change reported results without review.

## The scientific gate

13 invariants, in `.github/scripts/scientific-gate.R`. Each is a *structural*
claim, not a snapshot of today's numbers.

| Check | Protects against |
|---|---|
| `outcome/offer-not-aliased-to-inclusion` | The original defect: `contact_office <- analytic_inclusion`, making acceptance 100% by construction |
| `outcome/offer-has-negative-events` | An outcome with no negatives, which cannot be modelled |
| `outcome/reached-refusals-retained` | Stated refusals dropped from the denominator — the only unambiguous `offered = 0` events |
| `cascade/monotonic` | Impossible cascade ordering (eligible > reached) |
| `data/all-exclusion-reasons-mapped` | A new free-text reason silently becoming `NA` and shrinking every denominator |
| `data/checkbox-encoding-parsed` | REDCap's two checkbox encodings; the API form once zeroed every service variable |
| `data/no-unresolved-near-duplicate-practices` | A spelling variant fragmenting a practice and deflating triads |
| `report/wait-reported-as-gmr-not-days` | Log-scale coefficients reported as differences in business days |
| `report/models-present` | A missing optional package silently deleting a model from the report |
| `report/caller-confounding-reported` | The caller/scenario confounding disappearing from the write-up |
| `manuscript/no-hardcoded-statistics` | Literal statistics drifting away from the data |
| `provenance/md5-matches-repo-export` | Provenance describing a different export than the one analysed |
| `denominators/distinct-levels` | Denominators collapsing into one another |

### Why the gate has its own test suite

`.github/scripts/gate-selftest.R` injects each defect into a scratch copy and
asserts the gate turns red. A gate that only demonstrates its happy path is
decoration.

Coverage is **enforced, not counted**: every case declares the check ID it
covers, the suite parses the gate's own check IDs from source, and any check
with neither a negative control nor an explicit `EXEMPT` entry fails the suite.
Adding a gate check without a control fails CI.

## Snapshot values vs. invariants

The gate never asserts that offer rates are 75.7% / 42.4% / 50.0%, or that
Cramér's V is 0.66. A legitimate data correction may change all of those.

It asserts the *structure*: correct denominator, refusals retained, outcome not
aliased, models present, correct reporting scale. An invariant failing means
**the analysis became invalid**. A number changing means **the answer changed** —
different things, deliberately not conflated.

`ci-results/denominator-audit.csv` records the cohort every run so drift is
visible without reading a log.

## How `mysterycall` is pinned

One file: `.github/mysterycall-sha.txt`. All workflows read it, and
`check-workflow-contract.R` fails if any hard-codes a different SHA.

To update it deliberately: change the SHA, re-run the pipeline, inspect the
gate, inspect the changed estimands, render the manuscript, then merge. A
change in another repository must never silently change LABUBU results.

## The fixture

`tests/fixtures/LABUBU_DATA_LABELS_fixture.csv` is a committed, de-identified
export. Practice names are pseudonyms, callers are `Caller A`/`B`/…, free-text
notes are stripped. Regenerate with `.github/scripts/make-fixture.R`.

Pseudonyms are assigned on the *normalised* practice key, so variants that
collapse in the real data collapse identically here. Its denominators match the
real export exactly (234 calls, 108 reached, 102 offer-eligible, 48 triads).

## What CI cannot do

- It cannot tell you the offer outcome is a **derived proxy**. REDCap has no
  "did they agree to schedule you?" field. Strict and broad definitions give
  triad ORs of 0.04 and 0.31; that gap is a measurement limitation, not a bug.
- It cannot fix **caller confounding**. Caller and scenario are not separately
  identifiable in this design. CI only guarantees the diagnostic stays visible.
- It cannot adjudicate the **restriction checkboxes**, whose coding is ambiguous.

## Recommended required checks

Not enabled — branch protection is unchanged. Recommended:

- `scientific gate`
- `pipeline execution`

`re-derive from REDCap` should stay optional: it depends on an external API and
a token, and a required check must not be able to fail for reasons unrelated to
the code under review.
