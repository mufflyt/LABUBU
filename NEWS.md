# NEWS

Short, dated notes for people returning to LABUBU. For the full record see
`CHANGELOG.md`; for why the CI is shaped the way it is, `docs/APPENDIX-lessons.md`.

## 2026-09-06 — practices split by practitioner type

**Tyler's question: are the near-zero IUI and IVF rates just an artifact of
pooling Creighton practitioners with actual physicians?** A FertilityCare
practitioner holds a certificate in cycle-tracking instruction, not a medical
licence, and of course would not offer IVF. If most of the roster is
practitioners, the headline finding could be an accident of the denominator.

**Checked. It is not, and the finding gets stronger.** Among the 39 interviewed
calls to physician-led (MD/DO) practices, IUI and IVF were each offered by
**one**, 2.6% (95% CI 0.5 to 13.2). Among the 59 calls to FertilityCare centres,
neither was offered at all (0%, upper bound 6.1%). The one practice offering IUI
also offered IVF and worked with donor sperm, was physician-led, and is the only
practice in the sample providing the full donor-conception pathway.

**The stratification also confirms the division of labour, and it is the
cleanest contrast in the study.** Hormonal laboratory monitoring: 87.2% of
physician-led calls against 47.5% of FertilityCare calls, P < .001. Cycle
tracking is near-universal in both. Physicians do the workup, practitioners
teach cycle tracking, exactly as the model describes.

This pre-empts the strongest objection a reviewer can make to the primary
finding. New **Table 2**; the paired analysis moves to Table 3.

Classification is from credential tokens in the practice name, **never** from
the services observed, and `stratum/practitioner-type-not-derived-from-outcomes`
enforces that: deriving a stratum from the outcomes it explains would make the
difference true by construction. This repository has made the analogous mistake
before, when a figure's colour grouping was derived from observed percentages.

## 2026-09-05 (evening) — manuscript sent to coauthors

**The paper went out.** Manuscript, supplement, three figures and a draft cover
letter emailed to all four coauthors. **Comments are due October 1**, after
which revisions, submission and reviewer responses pass to the remaining
authors.

**We were four times more underpowered than the paper admitted.** The minimum
detectable effect had been computed with a normal approximation, reporting
OR 8.1 and 9.0. Those deliver about 44% power, not 80%. The exact values are
OR 30.9 and 35.4 — and for Lesbian couple versus Single mother, with two
discordant practices, **no effect size is detectable at all**; the exact test
cannot reject at any odds ratio. This was found by an independent
recalculation, confirmed by simulation, and corrected everywhere. It makes the
existing "exploratory, underpowered" framing more true rather than less.

**The restriction checkbox question is closed.** Do not poll the callers. The
codebook says a ticked box means a restriction; the data show two incompatible
conventions keyed to who filled in the form, and a quarter of calls record no
caller. Two conventions cannot be merged into one measurement after the fact.

**Figures were the blind spot.** All 27 invariants passed while Figure 1 plotted
Clopper-Pearson intervals and its own supplemental table printed Wilson ones.
Every check read a CSV, a model, or text; none had ever looked at what a figure
plots. Figures now publish the data they draw, and two checks compare them
against the tables they duplicate. A human found this one, in Preview, minutes
before the email went out.

**If you take one thing from this session:** coverage is not a count of checks.
Ask which classes of artifact can still ship a wrong number with nothing
noticing. See `docs/APPENDIX-lessons.md` §7.

**One thing still outstanding:** the REDCap token was pasted in plaintext on
2026-09-05 and **has not been rotated**.

## 2026-09-05

**The primary outcome changed, and the old one was not measuring what it said.**
`contact_office` had aliased the analytic-inclusion flag, so "appointment
offered" and "was this call included" were the same variable. Acceptance was
100% inside the analytic sample by construction. Reaching a live office and
being offered an appointment are now separate constructs with separate
denominators.

**The instrument never asked whether an appointment was offered.** The outcome
is now described everywhere as *appointment availability inferred from call
documentation*, and the manuscript no longer says practices "offered
appointments". Strict and broad definitions give triad ORs of 0.04 and 0.31 —
same direction, order-of-magnitude different size. That dependence is reported
as a finding.

**Two data defects had already reached committed artifacts.** A REDCap API pull
encodes checkboxes differently from the browser export, which silently zeroed
every service variable; and two records had a phone number typed into the
practice-name field, leaking contact details into every derived file. Both are
fixed and both now have CI checks.

**Four PI decisions were recorded and encoded** — duplicate-call handling,
caller confounding as a design limitation, strict-primary/broad-sensitivity,
and restriction checkboxes held out pending codebook resolution. See
`docs/OPEN-DECISIONS.md`.

**What still needs a person**, in `docs/PI-QUERY-restriction-checkbox.md`:
ask all seven callers what a ticked restriction box meant. Note that 59 of 234
calls record no caller, so no answer can cover a quarter of the data.

Two further changes belong to the next wave rather than this one: add an
explicit appointment-offer item to the instrument, and block-randomise callers
across scenarios.
