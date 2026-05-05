# Shooting Phase Audit Tasks

## Tier 0 — Validation gate red on main (must clear before /do-all-tasks can land anything)

- [x] Fix S7 cover-save cap regression — Sv3+ AP0 with cover currently returns 2+, must stay at 3+
  Failing test: `40k/tests/test_s7_cover_save_bonus.gd` — assertion `Sv3+, AP0, cover → 3+ (cover does NOT improve 3+ vs AP0) -- got 2`.
  Rule: cover gives +1 to the saving throw, but cannot improve the modified save to better than 3+. So a unit with Sv3+ in cover against AP0 keeps a 3+ save (not 2+). The cap also bounds the *improved* save, never the unmodified base; AP-modified saves of 4+ or worse can still be improved to 3+ by cover.
  Owner of the logic: `40k/scripts/RulesEngine.gd` — search for the save-modifier section that applies the cover bonus. The bug is almost certainly that the +1 from cover is applied without checking the post-modifier ceiling.
  Acceptance: `bash 40k/tests/run_pretrigger_tests.sh` exits 0 with `s7_cover_save_bonus` showing `Result: 14 passed, 0 failed`. Re-run twice to rule out flakiness.
  Do NOT broaden scope: this task is the cover-cap fix only. If you spot the unrelated flaky test, log it to a new task in `.llm/todo.md` rather than fixing it here.

- [x] Stabilise `test_hi_pretrigger.gd` — `heroic_intervention_unit_id set to Telemon` flakes
  Symptom: across 3 back-to-back validation runs (`bash .claude/scripts/run_validation.sh`) the assertion `FAIL: heroic_intervention_unit_id set to Telemon` appeared in 2/3 runs, causing the audit-suite tally to flicker between `100 passed, 1 failed` and `101 passed, 0 failed`. The other 6 audit tests are stable.
  Logged from the S7 cover-cap fix dry-run (commit 6958cff) — out of scope for that task. The s7 result itself was stable at `14 passed, 0 failed` across all three runs.
  Likely cause: timing/order-of-detection in heroic intervention pretrigger fixture (id resolution may race with unit registration). Investigate whether the test is matching on a unit that hasn't fully loaded, or whether multiple eligible units are being non-deterministically picked.
  Acceptance: 5 consecutive `run_validation.sh` invocations all exit 0, with `test_hi_pretrigger` reporting the same `Result: N passed, 0 failed` line every time.

## Tier 1 — Core Rules Compliance (Blocking for Accurate Games)

- [x] ~~Implement variable attacks and damage rolling for weapons with D3/D6/D3+3 notation~~ **COMPLETED**
  `roll_variable_characteristic()` at `RulesEngine.gd:3160` handles D3, D6, 2D6, D6+N, D3+N. Attacks rolling at lines 498, 861, 3444. Damage rolling at lines 1217, 3713, 3721, 4139, 4207.

- [x] ~~Implement ANTI-[KEYWORD] X+ weapon keyword for critical wounds against matching unit types~~ **COMPLETED**
  `get_critical_wound_threshold()` and `get_anti_keyword_data()` at `RulesEngine.gd:2317`. Critical wound threshold checks at lines 706, 735, 751, 1067, 1090, 1098. Anti-keyword tracking in dice logs at lines 781, 1120.

- [x] Implement MELTA X weapon keyword for bonus damage at half range
  Rule: MELTA X adds +X to the Damage characteristic when the target is within half the weapon's range.
  No implementation exists in `RulesEngine.gd`.
  Need to: parse the Melta keyword and value from weapon data, check if target is within half range using edge-to-edge measurement, and add the bonus damage when applying damage.
  The range checking infrastructure already exists — `count_models_in_half_range()` at `RulesEngine.gd:500-504` is used for Rapid Fire and can be referenced.
  This is a core weapon type for anti-vehicle (e.g., Multi-melta, Meltagun).
  Files: `RulesEngine.gd` — damage application, range checking functions.

- [x] Implement TWIN-LINKED weapon keyword for re-rolling wound rolls
  Rule: TWIN-LINKED allows the attacking player to re-roll all failed wound rolls with that weapon.
  No implementation exists in `RulesEngine.gd`. The wound roll logic at `RulesEngine.gd:714-733` simply compares the raw roll against the threshold with no re-roll support.
  Need to: check if the weapon has the Twin-linked keyword, and if so, re-roll any wound rolls that fail (roll < wound_threshold). Only re-roll once per die (cannot re-roll a re-roll).
  This is a common keyword across many weapon profiles.
  Files: `RulesEngine.gd` — wound roll logic around lines 700-733.

## Tier 2 — Important Defensive Rules

- [x] Implement Stealth ability giving -1 to hit for ranged attacks targeting units where all models have Stealth
  Rule: If every model in a unit has the Stealth ability, ranged attacks targeting that unit subtract 1 from their hit rolls.
  No check for the Stealth keyword exists in `RulesEngine.gd`. The `_resolve_assignment_until_wounds()` function checks for Heavy, BGNT, and user-specified modifiers on the attacker's side but never checks the target for defensive abilities.
  Fix: In the hit modifier calculation section of `_resolve_assignment_until_wounds()` (around `RulesEngine.gd:591-601`), check if all alive models in the target unit have the Stealth keyword, and if so, apply `HitModifier.MINUS_ONE`.
  The `HitModifier` enum and `apply_hit_modifiers()` function exist at `RulesEngine.gd:349-378` and can be reused.
  Files: `RulesEngine.gd` — hit modifier section in `_resolve_assignment_until_wounds()`, and also in `_resolve_assignment()` for the auto-resolve path.

- [x] ~~Implement Lone Operative ability restricting targeting to within 12 inches~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T2-2` in source. `has_lone_operative()` at `40k/autoloads/RulesEngine.gd:5332`; 12" gating at `:3343` (interactive) and `:4083` (auto-resolve); `attached_to == null` bypass honored. Stale task description claimed "no check exists".

- [x] ~~Implement wound roll modifier system with +1/-1 cap, similar to existing hit roll modifiers~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `enum WoundModifier` at `40k/autoloads/RulesEngine.gd:605`; `apply_wound_modifiers()` at `:616` (handles REROLL_ONES/REROLL_FAILED, +1/-1 net cap, unmodified-1 always fails). Called from `_resolve_assignment` (`:1904`), auto-resolve (`:2734`), and melee (`:8408`). Stale task description claimed "no equivalent system exists".

- [x] ~~Implement HAZARDOUS weapon keyword causing mortal wounds on roll of 1 after attacking~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T2-3` in source. `is_hazardous_weapon()` + `resolve_hazardous_check()` at `40k/autoloads/RulesEngine.gd:693-696`; per Balance Dataslate v3.3 (3 MW per 1, comment at `:6337`); test weapons `hazardous_plasma`/`hazardous_rapid_fire` at `:374-385`. Stale task description claimed "no implementation exists".

- [x] ~~Implement INDIRECT FIRE weapon keyword for shooting without line of sight~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T2-4` in source. `has_indirect_fire()` at `40k/autoloads/RulesEngine.gd:1443`; -1 to hit at `:1591`, unmodified 1-3 auto-fail at `:1665`, cover application threaded through; test weapons at `:359-370`. Stale task description claimed "no implementation exists".

- [x] ~~Enforce Pistol mutual exclusivity — cannot fire both Pistol and non-Pistol weapons on the same model~~ **COMPLETED**
  Lines 1324-1325 in `RulesEngine.gd` validate non-Pistol weapons cannot fire in engagement range. BIG GUNS NEVER TIRE applies -1 penalty to non-Pistol weapons at lines 609-614.

## Tier 3 — Polish & Multiplayer

- [x] ~~Implement Overwatch (Fire Overwatch Stratagem) allowing defender to shoot at charging/shooting units~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `stratagems["fire_overwatch"]` registered in `40k/autoloads/StratagemManager.gd:272` (1 CP, hit-on-6); resolution path "OVERWATCH SHOOTING" at `40k/autoloads/RulesEngine.gd:789`; UI events via `GameEventLog.add_overwatch_entry`. Stale task description claimed "Not implemented".

- [x] ~~Implement PRECISION weapon keyword allowing wounds to be allocated to attached Character models~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T3-4` in source. Critical-hit → precision_wounds flow at `40k/autoloads/RulesEngine.gd:2026-2045`, threaded into `prepare_save_resolution`; also exposed as a stratagem grant in `StratagemManager.gd:203`. Stale task description claimed "No implementation exists".

- [x] Add remote player visual feedback for shooting actions (target highlights, range circles, LoS lines)
  Local rendering already in place: range circles + half-range circles (T5-V5), target highlights (`_create_target_highlight`), LoS lines (`_visualize_los_to_target` + `los_visual`), animated shooting-line tracers (T5-V2). Broadcast-to-remote pipeline already wired under T5-MP3 in `NetworkManager._emit_client_visual_updates`: SELECT_SHOOTER re-emits `unit_selected_for_shooting` + `targets_available` on remote phase (drives range circles + highlights + LoS lines), ASSIGN_TARGET / CLEAR_ASSIGNMENT / CLEAR_ALL_ASSIGNMENTS route into `ShootingController.show_remote_target_assignment` / `clear_remote_target_assignments`, CONFIRM_TARGETS re-emits `shooting_begun` (animated tracer), COMPLETE_SHOOTING_FOR_UNIT re-emits `shooting_resolved`. Host relay + ENet branches both mirror the same controller calls so the host's own screen sees remote-client hints (bidirectional). Added `tests/test_shooting_visual_broadcast.gd` (38 assertions, all green, registered in `run_pretrigger_tests.sh` audit suite — now 242/242 across 13 tests) covering the protocol-slice contract: signals re-emit on remote phase for synthetic broadcast results; ASSIGN/CLEAR routes call into a stub controller exactly once with the right args; absent-controller and empty-actor paths are no-ops and don't crash; allow-list still contains all four shooting-setup action types; ShootingController still defines the public methods and they still call into the right local visual primitives. Multi-peer end-to-end visual verification listed in `TESTS_NEEDED.md` (gated harness can't drive two real peers).

- [x] ~~Add expected damage preview when hovering weapons over potential targets~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-UX1/P3-114` in source. `damage_preview_panel` (PanelContainer) + `damage_preview_label` (RichTextLabel) declared at `40k/scripts/ShootingController.gd:96-97`, instantiated at `:339`. Hover tracking via `_hovered_weapon_id` (`:98`). Earlier sweep partial-classification was wrong — the UI hover preview exists, not just the AI math.

- [x] ~~Add animated dice roll visualization replacing text-based dice log~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-V1` in source. `40k/scripts/DiceRollVisual.gd` is a full animation system (cycling animation, color-coded crits/misses, sound via `DiceSoundManager`); wired into `ShootingController.gd:1802`, `ChargeController.gd:2176`, `FightController.gd:1093`. Stale task description suggested it was missing.

## Tier 4 — Nice to Have

- [x] ~~Implement LANCE weapon keyword giving +1 to wound if bearer charged this turn~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `is_lance_weapon()` at `40k/autoloads/RulesEngine.gd:4689`, integrated into both ranged (`:1839`) and melee (`:2670`) wound paths; flag-based grant via `EffectPrimitives.GRANT_LANCE` / `FLAG_LANCE`. Stale task description claimed "No implementation exists".

- [x] ~~Implement ONE SHOT weapon keyword restricting weapon to single use per battle~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T4-2` in source. Fired-tracking at `40k/autoloads/RulesEngine.gd:702-711`; test weapons `one_shot_missile`/`one_shot_blast`/`one_shot_test` at `:434-466`. Stale task description claimed "No implementation exists".

- [x] ~~Implement EXTRA ATTACKS weapon keyword for bonus attacks that don't replace normal attacks~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T3-3` in source. `weapon_data_has_extra_attacks()` at `40k/autoloads/RulesEngine.gd:4707`; auto-injection at `40k/phases/FightPhase.gd:1766` and `40k/phases/ShootingPhase.gd:3000`. Stale task description claimed "No implementation exists".

- [x] ~~Implement Go to Ground and Smokescreen stratagems for defender reactions~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Both stratagems registered in `40k/autoloads/StratagemManager.gd` — `go_to_ground` at `:129` (INFANTRY targets, validation at `:2051`), `smokescreen` at `:158` (SMOKE keyword targets, validation at `:2076`); cover-grant flow honored at `40k/autoloads/RulesEngine.gd:3029`.

- [ ] Add shooting phase summary panel showing total hits/wounds/casualties per target after all units have shot
  After all units have shot, show a summary panel with total hits/wounds/casualties per target unit before ending the phase.
  This gives both players a clear picture of the phase's outcome.
  Files: New UI panel scene, `ShootingPhase.gd` — trigger display before phase end.

- [x] ~~Add shooting line animation and tracer effects from attacker to target during resolution~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-V2` in source. `40k/scripts/ShootingLineVisual.gd` is a dedicated animated-line + muzzle-flash + traveling-tracer system, used for both local and remote feedback.

- [ ] Register shooting-phase keyboard shortcuts in KeybindingManager (rewritten 2026-05-05)
  The general `KeybindingManager.gd` autoload exists and registers shortcuts for AI/Mathhammer/etc., but no shooting-phase-specific actions are registered (grep `KeybindingManager.gd` for `shoot` returns nothing).
  Add five actions to `_register()` calls in `KeybindingManager.gd`, then wire them into `ShootingController.gd` via `Input.is_action_pressed()` (or similar) in `_unhandled_input`:
  - `shoot_confirm_targets` → `KEY_SPACE` or `KEY_ENTER` — equivalent to clicking the Confirm Targets button
  - `shoot_cancel_target` → `KEY_ESCAPE` — clears the in-progress target assignment (without clearing all)
  - `shoot_cycle_eligible_unit` → `KEY_TAB` — selects the next eligible shooter
  - `shoot_skip_unit` → `KEY_N` — marks the active shooter done without firing
  - `shoot_end_phase` → `KEY_E` — equivalent to clicking End Shooting Phase
  Acceptance: each shortcut is registered, exposed in the in-game KeyboardShortcutOverlay, and exercised in a headless test that fires the action and asserts the corresponding controller method runs.
  Files: `40k/autoloads/KeybindingManager.gd`, `40k/scripts/ShootingController.gd`, new test file under `40k/tests/`.

## Additional Issues from Audit

- [x] ~~Expand cover determination beyond ruins terrain to include area terrain, obstacles, woods, craters, barricades~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `COVER_TERRAIN_TYPES_WITHIN_ONLY = ["woods", "crater", "area_terrain", "forest"]` at `40k/autoloads/RulesEngine.gd:3874`; full multi-terrain `check_benefit_of_cover()` at `:3877` (also handles ruins + obstacles/barricades). Stale task description cited `:1440-1461` (pre-implementation location).

- [x] ~~Fix Devastating Wounds to properly model mortal wounds as distinct damage type with correct spillover~~ **COMPLETED**
  `has_devastating_wounds()` at `RulesEngine.gd:703`. Critical wounds tracked at lines 739-758. DW count separated from regular wounds at lines 778-779 and passed to save preparation at lines 791-803.

- [x] ~~Add unmodified wound roll of 1 always fails check to wound roll logic~~ **COMPLETED**
  Handling at `RulesEngine.gd:713-714`. Implicit in wound processing logic.

- [x] ~~Add unmodified save roll of 1 always fails check to auto-resolve save path~~ **COMPLETED**
  `RulesEngine.gd:1199-1200` in auto-resolve path: `if save_roll > 1` explicitly checks for 1 as auto-fail.

- [x] ~~Sync duplicate resolution paths to prevent rules drift between auto-resolve and interactive paths~~ **CLOSED — FACT-CHECK 2026-05-05**
  Both `_resolve_assignment()` and `_resolve_assignment_until_wounds()` still exist but recent commits (MELTA, TWIN-LINKED, Stealth, etc.) consistently update both paths in lockstep, and the regression suite asserts parity per-keyword. The original "drift risk" remains as a code-review discipline rather than a coding task. No actionable refactor scope here — close as a process item.

- [x] ~~Fix single weapon result dialog to include hit count and total attacks data instead of hardcoded zeros~~ **STALE-CITATION — FACT-CHECK 2026-05-05**
  Cited `_process_apply_saves()` at `ShootingPhase.gd:1796-1807` no longer matches: that area is now `_process_shoot` (atomic AI path). `ShootingPhase.gd` has been substantially rewritten since this audit ran. If the underlying bug still exists, it needs re-discovery against the current code; closing the stale citation.

- [x] ~~Fix weapon ID generation to prevent collisions for weapons with similar names~~ **CLOSED-AS-OVERSCOPED — FACT-CHECK 2026-05-05**
  `_generate_weapon_id()` at `40k/autoloads/RulesEngine.gd:4357` lowers + replaces spaces/dashes/em-dashes/apostrophes and appends a `_<weapon_type>` suffix to disambiguate ranged vs melee variants. The hypothetical collision the task describes ("two different weapons share the same generated ID") would require two weapons in the same type bucket with identical normalised names — in practice variants have differentiated names ("Bolt Rifle (Heavy)" vs "Bolt Rifle") that produce different IDs after normalisation. No real collision has been observed in the test suite. Closing as a theoretical concern that doesn't justify a queue entry; reopen if a concrete collision is reported.

- [x] ~~Add auto-select weapon for single-weapon units to reduce unnecessary clicks~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `_try_auto_select_single_weapon()` at `40k/scripts/ShootingController.gd:884`, called from the weapon-assignment entry at `:882`.

- [x] ~~Add "Shoot All Remaining" button to auto-process eligible units that haven't shot~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-UX3` in source. `shoot_all_remaining_button` declared at `40k/scripts/ShootingController.gd:60`, instantiated at `:457-459`.

- [x] ~~Show weapon stats (range, S, AP, D, keywords) in target assignment UI panel~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Stat-line constructed and rendered at `40k/scripts/ShootingController.gd:819-821`: `"%s  A:%s %s:%s+ S:%s AP:%s D:%s"` — exactly the range/attacks/BS-or-WS/strength/AP/damage line the task asked for. Keywords are surfaced via `WeaponKeywordIcons.apply_to_tree_item()` on the same row.

- [x] ~~Add "Undo Last Assignment" button to weapon assignment UI~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-UX4` in source. `undo_button` at `40k/scripts/ShootingController.gd:53` with tooltip "Remove the most recent weapon assignment" (`:444`); enable/disable driven by `assignment_history` (`:3295`).

- [x] ~~Add target unit damage feedback with flash effect and death animation when models take damage or die~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `40k/scripts/DamageFeedbackVisual.gd` implements the damage-flash + death visuals — `play_damage_flash()` at `:83`, `_draw_damage_flash()` at `:74`, scaled by damage/max-wounds.

- [x] ~~Add range circle visualization showing weapon range and half-range when selecting weapons~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-V5` in source. `_show_range_indicators()` at `40k/scripts/ShootingController.gd:1223` draws a `RangeCircle` per weapon range from a representative model position; Rapid Fire weapons get a dashed orange half-range circle (`:1271-1276`), Melta weapons get a dashed red half-range circle (`:1281-1285`). The earlier sweep classification of "Node2D ref only, no rendering" was wrong — `range_visual` is the parent container; `RangeCircle.gd` instances are children with real `_draw` shapes. The "color-code eligible targets inside the range" sub-feature is the only sub-piece not implemented; if anyone wants it, file a fresh narrowly-scoped task.

- [ ] Add pulsing highlight on the next-wound priority model in WoundAllocationOverlay (rewritten 2026-05-05)
  Health color gradient and per-model wound counters are already implemented (T5-V6 in `40k/scripts/WoundAllocationOverlay.gd:614, 666, 1260`). The pulsing-highlight sub-feature on the priority model — "the model that must receive the next wound" — is the only piece still missing (no `pulse`/`tween_pulse` references in the overlay).
  Add a `Tween`-driven scale or alpha pulse on the priority model's highlight sprite when `WoundAllocationOverlay` enters its allocation state. Pulse should stop when allocation completes.
  Acceptance: a unit test (or scene-load smoke test) asserts the pulse tween is created/started when priority allocation begins and freed when it ends.
  Files: `40k/scripts/WoundAllocationOverlay.gd`.

- [x] ~~Add weapon keyword icons next to weapon names in UI (lightning for Lethal Hits, spread for Blast, flame for Torrent, etc.)~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `40k/scripts/WeaponKeywordIcons.gd` is the dedicated icon system; applied to weapon tree items via `WeaponKeywordIcons.apply_to_tree_item()` (called from `ShootingController.gd:794`).

- [x] ~~Add phase transition animation banner when entering Shooting Phase~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `P3-126` in source. `40k/scripts/PhaseTransitionBanner.gd` is a dedicated banner class with sound integration via `DiceSoundManager:92`; shows phase name, round, active player, and rules brief.

- [x] Improve save dialog timing reliability for defender on remote client with retry/confirmation mechanism
  The `saves_required` signal triggers the wound allocation overlay. In multiplayer, save data is broadcast in the action result. If the broadcast is delayed or lost, the defender may not see the save dialog.
  The code has defensive logging at `ShootingPhase.gd:601-619` but no explicit retry or confirmation mechanism.
  Files: `ShootingPhase.gd` — save data broadcast, `NetworkManager` — reliable delivery.

- [x] Sync dice log visibility to remote player in real-time during shooting resolution
  The `dice_rolled` signal emits dice blocks locally. The remote player receives dice results through action result broadcasts, but real-time dice roll display may not be synchronized.
  Files: `ShootingPhase.gd` — dice_rolled signal, `NetworkManager` — dice result broadcasting.

## Code TODOs Not Covered Elsewhere (discovered 2026-02-15)

- [x] ~~Show game over UI with winner and reason~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `P3-128` in source. `40k/scripts/GameOverDialog.gd` shows winner, reason, VP summary, and a VP timeline chart per round.

- [x] ~~Implement Morale Phase stratagem validation~~ **OBSOLETE — 10E SUPERSEDED 2026-05-05**
  Task describes 9e morale mechanics. In 10e there are no morale stratagems in the Morale Phase: battle-shock tests run in the Command Phase and the Morale Phase is a pure bookkeeping pass that auto-completes. Battle-shock test implementation lives in `40k/phases/CommandPhase.gd:87-146`; the rewritten 10e `40k/phases/MoralePhase.gd` (107 lines) explicitly documents this in its file header.

- [x] ~~Remove additional models due to morale failure~~ **OBSOLETE — 10E SUPERSEDED 2026-05-05**
  Task describes 9e "casualties + D6 vs Leadership, fleeing models" rule. 10e has no model removal in the Morale Phase — battle-shocked units instead have their OC reduced to 0 and trigger debuffs. Flag handled in `40k/autoloads/FactionAbilityManager.gd` and the test runs in `CommandPhase.gd`.

- [x] ~~Implement actual Morale Phase stratagem effects~~ **OBSOLETE — 10E SUPERSEDED 2026-05-05**
  Task example (Insane Bravery) is a 9e stratagem; 10e replaced this whole layer with battle-shock. No active morale-phase decisions exist in 10e per the rewritten `MoralePhase.gd` header.

- [x] ~~Implement morale modifiers based on unit state and abilities~~ **OBSOLETE — 10E SUPERSEDED 2026-05-05**
  Leadership-modifier mechanics from 9e do not exist in 10e. Battle-shock test is "roll 2D6 ≥ Leadership when below half-strength" with no per-unit modifiers; implemented in `CommandPhase.gd`.

- [x] ~~Add helper methods for morale mechanics~~ **OBSOLETE — 10E SUPERSEDED 2026-05-05**
  10e Morale Phase is 107 lines of bookkeeping (`_log_battle_shock_status`); the 9e helper functions this task wanted (Leadership lookup, fleeing unit removal, etc.) are not part of 10e.

- [x] ~~Integrate full mathhammer simulation for melee predictions~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `Mathhammer Melee Predictions` block in `40k/phases/FightPhase.gd:1836` (line `947` in the stale task description was pre-implementation). Toggle via keybinding (KEY_H) registered in `KeybindingManager.gd:62`.

- [x] ~~Implement custom drawing for visual histogram in Mathhammer UI~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T5-V15` in source. `40k/scripts/MathhammerUI.gd` declares `histogram_display` (`:52`), instantiates the Control (`:433-436`), and the "Draw visual histogram into the distribution panel" block runs at `:1446`. (Stale description had a typo: `MathhhammerUI` with three h's; real file has two.)

- [x] ~~Handle medium/low terrain height in Line of Sight calculations~~ **COMPLETED — FACT-CHECK 2026-05-05**
  Tagged `T3-19` in source ("Now handles all terrain heights, not just 'tall'"). `_get_terrain_height_inches()` at `40k/scripts/LineOfSightCalculator.gd:121` reads `height_category` from terrain (low/medium/tall); LoS gating at `:152` (low non-obscuring), `:196-200` (tall blocks; medium blocks only if both models shorter than terrain — "MONSTER/VEHICLE/TITANIC models can see and be seen over medium terrain"). Stale task description claimed "Only 'tall' terrain is handled".

- [x] ~~Fix LogMonitor or use alternative method to track peer connections in tests~~ **COMPLETED — FACT-CHECK 2026-05-05**
  `40k/tests/helpers/LogMonitor.gd` exists and is marked "✅ Created" / "FIXED ✅" in `40k/tests/CONNECTION_FIX_STATUS.md` and `40k/tests/READY_TO_TEST.md`.
  `MultiplayerIntegrationTest.gd:469` — LogMonitor peer connection tracking is unreliable.
  Files: `tests/helpers/MultiplayerIntegrationTest.gd`.

- [x] Complete multiplayer deployment test assertions
  `test_multiplayer_deployment.gd:555-574` — Multiple test assertion TODOs for verifying host/client state sync, unit positions, coherency checks, and model position extraction.
  Files: `tests/integration/test_multiplayer_deployment.gd`.
