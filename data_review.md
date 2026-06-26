# Mystery Caller Study Data Review

Source file: `LABUBU_DATA_LABELS_2026-06-24_1308.csv`

## Dataset Snapshot

- Records: 176
- Columns: 29
- Scenario distribution:
  - Lesbian couple: 83
  - Straight couple: 67
  - Single mother: 22
  - Missing scenario: 4
- `Complete?` is present in the export but should be ignored for analysis.

## Key Analytic Denominator Issue

`Complete?` should not be used as the analytic inclusion flag and should be ignored analytically.

The most defensible starting denominator is records with:

- `Reason for exclusions = Included where physician was able to be contacted`
- and, if requiring finalized forms, `Complete? = Complete`

Counts:

- Included by exclusion field: 69
  - Straight couple: 25
  - Lesbian couple: 22
  - Single mother: 22
- Included and complete: 58
  - Straight couple: 24
  - Lesbian couple: 16
  - Single mother: 18

This creates a major imbalance if only included-and-complete records are analyzed.

## Record-Level Inconsistencies
Records that look internally inconsistent by inclusion/exclusion status:

- 19, 20, 21, 22, 25, 29, 30, 34, 35, 41, 50, 51, 79, 80, 81, 82, 84, 85, 102, 103, 104, 105, 108, 109, 110, 117, 120, 161, 162, 163, 164, 166, 172

## Missing Scenario Values

Four records have no scenario:

- 21, 22, 23, 49

Two of these are marked complete despite being excluded for wrong number or wrong specialty. These should be corrected or excluded before scenario-level analysis.

## Date and Time Problems

The first call field is labeled as date and time, but most entries contain only dates. There is one likely erroneous or out-of-window entry:

- Record 3: `2026-08-03 10:07`

Because the export date is 2026-06-24, this appears to be a future date unless it was intentionally entered for a later scheduled call.

## Missingness in Included-and-Complete Records

Among the 58 included-and-complete records:

- Time to scheduled visit missing: 15/58
- Insurance acceptance missing: 5/58
- Time to pregnancy/live birth missing: 10/58
- Cost estimate missing: 9/58
- REI referral missing: 0/58
- Donor sperm response missing: 0/58

The live-birth question appears to be stored as `How long does it typically take for people to get pregnant?`, which is not equivalent to live birth.

## Field Coding Concerns

The transfer field is not numeric. Values such as `No transfers` were entered, so the field needs recoding before analysis.

Recommended recode:

- `No transfers` -> 0
- text with a numeric count -> numeric value
- blank -> missing, not zero

Service checkboxes show no IUI or IVF services selected in any record:

- IUI checked: 0/176
- IVF checked: 0/176

This may be true for the sampled practices, but it should be verified because the call script specifically asks about offering or referring for IUI/IVF.

Restriction checkboxes are ambiguous because the field asks, "Are there any restrictions to the individuals you would provide care to?" A checked `Straight couple` could mean either restriction against straight couples or a requirement to be a straight couple, depending on how staff interpreted the field.

## Protocol/Data Capture Concerns

The heterosexual script asks for a three-year cost estimate twice. This may have increased missingness or inconsistent responses if callers handled the duplicate question differently.

The script asks about live birth, but the REDCap field captures pregnancy. These should be separated or renamed before reporting.

The lesbian and single mother scripts ask about donor sperm, but the donor sperm field includes `N/a > not a single mother or lesbian couple scenario`; at least three records used this value. Donor sperm should be analyzed only for scenarios where it was asked.

The `Reason for exclusions` field is doing two jobs: eligibility status and exclusion reason. A separate binary `analytic_inclusion` field would reduce ambiguity.

No columns are 100% NA in the current export, so there is nothing to drop on that rule right now. If a future export contains a fully missing field, remove it before analysis.

## Recommended Cleaning Rules

1. Create a derived `analytic_inclusion` field:
   - Included if `Reason for exclusions = Included where physician was able to be contacted`
   - Excluded otherwise
2. Add branching so `Date of first available appointment` is not required when the practice refuses to schedule because of caller scenario.
3. Recode `Number of Transfers` to numeric.
4. Recode appointment wait using date difference between call date and first-available appointment date.
5. Analyze donor sperm only within lesbian couple and single mother scenarios.
6. Treat pregnancy-time responses as pregnancy outcomes, not live-birth outcomes, unless the REDCap variable is corrected.
7. Review the 4 missing scenario records and the future-dated record 3 manually.
8. Remove any columns that are 100% NA in a future export.
