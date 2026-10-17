#!/usr/bin/env python3
"""Filter a Wahapedia 11e CSV export to one faction and write a readable rules extract.

Usage (run with -I; the export dir is untrusted downloaded data):
  python3 -I extract_snapshot.py <export_dir> <FACTION_ID> <out_dir> [faction_page.html]

<export_dir> holds the CSVs from https://wahapedia.ru/wh40k11ed/<Name>.csv
(Last_update, Source, Factions, Datasheets*, Abilities, Detachments,
Detachment_abilities, Enhancements, Stratagems). Writes <out_dir>/wahapedia/*.csv
(faction rows only) and <out_dir>/RULES.md. If the faction page HTML is given,
the text between `html_start` and `html_end` markers (see MARKERS) is appended —
used for rules the CSV export omits (e.g. the Custodes ka'tah abilities).
"""
import csv
import html
import os
import re
import sys

MARKERS = {
    "AC": ("CONSERVAI KA’TAH", "Aegis of the Emperor"),
}


def load(path):
    with open(path, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh, delimiter="|"))


def strip(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub("<[^>]+>", " ", s or ""))).strip()


def main():
    export_dir, faction, out_dir = sys.argv[1:4]
    page = sys.argv[4] if len(sys.argv) > 4 else None
    os.makedirs(os.path.join(out_dir, "wahapedia"), exist_ok=True)
    L = lambda f: load(os.path.join(export_dir, f))

    src = {r["id"]: r for r in L("Source.csv")}
    sheets = [r for r in L("Datasheets.csv") if r["faction_id"] == faction]
    ids = {r["id"] for r in sheets}
    for f in sorted(os.listdir(export_dir)):
        if not f.endswith(".csv"):
            continue
        rows = L(f)
        if not rows:
            continue
        keys = [k for k in rows[0].keys() if k]
        if "datasheet_id" in keys:
            keep = [r for r in rows if r["datasheet_id"] in ids]
        elif "faction_id" in keys:
            keep = [r for r in rows if r["faction_id"] == faction]
        elif f == "Last_update.csv":
            keep = rows
        else:
            continue
        with open(os.path.join(out_dir, "wahapedia", f), "w", encoding="utf-8", newline="") as o:
            w = csv.DictWriter(o, fieldnames=keys, delimiter="|", extrasaction="ignore")
            w.writeheader()
            w.writerows(keep)
        print(f, len(keep))

    stamp = L("Last_update.csv")[0]["last_update"]
    out = [f"# {faction} 11e — Wahapedia rules extract (export {stamp})\n"]
    out.append("## Datasheets by source\n")
    for r in sorted(sheets, key=lambda r: (src.get(r["source_id"], {}).get("name", ""), r["name"])):
        out.append(f"- {r['name']} — {src.get(r['source_id'], {}).get('name', '?')}")
    out.append("\n## Army rules\n")
    for r in L("Abilities.csv"):
        if r.get("faction_id") == faction:
            out.append(f"### {r['name']}\n{strip(r['description'])}\n")
    if page and faction in MARKERS:
        with open(page, encoding="utf-8") as fh:
            s = fh.read()
        t = strip(re.sub(r"(?s)<script.*?</script>|<style.*?</style>", "", s))
        a, b = MARKERS[faction]
        i = t.find(a)
        j = t.find(b, i)
        if i >= 0 and j > i:
            out.append("### From the faction page (not in the CSV export)\n" + t[i:j] + "\n")
    dets = [r for r in L("Detachments.csv") if r["faction_id"] == faction]
    da, en, st = L("Detachment_abilities.csv"), L("Enhancements.csv"), L("Stratagems.csv")
    for d in dets:
        out.append(f"## Detachment: {d['name']} ({d.get('dp', '')}DP, {d.get('force_disposition', '')})\n")
        for r in da:
            if r["detachment_id"] == d["id"]:
                out.append(f"**Rule — {r['name']}:** {strip(r['description'])}\n")
        for r in en:
            if r["detachment_id"] == d["id"]:
                out.append(f"- **Enh {r['name']}** ({r['cost']} pts): {strip(r['description'])}")
        out.append("")
        for r in st:
            if r["detachment_id"] == d["id"]:
                out.append(f"- **Strat {r['name']}** ({r['cp_cost']}CP, {r['type']}, {r['phase']}): {strip(r['description'])}")
        out.append("")
    with open(os.path.join(out_dir, "RULES.md"), "w", encoding="utf-8") as o:
        o.write("\n".join(out))


if __name__ == "__main__":
    main()
