-- Three-step cleaning
-- Isolate #NAME? (unrecoverable ID collision), isolate the 11 IDs with
-- inconsistent publish attributes, then dedup same-day duplicate scrapes.
-- Order matters: isolate first (pull out bad IDs entirely), dedup last —
-- otherwise a bad ID's rows get "pre-selected" by dedup before being
-- isolated, muddying the audit trail.
--
-- Input:  ../data/youtube.csv (161,470 rows)
-- Output: table `clean` (159,377 rows expected)
--
-- Dialect notes:
--   - strptime(...)::DATE is DuckDB syntax. BigQuery: PARSE_DATE('%y.%d.%m', trending_date).
--     Postgres: TO_DATE(trending_date, 'YY.DD.MM').
--   - QUALIFY (used in 02/03) is DuckDB/Snowflake/BigQuery syntax for filtering
--     on a window function without a subquery. Postgres has no QUALIFY — wrap
--     the ROW_NUMBER() in a subquery and filter in an outer WHERE instead.

CREATE OR REPLACE TABLE bad_pub AS
SELECT video_id
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id <> '#NAME?'
GROUP BY 1
HAVING COUNT(DISTINCT publish_date) > 1
    OR COUNT(DISTINCT time_frame) > 1;

CREATE OR REPLACE TABLE clean AS
SELECT * EXCLUDE (rn, trend_dt), trend_dt FROM (
    SELECT *,
           strptime(trending_date, '%y.%d.%m')::DATE AS trend_dt,
           ROW_NUMBER() OVER (
               PARTITION BY video_id, publish_country, strptime(trending_date, '%y.%d.%m')::DATE
               ORDER BY views DESC, likes DESC
           ) AS rn
    FROM read_csv_auto('../data/youtube.csv')
    WHERE video_id <> '#NAME?'
      AND video_id NOT IN (SELECT video_id FROM bad_pub)
) WHERE rn = 1;

-- Expected: 159,377
SELECT COUNT(*) AS n_clean_rows FROM clean;
