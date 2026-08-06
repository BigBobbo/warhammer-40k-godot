#!/usr/bin/env python3
"""Mine one faction's transcripts for decision-shaped statements.

Attribution guard: by default only transcripts whose TITLE names the faction are
searched. Titles are human-written, so they survive the caption errors that make
in-body proper nouns unreliable ("Votann" -> "voltan", "Orks" -> "orcs"). Use
--body to relax to body-attributed transcripts when the title-only pool is thin;
findings drawn from that pool must be marked lower confidence.

    python3 faction_mine.py Orks 'waaagh.{0,80}' --max 12
    python3 faction_mine.py Necrons 'reanimat\\w+' --body
"""

from __future__ import annotations

import argparse

from search_transcripts import load
from faction_index import COMPILED, MIN_BODY_HITS
from mine import run


def pool(faction, body=False):
    rx = COMPILED[faction]
    out = []
    for rec in load():
        if rx.search(rec["title"]):
            out.append(rec)
        elif body and len(rx.findall(rec["text"])) >= MIN_BODY_HITS:
            out.append(rec)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("faction", choices=sorted(COMPILED))
    ap.add_argument("pattern")
    ap.add_argument("--body", action="store_true")
    ap.add_argument("--max", type=int, default=12)
    ap.add_argument("--width", type=int, default=200)
    ap.add_argument("--per-video", type=int, default=1)
    args = ap.parse_args()

    recs = pool(args.faction, args.body)
    hits = run(args.pattern, recs, args.width, args.per_video, args.max)
    print("### %s (pool=%d transcripts, %d channels) — %d hits shown"
          % (args.faction, len(recs), len({r["channel"] for r in recs}), len(hits)))
    for h in hits:
        print("- [%s|%s|%s|%s] %s" % (h["channel"][:22], h["date"][5:], h["ts"],
                                      h["video_id"], h["snip"]))


if __name__ == "__main__":
    main()
