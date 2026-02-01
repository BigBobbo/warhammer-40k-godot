# PRP-022: Hazardous Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **HAZARDOUS** ability can harm the wielder. When firing, roll a D6 for each Hazardous weapon - on a 1, the model suffers damage.

**Reference:** Wahapedia Core Rules - Weapon Abilities - HAZARDOUS

---

## Problem Statement

Currently, shooting attacks never damage the attacking unit. There's no mechanism for self-inflicted damage from weapon abilities.

---

## Solution Overview

1. After attack resolution, roll Hazardous check for each Hazardous weapon fired
2. On roll of 1: Character/Vehicle/Monster takes 3 mortal wounds, other models slain
3. Apply self-damage before next weapon resolves

---

## Technical Requirements

### 10th Edition Rules
1. Roll D6 for each Hazardous weapon fired
2. On a 1:
   - CHARACTER, VEHICLE, or MONSTER: 3 mortal wounds
   - Other models: 1 model destroyed (owner's choice)
3. Check happens after the weapon's attacks resolve

### Code Changes Required

```gdscript
static func is_hazardous_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "hazardous" in profile.get("special_rules", "").to_lower()

static func resolve_hazardous_check(
    unit_id: String,
    weapon_id: String,
    models_fired: int,
    board: Dictionary,
    rng: RNGService
) -> Dictionary:
    if not is_hazardous_weapon(weapon_id, board):
        return {"hazardous_triggered": false}

    var rolls = rng.roll_d6(models_fired)
    var ones_rolled = rolls.count(1)

    if ones_rolled == 0:
        return {"hazardous_triggered": false, "rolls": rolls}

    # Determine damage type
    var unit = board.get("units", {}).get(unit_id, {})
    var keywords = unit.get("meta", {}).get("keywords", [])
    var is_big = "CHARACTER" in keywords or "VEHICLE" in keywords or "MONSTER" in keywords

    return {
        "hazardous_triggered": true,
        "rolls": rolls,
        "ones_rolled": ones_rolled,
        "damage_type": "mortal_wounds" if is_big else "slay_model",
        "damage": 3 * ones_rolled if is_big else ones_rolled
    }
```

---

## Acceptance Criteria

- [ ] Hazardous check rolled after weapon fires
- [ ] Roll of 1 causes self-damage
- [ ] CHARACTER/VEHICLE/MONSTER take 3 mortal wounds per 1
- [ ] Other units lose 1 model per 1
- [ ] Dice log shows Hazardous check results
- [ ] UI shows [HAZ] indicator

---

## Implementation Tasks

- [ ] Add `is_hazardous_weapon()` function
- [ ] Add `resolve_hazardous_check()` function
- [ ] Integrate Hazardous check into weapon resolution
- [ ] Implement mortal wound self-damage
- [ ] Implement model removal self-damage
- [ ] Update dice log
- [ ] Add unit tests
