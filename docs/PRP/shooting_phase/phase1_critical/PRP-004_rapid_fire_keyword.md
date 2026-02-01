# PRP-004: Rapid Fire Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **RAPID FIRE X** keyword fire X additional attacks when the target is within half the weapon's range. This is one of the most common weapon abilities, appearing on iconic weapons like bolters.

**Reference:** Wahapedia Core Rules - Weapon Abilities - RAPID FIRE

---

## Problem Statement

Currently, the shooting phase calculates attacks as a flat value from the weapon profile. There's no mechanism to check if the target is within half range and add bonus attacks for Rapid Fire weapons.

---

## Solution Overview

Implement the RAPID FIRE keyword that:
1. Parses the Rapid Fire value (X) from weapon special_rules or keywords
2. Checks if any models are within half weapon range of any target models
3. Adds X bonus attacks for models within half range
4. Shows the Rapid Fire bonus in UI and dice log

---

## User Stories

- **US1:** As a player with Rapid Fire weapons, I want to get extra attacks at close range so that I'm rewarded for aggressive positioning.
- **US2:** As a player, I want to see the Rapid Fire range threshold so I can position my units optimally.
- **US3:** As a player, I want to see how many bonus attacks I'm getting from Rapid Fire in the dice log.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Rapid Fire X adds X to the Attacks characteristic when target is within half range
2. "Within half range" is checked model-by-model (each model in half range gets the bonus)
3. Range is measured from shooting model to closest target model (edge-to-edge per 10e FAQ)
4. If some models are in half range and some aren't, only those in half range get the bonus

### Data Model Changes
- Weapon special_rules string should contain "Rapid Fire X" (e.g., "Rapid Fire 1")
- OR add to keywords array as "RAPID FIRE 1"

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Parse Rapid Fire value from weapon
static func get_rapid_fire_bonus(weapon_id: String, board: Dictionary = {}) -> int:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    # Check special_rules string
    var regex = RegEx.new()
    regex.compile("rapid fire (\\d+)")
    var result = regex.search(special_rules)
    if result:
        return result.get_string(1).to_int()

    # Check keywords array
    for keyword in keywords:
        var kw_result = regex.search(keyword.to_lower())
        if kw_result:
            return kw_result.get_string(1).to_int()

    return 0  # Not a Rapid Fire weapon

# Check how many models are in half range
static func count_models_in_half_range(
    actor_unit: Dictionary,
    target_unit: Dictionary,
    weapon_id: String,
    model_ids: Array,
    board: Dictionary
) -> int:
    var weapon_profile = get_weapon_profile(weapon_id, board)
    var weapon_range = weapon_profile.get("range", 24)
    var half_range_px = Measurement.inches_to_px(weapon_range / 2.0)

    var models_in_half_range = 0

    for model_id in model_ids:
        var model = _get_model_by_id(actor_unit, model_id)
        if not model or not model.get("alive", true):
            continue

        var model_pos = _get_model_position(model)
        var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))

        # Check distance to closest target model
        var closest_distance = INF
        for target_model in target_unit.get("models", []):
            if not target_model.get("alive", true):
                continue
            var target_pos = _get_model_position(target_model)
            var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
            var edge_distance = model_pos.distance_to(target_pos) - model_radius - target_radius
            closest_distance = min(closest_distance, edge_distance)

        if closest_distance <= half_range_px:
            models_in_half_range += 1

    return models_in_half_range

# Modify attack calculation in _resolve_assignment_until_wounds
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # ... existing logic ...

    # Calculate base attacks
    var attacks_per_model = weapon_profile.get("attacks", 1)
    var base_total_attacks = model_ids.size() * attacks_per_model

    # Check for Rapid Fire bonus
    var rapid_fire_bonus = get_rapid_fire_bonus(weapon_id, board)
    var rapid_fire_attacks = 0

    if rapid_fire_bonus > 0:
        var models_in_half = count_models_in_half_range(actor_unit, target_unit, weapon_id, model_ids, board)
        rapid_fire_attacks = models_in_half * rapid_fire_bonus

    var total_attacks = base_total_attacks + rapid_fire_attacks

    # ... rest of hit roll logic ...
```

---

## Acceptance Criteria

- [ ] Rapid Fire weapons get bonus attacks when target is within half range
- [ ] Bonus is calculated per-model (only models in half range get bonus)
- [ ] Rapid Fire value (X) is parsed from special_rules or keywords
- [ ] UI shows half range indicator for Rapid Fire weapons
- [ ] Dice log shows "Rapid Fire: +X attacks (Y models in half range)"
- [ ] Standard bolters (Rapid Fire 1) work correctly
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Range must be edge-to-edge (not center-to-center)
- Must handle variable Rapid Fire values (1, 2, etc.)
- Must work with mixed model ranges (some in half, some not)

---

## Implementation Notes

### Common Rapid Fire Weapons
| Weapon | Rapid Fire Value | Base Range | Half Range |
|--------|------------------|------------|------------|
| Bolt Rifle | Rapid Fire 1 | 24" | 12" |
| Bolter | Rapid Fire 1 | 24" | 12" |
| Heavy Bolter | - | 36" | - |
| Plasma Gun (standard) | Rapid Fire 1 | 24" | 12" |

### Visual Indicator
Show half-range circle on board when:
- Rapid Fire weapon is selected
- Different color from full range circle (e.g., orange vs green)

### Edge Cases
1. **Mixed range:** 3 models in half range, 2 outside → 3 get bonus, 2 don't
2. **Multiple weapons:** Each weapon calculates Rapid Fire independently
3. **Attached characters:** Character's Rapid Fire weapons calculate separately
4. **Variable attacks:** If base attacks is D6, Rapid Fire adds to the rolled value

### Testing Scenarios
1. 5 models with Bolt Rifle (RF1) at 10" → 10 attacks (5 base + 5 RF)
2. 5 models with Bolt Rifle (RF1) at 20" → 5 attacks (no RF bonus)
3. 3 models at 10", 2 models at 20" → 8 attacks (6 from close + 2 from far)
4. Weapon with Rapid Fire 2 at close range → double the bonus

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `get_rapid_fire_bonus()`, `count_models_in_half_range()`, modify attack calculation |
| `40k/scripts/ShootingController.gd` | Show half-range circle, show RF indicator |
| `40k/autoloads/Measurement.gd` | May need edge-to-edge distance helper |

---

## Implementation Tasks

- [ ] Add `get_rapid_fire_bonus()` function to parse Rapid Fire value
- [ ] Add `count_models_in_half_range()` function
- [ ] Modify `_resolve_assignment_until_wounds()` to calculate Rapid Fire attacks
- [ ] Update dice log to show Rapid Fire bonus details
- [ ] Add half-range circle visualization to ShootingController
- [ ] Update weapon tree to show [RF X] indicator
- [ ] Add Rapid Fire keyword to bolt_rifle and other appropriate weapons
- [ ] Add unit tests for Rapid Fire calculations
- [ ] Test with mixed model ranges
- [ ] Test multiplayer sync
