# LABUBU Mysterycall Evaluation

Generated: 2026-09-04 18:26:05 MDT

## Package

- mysterycall version: 1.6.3.9000

## Denominators

Each analysis uses a different denominator. Quote none of these without its rule.

- Calls placed (all records): 234
- Reached a live office (codes 0, 2, 7, 9, 10): 108
- Eligible for the offer model (codes 0, 7, 9, 10): 102
- Offer model analytic sample (eligible, scenario + outcome present): 100
- Historical 'analytic inclusion' flag (code 0 only): 98
- Historical inclusion AND finalized form: 98
- Wait-time subset (appointment date observed): 57

> Note on a corrected definition: `contact_office` previously aliased the analytic-inclusion flag, which made 'appointment offered' the same variable as 'was this call included'. Acceptance was therefore 100% inside the analytic sample by construction, and the 10 reached-but-declined calls (Greater than 5 minutes on hold; Not accepting new patients) were discarded — the only unambiguous 'offered = 0' events in the study. `contact_office` now means 'a live office answered'; the offer outcome is `appt_offered`.

## Data Quality

- Completeness quality tier: low
- Completeness score: 0.705
- General quality score: 0.95

## Data Collection Status

Study design: each RRM practice called once per scenario (straight couple, lesbian couple, single mother using donor sperm). Primary analysis: mixed-effects logistic regression on the appointment-offer outcome with a practice random intercept (lme4::glmer). Note: REI comparison arm removed from scope; analysis is within-RRM only.

- Total unique practices: 105
- Complete triads (all 3 scenarios): 48
- Dyads (2 of 3 scenarios): 25
- Singletons (1 scenario only): 32

Missing calls by scenario:
  - Missing straight-couple call: 32 practices
  - Missing lesbian-couple call:  25 practices
  - Missing single-mother call:   32 practices

## ACCESS CASCADE — reachability and offer are different things

Every stage has its own denominator (each nested in the previous). The single 'acceptance rate' this replaces mixed 'nobody picked up the phone' with 'someone picked up and said no'.

```
<mysterycall access cascade: 4 stages, 234 analytic calls>
# A tibble: 4 × 6
  group          measure                      n denominator pct    ci           
  <chr>          <chr>                    <int>       <int> <chr>  <chr>        
1 Access cascade Calls placed               234         234 100.0% [98.4, 100.0]
2 Access cascade Reached a live office      108         234 46.2%  [39.9, 52.6] 
3 Access cascade Eligible for offer model   102         108 94.4%  [88.4, 97.4] 
4 Access cascade Appointment offered         57         102 55.9%  [46.2, 65.1] 
```

By scenario (strict offer = appointment date obtained; broad = date OR a concrete scheduling timeframe):

```
         scenario calls_placed reached offer_eligible offered_strict
1 Straight couple           77      39             37             28
2  Lesbian couple           83      37             34             14
3   Single mother           74      32             31             15
  offered_broad pct_offered_strict pct_offered_broad
1            29               75.7              78.4
2            20               42.4              60.6
3            18               50.0              60.0
```

### Appointment-offer rate by scenario

```
# A tibble: 3 × 8
  scenario       n_total n_missing n_accepted n_rejected  rate ci_lower ci_upper
  <chr>            <int>     <int>      <int>      <int> <dbl>    <dbl>    <dbl>
1 Straight coup…      37         0         28          9 0.757    0.599    0.866
2 Lesbian couple      33         0         14         19 0.424    0.272    0.592
3 Single mother       30         0         15         15 0.5      0.332    0.668
```

- Unmatched test (descriptive only): chi-square; p = 0.0127

Sensitivity — broad offer definition:

```
# A tibble: 3 × 8
  scenario       n_total n_missing n_accepted n_rejected  rate ci_lower ci_upper
  <chr>            <int>     <int>      <int>      <int> <dbl>    <dbl>    <dbl>
1 Straight coup…      37         0         29          8 0.784    0.628    0.886
2 Lesbian couple      33         0         20         13 0.606    0.437    0.753
3 Single mother       30         0         18         12 0.6      0.423    0.754
```

> **The offer outcome is a derived proxy, and this is the study's principal measurement limitation.** The REDCap instrument has no 'did the practice agree to schedule you?' item. 'Offered' is therefore read off the appointment date (strict) or the date plus a concrete scheduling timeframe (broad), with an explicit 'not accepting new patients' scored as a refusal. A call where staff offered an appointment but the caller recorded no date is misclassified as a refusal. Adding an explicit offer field to REDCap is the single highest-value fix to the instrument.

### Reachability by scenario (secondary — a live office answered)

```
# A tibble: 3 × 8
  scenario       n_total n_missing n_accepted n_rejected  rate ci_lower ci_upper
  <chr>            <int>     <int>      <int>      <int> <dbl>    <dbl>    <dbl>
1 Straight coup…      77         0         39         38 0.506    0.397    0.615
2 Lesbian couple      83         0         37         46 0.446    0.344    0.553
3 Single mother       74         0         32         42 0.432    0.326    0.546
```

- Descriptive test only: chi-square; p = 0.618

## CALLER CONFOUNDING — read this before interpreting any scenario contrast

Scenario was not randomised across callers. Where one caller placed most of a scenario's calls, 'scenario effect' and 'caller effect' are the same number, and within-practice pairing does NOT separate them: the pair compares two scenarios dialled by two different people.

Calls by caller and scenario:

```
            
             Straight couple Lesbian couple Single mother
  Caller A                 0             14             4
  Caller B                 0              0             1
  Caller C                 2             28            38
  Caller D                53              3             0
  Caller E                 1              0             0
  Caller F                 2              9             4
  Caller G                16              0             0
  Unrecorded               3             29            27
```

- Caller x scenario association: Fisher-Freeman-Halton exact test (simulated), p = < 0.001, Cramer's V = 0.664 (large).

Single-caller dominance of each scenario:

```
                  scenario n_calls top_caller top_caller_n top_caller_pct
Caller D   Straight couple      77   Caller D           53           68.8
Unrecorded  Lesbian couple      83 Unrecorded           29           34.9
Caller C     Single mother      74   Caller C           38           51.4
```

Per-caller reach and offer rates (callers differ substantially, which is the mechanism):

```
      caller n_calls pct_reached n_offer_eligible pct_offered
1   Caller A      18        88.9               15        26.7
2   Caller B       1       100.0                1       100.0
3   Caller C      68        48.5               33        69.7
4   Caller D      56        48.2               23        82.6
5   Caller E       1       100.0                1       100.0
6   Caller F      15       100.0               15        21.4
7   Caller G      16        50.0                8        75.0
8 Unrecorded      59        11.9                6         0.0
```

Offer model adjusted for caller (scenario + caller + practice random intercept):

```
                         Estimate Std. Error      z value  Pr(>|z|)
(Intercept)             3.3310729   4.454300  0.747833011 0.4545609
scenarioLesbian couple -4.7426485   4.531931 -1.046496246 0.2953320
scenarioSingle mother  -5.0336075   4.306174 -1.168928047 0.2424326
callerCaller B         11.1099901  46.437168  0.239247796 0.8109134
callerCaller C          3.1010438   1.737978  1.784282305 0.0743778
callerCaller D          0.0336122   3.754765  0.008951879 0.9928575
callerCaller E          4.7459294  15.957413  0.297412204 0.7661518
callerCaller F         -1.4604792   2.269238 -0.643598889 0.5198356
callerCaller G         -0.7766047   3.769480 -0.206024359 0.8367719
callerUnrecorded       -9.5947732   8.791394 -1.091382409 0.2751046
```

> Inspect the standard errors above. Where they are very large, scenario and caller are not jointly identifiable and the adjusted estimate should not be reported as a corrected effect — it is evidence that the design cannot separate the two.

Drift checks (a distinct threat: rates changing over the study period or over a caller's call sequence):

- Calendar: Acceptance rates did not change significantly over the study period (slope=-0.064 per week, p = 0.539)
- Sequence: Acceptance rates did not change significantly over call sequence (slope=-0.003 per call, p = 0.693)

## MATCHED ANALYSIS — Within-Practice Paired Appointment Offer (exact McNemar)

Each contrast uses only practices called for BOTH scenarios; only DISCORDANT practices (different answer to the two callers) carry information, so effective n = the discordant count. Concordant practices (same answer to both) are the substantive majority — most practices do not differentiate — but contribute nothing to the test. Outcome = `appt_offered`. Caller confounding (above) is NOT removed by this pairing.

```
                           contrast n_paired concordant discordant disc_favor_A
1  Straight couple vs Single mother       16          9          7            6
2   Lesbian couple vs Single mother       21         19          2            0
3 Straight couple vs Lesbian couple       21         13          8            8
  disc_favor_B mcnemar_p mde_or_80power
1            1     0.125            8.1
2            2     0.500            8.1
3            0     0.008            9.0
```

Secondary — same pairing on reachability (a live office answered):

```
                           contrast n_paired concordant discordant disc_favor_A
1  Straight couple vs Single mother       54         37         17           11
2   Lesbian couple vs Single mother       65         50         15            9
3 Straight couple vs Lesbian couple       50         37         13            7
  disc_favor_B mcnemar_p mde_or_80power
1            6     0.332            3.3
2            6     0.607            3.8
3            6     1.000            4.6
```

**Power / precision:** discordant practices number only 7, 2, 8 across the three contrasts. At 80% power (alpha 0.05, exact McNemar) the smallest detectable effect is an odds ratio of roughly 8.1/8.1/9. Plausible audit-study effects (OR ~1.5-2.5) are well below this floor: the matched data can rule out a LARGE differential but is underpowered for small-to-moderate effects. Report as estimation with this precision statement, not as a null hypothesis test.

## PRIMARY ANALYSIS — Appointment Offered (mixed-effects logistic regression)

Outcome: `appt_offered` among offer-eligible calls. Random intercept for practice accounts for within-practice correlation across the scenario calls. Read every estimate below alongside the caller-confounding section.

### Complete Practice Triads Only (n = 76 records)
Restricted to practices called for ALL 3 scenarios, removing practice-selection dialing bias (but not caller confounding).

```
                   Term     OR CI_lo   CI_hi     p
            (Intercept) 18.081 2.986 109.507 0.002
 scenarioLesbian couple  0.039 0.005   0.276 0.001
  scenarioSingle mother  0.095 0.014   0.648 0.016
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. n = 76 records across 34 practices. Practice random-intercept variance: 9.977. 

### Full Offer Sample (n = 100 records)
> Includes unbalanced singletons/dyads, so practice selection is not removed. The triad model above is the primary estimate.

```
                   Term    OR CI_lo  CI_hi       p
            (Intercept) 7.840 1.806 34.033   0.006
 scenarioLesbian couple 0.055 0.010  0.303 < 0.001
  scenarioSingle mother 0.106 0.019  0.584   0.010
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. n = 100 records across 54 practices. Practice random-intercept variance: 10.679. 

### Sensitivity — Broad Offer Definition (n = 100 records)
Offer = appointment date OR a concrete scheduling timeframe. Tests whether the strict definition drives the result.

```
                   Term    OR CI_lo  CI_hi     p
            (Intercept) 5.459 1.664 17.906 0.005
 scenarioLesbian couple 0.308 0.076  1.246 0.099
  scenarioSingle mother 0.285 0.064  1.269 0.100
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. n = 100 records across 54 practices. Practice random-intercept variance: 5.208. 

## SECONDARY ANALYSIS — Reachability (a live office answered)

This is the model the pipeline previously reported as 'acceptance'. It is a real access outcome — whether the phone gets answered — but it is not the appointment-offer outcome the protocol specifies.

### Complete Practice Triads Only (n = 148 records)

```
                   Term    OR CI_lo CI_hi     p
            (Intercept) 1.448 0.583 3.595 0.425
 scenarioLesbian couple 1.085 0.410 2.870 0.869
  scenarioSingle mother 0.710 0.269 1.876 0.490
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. n = 148 records across 48 practices. Practice random-intercept variance: 4.219. 

### Full Sample (n = 234 records)

```
                   Term    OR CI_lo CI_hi     p
            (Intercept) 0.941 0.472 1.877 0.863
 scenarioLesbian couple 0.736 0.328 1.654 0.459
  scenarioSingle mother 0.641 0.282 1.458 0.289
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of the modelled outcome. n = 234 records across 105 practices. Practice random-intercept variance: 4.1. 

## TWO-PART (HURDLE) MODEL — offer and wait estimated jointly

The complete-case wait model below conditions on having an appointment date, and that missingness is strongly scenario-dependent — so it silently drops the selection step that carries most of the signal. mysterycall_hurdle_wait() estimates both parts: obtainment (odds ratios) and wait-given-obtained (incidence rate ratios).

```
<mysterycall hurdle wait model: hurdle n=100, count n=54 (zero-truncated nbinom2)>

Hurdle part -- appointment obtained (odds ratios):
# A tibble: 3 × 5
  term                    estimate   conf_low conf_high p_value
  <chr>                      <dbl>      <dbl>     <dbl>   <dbl>
1 (Intercept)            122.      2.27         6511.    0.0181
2 scenarioLesbian couple   0.00132 0.00000161      1.09  0.0530
3 scenarioSingle mother    0.00389 0.0000104       1.46  0.0665

Count part -- wait days | obtained (incidence rate ratios):
# A tibble: 3 × 5
  term                   estimate conf_low conf_high  p_value
  <chr>                     <dbl>    <dbl>     <dbl>    <dbl>
1 (Intercept)              24.0     16.1       35.9  2.42e-54
2 scenarioLesbian couple    0.778    0.471      1.29 3.28e- 1
3 scenarioSingle mother     0.869    0.497      1.52 6.24e- 1
```

> Check the confidence intervals on the hurdle part. Extremely wide intervals indicate near-separation with this sample size: the direction is informative, the magnitude is not.

## WAIT TIME — Mixed-Effects Linear Model (complete cases)

Via mysterycall_lmm(). The wait is right-skewed, so the package's auto_log applies log1p() and the table below is the back-transformed GEOMETRIC MEAN RATIO (GMR), not a difference in days. The intercept is the reference group's geometric-mean wait in business days; scenario rows are multiplicative (GMR < 1 = shorter wait). n = 57 records with an observed appointment date. Complete-case only — see the hurdle model above for the version that keeps the selection step.

```
                   Term   GMR CI_lo CI_hi       p
            (Intercept) 17.64 11.26 27.61 < 0.001
 scenarioLesbian couple  0.83  0.47  1.46   0.494
  scenarioSingle mother  0.82  0.46  1.45   0.479
```

Note: mysterycall_lmm() [lme4::lmer]. Outcome: log1p_business_days. auto_log applied log1p() to the right-skewed wait; the table is the back-transformed GEOMETRIC MEAN RATIO from $gmr_table. The intercept is the reference group's geometric-mean wait in business days; each scenario row is a multiplicative ratio vs. Straight couple (GMR < 1 = shorter wait). These are NOT differences in days. n = 57 records with observed appointment date. Shapiro-Wilk on residuals: p = 0.208 (normality satisfied). Marginal R² = 0.006, Conditional R² = 0.702.

## Wait Time by Scenario — Descriptive (unmatched)

```
# A tibble: 3 × 10
  scenario            n n_missing  mean    sd median    q1    q3   min   max
  <chr>           <int>     <int> <dbl> <dbl>  <dbl> <dbl> <dbl> <dbl> <dbl>
1 Straight couple    28         6  46.1  47.8   26.5   9    61.5     0   179
2 Lesbian couple     14        19  38.9  39.9   29     7    55.2     1   139
3 Single mother      15        16  26.9  30.0   18     5.5  41       0   105
```

- Unmatched test (descriptive only): Kruskal-Wallis; p = 0.297

## MATCHED ANALYSIS — Within-Practice Paired Wait Time (paired t / Wilcoxon)

Practices with an observed appointment date for BOTH scenarios. Even scarcer than the acceptance pairs because most included calls lack an appointment date (~40% missing).

```
                           contrast n_paired mean_diff_days sd_diff paired_t_p
1  Straight couple vs Single mother        8            0.8    22.7      0.928
2   Lesbian couple vs Single mother       10           -7.0    33.6      0.526
3 Straight couple vs Lesbian couple        9            7.6    26.5      0.417
  wilcoxon_p mde_days_80power
1      0.932             26.2
2      0.352             33.4
3      0.447             28.3
```

**Power / precision:** only 8, 10, 9 practices have both dates. The minimum detectable mean difference at 80% power is ~26.2/33.4/28.3 business days — far larger than any clinically meaningful gap. The paired wait-time comparison is the least-powered analysis in the study and should be reported as descriptive only.

## HOW TO READ THE OFFER RESULT

The appointment-offer contrast is the study's headline candidate, and it is fragile in three specific ways. State all three or do not report the effect.

1. **Outcome definition.** Strict (appointment date) and broad (date or a scheduling timeframe) give materially different answers. Compare the triad/full-sample models with the broad sensitivity model above. If the effect survives only under the strict definition, what is being measured may be whether the caller wrote a date down.
2. **Caller.** Cramer's V for caller x scenario is 0.66. In the caller-adjusted model the scenario standard errors inflate, which means the design cannot attribute the difference to caller identity rather than to scenario.
3. **Separation.** The practice random-intercept variance is large and several intervals span orders of magnitude. Odds-ratio magnitudes are not interpretable at this sample size; only direction is.

The well-powered, unconfounded results are the service-menu prevalences and the access cascade. Those do not depend on the derived offer outcome, on caller identity, or on the matched design.

## SENSITIVITY ANALYSIS — GEE (exchangeable correlation, logit link)

Population-average model; uses all records including singletons and dyads. Complements glmer (which is subject-specific/conditional). Exchangeable correlation within practice.

```
                        Estimate   Std.err      Wald     Pr(>|W|)
(Intercept)             1.205099 0.4004536  9.056102 0.0026181953
scenarioLesbian couple -1.592329 0.4449006 12.809725 0.0003448223
scenarioSingle mother  -1.338741 0.5021744  7.106962 0.0076785113
```

Note: GEE (sensitivity). Coefficients are log-ORs vs. Straight couple. 

## SERVICE MENU — the well-powered descriptive result

Denominator: 98 calls that reached staff and were asked the service questions. Wilson intervals via the package.

```
               option  n total prevalence ci_lower ci_upper
1      cycle_tracking 93    98      0.949    0.886    0.978
2     hormonal_timing 62    98      0.633    0.534    0.721
3 ovulation_induction 11    98      0.112    0.064    0.190
4                 iui  1    98      0.010    0.002    0.056
5                 ivf  1    98      0.010    0.002    0.056
```

Works with donor sperm:

```
  category  n total proportion ci_lower ci_upper method
1    FALSE 95    98      0.969    0.914    0.990 wilson
2     TRUE  3    98      0.031    0.010    0.086 wilson
```

> IUI and IVF are each a single practice. Report the proportion with its interval and say so explicitly; do not describe a 1/98 count as a rate estimate.

### Restriction checkboxes — needs adjudication before use

The only directly measured discrimination item. Currently unanalysable because the coding is ambiguous: the straight-couple box is ticked on straight-couple calls, so 'checked' may mean 'restricted' or 'served'. Resolve against the REDCap codebook, then this becomes a candidate primary outcome.

```
                    item checked_all checked_included
1       restrict_lesbian          27               27
2      restrict_straight          37               36
3 restrict_single_mother          19               19
                                     by_scenario_included
1  Straight couple=0, Lesbian couple=16, Single mother=11
2 Straight couple=12, Lesbian couple=11, Single mother=13
3   Straight couple=0, Lesbian couple=9, Single mother=10
```

## Missing Appointment Date Analysis

```
            variable n_observed n_missing pct_missing       test  statistic df
1           scenario         98         0        41.8 Chi-square 12.7528165  2
2 contact_first_call         98         0        41.8 Chi-square  0.3672411  1
3           attempts         98         0        41.8     Fisher         NA NA
4          insurance         76        22        41.8 Chi-square  0.4002389  1
5      cost_estimate         71        27        41.8 Chi-square  7.0073733  1
      p_value significant
1 0.001701222        TRUE
2 0.544511965       FALSE
3 0.484257871       FALSE
4 0.526965892       FALSE
5 0.008117469        TRUE
```

41 of 98 calls (41.8%) have a missing appointment date. Missingness was significantly associated with: scenario, cost_estimate. This pattern is consistent with data missing at random (MAR) conditional on observed covariates. Complete-case analyses may underestimate the magnitude of insurance-related disparities; consider multiple imputation or sensitivity analyses for robustness.

### Little's MCAR test

```
         variable           label missingness_type n_total n_missing
1 first_appt_date first_appt_date       item-level      98        41
2   wait_category   wait_category       item-level      98        36
3  pregnancy_time  pregnancy_time       item-level      98        29
4   cost_estimate   cost_estimate       item-level      98        27
5       insurance       insurance       item-level      98        22
  pct_missing n_unknown n_informative pct_informative
1        41.8         0            57            58.2
2        36.7         0            62            63.3
3        29.6         0            69            70.4
4        27.6         0            71            72.4
5        22.4         0            76            77.6
```

- Missingness was assessed for 5 analytic variables across 98 units, separated into item-level (n=5) and structural, missing-by-design (n=0) mechanisms. Item-level missingness ranged from 22.4% to 41.8% (greatest for first_appt_date) and reflects source non-linkage that is independent of the subgroup structure, rather than missingness conditioned on a unit's subgroup or observation status. Little's MCAR test not evaluated: Fewer than 2 numeric item-level variables; Little's test not defined.

## Data-Quality Guards

- Wait-time contamination guard (mysterycall_guard_contaminated_wait): clean
- Reached but no appointment date recorded: 41 calls (these are the rows the strict offer definition scores as refusals)
- Excluded but carrying an appointment date: 0 calls

## Key Record IDs for Manual Review

- Missing scenario: 
- Included but incomplete: 
- Complete but excluded: 1, 4, 5, 7, 8, 10, 12, 13, 18, 19, 20, 21, 22, 23, 25, 27, 29, 30, 31, 32, 34, 35, 36, 37, 39, 40, 41, 44, 47, 50, 51, 52, 56, 69, 74, 79, 80, 81, 82, 83, 84, 85, 92, 93, 102, 103, 104, 105, 108, 109, 110, 117, 120, 124, 125, 127, 129, 130, 132, 133, 134, 135, 136, 137, 138, 140, 141, 142, 143, 144, 145, 146, 148, 149, 150, 151, 152, 153, 154, 155, 157, 159, 161, 162, 163, 165, 166, 168, 169, 172, 174, 177, 180, 181, 182, 183, 184, 185, 186, 187, 189, 190, 191, 192, 194, 202, 212, 213, 214, 215, 216, 217, 218, 220, 221, 222, 223, 225, 226, 227, 228, 229, 231, 232, 233, 234
- Included/finalized but missing call time: 33
- Included/finalized but missing appt date: 43, 45, 57, 59, 63, 65, 66, 71, 75, 90, 95, 96, 97, 98, 99, 106, 111, 112, 114, 115, 121, 122, 123, 126, 128, 131, 139, 147, 156, 158, 164, 178, 179, 188, 193, 195, 196, 197, 199, 200, 230
- Negative wait days: 
- Wait days > 180: 

## Output Files

- `labubu_cleaned_analysis.csv`
- `mysterycall_paired_acceptance_mcnemar.csv`
- `mysterycall_paired_wait_within_practice.csv`
- `practice_name_review_nearduplicates.csv`
- `practice_name_review_singletons.csv`
- `mysterycall_completeness.csv`
- `mysterycall_access_cascade.csv`
- `mysterycall_access_cascade_by_scenario.csv`
- `mysterycall_reach_by_scenario.csv`
- `mysterycall_offer_by_scenario.csv`
- `mysterycall_offer_by_scenario_broad.csv`
- `mysterycall_paired_reached_mcnemar.csv`
- `mysterycall_service_prevalence.csv`
- `mysterycall_missingness_mcar.csv`
- `caller_by_scenario.csv`
- `caller_rates.csv`
- `caller_dominance_by_scenario.csv`
- `exclusion_crosswalk.csv`
- `restriction_checkbox_review.csv`
- `matched_reached_wide.csv`
- `mysterycall_wait_by_scenario_included.csv`
- `mysterycall_wait_by_scenario_included_complete.csv`
- `mysterycall_missing_appt_summary.csv`
- `mysterycall_table1_included_complete.csv`
- `scenario_counts_by_completion.csv`
- `scenario_counts_by_inclusion.csv`
- `practice_scenario_coverage.csv`
- `matched_acceptance_wide.csv`
- `matched_wait_wide.csv`
