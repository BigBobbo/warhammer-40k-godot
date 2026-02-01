# PRP-025: Lance Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **LANCE** keyword get +1 to wound on a turn the bearer's unit charged. This represents the momentum of a charge making weapons more effective.

**Reference:** Wahapedia Core Rules - Weapon Abilities - LANCE

---

## Problem Statement

Currently, there's no wound modifier system and no tracking of whether a unit charged this turn for shooting purposes.

---

## Solution Overview

1. Track `charged_this_turn` flag from Charge phase
2. Lance weapons get +1 to wound on the turn the unit charged
3. This affects the wound threshold calculation

---

## Technical Requirements

### 10th Edition Rules
1. +1 to wound rolls on a turn the bearer's unit made a charge move
2. The bonus applies in any phase that turn (including Fight phase for melee Lance weapons)
3. Standard wound modifier cap applies (+1/-1 max)

### Code Changes Required

```gdscript
static func is_lance_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "lance" in profile.get("special_rules", "").to_lower()

# Modify wound roll with Lance bonus
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # Check for Lance bonus
    var charged_this_turn = actor_unit.get("flags", {}).get("charged_this_turn", false)
    var is_lance = is_lance_weapon(weapon_id, board)

    var wound_modifier = 0
    if charged_this_turn and is_lance:
        wound_modifier += 1

    # Apply wound modifier (capped)
    wound_modifier = clamp(wound_modifier, -1, 1)

    for roll in wound_rolls:
        if roll + wound_modifier >= wound_threshold:
            wounds += 1
```

---

## Acceptance Criteria

- [ ] Lance weapons get +1 to wound after charging
- [ ] Bonus only applies on charge turn
- [ ] Wound modifier cap respected
- [ ] Works in Fight phase too
- [ ] UI shows [L] indicator

---

## Implementation Tasks

- [ ] Add `is_lance_weapon()` function
- [ ] Verify `charged_this_turn` flag exists
- [ ] Add wound modifier to wound roll calculation
- [ ] Update dice log to show Lance bonus
- [ ] Add unit tests
