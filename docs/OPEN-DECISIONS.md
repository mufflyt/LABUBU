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

**Codebook retrieved 2026-09-05** via the REDCap metadata API (pid 39546):

```
field_name : restrictions
field_type : checkbox
label      : "Are there any restrictions to the individuals you would provide care to?"
choices    : 1, Lesbian couple | 2, Straight couple | 3, Single mother
field_note : (none)
branching  : (none)
```

**This narrows the question but does not close it.** The instrument carries no
field note and no branching logic, so it defines the item without constraining
how callers recorded it. The literal reading of the label is that a ticked box
marks a group the practice *would restrict*.

The observed frequencies point the other way:

| box ticked | n |
|---|---|
| Straight couple | 37 |
| Lesbian couple | 27 |
| Single mother | 19 |

Under the literal reading, 37 practices restrict straight couples — implausible
for fertility practices, and the ordering straight > lesbian > single mother is
exactly what "groups this practice **will** serve" would produce. Reading the
data against the label is what suggests the field was used inversely.

**CI now enforces the exclusion.** `restriction/excluded-from-inference` fails
the build if a restriction variable is used as a model outcome or predictor, or
appears as a reported estimand or manuscript claim. Descriptive tabulation for
review stays allowed; the point is that these must not become evidence while
their meaning is unknown.

**Still needed, and not inferable from the export:** confirmation from the
callers of what they recorded when they ticked a box. The exact wording to
send, the pre-set decision rule, and why the frequency pattern must not settle
it are in `docs/PI-QUERY-restriction-checkbox.md`. Ask every caller who entered
data; if answers conflict, the variable is unusable for this wave. Deciding this
from the frequency pattern alone would be reverse-coding on intuition, which
this decision explicitly rules out — and it is the one reading that would
reverse the direction of a discrimination finding.

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
