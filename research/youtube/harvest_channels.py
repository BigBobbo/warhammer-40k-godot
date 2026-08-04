#!/usr/bin/env python3
"""Harvest recent videos for every discovered channel (page + RSS)."""
import json, re, subprocess, time
from datetime import datetime, timedelta, timezone
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
NOW=datetime(2026,8,4,tzinfo=timezone.utc)

def curl(url,tries=2):
    for i in range(tries):
        r=subprocess.run(["curl","-sL","--compressed","-m","40","-A",UA,url],
                         capture_output=True,text=True,errors="ignore")
        if r.returncode==0 and len(r.stdout)>1000: return r.stdout
        time.sleep(1.0*(i+1))
    return ""

def walk(o,key,out):
    if isinstance(o,dict):
        if key in o: out.append(o[key])
        for v in o.values(): walk(v,key,out)
    elif isinstance(o,list):
        for v in o: walk(v,key,out)
    return out

REL=re.compile(r"(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago")
def rel(rows):
    for s in rows:
        m=REL.search(s or "")
        if m:
            n,u=int(m.group(1)),m.group(2)
            d={"second":0,"minute":0,"hour":0,"day":1,"week":7,"month":30.44,"year":365.25}[u]
            return NOW-timedelta(days=n*d)
    return None

def page_videos(cid):
    h=curl(f"https://www.youtube.com/channel/{cid}/videos")
    m=re.search(r'var ytInitialData\s*=\s*(\{.*?\});</script>',h,re.S)
    if not m: return {}
    d=json.loads(m.group(1)); out={}
    for lk in walk(d,'lockupViewModel',[]):
        vid=lk.get('contentId')
        if not vid or lk.get('contentType')!='LOCKUP_CONTENT_TYPE_VIDEO': continue
        meta=(lk.get('metadata') or {}).get('lockupMetadataViewModel') or {}
        title=(meta.get('title') or {}).get('content')
        if not title: continue
        rows=[x['content'] for x in walk(meta,'text',[]) if isinstance(x,dict) and 'content' in x]
        ln=None
        for b in walk(lk,'thumbnailBadgeViewModel',[]):
            if re.fullmatch(r"(\d+:)?\d+:\d{2}",b.get('text','') or ''): ln=b['text']
        dt=rel(rows)
        out[vid]={"video_id":vid,"title":title,"length":ln,
                  "published":dt.isoformat() if dt else None,"date_exact":False,
                  "views":next((r for r in rows if 'view' in r.lower()),None),
                  "url":f"https://www.youtube.com/watch?v={vid}","src":"channel"}
    return out

def rss_videos(cid):
    xml=curl(f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}")
    out={}
    for e in re.findall(r"<entry>(.*?)</entry>",xml,re.S):
        v=re.search(r"<yt:videoId>([^<]+)</yt:videoId>",e)
        t=re.search(r"<title>(.*?)</title>",e,re.S)
        p=re.search(r"<published>([^<]+)</published>",e)
        de=re.search(r"<media:description>(.*?)</media:description>",e,re.S)
        if not v: continue
        out[v.group(1)]={"video_id":v.group(1),"title":(t.group(1) if t else '').strip(),
                         "published":p.group(1) if p else None,"date_exact":True,
                         "desc":(de.group(1)[:500] if de else ''),
                         "url":f"https://www.youtube.com/watch?v={v.group(1)}","src":"rss"}
    return out

chans=json.load(open("discovered_channels.json"))
allv={}
for i,(cid,name) in enumerate(chans.items(),1):
    merged={}
    for vid,v in page_videos(cid).items(): merged[vid]=v
    for vid,v in rss_videos(cid).items():
        merged.setdefault(vid,{}).update({k:x for k,x in v.items() if x})
    for v in merged.values(): v["channel"]=name; v["channel_id"]=cid
    allv.update(merged)
    print(f"[{i:3d}/{len(chans)}] {name[:32]:32s} +{len(merged):3d} total={len(allv)}",flush=True)
json.dump(allv,open("channel_videos.json","w"),indent=1)
print("CHANNEL TOTAL",len(allv))
