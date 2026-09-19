# SQL Scripts

Run in order (or via `uv run python src/build_tables.py`, which runs all
three and exports CSVs):

| Script | Purpose | Input | Output | Expected rows |
|---|---|---|---|---|
| `00-invariants.sql` | Data quality audit: disprove `time_frame` field description, find rows violating two invariants, check scrape completeness | `../data/youtube.csv` | (no persisted table; `clean` created here is scratch, superseded by `01-clean.sql`) | — |
| `01-clean.sql` | Three-step cleaning: isolate `#NAME?`, isolate 11 inconsistent-publish IDs, dedup same-day duplicates | `../data/youtube.csv` | table `clean` | 159,377 |
| `02-video-life.sql` | Aggregate to video x country grain; deterministic attribute columns via `ARG_MAX`; compute `gap_real`/`gap_scrape` | table `clean` | table `video_life` | 63,783 |
| `03-channel.sql` | Aggregate to channel grain | table `video_life` | table `channel` | 12,253 |
| `04-velocity.sql` | Daily view increment via `LAG` window function (grain stays event-level, no aggregation) | table `clean` | query result (feeds charts, not materialized) | — (161,470-scale query, no row count check) |

## Why `ARG_MAX(col, trend_dt)` and not `ANY_VALUE(col)`

55 videos changed `channel_title` mid-trending, 538 changed `title`, 49
changed `category_id`. `ANY_VALUE` picks an arbitrary row for these
non-deterministic cases, so the channel count drifts between runs. I
verified this directly — three consecutive runs of the same pipeline:

I isolated exactly where the drift comes from by testing two scenarios
separately:

| Scenario | `ANY_VALUE` distinct channel count across 3 runs | `ARG_MAX(col, trend_dt)` |
|---|---|---|
| Querying the same, already-materialized `clean` table 3 times | 12,248 / 12,248 / 12,248 (stable) | 12,253 / 12,253 / 12,253 |
| Rebuilding `clean` from the CSV from scratch each time, then querying | 12,256 / 12,255 / 12,251 (drifts) | 12,253 / 12,253 / 12,253 |

**The drift doesn't come from `GROUP BY` aggregation being randomized on
each call** — querying a fixed, already-built table repeatedly gives a
stable (if arbitrary) answer, because the physical row order doesn't
change between queries. The drift comes from **CSV parallel-read scheduling**:
each time `clean` is rebuilt from `read_csv_auto`, DuckDB's worker threads
can finish reading different chunks in a slightly different order, so
which row `ANY_VALUE` happens to land on changes between builds — this
matters in practice because a CI pipeline rebuilding these tables from
scratch on every run is exactly the "rebuild from CSV" scenario, not the
"query a cached table" scenario.

This is also why "it didn't drift when I tested it" isn't a safe argument
for using `ANY_VALUE` — its result is formally *unspecified* by both the
SQL standard and DuckDB's documentation. Whether it happens to stay
constant on a given machine, DuckDB version, or thread count is
implementation detail, not a guarantee.

`ARG_MAX(channel_title, trend_dt)` deterministically takes the value from
the row with the latest `trend_dt` (the most recent snapshot) regardless
of physical row order or thread scheduling, so it's stable in every
scenario above. This is the same logic as taking `MAX(views)` for peak
views, or `ROW_NUMBER() ... ORDER BY views DESC` for dedup — always
resolve ties by a well-defined ordering column, never leave it to chance.

## Why `gap_real` and `gap_scrape` need two separate `UPDATE` statements

Standard SQL evaluates a single `UPDATE`'s `SET` clause against
pre-update column values. If `gap_real` and `gap_scrape` were computed in
one `UPDATE`, the `gap_scrape` expression would read `gap_real` as its
pre-update value (`NULL`, since the column was just added), and every row
would incorrectly get `gap_scrape = 0`. Splitting into two statements
lets the second `UPDATE` read `gap_real`'s already-committed value.

## Dialect differences (BigQuery / PostgreSQL)

| DuckDB syntax | BigQuery equivalent | PostgreSQL equivalent |
|---|---|---|
| `strptime(trending_date, '%y.%d.%m')::DATE` | `PARSE_DATE('%y.%d.%m', trending_date)` | `TO_DATE(trending_date, 'YY.DD.MM')` |
| `ARG_MAX(col, order_col)` | `ARG_MAX(col, order_col)` (supported) | Not built in — emulate with `(ARRAY_AGG(col ORDER BY order_col DESC))[1]` |
| `QUALIFY ROW_NUMBER() OVER (...) = 1` | `QUALIFY ROW_NUMBER() OVER (...) = 1` (supported) | Not supported — wrap in a subquery and filter with an outer `WHERE rn = 1` |
| `(MAX(trend_dt) - MIN(trend_dt)) + 1` | `DATE_DIFF(MAX(trend_dt), MIN(trend_dt), DAY) + 1` | `(MAX(trend_dt) - MIN(trend_dt)) + 1` (same integer-day subtraction) |
| `read_csv_auto('path')` | Load into a table first (`bq load`), or use an external table | `COPY ... FROM 'path' CSV HEADER` into a staging table first |

## Reading the query plan

Running `EXPLAIN` on the `01-clean.sql` dedup query shows this pipeline
(top consumer first, i.e. read bottom-up):

```
READ_CSV_AUTO  (~923,786 rows estimated)
  -> WINDOW (ROW_NUMBER() OVER PARTITION BY video_id, publish_country,
              trend_dt ORDER BY views DESC, likes DESC)
  -> FILTER (rn = 1)
  -> PROJECTION
```

Two things worth noting from the actual plan (not guessed):

1. **The `WINDOW` operator is the expensive step**, not the CSV scan itself
   — it has to fully sort every partition by `(video_id, publish_country,
   trend_dt, views, likes)` across the *entire unfiltered table* before the
   `WHERE rn = 1` filter can discard anything. The filter can't push down
   past a window function.
2. **DuckDB's row-count estimate for the CSV scan (~923,786) is roughly
   5.7x the real row count (161,470)** — its sampling-based estimator gets
   thrown off by this file's irregular `trending_date` format and doesn't
   correct until it actually reads the file. This is a good reminder that
   `EXPLAIN` estimates (as opposed to `EXPLAIN ANALYZE`, which runs the
   query and reports real counts) can be badly wrong on messy CSVs.
