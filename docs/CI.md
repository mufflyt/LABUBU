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
| `scientific gate` | The committed outputs satisfy 18 scientific invariants, and the gate is provably able to fail | Only `yaml` |
| `pipeline execution` | The analysis code runs and *regenerates* its outputs from scratch | Committed fixture |
| `re-derive from REDCap` | Full run against live REDCap | Manual dispatch only |

`scientific gate` installs one leaf package, `yaml`, and nothing else. It reads
committed CSVs with base R, so an outage in the *analysis* dependency stack
cannot take down the study's validation. (Not hypothetical: `Deriv` was
archived from CRAN mid-project and took `glmmTMB` with it.)

It runs, in order:
`check-workflow-contract.R` (are the workflows themselves sound),
`check-ci-contract.R` (does `config/ci_contract.yml` match the implementation),
`check-docs-sync.R` (is this file still true),
`gate-selftest.R` (can the gate fail),
then `scientific-gate.R`.

`pipeline execution` deletes `mysterycall_outputs/` before running. It then
runs, in order: `check-lockfile.R`, `preflight-env.R`, the pipeline,
`provenance.R`, `pipeline-receipt.R`, `data-contract.R`, `estimand-report.R`,
`manuscript-claims.R`, `scientific-gate.R`, `check-manuscript-render.R`. That is
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

18 invariants, in `.github/scripts/scientific-gate.R`. Each is a *structural*
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
| `privacy/callers-de-identified` | Staff names reaching a committed analysis artifact |
| `privacy/no-contact-details-in-artifacts` | Phone numbers or emails in committed outputs |
| `manuscript/claims-resolve` | A manuscript claim no longer backed by an estimand |
| `figures/opaque-background` | A figure saved with a transparent background, invisible in dark viewers |
| `restriction/excluded-from-inference` | The restriction checkboxes entering a model, estimand or claim while their meaning is unresolved |

Beyond the gate, three scripts assert things the gate cannot:
`data-contract.R` (18 row-level assertions, reported with offending record
ids), `pipeline-receipt.R` (the analysis actually ran and its denominators
nest), and `check-manuscript-render.R` (the paper still knits).

### Why the gate has its own test suite

`.github/scripts/gate-selftest.R` injects each defect into a scratch copy and
asserts the gate turns red. A gate that only demonstrates its happy path is
decoration.

Coverage is **enforced, not counted**: every case declares the check ID it
covers, the suite parses the gate's own check IDs from source, and any check
with neither a negative control nor an explicit `EXEMPT` entry fails the suite.
Adding a gate check without a control fails CI.

## Nightly drift: what counts as a result

`check-drift.R` compares the **analytic CSVs** and nothing else;
`estimand-diff.R` judges `estimands.csv`, holding point estimates to 1e-4 and
interval bounds to 5e-2 because bounds are far less numerically stable.

That split was learned the hard way. Three earlier rounds tried to list which
lines were "volatile" — timestamps, commit SHAs, export filenames, the package
banner — and a nightly with all of them merged still opened a spurious PR over
the platform triple (`x86_64-apple-darwin20` vs `x86_64-pc-linux-gnu`) and R's
`print()` widening a column when a number gains a digit. A nightly runs on a
Linux runner and compares against artifacts generated on a maintainer's Mac,
so environment metadata differs by construction and no pattern list can ever
be complete. Results live in the CSVs and the estimands; everything else is
narrative, figures, or metadata regenerated from them.

## Dependencies

`config/dependencies.lock.csv` records the 24 packages the analysis runs on.
Regenerate it deliberately with `write-lockfile.R`. `check-lockfile.R`
reports version drift rather than failing on it — a runner
will not match a laptop package-for-package — but fails when an essential
package is absent or `mysterycall` is off its pinned SHA. renv is deliberately
not used; see the lockfile PR for why.

## The CI contract

`config/ci_contract.yml` declares every required check, its layer, and the
workflow that runs it. `check-ci-contract.R` verifies declaration and
implementation agree in **both** directions: declared-but-unimplemented is a
check that exists only on paper, implemented-but-undeclared is one that
escaped review. Its `advisory` section records checks that are surfaced but
never enforced, currently `practice/one-call-per-scenario`.

`strobe-checklist.R` generates the completed STROBE checklist the journal
requires, using the study's own answers rather than the package helper, which
accepts only count models.

`check-docs-sync.R` asserts this file names every gate check and every CI
script, because documentation that silently falls behind is worse than none —
it is trusted. It caught this file describing thirteen checks when the gate had sixteen.

## Open decisions

`docs/OPEN-DECISIONS.md` holds questions CI has isolated but must not answer,
because each would change an estimand or the instrument: the duplicate
practice-scenario tie-break, restriction-checkbox coding, the derived offer
proxy, and caller confounding.

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
