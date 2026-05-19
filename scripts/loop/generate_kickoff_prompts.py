#!/usr/bin/env python3
"""Generate per-scenario kickoff prompts for the parallel cloud-session sweep.

Pairs with `scripts/loop/kickoff_parallel.md` and
`scripts/loop/list_scenarios_by_priority.py`. Emits one self-contained
prompt per scenario — ready to paste into a Claude Code web-UI session.

Modes:
  --stdout      print all prompts to stdout separated by --- markers (default)
  --dir <path>  write each prompt to <path>/<scenario_id>.prompt.txt
  --top N       limit to top-N priority scenarios
  --include <p> only include scenario paths matching glob pattern (repeatable)

Usage:
  # All scenarios, paste from stdout
  python3 scripts/loop/generate_kickoff_prompts.py

  # Top 10 to a directory
  python3 scripts/loop/generate_kickoff_prompts.py --top 10 --dir /tmp/loop_prompts

  # Only fight-phase scenarios
  python3 scripts/loop/generate_kickoff_prompts.py --include '*fight*'

The operator's workflow:
  1. Run this script with --dir <path>.
  2. Open <path> — there's one .prompt.txt per scenario.
  3. For each scenario you want to run, open a new Claude Code web-UI
     session against this repo, paste the prompt body, send. Each
     session is isolated.
  4. Track the resulting PRs (each session opens its own PR on a
     `loop/<scenario>-<ts>` branch).
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys
from pathlib import Path

PROMPT_TEMPLATE = """You are a Claude Code session driving the visual-regression loop
for ONE scenario. Read `scripts/loop/playbook.md` and follow it
end-to-end for the scenario below. The playbook covers the per-scenario
loop, critic/fixer subagent invocation, anti-cycle, and halt taxonomy.

## Scenario

  SCENARIO_PATH = "{scenario_path}"
  SCENARIO_ID   = "{scenario_id}"

## Constraints (mirror `.llm/visual-regression-loop-plan.md`)

- LOOP_MAX_ITERATIONS = 4
- max diff per iteration = 200 lines (enforced by `.githooks/pre-commit-loop`)
- max wall clock = 30 min
- branch: `loop/{scenario_id}-<unix_timestamp>`
- open a PR against `main` when the critic returns `[]`
- if you halt for `cycle_detected` or `max_iterations`, open the PR
  anyway with the halt reason in the title and a diagnostic in the
  body — humans need visibility into stuck scenarios

## Hard rules

- Per `scripts/loop/fixer_prompt.md` caps, do NOT edit:
  - `40k/tests/scenarios/**` (scenarios are immutable inside the loop)
  - `40k/autoloads/GameState.gd`
  - `40k/scripts/SaveLoadManager.gd`
  - `40k/data/**`
- Stay inside `40k/scripts/` and `40k/scenes/` unless the critique
  evidence points elsewhere AND you justify it in the commit body.
- Commit messages must include a `Justification:` paragraph — the
  pre-commit hook rejects empty justifications.

## Start

  bash scripts/loop/run_one_scenario_loop.sh {scenario_path}

Proceed from there per the playbook. Do NOT exceed any cap.
"""


def _list_scenarios(repo_root: Path, top: int | None, includes: list[str]) -> list[Path]:
    """Run list_scenarios_by_priority.py --paths and return the paths in
    priority order, optionally filtered."""
    lister = repo_root / "scripts" / "loop" / "list_scenarios_by_priority.py"
    if not lister.exists():
        # Fallback: globs of sp/*.json sorted alphabetically
        sp_dir = repo_root / "40k" / "tests" / "scenarios" / "sp"
        return sorted(sp_dir.glob("*.json"))

    result = subprocess.run(
        [sys.executable, str(lister), "--paths"],
        capture_output=True, text=True, cwd=str(repo_root))
    if result.returncode != 0:
        print(f"[gen_kickoff] WARN: priority lister failed: {result.stderr}",
              file=sys.stderr)
        sp_dir = repo_root / "40k" / "tests" / "scenarios" / "sp"
        paths = sorted(sp_dir.glob("*.json"))
    else:
        paths = [Path(line.strip()) for line in result.stdout.splitlines()
                 if line.strip()]

    if includes:
        paths = [p for p in paths
                 if any(fnmatch.fnmatch(str(p), pat) for pat in includes)]

    if top:
        paths = paths[:top]

    return paths


def _build_prompt(scenario_path: Path, repo_root: Path) -> tuple[str, str]:
    """Return (scenario_id, prompt_text)."""
    rel = scenario_path.relative_to(repo_root) if scenario_path.is_absolute() \
          else scenario_path
    scenario_id = scenario_path.stem
    prompt = PROMPT_TEMPLATE.format(
        scenario_path=str(rel),
        scenario_id=scenario_id,
    )
    return (scenario_id, prompt)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--stdout", action="store_true", default=True)
    p.add_argument("--dir", default=None,
                   help="write prompts to this directory instead of stdout")
    p.add_argument("--top", type=int, default=None,
                   help="only emit the top-N priority scenarios")
    p.add_argument("--include", action="append", default=[],
                   help="only include scenario paths matching this glob "
                        "(repeatable)")
    args = p.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    scenarios = _list_scenarios(repo_root, args.top, args.include)
    if not scenarios:
        print("[gen_kickoff] FAIL: no scenarios matched", file=sys.stderr)
        return 2

    if args.dir:
        outdir = Path(args.dir)
        outdir.mkdir(parents=True, exist_ok=True)
        written = []
        for sp in scenarios:
            sid, prompt = _build_prompt(sp, repo_root)
            fp = outdir / f"{sid}.prompt.txt"
            fp.write_text(prompt)
            written.append(fp)
        print(f"[gen_kickoff] wrote {len(written)} prompt files to {outdir}/")
        print("\nNext steps:")
        print("  1. Open each .prompt.txt and copy its body.")
        print("  2. In the Claude Code web UI, start a new session against")
        print("     this repo, paste the prompt, send.")
        print("  3. Each session opens its own PR. Track them as they land.")
        return 0

    # stdout mode
    for sp in scenarios:
        sid, prompt = _build_prompt(sp, repo_root)
        print(f"--- {sid} ---")
        print(prompt)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
