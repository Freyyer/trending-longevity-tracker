"""
Builds the three-layer metrics stack (clean -> video_life -> channel) and
exports each table to data/exports/*.csv for downstream use (pandas
reconciliation, dashboard, hypothesis testing).

The SQL for each stage used to live in separate sql/*.sql files; it is now
embedded directly below so this script has no external file dependency
beyond the raw CSV. See README.md for a narrative walkthrough of each query,
dialect notes (BigQuery / PostgreSQL), and the EXPLAIN query plan analysis
that used to live in sql/README.md.

Usage:
    uv run python src/build_tables.py
"""
from pathlib import Path

import duckdb

EXPORT_DIR = Path(__file__).parent.parent / "data" / "exports"

# Stage 1, three-step cleaning. Isolate #NAME? (unrecoverable ID collision),
# isolate the 11 ids with inconsistent publish attributes, then dedup
# same-day duplicate scrapes. Order matters: isolate first, dedup last,
# otherwise a bad id's rows get pre-selected by dedup before being isolated.
CLEAN_STATEMENTS = [
    """
    CREATE OR REPLACE TABLE bad_pub AS
    SELECT video_id
    FROM read_csv_auto('data/youtube.csv')
    WHERE video_id <> '#NAME?'
    GROUP BY 1
    HAVING COUNT(DISTINCT publish_date) > 1
        OR COUNT(DISTINCT time_frame) > 1
    """,
    """
    CREATE OR REPLACE TABLE clean AS
    SELECT * EXCLUDE (rn, trend_dt), trend_dt FROM (
        SELECT *,
               strptime(trending_date, '%y.%d.%m')::DATE AS trend_dt,
               ROW_NUMBER() OVER (
                   PARTITION BY video_id, publish_country, strptime(trending_date, '%y.%d.%m')::DATE
                   ORDER BY views DESC, likes DESC
               ) AS rn
        FROM read_csv_auto('data/youtube.csv')
        WHERE video_id <> '#NAME?'
          AND video_id NOT IN (SELECT video_id FROM bad_pub)
    ) WHERE rn = 1
    """,
    # Expected on the real dataset: 159,377
    "SELECT COUNT(*) AS n_clean_rows FROM clean",
]

# Stage 2, video-level metrics (grain: video x country). Attribute columns
# use ARG_MAX(col, trend_dt), not ANY_VALUE, to deterministically take the
# latest-snapshot value (see README.md, "Why ARG_MAX and not ANY_VALUE").
VIDEO_LIFE_STATEMENTS = [
    """
    CREATE OR REPLACE TABLE video_life AS
    SELECT video_id, publish_country,
           ARG_MAX(channel_title, trend_dt)         AS channel_title,
           ARG_MAX(category_id, trend_dt)           AS category_id,
           ARG_MAX(published_day_of_week, trend_dt) AS pub_dow,
           ARG_MAX(time_frame, trend_dt)            AS pub_hour_utc,
           MIN(trend_dt)                             AS first_trend_day,
           MAX(trend_dt)                             AS last_trend_day,
           COUNT(DISTINCT trend_dt)                  AS days_on_trending,
           (MAX(trend_dt) - MIN(trend_dt)) + 1        AS trending_span,
           CASE WHEN COUNT(DISTINCT trend_dt) >= 2 THEN 1 ELSE 0 END AS survived_day1,
           MAX(views)                                AS peak_views,
           MAX(likes)                                AS peak_likes,
           MAX(comment_count)                        AS peak_comments
    FROM clean
    GROUP BY 1, 2
    """,
    # The 8 days the scraper was down, hardcoded here since they were
    # already identified in docs/data-quality-report.md, section 3.
    """
    CREATE OR REPLACE TABLE scrape_missing_days AS
    SELECT UNNEST(['2018-01-10','2018-01-11','2018-04-08','2018-04-09',
                   '2018-04-10','2018-04-11','2018-04-12','2018-04-13'])::DATE AS d
    """,
    "ALTER TABLE video_life ADD COLUMN IF NOT EXISTS gap_real INT",
    "ALTER TABLE video_life ADD COLUMN IF NOT EXISTS gap_scrape INT",
    # These two UPDATEs must stay separate. Standard SQL evaluates a single
    # UPDATE's SET clause against pre-update column values, so merging them
    # would make gap_scrape read gap_real as NULL and always compute 0.
    """
    UPDATE video_life v SET
        gap_real = CASE WHEN trending_span - days_on_trending
                            - (SELECT COUNT(*) FROM scrape_missing_days m
                               WHERE m.d BETWEEN v.first_trend_day AND v.last_trend_day) > 0
                        THEN 1 ELSE 0 END
    """,
    """
    UPDATE video_life SET
        gap_scrape = CASE WHEN trending_span > days_on_trending AND gap_real = 0 THEN 1 ELSE 0 END
    """,
    # Expected on the real dataset: 63,783
    "SELECT COUNT(*) AS n_video_life_rows FROM video_life",
]

# Stage 3, channel-level metrics (grain: channel). Uses COUNT(DISTINCT
# video_id), not COUNT(*), since a video can appear in up to 4 rows in
# video_life, one per country it trended in.
CHANNEL_STATEMENTS = [
    """
    CREATE OR REPLACE TABLE channel AS
    SELECT channel_title,
           COUNT(DISTINCT video_id)        AS trending_videos,
           AVG(days_on_trending)           AS avg_video_life,
           AVG(survived_day1)              AS multi_day_rate,
           COUNT(DISTINCT publish_country) AS countries_reached
    FROM video_life
    GROUP BY 1
    """,
    # Expected on the real dataset: 12,253
    "SELECT COUNT(*) AS n_channel_rows FROM channel",
]


def run_statements(con: duckdb.DuckDBPyConnection, label: str, statements: list[str]) -> None:
    print(f"--- Running {label} ---")
    for stmt in statements:
        result = con.execute(stmt)
        if stmt.strip().upper().startswith("SELECT"):
            print(result.fetchdf())


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()

    run_statements(con, "clean", CLEAN_STATEMENTS)
    run_statements(con, "video_life", VIDEO_LIFE_STATEMENTS)
    run_statements(con, "channel", CHANNEL_STATEMENTS)

    for table, filename in [
        ("clean", "clean.csv"),
        ("video_life", "video_life.csv"),
        ("channel", "channel.csv"),
    ]:
        out_path = EXPORT_DIR / filename
        con.execute(f"COPY {table} TO '{out_path}' (HEADER, DELIMITER ',')")
        n_rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"Exported {table} -> {out_path} ({n_rows} rows)")


if __name__ == "__main__":
    main()
