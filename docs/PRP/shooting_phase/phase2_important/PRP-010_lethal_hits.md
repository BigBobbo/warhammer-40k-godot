# PRP-010: Lethal Hits Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **LETHAL HITS** ability cause Critical Hits (unmodified 6s to hit) to automatically wound without needing to roll to wound. This is a powerful ability that bypasses the wound roll entirely.

**Reference:** Wahapedia Core Rules - Weapon Abilities - LETHAL HITS

---

## Problem Statement

Currently, the shooting phase does not track Critical Hits (unmodified 6s). All successful hits proceed to wound rolls regardless of the original roll value. There's no mechanism to auto-wound on critical hits.

**Dependency:** Requires PRP-031 (Critical Hit Tracking) to be implemented first.

---

## Solution Overview

Implement Lethal Hits that:
1. Tracks unmodified 6s on hit rolls separately from regular hits
2. For Lethal Hits weapons, critical hits skip the wound roll and count as automatic wounds
3. Regular hits still proceed to normal wound rolls
4. Shows Lethal Hits wounds clearly in dice log

---

## User Stories

- **US1:** As a player with Lethal Hits weapons, I want my critical hits to auto-wound so that I'm rewarded for rolling well.
- **US2:** As a player, I want to see which wounds came from Lethal Hits vs normal wound rolls so I understand the results.
- **US3:** As a player, I want Lethal Hits to interact correctly with other abilities (like Sustained Hits).

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Critical Hit = unmodified hit roll of 6 (before any modifiers)
2. With Lethal Hits, Critical Hits automatically wound (no wound roll needed)
3. The attack still proceeds to saving throw normally
4. Lethal Hits wounds are NOT mortal wounds (they can still be saved)
5. If a weapon has both Sustained Hits and Lethal Hits, the extra hits from Sustained also need separate wound rolls

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Check if weapon has Lethal Hits
static func has_lethal_hits(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    if "lethal hits" in special_rules:
        return true

    for keyword in keywords:
        if "lethal hits" in keyword.to_lower():
            return true

    return false

# Modified hit roll resolution
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # Roll hits and track critical hits separately
    var hit_rolls = rng.roll_d6(total_attacks)
    var regular_hits = 0
    var critical_hits = 0

    for roll in hit_rolls:
        var unmodified_roll = roll  # Store before modification
        var modifier_result = apply_hit_modifiers(roll, hit_modifiers, rng)
        var final_roll = modifier_result.modified_roll

        if final_roll >= bs:
            # It's a hit - but was it a critical?
            if unmodified_roll == 6:
                critical_hits += 1
            else:
                regular_hits += 1

    # Process wounds
    var auto_wounds = 0  # From Lethal Hits
    var wounds_from_rolls = 0

    if has_lethal_hits(weapon_id, board):
        # Critical hits auto-wound
        auto_wounds = critical_hits
        # Only roll wounds for regular hits
        if regular_hits > 0:
            var wound_rolls = rng.roll_d6(regular_hits)
            for roll in wound_rolls:
                if roll >= wound_threshold:
                    wounds_from_rolls += 1
    else:
        # Normal processing - all hits roll to wound
        var total_hits = regular_hits + critical_hits
        if total_hits > 0:
            var wound_rolls = rng.roll_d6(total_hits)
            for roll in wound_rolls:
                if roll >= wound_threshold:
                    wounds_from_rolls += 1

    var total_wounds = auto_wounds + wounds_from_rolls
    # ... continue to save resolution ...
```

---

## Acceptance Criteria

- [ ] Critical hits (unmodified 6s) are tracked separately
- [ ] Lethal Hits weapons auto-wound on critical hits
- [ ] Regular hits still roll to wound normally
- [ ] Dice log shows "Lethal Hits: X auto-wounds"
- [ ] Lethal Hits wounds proceed to saves normally (not mortal wounds)
- [ ] UI shows [LH] indicator for Lethal Hits weapons
- [ ] Works correctly with Sustained Hits (extra hits still need wound rolls)
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must track UNMODIFIED roll (before any +1/-1 modifiers)
- Must not be confused with mortal wounds (these are regular wounds)
- Requires PRP-031 (Critical Hit Tracking) infrastructure

---

## Implementation Notes

### Critical Hit Tracking
Track the unmodified roll separately:
```gdscript
# In dice data structure
{
    "context": "hit_roll",
    "rolls_raw": [3, 6, 2, 6, 4],      # Unmodified rolls
    "rolls_modified": [4, 7, 3, 7, 5],  # After modifiers
    "critical_hits": 2,                  # Count of unmodified 6s
    "regular_hits": 1,                   # Non-critical successes
    "successes": 3                       # Total hits
}
```

### Interaction with Other Abilities
| Ability Combo | Behavior |
|---------------|----------|
| Lethal Hits + Sustained Hits 1 | Crit 6: auto-wound + 1 extra hit (rolls to wound) |
| Lethal Hits + Anti-X | Crit wound on Anti roll OR Lethal Hit crit |
| Lethal Hits + Twin-linked | Re-roll wounds only for non-Lethal hits |

### Edge Cases
1. **Modified 6:** A roll of 5 with +1 to hit = 6, but NOT a critical (unmodified was 5)
2. **All criticals:** If all hits are critical, no wound roll is made at all
3. **Variable attacks:** Critical tracking works same way for D6 attacks

### Testing Scenarios
1. Roll 5 attacks, get two 6s → 2 auto-wounds + roll for other hits
2. Roll 5 attacks, all hits are 6s → 5 auto-wounds, no wound roll
3. Non-Lethal Hits weapon, roll 6s → normal wound rolls

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `has_lethal_hits()`, modify hit/wound resolution |
| `40k/scripts/ShootingController.gd` | Show [LH] indicator |

---

## Dependencies

- **PRP-031 (Critical Hit Tracking):** Must be implemented first to track unmodified 6s

---

## Implementation Tasks

- [ ] Implement PRP-031 (Critical Hit Tracking) first
- [ ] Add `has_lethal_hits()` function to RulesEngine
- [ ] Modify hit roll to track critical vs regular hits
- [ ] Modify wound roll to skip for Lethal Hits critical hits
- [ ] Update dice log to show Lethal Hits auto-wounds
- [ ] Add Lethal Hits to test weapon profiles
- [ ] Update weapon tree UI to show [LH] indicator
- [ ] Test interaction with Sustained Hits
- [ ] Add unit tests
- [ ] Test multiplayer sync
