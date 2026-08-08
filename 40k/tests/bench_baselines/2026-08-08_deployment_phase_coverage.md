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

`fixture_check.py` recognises the mode from `meta.phase` and checks that unit
status and model position **agree**, rather than applying post-deployment
invariants that a pre-deployment save cannot satisfy. It is not a relaxation —
both mismatches are silent bugs in opposite directions. DEPLOYED but
positionless: `DeploymentPhase` emits `DEPLOY_UNIT` only for UNDEPLOYED units,
so nothing ever places it and it sits out the game with no error anywhere.
Fully positioned but UNDEPLOYED: it gets offered for deployment again and
re-placed, discarding the author's setup. Both, plus the half-placed case, are
verified by seeding each defect into `mirror_custodes_2000_predeploy` and
confirming the gate rejects it. A *partially* deployed fixture stays legal —
that is what `deployment_nearly_complete` exists to be.

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

## The exam that now guards it

`40k/tests/exams/dp01_deployment_is_recorded.json`, run on
`mirror_custodes_2000_predeploy`:

```
[AIExam] dp01_deployment_is_recorded: 3 passed, 0 failed -> PASS
   OK  player 1 actually placed units on the table                     got 11, expected >= 3
   OK  every deployment decision is recorded with scored candidates    got 22, expected >= 3
   OK  deployment records name the DEPLOY_TERRAIN_* parameters read    got 11, expected >= 1
```

The second and third assertions are the ones that matter for tuning. A
decision with no record is invisible to everything in `tools/ai_lab/`, and a
record that does not name the parameters it read cannot be attributed to a
coefficient. 22 recorded deployment decisions across 26 decision batches, and
these coefficients named in them:

```
DEPLOY_TERRAIN_CHAR_COVER        DEPLOY_TERRAIN_DURABLE_COVER
DEPLOY_TERRAIN_CHAR_LOS_BLOCK    DEPLOY_TERRAIN_DURABLE_LOS_BLOCK
DEPLOY_TERRAIN_MELEE_COVER       DEPLOY_TERRAIN_FORWARD_WEIGHT
DEPLOY_TERRAIN_MELEE_LOS_BLOCK
```

Seven of the twelve. The missing five are the `FRAGILE_*` and `SCREEN_*`
pairs, and their absence is a property of the army rather than a defect:
`_classify_deployment_role` never returns `fragile_shooter` or `screen` for
Lions of the Emperor, whose cheapest unit is 45 points of 1-wound Prosecutors
and whose rest are 4-wound elites. Exercising those five needs
`mirror_orks_2000_predeploy` — Gretchin and Stormboyz classify differently.
Worth doing before anyone tries to tune them; until then, treat those five as
**unverified as reachable**, not as verified.

## Still open

* ~~No A/A reference on `_predeploy`~~ — **measured 2026-08-08**, and the
  answer is larger than the per-game cost suggested. 12 games on
  `mirror_custodes_2000_predeploy`: F = −0.25 ± 5.83, **sd 20.21** against the
  post-deployment fixture's 11.35. Games needed scale with sd², so equal
  statistical power costs **3.17x the games and 4.44x the wall clock**. A
  paired A/B that resolves in an hour post-deployment needs about four and a
  half hours pre-deployment. Full table in `2026-08-08_2000pt_fixture_AA.md`.
  This is the honest price of covering deployment, and it is the concrete
  reason `_postdeploy` stays the instrument for changes deployment cannot
  touch.
* The Ork fixtures have no A/A reference yet, and their packing is a known
  problem — 77 models at a 0.07" median nearest-neighbour gap make the
  movement phase grind (see `40k/tests/exams/slow/README.md`). Measure before
  trusting a stopping rule there.
* The five `FRAGILE_*` / `SCREEN_*` deployment coefficients are still
  **unverified as reachable** — see above. `mirror_orks_2000_predeploy` is the
  fixture that would settle it, and no exam points there yet.
* Task A6's deployment-decision-record gap is closed for the decision type
  itself (`dp01` above), which is what retired the aspirational
  `_a6_deployment_records` probe. The other A6 decision types that no fixture
  exercised — warlord designation, leader attachment, reserves declaration —
  are reachable from a `_predeploy` fixture's Formations phase but have no
  exam asserting their records yet.
