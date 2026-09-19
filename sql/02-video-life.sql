-- Video-level metrics table (grain: video x country)
-- Aggregates the event-grain `clean` table up one level. Attribute columns
-- (channel_title, category_id, pub_dow, pub_hour_utc) use ARG_MAX(col, trend_dt)
-- to take the latest-snapshot value deterministically — NOT ANY_VALUE, which
-- would pick an arbitrary row and drift between runs whenever a video's
-- channel_title, title, or category_id changed mid-trending (55/538/49
-- videos respectively, see docs/data-quality-report.md).
--
-- Input:  table `clean` (from sql/01-clean.sql)
-- Output: table `video_life` (63,783 rows expected)
--
-- Dialect notes:
--   - ARG_MAX(col, order_col) is DuckDB/BigQuery/Snowflake syntax.
--     Postgres has no ARG_MAX; emulate with:
--     (ARRAY_AGG(col ORDER BY trend_dt DESC))[1]
--   - (MAX(trend_dt) - MIN(trend_dt)) + 1 relies on DuckDB's DATE - DATE
--     returning an integer number of days. BigQuery: DATE_DIFF(MAX(trend_dt), MIN(trend_dt), DAY) + 1.
--     Postgres: (MAX(trend_dt) - MIN(trend_dt)) + 1 also works (same integer-day subtraction).

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
GROUP BY 1, 2;

-- Real gap vs. scrape-attributable gap: a video's trending_span can exceed
-- days_on_trending for two reasons — it genuinely dropped off and came
-- back (gap_real), or it was on the list the whole time but the scraper
-- had an outage during that stretch (gap_scrape). The 8 days the scraper
-- was down are hardcoded here since they were already identified in the
-- data quality audit (docs/data-quality-report.md, section 3).
CREATE OR REPLACE TABLE scrape_missing_days AS
SELECT UNNEST(['2018-01-10','2018-01-11','2018-04-08','2018-04-09',
               '2018-04-10','2018-04-11','2018-04-12','2018-04-13'])::DATE AS d;

ALTER TABLE video_life ADD COLUMN IF NOT EXISTS gap_real INT;
ALTER TABLE video_life ADD COLUMN IF NOT EXISTS gap_scrape INT;

-- These two UPDATEs must stay separate. Standard SQL evaluates the SET
-- clause against pre-update column values within a single statement — if
-- merged into one UPDATE, gap_scrape's CASE would read gap_real as NULL
-- (its pre-update value), and every row would incorrectly get gap_scrape = 0.
UPDATE video_life v SET
    gap_real = CASE WHEN trending_span - days_on_trending
                        - (SELECT COUNT(*) FROM scrape_missing_days m
                           WHERE m.d BETWEEN v.first_trend_day AND v.last_trend_day) > 0
                    THEN 1 ELSE 0 END;

UPDATE video_life SET
    gap_scrape = CASE WHEN trending_span > days_on_trending AND gap_real = 0 THEN 1 ELSE 0 END;

-- Expected: 63,783
SELECT COUNT(*) AS n_video_life_rows FROM video_life;
