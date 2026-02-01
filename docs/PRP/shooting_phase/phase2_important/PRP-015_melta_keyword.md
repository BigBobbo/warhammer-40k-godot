# PRP-015: Melta Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **MELTA X** keyword deal additional damage when the target is within half range. This represents the intense, focused heat of melta weapons being most effective at close range.

**Reference:** Wahapedia Core Rules - Weapon Abilities - MELTA

---

## Problem Statement

Currently, weapon damage is calculated as a flat value from the weapon profile. There's no mechanism to increase damage based on range to target, and the Melta keyword is not implemented.

---

## Solution Overview

Implement the MELTA keyword that:
1. Parses the Melta value (X) from weapon profile
2. Checks if target is within half weapon range
3. Adds X to the damage characteristic when in half range
4. Shows the Melta bonus in UI and damage rolls

---

## User Stories

- **US1:** As a player with Melta weapons, I want to deal extra damage at close range so that I'm rewarded for getting close to my targets.
- **US2:** As a player, I want to see the Melta range threshold so I can position my units optimally.
- **US3:** As a defender, I want to know when Melta damage is being applied to my unit.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. MELTA X weapons add X to their Damage characteristic at half range
2. "Half range" is measured from the shooting model to the closest target model (edge-to-edge)
3. The bonus applies per attack, not per weapon
4. If some models are in half range and some aren't, only attacks from models in half range get the bonus

### Common Melta Values
| Weapon | Base Damage | Melta Value | Damage at Half Range |
|--------|-------------|-------------|---------------------|
| Meltagun | D6 | Melta 2 | D6+2 |
| Multi-melta | D6 | Melta 2 | D6+2 |
| Inferno Pistol | D3 | Melta 2 | D3+2 |

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Parse Melta value from weapon
static func get_melta_bonus(weapon_id: String, board: Dictionary = {}) -> int:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    # Check special_rules string: "Melta 2", "Melta 4", etc.
    var regex = RegEx.new()
    regex.compile("melta (\\d+)")

    var result = regex.search(special_rules)
    if result:
        return result.get_string(1).to_int()

    # Check keywords array
    for keyword in keywords:
        result = regex.search(keyword.to_lower())
        if result:
            return result.get_string(1).to_int()

    return 0  # Not a Melta weapon

# Check if model is in melta range
static func is_in_melta_range(
    model_pos: Vector2,
    model_radius: float,
    target_unit: Dictionary,
    weapon_id: String,
    board: Dictionary
) -> bool:
    var weapon_profile = get_weapon_profile(weapon_id, board)
    var weapon_range = weapon_profile.get("range", 12)
    var half_range_px = Measurement.inches_to_px(weapon_range / 2.0)

    # Find closest target model
    var closest_distance = INF
    for target_model in target_unit.get("models", []):
        if not target_model.get("alive", true):
            continue
        var target_pos = _get_model_position(target_model)
        var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
        var edge_distance = model_pos.distance_to(target_pos) - model_radius - target_radius
        closest_distance = min(closest_distance, edge_distance)

    return closest_distance <= half_range_px

# Calculate damage with Melta bonus
static func calculate_melta_damage(
    base_damage: int,  # Already rolled if variable
    weapon_id: String,
    model_in_half_range: bool,
    board: Dictionary
) -> int:
    var melta_bonus = get_melta_bonus(weapon_id, board)

    if melta_bonus > 0 and model_in_half_range:
        return base_damage + melta_bonus

    return base_damage
```

#### Damage Application
```gdscript
# In save resolution / damage application
func apply_save_damage(...) -> Dictionary:
    # For each failed save, calculate damage with Melta
    for save_result in save_results:
        if save_result.saved:
            continue

        var model_index = save_result.model_index
        var base_damage = save_data.damage

        # Check if attacking model was in melta range
        var melta_applies = save_result.get("melta_applies", false)
        var final_damage = calculate_melta_damage(base_damage, weapon_id, melta_applies, board)

        # Apply damage to model
        # ... existing damage logic using final_damage ...
```

### Save Data Enhancement
```gdscript
# When building save data, track melta status per attack
var save_data = {
    # ... existing fields ...
    "melta_bonus": melta_bonus,
    "attacks_in_melta_range": models_in_half_range,
    "attacks_outside_melta_range": total_models - models_in_half_range
}
```

---

## Acceptance Criteria

- [ ] Melta weapons deal bonus damage at half range
- [ ] Melta value (X) is parsed from weapon profile
- [ ] Bonus is calculated per-model (only models in half range get bonus)
- [ ] UI shows half range indicator for Melta weapons
- [ ] Dice log shows "Melta: +X damage (in half range)"
- [ ] UI shows [M X] indicator for Melta weapons
- [ ] Variable damage (D6) + Melta bonus calculated correctly
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Range must be edge-to-edge measurement
- Bonus applies per-model, not per-weapon
- Must handle variable damage (D6+2, D3+2, etc.)

---

## Implementation Notes

### Variable Damage with Melta
For weapons with variable damage:
1. Roll damage dice (e.g., D6)
2. Add Melta bonus if in half range
3. Apply total damage

Example: Meltagun (D6 damage, Melta 2) in half range
- Roll D6 → get 4
- Add Melta bonus → 4 + 2 = 6 damage

### Split Range Scenarios
If unit has 3 models:
- 2 models in half range: Their attacks get Melta bonus
- 1 model outside half range: Its attacks use base damage

### UI Visualization
Show melta range circle:
- Full range circle (standard)
- Half range circle (different color, e.g., orange for "danger zone")
- Tooltip: "Within 6" - Melta +2 damage"

### Edge Cases
1. **All models in range:** All attacks get Melta bonus
2. **No models in range:** No Melta bonus
3. **Multi-damage roll:** Roll once, add bonus, apply to model

### Testing Scenarios
1. Meltagun at 4" (half of 8") → +2 damage
2. Meltagun at 6" (outside half range) → base damage
3. Multi-melta (D6, Melta 2) at close range → D6+2
4. Squad with 2 meltaguns, 1 in range, 1 out → different damage

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `get_melta_bonus()`, `is_in_melta_range()`, `calculate_melta_damage()` |
| `40k/scripts/ShootingController.gd` | Show melta range circle, show [M X] indicator |
| `40k/scripts/SaveDialog.gd` | Show melta damage bonus in damage display |

---

## Implementation Tasks

- [ ] Add `get_melta_bonus()` function to RulesEngine
- [ ] Add `is_in_melta_range()` function
- [ ] Add `calculate_melta_damage()` function
- [ ] Track melta status per-model in attack resolution
- [ ] Apply Melta bonus in damage calculation
- [ ] Update dice log to show Melta bonus
- [ ] Add melta range circle visualization
- [ ] Add Melta keyword to meltagun profiles
- [ ] Update weapon tree UI to show [M X] indicator
- [ ] Add unit tests
- [ ] Test with variable damage weapons
- [ ] Test multiplayer sync
