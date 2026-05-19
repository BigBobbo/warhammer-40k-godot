# Visual-regression loop — host-session playbook

This is the runbook a cloud Claude session follows when it's been asked
to drive ONE scenario through the loop. Pair with `critic_prompt.md`
and `fixer_prompt.md`.

A separate cloud Claude session is spun up per scenario. The session
runs this playbook end to end, then commits to
`loop/<scenario_id>-<timestamp>` and opens a PR. Each session is
isolated — no shared workspace, no cross-contamination.

## Inputs

- Scenario path (e.g. `40k/tests/scenarios/sp/co_offer_after_charge.json`)
- Caps from `.llm/visual-regression-loop-plan.md`:
  - `LOOP_MAX_ITERATIONS=4`
  - diff ≤ 200 lines per fixer iteration
  - 30-min wall clock budget
- An anti-cycle log of `{iteration, edited_files}` accumulated as you go

## Per-scenario loop

```
iter = 0
while iter < LOOP_MAX_ITERATIONS:
    1. Run driver:
       bash scripts/loop/run_one_scenario_loop.sh <scenario>

    2. If driver exit != 0 and reason == selector_preflight_failure:
       → fixer round (selectors fix), iter += 1, continue

       If driver exit != 0 and reason == scenario_step_failed:
       → fixer round (logic fix), iter += 1, continue

       If driver exit != 0 and reason == golden_drift:
       → CRITIC round (decide: regression or intentional UI change?)

       If driver exit == 0:
       → CRITIC round (sanity: does any screenshot LOOK wrong?)

    3. CRITIC round — invoke the critic subagent (see below).
       Critic returns critique.json (array).

       If critique.json == []:
         If goldens missing for this scenario: --bless run, commit goldens
         Else: scenario is clean — exit the loop, open PR if any
         intermediate fixer commits exist
       Else:
       → FIXER round, iter += 1

    4. FIXER round — invoke the fixer subagent (see below).
       Fixer edits code, returns commit message body.
       Commit on loop/<scenario>-<ts>; pre-commit-loop enforces caps.

    5. Anti-cycle: if same file edited in 3 consecutive iterations with
       scenario still red → halt with `cycle_detected` exit reason and a
       diagnostic comment.

if iter == LOOP_MAX_ITERATIONS:
    halt with `max_iterations` exit reason, diagnostic in PR
```

## Invoking the critic subagent

```
Agent({
  description: "Critic for <scenario_id>",
  subagent_type: "claude",
  prompt: <<EOF
<contents of scripts/loop/critic_prompt.md>

## This run's inputs

Scenario JSON: 40k/tests/scenarios/sp/<scenario>.json
Results JSON: ~/.local/share/godot/app_userdata/40k/test_results/scenarios/<scenario_id>.json
Goldens report: ~/.local/share/godot/app_userdata/40k/test_results/scenarios/goldens_report.json
Per-step screenshots: ~/.local/share/godot/app_userdata/40k/test_results/scenarios/<scenario_id>_step_*.png
Goldens dir: 40k/tests/scenarios/goldens/
Godot log: /tmp/loop_scenario_<scenario_id>.log

Read each PNG, the scenario JSON, and the results JSON.
Write your JSON critique array to /tmp/critique_<scenario_id>.json
AND return the same JSON as your final message.
EOF
})
```

The agent uses `Read` (which supports PNGs) to view each screenshot,
emits JSON conforming to `critic_prompt.md`'s schema, writes it to the
specified path, and echoes it back.

The host session reads the file (don't trust the message body alone —
the file is the source of truth) and decides whether to invoke the
fixer.

## Invoking the fixer subagent

```
Agent({
  description: "Fixer for <scenario_id> iter <N>",
  subagent_type: "claude",
  prompt: <<EOF
<contents of scripts/loop/fixer_prompt.md>

## This run's inputs

Scenario JSON: 40k/tests/scenarios/sp/<scenario>.json  (READ-ONLY)
Critique JSON: /tmp/critique_<scenario_id>.json
Anti-cycle log: <list of files edited in prior iterations>

After editing, run:
  bash 40k/tests/run_scenarios.sh <scenario>
to confirm the engine still accepts the action. Do not run the full
windowed loop — the host session does that.

Stage and commit your changes with the required Justification: paragraph.
Return the commit SHA as your final message.
EOF
})
```

## What this session has already proven

- Phase 1: driver runs, manifest writer correct, stub critic OK
- Phase 2: golden diff catches injected drift (10/11 match, 1 drift on
  injected frame, driver exit 1)
- Phase 3: selector preflight catches missing `unit_id` and `node` paths
  with itemized errors before the windowed run
- Phase 5 (this commit): the critic Agent invocation pattern is
  validated against runner_smoke — see `40k/tests/scenarios/agent_runs/`
  for the captured critique JSON. Runner_smoke has no UI mutation so
  the critique is `[]` (the correct answer); a scenario with a real
  regression will produce a non-empty critique.

## Outstanding for Phase 7 (parallel kickoff)

The kickoff doc will document how to spawn N parallel cloud sessions
from the web UI: one session per scenario, ordered by
`coverage.json:last_verified_commit` ascending. Each session runs this
playbook end to end.
