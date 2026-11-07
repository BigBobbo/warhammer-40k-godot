# Adding an AI movement intent: implementation guide

Line numbers are as of HEAD `1c51d7b`. Each one was spot-checked against the code. File abbreviations:

- **ADM** = `40k/scripts/AIDecisionMaker.gd` (29,128 lines, all functions static)
- **AIP** = `40k/autoloads/AIPlayer.gd`
- **TM** = `40k/autoloads/TerrainManager.gd`
- **RE** = `40k/autoloads/RulesEngine.gd`
- **MP** = `40k/phases/MovementPhase.gd`
- **GEL** = `40k/autoloads/GameEventLog.gd`
- **GC** = `40k/scripts/rules/GameConstants.gd`

Units: 40 px = 1" (ADM:30).

Ground rules:
- The line numbers in `docs/ai_dossiers/movement.md` come from a 24k-line version of ADM. Do not use them.
- Only one agent may edit ADM at a time (`.llm/ai-overhaul-todo.md:107-112`). `40k/data/version_history.json` and `tools/ai_lab/ratchet.json` also cause merge conflicts.

---

## 1. Architecture in one page

AIPlayer asks for one action, executes it, then asks again.

```
decide()                                    ADM:3267   (phase/round change clears plans 3371-3388)
└ _decide_movement()                        6770
  ├ fallbacks: decline re-roll 6778 · Kunnin' 6792 · CONFIRM 6804
  ├ _decide_reserves_arrival                6815→7728  (only sample-and-score generator: 8137/8204)
  ├ _decide_transport_disembark             6823→8417
  ├ _select_movement_action                 6857
  │ ├ _build_phase_plan (once/phase)        3773  charge_intent · lock_targets · shooting_lanes
  │ ├ movement stratagems (may return)      6924
  │ ├ _calculate_enemy_threat_data          6931  EVERY call, centroid distance only
  │ ├ battle plan: built once, reused       6947-7011 (re-plan: new round / new movable unit / consumed unit movable again)
  │ │  ├ _evaluate_all_objectives           8926
  │ │  └ _assign_units_to_objectives        9834
  │ │     candidate loop (unit × objective) 9912-10598 → sort 10601
  │ │     P1 hold 10606 · P2 capture 10774 · P2.5 attack 11340 · backfill 11400
  │ │     P3 screen_denial / screen_protect / corridor_block / support / "none" 11438-11753
  │ │     candidates stashed for decision cards 11877
  │ ├ engaged units first → _decide_engaged_unit   7110→11958
  │ ├ order: tier (disembarked/normal/transport) → front-to-back → score   7123-7146
  │ └ executor: the FIRST unit returns an action    7158
  │    hold 7191 · advance 7203 · attack 7228 · screen 7275 · move/support 7306
  │    normal chain: on-objective hold 7347 · threat hold 7357 · hold-to-shoot 7410 · Heavy 7424
  │      · Lone Op 7436 · Deadly Demise 7466 · target shaping 7491-7593
  │      · _compute_movement_toward_target 7595 · charge follow-through 7600-7625 · return 7636
  │    fallback REMAIN_STATIONARY 7646
  ├ _ai_assignment attached 6848 → _finalize_movement_decision 3994
  │    (plan entry consumed 4038, OC ledger 3977/4044, decision record 4186)
  └ END_MOVEMENT 6854
AIP _execute_ai_movement 2733 → _try_stage_and_confirm 2881: STAGE_MODEL_MOVE per model (waypoint first),
   CONFIRM (a PARTIAL stage is still confirmed, 2948); on failure re-plan at 75/50/25% toward the old
   heading with NO threat/range data (2769-2815); an Advance is re-planned at the real roll, heading only (1657-1722).
```

### Plan actions

| action | produced by | executed as |
|---|---|---|
| hold | P1, or P3 "none" | REMAIN_STATIONARY (7191) |
| move | P2, P3 support | normal chain (7306-7645) |
| advance | P2 via `_should_unit_advance` (12650) | BEGIN_ADVANCE at M+2" toward `_objective_approach_target` (13193). Threat dodge on, no range clamp (7203). |
| attack | P2.5 `_melee_chase_gate` (2947) | Advance or Normal move at the target centroid, no threat dodge. Falls back to `move` (7228-7272). |
| screen | P3, pseudo objective id | Holds if within Engagement Range (ER) of the spot, else a Normal move, no threat dodge. Falls back to `move` (7275-7304). |

### Scoring

Each (unit, objective) candidate keeps an additive ledger: `score += _t_add(score_terms, key, Δ)` (2374), with `sum(score_terms) == score`.

| Term | Line |
|---|---|
| objective_priority | 10083 |
| oc_efficiency | 10087 |
| contest/reinforce race | 10150 / 10177 |
| distance_penalty | 10188 |
| reach_horizon (off) | 10201 |
| stay/horde | 10218 |
| reachability | 10233 |
| firing_position (range only) | 10251-10273 |
| threat_delta | 10275 |
| overwatch_risk (off) | 10290 |
| hidden_gain (off) | 10306 |
| charge_lane / shooting_lane | 10318-10349 |
| mission / secondaries | 10359-10559 |
| plan_earmark | 10568 |

- **Every geometric term is priced at `estimated_dest` (10249).** That point is a straight line toward the approach point, capped at M (plus Advance). It is not where the generator will actually put the unit.
- **Nothing in movement checks line of sight.**

### Generation

`_compute_movement_toward_target(unit, uid, target, move_in, snapshot, enemies, max_weapon_range=0, threat_data=[], objectives=[])` (14212, implementation at 14321) turns one target point into one vector from the unit's centroid. It then runs these stages in order:

1. Terrain path plus the legacy cover nudge of ±15/30° (14724 / 14817).
2. Dogleg around solid terrain (14364).
3. Climb-cost angles (14403).
4. Range clamp (14476), only if `max_weapon_range > 0`.
5. Threat dodge `_find_safer_position` (14486), only if `threat_data` is passed.
6. Placement ladder:
   - fractions 1→0.1 of 0.95×M (14518/14524)
   - formation move (14581)
   - ±45/90° (14606)
   - shrunken collision radii (14635-14720)

Per-model checks run in `_try_move_with_collision_check` (15405): ER, overlap, walls, MONSTER/VEHICLE crossing, coherency, and a final coherency gate (~15697). There is no "score N spots" evaluator in movement.

---

## 2. Where to plug a new intent

### Mechanisms

| Intent shape | Mechanism | Exact hook | Also touch |
|---|---|---|---|
| Bias **which** objective a unit takes | **A.** Plan term | Candidate loop next to `hidden_gain`, ADM:10306-10314 | Glossary label `AIReasoningGlossary.TERMS` (`40k/scripts/AIReasoningGlossary.gd:29`) |
| Keep the objective, change **where** the move ends | **B.** Target-shaping stage | Normal chain after the T7-14 block (7593), before 7595. Re-check the returned destinations as 7600-7625 does. | Notes only after the reset at 7500. Keep "moves toward \<obj\>" in `_ai_description`. |
| Micro-adjust every move's endpoint | **C.** Generator | `_find_safer_position` 28892 (F001 hook at 28966-28970) or `_find_cover_path` 14817 | Hits every caller. Runs only when threat rises by ≥1.0 (28908) or the direct path is clear (14745). |
| "Stay put because…" | **D.** Early return in the hold chain | Sibling of 7410 / 7424 | The plan still says MOVE and credits the objective's OC (4044). Prefer A+E. |
| New job for spare units | **E.** New P3 assignment plus executor branch | P3 at 11438 (copy `screen_denial`, 11542-11557). Branch after 7304. | Plan line 7097, `action_counts` 7035, card wording 4107-4113, support ledger 11507. The pseudo id must **not** start with `"obj"` (4044, 4096, 11507). |
| Engaged units | Fall-back target | `_pick_fall_back_target` 12429 / `_compute_fall_back_destinations` 12185 | Engaged units never reach the plan (9920, 11486). |
| Arrival spots | Reserves scorer | `_score_and_sort_reinforcement_candidates` 8204 (candidates 8073/8137) | 11e 8" rule: GC:49, `scripts/rules/movetypes/IngressMove.gd:44` |

### Suggested order for the named intents

Intents with the most existing machinery and the highest bench fire rate come first.

| # | Intent | Mechanism | Why here |
|---|---|---|---|
| 1 | Go Hidden | B + existing A (`hidden_gain`) + F002 | Weights already exist (ADM:2633-2647). Bench boards have ruins and Custodian Guard. |
| 2 | Move into cover | B (same spot sampler, cover predicate) + A | Cover = every model INFANTRY/BEASTS/SWARM inside **any** area, or not fully visible (TM:1388; rule text in `docs/rules/40k_11th_edition_core_rules.txt:2278`). |
| 3 | Move to get a shot | B (line-of-sight-aware sibling of T7-14) + A (refine `firing_position`) | Prior art: `tools/ai_lab/r5_designs/ranged_hold_vs_centre/` |
| 4 | Move into charge range | Extend the charge blend (7491-7548) + attack branch (7228) | Use edge distance + `_charge_roll_needed`. Prior art: `r5_designs/attack_move/` |
| 5 | Stage out of LoS | B (D for "stay") | The enemy moves before it shoots, so this is the weakest proxy. Conflicts with #3. |
| 6 | Screen vs deep strike | E: extend P3 (11438-11577) + `_calculate_denial_positions` 14929 | Fires only when the enemy has reserves. `FIX_SCREEN_VS_OBJECTIVE` was parked at 0.17 fires/game (`tools/ai_lab/results/2026-10-31/STATUS.md:394`). |

### Sketch 1: end the move in cover or Hidden (B + A)

**Constants.** Put these next to ADM:2633, with a rationale comment (what, evidence, "0 = previous behaviour"):

```gdscript
const FIX_MOVE_COVER: float = 0.0              # 1 = search a cover/Hidden end spot
const MOVE_COVER_MAX_LOSS_INCHES: float = 2.0  # objective progress it may give up
const MOVE_COVER_HIDDEN_WEIGHT: float = 3.0
const MOVE_COVER_COVER_WEIGHT: float = 1.5
const MOVE_COVER_LOSS_WEIGHT: float = 1.0      # per inch of progress lost
```

**Stage.** Insert after 7593:

```gdscript
var pre_cover_target := move_target
if get_param("FIX_MOVE_COVER", FIX_MOVE_COVER) >= 0.5 and GameConstants.edition >= 11 \
        and charge_intent.is_empty() and _unit_hidden_eligible(unit):
    var spot := _pick_cover_spot(unit, unit_id, centroid, move_target, target_pos, move_inches, enemies, snapshot)
    if not spot.is_empty():
        print("AIDecisionMaker: [FIX_MOVE_COVER] %s end spot old=%s new=%s" % [...])
        _move_shape_notes.append("Ends in %s: Hidden from %d of %d enemy shooters (%.1f\" less progress)" % [...])
        move_target = spot.pos
```

**`_pick_cover_spot`:**

1. **Baseline.** `base_end = _projected_move_end(centroid, move_target, move_inches * 0.95)` (14174). The 0.95 matches the ladder cap at 14518.
2. **Candidate points.** Aim for at most ~12:
   - For each `TM.terrain_features` piece within M+3", take the polygon point nearest `base_end` and push it one base radius inside. For Hidden, keep only pieces where `TerrainManager.category_allows_hidden(TerrainManager.category_of(p))` (TM:1049/792). For cover, any area counts.
   - Add 8 headings × 2" around `base_end`.
3. **Rejections:**
   - more than 0.95×M from the centroid;
   - `_move_path_blocked(centroid, p, kw, terrain, unit)` (15244);
   - objective gap (`_unit_gap_to_objective_px` 13163, on the translated copy) worse than at the baseline by more than `MOVE_COVER_MAX_LOSS_INCHES`;
   - losing control range that `_unit_has_model_in_control_range` (13269) had at the baseline.
4. **Score on a translated probe.** Move every alive model **and every attached-character model** by the same offset (the engine moves characters by the first bodyguard model's delta, MP:9253-9290).
   - Hidden: all models pass `tm.is_model_hidden(m, unit)` (TM:1001). Value it as `HIDDEN_WEIGHT × _hidden_immunity_fraction(unit, p, enemies)` (28548).
   - Cover: the share of the ≤4 nearest ranged enemy units for which `tm.unit_has_cover_11e(probe_unit, nearest_enemy_model)` (TM:1388) is true, × `COVER_WEIGHT`.
   - Subtract `LOSS_WEIGHT × loss` and the threat increase (28794).
   - Keep the best spot only if it beats `base_end`. Read every number through `get_param`.
5. **Optional side record.** `_record_choice("move_spot", unit_id, name, scored, key, {"unit_pos": [cx, cy]})` (2341), with `pos` on each candidate, gives board highlights. You must then add `"move_spot"` to `_SIDE_RECORD_TYPES` (ADM:3584) **and** to `SIDE_RECORD_TYPES` in `40k/scripts/AISuggestionTestCases.gd:52`.

**Follow-through.** After 7595, copy the pattern at 7600-7625:
- rebuild the probe from the **returned** `model_destinations` (plus characters);
- if the unit is no longer Hidden or covered, recompute toward `pre_cover_target`;
- `push_front` a note such as "Dropped the cover spot: …".

**Plan level.** Add a `cover_gain` term next to `hidden_gain` (10306), behind the same flag. Use a single probe at `estimated_dest`.

**Profile.** `40k/tests/bench_profiles/move_cover_on.json` sets `FIX_MOVE_COVER: 1` and `HIDDEN_FORFEIT_PENALTY: 3.0`. Without F002 (16779) the unit walks into Hidden and then shoots it away (TM:1024-1029).

**Exam.**
- Setup: Custodian Guard 4-6" from a ruin that lies ≤2" off its line to an uncontested objective, with one enemy shooter 18-24" away.
- Assert every alive model passes `TerrainManager.is_model_hidden(m, u)`.
- Guard: objective gap ≤ straight-line gap + 2".

### Sketch 2: move so a ranged weapon has a shot next phase (B)

**Constants:** `FIX_MOVE_FOR_SHOT = 0.0`, `MOVE_FOR_SHOT_MAX_LOSS_INCHES = 3.0`, `MOVE_FOR_SHOT_PROBES = 8` (read with `get_param_int`).

**Trigger** (after 7593). All of these must hold:
- `has_ranged_weapons`, after the transport overrides at 7392-7404;
- `charge_intent.is_empty()`;
- plan action is `move` or support (an Advance forfeits non-[ASSAULT] shooting);
- **no** eligible target from `base_end`.

**Engine predicate on a hypothetical board.** Use shallow copies (pattern at ADM:21686-21706):

```gdscript
static func _has_shot_from(uid: String, dests: Dictionary, snapshot: Dictionary, only_ids: Dictionary) -> bool:
    var units: Dictionary = snapshot.get("units", {}).duplicate()
    var u: Dictionary = units[uid].duplicate()
    var ms: Array = []
    for m in u.get("models", []):
        var m2: Dictionary = m.duplicate()
        var mid := str(m.get("id", ""))
        if dests.has(mid):
            m2["position"] = Vector2(float(dests[mid][0]), float(dests[mid][1]))
        ms.append(m2)
    u["models"] = ms
    var f: Dictionary = u.get("flags", {}).duplicate()
    f["in_engagement"] = false            # RE:7148 reads it; only refreshed at shooting entry
    u["flags"] = f
    units[uid] = u                        # + attached-character units, moved by the bodyguard delta
    var hypo: Dictionary = snapshot.duplicate()
    hypo["units"] = units
    return not _rules_engine().get_eligible_targets(uid, hypo, true, only_ids).is_empty()
```

- `only_ids` = enemies whose nearest model is within `RE.max_ranged_weapon_range_inches(uid, snapshot)` + M. RE:6693 counts attached-character guns; `_get_max_weapon_range` (13517) does not.
- **Candidates:** the 9-heading fan of `_find_firing_position_toward_objective` (13848) plus 0.75×M versions, each as a translated destinations dict, filtered by progress loss.
- **Cost control:** pre-filter with `tm.is_obscured_between(probe_centroid, enemy_centroid)` (TM:976), and make at most `MOVE_FOR_SHOT_PROBES` engine calls.
- **Pick:** the least-loss spot that has a shot, tie-broken by `_estimate_weapon_damage` (17984).
- Set `move_target`, add a note ("Angled N° so \<target\> is visible next phase"), and print `[FIX_MOVE_FOR_SHOT] … old=no_shot new=<id>`.

**Re-check after 7595.** Call `_has_shot_from` on the **returned** destinations. Three later stages can undo the shot:
- the legacy cover nudge (14745-14749) rotates clear-path moves up to 30° to put terrain between the unit and an enemy, which can block the shot;
- the threat dodge can cut the move to 50-75%;
- the range clamp can shorten it.

If the shot is lost, fall back to the pre-shot target.

**Optional plan term.** Behind the same flag, let `firing_position` (10251) count only enemies where `is_obscured_between(estimated_dest, enemy_centroid)` is false.

**Exam.**
- Setup: the unit's only enemy is behind a dense ruin, both from its start and from its straight-line endpoint.
- Assert after the phase that `RulesEngine.get_eligible_targets(uid, GameState.state, true)` is non-empty.
- Guard: gap ≤ straight-line gap + 3".

---

## 3. Conventions checklist

- **Knob shape.**
  - Behaviour switch: `const FIX_<NAME>: float = 0.0`, read as `get_param("FIX_<NAME>", FIX_<NAME>) >= 0.5` (1553). Weights are plain number consts. Integers use `get_param_int` (1576).
  - Write a comment block like ADM:1749-1764.
  - The default argument must be a bare const or a literal. Otherwise `tools/ai_lab/params_manifest.py` (:38-40) cannot see it, and `validate_profile.py` (:137-141) rejects any profile that names it.
- **Ship OFF.** At 0 the AI must play byte-identically (`tools/ai_lab/protocol_v2.md:73-74`; ADM:2614-2630).
  - Add an opt-in profile `40k/tests/bench_profiles/<name>_on.json` in the format of `yt_findings_on.json`.
  - Lint it with `python3 tools/ai_lab/validate_profile.py <file>`. CI lints every bench profile (`.github/workflows/ai-lab.yml:62`).
  - Add a row to `docs/AI_TUNING.md` (:462-467).
- **No bare literals** on `score/value/priority +=` lines (`tools/ai_lab/tunability_audit.py:26-30`). `ratchet_check.py` fails if the count of untunable numbers rises or the number of `_t_add` call sites falls (:93-117).
- **Rule DSL traps.** `multiply`/`add` on an undeclared parameter starts from 0 (ADM:1518-1528). An unknown condition type counts as met (ADM:1448).
- **Naming.** Avoid "intent" in code and UI text. It already names the movement ledger (`_record_movement_intent`, 3977) and is the player-facing word for plan earmarks (`40k/docs/PLAN_FORMAT.md:433-437`).
- **Ledger.** Only `_t_add`/`_t_mul` values go in `score_terms`. Descriptive numbers go in the record's `context`. A descriptive key placed in `score_breakdown` needs two entries: `NON_ADDITIVE_KEYS` (`tools/ai_lab/validate_records.py:82-89`) and a glossary entry with a format other than `"pts"`. (Exam mv04 has no list of its own since EXAM-DET-1: it skips whatever `AIReasoningGlossary.is_addend` rejects.)
- **Decision records.** Movement records come only from `_finalize_movement_decision` (4084-4198), and only for units with more than one objective candidate. A new pass sets `assign_pass`, which becomes `assigned_by` on the card. New decision types go through `_record_choice` (2341).
- **Player-visible text.**
  - Plan card: `_add_thinking_step` (2810). The header starts with "Movement plan". Unit lines are `"  <name> (OCn): VERB <target>, … — reason"`. AIP:2323-2339 slices the card on these, and GEL:758-813 matches them.
  - Action line: `_ai_description`. Keep "moves toward / advances toward / holds \<obj_id\>" when the objective is unchanged, or the integrity gate reports a mismatch.
  - Move shape: `_move_shape_notes.append()` (516). These render in Suggest (K) (`AISuggestionBreakdownPanel.gd:576-581`) and as "\<unit\> move: …" steps (7635). A new branch must return `_ai_move_adjustments` itself (7640).
- **Fire-count tag.** Print one `[FIX_<NAME>] <unit> <what> old=… new=…` line per evaluation in which the fix changes a value (`protocol_v2.md:21-24`). Use **one** channel: `print()` (house style), or `_debug_log_info()` (ADM:61), which DebugLogger echoes to stdout in debug builds (`DebugLogger.gd:141,183`). Never both, or the count doubles.
- **Debug logs.** Never remove existing ones. New diagnostics go through `_debug_log_info()` so they reach `debug_*.log`; game-log entries already reach it (GEL:472-476).
- **Static caches** must be added to `reset_caches()` (568) **and** to `_snapshot_planning_state` / `_restore_planning_state` (3675/3722).
- **Autoloads** only through the late-bound getters (`_terrain_manager` 83, `_rules_engine` 51, `_measurement` 69). Never write `AIDecisionMaker.` inside ADM: `ai_versions.py:55-57` warns that such a copy would call the current code.

---

## 4. Validation recipe (in order)

### 0. Baseline, once per session

```bash
export PATH="$HOME/bin:$PATH"; cd /home/user/warhammer-40k-godot
(cd 40k && godot --headless --import)            # fresh container only: a few minutes
python3 tools/ai_lab/params_manifest.py && python3 tools/ai_lab/ratchet_check.py && python3 tools/ai_lab/check_exams.py   # seconds
bash 40k/tests/run_exams.sh > /tmp/exams_before.txt   # 10 gated exams, 3 lanes, ~10 min
```

Write down what is already red. I did not run these; by reading the code they are probably red already:

- **mv04 exam.** Every candidate carries `gap_inches` (ADM:10580 → 4148), and mv04's SKIP list lacked it. Confirmed red (54 mismatches) and fixed 2026-11-07 (EXAM-DET-1): mv04 now asks `AIReasoningGlossary.is_addend`. mv01/mv03 were also red on a fresh user dir (stale board coordinates) and were re-authored.
- **Six scenarios** call `AIPlayer.configure(types, {…})` with two arguments; AIP:254 takes one. These are `ai_battle_plan_log_integrity`, `ai_coordinated_movement`, `ork11e_ai_attacker_reactive_dialog_shown`, `pm2a_ai_deploys_from_plan`, `pm2b_formations_from_plan` and `pm3_earmarks_bias_assignment`. Two more, `ai_move_shape_telemon_gantry` and `ai_suggestion_fight_multi_target`, call `request_suggestion(-1, id)` with the same problem.
- **Two headless tests already fail:** `test_ai_cover_scoring.gd` 21/3 and `test_ai_threat_range_awareness.gd` 34/3 (`40k/tests/ci/direct_known_failures.txt:30,35`).

### 1. Aspirational exam first (it must fail)

Create `40k/tests/exams/aspirational/mvNN_<name>.json`:

- Keys: `id`, `covers`, `fixture`, `"phase": 7`, `player`, `seed`, `setup`, `assert[]` (each with `equals`, `expect_min` or `expect_max`), `rationale`, `owner`.
- Turn the switch on **in setup**. Setup runs after configure and profile loading (`40k/autoloads/AIBenchmarkRunner.gd:407-462`):
  `AIDecisionMaker.load_player_profile(1, {"parameters": {"FIX_<NAME>": 1.0}})`
  Load it inline: a profile file naming a parameter nothing reads yet fails the profile linter.
- Assert the decision **and** a guard against degenerate play.
- Move only the units the exam is about. Never teleport whole armies on the Ork fixture.

Run `python3 tools/ai_lab/check_exams.py && bash 40k/tests/run_exams.sh mvNN_<name>`. It should FAIL (~2 min; Ork exams up to 12 min).

### 2. Implement behind the flag

Re-run the static gates, plus `validate_profile.py` on the new `_on` profile.

### 3. Exam passes

`bash 40k/tests/run_exams.sh mvNN_<name>` should PASS. Then `git mv` the file into `40k/tests/exams/`. Set the switch to 0 once locally: it must fail again, which proves the switch made the difference.

### 4. Full exam suite

Run `bash 40k/tests/run_exams.sh` and `--aspirational`. There must be no new failures against step 0. For screening intents also run `--slow` (sc02 on the Ork fixture; more than 25 min).

### 5. Headless tests

Run each with `cd 40k && godot --headless --path . -s <file>` (~11 s boot).

**New test** `tests/unit/test_ai_fix_<name>.gd`, copied from `tests/unit/test_ai_fix_obj_area_hold.gd`:
- Include ON cases, `test_param_zero_restores_old_reads`, and `test_guard_*` checks.
- Set `GameConstants.edition = 11` and `tm.terrain_features` explicitly (that file's lines 76-83).
- Call `RulesEngine.clear_los_memo()` after changing terrain.
- Erase the `_config_overrides` key at the end.
- Print "N passed, M failed" (a 0/0 result counts as a failure).
- Add the file to TESTS in `40k/tests/run_pretrigger_tests.sh:184-373`.

**Regression set:**
- `tests/test_ai_movement_coordination.gd`
- `tests/test_ai_battle_plan.gd`
- `tests/unit/test_ai_plan_earmarks.gd`
- `tests/test_oc_per_model_14_02.gd`
- `tests/test_iss052_hidden_11e.gd`
- `tests/unit/test_ai_movement_decisions.gd`
- `tests/unit/test_ai_multi_phase_planning.gd`
- `tests/unit/test_ai_objective_race.gd`
- `tests/unit/test_ai_fall_back_positioning.gd`
- `tests/test_ai_objective_gap_advance.gd`
- `tests/test_ai_objective_assignment_fixes.gd`
- `tests/unit/test_ai_cover_scoring.gd` and `tests/unit/test_ai_threat_range_awareness.gd`, which must stay at 21/3 and 34/3.

The full gated suite is optional: `AUDIT_SHARD=i/4 bash 40k/tests/run_pretrigger_tests.sh` (188 files, ~35 min if run in series).

### 6. Windowed scenario and screenshot

Create `40k/tests/scenarios/sp/ai_<name>.json` with `"edition": 11` and `"disable_ai": true`. Templates:
- `ai_objective_race_long_trip.json` for the Suggest (K) path;
- `ai_hidden_awareness_11e.json` steps 5, 22 and 23 for "profile ON → clear → shipped default unchanged → reload".

Suggest (K) path, step by step:

1. `AIPlayer.configure({1: "HUMAN", 2: "HUMAN"})` with **one** argument.
2. Load the profile **after** that, because configure wipes profiles (AIP:323). Use `"multiline": true`; ScenarioRunner never auto-detects multi-line scripts.
3. `GameState.set_active_player(1)`, then `PhaseManager.transition_to_phase(7)`.
4. `main.refresh_ai_suggestion_button()`. Optionally focus a unit with `main._on_ai_suggestion_unit_focus("U_X")`.
5. `click_node` on `/root/Main/HUD_Right/VBoxContainer/AIControlsRow/AISuggestionButton`.
6. Assert `main._ai_suggestion_panel.full_text.contains("<your note>")`.
7. Add a `screenshot` step.

For a live AI turn instead:
- configure P2 as `"AI"`, then `transition_to_phase(7)`;
- `wait_for_script` on `return GameState.get_current_phase() != 7` with `timeout_s`;
- assert the per-model end state and `GameEventLog.movement_plan_integrity()["mismatches"].size() == 0`.

Run it and update coverage:
- `bash 40k/tests/run_scenario.sh tests/scenarios/sp/ai_<name>.json` (1-3 min). PNGs land in `user://test_results/scenarios/`.
- `python3 40k/tests/sync_coverage.py && python3 40k/tests/check_coverage.py`.

For the end-of-task summary, also capture a live screenshot through the MCP bridge: launch `godot --path 40k --rendering-method gl_compatibility > /tmp/game.log 2>&1 &`, wait for `GodotMCP] Listening`, drive the same path, then `capture_screenshot` and `verify_delivery`.

### 7. Short AI-vs-AI A/B

This box has 4 cores, so use `--lanes 3`. Time per game per lane: ≈3-5 min Custodes, ≈10 min asym, ≈16-20 min Orks. Use `ai_versions.py`: `run_paired.py` and `run_lanes.py` cannot play the 11e mission rules.

**a. OFF is a no-op** (6 games, ~10 min). This only covers changes inside ADM.

```bash
python3 tools/ai_lab/ai_versions.py extract SHIP=<commit-before-change>
python3 tools/ai_lab/ai_versions.py run --base SHIP --cand HEAD --rules11e --fixture mirror_custodes_2000_postdeploy \
  --season bench_data/<name>_null --seed-base 95000 --pairs 3 --lanes 3 --max-seconds 1800
```

E must be 0.0 with SE 0.0 (identical margins; `tools/ai_lab/README.md:312-315`).

**b. Fire gate** (protocol V2-1; 6 games, ~30-40 min). Run one pair per fixture:

| Fixture | Seed | Max seconds |
|---|---|---|
| mirror_custodes_2000_postdeploy | 91000 | 1800 |
| asym_2000_postdeploy | 91100 | 1800 |
| mirror_orks_2000_postdeploy | 91200 | 2400 |

```bash
AI_LAB_KEEP_LOG_GREP='[FIX_<NAME>]' python3 tools/ai_lab/ai_versions.py run --base HEAD --cand HEAD \
  --cand-profile 40k/tests/bench_profiles/<name>_on.json --rules11e --fixture F --season bench_data/<name>_gate_F \
  --seed-base S --pairs 1 --lanes 3 --max-seconds 1800
grep -h '\[FIX_<NAME>\]' bench_data/<name>_gate_*/_logs/*.log | uniq | wc -l    # divide by 6
```

Below 1.0 line per game means PARK: keep the code, leave the parameter at 0. Screening intents should use the `*_reserves_postdeploy` fixtures.

**c. Directional A/B** (12-24 games, 20-60 min). Same command as (b) with `--pairs 6 --seed-base 95000`, on Custodes and optionally asym. Read the result with `ai_versions.py report --season …`:

- E = (M1 − M2)/2 VP per seed; E > 0 means the candidate is better.
- Per-seed SD is 9-15 VP, so SE ≈ 4-6 VP at 6 pairs. That can only show a disaster.
- Any `stalled` or `error` game is a hard fail; reproduce it from its seed.
- `timeout` means the box was oversubscribed, not an AI defect.
- A 95% CI wholly below 0 means stop and investigate. Any other result means "no evidence": the feature ships at 0 and you report the numbers.
- Turning it ON needs V2-2: 124/248/372 pairs, z ≥ 3.710/2.512/1.993, and no fixture CI wholly below 0 (`protocol_v2.md:30-51`). That is not one agent's job.
- `rollout.py` cannot value a spot: its move override only takes an objective plus a mode (ADM:7164-7178).

### 8. version_history

Prepend an entry to the `releases` array in `40k/data/version_history.json` (newest is 1.73.3, 2026-11-07).

- Bump the minor version only if the default game changes.
- Dormant work needs no entry, or an "Under the hood … switched OFF by default" bullet (precedent: 1.28.6).
- Any new text visible with the flag OFF counts as player-facing: it needs an entry and a windowed scenario.
- Turning a feature ON needs an entry, a scenario, a screenshot, and updates to unit tests that assumed it was off (`protocol_v2.md:114-116`).

---

## 5. Reusable helpers index

| Function | file:line | Answers |
|---|---|---|
| `_compute_movement_toward_target` | ADM:14212 | Legal per-model destinations toward one point |
| `_projected_move_end` / `_destinations_centroid` / `_destinations_max_move_inches` | ADM:14174 / 14181 / 14194 | Straight-line endpoint; summary of returned destinations |
| `_move_path_blocked` | ADM:15244 | The planner's terrain path rule |
| `_is_position_near_enemy` | ADM:15329 | Within Engagement Range of an enemy |
| `_find_safer_position` | ADM:28892 | Threat-dodge micro-search |
| `_get_alive_models_with_positions` / `_get_unit_centroid` / `_get_model_position` | ADM:24399 / 24414 / 24311 | Geometry basics |
| `_objective_approach_target` | ADM:13193 | Shortest aim onto an objective's footprint |
| `_unit_gap_to_objective_px` / `_unit_has_model_in_control_range` / `_unit_on_objective` | ADM:13163 / 13269 / 13352 | Engine-exact objective range (terrain-area aware) |
| `_objective_pos_by_id` / `_nearest_objective_pos` | ADM:414 / 13985 | Objective lookup |
| `MissionManager.get_level_of_control` | `40k/autoloads/MissionManager.gd:863` | Side-effect-free control check; never call `_check_objective_control` (878) |
| `_calculate_enemy_threat_data` / `_evaluate_position_threat` | ADM:28695 / 28794 | Distance-only danger |
| `_charge_roll_needed` / `_charge_success_probability` | ADM:18840 / 18928 | 11e charge odds from edge distance |
| `_get_closest_model_distance_inches` / `_get_closest_model_pair_info` | ADM:19697 / 19703 | Edge distance between units |
| `_get_charge_intent` | ADM:3961 | Planned charge |
| `RE.eligible_to_charge` | RE:12050 | Advance / Fall Back gating |
| `RE.get_eligible_targets(actor, board, first_only, only_ids)` | RE:7137 | Legal ranged targets (range + LoS + Hidden + rules) |
| `RE.unit_sight_line(a, b, board, false, max_pairs)` | RE:6641 | Can these units see each other? |
| `RE.max_ranged_weapon_range_inches` / `RE.unit_within_weapon_reach` | RE:6693 / 6718 | Range including attached-character guns, no LoS |
| `RE.snap_shooting_targets_11e` | RE:1475 | Fire Overwatch legality |
| `_get_enemies_in_weapon_range` / `_clamp_move_for_weapon_range` / `_find_firing_position_toward_objective` | ADM:13760 / 13780 / 13848 | Centroid range only |
| `_get_unit_half_range_data` / `_find_best_half_range_position` | ADM:13669 / 13702 | Rapid Fire / Melta half range |
| `_estimate_weapon_damage` / `RE.preview_attack` | ADM:17984 / RE:17805 | Expected damage |
| `TM.area_at` / `TM.category_of` / `TM.category_allows_hidden` / `TM.pieces_model_within_of` | TM:847 / 792 / 1049 / 927 | Terrain membership |
| `TM.is_model_hidden` / `_position_would_be_hidden` (one probe) / `_hidden_immunity_fraction` / `_hidden_gain_value` / `_hidden_forfeit_cost` | TM:1001 / ADM:28515 / 28548 / 28578 / 28592 | Hidden (13.09) |
| `TM.unit_has_cover_11e(unit, attacker_model)` | TM:1388 | Benefit of cover (13.08), per firing model |
| `TM.model_visible_11e` / `TM.model_fully_visible_11e` / `TM.is_obscured_between` | TM:1209 / 1215 / 976 | Visibility; the last is a one-line pre-filter |
| `TM.detection_range_inches_for` / `TM.can_move_through_11e` | TM:1069 / 1257 | Detection range; 13.06 movement |
| `_get_enemy_reserves` / `_is_screening_candidate` / `_calculate_denial_positions` / `_compute_screen_position` / `_calculate_corridor_blocking_positions` | ADM:14884 / 14911 / 14929 / 15028 / 15092 | Screening |
| `_deep_strike_denial_radius_px` / `_screen_spacing_px` / `IngressMove.validate_setup` | ADM:28452 / 28484 / `IngressMove.gd:44` | Where an enemy can legally drop |
| `get_param` / `_t_add` / `_record_choice` / `_add_thinking_step` / `_debug_log_info` | ADM:1553 / 2374 / 2341 / 2810 / 61 | Conventions plumbing |

---

## 6. Pitfalls found in the code

### Performance

- `_compute_movement_toward_target` is the hot path.
  - Its ladder has about 78 rungs, each re-searching about 392 positions per model.
  - On the 154-model Ork board, about two unit moves took 3.08M obstacle iterations (ADM:16000-16011), and one decision ran for minutes (ADM:2213-2222).
  - Never call it once per sampled spot. Sample with cheap probes, call it once, and re-check the result.
- `threat_data` is rebuilt on every `decide()` (6931). Only terrain-only precomputation is safe to cache for a phase.
- The RE line-of-sight memo has no eviction: 200k cap at RE:6820, epoch guard at 6825. Snapshots nest terrain under `board.board`, so the guard never fires. Only `terrain_loaded` clears the memo (TM:73).
  - Hypothetical probes add new memo keys. Bulk sampling can fill the memo, after which every real query is a miss: slow, not wrong.
  - In tests, after assigning `tm.terrain_features` directly, call `RulesEngine.clear_los_memo()`.
- TM visibility costs:
  - `model_visible_11e` draws 9 lines and rebuilds the group map on every call (TM:1196-1198).
  - `unit_has_cover_11e` costs about 1.5-3.5 ms per firing model (RE:17999).
  - `detection_range_inches_for` makes six `load()` calls per call.
- A whole-army `get_eligible_targets` sweep once took 3-32 s (RE:6807). Always pass `first_match_only` and `only_target_ids`.

### Caches and state

- `_move_shape_notes` is reset only at 7500 and 7611. Notes added earlier are lost, and only the normal branch turns them into `_ai_move_adjustments`.
- Suggest (K) runs `suggest_action` (3469) and restores only the state listed in `_snapshot_planning_state`. Any other new static leaks into the live AI.
- TM predicates read the **live** `TM.terrain_features`; the generator reads `snapshot.board.terrain_features`. Headless tests must set both.
- `_finalize_movement_decision` credits any `obj*` id with hold/move/advance as incoming OC (4044). An intent that leaves the objective but keeps the assignment overstates OC for the units that move after it.

### Coherency and placement

- 11e coherency requires each model within 2" of another and within 9" of every other (`scripts/rules/AttackSequence.gd:229`; GC:67-77). Cover needs **every** model. Translate the whole unit rather than steering single models.
- AIP confirms partial stages (AIP:2948), so the per-model end state can differ from the plan. Assert per model in exams and scenarios.
- The returned destinations are not the target you passed:
  - the legacy cover nudge rotates clear-path moves up to 30° (14745);
  - relaxed rungs can turn a move up to 180°;
  - AIP retries drop threat and range data (AIP:2808-2811);
  - Advances are re-planned toward the heading only (AIP:1683-1722).
- The AI plans with raw `meta.stats.move` (7204, 7308), never `MP.get_unit_movement` (MP:203), and caps each model at 0.95×M.
- With `FIX_MOVE_TERRAIN_11E` = 0, the planner blocks any piece whose `can_move_through` map lacks one of the unit's keywords, including ending inside it (15267-15302). Check each candidate spot with `_move_path_blocked`.

### Attached characters

- They are left out of the destinations (14328-14333); the engine moves them at CONFIRM by the first bodyguard model's delta (MP:9253). Include them in "every model" checks, and in hypothetical boards for weapon and LoS checks.
- The standard bench fixtures have no attached leaders and no [HEAVY] weapons (`tools/ai_lab/tuning_track_proposal.md:24`). The reserves fixture has an attached Blade Champion.

### Engaged and constrained units

- Engaged units skip the plan entirely (9920, 11486, 7110).
- A unit that Falls Back cannot shoot or charge. A unit that Advances cannot charge and fires only [ASSAULT] weapons. Do not route shot-seeking or charge-range intents through `advance`.

### Edition and rules gates

- `GameConstants.edition` defaults to 11 (GC:27). Below 11, TM predicates give permissive answers: `model_visible_11e` is true, while `unit_has_cover_11e` and `is_model_hidden` are false. Gate 11e-only logic explicitly.
- The threat model's charge reach is centroid distance + 12" + ER (28714). In 11e a charge needs a roll at least equal to the edge distance (`_charge_roll_needed`, 18840).
- Hidden means light **or** dense terrain (TM:990-995, 1043). The comments at ADM:2596-2600 and 10306-10308 still say dense only.
- Hidden is per model and uses base overlap; cover uses each model's centre (`area_at`).
- Hidden reads the live turn index (TM:1024-1029). Shooting this turn voids Hidden next turn (`40k/phases/ShootingPhase.gd:6084`). Live shooting never writes `flags.shot_recently`, so the checks at ADM:28597 and 28615 never fire.
- `_hidden_immunity_fraction` compares centroid distance with the base 15" and has no LoS or enemy-movement model. Its Gone to Ground comment (28547) is wrong. LoS from enemies' current positions is a weak proxy for next turn.

### Small traps

- `_find_safer_position` measures progress to the objective nearest the desired spot, not the assigned one (28953).
- Corridor blocks stand 55% of the way from the enemy toward the objective (15141); the constant's comment (2682) says the reverse.
- Screening can never fire on the Custodes mirror (`40k/tests/exams/slow/README.md`). Use the reserves fixtures or the Ork mirror.