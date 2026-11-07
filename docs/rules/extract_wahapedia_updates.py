"""Extract errata, FAQs and rules-commentary sections from wahapedia's 11e core rules page.

Usage: python3 -I docs/rules/extract_wahapedia_updates.py <out.md> <out.json> <fetched-date> core-rules=<html> rules-appendix=<html>
Tooltip templates (which duplicate rule text) are removed first. Output is deduped by text.
"""
import json, re, sys
from bs4 import BeautifulSoup, NavigableString, Tag

URLS = {"core-rules": "https://wahapedia.ru/wh40k11ed/the-rules/core-rules/",
        "rules-appendix": "https://wahapedia.ru/wh40k11ed/the-rules/rules-appendix/"}
NUM_RE = re.compile(r"^\d{2}\.\d{2}(\.\d{2})?$")


def txt(el):
    s = el.get_text(" ", strip=False) if isinstance(el, Tag) else str(el)
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"\s+([.,;:!?’)])", r"\1", s)


def heading_info(h):
    num = h.find("span", class_="h_number")
    if not num:
        return None
    n = txt(num)
    if not NUM_RE.match(n):
        return None
    title = txt(h).replace(n, "").strip()
    return n, title


def is_section_heading(t):
    return isinstance(t, Tag) and t.name in ("h2", "h3") and heading_info(t) is not None


def section_of(el):
    h = el.find_previous(is_section_heading)
    if not h:
        return ""
    n, title = heading_info(h)
    return f"{n} {title}"


def main():
    out_md, out_json, date = sys.argv[1:4]
    sources = [a.split("=", 1) for a in sys.argv[4:]]
    items = []
    for label, src in sources:
        soup = BeautifulSoup(open(src, encoding="utf-8", errors="replace").read(), "lxml")
        for t in soup.select(".tooltip_templates, script, style, noscript"):
            t.decompose()
        before = len(items)
        collect(soup, items)
        for it in items[before:]:
            it["source"] = label
    finish(items, out_md, out_json, date, sources)


def collect(soup, items):
    # Errata: div.errata_H followed by div.errata
    for h in soup.select("div.errata_H"):
        body = h.find_next_sibling("div", class_="errata")
        items.append({"kind": "Errata", "section": section_of(h), "title": txt(h),
                      "text": txt(body) if body else ""})
    # Stratagem errata blocks
    for s in soup.select(".faqErrataStrat"):
        items.append({"kind": "Stratagem errata", "section": section_of(s), "title": "", "text": txt(s)})
    # FAQs: div.faq > table: td.faq_Q + next td (question), td.faq_A + next td (answer)
    for f in soup.select("div.faq"):
        q = f.find("td", class_="faq_Q")
        a = f.find("td", class_="faq_A")
        qt = txt(q.find_next_sibling("td")) if q and q.find_next_sibling("td") else ""
        at = txt(a.find_next_sibling("td")) if a and a.find_next_sibling("td") else ""
        items.append({"kind": "FAQ", "section": section_of(f), "title": qt, "text": at})
    # Commentary: h2/h3 numbered NN.NN.NN; body = following siblings until next heading/anchor block
    for h in soup.find_all(is_section_heading):
        n, title = heading_info(h)
        if n.count(".") != 2:
            continue
        parts = []
        for sib in h.next_siblings:
            if isinstance(sib, Tag):
                if sib.name in ("h1", "h2", "h3") or (sib.name == "a" and sib.get("name")):
                    break
                if sib.find(is_section_heading):
                    break
                if "faq" in (sib.get("class") or []) or sib.select_one(".faqErrataSpoiler"):
                    continue  # FAQs/errata are captured separately
            parts.append(txt(sib))
        body = " ".join(p for p in parts if p).strip()
        if len(body) < 20:  # content nested deeper than the heading's siblings: walk the document instead
            buf = []
            for el in h.next_elements:
                if isinstance(el, Tag) and el is not h and is_section_heading(el):
                    break
                if isinstance(el, NavigableString) and el.parent is not None and not el.find_parent(class_="faq") \
                        and el.find_parent(lambda t: t is h) is None:
                    buf.append(str(el))
            body = re.sub(r"\s+", " ", " ".join(buf)).strip()
        items.append({"kind": "Commentary", "section": f"{n} {title}", "title": title, "text": body})



def finish(items, out_md, out_json, date, sources):
    # dedupe, keep document order per kind
    seen, uniq = set(), []
    for it in items:
        key = (it["kind"], it["section"].split(" ")[0], it["text"])
        if key in seen:
            continue
        seen.add(key)
        uniq.append(it)

    def sort_key(it):
        m = re.match(r"(\d{2})\.(\d{2})(?:\.(\d{2}))?", it["section"])
        return tuple(int(x or 0) for x in m.groups()) if m else (99, 99, 99)

    uniq.sort(key=sort_key)
    counts = {}
    for it in uniq:
        counts[it["kind"]] = counts.get(it["kind"], 0) + 1
    json.dump({"sources": dict(sources), "fetched": date,
               "counts": counts, "items": uniq}, open(out_json, "w"), indent=1, ensure_ascii=False)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write("# 11th edition core rules: errata, FAQs and rules commentary\n\n")
        f.write(f"Extracted {date} from " + ", ".join(f"<{u}>" for u in URLS.values()) + ". "
                "These are the official updates layered on top of the core rules. "
                "`40k_11th_edition_core_rules.txt` (launch PDF text) does **not** contain them; "
                "where they conflict, these win. Items are grouped under the nearest preceding numbered heading on "
                "the page, so a few FAQs sit one section early; errata titles carry their own section numbers. "
                "Refresh: download both pages, then run this file's generator, `extract_wahapedia_updates.py`.\n\n")
        f.write("| kind | count |\n|---|---|\n" + "".join(f"| {k} | {v} |\n" for k, v in sorted(counts.items())) + "\n")
        cur = None
        for it in uniq:
            if it["section"] != cur:
                cur = it["section"]
                f.write(f"\n## {cur or '(unnumbered)'}\n\n")
            src = f" _({it['source']})_"
            if it["kind"] == "FAQ":
                f.write(f"- **FAQ** Q: {it['title']}\n  A: {it['text']}{src}\n")
            elif it["kind"] == "Errata":
                f.write(f"- **Errata** {it['title']}: {it['text']}{src}\n")
            elif it["kind"] == "Commentary":
                f.write(f"- **Commentary**: {it['text']}{src}\n")
            else:
                f.write(f"- **{it['kind']}**: {it['text']}{src}\n")
    print(counts, "total", len(uniq))


if __name__ == "__main__":
    main()
