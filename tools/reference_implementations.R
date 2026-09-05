# reference_implementations.R
#
# Independent reference implementations of every quantity the manuscript
# reports, written from the published formula and deliberately NOT delegating to
# the function that produced the number under test.
#
# The pattern, and the argument for it, are borrowed from mufflyt/isochrones-ci:
#
#   "A test suite that lives inside the code it tests shares that code's blind
#    spots. If a helper is subtly wrong, both the implementation and its tests
#    use the wrong helper, and the suite certifies the wrong answer with total
#    confidence."
#
# and, on statistical helpers specifically:
#
#   "Every reference here is written from the formula, not delegated to the R
#    function production also calls. Comparing prop.test() to prop.test() would
#    certify agreement between a function and itself."
#
# LABUBU's twenty gate invariants are all structural: they check that a number
# came from the right denominator, was labelled correctly, or was not aliased to
# something else. None of them recompute a number. Everything in the manuscript
# ultimately comes out of `mysterycall`, and every check calls `mysterycall` to
# verify it. This file is the first thing in the repository that does not.
#
# Nothing here may call mysterycall, and nothing here may call the pipeline.

# ── Wilson score interval for a single proportion ─────────────────────────────
# Wilson EB (1927), J Am Stat Assoc 22:209-212. The interval is the set of p0
# for which |p_hat - p0| / sqrt(p0(1-p0)/n) <= z, solved as a quadratic, which
# is why it is not symmetric about p_hat and does not collapse at 0 or 1 the way
# the Wald interval does.
ref_wilson_ci <- function(x, n, conf = 0.95) {
  stopifnot(x >= 0, n > 0, x <= n)
  z  <- stats::qnorm(1 - (1 - conf) / 2)
  ph <- x / n
  d  <- 1 + z^2 / n
  c1 <- (ph + z^2 / (2 * n)) / d
  hw <- (z / d) * sqrt(ph * (1 - ph) / n + z^2 / (4 * n^2))
  c(estimate = ph, lower = max(0, c1 - hw), upper = min(1, c1 + hw))
}

# ── Clopper-Pearson exact interval ────────────────────────────────────────────
# Clopper & Pearson (1934), Biometrika 26:404-413. Inverts the binomial test;
# expressed through the Beta quantile function, which is exact rather than an
# approximation of the inversion.
ref_clopper_pearson_ci <- function(x, n, conf = 0.95) {
  stopifnot(x >= 0, n > 0, x <= n)
  a <- (1 - conf) / 2
  lo <- if (x == 0) 0 else stats::qbeta(a,     x,     n - x + 1)
  hi <- if (x == n) 1 else stats::qbeta(1 - a, x + 1, n - x)
  c(estimate = x / n, lower = lo, upper = hi)
}

# ── Exact McNemar test ────────────────────────────────────────────────────────
# Conditional on the number of discordant pairs, the count favouring one
# direction is Binomial(n_discordant, 1/2) under the null. The exact two-sided
# p is the two-sided binomial test, NOT the chi-square approximation with or
# without continuity correction. With the two to eight discordant pairs LABUBU
# actually has, the approximation is not usable, so the distinction is not
# academic.
ref_mcnemar_exact_p <- function(b, c) {
  n <- b + c
  if (n == 0) return(1)
  stats::binom.test(b, n, p = 0.5, alternative = "two.sided")$p.value
}

# ── Minimum detectable odds ratio for a paired design ─────────────────────────
# Power in a paired binary design depends on the discordant pairs alone. Under
# the null the discordant split is Binomial(n, 1/2); under an alternative with
# odds ratio psi it is Binomial(n, psi/(1+psi)). Solve for the smallest psi whose
# exact binomial test attains `power` at the given alpha, by direct search over
# the exact rejection region rather than a normal approximation.
ref_mde_or_paired <- function(n_discordant, power = 0.80, alpha = 0.05,
                              upper = 200) {
  if (n_discordant < 1) return(NA_real_)
  # Exact rejection region: the discordant counts whose two-sided binomial p is
  # at or below alpha under H0.
  ks   <- 0:n_discordant
  pval <- vapply(ks, function(k)
    stats::binom.test(k, n_discordant, 0.5)$p.value, numeric(1))
  reject <- ks[pval <= alpha]
  if (!length(reject)) return(NA_real_)   # no attainable rejection at this n
  pow_at <- function(psi) {
    p <- psi / (1 + psi)
    sum(stats::dbinom(reject, n_discordant, p))
  }
  if (pow_at(upper) < power) return(NA_real_)
  stats::uniroot(function(psi) pow_at(psi) - power,
                 interval = c(1 + 1e-9, upper))$root
}

# ── Business days between two dates ───────────────────────────────────────────
# Weekdays in the half-open interval (from, to], excluding US federal holidays.
# Counted by enumerating days rather than by any weekday arithmetic shortcut:
# the shortcut is where off-by-one errors live, and this is a reference, so it
# is written for transparency rather than speed.
#
# The holiday rule is written out explicitly instead of being read from a
# calendar package, so that a wrong calendar in production cannot be confirmed
# by a reference that consults the same calendar.
ref_us_federal_holidays <- function(years) {
  nth_wday <- function(year, month, wday, n) {
    d <- seq(as.Date(sprintf("%d-%02d-01", year, month)),
             by = "day", length.out = 31)
    d <- d[format(d, "%m") == sprintf("%02d", month)]
    hits <- d[as.integer(format(d, "%u")) == wday]
    if (n > 0) hits[n] else rev(hits)[-n]
  }
  out <- as.Date(character(0))
  for (y in years) {
    h <- c(
      as.Date(sprintf("%d-01-01", y)),   # New Year's Day
      nth_wday(y, 1, 1, 3),              # MLK Day, 3rd Monday in January
      nth_wday(y, 2, 1, 3),              # Washington's Birthday, 3rd Mon Feb
      nth_wday(y, 5, 1, -1),             # Memorial Day, last Monday in May
      as.Date(sprintf("%d-06-19", y)),   # Juneteenth
      as.Date(sprintf("%d-07-04", y)),   # Independence Day
      nth_wday(y, 9, 1, 1),              # Labor Day, 1st Monday in September
      nth_wday(y, 10, 1, 2),             # Columbus Day, 2nd Monday in October
      as.Date(sprintf("%d-11-11", y)),   # Veterans Day
      nth_wday(y, 11, 4, 4),             # Thanksgiving, 4th Thursday in Nov
      as.Date(sprintf("%d-12-25", y)))   # Christmas Day
    # Federal observance: a Saturday holiday is observed on the preceding
    # Friday, a Sunday holiday on the following Monday.
    wd  <- as.integer(format(h, "%u"))
    obs <- h + ifelse(wd == 6, -1, ifelse(wd == 7, 1, 0))
    out <- c(out, h, obs)
  }
  sort(unique(out))
}

ref_business_days <- function(from, to, holidays = NULL) {
  from <- as.Date(from); to <- as.Date(to)
  n <- max(length(from), length(to))
  from <- rep_len(from, n); to <- rep_len(to, n)
  if (is.null(holidays)) {
    yrs <- unique(as.integer(format(c(from, to), "%Y")))
    yrs <- yrs[!is.na(yrs)]
    holidays <- if (length(yrs))
      ref_us_federal_holidays(seq(min(yrs) - 1L, max(yrs) + 1L)) else as.Date(character(0))
  }
  vapply(seq_len(n), function(i) {
    a <- from[i]; b <- to[i]
    if (is.na(a) || is.na(b)) return(NA_real_)
    if (b <= a) return(0)
    d  <- seq(a + 1, b, by = "day")          # half-open: (a, b]
    wd <- as.integer(format(d, "%u"))
    sum(wd <= 5 & !(d %in% holidays))
  }, numeric(1))
}

# ── Geometric mean ratio from log-scale coefficients ──────────────────────────
# The back-transform is exp(beta). Stated as a reference so that a coefficient
# reported on the log scale cannot silently be printed as a day difference,
# which is the failure report/wait-reported-as-gmr-not-days guards structurally
# and this guards numerically.
ref_gmr <- function(beta, se, z = stats::qnorm(0.975)) {
  c(gmr = exp(beta), lower = exp(beta - z * se), upper = exp(beta + z * se))
}

# ── Variance-components ICC ───────────────────────────────────────────────────
# ICC = between-group variance / (between + within). Written from the definition
# so the caller ICC reported in the manuscript is checked against something
# other than the lme4 call that produced it. This is the one-way random-effects
# ANOVA estimator (ICC(1) in Shrout & Fleiss 1979), which for unbalanced groups
# uses the mean group size correction n0.
ref_icc_oneway <- function(value, group) {
  keep  <- !is.na(value) & !is.na(group)
  value <- as.numeric(value[keep]); group <- as.factor(as.character(group[keep]))
  k <- nlevels(group); N <- length(value)
  if (k < 2 || N <= k) return(NA_real_)
  ni    <- as.numeric(table(group))
  gmean <- tapply(value, group, mean)
  msb   <- sum(ni * (gmean - mean(value))^2) / (k - 1)
  msw   <- sum((value - gmean[as.character(group)])^2) / (N - k)
  n0    <- (N - sum(ni^2) / N) / (k - 1)
  icc   <- (msb - msw) / (msb + (n0 - 1) * msw)
  max(0, min(1, icc))
}
