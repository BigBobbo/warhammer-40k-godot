#!/usr/bin/env python3
"""Post a loop critique/result to a GitHub PR as a comment.

The visual-regression loop produces several artefacts per run:
  - `<user_dir>/test_results/scenarios/goldens_report.json` (diff)
  - `<user_dir>/test_results/scenarios/critique.json` (critic critique)
  - `<user_dir>/test_results/scenarios/<scenario_id>.json` (scenario result)

This script formats those into a single Markdown PR comment and posts
it via the GitHub REST API. Designed to run from CI immediately after
the loop driver completes — the comment is what closes the feedback
loop between "loop ran" and "developer sees the result on their PR."

Auth: needs GITHUB_TOKEN with `pull_request:write` (the standard
GITHUB_TOKEN in GitHub Actions has this) or a PAT. Falls back to
printing the body to stdout if no token is set.

Usage:
  python3 scripts/loop/post_critique_to_pr.py \
    --scenario-id 367_designate_warlord \
    --pr 412 \
    --owner BigBobbo --repo warhammer-40k-godot \
    --user-dir /root/.local/share/godot/app_userdata/40k \
    [--fixer-sha <sha>]

  # Dry run — print body to stdout, no API call:
  python3 scripts/loop/post_critique_to_pr.py ... --dry-run

  # In CI, with $GITHUB_REPOSITORY (owner/repo) and $PR_NUMBER set:
  python3 scripts/loop/post_critique_to_pr.py \
    --scenario-id 367_designate_warlord \
    --user-dir $GITHUB_WORKSPACE/.user_dir
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from urllib import request, error


def _read_optional_json(path: Path) -> dict | list | None:
    if not path.is_file():
        return None
    try:
        with path.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        return None


def _format_diff_summary(report: dict) -> str:
    """Format goldens_report.json summary as a Markdown table."""
    if not report:
        return "_no diff report_"
    summary = report.get("summary", {})
    platform = report.get("platform", "unknown")
    lines = [
        f"**Platform**: `{platform}` &nbsp; "
        f"**Mode**: `{report.get('mode', 'diff')}`",
        "",
        "| Status | Count |",
        "| --- | ---: |",
        f"| match | {summary.get('match', 0)} |",
        f"| drift | {summary.get('drift', 0)} |",
        f"| missing_golden | {summary.get('missing_golden', 0)} |",
        f"| blessed | {summary.get('blessed', 0)} |",
        f"| skipped | {summary.get('skipped', 0)} |",
    ]
    drifted = summary.get("drifted_steps", [])
    if drifted:
        lines.append("")
        lines.append(f"**Drifted steps**: `{drifted}`")
        # Show per-tile distances for drifted steps
        results = report.get("results", [])
        drifted_results = [r for r in results
                           if r.get("step_idx") in drifted]
        if drifted_results:
            lines.append("")
            lines.append("<details><summary>Per-tile distances</summary>")
            lines.append("")
            lines.append("| step | act | hd_max | per_tile (3×3) |")
            lines.append("| ---: | --- | ---: | --- |")
            for r in drifted_results[:10]:  # cap at 10 to avoid bloat
                pt = r.get("per_tile_distances", [])
                pt_fmt = " ".join(f"{x:>2d}" for x in pt) if pt else "—"
                lines.append(
                    f"| {r.get('step_idx')} | `{r.get('act')}` | "
                    f"{r.get('hamming_distance', '?')} | `{pt_fmt}` |"
                )
            if len(drifted_results) > 10:
                lines.append(f"| ... | _and {len(drifted_results)-10} more_ "
                             f"| | |")
            lines.append("")
            lines.append("</details>")
    return "\n".join(lines)


def _format_critique(critique: list) -> str:
    """Format a critic-prompt-shaped JSON array as Markdown."""
    if not critique:
        return "_critic returned `[]` — no findings._"
    by_sev = {"high": [], "medium": [], "low": []}
    for entry in critique:
        sev = entry.get("severity", "low")
        by_sev.setdefault(sev, []).append(entry)
    lines = []
    for sev in ["high", "medium", "low"]:
        if not by_sev.get(sev):
            continue
        lines.append(f"**{sev.upper()}** ({len(by_sev[sev])})")
        lines.append("")
        for e in by_sev[sev][:20]:  # cap per-severity
            cat = e.get("category", "other")
            step = e.get("step_idx", "?")
            expected = e.get("expected", "")
            observed = e.get("observed", "")
            lines.append(f"- step {step} · `{cat}`")
            lines.append(f"  - expected: {expected}")
            lines.append(f"  - observed: {observed}")
            focus = e.get("suggested_focus_files", [])
            if focus:
                lines.append(f"  - focus: {', '.join(f'`{f}`' for f in focus)}")
        if len(by_sev[sev]) > 20:
            lines.append(f"- _… and {len(by_sev[sev])-20} more {sev} entries_")
        lines.append("")
    return "\n".join(lines)


def _build_comment(scenario_id: str, results: dict | None,
                   report: dict | None, critique: list | None,
                   fixer_sha: str | None) -> str:
    """Assemble the full PR comment body."""
    parts = []
    parts.append(f"## 🔁 Visual-regression loop — `{scenario_id}`")
    parts.append("")

    # Scenario result
    if results:
        passed = sum(1 for s in results.get("steps", [])
                     if s.get("pass"))
        total = len(results.get("steps", []))
        parts.append(f"**Scenario**: {passed}/{total} steps passed")
        parts.append("")

    # Diff summary
    parts.append("### Visual diff")
    parts.append(_format_diff_summary(report) if report else "_no report_")
    parts.append("")

    # Critique
    parts.append("### Critic findings")
    if critique is None:
        parts.append("_critic not invoked_")
    else:
        parts.append(_format_critique(critique))
    parts.append("")

    # Fixer
    if fixer_sha:
        parts.append("### Fixer commit")
        parts.append(f"`{fixer_sha}` — see the file change in the PR diff.")
        parts.append("")

    parts.append("---")
    parts.append("_Posted by `scripts/loop/post_critique_to_pr.py`. "
                 "Run details in CI artefacts._")
    return "\n".join(parts)


def _post_to_github(owner: str, repo: str, pr_number: int,
                    body: str, token: str) -> int:
    url = (f"https://api.github.com/repos/{owner}/{repo}"
           f"/issues/{pr_number}/comments")
    data = json.dumps({"body": body}).encode("utf-8")
    req = request.Request(url, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("Content-Type", "application/json")
    try:
        with request.urlopen(req) as resp:
            payload = json.loads(resp.read())
            print(f"[post_critique] posted: {payload.get('html_url')}")
            return 0
    except error.HTTPError as e:
        print(f"[post_critique] FAIL HTTP {e.code}: {e.read().decode()}",
              file=sys.stderr)
        return 1
    except error.URLError as e:
        print(f"[post_critique] FAIL URL: {e}", file=sys.stderr)
        return 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scenario-id", required=True)
    p.add_argument("--user-dir", required=True,
                   help="Godot user:// dir; the script reads "
                        "test_results/scenarios/* under this")
    p.add_argument("--pr", type=int, default=None,
                   help="PR number to comment on. If omitted, infer from "
                        "$PR_NUMBER or $GITHUB_REF.")
    p.add_argument("--owner", default=None,
                   help="repo owner. Defaults to $GITHUB_REPOSITORY's owner.")
    p.add_argument("--repo", default=None,
                   help="repo name. Defaults to $GITHUB_REPOSITORY's name.")
    p.add_argument("--fixer-sha", default=None,
                   help="optional fixer commit SHA to mention in the comment")
    p.add_argument("--dry-run", action="store_true",
                   help="print the body to stdout, do not call GitHub")
    args = p.parse_args()

    user_dir = Path(args.user_dir)
    results_dir = user_dir / "test_results" / "scenarios"

    results = _read_optional_json(
        results_dir / f"{args.scenario_id}.json")
    report = _read_optional_json(results_dir / "goldens_report.json")
    critique = _read_optional_json(results_dir / "critique.json")

    if (results is None and report is None and critique is None):
        print(f"[post_critique] FAIL no artefacts in {results_dir}",
              file=sys.stderr)
        return 2

    body = _build_comment(
        scenario_id=args.scenario_id,
        results=results if isinstance(results, dict) else None,
        report=report if isinstance(report, dict) else None,
        critique=critique if isinstance(critique, list) else None,
        fixer_sha=args.fixer_sha,
    )

    if args.dry_run:
        print(body)
        return 0

    # Resolve PR + owner/repo from env if not given
    pr_number = args.pr
    if pr_number is None:
        env_pr = os.environ.get("PR_NUMBER")
        if env_pr:
            pr_number = int(env_pr)

    owner = args.owner
    repo = args.repo
    if (not owner or not repo) and os.environ.get("GITHUB_REPOSITORY"):
        gh_repo = os.environ["GITHUB_REPOSITORY"]
        if "/" in gh_repo:
            o, r = gh_repo.split("/", 1)
            owner = owner or o
            repo = repo or r

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("[post_critique] no GITHUB_TOKEN set — printing body to "
              "stdout instead", file=sys.stderr)
        print(body)
        return 0

    if not (owner and repo and pr_number):
        print("[post_critique] FAIL need --owner/--repo/--pr or "
              "$GITHUB_REPOSITORY+$PR_NUMBER", file=sys.stderr)
        return 2

    return _post_to_github(owner, repo, pr_number, body, token)


if __name__ == "__main__":
    sys.exit(main())
