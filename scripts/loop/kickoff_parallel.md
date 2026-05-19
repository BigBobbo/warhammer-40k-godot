# Visual-regression loop — parallel kickoff

Operator runbook for spawning the loop across all 25 scenarios at
once, one cloud Claude session per scenario. The loop itself is
defined in `playbook.md`; this doc is what an operator (you, from the
Claude Code web UI) needs to fire it.

## Capacity sanity check

| Resource | Limit | Per-session usage | Headroom for 25 in parallel |
|---|---|---|---|
| Cloud Claude sessions | depends on your plan | 1 | check first |
| Wall time | 30-min cap per session (see design doc) | up to 30 min | sessions run in parallel — wall time is per-session, not summed |
| Disk for outputs | each session has its own container | a few MB of PNGs + JSON in user dir | 25 × isolated containers, no shared FS |
| Critic tokens | Anthropic budget | ~30k input tokens per critic invocation, ~5-10k output | budget for N iterations × 25 |

If your plan doesn't allow 25 concurrent sessions, spawn in batches.
The script below prints the prioritized list — peel off the top N you
have capacity for.

## Generating the spawn list

```bash
# Human-readable table, all scenarios in priority order
python3 scripts/loop/list_scenarios_by_priority.py

# Top 10 only
python3 scripts/loop/list_scenarios_by_priority.py --top 10

# Just paths, one per line — feed to the spawn step
python3 scripts/loop/list_scenarios_by_priority.py --paths

# Machine-readable
python3 scripts/loop/list_scenarios_by_priority.py --tsv
```

Priority rule (codified in the script):

1. Scenarios on disk but NOT in `coverage.json` jump to the top —
   they've never had a last-verified-commit recorded, so the loop
   hasn't seen them. (Run the loop, then add them to coverage.)
2. Scenarios whose tile recorded a commit we can't resolve (foreign
   branch, deleted SHA) come next — `?` in the age column. Treat as
   "stale, verify before trusting."
3. Remaining scenarios sort by the OLDEST tile commit they cover,
   ascending. Longest-since-last-green-run first.

Ties break alphabetically for determinism.

## Per-session prompt template

Each cloud Claude session you spawn is briefed with a self-contained
prompt naming ONE scenario. Copy the template, swap in the scenario
path, paste into the web UI.

```
You are a Claude Code session driving the visual-regression loop for
ONE scenario. Read scripts/loop/playbook.md and follow it end to end
for this scenario:

  SCENARIO_PATH = "<paste from list_scenarios_by_priority.py --paths>"

Constraints (mirror .llm/visual-regression-loop-plan.md):
  - LOOP_MAX_ITERATIONS = 4
  - max diff per iteration = 200 lines (enforced by pre-commit-loop)
  - max wall clock = 30 min
  - branch: loop/<scenario_id>-<unix_timestamp>
  - open PR against main when the critic returns []
  - if you halt for `cycle_detected` or `max_iterations`, open the PR
    anyway with the halt reason in the title and a diagnostic in the
    body — humans need visibility into stuck scenarios

Start by reading playbook.md, then run the driver:

  bash scripts/loop/run_one_scenario_loop.sh $SCENARIO_PATH

and proceed from there. Do NOT exceed any cap. Do NOT touch any
forbidden path (the hook will reject the commit if you try).
```

## Wiring it into the web UI

The Claude Code web UI lets you start a session with:

- A repo (this one — restricted to `BigBobbo/warhammer-40k-godot`)
- A starting branch (use `claude/visual-regression-loop` as the base,
  or `main` if all phases have merged)
- An initial prompt (paste the template above with the scenario
  filled in)

For batch spawn-from-script, generate one curl/CLI invocation per
scenario from the `--tsv` output:

```bash
python3 scripts/loop/list_scenarios_by_priority.py --paths --top 10 \
| while read path; do
    sid=$(basename "$path" .json)
    echo "TODO: spawn session for $sid → $path"
    # If the Claude Code CLI exposes a programmatic session-create,
    # invoke it here with the per-session prompt. As of writing this is
    # a web-UI-only flow; keep this loop as a smoke check until then.
done
```

## What success looks like

After the sweep completes, you have N new PRs on the repo, one per
scenario that needed any fix. Each PR:

- Lives on `loop/<scenario>-<timestamp>`
- Has the critic's top-severity finding as the PR title
- Has the full critique JSON + before/after screenshots in the body
- Has only minimal diff (≤200 lines, enforced) with a Justification:
  paragraph per commit

Scenarios that come back clean (no critique findings, no drift) emit
NO PR — they just bless their goldens silently. Check the goldens
directory diff on `main` to see which ones moved.

Coverage.json is the post-sweep deliverable: update each tile's
`last_verified_commit` to the green sweep's commit SHA so the next
run's priority list reflects the new baseline.

## What failure looks like

Sessions can halt before opening a PR. The taxonomy:

| Halt reason | Meaning | Operator response |
|---|---|---|
| `preflight_failed` | headless audit suite was already red on main | fix the audit on main first, then re-spawn |
| `selector_preflight_failed` | scenario references a node/unit that no longer exists | open issue, hand-author a fix on main |
| `cycle_detected` | fixer edited same file 3 iters in a row, scenario still red | open issue with the iteration log; loop can't fix this autonomously |
| `max_iterations` | 4 fixer rounds, scenario still red | escalate; the diff may need to be bigger than 200 lines |
| `cap_violation` | diff or path or Justification rejected by pre-commit-loop | the fixer agent's commit didn't conform; the session retries once, then halts |

Each halt should leave a diagnostic comment on the PR (or, if no PR
was opened, in the session transcript). The operator's job is to
triage the halt list and decide which warrant human follow-up.

## Coordination cost

Zero. Sessions are isolated; their only shared state is git (each PR
on its own branch). The merge order is the order PRs come in; pick the
first ready one, review, merge, repeat. Merge conflicts between two
loop PRs are exceedingly unlikely (each touches different files under
`40k/scripts/`) and trivially resolvable.

If a loop PR conflicts with a human PR landing during the sweep,
that's a human-side rebase — the loop sessions don't watch for it.
