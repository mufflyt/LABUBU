# Resolution needed: the restriction checkbox

**Status:** unresolved. The variable is excluded from all inferential analyses
and CI enforces that exclusion (`restriction/excluded-from-inference`).

**Who to ask:** every caller who entered data — not one person. A convention
one caller used is not evidence about what another recorded.

**Seven callers** entered data (`Caller A`–`Caller G`; the raw export holds ten
distinct name strings, three of which are typos that `normalize_practice`-style
cleanup collapses). Their call volumes are very uneven:

| caller | calls |
|---|---|
| Caller C | 68 |
| Caller D | 56 |
| Caller A | 18 |
| Caller G | 16 |
| Caller F | 15 |
| Caller B | 1 |
| Caller E | 1 |

**A limit on what any answer can establish.** 59 of 234 calls — 25% — record no
caller at all. Nobody can be asked about those, so even unanimous agreement
among all seven leaves a quarter of the checkbox responses unattributable to
any stated convention. Two callers contributed a single call each, so their
answers describe one observation apiece.

If the convention is to be relied on, that 25% has to be accounted for
explicitly: either the unattributed calls are also excluded, or the analysis
states that it assumes a convention it cannot verify for a quarter of the data.
That is a further decision, not something this query resolves.

---

## The question to send

> In REDCap there is a question that reads **"Are there any restrictions to the
> individuals you would provide care to?"** with checkboxes for *Lesbian
> couple*, *Straight couple* and *Single mother*.
>
> When you checked one of those boxes, did you check the groups the practice
> said it **WOULD NOT** serve, or the groups the practice said it **WOULD**
> serve?

Ask it exactly that way. Do not supply the frequency table with the question,
and do not mention which reading the data appear to support — a caller shown
the pattern first may reconstruct an intent rather than recall one.

---

## Why this cannot be settled from the data

**The instrument is silent.** The REDCap metadata (pid 39546) gives:

```
field_name : restrictions
field_type : checkbox
label      : "Are there any restrictions to the individuals you would provide care to?"
choices    : 1, Lesbian couple | 2, Straight couple | 3, Single mother
field_note : (none)
branching  : (none)
```

No field note, no branching logic. The instrument defines the item without
constraining how it was recorded.

**The two readings point in opposite directions.**

| reading | a ticked box means | implied by |
|---|---|---|
| literal | this group would be **restricted** | the label's wording |
| inverse | this group **would be served** | the response pattern |

Observed ticks: straight couple 37, lesbian couple 27, single mother 19. Under
the literal reading, 37 practices restrict straight couples — implausible for
fertility practices, and the ordering straight > lesbian > single mother is
exactly what "groups we will serve" produces.

**That inference is precisely what must not be made.** Reverse-coding a
variable because its distribution looks wrong under the documented reading is
circular: the pattern is the thing being explained, and this is the single
variable whose direction, if flipped, would reverse a discrimination finding.

---

## Decision rule, set in advance

Fixing the rule before seeing the answers prevents choosing whichever reading
suits the result.

1. **Callers agree, and the convention is clear.** Encode it explicitly in
   `evaluate_labubu_mysterycall.R`, document it here, and lift the CI guard in
   the same change. If the convention is "would restrict", this becomes a
   candidate primary discrimination outcome — directly measured rather than
   inferred from call documentation — and adopting it requires an explicit
   protocol/SAP amendment, not a quiet substitution.
2. **Callers disagree, or any answer is hedged or uncertain.** The variable is
   **unusable for this wave.** It stays excluded and is reported as a
   limitation. Do not reconstruct intent retrospectively from partial
   agreement, seniority, or who placed the most calls.
3. **In every case**, the raw checkbox values remain in the dataset unchanged.
   Nothing here edits recorded data; the question is only how it may be read.

---

## For the next wave

Rewrite the item so the direction cannot be misread — a single question with
explicit mutually exclusive options per group ("would serve" / "would not
serve" / "not discussed"), rather than a checkbox whose meaning depends on
reading the stem correctly. Alongside the other two instrument changes already
agreed: an explicit appointment-offer item, and block-randomised callers
across scenarios.
