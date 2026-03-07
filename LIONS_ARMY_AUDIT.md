# Lions of the Emperor Army Audit

**Date:** 2026-03-07
**Army List:** 1995pts Adeptus Custodes — Lions of the Emperor (Against All Odds)
**Scope:** All units in the army list audited for ability implementation, UI access, and AI usage

---

## Executive Summary

| Category | Count |
|----------|-------|
| Units fully in the game (JSON + all abilities working) | 3 |
| Units in JSON but missing some abilities | 2 |
| Units NOT in any army JSON at all | 7 |
| Detachment rule (Against All Odds) implemented | **NO** |
| Enhancement (Admonimortis) implemented | **NO** |
| Lions of the Emperor stratagems in data CSV | Yes (6) |
| Lions of the Emperor stratagems implemented in code | **NO** |
| Talons of the Emperor faction auras implemented | **NO** |
| **Total ability gaps** | **~50** |

---

## Table of Contents

1. [Detachment & Enhancement](#detachment--enhancement)
2. [Unit-by-Unit Audit](#unit-by-unit-audit)
   - [Trajann Valoris](#1-trajann-valoris-character)
   - [Blade Champion x2](#2-blade-champion-x2-character)
   - [Shield-Captain on Dawneagle Jetbike](#3-shield-captain-on-dawneagle-jetbike-character)
   - [Custodian Guard x5](#4-custodian-guard-x5-battleline)
   - [Allarus Custodians](#5-allarus-custodians)
   - [Prosecutors](#6-prosecutors)
   - [Vertus Praetors](#7-vertus-praetors)
   - [Witchseekers x2](#8-witchseekers-x2)
   - [Callidus Assassin](#9-callidus-assassin-allied)
   - [Inquisitor Draxus](#10-inquisitor-draxus-allied)
3. [Faction Ability: Martial Ka'tah](#faction-ability-martial-katah)
4. [Summary of All Gaps](#summary-of-all-gaps)

---

## Detachment & Enhancement

### Lions of the Emperor — Against All Odds (Detachment Rule)

**Rules:** Whenever an Adeptus Custodes unit from your army (excluding Vehicles) makes an attack, if there are no other friendly units within 6", add 1 to the Hit roll and 1 to the Wound roll.

| Aspect | Status | Notes |
|--------|--------|-------|
| Detachment listed in Detachments.csv | **Yes** | Row 9, ID 000001029 |
| Stratagems in Stratagems.csv | **Yes** | 6 stratagems: Peerless Warrior, Unleash the Lions, Defiant to the Last, Gilded Champion, Swift as the Eagle, Manoeuvre and Fire |
| Detachment ability in FactionAbilityManager.gd | **NO** | Only Shield Host, Gladius Task Force, and War Horde are implemented in DETACHMENT_ABILITIES constant |
| Detachment ability applied in RulesEngine | **NO** | No code checks for "Lions of the Emperor" or "Against All Odds" |
| UI for detachment selection | **NO** | Army JSON hardcodes `"detachment": "Shield Host"` — no UI to select Lions of the Emperor |
| AI aware of detachment bonus | **NO** | AI has no logic for Against All Odds positioning/spacing |
| Stratagems implemented in StratagemManager | **NO** | Only Shield Host stratagems are wired up in code |

**Impact:** The core benefit of this army list — +1 to hit and wound when isolated — is completely non-functional. This is a critical gap since the entire army composition is designed around this rule.

### Lions of the Emperor Enhancements (4 total)

Only **Admonimortis** is used in this army list (on the Shield-Captain on Dawneagle Jetbike). All 4 are listed for completeness.

| Enhancement | Points | Restriction | Effect | Status |
|-------------|--------|-------------|--------|--------|
| **Admonimortis** | 10pts | Shield-Captain only | Bearer's melee weapons get +3 Strength, +1 AP, +1 Damage | **NOT IMPLEMENTED** |
| Superior Creation | 25pts | Infantry only | Once per battle: when destroyed, 2+ to return with full wounds | **NOT IMPLEMENTED** |
| Praesidius | 25pts | Any character | Bearer gains Lone Operative and Stealth | **NOT IMPLEMENTED** |
| Fierce Conqueror | 15pts | Shield-Captain only | +2 melee Attacks per 5 enemy models within 6" (rounded down) | **NOT IMPLEMENTED** |

| Aspect | Status | Notes |
|--------|--------|-------|
| Enhancement data in `40k/data/` | **NO** | No enhancement data files for Lions of the Emperor |
| Enhancement system in code | **NO** | No code references to any of these enhancements in `.gd` files |
| Weapon stat modification for enhancements | **NO** | No generic system to modify weapon stats based on enhancements |
| UI for enhancement effects | **NO** | No enhancement effect display or weapon stat overlay |
| AI aware of enhancements | **NO** | AI has no enhancement awareness |

**Impact of Admonimortis:** The Shield-Captain's interceptor lance should hit at S10 AP-2 D3 instead of S7 AP-1 D2 in melee. Without this, the unit is significantly weaker than intended.

---

## Unit-by-Unit Audit

### 1. Trajann Valoris (Character)

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Deep Strike | Core | Set up in Reserves, deploy 9"+ from enemies | N/A | Deployment system exists | N/A | N/A | **Not in game** |
| Martial Ka'tah | Faction | Choose Dacatarai (Sustained Hits 1) or Rendax (Lethal Hits) when fighting | N/A | FactionAbilityManager handles this | N/A | N/A | **Not in game** |
| Captain-General | Datasheet (Leader) | While leading, ignore any/all modifiers to BS/WS and Hit roll modifiers | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Moment Shackle | Datasheet | Once per battle, start of Fight phase, choose one: (1) Watcher's Axe has 12 Attacks, OR (2) 2+ invuln save | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Golden Laurels | Datasheet (Leader) | While leading, worsen AP of incoming melee attacks by 1 | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Hero of Lion's Gate | Datasheet | Once per battle: change any Hit/Wound/Save roll to unmodified 6 | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Warlord requirement | Special | Must be Warlord if in army | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Trajann is an Epic Hero with 4 unique datasheet abilities. None exist in the codebase. Captain-General is particularly impactful as it negates all hit modifiers (e.g., cover, -1 to hit abilities). Golden Laurels provides passive melee defense, and Hero of Lion's Gate is a clutch once-per-battle roll manipulation.

---

### 2. Blade Champion x2 (Character)

**Status: PARTIALLY IN GAME** — Exists in `adeptus_custodes.json` (1 copy as `U_BLADE_CHAMPION_A`).

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Deep Strike | Core | Teleport deployment | **Yes** | Deployment system | Yes | Yes | **Working** |
| Martial Ka'tah | Faction | Stance selection in Fight phase | **Yes** | FactionAbilityManager | KatahStanceDialog | Yes | **Working** |
| Swift Onslaught | Datasheet (Leader) | While leading, re-roll Charge rolls | **Yes** | UnitAbilityManager `reroll_charge` | ChargePhase offers reroll | Yes | **Working** |
| Martial Inspiration | Datasheet (Leader) | Once per battle: charge after advancing | **Yes** | UnitAbilityManager `advance_and_charge` | ChargePhase checks flag | Yes | **Working** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | **No** (missing from stats) | N/A | N/A | N/A | **MISSING** |

**Notes:** Both abilities are fully functional. However, the army list needs 2 Blade Champions — the existing JSON only has 1. The invulnerable save 4+ is not set in the stats block (`invuln` key is missing).

---

### 3. Shield-Captain on Dawneagle Jetbike (Character)

**Status: NOT IN GAME** — No entry in any army JSON. The existing `U_SHIELD_CAPTAIN_A` is a foot Shield-Captain (M6, Infantry), NOT the Dawneagle Jetbike version (M12, Mounted).

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Martial Ka'tah | Faction | Stance selection when fighting | N/A | FactionAbilityManager | N/A | N/A | **Not in game** |
| Strategic Mastery | Datasheet | Once per round: reduce stratagem CP by 1 | N/A | StratagemManager (exists for foot Shield-Captain) | N/A | N/A | **Not in game** |
| Sweeping Advance | Datasheet | Once per battle: free Fall Back or Normal move after fighting | N/A | **NO** — not in any code | **NO** | **NO** | **Not in game** |
| Leader (Vertus Praetors) | Core | Can lead Vertus Praetors | N/A | Attachment system | N/A | N/A | **Not in game** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |
| Mounted, Fly keywords | Special | 12" move, Fly keyword | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** This is a completely different datasheet from the foot Shield-Captain. It has different stats (M12, T6, W7), different weapons (Interceptor lance + Salvo launcher), different keywords (MOUNTED, FLY), and a different leader ability (Sweeping Advance vs Master of the Stances). Strategic Mastery exists in code for the foot version but Sweeping Advance has zero implementation anywhere.

---

### 4. Custodian Guard x5 (Battleline)

**Status: PARTIALLY IN GAME** — One squad exists in `adeptus_custodes.json` as `U_CUSTODIAN_GUARD_B` (4 models). The army list needs 5 squads (three x5, two x4).

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Deep Strike | Core | Teleport deployment | **Yes** | Deployment system | Yes | Yes | **Working** |
| Martial Ka'tah | Faction | Stance selection in Fight phase | **Yes** | FactionAbilityManager | KatahStanceDialog | Yes | **Working** |
| Stand Vigil | Datasheet | Re-roll wound 1s; re-roll ALL wounds if on controlled objective | **Yes** | UnitAbilityManager `reroll_wounds: ones` | Passive | Yes | **PARTIAL** — objective-conditional reroll ALL not implemented |
| Sentinel Storm | Datasheet | Once per battle: shoot again | **Yes** | ShootingPhase `has_shoot_again_ability()` | SentinelStormDialog | Always activates | **Working** |
| Praesidium Shield | Wargear | +1 Wounds | **Yes** | ArmyListManager WARGEAR_STAT_BONUSES | Passive | N/A | **Working** |
| Vexilla | Wargear | +1 OC | **Yes** | ArmyListManager WARGEAR_STAT_BONUSES | Passive | N/A | **Working** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | **No** (missing from stats) | N/A | N/A | N/A | **MISSING** |

**Notes:** Stand Vigil's enhanced mode (re-roll ALL wound rolls near controlled objectives) is not implemented — only the basic "re-roll 1s" works. The invulnerable save 4+ is missing from the stats block.

---

### 5. Allarus Custodians

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Deep Strike | Core | Teleport deployment | N/A | Deployment system exists | N/A | N/A | **Not in game** |
| Martial Ka'tah | Faction | Stance selection when fighting | N/A | FactionAbilityManager | N/A | N/A | **Not in game** |
| Slayers of Tyrants | Datasheet | Re-roll Wound rolls when attacking CHARACTER, MONSTER, or VEHICLE | N/A | **NO** | **NO** | **NO** | **Not in game** |
| From Golden Light | Datasheet | Once per battle: at end of opponent's turn, if not in Engagement Range, redeploy 9"+ from all enemies | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |
| Terminator keyword | Special | Relevant for Unleash the Lions stratagem | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Slayers of Tyrants is a powerful anti-elite ability (re-roll wounds vs Characters/Monsters/Vehicles). From Golden Light allows tactical redeployment mid-game. The Unleash the Lions stratagem (split into single-model units) is in the CSV data but has no code implementation.

---

### 6. Prosecutors

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Daughters of the Abyss | Datasheet | FNP 3+ vs Psychic Attacks and mortal wounds | N/A | UnitAbilityManager has entry (for Witchseekers) | N/A | N/A | **Not in game** |
| Purity of Execution | Datasheet | Ranged attacks vs PSYKER units gain [PRECISION] and [DEVASTATING WOUNDS] | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Null Aegis (Aura) | Faction (Talons of the Emperor) | Custodes within 6" get FNP 5+ vs Psychic Attacks and mortal wounds | N/A | **NO** | **NO** | **NO** | **Not in game** |
| ANATHEMA PSYKANA keyword | Special | Anti-psyker faction keyword | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Prosecutors are a Sisters of Silence unit. Purity of Execution gives Precision + Devastating Wounds vs Psykers. Null Aegis is a faction-level aura that benefits nearby Custodes units — this is part of the Talons of the Emperor faction rules which are entirely unimplemented.

---

### 7. Vertus Praetors

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Martial Ka'tah | Faction | Stance selection when fighting | N/A | FactionAbilityManager | N/A | N/A | **Not in game** |
| Quicksilver Execution | Datasheet | After moving over enemy models, roll D6 per model: 2+ = 1 mortal wound | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Turbo-boost | Core/Datasheet | Fixed Advance distance (no roll) | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Mounted, Fly keywords | Special | Fast movement, Fly | N/A | N/A | N/A | N/A | **Not in game** |
| Lance (weapon keyword) | Weapon | +1 to wound on charge turn | N/A | N/A | N/A | N/A | **Not in game** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Vertus Praetors are the jetbike unit. Quicksilver Execution (fly-over mortal wounds) is a unique ability with no equivalent in the codebase. The Lance weapon keyword (+1 to wound on charge turn) is also not implemented for their interceptor lances.

---

### 8. Witchseekers x2

**Status: IN GAME** — Two squads exist in `adeptus_custodes.json` as `U_WITCHSEEKERS_C` and `U_WITCHSEEKERS_D`.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Scout 6" | Core | Pre-game 6" movement | **Yes** (ability entry with parameter "6\"") | ScoutPhase | Yes | Yes | **Working** |
| Daughters of the Abyss | Datasheet | FNP 3+ vs Psychic/mortal wounds | **Yes** | UnitAbilityManager `grant_fnp_psychic_mortal` | Passive | N/A | **PARTIAL** — simplified as FNP 3+ always, should only apply vs Psychic Attacks and mortal wounds |
| Sanctified Flames | Datasheet | After shooting, enemy hit takes Battle-shock test | **Yes** | ShootingPhase | Automatic | Yes | **Working** |
| Null Aegis (Aura) | Faction (Talons of the Emperor) | Custodes within 6" get FNP 5+ vs Psychic Attacks and mortal wounds | **No** | **NO** | **NO** | **NO** | **MISSING** |

**Notes:** Witchseekers are the most complete unit in this army list. Daughters of the Abyss has a minor implementation issue (FNP 3+ should only apply against Psychic Attacks and mortal wounds, not all damage). Null Aegis aura (part of Talons of the Emperor faction rules) is entirely missing — this would give nearby Custodes units FNP 5+ vs psychic/mortal wounds.

---

### 9. Callidus Assassin (Allied)

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Infiltrators | Core | Deploy anywhere 9"+ from enemy deployment zone and models | N/A | Deployment system exists for Kommandos | N/A | N/A | **Not in game** |
| Lone Operative | Core | Cannot be targeted unless within 12" | N/A | RulesEngine.has_lone_operative() exists | N/A | N/A | **Not in game** |
| Acrobatic Escape | Datasheet | End of Fight: Fall Back D6". End of opponent's turn if not in engagement: redeploy 9"+ from enemies | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Lord of Deceit (Aura) | Datasheet | Enemy stratagems cost +1CP within 12" | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Invulnerable Save 4+ | Innate | 4+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |
| Phase sword (AP-4, Precision) | Weapon | High AP precision melee weapon | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Callidus is a complex unit with redeployment mechanics and a CP-taxing aura that would require significant StratagemManager integration. Lord of Deceit is particularly impactful in competitive play.

---

### 10. Inquisitor Draxus (Allied)

**Status: NOT IN GAME** — No entry in any army JSON file.

| Ability | Type | Rules Text | In JSON | In Code | UI | AI | Status |
|---------|------|-----------|---------|---------|----|----|--------|
| Authority of the Inquisition | Datasheet (Leader) | While leading, can embark in any Transport bodyguard can use | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Xenos Hunter | Datasheet (Leader) | While leading, +1 to Hit vs non-IMPERIUM/CHAOS | N/A | **NO** | **NO** | **NO** | **Not in game** |
| Psychic Veil (Psychic) | Datasheet | Command phase: D6 — 1: D3 mortal wounds to own unit; 2+: can only be targeted if attacker within 18" | N/A | **NO** | **NO** | **NO** | **Not in game** |
| PSYKER keyword | Special | Is a Psyker | N/A | N/A | N/A | N/A | **Not in game** |
| Invulnerable Save 5+ | Innate | 5+ invulnerable save | N/A | N/A | N/A | N/A | **Not in game** |

**Notes:** Draxus is from the Agents of the Imperium faction. Xenos Hunter's +1 to Hit against non-IMPERIUM/CHAOS targets is broadly useful but requires keyword checking infrastructure. Psychic Veil's 18" range restriction is a unique defensive mechanic with no equivalent in the codebase.

---

## Faction Ability: Talons of the Emperor

**Status: NOT IMPLEMENTED** — No code references to these aura interactions.

| Rule | Applies To | Effect | Status |
|------|-----------|--------|--------|
| Null Aegis (Aura) | ANATHEMA PSYKANA units (Sisters of Silence) | While a Custodes unit is within 6", that Custodes unit gets FNP 5+ vs Psychic Attacks and mortal wounds | **Not implemented** |
| Deadly Unity (Aura) | ADEPTUS CUSTODES units (non-Anathema Psykana) | While an Anathema Psykana unit is within 6", +1 to Hit for that Anathema Psykana unit | **Not implemented** |

**Notes:** These are cross-faction auras that encourage mixed Custodes + Sisters of Silence positioning. Both Witchseeker and Prosecutor squads in this army would project Null Aegis, and all Custodes units would project Deadly Unity. This requires the aura ability infrastructure in UnitAbilityManager.

---

## Faction Ability: Martial Ka'tah

**Status: IMPLEMENTED** for units that exist in the game.

| Aspect | Status |
|--------|--------|
| Dacatarai Stance (Sustained Hits 1) | **Working** — FactionAbilityManager + KatahStanceDialog |
| Rendax Stance (Lethal Hits) | **Working** — FactionAbilityManager + KatahStanceDialog |
| Player UI for stance selection | **Working** — KatahStanceDialog shown in Fight Phase |
| AI stance selection | **Working** — AI selects stance automatically |

**Notes:** Martial Ka'tah works correctly for all units that exist in the game. Units not in the game (Trajann, Allarus, Vertus Praetors, Dawneagle Shield-Captain) would inherit this functionality once added to the army JSON.

---

## Summary of All Gaps

### Critical Gaps (Game-Breaking for this Army List)

1. **Against All Odds detachment rule not implemented** — The entire army is built around +1 hit/+1 wound when isolated. Without this, every unit is significantly weaker than intended.
2. **7 of 10 unique unit types not in the game** — Trajann Valoris, Shield-Captain on Dawneagle Jetbike, Allarus Custodians, Prosecutors, Vertus Praetors, Callidus Assassin, Inquisitor Draxus have no army JSON entries.
3. **Lions of the Emperor stratagems not implemented** — 6 stratagems exist in CSV data but none are wired up in code (Peerless Warrior, Unleash the Lions, Defiant to the Last, Gilded Champion, Swift as the Eagle, Manoeuvre and Fire).

### Major Gaps (Significant Ability Missing)

4. **Admonimortis enhancement not implemented** — +3S/+1AP/+1D to melee weapons is a significant power boost.
5. **Trajann's 4 unique abilities not implemented** — Captain-General, Moment Shackle, Golden Laurels, Hero of Lion's Gate.
6. **Sweeping Advance not implemented** — Shield-Captain on Dawneagle Jetbike's key ability.
7. **Quicksilver Execution not implemented** — Vertus Praetors' fly-over mortal wounds.
8. **Callidus Assassin's Acrobatic Escape & Lord of Deceit not implemented** — Unique redeployment and CP-taxing mechanics.
9. **Allarus Custodians' Slayers of Nightmares not implemented** — Post-charge Battle-shock forcing.
10. **Inquisitor Draxus's 3 abilities not implemented** — Authority, Xenos Hunter, Psychic Veil.

### Minor Gaps (Partially Working or Edge Cases)

11. **Stand Vigil objective-conditional upgrade** — Re-roll ALL wound rolls near controlled objectives not implemented (only re-roll 1s works).
12. **Daughters of the Abyss over-simplified** — FNP 3+ applies to all damage instead of only Psychic Attacks and mortal wounds.
13. **Invulnerable saves missing from unit stats** — Blade Champion and Custodian Guard JSON entries lack `"invuln": 4` in their stats blocks.
14. **Lance weapon keyword** — +1 to wound on charge turn not implemented for interceptor lances.
15. **Turbo-boost** — Fixed advance distance for jetbikes not implemented.

### What IS Working

- **Blade Champion** — Swift Onslaught (reroll charge), Martial Inspiration (advance & charge), Martial Ka'tah all functional with UI and AI.
- **Custodian Guard** — Stand Vigil (basic), Sentinel Storm (shoot again), Praesidium Shield, Vexilla all functional with UI and AI.
- **Witchseekers** — Scout 6", Daughters of the Abyss (simplified), Sanctified Flames all functional.
- **Martial Ka'tah faction ability** — Fully working with KatahStanceDialog, FactionAbilityManager, and AI.
- **Deep Strike** — Deployment system handles this for units that exist.

---

## Recommendations (Priority Order)

1. **Add Against All Odds to FactionAbilityManager** — Detect "Lions of the Emperor" detachment, apply +1 hit/+1 wound when no friendly units within 6". This is the single highest-impact change.
2. **Create army JSON entries** for the 7 missing unit types with correct stats, weapons, and abilities.
3. **Wire up Lions of the Emperor stratagems** — The CSV data exists; StratagemManager needs to recognise and apply them.
4. **Implement Admonimortis enhancement** — Weapon stat modification system for enhancements.
5. **Add invulnerable saves** to existing unit stat blocks (Blade Champion, Custodian Guard).
6. **Implement new ability types** — Sweeping Advance, Quicksilver Execution, Moment Shackle, Captain-General, etc. require new UnitAbilityManager entries and phase integration.
7. **Fix Stand Vigil** objective-conditional upgrade and Daughters of the Abyss scope.
