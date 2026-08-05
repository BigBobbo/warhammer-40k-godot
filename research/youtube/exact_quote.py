#!/usr/bin/env python3
"""Print the verbatim corpus span around a probe phrase, with its true timestamp.

Used to replace hand-typed (and therefore paraphrased) quotes in
build_learnings.py with text that actually appears in the transcript.

    python3 exact_quote.py <video_id> '<probe words>' [chars]
"""
import re, sys
from search_transcripts import load, marker_index, seconds_at, fmt_ts, MARKER_RE

vid, probe = sys.argv[1], sys.argv[2]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 200
rec = next(r for r in load() if r["video_id"] == vid)
raw = rec["text"]
flat = re.sub(r"\s+", " ", MARKER_RE.sub(" ", raw))
rx = re.compile(r"\s*".join(re.escape(c) for c in probe.lower().replace(" ", "")), re.I)
m = rx.search(re.sub(r"\s+", "", flat))
# simpler: search word-wise on the flattened text
words = probe.split()
rx2 = re.compile(r"[^a-zA-Z0-9]+".join(re.escape(w) for w in words), re.I)
m2 = rx2.search(flat)
if not m2:
    print("NOT FOUND in flattened text"); sys.exit(1)
# recover timestamp by finding the same span in raw
markers = marker_index(raw)
rx3 = re.compile(r"[^a-zA-Z0-9]+".join(re.escape(w) for w in words), re.I)
m3 = rx3.search(raw)
ts = fmt_ts(seconds_at(markers, m3.start())) if m3 else "??"
lo, hi = max(0, m2.start()-40), min(len(flat), m2.end()+width)
print("TS", ts, "|", rec["channel"])
print(flat[lo:hi])
