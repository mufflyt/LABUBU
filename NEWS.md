# NEWS

Short, dated notes for people returning to LABUBU. For the full record see
`CHANGELOG.md`; for why the CI is shaped the way it is, `docs/APPENDIX-lessons.md`.

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
