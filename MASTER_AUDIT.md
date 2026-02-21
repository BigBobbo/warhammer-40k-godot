# Master Audit — All Phases Combined & Prioritized

> **Generated:** 2026-02-16 | **Updated:** 2026-02-20 (AI Player Audit)
> **Source audits:** AUDIT_COMMAND_PHASE.md, MOVEMENT_PHASE_AUDIT.md, DEPLOYMENT_AUDIT.md, SHOOTING_PHASE_AUDIT.md, CHARGE_PHASE_AUDIT.md, FIGHT_PHASE_AUDIT.md, TERRAIN_LAYOUTS_AUDIT.md, TESTING_AUDIT_SUMMARY.md, **MATHHAMMER_AUDIT** (inline below), **AI_AUDIT.md**, plus TODO comments found in code.
>
> Items are grouped into priority tiers based on impact to gameplay correctness, then by phase. Each item links back to its source audit.

---

## How to Read This Document

- **DONE** = verified implemented in the codebase as of 2026-02-16
- **PARTIAL** = infrastructure exists but integration incomplete
- **OPEN** = not yet implemented
- Severity: CRITICAL > HIGH > MEDIUM > LOW > QoL/Visual
- Items within a tier are ordered by estimated gameplay impact

---

## Recently Completed Items (for reference)

These items were previously open in the audit files and have now been verified as done:

| Item | Phase | Source Audit |
|------|-------|-------------|
| T3-24 (2026-02-21): Defender stats override panel — Verified existing implementation of "Custom Defender Stats" checkbox with SpinBox fields for T/Sv/W/Models/Invuln/FNP in MathhammerUI.gd, auto-populating from selected defender. Overrides applied via `Mathhammer._apply_defender_overrides()`. Added 9 unit tests. | Mathhammer | MATHHAMMER_AUDIT |
| T3-17 (2026-02-21): Dual resolution paths — prevent rules drift — Synchronized auto-resolve with interactive path: added DW tracking/save bypass with spillover, FNP, Precision, half-damage to `_resolve_assignment()` | Shooting | SHOOTING_PHASE_AUDIT.md §Additional Issues |
| T3-16 (2026-02-21): Difficult terrain / movement penalties — Added terrain traits system with `"difficult_ground"` trait (flat 2" penalty per piece crossed). FLY units ignore. 17 tests. | Movement | MOVEMENT_PHASE_AUDIT.md §2.7 |
| T3-15 (2026-02-21): Disembarked units don't count as Remained Stationary — Added `disembarked_this_phase` check in `_process_remain_stationary()` to prevent Heavy weapon bonus for disembarked units | Movement | MOVEMENT_PHASE_AUDIT.md §2.12 |
| T3-14 (2026-02-21): Desperate Escape battle-shocked modifier — Added conditional fail threshold (1-3 for battle-shocked, 1-2 for normal) in `_process_desperate_escape()`. Previously hardcoded to `roll <= 2` for all cases. | Movement | AUDIT_COMMAND_PHASE.md |
| T3-13 (2026-02-21): Fight selection dialog sync for remote player — Replaced fragile 0.1s timer workaround with pending data retrieval pattern in FightPhase/FightController, eliminating race condition on initial fight selection dialog for remote players. | Fight | FIGHT_PHASE_AUDIT.md §3.4 |
| T7-50 (2026-02-21): AI multi-target charge declarations — Added `_evaluate_multi_target_charge()` and `_score_multi_target_combo()` to evaluate 2- and 3-target charge combinations. Multi-target bonus (+15% per extra target) and clustering bonus. Correctly picks multi-target when targets are close together. | Charge/AI | AI_AUDIT.md §CHARGE-4 |
| T7-38 (2026-02-21): AI shooting target line visualization — Red targeting line from shooter to target(s) during AI shooting, floating hit/wound result summary, and per-model damage numbers/death animations via `shooting_damage_applied` signal in AI path. | UI | AI_AUDIT.md §VIS-2 |
| T7-36 (2026-02-21): AI speed controls — Added `AISpeedPreset` enum (FAST/NORMAL/SLOW/STEP_BY_STEP) with configurable delays (0ms/200ms/500ms/pause) to AIPlayer.gd. Speed dropdown in MainMenu.gd, in-game HUD with comma/period/slash keyboard controls, step-by-step mode with "Continue (Space)" button. | UI/Settings | AI_AUDIT.md §QoL-3 |
| T7-19 (2026-02-20): AI turn summary panel — Created `AITurnSummaryPanel.gd` post-turn summary popup consuming `ai_turn_ended` signal. Displays categorized action counts per phase (units moved, fired, charged, fought, stratagems used) with notable action descriptions. WhiteDwarf gothic theme, auto-dismiss after 12s, Escape/button dismiss. | UI/AI | AI_AUDIT.md §QoL-1 |
| T7-14 (2026-02-20): AI shooting range consideration in movement — Enhanced movement destination scoring to evaluate weapon range at estimated destinations (bonus for maintaining range, penalty for losing all targets, bonus for gaining new targets). Added firing position preservation with arc-sampling for ranged units moving toward objectives. | Movement/AI | AI_AUDIT.md §MOV-1 |
| T7-12 (2026-02-20): AI scout move execution — Fixed double `phase_completed` emission in ScoutPhase and objective zone index alignment in AIDecisionMaker. Scout movement toward nearest uncontrolled objective with >9" enemy distance verified working (32 tests pass). | Scout/AI | AI_AUDIT.md §SCOUT-1, SCOUT-2 |
| T7-11 (2026-02-20): AI unit ability awareness — Added Deadly Demise detection, doomed-vehicle leverage (movement toward enemies + charge bonus), Lone Operative movement protection (>12" retreat), Lone Operative targeting restriction in focus-fire, enhanced Oath of Moment (invuln/leader/weapon-efficiency awareness). 10 new tests pass. | All/AI | AI_AUDIT.md §AI-GAP-4 |
| T7-58 (2026-02-20): AI charge arrow visualization — Created ChargeArrowVisual.gd with animated arrow (state machine: idle→line_draw→hold→fade), orange/yellow arrowhead with glow, charge roll result label. Integrated into ChargeController and Main.gd for both human and AI charge declarations. | UI/AI | AI_AUDIT.md §VIS-3 |
| T7-57 (2026-02-20): AI post-game performance summary — Extended GameOverDialog with AI Performance Analysis section showing VP breakdown, units killed/lost, models remaining, CP spent/remaining, objectives held per round, key moments. Added tracking infrastructure to AIPlayer.gd with hooks in ShootingPhase, FightPhase, ScoringPhase. | UI/AI | AI_AUDIT.md §QoL-9 |
| T7-56 (2026-02-20): AI turn replay — Per-turn action history in AIPlayer.gd, AITurnReplayPanel.gd with round/player navigation and color-coded phase entries, 'R' key toggle, ESC/X close. Turn-grouped query methods in ReplayManager.gd. | UI/AI | AI_AUDIT.md §QoL-8 |
| T7-55 (2026-02-20): AI vs AI spectator mode improvements — Added spectator mode detection (both players AI), auto-slowed action delay (500ms, adjustable 0.25x-4.0x via comma/period/slash keys), phase summaries with action counts per player in AIActionLogOverlay, spectator speed indicator HUD. | UI/AI | AI_AUDIT.md §QoL-7 |
| T7-54 (2026-02-20): AI action log overlay — Created `AIActionLogOverlay.gd` — small scrolling overlay in bottom-right corner showing real-time AI actions with color-coded entries, phase headers, auto-fade after inactivity, auto-scroll, and old-entry trimming. Integrated via `ai_action_taken`/`ai_turn_started`/`ai_turn_ended` signals in Main.gd. | UI/AI | AI_AUDIT.md §VIS-7 |
| T7-53 (2026-02-20): AI floating damage numbers — Added `shooting_damage_applied` signal to ShootingPhase, floating damage number display to ShootingController (matching FightController pattern), floating numbers to WoundAllocationOverlay for interactive saves, `play_kill_notification()` to DamageFeedbackVisual for "UNIT DESTROYED" banners, and kill notification checks to both FightController and ShootingController. | UI/AI | AI_AUDIT.md §VIS-6 |
| T7-52 (2026-02-20): AI unit highlighting during actions — Created `AIUnitHighlight.gd` visual component with pulsing glow rings (blue=move, red=shoot, orange=charge/fight). Integrated into `Main.gd` via `ai_action_taken` signal to highlight the AI's active unit during each action, with position tracking and auto-clear on phase/turn end. | UI/AI | AI_AUDIT.md §VIS-5 |
| T7-51 (2026-02-20): AI overwatch risk assessment for charges — Added `_estimate_overwatch_risk()` and `_estimate_unit_overwatch_damage()` to AIDecisionMaker.gd. AI evaluates best enemy overwatch shooter (within 24", with CP, ranged weapons) using hit-on-6s damage math (wound prob, save, wound overflow cap, FNP). Risk classified as low/moderate/high/extreme with score penalties. Extra caution for CHARACTERs and when overwatch could kill 50%+ of charger HP. 5 new tests pass. | Charge/AI | AI_AUDIT.md §CHARGE-5 |
| T7-49 (2026-02-20): AI counter-play to opponent defensive stratagems — Added strategic deprioritization (×0.80) in `_score_shooting_target()` for targets with active effect-granted cover, stealth, or invulnerable saves from defensive stratagems. Encourages AI to redirect firepower to softer targets. 3 new tests pass. | Shooting/AI | AI_AUDIT.md §SHOOT-10 |
| T7-47 (2026-02-20): AI secondary mission discard logic — Replaced stub `_decide_scoring()` with full mission achievability evaluation. Added 14 mission-specific assessors. AI discards unachievable missions for +1 CP based on board state analysis. 16/16 tests pass. | Scoring/AI | AI_AUDIT.md §SCORE-2 |
| T7-46 (2026-02-20): AI fight order optimization — Added `_build_fight_order_plan()` and `_score_fighter_priority()` to AIDecisionMaker.gd. When multiple AI units are eligible to fight, the AI now scores each by kill potential, target value, vulnerability, and damage output to determine optimal activation order. Uses the same plan-cache pattern as the shooting focus fire plan. | Fight/AI | AI_AUDIT.md §FIGHT-6 |
| T7-45 (2026-02-20): AI faction ability activation — Added `_select_oath_of_moment_target()` with strategic threat-based Oath of Moment target selection. Reuses macro target priority (`_calculate_target_value`) plus Oath-specific bonuses for toughness, save, remaining wounds, and below-half-strength. Integrated into `_decide_command()` after battle-shock tests. 13/13 tests pass. | Command/AI | AI_AUDIT.md §CMD-3 |
| T7-44 (2026-02-20): AI counter-deployment — Added `_apply_counter_deployment()` and `_get_deployed_enemy_analysis()` to react to opponent's deployed units. Melee units shift toward enemy fragile/high-value targets, fragile shooters shift away from enemy melee, durable shooters orient toward enemy concentrations, characters avoid enemy shooting lanes. Gated at Normal+ difficulty via `use_counter_deployment()` in AIDifficultyConfig.gd. | Deployment/AI | AI_AUDIT.md §DEPLOY-2 |
| T7-43 (2026-02-20): AI late-game strategy pivot — Added `_get_round_strategy_modifiers()` with per-round multipliers (aggression, objective_priority, survival, charge_threshold). Rounds 1-2 AGGRESSIVE: +30% kill value, -15% obj weight, -20% threat penalty, -20% charge threshold. Round 3 BALANCED: all 1.0. Rounds 4-5 OBJECTIVE/SURVIVAL: -30% kill value, +40% obj priority, +40% threat avoidance, +30% charge threshold, +50% objective-charge bonus, +30% objective-target bonus. Applied across movement, shooting, charge, engaged-unit, and consolidation decisions. | All/AI | AI_AUDIT.md §AI-TACTIC-10 |
| T7-42 (2026-02-20): AI move blocking — Added `_calculate_corridor_blocking_positions()` to identify key corridors between enemy units and objectives, then assign expendable units to block them. Corridor positions calculated at 55% along the enemy-to-objective line, prioritized by objective importance and enemy proximity. Integrated into PASS 3 of unit assignment alongside existing screening/denial logic. Capped at 4 blocking positions with 5" minimum spacing. | Movement/AI | AI_AUDIT.md §AI-TACTIC-9 |
| T7-40 (2026-02-20): AI difficulty levels — Created `AIDifficultyConfig.gd` with Easy/Normal/Hard/Competitive difficulty enum and per-level feature flags (stratagems, multi-phase planning, threat awareness, trade analysis, score noise, charge thresholds). Easy uses random valid actions; Normal is current behavior; Hard adds stratagems and multi-phase planning; Competitive adds look-ahead and zero noise. Per-player difficulty stored in AIPlayer, gating reactive stratagems/overwatch/counter-offensive/command reroll by level. Difficulty dropdowns auto-shown in MainMenu when player type is AI. | Settings/AI | AI_AUDIT.md §QoL-5 |
| T7-39 (2026-02-20): AI objective control flash on change — Added `flash_control_change()` to ObjectiveVisual.gd with pulsing ring animation (green=AI capture, red=AI loss, yellow=contested). Real-time objective rechecks after movement/charge via `call_deferred`. Updated `objective_control_changed` signal to include old_controller. | UI/AI | AI_AUDIT.md §VIS-4 |
| T7-37 (2026-02-20): AI decision explanations — Enhanced `_ai_description` strings across shooting (expected damage vs HP, kill %), charge (melee damage, charge probability), fight (weapon + expected damage vs HP), deployment (grid position), reactive stratagems (protection score, points). Key tactical decisions routed through `GameEventLog.add_ai_entry()` via AIPlayer. Updated test assertion in test_ai_focus_fire.gd. | UI/AI | AI_AUDIT.md §QoL-4 |
| T7-34 (2026-02-20): AI reserves declarations — Added `_evaluate_reserves_declarations()` and `_score_unit_for_reserves()` to AIDecisionMaker.gd. AI scores units for reserves by type (Deep Strike melee 8.0, DS short-range 5.0, strategic reserves melee/fast 4.0+). Excludes CHARACTER leaders, FORTIFICATION, embarked units. Penalizes VEHICLE/MONSTER ranged and long-range shooters. Respects 25% pts cap, 50% unit cap, 2.0 score threshold. | Formations/AI | AI_AUDIT.md §FORM-3 |
| T7-33 (2026-02-20): AI transport usage — Added `_evaluate_transport_embarkation()` and `_score_unit_for_embarkation()` for formations phase (FORM-2), plus `_decide_transport_disembark()`, `_score_disembark_benefit()`, and `_compute_disembark_positions()` for movement phase (MOV-7). AI scores units for embarkation by fragility/speed/weapons, disembarks based on objective proximity/shooting/charge opportunities/transport safety. | Formations/Movement/AI | AI_AUDIT.md §FORM-2, MOV-7 |
| T7-32 (2026-02-20): AI Counter-Offensive stratagem usage — Added `evaluate_counter_offensive()` in AIDecisionMaker.gd with scoring heuristic (unit value, melee capability, keywords, wound status, engagement risk). Connected signal in AIPlayer.gd, added AI skip in FightController.gd. | Fight/AI | AI_AUDIT.md §FIGHT-5 |
| T7-31 (2026-02-20): AI cover consideration in target scoring — Added `_target_has_benefit_of_cover()`, `_check_position_has_terrain_cover()`, `_weapon_ignores_cover()` helpers. Both `_score_shooting_target()` and `_estimate_weapon_damage()` now apply cover as +1 to armour save (min 2+), respecting Ignores Cover weapons and invuln save interaction. 24/24 tests pass. | Shooting/AI | AI_AUDIT.md §SHOOT-7 |
| T7-30 (2026-02-20): AI range-band optimization — Added half-range weapon analysis (`_get_unit_half_range_data`, `_find_best_half_range_position`) for Rapid Fire/Melta. Movement blends toward half-range positions (40% weight). `_should_hold_for_shooting` overridden when advancing would reach half range. | Shooting/Movement/AI | AI_AUDIT.md §SHOOT-6 |
| T7-29 (2026-02-20): AI fight target optimization — Rewrote `_assign_fight_attacks()` to score targets by combined damage + strategic value via new `_score_fight_target()`. Filters to engagement-range targets. Strategic scoring: kill potential, CHARACTER priority, overkill penalty, lock-shooters, objective presence, defensive abilities, trade efficiency. Preserves T7-28 multi-weapon optimization. | Fight/AI | AI_AUDIT.md §FIGHT-4 |
| T7-28 (2026-02-20): AI multi-weapon melee optimization — Rewrote `_assign_fight_attacks()` to evaluate all melee weapon profiles against all enemy targets. Separates weapons into primary vs Extra Attacks categories, calculates expected damage per weapon×target pairing (including EA weapon bonus), picks damage-maximizing combination. Added `_evaluate_melee_weapon_damage()` and `_weapon_has_extra_attacks()` helpers. 36+37+28 tests pass. | Fight/AI | AI_AUDIT.md §AI-GAP-7, FIGHT-3 |
| T7-27 (2026-02-20): AI engaged unit survival assessment — Added survival assessment helpers to estimate expected fight-phase melee damage from engaging enemies. Integrated into `_decide_engaged_unit()`: objective holders facing lethal damage fall back when others can hold; sole holders stay but log threat. Fall-back reasons enriched with survival data. 23/23 tests pass. | Movement/AI | AI_AUDIT.md §MOV-9 |
| T7-24 (2026-02-20): AI trade and tempo awareness — Added `_get_points_per_wound()`, `_get_trade_efficiency()`, `_calculate_tempo_modifier()` to AIDecisionMaker.gd. PPW-based target value bonus, trade efficiency in charge scoring, VP-differential tempo modifier affecting objective urgency/focus fire/charge thresholds. Desperation mode in rounds 4-5 when behind. 41+36+40+34 tests pass, 0 regressions. | All/AI | AI_AUDIT.md §AI-TACTIC-7 |
| T7-23 (2026-02-20): AI multi-phase planning — Added `_build_phase_plan()` cross-phase coordinator (movement→shooting→charge). Charge intent identifies melee units and blends movement toward charge angles. Shooting suppresses charge targets (`PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET`). Charge prefers locking dangerous shooters (`PHASE_PLAN_LOCK_SHOOTER_BONUS`). Expanded urgency scoring to all 5 rounds (R1 rush, R2 contest, R3 consolidate, R4-5 push). 34/34 tests pass. | All/AI | AI_AUDIT.md §AI-TACTIC-6 |
| T7-22 (2026-02-20): AI target priority framework — Implemented two-level target priority: macro-level `_calculate_target_value` with points-weighted base value, probability-weighted damage, ability value from AIAbilityAnalyzer, objective/OC scoring, leader buff priority; micro-level `_build_focus_fire_plan` with iterative marginal value optimization via `_calculate_marginal_value` (kill threshold bonuses, model kill milestones, overkill decay, opportunity cost). | Shooting/AI | AI_AUDIT.md §AI-TACTIC-1 |
| T7-20 (2026-02-20): AI thinking indicator — Added `_ai_thinking` state tracking and `ai_turn_started`/`ai_turn_ended` signal emissions to AIPlayer.gd. Created pulsing "AI is thinking..." overlay in Main.gd with animated ellipsis dots, WhiteDwarf gothic styling. Connected via `_initialize_ai_player()`. 15/15 tests pass. | UI/AI | AI_AUDIT.md §QoL-2 |
| T7-18 (2026-02-20): AI terrain-aware deployment — Added `_classify_deployment_role()`, `_score_terrain_for_role()`, `_find_terrain_aware_position()` to `_decide_deployment()`. Units classified by role (character/fragile_shooter/durable_shooter/melee/general) and positioned near beneficial terrain (LoS blockers for characters, cover for fragile shooters, front-edge LoS blockers for melee). 20/20 tests pass. | Deployment/AI | AI_AUDIT.md §DEPLOY-1 |
| T7-17 (2026-02-20): AI leader attachment in formations — Replaced stub `_decide_formations()` with synergy-based leader attachment. `_evaluate_best_leader_attachment()` and `_score_leader_bodyguard_pairing()` simulate each pairing using AIAbilityAnalyzer multipliers (offensive ranged/melee, defensive FNP/cover, tactical bonuses). Scales by model count and points. 16/16 tests pass. | Formations/AI | AI_AUDIT.md §AI-GAP-8, FORM-1 |
| T7-16 (2026-02-20): AI reserves deployment — Added `_decide_reserves_arrival()` for AI reserve unit deployment from Round 2+. Scores units by urgency, computes valid positions (strategic reserves: within 6" of edge; deep strike: near objectives). Enforces 9" enemy distance (edge-to-edge), Turn 2 opponent zone restriction. Updated AIPlayer.gd for reinforcement visuals. | Movement/AI | AI_AUDIT.md §MOV-8 |
| T7-15 (2026-02-20): AI screening and deep strike denial — Wired `_compute_screen_position()` into Pass 3 of unit assignment. Added `_get_enemy_reserves()`, `_is_screening_candidate()`, `_calculate_denial_positions()` for 9" deep strike denial zones. Cheap units prioritized for screening duty, spaced 18" apart. Added "screen" action handling in movement execution. | Movement/AI | AI_AUDIT.md §AI-TACTIC-3, MOV-4 |
| T7-13 (2026-02-20): AI enemy threat range awareness — Enemy threat ranges (charge M+12"+1", shooting max range) calculated pre-movement. Added 12" close melee proximity penalty, melee weapon quality in threat estimation, threat-aware assignment scoring/position adjustment. 34/35 tests pass (1 pre-existing). | Movement/AI | AI_AUDIT.md §AI-TACTIC-4, MOV-2 |
| T7-10 (2026-02-20): AI basic stratagem usage — AI uses all core stratagems: Grenade, Fire Overwatch, Go to Ground/Smokescreen, Command Re-roll (charge/advance/battleshock), Tank Shock, Heroic Intervention. Added `evaluate_tank_shock()` and `evaluate_heroic_intervention()` heuristics, signal handlers, movement phase reroll fallback. 33+36 tests pass. | All/AI | AI_AUDIT.md §AI-GAP-3 |
| T7-9 (2026-02-20): AI weapon keyword awareness in target scoring — `_apply_weapon_keyword_modifiers()` handles all 8 keywords (Torrent, Blast, Rapid Fire, Melta, Anti-keyword, Sustained/Lethal/Devastating Hits). Fixed Blast formula from 9th ed thresholds to correct 10th ed `floor(models/5)`. Both `_score_shooting_target()` and `_estimate_weapon_damage()` use keyword pipeline. 50/50 tests pass. | Shooting/AI | AI_AUDIT.md §SHOOT-5 |
| T7-8 (2026-02-20): AI invulnerable save consideration in target scoring — `_save_probability()` now accepts invuln parameter using `min(modified_save, invuln)`. Added `_get_target_invulnerable_save()` helper for model/meta/effect invuln sources. All callers pass invuln through. 18/18 tests pass. | Shooting/AI | AI_AUDIT.md §AI-GAP-6, SHOOT-3 |
| T7-7 (2026-02-20): AI weapon-target efficiency matching — Re-enabled damage waste penalty for multi-damage weapons vs 1W models (D3+ → 0.4×, D2 → 0.7×). Combined with role matching, lascannon vs grots = 0.24× efficiency. Added fallback logging. 40/40 tests pass. | Shooting/AI | AI_AUDIT.md §AI-TACTIC-5, SHOOT-2 |
| T7-6 (2026-02-20): AI focus fire coordination across units — Enhanced `_build_focus_fire_plan()` with wound overflow cap, value-per-threshold sorting, model-level partial kills with efficiency filtering, coordinated secondary target allocation. 41/41 focus fire tests pass, 37/37 efficiency tests pass. | Shooting/AI | AI_AUDIT.md §AI-TACTIC-2, SHOOT-1 |
| T7-21 (2026-02-20): AI movement path visualization — Created `AIMovementPathVisual.gd` with dashed trails, arrowheads, origin markers, player-themed colors, 1.5s hold + 0.8s fade. Integrated into `AIPlayer._execute_ai_movement()` and `_execute_ai_scout_movement()`. | UI/AI | AI_AUDIT.md §VIS-1 |
| T7-5 (2026-02-20): AI weapon range check in target scoring — `_score_shooting_target()` returns 0 for out-of-range targets using `_get_weapon_range_inches()` and `_get_closest_model_distance_inches()`. 15/15 range scoring tests pass. | Shooting/AI | AI_AUDIT.md §AI-GAP-5, SHOOT-4 |
| T7-4 (2026-02-20): AI fall-back model positioning — Fixed `_pick_fall_back_target()` directional scoring (skip near-objectives, prefer away-from-enemy direction), zero-direction safety fallback in `_compute_fall_back_destinations()`. 15/15 fall-back tests pass. | Movement/AI | AI_AUDIT.md §MOV-6 |
| T7-3 (2026-02-20): AI consolidation movement — Dedicated `_compute_consolidate_movements_engagement()` with wrapping (far-side angular distribution around enemies), tagging (prioritise unengaged enemy units within 4"), objective fallback. 37 tests pass (3 new). | Fight/AI | AI_AUDIT.md §AI-GAP-2, FIGHT-2 |
| T7-2 (2026-02-20): AI pile-in movement — Full pile-in movement via `_compute_pile_in_action()`/`_compute_pile_in_movements()`. 3" toward closest enemy, B2B skip, collision avoidance with friendly/enemy obstacle splitting (allows B2B contact with enemies). Consolidation engagement mode reuses pile-in logic. 28 tests pass. | Fight/AI | AI_AUDIT.md §AI-GAP-2, FIGHT-1 |
| T7-1 (2026-02-20): AI charge declarations — Full charge decision system: `_evaluate_best_charge()` with 2D6 probability, melee damage estimation, target scoring, objective bonuses, leader ability multipliers. `_compute_charge_move()` for B2B positioning and coherency. Fixed RulesEngine autoload dependency and SKIP_CHARGE handling. 36 tests pass. | Charge/AI | AI_AUDIT.md §AI-GAP-1, CHARGE-1–3 |
| T5-V15 (2026-02-20): Mathhammer visual histogram — Replaced text-based histogram with graphical ColorRect bar chart; vertical bars (<=20 values) or horizontal bars (>20), color-coded by damage vs mean, auto-bucketing for wide ranges, percentage labels, legend | Mathhammer | MATHHAMMER_AUDIT, Code TODO |
| T5-MH1 (2026-02-20): Visual histogram / probability distribution chart — Implemented via T5-V15 | Mathhammer | MATHHAMMER_AUDIT |
| T5-V14 (2026-02-20): Deployment zone edge highlighting — Animated dashed border with marching ants, multi-layer pulsing glow on inner edges, corner markers, zone depth labels; inner/outer edge detection for board-boundary vs no-man's-land edges | Deployment | DEPLOYMENT_AUDIT.md §QoL 6 |
| T5-V13 (2026-02-20): Engaged units board indicator (crossed swords) — Crossed swords badge overlay on engaged unit tokens during fight phase, color-coded by fight priority; is_engaged/fight_priority flags in FightPhase with phase-exit cleanup | Fight | fight_phase_audit_report.md §3.5 |
| T5-V12 (2026-02-19): Damage application visualization — Extended DamageFeedbackVisual with floating damage numbers; FightController parses diffs to trigger flash, floating numbers, death animations, and token red flash on melee damage | Fight | fight_phase_audit_report.md §4.5 |
| T5-V11 (2026-02-19): Unit tokens "has fought" indicator — Added fought overlay (dimmed opacity + checkmark) to TokenVisual/TokenDrawUtils; fixed has_fought flag reset in ScoringPhase | Fight | fight_phase_audit_report.md §4.4 |
| T5-V10: Fight phase state banner — FightPhaseStateBanner.gd with persistent subphase/player/units-remaining display, distinct color schemes per subphase, animated transition overlay, FightController signal integration | Fight | fight_phase_audit_report.md §4.3 |
| T5-V9: Engagement range pulsing animation — EngagementRangeVisual.gd with sine-wave pulsing on engagement range circles and target highlights, replacing static inline scripts in FightController.gd | Fight | fight_phase_audit_report.md §4.2 |
| T5-V8: Pile-in/consolidate movement arrows and distance labels — PileInMovementVisual.gd with directional arrows, animated dashed movement paths, and distance labels replacing plain Line2D direction lines | Fight | fight_phase_audit_report.md §4.1 |
| T5-V7: Weapon keyword icons in UI — WeaponKeywordIcons.gd with color-coded badge icons for all 10 weapon keywords, composited strip textures, TreeItem icon integration, keyword tooltips | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-V6: Wound allocation overlay enhancements — Pulsing PRIORITY/PRECISION highlights (sine-wave alpha+scale), health gradient ring overlay (green→red), wound counter labels on multi-wound models | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-V5: Range circle visualization — Enhanced RangeCircle.gd with dashed half-range circles for Rapid Fire (orange) and Melta (red) weapons, subtle pulse animation, single reference model display, enemy color-coding | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-V4: Target unit damage feedback — DamageFeedbackVisual.gd with red damage flash, death expanding ring + debris particles + skull marker, token modulate flash, death fade-out animation | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-V3: Phase transition animation banners — PhaseTransitionBanner.gd with slide-in/out animation, phase icons, round/player info, WhiteDwarf gothic theme | All Phases | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-V2: Shooting line animation and tracer effects — ShootingLineVisual.gd with muzzle flash, traveling tracer, impact flash, animated line draw for local/remote players | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 4 |
| T5-V1: Animated dice roll visualization — DiceRollVisual.gd with cycling animation, color-coded dice (gold 6s, red 1s, green success, gray fail), integrated into Shooting/Fight/Charge controllers | Shooting/Fight/Charge | SHOOTING_PHASE_AUDIT.md §Tier 3 |
| T5-MH13: Shooting/Melee phase toggle — OptionButton filtering weapons/rules by phase, simulation routing, phase label in results, no-weapons hint | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH12: Multi-target comparison matrix — Compare Targets button with multi-defender selection, per-target comparison cards, priority/efficiency rankings | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH11: Show dice notation (D6, D3+3) in weapon stats display — added A: field and raw dice notation for attacks, strength, damage | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH10: "Clear Results" / "Reset" button — disabled-by-default button that clears results, histogram, and restores placeholder text | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH9: Deduplicate results display — removed _populate_breakdown_panel() which duplicated all summary_panel content into breakdown_panel | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH8: Color-code results — green for high kill prob, red for low efficiency, yellow for overkill. Threshold-based coloring on kill probability, efficiency, and overkill across all result panels | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH7: Loading spinner / progress bar during simulation — ProgressBar + label with live trial count, thread-safe updates via call_deferred | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH6: Responsive panel sizing — viewport-relative layout replacing hardcoded 800px/400x600 sizes | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH4: Damage per point efficiency metric — Attacker Cost and Damage/Point displayed in overall stats and weapon comparison views with efficiency ranking | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH5: Swap attacker/defender button — one-click role reversal with auto-refresh of weapons, rules, and override panel | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH3: Multi-weapon side-by-side comparison view — Compare Weapons button runs independent per-weapon simulations with ranked results | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH2: Cumulative probability display — "X% chance of at least N wounds" table with color-coded probability tiers | Mathhammer | MATHHAMMER_AUDIT |
| T5-UX14: Mathhammer melee simulation integration (full Monte Carlo prediction before dice rolling, scoping bug fix in Mathhammer.gd) | Fight/Mathhammer | FIGHT_PHASE_AUDIT.md, Code TODO |
| T5-UX12: Keyboard shortcuts for shooting phase (Space/Enter confirm, Esc deselect, Tab cycle, N skip, E end phase) | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 4 |
| T5-UX13: Score objectives in Scoring Phase (objective control display + updated control check before secondary scoring) | Scoring | ScoringController.gd TODO |
| T5-UX11: Unit base preview on hover in deployment (tooltip with base size, model count, special deployment rules) | Deployment | DEPLOYMENT_AUDIT.md §QoL 7 |
| T5-UX10: Auto-zoom to deployment zone (smooth camera pan/zoom to active player's zone on phase entry and turn switch) | Deployment | DEPLOYMENT_AUDIT.md §QoL 5 |
| T5-UX9: Undo last model placement per-model in deployment (Ctrl+Z / Undo button removes last model, Reset Unit button for full reset) | Deployment | DEPLOYMENT_AUDIT.md §QoL 4 |
| T5-UX8: Deployment summary before ending phase (summary dialog with deployed units, transports, characters, reserves) | Deployment | DEPLOYMENT_AUDIT.md §QoL 8 |
| T5-UX7: End fight phase confirmation dialog (warning with unfought units list before ending fight phase) | Fight | fight_phase_audit_report.md §3.6 |
| T5-UX6: Show weapon stats in target assignment UI (compact stat sub-line: Range, A, BS, S, AP, D beneath each weapon) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-UX5: "All to Target" button in fight attack assignment dialog (one-click assign all weapons to selected target) | Fight | fight_phase_audit_report.md §3.1 |
| T5-UX4: "Undo Last Assignment" button in weapon assignment (undo stack, per-weapon clear, UI feedback) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-UX3: "Shoot All Remaining" button (confirmation dialog + sequential auto-shoot at nearest targets) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-UX2: Auto-select weapon for single-weapon units (auto-select in tree, skip manual weapon click) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-UX1: Expected damage preview when hovering weapons (analytical preview panel with hit/wound/save pipeline) | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 3 |
| T5-MP9: BEGIN_ADVANCE latency in multiplayer (seed-embedded deterministic optimistic execution) | Movement | MOVEMENT_PHASE_AUDIT.md §3.3 |
| T5-MP8: Phase timeout for AFK players (auto-end phase, game over after consecutive timeouts, timer HUD, waiting overlay for all phases, toast warnings) | All Phases | AUDIT_COMMAND_PHASE.md §P3 |
| T5-MP6: "Waiting for Opponent" state in deployment (overlay banner, timer countdown, zone pulse, toast notifications) | Deployment | DEPLOYMENT_AUDIT.md §QoL 3 |
| T5-MP3: Remote player visual feedback for shooting actions (shooting lines, target highlights, weapon labels for ASSIGN_TARGET/CONFIRM_TARGETS/COMPLETE_SHOOTING) | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 3 |
| T5-MP2: Pile-in/consolidate validation feedback on client (pre-confirm gate + server rejection toast + re-request) | Fight | FIGHT_PHASE_AUDIT.md §3.5 |
| T5-MP1: Pile-in/consolidate drag movement synced visually to remote player | Fight | FIGHT_PHASE_AUDIT.md §3.6 |
| CP Generation (1 CP per command phase) | Command | AUDIT_COMMAND_PHASE.md |
| CP Display in UI | Command | AUDIT_COMMAND_PHASE.md |
| Battle-shock tests (below-half-strength, 2D6 vs Ld, flag apply/clear) | Command | AUDIT_COMMAND_PHASE.md |
| Insane Bravery stratagem | Command | AUDIT_COMMAND_PHASE.md |
| Stratagem system (StratagemManager.gd) | All | AUDIT_COMMAND_PHASE.md |
| Unit coherency enforcement (all movement paths) | Movement | MOVEMENT_PHASE_AUDIT.md |
| Reinforcements/Deep Strike/Strategic Reserves | Movement/Deployment | MOVEMENT_PHASE_AUDIT.md, DEPLOYMENT_AUDIT.md |
| FLY keyword (Desperate Escape skip) | Movement | MOVEMENT_PHASE_AUDIT.md |
| TITANIC keyword (Desperate Escape skip) | Movement | MOVEMENT_PHASE_AUDIT.md |
| Path-through-enemy validation | Movement | MOVEMENT_PHASE_AUDIT.md |
| Board edge enforcement | Movement | MOVEMENT_PHASE_AUDIT.md |
| Infiltrators deployment ability | Deployment | DEPLOYMENT_AUDIT.md, MOVEMENT_PHASE_AUDIT.md |
| Targeting units in engagement with friendlies | Shooting | SHOOTING_PHASE_AUDIT.md |
| Variable attacks and damage rolling | Shooting/Fight | SHOOTING_PHASE_AUDIT.md |
| ANTI-[KEYWORD] X+ weapon keyword | Shooting/Fight | SHOOTING_PHASE_AUDIT.md |
| IGNORES COVER weapon keyword | Shooting | SHOOTING_PHASE_AUDIT.md |
| Battle-shocked units cannot shoot | Shooting | SHOOTING_PHASE_AUDIT.md |
| Overwatch stratagem (definition exists) | Shooting/Charge | SHOOTING_PHASE_AUDIT.md, CHARGE_PHASE_AUDIT.md |
| "Has been charged" flag on targets | Charge | CHARGE_PHASE_AUDIT.md |
| Per-model fight eligibility (ER + base-contact chain) | Fight | FIGHT_PHASE_AUDIT.md |
| Melee weapon abilities (Lethal Hits, Sustained Hits, Devastating Wounds) | Fight | FIGHT_PHASE_AUDIT.md |
| Variable attacks/damage in melee | Fight | FIGHT_PHASE_AUDIT.md |
| Invulnerable saves in melee | Fight | FIGHT_PHASE_AUDIT.md |
| Critical hit tracking in melee | Fight | FIGHT_PHASE_AUDIT.md |
| Deployment coherency enforcement | Deployment | DEPLOYMENT_AUDIT.md |
| Toast notifications system | Deployment | DEPLOYMENT_AUDIT.md |
| Deployment progress indicator | Deployment | DEPLOYMENT_AUDIT.md |
| Multi-model movement (Ctrl+click, drag-box, group move) | Movement | IMPLEMENTATION_VALIDATION.md |
| Double advance dice roll fix | Movement | MOVEMENT_PHASE_AUDIT.md |
| T6-4: Multiplayer test infrastructure (sync, latency, disconnect tests) | Testing | MASTER_AUDIT.md §Tier 6 |
| [MH-BUG-2] Twin-linked re-rolls wounds not hits | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T1-3: Wound roll modifier system (+1/-1 cap) | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Tier 2 |
| T5-MP5: Dice log visibility sync to remote player (resolution_start, weapon_progress blocks in broadcast + controller handler) | Shooting | SHOOTING_PHASE_AUDIT.md §3.4 |
| T5-MP4: Save dialog timing reliability for defender on remote client (ack/retry/timeout) | Shooting | SHOOTING_PHASE_AUDIT.md §3.3 |
| T1-1: Melta X weapon keyword — bonus damage at half range | Shooting | SHOOTING_PHASE_AUDIT.md §2.3 |
| T1-2: Twin-linked weapon keyword — re-roll wound rolls | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §2.3 |
| T1-4: Morale Phase 10e overhaul — replaced 9e stub with proper bookkeeping phase | Morale | MASTER_AUDIT.md §Tier 1 |
| T1-5: Pile-in must end with unit in engagement range | Fight | FIGHT_PHASE_AUDIT.md §2.2 |
| T1-8: Failed charge measurement divergence (client vs server) — unified to inches | Charge | CHARGE_PHASE_AUDIT.md §2.5 |
| T1-9: [MH-BUG-1] Mathhammer damage extraction — wound delta computation + double-count fix | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T1-7: Base-to-base contact enforcement in charge — B2B validation with tolerance | Charge | CHARGE_PHASE_AUDIT.md §2.4 |
| T1-6: Base-to-base contact enforcement in pile-in/consolidation | Fight | FIGHT_PHASE_AUDIT.md §2.3 |
| T2-1: Stealth ability — -1 to hit for ranged attacks | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 2 |
| T2-2: Lone Operative — 12" targeting restriction | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 2 |
| T2-3: Hazardous weapon keyword — mortal wounds on roll of 1 | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Tier 2 |
| T2-4: Indirect Fire weapon keyword — LoS skip, -1 to hit, 1-3 auto-fail, cover | Shooting | SHOOTING_PHASE_AUDIT.md §Tier 2 |
| T2-6: Consolidation into new enemies triggers new fights | Fight | FIGHT_PHASE_AUDIT.md §2.4 |
| T2-8: Terrain interaction during charges — vertical distance penalty + FLY diagonal | Charge | CHARGE_PHASE_AUDIT.md §2.6 |
| T2-10: Cover determination supports all terrain types (ruins, woods, craters, obstacles, barricades) | Shooting | SHOOTING_PHASE_AUDIT.md §2.9 |
| T2-11: Devastating Wounds — mortal wound spillover verified and melee path fixed | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §2.10 |
| T2-12: active_moves dictionary synced via GameState flags for multiplayer | Movement | MOVEMENT_PHASE_AUDIT.md §3.1 |
| T2-15: [MH-RULE-10] FNP toggle integration with simulation | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T2-16: [MH-RULE-12] No melee combat support in Mathhammer | Mathhammer/Fight | MASTER_AUDIT.md §MATHHAMMER |
| T3-1: Fights Last subphase not processed | Fight | FIGHT_PHASE_AUDIT.md §2.6 |
| T3-2: Fights First + Fights Last cancellation | Fight | FIGHT_PHASE_AUDIT.md §2.7 |
| T3-5: Scout moves — pre-game Scout phase with validation | Pre-game | DEPLOYMENT_AUDIT.md §5, MOVEMENT_PHASE_AUDIT.md §2.8 |
| T3-8: Charge move direction constraint — each model must end closer to a target | Charge | CHARGE_PHASE_AUDIT.md §2.9 |
| T3-9: Barricade engagement range (2" instead of 1") | Charge/Fight | CHARGE_PHASE_AUDIT.md §2.8 |
| T3-10: Faction abilities (Oath of Moment, etc.) | Command | AUDIT_COMMAND_PHASE.md §2.4 |
| T2-5: Pistol mutual exclusivity — cannot fire both Pistol and non-Pistol weapons | Shooting | SHOOTING_PHASE_AUDIT.md §2.11 |
| T2-7: Heroic Intervention — 2CP stratagem for counter-charging during opponent's charge phase | Fight/Charge | FIGHT_PHASE_AUDIT.md §2.5, CHARGE_PHASE_AUDIT.md §2.2 |
| T2-9: AIRCRAFT restriction — not checked in charge | Charge | CHARGE_PHASE_AUDIT.md §2.7 |
| T2-13: [MH-BUG-3] Anti-keyword modifier uses wrong mechanic — critical wound threshold override | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T2-14: [MH-RULE-9] Invulnerable save toggle/override for Mathhammer | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-3: Extra Attacks weapon ability — auto-include in assignments | Fight/Shooting | FIGHT_PHASE_AUDIT.md §2.8, SHOOTING_PHASE_AUDIT.md §Tier 4 |
| T3-4: Precision weapon keyword — allocate wounds to Characters | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Tier 3 |
| T3-6: Pre-battle formations declaration | Deployment | DEPLOYMENT_AUDIT.md §1 |
| T3-7: Determine first turn roll-off — RollOffPhase with D6 roll, tie re-rolls, winner choice | Post-deployment | DEPLOYMENT_AUDIT.md §6 |
| T3-11: Overwatch integration into charge/movement phases — reaction windows + shooting resolution | Charge/Movement | CHARGE_PHASE_AUDIT.md §2.1, MOVEMENT_PHASE_AUDIT.md §2.10 |
| T3-12: Multiplayer race condition in fight dialog sequencing — atomic batch action | Fight | FIGHT_PHASE_AUDIT.md §3.3 |
| T3-18: FLY units ignore terrain elevation during movement | Movement | MOVEMENT_PHASE_AUDIT.md §2.3 |
| T3-19: Terrain height handling in LoS — medium/low terrain height-aware blocking | Shooting (LoS) | MASTER_AUDIT.md §Tier 3 |
| T3-20: Rapid Fire toggle adds +X instead of doubling | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-21: Torrent weapons (auto-hit) toggle in Mathhammer simulation | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-22: Blast attack bonus auto-calculated from defender model count | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-23: Full re-roll support for hits and wounds (re-roll 1s, re-roll all failed) | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-25: Simulation runs on background thread to avoid freezing UI | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T3-26: Styled panel background is empty (visual bug) — content_vbox kept inside PanelContainer | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-1: Lance weapon keyword (+1 wound on charge) | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Tier 4 |
| T4-3: Counter-Offensive stratagem (2 CP, fight next after enemy fought) | Fight | FIGHT_PHASE_AUDIT.md §2.9 |
| T4-4: Aircraft restrictions in fight phase — AIRCRAFT/FLY keyword checks | Fight | FIGHT_PHASE_AUDIT.md §2.10 |
| T4-5: Models in base contact should not move during pile-in/consolidation | Fight | FIGHT_PHASE_AUDIT.md §2.11 |
| T4-7: Rapid Ingress stratagem (1 CP, arrive from reserves at end of opponent's movement) | Movement | MOVEMENT_PHASE_AUDIT.md §2.11 |
| T4-8: Secondary missions + New Orders stratagem | Command | AUDIT_COMMAND_PHASE.md §P3 |
| T4-9: Deployment map variety (Hammer and Anvil, Search and Destroy, etc.) | Deployment | DEPLOYMENT_AUDIT.md §7 |
| T4-10: Mission selection variety — 9 primary missions from Chapter Approved 2025-26 | Pre-game | DEPLOYMENT_AUDIT.md §8 |
| T4-11: Fortification deployment — cannot place in reserves, must deploy on table | Deployment | DEPLOYMENT_AUDIT.md §9 |
| T4-12: Unmodified wound roll of 1 always fails (defensive check) | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §2.12 |
| T4-13: Unmodified save roll of 1 always fails (auto-resolve path) | Shooting | SHOOTING_PHASE_AUDIT.md §2.13 |
| T4-14: Weapon ID collision for similar weapon names — type-aware IDs | Shooting | SHOOTING_PHASE_AUDIT.md §Additional Issues |
| T4-15: Single weapon result dialog has hardcoded zeros — stored hit/wound data in resolution_state | Shooting | SHOOTING_PHASE_AUDIT.md §Additional Issues |
| T4-16: [MH-RULE-6] Conversion X+ — expanded crit hit range at 12"+ distance | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-17: [MH-RULE-7] Half Damage — halve incoming damage (round up) defensive ability | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-18: [MH-RULE-14] Save modifier cap — +1/-1 save roll toggles with cap enforcement | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-19: [MH-BUG-6] Triple 'h' typo in Mathhammer class names — renamed to MathhammerUI/Results/RuleModifiers | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T6-1: Fix broken test compilation errors — BaseUITest created, autoload resolution fixed | Testing | TESTING_AUDIT_SUMMARY.md, PRPs/gh_issue_93_testing-audit.md |
| T6-5: CI/CD integration — all-branch triggers, correct test dirs, action version updates, timeouts | Testing | MASTER_AUDIT.md §Tier 6 |
| T6-2: Validate all existing tests and document status — 1234 tests validated, 6 compile fixes, 1 runtime fix | Testing | TESTING_AUDIT_SUMMARY.md, TEST_VALIDATION_REPORT.md |
| T7-35: AI Rapid Ingress stratagem usage — evaluate_rapid_ingress() + signal handler in AIPlayer | Movement/AI | AI_AUDIT.md §AI-GAP-3 Phase 3 |

---

## MATHHAMMER MODULE AUDIT

> **Audit date:** 2026-02-16
> **Files audited:** `Mathhammer.gd`, `MathhammerUI.gd`, `MathhammerResults.gd`, `MathhammerRuleModifiers.gd`, `RulesEngine.gd` (combat resolution paths)
> **Compared against:** Warhammer 40k 10th Edition Core Rules (wahapedia.ru), UnitCrunch, Adept Roll, Tactical Cogitator, open-source mathhammer tools (Stathammer, cogpunk/mathhammer, daed/mathhammer)

### Architecture Overview
The Mathhammer module uses Monte Carlo simulation (10,000 trials default) that delegates to the existing `RulesEngine.resolve_shoot()` for each trial. This is a solid approach — it guarantees consistency with actual gameplay resolution and naturally handles complex rule interactions. The `MathhammerResults.gd` provides advanced statistical analysis (confidence intervals, skewness, kurtosis, entropy) which exceeds what most community tools offer.

### Key Strengths
- Monte Carlo approach reusing the real RulesEngine — ensures simulation matches gameplay
- Configurable trial count (100–100,000)
- Per-weapon breakdown stats (hit rate, wound rate, unsaved rate)
- Advanced statistical analysis (confidence intervals, efficiency metrics, tactical recommendations)
- Seeded RNG for reproducible results

### Critical Issues Found
Items prefixed with **MH-** are Mathhammer-specific. They are also cross-referenced into the tiered list below.

| ID | Severity | Issue | File:Line |
|----|----------|-------|-----------|
| MH-BUG-1 | ~~**CRITICAL**~~ **DONE** | ~~`_extract_damage_from_result()` only counts model kills as 1 damage each — ignores actual wound deltas. A lascannon dealing 6 damage to a 12W vehicle counts as 0 damage if not killed.~~ Fixed: computes wound deltas from diffs with double-count prevention. | `Mathhammer.gd:239-254` |
| MH-BUG-2 | ~~**HIGH**~~ **DONE** | ~~Twin-linked toggle described as "Re-roll failed hits" but 10e Twin-linked re-rolls **wound** rolls, not hit rolls. The `_apply_twin_linked()` sets `reroll_hits` flag.~~ Fixed: moved to WOUND_MODIFIER, sets `reroll_wounds`, wound re-roll logic added to RulesEngine. | `MathhammerRuleModifiers.gd`, `RulesEngine.gd`, `Mathhammer.gd` |
| MH-BUG-3 | ~~**HIGH**~~ **DONE** | ~~Anti-keyword toggles described as "Re-roll wounds vs KEYWORD" but 10e Anti-X lowers the **critical wound threshold** (e.g., Anti-Vehicle 4+ means crits on 4+ to wound). Implementation sets `anti_keywords` without a threshold.~~ Fixed: Anti-keyword rules now include threshold parameter, inject text into weapon special_rules so RulesEngine's existing critical wound threshold logic picks it up. UI toggles added. | `MathhammerRuleModifiers.gd`, `Mathhammer.gd`, `MathhammerUI.gd` |
| MH-BUG-4 | **MEDIUM** | Rapid Fire toggle doubles all attacks (`attacks * 2`) but 10e Rapid Fire X adds only +X attacks, not double. Rapid Fire 1 on a 2-attack weapon = 3 attacks, not 4. | `Mathhammer.gd:188-189` |
| MH-BUG-5 | ~~**MEDIUM**~~ **DONE** | ~~`create_styled_panel()` removes `content_vbox` from its parent (lines 954-957), making the styled panel's PanelContainer an empty visual shell. Children added to the returned VBox appear outside the styled background.~~ Fixed: function now returns `panel_container` with full node tree intact; callers use `get_meta("content_vbox")` to add content inside the styled background. | `MathhammerUI.gd:1162-1202` |
| MH-BUG-6 | ~~**LOW**~~ **DONE** | ~~Class name typo — triple 'h': `MathhammerUI`, `MathhammerResults`, `MathhammerRuleModifiers`. Inconsistent with `Mathhammer.gd` (double 'h').~~ Fixed: renamed all three files and updated all class_name declarations, references, and project.godot paths to use double-h (`MathhammerUI`, `MathhammerResults`, `MathhammerRuleModifiers`). | All Mathhammer files |

### Missing Rules / Modifiers (not in simulation toggle system)

| ID | Rule | 10e Description | Priority |
|----|------|-----------------|----------|
| MH-RULE-1 | Melta X | +X Damage at half range | HIGH — see T1-1 |
| MH-RULE-2 | Lance | +1 to wound if charged | MEDIUM — see T4-1 |
| MH-RULE-3 | Indirect Fire | -1 to hit, unmod 1-3 fail, target gains cover | MEDIUM — see T2-4 |
| MH-RULE-4 | Hazardous | D6 per weapon after attacking; 1 = 3MW to bearer | MEDIUM — see T2-3 |
| MH-RULE-5 | Torrent | Auto-hit (no hit roll) | MEDIUM |
| MH-RULE-6 | ~~Conversion X+~~ **DONE** | ~~Expanded crit hit range at 12"+~~ Implemented: `get_critical_hit_threshold()` with distance check + Mathhammer toggle | ~~LOW~~ |
| MH-RULE-7 | ~~Half Damage~~ **DONE** | ~~Halve incoming damage (round up)~~ Implemented: `apply_half_damage()` with round-up + Mathhammer toggle | ~~LOW~~ |
| MH-RULE-8 | Stealth | Always has Benefit of Cover | LOW — see T2-1 |
| MH-RULE-9 | Invulnerable Save toggle | UI needs invuln save override input for defender | HIGH |
| MH-RULE-10 | ~~FNP toggle integration~~ **DONE** | ~~FNP exists in RulesEngine but Mathhammer toggles don't pass threshold to RulesEngine board state~~ Fixed: FNP toggles added to UI and propagated to trial board state | ~~HIGH~~ |
| MH-RULE-11 | Blast | +1 attack per 5 defender models — Mathhammer UI doesn't auto-calculate from defender model count | MEDIUM |
| MH-RULE-12 | Melee support | Mathhammer only supports shooting phase; no WS input, no Lance/charge conditions | HIGH |
| MH-RULE-13 | Re-roll wound rolls (generic) | Only re-roll hit 1s exists; no re-roll wounds, re-roll all failed hits/wounds | MEDIUM |
| MH-RULE-14 | ~~Save modifier cap~~ **DONE** | ~~Saves can be worsened by more than -1 (AP stacks fully) but cannot be improved by more than +1~~ Added ±1 save roll toggles with cap enforcement in all save resolution paths | ~~LOW~~ |

### Missing Features vs Community Tools

| ID | Feature | Available In | Priority |
|----|---------|-------------|----------|
| MH-FEAT-1 | Visual histogram / probability distribution chart | UnitCrunch, Adept Roll, Tactical Cogitator | HIGH |
| MH-FEAT-2 | Cumulative probability display ("X% chance of at least N damage") | UnitCrunch, Adept Roll | HIGH |
| MH-FEAT-3 | Multi-weapon side-by-side comparison | Tactical Cogitator, UnitCrunch | MEDIUM |
| MH-FEAT-4 | Damage per point (points efficiency) | Adept Roll, Cogitator40k | MEDIUM |
| MH-FEAT-5 | Swap attacker/defender button | Adept Roll | LOW |
| MH-FEAT-6 | Defender stats input (custom T/Sv/W/Invuln/FNP override) | All community tools | HIGH |
| MH-FEAT-7 | Variable damage notation display (show D6, D3+3 in UI) | UnitCrunch, MathHammer8th | LOW |
| MH-FEAT-8 | Quick-run on hover (expected damage preview) | UnitCrunch | LOW — **DONE** (T5-UX1) |
| MH-FEAT-9 | Auto-detect weapon abilities from datasheet | UnitCrunch (import), Adept Roll (screenshot) | MEDIUM |
| MH-FEAT-10 | Multi-target comparison matrix | Cogitator40k | LOW — **DONE** (T5-MH12) |
| MH-FEAT-11 | Simulation runs on background thread (async) | Standard practice | MEDIUM |

### UI / Visual Issues

| ID | Issue | Priority |
|----|-------|----------|
| MH-UI-1 | Histogram display is a TODO placeholder — `_draw_simple_histogram()` creates text-based bars but is never called from the main display path | HIGH — see T5-V15 — **DONE** |
| MH-UI-2 | Hardcoded 800px min height + 400x600 scroll container — doesn't adapt to screen size or browser viewport | MEDIUM |
| MH-UI-3 | No loading indicator during simulation — 10,000 trials blocks the main thread; UI shows "Running..." text only | MEDIUM |
| MH-UI-4 | ~70 debug print statements in `MathhammerUI.gd` — excessive logging in the UI layer (per project rules, keep debug logs but these are mostly state-debugging noise) | LOW |
| MH-UI-5 | OptionButton for defender but spinbox rows for attackers — inconsistent selection paradigms | LOW |
| MH-UI-6 | No color coding for good/bad results (e.g., green for high kill prob, red for low efficiency) | LOW |
| MH-UI-7 | Results are duplicated — `_create_detailed_results_display()` adds to `summary_panel`, then `_populate_breakdown_panel()` adds identical stats to `breakdown_panel` | MEDIUM |
| MH-UI-8 | No "Clear Results" or "Reset" button | LOW |

---

## TIER 1 — CRITICAL: Core Rules Compliance (Blocking Accurate Games)

These items cause incorrect game outcomes. They should be fixed before any competitive or serious playtesting.

### T1-1. Melta X weapon keyword — bonus damage at half range — **DONE**
- **Phase:** Shooting
- **Rule:** MELTA X adds +X to Damage when target is within half range
- **Impact:** Core anti-vehicle weapon type (Multi-melta, Meltagun) doesn't function correctly
- **Source:** SHOOTING_PHASE_AUDIT.md §2.3
- **Files:** `RulesEngine.gd` — damage application, range checking (can reference `count_models_in_half_range()`)
- **Resolution:** Added `get_melta_value()` and `is_melta_weapon()` helpers. Modified both interactive (`prepare_save_resolution` → `apply_save_damage`) and auto-resolve (`_resolve_assignment`) paths to add +X damage when attacking models are within half weapon range. Proportional melta allocation when only some models are in half range. Added meltagun/multi-melta weapon profiles and 17 unit tests.

### T1-2. Twin-linked weapon keyword — re-roll wound rolls — **DONE**
- **Phase:** Shooting/Fight
- **Rule:** Re-roll all failed wound rolls
- **Impact:** Common keyword across many weapon profiles
- **Source:** SHOOTING_PHASE_AUDIT.md §2.3
- **Files:** `RulesEngine.gd` — wound roll logic (~lines 700-733)
- **Resolution:** `WoundModifier.REROLL_FAILED` flag and `has_twin_linked()` helper detect Twin-linked from both keyword arrays and special_rules strings (case-insensitive). Wound re-rolls integrated into all three resolution paths (interactive shooting, auto-resolve shooting, melee). Re-rolls happen before modifiers per 10e rules. Added twin-linked test weapon profiles and 21 unit tests (has_twin_linked detection, apply_wound_modifiers re-roll logic, statistical validation, modifier interactions).

### T1-3. Wound roll modifier system (+1/-1 cap) — **DONE**
- **Phase:** Shooting/Fight
- **Rule:** Wound rolls can have modifiers capped at net +1/-1. Unmodified 1 always fails.
- **Impact:** Infrastructure needed for Twin-linked, Lance, and many unit abilities
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — create WoundModifier system near existing HitModifier (~lines 349-378)
- **Resolution:** Added `WoundModifier` enum and `apply_wound_modifiers()` function mirroring the existing `HitModifier` system. Integrated into all three wound roll paths (interactive shooting, auto-resolve shooting, melee). Modifiers capped at net +1/-1, unmodified 1 always fails, re-rolls before modifiers per 10e rules. Twin-linked re-rolls migrated to modifier system. Added `is_lance_weapon()` helper and Lance keyword integration (+1 to wound on charge).

### T1-4. Morale Phase — stub implementation, model removal missing — **DONE**
- **Phase:** Morale
- **Rule:** Battle-shocked units in 10e don't take a separate Morale test, but the Morale phase is where you check if Battle-shock is still active. The current implementation is a 9th-edition style stub that doesn't match 10e rules.
- **Impact:** Morale casualties are recorded but models are not actually removed
- **Source:** Code TODO in `MoralePhase.gd:164-165`, `MoralePhase.gd:7-8`
- **Files:** `MoralePhase.gd` — `_process_morale_failure()`, entire phase needs 10e overhaul
- **Resolution:** Overhauled MoralePhase.gd to match 10th edition rules. Removed all 9th-edition mechanics (casualties+D6 morale tests, model removal, FEARLESS/ATSKNF skip logic, morale modifiers). In 10e, Battle-shock tests happen in the Command Phase (already implemented in CommandPhase.gd), and the Morale Phase is a bookkeeping pass-through that logs battle-shocked unit status and auto-completes. Updated test_battle_shock.gd tests to verify 10e behavior. All 79 tests pass.

### T1-5. Pile-in must end with unit in engagement range — **DONE**
- **Phase:** Fight
- **Rule:** After pile-in, at least one model must be within 1" of an enemy. If impossible, no pile-in.
- **Impact:** Invalid pile-in positions accepted; unit could "pile in" away from engagement
- **Source:** FIGHT_PHASE_AUDIT.md §2.2
- **Files:** `FightPhase.gd` — `_validate_pile_in()` needs final unit-level ER check
- **Resolution:** Added unit-level engagement range check to `_validate_pile_in()` in FightPhase.gd. After all per-model movement validations (3" limit, toward closest enemy, coherency, no overlaps), the validator now calls `_can_unit_maintain_engagement_after_movement()` to verify at least one model ends within 1" of an enemy. Reuses the existing shape-aware engagement range check already used by consolidation validation.

### T1-6. Base-to-base contact enforcement in pile-in/consolidation — **DONE**
- **Phase:** Fight
- **Rule:** Models must end in base-to-base contact with closest enemy *if possible*
- **Impact:** Players can avoid base contact for positional advantage
- **Source:** FIGHT_PHASE_AUDIT.md §2.3
- **Files:** `FightPhase.gd` — PileIn/Consolidate validation
- **Resolution:** Added `_validate_base_to_base_if_possible()` to FightPhase.gd, called from both `_validate_pile_in()` and `_validate_consolidate_engagement_range()`. For each moved model, finds the closest enemy (edge-to-edge), checks if b2b is reachable within the 3" move limit, and rejects placements that stop short when b2b was achievable. Uses `BASE_CONTACT_TOLERANCE_INCHES` (0.25") for digital positioning tolerance and a small reachability tolerance (0.05") for floating-point precision. Comprehensive test suite in `test_pile_in_b2b_enforcement.gd` (10 tests covering valid b2b, unreachable, boundary, multi-model, dead models, and stationary models).

### T1-7. Base-to-base contact enforcement in charge — **DONE**
- **Phase:** Charge
- **Rule:** If a charging model can end in B2B with an enemy, it must
- **Impact:** Rules violation allowing positional advantage
- **Source:** CHARGE_PHASE_AUDIT.md §2.4
- **Files:** `ChargePhase.gd:971-1038`, `RulesEngine.gd:3523-3583`
- **Resolution:** Replaced the stub with real B2B enforcement logic. For each charging model, the validator checks whether it could reach base-to-base contact (straight-line distance ≤ rolled distance) and whether its final position achieves B2B (within 0.25" tolerance). If reachable but not achieved, a validation error is raised. Implemented consistently in both ChargePhase (interactive) and RulesEngine (auto-resolve) paths. 7 unit tests (17 assertions) verify all cases: valid B2B, missing B2B, unreachable targets, mixed models, dead targets, empty paths, and tolerance edge case.

### T1-8. Failed charge measurement divergence (client vs server) — **DONE**
- **Phase:** Charge
- **Rule:** Charge success/failure must be deterministic
- **Impact:** Client uses pixel measurement, server uses inches — potential desync
- **Source:** CHARGE_PHASE_AUDIT.md §2.5
- **Files:** `ChargeController.gd:790-831` vs `ChargePhase.gd:359`
- **Resolution:** Unified `ChargeController._is_charge_successful()` to use `Measurement.model_to_model_distance_inches()` (same as `ChargePhase._is_charge_roll_sufficient()`), eliminating pixel/inch conversion divergence. Both paths now compute edge-to-edge distance in inches and compare against rolled distance minus 1" engagement range.

### T1-9. [MH-BUG-1] Mathhammer damage extraction is fundamentally broken — **DONE**
- **Phase:** Mathhammer
- **Rule:** Damage dealt should equal wound points removed from defender models
- **Impact:** ~~`_extract_damage_from_result()` only counts model kills as 1 damage each. A lascannon dealing 6 damage to a 12W vehicle that doesn't die counts as 0 damage. Average damage, kill probability, efficiency — all output is wrong.~~ Fixed
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd:239-254`
- **Resolution:** Rewrote `_extract_damage_from_result()` to compute actual wound deltas (old_wounds − new_wounds) from `.current_wounds` diffs, reading pre-combat wounds from the trial board. Added `_get_wounds_from_board_by_path()` helper to look up model wounds from diff paths. Also tracks per-path wound values so multiple diffs on the same model (e.g. devastating wounds then failed save damage) don't double-count. Added 9 unit tests in `test_mathhammer_damage_extraction.gd`.

### T1-10. ~~[MH-BUG-2] Twin-linked modifier re-rolls hits instead of wounds~~ **DONE**
- **Phase:** Mathhammer
- **Rule:** 10e Twin-linked re-rolls all failed **wound** rolls, not hit rolls
- **Impact:** ~~Simulation applies wrong re-roll, inflating hit rates while ignoring wound re-rolls~~ Fixed
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerRuleModifiers.gd`, `MathhammerUI.gd`, `RulesEngine.gd`, `Mathhammer.gd`
- **Resolution:** Fixed `_apply_twin_linked()` to set `reroll_wounds` instead of `reroll_hits`. Moved twin-linked from HIT_MODIFIER to WOUND_MODIFIER category. Added `has_twin_linked()` keyword detection and wound re-roll logic to all three RulesEngine wound roll paths (interactive, auto-resolve, melee). Wired twin-linked toggle through Mathhammer simulation pipeline to RulesEngine assignments.

---

## TIER 2 — HIGH: Important Defensive & Gameplay Rules

These affect gameplay balance and tactical options significantly.

### T2-1. Stealth ability — -1 to hit for ranged attacks — **DONE**
- **Phase:** Shooting
- **Rule:** If all models in a unit have Stealth, ranged attacks targeting it get -1 to hit
- **Impact:** Many units rely on this for survivability (currently only implemented via Smokescreen stratagem, not as base ability)
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — hit modifier section in `_resolve_assignment_until_wounds()` (~lines 591-601)
- **Resolution:** Added `has_stealth_ability()` static function to detect Stealth in unit abilities (string or dict format, case-insensitive). Updated both `_resolve_assignment_until_wounds()` and `_resolve_assignment()` hit modifier sections to apply -1 to hit when target has Stealth ability (in addition to existing Smokescreen stratagem check). Stealth correctly only applies to ranged attacks, not melee.

### T2-2. Lone Operative — 12" targeting restriction — **DONE**
- **Phase:** Shooting
- **Rule:** Lone Operative units can only be targeted from within 12" unless attached
- **Impact:** Key survivability rule for standalone characters
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — `get_eligible_targets()`, `validate_shoot()`
- **Resolution:** Added `has_lone_operative()` static function to detect the Lone Operative ability (string or dict format, case-insensitive). Updated `get_eligible_targets()` to skip Lone Operative targets beyond 12" (unless the unit has attached characters, meaning it's leading a squad). Updated `validate_shoot()` with matching validation error. Distance check uses existing `_get_min_distance_to_target_rules()` for shape-aware edge-to-edge measurement.

### T2-3. Hazardous weapon keyword — mortal wounds on roll of 1 — **DONE**
- **Phase:** Shooting
- **Rule:** After attacking, roll D6 per Hazardous weapon; on 1, bearer takes 3 MW
- **Impact:** Affects all plasma weapons (common across many armies)
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd`, `ShootingPhase.gd` — post-attack resolution
- **Resolution:** Added `is_hazardous_weapon()` to detect HAZARDOUS keyword from both `keywords` array and `special_rules` string (case-insensitive). Added `resolve_hazardous_check()` which rolls D6 per model that fired; on 1, CHARACTER/VEHICLE/MONSTER takes 3 mortal wounds via `apply_mortal_wounds()`, other models are slain. Integrated into `resolve_shoot()` (auto-resolve), `resolve_shoot_until_wounds()` (interactive path with deferred post-save resolution), and `resolve_melee_attacks()` (fight phase). ShootingPhase.gd handles hazardous checks in all code paths: miss path, AI path, interactive post-save path, and sequential weapon resolution. Test weapons (`hazardous_plasma`, `hazardous_rapid_fire`) and comprehensive unit tests added.

### T2-4. Indirect Fire weapon keyword — **DONE**
- **Phase:** Shooting
- **Rule:** Can shoot without LoS; -1 to hit, unmodified 1-3 always fail, target gains cover
- **Impact:** Key for artillery units
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — `validate_shoot()`, `get_eligible_targets()`, hit roll logic, cover
- **Resolution:** Added `has_indirect_fire()` checker function. Modified `_check_target_visibility()` to skip LoS check (range-only) for Indirect Fire weapons. Applied -1 hit modifier and unmodified 1-3 auto-fail in both `_resolve_assignment_until_wounds()` and `_resolve_assignment()`. Granted automatic Benefit of Cover in both auto-resolve and interactive (`prepare_save_resolution`) save paths. Ignores Cover correctly overrides Indirect Fire cover. Added indirect_mortar and indirect_basic test weapon profiles and 17 unit tests.

### T2-5. Pistol mutual exclusivity — **DONE**
- **Phase:** Shooting
- **Rule:** Cannot fire both Pistol and non-Pistol weapons on same model
- **Impact:** Rules violation allowing extra firepower
- **Source:** SHOOTING_PHASE_AUDIT.md §2.11
- **Files:** `ShootingPhase.gd` — `_validate_assign_target()` (~lines 180-211)
- **Resolution:** Added pistol mutual exclusivity validation in both `RulesEngine.validate_shoot()` (cross-assignment check after individual validation) and `ShootingPhase._validate_assign_target()` (early check against pending assignments). Per 10e rules, a unit must choose to fire either its Pistol weapons or its non-Pistol weapons — never both. MONSTER and VEHICLE units are exempt. Added 6 unit tests covering: rejection of mixed assignments, pistol-only allowed, non-pistol-only allowed, MONSTER/VEHICLE exemption, and multiple-pistols allowed.

### T2-6. Consolidation into new enemies doesn't trigger new fights — **DONE**
- **Phase:** Fight
- **Rule:** After consolidation, newly eligible enemy units can fight back
- **Impact:** Removes major tactical risk of aggressive consolidation
- **Source:** FIGHT_PHASE_AUDIT.md §2.4
- **Files:** `FightPhase.gd` — `_process_consolidate()`, fight sequence rebuild
- **Resolution:** Added `_scan_newly_eligible_units_after_consolidation()` which runs after every consolidation move. Uses post-consolidation positions (via temporary override) to check all units not already in a fight sequence. Newly eligible units are added to `normal_sequence` (Remaining Combats). Added `_units_in_engagement_range_with_override()` helper for checking engagement with updated positions before game state snapshot refresh. 14 test cases (26 assertions) cover: new enemies added, no false positives, already-in-sequence/already-fought/dead exclusion, multi-enemy, correct player assignment, both player directions, and edge cases.

### T2-7. Heroic Intervention — not implemented — **DONE**
- **Phase:** Fight/Charge
- **Rule:** 2CP stratagem allowing CHARACTER within 6" to counter-charge
- **Impact:** Key defensive option missing for non-active player
- **Source:** FIGHT_PHASE_AUDIT.md §2.5, CHARGE_PHASE_AUDIT.md §2.2
- **Files:** `FightPhase.gd:1020-1023` (stub), StratagemManager integration
- **Resolution:** Full Heroic Intervention implementation verified across all layers: StratagemManager (2CP definition, eligibility validation within 6", VEHICLE/WALKER/battle-shocked checks), ChargePhase (trigger after successful charge, USE/DECLINE/CHARGE_ROLL/APPLY_MOVE action processing, auto 2D6 roll, heroic_intervention flag), FightPhase (HI units excluded from Fights First), HeroicInterventionDialog (UI), ChargeController (signal/dialog integration), GameManager (action routing), and NetworkManager (multiplayer signal re-emission for HI actions added). 37 tests pass.

### T2-8. Terrain interaction during charges — **DONE**
- **Phase:** Charge
- **Rule:** Charging over terrain >2" costs vertical distance against charge roll; FLY allows diagonal
- **Impact:** Charges through terrain have no distance penalty
- **Source:** CHARGE_PHASE_AUDIT.md §2.6
- **Files:** `ChargePhase.gd`, `ChargeController.gd`, `TerrainManager.gd`, `RulesEngine.gd`
- **Resolution:** Added terrain vertical distance penalty system. TerrainManager now provides `calculate_charge_terrain_penalty()` which checks path segments against terrain features. Terrain >2" adds climb up + climb down distance for non-FLY units, and diagonal measurement for FLY units. Integrated into ChargePhase path validation, ChargeController drag validation, and RulesEngine charge path validation. 14 unit tests verify all scenarios.

### T2-9. AIRCRAFT restriction — not checked in charge — **DONE**
- **Phase:** Charge
- **Rule:** AIRCRAFT cannot charge; only FLY units can charge AIRCRAFT
- **Impact:** Invalid charges allowed
- **Source:** CHARGE_PHASE_AUDIT.md §2.7
- **Files:** `ChargePhase.gd` — `_can_unit_charge()`, `_validate_declare_charge()`, `_get_eligible_targets_for_unit()`; `RulesEngine.gd` — `eligible_to_charge()`, `charge_targets_within_12()`
- **Resolution:** Added AIRCRAFT keyword check to `_can_unit_charge()` in ChargePhase.gd (blocking AIRCRAFT units from charging). Added FLY-only restriction for charging AIRCRAFT targets in `_validate_declare_charge()`, `_get_eligible_targets_for_unit()` (ChargePhase.gd), and `charge_targets_within_12()` (RulesEngine.gd). RulesEngine `eligible_to_charge()` already had the AIRCRAFT-cannot-charge check. 7 unit tests verify all scenarios.

### T2-10. Cover determination limited to ruins only — **DONE**
- **Phase:** Shooting
- **Rule:** Cover can be granted by ruins, area terrain, obstacles, woods, craters, barricades
- **Impact:** Non-ruins terrain gives no cover
- **Source:** SHOOTING_PHASE_AUDIT.md §2.9
- **Files:** `RulesEngine.gd` — `check_benefit_of_cover()` (~lines 1440-1461)
- **Resolution:** Extended `check_benefit_of_cover()` to support all cover-granting terrain types per 10e rules. Ruins/obstacles/barricades grant cover when target is within OR behind terrain. Area terrain (woods, craters, forest) grants cover only when target is within. Updated `TerrainManager._add_terrain_piece()` and JSON loader to support arbitrary terrain types. 19 new tests in `test_cover_terrain_types.gd`.

### T2-11. Devastating Wounds — mortal wound spillover needs verification — **DONE**
- **Phase:** Shooting/Fight
- **Rule:** Devastating Wounds create mortal wounds that spill over and are allocated after normal attacks
- **Impact:** Edge cases around spillover and FNP interaction
- **Source:** SHOOTING_PHASE_AUDIT.md §2.10
- **Files:** `RulesEngine.gd` — devastating wound handling (~lines 3776-3790)
- **Resolution:** Restructured melee damage application to properly separate devastating wound damage (mortal wounds with spillover via `_apply_damage_to_unit_pool`) from regular failed-save damage (per-wound, no spillover via new `_apply_damage_per_wound_no_spillover`). FNP now rolled separately for each damage category. Added helper functions `_distribute_fnp_across_wounds` and `_trim_wound_damages_to_total`. Ranged path already correct. 23 tests in `test_devastating_wounds.gd` including spillover verification.

### T2-12. active_moves dictionary not synced in multiplayer — **DONE**
- **Phase:** Movement
- **Rule:** Movement state must be consistent between host and client
- **Impact:** Potential silent desync leading to illegal moves or stuck state
- **Source:** MOVEMENT_PHASE_AUDIT.md §3.1
- **Files:** `MovementPhase.gd:20`, `NetworkManager`
- **Resolution:** Added synced `flags.movement_active` GameState flag that mirrors the local `active_moves` lifecycle. Flag set on BEGIN_NORMAL_MOVE, BEGIN_ADVANCE, BEGIN_FALL_BACK; cleared on CONFIRM_UNIT_MOVE and RESET_UNIT_MOVE. Updated `get_available_actions()` and `_validate_end_movement()` to check GameState flags (not local `active_moves.completed`). END_MOVEMENT now cleans up stale flags. Added `_check_active_moves_sync()` debug consistency checker. 33 tests in `test_active_moves_sync.gd`.

### T2-13. [MH-BUG-3] Anti-keyword modifier uses wrong mechanic — **DONE**
- **Phase:** Mathhammer
- **Rule:** Anti-[KEYWORD] X+ lowers the critical wound threshold (e.g., Anti-Vehicle 4+ = crits on wound rolls of 4+). It is NOT a wound re-roll.
- **Impact:** Simulation doesn't correctly model Anti-keyword; one of the most impactful offensive abilities in 10e
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerRuleModifiers.gd:77-83,296-299` — needs threshold parameter and crit wound threshold override
- **Resolution:** Rewrote Anti-keyword rule definitions with threshold parameter (e.g., Anti-Infantry 4+, Anti-Vehicle 4+, Anti-Monster 4+). Changed `_apply_anti_keyword()` from setting `anti_keywords` (re-roll mechanic) to storing anti-keyword entries with keyword+threshold. Mathhammer now injects anti-keyword text (e.g., "Anti-Infantry 4+") into weapon `special_rules` in the trial board state, so RulesEngine's existing `get_anti_keyword_data()` / `get_critical_wound_threshold()` correctly lowers the critical wound threshold. Added UI toggles in MathhammerUI.gd.

### T2-14. [MH-RULE-9] Mathhammer has no invulnerable save toggle/override — **DONE**
- **Phase:** Mathhammer
- **Rule:** Defender invulnerable save is a core defensive stat that determines whether AP is relevant
- **Impact:** Cannot model matchups involving invulnerable saves — a fundamental part of 40k combat math
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerUI.gd` — needs defender stat override panel; `Mathhammer.gd` — needs to pass invuln to trial board state
- **Resolution:** Added invulnerable save 2+/3+/4+/5+/6+ toggles to MathhammerUI rule toggle list. Updated `_create_trial_board_state()` with `_get_invuln_from_toggles()` to apply the selected invuln value to each defender model's `invuln` property, which RulesEngine already reads via `model.get("invuln", 0)` during save resolution. Only overrides if the toggle value is better (lower) than any existing model invuln.

### T2-15. [MH-RULE-10] FNP toggle doesn't integrate with simulation — **DONE**
- **Phase:** Mathhammer
- **Rule:** Feel No Pain is a per-wound save that dramatically reduces effective damage
- **Impact:** FNP exists in RulesEngine but the Mathhammer toggle values are not propagated to the trial board state's unit stats
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerRuleModifiers.gd:109-121`, `Mathhammer.gd:204-229` — `_create_trial_board_state()` needs to apply FNP from toggles
- **Resolution:** Added FNP 4+/5+/6+ toggles to MathhammerUI rule toggle list. Updated `_create_trial_board_state()` to accept `rule_toggles` and apply FNP threshold to the defender unit's `meta.stats.fnp`, which RulesEngine already reads via `get_unit_fnp()` during damage resolution.

### T2-16. [MH-RULE-12] No melee combat support in Mathhammer — **DONE**
- **Phase:** Mathhammer
- **Rule:** Melee uses the same attack sequence as shooting (WS instead of BS) with additional modifiers (Lance, charged condition)
- **Impact:** All community mathhammer tools support melee. Missing melee means Fight phase has no statistical preview.
- **Source:** MATHHAMMER_AUDIT, code TODO at `FightPhase.gd:947`
- **Files:** `Mathhammer.gd` — hardcoded to "shooting" phase; `MathhammerUI.gd` — needs shooting/melee toggle
- **Resolution:** Added melee combat support to Mathhammer simulation engine. `Mathhammer.gd` now branches on phase parameter to call `resolve_melee_attacks()` for fight/melee phase with proper engagement range positioning. `MathhammerUI.gd` gains a Shooting/Melee phase selector that filters weapons by type and shows phase-specific rule toggles (Lance/Charged). `FightPhase.gd` placeholder replaced with full Mathhammer simulation providing per-target damage predictions.

---

## TIER 3 — MEDIUM: Missing Rules & Polish

These are real rules gaps but affect niche situations or have workarounds.

### T3-1. Fights Last subphase not processed — **DONE**
- **Phase:** Fight
- **Rule:** Units with Fights Last fight after Remaining Combats
- **Impact:** Fights Last units placed in sequence but never activated
- **Source:** FIGHT_PHASE_AUDIT.md §2.6
- **Files:** `FightPhase.gd` — Subphase enum (add FIGHTS_LAST), `_transition_subphase()`
- **Resolution:** Added `FIGHTS_LAST` to the `Subphase` enum. Updated `_transition_subphase()` to progress FIGHTS_FIRST → REMAINING_COMBATS → FIGHTS_LAST → COMPLETE. Updated `_get_eligible_units_for_selection()`, `advance_to_next_fighter()`, `get_eligible_fighters_for_player()`, and dialog data builders to handle the new subphase. Updated `FightSelectionDialog.gd` to display Fights Last units.

### T3-2. Fights First + Fights Last cancellation — **DONE**
- **Phase:** Fight
- **Rule:** If both apply, unit fights in Remaining Combats (normal)
- **Impact:** Incorrect fight order
- **Source:** FIGHT_PHASE_AUDIT.md §2.7
- **Files:** `FightPhase.gd` — `_get_fight_priority()` (~lines 1026-1041)
- **Resolution:** Refactored `_get_fight_priority()` in both `FightPhase.gd` and `RulesEngine.gd` to collect Fights First and Fights Last conditions independently before returning a priority. When both apply, they cancel out and the unit returns NORMAL (Remaining Combats). Added debug logging for cancellation events.

### T3-3. Extra Attacks weapon ability — **DONE**
- **Phase:** Fight/Shooting
- **Rule:** Extra Attacks weapons are used IN ADDITION to normal weapon, not as alternative
- **Impact:** Players may miss using or misuse these weapons
- **Source:** FIGHT_PHASE_AUDIT.md §2.8, SHOOTING_PHASE_AUDIT.md §Tier 4
- **Files:** `AttackAssignmentDialog.gd`, `ShootingPhase.gd` — weapon assignment logic
- **Resolution:** Added `has_extra_attacks()` and `weapon_data_has_extra_attacks()` detection functions to RulesEngine.gd. Updated AttackAssignmentDialog.gd to separate Extra Attacks weapons from regular weapons in the UI — they are shown as mandatory additions and auto-included in assignments when confirmed. Added `_auto_inject_extra_attacks_weapons()` safety net in FightPhase.gd for AI/auto-resolve paths. Added parallel `_auto_inject_extra_attacks_weapons_shooting()` in ShootingPhase.gd for ranged Extra Attacks weapons. Validation prevents using Extra Attacks weapons as the only weapon choice. Added 12 unit tests.

### T3-4. Precision weapon keyword — allocate wounds to Characters — **DONE**
- **Phase:** Shooting/Fight
- **Rule:** Critical wounds from Precision weapons can be allocated to attached Characters
- **Impact:** Important for character sniping
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 3
- **Files:** `RulesEngine.gd` — wound allocation (~lines 3648-3718), `WoundAllocationOverlay.gd`
- **Resolution:** Extended `prepare_save_resolution()` with precision_data parameter. Precision wounds (capped by critical_hits count) can now be allocated to CHARACTER models even when bodyguard is alive. Updated `WoundAllocationOverlay.gd` with precision-aware model selection, PRECISION_TARGET highlight type (orange), and precision wound tracking. Updated auto-resolve path in `ShootingPhase.gd` to allocate precision wounds to character models first. Added `test_precision_keyword.gd` with 8 unit tests.

### T3-5. Scout moves — **DONE**
- **Phase:** Pre-game (between Deployment and Turn 1)
- **Rule:** Units with Scout X" can move X" after deployment, ending >9" from enemies
- **Impact:** Many army builds depend on early positioning
- **Source:** DEPLOYMENT_AUDIT.md §5, MOVEMENT_PHASE_AUDIT.md §2.8
- **Files:** New pre-game phase needed
- **Resolution:** Added SCOUT phase to Phase enum between DEPLOYMENT and COMMAND. Created ScoutPhase.gd with full movement validation (distance cap, >9" from enemies, board bounds, model overlap). Added unit_has_scout/get_scout_distance helpers to GameState.gd. Registered in PhaseManager with auto-skip when no Scout units. Added Scout 6" ability to Space Marines Infiltrator Squad. AI skips Scout moves. 27 dedicated tests pass.

### T3-6. Pre-battle formations declaration — **DONE**
- **Phase:** Deployment
- **Rule:** Before deployment, players secretly declare leader attachments, transport embarkations, and reserves
- **Impact:** Seeing opponent deployment before declaring formations is a strategic advantage
- **Source:** DEPLOYMENT_AUDIT.md §1
- **Files:** New pre-deployment configuration screen
- **Resolution:** Added FORMATIONS to Phase enum (before DEPLOYMENT). Created FormationsPhase.gd with full declaration/validation/confirmation flow for leader attachments, transport embarkations, and reserves. Added FormationsDeclarationDialog.gd UI with sections for each declaration type. Added GameState helpers (get_characters_for_player, get_transports_for_player, get_eligible_bodyguards_for_character, formations_declared, etc.). Integrated into PhaseManager, Main.gd, TurnManager, and GameManager phase flows. Phase auto-skips when no declarations possible. 28 dedicated tests pass.

### T3-7. Determine first turn roll-off — **DONE**
- **Phase:** Post-deployment
- **Rule:** Players roll off; winner chooses first or second turn
- **Impact:** Going first vs second is a major strategic decision
- **Source:** DEPLOYMENT_AUDIT.md §6
- **Files:** `TurnManager.gd` — currently hardcoded
- **Resolution:** Added `ROLL_OFF` phase to the Phase enum (between SCOUT and COMMAND). Created `RollOffPhase.gd` implementing D6 roll-off with tie re-rolls and winner's choice of first/second turn. Phase flow is now SCOUT → ROLL_OFF → COMMAND. Roll-off results and first-turn-player stored in game state meta. Active player set based on winner's choice. Attacker/Defender labels in UI now dynamically computed from roll-off result. 77 tests pass including 20 new roll-off-specific tests.

### T3-8. Charge move direction constraint — **DONE**
- **Phase:** Charge
- **Rule:** Each model must end charge move closer to at least one charge target
- **Impact:** Models can be placed suboptimally without enforcement
- **Source:** CHARGE_PHASE_AUDIT.md §2.9
- **Files:** `ChargeController.gd:1265-1286`, `ChargePhase.gd`
- **Resolution:** Added `_validate_charge_direction_constraint()` in ChargePhase.gd (server-side), direction check in `_validate_charge_position()` in ChargeController.gd (client-side drag validation), and `_validate_charge_direction_constraint_rules()` in RulesEngine.gd (auto-resolve path). New `FAIL_DIRECTION` error category with player-facing tooltip. All three paths consistently enforce that each model must end its charge move closer (center-to-center) to at least one model in any declared target unit.

### T3-9. Barricade engagement range (2" instead of 1") — **DONE**
- **Phase:** Charge/Fight
- **Rule:** Engagement range through barricades is 2"
- **Impact:** Charges across barricades are incorrectly strict
- **Source:** CHARGE_PHASE_AUDIT.md §2.8
- **Files:** No barricade terrain type exists
- **Resolution:** Added barricade-aware engagement range system. TerrainManager now provides `is_barricade_between()` and `get_engagement_range_for_positions()` which return 2" when a barricade terrain feature lies between two model positions, 1" otherwise. Updated all engagement range checks across ChargePhase.gd (charge validation, roll sufficiency, pre-charge ER check), RulesEngine.gd (static charge validation, fight eligibility, shooting ER checks), FightPhase.gd (unit engagement range, consolidation), and MovementPhase.gd (engagement range at position). 12 new tests in `test_barricade_engagement_range.gd`.

### T3-10. Faction abilities (Oath of Moment, etc.) — **DONE**
- **Phase:** Command
- **Rule:** Many factions have Command Phase abilities (re-rolls, sticky objectives, etc.)
- **Impact:** Faction identity missing
- **Source:** AUDIT_COMMAND_PHASE.md §2.4
- **Files:** New ability trigger system, army JSON data already has text descriptions
- **Resolution:** Created `FactionAbilityManager.gd` autoload that detects faction abilities from army JSON data and manages Oath of Moment target selection. Added `SELECT_OATH_TARGET` action to CommandPhase with validation and processing. Integrated reroll-1s for both hit and wound rolls into all three RulesEngine resolution paths (interactive shooting, auto-resolve shooting, melee) when ADEPTUS ASTARTES units attack the oath target. Added UI section in CommandController for target selection with current-target display. Auto-selects first enemy unit if player forgets. Extensible design for future faction abilities. 32 unit tests in `test_faction_abilities.gd`.

### T3-11. Overwatch integration into charge/movement phases — **DONE**
- **Phase:** Charge/Movement
- **Rule:** Overwatch can be triggered during charge and movement phases by the defending player
- **Impact:** Stratagem defined but reaction window not integrated into charge/movement flows
- **Source:** CHARGE_PHASE_AUDIT.md §2.1, MOVEMENT_PHASE_AUDIT.md §2.10
- **Files:** `ChargePhase.gd`, `MovementPhase.gd`, `StratagemManager.gd`
- **Resolution:** Added `is_fire_overwatch_available()` and `get_fire_overwatch_eligible_units()` to StratagemManager with 24" range check, ranged weapon check, engagement range exclusion, and battle-shock exclusion. Integrated reaction windows into ChargePhase (after DECLARE_CHARGE, before charge roll) and MovementPhase (after CONFIRM_UNIT_MOVE). Both phases emit `fire_overwatch_opportunity` signal and support `USE_FIRE_OVERWATCH`/`DECLINE_FIRE_OVERWATCH` actions following the established Heroic Intervention pattern. Added overwatch flag to RulesEngine `_resolve_assignment` and `_resolve_assignment_until_wounds` that forces BS=7 so only unmodified 6s hit. CP deduction and once-per-turn restriction enforced via existing StratagemManager infrastructure.

### T3-12. Multiplayer race condition in fight dialog sequencing — **DONE**
- **Phase:** Fight
- **Rule:** Actions must arrive in order
- **Impact:** Fixed 50ms delays between actions may be insufficient on slow connections
- **Source:** FIGHT_PHASE_AUDIT.md §3.3
- **Files:** `FightController.gd:1357-1392`
- **Resolution:** Replaced sequential individual actions (ASSIGN_ATTACKS × N + CONFIRM + ROLL_DICE) with fixed timing delays with a single atomic BATCH_FIGHT_ACTIONS composite action processed by FightPhase. Eliminates race condition by sending one action over the network instead of multiple actions with 50ms/100ms delays.

### T3-13. Fight selection dialog sync for remote player — **DONE**
- **Phase:** Fight
- **Rule:** Both players need to see the fighter selection dialog
- **Impact:** Client may miss initial fight selection on phase entry
- **Source:** FIGHT_PHASE_AUDIT.md §3.4
- **Files:** `FightController.gd` — `set_phase()`, signal timing
- **Resolution:** Replaced fragile 0.1s timer workaround with explicit pending data retrieval pattern. FightPhase now stores dialog data in `_pending_fight_selection_data` when `_emit_fight_selection_required()` fires, and FightController retrieves it via `get_pending_fight_selection_data()` after connecting signals. Eliminates the race condition entirely.

### T3-14. Desperate Escape — Battle-shocked modifier not verified — **DONE**
- **Phase:** Movement
- **Rule:** Battle-shocked units falling back have models destroyed on 1-3 instead of 1-2
- **Impact:** Battle-shocked penalty may not be fully applied
- **Source:** AUDIT_COMMAND_PHASE.md, code inspection needed
- **Files:** `MovementPhase.gd` — `_process_desperate_escape()`
- **Resolution:** Added conditional `fail_threshold` variable in `_process_desperate_escape()` that uses 3 for battle-shocked units (fail on 1-3) vs 2 for normal units (fail on 1-2). Previously the threshold was hardcoded to `roll <= 2` for all cases, ignoring the battle-shocked penalty.

### T3-15. Disembarked units should not count as Remained Stationary — **DONE**
- **Phase:** Movement
- **Rule:** Disembarked units don't get Heavy weapon bonus even if they don't move
- **Impact:** Edge case affecting Heavy weapon accuracy
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.12
- **Files:** `MovementPhase.gd` — `_process_remain_stationary()` (~line 880)
- **Resolution:** Added `disembarked_this_phase` check in `_process_remain_stationary()`. When a unit has disembarked this phase, `remained_stationary` is set to `false` instead of `true`, preventing the Heavy weapon +1 to hit bonus. Added integration tests verifying disembarked units don't get the bonus while non-disembarked stationary units still do.

### T3-16. Difficult terrain / movement penalties — **DONE**
- **Phase:** Movement
- **Rule:** Certain terrain may apply movement penalties
- **Impact:** Affects tactical positioning around terrain
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.7
- **Files:** `MovementPhase.gd`, `TerrainManager.gd`
- **Resolution:** Added terrain traits system to TerrainManager. Terrain pieces can now have a `"traits"` array (e.g. `["difficult_ground"]`). The `"difficult_ground"` trait adds a flat 2" penalty per terrain piece crossed during movement or charges. FLY units ignore this penalty. Updated JSON layout loading, save/load, and hardcoded layout to support traits. Added woods terrain pieces with difficult_ground to layout_2. 17 passing tests cover the trait helpers, movement penalty, charge penalty, FLY bypass, cumulative penalties, and combined height+difficult ground scenarios.

### T3-17. Dual resolution paths — prevent rules drift — **DONE**
- **Phase:** Shooting
- **Rule:** Auto-resolve and interactive resolve must produce same results
- **Impact:** Keywords updated in one path but not the other
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues
- **Files:** `RulesEngine.gd` — `_resolve_assignment()` vs `_resolve_assignment_until_wounds()`
- **Resolution:** Synchronized `_resolve_assignment()` (auto-resolve) with `_resolve_assignment_until_wounds()` (interactive). Added missing Devastating Wounds tracking (critical_wound_count/regular_wound_count) to wound rolls, DW save bypass with mortal-wound-style spillover damage via `_apply_damage_to_unit_pool()`, Feel No Pain rolls for both DW and regular damage, Precision keyword tracking, and half-damage support. Auto-resolve wound dice data now includes `devastating_wounds_weapon`, `critical_wounds`, and `regular_wounds` fields matching the interactive path.

### T3-18. FLY units should ignore terrain elevation during movement — **DONE**
- **Phase:** Movement
- **Rule:** FLY keyword allows ignoring vertical distance
- **Impact:** FLY units taxed by terrain height incorrectly
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.3 (remaining work)
- **Files:** `MovementPhase.gd`, `TerrainManager.gd`
- **Resolution:** Added `calculate_movement_terrain_penalty()` to TerrainManager.gd — FLY units return 0 penalty (ignore terrain elevation entirely), non-FLY units pay height*2 for terrain >2". Added `_get_movement_terrain_penalty()` helper in MovementPhase.gd, integrated into all movement distance calculations: `_validate_set_model_dest`, `_validate_stage_model_move`, `_process_stage_model_move`, `_process_group_movement`, and `_validate_individual_move_internal`. Tests in `test_fly_movement_terrain.gd`.

### T3-19. Terrain height handling in LoS — only "tall" terrain handled — **DONE**
- **Phase:** Shooting (LoS)
- **Rule:** Medium/low terrain should be handled based on model height
- **Impact:** LoS calculations may be incorrect for non-tall terrain
- **Source:** Code TODO in `LineOfSightCalculator.gd:79`
- **Files:** `LineOfSightCalculator.gd`
- **Resolution:** Implemented height-aware LoS blocking across all four LoS systems (LineOfSightCalculator, EnhancedLineOfSight, LineOfSightManager, RulesEngine legacy path). Low terrain (<2") never blocks LoS. Tall terrain (>5") always blocks LoS (Obscuring). Medium terrain (2-5") blocks LoS only when both shooter and target are shorter than the terrain — MONSTER/VEHICLE/TITANIC models (5"+) can see and be seen over medium terrain. Added `get_model_height_inches()` helper that detects height from model keywords. 31 unit tests in `test_terrain_height_los.gd`.

### T3-20. [MH-BUG-4] Rapid Fire toggle doubles attacks instead of adding X — **DONE**
- **Phase:** Mathhammer
- **Rule:** Rapid Fire X adds +X attacks at half range (e.g., Rapid Fire 1 on 2A weapon = 3 attacks, not 4)
- **Impact:** Overstates Rapid Fire weapon output by ~33% for RF1 weapons
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd:188-189` — `attacks_override` should add RF value, not multiply by 2
- **Resolution:** Changed `attacks_override` from `base_attacks * 2` to `base_attacks + rf_value * model_count`, using `RulesEngine.get_rapid_fire_value()` to look up the weapon's actual RF X value. Fixed misleading "Double attacks" descriptions in MathhammerUI and MathhammerRuleModifiers.

### T3-21. [MH-RULE-5] Torrent weapons (auto-hit) not in simulation toggles — **DONE**
- **Phase:** Mathhammer
- **Rule:** Torrent weapons automatically hit — no hit roll made, no critical hits possible
- **Impact:** Torrent is a common ability (flamers, etc.) that changes the math significantly
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerRuleModifiers.gd` — needs Torrent toggle that bypasses hit rolls
- **Resolution:** Added Torrent toggle to MathhammerRuleModifiers (rule definition + conflict with hit modifiers), MathhammerUI (shooting-phase checkbox), and Mathhammer.gd (passes `torrent` flag through weapon assignment). Extended RulesEngine to accept `assignment.get("torrent", false)` override on all 3 combat paths (interactive shoot, auto-resolve shoot, melee). Also fixed missing `auto_hit` dice context tracking in trial stats extraction.

### T3-22. [MH-RULE-11] Blast attack bonus not auto-calculated from defender model count — **DONE**
- **Phase:** Mathhammer
- **Rule:** Blast weapons get +1 attack per 5 models in target unit; minimum 3 attacks vs 6+ model units
- **Impact:** Mathhammer has defender unit data available but doesn't auto-adjust Blast weapon attacks
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd` — `_build_shoot_action()` should check Blast keyword and adjust
- **Resolution:** Added Blast keyword auto-calculation to `_build_shoot_action()` in Mathhammer.gd. Uses existing `RulesEngine.is_blast_weapon()`, `calculate_blast_bonus()`, and `calculate_blast_minimum()` to adjust `attacks_override` based on defender model count in the trial board. Bonus stacks with Rapid Fire.

### T3-23. [MH-RULE-13] No wound re-roll support (only hit re-roll 1s exists) — **DONE**
- **Phase:** Mathhammer
- **Rule:** Many abilities grant re-roll all failed wounds, re-roll wound rolls of 1, re-roll all failed hits
- **Impact:** Re-rolls are one of the most impactful modifiers; only partial support exists
- **Source:** MATHHAMMER_AUDIT
- **Files:** `RulesEngine.gd` — only `REROLL_ONES` hit modifier exists (line 342); needs WoundModifier with re-rolls
- **Resolution:** Added `HitModifier.REROLL_FAILED` (value 8) to the enum and updated `apply_hit_modifiers()` with a `hit_threshold` parameter. Wired up `reroll_failed` flag reading in all three combat paths (resolve_shoot, auto_resolve_shoot, resolve_melee_attacks). Refactored melee hit re-rolls to use the HitModifier system. Added 4 new Mathhammer UI toggles: Re-roll 1s to Hit, Re-roll All Failed Hits, Re-roll 1s to Wound, Re-roll All Failed Wounds. Both Mathhammer `_build_shoot_action` and `_build_melee_action` now pass hit/wound re-roll modifiers from rule toggles to RulesEngine assignments.

### T3-24. [MH-FEAT-6] No defender stats override panel — **DONE**
- **Phase:** Mathhammer
- **Rule:** Users should be able to override or input custom defender T/Sv/W/Invuln/FNP
- **Impact:** Cannot model hypothetical matchups or units not in the game state
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerUI.gd` — needs custom defender input fields alongside the unit dropdown
- **Resolution:** Feature already fully implemented. MathhammerUI.gd has a "Custom Defender Stats" checkbox (line 272) that reveals a panel with SpinBox fields for Toughness, Armor Save, Wounds, Models, Invuln Save, and Feel No Pain. Auto-populates from selected defender unit. Overrides are passed via config to `Mathhammer._apply_defender_overrides()` (line 572) which modifies toughness, save, wounds per model, model count, with FNP/invuln override priority over rule toggles. Added 9 passing unit tests verifying all override paths.

### T3-25. [MH-FEAT-11] Simulation blocks main thread — **DONE**
- **Phase:** Mathhammer
- **Rule:** 10,000 Monte Carlo trials should run on a background thread to avoid freezing the UI
- **Impact:** UI is unresponsive during simulation; at 100K trials this could freeze the browser tab
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerUI.gd:673-689` — `_run_simulation_async()` is not actually async
- **Resolution:** Refactored `_run_simulation_async()` to use Godot's `Thread` class. Simulation now runs on a background thread via `_simulation_thread_func()`, with UI updates deferred to the main thread via `call_deferred("_on_simulation_completed")`. Thread is properly joined on completion and cleaned up in `_exit_tree()`.

### T3-26. [MH-BUG-5] Styled panel background is empty (visual bug) — **DONE**
- **Phase:** Mathhammer
- **Rule:** `create_styled_panel()` removes `content_vbox` from its parent PanelContainer before returning it
- **Impact:** The colored background panels in results display are empty shells; content appears outside them
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerUI.gd:953-958` — should not remove child from parent; return the panel_container and add children to the nested content_vbox
- **Resolution:** Removed the code that detached `content_vbox` from `panel_bg`. Function now returns `panel_container` (with the full node tree intact) and stores `content_vbox` reference via `set_meta()`. All three callers updated to add children to the content area via `get_meta("content_vbox")`, so content renders inside the styled background.

---

## TIER 4 — LOW: Niche Rules & Stratagems

### T4-1. Lance weapon keyword (+1 wound on charge) — **DONE**
- **Phase:** Shooting/Fight
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4
- **Depends on:** T1-3 (wound modifier system)
- **Resolution:** Enhanced `is_lance_weapon()` to detect Lance from both `keywords` array and `special_rules` string (case-insensitive), matching the pattern of other keyword detectors. Lance +1 wound modifier was already integrated into all three RulesEngine resolution paths (interactive shooting, auto-resolve shooting, melee) via the WoundModifier.PLUS_ONE flag when `charged_this_turn` is true. The `charged_this_turn` flag is set by ChargePhase on successful charges and Heroic Interventions. Added `lance_melee`, `lance_lethal`, and `lance_ranged` test weapon profiles. Updated Mathhammer to apply Lance toggle for both shooting and melee phases. Fixed duplicate function declarations in StratagemManager.gd. 25 unit tests in `test_lance_keyword.gd`.

### T4-2. One Shot weapon keyword (single use per battle)
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4

### T4-3. Counter-Offensive stratagem — **DONE**
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.9
- **Resolution:** Full implementation already existed in StratagemManager (definition, validation, CP deduction, eligibility checks), FightPhase (trigger after consolidation, USE/DECLINE actions), FightController (UI signal wiring), and CounterOffensiveDialog (UI). Fixed StratagemManager.use_stratagem() null-safety for PhaseManager in test environment. All 26 tests pass.

### T4-4. Aircraft restrictions in fight phase — **DONE**
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.10
- **Resolution:** Added AIRCRAFT/FLY keyword checks throughout fight phase: `_is_unit_in_combat()` filters Aircraft from non-FLY combat eligibility, `_get_eligible_melee_targets()` enforces Aircraft↔FLY targeting, `_find_closest_enemy_model/position()` ignores Aircraft for non-FLY units during pile-in/consolidation, `_validate_pile_in/consolidate()` blocks Aircraft from making these moves, `_find_enemies_in_engagement_range()` and `_scan_newly_eligible_units_after_consolidation()` respect Aircraft restrictions. Added matching static helpers in RulesEngine (`is_eligible_to_fight`, `fight_targets_in_engagement`, `can_unit_pile_in`, `can_unit_consolidate`). All 18 tests pass.

### T4-5. Models in base contact should not move during pile-in — **DONE**
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.11
- **Resolution:** Added proactive UI-level prevention and validation enforcement. FightController detects models already in base contact (within 0.25" tolerance) during `_enable_pile_in_mode()` and locks them from being dragged. Visual indicators (red X with "B2B" label) show locked models. FightPhase `_validate_pile_in()` and `_validate_consolidate_engagement_range()` reject movements from models already in base contact via new `_is_model_in_base_contact_with_enemy()` helper. Same rule enforced for both pile-in and consolidation. PileInDialog info updated. Test file added: `test_pile_in_base_contact_locked.gd` (10 tests).

### T4-6. Go to Ground / Smokescreen stratagems
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4

### T4-7. Rapid Ingress stratagem — **DONE**
- **Phase:** Movement
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.11
- **Resolution:** Implemented Rapid Ingress stratagem (1 CP, opponent's Movement phase end). Added rapid_ingress_opportunity signal to MovementPhase.gd, USE_RAPID_INGRESS / DECLINE_RAPID_INGRESS / PLACE_RAPID_INGRESS_REINFORCEMENT action types, RapidIngressDialog.gd for unit selection UI, MovementController.gd signal handling, Main.gd placement flow, and NetworkManager.gd multiplayer sync. Includes battle round >= 2 restriction, 9" enemy distance check, Strategic Reserves edge placement rules, and unit coherency validation.

### T4-8. Secondary missions + New Orders stratagem — **DONE**
- **Phase:** Command
- **Source:** AUDIT_COMMAND_PHASE.md §P3
- **Resolution:** Full secondary missions system already implemented across multiple files. SecondaryMissionManager.gd (1360 lines) handles tactical deck building (18 cards), card drawing (max 2 active), voluntary discard (+1 CP), New Orders stratagem execution (discard and draw replacement), scoring with VP caps (40 secondary, 90 combined), when-drawn conditions (shuffle back, discard-and-draw, requires-interaction), and unit destruction tracking for kill-based missions. SecondaryMissionData.gd defines all 18 mission cards across 5 categories (Shadow Operations, Battlefield Supremacy, Strategic Conquests, Purge the Enemy, action-based). New Orders stratagem defined in StratagemManager.gd (1 CP, your Command phase, once per battle). CommandPhase.gd integrates deck init, card drawing, VOLUNTARY_DISCARD/USE_NEW_ORDERS/RESOLVE_MARKED_FOR_DEATH/RESOLVE_TEMPTING_TARGET actions with full validation. CommandController.gd provides UI with mission cards, discard buttons, New Orders buttons with availability checking. ScoringPhase.gd scores secondary missions at end of turn. ShootingPhase/FightPhase/WoundAllocationOverlay report unit destructions for kill-based missions. MarkedForDeathDialog.gd and TemptingTargetDialog.gd handle interactive mission requirements. Fixed broken test suite (test_secondary_missions.gd) — 292 tests pass.

### T4-9. Deployment map variety (Hammer and Anvil, Search and Destroy, etc.) — **DONE**
- **Phase:** Deployment
- **Source:** DEPLOYMENT_AUDIT.md §7
- **Resolution:** Five deployment maps (Hammer and Anvil, Dawn of War, Search and Destroy, Sweeping Engagement, Crucible of Battle) are data-driven via DeploymentZoneData.gd with JSON fallbacks. Deployment type selector added to MainMenu, MultiplayerLobby, and WebLobby. Multiplayer sync via RPC/relay messages.

### T4-10. Mission selection variety — **DONE**
- **Phase:** Pre-game
- **Source:** DEPLOYMENT_AUDIT.md §8
- **Resolution:** Created MissionData.gd registry with 9 primary missions from Chapter Approved 2025-26 (Take and Hold, Supply Drop, Purge the Foe, Scorched Earth, The Ritual, Sites of Power, Terraform, Linchpin, Hidden Supplies). Refactored MissionManager.gd to accept any mission_id from MissionData and dispatch scoring to mission-specific methods (_score_hold_objectives, _score_hold_and_kill, _score_supply_drop, _score_sites_of_power). Wired mission selection through MainMenu → GameState config → MissionManager.initialize_mission(). MainMenu dropdown now shows all 9 missions. Added kill tracking (record_unit_destroyed/reset_round_kills) for Purge the Foe integrated into ShootingPhase and FightPhase destruction hooks. Missions with complex special mechanics (burn, ritual, terraform) fall back to hold_objectives scoring until their action systems are implemented. 9 unit tests (99 assertions) verify MissionData registry, all mission structures, and API.

### T4-11. Fortification deployment — **DONE**
- **Phase:** Deployment
- **Source:** DEPLOYMENT_AUDIT.md §9
- **Resolution:** Added `GameState.unit_is_fortification()` to check for the FORTIFICATION keyword. `DeploymentPhase._validate_place_in_reserves()` now blocks fortification units from being placed in any reserve type (Strategic Reserves or Deep Strike) with a clear error message. `get_available_actions()` excludes reserve options for fortification units. `Main.gd` disables the reserves button and shows "Must Deploy (Fortification)" text for fortification units, and displays a `[FORT]` tag in the deployment unit list. Existing wholly-within-zone and no-overlap validation already applies.

### T4-12. Unmodified wound roll of 1 always fails (defensive check) — **DONE**
- **Phase:** Shooting/Fight
- **Source:** SHOOTING_PHASE_AUDIT.md §2.12
- **Depends on:** T1-3 (wound modifier system)
- **Resolution:** Verified that the `unmodified_roll == 1` auto-fail check already exists in all 6 wound roll code paths: interactive shooting (with/without Lethal Hits), auto-resolve shooting (with/without Lethal Hits), and fight phase (with/without Lethal Hits). Added `test_wound_roll_auto_fail.gd` with 13 tests covering the rule.

### T4-13. Unmodified save roll of 1 always fails (auto-resolve path) — **DONE**
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §2.13
- **Files:** `RulesEngine.gd` — `_resolve_assignment()` (~line 1129)
- **Resolution:** Verified that the `save_roll > 1` auto-fail check already exists in all 3 save roll code paths: auto-resolve shooting, overwatch, and melee fight phase. Added consistent "10e rules" comment and debug logging to the overwatch and auto-resolve paths. Added `test_save_roll_auto_fail.gd` with 17 tests (15 unit + 2 integration) covering the rule.

### T4-14. Weapon ID collision for similar weapon names — **DONE**
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues
- **Resolution:** Added weapon type suffix (_ranged/_melee) to `_generate_weapon_id()` to prevent collisions between ranged/melee variants of the same weapon name (e.g., "Guardian spear"). Consolidated all inline weapon ID generation to use the central function. Added backwards-compatible matching in `get_weapon_profile()` (typed ID, legacy ID, and exact name).

### T4-15. Single weapon result dialog has hardcoded zeros — **DONE**
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues
- **Files:** `ShootingPhase.gd:1796-1807`
- **Resolution:** Stored hit/wound/dice data in `resolution_state` during `_process_resolve_shooting` (single weapon path), then retrieved it in both the miss path and `_process_apply_saves` single weapon result builder. Replaced hardcoded zeros for `hits`, `total_attacks`, and empty `dice_rolls` with actual values from the resolution. Also added `hit_data` and `wound_data` fields for consistency with the sequential weapon path.

### T4-16. [MH-RULE-6] Conversion X+ (expanded crit range at distance) — **DONE**
- **Phase:** Mathhammer
- **Source:** MATHHAMMER_AUDIT
- **Resolution:** Implemented Conversion X+ weapon ability across all shooting resolution paths (interactive, auto-resolve) and Mathhammer simulation. Added `get_conversion_threshold()`, `has_conversion()`, `get_critical_hit_threshold()` to RulesEngine.gd. Modified hit roll logic to use dynamic `critical_hit_threshold` (default 6, lowered to X when Conversion X+ is present and target is 12"+ away). Added "Conversion 4+" and "Conversion 5+" toggles to MathhammerUI, with model placement at 13" distance for simulation. Rule text injection into weapon special_rules follows the same pattern as Anti-keyword.

### T4-17. [MH-RULE-7] Half Damage defensive ability — **DONE**
- **Phase:** Mathhammer
- **Source:** MATHHAMMER_AUDIT
- **Resolution:** Added `get_unit_half_damage()` and `apply_half_damage()` helpers to RulesEngine. Applied half-damage (round up) to all damage paths: `apply_save_damage` (regular + devastating), melee `_resolve_melee_assignment` (regular + devastating), Overwatch, and auto-resolve. Added "Half Damage" toggle to MathhhammerUI and registered rule in MathhhammerRuleModifiers. Mathhammer propagates toggle to trial board via `meta.stats.half_damage`. 15 unit tests (all passing).

### T4-18. [MH-RULE-14] Save modifier cap not enforced in mathhammer toggles — **DONE**
- **Phase:** Mathhammer
- **Rule:** Saves can be worsened by more than -1 (AP stacks) but cannot be improved by more than +1
- **Source:** MATHHAMMER_AUDIT
- **Resolution:** Added +1/-1 to Save toggles in MathhammerUI with mutual conflict. Registered save_plus_1/save_minus_1 in MathhammerRuleModifiers. Save modifier stored on defender flags in trial board and applied (clamped ±1 per 10e) in RulesEngine shooting, melee, and overwatch save resolution. AP stacking remains unlimited.

### T4-19. [MH-BUG-6] Triple 'h' typo in Mathhammer class names — **DONE**
- **Phase:** Mathhammer
- **Impact:** `MathhammerUI`, `MathhammerResults`, `MathhammerRuleModifiers` should be `MathhammerUI`, etc.
- **Source:** MATHHAMMER_AUDIT
- **Resolution:** Renamed all three files (`MathhammerUI.gd`, `MathhammerResults.gd`, `MathhammerRuleModifiers.gd`) to use double-h (`MathhammerUI.gd`, etc.). Updated `class_name` declarations, all print/comment references, `project.godot` class registrations and paths, `Main.gd` preload path, and benchmark test reference.
- **Files:** All `Mathhammer*.gd` files, `project.godot` autoload references

### T4-20. [MH-FEAT-9] Auto-detect weapon abilities from unit datasheet
- **Phase:** Mathhammer
- **Impact:** Weapon keywords (Lethal Hits, Sustained Hits, etc.) exist in unit data but aren't auto-enabled as toggles
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerRuleModifiers.gd:134-180` — `extract_unit_rules()` exists but isn't connected to UI

---

## TIER 5 — Quality of Life & UX Improvements

### Multiplayer UX
- T5-MP1. Pile-in/consolidate drag movement not synced visually to remote player (FIGHT_PHASE_AUDIT.md §3.6) — **DONE**
  - **Resolution:** Added real-time throttled drag previews during pile-in/consolidate (sent every 100ms to remote player) and smooth tween animations on PILE_IN/CONSOLIDATE action confirmation. Covers both ENet and WebSocket relay transport modes. Remote player now sees models moving during drag and smooth transitions on confirmation instead of teleportation.
- T5-MP2. Pile-in/consolidate validation feedback missing on client (FIGHT_PHASE_AUDIT.md §3.5) — **DONE**
  - **Resolution:** Added client-side validation gate in PileInDialog and ConsolidateDialog `_on_confirmed()` — dialog now blocks confirmation when movements are invalid, shows error in status label and toast. Added server-side rejection feedback in Main.gd: failed PILE_IN/CONSOLIDATE actions show toast error and re-request the movement dialog so the player can retry.
- T5-MP3. Remote player visual feedback for shooting actions (SHOOTING_PHASE_AUDIT.md §Tier 3) — **DONE**
  - **Resolution:** Added remote player visual feedback for all shooting actions: ASSIGN_TARGET draws orange shooting lines and weapon labels from shooter to target, CLEAR_ASSIGNMENT clears them, CONFIRM_TARGETS re-emits shooting_begun to draw shooting lines, COMPLETE_SHOOTING_FOR_UNIT re-emits shooting_resolved to clear visuals. Covers both ENet and WebSocket relay transport modes, and both host→client and client→host directions.
- T5-MP4. Save dialog timing reliability for defender on remote client (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Added defender→attacker acknowledgment handshake (`save_dialog_ack`), attacker-side "Waiting for defender" UI feedback, 8s ack timeout with automatic save data retry (`save_data_retry`), 10s processing flag safety reset, and APPLY_SAVES state cleanup. Covers both WebSocket relay and ENet RPC transport modes.
- T5-MP5. Dice log visibility sync to remote player (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Included `resolution_start` and `weapon_progress` dice blocks in broadcast results so remote players see the same dice log content as the local player. Added proper `resolution_start` context handler in ShootingController for header display. Enhanced NetworkManager dice sync logging with context details. Works across both ENet RPC and WebSocket relay modes.
- T5-MP6. "Waiting for Opponent" state in deployment (DEPLOYMENT_AUDIT.md §QoL 3) — **DONE**
  - **Resolution:** Added prominent centered overlay banner with "Waiting for Player X (Role) to deploy..." text, live turn timer countdown, pulse animations on both overlay and opponent's deployment zone, and toast notifications on deployment turn switches. Overlay managed via `_setup_waiting_for_opponent_overlay()`, `_update_waiting_for_opponent_overlay()`, and `_hide_waiting_overlay()` in Main.gd.
- T5-MP7. Game over UI with winner and reason (Code TODO in `NetworkManager.gd:1474`)
- T5-MP8. Phase timeout for AFK players (AUDIT_COMMAND_PHASE.md §P3) — **DONE**
  - **Resolution:** Implemented configurable phase timeout system for AFK players in multiplayer. NetworkManager now auto-ends the current phase on first timeout (90s), then triggers game over after 2 consecutive timeouts. Timer resets on any player action via PhaseManager.phase_action_taken signal. Added phase timer HUD countdown in top bar (color-coded green/yellow/red), extended "Waiting for Opponent" overlay to all phases (not just deployment), and added toast warnings at 30s/15s/10s/5s thresholds. Both active player and waiting opponent see timer state.
- T5-MP9. BEGIN_ADVANCE latency in multiplayer (MOVEMENT_PHASE_AUDIT.md §3.3) — **DONE**
  - **Resolution:** Added `BEGIN_ADVANCE` to `DETERMINISTIC_ACTIONS` for optimistic client-side execution. An RNG seed is now embedded in the action payload by `NetworkManager.submit_action()` before processing. Both the optimistic client and authoritative host read the same seed from the action, producing identical D6 advance rolls without a round-trip. `MovementPhase._process_begin_advance()` reads the seed from the payload first, falling back to host generation for backwards compatibility.

### Gameplay UX
- T5-UX1. Expected damage preview when hovering weapons (SHOOTING_PHASE_AUDIT.md §Tier 3) — **DONE**
  - **Resolution:** Added analytical expected damage preview panel in ShootingController. When hovering or selecting a weapon in the weapon tree, a compact preview shows expected hits, wounds, unsaved wounds, damage, and models killed against the assigned (or first eligible) target. Calculation uses 10e wound threshold rules, AP/invuln saves, and weapon stats. UI panel uses WH-themed styling with BBCode rich text.
- T5-UX2. Auto-select weapon for single-weapon units (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Added `_try_auto_select_single_weapon()` in ShootingController. When a unit has only one usable weapon type (accounting for Pistol/Assault restrictions), it is auto-selected in the weapon tree so the player can directly click an enemy unit to assign a target without first selecting the weapon. Works alongside existing single-target auto-assign for fully automatic handling of simple shooting scenarios.
- T5-UX3. "Shoot All Remaining" button (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Added "Shoot All Remaining" button to ShootingController UI. When pressed, shows a confirmation dialog listing all eligible units and their nearest targets. On confirmation, dispatches atomic SHOOT actions sequentially for each remaining unit, assigning all ranged weapons to the nearest eligible target. Uses the same resolution path as AI shooting (hits/wounds/saves resolved automatically).
- T5-UX4. "Undo Last Assignment" button in weapon assignment (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Added "Undo Last" button in ShootingController between "Clear All" and "Confirm Targets". Maintains an `assignment_history` stack that tracks weapon assignments in order. Undo pops the most recent assignment, clears it from local state and the phase's pending_assignments via `CLEAR_ASSIGNMENT` action, resets the weapon tree row text, and updates the "Apply to All" button state. History is cleared on new shooter selection, clear all, and shooting resolution.
- T5-UX5. "All to Target" button in fight attack assignment dialog (fight_phase_audit_report.md §3.1) — **DONE**
  - **Resolution:** Added "All to Target" button in AttackAssignmentDialog next to "Add Assignment". When clicked, assigns all unassigned regular melee weapons to the currently selected target, skipping any already-assigned weapons. Provides a one-click shortcut for the common case of directing all attacks at a single enemy unit.
- T5-UX6. Show weapon stats in target assignment UI (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Added compact weapon stat sub-line beneath each weapon in the shooting phase weapon tree. Each weapon now shows Range, Attacks, BS, Strength, AP, and Damage (e.g., "24" A:2 BS:3+ S:4 AP:-1 D:1") in a muted gold color. Stats child items also trigger the damage preview on hover. Disabled weapons have grayed-out stats.
- T5-UX7. End fight phase confirmation dialog (fight_phase_audit_report.md §3.6) — **DONE**
  - **Resolution:** Added EndFightConfirmationDialog.gd that shows when the player tries to end the Fight phase while eligible units haven't fought. Lists unfought units by player and subphase with a warning message. Added get_unfought_eligible_units() to FightPhase.gd and intercept logic in Main.gd. If no unfought units remain, the phase ends immediately without a dialog.
- T5-UX8. Deployment summary before ending phase (DEPLOYMENT_AUDIT.md §QoL 8) — **DONE**
  - **Resolution:** Added DeploymentSummaryDialog.gd that shows a full deployment summary when the player clicks End Deployment. Lists deployed units per player with positions, units in transports, attached characters, and units in reserves. Added get_deployment_summary() to DeploymentPhase.gd and intercept logic in Main.gd. Requires explicit "Confirm and Start Game" or "Go Back" before proceeding.
- T5-UX9. Undo last model placement (per-model) in deployment (DEPLOYMENT_AUDIT.md §QoL 4) — **DONE**
  - **Resolution:** Added `undo_last_model()` per-model undo to DeploymentController (Ctrl+Z or Undo button removes only the last placed model). Existing full-unit reset preserved as `reset_unit()` via the Reset Unit button. Both buttons now visible during deployment when models are placed.
- T5-UX10. Auto-zoom to deployment zone (DEPLOYMENT_AUDIT.md §QoL 5) — **DONE**
  - **Resolution:** Added `focus_on_deployment_zone(player)` to Main.gd with smooth tween animation. Auto-zooms to active player's deployment zone on phase entry and on deployment turn switch. Calculates bounding box of zone polygon and fits camera with 20% padding margin.
- T5-UX11. Unit base preview on hover in deployment (DEPLOYMENT_AUDIT.md §QoL 7) — **DONE**
  - **Resolution:** Added hover tooltip on UnitListPanel during deployment phase. When hovering over a unit in the list, a styled tooltip appears showing unit name, model count, base size/type, and special deployment rules (Deep Strike, Infiltrators, Fortification, CHARACTER, Transport capacity). Uses gui_input signal with get_item_at_position for hover detection, positioned to the left of the unit list.
- T5-UX12. Keyboard shortcuts for shooting phase (SHOOTING_PHASE_AUDIT.md §Tier 4) — **DONE**
  - **Resolution:** Added keyboard shortcuts to ShootingController._input(): Space/Enter to confirm targets, Escape to deselect/cancel shooter, Tab/Shift+Tab to cycle eligible units, N to skip current unit, E to end shooting phase. Main.gd ESC handler defers to ShootingController when a shooter is active. Multiplayer-safe (blocks input when not local player's turn).
- T5-UX13. Score objectives — not implemented (Code TODO in `ScoringController.gd:148`) — **DONE**
  - **Resolution:** Added objective control display to ScoringController right panel (shows each objective, its zone, and which player controls it, plus summary counts and mission name). ScoringPhase now calls `MissionManager.check_all_objectives()` on entry so objective-dependent secondary missions use up-to-date control data.
- T5-UX14. Mathhammer melee simulation integration (Code TODO in `FightPhase.gd:947`) — **DONE**
  - **Resolution:** The mathhammer melee prediction was already implemented in `_show_mathhammer_predictions()` (FightPhase.gd), replacing the original placeholder. Runs 1000-trial Monte Carlo simulation via `Mathhammer.simulate_combat()` with phase "fight" before dice rolling. Auto-detects Lance charge bonus. RulesEngine handles weapon special rules (Lethal Hits, Sustained Hits, Devastating Wounds, etc.) from weapon profiles. Also fixed a scoping bug in Mathhammer.gd where `fresh_defender` assignment was outside its declaring block.

### Mathhammer UX
- T5-MH1. [MH-FEAT-1] Visual histogram / probability distribution chart — replace text bars with graphical bars (MATHHAMMER_AUDIT) — see also T5-V15 — **DONE**
  - **Resolution:** Implemented via T5-V15. `_draw_visual_histogram()` provides graphical bar chart with color-coded bars, percentage labels, and automatic bucketing for wide damage ranges.
- T5-MH2. [MH-FEAT-2] Cumulative probability display — "X% chance of at least N wounds" table (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added `calculate_reverse_cumulative()` to MathhammerResults.gd for computing P(X >= N) reverse cumulative distribution. Added `_create_cumulative_probability_panel()` to MathhammerUI.gd displaying a color-coded table (green/yellow/orange/red by probability tier). Smart row filtering keeps the table manageable for large damage ranges. Panel appears in both the summary and breakdown sections.
- T5-MH3. [MH-FEAT-3] Multi-weapon side-by-side comparison view (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added "Compare Weapons" button to MathhammerUI.gd that runs independent Monte Carlo simulations per weapon against the same defender. Results displayed as side-by-side weapon stat cards showing avg damage, kill probability, expected survivors, hit/wound/unsaved rates, and damage efficiency. Best weapon highlighted with green background. Damage ranking panel sorts weapons by effectiveness with color-coded rank labels. Breakdown panel shows per-weapon cumulative probability tables. Runs on background thread to avoid UI freeze.
- T5-MH4. [MH-FEAT-4] Damage per point (points efficiency metric) — unit cost data exists in `meta.points` (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added damage-per-point efficiency metric to MathhammerUI.gd. Overall stats panel now shows "Attacker Cost" and "Damage/Point" (wounds per point) using unique attacker unit costs from `meta.points`. Weapon comparison view shows per-weapon unit cost and damage/point with best-efficiency highlighting. Added "Efficiency Ranking (Damage/Point)" panel to comparison rankings with gold/silver/bronze color-coding. Helper functions `_get_unit_points_cost()` and `_get_selected_attacker_points_cost()` compute costs. Existing `MathhammerResults.gd` calculation logic (`damage_per_point`, `kills_per_point`) unchanged.
- T5-MH5. [MH-FEAT-5] Swap attacker/defender button (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added "⇅ Swap Attacker / Defender" button between attacker and defender sections in MathhammerUI.gd. Swaps the first active attacker to become the new defender and the current defender to become an attacker with 1 attack. Resets all other attacker spinboxes, refreshes weapon selection, auto-detects new defender rules, and resets defender override panel. Validates that both attacker and defender are selected before swapping.
- T5-MH6. [MH-UI-2] Responsive panel sizing — adapt to viewport instead of hardcoded 800px/400x600 (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Replaced all hardcoded pixel sizes (800px panel height, 400x600 scroll container, 350/380-wide content areas, 400px expanded height) with viewport-relative calculations via helper functions. Connected to viewport `size_changed` signal so layout updates dynamically on resize. Sizes computed as percentages of viewport dimensions (e.g. panel width ~32%, scroll height ~58%, expanded height ~39%). Small UI elements (labels, spacers, spinboxes) left as fixed minimums for readability.
- T5-MH7. [MH-UI-3] Loading spinner / progress bar during simulation (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added ProgressBar + status label UI below the Run/Compare buttons, hidden by default. Added progress_callback parameter to Mathhammer.simulate_combat() that reports every ~2% of trials. Background thread defers progress updates to main thread via call_deferred. Both simulation and weapon comparison flows show live trial count / weapon name progress. Progress indicator auto-hides on completion.
- T5-MH8. [MH-UI-6] Color-code results — green for high kill prob, red for low efficiency, yellow for overkill (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added threshold-based color-coding to kill probability (green ≥75%, yellow-green ≥50%, yellow ≥25%, orange ≥10%, red <10%), damage efficiency (green ≥85%, yellow-green ≥60%, yellow ≥40%, red <40%), and overkill (orange/yellow when overkill is significant relative to average damage). Applied consistently across Overall Statistics panel and weapon comparison cards. Added new "Avg Overkill" stat row when overkill > 0.
- T5-MH9. [MH-UI-7] Deduplicate results display — stats shown in both summary_panel and breakdown_panel (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Removed `_populate_breakdown_panel()` which duplicated all four result sections (Overall Stats, Weapon Breakdown, Damage Distribution, Cumulative Probability) from summary_panel into breakdown_panel. Standard simulation now shows results only in summary_panel and hides the empty breakdown_panel. Comparison mode's `_populate_comparison_breakdown()` (which shows unique per-weapon cumulative tables) is preserved. `_clear_results_display()` restores breakdown_panel visibility for the comparison flow.
- T5-MH10. [MH-UI-8] "Clear Results" / "Reset" button (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added "Clear Results" button after the Compare Weapons button, disabled by default. Enabled after simulation or weapon comparison completes. Handler clears results display, histogram, resets stored simulation result to null, restores placeholder text in summary and breakdown panels, then disables itself.
- T5-MH11. [MH-FEAT-7] Show dice notation (D6, D3+3) in weapon stats display (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added attacks (A:) to weapon stats bracket and now display raw dice notation for attacks, strength, and damage fields (e.g., `[A:D6+3 BS:5+ S:D6+6 AP:-3 D:D6]`). Attacks label next to spinbox shows `(base: D6+3)` hint when attacks use dice notation.
- T5-MH12. [MH-FEAT-10] Multi-target comparison matrix — run same attacker against multiple defenders (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added "Compare Targets" button and multi-defender selection panel with checkboxes. Users toggle "Select Multiple Defenders" to reveal unit checkboxes, select 2+ defenders, then press "Compare Targets". Runs same attacker config against each defender independently on a background thread with progress updates. Displays per-target comparison cards showing defender profile (T/Sv/W/Models/Invuln/FNP), avg damage, kill probability, expected survivors, damage efficiency, and wound/unsaved rates with color-coded best values. Includes target priority ranking (by avg damage with gold/silver/bronze) and efficiency ranking (least overkill). Per-defender cumulative probability tables in breakdown panel.
- T5-MH13. Shooting/Melee phase toggle in Mathhammer UI (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Phase toggle OptionButton (Shooting/Melee) filters weapon list to show only ranged or melee weapons respectively, hides shooting-only rule toggles (Cover, Torrent, Rapid Fire, Conversion) in melee mode, routes simulation to correct RulesEngine method (resolve_shoot vs resolve_melee_attacks), and displays phase context in all result views. Added "no weapons" hint when a unit lacks weapons for the selected phase, phase label in Overall Statistics and comparison headers, and _unit_has_melee_weapons helper.

### Visual Polish
- T5-V1. Animated dice roll visualization (SHOOTING_PHASE_AUDIT.md §Tier 3) — **DONE**
  - **Resolution:** Created `DiceRollVisual.gd` — a reusable animated 2D dice display Control. Each die shows a cycling animation before settling on its final value. Color-coded: gold for critical hits (6s), red for natural 1s, green for successes, gray for failures. Integrated into ShootingController, FightController, and ChargeController via the `dice_rolled` signal. Appears above the text dice log in each phase's right panel.
- T5-V2. Shooting line animation and tracer effects (SHOOTING_PHASE_AUDIT.md §Tier 4) — **DONE**
  - **Resolution:** Created `ShootingLineVisual.gd` — animated shooting line with muzzle flash, traveling tracer pulse, and impact flash effects. Line extends from shooter to target with configurable timing. Integrated into `ShootingController.gd` for both local player (animated tracer on shooting_begun) and remote player (static line on target assignment). Replaces old plain Line2D shooting lines with the animated visual. Auto-fades after hold duration; cleaned up on shooting_resolved.
- T5-V3. Phase transition animation banners (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Created `PhaseTransitionBanner.gd` — an animated banner that slides in from the top of the screen when phases change. Shows phase name with unicode icons, round number, and active player. Uses WhiteDwarf gothic theme with gold accent borders. Slide-in with TRANS_BACK easing, holds 1.5s, then slides out with fade. Integrated into `Main._on_phase_changed()` for all phases.
- T5-V4. Target unit damage feedback (flash + death animation) (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Created `DamageFeedbackVisual.gd` — a Node2D that provides animated damage feedback effects. Damage flash: red tint pulse with expanding rings on model position, intensity scaled by damage ratio. Death animation: expanding red ring with debris particles and skull marker fade-in. Integrated into `WoundAllocationOverlay.gd` for interactive save resolution (both damage and death paths). Token flash effect via modulate tween on the actual TokenVisual. Death fade-out animation in `Main.update_unit_visuals()` — white flash then fade to transparent instead of instant hide.
- T5-V5. Range circle visualization for weapons (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Enhanced `RangeCircle.gd` with dashed circle mode, subtle pulse animation, and per-weapon-type color coding. Updated `ShootingController._show_range_indicators()` to show range circles from a single reference model (reducing clutter), use weapon display names, add dashed half-range circles for Melta weapons (red, +X dmg label), and use dashed style for Rapid Fire half-range circles (orange). Fixed `_show_range_label()` to not clear range circles when showing distance labels. Enemy units color-coded green (in range) or gray (out of range).
- T5-V6. Wound allocation overlay enhancements (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Enhanced WoundAllocationBoardHighlights.gd with three visual improvements: (1) Pulsing animation on PRIORITY and PRECISION_TARGET highlights using sine-wave _process() — alpha oscillates 0.3–0.9, scale pulses 0.95x–1.10x at ~2 Hz. (2) Health color gradient ring overlay on multi-wound models — green→yellow→red based on wound ratio using a hollow ring texture. (3) Wound counter label (e.g. "3/6") positioned below each damaged multi-wound model with color-coded text and dark outline for readability. All three displays update in real-time as damage is applied and are cleaned up on model death and overlay close.
- T5-V7. Weapon keyword icons in UI (SHOOTING_PHASE_AUDIT.md §Additional) — **DONE**
  - **Resolution:** Created `WeaponKeywordIcons.gd` — a static utility class that programmatically generates small color-coded icon badges for each weapon keyword (Torrent, Pistol, Assault, Heavy, Rapid Fire, Lethal Hits, Sustained Hits, Devastating Wounds, Blast, One Shot). Badges are drawn as rounded rectangles with pixel-art letter labels, composited into a horizontal strip texture via `Image.blit_rect()`. Integrated into `ShootingController._populate_weapon_tree()` using `TreeItem.set_icon()` with tooltip text describing each keyword's effect. Replaces the old text-based `[T/P/LH]` bracket indicators with visually distinct, color-coded icon badges. Texture caching prevents redundant regeneration.
- T5-V8. Pile-in/consolidate movement arrows and distance labels (fight_phase_audit_report.md §4.1) — **DONE**
  - **Resolution:** Created `PileInMovementVisual.gd` — a custom Node2D with `_draw()` override that replaces the plain Line2D direction lines with enhanced visuals: (1) Directional arrows with filled triangular arrowheads from current model position to closest enemy, colored green (valid) or red (invalid). (2) Animated dashed movement path ("marching ants") from original position to current drag position, colored green/yellow/red-orange based on validity and 3" distance limit. (3) Distance label at the movement path midpoint showing inches moved with dark background and colored border. Integrated into FightController via `_create_pile_in_visuals()` and `_update_pile_in_visuals()`. Updated PileInDialog and ConsolidateDialog info legends to reflect new visual indicators.
- T5-V9. Engagement range pulsing animation (fight_phase_audit_report.md §4.2) — **DONE**
  - **Resolution:** Created `EngagementRangeVisual.gd` — a dedicated Node2D script with sine-wave pulsing animation (0.7–1.0 alpha at ~2 Hz, matching RangeCircle.gd pattern). Supports two modes: engagement range circles (orange pulsing around fighter models) and target highlights (green pulsing for eligible enemies with outer glow ring, static gray for ineligible). Replaces inline GDScript approach in FightController.gd with proper preloaded script instances. Both fill and outline colors pulse in sync for a smooth breathing effect.
- T5-V10. Fight phase state banner (fight_phase_audit_report.md §4.3) — **DONE**
  - **Resolution:** FightPhaseStateBanner.gd — persistent banner below HUD_Top showing current subphase (FIGHTS FIRST / REMAINING COMBATS / FIGHTS LAST), selecting player, units remaining; distinct color schemes per subphase; animated transition overlay on subphase change; integrated via FightController signal flow
- T5-V11. Unit tokens "has fought" indicator (fight_phase_audit_report.md §4.4) — **DONE**
- T5-V12. Damage application visualization (floating numbers, flash) (fight_phase_audit_report.md §4.5) — **DONE**
  - **Resolution:** Extended DamageFeedbackVisual.gd with `play_floating_number()` — red damage numbers float upward from wounded models with fade-out animation. Integrated into FightController via `attacks_resolved` signal: parses fight resolution diffs to trigger floating numbers, damage flash, death animations, and token red flash on target models. Filters diffs per-assignment to avoid duplicates in multi-target fights.
- T5-V13. Engaged units board indicator (crossed swords) (fight_phase_audit_report.md §3.5) — **DONE**
  - **Resolution:** Crossed swords badge overlay on engaged unit tokens during fight phase — color-coded by fight priority (red/gold for Fights First, white for Normal, gray for Fights Last); `is_engaged`/`fight_priority` flags set in FightPhase._initialize_fight_sequence() and cleared on phase exit; badge hidden once unit has fought (defers to "has fought" overlay)
- T5-V14. Deployment zone edge highlighting (DEPLOYMENT_AUDIT.md §QoL 6) — **DONE**
  - **Resolution:** Enhanced `DeploymentZoneVisual.gd` with animated dashed border (marching ants), multi-layer pulsing glow on inner edges (facing no-man's-land), corner markers at zone boundary transitions, and zone depth labels (e.g., "12\"") on the longest inner edge. Board-boundary edges get subtle dimmed dashed lines while inner edges get full glow + emphasis treatment. Follows sine-wave animation patterns from EngagementRangeVisual.gd and dashed line patterns from RangeCircle.gd/PileInMovementVisual.gd.
- T5-V15. Mathhammer visual histogram (Code TODO in `MathhammerUI.gd:738`) — see also T5-MH1 — **DONE**
  - **Resolution:** Replaced text-based `_draw_simple_histogram()` with `_draw_visual_histogram()` using graphical ColorRect bars. Vertical bar chart for <=20 damage values, horizontal bar chart for larger distributions. Bars color-coded by damage relative to mean (blue=below, gold=average, green=above). Includes automatic bucketing for >30 unique damage values, percentage labels, damage labels, and a color legend. Integrated into `_display_simulation_results()` display path and clear-results flow.

---

## TIER 6 — Testing Infrastructure

These items come from the Testing Audit (PRPs/gh_issue_93_testing-audit.md) and affect development velocity.

### T6-1. Fix broken test compilation errors — **DONE**
- BaseUITest method signature mismatch (`assert_unit_card_visible` — 1 param vs 2)
- Missing assertion methods (`assert_has`, `assert_does_not_have`)
- GameState autoload resolution in headless tests
- **Source:** TESTING_AUDIT_SUMMARY.md, PRPs/gh_issue_93_testing-audit.md
- **Resolution:** Created missing `BaseUITest.gd` with correct 2-param `assert_unit_card_visible(visible, message)` signature, `assert_has`/`assert_does_not_have` collection assertions, and full UI testing helpers (scene loading, button clicks, model tokens, drag, phase transitions). Fixed `ensure_autoloads_loaded(get_tree())` parameter mismatch in BasePhaseTest.gd and test_multiplayer_gameplay.gd to use `verify_autoloads_available()`. Fixed `Engine.has_singleton`/`get_singleton` GameState access in test_full_gameplay_sequence.gd to use `AutoloadHelper.get_game_state()` (autoloads are scene tree nodes, not Engine singletons).

### T6-2. Validate all existing tests and document status — **DONE**
- ~300 tests across 52 files, many with ⚠️ Unknown status
- 8 fight phase test failures need investigation
- **Source:** TESTING_AUDIT_SUMMARY.md
- **Resolution:** Ran all 1234 tests across 65 scripts (unit, integration, network). Fixed 6 compilation errors blocking execution (RulesEngine undeclared vars, ChargePhase duplicate functions, Mathhammer scope error, test RNGService qualification). Fixed EffectPrimitives Array/String comparison crash (resolved 37 failures). Final results: 1147 passing (93%), 50 failing (documented root causes), 37 risky/pending. Fight phase test failures traced to: ChargePhase compilation cascade, EffectPrimitives type error, and 2 disabled tests using incompatible singleton patterns. Identified save calculation sign bug (`_calculate_save_needed` treats negative AP as improvement). Full report in `40k/TEST_VALIDATION_REPORT.md`.

### T6-3. Add E2E workflow tests
- No full deployment → movement → shooting → fight test
- No multi-turn game simulation
- **Source:** PRPs/gh_issue_93_testing-audit.md

### T6-4. Multiplayer test infrastructure — **DONE**
- No network synchronization tests
- No latency simulation
- No disconnect handling tests
- Multiplayer deployment test helpers have TODO stubs (`test_multiplayer_deployment.gd:555-574`)
- **Source:** PRPs/gh_issue_93_testing-audit.md, code TODOs
- **Resolution:** Created `test_multiplayer_network.gd` with 11 tests covering state synchronization (3 tests), latency/jitter/packet-loss simulation (4 tests), and disconnect handling (4 tests). Added `simulate_client_disconnect()`, `simulate_host_disconnect()`, `verify_instance_alive()`, `assert_game_states_match()`, and `get_action_round_trip_time_ms()` helpers to `MultiplayerIntegrationTest.gd`. Completed collision detection test and resolved TODO stubs in `test_multiplayer_deployment.gd`. Documented LogMonitor limitation (connection verified via command simulation instead).

### T6-5. CI/CD integration — **DONE**
- Tests not run automatically on commits
- **Source:** PRPs/gh_issue_93_testing-audit.md
- **Resolution:** Fixed test-suite.yml to trigger on all branch pushes (not just main/develop), corrected test directories to match actual structure (removed non-existent phases/ui dirs, added network tests), updated all workflow action versions (setup-godot@v2, upload-artifact@v4), added timeouts to prevent hanging, fixed .gutconfig.json, and updated CI/CD README documentation.

---

## TIER 7 — AI Player Intelligence

> **Source:** AI_AUDIT.md | **Primary files:** `AIPlayer.gd`, `AIDecisionMaker.gd`
> The AI player system provides a functional single-player experience but has major gaps: charges are completely skipped, pile-in/consolidation never moves models, no stratagem usage, no ability awareness, and no competitive tactical reasoning. These tasks address all identified AI gaps from the AI Player Audit.

### P0 — Critical: AI Plays Incorrectly Without These

### T7-1. AI charge declarations — charges are completely skipped — **DONE**
- **Phase:** Charge
- **Priority:** CRITICAL
- **Source:** AI_AUDIT.md §AI-GAP-1, CHARGE-1 through CHARGE-3
- **Files:** `AIDecisionMaker.gd` — `_decide_charge()`
- **Details:** `_decide_charge()` always returns SKIP_CHARGE. Implement charge feasibility check (distance ≤12"), 2D6 probability assessment, target evaluation, model positioning post-charge with B2B contact and coherency.
- **Resolution:** Full charge decision system implemented: `_evaluate_best_charge()` scores all (charger, target) pairs using distance feasibility (≤12"), 2D6 probability math (`_charge_success_probability()`), melee damage estimation, target value scoring, objective bonuses, and leader ability multipliers. `_compute_charge_move()` positions models with B2B contact and coherency. Fixed RulesEngine autoload dependency for test compilation; fixed SKIP_CHARGE handling for units with no eligible targets. 36/36 tests pass.

### T7-2. AI pile-in movement — models never move during fight — **DONE**
- **Phase:** Fight
- **Priority:** CRITICAL
- **Source:** AI_AUDIT.md §AI-GAP-2, FIGHT-1
- **Files:** `AIDecisionMaker.gd` — `_decide_fight()`
- **Details:** `_decide_fight()` sends empty `movements: {}` for PILE_IN actions. Implement 3" pile-in toward nearest enemy model, skip models already in B2B contact, maintain unit coherency.
- **Resolution:** Full pile-in movement implemented via `_compute_pile_in_action()` and `_compute_pile_in_movements()`. Each model moves up to 3" toward closest enemy, models in B2B hold position, collision avoidance with spiral search, board boundary clamping. Fixed collision detection to split friendly/enemy obstacles — friendly models use 2px gap (prevent stacking), enemy models use -1px gap (allow B2B contact). Consolidation engagement mode reuses pile-in logic. 28 tests pass.

### T7-3. AI consolidation movement — models never consolidate — **DONE**
- **Phase:** Fight
- **Priority:** CRITICAL
- **Source:** AI_AUDIT.md §AI-GAP-2, FIGHT-2
- **Files:** `AIDecisionMaker.gd` — `_decide_fight()`
- **Details:** Consolidation movements always empty. Implement 3" consolidation prioritizing: moving onto objectives, tagging new enemy units, wrapping enemies to prevent fall-back, maintaining coherency.
- **Resolution:** Implemented dedicated `_compute_consolidate_movements_engagement()` replacing basic pile-in reuse. Enhanced with: (1) wrapping — models distribute around enemies at different angles (far-side priority) to block fall-back, (2) tagging — identifies and prioritises unengaged enemy units within 4" reach, (3) objectives — existing OBJECTIVE mode moves toward closest objective marker. Added `_angle_difference()` helper for angular spacing. 37 tests pass (3 new: wrapping distribution, tagging new units, multi-model wrap).

### T7-4. AI fall-back model positioning — fall-back doesn't move models — **DONE**
- **Phase:** Movement
- **Priority:** CRITICAL
- **Source:** AI_AUDIT.md §MOV-6
- **Files:** `AIDecisionMaker.gd` — movement decision path
- **Details:** Fall-back path destinations not computed. Implement valid fall-back positioning that moves models away from enemy engagement range.
- **Resolution:** Fixed `_pick_fall_back_target()` to skip objectives within engagement range of the unit (prevented zero retreat direction when unit is on an objective), added directional scoring to prefer objectives in the "away from enemy" direction, and added safety fallback in `_compute_fall_back_destinations()` for zero-direction edge cases. All 15 fall-back positioning tests pass.

### P1 — High: AI Plays Very Poorly Without These

### T7-5. AI weapon range check in target scoring — **DONE**
- **Phase:** Shooting
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-GAP-5, SHOOT-4
- **Files:** `AIDecisionMaker.gd` — `_score_shooting_target()`
- **Details:** Target scoring doesn't check weapon range. AI wastes turns on out-of-range shots then falls back to SKIP_UNIT. Score 0 for targets beyond weapon range.
- **Resolution:** `_score_shooting_target()` checks weapon range via `_get_weapon_range_inches()` and `_get_closest_model_distance_inches()`, returning 0.0 for out-of-range targets. Caller passes `shooter_unit` for distance calculation. 15/15 weapon range scoring tests pass.

### T7-6. AI focus fire coordination across units — **DONE**
- **Phase:** Shooting
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-TACTIC-2, SHOOT-1
- **Files:** `AIDecisionMaker.gd` — `_decide_shooting()`, `_build_focus_fire_plan()`, `_estimate_weapon_damage()`, `_score_shooting_target()`
- **Details:** Each weapon independently picks best target, spreading fire across many units. Implement kill-threshold targeting: calculate total expected damage vs each target across ALL weapons, allocate to meet kill thresholds before moving to secondary targets.
- **Resolution:** Enhanced `_build_focus_fire_plan()` with: (1) wound overflow cap in `_estimate_weapon_damage()` and `_score_shooting_target()` — damage capped at model wounds for accurate kill-threshold math; (2) value-per-threshold priority sorting to allocate kills efficiently; (3) model-level partial kill assessment — focuses fire even when can't wipe a unit, using efficiency-filtered weapon selection; (4) coordinated Pass 2 secondary target allocation instead of independent spreading; (5) poorly-matched weapons skipped once kill threshold met. Removed redundant damage waste penalty from `_calculate_efficiency_multiplier()`. 41/41 focus fire tests pass, 37/37 weapon efficiency tests pass.

### T7-7. AI weapon-target efficiency matching — **DONE**
- **Phase:** Shooting
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-TACTIC-5, SHOOT-2
- **Files:** `AIDecisionMaker.gd` — `_decide_shooting()`
- **Details:** All weapons on a unit fire at same target. Match anti-tank to vehicles, anti-infantry to hordes. Penalize multi-damage weapons on single-wound models. Each weapon gets its own optimal target.
- **Resolution:** Re-enabled damage waste penalty in `_calculate_efficiency_multiplier()` for multi-damage weapons vs single-wound models: D3+ gets HEAVY penalty (0.4×), D2 gets MODERATE penalty (0.7×). Combined with existing role-based matching (anti-tank vs horde = 0.6×), a lascannon vs 1W grots now scores 0.24× efficiency. Added efficiency logging to fallback assignment path. Per-weapon target assignment and role matching were already functional from T7-5/T7-6. 40/40 weapon efficiency tests pass.

### T7-8. AI invulnerable save consideration in target scoring — **DONE**
- **Phase:** Shooting
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-GAP-6, SHOOT-3
- **Files:** `AIDecisionMaker.gd` — `_save_probability()`
- **Details:** Only basic save used in scoring. Use `min(modified_save, invuln)` to avoid wasting high-AP weapons on invuln-protected targets.
- **Resolution:** `_save_probability()` accepts optional `invuln` parameter and uses `min(modified_save, invuln)`. Added `_get_target_invulnerable_save()` helper checking model-level, meta.stats, and effect-granted invulns. All callers (`_score_shooting_target`, `_estimate_weapon_damage`, `_estimate_melee_damage`) pass invuln through. 18/18 tests pass.

### T7-9. AI weapon keyword awareness in target scoring — **DONE**
- **Phase:** Shooting
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §SHOOT-5
- **Files:** `AIDecisionMaker.gd` — `_score_shooting_target()`
- **Details:** Weapon keywords not factored into expected damage: Blast (+1A per 5 models), Rapid Fire (+X at half range), Melta (+X damage at half range), Anti-keyword (lower crit wound threshold), Torrent (100% hit), Sustained/Lethal/Devastating Hits.
- **Resolution:** `_apply_weapon_keyword_modifiers()` adjusts expected-damage components (attacks, p_hit, p_wound, p_unsaved, damage) for all 8 keywords: Torrent (p_hit=1.0), Blast (floor(models/5) bonus attacks per 10th ed), Rapid Fire X (+X attacks at half range with fallback probability), Melta X (+X damage at half range), Anti-keyword X+ (improved wound probability vs matching keywords), Sustained Hits X (crit-weighted attack multiplier), Lethal Hits (effective p_wound boost), Devastating Wounds (effective p_unsaved boost). Fixed Blast formula from incorrect 9th ed thresholds (6/11) to correct 10th ed `floor(alive/5)`. Both `_score_shooting_target()` and `_estimate_weapon_damage()` use the modifier pipeline. 50/50 keyword tests pass.

### T7-10. AI basic stratagem usage — **DONE**
- **Phase:** All
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-GAP-3
- **Files:** `AIDecisionMaker.gd`, `AIPlayer.gd`, `StratagemManager.gd`
- **Details:** AI never spends CP (except auto Command Re-roll on battle-shock). Implement staged stratagem usage: Grenade (shooting), Fire Overwatch (opponent's charge), Go to Ground/Smokescreen (defensive), intelligent Command Re-roll triggers (failed charges, critical saves).
- **Resolution:** AI now uses all core stratagems intelligently: Grenade (shooting phase, weak-ranged units vs nearby targets), Fire Overwatch (opponent's movement/charge, high-volume shooters vs valuable targets), Go to Ground/Smokescreen (defensive, opponent's shooting), Command Re-roll (charge rolls, advance rolls, battle-shock tests), Tank Shock (vehicle charges with T-based mortal wounds), and Heroic Intervention (melee counter-charges by CHARACTER units). Added `evaluate_tank_shock()` and `evaluate_heroic_intervention()` heuristic methods, connected `tank_shock_opportunity` and `heroic_intervention_opportunity` signals, added movement phase command reroll fallback. 33/33 stratagem + 36/36 charge tests pass.

### T7-11. AI unit ability awareness — **DONE**
- **Phase:** All
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-GAP-4
- **Files:** `AIDecisionMaker.gd`, `UnitAbilityManager.gd`, `AIAbilityAnalyzer.gd`
- **Details:** AI ignores all unit abilities. Factor leader attachment bonuses into unit value, detect "Fall Back and X" abilities, protect Lone Operatives (>12" from enemies), leverage Deadly Demise on doomed vehicles, select Oath of Moment targets intelligently.
- **Resolution:** Added Deadly Demise detection (has_deadly_demise, get_deadly_demise_value, is_unit_doomed) to AIAbilityAnalyzer. Integrated into AIDecisionMaker: (1) Lone Operative movement protection — AI keeps own LO units >12" from enemies by computing safe retreat positions. (2) Deadly Demise leverage — doomed vehicles move toward enemies and get charge score bonus (D3=1.5x, D6=2.0x). (3) Enhanced Oath of Moment — considers invuln saves, leader buff abilities, and army weapon efficiency against target. (4) Lone Operative targeting restriction — focus fire plan excludes LO targets >12" from shooters. Leader bonuses, Fall Back and X, FNP, Stealth, and offensive/defensive multipliers were already integrated in prior work. 10 new T7-11 tests pass.

### T7-12. AI scout move execution — **DONE**
- **Phase:** Scout
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §SCOUT-1, SCOUT-2
- **Files:** `AIDecisionMaker.gd`, `AIPlayer.gd`, `ScoutPhase.gd`
- **Details:** All scout moves are skipped entirely. Move scouts toward nearest uncontrolled objective while maintaining >9" from enemies.
- **Resolution:** Fixed double `phase_completed` emission in `ScoutPhase._check_scout_progression()` that could corrupt phase progression. Fixed objective zone lookup index alignment bug in `AIDecisionMaker._find_best_scout_objective()`. Scout logic (`_decide_scout`, `_execute_ai_scout_movement`) verified working with 32 passing unit tests covering movement, 9" enemy distance, fractional moves, and objective scoring.

### T7-13. AI enemy threat range awareness — **DONE**
- **Phase:** Movement
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-TACTIC-4, MOV-2
- **Files:** `AIDecisionMaker.gd` — `_decide_movement()`
- **Details:** No pre-measurement of enemy threat ranges before moving. Calculate all enemy threat ranges (movement + charge for melee, weapon ranges for shooting), add threat penalty for destinations within 12" of dangerous melee enemies.
- **Resolution:** Enemy threat ranges (charge: M+12"+1", shooting: max weapon range) are calculated once per movement phase and used in assignment scoring, position evaluation, and safer-position finding. Added 12" close melee proximity penalty (`THREAT_CLOSE_MELEE_PENALTY`) that adds extra danger for positions within raw charge range of melee enemies. Enhanced `_estimate_enemy_threat_level()` to factor in melee weapon quality (attacks, strength, AP, damage). All movement paths (normal, advance, hold) use threat data.

### T7-14. AI shooting range consideration in movement — **DONE**
- **Phase:** Movement
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §MOV-1
- **Files:** `AIDecisionMaker.gd` — `_decide_movement()`
- **Details:** May move units out of their weapon range toward objectives. Consider weapon ranges when scoring movement destinations to maintain firing positions.
- **Resolution:** Enhanced movement destination scoring in `_assign_units_to_objectives` to evaluate weapon range at estimated destination — objectives that maintain firing positions get a bonus (`WEIGHT_FIRING_POSITION_KEPT`), those that lose all targets get a penalty (`WEIGHT_FIRING_POSITION_LOST`), and those that bring new enemies into range get a smaller bonus (`WEIGHT_FIRING_POSITION_GAINED`). Added firing position preservation in movement execution: when a ranged unit's direct path to the objective would lose all shooting targets, `_find_firing_position_toward_objective` samples positions in a 180° arc to find the path that maintains weapon range while making maximum progress toward the objective, then blends the movement target accordingly.

### T7-15. AI screening and deep strike denial — **DONE**
- **Phase:** Movement
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-TACTIC-3, MOV-4
- **Files:** `AIDecisionMaker.gd` — `_compute_screen_position()` (exists but never called)
- **Details:** `_compute_screen_position()` exists but is disconnected from any decision path. Wire into pass 3 of unit assignment. Space cheap units 18" apart to create deep strike denial bubbles. Identify enemy units in reserves and calculate 9" denial zones.
- **Resolution:** Wired `_compute_screen_position()` into Pass 3 of unit assignment. Added `_get_enemy_reserves()` to detect enemy units in reserves, `_is_screening_candidate()` to identify cheap expendable units, and `_calculate_denial_positions()` to compute 9" deep strike denial zones around home objectives and backfield gaps. Cheap unassigned units are now prioritized for screening duty, spaced 18" apart for full denial coverage. Added explicit "screen" action handling in the movement execution phase.

### T7-16. AI reserves deployment — **DONE**
- **Phase:** Movement
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §MOV-8
- **Files:** `AIDecisionMaker.gd` — `_decide_movement()`
- **Details:** Units in reserves never brought onto the board from Round 2+. Implement reserves arrival logic with 9" enemy distance check and board edge placement rules.
- **Resolution:** Added `_decide_reserves_arrival()` to handle AI reserve unit deployment from Round 2+. The AI now checks for PLACE_REINFORCEMENT available actions before normal movement, scores units by deployment urgency (points value, round urgency, contested objectives), and computes valid placement positions. Strategic reserves are placed within 6" of board edges (with Turn 2 opponent zone restriction), deep strike units are placed near objectives. All placements enforce the 9" enemy distance rule (edge-to-edge). Updated AIPlayer.gd to emit `ai_unit_deployed` signal for reinforcement visuals.

### T7-17. AI leader attachment in formations — **DONE**
- **Phase:** Formations
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §AI-GAP-8, FORM-1
- **Files:** `AIDecisionMaker.gd` — `_decide_formations()`
- **Details:** `_decide_formations()` immediately confirms without evaluating leader-bodyguard pairings. Attach leaders based on ability synergies ("while leading" bonuses like re-rolls, FNP, +1 to hit).
- **Resolution:** Replaced stub `_decide_formations()` with synergy-based leader attachment. Added `_evaluate_best_leader_attachment()` and `_score_leader_bodyguard_pairing()` which simulate each character-bodyguard pairing using `AIAbilityAnalyzer` multipliers (offensive ranged/melee, defensive FNP/cover, tactical bonuses like fall-back-and-charge). Scoring scales by model count and point value. AI attaches all leaders optimally, then confirms. 16/16 tests pass.

### T7-18. AI terrain-aware deployment — **DONE**
- **Phase:** Deployment
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §DEPLOY-1
- **Files:** `AIDecisionMaker.gd` — `_decide_deployment()`
- **Details:** Units placed without regard to cover or LoS-blocking terrain. Position shooting units behind LoS blockers, use cover positions for fragile units.
- **Resolution:** Added terrain-aware deployment to `_decide_deployment()`. New `_classify_deployment_role()` categorizes units as character/fragile_shooter/durable_shooter/melee/general based on keywords, weapons, and stats. New `_score_terrain_for_role()` evaluates terrain pieces (LoS blockers, cover) for each role. New `_find_terrain_aware_position()` generates candidate positions around terrain features in the deployment zone and scores them by terrain value, objective proximity, depth preference, and drift from baseline. Characters hide behind LoS blockers (tall ruins), fragile shooters seek cover and LoS blocking, melee units deploy near front-edge LoS blockers for charge lanes. Falls back to column-based layout when no useful terrain exists. 20/20 tests pass.

### T7-19. AI turn summary panel — **DONE**
- **Phase:** UI
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §QoL-1
- **Files:** `AIPlayer.gd` (signals exist: `ai_action_taken`, `ai_turn_ended`, `_action_log`), new UI scene
- **Details:** AI actions logged to console only. Create turn summary panel consuming existing signals to show units moved, shooting results, charge results, fight results after each AI turn.
- **Resolution:** Created `AITurnSummaryPanel.gd` — a procedurally-built PanelContainer that connects to `ai_turn_ended` signal. Displays categorized summary per phase (units moved, units fired, charges declared, units fought, stratagems used, reinforcements, etc.) with notable action descriptions. Uses WhiteDwarf gothic theme, auto-dismisses after 12s, dismissible via button/Escape. Wired up in Main.gd alongside existing AI overlay panels.

### T7-20. AI thinking indicator — **DONE**
- **Phase:** UI
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §QoL-2
- **Files:** `AIPlayer.gd`, `Main.gd`, new test
- **Details:** No visual feedback during AI processing — game appears frozen for 50ms between actions. Show "AI is thinking..." indicator with spinner or pulsing animation during AI evaluation.
- **Resolution:** Added `_ai_thinking` state tracking to AIPlayer.gd with `ai_turn_started`/`ai_turn_ended` signal emissions. Created pulsing "AI is thinking..." overlay in Main.gd (WhiteDwarf-themed PanelContainer with animated ellipsis dots and modulate pulse). Connected via `_initialize_ai_player()`. 15/15 tests pass.

### T7-21. AI movement path visualization — **DONE**
- **Phase:** UI
- **Priority:** HIGH
- **Source:** AI_AUDIT.md §VIS-1
- **Files:** `AIPlayer.gd`, `GhostVisual.gd`
- **Details:** AI units teleport to destinations with no movement path shown. Draw brief movement trail (dotted line or arrow) from origin to destination during AI movement, fade after 1-2 seconds.
- **Resolution:** Created `AIMovementPathVisual.gd` — a Node2D that draws dashed movement trails with arrowheads and origin markers from each model's origin to destination, with player-themed colors (blue P1, red P2). Holds for 1.5s then fades over 0.8s, auto-frees on completion. Integrated into `AIPlayer._execute_ai_movement()` and `_execute_ai_scout_movement()` by capturing model positions before staging and spawning the visual after confirmed moves.

### P2 — Medium: AI Competence & Feel Improvements

### T7-22. AI target priority framework — **DONE**
- **Phase:** Shooting
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-TACTIC-1
- **Files:** `AIDecisionMaker.gd`
- **Details:** No macro-level threat assessment. Implement two-level priority: macro (rank enemies by threat level, damage output, objective presence, ability value) and micro (allocate weapons to maximize total expected value, not just per-weapon damage).
- **Resolution:** Implemented two-level target priority framework: (1) Macro-level `_calculate_target_value` enhanced with points-weighted base value, probability-weighted damage output, ability value assessment (offensive/defensive multipliers from AIAbilityAnalyzer), enhanced objective/OC scoring, and leader buff priority. (2) Micro-level `_build_focus_fire_plan` replaced greedy-per-target allocation with iterative marginal value optimization via `_calculate_marginal_value` that considers kill threshold crossing bonuses, model kill milestones, overkill decay, and opportunity cost across all targets.

### T7-23. AI multi-phase planning — **DONE**
- **Phase:** All
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-TACTIC-6
- **Files:** `AIDecisionMaker.gd`
- **Details:** Each phase decided independently. Movement should consider shooting lanes and charge angles; shooting should not target units planned for charge; charge should prefer locking dangerous shooting units in combat. Expand existing round-1 urgency scoring approach.
- **Resolution:** Added `_build_phase_plan()` cross-phase coordinator built once at movement phase start. Three plan components: (1) `charge_intent` identifies melee units likely to charge and their targets, movement blends toward charge angle; (2) `shooting_lanes` tracks ranged unit targets, `_build_focus_fire_plan` suppresses target value for charge targets via `PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET`; (3) `lock_targets` identifies dangerous enemy shooters (ranged output >= 5.0), `_score_charge_target` gives `PHASE_PLAN_LOCK_SHOOTER_BONUS` for locking them in combat. Expanded urgency scoring from round-1-only to all 5 rounds: R1 rush, R2 contest, R3 consolidate, R4-5 aggressive push. 34/34 tests pass.

### T7-24. AI trade and tempo awareness — **DONE**
- **Phase:** All
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-TACTIC-7
- **Files:** `AIDecisionMaker.gd`
- **Details:** No tracking of unit points values. Use `unit.meta.points` for points-per-wound calculations. Adjust aggression based on VP score differential and turn count.
- **Resolution:** Added points-per-wound (PPW) calculation using `unit.meta.points` for trade efficiency analysis. Integrated trade efficiency into target value scoring and charge target evaluation. Added tempo modifier system that adjusts AI aggression based on VP score differential and battle round (desperation mode in rounds 4-5 when behind). Applied tempo to objective urgency scoring, focus fire target prioritization, and charge threshold decisions.

### T7-25. AI secondary mission awareness
- **Phase:** Command/Movement/Scoring
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-TACTIC-8, SCORE-1
- **Files:** `AIDecisionMaker.gd`, `SecondaryMissionManager.gd`
- **Details:** `_decide_scoring()` immediately ends the scoring phase. Evaluate active secondary missions in command phase, factor secondary conditions into movement positioning, discard unachievable secondaries for +1 CP.

### T7-26. AI Heavy weapon stationary bonus
- **Phase:** Movement
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §MOV-3
- **Files:** `AIDecisionMaker.gd` — `_decide_movement()`
- **Details:** Heavy weapon bonus not considered when deciding to move. Prefer remaining stationary when Heavy bonus (+1 to hit) is significant vs. the objective benefit of moving.

### T7-27. AI engaged unit survival assessment — **DONE**
- **Phase:** Movement
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §MOV-9
- **Files:** `AIDecisionMaker.gd` — `_decide_movement()`
- **Details:** Doesn't estimate fight-phase damage before hold/fall-back decision. Calculate expected melee damage to the unit to inform whether to hold position or fall back.
- **Resolution:** Added survival assessment helpers (`_get_engaging_enemy_units`, `_estimate_incoming_melee_damage`, `_estimate_unit_remaining_wounds`, `_assess_engaged_unit_survival`) that estimate expected fight-phase damage from all engaging enemies. Integrated into `_decide_engaged_unit()`: units on objectives facing lethal melee damage now fall back when other friendlies can hold; sole holders stay but log the lethal threat; fall-back reasons enriched with survival data. Added 23 tests in `test_ai_survival_assessment.gd`.

### T7-28. AI multi-weapon melee optimization — **DONE**
- **Phase:** Fight
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-GAP-7, FIGHT-3
- **Files:** `AIDecisionMaker.gd` — `_assign_fight_attacks()`
- **Details:** Only first melee weapon used — `_assign_fight_attacks()` picks first melee weapon found. Evaluate all melee profiles per target, account for Extra Attacks weapons, pick damage-maximizing weapon combination.
- **Resolution:** Rewrote `_assign_fight_attacks()` to evaluate all melee weapon profiles against all enemy targets. Separates weapons into primary and Extra Attacks categories, calculates expected damage per weapon×target combination (including EA weapon bonus since FightPhase auto-injects them), and picks the damage-maximizing primary weapon + target pair. Added `_evaluate_melee_weapon_damage()` and `_weapon_has_extra_attacks()` helpers. CCW fallback evaluated alongside named weapons. All existing fight/charge/consolidation/pile-in tests pass.

### T7-29. AI fight target optimization — **DONE**
- **Phase:** Fight
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §FIGHT-4
- **Files:** `AIDecisionMaker.gd` — `_assign_fight_attacks()`
- **Details:** Melee target selection is nearest-distance only, not damage-optimal. Score targets by expected damage output and strategic value.
- **Resolution:** Rewrote `_assign_fight_attacks()` to score targets by combined damage output + strategic value via new `_score_fight_target()`. Filters targets to engagement range first. Strategic scoring includes: kill potential bonus (wipe/half-strength), CHARACTER priority, overkill penalty, lock-dangerous-shooters bonus, objective presence, low-toughness bonus, defensive ability awareness, and trade efficiency (points-per-wound). Preserves T7-28 multi-weapon optimization within the new per-target scoring loop.

### T7-30. AI range-band optimization — **DONE**
- **Phase:** Shooting/Movement
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §SHOOT-6
- **Files:** `AIDecisionMaker.gd`
- **Details:** No half-range bonus awareness. Position for Rapid Fire extra shots at half range. Prioritize Melta bonus damage at half range.
- **Resolution:** Added half-range weapon analysis (`_get_unit_half_range_data`, `_find_best_half_range_position`) that detects Rapid Fire and Melta keywords. Movement phase now blends target positions toward half-range of enemies when the damage bonus is significant (40% blend weight). Modified `_should_hold_for_shooting` to not hold stationary when advancing would reach half range for RF/Melta weapons. Damage estimation already correctly handled via existing `_apply_weapon_keyword_modifiers`.

### T7-31. AI cover consideration in target scoring — **DONE**
- **Phase:** Shooting
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §SHOOT-7
- **Files:** `AIDecisionMaker.gd` — `_score_shooting_target()`
- **Details:** Benefit of Cover not factored into target scoring. Penalize targets with cover (+1 to save) in expected damage calculation.
- **Resolution:** Added `_target_has_benefit_of_cover()` (checks terrain-based cover via majority-of-models polygon intersection + effect/flag-granted cover), `_check_position_has_terrain_cover()` (mirrors RulesEngine cover rules for ruins/obstacles/barricades within+behind and woods/craters within-only), and `_weapon_ignores_cover()` (checks weapon special_rules and effect flags). Both `_score_shooting_target()` and `_estimate_weapon_damage()` now apply cover as +1 to armour save (min 2+) when target has cover and weapon doesn't ignore it. Cover correctly interacts with invulnerable saves (only affects armour save comparison). 24/24 tests pass.

### T7-32. AI Counter-Offensive stratagem usage — **DONE**
- **Phase:** Fight
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §FIGHT-5
- **Depends on:** T4-3 (Counter-Offensive implementation — DONE)
- **Files:** `AIDecisionMaker.gd`, `StratagemManager.gd`
- **Details:** AI never uses Counter-Offensive (2CP). Use when AI's high-value melee unit is at risk after enemy fights.
- **Resolution:** Added `evaluate_counter_offensive()` in AIDecisionMaker.gd with scoring heuristic considering unit value, melee capability, CHARACTER/MONSTER/VEHICLE keywords, wound status, model count, and engagement risk (multiple enemies in range). Connected `counter_offensive_opportunity` signal in AIPlayer.gd with handler that evaluates and submits via `_submit_reactive_action()`. Added AI player check in FightController.gd to skip the Counter-Offensive dialog for AI players. Uses same 2CP cost threshold (3.0 score) as Heroic Intervention with CP conservation when reserves are tight.

### T7-33. AI transport usage — **DONE**
- **Phase:** Formations/Movement
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §FORM-2, MOV-7
- **Files:** `AIDecisionMaker.gd`
- **Details:** Transports never used. Embark small/fast units in formations for deployment efficiency, disembark during movement when beneficial for objective control or shooting.
- **Resolution:** Added `_evaluate_transport_embarkation()` and `_score_unit_for_embarkation()` for FORM-2: AI scores units for transport embarkation based on fragility (T/Sv/W), model count, weapon range, movement speed, OC, and points value, then greedily fills transports during formations phase. Added `_decide_transport_disembark()`, `_score_disembark_benefit()`, and `_compute_disembark_positions()` for MOV-7: AI evaluates disembarking based on objective proximity, shooting/charge opportunities, battle round, and transport safety; computes valid positions within 3" of transport edge avoiding engagement range and overlaps.

### T7-34. AI reserves declarations — **DONE**
- **Phase:** Formations
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §FORM-3
- **Files:** `AIDecisionMaker.gd` — `_decide_formations()`
- **Details:** No reserves declaration — all units deployed on table unless deployment fails. Put appropriate units in Strategic Reserves or Deep Strike based on army composition and mission.
- **Resolution:** Added `_evaluate_reserves_declarations()` and `_score_unit_for_reserves()` to AIDecisionMaker.gd. AI now parses DECLARE_RESERVES actions during formations phase (after leader attachments and transport embarkations). Scores units by reserve suitability: Deep Strike melee units highest priority (8.0), followed by DS short-range shooters (5.0), strategic reserves melee/fast units (4.0+speed). Exclusions for CHARACTER leaders, FORTIFICATION, embarked units. Universal modifiers penalize VEHICLE/MONSTER ranged, long-range shooters, cheap screens. Respects 25% points cap and 50% unit cap. Score threshold of 2.0 prevents marginal reserves.

### T7-35. AI Rapid Ingress stratagem usage — **DONE**
- **Phase:** Movement
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §AI-GAP-3 Phase 3
- **Depends on:** T4-7 (Rapid Ingress implementation — DONE)
- **Files:** `AIDecisionMaker.gd`, `StratagemManager.gd`
- **Details:** AI never uses Rapid Ingress to arrive from reserves at end of opponent's movement phase.
- **Resolution:** Added `evaluate_rapid_ingress()` static method to AIDecisionMaker.gd — scores reserve units for deployment urgency (reusing `_score_reserves_deployment`, `_compute_reinforcement_positions` logic), with Rapid Ingress-specific adjustments for late-game urgency and CP cost penalty. Connected `rapid_ingress_opportunity` signal in AIPlayer.gd `_connect_phase_stratagem_signals()`. Added `_on_movement_rapid_ingress_opportunity()` handler with Hard+ difficulty gate via `AIDifficultyConfigData.use_stratagems()`. Implemented two-step `_execute_rapid_ingress_sequence()` for USE_RAPID_INGRESS then PLACE_RAPID_INGRESS_REINFORCEMENT. Score threshold of 3.0, CP conservation (declines with ≤1 CP before Round 4). Added `USE_RAPID_INGRESS` and `PLACE_RAPID_INGRESS_REINFORCEMENT` to spectator action categorization. Added 4 tests to `test_ai_stratagem_evaluation.gd`.

### T7-36. AI speed controls — **DONE**
- **Phase:** UI/Settings
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §QoL-3
- **Files:** `AIPlayer.gd`
- **Details:** `AI_ACTION_DELAY` hardcoded to 50ms. Add speed slider in settings: Fast (0ms), Normal (200ms), Slow (500ms), Step-by-step (pause after each action).
- **Resolution:** Added `AISpeedPreset` enum (FAST/NORMAL/SLOW/STEP_BY_STEP) with configurable delays (0ms/200ms/500ms/pause) to AIPlayer.gd, replacing hardcoded 50ms delay. Added speed dropdown to MainMenu.gd (shown when any player is AI). In-game HUD panel shows current speed with comma/period/slash keyboard shortcuts to adjust. Step-by-step mode pauses after each action with "Continue (Space)" button. Speed persisted in game_config.

### T7-37. AI decision explanations — **DONE**
- **Phase:** UI
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §QoL-4
- **Files:** `AIDecisionMaker.gd`, `GameEventLog.gd`
- **Details:** `_ai_description` strings are terse. Route key decisions through `GameEventLog.add_ai_entry()` with enhanced reasoning (e.g., "Lascannon shoots at Battlewagon — expected 4.2 damage, 67% kill probability").
- **Resolution:** Enhanced `_ai_description` strings across shooting (expected damage vs HP, kill %), charge (melee damage estimate, charge probability), fight (weapon + expected damage vs HP), deployment (grid position), and reactive stratagems (protection score, points). Key tactical decisions (SHOOT, DECLARE_CHARGE, ASSIGN_ATTACKS, stratagems) are now explicitly routed through `GameEventLog.add_ai_entry()` via AIPlayer for UI visibility.

### T7-38. AI shooting target line visualization — **DONE**
- **Phase:** UI
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §VIS-2
- **Files:** `AIPlayer.gd`, `ShootingLineVisual.gd`
- **Details:** No visual connection between shooter and target during AI shooting. Draw brief targeting line (red) from shooting unit to target, show hit/wound results as floating text near target.
- **Resolution:** Added `ai_shooting_visual` signal to ShootingPhase emitted during AI atomic shoot path. ShootingController creates red ShootingLineVisual (with customizable color/hold via new properties) from shooter to each target with brief 1.5s hold and auto-cleanup. Also emits `shooting_damage_applied` in AI path for floating damage numbers/death animations via existing DamageFeedbackVisual. Added `play_result_summary()` to DamageFeedbackVisual showing "X hits, Y wounds → Z slain" floating text near target.

### T7-39. AI objective control flash on change — **DONE**
- **Phase:** UI
- **Priority:** MEDIUM
- **Source:** AI_AUDIT.md §VIS-4
- **Files:** New visual component
- **Details:** Objective control changes during AI movement not highlighted. Flash objective markers when control state changes (green flash on AI capture, red on loss).
- **Resolution:** Added `flash_control_change()` to ObjectiveVisual.gd with pulsing ring animation (green on AI capture, red on AI loss, yellow on contested). Updated `objective_control_changed` signal in MissionManager.gd to include old_controller. Added real-time objective rechecks after movement confirmation (MovementPhase.gd) and charge completion (ChargePhase.gd) via `call_deferred`. Flash triggers for all control changes during any movement, not just AI.

### P3 — Low: Polish & Competitive-Level Play

### T7-40. AI difficulty levels — **DONE**
- **Phase:** Settings
- **Priority:** LOW
- **Source:** AI_AUDIT.md §QoL-5
- **Files:** `AIPlayer.gd`, `AIDecisionMaker.gd`, `AIDifficultyConfig.gd`, `MainMenu.gd`, `Main.gd`
- **Details:** Single difficulty level. Implement Easy (random valid actions), Normal (current + Tier 7 P0/P1 fixes), Hard (full tactics + stratagems), Competitive (look-ahead planning + optimal stratagem timing).
- **Resolution:** Created `AIDifficultyConfig.gd` with Easy/Normal/Hard/Competitive enum and per-level feature flags (stratagems, multi-phase planning, focus fire, threat awareness, trade analysis, look-ahead, score noise, charge thresholds). Updated `AIPlayer.gd` to store per-player difficulty and gate reactive stratagems/overwatch/counter-offensive/command reroll by level. Updated `AIDecisionMaker.gd` with `_decide_random()` for Easy mode (random valid actions with required sequencing), difficulty noise on movement/charge scoring, stratagem gating for Normal-, and multi-phase plan suppression for Normal-. Added difficulty dropdowns to MainMenu UI (auto-shown when player type is AI). Config flows through `game_config` to `Main.gd` → `AIPlayer.configure()`.

### T7-41. AI army-specific strategies
- **Phase:** All
- **Priority:** LOW
- **Source:** AI_AUDIT.md §QoL-6
- **Files:** `AIDecisionMaker.gd`
- **Details:** Identical heuristics regardless of army. Detect archetype based on weapon/keyword distribution: melee-focused (aggressive advance, early charges), shooting-focused (castle, maintain range), balanced, elite (protect key models).

### T7-42. AI move blocking — **DONE**
- **Phase:** Movement
- **Priority:** LOW
- **Source:** AI_AUDIT.md §AI-TACTIC-9
- **Files:** `AIDecisionMaker.gd`
- **Details:** No movement corridor blocking. Identify key corridors between enemy units and objectives, position expendable units to block them.
- **Resolution:** Added `_calculate_corridor_blocking_positions()` that identifies corridors between enemy units (within 30") and high-value objectives, computing blocking positions at 55% along the corridor. Expendable units (`_is_screening_candidate`) assigned to block corridors in PASS 3 of unit assignment, using existing "screen" movement action. Priority based on objective importance + enemy proximity + threat level. Capped at 4 blocking positions with 5" spacing.

### T7-43. AI late-game strategy pivot — **DONE**
- **Phase:** All
- **Priority:** LOW
- **Source:** AI_AUDIT.md §AI-TACTIC-10
- **Files:** `AIDecisionMaker.gd`
- **Details:** Same strategy throughout the game. Implement turn-based modifier: Rounds 1-2 aggressive positioning, Round 3 balance, Rounds 4-5 prioritize objective control and survival over kills.
- **Resolution:** Added `_get_round_strategy_modifiers()` returning per-round aggression, objective_priority, survival, and charge_threshold multipliers. Applied across movement (objective scoring + threat penalties), shooting (target value + objective-presence bonus), charge (threshold + objective-charge bonus), engaged unit decisions (late-game hold bias), and consolidation (prefer objectives over marginal engagements in rounds 4-5).

### T7-44. AI counter-deployment — **DONE**
- **Phase:** Deployment
- **Priority:** LOW
- **Source:** AI_AUDIT.md §DEPLOY-2
- **Files:** `AIDecisionMaker.gd` — `_decide_deployment()`
- **Details:** Doesn't react to opponent's deployment. Adjust unit placement based on where opponent has deployed.
- **Resolution:** Added `_apply_counter_deployment()` and `_get_deployed_enemy_analysis()` to analyze opponent's deployed units during alternating deployment. AI categorizes enemy units by role (melee/shooter/high-value) and adjusts placement per own unit role: melee units shift toward enemy fragile targets, fragile shooters shift away from enemy melee, durable shooters orient toward enemy concentrations, characters avoid enemy shooting. Gated behind `use_counter_deployment()` at Normal+ difficulty. Also added `use_counter_deployment()` to AIDifficultyConfig.gd.

### T7-45. AI faction ability activation — **DONE**
- **Phase:** Command
- **Priority:** LOW
- **Source:** AI_AUDIT.md §CMD-3
- **Files:** `AIDecisionMaker.gd` — `_decide_command()`
- **Details:** No faction ability activation. Select Oath of Moment target based on focus-fire plan, declare Waaagh! at optimal timing (Orks).
- **Resolution:** Added `_select_oath_of_moment_target()` to AIDecisionMaker.gd with strategic threat-based scoring. Reuses `_calculate_target_value()` macro priority (points, damage output, objectives, abilities) plus Oath-specific bonuses: toughness scaling (T5+ gets 5% per T above 4), good-save bonus (Sv2+/3+ gets 10%), remaining-wounds scaling (6+ wounds), and below-half-strength bonus (1.2x). Integrated into `_decide_command()` after battle-shock tests. 13/13 tests pass.

### T7-46. AI fight order optimization — **DONE**
- **Phase:** Fight
- **Priority:** LOW
- **Source:** AI_AUDIT.md §FIGHT-6
- **Files:** `AIDecisionMaker.gd`
- **Details:** No consideration of which unit to activate first in fight phase for best overall outcomes.
- **Resolution:** Added `_build_fight_order_plan()` and `_score_fighter_priority()` to AIDecisionMaker.gd. When multiple AI units are eligible to fight, the AI now scores each by kill potential, target value, vulnerability, and damage output to determine optimal activation order. Uses the same plan-cache pattern as the shooting focus fire plan.

### T7-47. AI secondary mission discard logic — **DONE**
- **Phase:** Scoring
- **Priority:** LOW
- **Source:** AI_AUDIT.md §SCORE-2
- **Files:** `AIDecisionMaker.gd` — `_decide_scoring()`
- **Details:** Never discards unachievable secondary missions for +1 CP.
- **Resolution:** Replaced stub `_decide_scoring()` with full mission achievability evaluation. Added `_secondary_mission_manager()` accessor, `_evaluate_mission_achievability()` dispatcher, and 14 mission-specific assessors (kill-based: check if valid targets still alive; positional: check if AI has enough units; objective: check if relevant objectives exist; action: check if AI has units to perform actions; while-active: always keep if enemies exist). AI discards lowest-scoring mission when achievability score falls below threshold (0.2), gaining +1 CP. Late-game with empty deck uses lower threshold (0.1). 16/16 tests pass.

### T7-48. AI Pistol usage in engagement range
- **Phase:** Shooting
- **Priority:** LOW
- **Source:** AI_AUDIT.md §SHOOT-9
- **Files:** `AIDecisionMaker.gd` — `_decide_shooting()`
- **Details:** Doesn't fire Pistols when units are in engagement range.

### T7-49. AI counter-play to opponent defensive stratagems — **DONE**
- **Phase:** Shooting
- **Priority:** LOW
- **Source:** AI_AUDIT.md §SHOOT-10
- **Files:** `AIDecisionMaker.gd`
- **Details:** Doesn't penalize targets with active defensive buffs (Smokescreen, Go to Ground) in target scoring.
- **Resolution:** Added strategic deprioritization (×0.80) in `_score_shooting_target()` for targets with active effect-granted cover, stealth, or invulnerable saves from defensive stratagems. This is applied on top of the existing mechanical damage reductions, encouraging the AI to redirect firepower to softer targets.

### T7-50. AI multi-target charge declarations — **DONE**
- **Phase:** Charge
- **Priority:** LOW
- **Source:** AI_AUDIT.md §CHARGE-4
- **Depends on:** T7-1 (basic charge implementation)
- **Files:** `AIDecisionMaker.gd`
- **Details:** Declare charges against multiple nearby enemies when beneficial.
- **Resolution:** Added `_evaluate_multi_target_charge()` and `_score_multi_target_combo()` to evaluate 2- and 3-target charge combinations. Per 10th Edition rules, charge probability is based on the farthest target (must reach all), while combined target scores determine benefit. Multi-target bonus (+15% per extra target) and clustering bonus reward engaging grouped enemies. AI correctly picks multi-target when targets are close together and single-target when the probability cost is too high.

### T7-51. AI overwatch risk assessment for charges — **DONE**
- **Phase:** Charge
- **Priority:** LOW
- **Source:** AI_AUDIT.md §CHARGE-5
- **Depends on:** T7-1 (basic charge implementation)
- **Files:** `AIDecisionMaker.gd`
- **Details:** Weigh charge benefit vs. expected overwatch damage before declaring charges.
- **Resolution:** Added `_estimate_overwatch_risk()` and `_estimate_unit_overwatch_damage()` functions to AIDecisionMaker.gd. The AI now evaluates the best enemy overwatch shooter (within 24", with CP, with ranged weapons) and calculates expected damage using hit-on-6s, wound probability, save probability, wound overflow cap, and FNP. Risk is classified as low/moderate/high/extreme with corresponding score penalties applied to charge evaluations. Extra caution is applied for CHARACTER units and when overwatch could kill 50%+ of the charger's HP.

### T7-52. AI unit highlighting during actions — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §VIS-5
- **Files:** New visual component
- **Details:** No visual distinction for which unit the AI is currently acting with. Add glow/highlight ring (blue=move, red=shoot, orange=charge).
- **Resolution:** Created `AIUnitHighlight.gd` — a pulsing glow ring Node2D component with three layers (outer glow, main ring, inner fill). Integrated into `Main.gd`: the `_on_ai_action_taken` handler maps action types to colors (blue=movement, red=shooting, orange=charge/fight) and places highlight rings around all models of the AI's active unit. Highlights track token positions during movement and auto-clear on phase end or AI turn end.

### T7-53. AI floating damage numbers — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §VIS-6
- **Files:** `DamageFeedbackVisual.gd`
- **Details:** Show floating damage numbers above targets during AI combat and kill notifications on unit destruction.
- **Resolution:** Added `shooting_damage_applied` signal to `ShootingPhase.gd` that fires after save resolution with damage diffs. Added floating damage number display to `ShootingController.gd` (new `_on_shooting_damage_visual` handler, matching `FightController` pattern). Added floating numbers to `WoundAllocationOverlay.gd` for interactive saves. Added `play_kill_notification()` method to `DamageFeedbackVisual.gd` for "UNIT DESTROYED" banners. Added kill notification checks to both `FightController.gd` and `ShootingController.gd` for full unit wipes.

### T7-54. AI action log overlay — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §VIS-7
- **Files:** New UI component
- **Details:** Small scrolling text overlay in corner showing real-time AI actions as they happen.
- **Resolution:** Created `AIActionLogOverlay.gd` — a small scrolling overlay anchored to the bottom-right corner that shows real-time AI actions as they happen. Color-coded entries (blue for P1, red for P2) with phase headers in gold. Auto-fades after 8s of inactivity, auto-scrolls, trims old entries. Connected to `ai_action_taken`, `ai_turn_started`, and `ai_turn_ended` signals in Main.gd.

### T7-55. AI vs AI spectator mode improvements — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §QoL-7
- **Files:** `AIPlayer.gd`
- **Details:** AI vs AI flies by with no ability to follow. Auto-slow action delay and show turn summaries for both players in spectator mode.
- **Resolution:** Added spectator mode detection when both players are AI. Action delay auto-slows from 50ms to 500ms (adjustable via speed presets 0.25x-4.0x using comma/period/slash keys). Phase summaries emitted at each phase transition showing action counts per player. AIActionLogOverlay displays formatted summaries with longer fade delay. Speed indicator HUD shown at top-center during spectator mode.

### T7-56. AI turn replay — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §QoL-8
- **Files:** `AIPlayer.gd`, `ReplayManager.gd`
- **Details:** No way to review AI actions after turn passes. Store full action log per turn and provide replay panel accessible from game menu.
- **Resolution:** Added per-turn action history storage in AIPlayer.gd (`_turn_history`, `_store_turn_history()`, `get_turn_history()`). Created AITurnReplayPanel.gd — a centered, scrollable, WhiteDwarf-themed panel showing all past AI actions organized by battle round, with prev/next turn navigation and color-coded phase headers. Panel toggles with 'R' key and closes with ESC or X button. Added turn-grouped query methods to ReplayManager.gd for recorded events.

### T7-57. AI post-game performance summary — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §QoL-9
- **Files:** New UI component
- **Details:** No post-game AI analysis. Show total VP scored, units lost vs units killed, objectives held per turn, CP spent, key moments.
- **Resolution:** Extended GameOverDialog.gd with an "AI Performance Analysis" section that shows per-AI-player stats: VP breakdown (total/primary/secondary), units killed vs lost, units/models remaining, CP spent/remaining, objectives held per round, and key moments (stratagem uses, VP scoring). Added performance tracking infrastructure to AIPlayer.gd (record_ai_cp_spent, record_ai_unit_killed, record_ai_unit_lost, record_ai_objectives, record_ai_key_moment, get_performance_summary). Hooked tracking into ShootingPhase.gd, FightPhase.gd (unit kill/loss), ScoringPhase.gd (objectives per round), and AIPlayer reactive/proactive action flows (CP spent, key moments). Connected to MissionManager.victory_points_scored signal for VP key moments.

### T7-58. AI charge arrow visualization — **DONE**
- **Phase:** UI
- **Priority:** LOW
- **Source:** AI_AUDIT.md §VIS-3
- **Depends on:** T7-1 (basic charge implementation)
- **Files:** New visual component
- **Details:** Draw charge declaration arrows (orange/yellow) from charger to target, show charge roll result prominently.
- **Resolution:** Created ChargeArrowVisual.gd — animated arrow component with state machine (idle→line_draw→hold→fade), orange/yellow arrowhead with glow effects, and prominent charge roll result label at midpoint. Integrated into ChargeController.gd for both human player (target selection creates static arrows) and AI player (Main.gd listens to ai_action_taken for DECLARE_CHARGE and triggers animated arrows via show_ai_charge_arrows). Arrows update color to green/red on charge roll success/failure and display roll total prominently.

---

## Code TODOs Not Covered by Audit Files

The following TODOs were found in code but were not tracked in any existing audit document. They have been assigned to the most relevant tier above:

| File | Line | TODO | Assigned To |
|------|------|------|-------------|
| ~~`MoralePhase.gd`~~ | ~~7-8~~ | ~~Stub implementation for Morale phase~~ | ~~T1-4~~ **DONE** |
| ~~`MoralePhase.gd`~~ | ~~107-109~~ | ~~Add stratagem validation for morale~~ | ~~T1-4~~ **DONE** |
| ~~`MoralePhase.gd`~~ | ~~164-165~~ | ~~Remove models due to morale failure~~ | ~~T1-4~~ **DONE** |
| ~~`MoralePhase.gd`~~ | ~~203-204~~ | ~~Implement actual stratagem effects~~ | ~~T1-4~~ **DONE** |
| ~~`MoralePhase.gd`~~ | ~~339-343~~ | ~~Implement morale modifiers (keywords, characters, conditions)~~ | ~~T1-4~~ **DONE** |
| ~~`MoralePhase.gd`~~ | ~~357-359~~ | ~~Add helper methods for morale mechanics~~ | ~~T1-4~~ **DONE** |
| ~~`FightPhase.gd`~~ | ~~947~~ | ~~Integrate full mathhammer simulation for melee~~ | ~~T5-UX14~~ **DONE** |
| ~~`FightPhase.gd`~~ | ~~1022-1023~~ | ~~Heroic intervention not yet implemented~~ | ~~T2-7~~ **DONE** |
| ~~`FightPhase.gd`~~ | ~~1635-1637~~ | ~~Add heroic intervention specific validation~~ | ~~T2-7~~ **DONE** |
| ~~`LineOfSightCalculator.gd`~~ | ~~79~~ | ~~Handle medium/low terrain based on model height~~ | ~~T3-19~~ **DONE** |
| ~~`MathhammerUI.gd`~~ | ~~738~~ | ~~Implement custom drawing for visual histogram~~ | ~~T5-V15~~ **DONE** |
| ~~`ScoringController.gd`~~ | ~~148~~ | ~~Score objectives not implemented~~ | ~~T5-UX13~~ **DONE** |
| `NetworkManager.gd` | 1474 | Show game over UI with winner and reason | T5-MP7 |
| ~~`test_multiplayer_deployment.gd`~~ | ~~368~~ | ~~Implement collision detection test with turn handling~~ | ~~T6-4~~ **DONE** |
| ~~`test_multiplayer_deployment.gd`~~ | ~~555-557~~ | ~~Complete `assert_unit_deployed()` implementation~~ | ~~T6-4~~ **DONE** |
| ~~`test_multiplayer_deployment.gd`~~ | ~~562-564~~ | ~~Complete `assert_unit_not_deployed()` implementation~~ | ~~T6-4~~ **DONE** |
| ~~`test_multiplayer_deployment.gd`~~ | ~~569~~ | ~~Implement coherency check in tests~~ | ~~T6-4~~ **DONE** |
| ~~`test_multiplayer_deployment.gd`~~ | ~~574~~ | ~~Extract unit model positions from game state~~ | ~~T6-4~~ **DONE** |
| ~~`MultiplayerIntegrationTest.gd`~~ | ~~469~~ | ~~Fix LogMonitor for peer connection tracking~~ | ~~T6-4~~ **DONE** |
| `Mathhammer.gd` | 232-240 | ~~`_extract_damage_from_result()` broken — counts kills as 1 damage~~ **DONE** | T1-9 |
| `MathhammerRuleModifiers.gd` | 58-59 | ~~Twin-linked re-rolls hits instead of wounds~~ **DONE** | T1-10 |
| `MathhammerRuleModifiers.gd` | 77-83 | ~~Anti-keyword uses re-roll instead of crit threshold~~ **DONE** | T2-13 |
| `MathhammerUI.gd` | 953-958 | `create_styled_panel()` removes content_vbox from parent | T3-26 |
| `Mathhammer.gd` | 188-189 | Rapid Fire doubles attacks instead of adding X | T3-20 |

---

## Quick Stats

| Category | Done | Open | Total |
|----------|------|------|-------|
| Tier 1 — Critical Rules | 10 | 0 | 10 |
| Tier 2 — High Rules | 15 | 1 | 16 |
| Tier 3 — Medium Rules | 26 | 0 | 26 |
| Tier 4 — Low/Niche | 14 | 6 | 20 |
| Tier 5 — QoL/Visual | 42 | 9 | 51 |
| Tier 6 — Testing | 3 | 2 | 5 |
| Tier 7 — AI Player | 54 | 4 | 58 |
| **Total** | **158** | **28** | **186** |
| **Recently Completed** | **175** | — | **175** |
| *Mathhammer items (subset)* | *24* | *7* | *31* |

---

## Source Audit Files

| File | Phase | Location |
|------|-------|----------|
| AUDIT_COMMAND_PHASE.md | Command | `/home/user/warhammer-40k-godot/AUDIT_COMMAND_PHASE.md` |
| 40k/AUDIT_COMMAND_PHASE.md | Command | `/home/user/warhammer-40k-godot/40k/AUDIT_COMMAND_PHASE.md` |
| 40k/MOVEMENT_PHASE_AUDIT.md | Movement | `/home/user/warhammer-40k-godot/40k/MOVEMENT_PHASE_AUDIT.md` |
| DEPLOYMENT_AUDIT.md | Deployment | `/home/user/warhammer-40k-godot/DEPLOYMENT_AUDIT.md` |
| SHOOTING_PHASE_AUDIT.md | Shooting | `/home/user/warhammer-40k-godot/SHOOTING_PHASE_AUDIT.md` |
| CHARGE_PHASE_AUDIT.md | Charge | `/home/user/warhammer-40k-godot/CHARGE_PHASE_AUDIT.md` |
| FIGHT_PHASE_AUDIT.md | Fight | `/home/user/warhammer-40k-godot/FIGHT_PHASE_AUDIT.md` |
| 40k/PRPs/fight_phase_audit_report.md | Fight (superseded) | `/home/user/warhammer-40k-godot/40k/PRPs/fight_phase_audit_report.md` |
| TERRAIN_LAYOUTS_AUDIT.md | Terrain | `/home/user/warhammer-40k-godot/TERRAIN_LAYOUTS_AUDIT.md` |
| 40k/TESTING_AUDIT_SUMMARY.md | Testing | `/home/user/warhammer-40k-godot/40k/TESTING_AUDIT_SUMMARY.md` |
| PRPs/gh_issue_93_testing-audit.md | Testing | `/home/user/warhammer-40k-godot/PRPs/gh_issue_93_testing-audit.md` |
| IMPLEMENTATION_VALIDATION.md | Movement (multi-model) | `/home/user/warhammer-40k-godot/IMPLEMENTATION_VALIDATION.md` |
| DEPLOYMENT_FIX_STATUS.md | Deployment (debug) | `/home/user/warhammer-40k-godot/DEPLOYMENT_FIX_STATUS.md` |
| MASTER_AUDIT.md §MATHHAMMER | Mathhammer (inline) | `/home/user/warhammer-40k-godot/MASTER_AUDIT.md` — §MATHHAMMER MODULE AUDIT |
| AI_AUDIT.md | AI Player | `AI_AUDIT.md` |
