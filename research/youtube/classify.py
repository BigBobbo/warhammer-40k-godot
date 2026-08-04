#!/usr/bin/env python3
"""Tightened classifier: game-system gate + precise category patterns."""
import json, re
from datetime import datetime, timezone
from collections import Counter

EDITION_START = datetime(2026,6,1,tzinfo=timezone.utc)

allv={}
for f in ("channel_videos.json","search_videos.json"):
    try: src=json.load(open(f))
    except Exception: continue
    for vid,v in src.items():
        cur=allv.setdefault(vid,{})
        for k,x in v.items():
            if x and not cur.get(k): cur[k]=x
        cur.setdefault("video_id",vid)

FACTIONS = (r"space marines?|necrons?|aeldari|eldar|tyranids?|orks?|t'?au|chaos space marines?|"
            r"astra militarum|imperial guard|custodes|adepta sororitas|sisters of battle|"
            r"adeptus mechanicus|admech|drukhari|genestealer cults?|world eaters|death guard|"
            r"thousand sons|grey knights?|dark angels?|blood angels?|space wolves|deathwatch|"
            r"imperial knights?|chaos knights?|leagues of votann|harlequins?|emperor's children|"
            r"daemons?|chaos daemons|ultramarines|salamanders|iron hands|raven guard|white scars|"
            r"imperial fists|black templars|crimson fists")

# --- gate 1: is this Warhammer 40k at all? ---
IS_40K = re.compile(r"40k|40,000|40 ?000|warhammer 40|11th ed|11th edition|\bcodex\b|detachment|"
                    r"stratagem|battle-?shock|oath of moment|grimdark|" + FACTIONS, re.I)
# --- gate 2: explicitly a DIFFERENT system -> reject ---
OTHER_SYS = re.compile(r"konflikt|age of sigmar|\bAoS\b|kill ?team|necromunda|horus heresy|"
                       r"old world|bolt action|warcry|blood bowl|middle-?earth|legions imperialis|"
                       r"adeptus titanicus|battletech|star wars|shatterpoint|malifaux|infinity the game|"
                       r"one page rules|\bMESBG\b|underworlds|spearhead|boarding actions", re.I)
# --- gate 3: non-tactical content types -> reject ---
NON_TACTICAL = re.compile(r"paint|airbrush|unbox|kitbash|convert|sprue|\blore\b|history of|animation|"
                          r"short film|audio ?book|rumou?r|leak|teaser|hobby|speed ?paint|golden demon|"
                          r"store tour|haul|drama|controversy|goes after|price (rise|increase)|"
                          r"scalper|restock|black library|novel", re.I)

GUIDEY = r"guide|review|breakdown|analysis|tier list|top ?(ten|10|5|three|3)|best |strongest|worst |" \
         r"how to|tips|tricks|explained|focus|deep ?dive|primer|101|masterclass|tactics|competitive|" \
         r"why |should you|ranking|rated|overview"

CATS = [
 ("Core rules / how to play",
  r"how to play|core rules?|rules? (explained|breakdown|change|update)|rule change|beginner|"
  r"new player|learn (to|how to) play|getting started|tutorial|basics|101|what changed|"
  r"everything you need|full rules|rules? primer"),
 ("Army choice / list building",
  r"list ?building|army list|how to (start|build)|starting a|army building|what army|which army|"
  r"best (army|list|detachment)|detachment (guide|breakdown|review|focus)|"
  r"\d{3,4} ?(pts|points)|points (update|change|adjustment)|list review|list ideas|net ?list"),
 ("Deployment / setup / terrain",
  r"deploy|\bsetup\b|set-up|terrain|ruins|line of sight|board control|table quarter|screening|"
  r"scout move|pre-?game|first turn|going first|infiltrat|reserves?|deep ?strike"),
 ("Missions / objectives / scoring",
  r"mission|objective|secondar(y|ies)|primary|scoring|score|pariah|nexus|leviathan|"
  r"mission pack|tactical deck|fixed vs tactical"),
 ("Phase tactics",
  r"movement phase|shooting phase|fight phase|charge phase|command phase|psychic|battle-?shock|"
  r"overwatch|reactive move|phase (tips|tricks|guide)|positioning|melee (tips|tactics)|"
  r"combat trick|fall back|consolidat|pile ?in|heroic"),
 ("Faction / unit guides",
  r"(codex|faction focus|faction guide|unit (review|guide|analysis)|datasheet|tier list|"
  r"top ?(ten|10|5) |best units|army focus)"),
 ("Battle report", r"battle ?report|batrep|\bvs\.?\s|versus|game \d|match ?up|round \d"),
 ("Meta / competitive analysis",
  r"\bmeta\b|win ?rate|tier list|competitive|tournament|balance (dataslate|update)|\bnerf|\bbuff|"
  r"\bWTC\b|\bGT\b|\bLVO\b|top ?tables?|event recap|dataslate|faction ranking|podium|\bRTT\b"),
]
ELEVENTH = re.compile(r"\b11th\b|eleventh|11th ?ed", re.I)

kept=[]; rej=Counter()
for vid,v in allv.items():
    title=v.get('title','') or ''
    text=f"{title} {v.get('desc','')}"
    chan=v.get('channel','') or ''
    d=None
    if v.get('published'):
        try: d=datetime.fromisoformat(v['published'].replace('Z','+00:00'))
        except Exception: pass

    if OTHER_SYS.search(text):        rej['other game system']+=1; continue
    if NON_TACTICAL.search(title):    rej['non-tactical content']+=1; continue
    if not IS_40K.search(f"{text} {chan}"): rej['not identifiably 40k']+=1; continue
    if not ((d and d>=EDITION_START) or ELEVENTH.search(text)):
        rej['pre-11th / undated']+=1; continue

    cats=[]
    for name,pat in CATS:
        if not re.search(pat,text,re.I): continue
        # faction/unit guide must actually be guide-shaped, not just name-dropping
        if name=="Faction / unit guides" and not re.search(GUIDEY,title,re.I): continue
        cats.append(name)
    if not cats: rej['no tactical category']+=1; continue
    # a "X vs Y" batrep shouldn't masquerade as a faction guide
    if "Battle report" in cats and "Faction / unit guides" in cats and not re.search(
            r"codex|faction (focus|guide)|tier list|unit review", title, re.I):
        cats.remove("Faction / unit guides")

    v['categories']=cats
    v['explicit_11th']=bool(ELEVENTH.search(text))
    v['pub_date']=d.date().isoformat() if d else None
    kept.append(v)

kept.sort(key=lambda v:(v.get('pub_date') or '0000'),reverse=True)
json.dump(kept,open("final_videos.json","w"),indent=1)
print(f"merged pool: {len(allv)}\nKEPT: {len(kept)}   (explicit '11th': {sum(1 for v in kept if v['explicit_11th'])})")
print("\nRejected:")
for k,n in rej.most_common(): print(f"  {n:5d}  {k}")
print("\nBy category:")
for k,n in Counter(x for v in kept for x in v['categories']).most_common(): print(f"  {n:5d}  {k}")
print(f"\nChannels: {len(set(v.get('channel') for v in kept))}")
