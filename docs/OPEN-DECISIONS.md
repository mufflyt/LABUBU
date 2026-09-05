# Open decisions

Questions CI has isolated but must not answer. Each is a methods or PI-level
call: the code cannot pick without changing an estimand, so it reports the
situation, keeps the current behaviour explicit, and stops there.

---

## 1. Duplicate practice-scenario calls — DECIDED 2026-09-05

**PI decision, implemented in `evaluate_labubu_mysterycall.R`.**

The previous behaviour — first matching row, via `match()` — was an
undocumented software accident, not a methodology, and it could let a voicemail
outrank the completed call that followed it. It has been removed rather than
grandfathered into the protocol.

**Shape A — a failed attempt followed by a successful call.** Voicemail, wrong
numbers and abandoned/over-long holds are contact *attempts*, not completed
mystery calls. The first protocol-valid completed contact determines the cell;
the attempts stay in the call-level dataset as audit trail. A protocol-valid
completed call is one eligible for the offer model (exclusion codes 0, 7, 9,
10). *2 cells.*

**Shape B — two protocol-valid completed calls.** A protocol deviation. The
cell is **excluded from the primary paired analysis** rather than resolved by
preferring first or last, either of which would mean choosing the observation
that produces the preferred answer. Both calls remain in the call-level
dataset. *2 cells, listed in `mysterycall_outputs/protocol_deviation_cells.csv`.*

**Sensitivity.** First-successful and last-successful are both computed and
reported in `mysterycall_paired_offer_sensitivity.csv`. On the current export
they give identical discordant counts and p-values, so the excluded cells are
not load-bearing. If a future export makes them diverge, that divergence is a
finding for the manuscript, not a footnote.

**Effect on the current results.** Paired *n* moved in both directions, which
is the rule working rather than noise: Lesbian vs Single mother 21 → 22 (Shape
A recovered a cell where an attempt had been outranking a completed call), and
Straight vs Lesbian 21 → 19 (Shape B excluded two). Discordant counts and every
p-value were unchanged.

CI enforces the rule: the contract still surfaces duplicate cells, and the
paired contrasts are now tracked as estimands so a future change to this rule
registers as drift instead of moving silently.

---

## 2. Restriction-checkbox interpretation — DECIDED: do not analyse yet

**PI decision, 2026-09-05.** These variables are **excluded from all
inferential analyses and labelled unresolved** until the REDCap semantics are
verified from the instrument itself.

**The action needed:** retrieve the original REDCap field labels, choices,
branching logic and coded values, and determine whether a checked box means
"would provide care", "would restrict care", or something else. The observed
pattern is suspicious enough that reverse-coding on intuition is not
acceptable.

**If the codebook confirms they measure restriction,** this becomes a candidate
**primary discrimination outcome** — it is directly observed rather than
inferred from call documentation, which is a real improvement over the offer
proxy. Appointment access would then be reported as a separate operational
outcome. That swap requires an explicit manuscript/SAP amendment, not a quiet
substitution.

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

**PI decision, 2026-09-05.** Strict definition (evidence of an actual
schedulable appointment or date) is **primary**, because it has greater
specificity and requires less investigator interpretation. The broader
operational definition is **sensitivity**, and demonstrates how far the finding
depends on measurement assumptions.

The manuscript must not say practices "offered appointments" when the
instrument never asked that. The measure is described as **appointment
availability inferred from call documentation**.

The OR shift from 0.04 to 0.31 between definitions is presented **prominently,
not as a robustness footnote**. Both point the same direction; the magnitude is
measurement-definition dependent, and that is scientifically important.

**Still needed:** an explicit offer field in the instrument for the next wave.

---

## 4. Caller is confounded with scenario

Cramér's V = 0.66; one caller placed 53/77 straight-couple calls and zero
single-mother calls. Scenario and caller effects are not separately
identifiable, and within-practice pairing does not separate them because paired
calls were placed by different people.

**PI decision, 2026-09-05.** No attempt is made to statistically "fix" this in
the primary analysis. With Cramér's V = 0.66 and a caller who placed 53/77
straight-couple calls and no single-mother calls, a caller-adjusted regression
would look sophisticated while extrapolating into caller-scenario combinations
that barely or never occurred.

Caller-scenario confounding is treated as a **design limitation**. Scenario
effects are not interpreted as cleanly separable from caller effects, and the
caller-adjusted model is **not presented as resolving the problem** — it is
shown only as evidence that the design cannot separate the two. Exploratory
caller-stratified diagnostics are acceptable where genuine overlap exists; they
are not a rescue analysis.

**Still needed:** block-randomise scenario within caller in the next wave, so
every caller performs meaningful numbers of every scenario, ideally balanced
within time period and geography as well.
