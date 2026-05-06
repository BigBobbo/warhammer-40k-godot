#!/usr/bin/env python3
"""
Stop hook: blocks the assistant from claiming audit-task verification ("PASSED",
"verified", "complete") for a T-NNN task without having captured a screenshot
via the godot-mcp-bridge in the same response window.

Wired up in `.claude/settings.local.json` under `hooks.Stop`. Receives the
event JSON on stdin (with a `transcript_path` key); reads the JSONL transcript,
finds all assistant content since the last user message, and applies the
gate.

Exit codes:
  0 — allow stop
  2 — block; stderr is shown to the assistant as a system reminder

The gate is intentionally narrow: it only fires when BOTH a verification claim
and a `T-NNN`/`T-NNNa` task ID appear in the assistant's recent text content.
General responses are unaffected.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


# Verification language. Matches whole words case-insensitively, plus the
# checkmark glyph. Tweak here if false positives crop up.
_VERIFICATION_PATTERNS = [
    re.compile(r"\bPASSED\b"),
    re.compile(r"\b\d+/\d+\s+PASS\b", re.IGNORECASE),
    re.compile(r"\bpassed\b", re.IGNORECASE),
    re.compile(r"\bverified\b", re.IGNORECASE),
    re.compile(r"\b(green|all green)\b", re.IGNORECASE),
    re.compile(r"✅"),
    re.compile(r"\b(complete|completed)\b", re.IGNORECASE),
]

# Audit task IDs: T-001 ... T-999 with optional lowercase suffix (T-029a).
_TASK_ID_PATTERN = re.compile(r"\bT-\d{3}[a-z]?\b")

# MCP bridge tool name(s) that constitute live evidence.
_LIVE_EVIDENCE_TOOLS = {
    "mcp__godot-mcp-bridge__capture_screenshot",
}


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
    """Distinguish a real user prompt from a tool_result row.

    Transcripts store tool_result blocks inside `type: "user"` rows because
    that is the OpenAI/Anthropic role-tagging convention. A naive scan that
    treats every type=="user" as a turn boundary will exclude the tool_use
    calls that the assistant just made (the tool_use is in the previous
    assistant row; the tool_result row is what comes after the boundary).

    A real user message has either:
      - a string content field, OR
      - a content list whose blocks are NOT tool_result blocks.
    """
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
        # Empty content with no blocks is treated as a synthetic / non-user
        # event (system reminder etc.). Don't gate on those either.
        if len(content) == 0:
            return False
        return True
    return False


def _split_last_turn(rows: list[dict]) -> list[dict]:
    """Return rows from the last *true* user message to the end (i.e. the
    current assistant turn the Stop hook is gating). Tool_result rows masquerade
    as type=="user" in transcripts; this splitter ignores them."""
    last_user_idx = -1
    for i, row in enumerate(rows):
        if _is_true_user_message(row):
            last_user_idx = i
    return rows[last_user_idx + 1 :] if last_user_idx >= 0 else rows


def _iter_assistant_content(turn_rows: list[dict]):
    """Yield (kind, payload) for each content block in assistant messages.

    kind ∈ {"text", "tool_use"}; payload is the text string or the tool dict.
    """
    for row in turn_rows:
        if row.get("type") != "assistant":
            continue
        msg = row.get("message", {}) or {}
        content = msg.get("content", []) or []
        if isinstance(content, str):
            yield ("text", content)
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text":
                yield ("text", block.get("text", "") or "")
            elif btype == "tool_use":
                yield ("tool_use", block)


def _has_verification_claim(text: str) -> bool:
    return any(p.search(text) for p in _VERIFICATION_PATTERNS)


def _mentions_task(text: str) -> bool:
    return _TASK_ID_PATTERN.search(text) is not None


def main() -> int:
    event = _read_event()
    rows = _read_transcript(event.get("transcript_path", ""))
    if not rows:
        return 0  # nothing to gate
    turn_rows = _split_last_turn(rows)

    claimed_tasks: set[str] = set()
    saw_screenshot_call = False
    full_text_blob: list[str] = []

    for kind, payload in _iter_assistant_content(turn_rows):
        if kind == "text":
            text = payload
            full_text_blob.append(text)
            if _has_verification_claim(text):
                for m in _TASK_ID_PATTERN.finditer(text):
                    claimed_tasks.add(m.group(0))
        elif kind == "tool_use":
            name = payload.get("name", "")
            if name in _LIVE_EVIDENCE_TOOLS:
                saw_screenshot_call = True

    if not claimed_tasks:
        return 0  # no task verification claim → not gated

    if saw_screenshot_call:
        return 0  # claim ∧ live evidence → fine

    # Block: claim without live evidence.
    tasks_str = ", ".join(sorted(claimed_tasks))
    msg = (
        "[audit-screenshot-gate] Stop blocked.\n"
        f"You claimed verification for task(s): {tasks_str}\n"
        "but did NOT call mcp__godot-mcp-bridge__capture_screenshot in this "
        "response. The CLAUDE.md project rule and feedback_mcp_bridge_required "
        "memory both require that audit-task fixes be verified live via the "
        "MCP bridge with a screenshot captured to "
        "40k/test_results/audit_2026_05/session_*/screenshots/.\n\n"
        "Either:\n"
        "  (a) drive the live walkthrough now via play_main_scene → load "
        "fixture → dispatch_action → capture_screenshot, or\n"
        "  (b) if a hard blocker prevents the bridge from running, surface "
        "it explicitly as 'BLOCKED: <reason>' and stop claiming the task is "
        "verified.\n\n"
        "Headless .gd tests alone do NOT satisfy the verification rule for "
        "audit-task fixes — see feedback_mcp_bridge_required.md."
    )
    sys.stderr.write(msg)
    return 2


if __name__ == "__main__":
    sys.exit(main())
