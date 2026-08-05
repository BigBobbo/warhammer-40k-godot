#!/bin/bash
# Finish the transcript corpus on a local machine (Mac/Linux, residential IP).
#
# The remote container burned its YouTube quota partway through and is now
# throttled across every YouTube endpoint. A residential IP does not carry the
# cloud-provider penalty that triggers this, so yt-dlp works directly - no
# InnerTube poking needed.
#
#   cd research/youtube && ./finish_on_mac.sh
#
# Resumable: re-run it after any interruption and it picks up where it stopped.
set -euo pipefail
cd "$(dirname "$0")"

IDS=transcripts_pending_ids.txt
SUBS=subs_raw
OUT=transcripts_from_mac.jsonl

command -v yt-dlp >/dev/null || { echo "yt-dlp not found. Install: pip install -U yt-dlp"; exit 1; }
[ -f "$IDS" ] || { echo "missing $IDS"; exit 1; }

mkdir -p "$SUBS"
TOTAL=$(wc -l < "$IDS" | tr -d ' ')
echo "pending ids: $TOTAL"

# Skip ids already downloaded so re-runs are cheap.
: > .todo
while read -r id; do
  [ -z "$id" ] && continue
  compgen -G "$SUBS/$id.*" > /dev/null || echo "$id" >> .todo
done < "$IDS"
echo "still to fetch: $(wc -l < .todo | tr -d ' ')"

# --sleep-requests keeps a residential IP well under the throttle threshold.
# Add --cookies-from-browser chrome if you ever do hit a bot check.
yt-dlp \
  --skip-download --write-auto-subs --write-subs \
  --sub-langs "en.*" --sub-format json3 \
  --sleep-requests 1 --retries 5 --ignore-errors \
  --paths "$SUBS" -o "%(id)s" \
  --batch-file .todo || true

echo "downloaded files: $(ls -1 "$SUBS" | wc -l | tr -d ' ')"

# Fold the raw json3 caption files into the same JSONL shape the corpus uses.
python3 - "$SUBS" "$OUT" <<'PY'
import glob, json, os, re, sys
subs, out = sys.argv[1], sys.argv[2]
meta = {}
for r in json.load(open("warhammer_40k_11e_videos.json")):
    meta[r["url"].split("=")[1]] = r

n = 0
with open(out, "w") as fh:
    for path in sorted(glob.glob(os.path.join(subs, "*.json3"))):
        vid = os.path.basename(path).split(".")[0]
        try: d = json.load(open(path, encoding="utf-8"))
        except Exception: continue
        cues = []
        for e in d.get("events", []):
            if "segs" not in e: continue
            txt = "".join(s.get("utf8", "") for s in e["segs"]).strip()
            if txt: cues.append({"t": e["tStartMs"] / 1000, "text": txt})
        if not cues: continue
        # same [MM:00] bucketing the container-side corpus uses
        blocks, cur, blk = [], [], 0
        for c in cues:
            b = int(c["t"] // 60)
            if b != blk and cur:
                blocks.append(f"[{blk:02d}:00] " + " ".join(cur)); cur = []; blk = b
            cur.append(c["text"])
        if cur: blocks.append(f"[{blk:02d}:00] " + " ".join(cur))
        m = meta.get(vid, {})
        fh.write(json.dumps({
            "video_id": vid, "title": m.get("title", ""), "channel": m.get("channel", ""),
            "date": m.get("pub_date", ""), "cats": m.get("categories", []),
            "url": f"https://www.youtube.com/watch?v={vid}",
            "words": sum(len(c["text"].split()) for c in cues),
            "text": "\n".join(blocks)}) + "\n")
        n += 1
print(f"wrote {n} transcripts -> {out}")
PY

echo
echo "Done. Merge into the main corpus with:"
echo "  gzip -c $OUT >> transcripts_text.jsonl.gz   # gzip members concatenate cleanly"
echo "Then search everything with:  python3 search_transcripts.py \"your query\""
