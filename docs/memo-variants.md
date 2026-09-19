# Same Finding, Three Audiences

Same underlying finding as `docs/memo.md`, rewritten for three different readers who each need to answer a different question — not just the same content with different words swapped in.

---

## For a PM (needs to decide)

FRANCE and CANADA's trending lists churn daily (59-75% one-day-only videos). Friday-published videos show 4-5 points higher multi-day retention, consistent across three of four markets — a candidate lever, not a confirmed causal effect, since better channels may already prefer Fridays.

**Decision point**: approve a 4-week experiment in FRANCE and CANADA only (US/GB are saturated, no room to test). Estimated sample: 3,400-4,250 videos per market on the public-data proxy metric; real sample size needs recalculating internally before launch. Risk is low — guardrail metrics (trending rate, publish volume) protect against downside. Upside is a lever that could generalize across two markets.

## For Operations (needs to act)

Experiment design: randomly split channels in FRANCE and CANADA into two groups — one gets a "consider publishing on Friday" prompt, one doesn't. Runs 4 weeks.

**What you need to do**:
1. Confirm a channel to reach treatment-group creators (email? in-app message?)
2. Check two guardrail metrics weekly: trending rate must not drop, weekly publish volume must not drop — either breaching its threshold means stop immediately and notify the analytics team
3. Do not stop early just because results "look good" — the rule is run the full 4 weeks or stop only on a guardrail breach

You don't need to compute the primary metric yourself — that's handled after the experiment ends.

## For Engineering (needs the spec)

**Primary metric definition**:
- Numerator = videos published by the group during the experiment window with `days_on_trending >= 2`
- Denominator = **all videos published** by the group during the window — not just already-trending videos, since the treatment itself may change what trends, and using "already-trending" as the denominator would make the comparison unclean

**Randomization unit**: channel-level (needs a stable channel identifier). All of a channel's videos must be assigned to the same group.

**Guardrail metric definitions**:
- Trending rate = share of published videos that make the trending list
- Weekly publish volume = videos published per week, per group

**Known data gap**: this dataset has no `channel_id` — grouping by `channel_title` risks 52-53 case/whitespace duplicate groups. Production implementation needs a real channel identifier.
