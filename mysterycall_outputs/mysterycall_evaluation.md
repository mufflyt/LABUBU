# LABUBU Mysterycall Evaluation

Generated: 2026-08-19 20:05:13 MDT

## Package

- mysterycall version: 1.6.3.9000

## Denominators

- All records: 234
- Analytic inclusion (exclusion field): 98
- Analytic inclusion AND finalized form: 98

## Data Quality

- Completeness quality tier: low
- Completeness score: 0.705
- General quality score: 0.95

## Data Collection Status

Study design: each RRM practice called once per scenario (straight couple, lesbian couple, single mother using donor sperm). Primary analysis: mixed-effects logistic regression with practice random intercept (lme4::glmer). Note: REI comparison arm removed from scope; analysis is within-RRM only.

- Total unique practices: 106
- Complete triads (all 3 scenarios): 48
- Dyads (2 of 3 scenarios): 25
- Singletons (1 scenario only): 33

Missing calls by scenario:
  - Missing straight-couple call: 33 practices
  - Missing lesbian-couple call:  25 practices
  - Missing single-mother call:   33 practices

## Acceptance Rate by Scenario — Descriptive (unmatched)

`accepted` = analytic inclusion flag (practice successfully scheduled the caller).

```
# A tibble: 3 x 8
  scenario       n_total n_missing n_accepted n_rejected  rate ci_lower ci_upper
  <chr>            <int>     <int>      <int>      <int> <dbl>    <dbl>    <dbl>
1 Straight coup~      77         0         34         43 0.442    0.336    0.553
2 Lesbian couple      83         0         33         50 0.398    0.299    0.505
3 Single mother       74         0         31         43 0.419    0.313    0.533
```

- Chi-square (independent groups, descriptive only): chi-square; p = 0.853

> **CONFOUNDING CAUTION — do not report this chi-square as a result.** The three scenarios were not called at the same practices: single-mother calls landed disproportionately at high-acceptance practices (practices that received a single-mother call accept ~70% of *all* callers vs ~14% at practices that did not). The marginal rate therefore reflects *which practices were dialed*, not how callers were treated. Use the within-practice paired analysis below.

## MATCHED ANALYSIS — Within-Practice Paired Acceptance (exact McNemar)

Each contrast uses only practices called for BOTH scenarios; only DISCORDANT practices (different answer to the two callers) carry information, so effective n = the discordant count. Concordant practices (same answer to both) are the substantive majority — most practices do not differentiate — but contribute nothing to the test.

```
                           contrast n_paired concordant discordant disc_favor_A
1  Straight couple vs Single mother       54         37         17           11
2   Lesbian couple vs Single mother       65         52         13            7
3 Straight couple vs Lesbian couple       50         37         13            8
  disc_favor_B mcnemar_p mde_or_80power
1            6     0.332            3.3
2            6     1.000            4.6
3            5     0.581            4.6
```

**Power / precision:** discordant practices number only 17, 13, 13 across the three contrasts. At 80% power (alpha 0.05, exact McNemar) the smallest detectable effect is an odds ratio of roughly 3.3/4.6/4.6. Plausible audit-study effects (OR ~1.5-2.5) are well below this floor: the matched data can rule out a LARGE differential but is underpowered for small-to-moderate effects. Report as estimation with this precision statement, not as a null hypothesis test.

## PRIMARY ANALYSIS — Mixed-Effects Logistic Regression (glmer)

Protocol-specified analysis via mysterycall_logistic_model(). Random intercept for practice accounts for within-practice correlation across the scenario calls.

### Unconfounded Model — Complete Practice Triads Only (n = 
148
 records)
Restricted to practices called for ALL 3 scenarios to eliminate practice-selection dialing bias.

```
                   Term    OR CI_lo CI_hi     p
            (Intercept) 1.307 0.506 3.375 0.580
 scenarioLesbian couple 0.890 0.331 2.391 0.817
  scenarioSingle mother 0.701 0.260 1.887 0.482
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of appointment offer. n = 148 records across 48 practices. Practice random-intercept variance: 4.864. 

### Full-Sample Model — All Records (n = 
234
 records)
> **CONFOUNDING WARNING:** Includes unbalanced singletons/dyads. Single-mother calls landed 
> disproportionately at high-acceptance practices, causing this full-sample GLMER to reflect 
> practice selection rather than scenario effects. Use the complete-triads model above.

```
                   Term    OR CI_lo CI_hi     p
            (Intercept) 0.689 0.332 1.431 0.317
 scenarioLesbian couple 0.706 0.305 1.633 0.416
  scenarioSingle mother 0.720 0.308 1.682 0.447
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of appointment offer. n = 234 records across 106 practices. Practice random-intercept variance: 4.906. 

## SECONDARY ANALYSIS — Mixed-Effects Linear Model for Wait Time in Business Days (lmm)

Via mysterycall_lmm(). Outcome: business days (Mon–Fri, US federal holidays excluded). Estimates report the mean difference in business days relative to straight-couple callers (reference). n = 57 records with an observed appointment date. Note: wait-time distributions are typically right-skewed; see normality caveat in the model note below.

```
                   Term Est_business_days CI_lo CI_hi       p
            (Intercept)               2.9   2.4   3.3 < 0.001
 scenarioLesbian couple              -0.2  -0.8   0.4   0.494
  scenarioSingle mother              -0.2  -0.8   0.4   0.479
```

Note: mysterycall_lmm() [lme4::lmer]. Outcome: business days until appointment (Mon-Fri, excluding US federal holidays). Estimates are mean difference in business days vs. Straight couple (reference); negative = shorter wait. n = 57 records with observed appointment date. Shapiro-Wilk on residuals: p = 0.208 (normality satisfied). Marginal R² = 0.006, Conditional R² = 0.702.

## Wait Time by Scenario — Descriptive (unmatched)

```
# A tibble: 3 x 10
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

## SENSITIVITY ANALYSIS — GEE (exchangeable correlation, logit link)

Population-average model; uses all records including singletons and dyads. Complements glmer (which is subject-specific/conditional). Exchangeable correlation within practice.

```
                         Estimate   Std.err      Wald  Pr(>|W|)
(Intercept)            -0.3121386 0.2294665 1.8503602 0.1737415
scenarioLesbian couple -0.2328952 0.2622826 0.7884649 0.3745647
scenarioSingle mother  -0.2144550 0.2840270 0.5701027 0.4502181
```

Note: GEE (sensitivity). Coefficients are log-ORs vs. Straight couple. 

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
3 0.486756622       FALSE
4 0.526965892       FALSE
5 0.008117469        TRUE
```

41 of 98 calls (41.8%) have a missing appointment date. Missingness was significantly associated with: scenario, cost_estimate. This pattern is consistent with data missing at random (MAR) conditional on observed covariates. Complete-case analyses may underestimate the magnitude of insurance-related disparities; consider multiple imputation or sensitivity analyses for robustness.

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
- `mysterycall_acceptance_by_scenario_all_records.csv`
- `mysterycall_acceptance_by_scenario_finalized_records.csv`
- `mysterycall_wait_by_scenario_included.csv`
- `mysterycall_wait_by_scenario_included_complete.csv`
- `mysterycall_missing_appt_summary.csv`
- `mysterycall_table1_included_complete.csv`
- `scenario_counts_by_completion.csv`
- `scenario_counts_by_inclusion.csv`
- `practice_scenario_coverage.csv`
- `matched_acceptance_wide.csv`
- `matched_wait_wide.csv`
