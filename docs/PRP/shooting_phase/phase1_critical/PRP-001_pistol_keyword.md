# PRP-001: Pistol Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **PISTOL** keyword have special rules that allow them to be fired even when the unit is within Engagement Range of enemy models. This is a fundamental rule that enables close-combat units to shoot in tight situations.

**Reference:** Wahapedia Core Rules - Weapon Abilities - PISTOL

---

## Problem Statement

Currently, units within Engagement Range cannot shoot at all (`ShootingPhase.gd:1043` checks `flags.get("in_engagement", false)` and returns `false`). This prevents Pistol weapons from being used as intended by the 10th edition rules.

---

## Solution Overview

Implement the PISTOL keyword that:
1. Allows units in Engagement Range to shoot, but ONLY with Pistol weapons
2. Restricts Pistol fire to targets that are also within Engagement Range
3. Updates UI to show only valid Pistol targets when in engagement

---

## User Stories

- **US1:** As a player with a unit in Engagement Range, I want to fire my Pistol weapons so that I can deal damage before fighting in melee.
- **US2:** As a player, I want Pistol weapons to only target enemies in Engagement Range so that the rules are enforced correctly.
- **US3:** As a player, I want clear UI feedback showing which weapons are Pistols and which targets are valid.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. A unit within Engagement Range of enemies CAN shoot
2. When shooting while in Engagement Range, the unit can ONLY use Pistol weapons
3. Pistol weapons can ONLY target enemy units within Engagement Range of the shooting unit
4. Other weapons (non-Pistol) cannot be fired while in Engagement Range

### Data Model Changes
- Weapon profiles already support `keywords` array
- Need to check for "PISTOL" (case-insensitive) in keywords

### Code Changes Required

#### `ShootingPhase.gd`
```gdscript
func _can_unit_shoot(unit: Dictionary) -> bool:
    # ... existing checks ...

    # MODIFIED: Units in engagement CAN shoot (Pistol only)
    if flags.get("in_engagement", false):
        # Check if unit has any Pistol weapons
        return _unit_has_pistol_weapons(unit)

    # ... rest of function ...
```

#### `RulesEngine.gd`
```gdscript
# New function to check if weapon is a Pistol
static func is_pistol_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var keywords = profile.get("keywords", [])
    for keyword in keywords:
        if keyword.to_upper() == "PISTOL":
            return true
    return false

# Modify get_eligible_targets to filter by Pistol when in engagement
static func get_eligible_targets(actor_unit_id: String, board: Dictionary) -> Dictionary:
    # ... existing logic ...

    var actor_unit = units.get(actor_unit_id, {})
    var in_engagement = actor_unit.get("flags", {}).get("in_engagement", false)

    if in_engagement:
        # Only return targets within Engagement Range
        # Only include Pistol weapons in weapons_in_range
        # ... filter logic ...
```

#### `ShootingController.gd`
- Update `_refresh_weapon_tree()` to visually indicate Pistol weapons
- Disable non-Pistol weapons in UI when unit is in Engagement Range
- Filter target list to only show enemies in Engagement Range

---

## Acceptance Criteria

- [ ] Units in Engagement Range can select Pistol weapons for shooting
- [ ] Non-Pistol weapons are disabled/hidden when unit is in Engagement Range
- [ ] Pistol weapons can only target enemies within Engagement Range of the shooter
- [ ] Existing plasma_pistol and slugga weapons work with Pistol keyword
- [ ] UI clearly indicates which weapons are Pistols (e.g., [P] prefix)
- [ ] Multiplayer sync works correctly for Pistol shooting
- [ ] No regression in normal shooting when not in Engagement Range

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must integrate with existing `in_engagement` flag system
- Must work with Big Guns Never Tire (PRP-005) when implemented
- Pistol keyword check must be case-insensitive

---

## Implementation Notes

### Engagement Range Check
Use existing `Measurement.gd` functions:
```gdscript
const ENGAGEMENT_RANGE_INCHES = 1.0
var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
```

### Edge Cases
1. **Mixed weapons:** Unit has Pistols AND non-Pistols - only Pistols available in engagement
2. **Multiple enemies in ER:** Can choose which enemy unit to target with Pistols
3. **Embarked units:** Cannot fire Pistols through firing deck while transport is in engagement
4. **Characters attached:** Attached character's Pistols also fire

### Testing Scenarios
1. Intercessor unit with bolt_rifle + plasma_pistol in Engagement Range
2. Ork Boyz with sluggas in Engagement Range
3. Unit with only non-Pistol weapons in Engagement Range (should not be able to shoot)

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/phases/ShootingPhase.gd` | Modify `_can_unit_shoot()`, add `_unit_has_pistol_weapons()` |
| `40k/autoloads/RulesEngine.gd` | Add `is_pistol_weapon()`, modify `get_eligible_targets()`, modify `validate_shoot()` |
| `40k/scripts/ShootingController.gd` | Update weapon tree display, filter targets |

---

## Implementation Tasks

- [ ] Add `is_pistol_weapon()` function to RulesEngine
- [ ] Add `_unit_has_pistol_weapons()` helper to ShootingPhase
- [ ] Modify `_can_unit_shoot()` to allow shooting in engagement with Pistols
- [ ] Modify `get_eligible_targets()` to filter for engagement range when in_engagement
- [ ] Modify `validate_shoot()` to validate Pistol restrictions
- [ ] Update ShootingController weapon tree to show Pistol indicator
- [ ] Update ShootingController to disable non-Pistol weapons when in engagement
- [ ] Add unit tests for Pistol keyword behavior
- [ ] Test multiplayer sync
