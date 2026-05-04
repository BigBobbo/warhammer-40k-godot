# WH40K Game Audit — 2026-05

**Started:** 2026-05-03
**Method:** MCP-driven live-game validation against Wahapedia 10e core rules + faction quirks
**Armies:** Adeptus Custodes (Shield Host) vs Orks (War Horde) — default rosters in `40k/armies/`
**Deployment:** Crucible of Battle
**Terrain:** layout_2

## Status

| Tier | Status | Issues filed |
|------|--------|--------------|
| 0 — Infrastructure | ✅ done | #329 |
| 1 — Phase architecture | ⚠️ done with caveats | #330, #331, #332, #333 |
| 2 — Per-phase rules | not started | — |
| 3 — Unit abilities | not started | — |
| 4 — Cross-phase edge cases | not started | — |
| 5 — Save/load round-trips | not started | — |

## Baseline

- **Pregame baseline:** `40k/saves/audit_baseline_pregame.w40ksave` (123 KB) — Round 1 FORMATIONS, 26 units (9 Custodes + 17 Orks), no formations declared, all UNDEPLOYED
- **Post-deployment baseline:** *deferred — blocked by issue #331 until DeploymentPhase auto-complete is fixed; will rebuild once that's in*

To restore pregame baseline programmatically:
```
get_node('/root/GameState').initialize_default_state('crucible_of_battle')
get_node('/root/PhaseManager').set('game_ended', false)  # workaround for #330
get_node('/root/PhaseManager').transition_to_phase(0)
```

## RNG / Determinism — issue #329

Single-player dice rolls are non-deterministic:
- Only `MovementPhase.gd:1381` honors `payload.rng_seed`
- Charge / Shooting / Fight / Command / RollOff phases ignore the seed
- 8 direct `randi()` bypasses + 3 stratagems + 2 abilities also non-deterministic

Until #329 is patched, dice tests use **multi-trial sampling** for distribution checks; tests requiring exact outcomes are deferred with status `needs-determinism`.

---

## Tier 0 — Infrastructure

| ID | Item | Status | Notes |
|----|------|--------|-------|
| t0.a | RNG seed passthrough audit | done | Issue #329 filed; only MovementPhase honors `payload.rng_seed` |
| t0.b | Audit baseline save | done | Pregame baseline written; post-deploy deferred until #331 fixed |
| t0.c | Audit log structure | done | This file + per-tier sections |

---

## Tier 1 — Phase architecture

### t1.a — Phase ordering matches WH40K core
| Aspect | Method | Result |
|---|---|---|
| In-turn order (Cmd→Mvt→Sht→Chg→Fgt→Sco) | code review of `PhaseManager._get_next_phase()` + log replay from prior session | ✅ matches Wahapedia |
| Pre-game order (Formations→Deployment→Redeployment→RollOff→Scout→Command) | code review + live walk from FORMATIONS to ROLL_OFF | ⚠️ runs but DEPLOYMENT/REDEPLOYMENT silently skip — issue #331 |
| SCOUT fires only once per game | code review (no path returns SCOUT after first run) | ✅ correct |
| `MoralePhase` not in active flow | enum still present, but `_get_next_phase` only returns MORALE→DEPLOYMENT (dead) | ⚠️ deadcode — issue #332 |
| `SCOUT_MOVES` reachability | enum present, registered, but no caller returns SCOUT_MOVES | ⚠️ orphan — issue #332 |

### t1.b — END_PHASE idempotency (regression on issue #322)
| Aspect | Method | Result |
|---|---|---|
| `END_<PrevPhase>` accepted as no-op by successor phases | code review of PR #326 (Movement, Shooting, Charge, Fight, Scoring, Command) + prior-session integration test | ✅ in place; deferred re-verification on baseline since live test would require routing through #331 |

### t1.c — Round 5 game-end (regression on issue #319)
| Aspect | Method | Result |
|---|---|---|
| Game ends at P2's END_SCORING in Round 5 | code review of PR #328 (`MAX_BATTLE_ROUNDS`, `_handle_game_end_turn`, `_determine_vp_winner`) + prior-session live verification | ✅ in place |
| `meta.game_ended` and `meta.winner` set | prior-session test result confirmed | ✅ |
| ⚠️ side-effect: `PhaseManager.game_ended` is sticky | discovered during this audit | ❌ filed as #330 |

### t1.d — AUTO_PHASE_ADVANCE timing
| Aspect | Method | Result |
|---|---|---|
| Phases emit `phase_completed` only when complete | code review | ⚠️ DeploymentPhase fires it on enter when `_all_units_deployed()` returns true; that check returns true vacuously when all 26 units are still UNDEPLOYED — issue #331 |
| Live trigger only on action exhaustion | live test (FORMATIONS→ROLL_OFF skip) | ❌ FAIL — see #331 |

### t1.e — Special-phase gating
| Aspect | Method | Result |
|---|---|---|
| FORMATIONS only at game start | `PhaseManager` initial transition is the only entry; no `_get_next_phase` returns it | ✅ |
| ROLL_OFF only between REDEPLOYMENT and SCOUT | `_get_next_phase`: REDEPLOYMENT→ROLL_OFF, ROLL_OFF→SCOUT — never returned again | ✅ |
| SCOUT only before first COMMAND | `_get_next_phase`: ROLL_OFF→SCOUT, SCOUT→COMMAND — never returned again | ✅ |
| REDEPLOYMENT runs unconditionally | `_get_next_phase`: DEPLOYMENT→REDEPLOYMENT every game | ⚠️ design question — per 10e, redeployment is detachment-conditional; not a bug per-se but worth flagging |

---

## Issues filed during Tier 0+1

| # | Title | Severity | Tier |
|---|-------|----------|------|
| [#329](https://github.com/BigBobbo/warhammer-40k-godot/issues/329) | Single-player RNG non-deterministic — `payload.rng_seed` only honored by MovementPhase | High | 0 |
| [#330](https://github.com/BigBobbo/warhammer-40k-godot/issues/330) | `PhaseManager.game_ended` is sticky across new games | Medium | 1 |
| [#331](https://github.com/BigBobbo/warhammer-40k-godot/issues/331) | DEPLOYMENT phase auto-completes when entered — units never deployed | **Critical** | 1 |
| [#332](https://github.com/BigBobbo/warhammer-40k-godot/issues/332) | SCOUT_MOVES orphan + MORALE→DEPLOYMENT dead/wrong fallback | Low | 1 |
| [#333](https://github.com/BigBobbo/warhammer-40k-godot/issues/333) | MCP bridge `call_node_method` silently fails when args provided | Medium | 0 |

## Recommendations before Tier 2

1. ~~**Fix #331 first**~~ ✅ **FIXED** in branch `claude/audit-fix-cascade-and-game-ended` — root cause was a cascade: `BasePhase.execute_action` re-checks `_should_complete_phase()` after `process_action` returns, even if the action already emitted `phase_completed`. The signal then fires on the now-defunct phase whose connection is still wired to PhaseManager, causing PhaseManager to advance the *current* phase (which is the next one). Fix: guard the post-action check with `if pm.current_phase_instance == self`. Verified: `CONFIRM_FORMATIONS` for both players now correctly lands in DEPLOYMENT and stays.
2. ~~**Patch #330** alongside~~ ✅ **FIXED** in same branch — `PhaseManager.transition_to_phase(FORMATIONS)` now clears `game_ended`. Verified: after manually setting `game_ended=true`, transition to FORMATIONS clears it.
3. **Patch #329** before Tier 3 (unit abilities) — abilities trigger off dice; testing them properly needs determinism.
4. **#333** is convenience only — `execute_script` workaround is acceptable for the audit.
5. **#332** is cleanup — defer indefinitely.

## Tier 2+ blocker map

| Tier | Blocker | Workaround |
|------|---------|------------|
| 2 (per-phase rules) | #331 (can't reach deployed state scripted) | Build post-deploy save by hand from a UI-driven game, then load |
| 3 (unit abilities) | #329 (dice non-deterministic) | Multi-trial sampling for distribution; defer exact-outcome tests |
| 4 (edge cases) | #331, #329 | Same as above |
| 5 (save/load round-trips) | #330 (game_ended sticky may corrupt saves taken after game-end) | Verify save → reload → state is clean before proceeding |

---

## Tier 2 — Per-phase rules correctness

### Deployment Phase (in progress)

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.d1 | P1/P2 alternation on successful deploy | Deploy Shield-Captain, check `active_player` flip | 1 → 2 | 1 → 2 ✓ | pass | — |
| t2.d2a | Single-model out of zone rejected | DEPLOY_UNIT with center outside polygon | Validation fails, state unchanged, alternation does not flip | Rejected with "Model must be wholly within deployment zone"; status=UNDEPLOYED; active_player unchanged ✓ | pass | — |
| t2.d2b | Multi-model with one out-of-zone rejected | Witchseekers ×4, model 4 mid-board | Whole-action rejected, no per-model partial deploy | Rejected; all models stay UNDEPLOYED ✓ | pass | — |
| t2.d3 | 9" enemy distance rule | Crucible zones too far apart (≥32") to test in-zone; rule is auto-enforced | N/A in Crucible standard deploy | structurally untestable here | skip | — |
| t2.d4 | Unit coherency on initial deploy | Witchseekers ×4 with model 4 at 7" from siblings | Validation fails | **Deployment succeeded** — coherency not enforced | **fail** | [#335](https://github.com/BigBobbo/warhammer-40k-godot/issues/335) |
| t2.d5 | Strategic Reserves placement | (deferred — needs formations restart with reserves declared) | — | — | deferred | — |
| t2.d6 | Post-deploy baseline save | Deploy all 26 units, save | full save | partial — to follow-up session | deferred | — |

### Findings
- [#335](https://github.com/BigBobbo/warhammer-40k-godot/issues/335) — `DeploymentPhase._validate_deploy_unit_action()` only validates fields, ownership, and per-model zone containment. The 2" coherency rule (enforced in Movement / Charge / Fight) is missing from deployment. Models can be deployed at any distance and the unit ends up `status: DEPLOYED`. Bug surfaces silently — UI normally gates positions visually so this only manifests via scripted/save-edited deployments.
- 9" enemy distance rule cannot be exercised in Crucible of Battle (zones don't overlap, are >32" apart at narrowest). Defer testing until Reserves-arrival or Infiltrator audit, where the rule actually fires.

### Pending Tier 2 work — Deployment
- Strategic Reserves placement (t2.d5)
- ~~Post-deployment baseline save (t2.d6)~~ ✅ saved as `audit_baseline_postdeploy.w40ksave` (16 deployed, 10 in Strategic Reserves; reserves status set via direct mutation as a baseline shortcut due to terrain/zone packing constraints)

### Command Phase

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.c1 | CP gain on first Command phase | Drive new game to Round 1 P1 Command, check `players.{1,2}.cp` deltas vs initial state | 10e: Round 1 grants **no** CP | Both players gain +1 CP in Round 1 P1 Command (3 → 4 each) | **fail** | [#336](https://github.com/BigBobbo/warhammer-40k-godot/issues/336) |
| t2.c1b | CP gain to opponent | Same | Only active player gains CP | Opponent also gains +1 | **fail** | [#336](https://github.com/BigBobbo/warhammer-40k-godot/issues/336) |

### Findings (Tier 2 cumulative)
- [#335](https://github.com/BigBobbo/warhammer-40k-godot/issues/335) — DeploymentPhase doesn't validate unit coherency
- [#336](https://github.com/BigBobbo/warhammer-40k-godot/issues/336) — Command Phase CP gain doesn't match 10e (rule wrongly applied to round 1 + opponent)

### Movement Phase

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.m1 | Normal move within M" | Blade Champion (M=6"=240px) move from (120,100) to (120,280) = 180px / 4.5" | Position updates, flags.moved=true | Position updated; moved=true ✓ | pass | — |
| t2.m2 | Over-move rejected with proper error | Custodian Guard m1 from (200,100) to (200,400) = 7.5" > 6" cap | Error "Move exceeds cap: 7.5\" > 6.0\"" | Got exact error ✓ | pass | — |
| t2.m3 | Advance adds D6 to move cap | BEGIN_ADVANCE on Witchseekers (M=6"); roll D6 | move_cap_inches = 6 + roll | Roll=3, cap=9, advanced=true ✓; supports Command Re-roll integration | pass | — |
| t2.m4 | FLY ignores terrain | Move Jetbike through ruins | (deferred to next session) | — | deferred | — |
| t2.m5 | Strategic Reserves blocked Round 1 | PLACE_REINFORCEMENT on Caladius in Round 1 | Reject with appropriate error | "Reserves cannot arrive until Battle Round 2 (currently Round 1)" ✓ | pass | — |
| t2.m6 | Base-touching tolerance (#321/#327 regression) | 32mm bases at 50.0px (0.4px under touching boundary) | Allowed within 0.5px tolerance | (deferred — needs precise positioning setup) | deferred | — |

### Movement Phase observations
- `CONFIRM_UNIT_MOVE` after a failed `SET_MODEL_DEST` succeeded with `flags.moved=true` even though no model actually moved (ended at original position). This is **probably intentional** (player "moved" 0 inches, which counts as "moved" for subsequent rules) but worth noting since it differs from `REMAIN_STATIONARY` which sets `flags.remained_stationary`. Different downstream effects (e.g., heavy weapons -1 to hit if `moved`, but unaffected if `remained_stationary`).
- Engine validates over-move with clear error message including measured and cap distances — good UX.
- Advance roll fires D6 immediately on `BEGIN_ADVANCE` and integrates with Command Re-roll stratagem (`awaiting_reroll: true` returned).

### Shooting Phase (in progress)

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.s1 | Eligibility filter (range/visibility) | Try SELECT_SHOOTER on a unit far from any target | "no eligible targets" | Got exact error ✓ | pass | — |
| t2.s3 | End-to-end attack resolution | Telemon (8 attacks, BS 2+, S6, AP-1, D2) shoots Warboss | Hits → wounds → save data; sub-step traces | All sub-traces present (to_hit, to_wound, save_data); stratagem opportunity offered | pass (with #337 caveat) | — |
| t2.s3a | BIG GUNS NEVER TIRE gating | Vehicle out of engagement, target out of engagement of friendlies | No -1 to hit penalty | -1 applied unconditionally | **fail** | [#337](https://github.com/BigBobbo/warhammer-40k-godot/issues/337) |
| t2.s2/s4-s7 | Advance-blocks-shoot, Sustained/Lethal/Devastating, Cover, LOOK OUT SIR | (deferred — needs determinism for keyword tests, more setup for cover/LOS) | — | — | deferred | — |

### Shooting Phase observations
- **Stratagem timing windows work correctly**: After `CONFIRM_TARGETS`, the engine surfaces the opponent's reactive stratagem options ("Go to Ground" was offered on Warboss). Confirms 10e timing trigger `after_target_selected` is honoured.
- Pipeline structure matches 10e: SELECT_SHOOTER → ASSIGN_TARGET (per weapon, with model_ids and weapon_id in payload) → CONFIRM_TARGETS → reactive stratagem window → RESOLVE_SHOOTING → APPLY_SAVES (interactive save resolution).
- Hit/wound/save sub-traces are richly detailed — each step returns dice, modifiers, threshold, special-rules flags. Excellent for debugging and audit.

### Charge Phase

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.ch1 | Charge declaration with valid target | Telemon at (50, 2000) declares charge on Warboss at (50, 2330) | Engine accepts, offers Fire Overwatch to opponent | ✓ overwatch offered (6 P2 units eligible) | pass | — |
| t2.ch1b | Charge declaration beyond 12" | Telemon at (50, 1500) declares charge on Warboss (20.75" away) | Reject "Target beyond 12\" charge range" | ✓ exact error returned | pass | — |
| t2.ch2 | 2D6 charge roll | CHARGE_ROLL action | 2D6 dice, total compared to min_distance (base-aware), Command Re-roll integration | Rolled [6,3]=9, min_distance=5.49"; awaiting_reroll=true ✓ | pass | — |
| t2.ch3 | Reserves filter (#320 regression) | List eligible chargers and targets | Reserves units (Boyz/Battlewagon/etc) absent | ✓ none of the 10 reserves units appear | pass | — |
| t2.ch4 | Cannot end in engagement of non-target | Apply charge to position close to WARBOSS_B but also within 1" of WARBOSS_C | Reject | ✓ "Cannot end within engagement range of non-target unit: Warboss" | pass | — |
| t2.ch5 | Charged unit gets fights_first flag | After successful APPLY_CHARGE_MOVE, check Telemon's flags | flags.charged_this_turn = true, flags.fights_first = true | Both set ✓ + WARBOSS_B.has_been_charged set | pass | — |
| t2.ch6 | Tank Shock stratagem trigger on vehicle charge | After vehicle charge applied | Engine offers Tank Shock | ✓ trigger_tank_shock=true | pass | — |

### Fight Phase (partial)

| ID | Rule | Method | Expected | Observed | Status | Issue |
|----|------|--------|----------|----------|--------|-------|
| t2.f1 | Charger eligible to fight first | After charge, FIGHT phase shows Telemon as fighter | SELECT_FIGHTER offered for Telemon | ✓ only Telemon (the charger) offered | pass | — |
| t2.f1b | Custodes Martial Ka'tah stance triggers on melee | SELECT_FIGHTER on Custodes unit | trigger_katah_stance fires, master_of_the_stances_available checked | ✓ both fields returned correctly | pass | — |
| t2.f1c | Pile-in action | PILE_IN dispatched | Pile-in resolves, attack assignment triggered | ✓ trigger_attack_assignment=true with correct attack_targets | pass | — |
| t2.f2 | Weapon name disambiguation in ASSIGN_ATTACKS | Assign "Telemon Caestus" (which has both ranged and melee modes with same name) | Engine resolves to melee mode in melee context | "Weapon is not a melee weapon: Telemon Caestus" — engine resolves to ranged variant by name | observation | (potential — needs investigation) |

### Charge / Fight observations
- **All 7 charge tests pass** — declaration, range validation, 2D6 mechanic, reserves filter (#320 regression intact), engagement-of-non-target rule, fights_first flag wiring, vehicle Tank Shock stratagem. This is one of the cleanest phases in the audit so far.
- **Heroic Intervention stratagem** correctly offered to opponent at end of charge with 3 eligible P2 character units listed.
- **Custodes Martial Ka'tah stance** triggers correctly via `trigger_katah_stance` flag on `SELECT_FIGHTER` for Custodes models.
- **Weapon name collision**: `Telemon Caestus` exists as both a Ranged (12") and Melee weapon entry in army JSON. `ASSIGN_ATTACKS` (melee context) by name resolves to the ranged variant first and fails. May be a minor bug or may require passing weapon index/disambiguator. Worth investigating; not yet filed pending more reproduction cases.

### Pending phases
- Scoring not yet started
- Movement: t2.m4 (FLY), t2.m6 (base-touching regression) deferred
- Shooting: t2.s2 (advance-blocks-shoot), t2.s4-s7 (keywords + cover) deferred — most need determinism (#329)
- Fight: t2.f2 melee attack pipeline blocked by weapon-name-collision; deferred

---

## Out of scope (this audit)

- Multiplayer / NetworkManager sync (Tier 6 deferred)
- Replay system
- Mathhammer prediction UI (FightPhase.gd:1847 uses random seed but doesn't affect gameplay)
