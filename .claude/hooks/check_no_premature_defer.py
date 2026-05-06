#!/usr/bin/env python3
"""
Stop hook: blocks the assistant from shipping a "tasks I deliberately did NOT
attempt" rationalization document when the user asked for thorough work.

Wired up in `.claude/settings.local.json` under `hooks.Stop` alongside
check_audit_screenshots.py. Receives the event JSON on stdin (with a
`transcript_path` key); reads the JSONL transcript and inspects the assistant's
content since the last user message.

Gate fires when:
  (1) The assistant's text contains a "scope-defer" phrase from
      _DEFER_PATTERNS (very specific phrasing that almost only appears in the
      rationalization-document failure mode), AND
  (2) There is NO accompanying `BLOCKED: <something>` line within the same
      response (which is the user-approved way to surface a real blocker), AND
  (3) The user's most recent message did NOT explicitly authorize deferral
      (e.g. "skip", "defer", "scope down", "leave for later").

Exit codes:
  0 — allow stop
  2 — block; stderr is shown to the assistant as a system reminder
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


# Specific phrasing that signals work-avoidance rationalization, not legitimate
# scope discussion. Conservative — these phrases rarely appear except in the
# failure mode this hook exists to prevent.
_DEFER_PATTERNS = [
    re.compile(r"deliberately did NOT", re.IGNORECASE),
    re.compile(r"deliberately did not attempt", re.IGNORECASE),
    re.compile(r"\bdid NOT attempt\b"),
    re.compile(r"out of scope this session", re.IGNORECASE),
    re.compile(r"deferred to a future session", re.IGNORECASE),
    re.compile(r"too large for (one|this) session", re.IGNORECASE),
    re.compile(r"too big for (one|this) session", re.IGNORECASE),
    re.compile(r"multi-day architectural", re.IGNORECASE),
    re.compile(r"tasks I (deliberately |)did(\s+not| not) attempt", re.IGNORECASE),
    re.compile(r"\bDeferred to follow[- ]up\b", re.IGNORECASE),
]

# A BLOCKED surfacing — paired with a defer phrase, this is the *correct*
# surface and should not be blocked.
_BLOCKED_PATTERN = re.compile(
    r"\bBLOCKED\s*[:\-—]\s*\S",
    re.IGNORECASE,
)

# User-authorized deferral language. If the user used these in their most
# recent message, the gate releases.
_USER_DEFER_PERMISSIONS = [
    re.compile(r"\b(skip|defer|deprioritise|deprioritize|scope down|out of scope|leave for later|drop)\b", re.IGNORECASE),
]


def _read_event() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def _read_transcript(path_str: str) -> list[dict]:
    if not path_str:
        return []
    p = Path(path_str)
    if not p.exists():
        return []
    rows: list[dict] = []
    with p.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def _is_true_user_message(row: dict) -> bool:
    """Distinguish a real user prompt from a tool_result row. Tool_result blocks
    masquerade as type=="user" in transcripts; treating them as turn boundaries
    incorrectly excludes the assistant's tool_use calls."""
    if row.get("type") != "user":
        return False
    msg = row.get("message", {}) or {}
    content = msg.get("content", "")
    if isinstance(content, str):
        return content.strip() != ""
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                return False
        if len(content) == 0:
            return False
        return True
    return False


def _split_last_turn(rows: list[dict]) -> tuple[dict | None, list[dict]]:
    """Return (last_user_message, rows_since_last_user_message). Tool_result
    rows are NOT considered user messages."""
    last_user_idx = -1
    for i, row in enumerate(rows):
        if _is_true_user_message(row):
            last_user_idx = i
    last_user = rows[last_user_idx] if last_user_idx >= 0 else None
    after = rows[last_user_idx + 1 :] if last_user_idx >= 0 else rows
    return last_user, after


def _user_text(user_row: dict | None) -> str:
    if not user_row:
        return ""
    msg = user_row.get("message", {}) or {}
    content = msg.get("content", "")
    if isinstance(content, str):
        return content
    out: list[str] = []
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "text":
            out.append(block.get("text", "") or "")
        elif isinstance(block, str):
            out.append(block)
    return "\n".join(out)


def _assistant_text(turn_rows: list[dict]) -> str:
    out: list[str] = []
    for row in turn_rows:
        if row.get("type") != "assistant":
            continue
        msg = row.get("message", {}) or {}
        content = msg.get("content", []) or []
        if isinstance(content, str):
            out.append(content)
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                out.append(block.get("text", "") or "")
    return "\n".join(out)


def _user_authorized_deferral(text: str) -> bool:
    return any(p.search(text) for p in _USER_DEFER_PERMISSIONS)


def _find_defer_hits(text: str) -> list[str]:
    hits: list[str] = []
    for p in _DEFER_PATTERNS:
        for m in p.finditer(text):
            hits.append(m.group(0))
    return hits


def main() -> int:
    event = _read_event()
    rows = _read_transcript(event.get("transcript_path", ""))
    if not rows:
        return 0

    user_row, turn_rows = _split_last_turn(rows)
    user_text = _user_text(user_row)
    asst_text = _assistant_text(turn_rows)

    if not asst_text:
        return 0

    defer_hits = _find_defer_hits(asst_text)
    if not defer_hits:
        return 0  # no scope-defer language → fine

    # If the response also surfaces an explicit BLOCKED, that is the
    # user-approved channel for surfacing a real obstacle — allow it.
    if _BLOCKED_PATTERN.search(asst_text):
        return 0

    # If the user explicitly authorized deferral in this turn, allow it.
    if _user_authorized_deferral(user_text):
        return 0

    sample = ", ".join(sorted(set(defer_hits))[:5])
    msg = (
        "[premature-defer-gate] Stop blocked.\n"
        f"Your response contains scope-defer phrasing: {sample}\n"
        "but the user did NOT authorize deferral in this turn, and you did "
        "not surface an explicit `BLOCKED: <specific reason>` line for any "
        "of the items being deferred.\n\n"
        "When the user asks for thorough audit-task work (\"work through\", "
        "\"in order\", \"high effort\"), you do not get to triage which tasks "
        "are too big on your own authority. Attempt each task; if you "
        "genuinely cannot finish one, surface 'BLOCKED: <specific concrete "
        "obstacle>' and move to the next.\n\n"
        "Either:\n"
        "  (a) remove the scope-defer phrasing and actually attempt the "
        "tasks, or\n"
        "  (b) for each item you cannot finish, replace the defer phrasing "
        "with `BLOCKED: <specific reason I hit while attempting>`.\n\n"
        "See feedback_no_pre_emptive_scoping.md."
    )
    sys.stderr.write(msg)
    return 2


if __name__ == "__main__":
    sys.exit(main())
