# PRP-012: Devastating Wounds Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **DEVASTATING WOUNDS** ability cause Critical Wounds (unmodified 6s to wound) to bypass saving throws entirely, inflicting damage directly. This represents weapons capable of finding weak points or dealing catastrophic damage.

**Reference:** Wahapedia Core Rules - Weapon Abilities - DEVASTATING WOUNDS

---

## Problem Statement

Currently, all wounds proceed to saving throws. There's no mechanism to bypass saves on critical wounds, and the system doesn't track unmodified wound rolls.

**Dependency:** Requires critical roll tracking infrastructure (similar to PRP-031).

---

## Solution Overview

Implement Devastating Wounds that:
1. Tracks unmodified 6s on wound rolls (Critical Wounds)
2. For Devastating Wounds weapons, critical wounds bypass saves
3. Damage from devastating wounds is applied directly
4. Regular wounds still proceed to saves normally
5. **Important 10e Change:** Devastating Wounds now deals the weapon's damage (not mortal wounds)

---

## User Stories

- **US1:** As a player with Devastating Wounds weapons, I want my critical wounds to bypass saves so that heavily armored targets can still be damaged.
- **US2:** As a player, I want to see which wounds came from Devastating Wounds in the dice log.
- **US3:** As a defender, I want to know which wounds I cannot save against.

---

## Technical Requirements

### 10th Edition Rules (Exact - Updated in 2024)
1. Critical Wound = unmodified wound roll of 6 (before any modifiers)
2. With Devastating Wounds, Critical Wounds cannot be saved (armor or invulnerable)
3. The attack's Damage characteristic is applied directly (NOT mortal wounds)
4. Regular wounds proceed to saves normally
5. Feel No Pain abilities CAN still be used against Devastating Wounds damage

### Data Model Changes
- Need to track unmodified wound rolls
- Save data needs to indicate which wounds are "unsaveable"

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Check if weapon has Devastating Wounds
static func has_devastating_wounds(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    if "devastating wounds" in special_rules:
        return true

    for keyword in keywords:
        if "devastating wounds" in keyword.to_lower():
            return true

    return false

# Modified wound roll resolution
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # ... hit roll processing ...

    var wound_rolls = rng.roll_d6(total_hits)
    var regular_wounds = 0
    var devastating_wounds = 0  # Critical wounds with Devastating Wounds

    var has_dev_wounds = has_devastating_wounds(weapon_id, board)

    for roll in wound_rolls:
        var unmodified_roll = roll
        # Apply wound modifiers if any
        var final_roll = roll  # TODO: Add wound modifier system

        if final_roll >= wound_threshold:
            if has_dev_wounds and unmodified_roll == 6:
                devastating_wounds += 1
            else:
                regular_wounds += 1

    # Build save data
    var save_data = {
        "wounds_to_save": regular_wounds,
        "devastating_wounds": devastating_wounds,  # Cannot be saved
        "devastating_damage": devastating_wounds * damage_per_wound,
        # ... other save data ...
    }

    result.dice.append({
        "context": "wound_roll",
        "rolls_raw": wound_rolls,
        "successes": regular_wounds + devastating_wounds,
        "critical_wounds": devastating_wounds,
        "regular_wounds": regular_wounds
    })

    # ... continue to save resolution ...
```

#### Save Dialog Integration
```gdscript
# In SaveDialog.gd
func setup_save_data(save_data: Dictionary):
    var dev_wounds = save_data.get("devastating_wounds", 0)
    var dev_damage = save_data.get("devastating_damage", 0)

    if dev_wounds > 0:
        # Show unsaveable damage section
        _show_devastating_wounds_section(dev_wounds, dev_damage)

    # Only roll saves for regular wounds
    var saveable_wounds = save_data.get("wounds_to_save", 0)
    _setup_save_rolls(saveable_wounds)
```

---

## Acceptance Criteria

- [ ] Critical wounds (unmodified 6s) are tracked separately
- [ ] Devastating Wounds critical wounds bypass saves entirely
- [ ] Damage is applied directly (weapon's damage characteristic)
- [ ] Regular wounds still get saving throws
- [ ] SaveDialog shows devastating wounds damage clearly
- [ ] Dice log shows "Devastating Wounds: X wounds (unsaveable)"
- [ ] UI shows [DW] indicator for Devastating Wounds weapons
- [ ] Feel No Pain should work against DW damage (if implemented)
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly (2024 update)
- Devastating Wounds = weapon damage, NOT mortal wounds
- Must track UNMODIFIED wound roll
- Cannot use armor saves OR invulnerable saves against DW

---

## Implementation Notes

### 2024 Rule Update
Previously, Devastating Wounds inflicted mortal wounds. The 2024 update changed this:
- **Old:** Critical wound = mortal wounds equal to damage
- **New:** Critical wound = normal damage that cannot be saved

### Save Dialog Changes
The SaveDialog needs to handle two categories:
1. **Saveable wounds:** Roll saves as normal
2. **Devastating wounds:** Auto-applied damage (show to defender but no roll)

### Damage Application
```gdscript
# In apply_save_damage
var total_unsaveable_damage = save_data.get("devastating_damage", 0)
var saved_damage = 0
var failed_save_damage = 0

# Apply devastating wounds first (no save possible)
_apply_damage_to_unit(target_unit_id, total_unsaveable_damage, ...)

# Then process saveable wounds
# ... existing save logic ...
```

### Interaction with Other Abilities
| Ability | Interaction with Devastating Wounds |
|---------|-------------------------------------|
| Lethal Hits | Separate (hit roll vs wound roll) |
| Anti-X | Can trigger crit wound, enabling DW |
| Feel No Pain | CAN be used against DW damage |
| Invulnerable Save | Cannot be used against DW |

### Edge Cases
1. **All devastating:** If all wounds are critical, no saves rolled
2. **Modified 6:** Wound roll of 5 with +1 = 6, but NOT critical
3. **Multi-damage weapons:** Each DW wound does full damage

### Testing Scenarios
1. Roll 4 wound rolls, two are 6s → 2 unsaveable + 2 saveable
2. Melta (damage 6) with DW, roll 6 to wound → 6 unsaveable damage
3. Roll no 6s → all wounds saveable normally

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `has_devastating_wounds()`, modify wound processing |
| `40k/scripts/SaveDialog.gd` | Handle unsaveable devastating wounds |
| `40k/scripts/ShootingController.gd` | Show [DW] indicator |

---

## Implementation Tasks

- [ ] Add critical wound tracking to wound roll
- [ ] Add `has_devastating_wounds()` function to RulesEngine
- [ ] Modify wound roll to separate critical vs regular wounds
- [ ] Update save_data structure to include devastating wounds
- [ ] Modify SaveDialog to show unsaveable damage section
- [ ] Apply devastating damage without save rolls
- [ ] Update dice log to show devastating wounds
- [ ] Add Devastating Wounds to test weapon profiles
- [ ] Update weapon tree UI to show [DW] indicator
- [ ] Add unit tests
- [ ] Test multiplayer sync
