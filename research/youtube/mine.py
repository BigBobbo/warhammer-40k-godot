#!/usr/bin/env python3
"""Compact batch miner — run many themed regexes and print one line per hit.

Built for scanning breadth before deep-diving: each hit is trimmed to a short
window so hundreds of hits stay readable, and every line carries the channel and
timestamp needed to cite it.

    python3 mine.py THEME 'regex' [--width 180] [--per-video 1] [--max 30]
                    [--channel S] [--title S] [--faction NAME]
"""

from __future__ import annotations

import argparse
import re
import sys

from search_transcripts import load, marker_index, seconds_at, fmt_ts, clean


def run(pattern, recs, width=180, per_video=1, max_hits=30, require=None):
    rx = re.compile(pattern, re.IGNORECASE)
    req = re.compile(require, re.IGNORECASE) if require else None
    out = []
    for rec in recs:
        text = rec["text"]
        if req and not req.search(text):
            continue
        markers = marker_index(text)
        found = 0
        for m in rx.finditer(text):
            if found >= per_video:
                break
            found += 1
            secs = seconds_at(markers, m.start())
            lo = max(0, m.start() - width // 2)
            hi = min(len(text), m.end() + width)
            out.append({
                "channel": rec["channel"], "date": rec.get("date", ""),
                "video_id": rec["video_id"], "title": rec["title"],
                "ts": fmt_ts(secs), "secs": secs,
                "snip": clean(text[lo:hi]),
            })
    return out[:max_hits]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme")
    ap.add_argument("pattern")
    ap.add_argument("--width", type=int, default=180)
    ap.add_argument("--per-video", type=int, default=1)
    ap.add_argument("--max", type=int, default=30)
    ap.add_argument("--channel", default="")
    ap.add_argument("--title", default="")
    ap.add_argument("--require", default="")
    args = ap.parse_args()

    recs = [r for r in load()
            if args.channel.lower() in r["channel"].lower()
            and args.title.lower() in r["title"].lower()]
    hits = run(args.pattern, recs, args.width, args.per_video, args.max,
               args.require or None)
    print("### %s — %d shown" % (args.theme, len(hits)))
    for h in hits:
        print("- [%s|%s|%s|%s] %s" % (h["channel"][:22], h["date"][5:], h["ts"],
                                      h["video_id"], h["snip"]))


if __name__ == "__main__":
    main()
