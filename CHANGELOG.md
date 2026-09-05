# Changelog

Notable changes to the LABUBU analysis and its CI. Entries are grouped by what
they change: the **science** (anything that moves an estimand or a definition),
the **instrument and data**, or the **machinery** that checks them.

Format loosely follows [Keep a Changelog](https://keepachangelog.com).

---

## 2026-09-05

A single session that rebuilt the study's primary outcome, corrected two data
defects that had reached committed artifacts, and built CI capable of catching
both classes.

### Science — outcome definition

- **Separated "reached" from "offered".** `contact_office` had aliased
  `analytic_inclusion`, so "appointment offered" *was* the analytic-inclusion
  filter: acceptance was 100% inside the analytic sample by construction, and
  the 10 reached-but-declined calls — the only unambiguous `offered = 0`
  events — were discarded. Denominators are now distinct: reached 108,
  offer-eligible 102, historical inclusion 98.
- **Derived an appointment-availability outcome.** The instrument never asked
  whether staff agreed to schedule the caller, so the outcome is inferred from
  call documentation: strict (an appointment date was recorded) as primary,
  broad (date *or* a concrete scheduling timeframe) as sensitivity. Availability
  75.7% / 42.4% / 50.0% by scenario.
- **Reported the definition-dependence as a finding.** Triad ORs move from
  0.04 and 0.09 (strict) to 0.31 and 0.29 (broad). Both definitions point the
  same direction; only the strict one lands far from the null. The manuscript
  states that direction is the defensible claim and magnitude should not be
  quoted without its definition.
- **Wait time reported as geometric mean ratios.** `mysterycall_lmm()` applies
  `log1p()` to the right-skewed wait and returns log-scale coefficients; these
  had been labelled "business days", reporting an intercept of 2.9 log-units as
  2.9 days. Now back-transformed from `$gmr_table` (reference geometric mean
  17.6 business days).
- **Added a two-part hurdle model** so obtainment and wait-given-obtained are
  estimated together, rather than a complete-case wait model conditioning on
  scenario-dependent missingness.

### Science — PI decisions (2026-09-05)

- **Duplicate practice-scenario calls.** "First call" was never a methodology;
  it was `match()` returning the first row, which could let a voicemail outrank
  the completed call that followed. Replaced: a failed attempt never determines
  a cell (2 cells), and two *completed* calls make the cell a protocol
  deviation excluded from the primary paired analysis (2 cells), with
  first-vs-last reported as sensitivity. Paired *n* moved both directions —
  Lesbian vs Single mother 21→22 (a recovered cell), Straight vs Lesbian 21→19
  (two excluded). Discordant counts and p-values unchanged.
- **Caller confounding is a design limitation, not something to adjust away.**
  Cramér's V 0.66; one caller placed 53/77 straight-couple calls and no
  single-mother calls. The caller-adjusted model is reported *only* as evidence
  that the two effects are not separately identifiable.
- **Restriction checkboxes excluded pending codebook resolution**, and now
  guarded in CI so they cannot silently enter a model, estimand or claim.

### Data and instrument

- **REDCap API checkbox encoding.** The API returns the option label when
  ticked and `""` when not; the browser export returns `"Checked"`/`"Unchecked"`.
  Matching only `"Checked"` zeroed every service and restriction variable
  against an API pull — cycle tracking went 93/98 → 0 with no error raised.
- **Phone numbers in committed artifacts.** Two records had a phone number
  typed into the practice-name field, so contact details propagated into every
  derived artifact, bypassing the `.gitignore` rule for raw exports. Redacted;
  affected records flagged for repair in REDCap.
- **Callers de-identified** to stable `Caller A`–`G` labels; `caller_raw` is no
  longer written.
- **`redcap_pull.R` is idempotent** — an export byte-identical to one already
  present keeps the existing filename instead of creating a phantom "new" one.
- **Monte Carlo tests seeded**, so a rerun on identical data is bit-identical.

### Figures

- **STROBE flow given a white background.** It was 72% fully transparent:
  black text on transparency renders correctly on a white page and disappears
  in any dark viewer. Fixed upstream in `mufflyt/mysterycall#260` and re-saved
  locally at the pinned SHA.
- **Added a per-scenario STROBE panel** (`fig0b`), which makes the study's
  central asymmetry visible in the figure: the three arms enter the funnel at
  comparable widths (39/37/32 reached) and leave at very different ones
  (28/14/15 in the wait analysis).

### CI

- **18 scientific invariants**, each with a negative control; a coverage audit
  fails the build if any check lacks one.
- **Proof of execution**: outputs are wiped before the pipeline runs, and a
  completion receipt is written only after every expected artifact exists and
  the denominator cascade nests.
- **Row-level data contract** — 18 assertions reported with offending record
  ids.
- **Manuscript renders in CI** and its headline numbers resolve through a named
  claims table.
- **Nightly opens a review PR instead of rewriting `main`**, and only when a
  *result* changed. Reaching that took five rounds; see
  `docs/APPENDIX-lessons.md`.
- **Pinned `mysterycall` by SHA** in one file that all workflows read.
- **Privacy, docs-sync, workflow-contract and CI-contract checks** added.

---

## Before 2026-09-05

See git history. The analysis existed and ran; what it did not have was any
mechanism to notice when it stopped being correct.
