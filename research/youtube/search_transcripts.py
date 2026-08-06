#!/usr/bin/env python3
"""Filtered / regex search over the Warhammer 40k YouTube transcript corpus.

The corpus (research/youtube/transcripts_text.jsonl.gz, gitignored) is one JSON
object per line with the fields:
    video_id, title, channel, date, cats, url, auto, words, text

`text` carries per-minute markers of the form ``[MM:00]``, so every hit can be
cited back to a timestamp and a deep link.

Usage
-----
    python3 search_transcripts.py 'reactive move' --window 220
    python3 search_transcripts.py 'oath of moment' --channel 'Vanguard' --limit 20
    python3 search_transcripts.py 'secondar\\w+ scor\\w+' --cat Missions --json

Options
-------
    --window N      characters of context around the hit (default 200)
    --channel S     substring filter on channel name (case-insensitive)
    --title S       substring filter on video title (case-insensitive)
    --cat S         require this tag in `cats`
    --since / --until  YYYY-MM-DD date bounds
    --limit N       max hits to print (default 40)
    --per-video N   max hits from any single video (default 2)
    --json          emit JSON instead of human-readable text
    --count-only    just report hits per channel / per video
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys
from collections import Counter

DEFAULT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "transcripts_text.jsonl.gz")

MARKER_RE = re.compile(r"\[(\d+):(\d+)\]")


def load(path: str = DEFAULT_PATH):
    """Yield every transcript record. Fails loudly if the corpus is missing."""
    if not os.path.exists(path):
        sys.exit(
            "Corpus not found at %s.\n"
            "It is gitignored on purpose (19MB). Restore it before running "
            "any analysis - do not substitute invented data." % path
        )
    with gzip.open(path, "rt") as fh:
        for line in fh:
            line = line.strip()
            if line:
                yield json.loads(line)


def marker_index(text: str):
    """Return [(char_offset, seconds)] for every [MM:00] marker, in order."""
    out = []
    for m in MARKER_RE.finditer(text):
        out.append((m.start(), int(m.group(1)) * 60 + int(m.group(2))))
    return out


def seconds_at(markers, offset: int) -> int:
    """Seconds of the last marker at or before `offset` (binary search)."""
    lo, hi, best = 0, len(markers) - 1, 0
    while lo <= hi:
        mid = (lo + hi) // 2
        if markers[mid][0] <= offset:
            best = markers[mid][1]
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def fmt_ts(seconds: int) -> str:
    return "%02d:%02d" % (seconds // 60, seconds % 60)


def clean(snippet: str) -> str:
    """Strip markers and collapse whitespace so quotes read as prose."""
    return re.sub(r"\s+", " ", MARKER_RE.sub(" ", snippet)).strip()


def search(pattern, records, window=200, per_video=2, ignore_case=True):
    """Yield hit dicts for `pattern` (regex) over `records`."""
    flags = re.IGNORECASE if ignore_case else 0
    rx = re.compile(pattern, flags)
    for rec in records:
        text = rec["text"]
        markers = marker_index(text)
        found = 0
        for m in rx.finditer(text):
            if per_video and found >= per_video:
                break
            found += 1
            secs = seconds_at(markers, m.start())
            lo = max(0, m.start() - window)
            hi = min(len(text), m.end() + window)
            yield {
                "video_id": rec["video_id"],
                "channel": rec["channel"],
                "title": rec["title"],
                "date": rec.get("date", ""),
                "cats": rec.get("cats", []),
                "timestamp": fmt_ts(secs),
                "seconds": secs,
                "url": "https://youtube.com/watch?v=%s&t=%ds" % (rec["video_id"], secs),
                "match": m.group(0),
                "snippet": clean(text[lo:hi]),
            }


def matching_records(args, records):
    for rec in records:
        if args.channel and args.channel.lower() not in rec["channel"].lower():
            continue
        if args.title and args.title.lower() not in rec["title"].lower():
            continue
        if args.cat and args.cat not in rec.get("cats", []):
            continue
        date = rec.get("date", "")
        if args.since and (not date or date < args.since):
            continue
        if args.until and (not date or date > args.until):
            continue
        yield rec


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pattern", help="regex, case-insensitive by default")
    ap.add_argument("--path", default=DEFAULT_PATH)
    ap.add_argument("--window", type=int, default=200)
    ap.add_argument("--channel", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--cat", default="")
    ap.add_argument("--since", default="")
    ap.add_argument("--until", default="")
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--per-video", type=int, default=2)
    ap.add_argument("--case-sensitive", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--count-only", action="store_true")
    args = ap.parse_args()

    records = list(matching_records(args, load(args.path)))
    hits = list(search(args.pattern, records, window=args.window,
                       per_video=args.per_video,
                       ignore_case=not args.case_sensitive))

    if args.count_only:
        by_channel = Counter(h["channel"] for h in hits)
        vids = {h["video_id"] for h in hits}
        print("%d hits across %d videos / %d channels (of %d records searched)"
              % (len(hits), len(vids), len(by_channel), len(records)))
        for ch, n in by_channel.most_common(30):
            print("%5d  %s" % (n, ch))
        return

    hits = hits[: args.limit]
    if args.json:
        print(json.dumps(hits, indent=2))
        return
    for h in hits:
        print("=" * 100)
        print("%s | %s | %s | %s" % (h["channel"], h["date"], h["timestamp"], h["title"][:70]))
        print(h["url"])
        print(h["snippet"])


if __name__ == "__main__":
    main()
