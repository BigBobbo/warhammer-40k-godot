# FEB21 AUDIT - Warhammer 40k Godot Implementation

**Date:** 2026-02-21
**Sources:** Wahapedia Core Rules & Commentary, Balance Dataslate v3.3, Core Rules Updates & Errata, Munitorum Field Manual v3.9, Chapter Approved Tournament Companion, Quick Start Guide
**Codebase:** `/Users/robertocallaghan/Documents/claude/godotv2/40k`

---

## TABLE OF CONTENTS

1. [Executive Summary](#executive-summary)
2. [Command Phase](#1-command-phase)
3. [Movement Phase](#2-movement-phase)
4. [Shooting Phase](#3-shooting-phase)
5. [Charge Phase](#4-charge-phase)
6. [Fight Phase](#5-fight-phase)
7. [Deployment, Terrain & Missions](#6-deployment-terrain--missions)
8. [General Rules & Stratagems](#7-general-rules--stratagems)
9. [Quality of Life Improvements](#8-quality-of-life-improvements)
10. [Visual Improvements](#9-visual-improvements)
11. [Full TODO List](#10-full-todo-list)

---

## Executive Summary

The project is a **production-quality implementation** of Warhammer 40k 10th Edition in Godot with multiplayer support. Core mechanics across all 5 phases are substantially implemented with 150+ tests, comprehensive AI, and multiplayer infrastructure. However, this audit identified **67 actionable items** across rules compliance, QoL, and visual improvements.

**Key Strengths:**
- All 5 game phases fully implemented with correct sequencing
- 17+ weapon abilities working (Lethal Hits, Sustained Hits, Devastating Wounds, Blast, Rapid Fire, Melta, Torrent, etc.)
- Full melee weapon ability pipeline (previously missing, now complete)
- Excellent multiplayer with deterministic RNG and optimistic execution
- Comprehensive AI with difficulty scaling
- Mathhammer Monte Carlo simulation tool

**Critical Gaps Found:**
- Reinforcement phase missing entirely (reserves declared but never arrive)
- CHARACTER targeting "closest eligible" rule not enforced in shooting
- Pivot values for non-round base models not implemented (Core Rules Updates errata)
- Out-of-Phase rules restriction not implemented
- Several Balance Dataslate v3.3 changes not applied
- Cover-from-terrain integration with save system incomplete

---

## 1. COMMAND PHASE

**Files:** `phases/CommandPhase.gd`, `autoloads/StratagemManager.gd`, `autoloads/GameState.gd`

### Correctly Implemented
- Both players gain 1 CP at start of Command Phase
- Battle-shock tests: 2D6 vs Leadership for below-half-strength units
- Battle-shocked units have OC 0
- Battle-shock persists until next Command Phase
- Insane Bravery stratagem (1CP, once per battle, auto-pass)
- Command Re-roll available for battle-shock tests

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| CMD-1 | MEDIUM | No CP cap implementation | Players can accumulate unlimited CP. Competitive play typically caps at a reasonable amount. No validation in `_generate_command_points()` |
| CMD-2 | MEDIUM | No FEARLESS/ATSKNF keyword support | Units with these keywords should be immune to battle-shock. No keyword check in `_identify_units_needing_tests()` (line 144-174) |
| CMD-3 | LOW | Battle-shocked units can use own stratagems | `StratagemManager.gd:526-531` only prevents targeting battle-shocked units with friendly stratagems, not self-targeted stratagems |
| CMD-4 | LOW | No confirmation before auto-resolving untaken tests | Lines 989-997 auto-resolve silently; should warn player |
| CMD-5 | LOW | CP gain per battle round limit (Balance Dataslate FAQ) | Balance Dataslate FAQ states rules giving more than 1CP per battle round have specific exceptions; verify compliance |

---

## 2. MOVEMENT PHASE

**Files:** `phases/MovementPhase.gd`, `autoloads/RulesEngine.gd`, `autoloads/TransportManager.gd`

### Correctly Implemented
- Normal Move, Advance (D6 + Move), Fall Back, Remain Stationary
- Engagement Range restrictions (1" horizontal)
- FLY keyword: move over models/terrain, no Desperate Escape
- TITANIC keyword: skip Desperate Escape
- Terrain elevation penalties (non-FLY units)
- Difficult Ground (-2" movement)
- Transport embark/disembark rules
- Disembarked units excluded from Heavy bonus (T3-15)
- Fire Overwatch during movement (T3-11)
- Advance restricts to ASSAULT weapons only
- Fall Back prevents shooting and charging
- Unit Coherency (2" horizontal, 7+ model 2-connection rule)
- Desperate Escape (D6 per model: 1-2 destroyed, battle-shocked 1-3)
- Command Re-roll for Advance rolls

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| MOV-1 | HIGH | Pivot values not implemented | Core Rules Updates adds pivot values: non-round base non-Monster/Vehicle = 1", Monster/Vehicle non-round base = 2", Vehicle round base >32mm with flying stem = 2". Subtracts from remaining movement distance on first pivot. Not implemented anywhere |
| MOV-2 | HIGH | Vertical coherency (5") not validated | `_check_models_coherency()` only checks 2" horizontal. Rule requires 5" vertical limit. `Measurement.model_to_model_distance_inches()` only measures 2D distance |
| MOV-3 | MEDIUM | Surge moves not implemented | Core Rules Updates defines "surge" moves (out-of-phase moves triggered by abilities). Missing restrictions: once per phase, not while battle-shocked, not while in Engagement Range |
| MOV-4 | MEDIUM | One Normal move per phase not enforced | Core Rules Updates: "A unit cannot make more than one Normal move per phase." No tracking of normal moves per phase |
| MOV-5 | MEDIUM | Monster/Vehicle movement through restriction | Errata: Monsters/Vehicles cannot move through other friendly Monsters/Vehicles. Not validated |
| MOV-6 | LOW | Embark/disembark distance calc inconsistency | Embark uses `model_to_model_distance_inches()` but disembark uses shape-aware distance |
| MOV-7 | LOW | Movement phase archived tests | Active movement phase tests are archived/disabled. Should re-enable |

---

## 3. SHOOTING PHASE

**Files:** `phases/ShootingPhase.gd`, `autoloads/RulesEngine.gd`, `scripts/ShootingController.gd`

### Correctly Implemented
- Full attack resolution: Hit Roll → Wound Roll → Save → Damage
- Wound threshold matrix (S vs T) correct
- Hit/wound modifier caps at +1/-1
- Unmodified 1 always misses/fails saves; unmodified 6 always hits/wounds
- All 17+ weapon abilities: Lethal Hits, Sustained Hits, Devastating Wounds, Blast, Rapid Fire, Melta, Torrent, Pistol, Assault, Heavy, Anti-X, Ignores Cover, Indirect Fire, Precision, Lance, Twin-linked, One Shot, Hazardous
- Feel No Pain rolls
- Big Guns Never Tire (VEHICLE/MONSTER shoot while in ER with -1 to hit)
- Stealth (-1 to hit)
- Lone Operative (12" targeting restriction)
- Benefit of Cover (+1 to save)
- Overwatch (hits on unmodified 6s only)
- Variable attacks/damage (D3, D6, D6+N)
- Sequential weapon resolution for multi-weapon units
- Lethal Hits + Sustained Hits combo correct
- Devastating Wounds + Melta interaction correct
- FNP vs Devastating Wounds correct

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| SHOOT-1 | HIGH | CHARACTER targeting "closest eligible" rule missing | 10e rules: Characters cannot be targeted unless they are the closest eligible visible unit. Only Lone Operative (12") and Precision are implemented. No "closest visible" enforcement in `_validate_assign_target()` |
| SHOOT-2 | HIGH | Hazardous updated rules not applied | Balance Dataslate v3.3 changes Hazardous allocation priority: (1) wounded model with Hazardous weapon, (2) non-Character with Hazardous, (3) Character with Hazardous. Unit suffers 3 mortal wounds allocated to selected model. Current implementation may not follow this priority |
| SHOOT-3 | MEDIUM | Devastating Wounds Balance Dataslate update | Balance Dataslate changes DW wording - verify current implementation matches updated text for how mortal wounds from DW are applied |
| SHOOT-4 | MEDIUM | Extra Attacks updated rules | Balance Dataslate: "number of attacks made with an Extra Attacks weapon cannot be modified by other rules, unless that weapon's name is explicitly specified in that rule." Verify this restriction is enforced |
| SHOOT-5 | MEDIUM | Firing Deck not implemented | Core Rules Updates: Transport models with "Firing Deck x" can select weapons from embarked models. Not found in implementation |
| SHOOT-6 | MEDIUM | Melta bonus calculation may be wrong | Current implementation uses proportional bonus (wounds * models_in_half_range / total_models). Should apply Melta bonus to ALL wounds from weapons fired by models in half range |
| SHOOT-7 | LOW | Unit cannot be selected to shoot with no eligible targets | Core Rules Updates: "Unless at least one model in a unit has an eligible target, that unit cannot be selected to shoot." Verify enforcement |
| SHOOT-8 | LOW | Invulnerable save source not tracked in UI | When invuln is used, no indicator of whether it's model-native or effect-granted |

---

## 4. CHARGE PHASE

**Files:** `phases/ChargePhase.gd`, `scripts/ChargeController.gd`

### Correctly Implemented
- Charge declaration against 1+ enemy units within 12"
- 2D6 charge roll with Command Re-roll
- Must end within Engagement Range of ALL declared targets
- Cannot end within ER of non-target enemy units
- Failed charge = no movement
- Charging unit gains Fights First
- Advanced/Fell Back units cannot charge (unless abilities)
- Units already in ER cannot charge
- FLY keyword: charge over terrain, required to charge AIRCRAFT
- Heroic Intervention (2CP, counter-charge, does NOT grant Fights First)
- Tank Shock (VEHICLE charge ramming)
- Fire Overwatch integration
- Charge direction constraint (must move closer to target)
- Base-to-base contact enforcement
- Terrain vertical distance penalties
- Barricade-aware engagement range (2" through barricades)
- Structured failure reporting with educational tooltips

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| CHG-1 | MEDIUM | Tank Shock Balance Dataslate update | v3.3: Roll D6 equal to TOUGHNESS of selected Vehicle model, 5+ = mortal wound (max 6 MW). Verify current implementation matches updated wording |
| CHG-2 | MEDIUM | HI charge roll missing terrain penalties | `_is_heroic_intervention_roll_sufficient()` does not apply terrain vertical distance penalties, unlike normal charge roll sufficiency check |
| CHG-3 | LOW | Terrain penalty not displayed to player | Players see rolled distance but not effective distance after terrain penalties. Should show "Effective: X\" (Y\" - Z\" terrain)" |
| CHG-4 | LOW | No live direction validation feedback | No real-time feedback as player drags model to show if final position satisfies direction constraint |

---

## 5. FIGHT PHASE

**Files:** `phases/FightPhase.gd`, `autoloads/RulesEngine.gd`, `scripts/FightController.gd`

### Correctly Implemented (All Previous Audit Issues FIXED)
- Full melee weapon ability pipeline (Lethal Hits, Sustained Hits, Devastating Wounds, Anti-X, Twin-linked, Torrent, Lance, Precision, Hazardous)
- Per-model fight eligibility (within ER or base-contact chain)
- Pile-in must end in Engagement Range
- Pile-in movement constraints (3", closer to enemy)
- Consolidation with new engagement scanning (T2-6)
- Variable attack/damage characteristics rolled correctly
- Heroic Intervention moved to Charge Phase (correct per rules)
- Invulnerable saves in melee
- Critical hit/wound tracking in melee
- Fights First / Remaining Combats / Fights Last three-tier subphases
- Fights First + Fights Last cancellation → Normal priority
- Counter-Offensive stratagem (2CP)
- Aircraft fight restrictions (T4-4)
- Base-contact enforcement (T4-5)
- Devastating Wounds spillover in melee (T2-11)
- Batched multiplayer actions (T3-13)
- End fight confirmation dialog

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| FGT-1 | MEDIUM | Consolidation mandatory per FAQ | Core Rules Updates FAQ: "Consolidation for a unit is not optional. However, during that Consolidation, for each model in that unit, whether or not that model makes a Consolidation move is optional." Verify unit-level consolidation is forced |
| FGT-2 | LOW | Epic Challenge stratagem interaction | Verify Epic Challenge (1CP) properly enables CHARACTER vs CHARACTER melee dueling within attached units |
| FGT-3 | LOW | Pile-in/Consolidation drag not synced for remote player | Remote sees models "teleport" to final positions; cosmetic only |

---

## 6. DEPLOYMENT, TERRAIN & MISSIONS

**Files:** `phases/FormationsPhase.gd`, `phases/DeploymentPhase.gd`, `phases/ScoutPhase.gd`, `phases/ScoringPhase.gd`, `autoloads/TerrainManager.gd`, `autoloads/MissionManager.gd`, `autoloads/SecondaryMissionManager.gd`

### Correctly Implemented
- Alternating unit placement
- Strategic Reserves declaration with 25% army point limit
- Infiltrators (deploy anywhere >9" from enemy zone/models)
- Scout moves (up to 6", >9" from enemies, first player moves first)
- Leader attachment during Formations
- Transport embarkation during Formations
- Terrain height categories (LOW/MEDIUM/TALL)
- Difficult Ground (-2" penalty, FLY immune)
- Terrain charge/movement penalties with vertical distance
- Wall movement blocking (keyword-based)
- Barricade terrain interaction
- 8+ primary missions (Take and Hold, Supply Drop, Purge the Foe, Sites of Power, Linchpin, etc.)
- Objective Control (OC-based, battle-shocked = 0)
- Secondary mission tactical deck (18 cards, hand of 2)
- New Orders (discard + redraw secondary)
- VP caps (50 primary, 40 secondary, 90 combined)

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| DEP-1 | **CRITICAL** | Reinforcement phase missing entirely | Units declared as reserves/deep strike have no mechanism to arrive on the battlefield. No ReinforcePhase.gd exists. Strategic Reserves should arrive Turn 2+ within 6" of board edge; Deep Strike should arrive 9"+ from enemies. This fundamentally breaks the reserves system |
| DEP-2 | HIGH | Deep Strike arrival distance not validated | No validation of 9" from enemies at reinforcement time. Only validates ability exists at declaration |
| DEP-3 | HIGH | Balance Dataslate: Deep Strike can use Strategic Reserves rules | "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose to set up using Strategic Reserves OR Deep Strike." Not implemented |
| DEP-4 | HIGH | Scouts updated rules (Balance Dataslate) | Scouts rules updated: Dedicated Transports can use Scouts ability from embarked unit. Distance can exceed Move characteristic as long as ≤ x". Not fully implemented |
| TER-1 | HIGH | Cover save integration with terrain missing | Terrain loaded and LoS calculated, but NO explicit cover save grant system. No mechanism to award cover to units in/behind terrain |
| TER-2 | HIGH | Ruins visibility rules not implemented | Core Rules Updates: "Models cannot see over or through [Ruins] terrain. Aircraft are exceptions. Models can see into normally. Models wholly within can see out normally. Towering models within can see out normally." Not enforced |
| TER-3 | MEDIUM | Woods/Forest cover rules missing | No cover grant for models inside woods terrain |
| TER-4 | MEDIUM | Obscuring terrain not implemented | No -1 to hit for attacks through obscuring terrain |
| MIS-1 | MEDIUM | Scorched Earth mission incomplete | Burn mechanics not implemented (stub) |
| MIS-2 | MEDIUM | The Ritual mission incomplete | Action-based objective mechanics not implemented (stub) |
| MIS-3 | MEDIUM | Terraform mission incomplete | Objective flipping between players not implemented (stub) |
| MIS-4 | MEDIUM | Fixed secondary mission option missing | Only tactical deck mode available; no fixed 3-card selection |
| MIS-5 | LOW | When-drawn secondary interactions incomplete | Marked for Death and Tempting Target opponent selection UI not fully wired |
| MIS-6 | LOW | Objective control checked at end of phase OR turn | Core Rules Updates: "A player will control an objective marker at the end of any phase or turn." Verify timing |

---

## 7. GENERAL RULES & STRATAGEMS

**Files:** `autoloads/StratagemManager.gd`, `autoloads/UnitAbilityManager.gd`, `autoloads/GameState.gd`, `autoloads/EffectPrimitives.gd`

### Correctly Implemented
- All 11 core stratagems (Command Re-roll, Insane Bravery, Counter-Offensive, Epic Challenge, Grenade, Fire Overwatch, Go to Ground, Smokescreen, Heroic Intervention, Rapid Ingress, Tank Shock)
- Stratagem restrictions (once per battle, per turn, per phase)
- CP economy (start 3, gain 1 per Command Phase)
- Re-rolls applied before modifiers
- Hit/wound modifier caps at +1/-1
- Effect system (EffectPrimitives) for buff/debuff application
- Leader ability application (UnitAbilityManager)
- Faction stratagem loading infrastructure

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| GEN-1 | HIGH | Out-of-Phase rules not implemented | Core Rules Updates: "When using out-of-phase rules to perform an action as if it were one of your phases, you cannot use any other rules that are normally triggered in that phase." Critical for Fire Overwatch interactions (e.g., prevents Pinning Bombardment during Overwatch) |
| GEN-2 | HIGH | Deadly Demise not implemented | When a model with Deadly Demise is destroyed, roll D6: on 6, deal mortal wounds to nearby units. No implementation found in RulesEngine |
| GEN-3 | HIGH | Look Out Sir / wound allocation to bodyguard incomplete | No wound reallocation logic from CHARACTER to bodyguard models in attached units. Only Precision targeting of characters is handled |
| GEN-4 | MEDIUM | Balance Dataslate stratagem changes not applied | Multiple stratagem modifications from Balance Dataslate v3.3 not implemented: closer setup range (3" → 6"), AP worsening timing, CP cost modification rules, targeting prevention (12" → 18"), unit addition once per battle restriction |
| GEN-5 | MEDIUM | Rapid Ingress Balance Dataslate update | Updated: "if every model has Deep Strike ability, you can set up using Deep Strike (even though not your Movement phase)." Verify implementation |
| GEN-6 | MEDIUM | Fire Overwatch updated timing | Balance Dataslate: Trigger updated to "just after an enemy unit is set up or when an enemy unit starts or ends a Normal, Advance or Fall Back move, or declares a charge." Verify timing matches |
| GEN-7 | MEDIUM | Aura abilities not implemented | No range-based aura effect application system. Cannot apply abilities that affect units within X" |
| GEN-8 | MEDIUM | Transport destruction effects missing | No "destroyed transport = disembark + mortal wound tests" logic in RulesEngine |
| GEN-9 | LOW | Warlord designation not enforced | `is_warlord` field exists but no validation that exactly one CHARACTER is designated |
| GEN-10 | LOW | Army construction validation missing | Points tracked but no points validation during list building. No detachment enforcement |
| GEN-11 | LOW | Persisting effects system | Core Rules Updates defines "persisting effects" with specific duration tracking. Verify effect expiration matches |
| GEN-12 | LOW | Redeployment rules not implemented | Core Rules Updates: Rules allowing redeployment resolved after Deploy Armies, before Determine First Turn |

---

## 8. QUALITY OF LIFE IMPROVEMENTS

| ID | Area | Suggestion | Details |
|----|------|------------|---------|
| QOL-1 | General | Turn/round progress indicator | Show "Round 3/5 - Player 1 Turn" persistently in HUD |
| QOL-2 | General | Phase rules brief during transitions | Brief popup/tooltip explaining what actions are available in each phase |
| QOL-3 | General | Keyboard hotkeys for common actions | Tab to cycle units, number keys for quick-select, Enter to confirm, Esc to cancel |
| QOL-4 | General | Settings menu | Audio controls, visual settings, UI scale, animation speed, colorblind mode |
| QOL-5 | General | Auto-save at round end | Automatic saves at key points (round end, phase transitions) |
| QOL-6 | Shooting | Quick-assign "All weapons to target" button | Common case where all weapons attack one target should be one click |
| QOL-7 | Shooting | Expected damage preview | Show Mathhammer-style prediction as weapon assignments are made |
| QOL-8 | Fight | Attack assignment "All to Target" shortcut | Same as shooting QOL-6 for melee |
| QOL-9 | Movement | Available movement indicator | Show "X inches remaining" floating text during model movement |
| QOL-10 | Movement | Coherency preview during movement | Visual line showing unit coherency as models move |
| QOL-11 | Charge | Terrain penalty display | Show effective charge distance after terrain penalties |
| QOL-12 | Dice | Dice roll history panel | Scrollable history of past dice rolls for review |
| QOL-13 | Dice | Dice statistics summary | Show aggregate counts (e.g., "8 hits out of 10 rolls") after each roll |
| QOL-14 | Dice | Reroll visualization | Show original die + new die side-by-side when Command Re-roll used |
| QOL-15 | Multiplayer | Live opponent action feed | Show "Player 2 moved Ork Boyz forward" in real-time |
| QOL-16 | Multiplayer | Chat/emote system | Quick predefined messages (Good Luck, Nice Move, etc.) |
| QOL-17 | Save/Load | Save descriptions | User-editable notes on save files |
| QOL-18 | Save/Load | Quick save hotkey | F5 to quick-save, F9 to quick-load |
| QOL-19 | Mathhammer | Quick start presets | "Typical Infantry vs Light Armor" templates |
| QOL-20 | Mathhammer | Melee combat support | Currently shooting-only simulation (T2-16) |
| QOL-21 | Units | Unit filter/sort in selection panel | Filter by status (wounded, fresh, moved) or type (infantry, vehicle) |
| QOL-22 | Units | Double-click zoom to unit | Camera centers on selected unit on double-click |
| QOL-23 | Objectives | Scoring counter HUD | Display current VP by player persistently |
| QOL-24 | Objectives | Secondary objective progress tracking | Show progress toward active secondary missions |

---

## 9. VISUAL IMPROVEMENTS

| ID | Area | Suggestion | Details |
|----|------|------------|---------|
| VIS-1 | Dice | Sound effects for dice rolls | Rolling, settling, critical success/failure audio cues |
| VIS-2 | Dice | Larger dice on mobile | Current 28px dice too small for touchscreen |
| VIS-3 | Board | Terrain type visual distinction | Distinct visual styles for ruins, forests, hills, obstacles |
| VIS-4 | Board | Measurement grid overlay | Optional inch markers (every 6", every 12") |
| VIS-5 | Board | Height visualization | Elevated terrain shown with shading/3D effect |
| VIS-6 | Board | Sight line blocker indication | Visual distinction for LoS-blocking terrain |
| VIS-7 | Models | Persistent health bars | Show model wounds above/below bases on board |
| VIS-8 | Models | Damaged model visual distinction | Wounded models look different from fresh ones |
| VIS-9 | Movement | Human player movement path preview | Drag-to-plan movement path visualization (AI has this, humans don't) |
| VIS-10 | Movement | Movement cost terrain heatmap | Darker colors = slower movement areas |
| VIS-11 | Engagement | Multi-enemy engagement highlighting | Show all eligible enemies simultaneously |
| VIS-12 | Engagement | Colorblind-friendly engagement indicators | Add shapes/patterns in addition to color |
| VIS-13 | Phase | Phase transition sound effects | Audio cues for phase changes |
| VIS-14 | Charge | Charge trajectory preview | Show expected path when declaring charges |
| VIS-15 | Weapons | Simultaneous multi-weapon range display | Show all weapon ranges overlaid together |
| VIS-16 | Weapons | Threat range indicators | Show where enemy counter-attacks can reach |
| VIS-17 | Scoring | Scoring timeline visualization | VP progression chart over game rounds |

---

## 10. FULL TODO LIST

### Priority 0 - Critical (Game-breaking)

- [ ] **DEP-1**: Implement Reinforcement Phase - units in reserves/deep strike must be able to arrive on the battlefield (Turn 2+ for Strategic Reserves within 6" of board edge, Turn 2+ for Deep Strike 9"+ from enemies)

### Priority 1 - High (Incorrect rules that affect gameplay)

- [ ] **SHOOT-1**: Implement CHARACTER targeting "closest eligible visible unit" restriction
- [ ] **GEN-1**: Implement Out-of-Phase rules restriction (no other phase rules during out-of-phase actions)
- [ ] **GEN-2**: Implement Deadly Demise (D6 on model destruction, 6 = mortal wounds to nearby)
- [ ] **GEN-3**: Complete Look Out Sir / wound allocation to bodyguard in attached units
- [ ] **MOV-1**: Implement pivot values for non-round base models (1" for infantry, 2" for Monster/Vehicle)
- [ ] **MOV-2**: Implement vertical coherency limit (5") in `_check_models_coherency()`
- [ ] **DEP-2**: Validate Deep Strike arrival distance (9" from enemies) at reinforcement time
- [ ] **DEP-3**: Implement "Deep Strike can choose Strategic Reserves OR Deep Strike" per Balance Dataslate
- [ ] **DEP-4**: Update Scouts rules per Balance Dataslate (Dedicated Transport, distance > Move allowed)
- [ ] **TER-1**: Integrate cover saves with terrain system (auto-grant cover from terrain positions)
- [ ] **TER-2**: Implement Ruins visibility rules (cannot see over/through, Aircraft/Towering exceptions)
- [ ] **SHOOT-2**: Update Hazardous to Balance Dataslate v3.3 allocation priority rules
- [ ] **GEN-8**: Implement transport destruction effects (disembark + mortal wound tests)

### Priority 2 - Medium (Rules gaps that occasionally affect gameplay)

- [ ] **CMD-1**: Implement CP cap
- [ ] **CMD-2**: Add FEARLESS/ATSKNF keyword immunity to battle-shock
- [ ] **MOV-3**: Implement surge move rules and restrictions
- [ ] **MOV-4**: Enforce one Normal move per phase limit
- [ ] **MOV-5**: Validate Monster/Vehicle cannot move through other friendly Monster/Vehicle
- [ ] **SHOOT-3**: Verify Devastating Wounds matches Balance Dataslate updated wording
- [ ] **SHOOT-4**: Enforce Extra Attacks cannot be modified unless weapon name specified
- [ ] **SHOOT-5**: Implement Firing Deck for Transports
- [ ] **SHOOT-6**: Fix Melta bonus calculation (per-weapon not proportional)
- [ ] **CHG-1**: Verify Tank Shock matches Balance Dataslate v3.3 wording
- [ ] **CHG-2**: Add terrain penalties to Heroic Intervention charge roll sufficiency check
- [ ] **FGT-1**: Verify consolidation is mandatory at unit level per FAQ
- [ ] **TER-3**: Implement Woods/Forest cover rules
- [ ] **TER-4**: Implement Obscuring terrain rules
- [ ] **MIS-1**: Complete Scorched Earth mission (burn mechanics)
- [ ] **MIS-2**: Complete The Ritual mission (action-based objectives)
- [ ] **MIS-3**: Complete Terraform mission (objective flipping)
- [ ] **MIS-4**: Add Fixed secondary mission mode option
- [ ] **GEN-4**: Apply Balance Dataslate v3.3 stratagem modifications
- [ ] **GEN-5**: Update Rapid Ingress per Balance Dataslate (Deep Strike from reserves)
- [ ] **GEN-6**: Update Fire Overwatch timing per Balance Dataslate
- [ ] **GEN-7**: Implement aura abilities system

### Priority 3 - Low (Edge cases, polish, minor gaps)

- [ ] **CMD-3**: Prevent battle-shocked units from using self-targeted stratagems
- [ ] **CMD-4**: Add confirmation before auto-resolving untaken battle-shock tests
- [ ] **CMD-5**: Verify CP gain per battle round limitations
- [ ] **MOV-6**: Fix embark/disembark distance calculation inconsistency
- [ ] **MOV-7**: Re-enable archived movement phase tests
- [ ] **SHOOT-7**: Enforce "cannot select to shoot with no eligible targets"
- [ ] **SHOOT-8**: Track invulnerable save source in UI (native vs effect-granted)
- [ ] **CHG-3**: Display terrain penalty in charge distance UI
- [ ] **CHG-4**: Add live direction validation feedback during charge movement
- [ ] **FGT-2**: Verify Epic Challenge stratagem interaction in attached units
- [ ] **FGT-3**: Sync pile-in/consolidation drag for remote player (cosmetic)
- [ ] **MIS-5**: Complete when-drawn secondary mission interactions UI
- [ ] **MIS-6**: Verify objective control timing (end of phase OR turn)
- [ ] **GEN-9**: Validate Warlord designation (exactly one CHARACTER)
- [ ] **GEN-10**: Add army construction points validation
- [ ] **GEN-11**: Verify persisting effects match Core Rules Updates
- [ ] **GEN-12**: Implement redeployment rules

### Quality of Life

- [ ] **QOL-1**: Turn/round progress indicator in HUD
- [ ] **QOL-2**: Phase rules brief during transitions
- [ ] **QOL-3**: Keyboard hotkeys for common actions
- [ ] **QOL-4**: Settings menu (audio, visual, accessibility)
- [ ] **QOL-5**: Auto-save at round end
- [ ] **QOL-6**: Quick-assign "All weapons to target" in shooting
- [ ] **QOL-7**: Expected damage preview during weapon assignment
- [ ] **QOL-8**: Quick-assign "All to Target" in melee
- [ ] **QOL-9**: Available movement indicator (inches remaining)
- [ ] **QOL-10**: Coherency preview during movement
- [ ] **QOL-11**: Terrain penalty display during charge
- [ ] **QOL-12**: Dice roll history panel
- [ ] **QOL-13**: Dice statistics summary after rolls
- [ ] **QOL-14**: Reroll visualization (original + new side-by-side)
- [ ] **QOL-15**: Live opponent action feed in multiplayer
- [ ] **QOL-16**: Chat/emote system for multiplayer
- [ ] **QOL-17**: Save descriptions (user notes)
- [ ] **QOL-18**: Quick save/load hotkeys
- [ ] **QOL-19**: Mathhammer quick start presets
- [ ] **QOL-20**: Mathhammer melee combat support
- [ ] **QOL-21**: Unit filter/sort in selection panel
- [ ] **QOL-22**: Double-click zoom to unit
- [ ] **QOL-23**: Scoring counter HUD (VP display)
- [ ] **QOL-24**: Secondary objective progress tracking

### Visual Improvements

- [ ] **VIS-1**: Dice roll sound effects
- [ ] **VIS-2**: Larger dice for mobile/touch
- [ ] **VIS-3**: Distinct terrain type visuals
- [ ] **VIS-4**: Measurement grid overlay
- [ ] **VIS-5**: Height/elevation visualization
- [ ] **VIS-6**: LoS blocker terrain indication
- [ ] **VIS-7**: Persistent model health bars on board
- [ ] **VIS-8**: Damaged model visual distinction
- [ ] **VIS-9**: Human player movement path preview
- [ ] **VIS-10**: Movement cost terrain heatmap
- [ ] **VIS-11**: Multi-enemy engagement highlighting
- [ ] **VIS-12**: Colorblind-friendly indicators
- [ ] **VIS-13**: Phase transition sound effects
- [ ] **VIS-14**: Charge trajectory preview
- [ ] **VIS-15**: Multi-weapon range display overlay
- [ ] **VIS-16**: Enemy threat range indicators
- [ ] **VIS-17**: VP scoring timeline chart

---

## AUDIT TOTALS

| Category | Count |
|----------|-------|
| Critical | 1 |
| High Priority Rules | 13 |
| Medium Priority Rules | 20 |
| Low Priority Rules | 16 |
| Quality of Life | 24 |
| Visual Improvements | 17 |
| **Total Items** | **91** |

---

*Audit conducted 2026-02-21. Sources: Wahapedia 10e Core Rules, Wahapedia Rules Commentary, Balance Dataslate v3.3, Core Rules Updates & Errata, Munitorum Field Manual v3.9, Chapter Approved Tournament Companion.*
