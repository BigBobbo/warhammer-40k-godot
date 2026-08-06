#!/usr/bin/env python3
"""Verify every evidence quote in ai_learnings.json against the corpus.

Checks, per evidence row:
  1. the video_id exists in the corpus
  2. the channel name matches that video's channel
  3. each fragment of the quote (split on the ellipsis used to elide) appears in
     the transcript, normalised for whitespace and case
  4. the first fragment sits within +/-TOLERANCE minutes of the cited timestamp

Exit code is non-zero if anything fails, so this can gate a commit.
"""

from __future__ import annotations

import json
import os
import re
import sys

from search_transcripts import load, marker_index, seconds_at, MARKER_RE

HERE = os.path.dirname(os.path.abspath(__file__))
TOLERANCE_MIN = 2


def norm(s: str) -> str:
    s = MARKER_RE.sub(" ", s)
    s = s.replace("’", "'").replace("“", '"').replace("”", '"')
    s = re.sub(r"[^a-z0-9' ]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def main():
    doc = json.load(open(os.path.join(HERE, "ai_learnings.json")))
    corpus = {r["video_id"]: r for r in load()}
    fails, checked = [], 0

    for finding in doc["findings"]:
        for e in finding["evidence"]:
            checked += 1
            tag = "%s %s %s" % (finding["id"], e["video_id"], e["timestamp"])
            rec = corpus.get(e["video_id"])
            if rec is None:
                fails.append("%s: video_id not in corpus" % tag)
                continue
            if rec["channel"] != e["channel"]:
                fails.append("%s: channel %r != corpus %r"
                             % (tag, e["channel"], rec["channel"]))
            raw = rec["text"]
            markers = marker_index(raw)
            # Blank out [MM:00] markers in place (same length) so offsets into
            # `raw` stay valid while the marker digits stop polluting the text.
            masked = MARKER_RE.sub(lambda m: " " * len(m.group(0)), raw)
            # Map every raw-text offset onto its offset in the normalised string,
            # so a match in normalised space can be traced back to a timestamp.
            back = []
            buf = []
            prev_space = True
            for i, ch in enumerate(masked):
                c = norm(ch)
                if c == "":
                    if not prev_space and buf and buf[-1] != " ":
                        buf.append(" ")
                        back.append(i)
                    prev_space = True
                    continue
                prev_space = False
                buf.append(c)
                back.append(i)
            hay = "".join(buf)
            first_at = None
            for frag in [f for f in e["quote"].split("...") if norm(f)]:
                nf = norm(frag)
                pos = hay.find(nf)
                if pos < 0:
                    fails.append("%s: fragment not found: %r" % (tag, frag.strip()))
                    continue
                if first_at is None:
                    first_at = seconds_at(markers, back[pos])
            if first_at is not None:
                cited = int(e["timestamp"].split(":")[0]) * 60
                if abs(first_at - cited) > TOLERANCE_MIN * 60:
                    fails.append("%s: quote near %02d:00 but cited %s"
                                 % (tag, first_at // 60, e["timestamp"]))

    print("checked %d evidence rows across %d findings" % (checked, len(doc["findings"])))
    if fails:
        print("\n%d PROBLEM(S):" % len(fails))
        for f in fails:
            print("  -", f)
        sys.exit(1)
    print("all quotes verified against the corpus")


if __name__ == "__main__":
    main()
