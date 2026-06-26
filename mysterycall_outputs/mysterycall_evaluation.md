# LABUBU Mysterycall Evaluation

Generated: 2026-06-25 20:57:55 MDT

## Package

- mysterycall version: 1.5.0

## Denominators

- All records: 176
- Analytic inclusion (exclusion field): 75
- Analytic inclusion AND finalized form: 75

## Data Quality

- Completeness quality tier: low
- Completeness score: 0.728
- General quality score: 0.95

## Data Collection Status

Study design: each RRM practice called once per scenario (straight couple, lesbian couple, single mother using donor sperm). Primary analysis: mixed-effects logistic regression with practice random intercept (lme4::glmer). Note: REI comparison arm removed from scope; analysis is within-RRM only.

- Total unique practices: 102
- Complete triads (all 3 scenarios): 19
- Dyads (2 of 3 scenarios): 32
- Singletons (1 scenario only): 51

Missing calls by scenario:
  - Missing straight-couple call: 33 practices
  - Missing lesbian-couple call:  21 practices
  - Missing single-mother call:   80 practices

## Acceptance Rate by Scenario — Descriptive (unmatched)

`accepted` = analytic inclusion flag (practice successfully scheduled the caller).

```
# A tibble: 3 × 8
  scenario       n_total n_missing n_accepted n_rejected  rate ci_lower ci_upper
  <chr>            <int>     <int>      <int>      <int> <dbl>    <dbl>    <dbl>
1 Straight coup…      71         0         28         43 0.394    0.289    0.511
2 Lesbian couple      83         0         25         58 0.301    0.213    0.407
3 Single mother       22         0         22          0 1        0.851    1    
```

- Chi-square (independent groups, descriptive only): chi-square (small cells -- interpret cautiously); p = < 0.001

## PRIMARY ANALYSIS — Mixed-Effects Logistic Regression (glmer)

Protocol-specified analysis via mysterycall_logistic_model(). Random intercept for practice accounts for within-practice correlation across the three scenario calls. n = 176 records.

```
                   Term           OR CI_lo CI_hi     p
            (Intercept)        0.584 0.306 1.116 0.104
 scenarioLesbian couple        0.579 0.263 1.276 0.175
  scenarioSingle mother 72532611.392 0.000   Inf 0.989
```

Note: mysterycall_logistic_model() [lme4::glmer]. Reference: Straight couple. OR < 1 = lower odds of appointment offer. n = 176 records across 102 practices. Practice random-intercept variance: 2.62. WARNING: complete separation for: scenarioSingle mother. OR not interpretable; consider Firth penalized regression.

## SECONDARY ANALYSIS — Mixed-Effects Linear Model for Wait Time (lmm)

Via mysterycall_lmm(). n = 53 records with observed wait time.

```
                   Term log_Est log_CI_lo log_CI_hi   GMR GMR_lo GMR_hi       p
            (Intercept)   3.160     2.666     3.653 23.56  14.39  38.59 < 0.001
 scenarioLesbian couple  -0.143    -0.720     0.434  0.87   0.49   1.54   0.631
  scenarioSingle mother  -0.036    -0.633     0.561  0.96   0.53   1.75   0.907
```

Note: mysterycall_lmm() [lme4::lmer] on log1p(wait_days). log_Est = coefficient on log scale; GMR = geometric mean ratio of (wait_days + 1) vs. Straight couple (reference); GMR < 1 = shorter wait. n = 53 records with observed wait time. Shapiro-Wilk on residuals: p = 0.357 (log-transform applied; check Q-Q plot if still flagged). Marginal R² = 0.002, Conditional R² = 0.715.

## Wait Time by Scenario — Descriptive (unmatched)

```
# A tibble: 3 × 10
  scenario            n n_missing  mean    sd median    q1    q3   min   max
  <chr>           <int>     <int> <dbl> <dbl>  <dbl> <dbl> <dbl> <dbl> <dbl>
1 Straight couple    26         2  57.8 107.    23    9     59.2     0   544
2 Lesbian couple     12        13  29.1  28.9   17.5  6.75  50       1    92
3 Single mother      13         9  26.3  29.8   18    6     33       0   105
```

- Unmatched test (descriptive only): Kruskal-Wallis; p = 0.391

## SENSITIVITY ANALYSIS — GEE (exchangeable correlation, logit link)

Population-average model; uses all records including singletons and dyads. Complements glmer (which is subject-specific/conditional). Exchangeable correlation within practice.

```
                            Estimate      Std.err         Wald   Pr(>|W|)
(Intercept)            -4.776008e-01 2.411740e-01 3.921652e+00 0.04766802
scenarioLesbian couple -4.514990e-01 2.805163e-01 2.590581e+00 0.10750089
scenarioSingle mother   4.503599e+15 6.731298e+06 4.476326e+17 0.00000000
```

Note: GEE (sensitivity). Coefficients are log-ORs vs. Straight couple. WARNING: complete separation for: scenarioSingle mother.

## Missing Appointment Date Analysis

```
            variable n_observed n_missing pct_missing       test  statistic df
1           scenario         75         0          32 Chi-square 13.3486917  2
2 contact_first_call         75         0          32 Chi-square  2.2486772  1
3           attempts         75         0          32     Fisher         NA NA
4          insurance         67         8          32 Chi-square  0.8282862  1
5      cost_estimate         64        11          32     Fisher         NA NA
      p_value significant
1 0.001262898        TRUE
2 0.133728670       FALSE
3 0.143428286       FALSE
4 0.362768570       FALSE
5 0.006156476        TRUE
```

24 of 75 calls (32%) have a missing appointment date. Missingness was significantly associated with: scenario, cost_estimate. This pattern is consistent with data missing at random (MAR) conditional on observed covariates. Complete-case analyses may underestimate the magnitude of insurance-related disparities; consider multiple imputation or sensitivity analyses for robustness.

## Key Record IDs for Manual Review

- Missing scenario: 
- Included but incomplete: 
- Complete but excluded: 1, 4, 5, 7, 8, 10, 12, 13, 18, 19, 20, 21, 22, 23, 25, 27, 29, 30, 32, 34, 35, 36, 37, 39, 40, 41, 44, 47, 50, 51, 52, 56, 69, 74, 79, 80, 81, 82, 83, 84, 85, 92, 93, 102, 103, 104, 105, 108, 109, 110, 117, 120, 124, 125, 127, 129, 130, 133, 135, 137, 140, 148, 159, 161, 162, 163, 164, 165, 166, 168, 169, 172, 174
- Included/finalized but missing call time: 33
- Included/finalized but missing appt date: 43, 45, 57, 59, 63, 65, 66, 71, 90, 95, 96, 97, 98, 99, 106, 115, 121, 122, 123, 126, 128, 139, 147, 158
- Negative wait days: 
- Wait days > 180: 116

## Output Files

- `labubu_cleaned_analysis.csv`
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
