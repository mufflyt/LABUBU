# Appendix: borrowed validation techniques, and what each one found

Five strategies adapted from sibling repositories rather than invented here.
Each is recorded with its source, the argument for it in the source's own
words, and what it actually caught the first time it ran. A technique that
found nothing on its first run would be worth listing too, but none of these
were.

Attribution belongs in the code as well as here; each script carries the
quotation that justifies it.

---

## 1. Independent reference implementations

**From:** [`mufflyt/isochrones-ci`](https://github.com/mufflyt/isochrones-ci),
`tests/testthat/test-statistics-crosscheck.R`

**The argument, in that repository's words:**

> A test suite that lives inside the code it tests shares that code's blind
> spots. If a helper is subtly wrong, both the implementation and its tests use
> the wrong helper, and the suite certifies the wrong answer with total
> confidence.

and, on statistical helpers specifically:

> Every reference here is written from the formula, not delegated to the R
> function production also calls. Comparing `prop.test()` to `prop.test()` would
> certify agreement between a function and itself.

**Here:** `tools/reference_implementations.R` recomputes Wilson and
Clopper-Pearson intervals, the exact McNemar p, the paired minimum detectable
odds ratio, US federal business days, and a one-way ICC from published formulae.
It is the only file in this repository that never calls `mysterycall`.
`.github/scripts/check-reference-crosscheck.R` requires agreement.

**What it found, immediately:** `mcnemar_mde_or()` built its rejection region
from `qbinom(0.025, n, 0.5)`. That is not a valid 5% region. At seven discordant
pairs it admits a split whose exact two-sided p is 0.125; at two pairs it admits
a "test" that rejects half the time under the null.

| Contrast | Discordant | Reported MDE | Actual power | Correct MDE |
|---|---:|---:|---:|---:|
| Straight vs single mother | 7 | OR 8.1 | 44% | OR 30.9 |
| Straight vs lesbian | 8 | OR 9.0 | 43% | OR 35.4 |
| Lesbian vs single mother | 2 | OR 8.1 | 0% | **none attainable** |

Confirmed by Monte Carlo (40,000 replicates) before anything was changed. The
manuscript had been understating its own underpowering roughly fourfold, and
reporting a finite minimum detectable effect for a contrast where the exact test
cannot reject at *any* effect size.

**The circularity trap this creates, and how it is avoided.** Once the pipeline
was corrected, its implementation and the reference would have been the same
code, and the check would have certified a function against itself. So the two
are deliberately written differently: the pipeline uses the closed form
`2 * pbinom(min(k, n - k), n, 0.5)` with bisection on a geometric midpoint; the
reference uses `binom.test()` with `uniroot`. They agree to two decimals across
every n tested, by two routes.

---

## 2. Precision bounds: what the data exclude

**From:** [`mufflyt/lizeth`](https://github.com/mufflyt/lizeth) (Acosta &
Muffly, urogynecology mystery-caller study), `null_verification.R`, section 2,
"PRECISION — WHAT THE CIs RULE OUT", whose closing line is:

> Interpretation: the upper CI is the LARGEST delay compatible with our data.

**Here:** `precision_bounds.csv` and Appendix Table S8 report the paired
difference on the percentage-point scale with its interval, so the paper says
what it *excludes* rather than only what it failed to detect. Straight versus
single mother is +31 points (95% CI −7 to +43): compatible with a large
disadvantage and with none, which is a more useful sentence than "no significant
difference".

---

## 3. Mutation and sabotage testing

**From:** `mufflyt/isochrones-ci`, `tests/testthat/test-mutation-sabotage.R`.
Two ideas taken directly. What makes a mutant worth having:

> The mutants are plausible mistakes, not nonsense. "Return 42" proves nothing;
> "`<` where the specification says `<=`" is the edit that passes review, moves
> a headline number by a fraction of a point, and never crashes.

and that a survivor is a reported hole rather than a tolerated one.

**Here:** `.github/scripts/mutation-sabotage.R` breaks the analysis code six
ways and requires the check held responsible for each to go red. Nightly only:
one full pipeline run per mutant. Results land in `mutation_report.csv`.

This is distinct from `gate-selftest.R`, which injects defects into committed
**artifacts** and answers "would we notice a corrupted output?". Sabotage
injects defects into **code** and answers "would we notice a wrong analysis?" —
the case where every artifact is internally consistent and quietly wrong.

**What it found:** two inert mutants, and finding out *why* was worth more than
the mutants would have been. See section 5.

---

## 4. Caller intraclass correlation

**From:** `mufflyt/lizeth`, `caller_icc.R`, which hit this repository's exact
problem and documented the fallback:

> The earlier paired-ICC method is not usable on the 2026-07-04 data (only 1
> complete same-office caller pair), so a mixed-model variance-components ICC is
> used instead.

**Here:** caller confounding was argued qualitatively (Cramér's V = 0.66, zero
caller overlap on two of three contrasts, an adjusted model that goes
non-identifiable). It now has a number. The share of variance lying between
callers rather than within them is 0.29 for reaching a live office, 0.31 for
inferred appointment availability, and 0.36 for the business-day wait. Roughly a
third of what was measured tracks who dialled the phone, which is the same order
of magnitude as any scenario effect the study could have detected.

---

## 5. Metamorphic tests

**From:** `mufflyt/isochrones-ci`, `tests/testthat/test-metamorphic.R`:

> These catch a class that fixed expected values cannot: hidden dependence on
> input order, on identifier text, on chunking, or on how many workers happen to
> be running. Such bugs produce a *plausible* number every time, so no golden
> comparison flags them — only invariance under a transformation does.

**Here:** `.github/scripts/check-metamorphic.R` re-runs the pipeline under three
row shuffles and a practice relabelling, requires every estimand unchanged, and
adds a direct order-invariance check on `make_wide()`.

### Three things this cost, all worth recording

**The relabelling test caught its author before it caught anything else.** Its
first run reported 47 lost triads. That was the test's fault: it relabelled raw
practice strings one-to-one, splitting practices that `normalize_practice()`
deliberately collapses, and its replacement tokens ended in digits, which the
normalizer strips as call-list indices — so every practice collapsed onto the
single name "Practice". The fixture builder had made the identical mistake
earlier in the project. Tokens are now asserted to be fixed points of the
normalizer.

**A mutant survived three rounds, and the reason was the finding.** Reordering
the duplicate-resolution preference list changes zero of thirty estimands:
ambiguous cells are excluded outright, so the rule never chooses between two
valid calls, and the `"first"` branch sorts by call date then record id. The
analysis is order-independent by construction. Replacing it with the mistake
that *would* break it — resolving an ambiguous cell by taking whichever row
arrives first — still survived, because `dat` passes through
`mysterycall_business_days()` and `mysterycall_appointment_obtained()` before
`make_wide()` sees it, and those normalise row order. Permuting the export is
invisible by the time the rule runs. The property is now checked on the
function, where it lives.

**That new check then passed vacuously.** It was wrapped in `try()`, so when its
input was missing in the sabotage sandbox it printed an error and reported
success. This is precisely the rule `docs/APPENDIX-lessons.md` exists to
enforce: *a check that cannot evaluate its condition must fail, never skip.*
Fixed, and the sandbox now mirrors the real tree.

---

## What was surveyed and deliberately not used

- **`mufflyt/mysterymaps`** — isochrone and geocoding tools for drive-time
  accessibility. Needs geocoded practice addresses; the LABUBU instrument
  recorded none. The only location signal is a parenthesised state tag in some
  practice names, which is a string, not a coordinate. Geocoding 105 practice
  names from scratch would be new data collection presented as analysis.
- **`mufflyt/mysterynpi`** — links person rosters to NPI. The RRM roster is
  majority FertilityCare centres and FCP-credentialed nurses, who are largely
  not NPI holders. An NPI link would resolve about a quarter of the roster and
  silently drop the part of the field that most distinguishes RRM from
  conventional fertility care.
- **`mufflyt/mystery_shopper`** — roster construction (ABOHNS, NPPES,
  Healthgrades scraping), upstream of where LABUBU sits. Its
  `create_ent_table1.R` did prompt a check of what practice characteristics
  LABUBU could report; the answer produced a limitation sentence rather than a
  table, because the characteristics are parsed from name strings and missing
  for 26% of practices.
