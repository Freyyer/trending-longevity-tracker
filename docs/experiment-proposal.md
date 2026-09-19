# Experiment Proposal: Does Friday Publishing Improve Multi-Day Retention?

**Audience**: a hypothetical creator operations team (this project has no real employer or client — see the honest disclosures in the main README).

## Observed starting point

Pooled by publish weekday, Friday-published videos show the highest multi-day retention rate (44.7%), Saturday the lowest (37.2%). But pooled numbers across four countries with wildly different mechanisms are not trustworthy on their own — see `docs/data-quality-report.md` and `notebooks/02-metric-tables.ipynb` for why. Broken down per country (`notebooks/04-hypothesis-test.ipynb`):

| Country | Friday retention | Non-Friday | Diff (points) | 95% CI (Newcombe) | Friday n |
|---|---|---|---|---|---|
| FRANCE | 29.0% | 24.0% | +5.0 | +3.7 to +6.4 | 4,873 |
| CANADA | 44.0% | 39.9% | +4.2 | +2.5 to +5.9 | 3,904 |
| US | 91.8% | 88.3% | +3.5 | +1.5 to +5.3 | 1,038 |
| GB | 93.6% | 93.0% | +0.6 | -1.8 to +2.6 | 610 |

Three countries show a consistent positive effect with confidence intervals not crossing zero; GB doesn't. GB's baseline is already ~93% — a ceiling effect, not evidence that "Friday doesn't work in GB". This is a candidate lever, not a causal effect: better-performing channels may simply prefer publishing on Fridays already (confounding).

A logistic regression (`survived_day1 ~ is_friday + C(publish_country)`, FRANCE as reference, no interaction term — one model, one question) confirms the association holds after controlling for country: `is_friday` odds ratio 1.25 (95% CI 1.19-1.31). This model is descriptive, not causal, and doesn't control for channel quality — the odds ratio should be read as "the strength of association after controlling for country," not "the effect of Friday publishing."

## Hypothesis test design

- **Null hypothesis**: within a given country, Friday-published and non-Friday-published videos have the same multi-day retention rate
- **Primary metric for this test**: `survived_day1`, binary — chosen over average days-on-trending because FRANCE and CANADA have 59-75% of videos surviving only 1 day, and a mean would be dominated by long-tail outliers
- **Test**: four separate two-proportion z-tests, not a pooled test — pooling mixes in the country-composition effect
- **Effect size**: difference in proportions, with Newcombe-method confidence intervals, cross-checked with a 2,000-iteration bootstrap
- **Secondary metric**: `days_on_trending`, tested with Mann-Whitney U (the distribution is right-skewed and non-normal, violating the t-test's assumptions)
- **Second implementation of the stratified test**: logistic regression, controlling for country. Chosen over a Cochran-Mantel-Haenszel test because it satisfies a "regression analysis" skill requirement while doing the same job — one method for two needs

## Proposal

| Element | Design | Reasoning |
|---|---|---|
| Hypothesis | Nudging creators to publish on Friday improves multi-day retention | From the observation above; directionally consistent across three countries |
| Target markets | **FRANCE and CANADA**, analyzed independently | US and GB have baselines of 89-93% — the binary metric is already saturated, and GB's observed effect isn't even significant. The two target markets' baselines differ by 16 points, so they can't be merged into one analysis |
| Randomization unit | **Channel**, not video | Videos from the same channel are highly correlated (audience, style, publishing habits). Randomizing by video would let the same channel appear in both treatment and control, diluting the treatment effect through contamination |
| Treatment | Receives a "consider publishing on Friday" prompt | Actionable for operations |
| Control | No prompt | |
| Primary metric | **Share of all videos published by the channel during the experiment that trend and stay on the list 2+ days** | Denominator is "all published videos," not "already-trending videos." The treatment itself may change which videos trend — if the denominator were "already-trending," both groups' denominators would already be filtered by the treatment, making the comparison unclean |
| Guardrail metrics | Trending rate (share of published videos that make the list) must not decline; weekly publish volume must not decline | Prevents creators from publishing less while waiting for Friday, and prevents the treatment from merely reclassifying "trending" as "surviving" without real improvement |
| **Calculation basis note** | The baseline, MDE, and sample size rows below are demonstrated on the **proxy metric** (multi-day retention rate, denominator = already-trending videos) computable from public data | The real primary metric's denominator is "all published videos" — public data doesn't have it. Switching to the real denominator would drop the baseline by an order of magnitude (perhaps 1-2%, if only ~5% of published videos ever trend), at which point an absolute 3-point MDE is unrealistic and should become a relative lift (e.g., 10-15%), with sample size recalculated against the internal baseline. The value of this demonstration is a reproducible *process*, not these specific numbers |
| Baseline (proxy metric) | FRANCE 24.8%, CANADA 40.5% (multi-day retention rate, from `video_life`) | |
| Minimum detectable effect (proxy metric) | +3 percentage points | A business judgment about the smallest lift worth acting on, not a statistical one |
| Significance level / power | alpha = 0.05 two-sided, power = 0.80 | Industry default |
| Sample size (proxy metric) | Video-level: FRANCE ~3,380/group, CANADA ~4,250/group. Randomizing by channel requires multiplying by a design effect (typically 1.5-3x); an intra-class correlation coefficient (ICC) should be estimated from internal data before execution | See calculation below |
| Duration | At least 4 full weeks | Avoids single-week anomalies |
| Early stopping rule | **Stop only if a guardrail metric breaches its threshold.** Do not stop early just because the primary metric becomes significant — this avoids peeking | |

## Sample size calculation: two methods, cross-checked

Inputs: baseline proportion p0, target p1 = p0 + 0.03, alpha = 0.05 two-sided (0.025 one-sided-equivalent), power = 0.80.

- **Tool**: `statsmodels.stats.proportion.samplesize_proportions_2indep_onetail(diff=0.03, prop2=p0, power=0.8, alpha=0.025, alternative='larger')`
- **Manual cross-check**: n/group = (z_0.975 + z_0.80)^2 x [p0(1-p0) + p1(1-p1)] / 0.03^2
- FRANCE: p0 = 0.248, tool 3,380, manual 3,377
- CANADA: p0 = 0.405, tool 4,249, manual 4,246
- The two methods agree within 3 units

**A gotcha worth flagging**: `samplesize_proportions_2indep_onetail` defaults to `alternative='two-sided'` despite its name — passing `alpha=0.025` alone without `alternative='larger'` silently computes a two-sided sample size (I first got 4,093 for FRANCE, not 3,380, until I caught this). This is easy to get wrong and worth double-checking with the manual formula every time.

**Sample ratio mismatch (SRM)**: after randomization, verify that the two groups have close-to-50/50 channel counts before running the experiment. A deviation is grounds to suspect the randomization itself.

## Non-technical summary

Two markets (FRANCE, CANADA) have trending lists that churn daily — most videos survive only one day. Videos published on Friday show 4-5 percentage points higher multi-day retention than other days, consistently across three of four markets. This is worth testing directly with an experiment rather than acting on the observation alone, since better channels may simply prefer Fridays already (a confound the observational data can't rule out). A proxy-metric demonstration puts the required sample at roughly 3,400-4,250 videos per market; the real sample size (using the true "all published videos" denominator) would need to be recalculated against internal data before running the experiment. Estimated duration: 4 weeks.
