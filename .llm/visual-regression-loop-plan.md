# Visual-regression sweep loop — design doc

Living document. Captures the design for the autonomous play → screenshot →
critique → fix → repeat loop. Successor to the deferred items in
`.llm/scaled-testing-plan.md` ("Multi-Claude parallel orchestration",
"Visual-diff perceptual screenshot harness"). Reference from
`SESSION_PLAYBOOK.md` once Phase 2 lands.

## Goals

1. **Catch silent UI regressions** across the existing 25 single-player
   scenarios. The headless+windowed scenario gate already proves the
   *engine* accepts an action; this loop proves the *rendered frame* still
   looks right.
2. **Per-scenario isolation.** One cloud Claude container per scenario.
   No shared workspace, no cross-contamination, parallel by default.
3. **One PR per scenario-fix.** Small, reviewable, bisectable. The PR
   title carries the critique; the branch is `loop/<scenario>-<timestamp>`.
4. **Mechanical caps.** Diff size, restricted paths, max iterations,
   scenarios are immutable inside the loop. Open-ended self-improvement
   loops drift; bounded ones converge.
5. **Critic ≠ fixer.** Two subagents with disjoint tool sets — the critic
   never sees source code, the fixer never sees the screenshot directly
   (only the structured critique).

## Non-goals

- Free-roam exploratory play. (Considered in the design discussion; deferred
  — false-positive rate is too high until the regression sweep is mature.)
- AI-vs-AI balance tuning. The legacy `ai_fix_loop.sh` covers that and is
  Mac-pinned by design.
- Replacing `run_scenarios.sh` or the existing scenario JSONs. This loop
  *consumes* them — it never edits them.

## Architecture

### Per-scenario cloud session lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│  Cloud Claude container for scenario X (e.g. 376_da_jump_bounds)     │
│                                                                       │
│  ┌──────────────┐                                                    │
│  │ 0. Preflight │  headless audit suite green? selectors resolve?    │
│  └──────┬───────┘  determinism check (run scenario twice, hashes     │
│         │          match)? if any red → halt + comment, no PR.       │
│         ↓                                                             │
│  ┌──────────────┐                                                    │
│  │ 1. Capture   │  run scenario windowed; screenshot EVERY step      │
│  └──────┬───────┘  (not just labeled); save screenshot_manifest.json │
│         │          with {step_idx, act, expected_state, png_path,    │
│         ↓           log_tail, cropped_dialog_png}.                   │
│  ┌──────────────┐                                                    │
│  │ 2. Critic    │  subagent_type=Haiku-class, tools=Read+image only. │
│  │  (subagent)  │  Input: manifest + scenario JSON + golden PNGs if  │
│  └──────┬───────┘  any. Output: structured critique JSON, one row    │
│         │          per flagged step: {severity, category, evidence,  │
│         ↓           expected, observed, suggested_focus_files}.      │
│  ┌──────────────┐                                                    │
│  │ 3. Triage    │  no critique → bless screenshots as goldens, exit  │
│  └──────┬───────┘  green. critique with no severity≥medium →         │
│         │          informational comment, exit green. else → fixer.  │
│         ↓                                                             │
│  ┌──────────────┐                                                    │
│  │ 4. Fixer     │  subagent_type=Opus, tools=Read/Edit/Bash limited. │
│  │  (subagent)  │  Input: critique JSON + suggested_focus_files +    │
│  └──────┬───────┘  scenario JSON (read-only). Output: code edit +    │
│         │          one-paragraph justification.                      │
│         ↓                                                             │
│  ┌──────────────┐                                                    │
│  │ 5. Verify    │  re-run scenario; re-screenshot; re-critic.        │
│  └──────┬───────┘  if critic green → commit + push + open PR.        │
│         │          if still red → loop back to 4 (max N inner iters).│
│         ↓          if N exhausted → halt with diagnostic.            │
│  ┌──────────────┐                                                    │
│  │ 6. PR        │  branch loop/<scenario>-<ts>; PR title = top       │
│  └──────────────┘  critique; body = full critique + before/after     │
│                    screenshots + diff size.                          │
└─────────────────────────────────────────────────────────────────────┘
```

### Kickoff (outside per-scenario session)

Triggered manually from the Claude Code web UI: open N parallel sessions
against `claude/loop-sweep` branch base, each with a prompt that names one
scenario file and invokes the per-scenario driver. Scenario selection
order = oldest `last_verified_commit` in `coverage.json` first.

There is no central coordinator. PRs land independently; humans review and
merge.

## Improvements wired in

| # | Improvement | How it's enforced |
|---|---|---|
| 1 | Separate agent turns, state on disk | Critic and fixer are `Agent` subagents; state in `screenshot_manifest.json`, `critique.json`, `iteration_log.json` |
| 2 | Dedicated critic, no codebase access | `subagent_type` with `tools: Read, image-only`; system prompt forbids editing |
| 3 | Commit per iteration | `loop/<scenario>-<ts>` branch, one commit per fixer iteration, `git bisect` ready |
| 4 | Golden screenshots as regression net | First-green-run blesses; PHASH diff thereafter; goldens checked in under `40k/tests/scenarios/goldens/` |
| 5 | Hard caps | `LOOP_MAX_ITERATIONS=4`, `LOOP_MAX_DIFF_LINES=200`, mandatory `justification` field |
| 6 | Parallel containers | One cloud Claude per scenario; scenario-scoped output dirs (`test_results/scenarios/loop/<scenario_id>/`) |
| 7 | Tiered models | Critic=Haiku, Fixer=Opus, Planner=Sonnet. Encoded in subagent invocations |
| 8 | Coverage-aware ordering | Kickoff script reads `coverage.json`, sorts by `last_verified_commit` ascending |
| 9 | Critic gets multiple views | Per step: full screenshot, cropped active-dialog crop, last 40 log lines, expected_state slice |
| 10 | Auto-bisect on regression | Per-iteration commits + `scripts/loop/bisect.sh <golden_sha>..HEAD` invocation |
| 11 | Anti-cycle guard | `iteration_log.json` tracks edited files; if same file edited 3 iters with same scenario still red → halt |
| 12 | Scenarios immutable inside loop | Pre-commit hook on `loop/*` branches rejects diffs touching `40k/tests/scenarios/**` |
| 13 | Headless preflight | `bash 40k/tests/run_pretrigger_tests.sh` runs first; non-zero exit → halt before xvfb |
| 14 | Selector dry-run | New `scripts/loop/selector_preflight.gd` walks every `click_node` / `expect_node_*` path in the scenario, asserts resolvable |
| 15 | Determinism gate | Scenario is run twice; perceptual hash of each labeled screenshot must match; mismatch → halt with `determinism_leak` reason |
| 16 | Golden bootstrap | No human seeding required; first all-green run writes goldens; subsequent runs PHASH-compare. Threshold tunable in `goldens/_thresholds.json` |
| 17 | Loop-branch pre-commit guardrails | Restricted-path list (`40k/autoloads/GameState.gd`, `40k/scripts/SaveLoadManager.gd`, anything matching `*_phase.gd` constants block), diff-line cap |
| 18 | CI feedback into next iteration | After PR push, `subscribe_pr_activity` watches CI; failures wake the session for a follow-up commit |

## New artifacts to add

```
40k/tests/scenarios/
├── goldens/                                  # NEW
│   ├── _thresholds.json                       # per-scenario PHASH tolerance
│   ├── <scenario_id>_<label>.png              # blessed reference frames
│   └── ...
40k/tests/
├── run_pretrigger_tests.sh                   # unchanged
├── run_scenarios.sh                          # unchanged
└── scenario_runner.gd                        # unchanged
40k/autoloads/
└── ScenarioRunner.gd                         # MODIFIED — add
                                              # SCREENSHOT_EVERY_STEP env
                                              # gate, write
                                              # screenshot_manifest.json
scripts/loop/
├── README.md                                 # NEW
├── kickoff_parallel.md                       # NEW — instructions to spawn
│                                              # N cloud Claude sessions
├── run_one_scenario_loop.sh                  # NEW — per-session driver,
│                                              # invoked inside the cloud
│                                              # Claude container
├── selector_preflight.gd                     # NEW — dry-run scenario
│                                              # selectors in headless mode
├── determinism_check.sh                      # NEW — run-twice, hash-diff
├── golden_diff.py                            # NEW — PHASH compare,
│                                              # writes critic input JSON
├── critic_prompt.md                          # NEW — system prompt for
│                                              # critic subagent
├── fixer_prompt.md                           # NEW — system prompt for
│                                              # fixer subagent
└── bisect_loop_branch.sh                     # NEW — auto-bisect helper

.githooks/
└── pre-commit-loop                           # NEW — chained from existing
                                              # pre-commit when branch
                                              # matches loop/*; enforces
                                              # diff cap, restricted paths,
                                              # scenario immutability
```

## Phased rollout

| Phase | Deliverable | Status |
|---|---|---|
| 0 | This design doc | THIS COMMIT |
| 1 | `ScenarioRunner.gd` per-step screenshot mode + `screenshot_manifest.json` writer | TODO |
| 2 | `golden_diff.py` (PHASH) + `goldens/` directory + bootstrap path | TODO |
| 3 | `selector_preflight.gd` + `determinism_check.sh` + headless preflight wired into the per-scenario driver | TODO |
| 4 | `run_one_scenario_loop.sh` — single-scenario end-to-end driver. **Verified live against `runner_smoke.json`.** | TODO |
| 5 | `critic_prompt.md` + `fixer_prompt.md` + Agent invocations inside the driver | TODO |
| 6 | `pre-commit-loop` guardrails + restricted-path list + diff-line cap | TODO |
| 7 | `kickoff_parallel.md` + coverage-ordered scenario selection | TODO |
| 8 | First real parallel sweep across all 25 scenarios. Treat all resulting PRs as the validation evidence for the loop itself. | TODO |

Each phase is self-contained and lands on its own branch (not on
`loop/*` — that namespace is reserved for the loop's own output).
Phase ordering is strict: each phase depends on the previous one's
artifacts.

## Caps and guardrails (the bounded part)

| Bound | Value | Where enforced |
|---|---|---|
| Max iterations per scenario | 4 | `run_one_scenario_loop.sh` while-loop |
| Max diff lines per iteration | 200 | `pre-commit-loop` |
| Max total session wall time | 30 min | `timeout 1800` wrapper |
| Forbidden paths | `40k/tests/scenarios/**`, `40k/autoloads/GameState.gd`, `40k/scripts/SaveLoadManager.gd`, `40k/data/**`, anything outside `40k/scripts/` and `40k/scenes/` | `pre-commit-loop` allowlist |
| Critic must justify | every flagged step needs `severity`, `category`, `evidence_path` populated; missing → critique rejected | driver script JSON-schema check |
| Fixer must justify | one-paragraph `justification` field in commit body; empty → commit rejected | `pre-commit-loop` |
| Scenarios immutable | any `40k/tests/scenarios/**` diff on `loop/*` branch → reject | `pre-commit-loop` |
| Anti-cycle | same file edited 3 iters in a row with scenario still red → halt with `cycle_detected` exit reason | `run_one_scenario_loop.sh` |

## Critic prompt (sketch)

```
You are a visual regression critic for the Warhammer 40k Godot game.
You have NO access to source code. You see:
  - The scenario JSON (intent of the test)
  - A manifest of screenshots, one per step, with the expected state
    slice at that step
  - A golden screenshot per labeled step, when one exists
  - The last 40 lines of the Godot log preceding each screenshot

Your job is to flag steps where the screenshot does not match what the
scenario clearly expects. For each flagged step output JSON:

  {
    "step_idx": int,
    "severity": "low" | "medium" | "high",
    "category": "missing_dialog" | "wrong_text" | "token_misplaced" |
                "ui_overlap" | "modulate_wrong" | "log_error" | "other",
    "evidence_path": "test_results/.../step_07.png",
    "expected": "Counter-Offensive dialog visible per step 5",
    "observed": "Board shown, no dialog present",
    "suggested_focus_files": ["40k/scripts/CounterOffensiveDialog.gd"]
  }

Output ONLY a JSON array. If nothing is wrong, output [].
```

## Fixer prompt (sketch)

```
You are a fix agent. You receive a critique JSON array and the scenario
JSON. You may Read any file but you may NOT edit:
  - 40k/tests/scenarios/**
  - 40k/autoloads/GameState.gd
  - 40k/scripts/SaveLoadManager.gd
  - 40k/data/**

Your diff must be ≤ 200 lines. Your commit body must include a
"Justification:" paragraph naming which critique entry the change
addresses and why this is the minimal fix.

After editing, run `bash 40k/tests/run_scenarios.sh tests/scenarios/<path>`.
If it fails, iterate. If it passes, exit.
```

## Open design questions

- Whether to use PHASH (cheap, robust to subpixel) or SSIM (catches subtle
  rendering bugs but flaky). Default: PHASH with tolerance 4 bits, SSIM
  available as an opt-in per-scenario in `goldens/_thresholds.json`.
- Whether the critic should be Haiku 4.5 (vision-strong, cheap) or
  Sonnet 4.6 (better reasoning, ~5x cost). Default: Haiku 4.5; promote to
  Sonnet only if critic false-negative rate exceeds 20%.
- Whether `loop/*` branches auto-open PRs or wait for human kickoff.
  Default: auto-open PR + tag as `loop-generated` so a label filter can
  surface them.
- Whether to extend this loop to multi-peer scenarios (mp/). Default: no
  for v1 — two-container choreography multiplies the failure surface
  before we've proven the single-peer path.

## References

- `.llm/scaled-testing-plan.md` — predecessor design that built the
  scenario harness. This doc picks up its "deferred" section.
- `CLAUDE.md` — project anti-patterns: pin tests aren't validation,
  screenshots-as-markers, "drive the feature path live."
- `SESSION_PLAYBOOK.md` — daily loop rules.
- `40k/addons/godot_mcp/` — MCP bridge, source of `simulate_click`,
  `capture_screenshot`, `get_node_info`.
- PR #399 — SessionStart hook that unlocks cloud Godot/xvfb (prerequisite
  for any cloud-side phase of this loop).
