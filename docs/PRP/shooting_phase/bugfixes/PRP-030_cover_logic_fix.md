# PRP-030: Cover Logic Bug Fix

## Context

The cover system has incorrect logic that prevents 3+ saves from benefiting from cover against AP 0 weapons. This doesn't match 10th edition rules.

**Severity:** HIGH - Affects all combat with cover

---

## Problem Statement

In `RulesEngine.gd` lines 639-642:
```gdscript
if has_cover and ap == 0 and base_save <= 3:
    has_cover = false  # This removes cover for 3+ saves vs AP0
```

This is INCORRECT. In 10th edition:
- Cover gives +1 to save (e.g., 3+ becomes 2+)
- This benefit is NOT restricted by save value
- The only restriction is the +1 cap (can't stack multiple cover sources)

---

## Solution Overview

1. Remove the incorrect cover restriction
2. Properly apply cover as +1 to save
3. Respect the +1 maximum cap
4. Ensure 2+ is the best possible save

---

## Technical Requirements

### 10th Edition Cover Rules
1. Benefit of Cover: +1 to saving throws
2. Maximum save improvement: +1 (from all sources combined)
3. Saves cannot be better than 2+
4. Cover affects armour saves, not invulnerable saves
5. Cover applies regardless of AP value or base save

### Current Code (INCORRECT)
```gdscript
static func _calculate_save_needed(base_save: int, ap: int, has_cover: bool, invuln: int) -> Dictionary:
    var armour_save = base_save + ap  # AP makes saves worse

    # BUG: This incorrectly prevents 3+ saves from getting cover vs AP0
    if has_cover and ap == 0 and base_save <= 3:
        has_cover = false  # WRONG - remove this

    if has_cover:
        armour_save -= 1  # Cover improves save by 1

    # ... rest of function
```

### Corrected Code
```gdscript
static func _calculate_save_needed(base_save: int, ap: int, has_cover: bool, invuln: int) -> Dictionary:
    # Step 1: Apply AP to base save
    var modified_save = base_save + ap  # AP makes saves worse (AP is negative, so + makes higher)

    # Step 2: Apply cover bonus (+1 to save = -1 to required roll)
    if has_cover:
        modified_save -= 1

    # Step 3: Cap improvement at +1 from base
    # (Only relevant if multiple cover sources existed)
    var max_improvement = 1
    var min_save = base_save - max_improvement
    modified_save = max(modified_save, min_save)

    # Step 4: Saves can never be better than 2+
    modified_save = max(2, modified_save)

    # Step 5: Check invulnerable save
    var use_invuln = false
    if invuln > 0 and invuln < modified_save:
        use_invuln = true

    return {
        "armour": modified_save,
        "inv": invuln if invuln > 0 else 99,
        "use_invuln": use_invuln,
        "cover_applied": has_cover
    }
```

---

## Acceptance Criteria

- [ ] 3+ saves benefit from cover (+1) against all AP values
- [ ] 4+, 5+, 6+ saves benefit from cover against all AP values
- [ ] Cover improvement capped at +1 total
- [ ] Saves cannot be better than 2+
- [ ] AP 0 attacks are correctly affected by cover
- [ ] High AP attacks correctly reduce cover benefit
- [ ] Dice log shows cover status correctly
- [ ] No regression in existing save mechanics

---

## Test Cases

| Base Save | AP | Cover | Expected Save |
|-----------|-----|-------|---------------|
| 3+ | 0 | Yes | 2+ |
| 3+ | -1 | Yes | 3+ (AP-1 + cover = net 0) |
| 3+ | -2 | Yes | 4+ (AP-2 + cover = net -1) |
| 4+ | 0 | Yes | 3+ |
| 6+ | 0 | Yes | 5+ |
| 2+ | 0 | Yes | 2+ (can't go below 2+) |
| 3+ | 0 | No | 3+ |

---

## Related Files

| File | Changes Required |
|------|------------------|
| `40k/autoloads/RulesEngine.gd` | Fix `_calculate_save_needed()` |

---

## Implementation Tasks

- [ ] Remove incorrect cover restriction (lines 639-642)
- [ ] Verify cover +1 applies correctly
- [ ] Ensure 2+ minimum save
- [ ] Add comprehensive unit tests for cover scenarios
- [ ] Test with various AP values
- [ ] Verify dice log shows correct save values
