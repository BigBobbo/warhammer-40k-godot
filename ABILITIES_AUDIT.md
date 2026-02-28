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
| Datasheet abilities missing from ABILITY_EFFECTS table entirely | 0 |
| Datasheet abilities in ABILITY_EFFECTS but marked not implemented | 5 |
| Wargear abilities not implemented | 1 |
| Core abilities not implemented or partially implemented | 1 |
| Detachment rules not implemented | 0 |
| Oath of Moment rules text is outdated | 0 |
| **Total gaps** | **7** |

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
| Firing Deck 11 | Core | Yes | Yes (ShootingPhase/TransportManager) | **Yes** | Added to JSON. ArmyListManager parses "FIRING DECK" ability, sets transport_data.firing_deck=11. ShootingPhase detects firing deck, shows FiringDeckDialog for model/weapon selection (up to 11). 'Ard Case wargear removes firing_deck via WARGEAR_STAT_BONUSES |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Ramshackle | Datasheet | Yes | Yes (implemented) | **Yes** | Correctly worsens AP of incoming attacks by 1 |
| Damaged: 1-5 Wounds | Datasheet | Yes | Yes (RulesEngine) | **Yes** | -1 to hit when 1-5 wounds remaining — added to JSON, RulesEngine.is_damaged_profile_active() checks wounds and applies -1 to hit |
| 'Ard Case | Wargear | Yes | Yes (ArmyListManager) | **Yes** | +2 Toughness, lose Firing Deck — added to JSON, applied at army load time via WARGEAR_STAT_BONUSES. Updates meta.stats.toughness and removes firing_deck from transport_data |
| Transport (22 capacity) | Special | Yes | No | Unknown | Transport mechanic |

### Painboss

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Feel No Pain 5+ | Core | Yes | No (stats-based) | **Yes** | Painboss's own FNP — `fnp: 5` in stats, handled by RulesEngine |
| Leader | Core | No | No | Partial | Attachment system works — `leader_data.can_lead: ["BEAST SNAGGA BOYZ"]` |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Dok's Toolz | Datasheet | Yes | Yes (implemented) | **Yes** | Grants FNP 5+ to led unit — `grant_fnp` effect applied via UnitAbilityManager |
| Sawbonez | Datasheet | Yes | Yes (implemented) | **Yes** | At end of Movement phase, heal friendly BEAST SNAGGA CHARACTER within 3" up to 3 wounds. MovementPhase offers USE_SAWBONEZ action |
| One Scalpel Short of a Medpack | Datasheet | Yes | Yes (implemented) | **Yes** | Led unit can charge after falling back — `fall_back_and_charge` effect, ChargePhase checks it |
| Grot Orderly | Wargear | Yes | Yes (implemented) | **Yes** | Once per battle: at start of Command phase, return up to D3 destroyed Bodyguard models. CommandPhase offers USE_GROT_ORDERLY action, once-per-battle tracking |

### Weirdboy

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | Yes | Yes (implemented) | **Yes** | Mortal wounds on destruction — RulesEngine.resolve_deadly_demise() handles via ability name parsing |
| Leader | Core | Yes | No | Partial | Attachment system works — `leader_data.can_lead: ["BOYZ"]` |
| Waaagh! | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Waaagh! system implemented |
| Waaagh! Energy | Datasheet | Yes | Yes (not implemented) | **No** | +1 S and D per 5 models in led unit, Hazardous at 10+ — requires dynamic weapon stat modification |
| Da Jump (Psychic) | Datasheet | Yes | Yes (not implemented) | **No** | Teleport unit at end of Movement phase, risk D6 mortal wounds — requires MovementPhase integration |

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
| Firing Deck 11 | Battlewagon | **Yes** | Added to JSON. ArmyListManager parses ability and sets transport_data.firing_deck=11. ShootingPhase shows FiringDeckDialog for embarked model weapon selection. 'Ard Case removes firing_deck |

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
| 33 | Sawbonez | end_of_movement | heal CHARACTER 3 wounds | Yes | **Yes** — At end of Movement phase, heal friendly BEAST SNAGGA CHARACTER within 3" up to 3 wounds. MovementPhase offers USE_SAWBONEZ/DECLINE_SAWBONEZ actions. Proximity-checked, model-level healing |
| 34 | Grot Orderly | start_of_command | return D3 destroyed models | Yes | **Yes** — Once per battle: at start of Command phase, return up to D3 destroyed Bodyguard models. CommandPhase offers USE_GROT_ORDERLY action. D3 roll, model revival, once-per-battle tracking |
| 35 | Da Jump | end_of_movement | teleport unit | No | **No** — Once per turn: at end of Movement phase, roll D6: on 1 unit suffers D6 MW; on 2+ teleport 9"+ from enemies. Requires MovementPhase integration |
| 36 | Waaagh! Energy | while_leading | +1 S/D per 5 models | No | **No** — +1 Strength and Damage to 'Eadbanger per 5 models in led unit; Hazardous at 10+ models. Requires dynamic weapon stat modification |

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
29. **Add Painboss to army JSON** — Sawbonez (heal), Grot Orderly (revive) — **DONE**
30. **Add Weirdboy to army JSON** — Waaagh! Energy, Da Jump — **DONE**
31. **Implement Firing Deck** — embarked model shooting (Battlewagon) — **DONE**
32. **Implement Transport capacity** — embark/disembark mechanics
33. **Add optional wargear** — Helix Gauntlet (FNP 6+), Infiltrator Comms Array (CP regen)
34. **Implement Devoted to Destruction** — +2 Attacks with dual Telemon caestus
35. **Implement Bodyguard (20-model)** — double Leader attachment for large Boyz units

### P1 — High (Deployment rules gaps)
36. **Fix reserves point cap from 25% to 50%** — Chapter Approved 2025-26 rules specify max 50% of points AND 50% of units in reserves, but `DeploymentPhase._validate_place_in_reserves()` at line 276 uses `int(total_points * 0.25)`. Update to `0.50` and add unit count validation. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-RULES-1 as DONE. — **DONE**
37. **Destroy reserves units not arrived by end of Round 3** — Per rules, any reserves units not on the battlefield by end of Round 3 count as destroyed. Add check at end-of-round processing to mark remaining `IN_RESERVES` units as `DESTROYED` with notification to both players. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-RULES-2 as DONE. — **DONE**

### P2 — Medium (Deployment QoL and multiplayer)
38. **Add per-model undo during deployment** — Current undo resets entire unit. Add Ctrl+Z to undo only the last placed model by decrementing `model_idx` and clearing last `temp_positions` entry in `DeploymentController.gd`. Keep full-unit reset as separate button. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-QOL-1 as DONE.
39. **Add coherency distance display during deployment placement** — Show real-time distance from ghost model to nearest placed model as a floating label (e.g., "1.8\"" green / "2.3\"" red) near the cursor in `DeploymentController.gd`. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-QOL-2 as DONE.
40. **Add opponent deployment camera pan and notification in multiplayer** — When opponent deploys a unit in multiplayer: briefly pan camera to show placement location, show toast "[Unit Name] deployed", add deployment log panel showing order of all deployments. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-QOL-4 as DONE.
41. **Implement graceful disconnect handling during deployment** — Replace `get_tree().quit()` on peer disconnect in `NetworkManager._on_peer_disconnected()` with reconnection dialog, grace period, option to save state via `SaveLoadManager` or continue in single-player mode. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-MP-1 as DONE.
42. **Reduce deployment timeout punitiveness** — Increase timeout during deployment phase beyond 90s for large armies, add warnings at 60s and 30s remaining, consider auto-placing remaining units in default formation instead of instant loss on timeout. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-MP-3 as DONE.
43. **Batch deploy+embark/attach into composite action** — Fix race condition where embark/attach actions arrive after player switch in multiplayer by bundling deploy + embark/attach into a single atomic action in `DeploymentController._complete_deployment()`. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-MP-4 as DONE.
44. **Add player turn screen-edge color indicator** — Add prominent colored border around screen edge matching active player color (blue for P1, red for P2), flash briefly on turn swap. Works across all phases. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-2 as DONE.
45. **Consolidate duplicate geometry functions** — Move shared `_circle_wholly_in_polygon()`, `_point_to_line_distance()`, `_shape_wholly_in_polygon()` from `DeploymentPhase.gd` and `DeploymentController.gd` into `Measurement.gd` as single source of truth. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-CODE-1 as DONE.
46. **Fix snapshot staleness in _all_units_deployed()** — Refresh phase snapshot in `DeploymentPhase._process_deploy_unit()` after applying changes so `_all_units_deployed()` can use snapshot instead of direct `GameState.state` access. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-CODE-2 as DONE.

### P3 — Low (Deployment visual polish)
47. **Add unit placement drop-in animation** — Brief scale 0→1 or fade-in over 0.2s when model is placed in `DeploymentController._spawn_preview_token()` for tactile feedback. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-1 as DONE.
48. **Add deployment zone theming** — Add subtle textures or patterns within deployment zones (diagonal hatching, military-style markers) in `DeploymentZoneVisual.gd` to distinguish from regular board. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-3 as DONE.
49. **Enhance ghost visual with coherency aids** — Add pulsing effect to ghost in `GhostVisual.gd`, connecting line from ghost to nearest placed model, distance display to nearest friendly model in inches. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-4 as DONE.
50. **Add coherency visualization circles during deployment** — Draw faint 2" radius circles around placed models in `DeploymentController.gd`, green when next model in coherency range, red when out of range. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-5 as DONE.
51. **Add unit name labels on deployed tokens** — Show unit name on hover over deployed token in `TokenVisual.gd`, or as tiny label beneath each token cluster to distinguish same-type units. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-6 as DONE.
52. **Add opponent deployment zone dimming** — Dim/desaturate opponent's deployment zone when it's your turn in `Main.gd`, brighten your own zone. Reverse on opponent's turn. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-VIS-7 as DONE.
53. **Implement TITANIC unit deployment skip** — When a player deploys a TITANIC unit, they skip their next deployment turn per 10e rules. Detect TITANIC keyword in `TurnManager.check_deployment_alternation()` and skip the deploying player's next turn to set up a unit. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-RULES-3 as DONE.
54. **Add keyboard shortcut reference overlay during deployment** — Show toggleable controls panel (press ? to show/hide) listing Q/E rotation, Shift+click reposition, mouse wheel rotation, formation modes. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-QOL-5 as DONE.
55. **Add measuring tool button visible during deployment** — Ensure measuring tape is accessible during deployment with a visible button in the deployment UI panel and tooltip showing the keybind. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-QOL-3 as DONE.
56. **Add web relay "Waiting for game state" loading screen** — Add loading screen on guest side in web relay mode that dismisses once host state is received, preventing flash of default army configuration. Update DEPLOYMENT_AUDIT.md to mark DEPLOY-MP-2 as DONE.

### P0 — Critical (game-breaking rules violations — holistic audit)
57. **Implement CHARACTER targeting "closest eligible visible unit" restriction** — Characters with W<=9 near friendly non-Character units (3+ models or VEHICLE/MONSTER) cannot be targeted by ranged attacks unless they are the closest eligible visible target. Add closest-eligible check to `_validate_assign_target()` in ShootingPhase.gd and `get_eligible_targets()` in RulesEngine.gd. Must compute distance from attacking model to all eligible targets. Reference 10e Core Rules character targeting section on wahapedia. (SHOOT-1)
58. **Implement defender-controlled wound allocation** — Per 10e rules the DEFENDING player chooses which model receives each wound (with restriction that models already wounded or allocated to this phase must be allocated first). Currently auto-allocated without defender input. Add wound allocation prompt for defending player in ShootingPhase.gd and FightPhase.gd with auto-allocation fallback for AI. In multiplayer the defender must be given the choice. Reference Core Rules "Allocate Attack" step. (SHOOT-9)

### P1 — High (incorrect rules that significantly affect gameplay)
59. **Implement Out-of-Phase rules restriction** — When using out-of-phase rules (e.g. Fire Overwatch during opponent's movement), you cannot use any other rules normally triggered in that phase. Add `out_of_phase` flag to track reactive actions and gate phase-specific abilities/stratagems accordingly. Prevents e.g. Pinning Bombardment during Overwatch. Files: StratagemManager.gd, MovementPhase.gd, ChargePhase.gd. (GEN-1)
60. **Implement transport destruction effects** — When a transport with embarked units is destroyed: roll D6 per embarked model (1 = 1 MW set up within 3", 1-3 = 1 MW set up within 6", 4+ = safe). Models that can't be placed are destroyed. Surviving models count as having disembarked. Add `resolve_transport_destruction()` to RulesEngine.gd triggered when a transport unit is destroyed in damage application. Files: RulesEngine.gd, TransportManager.gd. (GEN-8)
61. **Implement pivot values for non-round base models** — Core Rules Updates: non-round base non-Monster/Vehicle = 1" subtracted from movement on first pivot, Monster/Vehicle non-round base = 2", Vehicle round base >32mm with flying stem = 2". Add pivot tracking and movement deduction to MovementPhase.gd. (MOV-1)
62. **Implement vertical coherency limit (5")** — `_check_models_coherency()` only checks 2" horizontal distance. Rules require models within 2" horizontal AND 5" vertical of coherency partners. Add vertical distance check to coherency validation in MovementPhase.gd. Also update Measurement.gd if needed. (MOV-2)
63. **Add 5" vertical component to Engagement Range checks** — `Measurement.is_in_engagement_range_shape_aware()` is purely 2D (1" horizontal only). Rules define ER as 1" horizontal AND 5" vertical. Add height/elevation check to engagement range calculation in Measurement.gd. This affects movement restrictions, shooting eligibility, fight eligibility, and charge validation. (MOV-8)
64. **Fix attached unit starting strength for battle-shock** — `is_below_half_strength()` in GameState.gd does not combine bodyguard + attached character models for starting strength. A Warboss (1 model) attached to 10 Boyz should have starting strength 11. Update to use `get_combined_models()` count when checking attached units in CommandPhase.gd. (CMD-6)
65. **Implement Ruins visibility rules** — Core Rules Updates: "Models cannot see over or through Ruins terrain." Aircraft and Towering models are exceptions. Models can see into Ruins normally. Models wholly within Ruins can see out normally. Add ruins-specific LoS blocking to LineOfSightManager.gd and/or EnhancedLineOfSight.gd. (TER-2)
66. **Fix leader attachment not working visually for human player** — User reports selecting leaders in Formations phase but they deploy separately. AI attachment works correctly. Investigate FormationsPhase → DeploymentPhase integration for human players. Ensure attachment state persists through phase transition and deployment skips attached characters correctly. Files: FormationsPhase.gd, DeploymentPhase.gd, GameState.gd. (BUG-1)
67. **Fix wound allocation overlay showing models in wrong positions** — "The Kommandos are not in the place where they are expected to be when I allocate wounds." Investigate WoundAllocationOverlay model position rendering — model tokens may not match actual board positions. Files: WoundAllocationOverlay.gd, ShootingController.gd. (BUG-2)
68. **Investigate and fix Line of Sight issues** — User reports LoS not working as expected. May relate to TER-2 (ruins visibility) or bugs in EnhancedLineOfSight.gd. Test LoS across various terrain configurations and fix discrepancies. Files: LineOfSightManager.gd, EnhancedLineOfSight.gd. (BUG-3)

### P2 — Medium (rules gaps that occasionally affect gameplay)
69. **Implement CP cap** — Core rules FAQ: players can gain at most 1 additional CP per battle round from non-automatic sources (beyond the 1 CP auto-generated each Command Phase). Add tracking of CP gained per round and cap enforcement in CommandPhase.gd and StratagemManager.gd. (CMD-1)
70. **Add FEARLESS and ATSKNF keyword immunity to battle-shock** — Units with FEARLESS or And They Shall Know No Fear keywords should auto-pass battle-shock tests. Add keyword check in `_identify_units_needing_tests()` in CommandPhase.gd to skip these units. (CMD-2)
71. **Implement surge move rules and restrictions** — Core Rules Updates defines "surge" moves (out-of-phase moves triggered by abilities). Restrictions: once per phase, not while battle-shocked, not while in Engagement Range. Add surge move validation to MovementPhase.gd. (MOV-3)
72. **Enforce one Normal move per phase limit** — "A unit cannot make more than one Normal move per phase." Add per-phase normal move tracking in MovementPhase.gd to prevent duplicate moves. (MOV-4)
73. **Validate Monster/Vehicle cannot move through friendly Monster/Vehicle** — Errata restriction: Monsters and Vehicles cannot move through other friendly Monsters/Vehicles. Add keyword-based movement blocking check in MovementPhase.gd path validation. (MOV-5)
74. **Update Hazardous to Balance Dataslate v3.3 allocation priority** — Allocation priority changed to: (1) wounded model with Hazardous weapon, (2) non-Character with Hazardous, (3) Character with Hazardous. Unit suffers 3 mortal wounds allocated to selected model. Verify and update `resolve_hazardous_check()` in RulesEngine.gd. (SHOOT-2)
75. **Enforce Extra Attacks number cannot be modified** — Balance Dataslate: "number of attacks made with an Extra Attacks weapon cannot be modified by other rules, unless that weapon's name is explicitly specified in that rule." Add validation in RulesEngine.gd attack count calculation. (SHOOT-4)
76. **Verify Tank Shock matches Balance Dataslate v3.3** — v3.3 wording: Roll D6 equal to TOUGHNESS of selected Vehicle model, 5+ = mortal wound (max 6 MW). Check current StratagemManager.gd Tank Shock implementation against updated wording and fix if needed. (CHG-1)
77. **Add terrain penalties to Heroic Intervention charge roll** — `_is_heroic_intervention_roll_sufficient()` in ChargePhase.gd does not apply terrain vertical distance penalties unlike normal charge sufficiency check. Add matching terrain penalty calculation. (CHG-2)
78. **Verify consolidation is mandatory at unit level per FAQ** — FAQ states: "Consolidation for a unit is not optional. However, for each model, whether or not that model makes a Consolidation move is optional." Ensure FightPhase.gd forces the consolidation step even if individual models don't move. (FGT-1)
79. **Implement Obscuring terrain keyword** — No special rules for terrain features with the Obscuring keyword. Add terrain trait and corresponding LoS interaction in TerrainManager.gd and LineOfSightManager.gd. (TER-4)
80. **Implement Deep Strike can choose Strategic Reserves placement** — Balance Dataslate: "If a unit with Deep Strike arrives from Strategic Reserves, the player can choose to set up using Strategic Reserves OR Deep Strike rules." Add option in reinforcement placement UI in MovementPhase.gd. (DEP-3)
81. **Update Scouts rules per Balance Dataslate** — Dedicated Transports can use Scouts ability inherited from embarked unit. Scout distance can exceed Move characteristic as long as ≤ X". Update ScoutPhase.gd validation. (DEP-4)
82. **Complete Scorched Earth mission** — Burn mechanics are stub only. Implement the burning action and scoring in MissionManager.gd. (MIS-1)
83. **Complete The Ritual mission** — Action-based objective mechanics not implemented. Add action system for ritual objectives in MissionManager.gd. (MIS-2)
84. **Complete Terraform mission** — Objective flipping between players not implemented. Add flip mechanics in MissionManager.gd. (MIS-3)
85. **Add Fixed secondary mission mode** — Only tactical deck mode available. Add option for players to select 3 fixed secondary missions before game in SecondaryMissionManager.gd and MainMenu.gd. (MIS-4)
86. **Apply Balance Dataslate v3.3 stratagem modifications** — Multiple stratagem changes from v3.3: closer setup range, AP worsening timing, CP cost modifications, targeting prevention range changes, unit addition once per battle restriction. Update StratagemManager.gd definitions. (GEN-4)
87. **Update Rapid Ingress per Balance Dataslate** — Updated wording: "if every model has Deep Strike ability, you can set up using Deep Strike (even though not your Movement phase)." Verify and update implementation in StratagemManager.gd. (GEN-5)
88. **Update Fire Overwatch timing per Balance Dataslate** — Trigger expanded to: "just after an enemy unit is set up or when an enemy unit starts or ends a Normal, Advance or Fall Back move, or declares a charge." Verify timing matches in MovementPhase.gd and ChargePhase.gd. (GEN-6)
89. **Implement aura abilities system** — No range-based aura effect application exists. `passive_aura` condition type defined in UnitAbilityManager.gd but not functionally applied to other units within range. Build aura detection and effect propagation system. Files: UnitAbilityManager.gd, EffectPrimitives.gd. (GEN-7)
90. **Fix attached unit Toughness resolution** — Wound rolls against attached units should use bodyguard unit's Toughness, not the leader's. RulesEngine.gd reads T from the target unit directly with no special handling for attached characters. Add attached unit T lookup in wound roll calculation. (GEN-13)
91. **Fix weapon-by-weapon attack allocation for multi-weapon units** — User reports inability to allocate each weapon's attacks separately against different targets. Verify multi-weapon target assignment works correctly in ShootingPhase.gd and ShootingController.gd. (BUG-4)
92. **Fix save/load games with AI players** — SaveLoadManager.gd has no AI player detection or state serialization. AI difficulty setting and player type not preserved across save/load. Add AI state to serialized game state. Files: SaveLoadManager.gd, StateSerializer.gd, AIPlayer.gd. (BUG-5)

### P3 — Low (edge cases, polish, minor gaps)
93. **Prevent battle-shocked units from using self-targeted stratagems** — StratagemManager.gd only prevents targeting battle-shocked units with friendly stratagems, not all stratagem usage by battle-shocked units themselves. Add self-target check. (CMD-3)
94. **Add confirmation before auto-resolving untaken battle-shock tests** — Currently auto-resolves silently. Show warning dialog before auto-resolving in CommandPhase.gd. (CMD-4)
95. **Fix embark/disembark distance calculation inconsistency** — Embark uses `model_to_model_distance_inches()` but disembark uses shape-aware distance. Standardize both to use shape-aware in TransportManager.gd. (MOV-6)
96. **Enforce cannot select to shoot with no eligible targets** — "Unless at least one model in a unit has an eligible target, that unit cannot be selected to shoot." Add pre-selection check in ShootingPhase.gd. (SHOOT-7)
97. **Track invulnerable save source in UI** — When invuln save is used, show indicator of native vs effect-granted source in WoundAllocationOverlay.gd. (SHOOT-8)
98. **Display terrain penalty in charge distance UI** — Players see rolled distance but not effective distance after terrain penalties. Show "Effective: X\" (Y\" - Z\" terrain)" in ChargeController.gd. (CHG-3)
99. **Add live direction validation feedback during charge movement** — No real-time feedback as player drags model to show if final position satisfies charge direction constraint. Add visual indicator in ChargeController.gd. (CHG-4)
100. **Verify Epic Challenge stratagem in attached units** — Ensure 1CP Epic Challenge properly enables CHARACTER vs CHARACTER melee dueling within attached units in FightPhase.gd. (FGT-2)
101. **Sync pile-in/consolidation drag for remote player** — Remote player sees models teleport to final positions instead of animated movement. Add drag sync in FightController.gd. Cosmetic only. (FGT-3)
102. **Complete when-drawn secondary mission interactions UI** — Marked for Death and Tempting Target opponent selection UI not fully wired in SecondaryMissionManager.gd. (MIS-5)
103. **Verify objective control timing** — "A player will control an objective marker at the end of any phase or turn." Ensure timing matches rules in ScoringPhase.gd. (MIS-6)
104. **Validate Warlord designation** — `is_warlord` field exists but no enforcement of exactly one CHARACTER designated. Add validation in FormationsPhase.gd. (GEN-9)
105. **Add army construction points validation** — Points tracked but no validation during list building. No detachment enforcement. Add validation in army loading. (GEN-10)
106. **Verify persisting effects match Core Rules Updates** — Core Rules Updates defines persisting effects with specific duration tracking. Verify effect expiration logic in EffectPrimitives.gd. (GEN-11)
107. **Implement redeployment rules** — Core Rules Updates: redeployment rules resolved after Deploy Armies, before Determine First Turn. Add phase handling. (GEN-12)
108. **Make deployment zone toggle more prominent** — User requested toggle. Ensure button is easy to find in deployment UI. (BUG-6)
109. **Add turn/round progress indicator to HUD** — Show "Round 3/5 - Player 1 Turn" persistently in Main.gd HUD. (QOL-1)
110. **Add phase rules brief during transitions** — Brief popup explaining available actions in each phase during PhaseTransitionBanner. (QOL-2)
111. **Add settings menu** — Audio controls, visual settings, UI scale, animation speed, colorblind mode. New SettingsMenu.gd scene. (QOL-4)
112. **Add auto-save at round end** — Automatic saves at round end and phase transitions via SaveLoadManager.gd. (QOL-5)
113. **Add quick-assign All weapons to target in shooting** — One-click button to assign all weapons to selected target in ShootingController.gd. (QOL-6)
114. **Add expected damage preview during weapon assignment** — Mathhammer-style prediction as weapon assignments are made in ShootingController.gd. (QOL-7)
115. **Add available movement indicator** — Show "X inches remaining" floating text during model movement in MovementController.gd. (QOL-9)
116. **Add coherency preview during movement** — Visual line showing unit coherency status as models move in MovementController.gd. (QOL-10)
117. **Add dice roll history panel** — Scrollable history of past dice rolls for review. New DiceHistoryPanel.gd. (QOL-12)
118. **Add reroll visualization** — Show original + new die side-by-side when Command Re-roll used in DiceRollVisual.gd. (QOL-14)
119. **Add live opponent action feed in multiplayer** — Show "Player 2 moved Ork Boyz forward" feed in real-time. (QOL-15)
120. **Add scoring counter HUD** — Display current VP by player persistently in Main.gd. (QOL-22)
121. **Add secondary objective progress tracking** — Show progress toward active secondary missions in ScoringController.gd. (QOL-23)
122. **Add dice roll sound effects** — Rolling, settling, critical success/failure audio cues in DiceRollVisual.gd. (VIS-1)
123. **Add distinct terrain type visuals** — Different visual styles for ruins, forests, hills, obstacles in BoardVisual.gd. (VIS-3)
124. **Add persistent model health bars on board** — Show model wounds above/below bases via TokenVisual.gd. (VIS-7)
125. **Add human player movement path preview** — Drag-to-plan movement path visualization matching AI's AIMovementPathVisual.gd. (VIS-9)
126. **Add phase transition sound effects** — Audio cues for phase changes in PhaseTransitionBanner.gd. (VIS-13)
127. **Add charge trajectory preview** — Show expected charge path when declaring charges in ChargeController.gd. (VIS-14)
128. **Add VP scoring timeline chart** — VP progression chart over game rounds in GameOverDialog or ScoringController. (VIS-17)
