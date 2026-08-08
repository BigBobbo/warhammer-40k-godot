# Why the benchmarks skipped deployment, and what changed

**Date:** 2026-08-08 · **Question asked:** "The tests you ran earlier all skip
the deployment phase — why? The deployment phase is very important so the AI
should be tested right from the start of the game."

## The answer: the fixtures skipped it, not the harness

Nothing in the benchmark harness excludes deployment. `AIBenchmarkRunner`
picks its start phase straight from the save:

```gdscript
# 40k/autoloads/AIBenchmarkRunner.gd
var start_phase = int(GameState.state.get("meta", {}).get("phase", 6))
...
pm.transition_to_phase(start_phase)
```

Every benchmark fixture in the repo was a `*_postdeploy` save with
`meta.phase = 6` (`Phase.COMMAND`), so every game started after deployment had
already happened — with a placement written by the fixture generator, not
chosen by the AI. The harness was doing what it was told.

That mattered more than it sounds, because the AI does have a deployment
brain and it was never being exercised:

* `AIDecisionMaker._decide_deployment` (line ~3859) classifies each unit into
  `fragile_shooter` / `durable_shooter` / `melee` / `character` / `anti_tank`
  and places it accordingly.
* Twelve terrain coefficients exist purely for that decision
  (`DEPLOY_TERRAIN_CHAR_COVER`, `DEPLOY_TERRAIN_FRAGILE_LOS_BLOCK`, …), and
  the A5 promotion note in the source says the quiet part out loud:
  *"deployment largely decides rounds 1-2"*.

So the single phase the code itself calls decisive had **zero games** behind
any of its numbers. Worse, tuning those twelve coefficients was untestable:
a paired A/B on a post-deployment fixture cannot move a parameter that is
only read before the fixture starts. The measured effect would be exactly
zero by construction, and would look like "this parameter does not matter".

## What changed

Three `*_predeploy` fixtures, built by the same generator with `--predeploy`:

| fixture | start | units |
|---|---|---|
| `mirror_custodes_2000_predeploy` | `Phase.DEPLOYMENT`, nothing on the table | 11 v 11, 2000 pts a side |
| `mirror_orks_2000_predeploy` | same | 17 v 17, 2000 pts a side |
| `asym_2000_predeploy` | same | Custodes 11 v Orks 17 |

`--predeploy` strips every model position and sets every unit's status to
`UNDEPLOYED (0)`, which is what `DeploymentPhase._get_undeployed_units_for_player`
keys off when it emits `DEPLOY_UNIT` actions.

`fixture_check.py` now asserts the **inverse** invariants on these rather than
failing them: nothing placed, every unit UNDEPLOYED or IN_RESERVES. That is
not a skipped check — a unit that arrives at phase 1 already marked DEPLOYED
emits no `DEPLOY_UNIT` action, is never placed, and silently sits out the
entire game with no error raised anywhere. It is the exact failure the gate
should catch, just inverted.

## Verification — a real game, from deployment to round 5

```
$ godot --headless --path 40k --ai-benchmark \
    --bench-fixture=mirror_custodes_2000_predeploy --bench-seed=9001 \
    --bench-difficulty=2 --bench-time-scale=6 --bench-max-seconds=1100

[AIBench] RESULT {"actions_taken":826,"battle_round":5,"difficulty":2,
  "fixture":"mirror_custodes_2000_predeploy","seed":9001,"status":"completed",
  "vp":{"player1":{"primary":30.0,"secondary":36.0,"total":66.0},
        "player2":{"primary":45.0,"secondary":36.0,"total":81.0}},
  "vp_diff_p2_minus_p1":15,"wall_seconds":194.338,"winner":2}
```

`status: completed`, `battle_round: 5`, 826 actions, and 103 `Deploying <unit>
(role=…)` lines in the log — the AI placed all 84 models itself and then
played the game out. Zero errors.

## What it costs

**194 s/game**, against ~48 s/game on the retired 1335-pt post-deployment
Custodes mirror. Roughly 4x, from two compounding causes: 2000 points is 42
models a side instead of 9 units, and deployment is ~100 extra decisions
before the game starts. The Ork fixture (77 models a side) is materially
worse again.

This is a real budget change, and it is the reason both variants are kept
rather than replacing one with the other:

* **`_predeploy` is the honest whole-game evaluation.** It is the only way to
  measure anything that reads a `DEPLOY_*` parameter, and the only
  configuration in which "is the AI better?" means what a player would mean.
* **`_postdeploy` stays the instrument for A/B work on later phases.** It
  holds deployment fixed, which removes a whole phase of variance from the
  paired comparison, and it is 4x cheaper per data point. Using it for a
  shooting or charge change is variance reduction, not a shortcut.

Choosing `_postdeploy` is legitimate; choosing it *by default and without
noticing* is what produced a lab where the decisive phase had no coverage.

## Still open

* No A/A reference (F, sd) has been measured on the `_predeploy` fixtures
  yet, so the games-per-VP-of-resolution cost of the extra deployment
  variance is **not yet known**. Until that exists, do not run a paired A/B
  on `_predeploy` and read its stopping rule as if it had the same spread as
  the post-deployment mirrors.
* Task A6's deployment-decision-record gap is unblocked but not closed: the
  aspirational exam `_a6_deployment_records.json` can now be pointed at a
  fixture that actually reaches the deployment phase.
