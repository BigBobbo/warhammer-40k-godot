# PRP-026: Precision Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with **PRECISION** allow the attacker to allocate successful wounds to visible CHARACTER models, bypassing normal wound allocation rules.

**Reference:** Wahapedia Core Rules - Weapon Abilities - PRECISION

---

## Problem Statement

Currently, wound allocation follows standard rules (wounded models first, then player choice). There's no mechanism to target specific models like attached Characters.

---

## Solution Overview

1. For Precision weapons, on Critical Hits (6s), attacker can allocate wounds to visible Character
2. Bypasses "Look Out Sir" / Lone Operative protections
3. Requires Character targeting UI

---

## Technical Requirements

### 10th Edition Rules
1. On Critical Hit (unmodified 6), wounds can be allocated to a visible CHARACTER
2. Bypasses wound allocation priorities
3. Only affects wound allocation, not targeting
4. Attacker chooses which model receives the wound

### Code Changes Required

```gdscript
static func has_precision(weapon_id: String, board: Dictionary = {}) -> bool:
    var profile = get_weapon_profile(weapon_id, board)
    return "precision" in profile.get("special_rules", "").to_lower()

# In save data, include precision wound options
var save_data = {
    # ... existing fields ...
    "precision_wounds": precision_hit_count,  # Critical hits from Precision weapons
    "character_models": _get_visible_characters(target_unit)  # Valid Precision targets
}
```

---

## Acceptance Criteria

- [ ] Precision weapons can allocate wounds to Characters on Critical Hits
- [ ] Only critical hits enable Precision allocation
- [ ] UI shows Character model options for Precision wounds
- [ ] UI shows [P] indicator

---

## Implementation Tasks

- [ ] Add `has_precision()` function
- [ ] Track critical hits for Precision separately
- [ ] Add Character detection in target units
- [ ] Add Precision allocation UI in SaveDialog
- [ ] Add unit tests
