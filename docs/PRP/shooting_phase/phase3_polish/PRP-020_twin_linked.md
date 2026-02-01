# PRP-020: Twin-linked Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with the **TWIN-LINKED** ability allow the attacker to re-roll wound rolls. This represents paired or linked weapons that increase the chance of inflicting damage.

**Reference:** Wahapedia Core Rules - Weapon Abilities - TWIN-LINKED

---

## Problem Statement

Currently, there's no wound modifier system. Hit modifiers exist (re-roll 1s, +1/-1) but wound rolls have no equivalent system for re-rolls.

---

## Solution Overview

1. Create wound modifier system similar to hit modifiers
2. Twin-linked grants re-roll ALL failed wound rolls
3. Apply re-rolls after initial wound roll, before save resolution

---

## Technical Requirements

### 10th Edition Rules
1. TWIN-LINKED allows re-rolling ALL failed wound rolls (not just 1s)
2. Re-rolls happen before saving throws
3. Each failed wound roll can be re-rolled once

### Code Changes Required

```gdscript
# New wound modifier enum
enum WoundModifier {
    NONE = 0,
    REROLL_ALL = 1,      # Twin-linked
    REROLL_ONES = 2,     # Some abilities
    PLUS_ONE = 4,        # Lance, etc.
    MINUS_ONE = 8        # Some debuffs
}

static func is_twin_linked(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    var special_rules = profile.get("special_rules", "").to_lower()
    return "twin-linked" in special_rules or "twin linked" in special_rules
```

---

## Acceptance Criteria

- [ ] Twin-linked weapons can re-roll ALL failed wound rolls
- [ ] Re-rolls applied correctly (only once per roll)
- [ ] Dice log shows re-rolled wound values
- [ ] UI shows [TL] indicator

---

## Implementation Tasks

- [ ] Create WoundModifier enum
- [ ] Add `apply_wound_modifiers()` function
- [ ] Add `is_twin_linked()` function
- [ ] Modify wound roll to support re-rolls
- [ ] Update dice log display
- [ ] Add unit tests
