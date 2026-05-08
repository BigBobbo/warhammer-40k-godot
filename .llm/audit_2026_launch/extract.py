#!/usr/bin/env python3
"""
Audit Stage 2 — extract the universe of rules/data the game must implement.

Sources:
  - 40k/data/*.csv  (Wahapedia download — the "should" universe)
  - 40k/armies/*.json (curated rosters — the "actually wired" universe)

Outputs:
  - .llm/audit_2026_launch/universe/{abilities,weapon_rules,keywords,
    stratagems,enhancements,detachment_abilities,roster_priority}.json
  - .llm/audit_2026_launch/universe/_summary.md
"""
from __future__ import annotations
import csv
import json
import re
from collections import Counter, defaultdict
from html import unescape
from pathlib import Path

ROOT = Path("/Users/robertocallaghan/Documents/claude/godotv2")
DATA = ROOT / "40k" / "data"
ARMIES = ROOT / "40k" / "armies"
OUT = ROOT / ".llm" / "audit_2026_launch" / "universe"
OUT.mkdir(parents=True, exist_ok=True)


def read_pipe_csv(path: Path) -> list[dict]:
    """Wahapedia CSVs: pipe-delimited, BOM, trailing empty column, embedded HTML.
    The HTML can contain pipes inside attributes — but in practice Wahapedia
    HTML uses double quotes only and no | inside tags, so plain split is safe.
    Verified by spot-check; if a row appears truncated downstream, revisit."""
    text = path.read_text(encoding="utf-8-sig")
    lines = text.split("\n")
    if not lines:
        return []
    headers = [h.strip() for h in lines[0].split("|")]
    while headers and headers[-1] == "":
        headers.pop()
    rows = []
    for ln in lines[1:]:
        if not ln.strip():
            continue
        vals = ln.split("|")
        row = {headers[i]: vals[i] if i < len(vals) else ""
               for i in range(len(headers))}
        rows.append(row)
    return rows


def strip_html(s: str) -> str:
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    return unescape(s).strip()


# ---------- 1. ABILITIES ----------
def extract_abilities():
    abilities = read_pipe_csv(DATA / "Abilities.csv")
    ds_abil = read_pipe_csv(DATA / "Datasheets_abilities.csv")

    ref_count = Counter(r["ability_id"] for r in ds_abil if r.get("ability_id"))
    factions_per_ability = defaultdict(set)
    datasheets = read_pipe_csv(DATA / "Datasheets.csv")
    ds_to_faction = {r["id"]: r.get("faction_id", "") for r in datasheets}
    for r in ds_abil:
        aid = r.get("ability_id", "")
        ds = r.get("datasheet_id", "")
        if aid and ds in ds_to_faction:
            factions_per_ability[aid].add(ds_to_faction[ds])

    inline_count = sum(1 for r in ds_abil if not r.get("ability_id"))
    inline_by_faction = Counter()
    for r in ds_abil:
        if not r.get("ability_id"):
            ds = r.get("datasheet_id", "")
            if ds in ds_to_faction:
                inline_by_faction[ds_to_faction[ds]] += 1

    # Dedupe by ability id — Wahapedia has multiple rows per ability for
    # multi-faction abilities (e.g. Oath of Moment has 5 rows for SM subs).
    by_id = {}
    for a in abilities:
        aid = a["id"]
        if aid in by_id:
            by_id[aid]["faction_ids_in_catalog"].add(a.get("faction_id", ""))
        else:
            by_id[aid] = {
                "id": aid,
                "name": a["name"],
                "faction_ids_in_catalog": {a.get("faction_id", "")},
                "ref_count": ref_count.get(aid, 0),
                "factions_using": sorted(factions_per_ability.get(aid, set())),
                "description": strip_html(a["description"])[:400],
                "rule_text": strip_html(a["legend"])[:600],
            }
    out = []
    for v in by_id.values():
        v["faction_ids_in_catalog"] = sorted(v["faction_ids_in_catalog"])
        out.append(v)
    out.sort(key=lambda x: x["ref_count"], reverse=True)

    (OUT / "abilities.json").write_text(json.dumps({
        "summary": {
            "named_abilities_in_catalog": len(out),
            "datasheet_named_ability_links": sum(r["ref_count"] for r in out),
            "datasheet_inline_abilities": inline_count,
            "inline_by_faction": dict(inline_by_faction.most_common()),
        },
        "abilities": out,
    }, indent=2))
    return out, inline_count


# ---------- 2. WEAPON SPECIAL RULES ----------
KNOWN_TOKENS = [
    "anti-", "assault", "blast", "conversion", "devastating wounds",
    "extra attacks", "feel no pain", "hazardous", "heavy", "ignores cover",
    "indirect fire", "lance", "lethal hits", "melta", "one shot", "pistol",
    "precision", "psychic", "rapid fire", "sustained hits", "torrent",
    "twin-linked", "lone operative",
]

TOKEN_RE = re.compile(r"\[?([a-z][a-z\- ]+?)\s*(\d+\+?|\d|x|n)?\]?$", re.I)


def parse_weapon_rules(field: str):
    if not field:
        return []
    parts = [p.strip().lower() for p in re.split(r"[,;]", field) if p.strip()]
    base = []
    for p in parts:
        # strip trailing values like "4+", "2", "x"
        m = re.match(r"([a-z][a-z\- ]+?)(?:\s+(\d+\+?|\d|x|n))?$", p)
        if m:
            base.append(m.group(1).strip())
        else:
            base.append(p)
    return base


def extract_weapon_rules():
    wargear = read_pipe_csv(DATA / "Datasheets_wargear.csv")
    datasheets = read_pipe_csv(DATA / "Datasheets.csv")
    ds_to_faction = {r["id"]: r.get("faction_id", "") for r in datasheets}

    token_counts = Counter()
    factions_per_token = defaultdict(set)
    weapons_total = 0
    melee_count = 0
    ranged_count = 0

    for w in wargear:
        weapons_total += 1
        if w.get("type", "").lower().startswith("melee"):
            melee_count += 1
        else:
            ranged_count += 1
        rules_field = w.get("description", "") or ""
        # description holds the special-rules text per Wahapedia schema
        rules_field = strip_html(rules_field).lower()
        if not rules_field or rules_field in ("-", "—", ""):
            continue
        for tok in parse_weapon_rules(rules_field):
            # normalize anti-* family
            if tok.startswith("anti-"):
                tok = "anti-X"
            token_counts[tok] += 1
            factions_per_token[tok].add(ds_to_faction.get(w["datasheet_id"], ""))

    rows = []
    for tok, cnt in token_counts.most_common():
        rows.append({
            "token": tok,
            "weapon_uses": cnt,
            "factions": sorted(f for f in factions_per_token[tok] if f),
            "is_known_core": any(k in tok for k in KNOWN_TOKENS) or tok == "anti-X",
        })

    (OUT / "weapon_rules.json").write_text(json.dumps({
        "summary": {
            "total_weapon_profiles": weapons_total,
            "melee_profiles": melee_count,
            "ranged_profiles": ranged_count,
            "distinct_tokens": len(rows),
        },
        "tokens": rows,
    }, indent=2))
    return rows


# ---------- 3. KEYWORDS ----------
def extract_keywords():
    rows = read_pipe_csv(DATA / "Datasheets_keywords.csv")
    counts = Counter()
    faction_kw = Counter()
    for r in rows:
        kw = r.get("keyword", "").strip()
        if not kw:
            continue
        counts[kw] += 1
        if r.get("is_faction_keyword", "").lower() == "true":
            faction_kw[kw] += 1

    out = []
    for kw, cnt in counts.most_common():
        out.append({
            "keyword": kw,
            "datasheet_uses": cnt,
            "is_faction_keyword": faction_kw.get(kw, 0) > 0,
        })

    (OUT / "keywords.json").write_text(json.dumps({
        "summary": {
            "distinct_keywords": len(out),
            "total_keyword_assignments": sum(counts.values()),
        },
        "keywords": out,
    }, indent=2))
    return out


# ---------- 4. STRATAGEMS ----------
def extract_stratagems():
    strat = read_pipe_csv(DATA / "Stratagems.csv")
    ds_strat = read_pipe_csv(DATA / "Datasheets_stratagems.csv")
    ds_count = Counter(r["stratagem_id"] for r in ds_strat if r.get("stratagem_id"))

    by_phase = Counter()
    by_faction = Counter()
    by_detachment = Counter()
    rows = []
    for s in strat:
        sid = s["id"]
        rows.append({
            "id": sid,
            "name": s["name"],
            "faction_id": s.get("faction_id", ""),
            "type": s.get("type", ""),
            "cp_cost": s.get("cp_cost", ""),
            "turn": s.get("turn", ""),
            "phase": s.get("phase", ""),
            "detachment": s.get("detachment", ""),
            "datasheet_count": ds_count.get(sid, 0),
            "description": strip_html(s.get("description", ""))[:600],
        })
        by_phase[s.get("phase", "")] += 1
        by_faction[s.get("faction_id", "")] += 1
        by_detachment[s.get("detachment", "")] += 1

    rows.sort(key=lambda x: (-x["datasheet_count"], x["name"]))

    (OUT / "stratagems.json").write_text(json.dumps({
        "summary": {
            "total": len(rows),
            "by_phase": dict(by_phase.most_common()),
            "by_faction": dict(by_faction.most_common()),
            "by_detachment_top20": dict(by_detachment.most_common(20)),
        },
        "stratagems": rows,
    }, indent=2))
    return rows


# ---------- 5. ENHANCEMENTS ----------
def extract_enhancements():
    enh = read_pipe_csv(DATA / "Enhancements.csv")
    ds_enh = read_pipe_csv(DATA / "Datasheets_enhancements.csv")
    ds_count = Counter(r["enhancement_id"] for r in ds_enh if r.get("enhancement_id"))

    rows = []
    by_faction = Counter()
    by_detachment = Counter()
    for e in enh:
        rows.append({
            "id": e["id"],
            "name": e["name"],
            "faction_id": e.get("faction_id", ""),
            "cost": e.get("cost", ""),
            "detachment": e.get("detachment", ""),
            "eligible_datasheets": ds_count.get(e["id"], 0),
            "description": strip_html(e.get("description", ""))[:600],
        })
        by_faction[e.get("faction_id", "")] += 1
        by_detachment[e.get("detachment", "")] += 1

    (OUT / "enhancements.json").write_text(json.dumps({
        "summary": {
            "total": len(rows),
            "by_faction": dict(by_faction.most_common()),
            "by_detachment_top20": dict(by_detachment.most_common(20)),
        },
        "enhancements": rows,
    }, indent=2))
    return rows


# ---------- 6. DETACHMENT ABILITIES ----------
def extract_detachment_abilities():
    da = read_pipe_csv(DATA / "Detachment_abilities.csv")
    ds_da = read_pipe_csv(DATA / "Datasheets_detachment_abilities.csv")
    ds_count = Counter(r["detachment_ability_id"] for r in ds_da
                       if r.get("detachment_ability_id"))

    rows = []
    by_faction = Counter()
    for d in da:
        rows.append({
            "id": d["id"],
            "name": d["name"],
            "faction_id": d.get("faction_id", ""),
            "detachment": d.get("detachment", ""),
            "detachment_id": d.get("detachment_id", ""),
            "datasheet_count": ds_count.get(d["id"], 0),
            "rule_text": strip_html(d.get("description", ""))[:600],
        })
        by_faction[d.get("faction_id", "")] += 1

    (OUT / "detachment_abilities.json").write_text(json.dumps({
        "summary": {
            "total": len(rows),
            "by_faction": dict(by_faction.most_common()),
        },
        "detachment_abilities": rows,
    }, indent=2))
    return rows


# ---------- 7. ROSTER PRIORITY (active rosters) ----------
def extract_roster_priority():
    """Compare what the active rosters use vs what the catalog contains."""
    roster_abilities = Counter()       # name → uses across rosters
    roster_weapon_rules = Counter()
    roster_keywords = Counter()
    roster_factions = Counter()
    roster_units = Counter()           # unit name → roster count
    rosters_seen = []

    for jf in sorted(ARMIES.glob("*.json")):
        try:
            data = json.loads(jf.read_text())
        except Exception as e:
            print(f"[warn] {jf.name}: {e}")
            continue
        rosters_seen.append(jf.name)
        units = data.get("units", {})
        if isinstance(units, dict):
            unit_iter = units.values()
        elif isinstance(units, list):
            unit_iter = units
        else:
            continue
        for u in unit_iter:
            if not isinstance(u, dict):
                continue
            meta = u.get("meta", {}) if isinstance(u.get("meta"), dict) else {}
            name = meta.get("name") or u.get("name", "?")
            roster_units[name] += 1
            faction = data.get("faction", {})
            if isinstance(faction, dict):
                roster_factions[faction.get("name", "?")] += 1
            for kw in meta.get("keywords", []) or []:
                roster_keywords[str(kw).strip()] += 1
            for ab in meta.get("abilities", []) or []:
                nm = ab.get("name", "?") if isinstance(ab, dict) else str(ab)
                # Normalize curly-vs-straight apostrophes (Ka'tah vs Ka'tah)
                nm = nm.strip().replace("’", "'").replace("‘", "'")
                roster_abilities[nm] += 1
            for w in meta.get("weapons", []) or []:
                if not isinstance(w, dict):
                    continue
                rules_field = (w.get("special_rules") or "").lower()
                for tok in parse_weapon_rules(strip_html(rules_field)):
                    if tok.startswith("anti-"):
                        tok = "anti-X"
                    roster_weapon_rules[tok] += 1

    (OUT / "roster_priority.json").write_text(json.dumps({
        "rosters_scanned": rosters_seen,
        "factions_in_rosters": dict(roster_factions.most_common()),
        "abilities_in_rosters": dict(roster_abilities.most_common()),
        "weapon_rules_in_rosters": dict(roster_weapon_rules.most_common()),
        "keywords_in_rosters": dict(roster_keywords.most_common()),
        "units_in_rosters": dict(roster_units.most_common()),
    }, indent=2))
    return roster_abilities, roster_weapon_rules


# ---------- WRITE SUMMARY ----------
def write_summary(stats):
    md = []
    md.append("# Stage 2 — Extracted Universe\n")
    md.append("Generated by `.llm/audit_2026_launch/extract.py`. "
              "Sources: `40k/data/*.csv` (Wahapedia download) and "
              "`40k/armies/*.json` (active rosters).\n")
    md.append("## Universe sizes (Wahapedia catalog)\n")
    for line in stats["catalog"]:
        md.append(f"- {line}")
    md.append("\n## Roster usage (what's actually fielded)\n")
    for line in stats["roster"]:
        md.append(f"- {line}")
    md.append("\n## Files written\n")
    for f in sorted(OUT.glob("*.json")):
        md.append(f"- `{f.relative_to(ROOT)}` ({f.stat().st_size // 1024} KB)")
    (OUT / "_summary.md").write_text("\n".join(md))


def main():
    abilities, inline_count = extract_abilities()
    weapon_rules = extract_weapon_rules()
    keywords = extract_keywords()
    stratagems = extract_stratagems()
    enhancements = extract_enhancements()
    detach_abilities = extract_detachment_abilities()
    roster_abil, roster_wr = extract_roster_priority()

    stats = {
        "catalog": [
            f"Named abilities catalog (deduped by id): **{len(abilities)}**",
            f"  Top 10 by reference count: " +
                ", ".join(f"{a['name']} ({a['ref_count']})"
                          for a in abilities[:10]),
            f"Inline (datasheet-specific) ability rows: **{inline_count}**",
            f"Weapon special-rule tokens (distinct): **{len(weapon_rules)}**",
            f"  Top 20: " + ", ".join(
                f"{r['token']}({r['weapon_uses']})"
                for r in weapon_rules[:20]),
            f"Keywords (distinct): **{len(keywords)}**",
            f"Stratagems: **{len(stratagems)}**",
            f"Enhancements: **{len(enhancements)}**",
            f"Detachment abilities: **{len(detach_abilities)}**",
        ],
        "roster": [
            f"Distinct abilities used in active rosters: **{len(roster_abil)}**",
            f"  Top 15: " + ", ".join(
                f"{n}({c})" for n, c in roster_abil.most_common(15)),
            f"Distinct weapon-rule tokens used in rosters: **{len(roster_wr)}**",
            f"  Top 15: " + ", ".join(
                f"{n}({c})" for n, c in roster_wr.most_common(15)),
        ],
    }
    write_summary(stats)
    print("Wrote universe/ files:")
    for f in sorted(OUT.glob("*")):
        print(f"  {f.name}: {f.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
