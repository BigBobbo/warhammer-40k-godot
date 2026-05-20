#!/usr/bin/env python3
"""Apply a Tier B review.json (from the browser HTML report) back to
.llm/todo.md and stage refinement tasks from the notes.

Usage:
  python3 40k/tests/tools/apply_review_ticks.py review.json

Round-trip flow:
  1. Reviewer opens review-*of5.html in browser, ticks boxes, fills notes
  2. Reviewer clicks "Download review.json"
  3. Reviewer sends review.json to the engineer
  4. Engineer runs this script
  5. .llm/todo.md gets the [x] flips; T##b refinement entries get appended
     at the bottom (one per task with non-empty notes); script prints a
     summary diff. Engineer reviews + commits.

The script is idempotent — running it twice with the same JSON yields
the same .llm/todo.md content.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from datetime import datetime

REPO_ROOT = Path(__file__).resolve().parents[3]
TODO_MD = REPO_ROOT / ".llm" / "todo.md"

TASK_HEADER_RE = re.compile(r"^(- \[)([ x])(\] \*\*)(T\d+) — ([^\*]+)\*\*$")
TIER_B_ITEM_RE = re.compile(r"^(    - \[)([ x])(\] )(.+)$")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: apply_review_ticks.py review.json", file=sys.stderr)
        return 2
    review = json.loads(Path(argv[1]).read_text())
    ticks: dict[str, dict[str, bool]] = review.get("ticks", {})
    notes: dict[str, str] = review.get("notes", {})

    # Coerce keys to int where they came in as strings (JSON dicts are str-keyed).
    ticks_int: dict[str, dict[int, bool]] = {
        t: {int(k): v for k, v in items.items()}
        for t, items in ticks.items()
    }

    lines = TODO_MD.read_text().splitlines()
    out: list[str] = []
    current_task: str | None = None
    tier_b_index: int = 0
    in_tier_b = False
    tier_b_header = re.compile(r"^\s+- \*\*Acceptance — Tier B")
    flips_per_task: dict[str, int] = {}
    full_close_tasks: list[str] = []
    # Track per-task box totals so we know when to flip the parent header.
    box_totals: dict[str, int] = {}
    box_ticked: dict[str, int] = {}

    for line in lines:
        m_task = TASK_HEADER_RE.match(line)
        if m_task:
            current_task = m_task.group(4)
            tier_b_index = 0
            in_tier_b = False
            out.append(line)
            continue
        if current_task and tier_b_header.match(line):
            in_tier_b = True
            out.append(line)
            continue
        if in_tier_b:
            m_item = TIER_B_ITEM_RE.match(line)
            if m_item:
                box_totals[current_task] = box_totals.get(current_task, 0) + 1
                was_ticked = m_item.group(2) == "x"
                should_tick = was_ticked or ticks_int.get(current_task, {}).get(tier_b_index, False)
                if should_tick:
                    box_ticked[current_task] = box_ticked.get(current_task, 0) + 1
                    if not was_ticked:
                        flips_per_task[current_task] = flips_per_task.get(current_task, 0) + 1
                    out.append(m_item.group(1) + "x" + m_item.group(3) + m_item.group(4))
                else:
                    out.append(line)
                tier_b_index += 1
                continue
            elif line.strip() == "" or (line and not line.startswith("    ")):
                in_tier_b = False
        out.append(line)

    # Second pass: flip task header [ ] -> [x] for tasks where all items ticked.
    final: list[str] = []
    for line in out:
        m_task = TASK_HEADER_RE.match(line)
        if m_task:
            task_id = m_task.group(4)
            total = box_totals.get(task_id, 0)
            ticked = box_ticked.get(task_id, 0)
            if total > 0 and ticked == total and m_task.group(2) == " ":
                full_close_tasks.append(task_id)
                line = f"{m_task.group(1)}x{m_task.group(3)}{task_id} — {m_task.group(5)}**"
        final.append(line)

    # Append T##b refinement stubs for any task with non-empty notes that
    # isn't already followed by a T##b entry.
    body = "\n".join(final) + "\n"
    refinement_stubs: list[str] = []
    existing_b_re = re.compile(r"^- \[ \] \*\*T(\d+)b — ", re.MULTILINE)
    existing_b_ids: set[str] = {f"T{m.group(1)}b" for m in existing_b_re.finditer(body)}
    for task_id, note in sorted(notes.items()):
        note_clean = (note or "").strip()
        if not note_clean:
            continue
        rid = f"{task_id}b"
        if rid in existing_b_ids:
            continue
        refinement_stubs.append(
            f"- [ ] **{rid} — Tier B refinement for {task_id}**\n"
            f"  - **Parent:** {task_id}\n"
            f"  - **Source:** Tier B review {review.get('exported_at', '')[:10] or datetime.now().date().isoformat()}\n"
            f"  - **Issue (reviewer note):** {note_clean}\n"
            f"  - **Acceptance — Tier A:**\n"
            f"    - tbd — depends on fix scope\n"
            f"  - **Acceptance — Tier B:**\n"
            f"    - [ ] Reviewer confirms the original {task_id} Tier B item now passes\n"
        )

    if refinement_stubs:
        body = body.rstrip() + "\n\n## Tier B refinement tasks (from review feedback)\n\n" + "\n".join(refinement_stubs) + "\n"

    TODO_MD.write_text(body)

    # Summary
    total_ticks = sum(flips_per_task.values())
    print(f"Applied {total_ticks} new Tier B ticks across {len(flips_per_task)} tasks.")
    if full_close_tasks:
        print(f"Newly-closed tasks ({len(full_close_tasks)}): {', '.join(full_close_tasks)}")
    if refinement_stubs:
        print(f"Appended {len(refinement_stubs)} T##b refinement stub(s).")
    print()
    print("Diff preview:")
    import subprocess
    subprocess.run(["git", "-C", str(REPO_ROOT), "diff", "--stat", ".llm/todo.md"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
