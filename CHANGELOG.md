# Changelog

Notable changes to the LABUBU analysis and its CI. Entries are grouped by what
they change: the **science** (anything that moves an estimand or a definition),
the **instrument and data**, or the **machinery** that checks them.

Format loosely follows [Keep a Changelog](https://keepachangelog.com).

---

## 2026-09-06

### Science — the primary finding, stratified

- **Service menu split by practitioner type, answering the strongest objection
  to the primary finding.** A reviewer can say that pooling physicians with
  Creighton Model practitioners manufactures the absence of donor-conception
  services. Tested: among 39 interviewed calls to physician-led (MD/DO)
  practices, IUI and IVF were each offered by one, 2.6% (95% CI 0.5-13.2),
  against zero of 59 FertilityCare calls. The single practice offering IUI also
  offered IVF and donor sperm and was physician-led. New **Table 2**; the paired
  analysis moves to Table 3.
- **The division of labour is the cleanest contrast in the study.** Hormonal
  laboratory monitoring 87.2% of physician-led calls against 47.5% of
  FertilityCare calls, Fisher P<.001, with cycle tracking near-universal in
  both. Physicians perform the workup; practitioners teach cycle tracking.
- Added to the abstract, a Discussion paragraph on the two-provider structure,
  and Limitation 8 on the name-based classification.

### Machinery

- **New invariant `stratum/practitioner-type-not-derived-from-outcomes`.**
  Classification must come from credential tokens in the practice name, never
  from the services observed; the strata must partition the sample; and no row
  may use a denominator other than its stratum size. Deriving a stratum from the
  outcomes it explains would make the contrast true by construction, which this
  repository has done once before when a figure's colour grouping was derived
  from observed percentages. Both failure modes verified by injection. Gate is
  30 checks with 30 negative controls.
- **A zero-event confidence interval of zero width was found and fixed in the
  new code before it shipped.** `mysterycall_prevalence_ci()` returns no TRUE
  row when there are no events, and the obvious fallback reported 0.0% (0.0-0.0)
  for FertilityCare IUI, asserting certainty that no such practice offers it.
  The Wilson upper bound for 0/59 is 6.1%; `tools/reference_implementations.R`
  confirms the corrected value independently.
- **`tools/verify_reported_values.R`** reproduces all 14 headline values from
  committed outputs and exits non-zero on any disagreement.

## 2026-09-05 (evening)

Manuscript restructured around the service-menu finding and sent to coauthors.
A statistical defect that had understated the study's own underpowering was
found and corrected, and figures gained numeric coverage for the first time.

### Science — power and precision

- **The minimum detectable effect was wrong by roughly fourfold, and one
  contrast had none at all.** `mcnemar_mde_or()` built its rejection region from
  `qbinom(0.025, n, 0.5)`, which is not a valid 5% region: at seven discordant
  pairs it admits a split whose exact two-sided p is 0.125. Reported MDEs of
  OR 8.1 and 9.0 deliver about 44% power, not 80%. Exact values are OR 30.9 and
  35.4, and the Lesbian-vs-Single-mother contrast (2 discordant pairs) has **no
  attainable MDE**: the exact test cannot reject at any effect size. Confirmed
  by Monte Carlo before changing anything. Table 2 now prints "None attainable".
- **Caller confounding has a number.** Variance-components ICCs: 0.29 for
  reaching a live office, 0.31 for inferred availability, 0.36 for the
  business-day wait. Roughly a third of outcome variance tracks who dialled.
- **Precision bounds replace bare nulls.** `precision_bounds.csv` and Appendix
  Table S8 report what the paired intervals *exclude* on the percentage-point
  scale, not only what the design failed to detect.
- **Figure 1 and its own table disagreed.** The forest plot computed
  Clopper-Pearson intervals via `binom.test()` while Appendix Table S3 used
  Wilson. Both now use Wilson, computed once, and the legend says so.

### Instrument and data

- **The restriction checkbox is closed, not pending.** The data dictionary
  defines a ticked box as a restriction. The recorded data follow two
  incompatible conventions keyed to the caller — one caller ticked all three
  boxes on 19 of 24 entries (the inverse of the label), everyone else echoed the
  scenario they called as — and 25% of calls record no caller. No poll can merge
  two conventions after the fact. See `docs/PI-QUERY-restriction-checkbox.md`.
- **Practice and clinician names were about to ship in a public supplement.**
  `protocol_deviation_cells.csv` carries real names including individual
  clinicians with credentials. Both S5 tables now show study IDs only.
- **The pipeline could not run on its own.** The default `input_file` named an
  export archived to `Old_redcap/`. It now resolves the newest export and pulls
  from the REDCap API if none is present.

### Manuscript

- Restructured around the service menu as the primary outcome; Methods
  compressed 813 → 703 words; abstract to 267, précis to 22.
- Three miscitations fixed, including SAMPL cited as the source for the Wilson
  interval and a housing-discrimination study cited for the RRM clinical menu.
  References renumbered into Vancouver first-appearance order.
- Supplemental digital content created as a separate document (Tables S1–S8,
  Figure S1); three appendix tables had been printed inline in the main text
  while being listed as supplemental.
- Green Journal cover letter drafted, resolving its numbers through the same
  claims table the manuscript uses.

### Machinery

- **Gate grew from 18 to 29 invariants, each with a negative control** (32
  injected defects, all caught).
- **Five validation techniques adopted from sibling repositories**, documented
  with attribution in `docs/APPENDIX-borrowed-techniques.md`: independent
  reference implementations and metamorphic and mutation testing from
  `mufflyt/isochrones-ci`; caller ICC and precision bounds from
  `mufflyt/lizeth`.
- **`tools/reference_implementations.R`** recomputes every reported quantity
  from published formulae and never calls `mysterycall`. It found the MDE defect
  on its first run.
- **Figures now publish the data they plot.** `figures/plotted-values-match-tables`
  and `figures/strobe-counts-match-data` verify seven and six failure modes
  respectively. Previously every invariant read CSVs, models or text, and
  figures were the only artifact class carrying numbers with no numeric check.
- **Seven regression invariants added, one per mistake actually made here** —
  missing supplement, duplicate tables, over-length abstract, rotting default
  export, `try()` swallowing a failure, duplicate contract registration, and a
  fixture whose pseudonymisation destroyed its triads.
- `tools/reproduce.R` rebuilds every artifact from the export `PROVENANCE.md`
  names and fails if any estimand moved.

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
