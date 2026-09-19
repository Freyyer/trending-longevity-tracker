-- Channel-level metrics table (grain: channel)
-- Aggregates video_life up one more level. Uses COUNT(DISTINCT video_id),
-- not COUNT(*), because a video can appear in up to 4 rows in video_life
-- (one per country it trended in) — COUNT(*) would double/triple/quadruple
-- count cross-country videos.
--
-- Known limitation (not fixed here, documented in docs/data-dictionary.md):
-- the dataset has no channel_id, so grouping is by channel_title alone.
-- 52-53 groups differing only by case/whitespace get mis-split into
-- separate "channels", and 55 videos that changed channel name mid-trending
-- get attributed entirely to their latest channel name.
--
-- Input:  table `video_life` (from sql/02-video-life.sql)
-- Output: table `channel` (12,253 rows expected)
--
-- Dialect notes: no dialect-specific syntax in this query; COUNT(DISTINCT ...)
-- and AVG(...) are standard SQL across DuckDB/BigQuery/Postgres.

CREATE OR REPLACE TABLE channel AS
SELECT channel_title,
       COUNT(DISTINCT video_id)        AS trending_videos,
       AVG(days_on_trending)           AS avg_video_life,
       AVG(survived_day1)              AS multi_day_rate,
       COUNT(DISTINCT publish_country) AS countries_reached
FROM video_life
GROUP BY 1;

-- Expected: 12,253
SELECT COUNT(*) AS n_channel_rows FROM channel;
