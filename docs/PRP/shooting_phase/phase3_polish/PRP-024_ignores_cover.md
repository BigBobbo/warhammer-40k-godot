# PRP-024: Ignores Cover Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with **IGNORES COVER** negate the Benefit of Cover for the target. This represents weapons accurate enough to find targets in terrain.

**Reference:** Wahapedia Core Rules - Weapon Abilities - IGNORES COVER

---

## Problem Statement

Currently, cover is applied to all models in/behind terrain. There's no mechanism to ignore cover for specific weapons.

**Dependency:** Requires PRP-030 (Cover Logic Fix) to ensure cover system is correct first.

---

## Solution Overview

1. Check if weapon has Ignores Cover
2. If true, do not apply cover save bonus to target
3. Simple flag check in save calculation

---

## Technical Requirements

### 10th Edition Rules
1. Target does not receive Benefit of Cover against this weapon
2. This includes cover from terrain AND abilities that grant cover
3. Simple binary - either ignores all cover or doesn't

### Code Changes Required

```gdscript
static func ignores_cover(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "ignores cover" in profile.get("special_rules", "").to_lower()

# Modify save calculation
static func _calculate_save_needed(base_save, ap, has_cover, invuln, weapon_id, board) -> Dictionary:
    # Check if cover is negated
    if ignores_cover(weapon_id, board):
        has_cover = false

    # ... existing save calculation ...
```

---

## Acceptance Criteria

- [ ] Ignores Cover weapons negate cover save bonus
- [ ] Cover from terrain ignored
- [ ] Cover from abilities ignored
- [ ] UI shows [IC] indicator
- [ ] Dice log shows "Cover ignored"

---

## Implementation Tasks

- [ ] Add `ignores_cover()` function
- [ ] Modify save calculation to check Ignores Cover
- [ ] Update dice log to show when cover ignored
- [ ] Add unit tests
