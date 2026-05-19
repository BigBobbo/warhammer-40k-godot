# Visual-regression loop scripts

Per-scenario "run windowed → critique → fix → re-run" loop. One cloud
Claude session per scenario, parallel by default. See
`.llm/visual-regression-loop-plan.md` for full design.

## Phase 1 status (this directory)

| Piece | Status | Notes |
|---|---|---|
| Per-step screenshot mode in `ScenarioRunner` | done | `SCENARIO_SCREENSHOT_EVERY_STEP=1` env var |
| Driver script | done | `run_one_scenario_loop.sh` |
| Critic | **stub** | `critic_stub.py` returns `[]`, validates I/O contract only |
| Critic prompt for real run | done | `critic_prompt.md` (consumed by the Agent tool inside a cloud Claude session) |
| Fixer prompt for real run | done | `fixer_prompt.md` (same) |
| Golden screenshot diff | TODO | Phase 2 |
| Selector preflight | TODO | Phase 3 |
| Pre-commit guardrails | TODO | Phase 6 |
| Parallel kickoff | TODO | Phase 7 |

## How to drive one scenario locally

```bash
bash scripts/loop/run_one_scenario_loop.sh 40k/tests/scenarios/sp/runner_smoke.json
```

Expected output: per-step screenshots written to
`~/.local/share/godot/app_userdata/40k/test_results/scenarios/runner_smoke_step_NN_<act>.png`,
results JSON at `runner_smoke.json` in the same directory with each
step's record carrying `per_step_screenshot` + `step_input`, and an
empty `critique.json` from the stub critic.

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

## Why a stub critic in Phase 1

The Agent tool runs inside a Claude session, not from a shell script. A
local user running `run_one_scenario_loop.sh` outside of a Claude session
has no way to invoke the critic. The stub lets us prove the I/O contract
(manifest format, screenshot paths, critique file location) works end to
end before wiring real Agent calls into the cloud-session prompt.
