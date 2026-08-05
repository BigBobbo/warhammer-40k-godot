#!/usr/bin/env python3
"""Faction attribution over the transcript corpus.

Auto-captions mangle proper nouns constantly ("orks" -> "orcs", "Votann" ->
"voltan", "Aeldari" -> "eldari"), so faction attribution never rests on a single
mention. Each faction has a set of aliases; a transcript is attributed to a
faction when EITHER the title names it (strong signal, human-written) OR the
body mentions it repeatedly (>= MIN_BODY_HITS distinct alias hits).

Usage:
    python3 faction_index.py                 # table of per-faction transcript counts
    python3 faction_index.py --faction Orks  # list transcripts attributed to a faction
"""

from __future__ import annotations

import argparse
import re
from collections import Counter, defaultdict

from search_transcripts import load

MIN_BODY_HITS = 6  # distinct in-body alias mentions before body-only attribution

# alias -> regex fragments. Deliberately conservative: ambiguous fragments
# ("guard" alone, "marines" alone, "demons" alone) are excluded or paired.
FACTIONS = {
    "Space Marines": r"space marines?|astartes|adeptus astartes|codex marines?|gladius",
    "Blood Angels": r"blood angels?",
    "Dark Angels": r"dark angels?|deathwing|ravenwing",
    "Space Wolves": r"space wolves|space wolf",
    "Black Templars": r"black templars?",
    "Deathwatch": r"deathwatch",
    "Grey Knights": r"gr[ea]y knights?",
    "Adeptus Custodes": r"custod[ei]s|custodian guard|allarus|adeptus custodes",
    "Adepta Sororitas": r"sororitas|sisters of battle|adepta sororitas",
    "Astra Militarum": r"astra militarum|imperial guard|guardsmen|leman russ|catachan|cadian",
    "Adeptus Mechanicus": r"ad[- ]?mech|mechanicus|skitarii|kataphron",
    "Imperial Knights": r"imperial knights?|knight paladin|knight castellan|questoris",
    "Agents of the Imperium": r"agents of the imperium|assassinorum|callidus|vindicare|eversor",
    "Chaos Space Marines": r"chaos space marines?|c\.?s\.?m\.?\b|legionaries|heretic astartes",
    "World Eaters": r"world eaters?|khorne berzerkers?|angron",
    "Death Guard": r"death guard|plague marines?|mortarion",
    "Thousand Sons": r"thousand sons|rubric marines?|magnus the red",
    "Emperor's Children": r"emperor'?s children|fulgrim|noise marines?",
    "Chaos Daemons": r"chaos daemons|chaos demons|daemon prince|bloodletters|plaguebearers",
    "Chaos Knights": r"chaos knights?|knight desecrator|knight rampager|war dog",
    "Aeldari": r"aeldari|eldari|craftworld|asuryani|wraithknight|farseer|guardian defenders",
    "Drukhari": r"drukhari|dark eldar|drukari|kabalite|wych|haemonculus",
    "Harlequins": r"harlequins?|troupe master|solitaire",
    "Ynnari": r"ynnari|yncarne",
    "Necrons": r"necrons?|lychguard|canoptek|szarekh|silent king|immortals",
    "Orks": r"\borks?\b|\borcs?\b|waaagh|boyz|meganobz|nobz|deffkopta|warboss|beast snagga",
    "T'au Empire": r"t'?au empire|\bt'?au\b|tau empire|fire warriors?|crisis suits?|riptide|battlesuit",
    "Tyranids": r"tyranids?|\bnids\b|hormagaunts?|termagants?|carnifex|hive tyrant|synapse",
    "Genestealer Cults": r"genestealer cults?|\bg\.?s\.?c\.?\b|neophyte|acolyte hybrids?|cult ambush",
    "Leagues of Votann": r"votann|votan\b|hearthkyn|hearthguard|kin\b.{0,20}votann|sagitaur",
    "Sisters of Silence": r"sisters of silence|prosecutors|vigilators",
}

COMPILED = {name: re.compile(rx, re.IGNORECASE) for name, rx in FACTIONS.items()}


def attribute(rec):
    """Return {faction: {'title': bool, 'hits': int}} for one transcript."""
    out = {}
    title = rec["title"]
    text = rec["text"]
    for name, rx in COMPILED.items():
        in_title = bool(rx.search(title))
        hits = len(rx.findall(text))
        if in_title or hits >= MIN_BODY_HITS:
            out[name] = {"title": in_title, "hits": hits}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--faction", default="")
    ap.add_argument("--min-hits", type=int, default=MIN_BODY_HITS)
    args = ap.parse_args()

    recs = list(load())
    counts = Counter()
    title_counts = Counter()
    per_faction = defaultdict(list)
    for rec in recs:
        for name, info in attribute(rec).items():
            counts[name] += 1
            if info["title"]:
                title_counts[name] += 1
            per_faction[name].append((info["hits"], info["title"], rec))

    if args.faction:
        rows = sorted(per_faction[args.faction], key=lambda r: -r[0])
        for hits, in_title, rec in rows[:60]:
            print("%4d %s %-28s %s | %s" % (
                hits, "T" if in_title else " ", rec["channel"][:28],
                rec.get("date", ""), rec["title"][:70]))
        print("total attributed:", len(rows))
        return

    print("%-24s %8s %8s" % ("faction", "attrib", "in-title"))
    for name, n in counts.most_common():
        print("%-24s %8d %8d" % (name, n, title_counts[name]))


if __name__ == "__main__":
    main()
