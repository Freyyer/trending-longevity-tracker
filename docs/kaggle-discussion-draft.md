# Kaggle Discussion Post — Draft

> ⚠️ This is a draft. You need to log into your own Kaggle account and post
> it at
> https://www.kaggle.com/datasets/thedevastator/youtube-trending-videos-dataset/discussion
> After posting, record the public URL at the bottom of this file.

---

**Title**: `time_frame` column is publish hour (UTC), not "video's trending duration"

**Body**:

The dataset description says `time_frame` represents "the video's time frame in the trending list" (i.e. duration). After analysis, I believe this is incorrect — `time_frame` actually represents the video's **publish hour in UTC**, not a duration. Three pieces of evidence:

1. **Value shape**: `time_frame` only takes 24 distinct values (`0:00 to 0:59` through `23:00 to 23:59`), each covering exactly one clock hour. A "duration in the trending list" would not naturally cluster into 24 fixed hourly bins.

2. **Invariant across rows**: For a single video that trends across multiple countries and many days (example: video_id `NooW_RbfdWI`, trending 38 days in GB, 10 in US, 6 in CANADA, 3 in FRANCE), `time_frame` never changes within a country. If it were a duration accumulated over the trending period, it should vary as the video stays on the list longer — it doesn't.

3. **Direct counter-example**: Among US-trending videos with `time_frame = '0:00 to 0:59'` (which under the "duration" interpretation would mean "trended for less than an hour"), video_id `XdNOI-q70q4` actually trended for 22 consecutive days. "Trended for under an hour" and "appeared in 22 consecutive daily snapshots" cannot both be true.

**Reproducible SQL** (DuckDB, reading the CSV directly):

```sql
-- Evidence 1: only 24 distinct values
SELECT COUNT(DISTINCT time_frame) FROM read_csv_auto('youtube.csv');
-- -> 24

-- Evidence 2: invariant per video per country
SELECT publish_country, COUNT(DISTINCT time_frame)
FROM read_csv_auto('youtube.csv')
WHERE video_id = 'NooW_RbfdWI'
GROUP BY publish_country;
-- -> every row returns 1

-- Evidence 3: counter-example
SELECT video_id, COUNT(DISTINCT strptime(trending_date, '%y.%d.%m')::DATE) AS days
FROM read_csv_auto('youtube.csv')
WHERE publish_country = 'US' AND time_frame = '0:00 to 0:59'
GROUP BY video_id ORDER BY days DESC LIMIT 5;
-- -> top result: 22 days
```

Given the two adjacent columns `publish_date` and `published_day_of_week`, I believe `time_frame` completes a "publish date, publish weekday, publish hour (UTC)" triple, all describing when the video was first published — not anything about the trending list duration.

Happy to be corrected if I'm missing context about how this field was originally generated. Full analysis (including a data quality report covering other issues in this dataset — duplicate IDs, a corrupted `#NAME?` video_id, and 8 days of missing scrape data) is here: https://github.com/Freyyer/trending-longevity-tracker

---

## Post-publication log

- Publish date:
- Public URL:
- Any replies:
