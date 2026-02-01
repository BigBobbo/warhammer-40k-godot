# PRP-013: Blast Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **BLAST** keyword make additional attacks against larger enemy units. The more models in the target unit, the more attacks the weapon makes. This represents explosive weapons being more effective against massed infantry.

**Reference:** Wahapedia Core Rules - Weapon Abilities - BLAST

---

## Problem Statement

Currently, weapon attacks are calculated as a flat value from the weapon profile, regardless of target unit size. There's no mechanism to scale attacks based on the number of models in the target unit.

---

## Solution Overview

Implement the BLAST keyword that:
1. Counts alive models in the target unit
2. Adds +1 attack per 5 models in the target (rounded down)
3. Minimum of 3 attacks when targeting units of 6+ models
4. Shows the Blast bonus in UI and dice log

---

## User Stories

- **US1:** As a player with Blast weapons, I want to deal more attacks against large units so that my explosive weapons are more effective against hordes.
- **US2:** As a player, I want to see how many bonus attacks I'm getting from Blast before confirming my target.
- **US3:** As a defending player, I want to understand why more attacks are being made against my large unit.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Weapons with BLAST add 1 to Attacks for every 5 models in target unit
2. When targeting a unit with 6+ models, Blast weapons always make minimum 3 attacks
3. The bonus is calculated per weapon, not per attacking model
4. BLAST weapons cannot target units within Engagement Range of friendly units (anti-cheese rule)

### Bonus Calculation
| Target Unit Size | Blast Bonus |
|-----------------|-------------|
| 1-4 models | +0 (no bonus) |
| 5-9 models | +1 (minimum 3 if weapon has fewer base attacks) |
| 10-14 models | +2 |
| 15-19 models | +3 |
| 20+ models | +4, etc. |

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Check if weapon has Blast
static func is_blast_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    if "blast" in special_rules:
        return true

    for keyword in keywords:
        if keyword.to_upper() == "BLAST":
            return true

    return false

# Calculate Blast bonus attacks
static func calculate_blast_bonus(weapon_id: String, target_unit: Dictionary, board: Dictionary = {}) -> int:
    if not is_blast_weapon(weapon_id, board):
        return 0

    # Count alive models in target unit
    var model_count = 0
    for model in target_unit.get("models", []):
        if model.get("alive", true):
            model_count += 1

    # Calculate bonus: +1 per 5 models
    var bonus = model_count / 5  # Integer division

    return bonus

# Calculate minimum attacks for Blast
static func calculate_blast_minimum(weapon_id: String, base_attacks: int, target_unit: Dictionary, board: Dictionary = {}) -> int:
    if not is_blast_weapon(weapon_id, board):
        return base_attacks

    # Count alive models
    var model_count = 0
    for model in target_unit.get("models", []):
        if model.get("alive", true):
            model_count += 1

    # Minimum 3 attacks against 6+ model units
    if model_count >= 6 and base_attacks < 3:
        return 3

    return base_attacks

# Validate Blast targeting restriction
static func validate_blast_targeting(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
    if not is_blast_weapon(weapon_id, board):
        return {"valid": true, "errors": []}

    # Blast cannot target units in engagement with friendlies
    var units = board.get("units", {})
    var actor_unit = units.get(actor_unit_id, {})
    var target_unit = units.get(target_unit_id, {})
    var actor_owner = actor_unit.get("owner", 0)

    # Check if target is in engagement range of any friendly unit
    for unit_id in units:
        var unit = units[unit_id]
        if unit.get("owner", 0) != actor_owner:
            continue  # Skip enemy units

        if unit_id == actor_unit_id:
            continue  # Skip self

        # Check if this friendly unit is in engagement with target
        if _check_engagement_range(unit, target_unit, board):
            return {
                "valid": false,
                "errors": ["Cannot fire Blast weapon at unit in Engagement Range of friendly units"]
            }

    return {"valid": true, "errors": []}
```

#### Attack Calculation
```gdscript
# In _resolve_assignment_until_wounds
var attacks_per_model = weapon_profile.get("attacks", 1)
var base_total_attacks = model_ids.size() * attacks_per_model

# Apply Blast bonus
var blast_bonus = calculate_blast_bonus(weapon_id, target_unit, board)
var total_attacks = base_total_attacks + blast_bonus

# Apply Blast minimum (if applicable)
var blast_min = calculate_blast_minimum(weapon_id, attacks_per_model, target_unit, board)
if blast_min > attacks_per_model:
    # Recalculate with minimum
    total_attacks = model_ids.size() * blast_min + blast_bonus

result.dice.append({
    "context": "attack_calculation",
    "base_attacks": base_total_attacks,
    "blast_bonus": blast_bonus,
    "total_attacks": total_attacks
})
```

---

## Acceptance Criteria

- [ ] Blast weapons gain +1 attack per 5 models in target unit
- [ ] Blast weapons make minimum 3 attacks vs 6+ model units
- [ ] Blast weapons cannot target units in engagement with friendlies
- [ ] UI shows Blast bonus preview before confirming target
- [ ] Dice log shows "Blast: +X attacks (Y models in target)"
- [ ] UI shows [B] indicator for Blast weapons
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must prevent targeting units in friendly engagement
- Bonus calculated from alive models only
- Works with variable attack weapons (e.g., D6 + Blast bonus)

---

## Implementation Notes

### UI Integration
Show blast bonus when target is selected:
```
Target: Ork Boyz (12 models)
Bolt Rifle: 2 attacks
Grenade: 3 attacks + 2 (Blast) = 5 attacks
```

### Variable Attacks with Blast
If weapon has D6 attacks:
1. Roll D6 for base attacks
2. Add Blast bonus after rolling
3. Apply Blast minimum if applicable

Example: Frag missile (D6 attacks, Blast) vs 10 models
- Roll D6 → get 2
- Blast minimum: 3 (vs 6+ models)
- Blast bonus: +2 (10 models = +2)
- Total: max(2, 3) + 2 = 5 attacks

### Engagement Range Check
Need to check if target unit is in ER with ANY friendly unit:
```gdscript
static func _check_engagement_range(unit1: Dictionary, unit2: Dictionary, board: Dictionary) -> bool:
    # Check if any model from unit1 is within 1" of any model from unit2
    const ER_INCHES = 1.0
    var er_px = Measurement.inches_to_px(ER_INCHES)

    for model1 in unit1.get("models", []):
        if not model1.get("alive", true):
            continue
        var pos1 = _get_model_position(model1)
        var radius1 = Measurement.base_radius_px(model1.get("base_mm", 32))

        for model2 in unit2.get("models", []):
            if not model2.get("alive", true):
                continue
            var pos2 = _get_model_position(model2)
            var radius2 = Measurement.base_radius_px(model2.get("base_mm", 32))

            var edge_distance = pos1.distance_to(pos2) - radius1 - radius2
            if edge_distance <= er_px:
                return true

    return false
```

### Testing Scenarios
1. Blast vs 4 models → no bonus
2. Blast vs 10 models → +2 bonus
3. Blast vs 6 models, base attack 1 → minimum 3
4. Blast vs unit in engagement with friendly → invalid target
5. Blast with D6 attacks vs 15 models → roll D6 + 3 bonus

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add blast functions, modify attack calculation, add targeting validation |
| `40k/scripts/ShootingController.gd` | Show blast bonus preview, show [B] indicator |
| `40k/phases/ShootingPhase.gd` | Validate blast targeting restrictions |

---

## Implementation Tasks

- [ ] Add `is_blast_weapon()` function to RulesEngine
- [ ] Add `calculate_blast_bonus()` function
- [ ] Add `calculate_blast_minimum()` function
- [ ] Add `validate_blast_targeting()` function
- [ ] Modify attack calculation to include Blast bonus
- [ ] Add Blast targeting restriction to validation
- [ ] Update UI to show Blast bonus preview
- [ ] Update dice log to show Blast details
- [ ] Add Blast keyword to test weapon profiles (grenades, missiles)
- [ ] Update weapon tree UI to show [B] indicator
- [ ] Add unit tests
- [ ] Test multiplayer sync
