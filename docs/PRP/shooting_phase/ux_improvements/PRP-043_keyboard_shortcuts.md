# PRP-043: Keyboard Shortcuts for Shooting

## Context

The shooting phase is entirely mouse-driven. Keyboard shortcuts would speed up common actions for experienced players.

**Priority:** LOW - Quality of life improvement

---

## Problem Statement

Current input methods:
- Mouse only for all interactions
- No keyboard shortcuts
- Slower than necessary for experienced players

---

## Solution Overview

Add keyboard shortcuts for common shooting actions:
- Number keys to select targets
- Enter to confirm
- Escape to cancel/clear
- Tab to cycle weapons
- Shift+click for quick-assign (see PRP-040)

---

## Proposed Shortcuts

| Key | Action |
|-----|--------|
| `1-9` | Select target by number (shown in UI) |
| `Enter` | Confirm targets / Continue |
| `Escape` | Clear current selection |
| `Tab` | Cycle to next weapon |
| `Shift+Tab` | Cycle to previous weapon |
| `Space` | Assign current weapon to current target |
| `A` | Assign all weapons to current target |
| `C` | Clear all assignments |
| `S` | Skip unit (end shooting for this unit) |
| `E` | End shooting phase |

---

## User Stories

- **US1:** As an experienced player, I want keyboard shortcuts to speed up gameplay.
- **US2:** As a player, I want to quickly assign weapons without excessive clicking.
- **US3:** As a player, I want to see shortcut hints in the UI.

---

## Technical Requirements

### Input Handling
```gdscript
# ShootingController.gd

func _input(event: InputEvent) -> void:
    if not visible or not current_phase:
        return

    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
                var index = event.keycode - KEY_1
                _select_target_by_index(index)
            KEY_ENTER:
                _on_confirm_pressed()
            KEY_ESCAPE:
                _on_clear_pressed()
            KEY_TAB:
                if event.shift_pressed:
                    _cycle_weapon(-1)
                else:
                    _cycle_weapon(1)
            KEY_SPACE:
                _assign_current_weapon_to_current_target()
            KEY_A:
                _assign_all_to_current_target()
```

### UI Hints
Show shortcut hints next to UI elements:
```
Targets:
  [1] Ork Boyz (12 models)
  [2] Gretchin (5 models)

[Enter] Confirm    [Esc] Clear    [Tab] Next Weapon
```

---

## Acceptance Criteria

- [ ] Number keys select targets
- [ ] Enter confirms targets
- [ ] Escape clears selection
- [ ] Tab cycles weapons
- [ ] Space assigns weapon to target
- [ ] Shortcut hints visible in UI
- [ ] Shortcuts only active during shooting phase
- [ ] No conflicts with other game shortcuts

---

## Implementation Tasks

- [ ] Add `_input()` handler to ShootingController
- [ ] Implement `_select_target_by_index()`
- [ ] Implement `_cycle_weapon()`
- [ ] Add shortcut hints to target list UI
- [ ] Add shortcut hints to button labels
- [ ] Ensure shortcuts don't fire during dialogs
- [ ] Test all shortcuts
- [ ] Document shortcuts in help/tutorial
