#!/usr/bin/env python3
"""Concurrently fetch transcripts for the whole corpus -> gzipped JSONL."""
import json, gzip, os, sys, time, threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from fetch_transcripts import transcript

rows = json.load(open("rows.json"))
todo = [(r["u"].split("=")[1], r) for r in rows]
OUT = "transcripts.jsonl.gz"

done = set()
if os.path.exists(OUT):                      # resumable
    with gzip.open(OUT, "rt") as f:
        for line in f:
            try: done.add(json.loads(line)["video_id"])
            except Exception: pass
todo = [(v, r) for v, r in todo if v not in done]
print(f"corpus={len(rows)} already={len(done)} todo={len(todo)}", flush=True)

lock = threading.Lock()
fh = gzip.open(OUT, "at")
stat = {"ok": 0, "fail": 0, "words": 0}

def work(item):
    vid, meta = item
    for attempt in range(2):
        t, err = transcript(vid)
        if t: break
        if "LOGIN_REQUIRED" in (err or "") or "LIVE_STREAM" in (err or ""): break
        time.sleep(1.5)
    with lock:
        if t:
            w = sum(len(c["text"].split()) for c in t["cues"])
            stat["ok"] += 1; stat["words"] += w
            fh.write(json.dumps({"video_id": vid, "title": meta["t"], "channel": meta["c"],
                                 "date": meta["d"], "cats": meta["g"], "url": meta["u"],
                                 "lang": t["lang"], "auto": t["auto"], "words": w,
                                 "cues": t["cues"]}) + "\n")
        else:
            stat["fail"] += 1
            fh.write(json.dumps({"video_id": vid, "title": meta["t"], "channel": meta["c"],
                                 "url": meta["u"], "error": err}) + "\n")
        n = stat["ok"] + stat["fail"]
        if n % 25 == 0:
            print(f"  {n}/{len(todo)}  ok={stat['ok']} fail={stat['fail']} "
                  f"words={stat['words']:,}", flush=True); fh.flush()

t0 = time.time()
with ThreadPoolExecutor(max_workers=6) as ex:
    list(as_completed(ex.submit(work, i) for i in todo))
fh.close()
el = time.time() - t0
print(f"\nDONE in {el/60:.1f} min  ok={stat['ok']} fail={stat['fail']} "
      f"({100*stat['ok']//max(1,stat['ok']+stat['fail'])}%)  words={stat['words']:,}")
print("size:", round(os.path.getsize(OUT)/1024/1024, 1), "MB")
