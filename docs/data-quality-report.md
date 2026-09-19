# Data Quality Report: YouTube Trending Videos Dataset

**Source**: Kaggle `thedevastator/youtube-trending-videos-dataset`, `youtube.csv` (161,470 rows, 18 columns, four countries US/CANADA/FRANCE/GB, 2017-11-14 to 2018-06-14)

**Verification**: every number below was run directly against the raw CSV with DuckDB, reproducible via `sql/00-invariants.sql`.

---

## 1. Field description correction: `time_frame`

The Kaggle page describes `time_frame` as "how long the video trended for". Three pieces of evidence disprove this:

| Evidence | Result |
|---|---|
| Value shape | Only 24 clock-hour values (`0:00 to 0:59` through `23:00 to 23:59`) — this is a publish hour (UTC), not a duration |
| Constant across rows for the same video | `NooW_RbfdWI` trends 38 days in GB, 6 in CANADA, 10 in US, 3 in FRANCE — within each country `time_frame` only takes 1 value, never changing across the scrape |
| Direct counter-example | Among US-trending videos with `time_frame='0:00 to 0:59'` (literally "under an hour"), `XdNOI-q70q4` actually trended for 22 consecutive days — the two claims can't both be true |

**Conclusion**: `time_frame` is the publish hour (UTC), not a duration. Across the whole table, only 12 videos (including `#NAME?`) have `time_frame` varying across rows; excluding `#NAME?` leaves 11 — exactly the IDs caught by "Invariant 2" below.

## 2. Violating rows: two data invariants

### Invariant 1: a video can only have one row per country per day

Violating this constraint: **180 distinct video_id, 729 (video_id, country, day) groups**. Split by whether the title matches:

| Violation shape | # of IDs | # of duplicate groups | Rows affected | Conclusion |
|---|---|---|---|---|
| `#NAME?` | 1 | 507 | **1,799** | A genuine ID collision — isolate entirely |
| The other 179 IDs | 179 | 222 | 444 (222 rows deleted after dedup) | Same video scraped twice on the same day — dedup, keep one row |

`#NAME?` is the error value Excel produces when it interprets a video_id starting with `-` or `=` as a formula.

### Invariant 2: a video_id's publish attributes (`publish_date`, `time_frame`) must be constant

Invariant 1 only catches violations colliding on the same day; it misses "different videos sharing one ID but never colliding on the same day/country", so a second invariant is needed:

**Catches 11 IDs, 72 rows** (must exclude `#NAME?` first, otherwise it would be caught here too due to its wildly inconsistent publish dates).

### Three shapes, three treatments

| Shape | Treatment | Rows |
|---|---|---|
| `#NAME?` same-day ID collision | Isolate entirely, unrecoverable | 1,799 |
| 11 IDs with inconsistent publish attributes | Isolate entirely, cannot be split back to source videos | 72 |
| 179 IDs, same-day duplicate scrapes | Dedup, keep the row with highest views/likes | 222 |

Total removed: **2,093 rows**, leaving **159,377 rows** after cleaning.

## 3. Capture completeness

Checked by country x day (**must run after cleaning and deduping** — duplicate rows would mask a partial-capture day):

| Country | Days scraped | Span (days) | Median rows/day | Min rows/day |
|---|---|---|---|---|
| CANADA | 205 | 213 | 197 | 169 |
| FRANCE | 205 | 213 | 197 | 164 |
| GB | 205 | 213 | 197 | **73** (2018-05-15) |
| US | 205 | 213 | 198 | 147 |

**All four countries are missing the exact same 8 days**: 2018-01-10, 01-11, 04-08 through 04-13. This synchronized gap across all four independent markets means the upstream scraper went down — it can't be four coincidentally-empty trending lists. GB's 2018-05-15 had only 73 rows — a partial capture, not a full outage.

**Conclusion**: a missing scrape can be detected but not repaired. Videos spanning a missing day will have their cumulative trending days undercounted — this is documented explicitly in the metric definitions (`gap_real` vs. `gap_scrape` columns, handled in the table-building step).

## 4. Attribute drift across rows (computed on cleaned data — avoids contamination from bad IDs)

| Attribute | Videos with drift |
|---|---|
| `channel_title` (channel renamed) | 55 |
| `title` (title changed) | 538 |
| `category_id` (category changed) | 49 |

**Conclusion**: these video-level attributes cannot be pulled with a non-deterministic function like `ANY_VALUE`; they need a deterministic rule (`ARG_MAX(col, trend_dt)`, taking the latest snapshot), otherwise results drift between runs.

## 5. Other data quality issues

| Issue | Rows | Note |
|---|---|---|
| `views` smaller than the previous day (cumulative value regressed) | 100 | An upstream snapshot-ordering or caching artifact; negative increments are clipped to 0 when plotting decay curves |
| `video_error_or_removed = True` | 126 | Video was deleted or errored; needs consideration when computing lifespan/retention metrics |
| `channel_title` groups differing only by case or whitespace | **53** (verified; original design doc said 52 — a 1-count difference from a minor edge-case judgment call, recorded honestly)| No `channel_id` in the dataset, so grouping by title mis-splits the same channel into multiple entries |
| `category_id` value range | Only 18 integers, no names — needs an external lookup table |

## 6. Why write the invariants first, then look at the data — not the other way around

Sorting naively by `MAX(COUNT(DISTINCT trending_date))` to find "the longest-lived videos" puts `video_id='#NAME?'` at the top (FRANCE 191 days, US 188 days) — a fake number, since `#NAME?` is hundreds of different videos crammed under one ID.

**Writing down the business constraints the data should satisfy (invariants) first, then hunting for rows that violate them**, separates "artifacts caused by bad data" from "genuine extreme values". The reverse order — sorting first, then explaining outliers — risks mistaking an artifact for a real finding, which is exactly what would have happened here if "191-day lifespan" had been reported as a headline number without first writing the invariants.

---

**Deliverables**: this report + `sql/00-invariants.sql` (21 independently reproducible queries) + `docs/data-dictionary.md`
