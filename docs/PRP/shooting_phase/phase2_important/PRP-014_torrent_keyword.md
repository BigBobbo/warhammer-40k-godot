# PRP-014: Torrent Weapon Keyword

## Context

In Warhammer 40K 10th Edition, weapons with the **TORRENT** keyword automatically hit their targets without needing to roll to hit. This represents weapons like flamers that engulf an area regardless of the user's accuracy.

**Reference:** Wahapedia Core Rules - Weapon Abilities - TORRENT

---

## Problem Statement

Currently, all shooting attacks roll to hit using the weapon's BS characteristic. There's no mechanism to skip the hit roll entirely for weapons that automatically hit.

---

## Solution Overview

Implement the TORRENT keyword that:
1. Skips the hit roll phase entirely for Torrent weapons
2. All attacks count as hits and proceed directly to wound rolls
3. Shows auto-hit status in UI and dice log
4. Works with other attack modifiers appropriately

---

## User Stories

- **US1:** As a player with Torrent weapons, I want my attacks to auto-hit so that flamers and similar weapons work as intended.
- **US2:** As a player, I want the dice log to clearly show that hits were automatic, not rolled.
- **US3:** As a player, I want Torrent to interact correctly with abilities that trigger on hit rolls.

---

## Technical Requirements

### 10th Edition Rules (Exact)
1. Weapons with TORRENT automatically hit - no hit roll is made
2. All attacks proceed directly to the wound roll
3. Since no hit roll is made, abilities that trigger on hit rolls (Lethal Hits, Sustained Hits) do NOT apply
4. Modifiers to hit (like Heavy, cover penalty) are irrelevant

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Check if weapon has Torrent
static func is_torrent_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    var keywords = profile.get("keywords", [])

    if "torrent" in special_rules:
        return true

    for keyword in keywords:
        if keyword.to_upper() == "TORRENT":
            return true

    return false

# Modified attack resolution
static func _resolve_assignment_until_wounds(...) -> Dictionary:
    # Calculate total attacks
    var attacks_per_model = weapon_profile.get("attacks", 1)
    var total_attacks = model_ids.size() * attacks_per_model

    # Check for Torrent - skip hit roll
    if is_torrent_weapon(weapon_id, board):
        # All attacks auto-hit
        var total_hits = total_attacks

        result.dice.append({
            "context": "auto_hit",
            "total_attacks": total_attacks,
            "successes": total_hits,
            "message": "Torrent: %d automatic hits" % total_hits
        })

        # Skip to wound rolls (no critical hits possible)
        var wound_rolls = rng.roll_d6(total_hits)
        var wounds_caused = 0
        for roll in wound_rolls:
            if roll >= wound_threshold:
                wounds_caused += 1

        # ... continue with wound processing ...
    else:
        # Normal hit roll processing
        var hit_rolls = rng.roll_d6(total_attacks)
        # ... existing hit roll logic ...
```

---

## Acceptance Criteria

- [ ] Torrent weapons skip the hit roll entirely
- [ ] All attacks count as automatic hits
- [ ] Dice log shows "Torrent: X automatic hits" instead of hit rolls
- [ ] Lethal Hits/Sustained Hits do NOT trigger (no hit roll = no crits)
- [ ] Hit modifiers (+1/-1) are ignored for Torrent weapons
- [ ] UI shows [T] indicator for Torrent weapons
- [ ] Wound rolls proceed normally
- [ ] Multiplayer sync works correctly

---

## Constraints

- Must match WH40K 10th Edition rules exactly
- No hit roll means no critical hits
- Must clearly communicate auto-hit in UI
- Works with other keywords (Blast, Twin-linked, etc.)

---

## Implementation Notes

### No Critical Hits
Important: Since Torrent weapons don't roll to hit:
- **Lethal Hits:** Cannot trigger (no hit roll)
- **Sustained Hits:** Cannot trigger (no hit roll)
- **Heavy:** Irrelevant (+1 to non-existent hit roll)
- **Assault:** Irrelevant (can still fire after advancing normally)

### Wound Roll Criticals
Critical wounds (unmodified 6s) CAN still happen on wound rolls:
- **Devastating Wounds:** CAN trigger from wound roll criticals
- **Anti-X:** CAN trigger from wound roll

### Common Torrent Weapons
- Flamers (Heavy Flamer, Flamer, etc.)
- Some plasma weapons in "supercharge" mode
- Spray weapons (Acid Spray, etc.)

### Dice Log Display
```
== ATTACK RESOLUTION ==
Flamer vs Ork Boyz
Attacks: 6 (automatic - Torrent)
Wound Roll: 6 attacks, S4 vs T4, need 4+
Rolls: [3, 5, 6, 2, 4, 5] → 4 wounds
```

### Edge Cases
1. **Variable attacks:** D6 attacks still roll for number of attacks, then all auto-hit
2. **Blast + Torrent:** Rare combo. Blast bonus applies, then all auto-hit
3. **Overwatch:** Torrent still auto-hits on overwatch (unlike normal weapons)

### Testing Scenarios
1. Flamer (Torrent, D6 attacks) → roll D6 for attacks, all auto-hit
2. Flamer with Lethal Hits → Lethal Hits doesn't trigger (no hit roll)
3. Flamer with Devastating Wounds → DW can trigger on wound roll
4. Heavy Flamer (Heavy, Torrent) → +1 to hit is irrelevant

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `is_torrent_weapon()`, modify attack resolution |
| `40k/scripts/ShootingController.gd` | Show [T] indicator, update dice log display |

---

## Implementation Tasks

- [ ] Add `is_torrent_weapon()` function to RulesEngine
- [ ] Modify attack resolution to skip hit roll for Torrent
- [ ] Add "auto_hit" dice log context
- [ ] Update dice log display for Torrent weapons
- [ ] Ensure Lethal/Sustained Hits don't trigger for Torrent
- [ ] Add Torrent keyword to flamer weapon profiles
- [ ] Update weapon tree UI to show [T] indicator
- [ ] Add unit tests for Torrent behavior
- [ ] Test interaction with other keywords
- [ ] Test multiplayer sync
