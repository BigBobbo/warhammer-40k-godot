# PRP-027: One Shot Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with **ONE SHOT** can only be fired once per battle. After firing, the weapon cannot be used again.

**Reference:** Wahapedia Core Rules - Weapon Abilities - ONE SHOT

---

## Problem Statement

Currently, weapons can be fired every turn without restriction. There's no mechanism to track weapon usage across the entire battle.

---

## Solution Overview

1. Track One Shot weapons that have been fired (per model)
2. Disable One Shot weapons after firing
3. Persist across battle (not just turn)

---

## Technical Requirements

### 10th Edition Rules
1. ONE SHOT weapons can only fire once per battle (not per turn)
2. After firing, the weapon is unavailable for the rest of the game
3. Tracked per model (each model with the weapon gets one use)

### Code Changes Required

```gdscript
static func is_one_shot_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "one shot" in profile.get("special_rules", "").to_lower()

# Track fired One Shot weapons in unit flags
# unit.flags.one_shot_fired = {"model_id": ["weapon_id1", "weapon_id2"]}

static func has_fired_one_shot(unit: Dictionary, model_id: String, weapon_id: String) -> bool:
    var fired = unit.get("flags", {}).get("one_shot_fired", {})
    var model_fired = fired.get(model_id, [])
    return weapon_id in model_fired

static func mark_one_shot_fired(unit_id: String, model_id: String, weapon_id: String) -> Dictionary:
    return {
        "op": "add_to_array",
        "path": "units.%s.flags.one_shot_fired.%s" % [unit_id, model_id],
        "value": weapon_id
    }
```

---

## Acceptance Criteria

- [ ] One Shot weapons can only fire once per battle
- [ ] Weapon disabled after firing (per model)
- [ ] Tracked across multiple turns
- [ ] UI clearly shows used/unused One Shot weapons
- [ ] UI shows [1] indicator for One Shot

---

## Implementation Tasks

- [ ] Add `is_one_shot_weapon()` function
- [ ] Add `has_fired_one_shot()` function
- [ ] Track One Shot usage in unit flags
- [ ] Disable fired One Shot weapons in weapon selection
- [ ] Update weapon tree to show One Shot status
- [ ] Persist flag through save/load
- [ ] Add unit tests
