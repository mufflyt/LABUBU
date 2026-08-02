# Mystery Caller Study Data Review

Source file: `LABUBU_DATA_LABELS_2026-08-02_1616.csv` (201 records, MD5 `3bee40ec332e8f9e`)
Reviewed: 2026-08-02. Supersedes the 2026-06-24 review (176 records).
Artifact fingerprints: [`PROVENANCE.md`](PROVENANCE.md).

## Dataset Snapshot

- Records: 201
- Columns: 29
- Scenario distribution:
  - Lesbian couple: 83
  - Straight couple: 75
  - Single mother: 43
  - Missing scenario: 0
- `Complete?` is present in the export but should be ignored for analysis — see below.

## Resolved since the June 24 review

Four issues from the previous review have been fixed in REDCap and need no
further action:

1. **Missing scenario values are gone.** All 201 records now carry a scenario;
   previously 4 records (21, 22, 23, 49) had none.
2. **The included-vs-complete imbalance is gone.** Included-by-exclusion and
   included-and-complete are now the *same* 95 records, evenly split 33 / 33 / 29
   across straight / lesbian / single mother. The June 24 review flagged a 69-vs-58
   gap with a lopsided scenario split; that no longer exists.
3. **The future-dated call is resolved.** No call date now falls after the export
   date. Record 3 previously carried `2026-08-03`, which has since passed and is
   no longer anomalous.
4. **IUI/IVF are no longer uniformly zero.** Each is now checked on exactly one
   record, confirming the fields are reachable and were not silently broken.

## Key Analytic Denominator Issue

`Complete?` must not be used as the analytic inclusion flag. As of this export
**every one of the 201 records is marked Complete**, so the field has zero
discriminating power — using it as a denominator silently returns the whole
dataset.

The correct denominator is:

- `Reason for exclusions = Included where physician was able to be contacted`

Counts:

- Included by exclusion field: 95
  - Straight couple: 33
  - Lesbian couple: 33
  - Single mother: 29
- Included **and** complete: 95 (identical — the `Complete?` filter is a no-op)

Note that inclusion is not the denominator for the wait-time figures either.
Only 55 of the 95 included calls produced an appointment date. See the
[denominator cascade](PROVENANCE.md#2-denominator-cascade--read-this-before-quoting-any-n)
before quoting any *n*.

## Exclusion Reasons

Of the 106 excluded records:

| Reason | n |
|---|---|
| Went to voicemail | 77 |
| Number did not correspond to expected office/specialty | 8 |
| Greater than 5 minutes on hold | 6 |
| Not accepting new patients | 4 |
| Phone not answered or busy signal on repeat calls | 4 |
| Physician's personal phone | 4 |
| Closed medical system (e.g. Kaiser or military hospital) | 2 |
| *(missing)* | 1 |

Voicemail dominates exclusions at 73% of them. One record has no exclusion
reason recorded and is neither included nor assigned a reason; it should be
resolved in REDCap.

## Field Coding Concerns

**The transfer field is still not numeric, and has gotten worse.** All 151
non-missing values are non-numeric text — the field now contains only
`No transfers` and `One transfer`. The recode is still required:

- `No transfers` -> 0
- `One transfer` -> 1
- text with a numeric count -> numeric value
- blank -> missing, not zero

Restriction checkboxes remain ambiguous: the field asks, "Are there any
restrictions to the individuals you would provide care to?" A checked
`Straight couple` could mean either a restriction *against* straight couples or
a requirement *to be* one, depending on how staff interpreted it. This has not
been resolved and limits any analysis of those three fields.

No columns are 100% NA in this export, so there is nothing to drop on that rule.

## Practice-Name Normalization

Zero near-duplicate practice-name pairs were flagged in this export, so no new
spelling variants have split a practice. However, **two practice keys are phone
numbers rather than names** — `(440) 823-9827` and `(603) 860-9942`. These are
pre-existing, not introduced by this export, but they can never match a triad
partner and should be corrected in REDCap.

## Protocol/Data Capture Concerns

These are unchanged from the June 24 review and remain open:

- The heterosexual script asks for a three-year cost estimate twice, which may
  inflate missingness or produce inconsistent responses.
- The script asks about **live birth**, but the REDCap field captures
  **pregnancy** (`How long does it typically take for people to get pregnant?`).
  These are not equivalent and must be separated or renamed before reporting.
- The lesbian and single-mother scripts ask about donor sperm, but the donor
  sperm field includes `N/a > not a single mother or lesbian couple scenario`.
  Donor sperm should be analyzed only within scenarios where it was asked.
- `Reason for exclusions` is doing two jobs — eligibility status and exclusion
  reason. A separate binary `analytic_inclusion` field in REDCap would remove the
  ambiguity. (The analysis derives one, but the raw field remains overloaded.)

## Recommended Cleaning Rules

Rules 1–5 are implemented in `evaluate_labubu_mysterycall.R`; the rest are open.

1. ~~Create a derived `analytic_inclusion` field.~~ **Implemented.**
2. ~~Recode appointment wait as business-day difference between call date and
   first-available appointment date.~~ **Implemented.**
3. ~~Review missing-scenario records.~~ **Resolved in REDCap.**
4. ~~Review the future-dated record.~~ **Resolved.**
5. ~~Remove columns that are 100% NA.~~ **None present.**
6. **Open —** Recode `Number of Transfers` to numeric.
7. **Open —** Analyze donor sperm only within lesbian and single-mother scenarios.
8. **Open —** Treat pregnancy-time responses as pregnancy outcomes, not
   live-birth outcomes, unless the REDCap variable is corrected.
9. **Open —** Add branching so `Date of first available appointment` is not
   required when the practice refuses to schedule because of caller scenario.
   This is the likely driver of the 40 included calls with no appointment date.
10. **Open —** Fix the two phone-number practice names and the one record with no
    exclusion reason.
