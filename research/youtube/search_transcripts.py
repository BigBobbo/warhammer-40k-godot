#!/usr/bin/env python3
"""Full-text search over the harvested 11th-edition transcript corpus.

Answers "where did someone actually explain this rule?" with a video, a
timestamp, and the surrounding words - so a rules claim can be traced to
a source before it gets implemented.

Usage:
    python3 search_transcripts.py "overwatch"
    python3 search_transcripts.py "deep strike" --cat Rules --limit 15
    python3 search_transcripts.py "battle-?shock" --regex --context 40
"""
import argparse, gzip, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "transcripts_text.jsonl.gz")


def load():
    if not os.path.exists(CORPUS):
        sys.exit(f"corpus not found: {CORPUS}\nRun scrape_all.py first.")
    with gzip.open(CORPUS, "rt") as f:
        for line in f:
            try: yield json.loads(line)
            except Exception: continue


def timestamp_at(text, pos):
    """Nearest preceding [MM:00] marker -> H:MM:SS."""
    marks = [(m.start(), int(m.group(1))) for m in re.finditer(r"\[(\d+):00\]", text[:pos + 1])]
    if not marks: return "0:00"
    mins = marks[-1][1]
    return f"{mins // 60}:{mins % 60:02d}:00" if mins >= 60 else f"{mins}:00"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("--regex", action="store_true", help="treat query as a regex")
    ap.add_argument("--cat", help="restrict to a category (Rules, Lists, Deployment, …)")
    ap.add_argument("--channel", help="restrict to a channel (substring match)")
    ap.add_argument("--limit", type=int, default=25, help="max videos to report")
    ap.add_argument("--context", type=int, default=30, help="words of context per hit")
    ap.add_argument("--per-video", type=int, default=2, help="max hits shown per video")
    a = ap.parse_args()

    pat = re.compile(a.query if a.regex else re.escape(a.query), re.I)
    results, total = [], 0

    for rec in load():
        if a.cat and a.cat not in rec.get("cats", []): continue
        if a.channel and a.channel.lower() not in rec["channel"].lower(): continue
        hits = list(pat.finditer(rec["text"]))
        if not hits: continue
        total += len(hits)
        snips = []
        for m in hits[:a.per_video]:
            words = rec["text"][:m.start()].split()
            before = " ".join(words[-a.context:])
            after = " ".join(rec["text"][m.end():].split()[:a.context])
            snips.append((timestamp_at(rec["text"], m.start()),
                          f"…{before} 〈{m.group(0)}〉 {after}…"))
        results.append((len(hits), rec, snips))

    results.sort(key=lambda r: -r[0])
    print(f"{total} mentions across {len(results)} videos "
          f"(showing {min(a.limit, len(results))})\n")
    for n, rec, snips in results[:a.limit]:
        print(f"── {rec['channel']} · {rec['date']} · {n} mention{'s' if n > 1 else ''}")
        print(f"   {rec['title'][:88]}")
        for ts, s in snips:
            clean = re.sub(r"\s+", " ", re.sub(r"\[\d+:00\]", "", s)).strip()
            print(f"   [{ts}] {clean[:260]}")
        print(f"   {rec['url']}\n")


if __name__ == "__main__":
    main()
