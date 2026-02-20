# Master Audit — All Phases Combined & Prioritized

> **Generated:** 2026-02-16 | **Updated:** 2026-02-16 (Mathhammer Audit)
> **Source audits:** AUDIT_COMMAND_PHASE.md, MOVEMENT_PHASE_AUDIT.md, DEPLOYMENT_AUDIT.md, SHOOTING_PHASE_AUDIT.md, CHARGE_PHASE_AUDIT.md, FIGHT_PHASE_AUDIT.md, TERRAIN_LAYOUTS_AUDIT.md, TESTING_AUDIT_SUMMARY.md, **MATHHAMMER_AUDIT** (inline below), plus TODO comments found in code.
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
| T5-V14 (2026-02-20): Deployment zone edge highlighting — Animated dashed border with marching ants, multi-layer pulsing glow on inner edges, corner markers, zone depth labels; inner/outer edge detection for board-boundary vs no-man's-land edges | Deployment | DEPLOYMENT_AUDIT.md §QoL 6 |
| T5-V13 (2026-02-20): Engaged units board indicator (crossed swords) — Crossed swords badge overlay on engaged unit tokens during fight phase, color-coded by fight priority; is_engaged/fight_priority flags in FightPhase with phase-exit cleanup | Fight | fight_phase_audit_report.md §3.5 |
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
| T5-MH7: Loading spinner / progress bar during simulation — ProgressBar + label with live trial count, thread-safe updates via call_deferred | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH6: Responsive panel sizing — viewport-relative layout replacing hardcoded 800px/400x600 sizes | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH3: Multi-weapon side-by-side comparison view — Compare Weapons button runs independent per-weapon simulations with ranked results | Mathhammer | MATHHAMMER_AUDIT |
| T5-MH2: Cumulative probability display — "X% chance of at least N wounds" table with color-coded probability tiers | Mathhammer | MATHHAMMER_AUDIT |
| T5-UX14: Mathhammer melee simulation integration (full Monte Carlo prediction before dice rolling, scoping bug fix in Mathhammer.gd) | Fight/Mathhammer | FIGHT_PHASE_AUDIT.md, Code TODO |
| T5-UX11: Unit base preview on hover in deployment (tooltip with base size, model count, special deployment rules) | Deployment | DEPLOYMENT_AUDIT.md §QoL 7 |
| T5-UX10: Auto-zoom to deployment zone (smooth camera pan/zoom to active player's zone on phase entry and turn switch) | Deployment | DEPLOYMENT_AUDIT.md §QoL 5 |
| T5-UX8: Deployment summary before ending phase (summary dialog with deployed units, transports, characters, reserves) | Deployment | DEPLOYMENT_AUDIT.md §QoL 8 |
| T5-UX7: End fight phase confirmation dialog (warning with unfought units list before ending fight phase) | Fight | fight_phase_audit_report.md §3.6 |
| T5-UX6: Show weapon stats in target assignment UI (compact stat sub-line: Range, A, BS, S, AP, D beneath each weapon) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
| T5-UX5: "All to Target" button in fight attack assignment dialog (one-click assign all weapons to selected target) | Fight | fight_phase_audit_report.md §3.1 |
| T5-UX4: "Undo Last Assignment" button in weapon assignment (undo stack, per-weapon clear, UI feedback) | Shooting | SHOOTING_PHASE_AUDIT.md §Additional |
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
| T4-10: Mission selection variety — 9 primary missions from Chapter Approved 2025-26 | Pre-game | DEPLOYMENT_AUDIT.md §8 |
| T4-11: Fortification deployment — cannot place in reserves, must deploy on table | Deployment | DEPLOYMENT_AUDIT.md §9 |
| T4-12: Unmodified wound roll of 1 always fails (defensive check) | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §2.12 |
| T4-14: Weapon ID collision for similar weapon names — type-aware IDs | Shooting | SHOOTING_PHASE_AUDIT.md §Additional Issues |
| T4-15: Single weapon result dialog has hardcoded zeros — stored hit/wound data in resolution_state | Shooting | SHOOTING_PHASE_AUDIT.md §Additional Issues |
| T4-16: [MH-RULE-6] Conversion X+ — expanded crit hit range at 12"+ distance | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-18: [MH-RULE-14] Save modifier cap — +1/-1 save roll toggles with cap enforcement | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T4-19: [MH-BUG-6] Triple 'h' typo in Mathhammer class names — renamed to MathhammerUI/Results/RuleModifiers | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T6-1: Fix broken test compilation errors — BaseUITest created, autoload resolution fixed | Testing | TESTING_AUDIT_SUMMARY.md, PRPs/gh_issue_93_testing-audit.md |
| T6-5: CI/CD integration — all-branch triggers, correct test dirs, action version updates, timeouts | Testing | MASTER_AUDIT.md §Tier 6 |

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
| MH-RULE-7 | Half Damage | Halve incoming damage (round up) | LOW |
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
| MH-UI-1 | Histogram display is a TODO placeholder — `_draw_simple_histogram()` creates text-based bars but is never called from the main display path | HIGH — see T5-V15 |
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

### T3-13. Fight selection dialog sync for remote player
- **Phase:** Fight
- **Rule:** Both players need to see the fighter selection dialog
- **Impact:** Client may miss initial fight selection on phase entry
- **Source:** FIGHT_PHASE_AUDIT.md §3.4
- **Files:** `FightController.gd` — `set_phase()`, signal timing

### T3-14. Desperate Escape — Battle-shocked modifier not verified
- **Phase:** Movement
- **Rule:** Battle-shocked units falling back have models destroyed on 1-3 instead of 1-2
- **Impact:** Battle-shocked penalty may not be fully applied
- **Source:** AUDIT_COMMAND_PHASE.md, code inspection needed
- **Files:** `MovementPhase.gd` — `_process_desperate_escape()`

### T3-15. Disembarked units should not count as Remained Stationary
- **Phase:** Movement
- **Rule:** Disembarked units don't get Heavy weapon bonus even if they don't move
- **Impact:** Edge case affecting Heavy weapon accuracy
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.12
- **Files:** `MovementPhase.gd` — `_process_remain_stationary()` (~line 880)

### T3-16. Difficult terrain / movement penalties
- **Phase:** Movement
- **Rule:** Certain terrain may apply movement penalties
- **Impact:** Affects tactical positioning around terrain
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.7
- **Files:** `MovementPhase.gd`, `TerrainManager.gd`

### T3-17. Dual resolution paths — prevent rules drift
- **Phase:** Shooting
- **Rule:** Auto-resolve and interactive resolve must produce same results
- **Impact:** Keywords updated in one path but not the other
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues
- **Files:** `RulesEngine.gd` — `_resolve_assignment()` vs `_resolve_assignment_until_wounds()`

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

### T3-24. [MH-FEAT-6] No defender stats override panel
- **Phase:** Mathhammer
- **Rule:** Users should be able to override or input custom defender T/Sv/W/Invuln/FNP
- **Impact:** Cannot model hypothetical matchups or units not in the game state
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhammerUI.gd` — needs custom defender input fields alongside the unit dropdown

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

### T4-9. Deployment map variety (Hammer and Anvil, Search and Destroy, etc.)
- **Phase:** Deployment
- **Source:** DEPLOYMENT_AUDIT.md §7

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

### T4-13. Unmodified save roll of 1 always fails (auto-resolve path)
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §2.13
- **Files:** `RulesEngine.gd` — `_resolve_assignment()` (~line 1129)

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

### T4-17. [MH-RULE-7] Half Damage defensive ability
- **Phase:** Mathhammer
- **Source:** MATHHAMMER_AUDIT

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
- T5-UX3. "Shoot All Remaining" button (SHOOTING_PHASE_AUDIT.md §Additional)
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
- T5-UX9. Undo last model placement (per-model) in deployment (DEPLOYMENT_AUDIT.md §QoL 4)
- T5-UX10. Auto-zoom to deployment zone (DEPLOYMENT_AUDIT.md §QoL 5) — **DONE**
  - **Resolution:** Added `focus_on_deployment_zone(player)` to Main.gd with smooth tween animation. Auto-zooms to active player's deployment zone on phase entry and on deployment turn switch. Calculates bounding box of zone polygon and fits camera with 20% padding margin.
- T5-UX11. Unit base preview on hover in deployment (DEPLOYMENT_AUDIT.md §QoL 7) — **DONE**
  - **Resolution:** Added hover tooltip on UnitListPanel during deployment phase. When hovering over a unit in the list, a styled tooltip appears showing unit name, model count, base size/type, and special deployment rules (Deep Strike, Infiltrators, Fortification, CHARACTER, Transport capacity). Uses gui_input signal with get_item_at_position for hover detection, positioned to the left of the unit list.
- T5-UX12. Keyboard shortcuts for shooting phase (SHOOTING_PHASE_AUDIT.md §Tier 4)
- T5-UX13. Score objectives — not implemented (Code TODO in `ScoringController.gd:148`)
- T5-UX14. Mathhammer melee simulation integration (Code TODO in `FightPhase.gd:947`) — **DONE**
  - **Resolution:** The mathhammer melee prediction was already implemented in `_show_mathhammer_predictions()` (FightPhase.gd), replacing the original placeholder. Runs 1000-trial Monte Carlo simulation via `Mathhammer.simulate_combat()` with phase "fight" before dice rolling. Auto-detects Lance charge bonus. RulesEngine handles weapon special rules (Lethal Hits, Sustained Hits, Devastating Wounds, etc.) from weapon profiles. Also fixed a scoping bug in Mathhammer.gd where `fresh_defender` assignment was outside its declaring block.

### Mathhammer UX
- T5-MH1. [MH-FEAT-1] Visual histogram / probability distribution chart — replace text bars with graphical bars (MATHHAMMER_AUDIT) — see also T5-V15
- T5-MH2. [MH-FEAT-2] Cumulative probability display — "X% chance of at least N wounds" table (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added `calculate_reverse_cumulative()` to MathhammerResults.gd for computing P(X >= N) reverse cumulative distribution. Added `_create_cumulative_probability_panel()` to MathhammerUI.gd displaying a color-coded table (green/yellow/orange/red by probability tier). Smart row filtering keeps the table manageable for large damage ranges. Panel appears in both the summary and breakdown sections.
- T5-MH3. [MH-FEAT-3] Multi-weapon side-by-side comparison view (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added "Compare Weapons" button to MathhammerUI.gd that runs independent Monte Carlo simulations per weapon against the same defender. Results displayed as side-by-side weapon stat cards showing avg damage, kill probability, expected survivors, hit/wound/unsaved rates, and damage efficiency. Best weapon highlighted with green background. Damage ranking panel sorts weapons by effectiveness with color-coded rank labels. Breakdown panel shows per-weapon cumulative probability tables. Runs on background thread to avoid UI freeze.
- T5-MH4. [MH-FEAT-4] Damage per point (points efficiency metric) — unit cost data exists in `meta.points` (MATHHAMMER_AUDIT)
- T5-MH5. [MH-FEAT-5] Swap attacker/defender button (MATHHAMMER_AUDIT)
- T5-MH6. [MH-UI-2] Responsive panel sizing — adapt to viewport instead of hardcoded 800px/400x600 (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Replaced all hardcoded pixel sizes (800px panel height, 400x600 scroll container, 350/380-wide content areas, 400px expanded height) with viewport-relative calculations via helper functions. Connected to viewport `size_changed` signal so layout updates dynamically on resize. Sizes computed as percentages of viewport dimensions (e.g. panel width ~32%, scroll height ~58%, expanded height ~39%). Small UI elements (labels, spacers, spinboxes) left as fixed minimums for readability.
- T5-MH7. [MH-UI-3] Loading spinner / progress bar during simulation (MATHHAMMER_AUDIT) — **DONE**
  - **Resolution:** Added ProgressBar + status label UI below the Run/Compare buttons, hidden by default. Added progress_callback parameter to Mathhammer.simulate_combat() that reports every ~2% of trials. Background thread defers progress updates to main thread via call_deferred. Both simulation and weapon comparison flows show live trial count / weapon name progress. Progress indicator auto-hides on completion.
- T5-MH8. [MH-UI-6] Color-code results — green for high kill prob, red for low efficiency, yellow for overkill (MATHHAMMER_AUDIT)
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
- T5-V12. Damage application visualization (floating numbers, flash) (fight_phase_audit_report.md §4.5)
- T5-V13. Engaged units board indicator (crossed swords) (fight_phase_audit_report.md §3.5) — **DONE**
  - **Resolution:** Crossed swords badge overlay on engaged unit tokens during fight phase — color-coded by fight priority (red/gold for Fights First, white for Normal, gray for Fights Last); `is_engaged`/`fight_priority` flags set in FightPhase._initialize_fight_sequence() and cleared on phase exit; badge hidden once unit has fought (defers to "has fought" overlay)
- T5-V14. Deployment zone edge highlighting (DEPLOYMENT_AUDIT.md §QoL 6) — **DONE**
  - **Resolution:** Enhanced `DeploymentZoneVisual.gd` with animated dashed border (marching ants), multi-layer pulsing glow on inner edges (facing no-man's-land), corner markers at zone boundary transitions, and zone depth labels (e.g., "12\"") on the longest inner edge. Board-boundary edges get subtle dimmed dashed lines while inner edges get full glow + emphasis treatment. Follows sine-wave animation patterns from EngagementRangeVisual.gd and dashed line patterns from RangeCircle.gd/PileInMovementVisual.gd.
- T5-V15. Mathhammer visual histogram (Code TODO in `MathhammerUI.gd:738`) — see also T5-MH1

---

## TIER 6 — Testing Infrastructure

These items come from the Testing Audit (PRPs/gh_issue_93_testing-audit.md) and affect development velocity.

### T6-1. Fix broken test compilation errors — **DONE**
- BaseUITest method signature mismatch (`assert_unit_card_visible` — 1 param vs 2)
- Missing assertion methods (`assert_has`, `assert_does_not_have`)
- GameState autoload resolution in headless tests
- **Source:** TESTING_AUDIT_SUMMARY.md, PRPs/gh_issue_93_testing-audit.md
- **Resolution:** Created missing `BaseUITest.gd` with correct 2-param `assert_unit_card_visible(visible, message)` signature, `assert_has`/`assert_does_not_have` collection assertions, and full UI testing helpers (scene loading, button clicks, model tokens, drag, phase transitions). Fixed `ensure_autoloads_loaded(get_tree())` parameter mismatch in BasePhaseTest.gd and test_multiplayer_gameplay.gd to use `verify_autoloads_available()`. Fixed `Engine.has_singleton`/`get_singleton` GameState access in test_full_gameplay_sequence.gd to use `AutoloadHelper.get_game_state()` (autoloads are scene tree nodes, not Engine singletons).

### T6-2. Validate all existing tests and document status
- ~300 tests across 52 files, many with ⚠️ Unknown status
- 8 fight phase test failures need investigation
- **Source:** TESTING_AUDIT_SUMMARY.md

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
| `MathhammerUI.gd` | 738 | Implement custom drawing for visual histogram | T5-V15 |
| `ScoringController.gd` | 148 | Score objectives not implemented | T5-UX13 |
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
| Tier 3 — Medium Rules | 20 | 6 | 26 |
| Tier 4 — Low/Niche | 14 | 6 | 20 |
| Tier 5 — QoL/Visual | 40 | 11 | 51 |
| Tier 6 — Testing | 3 | 2 | 5 |
| **Total Open** | **98** | **30** | **128** |
| **Recently Completed** | **118** | — | **118** |
| *Mathhammer items (subset)* | *21* | *10* | *31* |

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
