# PRP-031: Critical Hit Tracking Infrastructure

## Context

Multiple weapon abilities (Lethal Hits, Sustained Hits, Devastating Wounds) require tracking Critical Hits and Critical Wounds - unmodified 6s on dice rolls. This infrastructure is needed before implementing those abilities.

**Severity:** HIGH - Blocks multiple features (PRP-010, PRP-011, PRP-012)

---

## Problem Statement

Currently, hit rolls are processed as simple pass/fail:
```gdscript
for roll in hit_rolls:
    var final_roll = modifier_result.modified_roll
    if final_roll >= bs:
        hits += 1  # No distinction between regular hits and crits
```

There's no tracking of:
- Unmodified roll value (before modifiers)
- Whether a hit was a Critical Hit (unmodified 6)
- Whether a wound was a Critical Wound (unmodified 6)

---

## Solution Overview

1. Store unmodified roll value alongside modified value
2. Track Critical Hits (unmodified 6 to hit) separately
3. Track Critical Wounds (unmodified 6 to wound) separately
4. Include crit counts in dice data structures
5. Provide helper functions for ability implementations

---

## Technical Requirements

### Definition
- **Critical Hit:** Unmodified hit roll of 6
- **Critical Wound:** Unmodified wound roll of 6
- "Unmodified" means the dice result BEFORE any +1/-1 modifiers

### Important Rule
A roll of 5 with +1 to hit = 6 modified, but is NOT a Critical Hit.
A roll of 6 with -1 to hit = 5 modified, but IS still a Critical Hit.

### Data Structure Changes

#### Dice Data Block
```gdscript
# Enhanced hit roll data
{
    "context": "hit_roll",
    "threshold": "3+",
    "rolls": [
        {"raw": 3, "modified": 4, "success": true, "critical": false},
        {"raw": 6, "modified": 7, "success": true, "critical": true},   # Crit!
        {"raw": 2, "modified": 3, "success": true, "critical": false},
        {"raw": 6, "modified": 5, "success": true, "critical": true},   # Crit (despite -1)
        {"raw": 1, "modified": 2, "success": false, "critical": false}
    ],
    "total_attacks": 5,
    "hits": 4,
    "critical_hits": 2,
    "regular_hits": 2
}

# Enhanced wound roll data
{
    "context": "wound_roll",
    "threshold": "4+",
    "rolls": [
        {"raw": 4, "modified": 4, "success": true, "critical": false},
        {"raw": 6, "modified": 6, "success": true, "critical": true},   # Crit!
        {"raw": 3, "modified": 3, "success": false, "critical": false}
    ],
    "total_wounds": 2,
    "critical_wounds": 1,
    "regular_wounds": 1
}
```

### Code Changes Required

#### `RulesEngine.gd`
```gdscript
# Enhanced hit roll processing
static func process_hit_rolls(
    rolls: Array,
    bs: int,
    hit_modifiers: int,
    rng: RNGService
) -> Dictionary:
    var result = {
        "hits": 0,
        "critical_hits": 0,
        "regular_hits": 0,
        "roll_details": []
    }

    for roll in rolls:
        var unmodified_roll = roll
        var modifier_result = apply_hit_modifiers(roll, hit_modifiers, rng)
        var final_roll = modifier_result.modified_roll

        var is_critical = (unmodified_roll == 6)
        var is_hit = (final_roll >= bs)

        result.roll_details.append({
            "raw": unmodified_roll,
            "modified": final_roll,
            "success": is_hit,
            "critical": is_critical and is_hit  # Only counts if it hits
        })

        if is_hit:
            result.hits += 1
            if is_critical:
                result.critical_hits += 1
            else:
                result.regular_hits += 1

    return result

# Enhanced wound roll processing
static func process_wound_rolls(
    rolls: Array,
    wound_threshold: int,
    wound_modifiers: int = 0  # Future expansion
) -> Dictionary:
    var result = {
        "wounds": 0,
        "critical_wounds": 0,
        "regular_wounds": 0,
        "roll_details": []
    }

    for roll in rolls:
        var unmodified_roll = roll
        var final_roll = roll + wound_modifiers  # Apply modifiers if any

        var is_critical = (unmodified_roll == 6)
        var is_wound = (final_roll >= wound_threshold)

        result.roll_details.append({
            "raw": unmodified_roll,
            "modified": final_roll,
            "success": is_wound,
            "critical": is_critical and is_wound
        })

        if is_wound:
            result.wounds += 1
            if is_critical:
                result.critical_wounds += 1
            else:
                result.regular_wounds += 1

    return result
```

---

## Acceptance Criteria

- [ ] Unmodified roll value tracked for all hit rolls
- [ ] Unmodified roll value tracked for all wound rolls
- [ ] Critical Hits (unmodified 6) counted separately
- [ ] Critical Wounds (unmodified 6) counted separately
- [ ] Modified 6 (from +1) correctly NOT counted as critical
- [ ] Unmodified 6 with -1 modifier correctly counted as critical
- [ ] Dice log shows critical hits highlighted
- [ ] Data structures support ability implementations

---

## Dice Log Display Enhancement

Show criticals distinctly:
```
Hit Roll: 5 attacks, BS 3+
[3] [6*] [2] [6*] [4]  (* = Critical)
4 hits (2 critical)
```

---

## Test Cases

| Roll | Modifier | BS | Result | Critical? |
|------|----------|-----|--------|-----------|
| 6 | +0 | 3+ | Hit | Yes |
| 6 | -1 | 3+ | Hit (5) | Yes |
| 5 | +1 | 3+ | Hit (6) | No |
| 6 | +0 | 4+ | Hit | Yes |
| 6 | +0 | 7+ | Miss | No (missed) |
| 1 | +0 | 3+ | Miss | No |

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Add `process_hit_rolls()`, `process_wound_rolls()`, modify resolution |
| `40k/scripts/ShootingController.gd` | Update dice log display for criticals |

---

## Dependencies

This PRP blocks:
- PRP-010 (Lethal Hits) - needs critical hit tracking
- PRP-011 (Sustained Hits) - needs critical hit tracking
- PRP-012 (Devastating Wounds) - needs critical wound tracking
- PRP-021 (Anti-X) - needs variable critical threshold

---

## Implementation Tasks

- [ ] Create `process_hit_rolls()` function
- [ ] Create `process_wound_rolls()` function
- [ ] Update dice data structures to include critical info
- [ ] Modify `_resolve_assignment_until_wounds()` to use new functions
- [ ] Update dice log to highlight critical rolls
- [ ] Add unit tests for critical tracking
- [ ] Test edge cases (modified 6 vs unmodified 6)
- [ ] Document data structures for ability implementers
