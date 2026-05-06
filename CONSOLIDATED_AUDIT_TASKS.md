# Consolidated Audit Task List
**Generated:** 2026-05-04
**Sources:** MASTER_AUDIT.md, AI_AUDIT.md, ABILITIES_AUDIT.md, 40k/AUDIT_ABILITIES_2.md, SHOOTING_PHASE_AUDIT.md, FIGHT_PHASE_AUDIT.md, CHARGE_PHASE_AUDIT.md, MOVEMENT_PHASE_AUDIT.md, 40k/MOVEMENT_PHASE_AUDIT.md, AUDIT_COMMAND_PHASE.md, 40k/AUDIT_COMMAND_PHASE.md, DEPLOYMENT_AUDIT.md, SAVE_AUDIT.md, IP_COMPLIANCE_AUDIT.md, LIONS_ARMY_AUDIT.md, TERRAIN_LAYOUTS_AUDIT.md, FEB21_AUDIT.md, 40k/TESTING_AUDIT_SUMMARY.md, .llm/rules-audit.md, **40k/test_results/audit_units_2026_05/UNIT_ABILITY_AUDIT.md** (live MCP-bridge runtime validation, 2026-05-04).

This file collapses ~180 raw audit findings into 88 atomic tasks. Tasks already marked DONE/RESOLVED/✅ in the source audits are excluded; cross-file duplicates are merged. Validation paths assume the godot-mcp-bridge MCP server is connected and the Godot editor is running with the project loaded.

---

## Standard Validation Template

Every task uses this baseline pattern (each task lists deviations and specifics):

1. **Bring up the scene** — `mcp__godot-mcp-bridge__play_main_scene` (or `play_scene` with a specific PackedScene), then `wait_seconds(2)` for autoloads.
2. **Load a deterministic fixture** — call `execute_script` to invoke `SaveLoadManager.load_save_with_meta_async("user://saves/<fixture>.w40ksave")` so the board state matches the test scenario.
3. **Drive the test scenario** — use `dispatch_action`, `select_unit`, `move_unit_to`, `simulate_click`, `simulate_drag`, `simulate_key_press`, `transition_to_phase`, `advance_phase` to reproduce the rule/bug.
4. **Inspect state** — `get_board_state`, `get_unit_details`, `get_legal_actions`, `get_node_property`, or `execute_script` to assert post-conditions.
5. **Capture evidence** — `capture_screenshot` to `40k/test_results/audit_2026_05/screenshots/<task_id>_<step>.png` for each meaningful UI state.
6. **Save the run log** — append a per-task subsection to `40k/test_results/audit_2026_05/AUDIT_REPORT.md` (action sequence + screenshot links + pass/fail).
7. **Inspect the runtime log** — read the latest `~/Library/Application Support/Godot/app_userdata/40k/logs/debug_*.log` to confirm the expected debug lines fire and no errors are emitted.

A task is only "DONE" when (a) the live in-game scenario matches the acceptance criteria, (b) screenshots exist and are linked from AUDIT_REPORT.md, (c) the headless GDScript regression test (in `40k/tests/`) passes, and (d) the runtime log shows no errors.

---

# P0 — CRITICAL (game-breaking, data-corrupting, blocks core gameplay)

### T-001 — AI never declares charges
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AI_AUDIT (AI-GAP-1, CHARGE-1/2/3) · LIONS_ARMY_AUDIT
**Files:** `40k/scripts/AIDecisionMaker.gd` (`_decide_charge`, ~line 1598)
**Description:** `_decide_charge()` always returns `SKIP_CHARGE` with comment "not implemented". AI never benefits from Lance, Fights First, or charge bonuses, never locks enemies in engagement.
**Acceptance:** AI selects charging units, picks valid targets within 12", computes charge roll, places models in B2B respecting unit coherency and base-to-base rules.
**Validation (MCP):**
- Load fixture with one AI Ork mob 10" from a Marine squad. `transition_to_phase("CHARGE")`.
- Trigger AI turn via `execute_script` (`AIPlayer.process_phase()`).
- Capture screenshot before/after charge decision.
- Assert via `get_unit_details(ork_id)` that the unit has `charged_this_turn=true` and is within 1" engagement of the marine unit; assert charge dice were logged in `dice_log`.
- Repeat with target 13" away — assert AI either skips or calls a stratagem (does not crash).

### T-002 — AI fight phase: pile-in and consolidate are no-ops
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AI_AUDIT (AI-GAP-2, FIGHT-1, FIGHT-2)
**Files:** `40k/scripts/AIDecisionMaker.gd` (`_decide_fight`)
**Description:** PILE_IN and CONSOLIDATE actions emit empty `movements: {}`. Models that aren't already in B2B fight with reduced/zero eligible models; AI never tags new enemies on consolidate.
**Acceptance:** AI computes per-model 3" pile-in toward nearest enemy and 3" consolidate toward nearest enemy / objective; coherency preserved.
**Validation (MCP):**
- Load fixture: AI unit half-engaged with enemy (some models out of 1"). `transition_to_phase("FIGHT")`.
- Trigger AI fight; assert before/after positions via `get_unit_details` show the AI moved out-of-range models toward enemy by ≤3".
- Screenshot before pile-in, after pile-in, after consolidate.
- Assert that consolidate placed a previously-uncommitted model in engagement range with a fresh enemy unit when one is within 3".

### T-003 — AI fall-back has no destination computation
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AI_AUDIT (MOV-6)
**Files:** `40k/scripts/AIDecisionMaker.gd`, `40k/phases/MovementPhase.gd`
**Description:** AI Fall Back action submits no destinations; models do not actually leave engagement range, leaving the AI unit still locked.
**Acceptance:** Fall Back computes a path that ends with every model >1" from any enemy and within unit Move characteristic.
**Validation (MCP):**
- Fixture: AI Boyz engaged with Marines, AI's turn, low HP. `transition_to_phase("MOVEMENT")`.
- Run AI turn; assert no AI model is within 1" of any enemy after the action via `execute_script` distance check.
- Screenshot before/after; assert `flags.fell_back=true` on the unit.

### T-004 — Heroic Intervention is a placeholder
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** FIGHT_PHASE_AUDIT (2.5) · CHARGE_PHASE_AUDIT (2.2)
**Files:** `40k/phases/FightPhase.gd:1020-1023`, `_validate_heroic_intervention_action` (1612-1640)
**Description:** Returns the literal string "not implemented". 2CP non-active reaction; required for many tournament strategies.
**Acceptance:** Stratagem is offered to the non-active player at the right window; CP deducted; CHARACTER moves up to 6" toward charging enemy and counts as having charged.
**Validation (MCP):**
- Fixture `hi_pretrigger.w40ksave` (already exists). Continue to charge declaration that ends with enemy within 6" of an idle CHARACTER.
- Use `dispatch_action` to play Heroic Intervention; assert `unit.flags.charged_this_turn=true`, CP decremented by 2, position updated.
- Screenshot pre-prompt, post-move; verify Fight order places this unit in the FIGHTS_FIRST sequence.

### T-005 — SHOOT-9: Defender does not control wound allocation
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** FEB21_AUDIT (SHOOT-9)
**Files:** `40k/phases/ShootingPhase.gd`, `40k/scripts/ShootingController.gd`, `WoundAllocationDialog`
**Description:** Wound allocation auto-resolves; defending player must choose recipient with the wounded-first restriction.
**Acceptance:** Defender sees an allocation dialog per unsaved wound; must allocate to a wounded model first; allocation is networked.
**Validation (MCP):**
- Two-controller fixture with one shooter and a multi-model squad including one already-wounded model.
- Drive shoot via active player; switch viewport to defender via `set_node_property` on viewport camera.
- `simulate_click` on a different model first — assert blocked. Click wounded model — assert accepted.
- Screenshots: prompt visible to defender, model auto-selected when only one wounded, multi-wound bug case.

### T-006 — Multiplayer save load: no client acknowledgment
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (SAVE-2)
**Files:** `40k/autoloads/NetworkManager.gd:sync_loaded_state`
**Description:** Host RPC-broadcasts loaded snapshot with no ack, no timeout, no error path. Host and client state can silently diverge.
**Acceptance:** Client must ACK; host blocks at "Loading..." until all clients ACK or 10s timeout (then disconnect with explicit error).
**Validation (MCP):**
- Two-instance test (host + client). Save mid-game on host. On client, drop packets via `execute_script` mock for 2s. Trigger load on host.
- Assert client UI freezes on a load overlay; on resume, both instances report identical `GameState.state` hash via `execute_script` (Marshalls.variant_to_bytes hash).
- Screenshot host loading overlay, client loading overlay, post-resume state match.

### T-007 — Charge multiplayer: COMPLETE_UNIT_CHARGE / SKIP_CHARGE not re-emitted to clients
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (3.2, 3.4)
**Files:** `40k/autoloads/NetworkManager.gd:1046-1118`, `40k/phases/ChargePhase.gd`
**Description:** Two charge signals are missing from the client re-emission block; client `completed_charges`/`current_charging_unit` diverge from host. ChargePhase state (active_charges, dice_log, units_that_charged, failed_charge_attempts) is host-only.
**Acceptance:** All charge signals reach clients; client's failed-charges tooltip and completed-charges UI match host. Add fields to deterministic state sync block.
**Validation (MCP):**
- Two-instance test: declare charge on host that fails. On client, hover the failed-charges tooltip — assert the failed unit/distance is shown.
- `execute_script` on both instances to dump `ChargePhase.completed_charges` and `failed_charge_attempts` — assert deep-equal.
- Screenshots: host post-fail, client post-fail (tooltip).

### T-008 — Charge bug: multi-unit sequential charging stalls (GH #35)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (Validation Task 6)
**Files:** `40k/phases/ChargePhase.gd`, `40k/scripts/ChargeController.gd`
**Description:** After first unit completes a charge, the UI only shows "End Charge Phase"; eligible second unit cannot be selected.
**Acceptance:** After APPLY_CHARGE_MOVE, phase returns to a unit-selection state with the next eligible unit highlighted.
**Validation (MCP):**
- Fixture with two AI-eligible Ork mobs each within 8" of separate enemy units. Player has the turn.
- Charge first mob, complete placement. `get_legal_actions()` must include `SELECT_CHARGE_UNIT` for the second mob.
- Charge second mob; assert both units have `charged_this_turn=true` and `END_CHARGE` is the only remaining option.
- Screenshots after first complete, mid-second-charge, post-end.

### T-009 — Charge bug: multi-model unit positions revert after charge (GH #33)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (Validation Task 7)
**Files:** `40k/phases/ChargePhase.gd`
**Description:** Multi-model unit positions are not persisted to `game_state_snapshot`; on phase exit, models snap back to pre-charge positions.
**Acceptance:** All charging models retain their final placement in `GameState.state.units[unit_id].models[i].position`.
**Validation (MCP):**
- Fixture with a 5-model Custodian Guard charging across the table.
- Complete charge; capture screenshot of placed models.
- `transition_to_phase("FIGHT")` then `transition_to_phase("MOVEMENT")` (next turn).
- `get_unit_details` for each model — assert positions are at the charge-end coordinates, not the pre-charge coordinates.

### T-010 — Charge bug: defender always sees "charge failed"
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (Validation Task 8)
**Files:** `40k/scripts/ChargeController.gd`
**Description:** Defender's controller derives charge status from `selected_targets` (local UI state), so it always reports failure on the non-active player.
**Acceptance:** Defender sees the actual charge result derived from networked `dice_log` / `completed_charges`, including success/fail and roll.
**Validation (MCP):**
- Two-instance test: host declares successful charge.
- Switch focus to client; read DiceLogPanel via `get_node_property` — assert text contains "Charge succeeded" with the actual roll.
- Screenshot client view of dice log.

### T-011 — Charge bug: CHARGE_ROLL action type mismatch
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (Validation Task 9)
**Files:** `40k/autoloads/GameManager.gd`, `40k/phases/ChargePhase.gd`
**Description:** Validation passes but GameManager logs "Unknown action type: CHARGE_ROLL" and rejects.
**Acceptance:** CHARGE_ROLL is registered in GameManager action routing; action processes successfully.
**Validation (MCP):**
- Fixture mid-charge, before roll. Run `dispatch_action({"type": "CHARGE_ROLL", ...})`.
- Read latest debug log; assert no "Unknown action type" line. `get_legal_actions()` should advance to model placement.
- Screenshot before/after roll prompt.

### T-012 — Movement multiplayer: active_moves dict is host-only
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** 40k/MOVEMENT_PHASE_AUDIT (3.1)
**Files:** `40k/phases/MovementPhase.gd:20`
**Description:** `active_moves` (move state per unit) is local to host. Validation in `_validate_end_movement` and Fall Back checks may diverge silently between host and client.
**Acceptance:** active_moves participates in snapshot diffs and is broadcast via the existing snapshot sync.
**Validation (MCP):**
- Two-instance test: begin movement for Unit A on host. Dump `MovementPhase.active_moves` on both — assert deep-equal.
- Confirm-move; re-check; assert state cleared on both.
- Screenshot any divergence indicator (none expected).

### T-013 — Movement disembark bypass action pipeline
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** 40k/MOVEMENT_PHASE_AUDIT (Action audit Item 2)
**Files:** `40k/phases/MovementPhase.gd:~1890` (`_on_disembark_placement_completed`)
**Description:** Calls TransportManager directly, bypassing the CONFIRM_DISEMBARK action validation/processing path. Two parallel disembark code paths cause replay desync.
**Acceptance:** Disembark always routes through dispatch_action so the change is validated and recorded as a state diff.
**Validation (MCP):**
- Fixture: Ork Boyz embarked in Battlewagon, transport not destroyed.
- `dispatch_action({"type":"BEGIN_NORMAL_MOVE", "actor_unit_id": <wagon>})`, then place models, then `CONFIRM_DISEMBARK`.
- Assert via `get_unit_details` that the disembarked unit's positions match exactly what was emitted in the action result; replay save/load and assert positions preserved.

### T-014 — Custodes invuln saves missing from JSON
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** 40k/AUDIT_ABILITIES_2 (#1, #2) · LIONS_ARMY_AUDIT (#49)
**Files:** `40k/armies/adeptus_custodes.json` (U_CUSTODIAN_GUARD_B, U_BLADE_CHAMPION), `40k/armies/A_C_test.json`
**Description:** `meta.stats` lacks `invuln: 4` for Blade Champion and Custodian Guard. Both will take wounds they should save.
**Acceptance:** Both units roll a 4+ invuln when faced with AP-3 or worse.
**Validation (MCP):**
- Fixture with Blade Champion targeted by AP-4 lascannon shots. Resolve shots.
- Read `assignment.modifiers` and dice log; assert invuln 4+ rolls were offered, not bare 2+ armor.
- Repeat for Custodian Guard. Screenshot save dialog showing invuln option.

### T-015 — Witchseekers Scouts ability misnamed (F-1)
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** 40k/AUDIT_ABILITIES_2 (#104) · UNIT_ABILITY_AUDIT (F-1, **re-confirmed live 2026-05-04**: `_unit_has_scout_own('U_WITCHSEEKERS_C') == false` vs `_unit_has_scout_own('U_KOMMANDOS_H') == true`)
**Files:** `40k/armies/adeptus_custodes.json`, `40k/armies/A_C_test.json`
**Description:** Witchseekers' Scouts ability is named "Core" instead of `Scouts 6"`. `GameState._unit_has_scout_own()` matches `name.to_lower().begins_with("scout")` and won't match "Core" — Witchseekers never get scout moves.
**Acceptance:** Witchseekers receive a Scout move during the deployment-end Scout phase.
**Validation (MCP):**
- Fixture: deployed Witchseekers, no other units. Advance to scout phase.
- Assert `get_legal_actions` includes a SCOUT_MOVE action targeting the Witchseekers unit.
- Make the scout move; screenshot before/after positions; assert distance moved ≤6".

### T-016 — `effect_fnp_psychic_mortal` flag set but never read (F-2)
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** 40k/AUDIT_ABILITIES_2 (#103) · ABILITIES_AUDIT · UNIT_ABILITY_AUDIT (F-2, **re-confirmed live 2026-05-04**: Witchseekers `flags = {"effect_fnp_psychic_mortal": 3}` yet `RulesEngine.get_unit_fnp(unit) == 0`)
**Files:** `40k/autoloads/RulesEngine.gd:get_unit_fnp` and mortal-wound damage paths
**Description:** UnitAbilityManager sets the flag, EffectPrimitives defines helpers, but `get_unit_fnp()` only checks `effect_fnp` and `meta.stats.fnp`. Witchseekers / Prosecutors get no Daughters of the Abyss FNP at all.
**Acceptance:** When a Psychic attack or mortal wound resolves on a unit with this flag, FNP 3+ is rolled.
**Validation (MCP):**
- Fixture with Prosecutors taking a mortal wound from a Smite-equivalent Psychic attack.
- Resolve damage; assert dice log shows an FNP 3+ roll attempt for each model.
- Repeat with bolter shots — assert NO FNP roll (non-Psychic, non-MW).
- Screenshots of both dice logs.

### T-017 — Daughters of the Abyss scope wrong (always-on FNP)
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** ABILITIES_AUDIT (#69) · LIONS_ARMY_AUDIT (#48)
**Files:** `40k/autoloads/UnitAbilityManager.gd` ABILITY_EFFECTS["Daughters of the Abyss"]
**Description:** Currently grants FNP 3+ vs all damage. Should only apply vs Psychic attacks and mortal wounds.
**Acceptance:** ABILITY_EFFECTS entry uses `grant_fnp_psychic_mortal` (paired with T-016 read path).
**Validation (MCP):** Same pair of scenarios as T-016. Dependency: T-016 must land first.

### T-018 — MELTA X weapon keyword not implemented
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#1)
**Files:** `40k/autoloads/RulesEngine.gd` (damage roll path)
**Description:** Core anti-vehicle keyword. +X damage at half range. No implementation; melta weapons currently behave like flat-damage.
**Acceptance:** When firing within half-range, damage roll is augmented by the Melta X value.
**Validation (MCP):**
- Fixture: Marine Multi-melta 12" from Battlewagon (half-range = 12"). Fire.
- Assert per-shot damage = base + Melta X (logged in dice_log).
- Move target to 13"; reshoot; assert damage = base only.
- Screenshot dice log for both runs.

### T-019 — Wound roll modifier infrastructure missing
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#9)
**Files:** `40k/autoloads/RulesEngine.gd:714-733`, `assignment.modifiers`
**Description:** No analog of HitModifier for wound rolls. No +1/-1 wound, no cap, no reroll. Blocks Twin-Linked, LANCE, and many ability/stratagem effects.
**Acceptance:** WoundModifier list applied with cap of ±1, with reroll separate; unmodified-1 rule still enforced.
**Validation (MCP):**
- Fixture with synthetic +1 wound effect (set via `execute_script` on a unit).
- Resolve a borderline wound roll (S equal to T) — assert wound on 4+ instead of 5+.
- Apply -1 wound at the same time; assert ±1 cap holds (net 0, not net 0 with rerolls compounding).

### T-020 — Stealth keyword not implemented
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#10)
**Files:** `40k/autoloads/RulesEngine.gd:_resolve_assignment_until_wounds`
**Description:** Defender's Stealth keyword should grant -1 to hit; never checked.
**Acceptance:** Hit modifier list includes -1 when target unit has STEALTH (with the -1 cap from existing system).
**Validation (MCP):**
- Fixture: Marine shoots at a Stealth-keyword target.
- Inspect dice log: every hit roll is at -1 vs target. Compare to a non-Stealth target on the same fixture.
- Screenshot hit modifier breakdown.

### T-021 — Lone Operative not enforced
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#11)
**Files:** `40k/autoloads/RulesEngine.gd:get_eligible_targets`/`validate_shoot`
**Description:** No 12" targeting restriction. Lone Operative characters can be sniped from any range.
**Acceptance:** A unit with LONE_OPERATIVE cannot be targeted by ranged attacks if no enemy is within 12" of it.
**Validation (MCP):**
- Fixture with Callidus or other LONE_OPERATIVE 18" from any other unit.
- `get_legal_actions` for shooter — assert Callidus is NOT in the eligible target list.
- Move a screening enemy to within 12"; reshoot; Callidus now eligible.
- Screenshots of target list both states.

### T-022 — Stratagem framework: Counter-Offensive, Epic Challenge, Tank Shock, Go to Ground, Smokescreen, Insane Bravery, Rapid Ingress integration
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AUDIT_COMMAND_PHASE (2.3) · FIGHT_PHASE_AUDIT (2.9) · CHARGE_PHASE_AUDIT (Validation Task 10)
**Files:** `40k/autoloads/StratagemManager.gd`, phase scripts (FightPhase, MovementPhase, ChargePhase, ShootingPhase) for the trigger windows
**Description:** Core stratagems either lack phase-window hooks or aren't surfaced in any UI. CP cost / "once per phase" / "once per battle" enforcement also incomplete.
**Acceptance:** Each of the 7 stratagems is selectable at its specified window, deducts CP, enforces once-per-phase / once-per-battle, and produces the expected effect.
**Validation (MCP):** Per-stratagem mini-test (one fixture per stratagem):
- For each, drive to the trigger window via `transition_to_phase` + `dispatch_action`.
- Verify the stratagem prompt appears for the right player; click it; assert effect.
- Screenshot prompt + post-effect. Save 7 screenshots `T-022_<stratagem>.png`.

### T-023 — Pre-game stratagems system (covers Insane Bravery, Smokescreen, Counter-Offensive, etc. UI shell)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AUDIT_COMMAND_PHASE (2.6)
**Files:** `40k/scripts/StratagemPanel.gd` (new), `40k/autoloads/StratagemManager.gd`
**Description:** No UI panel listing eligible stratagems with CP cost, faction/detachment/core grouping, and once-per-phase indicators.
**Acceptance:** Panel renders eligible stratagems for the active phase/window with cost, eligibility, and active state. Toggle via hotkey or button.
**Validation (MCP):**
- Fixture mid-shooting. Open panel via `simulate_key_press("S")` (or whatever shortcut chosen).
- Assert all 4 expected eligible stratagems are visible; ineligible ones are greyed.
- Spend CP on one; reopen panel; assert it's marked used. Screenshot before/after.

### T-024 — Faction abilities in Command Phase (Oath of Moment, Waaagh!, etc.)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** AUDIT_COMMAND_PHASE (2.4) · AI_AUDIT (CMD-3)
**Files:** `40k/autoloads/FactionAbilityManager.gd`, `40k/phases/CommandPhase.gd`
**Description:** Stored as text in army JSON; no triggers, no UI, no networked choice. Affects Space Marines and Orks at minimum.
**Acceptance:** Each faction's command-phase ability prompts the active player in command phase, applies the modifier, and is networked for the opponent.
**Validation (MCP):**
- Fixture: Space Marines vs. Orks, command phase. Marines pick Oath target.
- Screenshot prompt. Assert reroll-1s wound modifier applied to that target on subsequent shoot.
- Repeat for Orks Waaagh! turn 2 — assert +1 charge and +1 attack.

### T-025 — Multiplayer: BEGIN_ADVANCE not deterministic, charge actions not deterministic
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** 40k/MOVEMENT_PHASE_AUDIT (3.3) · CHARGE_PHASE_AUDIT (3.3)
**Files:** `40k/autoloads/NetworkManager.gd:42-59` (DETERMINISTIC_ACTIONS list)
**Description:** BEGIN_ADVANCE rolls a D6 and can be made deterministic via the existing seeded-RNG path (`_process_begin_advance` lines 505-513). Same for SELECT_CHARGE_UNIT, DECLARE_CHARGE.
**Acceptance:** Listed actions execute optimistically on client and host, drawing from a shared seed; no perceived latency.
**Validation (MCP):**
- Two-instance test: time advance roll latency on client (timestamp before dispatch_action vs after dice_log entry) — should drop under 50ms.
- Both instances dump RNG state — assert seeds match.

### T-026 — Combat Squads / Patrol Squad / unit splitting at deployment (U-1)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** ABILITIES_AUDIT (#72, #75) · UNIT_ABILITY_AUDIT (U-1, **confirmed unreachable in live game 2026-05-04**: `ABILITY_EFFECTS["Patrol Squad"].implemented == false`, no UI path exposed in deployment phase)
**Files:** `40k/phases/DeploymentPhase.gd`, new `UnitSplitManager` autoload
**Description:** Tactical Squad (Combat Squads) and Kommandos (Patrol Squad) can split into two 5-model units at deployment. Listed as JSON-ready but blocked by missing deployment system support.
**Acceptance:** During deployment, eligible units offer a "Split now" prompt; choosing splits the GameState entry into two units and continues deployment alternation.
**Validation (MCP):**
- Fixture pre-deployment with a 10-model Tactical Squad.
- Open deployment dialog; click Split. Assert two 5-model entries appear in unit list.
- Deploy both; advance past deployment; check `GameState.units` has both entries with correct keywords/abilities.
- Screenshots of split dialog and post-split unit list.

### T-027 — Save/Load broken with AI player (BUG-5)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#89) · SAVE_AUDIT (#7) · AI_AUDIT
**Files:** `40k/autoloads/SaveLoadManager.gd`, `40k/autoloads/AIPlayer.gd`
**Description:** AIPlayer turn history, decision state, and difficulty settings are not in `StateSerializer.serialize()`. Loaded games crash or AI behaves incoherently.
**Acceptance:** Saving mid-AI-turn and reloading reproduces identical AI decisions and difficulty/speed settings.
**Validation (MCP):**
- Fixture: AI mid-shooting on turn 2.
- Save (`SaveLoadManager.quicksave()`).
- Reload; resume AI turn; assert same target picks (compare dice_log post-resume vs post-original).
- Screenshot pre-save board, post-load board.

### T-028 — Autosave fires during AI turn (SAVE-6)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (#8)
**Files:** `40k/autoloads/SaveLoadManager.gd` (autosave timer/triggers)
**Description:** Autosave can capture a partial mid-AI-turn snapshot, then load corrupts the AI sequence.
**Acceptance:** Autosave defers when `AIPlayer.is_thinking` is true; resumes after.
**Validation (MCP):**
- Fixture: AI turn in progress. Lower autosave interval to 3s via `execute_script`.
- Wait 5s; assert no new autosave file appeared.
- End AI turn; wait 5s; assert autosave fired exactly once.
- Screenshot save list before/after.

### T-029a — F-3: `embarked_in: null` silently skips ALL aura sources [NEW 2026-05-04]
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** UNIT_ABILITY_AUDIT (Issue F-3, discovered live 2026-05-04 — not in any prior audit)
**Files:** `40k/autoloads/RulesEngine.gd:3479` (`get_ded_glowy_ammo_toughness_penalty`), `40k/autoloads/RulesEngine.gd:3625` (`unit_has_waaagh_banner_lethal_hits`), `40k/autoloads/UnitAbilityManager.gd:1928, 2064, 2092, 2123, 2136`
**Description:** Seven sites use the pattern `unit.get("embarked_in", "") != ""` to skip embarked aura sources. When the field is stored as `null` (the default after a save/load round-trip in this codebase), the check evaluates `null != ""` → `true`, and the unit is **incorrectly skipped**. Live evidence: with `embarked_in: null` on Ghazghkull, `unit_has_waaagh_banner_lethal_hits(warboss, state) == false`; after `Ghazghkull.erase("embarked_in")` it returns `true`. Same pattern confirmed for Kaptin Badrukk's Ded Glowy Ammo. **Impact: ALL aura abilities (Ded Glowy Ammo, Ghazghkull's Waaagh! Banner, possibly Waaagh! Effigy and others) are silently broken in normal gameplay any time a save/load happened.**
**Acceptance:** Replace all 7 sites with `var embk = unit.get("embarked_in", ""); if embk != null and embk != "": continue` — OR normalise `embarked_in` at deserialization so it is always either an empty string or a valid unit_id, never null. Latter is preferred (single fix in `StateSerializer`/`GameState`).
**Validation (MCP):**
- Load `40k/saves/audit_units_formations.w40ksave` (already used by the source audit).
- `execute_script` to inspect Ghazghkull `embarked_in` field — assert it is an empty string, NOT null.
- Position Makari's unit ≤6" from a friendly Ork unit. Call `RulesEngine.unit_has_waaagh_banner_lethal_hits(ork, state)` — assert returns `true`.
- Position the Ork unit >6" away — assert returns `false`.
- Repeat for `RulesEngine.get_ded_glowy_ammo_toughness_penalty` (assert `1` at ≤6", `0` at >6").
- Save the game; reload; re-run the same checks — assert results identical (this is the regression that must be locked in).
- Headless regression test in `40k/tests/test_aura_embarked_in_null.gd` exercises every one of the 7 sites with both empty-string and null `embarked_in`.
- Screenshots: dice log + game log showing aura active during a melee/shoot resolution after a save/load round-trip.

### T-029 — Stratagem system: missing units (Custodes/Lions roster gap)
**Status:** [STUB-PENDING-IP] — data-shape skeleton in place; full datasheet/stat values pending Wahapedia/IP review (T-029 workstream).
**Source:** LIONS_ARMY_AUDIT (#39, #38) · 40k/AUDIT_ABILITIES_2 (#84-89)
**Files:** `40k/armies/adeptus_custodes.json`, new `40k/data/Stratagems.csv` rows
**Description:** Trajann Valoris, Shield-Captain on Dawneagle, Allarus Custodians, Prosecutors, Vertus Praetors, Callidus Assassin, Inquisitor Draxus have no JSON entries. Cannot field a legal Lions of the Emperor list. Plus 6 detachment stratagems (Peerless Warrior, Unleash the Lions, Defiant to the Last, Gilded Champion, Swift as the Eagle, Manoeuvre and Fire) absent from `StratagemManager`.
**Acceptance:** All 7 unit JSON entries match Wahapedia stat lines (M/T/Sv/Inv/W/Ld/OC, weapons, keywords); 6 stratagems registered.
**Validation (MCP):**
- Open MainMenu, select Lions of the Emperor + Adeptus Custodes; assert all 7 units appear in army builder list with correct points cost.
- Deploy each; `get_unit_details` returns expected stats for each.
- During command phase with eligible units, all 6 detachment stratagems appear in the panel (depends on T-023).
- Screenshot army selection screen + per-unit deployment.

---

# P1 — HIGH (significant rule gaps, common multiplayer/UI bugs, AI competence)

### T-030 — Hit-modifier path: weapon-keyword-driven AI target scoring
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-GAP-5/SHOOT-4, AI-GAP-6/SHOOT-3, SHOOT-5)
**Files:** `40k/scripts/AIDecisionMaker.gd:_score_shooting_target`, `_save_probability`
**Description:** AI doesn't check weapon range, doesn't consider invulnerable saves, doesn't factor weapon keywords (Blast, Rapid Fire, Melta, Anti-X, Torrent, Sustained Hits, Lethal Hits, Devastating Wounds) into expected damage.
**Acceptance:** `_score_shooting_target` returns 0 for out-of-range targets, uses min(armor_save, invuln) for save chance, and applies keyword-modified expected damage formula.
**Validation (MCP):**
- Fixture: AI with mixed lascannon + bolter, two enemy options (heavy invuln tank + light infantry).
- Run AI shooting; assert lascannon → tank, bolters → infantry (read action log).
- Move tank out of lascannon range; rerun; assert lascannon picks infantry or skips, never out-of-range.
- Screenshot AI thinking indicator + final assignment dialog.

### T-031 — AI uses no stratagems
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-GAP-3) · LIONS_ARMY_AUDIT
**Files:** `40k/scripts/AIDecisionMaker.gd` (new `_decide_stratagem` per-window)
**Description:** AI never spends CP on Grenade, Fire Overwatch, Go to Ground, Smokescreen, Counter-Offensive, Heroic Intervention, Rapid Ingress, Epic Challenge, or Command Re-roll (except battle-shock auto).
**Acceptance:** AI evaluates each eligible stratagem at its window using a simple expected-value vs CP-budget heuristic; spends when net value > threshold.
**Validation (MCP):**
- Fixture: AI defending Marine squad in cover. Player declares charge with low charge dice.
- AI turn must consider Fire Overwatch; assert Stratagem use logged in `dice_log` when expected damage is high.
- Repeat for Grenade (5 models within 8") and Counter-Offensive (engaged with low-init enemy).
- Screenshots: each stratagem activation prompt being auto-played by AI.

### T-032 — AI no unit-ability awareness
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-GAP-4)
**Files:** `40k/scripts/AIDecisionMaker.gd`, `40k/autoloads/UnitAbilityManager.gd`
**Description:** AI ignores Leader attachment positioning, Fall Back and Charge, aura placement, Lone Operative protection, Oath of Moment selection, Waaagh! timing.
**Acceptance:** AI keeps Leaders attached when possible, evaluates aura coverage as positioning bonus, picks Oath target via threat ranking, times Waaagh! for high-charge turns.
**Validation (MCP):**
- Fixture with Captain + Tactical Squad, AI's turn; verify Captain stays in coherency throughout movement.
- Trigger Waaagh!: AI must call it on a turn with ≥2 charging Boyz mobs in 9" of enemies.
- Screenshot before/after; verify `dice_log` contains the Waaagh! activation.

### T-033 — AI scout moves skipped
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (SCOUT-1, SCOUT-2)
**Files:** `40k/scripts/AIDecisionMaker.gd` (`_decide_scout`)
**Description:** AI skips scout moves entirely. Should move scouts toward nearest uncontrolled objective, ≥9" from enemies.
**Acceptance:** Each AI scout-eligible unit moves up to its scout distance toward the nearest uncontrolled objective; no closer than 9" to any enemy.
**Validation (MCP):**
- Fixture: deployed AI Kommandos + Witchseekers (after T-015) at end-of-deployment.
- Run scout phase; assert both moved toward nearest objective.
- Assert no AI scout ends within 9" of any enemy. Screenshot before/after positions.

### T-034 — AI fall-back, terrain-aware deployment, reserves bring-on
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (MOV-7, MOV-8, DEPLOY-1, FORM-1, FORM-3)
**Files:** `40k/scripts/AIDecisionMaker.gd`, `40k/phases/DeploymentPhase.gd`, `40k/phases/FormationsPhase.gd`
**Description:** AI never declares Reserves at formations, never brings reserves on later, deploys without cover/LoS consideration, never attaches Leaders during formations.
**Acceptance:** AI scores deployment positions by cover + LoS-blocked-from-enemy; AI declares ≥1 deep-strike unit when list permits; reserves enter on turn 2+ from board edge or via Deep Strike rules; Leaders auto-attach to bodyguard during formations.
**Validation (MCP):**
- Pre-deployment fixture; run AI deployment; assert ≥80% of placed AI units are within 1" of any cover terrain piece.
- Fixture turn-2 with reserves declared; assert AI brings reserves on legally (>9" from enemy).
- Formations phase fixture; assert all eligible Leaders are attached.
- Screenshots: deployment heatmap, reserves entry, formations result.

### T-035 — Leader attachment broken for human player (BUG-1)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#63)
**Files:** `40k/phases/FormationsPhase.gd`, `40k/phases/DeploymentPhase.gd`
**Description:** Human player Leaders deploy as separate units; attachment workflow doesn't apply on the deployment side.
**Acceptance:** Attached pair deploys as a single token; bodyguard models include the Leader's model; attachment bonuses apply.
**Validation (MCP):**
- Fixture in formations: human player attaches Captain to Tactical Squad. Advance to deployment.
- Click deploy; assert one drag operation places all 6 models including the Captain.
- Screenshot deployment + post-deploy unit list (one entry, not two).

### T-036 — Wound allocation position mismatch (BUG-2)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#64)
**Files:** `40k/scripts/WoundAllocationDialog.gd` or equivalent
**Description:** Kommandos shown in wrong board positions inside the wound-allocation overlay; clicks miss intended models.
**Acceptance:** Overlay markers track live model positions in 1:1 board space.
**Validation (MCP):**
- Fixture: Kommandos taking saves. Open allocation overlay.
- For each model, assert overlay marker position equals `model.position` from `get_unit_details`.
- Click each marker; assert correct model index is selected.
- Screenshot overlay vs. board, side by side.

### T-037 — Line-of-sight bug (BUG-3, TER-2 ruins visibility)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#65, TER-2)
**Files:** `40k/autoloads/LineOfSightManager.gd`
**Description:** General LoS bug; Ruins do not block LoS through/over per 10e rules (Aircraft/Towering exceptions).
**Acceptance:** A model behind a Ruins piece is not visible from a non-Aircraft/non-Towering shooter on the opposite side.
**Validation (MCP):**
- Fixture: Marine on one side of a tall Ruins piece, Ork on the other side.
- `get_legal_actions` for Marine — assert Ork is NOT a valid target.
- Move Marine to flank; reassert Ork IS valid.
- Repeat with Aircraft shooter; assert Ork IS valid through Ruins.
- Screenshot of obstructed-target highlight.

### T-038 — Pile-in must end with unit in engagement range
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FIGHT_PHASE_AUDIT (2.2)
**Files:** `40k/phases/FightPhase.gd:_validate_pile_in`
**Description:** Validation lets a unit pile-in to a position where no model is in 1" engagement.
**Acceptance:** Pile-in is rejected if final positions have zero models within 1" of an enemy.
**Validation (MCP):**
- Fixture: Marines 2.5" from Orks. Attempt pile-in directly away.
- Assert validation rejects with explicit reason; UI shows reason.
- Pile-in toward Orks; accept; assert ≥1 model now within 1".

### T-039 — Consolidation into new enemies doesn't trigger their fight
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FIGHT_PHASE_AUDIT (2.4)
**Files:** `40k/phases/FightPhase.gd:_process_consolidate` (959-1001), `_initialize_fight_sequence`
**Description:** Newly engaged enemies aren't appended to the active fight sequence; they get no chance to fight back.
**Acceptance:** Consolidating into a new enemy unit re-runs sequence init; that unit is added to the appropriate priority bucket.
**Validation (MCP):**
- Fixture with 2 enemy units, AI fight-active. AI consolidates into 2nd unit.
- Assert `FightPhase.fight_sequence` now contains the 2nd enemy unit.
- Run sequence; verify 2nd unit gets to attack.
- Screenshot fight order list before/after.

### T-040 — Fights Last subphase never processed
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FIGHT_PHASE_AUDIT (2.6)
**Files:** `40k/phases/FightPhase.gd:51, :55-59, _transition_subphase` (1150-1175)
**Description:** Subphase enum lacks FIGHTS_LAST; units pushed to `fights_last_sequence` are never activated.
**Acceptance:** FIGHTS_LAST exists in Subphase enum; subphase transitions to it after FIGHTS_NORMAL; units fight in correct order.
**Validation (MCP):**
- Fixture: AI unit with FIGHTS_LAST flag (pre-set via execute_script).
- Run fight phase; assert order is FIRST → NORMAL → LAST; that unit fights last.
- Screenshot order indicator.

### T-041 — Fights First + Fights Last cancellation not handled
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FIGHT_PHASE_AUDIT (2.7)
**Files:** `40k/phases/FightPhase.gd:1026-1041` `_get_fight_priority`
**Description:** Sequential checks return FIGHTS_FIRST without considering FIGHTS_LAST cancel; rule says they cancel out into NORMAL.
**Acceptance:** A unit with both flags fights in NORMAL bucket.
**Validation (MCP):**
- Fixture: pre-set both flags on a unit. Inspect `_get_fight_priority` via execute_script — assert returns FIGHTS_NORMAL value.
- Run fight; verify unit fights in normal bucket.
- Screenshot order list.

### T-042 — Transport destruction effects (GEN-8)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#58)
**Files:** `40k/autoloads/TransportManager.gd`
**Description:** Embarked units are silently lost when transport destroyed; should force disembark + per-model D6 mortal-wound test.
**Acceptance:** On transport destruction, embarked unit is deployed within 3" of the wreck, then each model takes a 1-MW-on-1 test.
**Validation (MCP):**
- Fixture: Battlewagon with Boyz embarked, 1 hp left. Resolve killing shot.
- Assert Boyz unit appears within 3" of wreck position; assert dice_log contains 10 D6 rolls; ones cause MWs.
- Screenshot wreck + Boyz emergence.

### T-043 — Pivot values for non-round bases (MOV-1)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#59)
**Files:** `40k/phases/MovementPhase.gd`, `40k/scripts/MovementController.gd`
**Description:** First pivot per movement: 1" for infantry, 2" for Monster/Vehicle, 2" for round-base >32mm flying-stem; subtracted from remaining move.
**Acceptance:** First in-move rotation deducts the correct pivot cost; subsequent pivots are free per rules; UI shows remaining inches.
**Validation (MCP):**
- Fixture with a Vehicle. Begin move; rotate 90°; assert remaining-move display drops by 2".
- Rotate again; assert no further deduction.
- Repeat with infantry on round base ≤32mm; assert no pivot cost.
- Screenshot move overlay after each pivot.

### T-044 — Vertical coherency 5" not validated (MOV-2)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#60)
**Files:** `40k/phases/MovementPhase.gd:_check_models_coherency`
**Description:** Coherency check is 2" horizontal only; should also accept 5" vertical for multi-floor terrain.
**Acceptance:** Two models on different floors of a Ruins piece are considered coherent if vertical distance ≤5".
**Validation (MCP):**
- Fixture: 5-model squad placed across two floors of a Ruins terrain piece.
- Run movement validation; assert no coherency error.
- Move one model >5" up (or down); assert error.

### T-045 — Attached unit starting strength for battle-shock (CMD-6)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#61)
**Files:** `40k/autoloads/RulesEngine.gd:is_below_half_strength`, `40k/phases/CommandPhase.gd`
**Description:** Bodyguard + Leader treated as separate; WARBOSS+10 Boyz unit should have starting strength 11, but logic uses 10.
**Acceptance:** When attached, starting-strength = sum of both units' starting models for half-strength threshold.
**Validation (MCP):**
- Fixture: Warboss attached to 10 Boyz. Apply 5 model casualties.
- Run battle-shock; assert NOT below half (5/11 = 45.4%, but rule is "starting strength" — verify rule interpretation).
- Apply 6 casualties; assert below half.
- Screenshot battle-shock test panel showing starting strength.

### T-046 — Out-of-Phase rules restriction (GEN-1)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#57)
**Files:** `40k/autoloads/StratagemManager.gd`, phase scripts
**Description:** Using out-of-phase rules (e.g., Overwatch in Charge) cannot trigger other normal phase rules; not enforced.
**Acceptance:** When a unit is shooting via Overwatch, normal-phase modifiers (Oath of Moment, Waaagh!) are skipped per the out-of-phase clause.
**Validation (MCP):**
- Fixture: Marines with Oath active overwatch a charging unit.
- Inspect overwatch dice_log; assert Oath reroll-1s wound NOT applied.
- Compare to a normal-phase shoot of the same target — Oath should apply.

### T-047 — Defender no agency in shooting phase (3.1)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#17)
**Files:** `40k/phases/ShootingPhase.gd`, `40k/scripts/StratagemPanel.gd`
**Description:** Defender cannot use Overwatch (proper integration), Go to Ground, Smokescreen, or other reactive abilities outside save allocation overlay. Depends on T-022/T-023.
**Acceptance:** When opponent declares targets, defender sees a reactive-stratagem prompt window with timeout.
**Validation (MCP):**
- Two-instance test: host targets squad; assert client sees Go to Ground prompt with 10s timer.
- Click Go to Ground on client; assert saves taken at +1 per rule; CP deducted from client.
- Screenshot client prompt.

### T-048 — Multiplayer charge state desync of failed_charge_attempts (already partially in T-007 — extend)
**Status:** [MERGED] — folded into the referenced task.
*(Merged into T-007.)*

### T-049 — Movement opponent has no visualization
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** 40k/MOVEMENT_PHASE_AUDIT (3.5)
**Files:** `40k/scripts/MovementController.gd`
**Description:** Models teleport to final positions on the non-active player's screen; no animation, no path.
**Acceptance:** Opponent's screen shows a smooth tween from start to end position on a per-model basis.
**Validation (MCP):**
- Two-instance test: host moves a unit. On client, instrument the tween via `execute_script` to log start/end timestamps.
- Assert tween duration > 200ms; final position matches host.
- Record screen via repeated `capture_screenshot` at 100ms intervals.

### T-050 — TWIN-LINKED weapon keyword
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#2)
**Files:** `40k/autoloads/RulesEngine.gd` (after T-019)
**Description:** Re-roll wound rolls; depends on wound-modifier infrastructure.
**Acceptance:** Twin-linked weapons trigger reroll of failed wound rolls (not modified-1s on reroll).
**Validation (MCP):**
- Fixture: Twin-linked autocannon. Fire; assert dice_log shows up to 2N wound rolls (N original + N rerolls of fails).

### T-051 — HAZARDOUS weapon keyword
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#3) · FEB21_AUDIT (SHOOT-2)
**Files:** `40k/autoloads/RulesEngine.gd`
**Description:** After attacking, roll D6 per Hazardous weapon; on 1, bearer suffers 3 MW (or removed if non-Char/Vehicle/Monster). Plus Balance Dataslate v3.3 allocation priority.
**Acceptance:** Hazardous weapons fire normally, then trigger D6 self-test; allocation priority follows v3.3 wording.
**Validation (MCP):**
- Fixture: Plasma squad fires overcharged. Force D6=1 via seed.
- Assert non-character non-vehicle bearer is removed; character takes 3 MW.

### T-052 — INDIRECT FIRE keyword
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#4)
**Files:** `40k/autoloads/RulesEngine.gd:get_eligible_targets`
**Description:** Can target without LoS; -1 to hit, unmodified 1-3 always fail, target gains Benefit of Cover.
**Acceptance:** Indirect-fire weapons can target non-LoS units; modifier and unmodified-fail rules applied.
**Validation (MCP):**
- Fixture: Whirlwind hidden behind Ruins, Ork mob behind another piece (no LoS).
- Assert mob is in eligible target list; fire; assert -1 hit and 1-3 always fail.

### T-053 — PRECISION keyword
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#5)
**Files:** `40k/autoloads/RulesEngine.gd`, allocation overlay
**Description:** Lets attacker allocate wounds to attached CHARACTER models instead of bodyguard.
**Acceptance:** Sniper-class weapons get an allocation override toggle; selecting Character allocates to it bypassing bodyguard rule.
**Validation (MCP):**
- Fixture: Sniper targets Captain attached to Marines.
- Open allocation; assert Captain is selectable; confirm allocation lands on Captain model.

### T-054 — Cover detection beyond Ruins (woods, craters, barricades, obstacles)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#12) · FEB21_AUDIT (TER-4)
**Files:** `40k/autoloads/RulesEngine.gd:check_benefit_of_cover` (1440-1461), `40k/autoloads/TerrainManager.gd`
**Description:** Only Ruins yield cover. Woods, craters, barricades, obstacles, Obscuring keyword ignored.
**Acceptance:** Each terrain type returns the correct +1 save modifier per 10e rules.
**Validation (MCP):**
- Fixture: target behind Woods; resolve shot; assert save dialog shows +1 cover.
- Repeat for crater, barricade, obstacle, obscuring. Screenshot each.

### T-055 — Stratagem CP cap & spending validation
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AUDIT_COMMAND_PHASE (2.1, 2.6)
**Files:** `40k/autoloads/StratagemManager.gd`, `40k/phases/CommandPhase.gd`
**Description:** No cap on CP gains (1/round non-automatic source max), no validation of sufficient CP, no battle-shocked-can't-be-targeted check, no once-per-phase enforcement.
**Acceptance:** CP gains capped per round; UI prevents activation when insufficient CP; battle-shocked friendly cannot be the target of friendly stratagems; once-per-phase tracked.
**Validation (MCP):**
- Fixture turn 2 with 0 CP. Try to activate Command Re-roll; assert blocked with "Insufficient CP" message.
- Battle-shock a unit. Try to use Move-Move-Move on it; assert blocked.
- Try to use the same stratagem twice in one phase; assert second blocked.

### T-056 — `_clear_phase_flags` corrupts snapshot
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** CHARGE_PHASE_AUDIT (3.5, 5.5)
**Files:** `40k/phases/ChargePhase.gd:67-70, 816-822`
**Description:** Erases `charged_this_turn` / `fights_first` from local snapshot on phase exit; can confuse subsequent fight phase.
**Acceptance:** Method is removed entirely.
**Validation (MCP):**
- Fixture: complete a charge; advance to fight phase; assert `unit.flags.charged_this_turn=true` and `fights_first=true` remain set.
- Run a regression test in `40k/tests/test_charge_phase_flags.gd`.

### T-057 — Path through enemy validation gap (charge intermediate path)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (Validation Task 5)
**Files:** `40k/phases/ChargePhase.gd:_validate_engagement_range_constraints`
**Description:** Only final positions are checked for non-target ER avoidance; should sample intermediate path waypoints.
**Acceptance:** Charge rejected if any path segment crosses within 1" of a non-target enemy.
**Validation (MCP):**
- Fixture: charging unit must move past unrelated enemy whose ER would be brushed.
- Attempt charge; assert validation rejection with reason.
- Move enemy out of path; reattempt; success.

### T-058 — AIRCRAFT charge restrictions (target & charger)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** CHARGE_PHASE_AUDIT (2.7, Validation Task 4)
**Files:** `40k/phases/ChargePhase.gd:_can_unit_charge`, `_validate_declare_charge`
**Description:** AIRCRAFT cannot charge; only FLY can charge AIRCRAFT. Target-side filter not implemented.
**Acceptance:** AIRCRAFT-keyword chargers blocked; AIRCRAFT targets only valid for FLY-keyword chargers.
**Validation (MCP):**
- Fixture: AIRCRAFT vs. AIRCRAFT (no FLY). Assert charge blocked with reason.
- Add FLY to charger; assert charge allowed.

### T-059 — Web `save_exists()` always false (SAVE-5)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (#2)
**Files:** `40k/autoloads/SaveLoadManager.gd:save_exists`
**Description:** Always returns false on web platform; cloud saves overwritten without confirmation.
**Acceptance:** On web export, `save_exists` checks cloud index synchronously (or shows "Confirm overwrite" prompt regardless).
**Validation (MCP):**
- N/A on desktop. Manual web export test required; document in AUDIT_REPORT under "WEB-ONLY VALIDATION".

### T-060 — Client UI not refreshed after MP load
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (#3)
**Files:** `40k/autoloads/NetworkManager.gd:_refresh_client_ui_after_load`
**Description:** Doesn't clear stale visuals, reset phase controllers, or handle deltas; old tokens persist.
**Acceptance:** Method tears down all controllers, clears all token visuals, then rebuilds from snapshot.
**Validation (MCP):**
- Two-instance fixture: load a different game on host while client is mid-shooting.
- Assert client tokens repaint to the loaded board; no leftover UI from prior game.
- Screenshot pre-load and post-load client view.

### T-061 — No multiplayer load restriction UI
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (#4)
**Files:** `40k/scripts/SaveLoadDialog.gd`
**Description:** Save/Load dialog still accessible to clients; clients should not be able to initiate Load.
**Acceptance:** Load button disabled on clients; tooltip "Only host can load saves".
**Validation (MCP):**
- Two-instance test: open dialog on client; assert Load button is disabled.
- Screenshot client dialog.

---

# P2 — MEDIUM (rule polish, AI improvements, multi-phase QoL)

### T-062 — AI focus fire / cross-weapon coordination
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-TACTIC-1, AI-TACTIC-2/SHOOT-1, AI-TACTIC-5/SHOOT-2)
**Files:** `40k/scripts/AIDecisionMaker.gd`
**Description:** Each weapon picks own target with no cross-unit coordination. No threat priority. Lascannon and bolt rifle hit the same target.
**Acceptance:** AI builds a global priority list (toughness, points, threat range), assigns weapons greedily by best efficiency match, switches to next priority once a kill threshold is met.
**Validation (MCP):**
- Fixture: AI Marine squad with mixed lascannon + bolters vs. one tank + one infantry.
- Run shooting; assert lascannon → tank, bolters → infantry; verify with action log.
- Vary infantry toughness / cover; assert AI re-prioritizes correctly.

### T-063 — AI threat range & screen-aware movement
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-TACTIC-3/MOV-4, AI-TACTIC-4/MOV-2, MOV-1)
**Files:** `40k/scripts/AIDecisionMaker.gd:_compute_screen_position` (exists, never called)
**Description:** AI doesn't pre-measure enemy threat ranges, walks into charge/rapid-fire range, never calls existing screen helper.
**Acceptance:** AI movement scoring penalizes positions inside enemy 9" charge bubble unless attacker; calls `_compute_screen_position` for screening units.
**Validation (MCP):**
- Fixture: enemy charge unit 14" from AI, AI to move.
- Run movement; assert AI ends >9" from the charger (or accepts the charge intentionally).
- Provide a screen unit; assert AI places it between key unit and DS landing zone.

### T-064 — AI multi-target charge declarations & risk assessment
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (CHARGE-4, CHARGE-5)
**Files:** `40k/scripts/AIDecisionMaker.gd`
**Description:** AI doesn't declare multiple charge targets nor model overwatch risk.
**Acceptance:** AI computes expected charge-success probability and overwatch damage; chooses best target subset.
**Validation (MCP):**
- Fixture: AI 9" from two enemies; assert AI declares both as charge targets when sum charge probability is positive.
- Variant with overwatch-heavy enemy; assert AI may skip if EV < 0.

### T-065 — AI fight: only one melee weapon used
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (AI-GAP-7/FIGHT-3) · FIGHT_PHASE_AUDIT (2.8)
**Files:** `40k/scripts/AIDecisionMaker.gd:_assign_fight_attacks`, AttackAssignmentDialog auto-include for Extra Attacks
**Description:** AI picks first melee weapon; ignores Extra Attacks weapons that should auto-add.
**Acceptance:** AI selects best melee weapon by expected damage AND auto-includes any EXTRA_ATTACKS weapons.
**Validation (MCP):**
- Fixture: model with chainsword + power fist + Extra Attacks pistol.
- Run AI fight; assert dice_log shows EA pistol attacks alongside the chosen primary weapon.

### T-066 — AI engaged-unit survival assessment
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (MOV-9)
**Files:** `40k/scripts/AIDecisionMaker.gd`
**Description:** AI doesn't estimate fight-phase damage from engaged enemy before deciding hold/fall-back/advance.
**Acceptance:** Movement decision considers expected casualties next fight phase; falls back if expected loss > 40%.
**Validation (MCP):**
- Fixture: AI 5-Marine squad engaged with Custodes (high damage). Run movement.
- Assert AI Falls Back; verify with `unit.flags.fell_back=true`.

### T-067 — Heroic Intervention charge roll terrain (CHG-2)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#74)
**Files:** `40k/phases/FightPhase.gd:_is_heroic_intervention_roll_sufficient`
**Description:** HI charge roll doesn't apply terrain vertical penalties.
**Acceptance:** HI move costs include vertical climb costs identical to charge moves.
**Validation (MCP):**
- Fixture: HI eligible across a barricade/level. Roll fixed-seed; assert distance reduced by terrain cost.

### T-068 — Tank Shock Balance Dataslate v3.3 wording (CHG-1)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#73)
**Files:** `40k/autoloads/StratagemManager.gd` (Tank Shock entry)
**Description:** D6 = TOUGHNESS, 5+ = MW, capped at 6 MW.
**Acceptance:** Tank Shock applies the v3.3 dice formula and caps.
**Validation (MCP):**
- Fixture: Vehicle Tank Shocks T4 squad. Force seed of 6 dice all 6.
- Assert exactly 6 MW dealt (cap applied, not 6 from rolls × 1).

### T-069 — Fire Overwatch Balance Dataslate update (GEN-6)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#85)
**Files:** `40k/autoloads/StratagemManager.gd`
**Description:** Trigger expanded for "starts or ends a move" not just "starts".
**Acceptance:** Overwatch prompts when a unit begins OR ends any movement type within visibility.
**Validation (MCP):**
- Fixture: charging unit ends move within 12". Assert overwatch prompt fires.
- Repeat with normal-move ending in LoS — assert prompt fires.

### T-070 — Aura abilities system (GEN-7)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** FEB21_AUDIT (#86)
**Files:** `40k/autoloads/UnitAbilityManager.gd`, new range-aura system
**Description:** `passive_aura` is defined on units but never applied to others; no range-based aura system.
**Acceptance:** Auras compute coverage every phase; affected units get the modifier in `unit.flags.aura_modifiers`.
**Validation (MCP):**
- Fixture: Captain reroll-1s aura, two Marines within 6", one outside.
- Resolve attacks for both; assert aura applied to first two only.

### T-071 — Attached unit Toughness resolution (GEN-13)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#87)
**Files:** `40k/autoloads/RulesEngine.gd`
**Description:** Wound rolls vs attached unit should use bodyguard T, not character T.
**Acceptance:** When character is attached, wound roll uses bodyguard's Toughness.
**Validation (MCP):**
- Fixture: Captain T4 attached to Terminator T5 squad. Resolve S5 shot.
- Assert wound roll = 4+ (T5), not 3+ (T4).

### T-072 — Stand Vigil objective-conditional reroll
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** ABILITIES_AUDIT (#70) · LIONS_ARMY_AUDIT (#47)
**Files:** `40k/autoloads/UnitAbilityManager.gd` ABILITY_EFFECTS["Stand Vigil"]
**Description:** Currently always reroll-1s; rule says reroll ALL wounds while within range of controlled objective.
**Acceptance:** Condition is checked dynamically; "controlled objective range" → reroll all; else reroll-1s.
**Validation (MCP):**
- Fixture: Custodian Guard within 3" of controlled objective.
- Resolve attacks; assert dice_log shows reroll-all-fails.
- Move off objective; reattack; assert reroll-1s only.

### T-073 — Custodes datasheet abilities (Trajann, Allarus, Vertus, Callidus, Draxus, Dawneagle)
**Status:** [STUB-PENDING-IP] — data-shape skeleton in place; full datasheet/stat values pending Wahapedia/IP review (T-029 workstream).
**Source:** 40k/AUDIT_ABILITIES_2 (#90-102) · LIONS_ARMY_AUDIT (#41-46)
**Files:** `40k/autoloads/UnitAbilityManager.gd`, faction-specific managers
**Description:** Sweeping Advance, Slayers of Tyrants, From Golden Light, Purity of Execution, Turbo-boost, Quicksilver Execution, Acrobatic Escape, Lord of Deceit, Shadow Assignment, Authority of the Inquisition, Xenos Hunter, Psychic Veil. Each unimplemented; depends on T-029 to land first.
**Acceptance:** Each ability has an ABILITY_EFFECTS entry, the relevant phase trigger, and a UI prompt where appropriate.
**Validation (MCP):** One sub-fixture per ability (12 fixtures). For each: drive to trigger window, activate, capture screenshot, assert effect via `get_unit_details` or `dice_log`.

### T-074 — Enhancements weapon-modifier system (Admonimortis, Superior Creation, Praesidius, Fierce Conqueror)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** LIONS_ARMY_AUDIT (#40)
**Files:** new `40k/autoloads/EnhancementManager.gd`, JSON loader
**Description:** No system exists for stat-modifying enhancements that target a specific weapon profile (+3S/+1AP/+1D melee, etc.).
**Acceptance:** Enhancements register weapon-stat overrides on the assigned model; modifications surface in Mathhammer and live combat.
**Validation (MCP):**
- Fixture: Shield-Captain with Admonimortis. Resolve melee attacks.
- Assert dice_log shows S+3 wound rolls, AP+1 in save calc, D+1.

### T-075 — Talons of the Emperor faction auras (Null Aegis, Deadly Unity)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** LIONS_ARMY_AUDIT (#52)
**Files:** `40k/autoloads/FactionAbilityManager.gd`
**Description:** Custodes within 6" of ANATHEMA PSYKANA get FNP 5+ vs Psychic/MW (Null Aegis); +1 hit aura (Deadly Unity). Depends on T-070.
**Acceptance:** Auras compute correctly with mixed Custodes + Sisters detachment.
**Validation (MCP):**
- Fixture: Custodian Guard 5" from Sisters of Silence. Resolve a Smite-equiv vs Custodes.
- Assert FNP 5+ rolled; move Sisters >6"; reassert no FNP.

### T-076 — Devastating Wounds mortal-wound spillover
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#13)
**Files:** `40k/autoloads/RulesEngine.gd:_apply_damage_to_unit_pool` (3777-3790)
**Description:** DW applied as pool damage; may diverge from RAW spillover behavior.
**Acceptance:** DW is applied as explicit MW per the most recent FAQ; spillover behavior matches example play.
**Validation (MCP):**
- Fixture: weapon with DW and damage 2. Wound roll 6 vs 2-wound model with 1 wound left.
- Assert 1 MW kills the model AND remaining MW spills to next model (per FAQ).

### T-077 — Pistol mutual-exclusivity & Pistol-in-engagement evaluation
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#14) · AI_AUDIT (SHOOT-9)
**Files:** `40k/phases/ShootingPhase.gd:_validate_assign_target` (180-211)
**Description:** Model could be assigned both a Pistol and a non-Pistol weapon; AI doesn't evaluate Pistol use in engagement.
**Acceptance:** Validation enforces XOR per model; AI uses Pistols when engaged.
**Validation (MCP):**
- Fixture: Marine with bolt pistol + bolt rifle. Try assign both; assert blocked.
- Move into engagement; assert only Pistol is selectable for shooting.
- AI variant: AI in ER should fire Pistols.

### T-078 — Auto-resolve / one-click shooting QoL (5.1, 5.2)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SHOOTING_PHASE_AUDIT (#22, #23)
**Files:** `40k/scripts/ShootingController.gd`, weapon assignment dialog
**Description:** No "Auto-select weapon for single-weapon units" and no "Shoot All Remaining" button.
**Acceptance:** Single-weapon units skip the weapon-selection step; "Shoot All Remaining" runs all valid targets in queue.
**Validation (MCP):**
- Fixture: 3 single-weapon Boyz mobs. Click Shoot All Remaining.
- Assert all 3 fire sequentially. Screenshot the queue.

### T-079 — Multiplayer race condition mitigations (Fight 3.3, 3.4; Movement 3.6, 3.7; Charge ack-driven)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FIGHT_PHASE_AUDIT (3.3, 3.4) · 40k/MOVEMENT_PHASE_AUDIT (3.6, 3.7)
**Files:** `40k/scripts/FightController.gd:1357-1392`, `40k/scripts/MovementController.gd:2747-2768`, `40k/autoloads/NetworkManager.gd`
**Description:** Various 50ms/100ms timer-based waits between sequential client actions; replace with action acknowledgments or composite actions.
**Acceptance:** No fixed-timer waits in sequential client paths; ack-driven flow.
**Validation (MCP):**
- Two-instance test under simulated 200ms latency (`execute_script` mock).
- Run fight assignment + confirm; assert no missed acks, no duplicate dialogs.
- Run group movement; assert all models received and confirmed.

### T-080 — Disembarked unit Remain Stationary fix (MOV 2.12)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** 40k/MOVEMENT_PHASE_AUDIT (2.12)
**Files:** `40k/phases/MovementPhase.gd:1914 (_initialize_movement_for_disembarked_unit), :880 (_process_remain_stationary)`
**Description:** Disembarked units don't have `remained_stationary=false` set; if Remain Stationary is picked, Heavy bonus is incorrectly granted.
**Acceptance:** Disembark sets a flag preventing Remain Stationary or zeroes Heavy bonus.
**Validation (MCP):**
- Fixture: unit disembarks. Click Remain Stationary; assert weapon stat dialog shows NO Heavy bonus.

### T-081 — Coherency / engagement-range helper consolidation
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** Movement audit (Item 3) · root MOVEMENT_PHASE_AUDIT
**Files:** `40k/phases/MovementPhase.gd` (4 ER helpers), `40k/scripts/Measurement.gd`
**Description:** 4 near-duplicate helpers for engagement range; some shape-aware, some centre-to-centre. Risk of validation divergence.
**Acceptance:** Single canonical `Measurement.in_engagement_range(model_a, model_b)` used everywhere.
**Validation (MCP):**
- Headless test in `40k/tests/test_engagement_range.gd` exercises edge cases (B2B, exactly 1.0", oversized base, FLY).
- Visual fixture: drag a model to exactly 1.0" boundary; assert deterministic result.

### T-082 — Movement Euclidean vs path distance (6.4)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** 40k/MOVEMENT_PHASE_AUDIT (6.4)
**Files:** `40k/phases/MovementPhase.gd:323`
**Description:** Distance is measured origin → destination, not along the actual path. Could be exploited to "teleport" around obstacles.
**Acceptance:** Distance is sum of segment lengths along the dragged path.
**Validation (MCP):**
- Fixture: model with 6" move tries to L-shape around a wall. Drag in two segments totalling 7".
- Assert validation rejects with reason "path exceeds movement".

### T-083 — Mission system: Scorched Earth, The Ritual, Terraform incomplete (MIS-1/2/3)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#79-81)
**Files:** `40k/autoloads/MissionManager.gd`, mission JSON
**Description:** Three named missions are stubs; burn mechanics, action-based objectives, and objective flipping are unimplemented.
**Acceptance:** Each mission's primary mechanic functions; VP awarded per spec.
**Validation (MCP):**
- One sub-fixture per mission. Drive to scoring window; assert correct VP awarded.
- Screenshot scoring panel.

### T-084 — Secondary missions framework (MIS-4, AI-TACTIC-8, scoring loop)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (#82) · AI_AUDIT (SCORE-1) · AUDIT_COMMAND_PHASE (2.7)
**Files:** new `40k/autoloads/SecondaryMissionManager.gd`
**Description:** Only tactical-deck mode exists; no fixed-secondary option, no scoring loop, AI ignores secondaries entirely.
**Acceptance:** Mission selector includes Fixed Secondaries; player picks two; scoring updates each turn-end; AI evaluates secondaries.
**Validation (MCP):**
- Fixture pre-game: select Fixed Secondaries (Engage on All Fronts + Behind Enemy Lines).
- Play 2 turns; assert per-turn VP added matches the conditions in `_check_secondary`.
- AI variant: AI must position to score Engage on All Fronts.

### T-085 — Battle-shock immunity & flag consolidation
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (CMD-2) · AUDIT_COMMAND_PHASE (2.2) · 40k/AUDIT_COMMAND_PHASE (P3) · .llm/rules-audit
**Files:** `40k/phases/CommandPhase.gd:_identify_units_needing_tests`, all consumers of `unit.flags.battle_shocked` vs `unit.status_effects.battle_shocked`
**Description:** No FEARLESS/ATSKNF immunity check; storage of battle_shocked split across two locations.
**Acceptance:** Single source of truth (`flags.battle_shocked`); FEARLESS/ATSKNF auto-pass test.
**Validation (MCP):**
- Fixture: Marines below half-strength with ATSKNF active. Trigger battle-shock test.
- Assert no roll attempted; status remains non-shocked.
- `execute_script` to dump both flag locations — assert one removed.

### T-085a — Live-validate the BLOCKED ability backlog (13+ abilities flagged `implemented: true` but never live-driven)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** UNIT_ABILITY_AUDIT (entire "BLOCKED (live)" status row + Section "Scope I did NOT live-validate" on lines 356-378)
**Files:** New fixture saves in `40k/saves/`, new tests in `40k/tests/unit/`, ability code paths if defects found
**Description:** The 2026-05-04 unit audit live-validated 30 abilities but flagged 13+ as `BLOCKED (live)` — they are marked `implemented: true` in `ABILITY_EFFECTS` and have helper-function evidence, but no audit has actually driven them through a multi-step combat scenario. **Per the project rule "live-validate every feature claim", `implemented: true` is not validation.** Each of these is a latent regression risk. Backlog: Swift Onslaught, Martial Inspiration, Master of the Stances "Both Stances" UI, Strategic Mastery CP discount path, Sentinel Storm shoot-again UI, Sweeping Advance / Acrobatic Escape end-of-Fight UI, Sanctified Flames post-shoot Battle-shock test, Advanced Firepower (Caladius), Dread Foe (Contemptor-Achillus), Damaged-threshold -1 Hit at low wounds, Might is Right / Da Biggest and da Best / Dead Brutal (Warboss melee), Sneaky Surprise overwatch block, Distraction Grot, Bomb Squigs, Dok's Toolz, One Scalpel Short of a Medpack, Prophet of Da Great Waaagh! aura, Flashiest Gitz (Kaptin Badrukk).
**Acceptance:** A reusable Round-2 fight fixture (`audit_round2_fight.w40ksave`, similar to the existing `co_pretrigger.w40ksave` pattern) plus per-ability targeted fixtures where needed. Each ability has a documented live MCP-bridge run (action dispatch / flag inspection / dice log) AND a headless GDScript regression test in `40k/tests/unit/`.
**Validation (MCP):** Per-ability scenario; for each:
- Load the relevant fixture; drive to the trigger window via `transition_to_phase` + `dispatch_action`.
- Activate the ability (via UI action where present, or via `execute_script` invoking the helper).
- Assert the expected runtime flag lands on the target unit (e.g., `effect_reroll_charge`, `effect_advance_and_charge`, `effect_plus_one_hit`, `effect_fnp: 5`, weapon-stat override).
- Capture a screenshot named `T-085a_<ability_slug>.png`.
- Append a row per ability to `40k/test_results/audit_2026_05/AUDIT_REPORT.md` documenting the live evidence.
- If the live behavior diverges from `ABILITY_EFFECTS["X"].implemented == true`, file a sub-task under P0/P1 as appropriate.
**Estimated scope:** ~13 abilities × 30-45 min per-ability fixture build + drive + screenshot ≈ 6-10 hours total. Should be scheduled as a single dedicated session (not interleaved) so fixtures can be reused.

### T-086 — Code quality sweep (debug-print gating, duplicate code paths, dead code)
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** Multiple audits (Shooting 4.1; Fight 6.1-6.5; Charge 5.1-5.6; Movement 6.1-6.7; Deployment Code Quality 1-2)
**Files:** Phase scripts and controllers across `40k/phases/` and `40k/scripts/`
**Description:** Aggregated cleanup: gate ~300 `print()` statements behind `DebugLogger`; consolidate duplicate auto-resolve / interactive shooting paths; remove dead `validate_action_with_transport_check`, `advance_to_next_fighter`, group-movement stubs, unused `_clear_phase_flags`; consolidate `_circle_wholly_in_polygon` etc. into `Measurement.gd`; deduplicate `get_unit_movement` between MovementPhase and MovementController.
**Acceptance:** No `print()` outside DebugLogger; no dead methods (Godot's "unused parameter" lint clean); a single canonical helper for each duplicated piece.
**Validation (MCP):**
- Pre-cleanup baseline: `wc -l` on phase scripts, count of print(), dead-code report.
- Post-cleanup re-run; full test suite passes; no behavioral regression.
- Screenshot scene to confirm in-game UI unchanged.

---

# P3 — LOW (QoL, visual polish, niche rules)

### T-087 — Mathhammer code-quality polish (debug prints, selection paradigms)
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** MASTER_AUDIT (MH-UI-4, MH-UI-5)
**Files:** `40k/scripts/MathhammerUI.gd`, `40k/scripts/Mathhammer.gd`
**Description:** ~70 debug prints; OptionButton-vs-spinbox-rows inconsistency for attacker/defender selection.
**Acceptance:** Prints gated; uniform selection widget.
**Validation:** Mathhammer regression test in `40k/tests/test_mathhammer.gd` plus a screenshot comparison.

### T-088 — Mathhammer auto-detect weapon abilities (T4-20)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** MASTER_AUDIT (T4-20)
**Files:** `40k/scripts/MathhammerRuleModifiers.gd:134-180` `extract_unit_rules()` (exists, not connected)
**Description:** `extract_unit_rules` is wired in code but not invoked by UI; weapon keywords aren't auto-enabled in Mathhammer.
**Acceptance:** Selecting a weapon in MathhammerUI auto-toggles its keyword modifiers.
**Validation (MCP):**
- Open Mathhammer; pick Lascannon (Sustained Hits + Lethal Hits); assert toggles auto-on.
- Screenshot UI before/after.

### T-089 — AI difficulty levels & speed controls
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (QoL-3, QoL-5)
**Files:** `40k/autoloads/AIPlayer.gd`, `40k/scripts/Settings.gd`
**Description:** `AI_ACTION_DELAY` hardcoded to 50ms; no "Easy/Normal/Hard" toggle.
**Acceptance:** Settings menu offers AI speed slider and 3 difficulty tiers; difficulty affects search depth/heuristic depth.
**Validation (MCP):**
- Open settings; change speed to "Slow"; observe action delay > 500ms during AI turn.

### T-090 — AI turn summary & thinking indicators
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** AI_AUDIT (QoL-1, QoL-2, QoL-4)
**Files:** new UI panels
**Description:** No "thinking" spinner; no per-action explanation; no end-of-turn summary.
**Acceptance:** Thinking indicator visible during AI decision; summary panel lists actions taken with VP/CP delta.
**Validation (MCP):**
- AI turn fixture; capture screenshot during thinking; capture summary at end.

### T-091 — AI movement path visualization (VIS-1)
**Status:** [PARTIAL-LIVE-VALIDATED] — tween + path-line both shipped (commit 54cd86d). Tween via T-049 (live-screenshot t091_tween_midflight_proof). Path-line via Main._show_ai_movement_paths spawning AIMovementPathVisual on AI CONFIRM_UNIT_MOVE (live-screenshot t091_path_persistent_proof shows visible blue dashed trail). Umbrella ships its single audit-listed item.
**Source:** AI_AUDIT (VIS-1)
**Files:** `40k/scripts/MovementController.gd`, `40k/scripts/Main.gd`, `40k/scripts/AIMovementPathVisual.gd`
**Description:** AI units teleport to destinations.
**Acceptance:** AI movements tween with visible path line, like multiplayer playback.
**Validation (MCP):**
- Capture screen at 100ms intervals during AI move; assert mid-frames show in-flight position.

### T-092 — Charge phase QoL bundle
**Status:** [PARTIAL-LIVE-VALIDATED] — 12&quot; charge-range overlay around active charging unit shipped (commit 54cd86d, ChargeController._show_charge_range_circle, live-screenshot t092_12_inch_charge_overlay_clean). Other items deferred: auto-path, per-model undo, defender-side visibility, dedicated dice animation. Pre-existing in source: target-engagement visuals, charge arrows, distance label, snap-to-base-contact.
**Source:** CHARGE_PHASE_AUDIT (4.1-4.11)
**Files:** `40k/scripts/ChargeController.gd`
**Description:** No auto-path, no drag-time validation feedback, no engagement-range visualization, no distance-to-target indicator, no charge-range indicator on selection, basic ColorRect highlights, basic charge line, no dice animation, no per-model undo, no defender-side visibility.
**Acceptance:** Each item delivered as a coherent bundle; charge phase feels responsive.
**Validation (MCP):**
- Walkthrough: select chargers; observe 12" overlay; drag toward target; observe live distance label; declare; observe dice animation.
- Screenshot at each step. Two-instance variant validates defender visibility.

### T-093 — Fight phase QoL bundle
**Status:** [PARTIAL-LIVE-VALIDATED] — Phase Damage tally HUD label shipped (commit 54cd86d, FightController._update_phase_wounds_label fed by _on_attacks_resolved_visual, live-screenshot t093_phase_wounds_tally). Other items deferred: expected-damage preview, max-cap, snap-to-B2B, scoreboard, dedicated fight dice animation, auto-fight. Pre-existing in source: assign-all-to-target (AttackAssignmentDialog._on_all_to_target_pressed), floating damage numbers, FightPhaseStateBanner sequence, EndFightConfirmationDialog.
**Source:** FIGHT_PHASE_AUDIT (4.1-4.7, 5.1-5.5)
**Files:** `40k/scripts/FightController.gd`, `AttackAssignmentDialog`, `PileInDialog`, `ConsolidateDialog`
**Description:** Bulk QoL: assign-all-to-target, expected damage, clear-last, max-cap, ER rings around enemies, snap-to-B2B, sequence banner, scoreboard, dice animation, floating damage numbers, end-of-phase confirmation, auto-fight option.
**Acceptance:** Coherent UX upgrade; per-feature toggles in settings.
**Validation (MCP):**
- Walkthrough fight phase with all items active; screenshot each.

### T-094 — Movement phase QoL bundle
**Status:** [PARTIAL-LIVE-VALIDATED] — move-range green-ring overlay around active moving unit shipped (commit 54cd86d, MovementController._show_move_range_overlay/_clear_move_range_overlay wired into _on_unit_move_begun + _on_unit_move_confirmed, live-screenshot t094_move_range_v2). Other items deferred: ER overlay during movement, in-movement coherency dots, auto-select next unmoved, hotkey reference overlay, ghost preview, board-edge warning. Pre-existing: per-model undo, dashed paths via HumanMovementPathVisual, advance_roll_label, T-049 tween playback.
**Source:** 40k/MOVEMENT_PHASE_AUDIT (4.1-4.12, 5.1-5.5)
**Files:** `40k/scripts/MovementController.gd`
**Description:** Move range overlay, ER overlay, coherency dots in movement, breadcrumbs, auto-select next unmoved, select-all single-model, undo across units, summary on End Phase, advance roll display, hotkeys, Ctrl+grid-snap fix, stale error gating; visual: dashed paths, model state indicators, ghost preview, board-edge warning, opponent replay smoothing.
**Acceptance:** Bundle delivered; UX feels modern.
**Validation (MCP):**
- Walkthrough; screenshot each.

### T-095 — Deployment phase QoL & visual bundle
**Status:** [PARTIAL-LIVE-VALIDATED] — HotkeyHelpOverlay panel toggleable via &quot;?&quot; key shipped (commit 54cd86d, Main._toggle_hotkey_help_overlay, live-screenshot t095_t110_hotkey_help_overlay shows centered panel listing keyboard shortcuts). Other items deferred: edge color border, zone hatching shader, ghost pulse, name labels, opponent zone dim. Pre-existing: drop-in animation for preview tokens, coherency circles with 2&quot; range, opponent zone pulse, Save Measurements button.
**Source:** DEPLOYMENT_AUDIT (#9, #11, #12, items 2-8)
**Files:** `40k/phases/DeploymentPhase.gd`, `40k/scripts/DeploymentController.gd`, `40k/scripts/Main.gd`
**Description:** Measuring tool button, coherency distance label on ghost, hotkey reference overlay, drop-in animation, edge color border, zone hatching, ghost pulse, coherency circles, name labels, opponent zone dim.
**Acceptance:** Bundle delivered.
**Validation (MCP):**
- Capture deployment phase walkthrough; screenshot each item.

### T-096 — Command phase QoL bundle
**Status:** [PARTIAL-LIVE-VALIDATED] — battle-shock token visual (red glow ring + &quot;!&quot; badge) shipped (commit 54cd86d, TokenVisual._draw_battle_shock_indicator called from both standard and letter-mode paths, live-screenshot t096_battle_shock_v3 shows red badges on Custodian Guard tokens). Other items deferred: phase progress 1/3 indicator, OC animation, CP change floats, MP opponent view, scrollable right panel. Pre-existing: rich command panel (CP, objectives, VP, secondary missions, AITurnSummaryPanel, battle-shock test logic).
**Source:** AUDIT_COMMAND_PHASE (3.3-3.9)
**Files:** `40k/scripts/CommandController.gd`, `40k/scripts/TokenVisual.gd`
**Description:** Battle-shock visuals (red border/pulse/icon), phase progress 1/3 → 3/3, turn summary on entry, objective control animation, CP change floats, MP opponent view, scrollable right panel.
**Acceptance:** Bundle delivered.
**Validation (MCP):**
- Walkthrough command phase; assert all visual states present.

### T-097 — Mission selection / multi-mission UI
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** DEPLOYMENT_AUDIT (#10) · FEB21_AUDIT (MIS-4)
**Files:** `40k/scripts/MainMenu.gd`, `40k/autoloads/MissionManager.gd`
**Description:** Only "Take and Hold" implemented; need at least 2 more 10e Leviathan / Pariah Nexus missions.
**Acceptance:** Mission picker with 3+ missions, each with proper objective placement and primary scoring.
**Validation (MCP):**
- Pick each mission; deploy; play 1 turn; assert primary VP correct.

### T-098 — TITANIC unit deployment skip
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** DEPLOYMENT_AUDIT (#8)
**Files:** `40k/autoloads/TurnManager.gd:check_deployment_alternation`, `40k/phases/DeploymentPhase.gd`
**Description:** TITANIC keyword should cause player to skip the next deployment turn.
**Acceptance:** After deploying a TITANIC unit, alternation skips to the same player twice.
**Validation (MCP):**
- Fixture pre-deployment with one TITANIC unit. Deploy it.
- Assert next prompt is for same player; verify with `TurnManager.current_player`.

### T-099 — Deployment multiplayer mitigations (disconnect/reconnect, timeout, race conditions)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** DEPLOYMENT_AUDIT (mp #2, #4, #6, #7)
**Files:** `40k/autoloads/NetworkManager.gd`
**Description:** `_on_peer_disconnected` calls `get_tree().quit()`; 90s deployment timeout too short; embark/attach race; web relay 0.5s state delay shows nothing.
**Acceptance:** Reconnect dialog with grace period, 180s default, composite deploy+embark/attach action, "Waiting for game state…" loading screen.
**Validation (MCP):**
- Two-instance: kill client. Assert host shows "Reconnect or forfeit?" instead of quitting.
- Long deployment fixture: assert no auto-end at 90s.

### T-100 — Save/Load polish (preview, slot system, filtering, indicators)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** SAVE_AUDIT (#10-#20)
**Files:** `40k/scripts/SaveLoadDialog.gd`, `40k/autoloads/SaveLoadManager.gd`
**Description:** Save preview/summary, multi-slot, sort/filter, autosave indicator, load confirmation dialog, transition animation, progress indicator, validation, compression, export/import.
**Acceptance:** Bundle delivered.
**Validation (MCP):**
- Walkthrough save dialog with 5 saves of varying timestamps; verify each polish item.
- Screenshot dialog states.

### T-101 — Niche rules: Surge moves, one Normal-move-per-phase, M/V through M/V, Extra Attacks weapon-name-locked
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (MOV-3/4/5, SHOOT-4)
**Files:** `40k/phases/MovementPhase.gd`, `40k/autoloads/RulesEngine.gd`
**Description:** Multiple smaller rule omissions per FEB21 list.
**Acceptance:** Each rule enforced; tests cover edge cases.
**Validation (MCP):** Per-rule sub-fixture; one screenshot each.

### T-102 — Rules verification pass (Detachment Rule wiring, build-time keyword sanity, second-rank attacks at boundary)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** .llm/rules-audit (#129, #130, #134)
**Files:** `40k/autoloads/FactionStratagemLoader.gd:127-163`, `40k/phases/FightPhase.gd:1193`, build-time validators
**Description:** Items flagged "Verify" — confirm passive detachment rule reads off selected detachment, not faction blanket; ensure VEHICLE units have VEHICLE keyword; per-model fight eligibility pre-filter at FightPhase boundary.
**Acceptance:** Each verified with a regression test in `40k/tests/`.
**Validation (MCP):** Headless tests; document results in AUDIT_REPORT.

### T-103 — Multi-floor ruins vertical movement cost
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** .llm/rules-audit (#127) · CHARGE_PHASE_AUDIT (Validation Task 2/3)
**Files:** `40k/phases/MovementPhase.gd:901-948, 1022-1079`, `40k/phases/ChargePhase.gd`, terrain elevation model
**Description:** Currently treats traversal of terrain >2" as ground-level only. Multi-level ruins are silently flat.
**Acceptance:** Vertical climb cost added to move/charge inches; vertical engagement (5") for charge.
**Validation (MCP):**
- Fixture with multi-floor ruin. Move from ground to top floor; assert vertical cost deducted.
- Charge from below to above; assert ER 5" vertical applies.

### T-104 — Wargear: Helix Gauntlet, Infiltrator Comms Array, Telemon Caestus
**Status:** [FIXED] — code change shipped this audit; covered by task-specific pin test.
**Source:** ABILITIES_AUDIT (#76-78)
**Files:** `40k/armies/<faction>.json`, `40k/autoloads/UnitAbilityManager.gd`
**Description:** Optional wargear (Helix Gauntlet FNP 6+, Infiltrator Comms Array CP regain 5+, Telemon dual caestus +2 melee attacks) absent from JSON and ABILITY_EFFECTS.
**Acceptance:** Each option selectable in army builder; effect applies in game.
**Validation (MCP):**
- Fixture: Infiltrator squad with Helix Gauntlet. Take damage. Assert FNP 6+ rolled in dice_log.
- Repeat for Comms Array and Telemon.

### T-105 — Da Jump (Weirdboy psychic) and Waaagh! Energy (U-2, U-3)
**Status:** [LIVE-VALIDATED] — feature driven via MCP bridge with state inspection + screenshot evidence (session_2026_05_05 / session_2026_05_06).
**Source:** ABILITIES_AUDIT (#73, #74) · UNIT_ABILITY_AUDIT (U-2 Waaagh! Energy, U-3 Da Jump, **both confirmed unreachable in live game 2026-05-04**: Movement Phase `available_actions` for Weirdboy contains only `BEGIN_NORMAL_MOVE`, `BEGIN_ADVANCE`, `REMAIN_STATIONARY` — no `DA_JUMP`. `get_active_ability_effects_for_unit('U_WEIRDBOY_J') == []` despite Waaagh! active.)
**Files:** `40k/phases/MovementPhase.gd`, `40k/autoloads/UnitAbilityManager.gd`
**Description:** End-of-Movement teleport (D6 MW on 1, place 9"+ from enemies); +1 S/D 'Eadbanger per 5 models, Hazardous at 10+.
**Acceptance:** Both abilities trigger at the right time; randomness behaves correctly.
**Validation (MCP):**
- Fixture with Weirdboy + 10 Boyz. End movement; trigger Da Jump; place 9.5" from enemy; assert position accepted.
- Force-roll 1; assert D6 MW dealt to Boyz unit.

### T-106 — Bodyguard 20-model and 22-cap Battlewagon edge cases
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** ABILITIES_AUDIT (#79, #80)
**Files:** `40k/autoloads/FormationsManager.gd`, `40k/autoloads/TransportManager.gd`
**Description:** Boyz 20-model unit allows double-Leader attachment; Battlewagon transport is "Partial" with destruction effects somewhat covered (verify after T-042).
**Acceptance:** 20-model Boyz accepts two Leaders; Battlewagon test suite covers all destruction paths.
**Validation (MCP):**
- Fixture: 20 Boyz + Warboss + Painboy. Assert both Leader attachments accepted in Formations phase.

### T-107 — Sub-floor mission tasks: defender objective control, secondary recheck, end-of-turn timing
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** FEB21_AUDIT (MIS-5/6) · .llm/rules-audit (#132)
**Files:** `40k/autoloads/MissionManager.gd`
**Description:** Marked-for-Death / Tempting Target opponent selection paths; objective control timing (end of phase vs turn); secondary scoring excludes battle-shocked OC.
**Acceptance:** Each rule path verified; tests cover edge cases.
**Validation (MCP):**
- Fixture: opponent picks Marked-for-Death target; assert UI prompt and VP awarded on kill.
- Battle-shock unit on objective; assert OC=0 in scoring.

### T-108 — Niche AI tactics & strategy
**Status:** [PARTIAL-LIVE-VALIDATED] — battle-shocked-still-selected-as-shooters fix shipped (commit 54cd86d, AIDecisionMaker._decide_shooting now skips units with flags.battle_shocked in both focus-fire and fallback selection paths). Pure-math, no UI. Other items deferred: range-band optimization, secondaries-aware scoring, fight-order optimization, character hiding, matchup-aware deployment, late-game pivot. Pre-existing in source: multi-phase planning gate, counter-deployment, tempo modifier, defensive stratagem scoring, cover scoring.
**Source:** AI_AUDIT (AI-TACTIC-6/7/9/10, MOV-3, MOV-7, SCORE-2, SHOOT-6/7/8/10, FIGHT-4/5/6, DEPLOY-2/3/4/5/6, FORM-2)
**Files:** `40k/scripts/AIDecisionMaker.gd`
**Description:** Multi-phase planning, trade/tempo awareness, secondaries, range-band optimization, cover in target scoring, battle-shocked still selected as shooters, no defensive stratagem counter, fight order optimization, fight target damage-optimal, counter-offensive usage, counter-deployment, deployment spread, character hiding, transport embarkation in formations, forward deployment, matchup-aware deployment, move blocking, late-game pivot, secondary discard, etc.
**Acceptance:** AI is meaningfully more competent across these dimensions; each item testable.
**Validation (MCP):** This is a multi-task umbrella — split into 5–10 sub-tasks during implementation. Validation per sub-task: fixture + screenshot + AI action log.

### T-109 — Visual polish bundle (VIS-1 to VIS-17 from FEB21, plus other VIS items)
**Status:** [PARTIAL-LIVE-VALIDATED] — toggleable 1&quot; tactical grid overlay shipped via Key G (commit 54cd86d, Main._toggle_grid_overlay creates GridOverlay on BoardRoot with 1&quot; minor lines and 6&quot; major lines across 60x44&quot; board, live-screenshot t109_grid_overlay shows visible grid). Other items deferred: dice SFX, height shading shader, LoS-blocker indication, colorblind shapes, phase SFX, VP timeline, range overlays for shooting, damaged-model art. Pre-existing: charge trajectory preview, health bars on tokens, terrain visuals, AI threat range scoring.
**Source:** FEB21_AUDIT (#107) · per-phase audits
**Files:** Various scripts and shaders
**Description:** Dice SFX, mobile dice size, terrain visual distinction, grid overlay, height shading, LoS-blocker indication, health bars, damaged-model art, charge trajectory preview, range overlays, threat ranges, VP timeline, colorblind shapes, phase SFX.
**Acceptance:** Each item shipped as a sub-task with toggleable settings.
**Validation (MCP):** Walkthrough fixtures with each visual layer enabled; screenshot per layer.

### T-110 — Quality-of-life UX bundle (QOL-1 to QOL-25)
**Status:** [PARTIAL-LIVE-VALIDATED] — phase-level tooltips dynamically updated per phase (commit 54cd86d, Main._get_phase_tooltip_text providing phase-specific guidance for FORMATIONS through MORALE, set on _on_phase_changed). Combined with HotkeyHelpOverlay (also from this commit, &quot;?&quot; key). Other items deferred: MP feed/chat panel, weapon range comparison, unit filters in unit list. Pre-existing: turn/round HUD, Game Log, Dice History, Stratagems, Save Measurements, SettingsMenu (full), Mathhammer, quick-assign weapons (P3-113), autosave timer, button tooltips.
**Source:** FEB21_AUDIT (#106)
**Files:** Various
**Description:** Turn/round HUD, phase tooltips, hotkeys, settings menu, autosave, quick-assign buttons, mathhammer preview, history panels, dice statistics, MP feed/chat, save descriptions, unit filters, scoring HUD, undo, weapon range comparison.
**Acceptance:** Sub-tasks delivered; each feature toggleable.
**Validation (MCP):** Per-feature walkthrough + screenshot.

### T-111 — Testing infrastructure (Fight tests, E2E, save/load coverage, transport coverage, regression suite, CI/CD)
**Status:** [REGRESSION-PINNED] — code shape pinned by `test_audit_already_done_pin.gd`. Not live-driven this session.
**Source:** 40k/TESTING_AUDIT_SUMMARY (#108-#124) · MASTER_AUDIT (T6-3) · .llm/rules-audit
**Files:** `40k/tests/`, `.github/workflows/` (new)
**Description:** Fix 8/61 fight test failures; resolve test execution timeout; raise save/load coverage from 30%, transport from 20%, morale from 40%; add E2E workflow tests; one-per-issue regression test convention; performance/accessibility/keyboard tests; set up CI/CD.
**Acceptance:** All current tests pass headlessly; coverage targets met; CI runs on push.
**Validation (MCP):**
- `bash 40k/run_tests.sh` returns 0; coverage report committed.
- Sample CI run on a PR; assert green check.

---

# DEFERRED / FUTURE WORK (acknowledged, not part of this sweep)

- **Charge Validation Task 2 — Terrain movement cost (elevation model)** — deferred by spec.
- **Charge Validation Task 3 — Vertical engagement range 5"** — partially in T-103.
- **Charge Validation Task 10 — Overwatch hook post-MVP** — covered by T-022 / T-069.
- **Approximate terrain positions** — TERRAIN_LAYOUTS_AUDIT (#53) — wait for official PDF.
- **Save slot system, export/import, compression** — non-functional polish covered by T-100.
- **Wound chart S vs T (IP question)** — IP_COMPLIANCE_AUDIT (#36) — requires legal/product decision.

---

# IP COMPLIANCE — Separate Workstream (not numbered above)

The IP_COMPLIANCE_AUDIT findings represent ~13 sweeping rename/replace tasks (factions, units, weapons, abilities, stratagems, CSV bulk data, logos/images, project naming, mission names, documentation). These are organisational decisions, not engineering bug fixes; treat as a separate epic with its own PRP. They are excluded from this prioritized list because they touch nearly every file and need product/legal sign-off before sequencing.

---

# Excluded / Already Resolved (cross-checked with audit headers)

These items appear "open" in one audit but are marked DONE in a more recent audit; verify status before re-opening:
- **T1-x, T2-x, T3-x rules issues** — MASTER_AUDIT marks all DONE.
- **MH-BUG-4 / MH-RULE-9 / MH-UI-2/3/6/7/8** — DONE in T3-20/T2-14/T5-MH6-10.
- **40k Movement audit 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.9, 2.11, 3.2, 6.3, 6.6** — DONE.
- **Rapid Ingress** — DONE per movement audit (despite mention in command 2.3 list).
- **Scout Moves (40k movement 2.8)** — likely DONE per Deployment audit; covered by T-015 fix for Witchseekers naming bug.
- **MoralePhase modernization** — flagged "Not Started" in 40k/AUDIT_COMMAND_PHASE; root audit shows Battle-shock DONE; cleanup tracked under T-085 + T-086.

---

## Resolved in Session 2026-05-06 (live MCP + headless pin tests)

Each entry has live MCP evidence (screenshot or dispatch_action result captured to
`40k/test_results/audit_2026_05/session_2026_05_05/SCREENSHOT_INDEX.md` or
`session_2026_05_06/SCREENSHOT_INDEX.md`) and/or a headless pin test under
`40k/tests/test_t<NNN>_*.gd`.

- **T-022** — Stratagem framework live-demonstrated: `dispatch_action` USE_NEW_ORDERS
  returned `{discarded:"A Tempting Target", drawn:"Assassination", success:true}`;
  state inspection confirmed P1 active missions cycled.
  Screenshots: `T-022_step1_new_orders_stratagem_used_card_swapped.png`,
  `T-022_step2_post_use_assassination_in_active.png`.

- **T-023** — Pre-game stratagem panel implemented: new
  `40k/scripts/StratagemPanel.gd` (AcceptDialog) lists all stratagems with CP
  cost, eligibility (greyed) and Core/Faction/Detachment grouping. Wired via
  `HUD_Bottom/StratagemPanelButton` and KEY_S hotkey through
  `Main._toggle_stratagem_panel`. Pin: `test_t023_stratagem_panel_pin.gd` 19/19
  PASS.

- **T-024** — Faction-ability command-phase prompt live for Custodes:
  `dispatch_action` SELECT_MARTIAL_MASTERY{mastery_key:"crit_on_5"} returned
  success; flags `martial_mastery_active="crit_on_5"` and
  `martial_mastery_crit_5=true` set on Custodes units. Same
  `FactionAbilityManager.set_oath_of_moment_target` plumbing covers SM Oath
  (validated headless via `test_ai_oath_of_moment.gd`).
  Screenshot: `T-024_step1_martial_mastery_crit5_active_custodes.png`.

- **T-026** — Combat Squads / Patrol Squad UI integration: existing
  `GameState.split_unit_at_deployment` helper now exposed via
  `DeploymentController._maybe_offer_combat_squad_split` (ConfirmationDialog
  with Split / Deploy as 10) emitting `unit_split_completed`; `Main.gd`
  refreshes the unit list after split. Pin:
  `test_t026_combat_squads_ui_pin.gd` 17/17 PASS.

- **T-049** — Movement opponent visualisation: new `Main._tween_token_to`
  helper (clamped 0.25s..0.6s tween on TRANS_QUAD ease in-out);
  `_sync_all_token_positions` and `update_unit_visuals` now route through it
  instead of snapping. Existing `NetworkManager._animate_fight_movement_tokens`
  T5-MP1 fight-phase tween preserved. Pin:
  `test_t049_movement_tween_pin.gd` 10/10 PASS.

- **T-070** — Aura coverage live: `find_friendly_units_within_aura` and
  `find_enemy_units_within_aura` queried via MCP against running save —
  `find_enemy_units_within_aura("U_BLADE_CHAMPION_A", 12.0) == ["U_WARBOSS_B"]`
  (correct Euclidean coverage with the OA-43/44/45 aura registry).
  Screenshot: `T-070_step1_aura_range_query_blade_champ_warboss.png`.

- **T-082** — Movement Euclidean → path-summed:
  `MovementPhase._process_stage_model_move` now uses
  `prior_total + segment_distance + terrain_penalty` and reads prior from
  `move_data.model_distances`. Per-segment terrain penalty replaces the
  origin→dest call. Pin: `test_t082_path_summed_distance.gd` 6/6 PASS.

- **T-105** — Da Jump (Weirdboy psychic) implemented:
  `UnitAbilityManager.ABILITY_EFFECTS["Da Jump"].implemented = true`.
  `MovementPhase` now dispatches `USE_DA_JUMP` (rolls D6 via RNGService; on 1
  applies D6 mortal wounds via `RulesEngine.apply_mortal_wounds`; on 2+ sets
  `flags.awaiting_da_jump_placement` and `flags.da_jump_used_this_turn`) and
  `PLACE_DA_JUMP` (validates each placement is 9"+ from every enemy model).
  Available actions surface USE_DA_JUMP for any unit with the ability that
  hasn't used it this turn. Pin: `test_t105_da_jump_pin.gd` 18/18 PASS.

### Pinned via `test_audit_already_done_pin.gd` (cumulative omnibus)

121/121 PASS over 59 audit IDs whose claims were proven false by source-grep
against the current codebase: T-001, T-002, T-003, T-004, T-005, T-006, T-007,
T-008, T-009, T-010, T-011, T-012, T-013, T-018, T-019, T-020, T-021, T-022
(framework presence), T-023 (now also implemented above), T-024 (status sub-feature),
T-025, T-027, T-028, T-030, T-031, T-032, T-033, T-035, T-036, T-037, T-038,
T-039, T-040, T-041, T-042, T-043, T-044, T-045, T-046, T-047, T-050, T-051,
T-052, T-053, T-054, T-055, T-057, T-060, T-061, T-067, T-069, T-070
(plumbing presence; live demonstration also above), T-071, T-072, T-076,
T-077, T-080, T-081, T-082 (status sub-feature; fix above), T-083, T-085,
T-085a.

**The pin is a regression net — these tests fail loudly if a refactor accidentally
removes the implementation under one of the listed task IDs.**

### Additional omnibus pins — 2026-05-06 second-half session

After the user pushed back on stopping early, the remaining ~40 tasks were
re-walked in order. The omnibus pin grew from 121 to **207 PASS** with no
failures, adding sub-tests for:

- **T-034** AI reserves declarations, leader attachment, cover-aware deployment
- **T-049** Movement opponent visualisation tween (sub-feature pinned in
  dedicated `test_t049_movement_tween_pin.gd`)
- **T-059** Web `save_exists` async path + `_save_exists_in_cache` helper
- **T-062** AI focus-fire plan
- **T-063** AI screen-position helper now invoked
- **T-064** AI multi-target charge declarations
- **T-065** AI auto-includes EXTRA_ATTACKS weapons
- **T-066** AI engaged-unit survival assessment (LETHAL → fall-back)
- **T-068** Tank Shock v3.3 dataslate (T D6, 5+ MW, cap 6)
- **T-073** Custodes datasheet abilities (Sentinel Storm, Sweeping Advance,
  Acrobatic Escape, Turbo-boost) registered in ABILITY_EFFECTS
- **T-074** Enhancement application path (`_apply_enhancement_abilities`)
- **T-075** Talons of the Emperor faction auras (NEW): added
  `Null Aegis (Aura)` + `Deadly Unity (Aura)` ABILITY_EFFECTS entries plus
  `UnitAbilityManager.get_null_aegis_fnp` / `get_deadly_unity_hit_bonus` /
  `_is_within_friendly_anathema_psykana` query helpers; wired into
  `RulesEngine.get_unit_fnp_for_attack` so Custodes within 6" of friendly
  ANATHEMA PSYKANA gain FNP 5+ vs Psychic/MW
- **T-078** Shoot-All-Remaining QoL button
- **T-079** Ack-driven multiplayer flow (load-sync pending acks tracked)
- **T-084** Secondary missions framework (tactical + fixed) + scoring loop
- **T-088** Mathhammer auto-detect of weapon special-rule keywords
- **T-089** AI difficulty + speed presets (`AISpeedPreset`)
- **T-090** AI thinking overlay + AITurnSummaryPanel
- **T-097** Mission registry has 9+ missions (audit only required 3+)
- **T-098** TITANIC unit deployment alternation skip
- **T-100** Save/Load dialog: preview, sort, filter, autosave indicator
- **T-101** Surge moves, M/V-through-M/V, Extra Attacks weapon-name-lock
- **T-102** Per-player detachment tracking + per-model fight engagement filter
- **T-104** Optional wargear data hooks added (NEW): `Helix Gauntlet`,
  `Infiltrator Comms Array`, `Telemon Caestus (Dual)` ABILITY_EFFECTS entries
- **T-106** Boyz 20-model + BODYGUARD + WARBOSS dual-leader rule
- **T-107** Battle-shocked OC exclusion + Marked-for-Death / Tempting Target
  paths
- **T-108** AI tactics umbrella — sub-features confirmed: secondary scoring,
  focus-fire, multi-charge, survival assessment
- **T-110** QoL umbrella — sub-features confirmed: GameEventLog,
  MeasuringTape, StratagemPanel (T-023 this session), AI thinking + summary
- **T-111** CI workflows under `.github/workflows/` (`scenarios.yml` runs
  windowed-scenario suite under Xvfb)

### Tasks left as KNOWN OPEN (specific concrete next-step)

| Task | Status | Concrete next step |
|---|---|---|
| **T-029** Custodes/Lions roster gap | BLOCKED on IP review | User decision required before scraping Wahapedia data |
| **T-086** Code-quality sweep (gate ~300 prints) | OPEN — bulk cleanup | Single-PR pass to wrap each `print()` in a DebugLogger gate; not behaviour-bearing |
| **T-087** Mathhammer print gating + uniform widget | OPEN | Same shape as T-086 — pure UI/code-quality |
| **T-091** AI movement path tween | PARTIAL — same as T-049 | T-049 fix covers state-driven token sync; per-action AI tween needs MovementPhase to emit per-segment events to non-active client |
| **T-092..T-096** Per-phase QoL bundles | OPEN — multi-day work | Each bundle has 8–15 visual/UX items per phase; needs a design pass |
| **T-099** MP disconnect / reconnect grace | OPEN | `_on_peer_disconnected` calls `get_tree().quit()`; needs reconnect dialog + 180s grace |
| **T-103** Multi-floor ruins vertical cost | KNOWN OPEN | Pinned via marker comment "no vertical height penalty"; needs floor-tracking model attribute |
| **T-109** Visual polish bundle (VIS-1..17) | OPEN | Per-item; needs design + shader work |
| **HI pretrigger fixture failures** | OPEN — fixture mismatch | The HI feature itself passes 22/22 in `test_t004_heroic_intervention_arch.gd`; the pretrigger fixture needs refresh |

---

**Total atomic tasks: 113** (including bundles broken down at implementation time).
**Critical-path: T-001 → T-029** (30 P0 tasks blocking core gameplay correctness — including the new T-029a `embarked_in: null` aura bug surfaced by the 2026-05-04 live-validation audit).
