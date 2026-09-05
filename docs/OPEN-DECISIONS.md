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

## 2. Restriction-checkbox interpretation — CLOSED 2026-09-05: unusable this wave

**This is no longer an open decision and no longer awaits an answer from the
callers.** The variables stay excluded from every analysis, permanently for this
dataset. `restriction/excluded-from-inference` continues to enforce that.

**Supersedes the earlier plan to poll all seven callers.** That plan assumed the
ambiguity was about intent and could be resolved by asking. It cannot: the
codebook establishes the intended meaning, and the recorded data contradict it
in two mutually incompatible ways.

**What the codebook says** (`LABUBU_DataDictionary_2026-09-05.csv`, field
`restrictions`, checkbox): label *"Are there any restrictions to the individuals
you would provide care to?"*, choices `1, Lesbian couple | 2, Straight couple |
3, Single mother`, with **no field note, no branching logic and no annotation**.
A ticked box means a restriction applies to that group. There is no second
reading available from the instrument.

**What the data show.** A box is ticked on 43 of 234 calls, and the pattern is a
property of the person completing the form, not of the practice:

| Person completing | Patterns used | n |
|---|---|---:|
| Caller C | `Les+Str+SM` ×19, `Str` ×3, `Les+Str` ×2 | 24 |
| Caller F | `Str` ×9 | 9 |
| Caller D | `Str` ×4 | 4 |
| Caller A | `Les` ×3 | 3 |
| Caller E | `Les` ×2 | 2 |

One caller ticked all three boxes on 19 of 24 entries. Under the codebook
definition that asserts the practice restricts lesbian couples *and* straight
couples *and* single mothers — serves nobody — and plainly means the inverse.
Every other caller ticked only the box matching the scenario they themselves
called as: on straight-couple calls the straight box is ticked 13 times out of
13 and the other two never. That is an echo of the assignment, carrying no
information about the practice.

**Why asking cannot fix it.** Two conventions cannot be merged into one
measurement after the fact, and 59 of 234 calls (25%) record no caller, so those
records cannot be attributed to either convention even with unanimous answers.
This is a question-design failure, not a data-entry failure, and not anyone's
error: the item had no instruction and invited both readings.

**Consequence for a future wave** — an instrument change, not an analytic one:

1. Split into three explicit yes/no items with the direction stated in the stem
   ("Would this practice provide care to a single mother using donor sperm?").
2. Make the item required, so blank is distinguishable from "no restriction".
3. Require caller identity on every record, so a convention can be audited
   during collection rather than reconstructed afterwards.

**Evidence** `mysterycall_outputs/restriction_checkbox_by_caller.csv`,
`restriction_checkbox_review.csv`, Appendix Table S6, and the full argument in
`docs/PI-QUERY-restriction-checkbox.md`.

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
