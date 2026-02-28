# AI Audit Tasks

> Source: AI_AUDIT.md — 82 items across P0-P3 priorities

## P0 — Critical (AI plays incorrectly without these)

- [x] Implement AI charge declarations — evaluate charge feasibility (distance, probability), declare charges against optimal targets, compute model positions post-charge (AI-GAP-1, CHARGE-1 through CHARGE-3)
- [x] Implement pile-in movement — move models up to 3" toward nearest enemy during fight phase (AI-GAP-2, FIGHT-1)
- [x] Implement consolidation movement — move models up to 3" toward nearest enemy or objective after fighting (AI-GAP-2, FIGHT-2)
- [x] Implement fall-back model positioning — compute valid fall-back destinations away from enemy engagement range (MOV-6)

## P1 — High (AI plays very poorly without these)

- [x] Add weapon range checking to target scoring — score 0 for out-of-range targets (AI-GAP-5, SHOOT-4)
- [x] Implement focus fire system — coordinate weapon assignments across all shooting units to concentrate on kill thresholds (AI-TACTIC-2, SHOOT-1)
- [x] Implement weapon-target efficiency matching — match anti-tank to vehicles, anti-infantry to hordes, avoid wasting multi-damage on single-wound models (AI-TACTIC-5, SHOOT-2)
- [x] Add invulnerable save to target scoring — use min(modified_save, invuln) in shooting target evaluation (AI-GAP-6, SHOOT-3)
- [x] Add weapon keyword awareness to target scoring — Blast, Rapid Fire, Melta, Anti-keyword, Torrent, Sustained/Lethal/Devastating Wounds (SHOOT-5)
- [x] Implement basic stratagem usage — start with Grenade, Fire Overwatch, Go to Ground, Command Re-roll, Smokescreen (AI-GAP-3)
- [x] Implement unit ability awareness — read abilities, factor leader bonuses, detect "Fall Back and X" (AI-GAP-4)
- [x] Implement scout move execution — move scout units toward nearest uncontrolled objective (SCOUT-1, SCOUT-2)
- [x] Add enemy threat range awareness — calculate charge threat zones and shooting ranges, avoid moving into danger (AI-TACTIC-4, MOV-2)
- [x] Add shooting range consideration to movement — don't move units out of their weapon range (MOV-1)
- [ ] Implement screening/deep strike denial — position cheap units to deny enemy deep strike zones (AI-TACTIC-3, MOV-4)
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
- [x] Destroy reserves units not arrived by end of Round 3 — Per rules, any reserves units not on the battlefield by end of Round 3 count as destroyed. No enforcement exists. Add check at end-of-round processing to mark remaining `IN_RESERVES` units as `DESTROYED` with notification (DEPLOY-RULES-2)
- [ ] Implement TITANIC unit deployment skip — When a player deploys a TITANIC unit, they skip their next deployment turn. Detect TITANIC keyword in `TurnManager.check_deployment_alternation()` and skip the deploying player's next turn (DEPLOY-RULES-3)
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
- [ ] Add deployment zone theming — Subtle textures/patterns within zones (diagonal hatching, military markers) to distinguish from regular board (DEPLOY-VIS-3)
- [ ] Enhance ghost visual with coherency aids — Add pulsing effect to ghost, connecting line from ghost to nearest placed model, distance display to nearest friendly model (DEPLOY-VIS-4)
- [ ] Add coherency visualization circles — Draw faint 2" radius circles around placed models, green when next model in range, red when out of range (DEPLOY-VIS-5)
- [ ] Add unit name labels on deployed tokens — Show unit name on hover over deployed token or as tiny label beneath token cluster to distinguish same-type units (DEPLOY-VIS-6)
- [ ] Add opponent deployment zone dimming — Dim/desaturate opponent zone when it's your turn, brighten your own zone. Reverse on opponent's turn (DEPLOY-VIS-7)

## Multiplayer Issues

- [ ] Implement graceful disconnect handling during deployment — Replace `get_tree().quit()` on disconnect with reconnection dialog, grace period, option to save state or continue single-player (DEPLOY-MP-1)
- [ ] Add web relay "Waiting for game state" loading screen — Guest side loading screen that dismisses once host state is received, preventing flash of default army configuration (DEPLOY-MP-2)
- [ ] Reduce deployment timeout punitiveness — Longer timeout during deployment (>90s for large armies), warnings at 60s and 30s, consider auto-placing remaining units instead of instant loss (DEPLOY-MP-3)
- [ ] Batch deploy+embark/attach into composite action — Fix race condition where embark/attach actions arrive after player switch in multiplayer. Bundle deploy + embark/attach into single atomic action (DEPLOY-MP-4)

## Code Quality

- [ ] Consolidate duplicate geometry functions — Move shared `_circle_wholly_in_polygon()`, `_point_to_line_distance()`, `_shape_wholly_in_polygon()` from DeploymentPhase.gd and DeploymentController.gd into Measurement.gd (DEPLOY-CODE-1)
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
- [ ] Add 5" vertical component to Engagement Range checks — `Measurement.is_in_engagement_range_shape_aware()` is purely 2D (1" horizontal). Rules define ER as 1" horizontal AND 5" vertical. Add height/elevation check to engagement range calculation in Measurement.gd. Affects movement restrictions, shooting eligibility, fight eligibility, and charge validation. (MOV-8)
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
- [ ] Enforce Extra Attacks number cannot be modified — Balance Dataslate: "number of attacks made with an Extra Attacks weapon cannot be modified by other rules, unless that weapon's name is explicitly specified." Add validation in RulesEngine.gd attack count calculation. (SHOOT-4)
- [ ] Verify Tank Shock matches Balance Dataslate v3.3 — v3.3: Roll D6 equal to TOUGHNESS of selected Vehicle model, 5+ = MW (max 6 MW). Check StratagemManager.gd Tank Shock implementation against updated wording. (CHG-1)
- [ ] Add terrain penalties to Heroic Intervention charge roll — `_is_heroic_intervention_roll_sufficient()` does not apply terrain vertical distance penalties unlike normal charge sufficiency check. Add terrain penalty calculation. (CHG-2)
- [ ] Verify consolidation is mandatory at unit level per FAQ — "Consolidation for a unit is not optional. However, for each model, whether or not that model makes a Consolidation move is optional." Ensure FightPhase.gd forces the consolidation step even if individual models don't move. (FGT-1)
- [ ] Implement Obscuring terrain keyword — No special rules for terrain features with the Obscuring keyword. Add terrain trait and LoS interaction. (TER-4)
- [ ] Implement Deep Strike can choose Strategic Reserves placement — Balance Dataslate: "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose to set up using Strategic Reserves OR Deep Strike rules." Add option in reinforcement placement UI. (DEP-3)
- [ ] Update Scouts rules per Balance Dataslate — Dedicated Transports can use Scouts ability from embarked unit. Scout distance can exceed Move characteristic as long as ≤ X". Update ScoutPhase.gd. (DEP-4)
- [ ] Complete Scorched Earth mission — Burn mechanics are stub only. Implement the objective burning action and scoring. (MIS-1)
- [ ] Complete The Ritual mission — Action-based objective mechanics not implemented. Add action system for ritual objectives. (MIS-2)
- [ ] Complete Terraform mission — Objective flipping between players not implemented. Add flip mechanics. (MIS-3)
- [ ] Add Fixed secondary mission mode — Only tactical deck mode available. Add option for players to select 3 fixed secondary missions before the game. (MIS-4)
- [ ] Apply Balance Dataslate v3.3 stratagem modifications — Multiple stratagem changes: closer setup range (3"→6"), AP worsening timing, CP cost modifications, targeting prevention (12"→18"), unit addition once per battle restriction. Update StratagemManager.gd. (GEN-4)
- [ ] Update Rapid Ingress per Balance Dataslate — Updated: "if every model has Deep Strike ability, you can set up using Deep Strike (even though not your Movement phase)." Verify implementation in StratagemManager.gd. (GEN-5)
- [ ] Update Fire Overwatch timing per Balance Dataslate — Trigger expanded to: "just after an enemy unit is set up or when an enemy unit starts or ends a Normal, Advance or Fall Back move, or declares a charge." Verify timing in MovementPhase.gd and ChargePhase.gd. (GEN-6)
- [ ] Implement aura abilities system — No range-based aura effect application. `passive_aura` condition type exists in UnitAbilityManager.gd but is not functionally applied to other units within range. Build aura detection and effect propagation system. (GEN-7)
- [ ] Fix attached unit Toughness resolution — For wound rolls against an attached unit, Toughness should be the bodyguard unit's T value. RulesEngine.gd reads T from the target unit directly with no special handling for attached characters. May cause incorrect wound thresholds. (GEN-13)
- [ ] Fix weapon-by-weapon attack allocation for multi-weapon units — User reports "I should be able to allocate each user's attacks separately." Verify multi-weapon target assignment works correctly for units with different weapon profiles. (BUG-4)
- [ ] Fix save/load games with AI players — SaveLoadManager.gd has no AI player detection or state serialization. AI player state (difficulty, decision context) not preserved across save/load. (BUG-5)

## P3 — Low (Edge cases, polish, minor gaps)

- [ ] Prevent battle-shocked units from using self-targeted stratagems — StratagemManager.gd only prevents targeting battle-shocked units with friendly stratagems, not all stratagem usage by battle-shocked units. (CMD-3)
- [ ] Add confirmation before auto-resolving untaken battle-shock tests — Currently auto-resolves silently. Show warning dialog. (CMD-4)
- [ ] Fix embark/disembark distance calculation inconsistency — Embark uses `model_to_model_distance_inches()` but disembark uses shape-aware distance. Standardize. (MOV-6)
- [ ] Enforce "cannot select to shoot with no eligible targets" — "Unless at least one model in a unit has an eligible target, that unit cannot be selected to shoot." Add check to unit selection. (SHOOT-7)
- [ ] Track invulnerable save source in UI — When invuln save is used, show indicator of whether it's model-native or effect-granted. (SHOOT-8)
- [ ] Display terrain penalty in charge distance UI — Players see rolled distance but not effective distance after terrain penalties. Show "Effective: X\" (Y\" - Z\" terrain)". (CHG-3)
- [ ] Add live direction validation feedback during charge movement — No real-time feedback as player drags model to show if final position satisfies direction constraint. (CHG-4)
- [ ] Verify Epic Challenge stratagem interaction in attached units — Ensure 1CP Epic Challenge properly enables CHARACTER vs CHARACTER melee dueling within attached units. (FGT-2)
- [ ] Sync pile-in/consolidation drag for remote player — Remote player sees models "teleport" to final positions; cosmetic only. (FGT-3)
- [ ] Complete when-drawn secondary mission interactions UI — Marked for Death and Tempting Target opponent selection not fully wired. (MIS-5)
- [ ] Verify objective control timing — "A player will control an objective marker at the end of any phase or turn." Ensure timing matches rules. (MIS-6)
- [ ] Validate Warlord designation — `is_warlord` field exists but no enforcement that exactly one CHARACTER is designated. (GEN-9)
- [ ] Add army construction points validation — Points tracked but no validation during list building. No detachment enforcement. (GEN-10)
- [ ] Verify persisting effects match Core Rules Updates — Core Rules Updates defines "persisting effects" with specific duration tracking. Verify effect expiration. (GEN-11)
- [ ] Implement redeployment rules — Core Rules Updates: rules allowing redeployment resolved after Deploy Armies, before Determine First Turn. (GEN-12)
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
- [ ] Add persistent model health bars on board — Show model wounds above/below bases. (VIS-7)
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
