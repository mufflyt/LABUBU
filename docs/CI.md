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
| `scientific gate` | The committed outputs satisfy 27 scientific invariants, and the gate is provably able to fail | Only `yaml` |
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
`scientific-gate.R`, and `check-reference-crosscheck.R` (recomputes values against independent reference formulas).

`pipeline execution` deletes `mysterycall_outputs/` before running. It then
runs, in order: `check-lockfile.R`, `preflight-env.R`, the pipeline,
`provenance.R`, `pipeline-receipt.R`, `data-contract.R`, `estimand-report.R`,
`manuscript-claims.R`, `scientific-gate.R`, `check-reference-crosscheck.R`, `check-manuscript-render.R`. That is
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

27 invariants, in `.github/scripts/scientific-gate.R`. Each is a *structural*
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
| `manuscript/references-consistent` | A citation with no reference entry, a reference nobody cites, or numbering out of first-appearance order |
| `manuscript/sdc-items-resolve` | A supplemental item promised in the manuscript that the supplement never contains, or vice versa |
| `manuscript/no-duplicate-tables` | A repeated main-text table number, or a table printed in both the manuscript and the supplement |
| `manuscript/abstract-and-precis-within-limits` | Abstract over 300 words or precis over 25 |
| `pipeline/default-export-resolvable` | A hardcoded default export filename, which rots as soon as that export is archived |
| `ci/checks-cannot-silently-skip` | A check wrapped in `try()`, which lets a missing input pass as success |
| `ci/no-duplicate-script-registration` | One script enforced twice in the CI contract |
| `fixture/preserves-practice-structure` | A fixture whose pseudonymisation has split practices apart and destroyed its triads |
| `privacy/no-practice-names-in-submission-artifacts` | A practice or clinician name reaching the rendered manuscript, supplement or cover letter |
| `figures/opaque-background` | A figure saved with a transparent background, invisible in dark viewers |
| `restriction/excluded-from-inference` | The restriction checkboxes entering a model, estimand or claim while their meaning is unresolved |
| `manuscript/sdc-items-resolve` | A supplemental digital content item cited in text but missing from the supplement file |
| `manuscript/no-duplicate-tables` | Duplicate table headers or numbering in the manuscript |
| `manuscript/abstract-and-precis-within-limits` | Abstract or precis word count exceeding Green Journal limits |
| `pipeline/default-export-resolvable` | Pipeline failing to locate a valid export CSV |
| `ci/checks-cannot-silently-skip` | Checks silently skipping without explicit SKIP() classification |
| `ci/no-duplicate-script-registration` | Multiple registration of the same check ID |
| `fixture/preserves-practice-structure` | De-identification fixture fragmenting triads or practice keys |

Beyond the gate, four scripts assert things the gate cannot:
`data-contract.R` (18 row-level assertions, reported with offending record
ids), `pipeline-receipt.R` (the analysis actually ran and its denominators
nest), `check-reference-crosscheck.R` (recomputes values against independent reference formulas), and `check-manuscript-render.R` (the paper still knits).

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

## Borrowed strategies and attribution

Four of the checks here are adapted from sibling repositories rather than
invented locally. Recording the debt is not a courtesy: it tells a reader where
the fuller version of each idea lives.

| Technique | Borrowed from | What it does here |
|---|---|---|
| Independent reference implementations | [`mufflyt/isochrones-ci`](https://github.com/mufflyt/isochrones-ci), `test-statistics-crosscheck.R` | `tools/reference_implementations.R` recomputes Wilson intervals, exact McNemar, paired MDE and business-day waits from the published formulae, never calling `mysterycall`. `check-reference-crosscheck.R` requires agreement. |
| Metamorphic tests | `mufflyt/isochrones-ci`, `test-metamorphic.R` | `check-metamorphic.R` re-runs the pipeline under row shuffling and practice relabelling and requires every estimand to be unchanged. |
| Mutation / sabotage testing | `mufflyt/isochrones-ci`, `test-mutation-sabotage.R` | `mutation-sabotage.R` breaks the analysis code in plausible ways and requires a check to go red for each. |
| Caller ICC and precision bounds | `mufflyt/lizeth` (Acosta & Muffly), `caller_icc.R` and `null_verification.R` | Quantifies caller confounding, and reports what the paired intervals exclude rather than only what the design could detect. |

The governing arguments are quoted at the top of each script. The one worth
repeating is `isochrones-ci`'s reason for existing at all:

> A test suite that lives inside the code it tests shares that code's blind
> spots. If a helper is subtly wrong, both the implementation and its tests use
> the wrong helper, and the suite certifies the wrong answer with total
> confidence.

### Regression invariants

Seven checks exist because the mistake happened here, not because it was
imagined. Each names its incident in the source so nobody deletes it later
wondering what it guarded:

- a supplement promised in the manuscript that did not exist, with three of its
  tables printed inline in the main text instead;
- two Table 1s after a restructure, and later the same appendix tables shipped
  in both documents;
- an abstract and precis that had to be cut by hand to meet the journal limits;
- a default export filename that rotted the moment that export was archived,
  so the pipeline would not run on its own;
- a check wrapped in `try()`, which passed while its input was missing;
- one script registered twice in the CI contract by two people independently;
- a fixture whose pseudonymisation split practices apart and destroyed 34 of
  its complete triads, after which it certified a pipeline that could no longer
  see triads at all.

The last one bit a third time while its own negative control was being written:
the injected pseudonyms ended in digits, which `normalize_practice()` strips as
call-list indices, so every row collapsed onto one practice that then held all
three scenarios and hid the defect. The control now uses letters.

### What the first runs found

Each technique earned its place on the first run rather than passing vacuously.

- **The reference cross-check found a real defect.** `mcnemar_mde_or()` built
  its rejection region from `qbinom(0.025, n, 0.5)`, which is not a valid 5%
  region: at seven discordant pairs it admits a split whose exact two-sided p
  is 0.125, and at two pairs it admits a "test" that rejects half the time
  under the null. Reported minimum detectable odds ratios of 8.1 and 9.0
  delivered about 44% power, not 80%. The exact values are 30.9 and 35.4, and
  one contrast has no attainable MDE at all. Monte Carlo confirmed both the
  defect and the correction. The manuscript understated its own underpowering
  roughly fourfold.

- **A metamorphic test caught its author first.** The practice-relabelling
  transformation initially reported 47 lost triads. That was the test's fault,
  not the pipeline's: relabelling raw strings splits practices that
  `normalize_practice()` deliberately collapses, and the replacement tokens
  ended in digits, which the normalizer strips as call-list indices, collapsing
  every practice onto one name. The repository's fixture builder had made the
  same mistake earlier. Tokens are now fixed points of the normalizer, asserted
  as such.

- **A mutant survived, and the reason was worth more than the mutant.**
  Reordering the duplicate-resolution preference list changed zero of thirty
  estimands. Ambiguous cells are excluded outright, so the rule never chooses
  between two valid calls, and the `"first"` branch sorts by call date and
  record id. The analysis is order-independent by construction. The mutant was
  replaced with the mistake that would actually break it.

Every other invariant in this repository is structural: it checks that a number
came from the right denominator, was labelled correctly, or was not aliased to
something else. None of them recompute a number, and all of them call the same
`mysterycall` package the pipeline calls. `check-reference-crosscheck.R` is the
first thing here that does not, and it found a real defect on its first run: a
minimum detectable odds ratio built from a `qbinom` rejection region, which is
not a valid 5% region and overstated power roughly twofold.

