#!/usr/bin/env python3
"""Parse `github_issues_drafts.md` and file each issue via `gh issue create`.

Emits `filed_issues.md` mapping draft alias (A1-1, A1-2, ...) → issue number + URL.
Exits non-zero if any single creation fails (no rollback — manually close & retry).
"""
from __future__ import annotations
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional, Tuple

DRAFTS = Path(__file__).parent / "github_issues_drafts.md"
OUT = Path(__file__).parent / "filed_issues.md"

# Section pattern: ### A<X>-<N>. <title>
SECTION = re.compile(r"^### (A\d-\d+)\. (.+)$", re.MULTILINE)
# Labels line: **Labels:** `a`, `b`, ...
LABELS = re.compile(r"^\*\*Labels:\*\* (.+)$", re.MULTILINE)
# Body code-fence
BODY_FENCE = re.compile(r"^```\s*$", re.MULTILINE)


def parse_drafts(text: str) -> list[dict]:
    """Walk the drafts file extracting (alias, title, labels, body) per issue."""
    issues: list[dict] = []
    matches = list(SECTION.finditer(text))
    for i, m in enumerate(matches):
        alias = m.group(1)
        title = m.group(2).strip()
        # Section content runs from end of this match to start of next ### A
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        section = text[start:end]

        # Labels
        lm = LABELS.search(section)
        if not lm:
            print(f"[WARN] {alias}: no Labels line found, skipping", file=sys.stderr)
            continue
        labels_raw = lm.group(1)
        labels = [l.strip().strip("`") for l in labels_raw.split(",")]
        labels.append("audit_2026_launch")  # All Path A issues get this

        # Body — between first and second ``` after the labels line
        post_labels = section[lm.end():]
        fences = list(BODY_FENCE.finditer(post_labels))
        if len(fences) < 2:
            print(f"[WARN] {alias}: fewer than 2 ``` fences, skipping", file=sys.stderr)
            continue
        body_start = fences[0].end()
        body_end = fences[1].start()
        body = post_labels[body_start:body_end].strip("\n")

        issues.append({
            "alias": alias,
            "title": title,
            "labels": labels,
            "body": body,
        })
    return issues


def file_one(issue: dict) -> Optional[Tuple[str, str]]:
    """Call `gh issue create` and return (number, url). None on failure."""
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(issue["body"])
        body_path = fh.name

    cmd = [
        "gh", "issue", "create",
        "--title", issue["title"],
        "--body-file", body_path,
    ]
    for label in issue["labels"]:
        cmd.extend(["--label", label])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    finally:
        Path(body_path).unlink(missing_ok=True)

    if result.returncode != 0:
        print(f"[FAIL] {issue['alias']}: {result.stderr.strip()}", file=sys.stderr)
        return None

    url = result.stdout.strip()
    # URL like https://github.com/BigBobbo/warhammer-40k-godot/issues/363
    num = url.rsplit("/", 1)[-1]
    return num, url


def main() -> int:
    text = DRAFTS.read_text(encoding="utf-8")
    issues = parse_drafts(text)
    print(f"Parsed {len(issues)} issues from drafts.")

    results: list[dict] = []
    for issue in issues:
        out = file_one(issue)
        if out is None:
            print(f"[STOP] aborting on {issue['alias']}; "
                  f"{len(results)} already filed.", file=sys.stderr)
            break
        num, url = out
        print(f"  {issue['alias']:>6} → #{num}  {issue['title'][:60]}")
        results.append({**issue, "number": num, "url": url})

    # Write mapping
    lines = ["# Filed issues (2026-05-06 launch audit, Path A)\n"]
    lines.append(f"\n**Filed {len(results)} of {len(issues)} drafts.**\n")
    lines.append("\n| Alias | Issue | Title |\n|---|---|---|\n")
    for r in results:
        lines.append(f"| {r['alias']} | [#{r['number']}]({r['url']}) | {r['title']} |\n")
    OUT.write_text("".join(lines))
    print(f"\nWrote {OUT}")

    return 0 if len(results) == len(issues) else 1


if __name__ == "__main__":
    sys.exit(main())
