# PRP-005: Big Guns Never Tire

## Context

In Warhammer 40K 10th Edition, **Big Guns Never Tire** is a core rule that allows MONSTER and VEHICLE units to shoot even while within Engagement Range of enemy models. However, there are restrictions and penalties that apply.

**Reference:** Wahapedia Core Rules - Big Guns Never Tire

---

## Problem Statement

Currently, all units within Engagement Range are completely prevented from shooting (`ShootingPhase.gd:1043`). This incorrectly prevents Monsters and Vehicles from using their ranged weapons in close combat situations.

---

## Solution Overview

Implement Big Guns Never Tire that:
1. Allows MONSTER and VEHICLE keyword units to shoot while in Engagement Range
2. Applies -1 to hit penalty when shooting while in Engagement Range (except Pistols)
3. Restricts target selection appropriately
4. Works alongside the Pistol keyword rules

---

## User Stories

- **US1:** As a player with a Monster/Vehicle in combat, I want to shoot with my big guns so that being engaged doesn't completely neutralize my firepower.
- **US2:** As a player, I want the -1 to hit penalty applied automatically so the rules are enforced correctly.
- **US3:** As a player, I want to understand which weapons I can fire and at what targets when using Big Guns Never Tire.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Units with the MONSTER or VEHICLE keyword can shoot while within Engagement Range
2. When shooting while in Engagement Range:
   - Attacks made with PISTOL weapons have NO penalty
   - Attacks made with other weapons suffer -1 to hit
3. Units can target enemies they are in Engagement Range with, OR other visible enemies
4. Enemy units can also shoot at Monsters/Vehicles that are in Engagement Range with other units
5. The -1 penalty is subject to the standard modifier cap

### Data Model Changes
- Need to identify units with MONSTER or VEHICLE keywords
- Keywords should be in `unit.meta.keywords` array

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Check if unit is Monster or Vehicle
static func is_monster_or_vehicle(unit: Dictionary) -> bool:
    var keywords = unit.get("meta", {}).get("keywords", [])
    for keyword in keywords:
        var kw_upper = keyword.to_upper()
        if kw_upper == "MONSTER" or kw_upper == "VEHICLE":
            return true
    return false

# Check if Big Guns Never Tire applies
static func big_guns_never_tire_applies(unit: Dictionary) -> bool:
    var in_engagement = unit.get("flags", {}).get("in_engagement", false)
    if not in_engagement:
        return false
    return is_monster_or_vehicle(unit)
```

#### `ShootingPhase.gd`
```gdscript
func _can_unit_shoot(unit: Dictionary) -> bool:
    var flags = unit.get("flags", {})

    if flags.get("in_engagement", false):
        # Check for Pistol weapons (PRP-001)
        if _unit_has_pistol_weapons(unit):
            return true

        # Check for Big Guns Never Tire
        if RulesEngine.is_monster_or_vehicle(unit):
            return true

        # No valid shooting options while in engagement
        return false

    # ... rest of existing logic ...
```

#### Hit Modifier Application
```gdscript
# In _resolve_assignment_until_wounds
var in_engagement = actor_unit.get("flags", {}).get("in_engagement", false)
var is_pistol = is_pistol_weapon(weapon_id, board)
var is_bgnt = RulesEngine.big_guns_never_tire_applies(actor_unit)

# Apply Big Guns Never Tire penalty (except for Pistols)
if is_bgnt and not is_pistol:
    hit_modifiers |= HitModifier.MINUS_ONE
```

---

## Acceptance Criteria

- [ ] Monsters can shoot while in Engagement Range
- [ ] Vehicles can shoot while in Engagement Range
- [ ] Non-Monster/Vehicle units still cannot shoot (except Pistols per PRP-001)
- [ ] -1 to hit penalty applied for non-Pistol weapons when in engagement
- [ ] Pistol weapons have no penalty (they use normal Pistol rules)
- [ ] Penalty stacks with other modifiers but respects cap
- [ ] UI shows BGNT status and penalty clearly
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must work alongside Pistol keyword (PRP-001)
- Must respect existing modifier cap system
- Keyword checks must be case-insensitive

---

## Implementation Notes

### Interaction with Pistol Keyword
When a Monster/Vehicle is in Engagement Range:
- Pistol weapons: Can fire at enemies in ER, no penalty (Pistol rules)
- Other weapons: Can fire at any target, -1 to hit (BGNT rules)

Both can be used in the same shooting activation.

### Target Selection Logic
| Shooter Status | Weapon Type | Valid Targets |
|---------------|-------------|---------------|
| In ER, Monster/Vehicle | Pistol | Enemies in ER only |
| In ER, Monster/Vehicle | Other | Any visible enemy |
| In ER, Infantry | Pistol | Enemies in ER only |
| In ER, Infantry | Other | Cannot fire |

### Being Shot At
Units CAN shoot at Monsters/Vehicles that are in Engagement Range with other units. This is already handled by the targeting system (we check shooter's ER status, not target's).

### Common Monsters/Vehicles
- Dreadnoughts (VEHICLE)
- Land Raiders (VEHICLE)
- Carnifexes (MONSTER)
- Greater Daemons (MONSTER)
- Knights (VEHICLE or TITANIC VEHICLE)

### Edge Cases
1. **Monster with Pistol:** Can use Pistol (no penalty) OR other weapons (-1 penalty)
2. **Degrading profiles:** Some vehicles lose BS as they take damage - BGNT penalty stacks
3. **Titanic:** TITANIC keyword units follow same rules (they have VEHICLE or MONSTER)

### Testing Scenarios
1. Dreadnought in ER shoots bolt rifle → -1 to hit
2. Dreadnought in ER shoots pistol → no penalty
3. Carnifex in ER shoots bio-cannon → -1 to hit
4. Intercessor in ER (no Monster/Vehicle keyword) → cannot shoot non-Pistol

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/phases/ShootingPhase.gd` | Modify `_can_unit_shoot()` |
| `40k/autoloads/RulesEngine.gd` | Add `is_monster_or_vehicle()`, `big_guns_never_tire_applies()`, apply penalty |
| `40k/scripts/ShootingController.gd` | Show BGNT status, show penalty in dice log |

---

## Dependencies

- **PRP-001 (Pistol Keyword):** Must be implemented first or alongside, as BGNT interacts with Pistol rules

---

## Implementation Tasks

- [ ] Add `is_monster_or_vehicle()` function to RulesEngine
- [ ] Add `big_guns_never_tire_applies()` function
- [ ] Modify `_can_unit_shoot()` to allow Monster/Vehicle shooting in ER
- [ ] Apply -1 hit modifier for non-Pistol weapons when BGNT active
- [ ] Update dice log to show "Big Guns Never Tire: -1 to hit"
- [ ] Update ShootingController to show BGNT status indicator
- [ ] Ensure Pistol weapons don't get BGNT penalty
- [ ] Add MONSTER/VEHICLE keywords to test unit data
- [ ] Add unit tests for BGNT behavior
- [ ] Test interaction with Pistol keyword
- [ ] Test modifier cap with BGNT penalty
- [ ] Test multiplayer sync
