# PRP-021: Anti-X Weapon Ability

## Context

In Warhammer 40K 10th Edition, weapons with **ANTI-X Y+** (e.g., Anti-Vehicle 4+, Anti-Infantry 2+) score Critical Wounds against targets with the specified keyword on wound rolls of Y+.

**Reference:** Wahapedia Core Rules - Weapon Abilities - ANTI-

---

## Problem Statement

Currently, Critical Wounds only occur on unmodified 6s. There's no mechanism to lower the critical threshold based on target keywords.

**Dependency:** Requires PRP-012 (Devastating Wounds) or critical wound infrastructure.

---

## Solution Overview

1. Parse Anti-X Y+ from weapon profile
2. Check target unit for matching keyword
3. If matched, Critical Wounds trigger on Y+ instead of 6+
4. Works with Devastating Wounds to bypass saves

---

## Technical Requirements

### 10th Edition Rules
1. Anti-X Y+ lowers Critical Wound threshold to Y+ vs targets with keyword X
2. Common patterns: Anti-Vehicle 4+, Anti-Infantry 4+, Anti-Monster 4+
3. Critical Wounds from Anti- can trigger Devastating Wounds
4. Multiple Anti- abilities can apply (use best)

### Code Changes Required

```gdscript
# Parse Anti-X abilities
static func get_anti_abilities(weapon_id: String, board: Dictionary = {}) -> Array:
    # Returns: [{keyword: "VEHICLE", threshold: 4}, {keyword: "INFANTRY", threshold: 4}]
    var abilities = []
    var regex = RegEx.new()
    regex.compile("anti-(\\w+) (\\d+)\\+")
    # ... parse special_rules ...
    return abilities

# Check critical wound threshold
static func get_critical_wound_threshold(weapon_id: String, target_unit: Dictionary, board: Dictionary) -> int:
    var anti_abilities = get_anti_abilities(weapon_id, board)
    var target_keywords = target_unit.get("meta", {}).get("keywords", [])

    var threshold = 6  # Default critical on 6
    for anti in anti_abilities:
        if anti.keyword.to_upper() in target_keywords:
            threshold = min(threshold, anti.threshold)

    return threshold
```

---

## Acceptance Criteria

- [ ] Anti-X Y+ triggers critical wounds on Y+ vs matching targets
- [ ] Keywords checked case-insensitively
- [ ] Multiple Anti- abilities use best threshold
- [ ] Works with Devastating Wounds
- [ ] UI shows [Anti-X Y+] indicator

---

## Implementation Tasks

- [ ] Add `get_anti_abilities()` function
- [ ] Add `get_critical_wound_threshold()` function
- [ ] Modify wound roll to use variable critical threshold
- [ ] Update dice log to show Anti- triggers
- [ ] Add unit tests for various Anti- combinations
