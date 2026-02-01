# PRP-011: Sustained Hits Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **SUSTAINED HITS X** ability generate X additional hits on Critical Hits (unmodified 6s to hit). This represents weapons that become more deadly when they find their mark perfectly.

**Reference:** Wahapedia Core Rules - Weapon Abilities - SUSTAINED HITS

---

## Problem Statement

Currently, the shooting phase counts hits as a simple pass/fail check. There's no mechanism to generate additional hits from critical rolls, and Critical Hit tracking is not implemented.

**Dependency:** Requires PRP-031 (Critical Hit Tracking) to be implemented first.

---

## Solution Overview

Implement Sustained Hits that:
1. Tracks unmodified 6s on hit rolls
2. For Sustained Hits X weapons, each critical hit generates X additional hits
3. All hits (original + sustained) proceed to wound rolls
4. Shows Sustained Hits bonus clearly in dice log

---

## User Stories

- **US1:** As a player with Sustained Hits weapons, I want to generate extra hits on critical rolls so that my attacks become more dangerous.
- **US2:** As a player, I want to see how many bonus hits I got from Sustained Hits in the dice log.
- **US3:** As a player, I want Sustained Hits to work correctly with Lethal Hits.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Critical Hit = unmodified hit roll of 6 (before any modifiers)
2. With Sustained Hits X, each Critical Hit scores X additional hits
3. The additional hits automatically hit (no roll needed for them)
4. All hits (original + sustained) must roll to wound
5. Common values: Sustained Hits 1, Sustained Hits 2, Sustained Hits D3

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Parse Sustained Hits value
static func get_sustained_hits_value(weapon_id: String, board: Dictionary = {}) -> Dictionary:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    # Check for "Sustained Hits X" or "Sustained Hits D3"
    var regex = RegEx.new()
    regex.compile("sustained hits (d?\\d+)")

    var result = regex.search(special_rules)
    if result:
        return _parse_sustained_hits_value(result.get_string(1))

    for keyword in keywords:
        result = regex.search(keyword.to_lower())
        if result:
            return _parse_sustained_hits_value(result.get_string(1))

    return {"value": 0, "is_dice": false}

static func _parse_sustained_hits_value(value_str: String) -> Dictionary:
    if value_str.begins_with("d"):
        return {"value": value_str.to_int(), "is_dice": true}  # D3, D6
    else:
        return {"value": value_str.to_int(), "is_dice": false}  # 1, 2, etc.

# Modified hit roll resolution
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    var hit_rolls = rng.roll_d6(total_attacks)
    var hits = 0
    var critical_hits = 0
    var sustained_bonus_hits = 0

    var sustained = get_sustained_hits_value(weapon_id, board)

    for roll in hit_rolls:
        var unmodified_roll = roll
        var modifier_result = apply_hit_modifiers(roll, hit_modifiers, rng)
        var final_roll = modifier_result.modified_roll

        if final_roll >= bs:
            hits += 1
            if unmodified_roll == 6:
                critical_hits += 1
                # Generate Sustained Hits bonus
                if sustained.value > 0:
                    var bonus = sustained.value
                    if sustained.is_dice:
                        # Roll for variable sustained hits (e.g., D3)
                        bonus = rng.roll_d6(1)[0]
                        if sustained.value == 3:  # D3
                            bonus = (bonus + 1) / 2  # Convert D6 to D3
                    sustained_bonus_hits += bonus

    var total_hits_for_wounds = hits + sustained_bonus_hits

    # Record in dice data
    result.dice.append({
        "context": "hit_roll",
        "rolls_raw": hit_rolls,
        "successes": hits,
        "critical_hits": critical_hits,
        "sustained_bonus": sustained_bonus_hits,
        "total_for_wounds": total_hits_for_wounds
    })

    # All hits roll to wound
    if total_hits_for_wounds > 0:
        var wound_rolls = rng.roll_d6(total_hits_for_wounds)
        # ... wound processing ...
```

---

## Acceptance Criteria

- [ ] Critical hits (unmodified 6s) generate bonus hits
- [ ] Sustained Hits X generates exactly X bonus hits per critical
- [ ] Sustained Hits D3 rolls for each critical
- [ ] All hits (original + sustained) roll to wound
- [ ] Dice log shows "Sustained Hits: +X bonus hits"
- [ ] UI shows [SH X] indicator for Sustained Hits weapons
- [ ] Works correctly with Lethal Hits (sustain hits still wound normally)
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- Must track UNMODIFIED roll (before modifiers)
- Bonus hits auto-hit but must roll to wound
- Requires PRP-031 (Critical Hit Tracking) infrastructure

---

## Implementation Notes

### Variable Sustained Hits
Some weapons have variable values:
- **Sustained Hits 1:** +1 hit per crit (most common)
- **Sustained Hits 2:** +2 hits per crit
- **Sustained Hits D3:** Roll D3 per crit (treat as 1-3)

### Interaction with Lethal Hits
When weapon has both Sustained Hits and Lethal Hits:
1. Critical hit triggers BOTH abilities
2. The original critical hit auto-wounds (Lethal Hits)
3. The bonus hits from Sustained Hits roll to wound normally

Example: Weapon with Sustained Hits 1 + Lethal Hits
- Roll 6 (crit) → 1 auto-wound + 1 bonus hit that rolls to wound
- Roll 4 (regular hit) → 1 wound roll

### Dice Log Display
```
Hit Roll: 5 attacks, BS 3+
Rolls: [3, 6, 2, 6, 4] → 3 hits (2 critical)
Sustained Hits: +2 bonus hits
Total hits for wound roll: 5
```

### Edge Cases
1. **All misses:** No sustained hits generated
2. **Modified 6:** Roll of 5 with +1 = 6 modified, but NOT critical
3. **Multiple criticals:** Each generates its own sustained hits

### Testing Scenarios
1. Sustained Hits 1, roll two 6s → 2 regular hits + 2 sustained hits = 4 wound rolls
2. Sustained Hits 2, roll one 6 → 1 regular hit + 2 sustained hits = 3 wound rolls
3. Non-Sustained weapon, roll 6s → normal hit count only

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `get_sustained_hits_value()`, modify hit processing |
| `40k/scripts/ShootingController.gd` | Show [SH X] indicator |

---

## Dependencies

- **PRP-031 (Critical Hit Tracking):** Must be implemented first

---

## Implementation Tasks

- [ ] Implement PRP-031 (Critical Hit Tracking) first
- [ ] Add `get_sustained_hits_value()` function to RulesEngine
- [ ] Modify hit roll to generate sustained hits on criticals
- [ ] Handle variable sustained hits (D3, D6)
- [ ] Update dice log to show sustained hits bonus
- [ ] Add Sustained Hits to test weapon profiles
- [ ] Update weapon tree UI to show [SH X] indicator
- [ ] Test interaction with Lethal Hits
- [ ] Add unit tests
- [ ] Test multiplayer sync
