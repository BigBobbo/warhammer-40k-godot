# Abilities Audit

**Date:** 2026-02-22
**Scope:** All units across all army files, cross-referenced against wahapedia rules

---

## Table of Contents

1. [Summary](#summary)
2. [Broken Pipeline — Flags Set But Never Checked](#broken-pipeline)
3. [Once Per Battle — No Usage Tracking](#once-per-battle)
4. [Faction Abilities](#faction-abilities)
5. [Orks — Unit Ability Gaps](#orks-unit-ability-gaps)
6. [Adeptus Custodes — Unit Ability Gaps](#adeptus-custodes-unit-ability-gaps)
7. [Space Marines — Unit Ability Gaps](#space-marines-unit-ability-gaps)
8. [Core Abilities Audit](#core-abilities-audit)
9. [Detachment Rules](#detachment-rules)
10. [Implementation Status of ABILITY_EFFECTS Table](#ability-effects-table-status)

---

## Summary

| Category | Count |
|----------|-------|
| Broken pipeline (flags set, never checked by phase logic) | 0 |
| Once-per-battle abilities with no usage tracking | 0 |
| Faction abilities with broken/missing implementation | 0 |
| Datasheet abilities missing from ABILITY_EFFECTS table entirely | 1 |
| Datasheet abilities in ABILITY_EFFECTS but marked not implemented | 3 |
| Wargear abilities not implemented | 2 |
| Core abilities not implemented or partially implemented | 2 |
| Detachment rules not implemented | 0 |
| Oath of Moment rules text is outdated | 0 |
| **Total gaps** | **9** |

---

## Broken Pipeline

These abilities are marked `implemented: true` in `UnitAbilityManager.gd` and the flags ARE set on units, but the phase logic **never checks them**, so they have no in-game effect.

### 1. advance_and_charge — ChargePhase ignores flag
- **Ability:** Martial Inspiration (Blade Champion, Custodes)
- **Flag set:** `effect_advance_and_charge` via `UnitAbilityManager._apply_eligibility_effects()`
- **Where checked:** `ChargePhase._can_unit_charge()` (line 1034) checks `flags.get("advanced", false)` and returns false — but does NOT check `effect_advance_and_charge` to allow an exception
- **Fix:** Before returning false for advanced units, check `EffectPrimitives.has_effect_advance_and_charge(unit)`

### 2. fall_back_and_charge — ChargePhase ignores flag
- **Ability:** One Scalpel Short of a Medpack (Painboss, Orks)
- **Flag set:** `effect_fall_back_and_charge`
- **Where checked:** `ChargePhase._can_unit_charge()` (line 1037) checks `flags.get("fell_back", false)` and returns false — but does NOT check `effect_fall_back_and_charge`
- **Fix:** Before returning false for fell-back units, check `EffectPrimitives.has_effect_fall_back_and_charge(unit)`

### 3. fall_back_and_shoot — ~~ShootingPhase ignores flag~~ FIXED
- **Source:** No current ability grants this, but the flag/primitive exists for stratagem use
- **Flag set:** `effect_fall_back_and_shoot`
- **Where checked:** `ShootingPhase._can_unit_shoot()` now checks `EffectPrimitives.has_effect_fall_back_and_shoot(unit)` before returning false for fell-back units
- **Status:** Fixed — units with `effect_fall_back_and_shoot` flag can now shoot after falling back

### 4. ~~advance_and_shoot — ShootingPhase ignores flag~~ FIXED
- **Source:** No current ability grants this, but the flag/primitive exists for stratagem use
- **Flag set:** `effect_advance_and_shoot`
- **Where checked:** `ShootingPhase._can_unit_shoot()` now checks `EffectPrimitives.has_effect_advance_and_shoot(unit)` before restricting to assault weapons; `RulesEngine.validate_shooting_assignments()` also bypasses the Assault-only weapon restriction when the flag is set
- **Status:** Fixed — units with `effect_advance_and_shoot` flag can now shoot with all weapons after advancing

---

## Once Per Battle

These abilities should only be usable once per game but have no usage tracking mechanism.

### 1. ~~Martial Inspiration (Blade Champion, Custodes)~~ FIXED
- **Rules text:** "Once per battle, in your Charge phase, this model's unit is eligible to declare a charge in a turn which it Advanced."
- **Current state:** Once-per-battle tracking implemented via `_once_per_battle_used` dictionary in `UnitAbilityManager`. The flag is checked before applying in `_apply_eligibility_effects()` and `_apply_leader_abilities()`, and marked as used in `ChargePhase.on_declare_charge()` when a unit charges after advancing.
- **Status:** Fixed — once-per-battle tracking works correctly with save/load support

### ~~2. Sentinel Storm (Custodian Guard, Custodes)~~ FIXED
- **Rules text:** "Once per battle, in your Shooting phase, after this unit has shot, it can shoot again."
- **Implementation status:** Added to `ABILITY_EFFECTS` table with `once_per_battle: true`. `ShootingPhase._process_complete_shooting_for_unit()` checks `UnitAbilityManager.has_shoot_again_ability()` after a unit finishes shooting. If available, emits `sentinel_storm_available` signal; `ShootingController` shows `SentinelStormDialog` for player choice. `USE_SENTINEL_STORM` action marks ability as used via `mark_once_per_battle_used()` and resets the unit's shooting state so it can shoot again. `DECLINE_SENTINEL_STORM` completes shooting normally. AI always activates when available.
- **Status:** Fixed — once-per-battle tracking, UI prompt, AI support, and shoot-again flow all implemented

---

## Faction Abilities

### ~~Orks — Waaagh!~~ FIXED
- **Rules text:** "Once per battle, at the start of your Command phase, you can call a Waaagh!. If you do, until the start of your next Command phase: (1) Units with this ability are eligible to charge in a turn they Advanced. (2) Add 1 to Strength and Attacks of melee weapons. (3) Models have a 5+ invulnerable save."
- **Implementation status:** `FactionAbilityManager` tracks Waaagh! state via `activate_waaagh()`/`deactivate_waaagh()`. Once-per-battle enforced. `CommandPhase` offers `CALL_WAAAGH` action with validation. On activation, all Ork units with Waaagh! ability get `waaagh_active`, `effect_invuln=5`, and `effect_advance_and_charge` flags. `RulesEngine._resolve_melee_assignment()` checks `waaagh_active` flag and applies +1 Attacks, +1 Strength to melee weapons. Also resolves Da Biggest and da Best (+4 attacks) and Dead Brutal (damage=3 for 'Uge choppa). Melee save path now checks `effect_invuln` for the 5+ invuln. AI always activates when available. Deactivated at start of next Command phase.
- **Status:** Fixed — Waaagh! state manager, Command Phase UI trigger, melee bonuses, 5+ invuln, advance+charge, Da Biggest and da Best, Dead Brutal all implemented

### ~~Adeptus Custodes — Martial Ka'tah~~ FIXED
- **Rules text:** "Each time a unit with this ability is selected to fight, select one Ka'tah Stance: Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits). That stance is active until the unit finishes attacking."
- **Implementation status:** `FactionAbilityManager` tracks Ka'tah stance via `apply_katah_stance()`/`clear_katah_stance()`. `FightPhase` emits `katah_stance_required` signal after unit selection; `KatahStanceDialog` shows stance choice to player. Selected stance sets `effect_sustained_hits` or `effect_lethal_hits` flags on the unit. `RulesEngine._resolve_melee_assignment()` checks these flags in addition to weapon keywords. Stance is cleared after consolidation.
- **Status:** Fixed — fight phase stance selection UI, FactionAbilityManager tracking, RulesEngine integration for both Sustained Hits and Lethal Hits

### ~~Space Marines — Oath of Moment~~ FIXED
- **Rules text (Codex):** "Select one enemy unit. Each time a model with this ability makes an attack that targets your Oath of Moment target: you can re-roll the Hit roll. If your army does not include Black Templars/Blood Angels/Dark Angels/Deathwatch/Space Wolves keywords, add 1 to the Wound roll as well."
- **Implementation status:** `FactionAbilityManager` handles target selection and flags the target. `RulesEngine` checks `FactionAbilityManager.attacker_benefits_from_oath()` and applies full hit re-rolls (`REROLL_FAILED`) + `PLUS_ONE` to wound across all attack paths (ranged, auto-resolve, melee). Army JSON rules text updated to Codex wording.
- **Status:** Fixed — rules text updated, RulesEngine now applies correct Codex-era modifiers

---

## Orks — Unit Ability Gaps

### Warboss

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Leader | Core | No | No | Partial | Attachment system works but Leader ability not explicitly defined |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! state tracking, Command Phase trigger, advance+charge, +1 S/A melee, 5+ invuln |
| Might is Right | Datasheet | Yes | Yes (implemented) | Yes | +1 melee hit rolls working via RulesEngine |
| Da Biggest and da Best | Datasheet | Yes | Yes (implemented) | **Yes** | +4 melee attacks while Waaagh! active — applied in RulesEngine._resolve_melee_assignment() |

### Warboss in Mega Armour

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Leader | Core | No | No | Partial | Attachment system works |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! state tracking, Command Phase trigger, advance+charge, +1 S/A melee, 5+ invuln |
| Might is Right | Datasheet | Yes | Yes (implemented) | Yes | Working |
| Dead Brutal | Datasheet | Yes | Yes (implemented) | **Yes** | 'Uge choppa damage=3 while Waaagh! active — applied in RulesEngine._resolve_melee_assignment() |

### Boyz

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Get Da Good Bitz | Datasheet | Yes | Yes (implemented) | **Yes** | Sticky objectives — MissionManager.apply_sticky_objectives() locks controlled objectives at end of Command phase. Locks persist until opponent controls via OC or source unit destroyed |
| Bodyguard (20-model) | Special | Yes | No | Unknown | Double leader attachment for 20-model units |

### Kommandos

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Infiltrators | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Stealth | Core | Yes | Yes (RulesEngine) | **Yes** | Added to army JSON. RulesEngine.has_stealth_ability() detects it; -1 to hit applied in both resolve paths |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Throat Slittas | Datasheet | Yes | Yes (implemented) | **Yes** | Mortal wounds in shooting phase — roll 1D6 per model within 9" of enemy, 5+ = 1 MW. Unit cannot shoot if used. Player/AI prompt, full resolution |
| Sneaky Surprise | Datasheet | Yes | Yes (implemented) | **Yes** | Added to JSON. Blocks Fire Overwatch in both ChargePhase and MovementPhase. AI aware |
| Patrol Squad | Datasheet | Yes | Yes (not implemented) | **No** | Added to JSON. Unit splitting at deployment requires deployment system changes — flagged for future work |
| Distraction Grot | Wargear | Yes | Yes (implemented) | **Yes** | Added to JSON. Once per battle 5+ invuln when targeted in opponent's Shooting phase. Player/AI prompt, once-per-battle tracking |
| Bomb Squigs | Wargear | Yes | Yes (implemented) | **Yes** | Added to JSON. Once per battle after Normal move: select enemy within 12", roll D6: 3+ = D3 mortal wounds. Player/AI prompt, once-per-battle tracking |

### Battlewagon

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D6 | Core | Yes | Yes (implemented) | **Yes** | Mortal wounds on destruction — added to JSON, RulesEngine.resolve_deadly_demise() triggers on unit death |
| Firing Deck 11 | Core | **MISSING** | No | **No** | Embarked models can shoot — not in JSON or code |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Ramshackle | Datasheet | Yes | Yes (implemented) | **Yes** | Correctly worsens AP of incoming attacks by 1 |
| Damaged: 1-5 Wounds | Datasheet | Yes | Yes (RulesEngine) | **Yes** | -1 to hit when 1-5 wounds remaining — added to JSON, RulesEngine.is_damaged_profile_active() checks wounds and applies -1 to hit |
| 'Ard Case | Wargear | Yes | Yes (ArmyListManager) | **Yes** | +2 Toughness, lose Firing Deck — added to JSON, applied at army load time via WARGEAR_STAT_BONUSES. Updates meta.stats.toughness and removes firing_deck from transport_data |
| Transport (22 capacity) | Special | Yes | No | Unknown | Transport mechanic |

### Painboss (referenced in ABILITY_EFFECTS but no army JSON found)

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Feel No Pain 5+ | Core | N/A | No | Unknown | Painboss's own FNP |
| Leader | Core | N/A | No | Unknown | Can attach to Beast Snagga Boyz |
| Waaagh! | Faction | N/A | No | No | Missing |
| Dok's Toolz | Datasheet | N/A | Yes (implemented) | Partial | Flag set but needs army file |
| Sawbonez | Datasheet | **N/A** | No | **No** | Heal friendly CHARACTER 3 wounds — not implemented |
| One Scalpel Short of a Medpack | Datasheet | N/A | Yes (implemented) | **No** | Flag set but ChargePhase doesn't check it (see Broken Pipeline) |
| Grot Orderly | Wargear | **N/A** | No | **No** | Once per battle return D3 destroyed models — not implemented |

### Weirdboy (referenced in ABILITY_EFFECTS but no army JSON found)

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | N/A | No | No | Not implemented |
| Leader | Core | N/A | No | Unknown | Can attach to Boyz |
| Waaagh! | Faction | N/A | No | No | Missing |
| Waaagh! Energy | Datasheet | N/A | No | No | +1 S and D per 5 models, Hazardous at 10+ — not implemented |
| Da Jump (Psychic) | Datasheet | N/A | No | No | Teleport unit, risk D6 mortal wounds — not implemented |

---

## Adeptus Custodes — Unit Ability Gaps

### Blade Champion

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deep Strike | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Leader | Core | No | No | Partial | Attachment system works |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Swift Onslaught | Datasheet | Yes | Yes (implemented) | **Yes** | Reroll charge — `reroll_charge` primitive implemented, ChargePhase offers free ability reroll |
| Martial Inspiration | Datasheet | Yes | Yes (implemented) | **Yes** | Once-per-battle tracking implemented; ChargePhase checks advance_and_charge flag |

### Custodian Guard

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deep Strike | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Stand Vigil | Datasheet | Yes | Yes (implemented) | **Partial** | Reroll wound 1s works. "While within range of controlled objective, reroll all wound rolls" — objective-conditional part NOT implemented |
| Sentinel Storm | Datasheet | Yes (text only) | Yes (implemented) | **Yes** | Once per battle shoot again — implemented with UI prompt, AI support, once-per-battle tracking |
| Praesidium Shield | Wargear | Yes | Yes (ArmyListManager) | **Yes** | +1 Wounds — applied at army load time via WARGEAR_STAT_BONUSES. Updates meta.stats.wounds and model wound values |
| Vexilla | Wargear | Yes | Yes (ArmyListManager) | **Yes** | +1 OC — applied at army load time via WARGEAR_STAT_BONUSES. Updates meta.stats.objective_control |

### Witchseekers

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Scout 6" | Core | Yes | No (separate system) | Unknown | Should move 6" before first turn |
| Daughters of the Abyss | Datasheet | Yes | Yes (implemented) | **Partial** | Simplified as FNP 3+ always. Should be FNP 3+ against Psychic Attacks and mortal wounds only |
| Sanctified Flames | Datasheet | Yes (text only) | Yes (implemented) | **Yes** | After shooting, select one hit enemy unit — forced Battle-shock test (2D6 vs Ld). Implemented in ShootingPhase with hit tracking, auto-roll, and battle_shocked flag application |

### Caladius Grav-tank

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | Yes | Yes (implemented) | **Yes** | Mortal wounds on destruction — added to JSON, RulesEngine.resolve_deadly_demise() triggers on unit death |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Advanced Firepower | Datasheet | Yes | Yes (RulesEngine) | **Yes** | Conditional Lethal Hits by target type — Twin iliastus: Lethal Hits vs non-MONSTER/VEHICLE. Twin arachnus: Lethal Hits vs MONSTER/VEHICLE. check_advanced_firepower_lethal_hits() in RulesEngine, both resolve paths. Missing iliastus weapon added to JSON |
| Damaged: 1-5 Wounds | Datasheet | Yes | Yes (RulesEngine) | **Yes** | -1 to hit when 1-5 wounds remaining — added to JSON, RulesEngine.is_damaged_profile_active() checks wounds and applies -1 to hit |
| Invulnerable Save 5+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Contemptor-Achillus Dreadnought

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise 1 | Core | Yes | Yes (implemented) | **Yes** | Mortal wounds on destruction — added to JSON, RulesEngine.resolve_deadly_demise() triggers on unit death |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Dread Foe | Datasheet | Yes | Yes (FightPhase) | **Yes** | Mortal wounds on fight selection — auto-resolved when selected to fight. Roll D6 (+2 if charged): 4-5 = D3 MW, 6+ = 3 MW. RulesEngine.resolve_dread_foe() + FightPhase._resolve_dread_foe_then_pile_in() |
| Invulnerable Save 5+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Telemon Heavy Dreadnought

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | Yes | Yes (implemented) | **Yes** | Mortal wounds on destruction — added to JSON, RulesEngine.resolve_deadly_demise() triggers on unit death |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Guardian Eternal | Datasheet | Yes | Yes (RulesEngine) | **Yes** | -1 Damage to incoming attacks — JSON fixed (was "Eternal Protector"), ABILITY_EFFECTS entry added, RulesEngine applies minus_damage in all resolve paths (overwatch, auto-resolve, melee, interactive) |
| Devoted to Destruction | Datasheet | **MISSING** | No | **No** | +2 Attacks with dual Telemon caestus — not in JSON |
| Damaged: 1-4 Wounds | Datasheet | Yes | Yes (RulesEngine) | **Yes** | -1 to hit when 1-4 wounds remaining — added to JSON, RulesEngine.is_damaged_profile_active() checks wounds and applies -1 to hit |
| Invulnerable Save 4+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Shield-Captain

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deep Strike | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Leader | Core | No | No | Partial | Attachment system works but Leader ability not explicitly defined |
| Martial Ka'tah | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Stance selection in fight phase — Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) |
| Master of the Stances | Datasheet | Yes | Yes (implemented) | **Yes** | Once per battle: both Ka'tah stances active simultaneously. FightPhase offers "Both" option in KatahStanceDialog; FactionAbilityManager.apply_katah_stance() supports "both" stance; once-per-battle tracked via UnitAbilityManager |
| Strategic Mastery | Datasheet | Yes | Yes (implemented) | **Yes** | Once per battle round: reduce stratagem CP cost by 1 when targeting this unit. Integrated into StratagemManager.use_stratagem() and can_use_stratagem(); once-per-round tracked via UnitAbilityManager |
| Praesidium Shield | Wargear | Yes | Yes (ArmyListManager) | **Yes** | +1 Wounds — applied at army load time via WARGEAR_STAT_BONUSES. Updates meta.stats.wounds and model wound values |

---

## Space Marines — Unit Ability Gaps

### Intercessor Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Objective Secured | Datasheet | Yes | Yes (UnitAbilityManager) | **Yes** | Sticky objectives — added to JSON, MissionManager.apply_sticky_objectives() handles via has_sticky_objectives_ability() |
| Target Elimination | Datasheet | Yes | Yes (not implemented) | **No** | Added to JSON. +2 bolt rifle Attacks when targeting single enemy — requires ShootingPhase prompt for activation |

### Tactical Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Combat Squads | Datasheet | Yes | Yes (not implemented) | **No** | Added to JSON. Split into two 5-model units at deployment — requires deployment system changes |

### Infiltrator Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Infiltrators | Core | Yes | No (separate system) | Likely | Deployment logic |
| Scout 6" | Core | Yes | No (separate system) | Unknown | Pre-game movement |
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Omni-scramblers | Datasheet | Yes | Yes (UnitAbilityManager) | **Yes** | Blocks enemy deep strike within 12" — enforced in MovementPhase, DeploymentController, and AIDecisionMaker reinforcement placement validation |
| Helix Gauntlet | Wargear | **MISSING** | No | **No** | FNP 6+ for unit — optional wargear, not in JSON |
| Infiltrator Comms Array | Wargear | **MISSING** | No | **No** | 5+ to regain 1CP on stratagem — optional wargear, not in JSON |

---

## Core Abilities Audit

| Core Ability | Units With It | Implemented | Notes |
|---|---|---|---|
| Deep Strike | Blade Champion, Custodian Guard, Shield-Captain | Likely | Handled by deployment system, not ability pipeline |
| Infiltrators | Kommandos, Infiltrator Squad | Likely | Handled by deployment system |
| Scout 6" | Witchseekers, Infiltrator Squad | Unknown | Pre-game movement — needs verification |
| Stealth | Kommandos (per wahapedia) | **Yes** | Added to Kommandos army JSON. RulesEngine.has_stealth_ability() checks meta.abilities and applies -1 to hit on ranged attacks |
| Leader | Various characters | Partial | Attachment system works but Leader ability not explicitly tracked |
| Feel No Pain 5+ | Painboss | Unknown | Painboss not in army JSON files |
| Deadly Demise (D3/D6/1) | Battlewagon, Caladius, Telemon, Contemptor-Achillus, Weirdboy | **Yes** | Added to JSON for 4 units (Weirdboy has no army file). RulesEngine.resolve_deadly_demise() rolls trigger (6+), finds units within 6", applies mortal wounds. Hooked into ShootingPhase, FightPhase, and WoundAllocationOverlay |
| Firing Deck 11 | Battlewagon | **No** | No embarked shooting mechanic exists |

---

## Detachment Rules

These are army-wide bonuses from chosen detachments. All three are now implemented (P2-27).

### ~~Space Marines — Gladius Task Force: Combat Doctrines~~ FIXED
- **Devastator Doctrine:** Unit eligible to shoot after Advancing (all weapons, not just Assault)
- **Tactical Doctrine:** Unit eligible to shoot and charge after Falling Back
- **Assault Doctrine:** Unit eligible to charge after Advancing
- **Implementation:** `FactionAbilityManager` detects detachment from `GameState.state.factions[player].detachment`. `DETACHMENT_ABILITIES["Gladius Task Force"]` defines all three doctrines with once-per-battle-each tracking. `CommandPhase` offers `SELECT_COMBAT_DOCTRINE` actions; selected doctrine sets `effect_advance_and_shoot`, `effect_fall_back_and_shoot/charge`, or `effect_advance_and_charge` flags on all ADEPTUS ASTARTES units. Flags cleared at start of next Command Phase. AI selects based on battle round. Army JSON updated: detachment changed from "Battle Company" to "Gladius Task Force".
- **Status:** **Implemented** — Command Phase selection, flag application, AI support, save/load

### ~~Orks — War Horde: Get Stuck In~~ FIXED
- **Effect:** All Orks melee weapons gain Sustained Hits 1
- **Implementation:** Passive detachment ability. `FactionAbilityManager._apply_get_stuck_in()` sets `get_stuck_in` flag on all ORKS units at Command Phase start. `RulesEngine._resolve_melee_assignment()` checks `FactionAbilityManager.unit_has_get_stuck_in()` and grants Sustained Hits 1 to melee weapons (stacks with weapon's own Sustained Hits if any).
- **Status:** **Implemented** — passive flag, RulesEngine integration

### ~~Adeptus Custodes — Shield Host: Martial Mastery~~ FIXED
- **Effect:** At start of each battle round, choose: (1) unmodified 5+ hit rolls are Critical Hits in melee, or (2) improve melee AP by 1
- **Implementation:** `FactionAbilityManager` tracks `_active_mastery` per player per battle round. `CommandPhase` offers `SELECT_MARTIAL_MASTERY` actions when Custodes player has Shield Host detachment and hasn't selected for current round. Selected option sets `martial_mastery_crit_5` or `martial_mastery_improve_ap` flags on all units with Martial Ka'tah ability. `RulesEngine._resolve_melee_assignment()` applies: crit_on_5 lowers melee critical hit threshold from 6 to 5; improve_ap adds 1 to AP before defender's worsen_ap. AI picks based on enemy average save.
- **Status:** **Implemented** — battle round selection, crit threshold and AP integration, AI support

---

## Implementation Status of ABILITY_EFFECTS Table

All entries in `UnitAbilityManager.ABILITY_EFFECTS`:

| # | Ability Name | Condition | Effect Type | Implemented | Actually Working |
|---|---|---|---|---|---|
| 1 | Might is Right | while_leading | +1 melee hit | Yes | **Yes** |
| 2 | Speedboss | while_leading | +1 melee hit | Yes | **Yes** |
| 3 | Drill Boss | while_leading | +1 melee hit | Yes | **Yes** |
| 4 | Prophet of Da Great Waaagh! | while_leading | +1 melee hit & wound | Yes | **Yes** |
| 5 | More Dakka | while_leading | reroll ranged hits (1s) | Yes | **Yes** |
| 6 | Flashiest Gitz | while_leading | reroll all ranged hits | Yes | **Yes** |
| 7 | Red Skull Kommandos | while_leading | grant cover | Yes | **Yes** |
| 8 | Dok's Toolz | while_leading | FNP 5+ | Yes | **Yes** |
| 9 | Mad Dok | while_leading | FNP 5+ | Yes | **Yes** |
| 10 | One Scalpel Short of a Medpack | while_leading | fall_back_and_charge | Yes | **Yes** — ChargePhase now checks effect_fall_back_and_charge |
| 11 | Swift Onslaught | while_leading | reroll_charge | Yes | **Yes** — reroll_charge primitive implemented; ChargePhase offers free ability reroll before Command Re-roll |
| 12 | Martial Inspiration | while_leading | advance_and_charge | Yes | **Yes** — ChargePhase now checks effect_advance_and_charge + once-per-battle tracking added |
| 13 | Stand Vigil | always | reroll wounds (1s) | Yes | **Partial** — basic reroll works, objective-conditional upgrade missing |
| 14 | Ramshackle | always | worsen AP by 1 | Yes | **Yes** — correctly worsens AP of incoming attacks by 1 |
| 15 | Daughters of the Abyss | always | FNP 3+ | Yes | **Partial** — simplified. Should only apply vs Psychic/mortal wounds |
| 16 | Get Da Good Bitz | end_of_command | sticky objectives | Yes | **Yes** — MissionManager.apply_sticky_objectives() called at end of Command phase. Locks objectives, persists across turns until opponent controls via OC or source unit destroyed |
| 17 | Da Biggest and da Best | waaagh_active | +4 attacks | Yes | **Yes** — applied in RulesEngine._resolve_melee_assignment() when waaagh_active flag is set |
| 18 | Dead Brutal | waaagh_active | damage=3 | Yes | **Yes** — 'Uge choppa damage overridden to 3 in RulesEngine._resolve_melee_assignment() when waaagh_active flag is set |
| 19 | Sentinel Storm | always | shoot-again | Yes | **Yes** — once-per-battle shoot-again with UI prompt, AI support |
| 20 | Sanctified Flames | after_shooting | forced Battle-shock test | Yes | **Yes** — tracks hit targets, rolls 2D6 vs Ld, applies battle_shocked flag |
| 21 | Throat Slittas | start_of_shooting | mortal wounds vs nearby enemies | Yes | **Yes** — roll 1D6 per model within 9" of enemy, 5+ = MW. Player/AI prompt, unit cannot shoot if used |
| 22 | Deadly Demise | on_destruction | mortal wounds to all within 6" | Yes | **Yes** — roll 1D6 on unit death, on 6 each unit within 6" suffers D6/D3/1 mortal wounds. Hooked into ShootingPhase, FightPhase, WoundAllocationOverlay |
| 23 | Damaged | wounds_below_threshold | -1 to hit | Yes | **Yes** — RulesEngine.is_damaged_profile_active() checks current wounds vs threshold parsed from ability name. Applied in all 3 hit resolution paths (ranged interactive, ranged auto-resolve, melee) |
| 24 | Advanced Firepower | always | conditional Lethal Hits | Yes | **Yes** — RulesEngine.check_advanced_firepower_lethal_hits() checks weapon name + target keywords. Twin iliastus: Lethal Hits vs non-MONSTER/VEHICLE. Twin arachnus: Lethal Hits vs MONSTER/VEHICLE. Applied in all 4 ranged resolve paths |
| 25 | Dread Foe | on_fight_selection | mortal wounds on fight selection | Yes | **Yes** — Auto-resolved when selected to fight. Roll D6 (+2 if charged): 4-5 = D3 MW, 6+ = 3 MW. RulesEngine.resolve_dread_foe() + FightPhase integration |
| 26 | Guardian Eternal | always | minus_damage (1) | Yes | **Yes** — -1 Damage to all incoming attacks. JSON fixed (was "Eternal Protector"), RulesEngine applies in all resolve paths (overwatch, auto-resolve ranged, melee auto-resolve, interactive ranged, interactive melee). Min 1 damage enforced |
| 27 | Omni-scramblers | passive_aura | deep strike denial (12") | Yes | **Yes** — Enemy reinforcements cannot be set up within 12" of this unit. Enforced in MovementPhase (normal + Rapid Ingress), DeploymentController (UI), and AIDecisionMaker (candidate generation + validation) |
| 28 | Objective Secured | end_of_command | sticky objectives | Yes | **Yes** — Same mechanic as Get Da Good Bitz. MissionManager.apply_sticky_objectives() checks has_sticky_objectives_ability() which includes "Objective Secured" |
| 29 | Target Elimination | on_shooting_selection | +2 bolt rifle Attacks (single target) | No | **No** — Added to JSON and ABILITY_EFFECTS. Requires ShootingPhase prompt for activation choice |
| 30 | Combat Squads | deployment | unit split (two 5-model units) | No | **No** — Added to JSON and ABILITY_EFFECTS. Requires deployment system changes (same as Patrol Squad) |
| 31 | Master of the Stances | on_fight_selection | both Ka'tah stances active | Yes | **Yes** — Once per battle: both Dacatarai (Sustained Hits 1) and Rendax (Lethal Hits) active simultaneously. FightPhase offers "Both" option in KatahStanceDialog. FactionAbilityManager.apply_katah_stance() supports "both" stance. Once-per-battle tracked via UnitAbilityManager |
| 32 | Strategic Mastery | passive | reduce stratagem CP cost by 1 | Yes | **Yes** — Once per battle round: reduces CP cost by 1 for stratagems targeting this unit. Integrated into StratagemManager.use_stratagem() and can_use_stratagem(). Once-per-round tracked via UnitAbilityManager |

---

## Priority Recommendations

### P0 — Critical (abilities that claim to work but don't)
1. **Fix ChargePhase to check advance_and_charge flag** — Martial Inspiration — **DONE**
2. **Fix ChargePhase to check fall_back_and_charge flag** — One Scalpel Short of a Medpack — **DONE**
3. **Fix ShootingPhase to check fall_back_and_shoot flag** — future-proofing for stratagems/doctrines — **DONE**
4. **Fix ShootingPhase to check advance_and_shoot flag** — future-proofing for stratagems/doctrines — **DONE**
5. **Add once-per-battle tracking** for Martial Inspiration — **DONE**
6. **Fix Ramshackle** — currently FNP 6+, should be "worsen AP by 1" — **DONE**
7. **Update Oath of Moment rules text** — currently uses old Index wording — **DONE**

### P1 — High (missing abilities for units already in the game)
8. **Implement Martial Ka'tah** — affects all Custodes units (stance selection in fight phase) — **DONE**
9. **Implement Swift Onslaught** — reroll charge primitive needed — **DONE**
10. **Implement Sentinel Storm** — shoot-again mechanic for Custodian Guard — **DONE**
11. **Implement Sanctified Flames** — Battle-shock test after shooting (Witchseekers) — **DONE**
12. **Implement Throat Slittas** — mortal wounds mechanic (Kommandos) — **DONE**
13. **Implement Deadly Demise** — destruction-triggered mortal wounds (multiple vehicle units) — **DONE**
14. **Implement Damaged profiles** — -1 to hit at low wounds (Caladius, Telemon, Battlewagon) — **DONE**
15. **Add Stealth to Kommandos army JSON** — missing core ability — **DONE**
16. **Implement Advanced Firepower** — conditional Lethal Hits (Caladius) — **DONE**
17. **Implement Dread Foe** — mortal wounds on fight selection (Contemptor-Achillus) — **DONE**
18. **Implement Guardian Eternal** — -1 Damage (Telemon) — also fix JSON which has wrong ability name — **DONE**

### P2 — Medium (require new systems or are less impactful)
19. **Implement Waaagh! system** — unlocks Da Biggest/Dead Brutal + base Ork faction ability — **DONE**
20. **Implement wargear stat bonuses** — Praesidium Shield (+1W), Vexilla (+1OC), 'Ard Case (+2T) — **DONE**
21. **Fix Daughters of the Abyss** — restrict FNP 3+ to psychic/mortal wounds only
22. **Fix Stand Vigil** — add objective-conditional reroll-all upgrade
23. **Implement Get Da Good Bitz** — sticky objectives (Boyz) — **DONE**
24. **Implement Omni-scramblers mechanically** — block deep strike within 12" — **DONE**
25. **Add missing Kommandos abilities to JSON** — Sneaky Surprise, Patrol Squad, Distraction Grot, Bomb Squigs — **DONE**
26. **Add missing Space Marine abilities to JSON** — Objective Secured, Target Elimination, Combat Squads — **DONE**
27. **Implement Detachment rules** — Combat Doctrines, Get Stuck In, Martial Mastery — **DONE**

### P3 — Low (units not yet in army files or niche mechanics)
28. **Add Shield-Captain unit** — Master of the Stances, Strategic Mastery — **DONE**
29. **Add Painboss to army JSON** — Sawbonez (heal), Grot Orderly (revive)
30. **Add Weirdboy to army JSON** — Waaagh! Energy, Da Jump
31. **Implement Firing Deck** — embarked model shooting (Battlewagon)
32. **Implement Transport capacity** — embark/disembark mechanics
33. **Add optional wargear** — Helix Gauntlet (FNP 6+), Infiltrator Comms Array (CP regen)
34. **Implement Devoted to Destruction** — +2 Attacks with dual Telemon caestus
35. **Implement Bodyguard (20-model)** — double Leader attachment for large Boyz units
