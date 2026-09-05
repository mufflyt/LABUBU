# Open decisions

Questions CI has isolated but must not answer. Each is a methods or PI-level
call: the code cannot pick without changing an estimand, so it reports the
situation, keeps the current behaviour explicit, and stops there.

---

## 1. Duplicate practice-scenario calls

**Found by** `.github/scripts/data-contract.R`, check
`practice/one-call-per-scenario`.
**Evidence** `mysterycall_outputs/duplicate_practice_scenario_calls.csv`.

The design is one call per practice per scenario. Eight practice-scenario cells
currently hold two calls. They come in two shapes.

**Shape A — retry after a failed contact (6 cells).** The first call hit
voicemail, a wrong number, or an over-long hold; a later call reached the
office. Example: record 177 (voicemail) then record 179 (included), same
practice and scenario.

**Shape B — two successful contacts (2 cells).** Both calls reached staff and
both are analytically included:

| practice | scenario | records |
|---|---|---|
| Flourish FertilityCare (AL) | Lesbian couple | 126, 156 |
| Holy Family FertilityCare (MN) | Straight couple | 164, 193 |

**Current behaviour, which nobody chose.** `make_wide()` in
`evaluate_labubu_mysterycall.R` resolves a practice to a scenario value with
`match()`, which returns the *first* matching row. The earlier call therefore
becomes the practice's datum and the later one is silently discarded. That is
an artefact of `match()`, not a documented rule, and it affects the paired
McNemar contrasts and the wide matched tables.

### The decision needed

For Shape B, which call represents the cell?

1. **First call** — preserves today's numbers; earliest observation.
2. **Last call** — most recent state of the practice.
3. **Protocol deviation** — exclude the cell from paired analyses entirely.
4. **Something else**, e.g. require agreement and flag disagreement.

For Shape A the answer is probably "the successful call", but that should be
stated rather than inherited from `match()`.

### Why CI will not choose

Any of these changes an estimand. Options 1 and 2 differ whenever the two calls
disagree; option 3 changes the denominator of every paired contrast. This is a
methods decision for the PI.

### What happens until it is decided

The contract reports `REVIEW`, emits a CI warning, and writes the affected
records out. It does **not** fail the build, because the data are not incoherent
— the study simply contains a situation the protocol did not specify.

---

## 2. Restriction-checkbox interpretation

**Evidence** `mysterycall_outputs/restriction_checkbox_review.csv`.

The three "restrictions to the individuals you would provide care to"
checkboxes are the only directly measured discrimination item, and their coding
is ambiguous: the straight-couple box is ticked on straight-couple calls, so
"checked" may mean *restricted* or *served*. Resolve against the REDCap
codebook. If it means restricted, this becomes a candidate primary outcome and
is better measured than the derived offer proxy.

---

## 3. The offer outcome is a derived proxy

REDCap has no "did the practice agree to schedule you?" item. `appt_offered` is
inferred from whether an appointment date was recorded. Strict and broad
definitions give materially different triad ORs (0.04 vs 0.31), which is a
measurement limitation no test resolves.

**Decision needed:** add an explicit offer field to the instrument for the next
wave. Until then the manuscript reports both definitions and frames the
contrast as hypothesis-generating.

---

## 4. Caller is confounded with scenario

Cramér's V = 0.66; one caller placed 53/77 straight-couple calls and zero
single-mother calls. Scenario and caller effects are not separately
identifiable, and within-practice pairing does not separate them because paired
calls were placed by different people.

**Decision needed:** randomise or block caller across scenarios in the next
wave. CI only guarantees the diagnostic stays visible; it cannot repair the
design retrospectively.
