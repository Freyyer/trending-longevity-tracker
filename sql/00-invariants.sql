-- Data quality audit
-- Every query below is independently runnable. Together they disprove the
-- official field description of `time_frame`, isolate the rows that
-- violate two data invariants, and check scrape completeness.
-- Source: ../data/youtube.csv (161,470 rows, 18 columns)
-- Gotcha: trending_date is VARCHAR, not DATE (format "18.29.01" = YY.DD.MM).
--         Must cast explicitly with strptime(trending_date, '%y.%d.%m')::DATE
--         — DuckDB's read_csv_auto cannot infer this non-standard format.

-- ============================================================
-- Part 1: Disproving the `time_frame` field description
-- ============================================================

-- Evidence 1: time_frame only takes 24 clock-hour values, not an arbitrary
-- "duration" figure
-- Expected: 24
SELECT COUNT(DISTINCT time_frame) AS n_distinct_time_frame
FROM read_csv_auto('../data/youtube.csv');

-- Evidence 1 (detail): what do these 24 values actually look like
SELECT time_frame, COUNT(*) AS n_rows
FROM read_csv_auto('../data/youtube.csv')
GROUP BY time_frame
ORDER BY time_frame;

-- Evidence 2: is time_frame constant for the same video across rows
-- (different countries, different days)?
-- Example: NooW_RbfdWI trends 38 days in GB, 6 in CANADA, 10 in US, 3 in
-- FRANCE. Within each country, time_frame only takes 1 value -> this means
-- it's a "publish moment", not something that changes with each scrape.
SELECT publish_country,
       COUNT(DISTINCT strptime(trending_date, '%y.%d.%m')::DATE) AS days,
       COUNT(DISTINCT time_frame) AS distinct_time_frame_values
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id = 'NooW_RbfdWI'
GROUP BY publish_country;

-- Evidence 2 (detail): across the whole table, only a handful of videos
-- have time_frame varying across rows (12, including the corrupted
-- #NAME? id). Excluding #NAME? leaves 11 -> these are exactly the 11
-- IDs caught by invariant 2 below (inconsistent publish attributes).
SELECT COUNT(*) AS n_videos_with_time_frame_variation
FROM (
    SELECT video_id
    FROM read_csv_auto('../data/youtube.csv')
    GROUP BY video_id
    HAVING COUNT(DISTINCT time_frame) > 1
);

-- Evidence 3: a direct counter-example. Among US-trending videos with
-- time_frame = '0:00 to 0:59' (which under the "duration" interpretation
-- would mean "trended for under an hour"), video XdNOI-q70q4 actually
-- trended for 22 consecutive days. "Trended for under an hour" and
-- "appeared in 22 consecutive daily snapshots" cannot both be true.
SELECT video_id,
       COUNT(DISTINCT strptime(trending_date, '%y.%d.%m')::DATE) AS days_on_trending
FROM read_csv_auto('../data/youtube.csv')
WHERE publish_country = 'US' AND time_frame = '0:00 to 0:59'
GROUP BY video_id
ORDER BY days_on_trending DESC
LIMIT 5;

-- ============================================================
-- Part 2: Two invariants to find violating rows, then handle each
-- violation shape differently
-- ============================================================

-- Invariant 1: a video can only have one row per country per day.
-- Naively using COUNT(DISTINCT trending_date) gets polluted by the
-- corrupted #NAME? id (a fake 191-day "lifespan").
-- Violating this constraint: 180 distinct video_id, 729
-- (video_id, country, day) groups.
SELECT video_id, publish_country,
       strptime(trending_date, '%y.%d.%m')::DATE AS trend_dt,
       COUNT(*) AS rows_that_day,
       COUNT(DISTINCT title) AS distinct_titles,
       COUNT(DISTINCT views) AS distinct_views
FROM read_csv_auto('../data/youtube.csv')
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;

-- Split the violations by shape: #NAME? (1 id, 507 duplicate groups,
-- 1,799 rows) is a genuine ID collision; the other 179 ids (222 groups)
-- are the same video scraped twice on the same day.
SELECT
    CASE WHEN video_id = '#NAME?' THEN 'ID collision (#NAME?)' ELSE 'duplicate same-day scrape' END AS violation_form,
    COUNT(DISTINCT video_id) AS n_ids,
    COUNT(*) AS n_groups
FROM (
    SELECT video_id, publish_country,
           strptime(trending_date, '%y.%d.%m')::DATE AS trend_dt
    FROM read_csv_auto('../data/youtube.csv')
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
)
GROUP BY 1;

-- Total rows involved in the #NAME? collision (isolated entirely, cannot
-- be attributed back to any single video)
-- Expected: 1,799
SELECT COUNT(*) AS name_error_rows
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id = '#NAME?';

-- Invariant 2: a video_id's publish attributes (publish_date, time_frame)
-- must be constant, since a video is only published once. This catches
-- "different videos sharing one id, but never colliding on the same
-- day/country" — invariant 1 misses this case.
-- Catches 11 ids, 72 rows (must exclude #NAME? first, otherwise it gets
-- caught here too due to its wildly inconsistent publish dates).
CREATE OR REPLACE TABLE bad_pub AS
SELECT video_id
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id <> '#NAME?'
GROUP BY 1
HAVING COUNT(DISTINCT publish_date) > 1
    OR COUNT(DISTINCT time_frame) > 1;

SELECT COUNT(*) AS n_bad_pub_ids FROM bad_pub;

SELECT COUNT(*) AS n_bad_pub_rows
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id IN (SELECT video_id FROM bad_pub);

-- ============================================================
-- Three-step cleaning (verify row counts here; full pipeline lives
-- in the table-building scripts)
-- ============================================================

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

-- Expected: 159,377 (161,470 - 1,799 - 72 - 222)
SELECT COUNT(*) AS n_clean_rows FROM clean;

-- ============================================================
-- Scrape completeness (must run AFTER cleaning/deduping, otherwise
-- duplicate rows mask a partial-capture day)
-- ============================================================

-- Days scraped, span, median and minimum rows per day, by country
SELECT publish_country,
       COUNT(*) AS n_days,
       MAX(trend_dt) - MIN(trend_dt) + 1 AS trending_span_days,
       MEDIAN(n_rows) AS median_rows_per_day,
       MIN(n_rows) AS min_rows_per_day
FROM (
    SELECT publish_country, trend_dt, COUNT(*) AS n_rows
    FROM clean
    GROUP BY 1, 2
)
GROUP BY 1;

-- Days completely missing across all four countries (full calendar
-- LEFT JOIN against days actually scraped)
SELECT c.publish_country, cal.d AS missing_day
FROM (SELECT DISTINCT publish_country FROM clean) c
CROSS JOIN (
    SELECT UNNEST(generate_series(DATE '2017-11-14', DATE '2018-06-14', INTERVAL 1 DAY))::DATE AS d
) cal
LEFT JOIN (SELECT DISTINCT publish_country, trend_dt FROM clean) have
    ON have.publish_country = c.publish_country AND have.trend_dt = cal.d
WHERE have.trend_dt IS NULL
ORDER BY 1, 2;

-- Days with the fewest rows (confirms the GB 2018-05-15 partial-capture
-- day, 73 rows)
SELECT publish_country, trend_dt, COUNT(*) AS n_rows
FROM clean
GROUP BY 1, 2
ORDER BY n_rows ASC
LIMIT 5;

-- ============================================================
-- Data quality checklist: attribute drift across rows (must run on
-- `clean`, not raw — otherwise #NAME? and the inconsistent-publish
-- IDs pollute these counts)
-- ============================================================

-- 55 videos changed channel name, 538 changed title, 49 changed category
SELECT
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT channel_title) > 1)) AS channel_title_changed,
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT title) > 1)) AS title_changed,
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT category_id) > 1)) AS category_id_changed;

-- 100 rows where views is smaller than the previous day (cumulative
-- value regressed — an upstream snapshot ordering issue)
SELECT COUNT(*) AS views_regressed_rows
FROM (
    SELECT views,
           LAG(views) OVER (PARTITION BY video_id, publish_country ORDER BY trend_dt) AS prev_views
    FROM clean
)
WHERE views < prev_views;

-- 126 rows with video_error_or_removed = True
SELECT COUNT(*) AS video_error_rows
FROM clean
WHERE video_error_or_removed = True;

-- channel_title groups that differ only by case or whitespace (the
-- dataset has no channel_id, so this is a known limitation).
-- I verified 53 groups; the original design doc says 52 — the
-- difference of 1 is a minor edge-case judgment call, recorded here
-- honestly rather than silently reconciled.
SELECT COUNT(*) AS channel_title_case_variant_groups
FROM (
    SELECT LOWER(TRIM(channel_title)) AS norm_title, COUNT(DISTINCT channel_title) AS variants
    FROM clean
    GROUP BY 1
    HAVING COUNT(DISTINCT channel_title) > 1
);

-- category_id only has 18 integers, no name mapping (needs an external
-- lookup table)
SELECT COUNT(DISTINCT category_id) AS n_distinct_categories FROM clean;
