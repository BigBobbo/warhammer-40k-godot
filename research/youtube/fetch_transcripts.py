#!/usr/bin/env python3
"""Fetch YouTube transcripts via the InnerTube player API (ANDROID_VR client).

Works from IPs where yt-dlp's watch-page path is bot-blocked, because the
player endpoint is a plain JSON POST and returns pre-signed timedtext URLs.
"""
import json, re, subprocess, sys, time, html, os

KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
UA  = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X)"
# IOS first: ANDROID_VR returns LOGIN_REQUIRED on many videos, IOS does not.
CLIENTS = [
    {"clientName":"IOS","clientVersion":"20.10.4","deviceModel":"iPhone16,2"},
    {"clientName":"ANDROID_VR","clientVersion":"1.62.27","androidSdkVersion":32},
]

def post_player(vid, timeout=40):
    """Try each client until one returns caption tracks."""
    last = None
    for ctx in CLIENTS:
        body = {"context":{"client":ctx},"videoId":vid,"contentCheckOk":True,"racyCheckOk":True}
        r = subprocess.run(["curl","-s","-m",str(timeout),"-X","POST",
            f"https://www.youtube.com/youtubei/v1/player?key={KEY}",
            "-H","Content-Type: application/json","-H",f"User-Agent: {UA}",
            "-d",json.dumps(body)], capture_output=True, text=True)
        try: d = json.loads(r.stdout)
        except Exception: continue
        last = d
        tl = (d.get("captions",{}).get("playerCaptionsTracklistRenderer") or {}).get("captionTracks")
        if tl: return d
    return last

def parse_timedtext(raw):
    """Handle both json3 and the XML timedtext format."""
    raw = raw.strip()
    if raw.startswith("{"):
        d = json.loads(raw)
        return [{"t": e["tStartMs"]/1000,
                 "d": e.get("dDurationMs",0)/1000,
                 "text": "".join(s.get("utf8","") for s in e["segs"]).strip()}
                for e in d.get("events",[]) if "segs" in e]
    cues=[]
    for m in re.finditer(r'<p t="(\d+)"(?: d="(\d+)")?[^>]*>(.*?)</p>', raw, re.S):
        txt = re.sub(r"<[^>]+>","",m.group(3))
        txt = html.unescape(txt).strip()
        if txt: cues.append({"t":int(m.group(1))/1000,
                             "d":int(m.group(2) or 0)/1000,"text":txt})
    return cues

def transcript(vid, lang_pref=("en",)):
    d = post_player(vid)
    if not d: return None,"no player response"
    st = d.get("playabilityStatus",{}).get("status")
    tl = (d.get("captions",{}).get("playerCaptionsTracklistRenderer") or {}).get("captionTracks") or []
    if not tl: return None, f"no caption tracks (status={st})"
    track = next((t for t in tl if any(t.get("languageCode","").startswith(p) for p in lang_pref)), tl[0])
    url = track["baseUrl"]
    if "fmt=" not in url: url += "&fmt=json3"
    r = subprocess.run(["curl","-s","-m","40","-A",UA,url],capture_output=True,text=True)
    if not r.stdout.strip(): return None,"empty timedtext body"
    try: cues = parse_timedtext(r.stdout)
    except Exception as e: return None, f"parse error {e}"
    if not cues: return None,"zero cues"
    return {"video_id":vid,"lang":track.get("languageCode"),
            "auto":track.get("kind")=="asr","cues":cues}, None

if __name__=="__main__":
    ids = sys.argv[1:]
    ok=fail=0
    for i,v in enumerate(ids,1):
        t,err = transcript(v)
        if t:
            ok+=1; words=sum(len(c["text"].split()) for c in t["cues"])
            print(f"[{i:3d}] {v} OK   cues={len(t['cues']):5d} words={words:6d} lang={t['lang']} asr={t['auto']}")
        else:
            fail+=1; print(f"[{i:3d}] {v} FAIL {err}")
        time.sleep(0.4)
    print(f"\nSUCCESS {ok}/{ok+fail}  ({100*ok//max(1,ok+fail)}%)")
