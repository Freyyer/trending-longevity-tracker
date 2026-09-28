# Creator Ecosystem Brief: Mapping YouTube Trending to TikTok PGC Concepts

## Why this matters for a PGC (Professional Generated Content) team

A PGC team works with creators and institutions who already have distribution capability — they care about *sustained* distribution, not cold start. This dataset's trending list is a public proxy for "getting into a scaled distribution pool," and channel-level behavior (how often a channel trends, how long each trend lasts) is a proxy for "a creator's capacity to keep producing distributable content."

| What's in the YouTube data | Corresponding TikTok PGC concept |
|---|---|
| A video entering the trending list | Content entering a large-traffic distribution pool |
| Cumulative trending days | Duration of sustained distribution |
| A channel trending repeatedly | A creator's capacity to keep producing distributable content |
| Channels that only trend once (54.7%) | Creators who get a boost then churn out |
| Publish weekday, publish hour, tags, comments disabled | Actionable levers operations can hand to creators |
| Category, country, institutional-vs-individual | Factors operations can't control but must stratify by |

## Institutional vs. individual classification: method and honest results

**Rule** (`src/label_channels.py`): matches channel names against institutional keywords (`tv`, `news`, `show`, `network`, `media`, etc.) and a list of known media/sports-league acronyms (CNN, BBC, ESPN, NBA, etc.). Deliberately based only on the channel *name text* — not on `trending_videos` or `avg_video_life` — because those are exactly the metrics this label is later used to explain; using them as rule inputs would make that validation circular.

**Manual check**: 200 channels sampled at random (seed=42), each independently judged by reading the channel name for institutional-brand vs. individual-creator signals.

**Agreement rate: 81.5%** — short of an 85% target.

**Why it falls short, honestly**: the disagreements split roughly evenly into two failure modes:
- **False positives** (rule says institutional, manual judgment says individual): channels like `Selena StudioGaming`, `The Infographics Show`, `kawaiisweetworld`, `Family guy live` — individual creators who use words like "show," "studio," or "tv" in their channel name to sound more professional, which the keyword rule can't distinguish from a genuine institution
- **False negatives** (manual judgment says institutional, rule misses it): channels like `Roland Garros`, `Samsung FR`, `Galatasaray`, `VOA Tiếng Việt`, `Mecum Auctions` — real institutions whose brand name carries no generic English keyword, so no keyword list can catch them without turning into an ever-growing, hand-curated whitelist of proper nouns

I tried removing the two most obviously overly generic keywords (`live`, `world`), which moved agreement from 80.5% to 81.5% — a small, principled improvement, not a fix. I stopped there rather than continuing to hand-tune against this one 200-sample set, which would overfit to it rather than generalize. **A purely lexical, name-only rule has a real ceiling here** — the two classes are genuinely not cleanly separable by channel name text alone; a production system would need either a curated institution whitelist maintained over time, or a supervised classifier trained on a much larger labeled set.

## Validating the channel-frequency reversal: is it institution-driven?

The core finding from the channel-level table is that **the most frequently-trending channels have the shortest average per-video lifespan** — e.g., `VikatanTV` (206 trending videos) averages a short lifespan per video, relying on publish volume rather than staying power. The obvious hypothesis: this is because those top channels are institutional (daily-upload news/entertainment accounts).

Splitting by the institutional label tests this directly:

| Channel group | n | Average lifespan (days) |
|---|---|---|
| All individual channels | 10,492 | 2.80 |
| All institutional channels | 1,761 | 2.27 |
| Individual channels with 10+ trending videos | 944 | 2.13 |
| Institutional channels with 10+ trending videos | 230 | 2.07 |

**Finding**: among high-frequency channels (10+ trending videos), individual and institutional channels have nearly identical average lifespans (2.13 vs. 2.07 days) — the gap that exists across *all* channels (2.80 vs. 2.27) almost disappears once you control for publishing frequency.

**This means the reversal is not primarily driven by institutional status.** It's driven by publishing frequency itself: a channel that trends often — whether a news network or an individual creator — sees each individual video's lifespan compressed, likely because a constant stream of new uploads from the same channel pushes older ones off the list faster. This is a more precise finding than "the top channels are institutional, so they trend more and live shorter" — institutional status correlates with high frequency, but frequency, not institutional status, is what actually compresses lifespan.

## Three questions a PGC team would ask, and what this data can(not) answer

1. **"Which creators are worth investing operational support in?"** — this data can partially answer this: channels with 2-9 trending videos (35.7% of channels) show the second-highest average per-video lifespan (2.61 days) of the three frequency buckets, positioned between one-hit channels (2.89 days, likely inflated by small-sample variance) and high-frequency channels (2.12 days). But it can't say *why* a channel is in that middle bucket, or whether operational support would move them to the high-frequency bucket or just compress their lifespan the same way.

2. **"Does institutional status meaningfully change what levers work (e.g., does Friday publishing help institutional and individual creators differently)?"** — partially answerable with this label, but not attempted in this project's hypothesis test (`notebooks/04-hypothesis-test.ipynb` splits by country only, not by institutional status) — a reasonable extension.

3. **"Is a channel's growth trajectory accelerating or plateauing?"** — **not answerable** with this dataset. It's a snapshot of trending-list appearances over a fixed 7-month window; there's no subscriber-count time series or view-count-over-time-since-upload data (beyond the daily trending snapshot itself) to assess trajectory.

## Three things I don't know, and who I'd ask

1. **Whether the 81.5% agreement rate would hold on a larger, independently-drawn sample, or whether I got lucky/unlucky with this particular 200.** I'd ask a colleague to independently label a fresh 200-sample set and compare inter-rater agreement, not just rule-vs-one-rater agreement.
2. **Whether the "known acronym" list (CNN, BBC, ESPN, etc.) is complete enough for other regions.** This dataset spans FRANCE, CANADA, US, GB — a French or francophone media-brand list wasn't built here (e.g., `l'express`, `Medi1TV`, `WatchMojo Français` were all missed by the rule). I'd ask a francophone team member to help build a regional institutional-brand list.
3. **Whether "institutional" is even the right binary** — some channels (`AwesomenessTV`, `Reliance Entertainment`) are clearly companies but not traditional broadcast media; some individual-creator channels (`Michou`, `Rémi GAILLARD`) have teams behind them despite being named after one person. I'd ask whoever owns the actual creator-partnership data internally whether a finer-grained taxonomy (broadcast media / MCN or production company / solo creator with a team / solo creator) already exists and is more useful than a binary split.
