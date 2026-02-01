# PRP-040: Quick Assign All Weapons to Target

## Context

Currently, assigning weapons to targets requires multiple clicks - select weapon, click target, repeat for each weapon type. This is tedious for units with multiple identical weapons.

**Priority:** HIGH - Major usability improvement

---

## Problem Statement

Current flow:
1. Select shooter
2. Click first weapon type → click target
3. Click second weapon type → click target
4. Click third weapon type → click target
5. Confirm

For a 5-man squad with bolt rifles, this requires 10+ clicks to assign all weapons to one target.

---

## Solution Overview

Add "Assign All to Target" functionality:
1. After first weapon assignment, show quick-assign button
2. One click assigns ALL remaining weapons to same target
3. Alternative: Click target while holding Shift to auto-assign all

---

## User Stories

- **US1:** As a player, I want to quickly assign all weapons to one target when facing a single enemy unit.
- **US2:** As a player, I want a keyboard shortcut to speed up weapon assignment.
- **US3:** As a player, I still want the option to split fire when needed.

---

## Technical Requirements

### UI Changes
1. **"Assign All" Button:**
   - Appears after first weapon is assigned
   - Shows target name: "Assign All → Ork Boyz"
   - One click assigns all unassigned weapons to that target

2. **Shift+Click Target:**
   - Hold Shift + click target = assign ALL weapons
   - Normal click = assign selected weapon only

3. **Double-click Target:**
   - Alternative: Double-click target to assign all

### Code Changes

```gdscript
# ShootingController.gd

func _on_target_clicked(target_unit_id: String) -> void:
    if Input.is_key_pressed(KEY_SHIFT):
        _assign_all_weapons_to_target(target_unit_id)
    else:
        _assign_selected_weapon_to_target(target_unit_id)

func _assign_all_weapons_to_target(target_unit_id: String) -> void:
    var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)

    for model_id in unit_weapons:
        for weapon_id in unit_weapons[model_id]:
            if not weapon_assignments.has(weapon_id):
                # Check if weapon can target this unit
                var can_target = _can_weapon_target(weapon_id, target_unit_id)
                if can_target:
                    _send_assign_action(weapon_id, target_unit_id, [model_id])
```

---

## Acceptance Criteria

- [ ] "Assign All" button appears after first assignment
- [ ] Button assigns all unassigned weapons to last target
- [ ] Shift+click assigns all weapons to clicked target
- [ ] Weapons that can't reach target are skipped (out of range)
- [ ] UI updates to show all assignments
- [ ] Can still split fire with normal clicks
- [ ] Clear feedback when using quick-assign

---

## UI Mockup

```
┌─ Shooting Controls ─────────────────┐
│ Shooter: Intercessor Squad          │
├─────────────────────────────────────┤
│ Weapon Assignments:                 │
│ ┌───────────────────────────────┐   │
│ │ Bolt Rifle (5) → Ork Boyz    │   │
│ │ Plasma Pistol → [unassigned]  │   │
│ └───────────────────────────────┘   │
│                                     │
│ [Assign All → Ork Boyz]  ← NEW     │
│                                     │
│ [Clear All] [Confirm Targets]       │
└─────────────────────────────────────┘
```

---

## Implementation Tasks

- [ ] Add "Assign All" button to ShootingController UI
- [ ] Implement `_assign_all_weapons_to_target()` function
- [ ] Add Shift+click detection to target selection
- [ ] Update button text with target name
- [ ] Skip weapons out of range/LoS
- [ ] Add visual feedback for quick-assign
- [ ] Test with multi-weapon units
- [ ] Test with split-fire scenarios
