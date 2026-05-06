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

The gate fires only when ALL of the following are true in the current turn:
  - The assistant text contains a verification claim ("PASSED", "verified",
    "complete", checkmark, etc.).
  - The assistant text mentions a T-NNN task id.
  - The assistant ALSO produced a code change in this turn (Edit / Write /
    MultiEdit / NotebookEdit, or a Bash `git commit`). Recommendations,
    summaries, and meta discussion of past audit work do NOT trip the gate.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
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

# Tools whose presence in this turn marks the response as "code-changing".
# The gate only applies to code-changing turns; pure summary / recommendation
# / Q&A turns are not gated even if they reference T-NNN tasks with verb
# verification language.
_CODE_CHANGE_TOOLS = {
    "Edit",
    "Write",
    "MultiEdit",
    "NotebookEdit",
}

# Bash commands that count as code-changing because they finalize a change
# (commit) or apply edits via a CLI. Matched against the command string.
_CODE_CHANGE_BASH_PATTERNS = [
    re.compile(r"\bgit\s+commit\b"),
    re.compile(r"\bgit\s+(?:add|rm|mv|restore|reset)\b"),
    re.compile(r"\bgit\s+(?:apply|am|cherry-pick|rebase|merge)\b"),
]

# Bridge fallback transport: when the MCP stdio handshake gets dropped (e.g.
# after auto-compact), the assistant can still drive the same Godot addon
# directly over its TCP socket. Bash commands matching both substrings are
# treated as equivalent live evidence.
_BRIDGE_FALLBACK_PATTERNS = [
    # nc / curl / printf to 127.0.0.1:9080 (runtime) or :9081 (editor) with
    # the capture_screenshot command in the JSON body.
    (re.compile(r"capture_screenshot"), re.compile(r"\b(9080|9081)\b")),
]

# Final fallback: if a brand-new screenshot file lands in the canonical audit
# screenshot tree during this assistant turn, accept that as evidence even
# without an explicit tool_use match (defensive against future tool renames /
# transport quirks).
_AUDIT_SCREENSHOT_GLOB = (
    Path(os.environ.get("CLAUDE_PROJECT_DIR", "."))
    / "40k"
    / "test_results"
    / "audit_2026_05"
)


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


def _last_user_timestamp(rows: list[dict]) -> float:
    """Unix epoch seconds of the last true user message. Falls back to
    "10 minutes ago" if no parseable timestamp is found, so the on-disk
    screenshot fallback still has a reasonable window to scan."""
    last_ts: float = 0.0
    for row in rows:
        if not _is_true_user_message(row):
            continue
        ts_str = row.get("timestamp", "")
        if not ts_str:
            continue
        try:
            # ISO 8601 with trailing Z — datetime.fromisoformat needs +00:00
            normalized = ts_str.replace("Z", "+00:00")
            dt = datetime.fromisoformat(normalized)
            last_ts = dt.astimezone(timezone.utc).timestamp()
        except ValueError:
            continue
    if last_ts == 0.0:
        # Fall back to a 10-minute window from now so the disk-scan fallback
        # still works on transcripts without timestamps.
        import time as _time
        last_ts = _time.time() - 600.0
    return last_ts


def _bash_command_matches_bridge(cmd: str) -> bool:
    """True iff a Bash invocation looks like a direct call to the Godot MCP
    bridge's TCP transport (i.e. it carries the capture_screenshot command
    addressed at port 9080 or 9081)."""
    if not cmd:
        return False
    for pat_cmd, pat_port in _BRIDGE_FALLBACK_PATTERNS:
        if pat_cmd.search(cmd) and pat_port.search(cmd):
            return True
    return False


def _bash_command_changes_code(cmd: str) -> bool:
    """True iff a Bash invocation finalizes or applies code changes (commit,
    add, apply, etc.). Used to decide whether the current turn is a
    'code-changing' turn that the audit gate applies to."""
    if not cmd:
        return False
    for pat in _CODE_CHANGE_BASH_PATTERNS:
        if pat.search(cmd):
            return True
    return False


def _new_audit_screenshot_since(ts: float) -> bool:
    """True iff at least one .png file under the audit screenshot tree has
    an mtime >= the given epoch timestamp. Cheap to scan: we expect at most
    a few hundred files even after months of audits."""
    root = _AUDIT_SCREENSHOT_GLOB
    if not root.exists():
        return False
    try:
        for png in root.rglob("screenshots/*.png"):
            try:
                if png.stat().st_mtime >= ts:
                    return True
            except OSError:
                continue
    except OSError:
        return False
    return False


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
    turn_start_ts = _last_user_timestamp(rows)

    claimed_tasks: set[str] = set()
    # Three independent ways to satisfy the gate:
    #   1. The MCP-named tool fired (preferred path).
    #   2. A Bash call drove the bridge's TCP socket directly (works when
    #      the MCP transport is dropped, e.g. post-compact).
    #   3. A new screenshot file landed in the canonical audit dir during
    #      this turn (defensive against future tool renames / new transports).
    saw_evidence = False
    evidence_kind = ""
    # The gate only applies to code-changing turns. Recommendation /
    # summary turns are unaffected even if they reference task ids with
    # verification language.
    code_changed_this_turn = False

    for kind, payload in _iter_assistant_content(turn_rows):
        if kind == "text":
            if _has_verification_claim(payload):
                for m in _TASK_ID_PATTERN.finditer(payload):
                    claimed_tasks.add(m.group(0))
        elif kind == "tool_use":
            name = payload.get("name", "")
            if name in _LIVE_EVIDENCE_TOOLS:
                saw_evidence = True
                evidence_kind = "mcp_tool"
            if name in _CODE_CHANGE_TOOLS:
                code_changed_this_turn = True
            elif name == "Bash":
                cmd = (payload.get("input", {}) or {}).get("command", "")
                if _bash_command_matches_bridge(cmd):
                    saw_evidence = True
                    evidence_kind = "bash_tcp"
                if _bash_command_changes_code(cmd):
                    code_changed_this_turn = True

    if not claimed_tasks:
        return 0  # no task verification claim → not gated
    if not code_changed_this_turn:
        # Recommendations, summaries, and meta discussion of past audit
        # work do not require fresh live evidence — only turns that
        # actually edit / commit code do.
        sys.stderr.write(
            "[audit-screenshot-gate] OK (no code change in this turn)\n"
        )
        return 0

    if not saw_evidence and _new_audit_screenshot_since(turn_start_ts):
        saw_evidence = True
        evidence_kind = "new_png_on_disk"

    if saw_evidence:
        # Helpful breadcrumb to stderr so we can audit *which* path satisfied
        # the gate during post-mortems. Doesn't show to the user; only lands
        # in Claude Code's hook logs.
        sys.stderr.write(
            f"[audit-screenshot-gate] OK ({evidence_kind})\n"
        )
        return 0

    # Block: claim without live evidence.
    tasks_str = ", ".join(sorted(claimed_tasks))
    msg = (
        "[audit-screenshot-gate] Stop blocked.\n"
        f"You claimed verification for task(s): {tasks_str}\n"
        "but did NOT produce live evidence in this response. Acceptable "
        "evidence is any of:\n"
        "  - a `mcp__godot-mcp-bridge__capture_screenshot` tool call,\n"
        "  - a Bash call that talks to the bridge directly "
        "(127.0.0.1:9080 or :9081 with capture_screenshot in the body),\n"
        "  - a new .png file written under "
        "40k/test_results/audit_2026_05/session_*/screenshots/ during this "
        "turn.\n\n"
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
