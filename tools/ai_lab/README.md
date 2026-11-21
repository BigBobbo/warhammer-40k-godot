# `tools/ai_lab` — the offline half of the AI learning loop

Implements **M0** and **M1** (plus M2's static-analysis half) of
`research/ai_learning_framework_design.md`. Everything here is offline Python
operating on exported data — per that design's constraint, no ML runtime goes
in-engine.

The problem this addresses: `AIDecisionMaker.gd` builds a complete *"here were
my options, here is how I scored each one, here is what I picked, here are the
parameters I used"* trace for every decision it makes — and before M1 every one
of those traces was discarded when the process exited. The outcome went to a
separate JSON that had no idea the decisions existed. Nothing joined them, so
nothing could learn from them.

## What exists now

| Stage | Tool | What it does |
|---|---|---|
| M0 | `fixture_check.py` | Refuses to let a campaign run on a broken environment |
| M1 | `AIBenchmarkRunner` → `*.record.json` | One self-describing record per game |
| M1 | `build_index.py` | A season directory → Parquet + DuckDB with joining views |
| M2 | `params_manifest.py` | Extracts the real tunable surface from the source |
| M2 | `validate_profile.py` | Blocks the four silent-failure modes of the rule DSL |
| M2 | `run_lanes.py` | Plays one arm across concurrent lanes into a season |
| M2 | `determinism_check.py` | Proves two same-seed seasons are identical |
| M2 | `run_paired.py` | **The evaluator**: side-swapped pairs, sequential stopping |
| AB-SEAT | `ai_versions.py` | **Old vs new AI code**: each seat plays its own `AIDecisionMaker.gd` from a git ref (`extract V0=<ref>`, `run --base V0 --cand V3`); same side-swapped E as run_paired |
| M3 | `sensitivity_screen.py` | Ranks which constants actually move the margin |
| M4 | `cem_driver.py` | Cross-entropy search with racing over the ranked dims |
| — | `gate_candidate.py` | The five accept/reject gates a change must clear |
| — | `feature_census.py` | Maps the ceiling parameter search cannot pass |
| — | `tunability_audit.py` | Finds scoring no profile can reach |
| — | `audit_extract.py` | Builds expressiveness-audit dossiers from records |

### The pipeline, end to end

```
fixture_check ──► run_lanes ──► records ──► build_index ──► DuckDB views
                     │                                          │
                     ▼                                          ▼
              run_paired (E, F, verdict)              feature_census
                     │                                tunability_audit
        ┌────────────┴────────────┐                   audit_extract
        ▼                         ▼                          │
 sensitivity_screen ──────►  cem_driver                       ▼
        (rank dims)          (search them)            expressiveness
                                  │                       findings
                                  ▼
                          gate_candidate ──► ship + version_history entry
```

## M0 — `fixture_check.py`

```bash
python3 tools/ai_lab/fixture_check.py            # gate: the campaign fixtures
python3 tools/ai_lab/fixture_check.py --all      # survey every fixture
python3 tools/ai_lab/fixture_check.py mirror_orks_2000_postdeploy --json
```

Every AI baseline predating 2026-08-06 was tuned on a fixture containing an
army-list header row imported as a unit (`points: 2000`,
`keywords: ["UNKNOWN"]`). It inflated army totals, doubled the Strategic
Reserves cap, and drew the enemy AI into shooting a 1-wound phantom. Nothing
recorded which fixture a result came from, so the corruption stayed invisible
and invalidated every historical tuning decision at once.

The checker catches that class directly (placeholder detection, per-player
points sums, the 11e 20.01 50% reserves cap, dangling references, positionless
on-table models, mirror symmetry). It exits non-zero on failure and is called
advisorily from `run_ai_benchmark.sh`; a campaign driver must treat a non-zero
exit as **fatal**.

Verified against the real corruption:

```
$ python3 tools/ai_lab/fixture_check.py audit_baseline_postdeploy
[FAIL] audit_baseline_postdeploy
   P1: 9 units, 1335 pts, 215 pts (16%) in reserve
   P2: 17 units, 3840 pts, 1270 pts (33%) in reserve
   ERROR   U_STRIKE_FORCE_A ('Strike Force'): looks like an army-list header
           row, not a datasheet — keywords contain "UNKNOWN"; null weapons AND
           null unit_composition; points=2000 exceeds any real datasheet
```

Note `3840` — that is the phantom's 2000 points inflating a 1840-point army.
The campaign-eligible fixtures are the mirrors, and only those.

### The fixtures (changed 2026-08-08)

The lab used to run on `mirror_custodes_postdeploy` (1335 pts) and
`mirror_orks_postdeploy` (1840 pts), both built by mirroring an army already
inside the corrupt save. Neither matched a list a player can pick, and neither
was near 2000 points — the format 40k is balanced at and the one this game is
designed to be played at. So every number the lab had produced described a
format nobody plays.

The current fixtures are built by `40k/tests/make_2000pt_fixture.gd` from the
**shipped** army lists, through `ArmyListManager.load_army_list` +
`apply_army_to_game_state`, so display names, ability canonicalisation,
wargear/enhancement stat bonuses, model-profile wounds and the Custodes
deep-strike backfill all happen exactly as they do for a player:

| fixture | P1 | P2 | start |
|---|---|---|---|
| `mirror_custodes_2000_postdeploy` | Lions of the Emperor, 11 units / 42 models / 2000 pts | mirrored | R1 Command |
| `mirror_orks_2000_postdeploy` | Speedwaaagh!, 17 units / 77 models / 2000 pts | mirrored | R1 Command |
| `asym_2000_postdeploy` | Custodes 2000 | Orks 2000 | R1 Command |
| `mirror_custodes_2000_predeploy` | as above | as above | **Deployment** |
| `mirror_orks_2000_predeploy` | as above | as above | **Deployment** |
| `asym_2000_predeploy` | as above | as above | **Deployment** |

`_postdeploy` starts at round 1 Command with both armies packed into their
zones; deployment is held fixed, which removes one source of variance when
A/B-ing the phases after it. `_predeploy` starts at `Phase.DEPLOYMENT` with
nothing on the table, so the AI runs `_decide_deployment` and places its own
army — the only way to evaluate the phase the AI's own source calls out as
the one that "largely decides rounds 1-2".

Rebuild them with:

```bash
godot --headless --path 40k --script tests/make_2000pt_fixture.gd -- \
    --mirror=custodes_lions --out=mirror_custodes_2000_postdeploy
godot --headless --path 40k --script tests/make_2000pt_fixture.gd -- \
    --mirror=recon_stomps --out=mirror_orks_2000_predeploy --predeploy
godot --headless --path 40k --script tests/make_2000pt_fixture.gd -- \
    --p1=custodes_lions --p2=recon_stomps --out=asym_2000_postdeploy
```

`--mirror` takes a list name (`--mirror=<list>`); a bare `--mirror` is a hard
error, because it used to be silently ignored and produced a fixture named
like a mirror whose two sides were packed independently.

### Reserve fixtures (added 2026-10-31, opt-in)

The six fixtures above have every unit on the table and none in reserve, so
AI code that only runs when the enemy has reserves (deep-strike denial
screens, reserve-backed keepers) never runs in them. Three opt-in fixtures
add the reserves the AI's own Formations logic picks (`--reserves=ai`,
built from the committed fixture with `--base`):

| fixture | in reserve, per side |
|---|---|
| `mirror_custodes_2000_reserves_postdeploy` | Allarus A, Custodian Guard D + Blade Champion A (Warlord, attached), Custodian Guard A; all Deep Strike; 825/2000 pts, 4/11 units |
| `mirror_orks_2000_reserves_postdeploy` | Stormboyz C, D (Strategic Reserves), Deffkoptas A, B (Deep Strike); 410/1975 pts, 4/17 units (the shipped Recon Stomps plan) |
| `asym_2000_reserves_postdeploy` | Custodes set (P1) + Ork set (P2) |

```bash
godot --headless --path 40k --script tests/make_2000pt_fixture.gd -- \
    --base=mirror_custodes_2000_postdeploy --reserves=ai --out=mirror_custodes_2000_reserves_postdeploy
```

They are an extra gate for reserve-dependent fixes only; the three standard
fixtures stay the ship gate. Known caveats (smoke games + review, 2026-10-31):
the AI's Deep Strike placements for Deffkoptas are often rejected (walls) and
those units are destroyed at the end of round 3, so prefer the Custodes and
asym reserve fixtures; destroyed reserve units keep `IN_RESERVES` and can
still "arrive" (engine bug); `fixture_check.py` passes these fixtures only
without `--strict`. After any rebuild delete the stale copies in
`user://saves/` (the runner copies a fixture only when it is absent).

## M1 — game records

`AIBenchmarkRunner` now writes `<out>.record.json` next to its result file, on
**every** exit path (completed, stalled, errored). Schema lives in
`40k/scripts/AIGameRecord.gd` — a dependency-free `RefCounted` so it stays
testable without standing up a 6-minute game
(`40k/tests/test_game_record_export.gd`, 31 assertions).

```jsonc
{
  "schema": "wh40k_ai_game_record", "schema_version": 1,
  "game_id": "20260806_213000_game_1",
  "provenance": {            // NOT optional — see the fixture episode above
    "git_sha": "60ce588", "engine": "4.4.1-stable (official)",
    "fixture": "mirror_orks_postdeploy", "fixture_sha256": "4ac13a31...",
    "p1_profile": {"path": "...", "sha256": "...", "inline": {/* full JSON */}},
    "p2_profile": {...}, "difficulty": {"1": 2, "2": 2},
    "seed": 4242, "time_scale": 6.0, "arm": "baseline"
  },
  "outcome": { /* the existing _collect_result() dict, verbatim */ },
  "vp_events": [{"round": 2, "phase": 6, "player": 1, "points": 8,
                 "reason": "Battlefield Dominance (command): per_objective +6"}],
  "decisions": [ /* AIPlayer._all_decision_records, verbatim */ ],
  "action_log": [ /* AIPlayer._action_log, verbatim */ ],
  "decision_batches_total": 196, "decision_batches_dropped": 0
}
```

Two deliberate choices:

- **Written from `_write_and_quit`, not on game-complete.** The pre-existing
  `export_decision_log()` hook fires on game end, which never happens for a
  stalled game — the most informative kind. It also raced `_process`, which
  returns early once `PhaseManager.game_ended` is set.
- **The batch cap is raised to 100000 in benchmark mode only.** The 500-batch
  ring buffer is right for a desktop play session, but dropping batches biases
  a game's trace toward its *end*. `decision_batches_dropped` is recorded so
  the analysis layer can see when it happened; normal play is untouched.

**Measured size** (one real 5-round mirror game, 196 decisions, 751 actions):
485 KB raw, **49 KB gzipped** — so ~0.5 GB per 10k-game season. Stdout logs run
41–51 MB/game and are *not* part of the record; `run_ai_benchmark.sh` keeps
them only for stalled/errored games, gzipped, newest `BENCH_KEEP_LOGS` (50).

### Collecting a season

```bash
BENCH_DATA_DIR=bench_data/season_1 BENCH_ARM=baseline \
BENCH_DIFFICULTY=2 BENCH_TIME_SCALE=6 \
  bash 40k/tests/run_ai_benchmark.sh 10 mirror_orks_2000_postdeploy
```

`BENCH_DATA_DIR` gzips each record into a season directory. `BENCH_ARM` labels
it so an A/B campaign can split on it. The git sha (with a `-dirty` suffix when
the tree has uncommitted changes) is recorded automatically — the index refuses
to pool across shas by default, because a rules fix landing mid-season makes a
pooled effect meaningless.

## M1 — `build_index.py`

```bash
python3 tools/ai_lab/build_index.py bench_data/season_1
python3 tools/ai_lab/build_index.py --selftest
```

Flattens a season into three tables — `games`, `decisions`, `vp_events` — as
Parquet, plus `season.duckdb` carrying four views:

- **`decision_outcomes`** — every decision joined to how its game turned out.
  This is the join that did not exist before M1.
- **`round_vp`** — per (game, player, round) VP deltas: the cheap intermediate
  signal that makes per-round credit assignment possible without counterfactual
  replay.
- **`arm_summary`** — margin and spread per (fixture, arm, git_sha). The `sd`
  is the raw per-game spread, **not** a paired standard error; pairing belongs
  in the A/B driver, not the index.
- **`data_quality`** — games that dropped decision batches or recorded none.

`decisions.regret_vs_own_best` is the gap between the score of the candidate
taken and the best score assigned to any candidate. It is nonzero when
difficulty noise or a coordination override deflected the choice. It measures
deviation from the **heuristic's own opinion**, not from truth — a mining
signal, not a reward.

DuckDB is optional; without it the tool writes CSV instead of Parquet.

## M2 (partial) — `params_manifest.py` and `validate_profile.py`

```bash
python3 tools/ai_lab/params_manifest.py             # 104 params, 13 conds, 3 ops
python3 tools/ai_lab/validate_profile.py cand.json
python3 tools/ai_lab/validate_profile.py --selftest
```

The manifest is derived from `AIDecisionMaker.gd` itself, never
hand-maintained: 152 `const`s exist but only the **104** actually read through
`get_param`/`get_param_int` are reachable from a profile.

`ProfileManager.validate_profile()` checks *structure only* — format tag,
version, name, and that rules have ids/conditions/actions. It validates none of
the things a generated profile gets wrong. The linter covers the four traps,
each verified in source:

1. **Silent zero** (`AIDecisionMaker.gd:416-426`). `_get_base_param_value`
   returns `0.0` for any parameter not in the profile's own `parameters` map or
   in `ai_config.json` — including every parameter whose only value is a
   `const` default. So `multiply WEIGHT_CONTESTED_OBJ by 1.2` does not scale
   8.0 to 9.6; it computes `0.0 * 1.2` and **turns the weight off**. `add` is
   the same trap quieter: it yields the bare addend.
2. **Unknown conditions pass** (`:346-391`). `_check_rule_conditions` is a
   `match` with no default arm, so a misspelled type is treated as **met** and
   the rule fires unconditionally. `round_gt` is not a type; `round_gte` is.
3. **Unknown actions vanish** (`:393-414`). An op that is not
   override/multiply/add is silently dropped.
4. **Dead `vp_*` conditions.** `_get_vp_diff` (`:1182-1189`) reads
   `meta.player1_vp`/`meta.player2_vp`; a repo-wide search shows those keys are
   written by exactly one test. Real VP is at
   `GameState.state.players[pk].vp`. So `vp_diff` is always 0 in play:
   `vp_ahead`/`vp_diff_gte` never fire, and `vp_behind`/`vp_diff_lte` fire
   *always*.

A search process generating profiles hits all four. Without the linter it
spends its evaluation budget measuring the noise floor and concludes, honestly
and wrongly, that nothing helps.

## Tests

```bash
python3 tools/ai_lab/build_index.py --selftest        # indexer + DuckDB views
python3 tools/ai_lab/validate_profile.py --selftest   # one case per trap
python3 tools/ai_lab/fixture_check.py                 # the M0 gate itself
godot --headless --path 40k --script tests/test_game_record_export.gd
```

## Determinism — and what it bought

The AI layer called the **global** unseeded RNG in 16 places. Difficulty score
noise is applied inside a movement-ordering *sort comparator*, so unit
activation order was itself stochastic: two same-seed games diverged at the
fifth movement decision and finished as different games, one stalled and one
not. Everything now draws from a seeded `RandomNumberGenerator`, and
`Array.shuffle()` is replaced by a deterministic Fisher-Yates for the same
reason.

Verified by `determinism_check.py`: six seeds played twice reproduce **exactly**
— 2,403 action lines and 568 decision records identical, at Hard with noise
active.

What that bought, immediately:

- **Common random numbers.** A paired M1/M2 pair now shares dice, deck *and*
  noise draws, so the difference isolates the profile. The null test (candidate
  identical to baseline) returns `E = 0.00, se = 0.00` with byte-identical
  margins per seed — which is also a free **no-op detector** for candidates that
  lint clean but change nothing.
- **Stalls reproduce from their own seed**, which is how the round-5 charge
  deadlock got root-caused.

## `timeout` is not `stalled`

A game that exceeds its wall clock while still making progress is reported as
`timeout` (exit 3), not `stalled` (exit 2). Conflating them makes the
stall-rate guardrail depend on machine load — three oversubscribed Ork lanes
produced three "stalls" that were nothing of the kind. **Do not run more lanes
than you have cores minus one.**

## Benchmark rules: legacy fixture vs `--bench-11e` (2026-10-29)

The mirror fixtures were saved before the 11e mission system, so on their own
they play **legacy Take and Hold** (5 VP per objective incl. home, 15/turn cap)
with the **10e tactical secondary deck**. Board, terrain, deployment
(Crucible of Battle) and armies are 11e. The AI then has no primary card to
plan for, so card-driven logic (diminishing returns, primary cap) never runs.

- `--bench-11e` (runner) / `--rules11e` (`ai_versions.py run`): 11e GDM
  primary cards from the disposition pairing (rotates through the 25 pairings
  by seed, or fixed with `--bench-dispositions=p1,p2`) and a fresh 11e
  secondary deck built by the normal Command-phase flow. Use this for any
  question about how the AI plays the real game.
- The RESULT/record carries `rules` (`11e`, `11e_primary_only`,
  `legacy_fixture`) and `dispositions`, so seasons cannot be mixed by accident.
- `perf_seconds` in the RESULT splits wall time: snapshot build,
  `get_available_actions`, `route_action` (engine), AI `decide_*` per seat and
  phase, `step_<ACTION>` per action type, and `check_all_objectives`.

Measured on one legacy game (seed 9101, 310 s, CPU-bound — time scale and
rendering do not matter): engine `route_action` 137 s, available actions 30 s,
AI decide 24 s, snapshot 5 s.

After OBJ-CACHE (2026-10-29: per-recompute model OC memo + signature cache in
MissionManager), the same 11e game on a free CPU: 341 s -> 244 s (-28%),
objective-control checks 94 s -> 10.6 s; identical result and decisions.
`--bench-no-objective-cache` / `--bench-verify-objective-cache` switch the
cache off or recompute on every hit (mismatches in `perf_seconds`).

## Value check: counterfactual rollouts (`rollout.py`, `rollout_batch.py`) — 2026-10-30

What is ONE decision worth? From a saved position (an LLM-critic case), play
the AI's own choice (branch A) and a proposed alternative (branch B, a one-shot
forced decision via `AIBenchmarkRunner --bench-override`, AIDecisionMaker
ROLLOUT hooks for move / shoot / charge) forward to a fixed horizon over paired
seeds, and compare `value = decider VP gained - opponent VP gained`.
`--bench-stop-round=N` stops the game the moment round N+1 begins (before it
scores), so the cut-off is exact.

Measured on 4 critic findings (12 seeds each):

| Case | Effect (B - A), end of next round | sd/seed | Full game | sd/seed |
|---|---|---|---|---|
| hold home -> advance to NML (flawed per reviewer) | -13.1 VP [-17.8, -8.4] | 8.3 | -11.4 [-28.6, +5.7] | 30.3 |
| Prosecutors -> home instead of centre | -0.3 [-1.7, +1.2] | 2.6 | | |
| shoot Guard Delta instead of Gamma | -2.1 [-4.0, -0.2] | 3.4 | | |
| do not charge | -0.1 [-2.4, +2.2] | 4.1 | +4.2 [-9.9, +18.3] | 24.9 |

The short horizon gives the same answer with 4-6x less noise per seed
(15-36x fewer seeds) and 2.7x faster games (~55 s vs ~160 s from round 1-2).
Two A runs on one seed are identical, and A replays the reviewed decision.

Pipeline (critic -> value -> fix -> bundle):
1. `40k/tools/llm_critic/sweep.py` — many critic games side by side (own
   `GODOT_MCP_PORT` each), 11e dispositions + official layouts; the reviewer
   returns its better option as a machine-readable `alternative`;
   `critic.py value` writes the rollout jobs.
2. `rollout_batch.py pack` copies the cases into `40k/tests/rollout_cases/`
   (tracked, so sibling cloud sessions can run them); `run --shard k/N` per
   machine; `table` ranks the effects.
3. Positive findings -> param-gated fixes with failing-first tests.
4. Bundle test (`ai_versions.py run --rules11e --fixture ...`, 3 matchups),
   then switch fix groups off with `--cand-profile` to attribute.

## Game forecast in the AI (`AIForecast.gd`) — 2026-11-20

`40k/scripts/AIForecast.gd` ports the Combat Calc forecast
(`server/public/calc/forecast.mjs`) to GDScript; `test_ai_forecast.gd` holds it
to the JS (card parity + 28 statistical scenarios, worst gap 0.45 VP). The AI
uses it behind params, **off** by default except FORECAST-PLAN (see "This turn only" below): `FORECAST_SECONDARIES`,
`FORECAST_TEMPO` (+ `FORECAST_CAL_A/B/SEAT`), `FORECAST_HORIZON_WEIGHT`,
`FORECAST_SURVIVAL`, `FORECAST_PLAN`. `FORECAST_LOG` (on) records one
forecast per own turn for `forecast_calibration.py`.

### Pre-filter result: the forecast cannot rank movement alternatives

`forecast_prefilter.py` (driving `40k/tests/forecast_prefilter.gd`) priced 138
of the 156 measured single-unit movement rollouts in
`r4_designs/measured_positions.json` (plan with vs without the redirect,
600 trials, survival projection on):

| | |
|---|---|
| Pearson r(predicted, measured E) | +0.00 (Spearman +0.02), n = 138 |
| redirect changes projected ownership | 29 cases, r = +0.05 |
| rollout-clear cases (CI excludes 0) | 34: sign agrees on 4, predicts 0 on 26 |
| screen "pred >= 2 VP" | 13 pass, mean measured E +0.20 |

The forecast sees objective ownership, not positions, so most redirects do not
change its inputs, and when they do the predicted swing is unrelated to the
measured one. Consequences: no rollout pre-filter; `FORECAST_PLAN` (which uses
the same prediction) stays off and is not worth benchmark time.

### Paired A/B results (E = candidate minus baseline, VP, side-swapped)

| Item | Profile | Custodes mirror | Asymmetric | Orks mirror | Pooled | Verdict |
|---|---|---|---|---|---|---|
| Secondaries (1 CP = 1.5 VP) | `forecast_secondaries_on` | −2.1 | −3.3 | +2.1 | −1.3 [−4.3, 1.7], 22 pairs | off |
| Secondaries (cheap CP) | `forecast_secondaries_cheapcp` | +0.15 | −2.6 | — | −0.9 [−4.5, 2.7], 16 pairs | off |
| Horizon 0.6 + survival | `forecast_horizon_survival` | −0.75 [−7.3, 5.8] | −2.6 [−11.5, 6.4] | — | −1.4, 16 pairs | off |
| Tempo (calibrated margin, B 1.5, seat 9.4) | `forecast_tempo_on` | +1.95 [−0.35, 4.25] | +3.0 [−0.25, 6.25] | −4.55 (10 pairs, sd 13) | −0.27, 30 pairs | off |

Tempo helped both fast fixtures (most Custodes pairs played identically; the
rest all favoured it) but lost the Ork mirror, where the plan is decided more
by melee trades than by how aggressive the AI is. Re-test it per faction if
the forecast ever models positions.

The secondaries arm swapped cards a third as often as the rule-based baseline
and scored ~1.2 fewer secondary VP per game: the forecast prices a fresh draw
lower than the heuristic does, and the heuristic is right more often.
Horizon/survival moved hold choices without improving results (asymmetric
below the −2 VP floor).

### Position look-ahead (`AIPositionSim.gd`) — 2026-11-20

The forecast sees ownership, not positions. `40k/scripts/AIPositionSim.gd`
plays the next player turns forward on the real positions in expected values
— units walk to objectives at their Move, shoot and charge what they reach,
one keeper stays on each objective — and hands the forecast per-turn ownership
chances and expected kills (`turn_plan`), scored over the window a rollout
measures (`end_round`, common random numbers). `AIDecisionMaker._possim_world`
builds its world from a snapshot; `FORECAST_POSSIM` (off) makes FORECAST-PLAN
price plans with it.

Tools (all under `tools/ai_lab/`, GDScript side in `40k/tests/`):

| Tool | What it does |
|---|---|
| `forecast_prefilter.py --trials 0 --cache DIR` | rebuilds the plan in every measured case once and caches the sim inputs |
| `possim_truth.py --out DIR [--alt]` | plays the AI's own line (or the forced alternative) once with `--bench-trace`: objective control and unit states at every turn end |
| `possim_sweep.py --cache --truth --variants` | re-prices all cases under any sim options in seconds: r vs measured E, ownership Brier vs the real games, units lost, and the forecast's ownership -> VP step on real ownership |
| `possim_paired.py --cache --a --b` | real change in ownership from the forced move (B minus A, same seed) vs the sim's |

What the real games (102 traces) fixed in the sim: control reach from a unit's
centre **and spread** (front models hold an objective while the centre is 6-7 in
short), an objective nobody out-OCs stays with its last controller ~70% of the
time, a unit alone on an objective stays (93%) while of units sharing one about
half move on, and damage x0.7 with half of in-range shooting having line of sight.

| Check | Result |
|---|---|
| Ownership per turn end vs real games (Brier, lower is better) | 0.26 vs 0.49 for "nothing changes"; 0.18 / 0.26 / 0.29 / 0.38 by turn |
| Same without the movement policy / without damage | 0.32 / 0.26 — where units walk matters, damage barely does |
| Forecast VP from REAL ownership and kills | primary r = 0.76 (MAE 2.5 VP), secondary r = 0.66. Under-scored as the AI plays them: Death Trap 8.3 vs 16.1, Triangulation 7.1 vs 12.8 — fixed below: r = 0.93, MAE 1.3 |
| Predicted vs measured rollout effect E, 138 cases (ceiling 0.78) | full sim r = +0.12 [-0.02, +0.27]; without damage +0.17 [-0.04, +0.35]; reach only +0.09. Ownership-only forecast: 0.00 |
| Real change from the forced move, today's AI (88 paired games, B minus A) vs the sim's | ownership at the end of THIS turn r = +0.43 [+0.08, +0.68]; over the whole window r = +0.07 [-0.14, +0.26]; sign right on 15 of the 46 cases where ownership really swung |
| Real ownership swing -> real VP change (what a perfect sim could reach) | r = +0.63 |
| In-game A/B, `forecast_plan_possim` (FORECAST_PLAN + FORECAST_POSSIM), asymmetric, 6 pairs | **-8.2 VP [-12.1, -4.3]**, all 6 pairs negative |
| Same, Custodes mirror, 30 pairs | +3.0 VP [-1.9, +8.0] (sd 13.2 a pair; 10 + 20 pairs) |
| Pooled, 36 pairs | +1.2 VP [-3.3, +5.6] — fails on the asymmetric floor (-2 VP) |

Caveat on E: the 138 cases were measured weeks ago on an older AI; rebuilt
today, the plan picks a different objective for the unit in question in about
half of them, so the other units' moves the sim is given are not the ones the
rollout played.

**Verdict on the full window: off.** The look-ahead predicts absolute
ownership well and the immediate effect of a move moderately, but not how the
difference between two plans plays out over the next round. In the A/B it
adopted ~2 swaps a game, each "worth" about +2 VP by its own estimate; most
undid the planner's coordination (a unit sent back to the objective it scored
best on, typically the centre) and the asymmetric fixture lost 8 VP a game.
There is still no rollout pre-filter: r vs measured E is 0.12-0.24 against a
0.3 bar.

#### This turn only — shipped ON (2026-11-21)

Playing only the CURRENT turn, reach only (`sim_turns` 1, no damage), then
holding that ownership to the end of the window keeps the part real games bear
out: r vs measured E +0.24 [-0.02, +0.45] (full window +0.13), and against the
real ownership swing over the window in the 88 paired games +0.24 (full window
+0.07). It says "no difference" far more often (24 of the 46 real swings) and
is rarely wrong when nothing changes (35 of 42).

| Paired A/B, E = candidate minus baseline (VP) | asymmetric | Custodes mirror | Ork mirror | pooled |
|---|---|---|---|---|
| full window, damage on (`forecast_plan_possim`) | **-8.2** [-12.1, -4.3], 6 | +3.0 [-1.9, +8.0], 30 | — | +1.2, fails the -2 floor |
| this turn only (`forecast_plan_possim_turn`) | +2.0 [-3.8, +7.8], 14 | +0.85 [-6.7, +8.4], 10 | +0.1 [-3.4, +3.6], 6 | **+1.2 [-2.4, +4.9], 30 pairs** |
| this turn only, runner-ups within the gap either way (`..._turn_close`) | -0.7 [-9.4, +8.1], 6 | — | — | 0.3 swaps a game: inert |

The this-turn version passes the gate (pooled > 0, no fixture below -2 VP, no
stalls) and is the default: `FORECAST_PLAN` 1, `FORECAST_POSSIM` 1,
`FORECAST_POSSIM_TURNS` 1, `FORECAST_POSSIM_DAMAGE` 0 (`forecast_plan_off`
turns it off for attribution). About one swap a game, mostly a fast unit
(Deffkoptas, Warbikers, Stormboyz, a Blade Champion) sent to take an objective
this turn; ~1 s per movement plan. The pooled interval includes zero — it is
shipped on the gate, not on significance — and the first 6 asymmetric pairs
were also used to pick this variant (without them: +0.8 over 24 pairs).
Windowed check: `tests/scenarios/sp/ai_forecast_plan_swap_11e.json`.

### Mission scoring fixed from recorded games — 2026-11-20

Every VP award in a recorded game carries its mission, timing and rule
(`vp_events`), so 246 season games give the real VP per rule per round. Four
cards were off by more than a couple of VP a turn:

| Card | Real (by round) | Was | Now |
|---|---|---|---|
| Death Trap, Booby Trap VP | 13.8 / 4.3 / 3.9 / 0.9 / 1.5 | one trap a turn, ~2.5 flat | up to 4 areas on turn 1, one or two in R2-R3, few after; kill bonus only in terrain trapped earlier (app and game) |
| Triangulation tiers | 0 / 6 / 8.7 / 9.3 / 9.3 | action from round 2 | `tune.tri_from_round` = 1 in the game (the engine offers it in round 1) |
| Reconnaissance Sweep quarters | 3+ quarters on 0 / 22 / 44 / 78 / 56% of turns, all 4 rarely | 50% flat, half of them all 4 | `tune.quarters_shape`, `tune.quarters_full` in the game |
| Gather Intel tokens | 12.2 in R2, then ~1 | 7 per held NML objective every turn | `tune.intel_once` in the game: one token per objective |

`AIForecast.build_from_snapshot` applies `GAME_TUNE`, `GAME_ACTION_P` = 0.9
(the AI completes an action on 86-100% of turns) and seeds mission progress
(`start.ms`) from the game's own bookkeeping; a bare `forecast()` keeps the
app's defaults and the parity test (31 scenarios, 3 new) holds the GDScript to
`forecast.mjs` for both. Checked out of sample on the 102 real-game windows:
primary VP r 0.76 -> **0.93**, mean abs error 2.5 -> **1.3** (Death Trap 15.4
vs 16.1, Triangulation 13.0 vs 12.8, Reconnaissance Sweep 5.8 vs 5.5).

Still off, not changed: secondaries run ~2 VP high per two-round window
(10.5 vs 8.4); Punishment's Condemned kills pay on 42-83% of turns against
~25% forecast; the AI never scores Vanguard Operation's terrain action or
Surveil the Foe's action, which the forecast credits.

## Not built yet

Nothing in the M0–M4 chain. Remaining known gaps are the instrumentation ones
in `research/audit_findings_2026-08-07.md` (F-03…F-07): shooting records the
assigned plan rather than the alternatives, and movement `score` is a copy of
`objective_priority` rather than a decomposition.

Two corrections to `research/ai_learning_framework_design.md`, from building
this:

- It estimates "104 parameters across 152 call sites". The call-site count
  measured **166** at `60ce588`, and after promoting hardcoded coefficients the
  surface is now **126 parameters across 189 call sites**. Run
  `params_manifest.py` rather than trusting any written figure.
- Its throughput planning assumes the Ork mirror throughout. The Custodes
  mirror resolves a full game in ~48 s against ~487 s, so screens and racing
  rounds belong there and the M3 estimate of "~300 games ≈ one overnight run"
  is closer to 20 minutes.
