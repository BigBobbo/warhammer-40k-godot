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
| [MH-BUG-2] Twin-linked re-rolls wounds not hits | Mathhammer | MASTER_AUDIT.md §MATHHAMMER |
| T1-3: Wound roll modifier system (+1/-1 cap) | Shooting/Fight | SHOOTING_PHASE_AUDIT.md §Tier 2 |

---

## MATHHAMMER MODULE AUDIT

> **Audit date:** 2026-02-16
> **Files audited:** `Mathhammer.gd`, `MathhhammerUI.gd`, `MathhhammerResults.gd`, `MathhhammerRuleModifiers.gd`, `RulesEngine.gd` (combat resolution paths)
> **Compared against:** Warhammer 40k 10th Edition Core Rules (wahapedia.ru), UnitCrunch, Adept Roll, Tactical Cogitator, open-source mathhammer tools (Stathammer, cogpunk/mathhammer, daed/mathhammer)

### Architecture Overview
The Mathhammer module uses Monte Carlo simulation (10,000 trials default) that delegates to the existing `RulesEngine.resolve_shoot()` for each trial. This is a solid approach — it guarantees consistency with actual gameplay resolution and naturally handles complex rule interactions. The `MathhhammerResults.gd` provides advanced statistical analysis (confidence intervals, skewness, kurtosis, entropy) which exceeds what most community tools offer.

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
| MH-BUG-1 | **CRITICAL** | `_extract_damage_from_result()` only counts model kills as 1 damage each — ignores actual wound deltas. A lascannon dealing 6 damage to a 12W vehicle counts as 0 damage if not killed. | `Mathhammer.gd:232-240` |
| MH-BUG-2 | ~~**HIGH**~~ **DONE** | ~~Twin-linked toggle described as "Re-roll failed hits" but 10e Twin-linked re-rolls **wound** rolls, not hit rolls. The `_apply_twin_linked()` sets `reroll_hits` flag.~~ Fixed: moved to WOUND_MODIFIER, sets `reroll_wounds`, wound re-roll logic added to RulesEngine. | `MathhhammerRuleModifiers.gd`, `RulesEngine.gd`, `Mathhammer.gd` |
| MH-BUG-3 | **HIGH** | Anti-keyword toggles described as "Re-roll wounds vs KEYWORD" but 10e Anti-X lowers the **critical wound threshold** (e.g., Anti-Vehicle 4+ means crits on 4+ to wound). Implementation sets `anti_keywords` without a threshold. | `MathhhammerRuleModifiers.gd:77-83,296-299` |
| MH-BUG-4 | **MEDIUM** | Rapid Fire toggle doubles all attacks (`attacks * 2`) but 10e Rapid Fire X adds only +X attacks, not double. Rapid Fire 1 on a 2-attack weapon = 3 attacks, not 4. | `Mathhammer.gd:188-189` |
| MH-BUG-5 | **MEDIUM** | `create_styled_panel()` removes `content_vbox` from its parent (lines 954-957), making the styled panel's PanelContainer an empty visual shell. Children added to the returned VBox appear outside the styled background. | `MathhhammerUI.gd:953-958` |
| MH-BUG-6 | **LOW** | Class name typo — triple 'h': `MathhhammerUI`, `MathhhammerResults`, `MathhhammerRuleModifiers`. Inconsistent with `Mathhammer.gd` (double 'h'). | All Mathhammer files |

### Missing Rules / Modifiers (not in simulation toggle system)

| ID | Rule | 10e Description | Priority |
|----|------|-----------------|----------|
| MH-RULE-1 | Melta X | +X Damage at half range | HIGH — see T1-1 |
| MH-RULE-2 | Lance | +1 to wound if charged | MEDIUM — see T4-1 |
| MH-RULE-3 | Indirect Fire | -1 to hit, unmod 1-3 fail, target gains cover | MEDIUM — see T2-4 |
| MH-RULE-4 | Hazardous | D6 per weapon after attacking; 1 = 3MW to bearer | MEDIUM — see T2-3 |
| MH-RULE-5 | Torrent | Auto-hit (no hit roll) | MEDIUM |
| MH-RULE-6 | Conversion X+ | Expanded crit hit range at 12"+ | LOW |
| MH-RULE-7 | Half Damage | Halve incoming damage (round up) | LOW |
| MH-RULE-8 | Stealth | Always has Benefit of Cover | LOW — see T2-1 |
| MH-RULE-9 | Invulnerable Save toggle | UI needs invuln save override input for defender | HIGH |
| MH-RULE-10 | FNP toggle integration | FNP exists in RulesEngine but Mathhammer toggles don't pass threshold to RulesEngine board state | HIGH |
| MH-RULE-11 | Blast | +1 attack per 5 defender models — Mathhammer UI doesn't auto-calculate from defender model count | MEDIUM |
| MH-RULE-12 | Melee support | Mathhammer only supports shooting phase; no WS input, no Lance/charge conditions | HIGH |
| MH-RULE-13 | Re-roll wound rolls (generic) | Only re-roll hit 1s exists; no re-roll wounds, re-roll all failed hits/wounds | MEDIUM |
| MH-RULE-14 | Save modifier cap | Saves can be worsened by more than -1 (AP stacks fully) but cannot be improved by more than +1 | LOW |

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
| MH-FEAT-8 | Quick-run on hover (expected damage preview) | UnitCrunch | LOW — see T5-UX1 |
| MH-FEAT-9 | Auto-detect weapon abilities from datasheet | UnitCrunch (import), Adept Roll (screenshot) | MEDIUM |
| MH-FEAT-10 | Multi-target comparison matrix | Cogitator40k | LOW |
| MH-FEAT-11 | Simulation runs on background thread (async) | Standard practice | MEDIUM |

### UI / Visual Issues

| ID | Issue | Priority |
|----|-------|----------|
| MH-UI-1 | Histogram display is a TODO placeholder — `_draw_simple_histogram()` creates text-based bars but is never called from the main display path | HIGH — see T5-V15 |
| MH-UI-2 | Hardcoded 800px min height + 400x600 scroll container — doesn't adapt to screen size or browser viewport | MEDIUM |
| MH-UI-3 | No loading indicator during simulation — 10,000 trials blocks the main thread; UI shows "Running..." text only | MEDIUM |
| MH-UI-4 | ~70 debug print statements in `MathhhammerUI.gd` — excessive logging in the UI layer (per project rules, keep debug logs but these are mostly state-debugging noise) | LOW |
| MH-UI-5 | OptionButton for defender but spinbox rows for attackers — inconsistent selection paradigms | LOW |
| MH-UI-6 | No color coding for good/bad results (e.g., green for high kill prob, red for low efficiency) | LOW |
| MH-UI-7 | Results are duplicated — `_create_detailed_results_display()` adds to `summary_panel`, then `_populate_breakdown_panel()` adds identical stats to `breakdown_panel` | MEDIUM |
| MH-UI-8 | No "Clear Results" or "Reset" button | LOW |

---

## TIER 1 — CRITICAL: Core Rules Compliance (Blocking Accurate Games)

These items cause incorrect game outcomes. They should be fixed before any competitive or serious playtesting.

### T1-1. Melta X weapon keyword — bonus damage at half range
- **Phase:** Shooting
- **Rule:** MELTA X adds +X to Damage when target is within half range
- **Impact:** Core anti-vehicle weapon type (Multi-melta, Meltagun) doesn't function correctly
- **Source:** SHOOTING_PHASE_AUDIT.md §2.3
- **Files:** `RulesEngine.gd` — damage application, range checking (can reference `count_models_in_half_range()`)

### T1-2. Twin-linked weapon keyword — re-roll wound rolls
- **Phase:** Shooting/Fight
- **Rule:** Re-roll all failed wound rolls
- **Impact:** Common keyword across many weapon profiles
- **Source:** SHOOTING_PHASE_AUDIT.md §2.3
- **Files:** `RulesEngine.gd` — wound roll logic (~lines 700-733)

### T1-3. Wound roll modifier system (+1/-1 cap) — **DONE**
- **Phase:** Shooting/Fight
- **Rule:** Wound rolls can have modifiers capped at net +1/-1. Unmodified 1 always fails.
- **Impact:** Infrastructure needed for Twin-linked, Lance, and many unit abilities
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — create WoundModifier system near existing HitModifier (~lines 349-378)
- **Resolution:** Added `WoundModifier` enum and `apply_wound_modifiers()` function mirroring the existing `HitModifier` system. Integrated into all three wound roll paths (interactive shooting, auto-resolve shooting, melee). Modifiers capped at net +1/-1, unmodified 1 always fails, re-rolls before modifiers per 10e rules. Twin-linked re-rolls migrated to modifier system. Added `is_lance_weapon()` helper and Lance keyword integration (+1 to wound on charge).

### T1-4. Morale Phase — stub implementation, model removal missing
- **Phase:** Morale
- **Rule:** Battle-shocked units in 10e don't take a separate Morale test, but the Morale phase is where you check if Battle-shock is still active. The current implementation is a 9th-edition style stub that doesn't match 10e rules.
- **Impact:** Morale casualties are recorded but models are not actually removed
- **Source:** Code TODO in `MoralePhase.gd:164-165`, `MoralePhase.gd:7-8`
- **Files:** `MoralePhase.gd` — `_process_morale_failure()`, entire phase needs 10e overhaul

### T1-5. Pile-in must end with unit in engagement range
- **Phase:** Fight
- **Rule:** After pile-in, at least one model must be within 1" of an enemy. If impossible, no pile-in.
- **Impact:** Invalid pile-in positions accepted; unit could "pile in" away from engagement
- **Source:** FIGHT_PHASE_AUDIT.md §2.2
- **Files:** `FightPhase.gd` — `_validate_pile_in()` needs final unit-level ER check

### T1-6. Base-to-base contact enforcement in pile-in/consolidation
- **Phase:** Fight
- **Rule:** Models must end in base-to-base contact with closest enemy *if possible*
- **Impact:** Players can avoid base contact for positional advantage
- **Source:** FIGHT_PHASE_AUDIT.md §2.3
- **Files:** `FightPhase.gd` — PileIn/Consolidate validation

### T1-7. Base-to-base contact enforcement in charge
- **Phase:** Charge
- **Rule:** If a charging model can end in B2B with an enemy, it must
- **Impact:** Rules violation allowing positional advantage
- **Source:** CHARGE_PHASE_AUDIT.md §2.4
- **Files:** `ChargePhase.gd:784-788` — `_validate_base_to_base_possible()` currently returns `true` always

### T1-8. Failed charge measurement divergence (client vs server)
- **Phase:** Charge
- **Rule:** Charge success/failure must be deterministic
- **Impact:** Client uses pixel measurement, server uses inches — potential desync
- **Source:** CHARGE_PHASE_AUDIT.md §2.5
- **Files:** `ChargeController.gd:790-831` vs `ChargePhase.gd:359`

### T1-9. [MH-BUG-1] Mathhammer damage extraction is fundamentally broken
- **Phase:** Mathhammer
- **Rule:** Damage dealt should equal wound points removed from defender models
- **Impact:** `_extract_damage_from_result()` only counts model kills as 1 damage each. A lascannon dealing 6 damage to a 12W vehicle that doesn't die counts as 0 damage. Average damage, kill probability, efficiency — all output is wrong.
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd:232-240` — needs to compute actual wound delta from diffs (old wounds - new wounds) instead of checking `new_wounds == 0`

### T1-10. ~~[MH-BUG-2] Twin-linked modifier re-rolls hits instead of wounds~~ **DONE**
- **Phase:** Mathhammer
- **Rule:** 10e Twin-linked re-rolls all failed **wound** rolls, not hit rolls
- **Impact:** ~~Simulation applies wrong re-roll, inflating hit rates while ignoring wound re-rolls~~ Fixed
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerRuleModifiers.gd`, `MathhhammerUI.gd`, `RulesEngine.gd`, `Mathhammer.gd`
- **Resolution:** Fixed `_apply_twin_linked()` to set `reroll_wounds` instead of `reroll_hits`. Moved twin-linked from HIT_MODIFIER to WOUND_MODIFIER category. Added `has_twin_linked()` keyword detection and wound re-roll logic to all three RulesEngine wound roll paths (interactive, auto-resolve, melee). Wired twin-linked toggle through Mathhammer simulation pipeline to RulesEngine assignments.

---

## TIER 2 — HIGH: Important Defensive & Gameplay Rules

These affect gameplay balance and tactical options significantly.

### T2-1. Stealth ability — -1 to hit for ranged attacks
- **Phase:** Shooting
- **Rule:** If all models in a unit have Stealth, ranged attacks targeting it get -1 to hit
- **Impact:** Many units rely on this for survivability (currently only implemented via Smokescreen stratagem, not as base ability)
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — hit modifier section in `_resolve_assignment_until_wounds()` (~lines 591-601)

### T2-2. Lone Operative — 12" targeting restriction
- **Phase:** Shooting
- **Rule:** Lone Operative units can only be targeted from within 12" unless attached
- **Impact:** Key survivability rule for standalone characters
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — `get_eligible_targets()`, `validate_shoot()`

### T2-3. Hazardous weapon keyword — mortal wounds on roll of 1
- **Phase:** Shooting
- **Rule:** After attacking, roll D6 per Hazardous weapon; on 1, bearer takes 3 MW
- **Impact:** Affects all plasma weapons (common across many armies)
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd`, `ShootingPhase.gd` — post-attack resolution

### T2-4. Indirect Fire weapon keyword
- **Phase:** Shooting
- **Rule:** Can shoot without LoS; -1 to hit, unmodified 1-3 always fail, target gains cover
- **Impact:** Key for artillery units
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 2
- **Files:** `RulesEngine.gd` — `validate_shoot()`, `get_eligible_targets()`, hit roll logic, cover

### T2-5. Pistol mutual exclusivity
- **Phase:** Shooting
- **Rule:** Cannot fire both Pistol and non-Pistol weapons on same model
- **Impact:** Rules violation allowing extra firepower
- **Source:** SHOOTING_PHASE_AUDIT.md §2.11
- **Files:** `ShootingPhase.gd` — `_validate_assign_target()` (~lines 180-211)

### T2-6. Consolidation into new enemies doesn't trigger new fights
- **Phase:** Fight
- **Rule:** After consolidation, newly eligible enemy units can fight back
- **Impact:** Removes major tactical risk of aggressive consolidation
- **Source:** FIGHT_PHASE_AUDIT.md §2.4
- **Files:** `FightPhase.gd` — `_process_consolidate()`, fight sequence rebuild

### T2-7. Heroic Intervention — not implemented
- **Phase:** Fight/Charge
- **Rule:** 2CP stratagem allowing CHARACTER within 6" to counter-charge
- **Impact:** Key defensive option missing for non-active player
- **Source:** FIGHT_PHASE_AUDIT.md §2.5, CHARGE_PHASE_AUDIT.md §2.2
- **Files:** `FightPhase.gd:1020-1023` (stub), StratagemManager integration

### T2-8. Terrain interaction during charges — not implemented
- **Phase:** Charge
- **Rule:** Charging over terrain >2" costs vertical distance against charge roll; FLY allows diagonal
- **Impact:** Charges through terrain have no distance penalty
- **Source:** CHARGE_PHASE_AUDIT.md §2.6
- **Files:** `ChargePhase.gd`, `ChargeController.gd`

### T2-9. AIRCRAFT restriction — not checked in charge
- **Phase:** Charge
- **Rule:** AIRCRAFT cannot charge; only FLY units can charge AIRCRAFT
- **Impact:** Invalid charges allowed
- **Source:** CHARGE_PHASE_AUDIT.md §2.7
- **Files:** `ChargePhase.gd` — `_can_unit_charge()`, `_validate_declare_charge()`

### T2-10. Cover determination limited to ruins only
- **Phase:** Shooting
- **Rule:** Cover can be granted by ruins, area terrain, obstacles, woods, craters, barricades
- **Impact:** Non-ruins terrain gives no cover
- **Source:** SHOOTING_PHASE_AUDIT.md §2.9
- **Files:** `RulesEngine.gd` — `check_benefit_of_cover()` (~lines 1440-1461)

### T2-11. Devastating Wounds — mortal wound spillover needs verification
- **Phase:** Shooting/Fight
- **Rule:** Devastating Wounds create mortal wounds that spill over and are allocated after normal attacks
- **Impact:** Edge cases around spillover and FNP interaction
- **Source:** SHOOTING_PHASE_AUDIT.md §2.10
- **Files:** `RulesEngine.gd` — devastating wound handling (~lines 3776-3790)

### T2-12. active_moves dictionary not synced in multiplayer
- **Phase:** Movement
- **Rule:** Movement state must be consistent between host and client
- **Impact:** Potential silent desync leading to illegal moves or stuck state
- **Source:** MOVEMENT_PHASE_AUDIT.md §3.1
- **Files:** `MovementPhase.gd:20`, `NetworkManager`

### T2-13. [MH-BUG-3] Anti-keyword modifier uses wrong mechanic
- **Phase:** Mathhammer
- **Rule:** Anti-[KEYWORD] X+ lowers the critical wound threshold (e.g., Anti-Vehicle 4+ = crits on wound rolls of 4+). It is NOT a wound re-roll.
- **Impact:** Simulation doesn't correctly model Anti-keyword; one of the most impactful offensive abilities in 10e
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerRuleModifiers.gd:77-83,296-299` — needs threshold parameter and crit wound threshold override

### T2-14. [MH-RULE-9] Mathhammer has no invulnerable save toggle/override
- **Phase:** Mathhammer
- **Rule:** Defender invulnerable save is a core defensive stat that determines whether AP is relevant
- **Impact:** Cannot model matchups involving invulnerable saves — a fundamental part of 40k combat math
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerUI.gd` — needs defender stat override panel; `Mathhammer.gd` — needs to pass invuln to trial board state

### T2-15. [MH-RULE-10] FNP toggle doesn't integrate with simulation
- **Phase:** Mathhammer
- **Rule:** Feel No Pain is a per-wound save that dramatically reduces effective damage
- **Impact:** FNP exists in RulesEngine but the Mathhammer toggle values are not propagated to the trial board state's unit stats
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerRuleModifiers.gd:109-121`, `Mathhammer.gd:204-229` — `_create_trial_board_state()` needs to apply FNP from toggles

### T2-16. [MH-RULE-12] No melee combat support in Mathhammer
- **Phase:** Mathhammer
- **Rule:** Melee uses the same attack sequence as shooting (WS instead of BS) with additional modifiers (Lance, charged condition)
- **Impact:** All community mathhammer tools support melee. Missing melee means Fight phase has no statistical preview.
- **Source:** MATHHAMMER_AUDIT, code TODO at `FightPhase.gd:947`
- **Files:** `Mathhammer.gd` — hardcoded to "shooting" phase; `MathhhammerUI.gd` — needs shooting/melee toggle

---

## TIER 3 — MEDIUM: Missing Rules & Polish

These are real rules gaps but affect niche situations or have workarounds.

### T3-1. Fights Last subphase not processed
- **Phase:** Fight
- **Rule:** Units with Fights Last fight after Remaining Combats
- **Impact:** Fights Last units placed in sequence but never activated
- **Source:** FIGHT_PHASE_AUDIT.md §2.6
- **Files:** `FightPhase.gd` — Subphase enum (add FIGHTS_LAST), `_transition_subphase()`

### T3-2. Fights First + Fights Last cancellation
- **Phase:** Fight
- **Rule:** If both apply, unit fights in Remaining Combats (normal)
- **Impact:** Incorrect fight order
- **Source:** FIGHT_PHASE_AUDIT.md §2.7
- **Files:** `FightPhase.gd` — `_get_fight_priority()` (~lines 1026-1041)

### T3-3. Extra Attacks weapon ability
- **Phase:** Fight/Shooting
- **Rule:** Extra Attacks weapons are used IN ADDITION to normal weapon, not as alternative
- **Impact:** Players may miss using or misuse these weapons
- **Source:** FIGHT_PHASE_AUDIT.md §2.8, SHOOTING_PHASE_AUDIT.md §Tier 4
- **Files:** `AttackAssignmentDialog.gd`, `ShootingPhase.gd` — weapon assignment logic

### T3-4. Precision weapon keyword — allocate wounds to Characters
- **Phase:** Shooting/Fight
- **Rule:** Critical wounds from Precision weapons can be allocated to attached Characters
- **Impact:** Important for character sniping
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 3
- **Files:** `RulesEngine.gd` — wound allocation (~lines 3648-3718), `WoundAllocationOverlay.gd`

### T3-5. Scout moves — not implemented
- **Phase:** Pre-game (between Deployment and Turn 1)
- **Rule:** Units with Scout X" can move X" after deployment, ending >9" from enemies
- **Impact:** Many army builds depend on early positioning
- **Source:** DEPLOYMENT_AUDIT.md §5, MOVEMENT_PHASE_AUDIT.md §2.8
- **Files:** New pre-game phase needed

### T3-6. Pre-battle formations declaration
- **Phase:** Deployment
- **Rule:** Before deployment, players secretly declare leader attachments, transport embarkations, and reserves
- **Impact:** Seeing opponent deployment before declaring formations is a strategic advantage
- **Source:** DEPLOYMENT_AUDIT.md §1
- **Files:** New pre-deployment configuration screen

### T3-7. Determine first turn roll-off
- **Phase:** Post-deployment
- **Rule:** Players roll off; winner chooses first or second turn
- **Impact:** Going first vs second is a major strategic decision
- **Source:** DEPLOYMENT_AUDIT.md §6
- **Files:** `TurnManager.gd` — currently hardcoded

### T3-8. Charge move direction constraint
- **Phase:** Charge
- **Rule:** Each model must end charge move closer to at least one charge target
- **Impact:** Models can be placed suboptimally without enforcement
- **Source:** CHARGE_PHASE_AUDIT.md §2.9
- **Files:** `ChargeController.gd:1265-1286`, `ChargePhase.gd`

### T3-9. Barricade engagement range (2" instead of 1")
- **Phase:** Charge/Fight
- **Rule:** Engagement range through barricades is 2"
- **Impact:** Charges across barricades are incorrectly strict
- **Source:** CHARGE_PHASE_AUDIT.md §2.8
- **Files:** No barricade terrain type exists

### T3-10. Faction abilities (Oath of Moment, etc.)
- **Phase:** Command
- **Rule:** Many factions have Command Phase abilities (re-rolls, sticky objectives, etc.)
- **Impact:** Faction identity missing
- **Source:** AUDIT_COMMAND_PHASE.md §2.4
- **Files:** New ability trigger system, army JSON data already has text descriptions

### T3-11. Overwatch integration into charge/movement phases
- **Phase:** Charge/Movement
- **Rule:** Overwatch can be triggered during charge and movement phases by the defending player
- **Impact:** Stratagem defined but reaction window not integrated into charge/movement flows
- **Source:** CHARGE_PHASE_AUDIT.md §2.1, MOVEMENT_PHASE_AUDIT.md §2.10
- **Files:** `ChargePhase.gd`, `MovementPhase.gd`, `StratagemManager.gd`

### T3-12. Multiplayer race condition in fight dialog sequencing
- **Phase:** Fight
- **Rule:** Actions must arrive in order
- **Impact:** Fixed 50ms delays between actions may be insufficient on slow connections
- **Source:** FIGHT_PHASE_AUDIT.md §3.3
- **Files:** `FightController.gd:1357-1392`

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

### T3-18. FLY units should ignore terrain elevation during movement
- **Phase:** Movement
- **Rule:** FLY keyword allows ignoring vertical distance
- **Impact:** FLY units taxed by terrain height incorrectly
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.3 (remaining work)
- **Files:** `MovementPhase.gd`, `TerrainManager.gd`

### T3-19. Terrain height handling in LoS — only "tall" terrain handled
- **Phase:** Shooting (LoS)
- **Rule:** Medium/low terrain should be handled based on model height
- **Impact:** LoS calculations may be incorrect for non-tall terrain
- **Source:** Code TODO in `LineOfSightCalculator.gd:79`
- **Files:** `LineOfSightCalculator.gd`

### T3-20. [MH-BUG-4] Rapid Fire toggle doubles attacks instead of adding X
- **Phase:** Mathhammer
- **Rule:** Rapid Fire X adds +X attacks at half range (e.g., Rapid Fire 1 on 2A weapon = 3 attacks, not 4)
- **Impact:** Overstates Rapid Fire weapon output by ~33% for RF1 weapons
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd:188-189` — `attacks_override` should add RF value, not multiply by 2

### T3-21. [MH-RULE-5] Torrent weapons (auto-hit) not in simulation toggles
- **Phase:** Mathhammer
- **Rule:** Torrent weapons automatically hit — no hit roll made, no critical hits possible
- **Impact:** Torrent is a common ability (flamers, etc.) that changes the math significantly
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerRuleModifiers.gd` — needs Torrent toggle that bypasses hit rolls

### T3-22. [MH-RULE-11] Blast attack bonus not auto-calculated from defender model count
- **Phase:** Mathhammer
- **Rule:** Blast weapons get +1 attack per 5 models in target unit; minimum 3 attacks vs 6+ model units
- **Impact:** Mathhammer has defender unit data available but doesn't auto-adjust Blast weapon attacks
- **Source:** MATHHAMMER_AUDIT
- **Files:** `Mathhammer.gd` — `_build_shoot_action()` should check Blast keyword and adjust

### T3-23. [MH-RULE-13] No wound re-roll support (only hit re-roll 1s exists)
- **Phase:** Mathhammer
- **Rule:** Many abilities grant re-roll all failed wounds, re-roll wound rolls of 1, re-roll all failed hits
- **Impact:** Re-rolls are one of the most impactful modifiers; only partial support exists
- **Source:** MATHHAMMER_AUDIT
- **Files:** `RulesEngine.gd` — only `REROLL_ONES` hit modifier exists (line 342); needs WoundModifier with re-rolls

### T3-24. [MH-FEAT-6] No defender stats override panel
- **Phase:** Mathhammer
- **Rule:** Users should be able to override or input custom defender T/Sv/W/Invuln/FNP
- **Impact:** Cannot model hypothetical matchups or units not in the game state
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerUI.gd` — needs custom defender input fields alongside the unit dropdown

### T3-25. [MH-FEAT-11] Simulation blocks main thread
- **Phase:** Mathhammer
- **Rule:** 10,000 Monte Carlo trials should run on a background thread to avoid freezing the UI
- **Impact:** UI is unresponsive during simulation; at 100K trials this could freeze the browser tab
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerUI.gd:673-689` — `_run_simulation_async()` is not actually async

### T3-26. [MH-BUG-5] Styled panel background is empty (visual bug)
- **Phase:** Mathhammer
- **Rule:** `create_styled_panel()` removes `content_vbox` from its parent PanelContainer before returning it
- **Impact:** The colored background panels in results display are empty shells; content appears outside them
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerUI.gd:953-958` — should not remove child from parent; return the panel_container and add children to the nested content_vbox

---

## TIER 4 — LOW: Niche Rules & Stratagems

### T4-1. Lance weapon keyword (+1 wound on charge)
- **Phase:** Shooting/Fight
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4
- **Depends on:** T1-3 (wound modifier system)

### T4-2. One Shot weapon keyword (single use per battle)
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4

### T4-3. Counter-Offensive stratagem
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.9

### T4-4. Aircraft restrictions in fight phase
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.10

### T4-5. Models in base contact should not move during pile-in
- **Phase:** Fight
- **Source:** FIGHT_PHASE_AUDIT.md §2.11

### T4-6. Go to Ground / Smokescreen stratagems
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Tier 4

### T4-7. Rapid Ingress stratagem
- **Phase:** Movement
- **Source:** MOVEMENT_PHASE_AUDIT.md §2.11

### T4-8. Secondary missions + New Orders stratagem
- **Phase:** Command
- **Source:** AUDIT_COMMAND_PHASE.md §P3

### T4-9. Deployment map variety (Hammer and Anvil, Search and Destroy, etc.)
- **Phase:** Deployment
- **Source:** DEPLOYMENT_AUDIT.md §7

### T4-10. Mission selection variety
- **Phase:** Pre-game
- **Source:** DEPLOYMENT_AUDIT.md §8

### T4-11. Fortification deployment
- **Phase:** Deployment
- **Source:** DEPLOYMENT_AUDIT.md §9

### T4-12. Unmodified wound roll of 1 always fails (defensive check)
- **Phase:** Shooting/Fight
- **Source:** SHOOTING_PHASE_AUDIT.md §2.12
- **Depends on:** T1-3 (wound modifier system)

### T4-13. Unmodified save roll of 1 always fails (auto-resolve path)
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §2.13
- **Files:** `RulesEngine.gd` — `_resolve_assignment()` (~line 1129)

### T4-14. Weapon ID collision for similar weapon names
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues

### T4-15. Single weapon result dialog has hardcoded zeros
- **Phase:** Shooting
- **Source:** SHOOTING_PHASE_AUDIT.md §Additional Issues
- **Files:** `ShootingPhase.gd:1796-1807`

### T4-16. [MH-RULE-6] Conversion X+ (expanded crit range at distance)
- **Phase:** Mathhammer
- **Source:** MATHHAMMER_AUDIT

### T4-17. [MH-RULE-7] Half Damage defensive ability
- **Phase:** Mathhammer
- **Source:** MATHHAMMER_AUDIT

### T4-18. [MH-RULE-14] Save modifier cap not enforced in mathhammer toggles
- **Phase:** Mathhammer
- **Rule:** Saves can be worsened by more than -1 (AP stacks) but cannot be improved by more than +1
- **Source:** MATHHAMMER_AUDIT

### T4-19. [MH-BUG-6] Triple 'h' typo in Mathhammer class names
- **Phase:** Mathhammer
- **Impact:** `MathhhammerUI`, `MathhhammerResults`, `MathhhammerRuleModifiers` should be `MathhammerUI`, etc.
- **Source:** MATHHAMMER_AUDIT
- **Files:** All `Mathhammer*.gd` files, `project.godot` autoload references

### T4-20. [MH-FEAT-9] Auto-detect weapon abilities from unit datasheet
- **Phase:** Mathhammer
- **Impact:** Weapon keywords (Lethal Hits, Sustained Hits, etc.) exist in unit data but aren't auto-enabled as toggles
- **Source:** MATHHAMMER_AUDIT
- **Files:** `MathhhammerRuleModifiers.gd:134-180` — `extract_unit_rules()` exists but isn't connected to UI

---

## TIER 5 — Quality of Life & UX Improvements

### Multiplayer UX
- T5-MP1. Pile-in/consolidate drag movement not synced visually to remote player (FIGHT_PHASE_AUDIT.md §3.6)
- T5-MP2. Pile-in/consolidate validation feedback missing on client (FIGHT_PHASE_AUDIT.md §3.5)
- T5-MP3. Remote player visual feedback for shooting actions (SHOOTING_PHASE_AUDIT.md §Tier 3)
- T5-MP4. Save dialog timing reliability for defender on remote client (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-MP5. Dice log visibility sync to remote player (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-MP6. "Waiting for Opponent" state in deployment (DEPLOYMENT_AUDIT.md §QoL 3)
- T5-MP7. Game over UI with winner and reason (Code TODO in `NetworkManager.gd:1474`)
- T5-MP8. Phase timeout for AFK players (AUDIT_COMMAND_PHASE.md §P3)
- T5-MP9. BEGIN_ADVANCE latency in multiplayer (MOVEMENT_PHASE_AUDIT.md §3.3)

### Gameplay UX
- T5-UX1. Expected damage preview when hovering weapons (SHOOTING_PHASE_AUDIT.md §Tier 3)
- T5-UX2. Auto-select weapon for single-weapon units (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-UX3. "Shoot All Remaining" button (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-UX4. "Undo Last Assignment" button in weapon assignment (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-UX5. "All to Target" button in fight attack assignment dialog (fight_phase_audit_report.md §3.1)
- T5-UX6. Show weapon stats in target assignment UI (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-UX7. End fight phase confirmation dialog (fight_phase_audit_report.md §3.6)
- T5-UX8. Deployment summary before ending phase (DEPLOYMENT_AUDIT.md §QoL 8)
- T5-UX9. Undo last model placement (per-model) in deployment (DEPLOYMENT_AUDIT.md §QoL 4)
- T5-UX10. Auto-zoom to deployment zone (DEPLOYMENT_AUDIT.md §QoL 5)
- T5-UX11. Unit base preview on hover in deployment (DEPLOYMENT_AUDIT.md §QoL 7)
- T5-UX12. Keyboard shortcuts for shooting phase (SHOOTING_PHASE_AUDIT.md §Tier 4)
- T5-UX13. Score objectives — not implemented (Code TODO in `ScoringController.gd:148`)
- T5-UX14. Mathhammer melee simulation integration (Code TODO in `FightPhase.gd:947`)

### Mathhammer UX
- T5-MH1. [MH-FEAT-1] Visual histogram / probability distribution chart — replace text bars with graphical bars (MATHHAMMER_AUDIT) — see also T5-V15
- T5-MH2. [MH-FEAT-2] Cumulative probability display — "X% chance of at least N wounds" table (MATHHAMMER_AUDIT)
- T5-MH3. [MH-FEAT-3] Multi-weapon side-by-side comparison view (MATHHAMMER_AUDIT)
- T5-MH4. [MH-FEAT-4] Damage per point (points efficiency metric) — unit cost data exists in `meta.points` (MATHHAMMER_AUDIT)
- T5-MH5. [MH-FEAT-5] Swap attacker/defender button (MATHHAMMER_AUDIT)
- T5-MH6. [MH-UI-2] Responsive panel sizing — adapt to viewport instead of hardcoded 800px/400x600 (MATHHAMMER_AUDIT)
- T5-MH7. [MH-UI-3] Loading spinner / progress bar during simulation (MATHHAMMER_AUDIT)
- T5-MH8. [MH-UI-6] Color-code results — green for high kill prob, red for low efficiency, yellow for overkill (MATHHAMMER_AUDIT)
- T5-MH9. [MH-UI-7] Deduplicate results display — stats shown in both summary_panel and breakdown_panel (MATHHAMMER_AUDIT)
- T5-MH10. [MH-UI-8] "Clear Results" / "Reset" button (MATHHAMMER_AUDIT)
- T5-MH11. [MH-FEAT-7] Show dice notation (D6, D3+3) in weapon stats display (MATHHAMMER_AUDIT)
- T5-MH12. [MH-FEAT-10] Multi-target comparison matrix — run same attacker against multiple defenders (MATHHAMMER_AUDIT)
- T5-MH13. Shooting/Melee phase toggle in Mathhammer UI (MATHHAMMER_AUDIT)

### Visual Polish
- T5-V1. Animated dice roll visualization (SHOOTING_PHASE_AUDIT.md §Tier 3)
- T5-V2. Shooting line animation and tracer effects (SHOOTING_PHASE_AUDIT.md §Tier 4)
- T5-V3. Phase transition animation banners (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-V4. Target unit damage feedback (flash + death animation) (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-V5. Range circle visualization for weapons (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-V6. Wound allocation overlay enhancements (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-V7. Weapon keyword icons in UI (SHOOTING_PHASE_AUDIT.md §Additional)
- T5-V8. Pile-in/consolidate movement arrows and distance labels (fight_phase_audit_report.md §4.1)
- T5-V9. Engagement range pulsing animation (fight_phase_audit_report.md §4.2)
- T5-V10. Fight phase state banner (fight_phase_audit_report.md §4.3)
- T5-V11. Unit tokens "has fought" indicator (fight_phase_audit_report.md §4.4)
- T5-V12. Damage application visualization (floating numbers, flash) (fight_phase_audit_report.md §4.5)
- T5-V13. Engaged units board indicator (crossed swords) (fight_phase_audit_report.md §3.5)
- T5-V14. Deployment zone edge highlighting (DEPLOYMENT_AUDIT.md §QoL 6)
- T5-V15. Mathhammer visual histogram (Code TODO in `MathhhammerUI.gd:738`) — see also T5-MH1

---

## TIER 6 — Testing Infrastructure

These items come from the Testing Audit (PRPs/gh_issue_93_testing-audit.md) and affect development velocity.

### T6-1. Fix broken test compilation errors
- BaseUITest method signature mismatch (`assert_unit_card_visible` — 1 param vs 2)
- Missing assertion methods (`assert_has`, `assert_does_not_have`)
- GameState autoload resolution in headless tests
- **Source:** TESTING_AUDIT_SUMMARY.md, PRPs/gh_issue_93_testing-audit.md

### T6-2. Validate all existing tests and document status
- ~300 tests across 52 files, many with ⚠️ Unknown status
- 8 fight phase test failures need investigation
- **Source:** TESTING_AUDIT_SUMMARY.md

### T6-3. Add E2E workflow tests
- No full deployment → movement → shooting → fight test
- No multi-turn game simulation
- **Source:** PRPs/gh_issue_93_testing-audit.md

### T6-4. Multiplayer test infrastructure
- No network synchronization tests
- No latency simulation
- No disconnect handling tests
- Multiplayer deployment test helpers have TODO stubs (`test_multiplayer_deployment.gd:555-574`)
- **Source:** PRPs/gh_issue_93_testing-audit.md, code TODOs

### T6-5. CI/CD integration
- Tests not run automatically on commits
- **Source:** PRPs/gh_issue_93_testing-audit.md

---

## Code TODOs Not Covered by Audit Files

The following TODOs were found in code but were not tracked in any existing audit document. They have been assigned to the most relevant tier above:

| File | Line | TODO | Assigned To |
|------|------|------|-------------|
| `MoralePhase.gd` | 7-8 | Stub implementation for Morale phase | T1-4 |
| `MoralePhase.gd` | 107-109 | Add stratagem validation for morale | T1-4 |
| `MoralePhase.gd` | 164-165 | Remove models due to morale failure | T1-4 |
| `MoralePhase.gd` | 203-204 | Implement actual stratagem effects | T1-4 |
| `MoralePhase.gd` | 339-343 | Implement morale modifiers (keywords, characters, conditions) | T1-4 |
| `MoralePhase.gd` | 357-359 | Add helper methods for morale mechanics | T1-4 |
| `FightPhase.gd` | 947 | Integrate full mathhammer simulation for melee | T5-UX14 |
| `FightPhase.gd` | 1022-1023 | Heroic intervention not yet implemented | T2-7 |
| `FightPhase.gd` | 1635-1637 | Add heroic intervention specific validation | T2-7 |
| `LineOfSightCalculator.gd` | 79 | Handle medium/low terrain based on model height | T3-19 |
| `MathhhammerUI.gd` | 738 | Implement custom drawing for visual histogram | T5-V15 |
| `ScoringController.gd` | 148 | Score objectives not implemented | T5-UX13 |
| `NetworkManager.gd` | 1474 | Show game over UI with winner and reason | T5-MP7 |
| `test_multiplayer_deployment.gd` | 368 | Implement collision detection test with turn handling | T6-4 |
| `test_multiplayer_deployment.gd` | 555-557 | Complete `assert_unit_deployed()` implementation | T6-4 |
| `test_multiplayer_deployment.gd` | 562-564 | Complete `assert_unit_not_deployed()` implementation | T6-4 |
| `test_multiplayer_deployment.gd` | 569 | Implement coherency check in tests | T6-4 |
| `test_multiplayer_deployment.gd` | 574 | Extract unit model positions from game state | T6-4 |
| `MultiplayerIntegrationTest.gd` | 469 | Fix LogMonitor for peer connection tracking | T6-4 |
| `Mathhammer.gd` | 232-240 | `_extract_damage_from_result()` broken — counts kills as 1 damage | T1-9 |
| `MathhhammerRuleModifiers.gd` | 58-59 | ~~Twin-linked re-rolls hits instead of wounds~~ **DONE** | T1-10 |
| `MathhhammerRuleModifiers.gd` | 77-83 | Anti-keyword uses re-roll instead of crit threshold | T2-13 |
| `MathhhammerUI.gd` | 953-958 | `create_styled_panel()` removes content_vbox from parent | T3-26 |
| `Mathhammer.gd` | 188-189 | Rapid Fire doubles attacks instead of adding X | T3-20 |

---

## Quick Stats

| Category | Done | Open | Total |
|----------|------|------|-------|
| Tier 1 — Critical Rules | 2 | 8 | 10 |
| Tier 2 — High Rules | 0 | 16 | 16 |
| Tier 3 — Medium Rules | 0 | 26 | 26 |
| Tier 4 — Low/Niche | 0 | 20 | 20 |
| Tier 5 — QoL/Visual | 0 | 51 | 51 |
| Tier 6 — Testing | 0 | 5 | 5 |
| **Total Open** | **2** | **126** | **128** |
| **Recently Completed** | **32** | — | **32** |
| *Mathhammer items (subset)* | *1* | *30* | *31* |

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
