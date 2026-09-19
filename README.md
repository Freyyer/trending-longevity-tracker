# trending-longevity-tracker

Rebuilding a broken metric from raw YouTube trending-list snapshots, and designing an A/B test for the one lever that looks like it moves the needle.

## TL;DR

On the most commonly used YouTube trending dataset on Kaggle, the official field documentation turned out to be wrong. I rebuilt cumulative trending days from raw "video x country x day" event rows, built a three-layer metrics stack and a public dashboard, and found that the four countries' trending lists run on two completely different mechanisms (FRANCE and CANADA churn daily — 59-75% of videos survive only one day; US and GB lists are highly sticky — 89-93% of videos survive multiple days). I then designed a per-market A/B test proposal for the "does Friday publishing improve multi-day retention?" hypothesis, which is directionally consistent across three of the four markets.

## Quick start (5 minutes)

```bash
git clone <this-repo>
cd trending-longevity-tracker

# 1. Download the dataset (not committed, ~80MB)
#    https://www.kaggle.com/datasets/thedevastator/youtube-trending-videos-dataset
#    Save as data/youtube.csv

# 2. Set up the environment
uv sync

# 3. Run the pipeline
uv run python src/build_tables.py

# 4. Verify
uv run duckdb -c "SELECT COUNT(*) FROM 'data/exports/video_life.csv'"
# expect 63,783
```

## What's in this repo

| Directory | Contents |
|---|---|
| `sql/` | DuckDB queries: data quality invariants, three-step cleaning, three-layer tables |
| `src/` | Python pipeline scripts (pandas reconciliation, table building) |
| `notebooks/` | Hypothesis testing, logistic regression, EDA visualizations |
| `docs/` | Data quality report, data dictionary, experiment proposal, one-page memo |
| `figures/` | Exported charts (PNG) |
| `data/` | Small exported CSVs; raw `youtube.csv` is gitignored (download separately) |

## The story, in three acts

**Act 1 — The documentation lied.** The dataset's `time_frame` column is documented as "how long the video trended for". Three pieces of evidence prove it's actually the video's publish hour (UTC), not a duration. See [`docs/data-quality-report.md`](docs/data-quality-report.md).

**Act 2 — Rebuilding metrics from raw event rows.** Two data invariants isolate 1,799 + 72 corrupted rows and dedupe 222 duplicate-scrape rows. A three-layer table (`raw` → `video_life` → `channel`) is built in SQL and independently re-verified in pandas. Core finding: the four countries are two entirely different mechanisms.

**Act 3 — From observation to experiment.** A per-country two-proportion z-test (with Newcombe confidence intervals) checks whether Friday publishing improves multi-day retention. Three of four markets show a consistent positive effect; an experiment proposal (randomization unit, primary/guardrail metrics, sample size) is designed for the two markets where it matters.

## Dashboard

[Tableau Public link — coming soon]

## Honest disclosures

- No real employer or client. This is a self-directed learning project on public data; the "creator operations team" audience is hypothetical, used to constrain how findings are written up.
- No causal claims. All hypothesis-test results are observational and labeled hypothesis-generating, not causal.
- Full data source: [Kaggle — thedevastator/youtube-trending-videos-dataset](https://www.kaggle.com/datasets/thedevastator/youtube-trending-videos-dataset)
