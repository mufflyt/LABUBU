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

---

## 7. Lessons from the 2026-09-05 evening session

### The blind spot had a shape, and it was "figures"

Twenty-seven invariants passed while Figure 1 plotted Clopper-Pearson intervals
and Appendix Table S3 — captioned *numeric detail underlying Figure 1* — printed
Wilson intervals for the same six proportions. Donor sperm read 0.6–8.7 in the
figure and 1.0–8.6 in the table.

No check was wrong. Every one of the twenty-seven read a CSV, a model, or
manuscript text. `figures/opaque-background` inspects **pixels**. Figures were
the only artifact class carrying numbers with no numeric coverage at all, and
that is exactly where the error was.

**The rule, generalised:** a number is computed in exactly one place, and any
artifact that displays a number must publish that number. An opaque PNG cannot
be audited by anything. `fig5_service_forest_data.csv` and
`fig0_strobe_flow_data.csv` exist so the figures can be compared against the
tables they duplicate, and they are.

The corollary is uncomfortable and worth stating plainly: **coverage is not a
count of checks.** Twenty-seven felt like a lot. The right question is not "how
many checks do we have" but "which classes of artifact can currently ship a
wrong number without anything noticing".

### The user found it, not the CI, and the timing was the worst possible

The Figure 1 defect surfaced when a human opened the TIFF in Preview minutes
before emailing it to four coauthors. The bug was old — it had been in every
version of that figure — but nothing in hours of accumulated CI had ever looked
at it. When someone asks how to stop shipping errors after that happens, the
answer is a specific closable gap, not a defence of the existing machinery.

### Two agents in one working directory

A second agent was run against the same checkout while work was in progress. It
committed the in-flight, uncommitted changes as its own, then reported the
resulting registration gap as a defect it had discovered. Its fix duplicated
seven check-id registrations, and every contract check passed anyway, because
`check-ci-contract.R` compared declared ids to *gate* ids and never to each
other.

Consequences, in order of severity:

1. A real defect (duplicate ids) that nothing could see, now caught by
   `ci/no-duplicate-script-registration`, which compares ids as well as scripts.
2. An audit report claiming "100% success" and "publication-ready" describing a
   tree that contained that defect.
3. Wasted effort reconciling two sets of edits to the same files.

**Rule: give a second opinion its own clone.** Concurrent agents in one
directory produce findings that are artifacts of the race rather than of the
code.

### Inert mutants are findings, not failures

Two sabotage mutants survived. Neither was a hole in the suite:

- Reordering the duplicate-resolution preference list changes nothing, because
  ambiguous cells are excluded outright and the `"first"` branch sorts
  deterministically. **The analysis is order-independent by construction**,
  which is a property worth knowing and was not previously written down.
- Making `make_wide()` resolve an ambiguous cell positionally *is* a genuine
  order dependence — verified directly, it changes practice 65's lesbian-couple
  cell under row reversal — but it survived a pipeline-level shuffle because
  `mysterycall_business_days()` and `mysterycall_appointment_obtained()`
  normalise row order before `make_wide()` runs.

Both taught more than a killed mutant would have. Chase a survivor to its cause
before deleting it or weakening the check.

### A single random permutation is not a test

The row-order metamorphic check originally ran one shuffle. The dependence it
targets lives in a handful of duplicate cells, and one permutation has roughly a
one-in-four chance of leaving those pairs in their original relative order and
reporting a clean bill of health. It now runs three, matching `isochrones-ci`'s
`max(3L, n_random_worlds())`.

### Numbers that are both correct can still mislead

Table 1 reports 102 calls as offer-eligible; Figure 2 draws 100. Both are right:
102 reached a live office and were not excluded, and 100 of those carry a
recorded outcome (records 156 and 178 do not). Nothing needed a number changed —
but both were labelled "eligible", leaving a reader to guess which is the
mistake. The fix was a word. **Check labels for collisions, not just values.**
