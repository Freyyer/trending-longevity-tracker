# One-Page Memo: Friday Publishing and Multi-Day Retention

**To**: Creator Operations Team (hypothetical audience — see honest disclosures in the main README)

---

**Finding**: FRANCE and CANADA's trending lists churn daily — 59-75% of videos survive only one day. Videos published on Friday show multi-day retention rates 4-5 percentage points higher than other days, consistently across three of four markets (`notebooks/04-hypothesis-test.ipynb`).

**Recommendation**: Run an experiment in FRANCE and CANADA before recommending Friday publishing at scale. US and GB don't need this — their retention is already saturated at 89-93% (`docs/data-quality-report.md`).

**Why**: The observational data has a confound — better-performing channels may simply prefer Fridays already. A demonstration on the public-data proxy metric puts the sample at roughly 3,400-4,250 videos per market; the real sample size (using the true "all published videos" denominator) needs recalculating against internal data. Randomizing by channel (to avoid contaminating results across correlated videos) will need a larger sample still. Estimated duration: 4 weeks. Full design in `docs/experiment-proposal.md`.

---

**We don't know**: the true denominator for the primary metric (share of *all published* videos that trend and stay 2+ days) isn't computable from public data — see `docs/what-data-cannot-answer.md`.
