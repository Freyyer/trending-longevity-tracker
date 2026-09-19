-- POC-01: 数据质量审计
-- 每一条查询独立可跑, 用来证伪 time_frame 字段说明、找出两条不变量的违规行、检查抓取完整性。
-- 数据源: ../data/youtube.csv (161,470 行, 18 列)
-- 陷阱: trending_date 是 VARCHAR 不是 DATE (格式 "18.29.01" = YY.DD.MM), 必须用
--       strptime(trending_date, '%y.%d.%m')::DATE 显式转换, DuckDB 的 read_csv_auto
--       猜不出这个非标准格式。

-- ============================================================
-- 第一幕: 证伪 time_frame 的字段说明
-- ============================================================

-- 证据 1: time_frame 只有 24 个整点取值, 不是任意的"时长"数值
-- 预期: 24
SELECT COUNT(DISTINCT time_frame) AS n_distinct_time_frame
FROM read_csv_auto('../data/youtube.csv');

-- 证据 1 补充: 具体看这 24 个值长什么样
SELECT time_frame, COUNT(*) AS n_rows
FROM read_csv_auto('../data/youtube.csv')
GROUP BY time_frame
ORDER BY time_frame;

-- 证据 2: 同一视频跨行 (跨国家, 跨天) 的 time_frame 是否恒定
-- 例子: NooW_RbfdWI 在 GB 上榜 38 天, CANADA 6 天, US 10 天, FRANCE 3 天
--       每个国家内部 time_frame 只有 1 个值 -> 说明它是"发布时刻", 不随抓取日变化
SELECT publish_country,
       COUNT(DISTINCT strptime(trending_date, '%y.%d.%m')::DATE) AS days,
       COUNT(DISTINCT time_frame) AS distinct_time_frame_values
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id = 'NooW_RbfdWI'
GROUP BY publish_country;

-- 证据 2 补充: 全表里 time_frame 会跨行变化的视频只有极少数 (12 个, 含 #NAME?)
-- 排除 #NAME? 后是 11 个 -> 这 11 个正是第二幕不变量 2 抓到的跨日冲突 ID
SELECT COUNT(*) AS n_videos_with_time_frame_variation
FROM (
    SELECT video_id
    FROM read_csv_auto('../data/youtube.csv')
    GROUP BY video_id
    HAVING COUNT(DISTINCT time_frame) > 1
);

-- 证据 3: 直接反例 —— US 榜上 time_frame = '0:00 to 0:59' (声称"不到 1 小时热度")
-- 的视频里, 有连续上榜 22 天的 (XdNOI-q70q4, Matt Stonie)
-- "热了不到一小时"和"连续 22 天出现在每日快照里"不能同时成立
SELECT video_id,
       COUNT(DISTINCT strptime(trending_date, '%y.%d.%m')::DATE) AS days_on_trending
FROM read_csv_auto('../data/youtube.csv')
WHERE publish_country = 'US' AND time_frame = '0:00 to 0:59'
GROUP BY video_id
ORDER BY days_on_trending DESC
LIMIT 5;

-- ============================================================
-- 第二幕: 用两条不变量找违规行, 按违规形态分类处理
-- ============================================================

-- 不变量 1: 一个视频在一个国家的一天只能有一行
-- 天真地用 COUNT(DISTINCT trending_date) 会被 #NAME? 这种坏 ID 污染 (虚假的 191 天寿命)
-- 违反这条约束的有 180 个 distinct video_id, 729 个 (video_id, country, day) 分组
SELECT video_id, publish_country,
       strptime(trending_date, '%y.%d.%m')::DATE AS trend_dt,
       COUNT(*) AS rows_that_day,
       COUNT(DISTINCT title) AS distinct_titles,
       COUNT(DISTINCT views) AS distinct_views
FROM read_csv_auto('../data/youtube.csv')
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;

-- 违规按形态拆分: #NAME? (1 个 ID, 507 个重复组, 1,799 行) 是真正的 ID 冲突
--                其余 (179 个 ID, 222 个重复组) 是同一视频同日被抓两次
SELECT
    CASE WHEN video_id = '#NAME?' THEN '#NAME?' ELSE 'other (同日重复抓取)' END AS violation_form,
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

-- #NAME? 涉及的总行数 (整体隔离, 无法还原属于哪个视频)
-- 预期: 1,799
SELECT COUNT(*) AS name_error_rows
FROM read_csv_auto('../data/youtube.csv')
WHERE video_id = '#NAME?';

-- 不变量 2: 一个 video_id 的发布属性 (publish_date, time_frame) 必须恒定 (视频只发布一次)
-- 这条不变量能抓到"不同视频共用一个 ID, 但没有在同一天同一国撞车"的情况, 不变量 1 抓不到
-- 抓到 11 个 ID, 72 行 (必须先排除 #NAME?, 否则它自己就会因发布日期五花八门而被误抓)
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
-- 三步清洗 (第二幕交付给 POC-02 的核心逻辑, 这里先验证行数)
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

-- 预期: 159,377 (161,470 - 1,799 - 72 - 222)
SELECT COUNT(*) AS n_clean_rows FROM clean;

-- ============================================================
-- 抓取完整性检查 (必须在清洗、去重之后跑, 否则重复行会遮住残缺日)
-- ============================================================

-- 每国抓取日数, 跨度天数, 单日行数中位数与最少行数
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

-- 四国完全缺失的日子 (完整日历 LEFT JOIN 实际抓到的日子)
SELECT c.publish_country, cal.d AS missing_day
FROM (SELECT DISTINCT publish_country FROM clean) c
CROSS JOIN (
    SELECT UNNEST(generate_series(DATE '2017-11-14', DATE '2018-06-14', INTERVAL 1 DAY))::DATE AS d
) cal
LEFT JOIN (SELECT DISTINCT publish_country, trend_dt FROM clean) have
    ON have.publish_country = c.publish_country AND have.trend_dt = cal.d
WHERE have.trend_dt IS NULL
ORDER BY 1, 2;

-- 单日行数最少的几天 (确认 GB 2018-05-15 的 73 行残缺日)
SELECT publish_country, trend_dt, COUNT(*) AS n_rows
FROM clean
GROUP BY 1, 2
ORDER BY n_rows ASC
LIMIT 5;

-- ============================================================
-- 数据质量清单: 属性跨行变化 (必须在 clean 上算, 不能在原始 raw 上算,
-- 否则 #NAME? 和跨日冲突 ID 的坏数据会污染这几个数字)
-- ============================================================

-- 55 个视频改过频道名, 538 个改过标题, 49 个改过品类
SELECT
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT channel_title) > 1)) AS channel_title_changed,
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT title) > 1)) AS title_changed,
    (SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT category_id) > 1)) AS category_id_changed;

-- 100 行 views 比前一日小 (累计值倒退, 上游快照顺序问题)
SELECT COUNT(*) AS views_regressed_rows
FROM (
    SELECT views,
           LAG(views) OVER (PARTITION BY video_id, publish_country ORDER BY trend_dt) AS prev_views
    FROM clean
)
WHERE views < prev_views;

-- 126 行 video_error_or_removed = True
SELECT COUNT(*) AS video_error_rows
FROM clean
WHERE video_error_or_removed = True;

-- channel_title 仅大小写或空格不同的重复组 (数据没有 channel_id, 这是已知缺陷)
-- 我验证得到 53 组, case 文档写 52 组, 差 1 属于边界判断的微小差异, 已如实记录
SELECT COUNT(*) AS channel_title_case_variant_groups
FROM (
    SELECT LOWER(TRIM(channel_title)) AS norm_title, COUNT(DISTINCT channel_title) AS variants
    FROM clean
    GROUP BY 1
    HAVING COUNT(DISTINCT channel_title) > 1
);

-- category_id 只有 18 个整数, 无名称 (需要外部映射表)
SELECT COUNT(DISTINCT category_id) AS n_distinct_categories FROM clean;
