# Data Dictionary: YouTube Trending Videos Dataset

**Source**: Kaggle `thedevastator/youtube-trending-videos-dataset`, `youtube.csv`
**Grain**: one row = one video, one country, one day it appeared on the trending list (event grain)
**Unique key (after cleaning)**: `(video_id, publish_country, trend_dt)`

18 fields, each with: true meaning, type, value range, verification SQL, and how it differs from the official Kaggle description.

---

## 1. `index`

- **True meaning**: row sequence number, assigned by DuckDB on CSV import, starting at 0
- **Type**: BIGINT
- **Value range**: 0 to 161,469 (total rows - 1)
- **Verification SQL**: `SELECT COUNT(DISTINCT index) FROM raw` → should equal 161,470
- **Difference from official description**: none, behaves as expected

## 2. `video_id`

- **True meaning**: YouTube video ID, intended as part of the primary key
- **Type**: VARCHAR
- **Value range**: 55,886 distinct values (including `#NAME?`)
- **Verification SQL**: `SELECT COUNT(*) FROM raw WHERE video_id = '#NAME?'` → 1,799
- **Difference from official description**: **a known corrupted value, `#NAME?`**, exists (the error Excel produces when a video_id starting with `-`/`=` is parsed as a formula). It represents hundreds of different videos crammed together and must be isolated entirely — it cannot be trusted

## 3. `trending_date`

- **True meaning**: the date this snapshot row corresponds to, formatted `YY.DD.MM` (year.day.month — not the more common year.month.day)
- **Type**: VARCHAR (⚠️ **not DATE** — DuckDB's `read_csv_auto` can't infer this non-standard format and treats it as a string)
- **Value range**: `17.01.12` (2017-12-01) to `18.31.05` (2018-05-31), 205 distinct values
- **Verification SQL**: `SELECT strptime(trending_date, '%y.%d.%m')::DATE FROM raw LIMIT 5` to confirm correct parsing
- **Difference from official description**: **format gotcha**. Must explicitly cast with `strptime(trending_date, '%y.%d.%m')::DATE`, otherwise any query involving date comparison, sorting, or window functions will be wrong or misleading (string sort order doesn't match date order)

## 4. `title`

- **True meaning**: a snapshot of the video title (not a constant attribute — a title change will appear in later rows as new text)
- **Type**: VARCHAR
- **Value range**: 56,905 distinct values, with heavy emoji and multilingual usage (some render as mojibake — a CSV encoding artifact)
- **Verification SQL**: `SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT title)>1)` → 538 videos changed title
- **Difference from official description**: the official docs don't flag this as a "drifts across rows" attribute — it should be pulled with `ARG_MAX(title, trend_dt)` (latest snapshot), not `ANY_VALUE`

## 5. `channel_title`

- **True meaning**: a snapshot of the publishing channel's name (also drifts across rows if the channel is renamed)
- **Type**: VARCHAR
- **Value range**: 12,361 distinct values in the raw table; ⚠️ **not a primary key** — the dataset has no `channel_id`, so grouping is by title alone, and 52-53 groups differing only by case or whitespace get mis-split into separate "channels"
- **Verification SQL**: `SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT channel_title)>1)` → 55 videos changed channel name
- **Difference from official description**: it's easy to assume `channel_title` can serve as a unique channel identifier — **it cannot**. 55 videos changed channel names mid-trending, and 52-53 groups get double-counted due to case/whitespace variants. This is a known limitation for any channel-level analysis, documented rather than fixed in this project

## 6. `category_id`

- **True meaning**: a numeric code for the YouTube video category
- **Type**: BIGINT
- **Value range**: 18 integers (between 1 and 44, non-contiguous), **with no accompanying name mapping**
- **Verification SQL**: `SELECT DISTINCT category_id FROM raw ORDER BY 1` → 18 rows
- **Difference from official description**: this dataset does **not** ship a category-name lookup. The real ID→name mapping comes from the upstream `datasnaek` family of datasets' `*_category_id.json` files (YouTube's standard category table) and would need to be downloaded separately — the numeric codes should not be guessed

## 7. `publish_date`

- **True meaning**: the date the video was originally published (an attribute column, constant across the scrape)
- **Type**: DATE (this column is correctly inferred by DuckDB)
- **Value range**: 2006-07-23 to 2018-06-14, 471 distinct values
- **Verification SQL**: `SELECT video_id FROM raw WHERE video_id<>'#NAME?' GROUP BY 1 HAVING COUNT(DISTINCT publish_date)>1` → 11 IDs violate "publish date should be constant"
- **Difference from official description**: no dispute over meaning, but this is the key column for Invariant 2 — 11 video_ids have an inconsistent `publish_date` across rows, a signal the publish attributes for those IDs are unreliable

## 8. `time_frame`

- **True meaning**: the video's **publish hour in UTC** (e.g. `17:00 to 17:59` means published at UTC hour 17) — a publish *moment*, not a duration
- **Type**: VARCHAR
- **Value range**: 24 clock-hour bins, from `0:00 to 0:59` to `23:00 to 23:59`
- **Verification SQL**: see `sql/00-invariants.sql`, Evidence 1-3
- **Difference from official description**: **the Kaggle page describes it as "how long the video trended for" — this is wrong**. Three pieces of evidence (only 24 clock-hour values, constant across rows for a given video, and a US video with `time_frame='0:00 to 0:59'` that trended for 22 consecutive days) prove it's a publish hour, not a duration. All analysis in this project uses the clearer alias `pub_hour_utc`

## 9. `published_day_of_week`

- **True meaning**: the day of the week corresponding to `publish_date` (a redundant column — could be derived from `publish_date`, but reading it directly saves the derivation)
- **Type**: VARCHAR
- **Value range**: 7 values (Monday through Sunday)
- **Verification SQL**: `SELECT published_day_of_week, DAYNAME(publish_date) FROM raw LIMIT 5` cross-checks the two agree
- **Difference from official description**: none — this is the key grouping field for the Friday-vs-non-Friday hypothesis test

## 10. `publish_country`

- **True meaning**: which country's trending list this snapshot row came from
- **Type**: VARCHAR
- **Value range**: 4 values (US, CANADA, FRANCE, GB)
- **Verification SQL**: `SELECT DISTINCT publish_country FROM raw` → 4 rows
- **Difference from official description**: none — this is the core stratification dimension for this project: the four countries run on two entirely different trending-list mechanisms (one-day-only share 59-75% vs. 7-11%)

## 11. `tags`

- **True meaning**: video tags, concatenated with `"` as a separator (not a standard JSON array)
- **Type**: VARCHAR
- **Value range**: 50,239 distinct combinations, with multilingual and special characters
- **Verification SQL**: `SELECT tags FROM raw LIMIT 3` to inspect the actual format
- **Difference from official description**: not used in formal analysis for this project; listed here as a known field for completeness

## 12. `views`

- **True meaning**: cumulative view count at the moment of this snapshot
- **Type**: BIGINT
- **Value range**: 223 to 424,538,912
- **Verification SQL**: `SELECT COUNT(*) FROM (SELECT views, LAG(views) OVER (...) AS prev FROM clean) WHERE views < prev` → 100 regressed rows
- **Difference from official description**: no dispute over meaning, but there are **100 regressed rows** (smaller than the previous day's snapshot) — an upstream snapshot-ordering or caching artifact, not a video actually "losing" views

## 13. `likes`

- **True meaning**: cumulative like count at the moment of this snapshot
- **Type**: BIGINT
- **Value range**: 0 to 5,613,827
- **Verification SQL**: none standalone; used alongside `views` as a tiebreaker for dedup sort order (`ORDER BY views DESC, likes DESC`)
- **Difference from official description**: none

## 14. `dislikes`

- **True meaning**: cumulative dislike count at the moment of this snapshot
- **Type**: BIGINT
- **Value range**: 0 to 1,944,971
- **Verification SQL**: none
- **Difference from official description**: none; not used as a core metric in this project

## 15. `comment_count`

- **True meaning**: cumulative comment count at the moment of this snapshot
- **Type**: BIGINT
- **Value range**: 0 to 1,626,501
- **Verification SQL**: none
- **Difference from official description**: none

## 16. `comments_disabled`

- **True meaning**: whether comments were disabled for this video
- **Type**: BOOLEAN
- **Value range**: True / False
- **Verification SQL**: `SELECT comments_disabled, COUNT(*) FROM raw GROUP BY 1`
- **Difference from official description**: none; a candidate actionable lever for operations (whether to disable comments)

## 17. `ratings_disabled`

- **True meaning**: whether likes/dislikes were disabled for this video
- **Type**: BOOLEAN
- **Value range**: True / False
- **Verification SQL**: `SELECT ratings_disabled, COUNT(*) FROM raw GROUP BY 1`
- **Difference from official description**: none

## 18. `video_error_or_removed`

- **True meaning**: whether the video errored out or had been removed at scrape time
- **Type**: BOOLEAN
- **Value range**: True / False, 126 rows True (on cleaned data)
- **Verification SQL**: `SELECT COUNT(*) FROM clean WHERE video_error_or_removed = True` → 126
- **Difference from official description**: no dispute over meaning, but **these 126 rows need consideration when computing retention/lifespan metrics**, since their `views` and other fields may already be stale by the time the video was deleted

---

## Two known structural limitations (not fixed within this project, but documented explicitly)

1. **No `category_id` name mapping**: not shipped with this dataset; would need to be downloaded separately from the upstream `datasnaek` family of datasets' `*_category_id.json`
2. **`channel_title` is not a primary key**: the dataset has no `channel_id`; 52-53 groups of titles differing only by case/whitespace get mis-split into separate channels, and 55 videos changed channel names mid-trending (attributed to the latest snapshot's name, meaning early trending records "transfer" to the new name)

---

**Deliverables**: this dictionary + `docs/data-quality-report.md` + `sql/00-invariants.sql`
