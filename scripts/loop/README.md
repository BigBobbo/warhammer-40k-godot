# Visual-regression loop scripts

Per-scenario "run windowed → critique → fix → re-run" loop. One cloud
Claude session per scenario, parallel by default. See
`.llm/visual-regression-loop-plan.md` for full design.

## Status

| Piece | Status | Notes |
|---|---|---|
| Per-step screenshot mode in `ScenarioRunner` | done (Phase 1) | `SCENARIO_SCREENSHOT_EVERY_STEP=1` env var |
| Driver script | done (Phase 1) | `run_one_scenario_loop.sh` |
| Critic | **stub + live-tested** (Phase 1, 5) | `critic_stub.py` validates I/O contract; real critic is an Agent invocation documented in `playbook.md`, live-validated against runner_smoke (`agent_runs/runner_smoke_critique.json`) |
| Critic prompt for real run | done (Phase 1) | `critic_prompt.md` (consumed by the Agent tool inside a cloud Claude session) |
| Fixer prompt for real run | done (Phase 1) | `fixer_prompt.md` (same) |
| Host-session playbook | done (Phase 5) | `playbook.md` — runbook for the cloud Claude session driving one scenario |
| Golden screenshot PHASH diff | done (Phase 2) | `golden_diff.py`, goldens under `40k/tests/scenarios/goldens/` |
| Selector preflight | done (Phase 3) | `SCENARIO_SELECTOR_DRY_RUN=1` in `ScenarioRunner`, integrated into driver |
| Determinism check | done (Phase 3) | `determinism_check.sh`, standalone tool |
| Pre-commit guardrails | done (Phase 6) | `.githooks/pre-commit-loop` — fires on `loop/*` branches, enforces scenario-immutability, forbidden paths, diff cap, Justification |
| Parallel kickoff | TODO | Phase 7 |

## How to drive one scenario locally

```bash
# Diff mode (default): compare per-step screenshots to blessed goldens
bash scripts/loop/run_one_scenario_loop.sh 40k/tests/scenarios/sp/runner_smoke.json

# Bless mode: overwrite goldens with the current screenshots. Run only
# after manual sign-off, e.g. for a brand-new scenario or an intentional
# UI change.
bash scripts/loop/run_one_scenario_loop.sh --bless 40k/tests/scenarios/sp/runner_smoke.json
```

Expected output: per-step screenshots written to
`~/.local/share/godot/app_userdata/40k/test_results/scenarios/runner_smoke_step_NN_<act>.png`,
results JSON at `runner_smoke.json` in the same directory with each
step's record carrying `per_step_screenshot` + `step_input`, an empty
`critique.json` from the stub critic, and `goldens_report.json` with
per-step match / drift / missing_golden status.

Driver exits 0 only when scenario steps all pass AND all per-step
screenshots match their goldens under the configured PHASH threshold.

## Selector preflight

Before the windowed run, the driver does a `SCENARIO_SELECTOR_DRY_RUN=1`
pass: it loads the fixture and walks the steps, but only resolves
selectors (`click_node` / `click_unit` / `expect_node_*` /
`expect_token_visible`). Steps without selectors get
`selector_status: n/a` and pass automatically.

If any selector misses, the driver halts with an itemized list and
exits 1 BEFORE the expensive windowed run. This catches "scenario
silently no-ops because a button moved" — a class of bug that
previously surfaced as a flaky screenshot rather than a clear error.

The dry-run also writes `<scenario_id>_selectors_report.json` to the
results dir for debugging.

`LOOP_SKIP_SELECTOR_PREFLIGHT=1` bypasses it (use sparingly).

## Determinism check

`determinism_check.sh` runs a scenario twice and PHASH-compares every
per-step screenshot pair. Non-zero Hamming distance between runs of
the same step means the scenario isn't deterministic under the RNG
seed it claims to use — typically a real bug (un-seeded animation,
tween jitter, unordered dict walk) that will flake the golden diff
downstream.

Not wired into `run_one_scenario_loop.sh` because it doubles wall time
and would clobber the per-step PNGs the golden diff needs. Run it
separately when a scenario is suspected of flaking:

```bash
bash scripts/loop/determinism_check.sh 40k/tests/scenarios/sp/runner_smoke.json
```

## Golden screenshots

Pinned reference frames live in `40k/tests/scenarios/goldens/`.
Filenames mirror the runner output: `<scenario_id>_step_NN_<act>.png`.
Per-scenario PHASH tolerance is configured in `_thresholds.json`
alongside the goldens. Default tolerance is Hamming distance ≤ 4 on a
64-bit hash (empirically: 0-3 for subpixel rendering jitter, 12-18 for
genuine UI changes).

When a scenario or step changes intentionally, bless the new frames
with `--bless` and review the diff in PR. The goldens directory is the
record of "what the player should see"; never bump thresholds to
silence drift.

## How the cloud session uses it (Phase 5 onward)

The cloud Claude session is briefed with the scenario name. It:

1. Runs `bash scripts/loop/run_one_scenario_loop.sh <scenario.json>` once
2. Reads the resulting `*.json` + per-step screenshots
3. Invokes the **critic** subagent with `critic_prompt.md` as system prompt
   and the manifest + screenshots as input. The critic returns structured
   JSON to `critique.json` (the stub is only for local I/O testing — the
   real run replaces the stub with this Agent invocation).
4. If `critique.json == []`, blesses screenshots as goldens and exits.
5. Otherwise invokes the **fixer** subagent with `fixer_prompt.md` and the
   critique JSON. Fixer edits code, the driver re-runs, the critic
   re-judges.
6. Up to `LOOP_MAX_ITERATIONS=4` rounds. On green, commits to
   `loop/<scenario>-<timestamp>` and opens a PR.

## Loop-branch guardrails

Auto-fix commits land on `loop/<scenario>-<timestamp>` branches. The
existing `.githooks/pre-commit` chains into `.githooks/pre-commit-loop`
when the current branch matches `loop/*` and enforces:

| Cap | Where |
|---|---|
| Scenarios immutable | any diff under `40k/tests/scenarios/*.json` (top-level, `sp/`, `mp/`) → reject |
| Forbidden paths | `40k/autoloads/GameState.gd`, `40k/scripts/SaveLoadManager.gd`, `40k/data/`, `40k/project.godot`, `scripts/loop/`, `.githooks/`, the design doc → reject |
| Max diff lines | added + removed > 200 → reject. Override per-commit via `LOOP_MAX_DIFF_LINES=N` |
| Justification: paragraph | commit body without a non-empty `Justification:` line → reject |

The hook is a no-op on non-`loop/*` branches. Enable in your local
clone with `git config core.hooksPath .githooks`.

Standalone testing:
```bash
git checkout -b loop/test-temp
git add <file>
GIT_LOOP_DRY_RUN_COMMIT_MSG=/path/to/msg.txt bash .githooks/pre-commit-loop
git branch -D loop/test-temp
```

## Why a stub critic in Phase 1

The Agent tool runs inside a Claude session, not from a shell script. A
local user running `run_one_scenario_loop.sh` outside of a Claude session
has no way to invoke the critic. The stub lets us prove the I/O contract
(manifest format, screenshot paths, critique file location) works end to
end before wiring real Agent calls into the cloud-session prompt.
