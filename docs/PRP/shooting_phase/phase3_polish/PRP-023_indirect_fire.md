# PRP-023: Indirect Fire Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with **INDIRECT FIRE** can target units that are not visible to the shooter. However, they suffer a -1 to hit penalty and the target gains the Benefit of Cover.

**Reference:** Wahapedia Core Rules - Weapon Abilities - INDIRECT FIRE

---

## Problem Statement

Currently, Line of Sight is required for all shooting. There's no mechanism to bypass LoS checks or apply appropriate penalties for indirect fire.

---

## Solution Overview

1. Indirect Fire weapons can target units without Line of Sight
2. When firing without LoS: -1 to hit, target gains cover
3. If firing WITH LoS, no penalties apply (normal shooting)

---

## Technical Requirements

### 10th Edition Rules
1. Can target enemies not visible to the firing model
2. When no LoS: -1 to hit AND target gets Benefit of Cover
3. If LoS exists, can fire normally (no penalties)
4. Some weapons/abilities may bypass these penalties

### Code Changes Required

```gdscript
static func is_indirect_fire_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "indirect fire" in profile.get("special_rules", "").to_lower()

# Modified target visibility check
static func _check_target_visibility(...) -> Dictionary:
    # ... existing LoS check ...

    if not has_los and is_indirect_fire_weapon(weapon_id, board):
        return {
            "visible": true,  # Can target without LoS
            "indirect_fire": true,  # Flag for penalties
            "reason": "Indirect Fire (no LoS)"
        }

    return {"visible": has_los, "indirect_fire": false, "reason": reason}
```

---

## Acceptance Criteria

- [ ] Indirect Fire weapons can target units without LoS
- [ ] -1 to hit when firing without LoS
- [ ] Target gains cover when fired upon without LoS
- [ ] Normal shooting when LoS exists
- [ ] UI shows [IF] indicator
- [ ] Clear feedback when using Indirect Fire mode

---

## Implementation Tasks

- [ ] Add `is_indirect_fire_weapon()` function
- [ ] Modify visibility check to allow Indirect Fire
- [ ] Apply -1 hit modifier when no LoS
- [ ] Apply cover benefit when no LoS
- [ ] Update target selection UI for Indirect Fire
- [ ] Add unit tests
