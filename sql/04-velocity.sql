-- Daily view velocity (grain stays event-level: video x country x day)
-- Window function LAG subtracts the previous day's cumulative views,
-- PARTITIONed by video and country so a video's history never leaks
-- across countries or across different videos. This does NOT change the
-- grain of `clean` — it just adds a column. Contrast with sql/03-channel.sql,
-- which genuinely aggregates rows into a coarser grain.
--
-- 100 rows have a negative increment (views regressed vs. the previous
-- snapshot, an upstream ordering artifact — see docs/data-quality-report.md
-- section 5). These are left as negative here; downstream charting clips
-- them to 0 rather than silently dropping the row.
--
-- Input:  table `clean` (from sql/01-clean.sql)
-- Output: query result only (not materialized as a table — this feeds
--         figures directly, e.g. the decay-curve chart)
--
-- Dialect notes: LAG(...) OVER (PARTITION BY ... ORDER BY ...) is standard
-- SQL window-function syntax, identical across DuckDB/BigQuery/Postgres.

SELECT video_id, publish_country, trend_dt, views,
       views - LAG(views) OVER (
           PARTITION BY video_id, publish_country ORDER BY trend_dt
       ) AS views_gained_today
FROM clean
ORDER BY video_id, publish_country, trend_dt;
