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
| Faction abilities with broken/missing implementation | 2 |
| Datasheet abilities missing from ABILITY_EFFECTS table entirely | 16 |
| Datasheet abilities in ABILITY_EFFECTS but marked not implemented | 4 |
| Wargear abilities not implemented | 7 |
| Core abilities not implemented or partially implemented | 4 |
| Detachment rules not implemented | 3 |
| Oath of Moment rules text is outdated | 0 |
| **Total gaps** | **36** |

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

### 2. Sentinel Storm (Custodian Guard, Custodes)
- **Rules text:** "Once per battle, in your Shooting phase, after this unit has shot, it can shoot again."
- **Current state:** Not implemented at all — not in ABILITY_EFFECTS table, no shoot-again mechanic exists
- **What's needed:** Full implementation including once-per-battle tracking and a shoot-again trigger in ShootingPhase

---

## Faction Abilities

### Orks — Waaagh!
- **Rules text:** "Once per battle, at the start of your Command phase, you can call a Waaagh!. If you do, until the start of your next Command phase: (1) Units with this ability are eligible to charge in a turn they Advanced. (2) Add 1 to Strength and Attacks of melee weapons. (3) Models have a 5+ invulnerable save."
- **Current state:** Not implemented. No Waaagh! state tracking exists in the codebase
- **Impact:** Blocks implementation of Da Biggest and da Best, Dead Brutal, and the baseline Ork faction mechanic
- **What's needed:** Waaagh! state manager, Command Phase UI trigger, automatic effect application for all Ork units

### Adeptus Custodes — Martial Ka'tah
- **Rules text:** "Each time a unit with this ability is selected to fight, select one Ka'tah Stance: Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits). That stance is active until the unit finishes attacking."
- **Current state:** Listed in army JSON descriptions but not in ABILITY_EFFECTS table, no stance selection UI, no implementation
- **What's needed:** Fight phase stance selection UI, temporary weapon keyword application during fight resolution

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
| Waaagh! | Faction | No | No | No | Entire Waaagh! system missing |
| Might is Right | Datasheet | Yes | Yes (implemented) | Yes | +1 melee hit rolls working via RulesEngine |
| Da Biggest and da Best | Datasheet | Yes | Yes (not implemented) | No | Needs Waaagh! state + stat modification (+4 attacks) |

### Warboss in Mega Armour

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Leader | Core | No | No | Partial | Attachment system works |
| Waaagh! | Faction | No | No | No | Entire Waaagh! system missing |
| Might is Right | Datasheet | Yes | Yes (implemented) | Yes | Working |
| Dead Brutal | Datasheet | Yes | Yes (not implemented) | No | Needs Waaagh! state + weapon damage modification (damage=3) |

### Boyz

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Waaagh! | Faction | No | No | No | Missing |
| Get Da Good Bitz | Datasheet | Yes | Yes (not implemented) | No | Sticky objectives — needs objective system integration |
| Bodyguard (20-model) | Special | Yes | No | Unknown | Double leader attachment for 20-model units |

### Kommandos

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Infiltrators | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Stealth | Core | **MISSING** | No | **No** | Wahapedia lists Stealth (-1 to hit ranged attacks). Not in army JSON at all |
| Waaagh! | Faction | No | No | No | Missing |
| Throat Slittas | Datasheet | Yes | No | No | Mortal wounds in shooting phase — entirely unimplemented |
| Sneaky Surprise | Datasheet | **MISSING** | No | **No** | "Cannot be targeted by Fire Overwatch" — not in JSON or code |
| Patrol Squad | Datasheet | **MISSING** | No | **No** | Unit splitting at deployment — not in JSON or code |
| Distraction Grot | Wargear | **MISSING** | No | **No** | Once per battle 5+ invuln — not in JSON or code |
| Bomb Squigs | Wargear | **MISSING** | No | **No** | Once per battle mortal wounds — not in JSON or code |

### Battlewagon

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D6 | Core | **MISSING** | No | **No** | Mortal wounds on destruction — not in JSON or code |
| Firing Deck 11 | Core | **MISSING** | No | **No** | Embarked models can shoot — not in JSON or code |
| Waaagh! | Faction | No | No | No | Missing |
| Ramshackle | Datasheet | Yes | Yes (implemented) | **Yes** | Correctly worsens AP of incoming attacks by 1 |
| Damaged: 1-5 Wounds | Datasheet | **MISSING** | No | **No** | -1 to hit when 1-5 wounds remaining — not in JSON or code |
| 'Ard Case | Wargear | **MISSING** | No | **No** | +2 Toughness, lose Firing Deck — not in JSON or code |
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
| Martial Ka'tah | Faction | Yes (text only) | No | **No** | Stance selection not implemented |
| Swift Onslaught | Datasheet | Yes | Yes (not implemented) | **No** | Reroll charge — `reroll_charge` primitive doesn't exist |
| Martial Inspiration | Datasheet | Yes | Yes (implemented) | **Yes** | Once-per-battle tracking implemented; ChargePhase checks advance_and_charge flag |

### Custodian Guard

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deep Strike | Core | Yes | No (separate system) | Likely | Handled by deployment logic |
| Martial Ka'tah | Faction | Yes (text only) | No | **No** | Stance selection not implemented |
| Stand Vigil | Datasheet | Yes | Yes (implemented) | **Partial** | Reroll wound 1s works. "While within range of controlled objective, reroll all wound rolls" — objective-conditional part NOT implemented |
| Sentinel Storm | Datasheet | Yes (text only) | No | **No** | Once per battle shoot again — entirely unimplemented |
| Praesidium Shield | Wargear | Yes (text only) | No | **No** | +1 Wounds — not applied to model stats |
| Vexilla | Wargear | Yes (text only) | No | **No** | +1 OC — not applied to model stats |

### Witchseekers

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Scout 6" | Core | Yes | No (separate system) | Unknown | Should move 6" before first turn |
| Daughters of the Abyss | Datasheet | Yes | Yes (implemented) | **Partial** | Simplified as FNP 3+ always. Should be FNP 3+ against Psychic Attacks and mortal wounds only |
| Sanctified Flames | Datasheet | Yes (text only) | No | **No** | Force Battle-shock test on hit enemy — not implemented |

### Caladius Grav-tank

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | **MISSING** | No | **No** | Mortal wounds on destruction — not in JSON or code |
| Martial Ka'tah | Faction | Yes (text only) | No | **No** | Not implemented |
| Advanced Firepower | Datasheet | Yes (text only) | No | **No** | Conditional Lethal Hits by target type (MONSTER/VEHICLE vs other) — not implemented |
| Damaged: 1-5 Wounds | Datasheet | **MISSING** | No | **No** | -1 to hit when 1-5 wounds remaining |
| Invulnerable Save 5+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Contemptor-Achillus Dreadnought

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise 1 | Core | **MISSING** | No | **No** | Mortal wounds on destruction |
| Martial Ka'tah | Faction | Yes (text only) | No | **No** | Not implemented |
| Dread Foe | Datasheet | Yes (text only) | No | **No** | Mortal wounds on fight selection (D3 or 3, bonus on charge) — not implemented |
| Invulnerable Save 5+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Telemon Heavy Dreadnought

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deadly Demise D3 | Core | **MISSING** | No | **No** | Mortal wounds on destruction |
| Martial Ka'tah | Faction | Yes (text only) | No | **No** | Not implemented |
| Guardian Eternal | Datasheet | **MISSING** | No | **No** | -1 Damage to incoming attacks — wahapedia lists this, not in JSON. Note: JSON has "Eternal Protector" (reflect mortal wounds on save of 6) which appears to be incorrect/outdated |
| Devoted to Destruction | Datasheet | **MISSING** | No | **No** | +2 Attacks with dual Telemon caestus — not in JSON |
| Damaged: 1-4 Wounds | Datasheet | **MISSING** | No | **No** | -1 to hit when 1-4 wounds remaining |
| Invulnerable Save 4+ | Innate | Unknown | N/A | Unknown | Should be part of unit stats |

### Shield-Captain (NOT IN ANY ARMY FILE)

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Deep Strike | Core | N/A | No | N/A | Unit not in game |
| Leader | Core | N/A | No | N/A | Unit not in game |
| Martial Ka'tah | Faction | N/A | No | N/A | Unit not in game |
| Master of the Stances | Datasheet | N/A | No | N/A | Once per battle: both Ka'tah stances active simultaneously |
| Strategic Mastery | Datasheet | N/A | No | N/A | Once per battle round: reduce stratagem CP cost by 1 |
| Praesidium Shield | Wargear | N/A | No | N/A | +1 Wounds |

---

## Space Marines — Unit Ability Gaps

### Intercessor Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Objective Secured | Datasheet | **MISSING** | No | **No** | Sticky objectives — not in JSON or code |
| Target Elimination | Datasheet | **MISSING** | No | **No** | +2 bolt rifle attacks when targeting single enemy — not in JSON or code |

### Tactical Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Combat Squads | Datasheet | **MISSING** | No | **No** | Split into two 5-model units at deployment — not in JSON or code |

### Infiltrator Squad

| Ability | Type | In JSON | In ABILITY_EFFECTS | Working | Notes |
|---------|------|---------|-------------------|---------|-------|
| Infiltrators | Core | Yes | No (separate system) | Likely | Deployment logic |
| Scout 6" | Core | Yes | No (separate system) | Unknown | Pre-game movement |
| Oath of Moment | Faction | Yes | Yes (FactionAbilityManager) | **Yes** | Rules text and mechanics updated to Codex wording |
| Omni-scramblers | Datasheet | Yes (text only) | No | **No** | Blocks enemy deep strike within 12" — not implemented mechanically |
| Helix Gauntlet | Wargear | **MISSING** | No | **No** | FNP 6+ for unit — optional wargear, not in JSON |
| Infiltrator Comms Array | Wargear | **MISSING** | No | **No** | 5+ to regain 1CP on stratagem — optional wargear, not in JSON |

---

## Core Abilities Audit

| Core Ability | Units With It | Implemented | Notes |
|---|---|---|---|
| Deep Strike | Blade Champion, Custodian Guard, Shield-Captain | Likely | Handled by deployment system, not ability pipeline |
| Infiltrators | Kommandos, Infiltrator Squad | Likely | Handled by deployment system |
| Scout 6" | Witchseekers, Infiltrator Squad | Unknown | Pre-game movement — needs verification |
| Stealth | Kommandos (per wahapedia) | **No** | Missing from army JSON entirely. Should grant -1 to hit on ranged attacks |
| Leader | Various characters | Partial | Attachment system works but Leader ability not explicitly tracked |
| Feel No Pain 5+ | Painboss | Unknown | Painboss not in army JSON files |
| Deadly Demise (D3/D6/1) | Battlewagon, Caladius, Telemon, Contemptor-Achillus, Weirdboy | **No** | No destruction-triggered mortal wound mechanic exists |
| Firing Deck 11 | Battlewagon | **No** | No embarked shooting mechanic exists |

---

## Detachment Rules

These are army-wide bonuses from chosen detachments. None are currently implemented.

### Space Marines — Gladius Task Force: Combat Doctrines
- **Devastator Doctrine:** Unit eligible to shoot after Advancing (all weapons, not just Assault)
- **Tactical Doctrine:** Unit eligible to shoot and charge after Falling Back
- **Assault Doctrine:** Unit eligible to charge after Advancing
- **Status:** Not implemented. Would interact with the advance_and_shoot/charge and fall_back_and_shoot/charge flags

### Orks — War Horde: Get Stuck In
- **Effect:** All Orks melee weapons gain Sustained Hits 1
- **Status:** Not implemented

### Adeptus Custodes — Shield Host: Martial Mastery
- **Effect:** At start of each battle round, choose: (1) unmodified 5+ hit rolls are Critical Hits in melee, or (2) improve melee AP by 1
- **Status:** Not implemented

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
| 11 | Swift Onslaught | while_leading | reroll_charge | No | **No** — primitive doesn't exist |
| 12 | Martial Inspiration | while_leading | advance_and_charge | Yes | **Yes** — ChargePhase now checks effect_advance_and_charge + once-per-battle tracking added |
| 13 | Stand Vigil | always | reroll wounds (1s) | Yes | **Partial** — basic reroll works, objective-conditional upgrade missing |
| 14 | Ramshackle | always | worsen AP by 1 | Yes | **Yes** — correctly worsens AP of incoming attacks by 1 |
| 15 | Daughters of the Abyss | always | FNP 3+ | Yes | **Partial** — simplified. Should only apply vs Psychic/mortal wounds |
| 16 | Get Da Good Bitz | on_objective | sticky objectives | No | **No** |
| 17 | Da Biggest and da Best | waaagh_active | +4 attacks | No | **No** — needs Waaagh! system |
| 18 | Dead Brutal | waaagh_active | damage=3 | No | **No** — needs Waaagh! system |

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
8. **Implement Martial Ka'tah** — affects all Custodes units (stance selection in fight phase)
9. **Implement Swift Onslaught** — reroll charge primitive needed
10. **Implement Sentinel Storm** — shoot-again mechanic for Custodian Guard
11. **Implement Sanctified Flames** — Battle-shock test after shooting (Witchseekers)
12. **Implement Throat Slittas** — mortal wounds mechanic (Kommandos)
13. **Implement Deadly Demise** — destruction-triggered mortal wounds (multiple vehicle units)
14. **Implement Damaged profiles** — -1 to hit at low wounds (Caladius, Telemon, Battlewagon)
15. **Add Stealth to Kommandos army JSON** — missing core ability
16. **Implement Advanced Firepower** — conditional Lethal Hits (Caladius)
17. **Implement Dread Foe** — mortal wounds on fight selection (Contemptor-Achillus)
18. **Implement Guardian Eternal** — -1 Damage (Telemon) — also fix JSON which has wrong ability name

### P2 — Medium (require new systems or are less impactful)
19. **Implement Waaagh! system** — unlocks Da Biggest/Dead Brutal + base Ork faction ability
20. **Implement wargear stat bonuses** — Praesidium Shield (+1W), Vexilla (+1OC), 'Ard Case (+2T)
21. **Fix Daughters of the Abyss** — restrict FNP 3+ to psychic/mortal wounds only
22. **Fix Stand Vigil** — add objective-conditional reroll-all upgrade
23. **Implement Get Da Good Bitz** — sticky objectives (Boyz)
24. **Implement Omni-scramblers mechanically** — block deep strike within 12"
25. **Add missing Kommandos abilities to JSON** — Sneaky Surprise, Patrol Squad, Distraction Grot, Bomb Squigs
26. **Add missing Space Marine abilities to JSON** — Objective Secured, Target Elimination, Combat Squads
27. **Implement Detachment rules** — Combat Doctrines, Get Stuck In, Martial Mastery

### P3 — Low (units not yet in army files or niche mechanics)
28. **Add Shield-Captain unit** — Master of the Stances, Strategic Mastery
29. **Add Painboss to army JSON** — Sawbonez (heal), Grot Orderly (revive)
30. **Add Weirdboy to army JSON** — Waaagh! Energy, Da Jump
31. **Implement Firing Deck** — embarked model shooting (Battlewagon)
32. **Implement Transport capacity** — embark/disembark mechanics
33. **Add optional wargear** — Helix Gauntlet (FNP 6+), Infiltrator Comms Array (CP regen)
34. **Implement Devoted to Destruction** — +2 Attacks with dual Telemon caestus
35. **Implement Bodyguard (20-model)** — double Leader attachment for large Boyz units
