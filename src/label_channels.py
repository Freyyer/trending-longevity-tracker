"""
Rule-based classifier: institutional account (news organizations, sports
leagues, media companies, official brand/government accounts) vs.
individual creator.

Rules are based ONLY on channel_title text features -- deliberately not on
trending_videos or avg_video_life, since those are the metrics this label
is later used to explain (using them as rule inputs would make later
validation of "do institutional channels trend more but live shorter"
circular).

Manual annotation on a 200-channel random sample (seed=42) found this rule
agrees with human judgment 81.5% of the time -- short of an 85% target.
See docs/creator-ecosystem-brief.md for the honest breakdown of why: the
keywords 'tv', 'news', 'show', 'channel' are used both by real institutions
and by individual creators dressing up their channel name, so no purely
lexical rule cleanly separates the two. Rather than keep hand-tuning
against this one 200-sample set (which would just overfit to it), this
version is kept as the final rule and the disagreement is reported openly.

Usage:
    uv run python src/label_channels.py
"""
import pandas as pd

INSTITUTIONAL_KEYWORDS = [
    "tv", "news", "show", "official", "network", "media", "studio",
    "sports", "channel", "entertainment", "digital", "tonight",
    "press", "broadcast", "productions", "films", "studios",
    "magazine", "talk", "today", "sport",
]
# 'live' and 'world' were tried and dropped: both are common in individual
# creator channel names (e.g. "kawaiisweetworld", "Family guy live") and
# added false positives without meaningfully catching more real institutions.

KNOWN_INSTITUTIONAL_ACRONYMS = [
    "cnn", "bbc", "nbc", "abc", "cbs", "msnbc", "espn", "mtv", "wwe",
    "nfl", "nba", "nhl", "mlb", "fifa", "uefa", "pbs", "fox", "hbo",
]


def classify(title: str) -> tuple[bool, str]:
    t = str(title).lower().strip()
    for acr in KNOWN_INSTITUTIONAL_ACRONYMS:
        if acr in t.split() or t == acr:
            return True, f"known_acronym:{acr}"
    for kw in INSTITUTIONAL_KEYWORDS:
        if kw in t:
            return True, f"keyword:{kw}"
    return False, "no_match"


def main() -> None:
    channel = pd.read_csv("data/exports/channel.csv")
    results = channel["channel_title"].apply(classify)
    channel["is_institutional"] = results.apply(lambda x: x[0])
    channel["rule_reason"] = results.apply(lambda x: x[1])

    out_path = "data/channel_labels.csv"
    channel.to_csv(out_path, index=False)

    print(f"Labeled {len(channel)} channels -> {out_path}")
    print(f"Institutional: {channel['is_institutional'].sum()} ({channel['is_institutional'].mean():.1%})")
    print(f"Individual: {(~channel['is_institutional']).sum()} ({(~channel['is_institutional']).mean():.1%})")


if __name__ == "__main__":
    main()
