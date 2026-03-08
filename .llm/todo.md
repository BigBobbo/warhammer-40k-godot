# AI Audit Tasks

> Source: AI_AUDIT.md — 82 items across P0-P3 priorities

## P1 — High (AI plays very poorly without these)

- [x] Implement screening/deep strike denial — position cheap units to deny enemy deep strike zones (AI-TACTIC-3, MOV-4)
- [ ] Implement reserves deployment — bring reserve units onto the board from Round 2+ (MOV-8)
- [ ] Implement leader attachment in formations — evaluate and attach leaders to bodyguard units (FORM-1)
- [ ] Add terrain-aware deployment — place units behind LoS-blocking terrain for cover (DEPLOY-1)
- [ ] Add AI turn summary panel — consume existing AIPlayer signals to show what happened (QoL-1)
- [ ] Add AI thinking indicator — show visual feedback during AI processing (QoL-2)
- [ ] Add AI movement path visualization — draw movement trails during AI unit movement (VIS-1)

## P2 — Medium (AI competence and feel improvements)

- [ ] Implement target priority framework — macro-level threat ranking + micro-level weapon allocation (AI-TACTIC-1)
- [ ] Implement multi-phase planning — movement considers shooting lanes, shooting considers upcoming charges (AI-TACTIC-6)
- [ ] Implement trade/tempo awareness — track points values, adjust aggression based on VP score (AI-TACTIC-7)
- [ ] Implement secondary mission awareness — factor secondary conditions into positioning and targeting (AI-TACTIC-8)
- [ ] Implement Heavy weapon stationary bonus — prefer remaining stationary when Heavy bonus is significant (MOV-3)
- [ ] Implement engaged unit survival assessment — estimate fight-phase damage before hold/fall-back decision (MOV-9)
- [ ] Implement multi-weapon melee optimization — use Extra Attacks weapons, pick best weapon per target (AI-GAP-7, FIGHT-3)
- [ ] Implement fight target optimization — score melee targets by expected damage, not just distance (FIGHT-4)
- [ ] Add range-band optimization — prefer Rapid Fire half-range, Melta half-range positioning (SHOOT-6)
- [ ] Add cover consideration in target scoring — penalize targets with Benefit of Cover (SHOOT-7)
- [ ] Implement Counter-Operative stratagem — use 2CP when AI's high-value melee unit is at risk (FIGHT-5)
- [ ] Implement transport usage — embark in formations, disembark during movement (FORM-2, MOV-7)
- [ ] Implement reserves declarations — put appropriate units in strategic reserves or deep strike (FORM-3)
- [ ] Add Rapid Ingress stratagem — arrive from reserves at end of opponent's movement (AI-GAP-3 Phase 3)
- [ ] Add AI speed controls — configurable action delay (QoL-3)
- [ ] Add AI decision explanations — enhanced _ai_description with reasoning (QoL-4)
- [ ] Add AI shooting target lines — visual targeting feedback (VIS-2)
- [ ] Add objective control flash on change — highlight when AI flips objectives (VIS-4)

## P3 — Low (Polish and competitive-level play)

- [ ] Implement AI difficulty levels — Easy/Normal/Hard with different heuristic depths (QoL-5)
- [ ] Implement army-specific strategies — melee/shooting/balanced/elite archetypes (QoL-6)
- [ ] Implement move blocking — position units to block enemy movement corridors (AI-TACTIC-9)
- [ ] Implement late-game strategy pivot — shift priorities based on turn and VP score (AI-TACTIC-10)
- [ ] Implement counter-deployment — react to opponent's deployment choices (DEPLOY-2)
- [ ] Implement faction ability activation — Oath of Moment target, Waaagh! declaration (CMD-3)
- [ ] Implement fight order optimization — choose which unit fights first for best outcomes (FIGHT-6)
- [ ] Implement secondary mission discard logic — discard unachievable secondaries for CP (SCORE-2)
- [ ] Add Pistol usage in engagement range — fire Pistols when in melee (SHOOT-9)
- [ ] Add counter-play to opponent stratagems — penalize targets with defensive buffs (SHOOT-10)
- [ ] Implement charge multi-target declarations — declare charges against multiple nearby enemies (CHARGE-4)
- [ ] Implement overwatch risk assessment — weigh charge benefit vs. overwatch damage (CHARGE-5)
- [ ] Add AI unit highlighting during actions — glow effect on active unit (VIS-5)
- [ ] Add floating damage numbers — combat text for damage and kills (VIS-6)
- [ ] Add AI action log overlay — scrolling real-time action feed (VIS-7)
- [ ] Add AI vs AI spectator improvements — auto-slow and dual summaries (QoL-7)
- [ ] Add AI turn replay — review previous AI turn actions (QoL-8)
- [ ] Add post-game AI performance summary — VP, kills, objectives, CP spent (QoL-9)
- [ ] Implement charge arrow visualization — show charge declarations visually (VIS-3)

---

# Deployment Phase Audit Tasks

> Source: DEPLOYMENT_AUDIT.md — open items from deployment phase audit

## Rules Gaps

- [ ] Fix reserves point cap from 25% to 50% — Chapter Approved 2025-26 rules specify max 50% of points AND 50% of units in reserves, but `DeploymentPhase._validate_place_in_reserves()` at line 276 uses `int(total_points * 0.25)`. Update to `0.50` and add unit count check (DEPLOY-RULES-1)
- [ ] Add mission selection variety — Currently only "Take and Hold" with static objectives. Add additional mission types from Chapter Approved 2025-26 with different primary objectives and deployment configurations (DEPLOY-RULES-4)

## Quality of Life

- [ ] Add per-model undo during deployment — Current undo resets entire unit. Add Ctrl+Z to undo only the last placed model by decrementing `model_idx` and clearing last `temp_positions` entry. Keep full reset as separate button (DEPLOY-QOL-1)
- [ ] Add coherency distance display during placement — Show real-time distance from ghost model to nearest placed model as a floating label (e.g., "1.8\"" green / "2.3\"" red) near the cursor during deployment (DEPLOY-QOL-2)
- [ ] Add measuring tool button during deployment — Ensure measuring tape is accessible during deployment with a visible button or tooltip showing keybind (DEPLOY-QOL-3)
- [ ] Add opponent deployment notifications in multiplayer — When opponent deploys a unit: pan camera briefly to show placement, show toast "[Unit Name] deployed", add deployment log panel showing order of all deployments (DEPLOY-QOL-4)
- [ ] Add keyboard shortcut reference overlay during deployment — Show toggleable controls panel (press ? to show/hide) listing Q/E rotation, Shift+click reposition, mouse wheel rotation, formation modes (DEPLOY-QOL-5)

## Visual Improvements

- [ ] Add unit placement drop-in animation — Brief scale 0→1 or fade-in over 0.2s when model is placed in `_spawn_preview_token()` for tactile feedback (DEPLOY-VIS-1)
- [ ] Add player turn screen-edge color indicator — Prominent colored border around screen edge matching active player color (blue/red), flash briefly on turn swap, optional audio cue (DEPLOY-VIS-2)
- [ ] Enhance ghost visual with coherency aids — Add pulsing effect to ghost, connecting line from ghost to nearest placed model, distance display to nearest friendly model (DEPLOY-VIS-4)
- [ ] Add coherency visualization circles — Draw faint 2" radius circles around placed models, green when next model in range, red when out of range (DEPLOY-VIS-5)
- [ ] Add unit name labels on deployed tokens — Show unit name on hover over deployed token or as tiny label beneath token cluster to distinguish same-type units (DEPLOY-VIS-6)
- [ ] Add opponent deployment zone dimming — Dim/desaturate opponent zone when it's your turn, brighten your own zone. Reverse on opponent's turn (DEPLOY-VIS-7)

## Multiplayer Issues

- [ ] Implement graceful disconnect handling during deployment — Replace `get_tree().quit()` on disconnect with reconnection dialog, grace period, option to save state or continue single-player (DEPLOY-MP-1)
- [ ] Add web relay "Waiting for game state" loading screen — Guest side loading screen that dismisses once host state is received, preventing flash of default army configuration (DEPLOY-MP-2)
- [ ] Batch deploy+embark/attach into composite action — Fix race condition where embark/attach actions arrive after player switch in multiplayer. Bundle deploy + embark/attach into single atomic action (DEPLOY-MP-4)

## Code Quality

- [ ] Fix snapshot staleness in `_all_units_deployed()` — Refresh phase snapshot in `_process_deploy_unit()` after applying changes so `_all_units_deployed()` can use snapshot instead of direct GameState access (DEPLOY-CODE-2)

---

# Holistic Game Audit Tasks

> Source: FEB21_AUDIT.md (updated 2026-02-27) — Rules compliance, QoL, visual improvements
> Cross-referenced against: Wahapedia 10e Core Rules, Balance Dataslate v3.3, Core Rules Updates & Errata, MASTER_AUDIT.md

## P0 — Critical (Game-breaking rules violations)

- [ ] Implement CHARACTER targeting "closest eligible visible unit" restriction — Characters with W<=9 near friendly non-Character units (3+ models or VEHICLE/MONSTER) cannot be targeted by ranged attacks unless they are the closest eligible visible target to the attacker. Add closest-eligible check to `_validate_assign_target()` in ShootingPhase.gd and `get_eligible_targets()` in RulesEngine.gd. Must compute distance from each attacking model to all eligible targets and only allow CHARACTER targeting when it is the nearest. (SHOOT-1)
- [ ] Implement defender-controlled wound allocation — Per 10e rules, the DEFENDING player chooses which model receives each wound (with the restriction that a model that has already lost wounds or had attacks allocated to it this phase must be allocated first). Currently wounds are auto-allocated without defender input. Add a wound allocation prompt for the defending player in ShootingPhase.gd and FightPhase.gd, with the auto-allocation as fallback for AI. In multiplayer, the defender must be presented the allocation choice. (SHOOT-9)

## P1 — High (Incorrect rules that significantly affect gameplay)

- [ ] Implement Out-of-Phase rules restriction — When using out-of-phase rules (e.g., Fire Overwatch during opponent's movement), you cannot use any other rules normally triggered in that phase. Add an `out_of_phase` flag to track when actions are performed reactively and gate phase-specific abilities/stratagems. Critical for preventing e.g. Pinning Bombardment during Overwatch. (GEN-1)
- [ ] Implement transport destruction effects — When a transport with embarked units is destroyed: roll D6 per embarked model (1 = 1 MW set up within 3", 1-3 = 1 MW set up within 6", 4+ = safe). Models that can't be placed are destroyed. Surviving models count as having disembarked. Add `resolve_transport_destruction()` to RulesEngine.gd, triggered from damage application when a transport unit is destroyed. (GEN-8)
- [ ] Implement pivot values for non-round base models — Core Rules Updates: non-round base non-Monster/Vehicle = 1" subtracted from movement on first pivot, Monster/Vehicle non-round base = 2", Vehicle round base >32mm with flying stem = 2". Add pivot tracking to MovementPhase.gd and deduct from remaining movement distance. (MOV-1)
- [ ] Implement vertical coherency limit (5") — `_check_models_coherency()` in MovementPhase.gd only checks 2" horizontal distance. Rules require models be within 2" horizontal AND 5" vertical of coherency partners. Add vertical distance check to coherency validation. (MOV-2)
- [ ] Fix attached unit starting strength for battle-shock — `is_below_half_strength()` in GameState.gd does not combine bodyguard + attached character models for starting strength. A Warboss (1 model) attached to 10 Boyz should have starting strength 11. Update to use `get_combined_models()` count when checking attached units in CommandPhase.gd. (CMD-6)
- [ ] Implement Ruins visibility rules — Core Rules Updates: "Models cannot see over or through Ruins terrain." Aircraft and Towering models are exceptions. Models can see into Ruins normally. Models wholly within Ruins can see out normally. Add ruins-specific LoS blocking to LineOfSightManager.gd / EnhancedLineOfSight.gd. (TER-2)
- [ ] Fix leader attachment not working visually for human player — User reports selecting leaders in Formations phase but they still deploy separately. AI attachment works. Investigate FormationsPhase → DeploymentPhase integration for human players — ensure attachment state persists and deployment skips attached characters. (BUG-1)
- [ ] Fix wound allocation overlay showing models in wrong positions — "The Kommandos are not in the place where they are expected to be when I allocate wounds." Investigate WoundAllocationOverlay model position rendering — model tokens may not match actual board positions. (BUG-2)
- [ ] Investigate and fix Line of Sight issues — User reports "Line of sight is not working as expected." May relate to TER-2 (ruins) or bugs in EnhancedLineOfSight.gd. Test LoS across various terrain configurations and fix discrepancies. (BUG-3)

## P2 — Medium (Rules gaps that occasionally affect gameplay)

- [ ] Implement CP cap — Core rules + FAQ: players can gain at most 1 additional CP per battle round from non-automatic sources (beyond the 1 CP auto-generated). Add tracking of CP gained per battle round and cap enforcement in CommandPhase.gd and StratagemManager.gd. (CMD-1)
- [ ] Add FEARLESS/ATSKNF keyword immunity to battle-shock — Units with FEARLESS or And They Shall Know No Fear keywords should auto-pass battle-shock tests. Add keyword check in `_identify_units_needing_tests()` in CommandPhase.gd. (CMD-2)
- [ ] Implement surge move rules and restrictions — Core Rules Updates defines "surge" moves (out-of-phase moves triggered by abilities). Restrictions: once per phase, not while battle-shocked, not while in Engagement Range. Add surge move validation. (MOV-3)
- [ ] Enforce one Normal move per phase limit — "A unit cannot make more than one Normal move per phase." Add per-phase normal move tracking in MovementPhase.gd. (MOV-4)
- [ ] Validate Monster/Vehicle cannot move through friendly Monster/Vehicle — Errata: Monsters and Vehicles cannot move through other friendly Monsters/Vehicles. Add keyword-based movement blocking check. (MOV-5)
- [ ] Update Hazardous to Balance Dataslate v3.3 allocation priority — Allocation priority: (1) wounded model with Hazardous weapon, (2) non-Character with Hazardous, (3) Character with Hazardous. Unit suffers 3 mortal wounds allocated to selected model. Verify and update `resolve_hazardous_check()` in RulesEngine.gd. (SHOOT-2)
- [ ] Verify Tank Shock matches Balance Dataslate v3.3 — v3.3: Roll D6 equal to TOUGHNESS of selected Vehicle model, 5+ = MW (max 6 MW). Check StratagemManager.gd Tank Shock implementation against updated wording. (CHG-1)
- [ ] Add terrain penalties to Heroic Intervention charge roll — `_is_heroic_intervention_roll_sufficient()` does not apply terrain vertical distance penalties unlike normal charge sufficiency check. Add terrain penalty calculation. (CHG-2)
- [ ] Verify consolidation is mandatory at unit level per FAQ — "Consolidation for a unit is not optional. However, for each model, whether or not that model makes a Consolidation move is optional." Ensure FightPhase.gd forces the consolidation step even if individual models don't move. (FGT-1)
- [ ] Implement Obscuring terrain keyword — No special rules for terrain features with the Obscuring keyword. Add terrain trait and LoS interaction. (TER-4)
- [ ] Implement Deep Strike can choose Strategic Reserves placement — Balance Dataslate: "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose to set up using Strategic Reserves OR Deep Strike rules." Add option in reinforcement placement UI. (DEP-3)
- [ ] Update Scouts rules per Balance Dataslate — Dedicated Transports can use Scouts ability from embarked unit. Scout distance can exceed Move characteristic as long as ≤ X". Update ScoutPhase.gd. (DEP-4)
- [ ] Complete Scorched Earth mission — Burn mechanics are stub only. Implement the objective burning action and scoring. (MIS-1)
- [ ] Complete The Ritual mission — Action-based objective mechanics not implemented. Add action system for ritual objectives. (MIS-2)
- [ ] Add Fixed secondary mission mode — Only tactical deck mode available. Add option for players to select 3 fixed secondary missions before the game. (MIS-4)
- [ ] Apply Balance Dataslate v3.3 stratagem modifications — Multiple stratagem changes: closer setup range (3"→6"), AP worsening timing, CP cost modifications, targeting prevention (12"→18"), unit addition once per battle restriction. Update StratagemManager.gd. (GEN-4)
- [ ] Update Rapid Ingress per Balance Dataslate — Updated: "if every model has Deep Strike ability, you can set up using Deep Strike (even though not your Movement phase)." Verify implementation in StratagemManager.gd. (GEN-5)
- [ ] Update Fire Overwatch timing per Balance Dataslate — Trigger expanded to: "just after an enemy unit is set up or when an enemy unit starts or ends a Normal, Advance or Fall Back move, or declares a charge." Verify timing in MovementPhase.gd and ChargePhase.gd. (GEN-6)
- [ ] Implement aura abilities system — No range-based aura effect application. `passive_aura` condition type exists in UnitAbilityManager.gd but is not functionally applied to other units within range. Build aura detection and effect propagation system. (GEN-7)
- [ ] Fix attached unit Toughness resolution — For wound rolls against an attached unit, Toughness should be the bodyguard unit's T value. RulesEngine.gd reads T from the target unit directly with no special handling for attached characters. May cause incorrect wound thresholds. (GEN-13)
- [ ] Fix weapon-by-weapon attack allocation for multi-weapon units — User reports "I should be able to allocate each user's attacks separately." Verify multi-weapon target assignment works correctly for units with different weapon profiles. (BUG-4)

## P3 — Low (Edge cases, polish, minor gaps)

- [ ] Prevent battle-shocked units from using self-targeted stratagems — StratagemManager.gd only prevents targeting battle-shocked units with friendly stratagems, not all stratagem usage by battle-shocked units. (CMD-3)
- [ ] Add confirmation before auto-resolving untaken battle-shock tests — Currently auto-resolves silently. Show warning dialog. (CMD-4)
- [ ] Fix embark/disembark distance calculation inconsistency — Embark uses `model_to_model_distance_inches()` but disembark uses shape-aware distance. Standardize. (MOV-6)
- [ ] Enforce "cannot select to shoot with no eligible targets" — "Unless at least one model in a unit has an eligible target, that unit cannot be selected to shoot." Add check to unit selection. (SHOOT-7)
- [ ] Display terrain penalty in charge distance UI — Players see rolled distance but not effective distance after terrain penalties. Show "Effective: X\" (Y\" - Z\" terrain)". (CHG-3)
- [ ] Add live direction validation feedback during charge movement — No real-time feedback as player drags model to show if final position satisfies direction constraint. (CHG-4)
- [ ] Verify Epic Challenge stratagem interaction in attached units — Ensure 1CP Epic Challenge properly enables CHARACTER vs CHARACTER melee dueling within attached units. (FGT-2)
- [ ] Sync pile-in/consolidation drag for remote player — Remote player sees models "teleport" to final positions; cosmetic only. (FGT-3)
- [ ] Complete when-drawn secondary mission interactions UI — Marked for Death and Tempting Target opponent selection not fully wired. (MIS-5)
- [ ] Verify objective control timing — "A player will control an objective marker at the end of any phase or turn." Ensure timing matches rules. (MIS-6)
- [ ] Validate Warlord designation — `is_warlord` field exists but no enforcement that exactly one CHARACTER is designated. (GEN-9)
- [ ] Add army construction points validation — Points tracked but no validation during list building. No detachment enforcement. (GEN-10)
- [ ] Verify persisting effects match Core Rules Updates — Core Rules Updates defines "persisting effects" with specific duration tracking. Verify effect expiration. (GEN-11)
- [ ] Make deployment zone toggle more prominent — User requested deployment zone visibility toggle. Ensure button is easy to find. (BUG-6)

## QoL — Quality of Life Improvements

- [ ] Add turn/round progress indicator to HUD — Show "Round 3/5 - Player 1 Turn" persistently. (QOL-1)
- [ ] Add phase rules brief during transitions — Brief popup/tooltip explaining available actions in each phase. (QOL-2)
- [ ] Add keyboard hotkeys for common actions — Tab to cycle units, number keys for quick-select, Enter to confirm, Esc to cancel. (QOL-3)
- [ ] Add settings menu — Audio controls, visual settings, UI scale, animation speed, colorblind mode. (QOL-4)
- [ ] Add auto-save at round end — Automatic saves at key points (round end, phase transitions). (QOL-5)
- [ ] Add quick-assign "All weapons to target" in shooting — Common case should be one click. (QOL-6)
- [ ] Add expected damage preview during weapon assignment — Mathhammer-style prediction as assignments are made. (QOL-7)
- [ ] Add quick-assign "All to Target" in melee — Same as QOL-6 for fight phase. (QOL-8)
- [ ] Add available movement indicator — Show "X inches remaining" floating text during model movement. (QOL-9)
- [ ] Add coherency preview during movement — Visual line showing unit coherency as models move. (QOL-10)
- [ ] Add terrain penalty display during charge — Show effective charge distance after terrain penalties. (QOL-11)
- [ ] Add dice roll history panel — Scrollable history of past dice rolls for review. (QOL-12)
- [ ] Add dice statistics summary after rolls — Show aggregate counts (e.g., "8 hits out of 10 rolls"). (QOL-13)
- [ ] Add reroll visualization — Show original + new die side-by-side for Command Re-roll. (QOL-14)
- [ ] Add live opponent action feed in multiplayer — Show "Player 2 moved Ork Boyz forward" in real-time. (QOL-15)
- [ ] Add chat/emote system for multiplayer — Quick predefined messages (Good Luck, Nice Move, etc.). (QOL-16)
- [ ] Add save file descriptions — User-editable notes on save files. (QOL-17)
- [ ] Add quick save/load hotkeys — F5 to quick-save, F9 to quick-load. (QOL-18)
- [ ] Add Mathhammer quick start presets — "Typical Infantry vs Light Armor" templates. (QOL-19)
- [ ] Add unit filter/sort in selection panel — Filter by status (wounded, fresh, moved) or type (infantry, vehicle). (QOL-20)
- [ ] Add double-click zoom to unit — Camera centers on selected unit on double-click. (QOL-21)
- [ ] Add scoring counter HUD — Display current VP by player persistently. (QOL-22)
- [ ] Add secondary objective progress tracking — Show progress toward active secondary missions. (QOL-23)
- [ ] Add undo last action — Allow undoing last model placement/move/assignment. (QOL-24)
- [ ] Add weapon range comparison view — Side-by-side range circles for all weapons on selected unit. (QOL-25)

## Visual — Visual Improvements

- [ ] Add dice roll sound effects — Rolling, settling, critical success/failure audio cues. (VIS-1)
- [ ] Add larger dice for mobile/touch — Current dice too small for touchscreen. (VIS-2)
- [ ] Add distinct terrain type visuals — Different visual styles for ruins, forests, hills, obstacles. (VIS-3)
- [ ] Add measurement grid overlay — Optional inch markers (every 6", every 12"). (VIS-4)
- [ ] Add height/elevation visualization — Elevated terrain with shading/3D effect. (VIS-5)
- [ ] Add LoS blocker terrain indication — Visual distinction for LoS-blocking terrain. (VIS-6)
- [ ] Add damaged model visual distinction — Wounded models look different from fresh. (VIS-8)
- [ ] Add human player movement path preview — Drag-to-plan movement path visualization (AI has this, humans don't). (VIS-9)
- [ ] Add movement cost terrain heatmap — Darker colors = slower movement areas. (VIS-10)
- [ ] Add multi-enemy engagement highlighting — Show all eligible enemies simultaneously. (VIS-11)
- [ ] Add colorblind-friendly engagement indicators — Shapes/patterns in addition to color. (VIS-12)
- [ ] Add phase transition sound effects — Audio cues for phase changes. (VIS-13)
- [ ] Add charge trajectory preview — Show expected path when declaring charges. (VIS-14)
- [ ] Add multi-weapon range display overlay — All weapon ranges overlaid together. (VIS-15)
- [ ] Add enemy threat range indicators — Show where enemy counter-attacks can reach. (VIS-16)
- [ ] Add VP scoring timeline chart — VP progression chart over game rounds. (VIS-17)

---

# Save/Load System Audit Tasks

> Source: SAVE_AUDIT.md (2026-03-03) — Save/load system audit covering desktop, AI, multiplayer, and cloud saves

## Critical (Must Fix)

- [ ] Fix AI re-initialization after load — When loading a saved AI game mid-session, `_initialize_ai_player()` is not re-invoked. Add `reconfigure_ai_after_load(game_config)` to the load completion path in Main.gd. Must cancel AI thinking, reconnect signals, and apply loaded difficulty/type config. (SAVE-1)
- [ ] Fix multiplayer load sync confirmation — `NetworkManager.sync_loaded_state()` broadcasts via RPC with no confirmation that clients received and applied the state. Add client acknowledgment mechanism, timeout handling, and error recovery. Host should not proceed until clients confirm. (SAVE-2)
- [ ] Implement save format versioning and migration — StateSerializer hardcodes version "1.0.0" with no migration system. Add version comparison logic and upgrade functions so old saves can be migrated to current schema when game data format changes. (SAVE-3)
- [ ] Fix `_refresh_after_load()` to fully restore game state — Main._refresh_after_load() doesn't clear old unit visuals before recreating, doesn't reinitialize phase controllers, doesn't refresh dependent systems (EffectChainManager, DiceHistoryPanel), and doesn't reinitialize AI. Add complete teardown and rebuild. (SAVE-4)
- [ ] Fix web platform `save_exists()` returning false — SaveLoadManager.save_exists() always returns false on web because cloud storage is async. Add async overwrite check before cloud save to prevent silent overwrites. (SAVE-5)

## High (Should Fix)

- [ ] Prevent autosave during AI turn — Autosave on phase transition can trigger while AI is mid-action, capturing incomplete state. Add AIPlayer.is_thinking() guard to autosave triggers. (SAVE-6)
- [ ] Save AI turn history in game snapshot — AIPlayer turn history is not included in create_snapshot(). After loading, AI has no memory of previous turns and makes inconsistent decisions. Add AI decision history to snapshot data. (SAVE-7)
- [ ] Hide Load button for non-host in multiplayer — Save/Load dialog is accessible to clients who get an error only after attempting to load. Disable/hide the Load button for non-host players in multiplayer sessions. (SAVE-8)
- [ ] Add load confirmation dialog for unsaved progress — Loading a save replaces current game state without warning about unsaved changes. Prompt "You have unsaved changes. Load anyway?" before proceeding. (SAVE-9)
- [ ] Add autosave visual indicator — When autosave triggers, show a brief floppy disk icon or notification so the player knows the game was saved automatically. (SAVE-10)
- [ ] Add multiplayer resume game flow — No dedicated UI for resuming a saved multiplayer game. Host loads save and starts hosting, client connects — but there's no guidance for this workflow. Add "Resume Multiplayer Game" option with instructions. (SAVE-15)

## Medium (QoL/Visual Improvements)

- [ ] Add save file preview/summary — Save list shows name/timestamp/turn/phase but not army compositions, VP scores, unit counts, or a minimap thumbnail. Add richer metadata display. (SAVE-11)
- [ ] Add "Game Loaded" transition overlay — After loading, game state snaps instantly with no transition. Add brief "Loading save..." overlay with fade for smoother UX. (SAVE-12)
- [ ] Add AI difficulty to save metadata — The `.meta` sidecar stores player types but not AI difficulty or speed settings. Show this in save file listing. (SAVE-13)
- [ ] Add save list sorting and filtering — Save files listed chronologically only. Add sort by name/date, filter by game type (AI vs multiplayer), and search. (SAVE-14)

## Low (Nice to Have)

- [ ] Add multiple quick save slots — Only a single quicksave slot exists. Add numbered save slots for multiple save points in a single game. (SAVE-16)
- [ ] Enable save file compression — GZIP compression support exists in StateSerializer but is disabled. Activate for large saves. (SAVE-17)
- [ ] Add unit data validation on load — StateSerializer validates structure but not data integrity (unique unit IDs, valid positions, consistent statuses, reasonable CP/VP). Add integrity checks. (SAVE-18)
- [ ] Add save file export/import — No way to share save files between players. Add portable format with embedded army data. (SAVE-19)
- [ ] Add save/load progress indicator for cloud saves — Cloud saves have no visual feedback during upload/download. Add progress bar or spinner. (SAVE-20)

---

# Charge Phase Audit Tasks

> Source: CHARGE_PHASE_AUDIT.md (2026-02-13, v2) — Rules compliance, multiplayer, QoL, visual improvements
> Items marked DONE/RESOLVED in the audit have been omitted.

## Rules Compliance — Missing/Incomplete

- [ ] Complete Overwatch integration into charge phase — StratagemManager defines `fire_overwatch` but full integration into the charge phase interrupt window (reaction timing between declaration and roll) needs implementation. NetworkManager cross-player action support during charge phase needed. (CHG-RULES-1)
- [ ] Implement Heroic Intervention — FightPhase.gd:1020-1023 has placeholder returning "not implemented". Implement 2CP counter-charge stratagem: non-active player moves friendly unit within 6" (not in engagement range) into engagement. Only WALKER vehicles eligible among vehicles. Does NOT grant Fights First. (CHG-RULES-2)
- [ ] Add terrain interaction during charges — Charging over terrain >2" high should cost vertical distance against the charge roll. Models cannot end mid-climb. FLY keyword allows diagonal measurement. No terrain interaction code exists in ChargePhase.gd. PRD designs terrain cost functions but they were not implemented. (CHG-RULES-3)
- [ ] Add AIRCRAFT charge restrictions — AIRCRAFT units cannot declare charges. Only units with FLY can declare charges against AIRCRAFT targets. No keyword checks for AIRCRAFT or FLY in `_can_unit_charge()` or `_validate_declare_charge()`. (CHG-RULES-4)
- [ ] Add barricade engagement range (2") — When charging a unit on the other side of a Barricade terrain feature, engagement range is 2" instead of 1". No barricade terrain type exists. (CHG-RULES-5)
- [ ] Enforce charge move direction constraint — Each model making a charge move must end closer to at least one charge target than it started. No explicit check exists in `_validate_charge_position()` or `_validate_charge_movement_constraints()`. (CHG-RULES-6)
- [ ] Enforce B2B move ordering priority — Models should move into base-to-base contact with an enemy first, then remaining models move. Players can currently move models in any order with no enforcement. (CHG-RULES-7)

## Multiplayer Issues

- [ ] Add charge actions to DETERMINISTIC_ACTIONS — Only `END_CHARGE` is in `DETERMINISTIC_ACTIONS` in NetworkManager.gd. `SELECT_CHARGE_UNIT`, `DECLARE_CHARGE`, `SKIP_CHARGE`, `COMPLETE_UNIT_CHARGE` could be optimistically executed on clients for better responsiveness. (CHG-MP-1)
- [ ] Sync ChargePhase local state to clients — ChargePhase maintains local state (`active_charges`, `pending_charges`, `dice_log`, `units_that_charged`, `current_charging_unit`, `completed_charges`, `failed_charge_attempts`) only on host. Client phase instances have empty copies. Client can't determine charge success/failure from phase state. (CHG-MP-2)
- [ ] Remove or document `_clear_phase_flags()` on phase exit — `ChargePhase._on_phase_exit()` calls `_clear_phase_flags()` which erases `charged_this_turn` and `fights_first` from local snapshot. While real GameState has the flags via diffs, this is fragile. ScoringPhase already handles end-of-turn cleanup. Remove or clearly document. (CHG-MP-3)
- [ ] Add turn timer handling for charge phase — Charge phase has multiple sub-steps (select, declare, roll, move models, confirm). 90-second turn timer may expire mid-charge with no graceful handling. (CHG-MP-4)
- [ ] Fix client `charge_resolved` re-emission to include failure detail — NetworkManager re-emits `charge_resolved` for `APPLY_CHARGE_MOVE` with generic "Charge movement validation failed" instead of the structured `failure_record` with categorized errors. Defending player loses detailed error info. (CHG-MP-5)

## Quality of Life

- [ ] Add auto-path / snap-to-engagement for charge movement — PRD designs auto-path system that suggests valid charge positions. Only manual drag-and-drop exists. Implement "snap to nearest valid engagement" button that auto-places models respecting all constraints. (CHG-QOL-1)
- [ ] Add real-time drag validation feedback during charge — During drag-and-drop model placement, specific reason a position is invalid (distance, overlap, etc.) is only logged to console, not shown in-UI. Show structured error info alongside red/green ghost. (CHG-QOL-2)
- [ ] Add engagement range visualization during charge movement — No visual indicators for 1" engagement range ring around target models, whether dragged model is in range, or which targets still need contact. Draw engagement range circles, color-code red/green. (CHG-QOL-3)
- [ ] Add distance-to-target indicator during charge drag — Distance tracking shows total movement used vs available but not edge-to-edge distance to nearest target model. Add live "Distance to target: X.X\"" label. (CHG-QOL-4)
- [ ] Add charge range (12") indicator — When selecting units for charging, no visual indicator of 12" range. Show range circle to help identify which enemies are in charge range. (CHG-QOL-5)
- [ ] Add step progress indicator for charge flow — Multi-step flow (Select → Targets → Declare → Roll → Move → Confirm) could be more explicit. Add "Step 3/6: Roll 2D6" progress indicator. Grey out unreached steps. (CHG-QOL-6)
- [ ] Add undo for individual model placement during charge — Once a model is placed during charge movement, no undo. Add "Undo Last Move" button to revert most recently placed model. (CHG-QOL-7)
- [ ] Add defending player charge phase visibility — Opponent has minimal feedback during charges: no unit selected indicator, no target highlights, no model movement animation. Show status indicator, highlight charging unit and targets, animate model movements. (CHG-QOL-8)

## Visual Improvements

- [ ] Improve target highlights from squares to base-sized circles — `ChargeController._highlight_unit()` uses 32x32 ColorRect squares. Use circular highlights matching model base sizes, or pulsing outlines. (CHG-VIS-1)
- [ ] Improve charge line visuals — Lines between unit centers and targets are basic. Use dashed/animated lines with arrowheads and distance labels. (CHG-VIS-2)
- [ ] Add dice roll animation for charge rolls — 2D6 result appears instantly. Add brief bouncing/rolling animation before revealing result. (CHG-VIS-3)

## Code Quality

- [ ] Remove unused `_process()` computation in ChargeController — `ChargeController._process()` calls `current_phase.get_available_actions()` every frame but doesn't use the result. Remove wasted computation. (CHG-CODE-1)
- [ ] Remove direct GameState mutation in ChargeController — `ChargeController._update_model_position_in_gamestate()` directly mutates GameState during drag-and-drop, bypassing the action→result→diff pipeline. If server rejects the charge, client state has stale positions that were never reverted. Route through action pipeline. (CHG-CODE-2)
- [ ] Consolidate duplicate charge roll handlers — `ChargeController` has two nearly identical handlers: `_on_charge_roll_made()` and `_on_dice_rolled()`. Deduplication check via `last_processed_charge_roll` is fragile. Merge into single handler with clear entry point. (CHG-CODE-3)
