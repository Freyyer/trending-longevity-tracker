# trending-longevity-tracker

![Reconciliation Check](https://github.com/Freyyer/trending-longevity-tracker/actions/workflows/reconcile.yml/badge.svg)

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

# 4. Verify (build_tables.py already prints row counts, but to check independently)
uv run python -c "import pandas as pd; print(len(pd.read_csv('data/exports/video_life.csv')))"
# expect 63,783
```

## What's in this repo

| Directory | Contents |
|---|---|
| `src/` | Python pipeline scripts: DuckDB queries for the three-layer tables (embedded directly in `build_tables.py`, see "SQL dialect notes and query plan" below), channel classification |
| `scripts/` | CI helper (`ci_check.py`) — not part of the analysis pipeline itself |
| `notebooks/` | Data quality audit, metric tables, pandas reconciliation, hypothesis testing, logistic regression, EDA visualizations, all with real executed outputs |
| `docs/` | Data quality report, data dictionary, experiment proposal, memo, creator ecosystem brief |
| `figures/` | Exported charts (PNG) |
| `data/` | Small exported CSVs; raw `youtube.csv` is gitignored (download separately) |
| `.github/workflows/` | CI: dependency + source-file checks always; full pipeline reconciliation if Kaggle secrets are configured |

**Why `youtube.csv` isn't committed but `uv.lock` is**: the raw CSV is an 83MB third-party dataset — committing it would bloat the repo with a file anyone can re-download from Kaggle in seconds, and it's not something *this project* produces or owns. `uv.lock` is the opposite: it's small, and it's the one artifact that guarantees a stranger cloning this repo gets the *exact* same dependency versions I used, not "whatever pandas happens to resolve to today." One is a large, reproducible external input; the other is a small, non-reproducible-without-it build artifact.

**Issue-based audit trail**: every finding in `docs/data-quality-report.md` has a corresponding [closed GitHub Issue](https://github.com/Freyyer/trending-longevity-tracker/issues?q=is%3Aissue+is%3Aclosed) with a finding/impact/resolution writeup and a commit reference, rather than just living in a markdown file.

## The story, in three acts

**Act 1 — The documentation lied.** The dataset's `time_frame` column is documented as "how long the video trended for". Three pieces of evidence prove it's actually the video's publish hour (UTC), not a duration. Full write-up in [`docs/data-quality-report.md`](docs/data-quality-report.md); every query re-run live with real outputs in [`notebooks/01-data-quality-audit.ipynb`](notebooks/01-data-quality-audit.ipynb).

**Act 2 — Rebuilding metrics from raw event rows.** Two data invariants isolate 1,799 + 72 corrupted rows and dedupe 222 duplicate-scrape rows. A three-layer table (`raw` → `video_life` → `channel`) is built in SQL ([`src/build_tables.py`](src/build_tables.py), [`notebooks/02-metric-tables.ipynb`](notebooks/02-metric-tables.ipynb)) and independently re-verified in pandas ([`notebooks/03-pandas-reconciliation.ipynb`](notebooks/03-pandas-reconciliation.ipynb)). Core finding: the four countries are two entirely different mechanisms.

**Act 3 — From observation to experiment.** A per-country two-proportion z-test (with Newcombe confidence intervals) checks whether Friday publishing improves multi-day retention, cross-checked with a bootstrap and a logistic regression controlling for country ([`notebooks/04-hypothesis-test.ipynb`](notebooks/04-hypothesis-test.ipynb)). Three of four markets show a consistent positive effect; a full experiment proposal (randomization unit, primary/guardrail metrics, sample size) is in [`docs/experiment-proposal.md`](docs/experiment-proposal.md).

## For a non-technical reader

- [`docs/memo.md`](docs/memo.md) — the whole project in three short paragraphs: finding, recommendation, why an experiment is needed
- [`docs/memo-variants.md`](docs/memo-variants.md) — the same finding rewritten for a PM, for operations, and for engineering — each answering a different question, not just reworded
- [`docs/what-data-cannot-answer.md`](docs/what-data-cannot-answer.md) — three honest limitations: cold start, causality, and subscriber/watch-time data

## SQL dialect notes and query plan

All SQL in this project is written in DuckDB (embedded in `src/build_tables.py` and in the `notebooks/` cells that run it). DuckDB was chosen over BigQuery because the 83MB CSV runs in seconds locally, at zero cost, and anyone cloning this repo can reproduce it without a GCP account. The dialect notes below exist so the same logic can be ported if needed.

| DuckDB syntax | BigQuery equivalent | PostgreSQL equivalent |
|---|---|---|
| `strptime(trending_date, '%y.%d.%m')::DATE` | `PARSE_DATE('%y.%d.%m', trending_date)` | `TO_DATE(trending_date, 'YY.DD.MM')` |
| `ARG_MAX(col, order_col)` | `ARG_MAX(col, order_col)` (supported) | Not built in, emulate with `(ARRAY_AGG(col ORDER BY order_col DESC))[1]` |
| `QUALIFY ROW_NUMBER() OVER (...) = 1` | `QUALIFY ROW_NUMBER() OVER (...) = 1` (supported) | Not supported, wrap in a subquery and filter with an outer `WHERE rn = 1` |
| `(MAX(trend_dt) - MIN(trend_dt)) + 1` | `DATE_DIFF(MAX(trend_dt), MIN(trend_dt), DAY) + 1` | `(MAX(trend_dt) - MIN(trend_dt)) + 1` (same integer-day subtraction) |
| `read_csv_auto('path')` | Load into a table first (`bq load`), or use an external table | `COPY ... FROM 'path' CSV HEADER` into a staging table first |

Running `EXPLAIN` on the dedup query in `build_tables.py` (the `ROW_NUMBER()` step in the `clean` table) shows this pipeline (top consumer first, read bottom to top):

```
READ_CSV_AUTO  (~923,786 rows estimated)
  -> WINDOW (ROW_NUMBER() OVER PARTITION BY video_id, publish_country,
              trend_dt ORDER BY views DESC, likes DESC)
  -> FILTER (rn = 1)
  -> PROJECTION
```

Two things worth noting from the actual plan, not guessed: the `WINDOW` operator is the expensive step, not the CSV scan itself, since it has to fully sort every partition across the entire unfiltered table before the `WHERE rn = 1` filter can discard anything (the filter can't push down past a window function). Also, DuckDB's row-count estimate for the CSV scan (~923,786) is roughly 5.7x the real row count (161,470), because its sampling-based estimator gets thrown off by this file's irregular `trending_date` format and doesn't correct until it actually reads the file. A good reminder that `EXPLAIN` estimates, as opposed to `EXPLAIN ANALYZE` which runs the query and reports real counts, can be badly wrong on messy CSVs.

## Dashboard

[Tableau Public link — coming soon]

## Honest disclosures

- No real employer or client. This is a self-directed learning project on public data; the "creator operations team" audience is hypothetical, used to constrain how findings are written up.
- No causal claims. All hypothesis-test results are observational and labeled hypothesis-generating, not causal.
- Full data source: [Kaggle — thedevastator/youtube-trending-videos-dataset](https://www.kaggle.com/datasets/thedevastator/youtube-trending-videos-dataset)
