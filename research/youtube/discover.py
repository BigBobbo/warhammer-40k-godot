#!/usr/bin/env python3
"""Multi-query YouTube search discovery for 40k 11th-ed tactics content."""
import json, re, subprocess, sys, time, urllib.parse
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"

QUERIES = [
 "warhammer 40k 11th edition tactics","warhammer 40k 11th edition guide",
 "warhammer 40k 11th edition how to play","warhammer 40k 11th edition rules explained",
 "warhammer 40k 11th edition list building","warhammer 40k 11th edition army building",
 "warhammer 40k 11th edition deployment","warhammer 40k 11th edition terrain rules",
 "warhammer 40k 11th edition missions","warhammer 40k 11th edition secondary objectives",
 "warhammer 40k 11th edition stratagems","warhammer 40k 11th edition beginner guide",
 "warhammer 40k 11th edition battle report","warhammer 40k 11th edition competitive",
 "warhammer 40k 11th edition meta","warhammer 40k 11th edition faction guide",
 "warhammer 40k 11th edition codex review","warhammer 40k 11th edition movement tricks",
 "warhammer 40k 11th edition shooting phase","warhammer 40k 11th edition fight phase",
 "warhammer 40k 11th edition charge phase","warhammer 40k 11th edition command phase",
 "warhammer 40k 11th edition objectives scoring","warhammer 40k 11th edition detachment",
 "warhammer 40k 11th edition tournament","warhammer 40k 11th edition tips",
 "warhammer 40k 11th edition new player","warhammer 40k 11th edition unit review",
 "warhammer 40k 11th edition positioning","warhammer 40k 11th edition screening",
 "40k 11th edition what changed","warhammer 40k 11th edition core rules",
]

def curl(url, tries=3):
    for i in range(tries):
        r=subprocess.run(["curl","-sL","--compressed","-m","45","-A",UA,url],
                         capture_output=True,text=True,errors="ignore")
        if r.returncode==0 and len(r.stdout)>5000: return r.stdout
        time.sleep(1.5*(i+1))
    return ""

def walk(o,key,out):
    if isinstance(o,dict):
        if key in o: out.append(o[key])
        for v in o.values(): walk(v,key,out)
    elif isinstance(o,list):
        for v in o: walk(v,key,out)
    return out

def search(q):
    url="https://www.youtube.com/results?search_query="+urllib.parse.quote(q)+"&sp=CAI%253D"
    h=curl(url)
    m=re.search(r'var ytInitialData\s*=\s*(\{.*?\});</script>',h,re.S)
    if not m: return {}
    d=json.loads(m.group(1)); out={}
    for r in walk(d,'videoRenderer',[]):
        vid=r.get('videoId')
        if not vid: continue
        t=r.get('title',{})
        title=''.join(x.get('text','') for x in t.get('runs',[])) or t.get('simpleText','')
        own=r.get('ownerText',{}) or r.get('longBylineText',{})
        ch=''.join(x.get('text','') for x in own.get('runs',[])) if own else ''
        chid=''
        for ep in walk(own,'browseEndpoint',[]):
            if ep.get('browseId','').startswith('UC'): chid=ep['browseId']; break
        out[vid]={"video_id":vid,"title":title,"channel":ch,"channel_id":chid,
                  "published":(r.get('publishedTimeText') or {}).get('simpleText'),
                  "length":(r.get('lengthText') or {}).get('simpleText'),
                  "views":(r.get('viewCountText') or {}).get('simpleText'),
                  "desc":''.join(s.get('text','') for s in (r.get('detailedMetadataSnippets') or [{}])[0].get('snippetText',{}).get('runs',[])),
                  "url":f"https://www.youtube.com/watch?v={vid}","src":"search"}
    return out

if __name__=="__main__":
    allv={}; chans={}
    for i,q in enumerate(QUERIES,1):
        r=search(q)
        for v in r.values():
            allv.setdefault(v['video_id'],v)
            if v['channel_id']: chans[v['channel_id']]=v['channel']
        print(f"[{i:2d}/{len(QUERIES)}] {q[:46]:46s} +{len(r):3d}  total={len(allv)} chans={len(chans)}",flush=True)
        time.sleep(0.6)
    json.dump(allv,open("search_videos.json","w"),indent=1)
    json.dump(chans,open("discovered_channels.json","w"),indent=1)
    print("SEARCH TOTAL",len(allv),"CHANNELS",len(chans))
