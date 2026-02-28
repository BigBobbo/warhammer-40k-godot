# HOLISTIC AUDIT - Warhammer 40k Godot Implementation

**Date:** 2026-02-27 (updated from 2026-02-21 audit)
**Sources:** Wahapedia Core Rules & Commentary, Balance Dataslate v3.3, Core Rules Updates & Errata, Munitorum Field Manual v3.9, Chapter Approved Tournament Companion, Quick Start Guide
**Codebase:** `/Users/robertocallaghan/Documents/claude/godotv2/40k`

---

## TABLE OF CONTENTS

1. [Executive Summary](#executive-summary)
2. [Recently Completed Items](#recently-completed-items)
3. [Command Phase](#1-command-phase)
4. [Movement Phase](#2-movement-phase)
5. [Shooting Phase](#3-shooting-phase)
6. [Charge Phase](#4-charge-phase)
7. [Fight Phase](#5-fight-phase)
8. [Deployment, Terrain & Missions](#6-deployment-terrain--missions)
9. [General Rules & Stratagems](#7-general-rules--stratagems)
10. [User-Reported Bugs](#8-user-reported-bugs)
11. [Quality of Life Improvements](#9-quality-of-life-improvements)
12. [Visual Improvements](#10-visual-improvements)
13. [Full TODO List](#11-full-todo-list)

---

## Executive Summary

The project is a **production-quality implementation** of Warhammer 40k 10th Edition in Godot with multiplayer support. Core mechanics across all 5 phases are substantially implemented with 1200+ tests, comprehensive AI with difficulty scaling, and full multiplayer infrastructure.

**Key Strengths:**
- All 5 game phases fully implemented with correct sequencing
- 17+ weapon abilities working (Lethal Hits, Sustained Hits, Devastating Wounds, Blast, Rapid Fire, Melta, Torrent, etc.)
- Full melee weapon ability pipeline
- Excellent multiplayer with deterministic RNG and optimistic execution
- Comprehensive AI with difficulty levels (Easy/Normal/Hard/Competitive)
- Mathhammer Monte Carlo simulation tool with both shooting and melee
- Formations phase with leader attachment, transport embarkation, reserves declaration
- Scout moves, Roll-off, and full deployment system
- Cover system supporting all terrain types (ruins, woods, craters, obstacles, barricades)
- Reinforcements/Deep Strike/Strategic Reserves arrival working
- Deadly Demise, Look Out Sir/bodyguard, Firing Deck all implemented
- Fights First / Remaining / Fights Last three-tier fight sequencing

**Critical Gaps Remaining:**
- CHARACTER targeting "closest eligible" rule not enforced in shooting
- Wound allocation not controlled by defending player
- Engagement Range missing 5" vertical component
- Attached unit starting strength not combined for battle-shock
- Pivot values for non-round base models not implemented
- Out-of-Phase rules restriction not implemented
- Several Balance Dataslate v3.3 changes not applied
- Ruins-specific visibility rules not enforced
- Transport destruction effects (disembark + mortal wounds) missing

---

## Recently Completed Items

The following items from the original Feb 21 audit have been verified as implemented:

| Item | Status | Evidence |
|------|--------|----------|
| DEP-1: Reinforcement Phase | DONE | MovementPhase.gd `_validate_place_reinforcement()`, `_process_place_reinforcement()` - full reserves arrival system |
| GEN-2: Deadly Demise | DONE | RulesEngine.gd:7755 `resolve_deadly_demise()`, UnitAbilityManager.gd `has_deadly_demise()` |
| GEN-3: Look Out Sir / bodyguard wound allocation | DONE | RulesEngine.gd:7118-7182 bodyguard_alive tracking, ShootingPhase.gd:1554 bodyguard-first allocation |
| DEP-2: Deep Strike 9" arrival validation | DONE | Part of reinforcement system in MovementPhase.gd |
| SHOOT-5: Firing Deck | DONE | TransportManager.gd `has_firing_deck()`, ShootingPhase.gd `_show_firing_deck_dialog()`, FiringDeckDialog.gd |
| TER-1: Cover from terrain integration | DONE | RulesEngine.gd `check_benefit_of_cover()` supports all terrain types (T2-10) |
| TER-3: Woods/Forest cover | DONE | Included in T2-10 all-terrain-type cover (within-only for woods/craters) |
| SHOOT-3: Devastating Wounds verified | DONE | T2-11 - spillover and FNP interaction verified, 23 tests |
| SHOOT-6: Melta bonus calculation | DONE | T1-1 - proportional melta allocation for models in half range |

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
- Oath of Moment faction ability (AI + player)

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| CMD-1 | MEDIUM | No CP cap implementation | Core rules + FAQ: Players can gain at most 1 additional CP per battle round from non-automatic sources. No cap validation in `_generate_command_points()` |
| CMD-2 | MEDIUM | No FEARLESS/ATSKNF keyword support | Units with these keywords should be immune to battle-shock. No keyword check in `_identify_units_needing_tests()` |
| CMD-3 | LOW | Battle-shocked units can use own stratagems | `StratagemManager.gd` only prevents targeting battle-shocked units with friendly stratagems, not all stratagem usage by battle-shocked units |
| CMD-4 | LOW | No confirmation before auto-resolving untaken tests | Auto-resolve silently; should warn player |
| CMD-6 | **HIGH** | Attached unit starting strength incorrect for battle-shock | `is_below_half_strength()` does not combine bodyguard + attached character models for starting strength calculation. A WARBOSS (1 model) + 10 Boyz should have starting strength 11, but currently only counts the bodyguard's 10 |

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
- Disembarked units excluded from Heavy bonus
- Fire Overwatch during movement
- Advance restricts to ASSAULT weapons only
- Fall Back prevents shooting and charging
- Unit Coherency (2" horizontal, 7+ model 2-connection rule)
- Desperate Escape (D6 per model: 1-2 destroyed, battle-shocked 1-3)
- Command Re-roll for Advance rolls
- Reinforcements/Strategic Reserves arrival (Turn 2+)
- Deep Strike arrival with 9" from enemies validation

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| MOV-1 | HIGH | Pivot values not implemented | Core Rules Updates: non-round base non-Monster/Vehicle = 1", Monster/Vehicle non-round = 2", Vehicle round >32mm with flying stem = 2". Subtracts from remaining movement on first pivot |
| MOV-2 | HIGH | Vertical coherency (5") not validated | `_check_models_coherency()` only checks 2" horizontal. Rule requires 5" vertical limit |
| MOV-8 | **HIGH** | Engagement Range missing 5" vertical component | `Measurement.is_in_engagement_range_shape_aware()` is purely 2D (1" horizontal only). Rules require 1" horizontal AND 5" vertical. Models at different heights could be incorrectly in/out of ER |
| MOV-3 | MEDIUM | Surge moves not implemented | Core Rules Updates: "surge" moves (out-of-phase moves) have restrictions: once per phase, not while battle-shocked, not while in Engagement Range |
| MOV-4 | MEDIUM | One Normal move per phase not enforced | "A unit cannot make more than one Normal move per phase." No tracking |
| MOV-5 | MEDIUM | Monster/Vehicle cannot move through friendly Monster/Vehicle | Errata restriction not validated |
| MOV-6 | LOW | Embark/disembark distance calc inconsistency | Embark uses `model_to_model_distance_inches()` but disembark uses shape-aware distance |

---

## 3. SHOOTING PHASE

**Files:** `phases/ShootingPhase.gd`, `autoloads/RulesEngine.gd`, `scripts/ShootingController.gd`

### Correctly Implemented
- Full attack resolution: Hit Roll -> Wound Roll -> Save -> Damage
- Wound threshold matrix (S vs T) correct
- Hit/wound modifier caps at +1/-1
- Unmodified 1 always misses/fails saves; unmodified 6 always hits/wounds
- All 17+ weapon abilities working
- Feel No Pain rolls
- Big Guns Never Tire (VEHICLE/MONSTER shoot in ER with -1 to hit)
- Stealth (-1 to hit)
- Lone Operative (12" targeting restriction)
- Benefit of Cover (+1 to save, all terrain types)
- Overwatch (hits on unmodified 6s only)
- Variable attacks/damage (D3, D6, D6+N)
- Damage does NOT carry over between models (excess lost - correct)
- Save improvement cap (+1 max) enforced
- Firing Deck for transports
- Precision targeting of CHARACTERs
- Look Out Sir / bodyguard wound allocation (wounds to bodyguard first)
- Deadly Demise triggered on unit destruction

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| SHOOT-1 | **CRITICAL** | CHARACTER targeting "closest eligible visible unit" rule missing | 10e: Characters with W<=9 near friendly non-Character units (3+ models or VEHICLE/MONSTER) cannot be targeted unless they are the closest eligible visible unit. Only Lone Operative (12") and Precision are implemented. No "closest visible" check in `_validate_assign_target()` |
| SHOOT-9 | **HIGH** | Wound allocation not controlled by defending player | 10e: The defending player chooses which model receives wounds (with wounded-first restriction). Currently the system auto-allocates without defender input. Critical for multiplayer correctness |
| SHOOT-2 | MEDIUM | Hazardous updated rules (Balance Dataslate v3.3) | Allocation priority: (1) wounded model with Hazardous weapon, (2) non-Character with Hazardous, (3) Character with Hazardous. Verify current implementation matches |
| SHOOT-4 | MEDIUM | Extra Attacks cannot be modified unless weapon name specified | Balance Dataslate restriction on Extra Attacks number modification. Verify enforcement |
| SHOOT-7 | LOW | Unit cannot be selected to shoot with no eligible targets | "Unless at least one model in a unit has an eligible target, that unit cannot be selected to shoot." Verify enforcement |
| SHOOT-8 | LOW | Invulnerable save source not tracked in UI | No indicator of native vs effect-granted invuln |

---

## 4. CHARGE PHASE

**Files:** `phases/ChargePhase.gd`, `scripts/ChargeController.gd`

### Correctly Implemented
- Charge declaration against 1+ enemy units within 12"
- 2D6 charge roll with Command Re-roll
- Must end within ER of ALL declared targets
- Cannot end within ER of non-target enemy units
- Failed charge = no movement
- Charging unit gains Fights First
- Advanced/Fell Back units cannot charge
- Units already in ER cannot charge
- FLY keyword: charge over terrain, required to charge AIRCRAFT
- Heroic Intervention (2CP, counter-charge, does NOT grant Fights First)
- Tank Shock (VEHICLE charge ramming)
- Fire Overwatch integration
- Charge direction constraint (must move closer to target)
- Base-to-base contact enforcement
- Terrain vertical distance penalties
- Barricade-aware engagement range (2" through barricades)

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| CHG-1 | MEDIUM | Tank Shock Balance Dataslate update | v3.3: Roll D6 equal to TOUGHNESS, 5+ = MW (max 6 MW). Verify current implementation |
| CHG-2 | MEDIUM | HI charge roll missing terrain penalties | `_is_heroic_intervention_roll_sufficient()` does not apply terrain vertical distance penalties |
| CHG-3 | LOW | Terrain penalty not displayed to player | Players see rolled distance but not effective distance after terrain penalties |
| CHG-4 | LOW | No live direction validation feedback during charge drag |

---

## 5. FIGHT PHASE

**Files:** `phases/FightPhase.gd`, `autoloads/RulesEngine.gd`, `scripts/FightController.gd`

### Correctly Implemented
- Full melee weapon ability pipeline
- Per-model fight eligibility (ER + base-contact chain)
- Pile-in (3", closer to enemy, must end in ER, B2B enforcement)
- Consolidation with new engagement scanning
- Consolidation toward objectives as fallback
- Variable attack/damage in melee
- Heroic Intervention in Charge Phase (correct)
- Invulnerable saves in melee
- Fights First / Remaining / Fights Last three-tier subphases
- FF + FL cancellation -> Normal priority
- Counter-Offensive stratagem (2CP)
- Aircraft fight restrictions
- Devastating Wounds spillover in melee

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| FGT-1 | MEDIUM | Consolidation mandatory per FAQ | "Consolidation for a unit is not optional. However, for each model, whether or not that model makes a Consolidation move is optional." Verify unit-level consolidation is forced |
| FGT-2 | LOW | Epic Challenge stratagem interaction | Verify proper CHARACTER vs CHARACTER dueling in attached units |
| FGT-3 | LOW | Pile-in/consolidation drag not synced for remote player (cosmetic) |

---

## 6. DEPLOYMENT, TERRAIN & MISSIONS

**Files:** `phases/FormationsPhase.gd`, `phases/DeploymentPhase.gd`, `phases/ScoutPhase.gd`, `phases/ScoringPhase.gd`, `autoloads/TerrainManager.gd`, `autoloads/MissionManager.gd`

### Correctly Implemented
- Alternating unit placement
- Strategic Reserves declaration (25% army point limit)
- Infiltrators (deploy anywhere >9" from enemy zone/models)
- Scout moves (up to X", >9" from enemies)
- Leader attachment during Formations
- Transport embarkation during Formations
- Roll-off for first turn with winner's choice
- Terrain height categories (LOW/MEDIUM/TALL)
- Difficult Ground (-2" penalty, FLY immune)
- Terrain charge/movement penalties
- Cover from all terrain types (ruins, woods, craters, obstacles, barricades)
- 8+ primary missions
- OC-based objective control (battle-shocked = 0)
- Secondary mission tactical deck (18 cards, hand of 2)
- VP caps (50 primary, 40 secondary, 90 combined)
- Reinforcements arrive Turn 2+ (Strategic Reserves 6" from edge, Deep Strike 9"+ from enemies)

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| TER-2 | HIGH | Ruins visibility rules not implemented | Core Rules Updates: "Models cannot see over or through [Ruins] terrain. Aircraft/Towering exceptions. Models can see into normally. Models wholly within can see out normally." Not enforced in LineOfSightManager |
| DEP-3 | MEDIUM | Deep Strike can use Strategic Reserves rules (Balance Dataslate) | "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose to set up using Strategic Reserves OR Deep Strike." Not implemented |
| DEP-4 | MEDIUM | Scouts updated rules (Balance Dataslate) | Dedicated Transports can use Scouts ability from embarked unit. Distance can exceed Move characteristic as long as <= x" |
| TER-4 | MEDIUM | Obscuring terrain keyword not implemented | No special rules for Obscuring terrain features |
| MIS-1 | MEDIUM | Scorched Earth mission incomplete | Burn mechanics not implemented (stub) |
| MIS-2 | MEDIUM | The Ritual mission incomplete | Action-based objective mechanics not implemented (stub) |
| MIS-3 | MEDIUM | Terraform mission incomplete | Objective flipping not implemented (stub) |
| MIS-4 | MEDIUM | Fixed secondary mission option missing | Only tactical deck mode; no fixed 3-card selection |
| MIS-5 | LOW | When-drawn secondary interactions incomplete | Marked for Death and Tempting Target opponent selection not fully wired |
| MIS-6 | LOW | Objective control timing verification | "A player will control an objective marker at the end of any phase or turn." Verify timing |

---

## 7. GENERAL RULES & STRATAGEMS

**Files:** `autoloads/StratagemManager.gd`, `autoloads/UnitAbilityManager.gd`, `autoloads/GameState.gd`

### Correctly Implemented
- All 11 core stratagems (Command Re-roll, Insane Bravery, Counter-Offensive, Epic Challenge, Grenade, Fire Overwatch, Go to Ground, Smokescreen, Heroic Intervention, Rapid Ingress, Tank Shock)
- Stratagem restrictions (once per battle, per turn, per phase)
- CP economy (start 3, gain 1 per Command Phase)
- Re-rolls applied before modifiers
- Hit/wound modifier caps at +1/-1
- Effect system (EffectPrimitives) for buff/debuff application
- Leader ability application (UnitAbilityManager) with 20+ abilities
- Faction ability infrastructure (Oath of Moment)
- Deadly Demise triggered on model destruction (D6 on 6, MWs within 6")
- Look Out Sir / bodyguard wound allocation
- Firing Deck transport support

### Issues Found

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| GEN-1 | HIGH | Out-of-Phase rules not implemented | "When using out-of-phase rules to perform an action as if it were one of your phases, you cannot use any other rules that are normally triggered in that phase." Critical for Fire Overwatch interactions |
| GEN-4 | MEDIUM | Balance Dataslate stratagem changes not applied | Multiple modifications from v3.3 not implemented |
| GEN-5 | MEDIUM | Rapid Ingress Balance Dataslate update | Updated Deep Strike interaction rules |
| GEN-6 | MEDIUM | Fire Overwatch updated timing per Balance Dataslate | Trigger expanded to include "when enemy unit starts or ends a move" |
| GEN-7 | MEDIUM | Aura abilities not implemented | No range-based aura effect system. `passive_aura` defined in UnitAbilityManager but not functionally applied to other units |
| GEN-8 | HIGH | Transport destruction effects missing | No "destroyed transport = forced disembark + D6 mortal wound tests per model" logic. When a transport dies, embarked units are silently lost |
| GEN-9 | LOW | Warlord designation not enforced | `is_warlord` field exists but no validation of exactly one CHARACTER |
| GEN-10 | LOW | Army construction validation missing | Points tracked but no validation during list building |
| GEN-11 | LOW | Persisting effects duration tracking | Verify effect expiration matches Core Rules Updates |
| GEN-12 | LOW | Redeployment rules not implemented | Rules allowing redeployment resolved after Deploy Armies |
| GEN-13 | **MEDIUM** | Attached unit Toughness not correctly resolved | For wound rolls against an attached unit, the Toughness should be that of the bodyguard unit. RulesEngine reads T from the target unit directly with no special handling for attached characters. May cause incorrect wound thresholds when attacking attached units |

---

## 8. USER-REPORTED BUGS

These issues were reported through playtesting:

| ID | Severity | Issue | Details |
|----|----------|-------|---------|
| BUG-1 | HIGH | Leader attachment not visually working for human player | User reports selecting leaders in Formations phase but they deploy separately. AI attachment appears to work. Investigate FormationsPhase -> DeploymentPhase integration for human players |
| BUG-2 | HIGH | Wound allocation position mismatch | "The Kommandos are not in the place where they are expected to be when I allocate wounds" - wound allocation overlay showing models in wrong positions |
| BUG-3 | HIGH | Line of sight not working as expected | Reported as a general LoS issue. May relate to TER-2 (ruins visibility) or enhanced LoS system bugs |
| BUG-4 | MEDIUM | Cannot allocate attacks separately per weapon | "I should be able to allocate each user's attacks separately" - weapon-by-weapon target assignment may not be working correctly for multi-weapon units |
| BUG-5 | MEDIUM | Save/Load games do not work against AI | Load system does not properly restore AI player state. SaveLoadManager has no AI player detection or state serialization |
| BUG-6 | LOW | Deployment zone toggle missing or hard to find | User requested "toggle to show deployment zones" - may need more prominent UI |

---

## 9. QUALITY OF LIFE IMPROVEMENTS

| ID | Area | Suggestion | Details |
|----|------|------------|---------|
| QOL-1 | General | Turn/round progress indicator | Show "Round 3/5 - Player 1 Turn" persistently in HUD |
| QOL-2 | General | Phase rules brief during transitions | Brief popup/tooltip explaining available actions in each phase |
| QOL-3 | General | Keyboard hotkeys for common actions | Tab to cycle units, number keys for quick-select, Enter to confirm, Esc to cancel |
| QOL-4 | General | Settings menu | Audio controls, visual settings, UI scale, animation speed, colorblind mode |
| QOL-5 | General | Auto-save at round end | Automatic saves at key points (round end, phase transitions) |
| QOL-6 | Shooting | Quick-assign "All weapons to target" button | Common case should be one click |
| QOL-7 | Shooting | Expected damage preview | Mathhammer-style prediction as weapon assignments are made |
| QOL-8 | Fight | Attack assignment "All to Target" shortcut | Same as QOL-6 for melee |
| QOL-9 | Movement | Available movement indicator | Show "X inches remaining" floating text during model movement |
| QOL-10 | Movement | Coherency preview during movement | Visual line showing unit coherency as models move |
| QOL-11 | Charge | Terrain penalty display | Show effective charge distance after terrain penalties |
| QOL-12 | Dice | Dice roll history panel | Scrollable history of past dice rolls for review |
| QOL-13 | Dice | Dice statistics summary | Show aggregate counts after each roll |
| QOL-14 | Dice | Reroll visualization | Show original + new die side-by-side for Command Re-roll |
| QOL-15 | Multiplayer | Live opponent action feed | Show "Player 2 moved Ork Boyz forward" in real-time |
| QOL-16 | Multiplayer | Chat/emote system | Quick predefined messages (Good Luck, Nice Move, etc.) |
| QOL-17 | Save/Load | Save descriptions | User-editable notes on save files |
| QOL-18 | Save/Load | Quick save hotkey | F5 to quick-save, F9 to quick-load |
| QOL-19 | Mathhammer | Quick start presets | "Typical Infantry vs Light Armor" templates |
| QOL-20 | Units | Unit filter/sort in selection panel | Filter by status (wounded, fresh, moved) or type |
| QOL-21 | Units | Double-click zoom to unit | Camera centers on selected unit |
| QOL-22 | Objectives | Scoring counter HUD | Display current VP by player persistently |
| QOL-23 | Objectives | Secondary objective progress tracking | Show progress toward active secondary missions |
| QOL-24 | General | Undo last action | Allow undoing the last model placement/move/assignment |
| QOL-25 | Shooting | Weapon range comparison view | Side-by-side range circles for all weapons on selected unit |

---

## 10. VISUAL IMPROVEMENTS

| ID | Area | Suggestion | Details |
|----|------|------------|---------|
| VIS-1 | Dice | Sound effects for dice rolls | Rolling, settling, critical success/failure audio cues |
| VIS-2 | Dice | Larger dice on mobile | Current dice too small for touchscreen |
| VIS-3 | Board | Terrain type visual distinction | Distinct visual styles for ruins, forests, hills, obstacles |
| VIS-4 | Board | Measurement grid overlay | Optional inch markers (every 6", every 12") |
| VIS-5 | Board | Height visualization | Elevated terrain with shading/3D effect |
| VIS-6 | Board | Sight line blocker indication | Visual distinction for LoS-blocking terrain |
| VIS-7 | Models | Persistent health bars | Show model wounds above/below bases on board |
| VIS-8 | Models | Damaged model visual distinction | Wounded models look different from fresh |
| VIS-9 | Movement | Human player movement path preview | Drag-to-plan movement path (AI has this, humans don't) |
| VIS-10 | Movement | Movement cost terrain heatmap | Darker colors = slower movement areas |
| VIS-11 | Engagement | Multi-enemy engagement highlighting | Show all eligible enemies simultaneously |
| VIS-12 | Engagement | Colorblind-friendly engagement indicators | Add shapes/patterns in addition to color |
| VIS-13 | Phase | Phase transition sound effects | Audio cues for phase changes |
| VIS-14 | Charge | Charge trajectory preview | Show expected path when declaring charges |
| VIS-15 | Weapons | Multi-weapon range display overlay | Show all weapon ranges overlaid together |
| VIS-16 | Weapons | Enemy threat range indicators | Show where enemy counter-attacks can reach |
| VIS-17 | Scoring | VP scoring timeline chart | VP progression chart over game rounds |

---

## 11. FULL TODO LIST

### Priority 0 - Critical (Game-breaking)

- [ ] **SHOOT-1**: Implement CHARACTER targeting "closest eligible visible unit" restriction - Characters with W<=9 near friendly non-Character units cannot be targeted unless closest eligible visible target
- [ ] **SHOOT-9**: Implement defender-controlled wound allocation - The defending player must choose which model receives wounds (with wounded-first restriction). Currently auto-allocated

### Priority 1 - High (Incorrect rules that significantly affect gameplay)

- [ ] **GEN-1**: Implement Out-of-Phase rules restriction (no other phase rules during out-of-phase actions like Overwatch)
- [ ] **GEN-8**: Implement transport destruction effects (forced disembark + D6 mortal wound tests per embarked model)
- [ ] **MOV-1**: Implement pivot values for non-round base models (1" infantry, 2" Monster/Vehicle)
- [ ] **MOV-2**: Implement vertical coherency limit (5") in `_check_models_coherency()`
- [ ] **MOV-8**: Add 5" vertical component to Engagement Range checks in Measurement.gd
- [ ] **CMD-6**: Fix attached unit starting strength for battle-shock (combine bodyguard + character models)
- [ ] **TER-2**: Implement Ruins visibility rules (cannot see through/over, Aircraft/Towering exceptions)
- [ ] **BUG-1**: Fix leader attachment not working visually for human player in deployment
- [ ] **BUG-2**: Fix wound allocation overlay showing models in wrong positions
- [ ] **BUG-3**: Investigate and fix Line of Sight issues

### Priority 2 - Medium (Rules gaps that occasionally affect gameplay)

- [ ] **CMD-1**: Implement CP cap (1 additional CP per battle round from non-automatic sources)
- [ ] **CMD-2**: Add FEARLESS/ATSKNF keyword immunity to battle-shock
- [ ] **MOV-3**: Implement surge move rules and restrictions
- [ ] **MOV-4**: Enforce one Normal move per phase limit
- [ ] **MOV-5**: Validate Monster/Vehicle cannot move through friendly Monster/Vehicle
- [ ] **SHOOT-2**: Update Hazardous to Balance Dataslate v3.3 allocation priority
- [ ] **SHOOT-4**: Enforce Extra Attacks number cannot be modified unless weapon name specified
- [ ] **CHG-1**: Verify Tank Shock matches Balance Dataslate v3.3 wording
- [ ] **CHG-2**: Add terrain penalties to Heroic Intervention charge roll sufficiency check
- [ ] **FGT-1**: Verify consolidation is mandatory at unit level per FAQ
- [ ] **TER-4**: Implement Obscuring terrain keyword rules
- [ ] **DEP-3**: Implement "Deep Strike can choose Strategic Reserves OR Deep Strike" per Balance Dataslate
- [ ] **DEP-4**: Update Scouts rules per Balance Dataslate (Dedicated Transport, distance flexibility)
- [ ] **MIS-1**: Complete Scorched Earth mission (burn mechanics)
- [ ] **MIS-2**: Complete The Ritual mission (action-based objectives)
- [ ] **MIS-3**: Complete Terraform mission (objective flipping)
- [ ] **MIS-4**: Add Fixed secondary mission mode option
- [ ] **GEN-4**: Apply Balance Dataslate v3.3 stratagem modifications
- [ ] **GEN-5**: Update Rapid Ingress per Balance Dataslate (Deep Strike interaction)
- [ ] **GEN-6**: Update Fire Overwatch timing per Balance Dataslate
- [ ] **GEN-7**: Implement aura abilities system (range-based effects on nearby units)
- [ ] **GEN-13**: Fix attached unit Toughness resolution (use bodyguard T for wound rolls)
- [ ] **BUG-4**: Fix weapon-by-weapon attack allocation for multi-weapon units
- [ ] **BUG-5**: Fix save/load games with AI players (serialize AI player state)

### Priority 3 - Low (Edge cases, polish, minor gaps)

- [ ] **CMD-3**: Prevent battle-shocked units from using self-targeted stratagems
- [ ] **CMD-4**: Add confirmation before auto-resolving untaken battle-shock tests
- [ ] **MOV-6**: Fix embark/disembark distance calculation inconsistency
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
- [ ] **BUG-6**: Make deployment zone toggle more prominent

### Quality of Life (see Section 9 for full details)

- [ ] QOL-1 through QOL-25

### Visual Improvements (see Section 10 for full details)

- [ ] VIS-1 through VIS-17

---

## AUDIT TOTALS

| Category | Count |
|----------|-------|
| Critical | 2 |
| High Priority Rules | 10 |
| Medium Priority Rules | 22 |
| Low Priority Rules | 15 |
| Quality of Life | 25 |
| Visual Improvements | 17 |
| **Total Open Items** | **91** |

---

*Audit updated 2026-02-27. Previous audit 2026-02-21. Sources: Wahapedia 10e Core Rules, Rules Commentary, Balance Dataslate v3.3, Core Rules Updates & Errata, Munitorum Field Manual v3.9, Chapter Approved Tournament Companion. Cross-referenced against MASTER_AUDIT.md completed items.*
