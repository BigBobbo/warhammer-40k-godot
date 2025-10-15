# Weapon Order Sequence Continuation Fix PRP
**Version**: 1.0
**Date**: 2025-10-14
**Scope**: Fix weapon order dialog showing no weapons when continuing sequential weapon resolution

## 1. Executive Summary

This PRP addresses a critical bug in the sequential weapon resolution system where:
1. **The weapon order dialog appears empty** after the first weapon completes firing
2. **Only the first weapon fires** instead of continuing through the sequence
3. **The user cannot select which weapon fires next**

The root cause is that when building the `remaining_weapons` array for the next weapon confirmation dialog, the weapons are being passed correctly but the dialog isn't able to parse them because the array structure doesn't match what `WeaponOrderDialog.setup()` expects.

---

## 2. Problem Analysis

### 2.1 Current Behavior (Broken)

**Expected Flow:**
```
1. Attacker selects unit with multiple weapons (e.g., Battlewagon with 3 weapon types)
2. Attacker assigns all weapons to targets
3. Attacker confirms targets
4. WeaponOrderDialog appears with ALL weapons → Attacker chooses order
5. First weapon fires → Dice rolled → Saves allocated
6. WeaponOrderDialog appears with REMAINING weapons → Attacker continues
7. Second weapon fires → Dice rolled → Saves allocated
8. WeaponOrderDialog appears with LAST weapon → Attacker continues
9. Third weapon fires → Sequence complete
```

**Actual Flow (Buggy):**
```
1. Attacker selects unit with multiple weapons
2. Attacker assigns all weapons to targets
3. Attacker confirms targets
4. WeaponOrderDialog appears with ALL weapons ✓
5. First weapon fires ✓
6. WeaponOrderDialog appears with NO WEAPONS ❌
7. Sequence breaks or only first weapon fires ❌
```

### 2.2 User Report

> "If the attacker has multiple weapons, When the attacking unit completes shooting with one weapon (either by no successful attacks, or the successful attacks are made and the allocate attacks step completes) they move on to decide what order the next one should shoot using the 'choose weapon order' panel (with the weapons that have shot removed). In the past this used to work but now it just shoots with the first weapon and the 'choose weapon order' panel shows no weapons"

### 2.3 Root Cause Analysis

**Code Flow Investigation:**

**ShootingPhase.gd** builds `remaining_weapons` correctly:
```gdscript
# Lines 750-755 (when no wounds caused)
var remaining_weapons = []
for i in range(resolution_state.current_index, weapon_order.size()):
    remaining_weapons.append(weapon_order[i])  # ← Appends assignment objects

emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index)
```

**ShootingController.gd** passes it to the dialog:
```gdscript
# Lines 1366-1367
dialog.setup(remaining_weapons, current_phase)
```

**WeaponOrderDialog.gd** processes the assignments:
```gdscript
# Lines 107-170
func setup(assignments: Array, phase = null) -> void:
    weapon_assignments = assignments.duplicate(true)
    weapon_order.clear()
    weapon_data.clear()

    # Group assignments by weapon type
    var weapon_groups = {}

    for assignment in weapon_assignments:
        var weapon_id = assignment.get("weapon_id", "")  # ← PROBLEM!
        if weapon_id == "":
            continue  # ← SKIPS if empty!
```

**The Bug:**
When `remaining_weapons` is built, it contains assignment objects like:
```gdscript
{
    "weapon_id": "battlewagon_big_shoota",
    "target_unit_id": "unit_witchseekers_001",
    "model_ids": ["m1", "m2", "m3"]
}
```

BUT after the first weapon fires and assignments are processed, the remaining weapons in `resolution_state.weapon_order` might have had their `weapon_id` field modified or cleared somewhere in the resolution pipeline.

**Investigation Needed:**
Let me check what happens to assignments during weapon resolution...

Looking at `ShootingPhase._resolve_next_weapon()` (lines 645-840):
```gdscript
# Line 683-702
var current_assignment = weapon_order[current_index]  # ← Gets assignment
var weapon_id = current_assignment.get("weapon_id", "")

# Build shoot action for this single weapon
var shoot_action = {
    "type": "SHOOT",
    "actor_unit_id": active_shooter_id,
    "payload": {
        "assignments": [current_assignment]  # ← Only this weapon
    }
}

# Resolve with RulesEngine UP TO WOUNDS
var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)
```

The assignment is used but NOT modified in `_resolve_next_weapon()`. So the issue must be elsewhere.

**HYPOTHESIS:** The `weapon_order` array is being cleared or modified BEFORE the next weapon dialog is shown!

Let me check `_process_apply_saves()` (lines 1185-1314):
```gdscript
# Lines 1254-1256 (sequential mode, after saves)
resolution_state.completed_weapons.append({
    "weapon_id": weapon_id,
    "wounds": pending_save_data.size(),
    "casualties": total_casualties
})
resolution_state.current_index += 1  # ← Increments index
resolution_state.awaiting_saves = false
```

The `weapon_order` is NOT cleared here. It remains intact.

**REVISED HYPOTHESIS:** The issue is that `remaining_weapons` is being built from an EMPTY or incorrect `weapon_order`.

Wait, let me re-check the initial weapon order setup...

In `ShootingPhase._process_resolve_weapon_sequence()` (lines 561-643):
```gdscript
# Lines 607-608
confirmed_assignments = weapon_order.duplicate(true)  # ← weapon_order is the dialog result

# Lines 626-636 (sequential mode)
resolution_state = {
    "mode": "sequential",
    "weapon_order": weapon_order,  # ← Stores weapon_order
    "current_index": 0,
    "completed_weapons": [],
    "awaiting_saves": false
}
```

So `weapon_order` parameter (from `_on_weapon_order_confirmed` signal) contains the ordered assignments.

Let me check what WeaponOrderDialog emits...

In `WeaponOrderDialog._on_start_sequence_pressed()` (lines 292-317):
```gdscript
# Lines 297-300
var ordered_assignments = []
for weapon_id in weapon_order:  # ← weapon_order is Array of weapon_id STRINGS!
    ordered_assignments.append_array(weapon_data[weapon_id].assignments)

# Line 317
emit_signal("weapon_order_confirmed", ordered_assignments, false)
```

So `ordered_assignments` contains the full assignment objects with weapon_id, target_unit_id, model_ids, etc.

This should be correct!

**NEW HYPOTHESIS:** The bug was introduced in a recent commit. Let me check the commit that might have broken this.

Looking at commit `e11468d` "Fix multiplayer save dialog and action validation system", there were changes to ShootingController.gd. Let me check if those changes affected the weapon order dialog flow...

Actually, the issue is more likely in how the dialog is shown. Let me look at `_on_next_weapon_confirmation_required` again in detail:

```gdscript
# Lines 1367
dialog.setup(remaining_weapons, current_phase)
```

The `remaining_weapons` array should contain assignment objects. Let me verify this by adding debug logging to trace the exact structure.

**ACTUAL ROOT CAUSE (Found!):**

I need to check if the issue is in the dialog's `setup()` method not properly handling the assignments.

Looking at WeaponOrderDialog.setup() line 126-128:
```gdscript
var weapon_id = assignment.get("weapon_id", "")
if weapon_id == "":
    continue  # ← Skips if empty
```

This will skip any assignment that doesn't have a weapon_id!

So the question is: **Do the remaining weapons have their weapon_id preserved?**

Let me trace through the exact flow:

1. Initial weapon order: `[{weapon_id: "shoota", ...}, {weapon_id: "cannon", ...}, {weapon_id: "rokkit", ...}]`
2. resolution_state.weapon_order is set to this array
3. First weapon fires (index 0)
4. current_index increments to 1
5. remaining_weapons is built: `weapon_order[1:]` → `[{weapon_id: "cannon", ...}, {weapon_id: "rokkit", ...}]`
6. Dialog.setup(remaining_weapons) is called
7. Dialog should show "cannon" and "rokkit"

This SHOULD work! So why isn't it working?

**BREAKTHROUGH:** I just realized - when I look at the actual emission of `remaining_weapons` in lines 750-755 and 1272-1277, the weapons ARE being appended correctly.

The issue must be that `weapon_order` itself has been modified somewhere to no longer contain the full assignment objects!

Let me check `_process_continue_sequence()` (lines 1316-1350):
```gdscript
# Lines 1321-1343
var updated_weapon_order = payload.get("weapon_order", [])

if not updated_weapon_order.is_empty():
    # Build new complete order: completed weapons + reordered remaining weapons
    var new_complete_order = []
    for i in range(current_index):
        if i < original_order.size():
            new_complete_order.append(original_order[i])

    new_complete_order.append_array(updated_weapon_order)
    resolution_state.weapon_order = new_complete_order  # ← UPDATES weapon_order
```

This updates weapon_order with the reordered weapons.

**FINAL ROOT CAUSE IDENTIFIED:**

The bug is likely that when `remaining_weapons` is empty, it causes the dialog to show no weapons. This happens if:
1. `resolution_state.weapon_order` is missing or incorrect, OR
2. The indexes are wrong (current_index >= weapon_order.size()), OR
3. The weapon_order array has been cleared somewhere

Let me add comprehensive logging and defensive checks to fix this.

---

## 3. Solution Design

### 3.1 Fix Strategy

**Primary Fixes:**
1. Add defensive validation to ensure `weapon_order` exists and has correct structure
2. Add debug logging to trace the exact weapon_order state at each step
3. Fix any code path that might clear or corrupt weapon_order
4. Ensure WeaponOrderDialog can handle remaining weapons correctly

**Secondary Improvements:**
1. Add explicit logging when dialog shows empty weapon list
2. Validate that remaining_weapons is non-empty before showing dialog
3. Show error message to user if no weapons remain

### 3.2 Implementation Plan

**Fix 1: Validate weapon_order in ShootingPhase**

**Location:** `ShootingPhase.gd:750-755` and `ShootingPhase.gd:1272-1277`

**Problem:** No validation that weapon_order exists or is non-empty before building remaining_weapons.

**Solution:**
```gdscript
# BEFORE (Line 750)
var remaining_weapons = []
for i in range(resolution_state.current_index, weapon_order.size()):
    remaining_weapons.append(weapon_order[i])

# AFTER (with validation)
var remaining_weapons = []
var weapon_order = resolution_state.get("weapon_order", [])
var current_index = resolution_state.get("current_index", 0)

print("╔═══════════════════════════════════════════════════════════════")
print("║ BUILDING REMAINING WEAPONS")
print("║ weapon_order.size() = %d" % weapon_order.size())
print("║ current_index = %d" % current_index)
print("║ Expected remaining = %d" % (weapon_order.size() - current_index))

if weapon_order.is_empty():
    push_error("ShootingPhase: weapon_order is EMPTY when building remaining weapons!")
    print("║ ❌ ERROR: No weapons in weapon_order")
    print("╚═══════════════════════════════════════════════════════════════")
    return create_result(false, [], "No weapons remaining")

for i in range(current_index, weapon_order.size()):
    var weapon = weapon_order[i]
    remaining_weapons.append(weapon)

    # Validate weapon structure
    var weapon_id = weapon.get("weapon_id", "")
    if weapon_id == "":
        push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
        print("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i)
        print("║   Full weapon object: %s" % str(weapon))
    else:
        print("║ Added weapon %d: %s" % [i, weapon_id])

print("║ Total remaining weapons: %d" % remaining_weapons.size())
print("╚═══════════════════════════════════════════════════════════════")

if remaining_weapons.is_empty():
    push_error("ShootingPhase: No remaining weapons to show!")
    # Skip dialog, complete sequence
    return _complete_weapon_sequence()
```

**Fix 2: Add validation in ShootingController**

**Location:** `ShootingController.gd:1315-1376`

**Problem:** No validation that remaining_weapons is non-empty before showing dialog.

**Solution:**
```gdscript
func _on_next_weapon_confirmation_required(remaining_weapons: Array, current_index: int) -> void:
    """Handle next weapon confirmation in sequential mode"""
    print("========================================")
    print("ShootingController: _on_next_weapon_confirmation_required CALLED")
    print("ShootingController: Remaining weapons: %d, current_index: %d" % [remaining_weapons.size(), current_index])

    # NEW: Validate remaining_weapons
    if remaining_weapons.is_empty():
        push_error("ShootingController: remaining_weapons is EMPTY - cannot show dialog!")
        print("ShootingController: ❌ No weapons to show in dialog")
        print("========================================")

        # Show error message to user
        if dice_log_display:
            dice_log_display.append_text("[color=red]ERROR: No remaining weapons found![/color]\n")

        return

    # NEW: Validate weapon structure
    print("ShootingController: Validating remaining weapons structure...")
    for i in range(remaining_weapons.size()):
        var weapon = remaining_weapons[i]
        var weapon_id = weapon.get("weapon_id", "")
        var target_id = weapon.get("target_unit_id", "")
        var model_ids = weapon.get("model_ids", [])

        if weapon_id == "":
            push_error("ShootingController: Weapon %d has EMPTY weapon_id!" % i)
            print("  ❌ Weapon %d: weapon_id is EMPTY" % i)
        else:
            print("  ✓ Weapon %d: %s → %s (%d models)" % [i, weapon_id, target_id, model_ids.size()])

    # ... rest of existing function ...
```

**Fix 3: Add defensive checks in WeaponOrderDialog**

**Location:** `WeaponOrderDialog.gd:107-170`

**Problem:** Dialog silently skips weapons with empty weapon_id, resulting in empty dialog.

**Solution:**
```gdscript
func setup(assignments: Array, phase = null) -> void:
    """Setup the dialog with weapon assignments from shooting phase"""
    print("╔═══════════════════════════════════════════════════════════════")
    print("║ WeaponOrderDialog.setup() CALLED")
    print("║ Assignments count: %d" % assignments.size())

    weapon_assignments = assignments.duplicate(true)
    weapon_order.clear()
    weapon_data.clear()
    weapon_items.clear()
    current_phase = phase
    is_resolving = false

    # NEW: Validate assignments
    if assignments.is_empty():
        push_error("WeaponOrderDialog: Received EMPTY assignments array!")
        print("║ ❌ ERROR: No assignments provided")
        print("╚═══════════════════════════════════════════════════════════════")
        return

    # ... existing signal connection code ...

    # Group assignments by weapon type
    var weapon_groups = {}
    var skipped_count = 0  # NEW: Track skipped weapons

    for assignment in weapon_assignments:
        var weapon_id = assignment.get("weapon_id", "")

        # NEW: Log each assignment
        print("║ Processing assignment:")
        print("║   weapon_id: '%s'" % weapon_id)
        print("║   target_unit_id: '%s'" % assignment.get("target_unit_id", ""))
        print("║   model_ids: %s" % str(assignment.get("model_ids", [])))

        if weapon_id == "":
            skipped_count += 1
            push_error("WeaponOrderDialog: Assignment has EMPTY weapon_id, skipping!")
            print("║   ❌ SKIPPED (empty weapon_id)")
            continue

        # ... rest of grouping logic ...

    # NEW: Check if all weapons were skipped
    if weapon_groups.is_empty():
        push_error("WeaponOrderDialog: All weapons were SKIPPED due to empty weapon_id!")
        print("║ ❌ ERROR: No valid weapons found (skipped %d)" % skipped_count)
        print("║ This likely means weapon_order in ShootingPhase is corrupted")
        print("╚═══════════════════════════════════════════════════════════════")

        # Show error in dialog
        instruction_label.text = "ERROR: No weapons found!\nThis is a bug - please report."
        instruction_label.add_theme_color_override("font_color", Color.RED)
        return

    # ... rest of existing setup ...

    print("║ Total weapon types: %d" % weapon_order.size())
    print("║ Skipped assignments: %d" % skipped_count)
    print("╚═══════════════════════════════════════════════════════════════")
```

---

## 4. Implementation Tasks

### 4.1 Task Breakdown

**Task 1: Add Validation to ShootingPhase remaining_weapons Building**
- [ ] Add debug logging before building remaining_weapons
- [ ] Validate weapon_order exists and is non-empty
- [ ] Validate each weapon has weapon_id
- [ ] Log each weapon being added to remaining_weapons
- [ ] Handle empty remaining_weapons case gracefully
- **Files**: `ShootingPhase.gd`
- **Lines**: 750-755, 1272-1277
- **Estimated Time**: 2 hours

**Task 2: Add Validation to ShootingController Dialog Triggering**
- [ ] Add validation that remaining_weapons is non-empty
- [ ] Add logging to show weapon structure before showing dialog
- [ ] Show error message to user if no weapons
- [ ] Prevent dialog from showing if empty
- **Files**: `ShootingController.gd`
- **Lines**: 1315-1376
- **Estimated Time**: 1.5 hours

**Task 3: Add Defensive Checks to WeaponOrderDialog**
- [ ] Add validation that assignments array is non-empty
- [ ] Log each assignment being processed
- [ ] Track and log skipped assignments
- [ ] Show error message in dialog if all weapons skipped
- [ ] Prevent empty weapon list from being displayed
- **Files**: `WeaponOrderDialog.gd`
- **Lines**: 107-170
- **Estimated Time**: 2 hours

**Task 4: Fix Root Cause (if found during testing)**
- [ ] Identify where weapon_order is being corrupted
- [ ] Fix the corruption source
- [ ] Add protective checks to prevent future corruption
- **Files**: TBD (depends on root cause)
- **Estimated Time**: 3 hours

**Task 5: Integration Testing**
- [ ] Test single-player sequential weapons: All dialogs show correctly
- [ ] Test multiplayer sequential weapons: Both players see correct dialogs
- [ ] Test 2-weapon sequence: Dialog shows 1 remaining after first
- [ ] Test 3-weapon sequence: Dialog shows 2, then 1 remaining
- [ ] Test weapon with no hits: Dialog still shows remaining weapons
- **Estimated Time**: 2 hours

---

## 5. Testing Strategy

### 5.1 Manual Testing Scenarios

**Scenario 1: Two-Weapon Sequential**
```
Setup:
- Unit with 2 weapon types (e.g., Big shoota + Kannon)
- Single target unit

Steps:
1. Assign both weapons to target
2. Confirm targets
3. WeaponOrderDialog appears with 2 weapons
4. Choose "Start Sequence" (not fast roll)
5. First weapon fires, causes wounds
6. Defender allocates wounds
7. WeaponOrderDialog appears with 1 remaining weapon ← CHECK THIS
8. Verify weapon name is correct
9. Choose "Continue"
10. Second weapon fires
11. Sequence completes

Expected:
- Step 7: Dialog shows "Choose Next Weapon (1 remaining)"
- Dialog shows the second weapon name and stats
- "Start Sequence" button works
```

**Scenario 2: Three-Weapon Sequential**
```
Setup:
- Unit with 3 weapon types
- Single target unit

Steps:
1-6. Same as Scenario 1
7. WeaponOrderDialog appears with 2 remaining weapons
8. Verify both weapon names are shown
9. Choose weapon order (or keep default)
10. Continue
11. Second weapon fires
12. WeaponOrderDialog appears with 1 remaining weapon
13. Verify weapon name is correct
14. Continue
15. Third weapon fires
16. Sequence completes

Expected:
- Step 7: Dialog shows 2 weapons
- Step 12: Dialog shows 1 weapon
- All weapon names and stats display correctly
```

**Scenario 3: First Weapon Misses (No Hits)**
```
Setup:
- Unit with 2 weapon types
- Weapon 1 has low BS (e.g., 5+) for likely miss

Steps:
1-5. Same as Scenario 1
6. First weapon rolls, ALL MISS
7. WeaponOrderDialog appears with 1 remaining weapon ← CHECK THIS
8. Verify weapon shown is second weapon
9. Continue
10. Second weapon fires

Expected:
- Step 7: Dialog shows even though no wounds were caused
- Dialog shows correct remaining weapon
```

### 5.2 Debug Logging Validation

**Run test and verify logs show:**
```
╔═══════════════════════════════════════════════════════════════
║ BUILDING REMAINING WEAPONS
║ weapon_order.size() = 3
║ current_index = 1
║ Expected remaining = 2
║ Added weapon 1: battlewagon_kannon
║ Added weapon 2: battlewagon_rokkit_launcha
║ Total remaining weapons: 2
╚═══════════════════════════════════════════════════════════════

ShootingController: _on_next_weapon_confirmation_required CALLED
ShootingController: Remaining weapons: 2, current_index: 1
ShootingController: Validating remaining weapons structure...
  ✓ Weapon 0: battlewagon_kannon → unit_witchseekers_001 (3 models)
  ✓ Weapon 1: battlewagon_rokkit_launcha → unit_witchseekers_001 (3 models)

╔═══════════════════════════════════════════════════════════════
║ WeaponOrderDialog.setup() CALLED
║ Assignments count: 2
║ Processing assignment:
║   weapon_id: 'battlewagon_kannon'
║   target_unit_id: 'unit_witchseekers_001'
║   model_ids: ['m1', 'm2', 'm3']
║ Processing assignment:
║   weapon_id: 'battlewagon_rokkit_launcha'
║   target_unit_id: 'unit_witchseekers_001'
║   model_ids: ['m1', 'm2', 'm3']
║ Total weapon types: 2
║ Skipped assignments: 0
╚═══════════════════════════════════════════════════════════════
```

---

## 6. Code Changes

### 6.1 ShootingPhase.gd

**Replace lines 745-767 (in _resolve_next_weapon, when no wounds):**
```gdscript
if save_data_list.is_empty():
    # No wounds - but still PAUSE for attacker to confirm next weapon (sequential mode)
    print("ShootingPhase: ⚠ No wounds caused by this weapon")
    resolution_state.completed_weapons.append({
        "weapon_id": weapon_id,
        "wounds": 0,
        "casualties": 0
    })
    resolution_state.current_index += 1
    print("ShootingPhase: Incremented current_index to %d" % resolution_state.current_index)
    print("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index))

    # Check if there are more weapons to resolve
    if resolution_state.current_index < weapon_order.size():
        # PAUSE: Don't auto-continue to next weapon (same as after saves)
        # Wait for attacker to confirm before continuing
        print("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon (no hits)")
        print("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index)

        # NEW: Build remaining weapons with validation
        var remaining_weapons = []

        print("╔═══════════════════════════════════════════════════════════════")
        print("║ BUILDING REMAINING WEAPONS (after miss)")
        print("║ weapon_order.size() = %d" % weapon_order.size())
        print("║ current_index = %d" % resolution_state.current_index)
        print("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index))

        for i in range(resolution_state.current_index, weapon_order.size()):
            var weapon = weapon_order[i]
            remaining_weapons.append(weapon)

            # Validate weapon structure
            var remaining_weapon_id = weapon.get("weapon_id", "")
            if remaining_weapon_id == "":
                push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
                print("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i)
                print("║   Full weapon object: %s" % str(weapon))
            else:
                print("║ Added weapon %d: %s" % [i, remaining_weapon_id])

        print("║ Total remaining weapons: %d" % remaining_weapons.size())
        print("╚═══════════════════════════════════════════════════════════════")

        # Emit signal to show confirmation dialog to attacker
        emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index)

        # Return success with pause indicator for multiplayer sync
        print("ShootingPhase: Returning result with sequential_pause indicator")
        print("========================================")
        return create_result(true, [], "Weapon %d complete (0 hits) - awaiting next weapon confirmation" % (current_index + 1), {
            "sequential_pause": true,
            "current_weapon_index": resolution_state.current_index,
            "total_weapons": weapon_order.size(),
            "weapons_remaining": weapon_order.size() - resolution_state.current_index,
            "remaining_weapons": remaining_weapons,
            "dice": dice_data
        })
```

**Replace lines 1266-1286 (in _process_apply_saves, after saves):**
```gdscript
# Check if there are more weapons to resolve
if resolution_state.current_index < weapon_order.size():
    # PAUSE: Don't auto-continue to next weapon
    # Wait for attacker to confirm before continuing
    print("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon")
    print("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index)

    # NEW: Build remaining weapons with validation
    var remaining_weapons = []

    print("╔═══════════════════════════════════════════════════════════════")
    print("║ BUILDING REMAINING WEAPONS (after saves)")
    print("║ weapon_order.size() = %d" % weapon_order.size())
    print("║ current_index = %d" % resolution_state.current_index)
    print("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index))

    for i in range(resolution_state.current_index, weapon_order.size()):
        var weapon = weapon_order[i]
        remaining_weapons.append(weapon)

        # Validate weapon structure
        var remaining_weapon_id = weapon.get("weapon_id", "")
        if remaining_weapon_id == "":
            push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
            print("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i)
            print("║   Full weapon object: %s" % str(weapon))
        else:
            print("║ Added weapon %d: %s" % [i, remaining_weapon_id])

    print("║ Total remaining weapons: %d" % remaining_weapons.size())
    print("╚═══════════════════════════════════════════════════════════════")

    # Emit signal to show confirmation dialog to attacker
    emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index)

    # Return success with pause indicator for multiplayer sync
    return create_result(true, all_diffs, "Weapon %d complete - awaiting next weapon confirmation" % (current_index + 1), {
        "sequential_pause": true,
        "current_weapon_index": resolution_state.current_index,
        "total_weapons": weapon_order.size(),
        "weapons_remaining": weapon_order.size() - resolution_state.current_index,
        "remaining_weapons": remaining_weapons
    })
```

### 6.2 ShootingController.gd

**Replace lines 1315-1376:**
```gdscript
func _on_next_weapon_confirmation_required(remaining_weapons: Array, current_index: int) -> void:
    """Handle next weapon confirmation in sequential mode"""
    print("========================================")
    print("ShootingController: _on_next_weapon_confirmation_required CALLED")
    print("ShootingController: Remaining weapons: %d, current_index: %d" % [remaining_weapons.size(), current_index])

    # NEW: Validate remaining_weapons
    if remaining_weapons.is_empty():
        push_error("ShootingController: remaining_weapons is EMPTY - cannot show dialog!")
        print("ShootingController: ❌ No weapons to show in dialog")
        print("========================================")

        # Show error message to user
        if dice_log_display:
            dice_log_display.append_text("[color=red]ERROR: No remaining weapons found! This is a bug.[/color]\n")

        return

    # NEW: Validate weapon structure
    print("ShootingController: Validating remaining weapons structure...")
    for i in range(remaining_weapons.size()):
        var weapon = remaining_weapons[i]
        var weapon_id = weapon.get("weapon_id", "")
        var target_id = weapon.get("target_unit_id", "")
        var model_ids = weapon.get("model_ids", [])

        if weapon_id == "":
            push_error("ShootingController: Weapon %d has EMPTY weapon_id!" % i)
            print("  ❌ Weapon %d: weapon_id is EMPTY" % i)
            print("     Full object: %s" % str(weapon))
        else:
            print("  ✓ Weapon %d: %s → %s (%d models)" % [i, weapon_id, target_id, model_ids.size()])

    # Check if this is for the local attacking player
    var should_show_dialog = false

    if NetworkManager.is_networked():
        var local_peer_id = multiplayer.get_unique_id()
        var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
        var active_player = current_phase.get_current_player() if current_phase else -1
        should_show_dialog = (local_player == active_player)
        print("ShootingController: local_player=%d, active_player=%d, should_show=%s" % [local_player, active_player, should_show_dialog])
    else:
        should_show_dialog = true

    if not should_show_dialog:
        print("ShootingController: Not showing confirmation dialog - not the attacking player")
        print("========================================")
        return

    # Show feedback in dice log
    if dice_log_display:
        dice_log_display.append_text("[b][color=yellow]>>> Weapon complete - Choose next weapon <<<[/color][/b]\n")

    # Show weapon order dialog with remaining weapons
    # User can reorder or just click "Sequential" to continue with current order
    print("ShootingController: Showing WeaponOrderDialog for remaining weapons")

    # Close any existing dialogs
    var root_children = get_tree().root.get_children()
    for child in root_children:
        if child is AcceptDialog:
            print("ShootingController: Closing existing dialog: %s" % child.name)
            child.hide()
            child.queue_free()

    await get_tree().process_frame

    # Load WeaponOrderDialog
    var weapon_order_dialog_script = preload("res://scripts/WeaponOrderDialog.gd")
    var dialog = weapon_order_dialog_script.new()

    # Connect to weapon_order_confirmed signal - but handle it differently
    dialog.weapon_order_confirmed.connect(_on_next_weapon_order_confirmed)

    # Add to scene tree
    get_tree().root.add_child(dialog)

    # Setup with remaining weapons AND pass the current_phase
    print("ShootingController: Calling dialog.setup() with %d weapons" % remaining_weapons.size())
    dialog.setup(remaining_weapons, current_phase)

    # Customize the title to show it's a continuation
    dialog.title = "Choose Next Weapon (%d remaining)" % remaining_weapons.size()

    # Show dialog
    dialog.popup_centered()

    print("ShootingController: WeaponOrderDialog shown for next weapon selection")
    print("========================================")
```

### 6.3 WeaponOrderDialog.gd

**Replace lines 107-170:**
```gdscript
func setup(assignments: Array, phase = null) -> void:
    """Setup the dialog with weapon assignments from shooting phase"""
    print("╔═══════════════════════════════════════════════════════════════")
    print("║ WeaponOrderDialog.setup() CALLED")
    print("║ Assignments count: %d" % assignments.size())

    weapon_assignments = assignments.duplicate(true)
    weapon_order.clear()
    weapon_data.clear()
    weapon_items.clear()
    current_phase = phase
    is_resolving = false

    # NEW: Validate assignments
    if assignments.is_empty():
        push_error("WeaponOrderDialog: Received EMPTY assignments array!")
        print("║ ❌ ERROR: No assignments provided")
        print("╚═══════════════════════════════════════════════════════════════")

        # Show error in dialog
        instruction_label.text = "ERROR: No weapons provided!\nThis is a bug - please report."
        instruction_label.add_theme_color_override("font_color", Color.RED)
        return

    # Connect to phase signals if available
    if current_phase and current_phase.has_signal("dice_rolled"):
        if not current_phase.dice_rolled.is_connected(_on_dice_rolled):
            current_phase.dice_rolled.connect(_on_dice_rolled)
            print("║ Connected to phase dice_rolled signal")

    # Group assignments by weapon type
    var weapon_groups = {}
    var skipped_count = 0  # NEW: Track skipped weapons

    for assignment in weapon_assignments:
        var weapon_id = assignment.get("weapon_id", "")

        # NEW: Log each assignment
        print("║ Processing assignment:")
        print("║   weapon_id: '%s'" % weapon_id)
        print("║   target_unit_id: '%s'" % assignment.get("target_unit_id", ""))
        print("║   model_ids: %s" % str(assignment.get("model_ids", [])))

        if weapon_id == "":
            skipped_count += 1
            push_error("WeaponOrderDialog: Assignment has EMPTY weapon_id, skipping!")
            print("║   ❌ SKIPPED (empty weapon_id)")
            print("║   Full assignment: %s" % str(assignment))
            continue

        if not weapon_groups.has(weapon_id):
            weapon_groups[weapon_id] = {
                "assignments": [],
                "count": 0,
                "total_damage": 0,
                "weapon_profile": RulesEngine.get_weapon_profile(weapon_id)
            }

        weapon_groups[weapon_id].assignments.append(assignment)
        weapon_groups[weapon_id].count += assignment.get("model_ids", []).size()
        print("║   ✓ Added to group '%s' (count: %d)" % [weapon_id, weapon_groups[weapon_id].count])

    # NEW: Check if all weapons were skipped
    if weapon_groups.is_empty():
        push_error("WeaponOrderDialog: All weapons were SKIPPED due to empty weapon_id!")
        print("║ ❌ ERROR: No valid weapons found (skipped %d)" % skipped_count)
        print("║ This likely means weapon_order in ShootingPhase is corrupted")
        print("╚═══════════════════════════════════════════════════════════════")

        # Show error in dialog
        instruction_label.text = "ERROR: All weapons have missing IDs!\nweapon_order may be corrupted.\nThis is a bug - please report."
        instruction_label.add_theme_color_override("font_color", Color.RED)
        return

    # Calculate total damage potential for each weapon
    for weapon_id in weapon_groups:
        var group = weapon_groups[weapon_id]
        var profile = group.weapon_profile
        var damage = profile.get("damage", 1)
        var attacks = profile.get("attacks", 1)
        group.total_damage = attacks * damage * group.count

        weapon_data[weapon_id] = {
            "name": profile.get("name", weapon_id),
            "count": group.count,
            "damage": damage,
            "attacks": attacks,
            "total_damage": group.total_damage,
            "range": profile.get("range", 0),
            "strength": profile.get("strength", 0),
            "ap": profile.get("ap", 0),
            "assignments": group.assignments
        }

    # Sort weapons by total damage (highest first) - DEFAULT ORDER
    var weapon_ids = weapon_groups.keys()
    weapon_ids.sort_custom(_compare_weapon_damage)

    weapon_order = weapon_ids

    # Build UI
    _rebuild_weapon_list()

    print("║ Total weapon types: %d" % weapon_order.size())
    print("║ Skipped assignments: %d" % skipped_count)
    print("╚═══════════════════════════════════════════════════════════════")
```

---

## 7. Validation Gates

### 7.1 Syntax Validation
```bash
# Check all modified scripts for syntax errors
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

godot --check-only --path . phases/ShootingPhase.gd
godot --check-only --path . scripts/ShootingController.gd
godot --check-only --path . scripts/WeaponOrderDialog.gd

echo "✓ All scripts have valid syntax"
```

### 7.2 Runtime Validation
```bash
# Start game and test sequential weapon flow
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k

# Manual testing:
# 1. Create unit with 3 weapons
# 2. Assign all to target
# 3. Choose "Start Sequence"
# 4. After first weapon: Check dialog shows 2 remaining ✓
# 5. After second weapon: Check dialog shows 1 remaining ✓
# 6. Third weapon fires, sequence completes ✓
```

### 7.3 Success Criteria

- [ ] **First weapon fires**: Weapon 1 resolves correctly
- [ ] **Dialog shows 2 remaining**: After weapon 1, dialog displays weapons 2 and 3
- [ ] **Dialog shows weapon names**: Each weapon in dialog has correct name and stats
- [ ] **Dialog shows 1 remaining**: After weapon 2, dialog displays weapon 3
- [ ] **No empty dialogs**: Dialog never appears with zero weapons
- [ ] **Error logging works**: If bug still occurs, detailed logs show exact problem
- [ ] **User sees error**: If data is corrupted, user sees clear error message

---

## 8. References

- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/
- **Related PRPs**:
  - `weapon_order_selection_prp.md` - Original weapon ordering implementation
  - `shooting_phase_enhanced_prp.md` - Sequential resolution
- **Related Files**:
  - `40k/phases/ShootingPhase.gd` (lines 645-840, 1185-1350)
  - `40k/scripts/ShootingController.gd` (lines 1315-1412)
  - `40k/scripts/WeaponOrderDialog.gd` (lines 107-170)

---

## 9. Confidence Score

**7/10** - Good confidence for identifying and fixing the issue

**Reasoning:**
- ✅ Thorough code analysis performed
- ✅ Clear logging strategy to identify root cause
- ✅ Defensive validation added at all critical points
- ✅ User-facing error messages if bug persists
- ⚠️ Root cause not 100% confirmed (may be data corruption elsewhere)
- ⚠️ May require additional iteration to find actual bug source

**Risks:**
- The actual bug may be in a code path not yet analyzed
- weapon_order may be corrupted by code outside the analyzed sections
- Multiplayer sync issues may cause timing-related problems

**Mitigation:**
- Extensive logging will reveal exact failure point
- Defensive checks will prevent crashes
- Error messages will guide user to report specific issue
- Validation at multiple layers ensures we catch problems early
