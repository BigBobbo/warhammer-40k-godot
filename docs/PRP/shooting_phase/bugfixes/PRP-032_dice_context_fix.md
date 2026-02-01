# PRP-032: Dice Context Mismatch Fix

## Context

There's a mismatch between dice context strings used in RulesEngine and expected by ShootingPhase/Controller, which may cause display issues.

**Severity:** MEDIUM - May cause UI display issues

---

## Problem Statement

RulesEngine uses:
```gdscript
result.dice.append({
    "context": "to_hit",     # Line 299
    "context": "to_wound",   # Line 323
})
```

But some UI code expects:
```gdscript
if dice.context == "hit_roll":
    # Display hit roll
if dice.context == "wound_roll":
    # Display wound roll
```

This inconsistency can cause dice logs to display incorrectly.

---

## Solution Overview

1. Audit all dice context strings across codebase
2. Standardize on consistent naming convention
3. Update all producers and consumers

---

## Recommended Standard

Use consistent snake_case context names:
- `"hit_roll"` - Hit roll dice
- `"wound_roll"` - Wound roll dice
- `"save_roll"` - Save roll dice
- `"damage_roll"` - Variable damage roll (D6, D3)
- `"charge_roll"` - Charge distance roll
- `"auto_hit"` - Torrent/auto-hit (no dice shown)
- `"hazardous_roll"` - Hazardous check

---

## Files to Audit

| File | Context |
|------|---------|
| `RulesEngine.gd` | Producer - creates dice blocks |
| `ShootingPhase.gd` | May reference contexts |
| `ShootingController.gd` | Consumer - displays dice |
| `SaveDialog.gd` | Consumer - displays save rolls |
| `FightController.gd` | Producer/Consumer for melee |

---

## Implementation Tasks

- [ ] Grep for all "context" dice references
- [ ] Create list of all unique context strings
- [ ] Define standard context names
- [ ] Update RulesEngine to use standard names
- [ ] Update all consumers to match
- [ ] Add constants for context names
- [ ] Add unit tests to verify contexts
