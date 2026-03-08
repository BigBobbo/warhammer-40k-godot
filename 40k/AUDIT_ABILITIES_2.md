# AUDIT_ABILITIES_2.md — Unit Ability Implementation Audit

**Date:** 2026-03-08
**Source of truth:** Wahapedia CSV data (Datasheets_abilities.csv, Datasheets_models.csv)
**Scope:** All 9 units from the CSV-verified ability audit, cross-referenced against codebase implementation.

---

## Severity Legend

- **CRITICAL** — Ability is missing or broken; affects gameplay correctness
- **HIGH** — Ability exists but has significant logic gaps
- **MEDIUM** — Partial implementation; works in some paths but not all
- **LOW** — Minor data issue or UI polish needed
- **OK** — Fully implemented and correct

---

## 1. BLADE CHAMPION (Adeptus Custodes)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Missing `invuln: 4` in stats | **CRITICAL** | `adeptus_custodes.json` and `A_C_test.json` — Blade Champion's `meta.stats` has no `invuln` field. CSV confirms 4+ invuln. Shield-Captain has it correctly. The Blade Champion will take unsaved wounds that should be saved by a 4+ invuln. |
| Bogus `"Core"` ability entry | **LOW** | Both army files have `{"name": "Core", "type": "Core", "description": ""}` — this is a meaningless placeholder entry. The ability parser skips it (`ability_name == "Core"` guard in UnitAbilityManager), but it shouldn't be in the data. |
| Missing `Leader` core ability | **LOW** | CSV lists "Leader" as a core ability. Army JSON has `leader_data.can_lead` which is what the CharacterAttachmentManager actually uses, so functionally the attachment works. However, the "Leader" keyword should be in the abilities array for completeness and for any ability-inspection code that checks for it. |

### Ability Implementation

| Ability | Type | Status | Notes |
|---------|------|--------|-------|
| Deep Strike | Core | **OK** | Listed in army JSON. Handled by DeploymentPhase/MovementPhase with DeepStrikePlacementDialog. |
| Leader | Core | **OK** (functional) | Attachment works via `leader_data.can_lead`. Missing from abilities array but functionally complete. |
| Martial Ka'tah | Faction | **OK** | FactionAbilityManager handles stance selection. KatahStanceDialog provides UI. Both Dacatarai (Sustained Hits 1) and Rendax (Lethal Hits) work. |
| Swift Onslaught | Datasheet | **OK** | UnitAbilityManager ABILITY_EFFECTS maps it to `reroll_charge`. ChargePhase offers free reroll before Command Re-roll. Signals + UI flow complete. |
| Martial Inspiration | Datasheet | **OK** | UnitAbilityManager maps it to `advance_and_charge` with `once_per_battle: true`. ChargePhase checks `EffectPrimitivesData.has_effect_advance_and_charge()` and marks it used. |

---

## 2. SHIELD-CAPTAIN ON DAWNEAGLE JETBIKE (Adeptus Custodes)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | Neither `adeptus_custodes.json` nor `A_C_test.json` contain a Shield-Captain on Dawneagle Jetbike. Only a regular Shield-Captain (Infantry) exists. The Dawneagle variant has different stats (M14", T6, W7), keywords (MOUNTED, FLY), and a different weapon loadout. This unit cannot be played. |
| Sweeping Advance not implemented | **CRITICAL** | The datasheet ability "Sweeping Advance" (once per battle, at end of Fight phase, Fall Back or Normal Move) has no entry in UnitAbilityManager.ABILITY_EFFECTS, no dialog, and no FightPhase integration. |
| Strategic Mastery | — | See Shield-Captain below — the regular Shield-Captain has it implemented. |

### Notes on Regular Shield-Captain (present in army files)

| Ability | Type | Status | Notes |
|---------|------|--------|-------|
| Deep Strike | Core | **OK** | In army JSON. |
| Martial Ka'tah | Faction | **OK** | In army JSON. KatahStanceDialog works. |
| Master of the Stances | Datasheet | **OK** | UnitAbilityManager has it as `once_per_battle`. KatahStanceDialog shows "Both Stances" button when available. FactionAbilityManager.apply_katah_stance("both") sets both flags. |
| Strategic Mastery | Datasheet | **OK** | UnitAbilityManager tracks `once_per_battle_round`. StratagemManager checks `has_strategic_mastery()` and applies CP discount. |
| Praesidium Shield | Wargear | **OK** | ArmyListManager.WARGEAR_STAT_BONUSES applies +1W at load time. |

---

## 3. CUSTODIAN GUARD (Adeptus Custodes)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Missing `invuln: 4` in stats | **CRITICAL** | `adeptus_custodes.json` — Custodian Guard's `meta.stats` has no `invuln` field. CSV confirms 4+ invuln. All Custodian Guard models should have a 4+ invulnerable save. |

### Ability Implementation

| Ability | Type | Status | Notes |
|---------|------|--------|-------|
| Deep Strike | Core | **OK** | In army JSON. |
| Martial Ka'tah | Faction | **OK** | In army JSON. |
| Praesidium Shield | Wargear | **OK** | ArmyListManager handles +1W at load time. |
| Vexilla | Wargear | **OK** | ArmyListManager handles +1 OC at load time. |
| Stand Vigil | Datasheet | **HIGH** | Only the base effect is implemented: re-roll Wound rolls of 1 (`"effects": [{"type": "reroll_wounds", "scope": "ones"}]`). The **enhanced effect** — full re-roll of Wound rolls when within range of a controlled objective — is **NOT implemented**. The condition is hardcoded to `"always"` instead of checking objective proximity. |
| Sentinel Storm | Datasheet | **OK** | Full implementation: ShootingPhase detects it after shooting, SentinelStormDialog prompts the player, unit can shoot again. Once-per-battle tracking via UnitAbilityManager. Works for both human and AI players. |

---

## 4. ALLARUS CUSTODIANS (Adeptus Custodes)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | No Allarus Custodians unit exists in any army JSON file. This Terminator-equivalent unit with Slayers of Tyrants, From Golden Light, and Vexilla cannot be played at all. |

### Abilities That Would Need Implementation

| Ability | Type | Gap |
|---------|------|-----|
| Deep Strike | Core | Already handled system-wide — just needs to be in army JSON. |
| Martial Ka'tah | Faction | Already handled system-wide — just needs to be in army JSON. |
| Vexilla | Wargear | ArmyListManager already supports +1 OC — just needs to be in army JSON. |
| Slayers of Tyrants | Datasheet | **NOT IMPLEMENTED** — "Re-roll Wound roll vs CHARACTER, MONSTER, or VEHICLE." Would need: (1) Entry in ABILITY_EFFECTS with conditional re-roll based on target keywords. (2) RulesEngine integration to check target keywords at wound-roll time. |
| From Golden Light | Datasheet | **NOT IMPLEMENTED** — "Once per battle, at end of opponent's turn, if not in Engagement Range, remove from battlefield and place into Strategic Reserves." Would need: (1) End-of-opponent-turn trigger. (2) UI prompt. (3) Strategic Reserves re-entry logic. |

---

## 5. PROSECUTORS (Adeptus Custodes faction / Anathema Psykana)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | No Prosecutors unit exists in any army JSON file. |
| No invulnerable save | — | CSV confirms Prosecutors have NO invulnerable save (field is "-"). Correct if implemented. |
| No Martial Ka'tah | — | CSV confirms Prosecutors do NOT have Martial Ka'tah. Correct — they are Sisters of Silence, not Custodians. |

### Abilities That Would Need Implementation

| Ability | Type | Gap |
|---------|------|-----|
| Daughters of the Abyss | Datasheet | UnitAbilityManager already has this ability defined (`grant_fnp_psychic_mortal`, value 3) because Witchseekers share it. **However**, see the critical FNP bug below — the flag is never checked during damage resolution. |
| Purity of Execution | Datasheet | **NOT IMPLEMENTED** — "Ranged attacks targeting a PSYKER unit gain [PRECISION] and [DEVASTATING WOUNDS]." Would need: (1) Target keyword check for PSYKER. (2) Conditional weapon ability grants at attack resolution time. |

---

## 6. VERTUS PRAETORS (Adeptus Custodes)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | No Vertus Praetors unit exists in any army JSON file. |

### Abilities That Would Need Implementation

| Ability | Type | Gap |
|---------|------|-----|
| Martial Ka'tah | Faction | Already supported system-wide. |
| Turbo-boost | Datasheet | **NOT IMPLEMENTED** — "When this unit Advances, do not roll; instead add 6\" to Move." Would need: (1) Advance-roll override in MovementPhase. (2) Check for this ability when calculating advance distance. |
| Quicksilver Execution | Datasheet | **NOT IMPLEMENTED** — "Once per battle, after Normal Move/Advance, select enemy unit moved over (excluding MONSTER/VEHICLE), roll D6 per model: 2+ = 2 mortal wounds." Would need: (1) Move-path tracking to detect units moved over. (2) Post-move prompt/resolution. (3) Once-per-battle tracking. |

---

## 7. WITCHSEEKERS (Adeptus Custodes faction / Anathema Psykana)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Scouts ability has wrong name | **HIGH** | Army JSON has `{"name": "Core", "type": "Core", "parameter": "6\""}`. The `name` field is "Core" instead of "Scouts 6\"". GameState's `_unit_has_scout_own()` checks `name.to_lower().begins_with("scout")` which will **NOT match** "Core". This means **Witchseekers will not get Scout moves**. |
| No invulnerable save | — | CSV confirms Witchseekers have NO invulnerable save. Correct in army JSON (no `invuln` field). |
| No Martial Ka'tah | — | CSV confirms Witchseekers do NOT have Martial Ka'tah. Correctly absent from army JSON. |

### Ability Implementation

| Ability | Type | Status | Notes |
|---------|------|--------|-------|
| Scouts 6" | Core | **HIGH** — BROKEN | See data issue above. The ability name is "Core" instead of "Scouts 6\"", so the detection code won't find it. |
| Daughters of the Abyss | Datasheet | **HIGH** — FLAG SET BUT NEVER READ | UnitAbilityManager correctly maps this to `grant_fnp_psychic_mortal` with value 3. EffectPrimitives defines the flag (`FLAG_FNP_PSYCHIC_MORTAL`). **However, RulesEngine.get_unit_fnp() does NOT check `effect_fnp_psychic_mortal`**, meaning the 3+ FNP against psychic attacks and mortal wounds is **never actually applied** during damage resolution. The flag is set on the unit but silently ignored. |
| Sanctified Flames | Datasheet | **OK** | Fully implemented in ShootingPhase. After shooting, tracks which enemies were hit, auto-selects a target, rolls a Battle-shock test. Emits `sanctified_flames_result` signal for UI. Correctly skipped during out-of-phase actions (Fire Overwatch). |

---

## 8. CALLIDUS ASSASSIN (Agents of the Imperium)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | No Callidus Assassin exists in any army JSON file. No Agents of the Imperium army at all. |

### Abilities That Would Need Implementation

| Ability | Type | Gap |
|---------|------|-----|
| Deep Strike | Core | Already handled system-wide. |
| Fights First | Core | Already handled in FightPhase (fight priority system). |
| Infiltrators | Core | Already handled in DeploymentPhase/DeploymentController. |
| Lone Operative | Core | Already handled in RulesEngine (targeting restrictions). |
| Assigned Agents | Faction | **NOT IMPLEMENTED** — Faction ability for Agents of the Imperium. Would need FactionAbilityManager entry. |
| Acrobatic Escape | Datasheet | **NOT IMPLEMENTED** — Complex: (1) End of Fight phase Fall Back D6". (2) End of opponent's turn, if >3" from enemies, remove and redeploy 9"+ from enemies next Movement phase. Would need fight-phase-end triggers and board-removal/reserves mechanics. |
| Lord of Deceit (Aura) | Datasheet | **NOT IMPLEMENTED** — "Each time opponent targets a unit within 12\" with a Stratagem, increase CP cost by 1." Would need: (1) Aura distance check in StratagemManager. (2) CP cost modification based on proximity. |
| Shadow Assignment | Special | **NOT IMPLEMENTED** — Pre-game model swap mechanic. |

---

## 9. INQUISITOR DRAXUS (Agents of the Imperium)

### Data Issues

| Issue | Severity | Details |
|-------|----------|---------|
| Unit not in army files | **CRITICAL** | No Inquisitor Draxus exists in any army JSON file. |

### Abilities That Would Need Implementation

| Ability | Type | Gap |
|---------|------|-----|
| Leader | Core | CharacterAttachmentManager handles this via `leader_data`. |
| Assigned Agents | Faction | **NOT IMPLEMENTED** — Same as Callidus above. |
| Authority of the Inquisition | Datasheet | **NOT IMPLEMENTED** — "While leading a unit, can embark in any TRANSPORT that Bodyguard unit can embark in." Would need TransportManager modification to check leader abilities. |
| Xenos Hunter | Datasheet | **NOT IMPLEMENTED** — "While leading a unit, +1 to Hit rolls vs non-IMPERIUM/non-CHAOS targets." Would need: (1) ABILITY_EFFECTS entry with keyword-conditional hit modifier. (2) RulesEngine check for target keywords. |
| Psychic Veil (Psychic) | Datasheet | **NOT IMPLEMENTED** — "In Command phase, roll D6: on 1, unit suffers D3 mortal wounds; on 2+, unit can only be targeted by ranged attacks within 18\" until next Command phase." Would need: (1) Command phase trigger. (2) Range-based targeting restriction. (3) Psychic keyword/handling. |

---

## CROSS-CUTTING ISSUES

### 1. `effect_fnp_psychic_mortal` flag is never read during damage resolution

**Severity: HIGH**
**Affects:** Witchseekers, Prosecutors (Daughters of the Abyss ability)

**Problem:** `UnitAbilityManager` correctly sets the `effect_fnp_psychic_mortal` flag on units with "Daughters of the Abyss". `EffectPrimitives` defines helper functions `has_effect_fnp_psychic_mortal()` and `get_effect_fnp_psychic_mortal()`. However, `RulesEngine.get_unit_fnp()` only checks `effect_fnp` (the generic FNP flag) and `meta.stats.fnp`. It **never** checks `effect_fnp_psychic_mortal`.

**Fix needed:** In `RulesEngine`, anywhere FNP is checked during damage application:
- Check `EffectPrimitivesData.get_effect_fnp_psychic_mortal(target_unit)`
- Apply it only when the damage source is a Psychic attack or mortal wounds
- This requires knowing whether the incoming damage is from a Psychic weapon or is mortal wounds (the mortal wound path already exists separately)

**Files:** `autoloads/RulesEngine.gd` (function `get_unit_fnp`, mortal wound resolution paths)

---

### 2. Invulnerable save not read from `meta.stats.invuln` in shooting interactive path

**Severity: MEDIUM**
**Affects:** All units that store invuln in `meta.stats` but not in individual model data

**Problem:** The invulnerable save is read from `target_model.get("invuln", 0)` in the shooting interactive path (`prepare_save_resolution` at line ~7693). The melee auto-resolve path (line 7098-7100) has a fallback to `target_unit.get("meta", {}).get("stats", {}).get("invuln", 0)`, but the shooting interactive path does NOT have this fallback.

If a unit's army JSON stores `invuln` only in `meta.stats` (which is the common pattern for Custodes units), the shooting path may miss it unless models have individual `invuln` fields.

**Fix needed:** Add `meta.stats.invuln` fallback to the shooting interactive save path, matching the melee path pattern. Or better: propagate `meta.stats.invuln` to individual model data at army load time.

**Files:** `autoloads/RulesEngine.gd` (functions `prepare_save_resolution`, `_resolve_shooting_assignment_impl`)

---

### 3. Missing unit definitions in army files

**Severity: CRITICAL**
**Affects:** 5 of 9 audited units

The following units have NO army JSON definition and cannot be played:
1. **Shield-Captain on Dawneagle Jetbike** — different from regular Shield-Captain
2. **Allarus Custodians** — Terminator-equivalent, key unit
3. **Prosecutors** — Sisters of Silence ranged unit
4. **Vertus Praetors** — Jetbike unit
5. **Callidus Assassin** — requires Agents of the Imperium army
6. **Inquisitor Draxus** — requires Agents of the Imperium army

These need army JSON entries with correct stats, weapons, abilities, keywords, and model data.

---

### 4. Stand Vigil objective-conditional upgrade not implemented

**Severity: HIGH**
**Affects:** Custodian Guard

**Problem:** Stand Vigil has two modes:
- **Base:** Re-roll a Wound roll of 1 (always active) — **IMPLEMENTED**
- **Enhanced:** Re-roll the Wound roll (full re-roll) when within range of a controlled objective — **NOT IMPLEMENTED**

The ability is currently set to `"condition": "always"` with `"scope": "ones"`. It should conditionally upgrade to `"scope": "all"` when the unit is within range of a controlled objective marker.

**Fix needed:**
1. Add objective proximity check in UnitAbilityManager when applying Stand Vigil
2. Check if any controlled objective is within range of the unit
3. If so, upgrade the reroll scope from "ones" to "failed" (or "all")

**Files:** `autoloads/UnitAbilityManager.gd` (ABILITY_EFFECTS entry for "Stand Vigil"), may also need `autoloads/MissionManager.gd` or `autoloads/BoardState.gd` for objective proximity queries

---

### 5. Witchseeker Scouts ability has wrong name in army JSON

**Severity: HIGH**
**Affects:** Witchseekers in both `adeptus_custodes.json` and `A_C_test.json`

**Problem:** The ability is defined as:
```json
{"name": "Core", "type": "Core", "description": "", "parameter": "6\""}
```
The name should be `"Scouts 6\""` (or at minimum begin with "Scout"). `GameState._unit_has_scout_own()` checks `name.to_lower().begins_with("scout")` which will NOT match `"Core"`. Witchseekers will not be offered Scout moves during the Scout Phase.

**Fix needed:** Change `"name": "Core"` to `"name": "Scouts 6\""` in both army JSON files.

**Files:** `armies/adeptus_custodes.json`, `armies/A_C_test.json`

---

### 6. Blade Champion missing `invuln: 4` in both army files

**Severity: CRITICAL**
**Affects:** Blade Champion in `adeptus_custodes.json` and `A_C_test.json`

**Problem:** The Blade Champion's `meta.stats` does not include `"invuln": 4`. The CSV data confirms all Custodes models (except Sisters of Silence) have a 4+ invulnerable save. Without this, the Blade Champion will rely only on its 2+ armour save against high-AP weapons, taking significantly more damage than intended.

**Fix needed:** Add `"invuln": 4` to `meta.stats` for U_BLADE_CHAMPION_A in both army files.

**Files:** `armies/adeptus_custodes.json`, `armies/A_C_test.json`

---

### 7. Custodian Guard missing `invuln: 4`

**Severity: CRITICAL**
**Affects:** Custodian Guard in `adeptus_custodes.json`

**Problem:** Same as Blade Champion — `meta.stats` has no `invuln` field. CSV confirms 4+.

**Fix needed:** Add `"invuln": 4` to `meta.stats` for U_CUSTODIAN_GUARD_B.

**Files:** `armies/adeptus_custodes.json`

---

## SUMMARY TABLE

| Unit | In Army? | Invuln | Core Abilities | Faction Ability | Datasheet Abilities | Wargear |
|------|----------|--------|----------------|-----------------|---------------------|---------|
| Blade Champion | Yes | **MISSING** | Deep Strike OK, Leader OK (functional) | Ka'tah OK | Swift Onslaught OK, Martial Inspiration OK | — |
| Shield-Captain (Dawneagle) | **NO** | — | — | — | Sweeping Advance NOT IMPL, Strategic Mastery OK (on regular) | — |
| Custodian Guard | Yes | **MISSING** | Deep Strike OK | Ka'tah OK | Stand Vigil PARTIAL, Sentinel Storm OK | Shield OK, Vexilla OK |
| Allarus Custodians | **NO** | — | — | — | Slayers of Tyrants NOT IMPL, From Golden Light NOT IMPL | — |
| Prosecutors | **NO** | N/A (none) | — | — | Daughters of the Abyss FLAG BROKEN, Purity of Execution NOT IMPL | — |
| Vertus Praetors | **NO** | — | — | — | Turbo-boost NOT IMPL, Quicksilver Execution NOT IMPL | — |
| Witchseekers | Yes | N/A (none) | Scouts **BROKEN** (wrong name) | N/A | Daughters of the Abyss FLAG BROKEN, Sanctified Flames OK | — |
| Callidus Assassin | **NO** | — | — | — | All NOT IMPL | — |
| Inquisitor Draxus | **NO** | — | — | — | All NOT IMPL | — |

### Priority Fixes (by impact)

1. **Fix Blade Champion & Custodian Guard invuln saves** — Simple JSON edit, major gameplay impact
2. **Fix Witchseeker Scouts ability name** — Simple JSON edit, unit can't use pre-game Scouts
3. **Fix `effect_fnp_psychic_mortal` in RulesEngine** — Code change, Daughters of the Abyss FNP never applies
4. **Fix invuln save fallback in shooting interactive path** — Code change in RulesEngine
5. **Implement Stand Vigil objective-conditional upgrade** — Moderate code change
6. **Add missing unit army JSON definitions** — Large data effort for 5+ units
7. **Implement missing datasheet abilities** — Significant code effort per ability
