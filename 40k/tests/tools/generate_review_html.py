#!/usr/bin/env python3
"""Generate a single-file HTML review report for the Tier B walkthrough.

Reads:
  - .llm/todo.md to find each T##'s Tier B checklist (and current tick state)
  - 40k/test_results/design_guidelines/T##/T##_*.png screenshots
  - REVIEW_GUIDE.md's known-gap table

Writes:
  - 40k/test_results/design_guidelines/review.html — self-contained page
    with inline screenshots (file:// relative paths), tickable boxes
    (browser-only state, for live triage), and per-task demo commands.

Usage:
  python3 40k/tests/tools/generate_review_html.py
  open 40k/test_results/design_guidelines/review.html  # macOS
  xdg-open 40k/test_results/design_guidelines/review.html  # linux

The HTML is intentionally read-only with respect to .llm/todo.md — you
tick boxes in the browser to keep place, then mirror confirmed ticks
into .llm/todo.md via a normal text editor (the bottom-of-page export
button gives you the sed commands).
"""
from __future__ import annotations
import os
import re
import json
import sys
import base64
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
TODO_MD = REPO_ROOT / ".llm" / "todo.md"
ARTIFACT_DIR = REPO_ROOT / "40k" / "test_results" / "design_guidelines"
OUTPUT_HTML = ARTIFACT_DIR / "review.html"

# Tasks we ship for. Source of truth is .llm/todo.md task headers.
TASK_HEADER_RE = re.compile(r"^- \[(?P<state>[ x])\] \*\*(?P<id>T\d+) — (?P<title>[^\*]+)\*\*$")
TIER_B_HEADER_RE = re.compile(r"^\s+- \*\*Acceptance — Tier B")
TIER_B_ITEM_RE = re.compile(r"^    - \[(?P<state>[ x])\] (?P<text>.+)$")

# Demo commands per task. Hand-curated because not every task is fixture-
# driven; some need free interaction (T03, T31, T13).
DEMO_COMMANDS = {
    "T01": "godot --path 40k --scenario-file=tests/scenarios/visual/T01_uiconstants_present.json",
    "T02": "bash 40k/tests/run_scenarios.sh --visual  # 45/45 expected",
    "T03": "godot --path 40k  # then load co_pretrigger, enter movement phase, drag any model",
    "T04": "godot --path 40k --scenario-file=tests/scenarios/visual/T04_phase_bar.json",
    "T05": "godot --path 40k  # load co_pretrigger phase 8, select shooter, hover enemy",
    "T06": "godot --path 40k --scenario-file=tests/scenarios/visual/T06_weapon_order_panel.json",
    "T07": "godot --path 40k --scenario-file=tests/scenarios/visual/T07_terrain_cover_icons.json",
    "T08": "godot --path 40k --scenario-file=tests/scenarios/visual/T08_two_ring_token.json",
    "T09": "godot --path 40k --scenario-file=tests/scenarios/visual/T09_exhaustion_grayscale.json",
    "T10": "godot --path 40k  # load co_pretrigger phase 8, hold Tab",
    "T11": "godot --path 40k --scenario-file=tests/scenarios/visual/T11_los_line.json",
    "T12": "godot --path 40k  # load any fixture, compare with pre-T12 screenshots",
    "T13": "godot --path 40k  # load co_pretrigger, pan camera, press F",
    "T14": "godot --path 40k  # load co_pretrigger, select unit, Shift+F",
    "T15": "godot --path 40k --scenario-file=tests/scenarios/visual/T15_silhouettes.json",
    "T16": "godot --path 40k  # load co_pretrigger, zoom out below 0.6",
    "T17": "godot --path 40k --scenario-file=tests/scenarios/visual/T17_status_overflow.json",
    "T18": "godot --path 40k --scenario-file=tests/scenarios/visual/T18_wound_chip.json",
    "T19": "godot --path 40k  # load co_pretrigger, select unit, observe SlotRing pulse",
    "T20": "godot --path 40k --scenario-file=tests/scenarios/visual/T20_epic_challenge_panel.json",
    "T21": "godot --path 40k --scenario-file=tests/scenarios/visual/T21_wound_panel.json",
    "T22": "godot --path 40k --scenario-file=tests/scenarios/visual/T22_auto_zoom_decision.json",
    "T23": "godot --path 40k --scenario-file=tests/scenarios/visual/T23_end_phase_position.json",
    "T24": "godot --path 40k --scenario-file=tests/scenarios/visual/T24_substate_breadcrumb.json",
    "T25": "godot --path 40k --scenario-file=tests/scenarios/visual/T25_edge_tint.json",
    "T26": "godot --path 40k --scenario-file=tests/scenarios/visual/T26_phase_pill_clicks.json",
    "T27": "godot --path 40k --scenario-file=tests/scenarios/visual/T27_end_phase_refactor.json",
    "T28": "godot --path 40k --scenario-file=tests/scenarios/visual/T28_two_layer_range.json",
    "T29": "godot --path 40k --scenario-file=tests/scenarios/visual/T29_persistent_engagement.json",
    "T30": "godot --path 40k --scenario-file=tests/scenarios/visual/T30_charge_dashed_rings.json",
    "T31": "godot --path 40k  # load any fixture, press R, drag a line",
    "T32": "godot --path 40k  # load any fixture, hold L; release",
    "T33": "godot --path 40k  # resolve a shooting attack; observe dice surface",
    "T34": "godot --path 40k  # apply wounds; observe floating -NW / -N models",
    "T35": "godot --path 40k --scenario-file=tests/scenarios/visual/T35_roll_log.json",
    "T36": "godot --path 40k  # load co_pretrigger phase 8, click an enemy (should not fire); press ENTER",
    "T37": "godot --path 40k --scenario-file=tests/scenarios/visual/T37_roster_strip.json",
    "T38": "godot --path 40k --scenario-file=tests/scenarios/visual/T38_filter_chips.json",
    "T39": "godot --path 40k  # load co_pretrigger, select unit, press i",
    "T40": "godot --path 40k  # load co_pretrigger phase 8, select friendly, hover enemy",
    "T41": "godot --path 40k  # any fixture; eyeball that faction vs slot colors don't conflate",
    "T42": "godot --path 40k  # load fixture w/ Imperial Fists; hold Tab — yellow should be striped",
    "T43": "godot --path 40k  # walk each phase; count orange CTAs (target: 1 per phase)",
    "T44": "godot --path 40k  # exercise pulse, fade, slide; time the animations",
    "T45": "godot --path 40k --scenario-file=tests/scenarios/visual/T45_final_audit.json",
}

# Known-incomplete behaviors — Tier B items that WILL fail. Mirror of
# REVIEW_GUIDE.md so reviewers don't waste time investigating each.
KNOWN_GAPS = {
    "T06": "ESC dismissal not wired (Cancel button works; ESC binding missing in Main._input)",
    "T09": "Roster card dim not implemented — only TokenVisual modulate is wired",
    "T13": "Camera fit is instant — no tween animation",
    "T17": "Overflow chip is a static Label — no hover-expand behavior",
    "T20": "ESC dismissal not wired",
    "T21": "Commit button is a stub — no real allocation logic",
    "T36": "ENTER fires commit_targets() but doesn't trigger resolution downstream",
    "T42": "striped_pattern() exists but isn't applied to any overlay",
}


def parse_todo() -> list[dict]:
    """Walk .llm/todo.md and pull out per-task state + Tier B items."""
    tasks: list[dict] = []
    current: dict | None = None
    in_tier_b = False

    with TODO_MD.open() as f:
        for line in f:
            line = line.rstrip("\n")

            m = TASK_HEADER_RE.match(line)
            if m:
                if current is not None:
                    tasks.append(current)
                current = {
                    "id": m.group("id"),
                    "title": m.group("title").strip(),
                    "closed": m.group("state") == "x",
                    "tier_b": [],
                }
                in_tier_b = False
                continue

            if current is None:
                continue

            if TIER_B_HEADER_RE.match(line):
                in_tier_b = True
                continue

            if in_tier_b:
                m2 = TIER_B_ITEM_RE.match(line)
                if m2:
                    current["tier_b"].append({
                        "text": m2.group("text").strip(),
                        "ticked": m2.group("state") == "x",
                    })
                    continue
                # Tier B block ends at the next non-item line that isn't a continuation
                if line.strip() == "" or (line and not line.startswith("    ")):
                    in_tier_b = False

    if current is not None:
        tasks.append(current)

    # Filter to T01-T45 only (skip the foundation/quick-win heading block).
    tasks = [t for t in tasks if t["id"].startswith("T") and t["id"][1:].isdigit()]
    tasks.sort(key=lambda t: int(t["id"][1:]))
    return tasks


def find_screenshots(task_id: str) -> list[Path]:
    """Return Paths to all PNGs for this task, after-state first."""
    task_dir = ARTIFACT_DIR / task_id
    if not task_dir.is_dir():
        return []
    pngs = sorted(task_dir.glob("*.png"))
    def score(p: Path) -> int:
        name = p.name
        for tag in ("_after", "_open", "_drawn", "_p2_active", "_p1_active",
                   "_two_entries", "_movement", "_with_breadcrumb", "_overlay_on"):
            if tag in name:
                return 0
        return 1
    pngs.sort(key=score)
    return pngs


def png_as_data_uri(path: Path) -> str:
    """Inline a PNG as a base64 data URI so the HTML is fully self-contained."""
    with path.open("rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return f"data:image/png;base64,{b64}"


def render_html(tasks: list[dict]) -> str:
    closed_count = sum(1 for t in tasks if t["closed"])
    total = len(tasks)
    items_ticked = sum(1 for t in tasks for b in t["tier_b"] if b["ticked"])
    items_total = sum(len(t["tier_b"]) for t in tasks)

    parts: list[str] = []
    parts.append(f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>Tier B visual review — T01-T45</title>
<style>
  body {{ font-family: -apple-system, system-ui, sans-serif; max-width: 1100px;
         margin: 1em auto; padding: 0 1em; line-height: 1.5; }}
  h1 {{ border-bottom: 2px solid #333; padding-bottom: 0.3em; }}
  h2 {{ margin-top: 2em; padding-top: 0.5em; border-top: 1px solid #ccc; }}
  h2 .closed {{ color: #888; text-decoration: line-through; }}
  .meta {{ font-size: 0.9em; color: #666; }}
  .gap {{ background: #fee; border-left: 4px solid #c33; padding: 0.5em 1em;
          margin: 0.5em 0; }}
  .gap b {{ color: #c33; }}
  .demo {{ background: #f4f4f4; padding: 0.4em 0.8em; font-family: monospace;
           font-size: 0.85em; border-radius: 3px; user-select: all; }}
  ul.checklist {{ list-style: none; padding-left: 0.5em; }}
  ul.checklist li {{ margin: 0.3em 0; }}
  ul.checklist input {{ margin-right: 0.5em; transform: scale(1.2); }}
  ul.checklist li.preticked {{ color: #060; }}
  img.shot {{ max-width: 100%; border: 1px solid #888; display: block;
              margin: 0.5em 0; }}
  .nav {{ position: sticky; top: 0; background: #fff; border-bottom: 1px solid #ccc;
          padding: 0.5em; font-size: 0.85em; z-index: 10; }}
  .nav a {{ margin-right: 0.6em; }}
  .progress {{ background: #eee; height: 22px; border-radius: 4px; overflow: hidden; }}
  .progress > div {{ background: #4a4; height: 100%; }}
  .closed-section {{ opacity: 0.55; }}
</style></head>
<body>
<h1>Tier B visual review — T01–T45</h1>
<p class="meta">
  Cloud-session shipped <b>{total} tasks</b> with Tier A passing 45/45.
  Pre-pass closed <b>{closed_count}</b> tasks ({items_ticked}/{items_total} Tier B items).
  Walk through the remaining tasks below, exercising each in a windowed
  Godot session (commands inlined). Tick boxes in the browser to keep
  place, then mirror confirmed ticks to <code>.llm/todo.md</code> by hand.
</p>
<div class="progress"><div style="width: {(closed_count/total)*100:.0f}%"></div></div>

<div class="nav">
""")
    # TOC
    for t in tasks:
        cls = "closed" if t["closed"] else ""
        parts.append(f'<a class="{cls}" href="#{t["id"]}">{t["id"]}</a>')
    parts.append("</div>\n")

    for t in tasks:
        closed_cls = "closed-section" if t["closed"] else ""
        title_cls = "closed" if t["closed"] else ""
        parts.append(f'<section id="{t["id"]}" class="{closed_cls}">\n')
        parts.append(f'<h2><span class="{title_cls}">{t["id"]} — {t["title"]}</span></h2>\n')

        if t["id"] in KNOWN_GAPS:
            parts.append(
                f'<div class="gap"><b>Pre-known gap:</b> {KNOWN_GAPS[t["id"]]}'
                f' — file as {t["id"]}b during review, do not revert the parent commit.</div>\n'
            )

        cmd = DEMO_COMMANDS.get(t["id"], f"# no demo command registered for {t['id']}")
        parts.append(f'<p class="meta">Demo:</p>\n<div class="demo">{_html_escape(cmd)}</div>\n')

        shots = find_screenshots(t["id"])
        if shots:
            parts.append('<p class="meta">Cloud screenshot(s) (after-state first; embedded base64):</p>\n')
            # Cap at 2 embedded images per task to keep total HTML size sane.
            for shot in shots[:2]:
                uri = png_as_data_uri(shot)
                parts.append(
                    f'<img class="shot" src="{uri}" alt="{t["id"]} {shot.name}">\n'
                )
            if len(shots) > 2:
                parts.append(
                    f'<p class="meta"><i>+{len(shots)-2} more in '
                    f'<code>40k/test_results/design_guidelines/{t["id"]}/</code></i></p>\n'
                )

        if t["tier_b"]:
            parts.append('<p class="meta">Tier B checklist:</p>\n<ul class="checklist">\n')
            for i, b in enumerate(t["tier_b"]):
                pre = ' checked disabled' if b["ticked"] else ''
                cls = ' class="preticked"' if b["ticked"] else ''
                tag = " <small>(verified from artifacts)</small>" if b["ticked"] else ""
                parts.append(
                    f'<li{cls}><input type="checkbox" id="{t["id"]}_{i}"{pre}>'
                    f'<label for="{t["id"]}_{i}">{_html_escape(b["text"])}{tag}</label></li>\n'
                )
            parts.append('</ul>\n')
        else:
            parts.append('<p class="meta"><i>No Tier B items — Tier A only.</i></p>\n')

        parts.append('</section>\n')

    parts.append("""
<hr>
<h2>Exporting your ticks</h2>
<p>When done, open <code>.llm/todo.md</code> and flip <code>- [ ]</code> →
<code>- [x]</code> for items you ticked in this page. Commit as
<code>tick T## ...</code>. When every Tier B box is ticked, the design-
guidelines closure is complete.</p>
<p>Generator: <code>40k/tests/tools/generate_review_html.py</code> — re-run after editing
<code>.llm/todo.md</code> to refresh this page.</p>
</body></html>
""")
    return "".join(parts)


def _html_escape(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def main() -> int:
    if not TODO_MD.exists():
        print(f"ERROR: missing {TODO_MD}", file=sys.stderr)
        return 1
    tasks = parse_todo()
    if not tasks:
        print("ERROR: no tasks parsed from .llm/todo.md", file=sys.stderr)
        return 2
    html = render_html(tasks)
    OUTPUT_HTML.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_HTML.write_text(html)
    closed = sum(1 for t in tasks if t["closed"])
    items_ticked = sum(1 for t in tasks for b in t["tier_b"] if b["ticked"])
    items_total = sum(len(t["tier_b"]) for t in tasks)
    print(f"Wrote {OUTPUT_HTML.relative_to(REPO_ROOT)}")
    print(f"  Tasks: {closed}/{len(tasks)} fully closed")
    print(f"  Tier B items: {items_ticked}/{items_total} ticked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
