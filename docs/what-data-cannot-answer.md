# What This Data Cannot Answer

Honest boundaries matter as much as findings. Each item below states why the question can't be answered with this dataset, and whether internal data could answer it.

---

## 1. Cold start: why doesn't a video make the trending list in the first place?

**Why this data can't answer it**: every row in this dataset is a video that *already* made the trending list. There are no non-trending videos to compare against, so there's no way to identify what systematically distinguishes videos that trend from videos that don't.

**Could internal data answer it?** Yes — with a full list of all published videos (trending or not), a trending-vs-not comparison would be possible. That requires a completely different data source than this public dataset provides.

## 2. Causality: does Friday publishing *cause* higher retention, or is it just correlation?

**Why this data can't answer it**: this is observational data, not experimental data. Friday-published videos showing higher retention could mean the treatment has a real causal effect, or it could be confounding — higher-quality, more-established channels may simply prefer publishing on Fridays already, and their retention is high because of channel quality, not the publish day. The two explanations are entangled in observational data and can't be separated by looking at more of the same kind of data.

**Could internal data answer it?** No — not even with much more historical data. This isn't a "missing field" problem; it's a structural limitation of observational data. The only way to separate the two explanations is a randomized experiment, which is exactly why `docs/experiment-proposal.md` exists.

## 3. Subscriber counts and watch time

**Why this data can't answer it**: this dataset has `views`, `likes`, and `comment_count` as trending-snapshot metrics, but no channel subscriber counts and no per-user watch-time data. It can't answer whether trending genuinely drives subscriber growth, or use watch time as a finer-grained engagement signal than view counts.

**Could internal data answer it?** Yes, partially — the YouTube Data API v3 could pull each channel's *current* subscriber count and total video count. This was considered and deliberately left out of scope: it's roughly a week of extra work, and more importantly, the API only returns a *current snapshot*, not a historical time series — it can't be precisely matched back to "the subscriber count at the moment a specific video was trending," which limits its value for this kind of retroactive analysis.

---

## The pattern across all three

Items 1 and 3 are **structural gaps** — the dataset is missing certain fields or record types, and a more complete data source could in principle fill them in. Item 2 is a **methodological boundary** — no amount of additional historical data closes it; only a different research design (a randomized experiment) can. Conflating the two would give a false impression that "we just need more data" when, for the causal question, that's never true.
