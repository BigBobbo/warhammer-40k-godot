# PRP-002: Assault Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **ASSAULT** keyword can be fired even if the unit Advanced during the Movement phase. Without this keyword, units that Advance cannot shoot at all. This is crucial for aggressive playstyles and fast-moving armies.

**Reference:** Wahapedia Core Rules - Weapon Abilities - ASSAULT

---

## Problem Statement

Currently, the shooting phase does not track whether a unit Advanced. The `cannot_shoot` flag is set generically but doesn't distinguish between units that Advanced (which could shoot Assault weapons) and units that Fell Back (which cannot shoot at all without special rules).

---

## Solution Overview

Implement the ASSAULT keyword that:
1. Tracks whether units Advanced during Movement phase
2. Allows units that Advanced to shoot, but ONLY with Assault weapons
3. Updates UI to show only valid Assault weapons when unit has Advanced

---

## User Stories

- **US1:** As a player who Advanced a unit, I want to fire my Assault weapons so that I can maintain pressure while moving aggressively.
- **US2:** As a player, I want non-Assault weapons to be disabled after Advancing so that the rules are enforced correctly.
- **US3:** As a player, I want to see which of my weapons have the Assault keyword before deciding to Advance.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Units that Advanced during the Movement phase can still shoot
2. When shooting after Advancing, the unit can ONLY use Assault weapons
3. Non-Assault weapons cannot be fired after Advancing
4. There is NO penalty to hit when firing Assault weapons after Advancing

### Data Model Changes
- Add `advanced` flag to unit flags (may already exist)
- Weapon profiles need "ASSAULT" in keywords array

### Code Changes Required

#### Movement Phase Integration
Ensure `MovementPhase.gd` sets the flag:
```gdscript
# When unit completes an Advance move
unit.flags["advanced"] = true
```

#### `ShootingPhase.gd`
```gdscript
func _can_unit_shoot(unit: Dictionary) -> bool:
    var flags = unit.get("flags", {})

    # Units that Advanced CAN shoot (Assault only)
    if flags.get("advanced", false):
        return _unit_has_assault_weapons(unit)

    # Units that Fell Back CANNOT shoot (unless special rule)
    if flags.get("fell_back", false):
        return false

    # ... rest of existing logic ...
```

#### `RulesEngine.gd`
```gdscript
# New function to check if weapon is Assault
static func is_assault_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var keywords = profile.get("keywords", [])
    for keyword in keywords:
        if keyword.to_upper() == "ASSAULT":
            return true
    return false

# Modify validate_shoot to check Advanced + Assault
static func validate_shoot(action: Dictionary, board: Dictionary) -> Dictionary:
    # ... existing validation ...

    var actor_unit = units.get(actor_unit_id, {})
    var advanced = actor_unit.get("flags", {}).get("advanced", false)

    if advanced:
        # Validate all weapons are Assault type
        for assignment in assignments:
            var weapon_id = assignment.get("weapon_id", "")
            if not is_assault_weapon(weapon_id, board):
                errors.append("Cannot fire non-Assault weapon '%s' after Advancing" % weapon_id)

    # ... rest of validation ...
```

---

## Acceptance Criteria

- [ ] Units that Advanced can shoot with Assault weapons
- [ ] Units that Advanced cannot shoot with non-Assault weapons
- [ ] UI disables/hides non-Assault weapons when unit has Advanced
- [ ] UI shows [A] indicator for Assault weapons in weapon tree
- [ ] No hit penalty for Assault weapons after Advancing (10e removed this)
- [ ] `advanced` flag is set correctly by Movement phase
- [ ] Flag is cleared at start of next turn
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must integrate with existing movement flag system
- Must not affect units that moved normally (non-Advance)
- Assault keyword check must be case-insensitive

---

## Implementation Notes

### Flag Lifecycle
```
Movement Phase Start → Clear all movement flags
Advance Action → Set unit.flags.advanced = true
Shooting Phase → Check advanced flag for Assault restriction
Turn End → Flags persist until next Movement phase
```

### Interaction with Other Keywords
- **Assault + Pistol:** A weapon can have both. In Engagement Range after Advancing, check both.
- **Assault + Heavy:** A weapon can theoretically have both (rare). Assault allows shooting after Advance, Heavy gives +1 if stationary (mutually exclusive states).

### Edge Cases
1. **Mixed weapons:** Unit has Assault AND non-Assault weapons - only Assault available after Advance
2. **Attached characters:** Character's Assault weapons also fire after unit Advances
3. **Transport disembark + Advance:** If unit disembarks and transport Advances, check disembarked unit's own movement

### Testing Scenarios
1. Unit with Assault weapon Advances and shoots - should work
2. Unit with non-Assault weapon Advances and tries to shoot - should fail
3. Unit with mixed weapons Advances - only Assault weapons available
4. Unit moves normally (not Advance) - all weapons available

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/phases/MovementPhase.gd` | Ensure `advanced` flag is set on Advance |
| `40k/phases/ShootingPhase.gd` | Modify `_can_unit_shoot()`, add `_unit_has_assault_weapons()` |
| `40k/autoloads/RulesEngine.gd` | Add `is_assault_weapon()`, modify `validate_shoot()` |
| `40k/scripts/ShootingController.gd` | Update weapon tree display, filter weapons |

---

## Implementation Tasks

- [ ] Verify Movement phase sets `advanced` flag correctly
- [ ] Add `is_assault_weapon()` function to RulesEngine
- [ ] Add `_unit_has_assault_weapons()` helper to ShootingPhase
- [ ] Modify `_can_unit_shoot()` to allow shooting after Advance with Assault weapons
- [ ] Modify `validate_shoot()` to enforce Assault restriction
- [ ] Update ShootingController weapon tree to show Assault indicator [A]
- [ ] Update ShootingController to disable non-Assault weapons after Advance
- [ ] Add Assault keyword to appropriate weapon profiles in test data
- [ ] Add unit tests for Assault keyword behavior
- [ ] Test multiplayer sync
