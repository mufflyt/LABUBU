# Resolved: the restriction checkbox is unusable this wave

**Status: RESOLVED, and the resolution is that the variable cannot be used.**
It stays excluded from all inferential analyses and CI continues to enforce
that exclusion (`restriction/excluded-from-inference`). This is no longer a
question awaiting an answer from the callers.

Superseded the earlier plan to poll all seven callers. The codebook plus the
raw coded export answer the question directly, and they answer it against use.

## What the codebook says

`LABUBU_DataDictionary_2026-09-05.csv`, field `restrictions`:

| Property | Value |
|---|---|
| Field type | checkbox |
| Field label | "Are there any restrictions to the individuals you would provide care to?" |
| Choices | `1, Lesbian couple` \| `2, Straight couple` \| `3, Single mother` |
| Field note | *(none)* |
| Branching logic | *(none)* |
| Field annotation | *(none)* |

The intended semantics are therefore unambiguous: **a ticked box means a
restriction applies to that group.** There is no note, no branching logic and
no annotation that would suggest any other reading.

## What the data show

The intended semantics are not what was recorded. 43 of 234 calls have any box
ticked. Cross-tabulated against the scenario actually called:

| scenario called | n | any box | Lesbian ticked | Straight ticked | Single mother ticked |
|---|---:|---:|---:|---:|---:|
| Straight couple | 77 | 13 | 0 | 13 | 0 |
| Lesbian couple | 83 | 17 | 16 | 11 | 9 |
| Single mother | 74 | 13 | 11 | 13 | 10 |

Two things falsify the codebook reading:

1. **On straight-couple calls, only the straight-couple box is ever ticked**
   (13 of 13), never the other two. Under the codebook reading, thirteen
   practices volunteered to a straight caller that they restrict straight
   couples, and no practice restricted anyone else. That is not credible.

2. **The all-three pattern.** `Les+Str+SM` is the single most common
   combination (19 of 43). Under the codebook reading that practice restricts
   every group it could serve, i.e. serves nobody.

## The conventions are caller-specific and mutually incompatible

Splitting by the person who completed the form is decisive:

| person completing | patterns used | n |
|---|---|---:|
| Melanie | `Les+Str+SM` x19, `Str` x3, `Les+Str` x2 | 24 |
| SR / sr / Sam | `Str` x9 | 9 |
| Muffly | `Str` x4 | 4 |
| Beth | `Les` x3 | 3 |
| Sofie | `Les` x2 | 2 |
| *(blank)* | `Les` x1 | 1 |

- **Melanie ticks all three boxes on 19 of her 24 entries.** Read as
  restrictions this is "serves nobody"; read as its inverse it is "serves
  everyone", which is plausible and almost certainly what was meant. She was
  recording who the practice *would* care for, the opposite of the label.
- **Every other caller only ever ticks the box matching the scenario they
  called as.** Straight-couple callers tick Straight; lesbian-couple callers
  tick Lesbian. That is an echo of the scenario, not an observation about the
  practice, and carries no information at all.

So the field holds at least two incompatible conventions, one of which is the
logical inverse of the codebook label and the other of which is not a
measurement. No recoding rule can separate them after the fact, because the
convention is a property of the caller rather than of the response, and 59 of
234 calls (25%) record no caller at all and so cannot be attributed to either
convention.

## Consequence

The variable is unusable for this wave and is not rescued by asking the
callers: even a unanimous statement of intent cannot retroactively make two
different conventions into one measurement, nor attribute the unlabelled
quarter. It stays out of the analysis permanently for this dataset.

**For the next wave**, this is a fixable instrument problem, not a fixable
analysis problem:

1. Split the item into three explicit yes/no questions, one per group, with the
   direction stated in the stem ("Would this practice provide care to a single
   mother using donor sperm?").
2. Make the item required, so blank is distinguishable from "no restriction".
3. Require the caller's identity on every record, so a convention can be
   audited during collection rather than reconstructed afterwards.
