# PRP-003: Heavy Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **HEAVY** keyword get +1 to hit if the unit remained stationary during the Movement phase. This rewards careful positioning and makes heavy weapons more accurate when properly set up.

**Reference:** Wahapedia Core Rules - Weapon Abilities - HEAVY

---

## Problem Statement

Currently, the shooting phase does not track whether a unit remained stationary. There's no mechanism to apply a +1 to hit bonus for Heavy weapons, and the hit modifier system only tracks user-selected modifiers (reroll 1s, +1/-1 from abilities).

---

## Solution Overview

Implement the HEAVY keyword that:
1. Tracks whether units remained stationary during Movement phase
2. Automatically applies +1 to hit for Heavy weapons when stationary
3. Shows the Heavy bonus in UI feedback and dice log

---

## User Stories

- **US1:** As a player with a stationary unit, I want my Heavy weapons to get +1 to hit so that staying still is rewarded.
- **US2:** As a player, I want to see when the Heavy bonus is being applied so I can make informed tactical decisions.
- **US3:** As a player, I want the Heavy bonus to stack correctly with other modifiers (respecting the +1/-1 cap).

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. If a unit remained stationary during the Movement phase, Heavy weapons get +1 to hit
2. "Remained stationary" means the unit did not move at all (not even 0" move)
3. The +1 modifier is subject to the standard hit modifier cap (net +1/-1 max)
4. Heavy weapons do NOT get a penalty for moving (10e removed this from 9e)

### Data Model Changes
- Add `remained_stationary` flag to unit flags
- Need to track this from Movement phase

### Code Changes Required

#### Movement Phase Integration
```gdscript
# At start of Movement phase
for unit in player_units:
    unit.flags["remained_stationary"] = true  # Assume stationary

# When any movement occurs (including 0" move action)
func _process_move(action: Dictionary) -> Dictionary:
    # ... existing move logic ...
    unit.flags["remained_stationary"] = false
```

#### `RulesEngine.gd`
```gdscript
# Check if weapon is Heavy
static func is_heavy_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var keywords = profile.get("keywords", [])
    for keyword in keywords:
        if keyword.to_upper() == "HEAVY":
            return true
    return false

# Modify hit roll resolution to apply Heavy bonus
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # ... existing logic ...

    # Check for Heavy bonus
    var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
    var is_heavy = is_heavy_weapon(weapon_id, board)

    if remained_stationary and is_heavy:
        # Add Heavy bonus to hit modifiers
        hit_modifiers |= HitModifier.PLUS_ONE  # Already have PLUS_ONE enum

    # ... rest of hit roll logic ...
```

### Modifier Cap Enforcement
The existing `apply_hit_modifiers()` already caps at +1/-1:
```gdscript
# Line 143-144 in RulesEngine.gd
net_modifier = clamp(net_modifier, -1, 1)
```

This means Heavy (+1) + Cover (-1) = net 0, which is correct.

---

## Acceptance Criteria

- [ ] Heavy weapons get +1 to hit when unit remained stationary
- [ ] Heavy weapons do NOT get +1 if unit moved (even 0" move)
- [ ] Heavy bonus stacks with other modifiers but respects +1/-1 cap
- [ ] UI shows [H] indicator for Heavy weapons
- [ ] Dice log shows when Heavy bonus was applied
- [ ] `remained_stationary` flag is set correctly by Movement phase
- [ ] Flag is cleared when Movement phase starts (assume stationary until proven otherwise)
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must integrate with existing hit modifier system (HitModifier enum)
- Must work with existing modifier cap logic
- Heavy keyword check must be case-insensitive

---

## Implementation Notes

### Flag Lifecycle
```
Movement Phase Start → Set remained_stationary = true for all units
Any Move Action → Set remained_stationary = false for that unit
End Movement Phase → Flag persists
Shooting Phase → Check flag for Heavy bonus
End Turn → Flag persists until next Movement phase start
```

### Interaction with Other Modifiers
Example scenarios:
| Situation | Heavy Bonus | Cover Penalty | Net Modifier |
|-----------|-------------|---------------|--------------|
| Stationary, no cover | +1 | 0 | +1 |
| Stationary, in cover | +1 | -1 | 0 |
| Moved, no cover | 0 | 0 | 0 |
| Moved, in cover | 0 | -1 | -1 |
| Stationary, +1 ability, cover | +1 +1 | -1 | +1 (capped) |

### Interaction with Other Keywords
- **Heavy + Assault:** Rare but possible. If unit Advanced, can't fire (Assault allows fire). If stationary, gets +1 (Heavy bonus).
- **Heavy + Pistol:** Very rare. Follow both rules independently.

### Edge Cases
1. **Disembarked units:** If a unit disembarks, it counts as having moved
2. **Deep Strike / Reinforcements:** Units arriving from reserves count as having moved
3. **Pile In / Consolidate:** These don't affect shooting (happen in Fight phase)

### Testing Scenarios
1. Unit stays still → shoots Heavy weapon → +1 to hit
2. Unit moves 6" → shoots Heavy weapon → no bonus
3. Unit stays still → shoots non-Heavy weapon → no bonus
4. Unit stays still → Heavy + cover → +1 and -1 cancel out

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/phases/MovementPhase.gd` | Set `remained_stationary` flag logic |
| `40k/autoloads/RulesEngine.gd` | Add `is_heavy_weapon()`, modify hit roll resolution |
| `40k/scripts/ShootingController.gd` | Show [H] indicator, show bonus in dice log |

---

## Implementation Tasks

- [ ] Add `remained_stationary` flag initialization in Movement phase start
- [ ] Clear `remained_stationary` flag when unit moves
- [ ] Add `is_heavy_weapon()` function to RulesEngine
- [ ] Modify hit roll resolution to apply Heavy +1 bonus
- [ ] Update dice log to show "Heavy: +1 to hit" when applicable
- [ ] Update ShootingController weapon tree to show Heavy indicator [H]
- [ ] Add Heavy keyword to appropriate weapon profiles in test data
- [ ] Add unit tests for Heavy keyword behavior
- [ ] Verify modifier cap works correctly with Heavy bonus
- [ ] Test multiplayer sync
