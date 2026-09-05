# Appendix: why the CI is shaped this way

Every check in `.github/scripts/` exists because something specific went wrong.
This is that record. It is written down because the checks look like
over-engineering until you know what each one caught, and because several of
them were themselves wrong at first in instructive ways.

---

## 1. A check that passes for the wrong reason is worse than no check

Three checks written during this work passed while verifying nothing:

**The coverage audit read a stale artifact.** It enumerated the gate's checks
from `ci-results/scientific-gate.tsv` — a file produced by a *previous* run. It
passed locally because a stale copy was on disk, and failed in CI where none
was. The audit now parses check IDs from the gate's source, so it has no
ordering dependency. That is the same stale-artifact trap the pipeline receipt
exists to prevent, reproduced inside the tooling meant to prevent it.

**The restriction guard truncated its own search.** It scanned each model call
with `sub("\\).*$", "", text)`, cutting at the first closing paren — before
`outcome =` was ever reached. It reported PASS on an injected violation. A
commit message had already claimed it was verified.

**The figure-opacity check could not find `png`.** It failed in CI with
"cannot verify" because the package was installed locally and not on the
runner. This one is the counter-example: it *failed closed*, which is why the
gap surfaced within minutes instead of the guard sitting inert forever.

The rule that follows: **a check that cannot evaluate its condition must fail,
never skip.** And every check needs a negative control — an injected defect
that proves it can turn red. `gate-selftest.R` enforces that, and the coverage
audit fails the build if any gate check lacks one.

---

## 2. Verifying locally is not verifying

Three separate times, work that passed on this machine was wrong in the repo:

- The CI **fixture was never committed** — `.gitignore`'s `LABUBU_DATA_*.csv`
  rule is unanchored and silently swallowed `tests/fixtures/`. `git add -A`
  skipped it, and a commit message asserted it had been added.
- The first fixture **destroyed 34 triads** by pseudonymising raw practice
  names before `normalize_practice()` ran, so spelling variants stopped
  collapsing. Caught only by comparing denominators against the real data.
- The **STROBE re-save silently failed**, passing `compression = NULL` to
  `ggsave` for a PNG, which rejects the argument rather than ignoring it. The
  figure stayed transparent while the pipeline reported success.

`check-workflow-contract.R` now fails when a workflow references a file git
does not track. Clean-clone verification — `git clone` then run everything —
is the standard before merging anything consequential.

---

## 3. Drift: five rounds to ask the right question

The nightly opened nine spurious pull requests before this was right. Each
round fixed a real cause and missed the next:

| round | fixed | still opened PRs because |
|---|---|---|
| 1 | generation timestamps | commit SHAs, export filenames |
| 2 | SHAs, filenames, package banner | interval bounds moved 1.6% |
| 3 | bound tolerance on estimands | `manuscript_claims.csv` carried the same bounds |
| 4 | judged results, not prose | — |
| 5 | delegated the derived claims table | — |

Rounds 1–3 were all the same mistake: trying to enumerate which *lines* are
volatile. A nightly runs on a Linux runner and compares against artifacts built
on a maintainer's Mac, so environment metadata differs **by construction** —
platform triple, session-info package sets, and R's `print()` widening a column
when a number gains a digit. No pattern list can be complete.

The right question was **where do results live**: the analytic CSVs and
`estimands.csv`, both compared, everything else regenerated from them.

The fifth cause was found only because the stale PRs were *inspected* before
being closed rather than dismissed as noise.

---

## 4. Silent degradation is the failure mode of a wrapped pipeline

Every model call is wrapped in `tryCatch`, which is right for build survival
and wrong for an artifact that auto-commits. When `glmmTMB` went missing from
CI (its dependency `Deriv` was archived from CRAN), the two-part model simply
vanished from the report — and the nightly committed that thinner version over
the good one, with the gate passing because no invariant covered "a model
disappeared".

Hence `report/models-present`, which fails when the report says a model was
"not run", and `preflight-env.R`, which fails in seconds before the pipeline
writes anything.

`Deriv` also taught a second lesson: the newest archived version, 4.3.0, calls
`R_ClosureFormals()`, an R 4.5 C API entry, and cannot compile on the R 4.4.2
this project pins. "Newest archived" is the wrong heuristic; "the version
already proven against this R" is the right one.

---

## 5. What CI cannot establish

Worth stating plainly, because a wall of green checks invites the opposite
conclusion.

- **The offer outcome is a derived proxy.** No instrument item asked whether
  staff agreed to schedule. Strict and broad definitions give ORs of 0.04 and
  0.31. No test resolves that; only a new instrument item will.
- **Caller and scenario are not separately identifiable.** Cramér's V 0.66,
  with one caller placing 53/77 straight-couple calls and no single-mother
  calls. CI keeps the diagnostic visible; it cannot repair the design.
- **The restriction checkboxes have unknown semantics.** The codebook gives the
  label and choices but no field note and no branching logic, so it constrains
  nothing about how callers *recorded* the item. And 59 of 234 calls record no
  caller, so even unanimous answers leave a quarter unattributable.
- **Differential missingness by arm is unexplained.** "No call date recorded"
  is 6 / 19 / 12 across straight / lesbian / single-mother calls. That is a
  data-completeness asymmetry in a discrimination study and is not currently
  addressed in the manuscript.

---

## 6. Operational notes

- **`figures/opaque-background` verifies 2 figures in the `pipeline execution`
  job and 7 in `scientific gate`.** The execute job wipes outputs and runs only
  the pipeline, which draws `fig0` and `fig0b`; `figures_wait_time.R` is not
  run there. Not a defect, but the counts differ by design.
- **The nightly fires on merges to `main`**, not only on schedule, because its
  `push` trigger includes `**.R`. One merge produces one nightly.
- **`gh secret list` was empty until 2026-09-05.** The nightly's REDCap pull
  branch had never executed before that date.
- **Actions may create pull requests** (`can_approve_pull_request_reviews`),
  enabled 2026-09-05 so the nightly can open its drift PR. It bundles
  create-and-approve; the approve half matters if review approvals ever become
  required under branch protection.
