# PRP-042: Target Validation Indicators

## Context

Currently, all eligible targets are shown the same way. Players can't quickly see which weapons can reach which targets without trying each combination.

**Priority:** MEDIUM - Tactical decision improvement

---

## Problem Statement

When selecting targets:
- All eligible targets highlighted same color
- No indication of which weapons can reach each target
- Range differences not visualized
- Must click weapon + target to check validity

---

## Solution Overview

Color-code targets based on weapon compatibility:
1. **Green:** All selected weapons can target
2. **Yellow:** Some weapons can target (range/LoS issues for others)
3. **Red outline:** No weapons can target (shouldn't appear but failsafe)

Show weapon-specific range circles on board.

---

## User Stories

- **US1:** As a player, I want to see which targets my longest-range weapon can hit at a glance.
- **US2:** As a player, I want to know if splitting fire is necessary due to range.
- **US3:** As a player, I want visual range indicators on the board.

---

## Technical Requirements

### Target Highlighting
```gdscript
enum TargetStatus {
    ALL_WEAPONS,      # Green - all weapons can target
    SOME_WEAPONS,     # Yellow - partial coverage
    SELECTED_WEAPON,  # Bright green - current weapon's targets
    ASSIGNED          # Blue - already assigned a weapon
}
```

### Range Circle Visualization
- Show concentric circles for different weapon ranges
- Color-coded by weapon type
- Highlight half-range for Rapid Fire/Melta

### Board Visual Enhancements
```gdscript
# ShootingController.gd

func _update_target_highlights() -> void:
    for target_id in eligible_targets:
        var status = _get_target_status(target_id)
        match status:
            TargetStatus.ALL_WEAPONS:
                _highlight_target(target_id, Color.GREEN)
            TargetStatus.SOME_WEAPONS:
                _highlight_target(target_id, Color.YELLOW)
            TargetStatus.ASSIGNED:
                _highlight_target(target_id, Color.CYAN)
```

---

## Acceptance Criteria

- [ ] Targets color-coded by weapon coverage
- [ ] Range circles shown for selected weapon
- [ ] Half-range indicator for Rapid Fire/Melta
- [ ] Clear visual distinction between coverage levels
- [ ] Updates dynamically as weapons are assigned
- [ ] Legend/key for colors (optional)

---

## UI Mockup

```
Board View:
  [Shooter]
      |
      +-- 12" (inner circle, Rapid Fire range)
      |
      +-- 24" (outer circle, full range)

Target A: GREEN (in 24")
Target B: YELLOW (only pistol range)
Target C: CYAN (bolt rifle assigned)
```

---

## Implementation Tasks

- [ ] Create `_get_target_status()` function
- [ ] Update `_highlight_target()` with status colors
- [ ] Add concentric range circles to range_visual
- [ ] Show half-range circle differently (dashed?)
- [ ] Update highlighting on weapon selection change
- [ ] Update highlighting on assignment change
- [ ] Add color legend to UI (optional)
- [ ] Test with various weapon combinations
