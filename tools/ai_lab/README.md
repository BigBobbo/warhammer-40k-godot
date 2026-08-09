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
