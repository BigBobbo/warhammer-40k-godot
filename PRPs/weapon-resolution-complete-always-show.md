# Weapon Resolution Complete Window - Always Show PRP
**Version**: 1.0
**Date**: 2025-10-15
**Scope**: Fix weapon resolution complete dialog to show after ALL weapons, including final and single weapons

## 1. Executive Summary

This PRP addresses a UX issue where the "Weapon Resolution Complete" dialog (NextWeaponDialog) only appears when there are **additional weapons remaining**. This prevents attackers from seeing the results of:
1. **The final weapon in a sequence** (when no more weapons remain)
2. **The only weapon** (when a single weapon type is selected)

### Problem Statement

> "Weapon Resolution complete window in the shooting phase only shows up for the attacker if there are additional weapons currently. It should show up after all attacks by the attacker NOT ONLY IF THERE ARE ADDITIONAL WEAPONS TO SHOOT. This should show up when after the final weapon shoots and if only one weapon is selected also"

### Current Behavior (Broken)

**Multi-weapon scenario:**
1. Attacker has 3 weapons → selects sequential mode
2. Weapon 1 fires → Dialog shows (2 remaining) ✓
3. Weapon 2 fires → Dialog shows (1 remaining) ✓
4. Weapon 3 fires → **No dialog shown** ❌
5. Unit completes shooting without showing final results

**Single-weapon scenario:**
1. Attacker has 1 weapon → automatically resolved (no sequential mode)
2. Weapon fires → **No dialog shown** ❌
3. Unit completes shooting without showing results

### Proposed Solution

**Multi-weapon scenario (fixed):**
1. Weapon 1 fires → Dialog shows (2 remaining) ✓
2. Weapon 2 fires → Dialog shows (1 remaining) ✓
3. Weapon 3 fires → **Dialog shows (0 remaining, "Complete Shooting" button)** ✅

**Single-weapon scenario (fixed):**
1. Weapon fires → **Dialog shows (0 remaining, "Complete Shooting" button)** ✅

### Impact

- **User Experience**: Attackers can see results of every weapon, including the last one
- **Consistency**: Dialog behavior is uniform regardless of weapon count
- **Transparency**: No "hidden" results that players might miss
- **Multiplayer**: Both players see clear confirmation of when attacks complete

---

## 2. Core Requirements

### 2.1 Functional Requirements

- **FR1**: NextWeaponDialog appears after EVERY weapon completes (including the last one)
- **FR2**: Dialog shows even when only 1 weapon is selected
- **FR3**: When no weapons remain, button text changes to "Complete Shooting"
- **FR4**: When weapons remain, button text shows "Continue to Next Weapon"
- **FR5**: Dialog displays complete attack summary (hits, wounds, saves, casualties)
- **FR6**: Dialog respects multiplayer permissions (only attacker sees it)

### 2.2 Rules Compliance

- **RC1**: No changes to Warhammer 40k attack resolution rules
- **RC2**: Dialog does not alter weapon effectiveness or damage
- **RC3**: Follows 40k 10e core rules for Making Attacks sequence:
  - Hit Roll → Wound Roll → Allocate Attack → Saving Throw → Inflict Damage

### 2.3 Multiplayer Requirements

- **MR1**: Dialog appears only for attacking player
- **MR2**: Defender sees "Attacker reviewing results..." in dice log
- **MR3**: Network sync maintained when attacker clicks "Complete Shooting"
- **MR4**: Dialog state persists across save/load

### 2.4 Architecture Requirements

- **AR1**: Modify existing NextWeaponDialog.gd (no new files)
- **AR2**: Modify ShootingPhase.gd signal emission logic
- **AR3**: Handle single-weapon case without entering sequential mode
- **AR4**: Maintain backwards compatibility with existing sequential mode

---

## 3. Current Implementation Analysis

### 3.1 Existing Files & Signal Flow

**NextWeaponDialog.gd** (`40k/scripts/NextWeaponDialog.gd`):
- **Purpose**: Shows last weapon's results and remaining weapons
- **Current behavior**: Expects `remaining_weapons.size() > 0`
- **Lines 464-467**: Changes button text to "Complete Shooting" if no weapons remain
- **Problem**: This case is never reached because signal isn't emitted when no weapons remain

**ShootingPhase.gd** (`40k/phases/ShootingPhase.gd`):
- **Line 14**: Signal definition `next_weapon_confirmation_required`
- **Lines 785-835**: Emits signal after weapon with 0 hits (sequential mode)
- **Lines 1422-1482**: Emits signal after saves complete (sequential mode)
- **Problem**: Both emission sites check `if resolution_state.current_index < weapon_order.size()`
  - This means signal is NOT emitted when current_index == weapon_order.size() (final weapon)

**ShootingPhase._process_confirm_targets()** (lines 335-425):
- **Line 383**: Checks weapon count: `if weapon_count >= 2:`
- **Line 386-401**: If 2+ weapons → shows WeaponOrderDialog (sequential mode)
- **Line 403-425**: If 1 weapon → directly calls `_process_resolve_shooting()`
- **Problem**: Single weapon never enters sequential mode, so dialog never shows

### 3.2 Code Path Analysis

#### Multi-Weapon Sequential Mode

**Current flow (last weapon):**
```
ShootingPhase._process_apply_saves()
  ↓
resolution_state.current_index += 1  # Now equals weapon_order.size()
  ↓
if resolution_state.current_index < weapon_order.size():  # FALSE!
  ↓
(signal NOT emitted) ❌
  ↓
Mark shooter as done, clear state
  ↓
Unit completes without showing dialog
```

**Fixed flow (last weapon):**
```
ShootingPhase._process_apply_saves()
  ↓
resolution_state.current_index += 1  # Now equals weapon_order.size()
  ↓
if resolution_state.current_index <= weapon_order.size():  # TRUE!
  ↓
emit_signal("next_weapon_confirmation_required", [], current_index, last_weapon_result)
  ↓
NextWeaponDialog shows with 0 remaining weapons
  ↓
Button shows "Complete Shooting"
  ↓
User clicks → Unit completes
```

#### Single Weapon Mode

**Current flow:**
```
ShootingPhase._process_confirm_targets()
  ↓
weapon_count == 1 → Skip sequential mode
  ↓
_process_resolve_shooting() → Saves → Complete
  ↓
(No dialog shown) ❌
```

**Fixed flow (Option 1: Force sequential mode):**
```
ShootingPhase._process_confirm_targets()
  ↓
weapon_count >= 1 → ALWAYS enter sequential mode
  ↓
emit_signal("weapon_order_required")
  ↓
User sees dialog with 1 weapon → Clicks "Start Sequence"
  ↓
_process_resolve_weapon_sequence() → Sequential mode
  ↓
Weapon fires → Dialog shows results
  ↓
Button shows "Complete Shooting"
```

**Fixed flow (Option 2: Show dialog after single weapon):**
```
ShootingPhase._process_confirm_targets()
  ↓
weapon_count == 1 → Direct resolution
  ↓
_process_resolve_shooting() → Saves complete
  ↓
emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)
  ↓
NextWeaponDialog shows with 0 remaining
  ↓
Button shows "Complete Shooting"
```

**Recommendation**: Use **Option 2** because:
- Minimal code changes
- No change to user flow for single weapons (no extra weapon order dialog)
- Consistent result display across all weapon counts

---

## 4. Proposed Solution

### 4.1 Change #1: Always Emit Signal After Weapon Completes

**Modify ShootingPhase._resolve_next_weapon()** (lines 785-858)

**BEFORE (line 786):**
```gdscript
if resolution_state.current_index < weapon_order.size():
    # Emit signal only if MORE weapons remain
    emit_signal("next_weapon_confirmation_required", remaining_weapons, ...)
else:
    # Complete sequence WITHOUT showing dialog
    ...
```

**AFTER:**
```gdscript
# ALWAYS emit signal to show results, even if no weapons remain
var remaining_weapons = []
for i in range(resolution_state.current_index, weapon_order.size()):
    remaining_weapons.append(weapon_order[i])

var last_weapon_result = _get_last_weapon_result()
emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

# Return with pause indicator
return create_result(true, [], "Weapon complete - awaiting confirmation", {
    "sequential_pause": true,
    "remaining_weapons": remaining_weapons
})

# NOTE: Completion logic moves to NextWeaponDialog button handler
```

**Impact**: Dialog shows after EVERY weapon, including the last one.

### 4.2 Change #2: Same Fix for After-Saves Path

**Modify ShootingPhase._process_apply_saves()** (lines 1422-1487)

**BEFORE (line 1422):**
```gdscript
if resolution_state.current_index < weapon_order.size():
    # Emit signal only if MORE weapons remain
    emit_signal("next_weapon_confirmation_required", ...)
else:
    # Complete sequence WITHOUT showing dialog
    ...
```

**AFTER:**
```gdscript
# ALWAYS emit signal, even if no weapons remain
var remaining_weapons = []
for i in range(resolution_state.current_index, weapon_order.size()):
    remaining_weapons.append(weapon_order[i])

var last_weapon_result = _get_last_weapon_result()
emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

return create_result(true, all_diffs, "Weapon complete - awaiting confirmation", {
    "sequential_pause": true,
    "remaining_weapons": remaining_weapons
})

# NOTE: Completion logic moves to NextWeaponDialog button handler
```

### 4.3 Change #3: Handle Single Weapon Case

**Modify ShootingPhase._process_resolve_shooting()** (lines 427-510)

**Add at end of function** (after line 510):
```gdscript
# If this was a single weapon (no sequential mode), still show results dialog
var mode = resolution_state.get("mode", "")
if mode != "sequential":
    # Single weapon or fast-roll mode
    # After saves complete, show results dialog
    # This will be triggered by _process_apply_saves for fast mode
    # For truly single weapon (no mode set), we emit here

    # Check if we should show results dialog
    if active_shooter_id != "":
        # Build last weapon result
        var last_weapon_result = {
            "weapon_id": confirmed_assignments[0].get("weapon_id", "") if confirmed_assignments.size() > 0 else "",
            "weapon_name": "Unknown",
            "target_unit_id": confirmed_assignments[0].get("target_unit_id", "") if confirmed_assignments.size() > 0 else "",
            "target_unit_name": "Unknown",
            "hits": 0,  # Will be filled from pending_save_data
            "wounds": pending_save_data.size(),
            "saves_failed": 0,  # Will be updated after saves
            "casualties": 0,  # Will be updated after saves
            "total_attacks": 0,
            "dice_rolls": dice_data
        }

        # Store this for later use when saves complete
        resolution_state["pending_single_weapon_result"] = last_weapon_result

# Existing return statement...
return create_result(true, [], "Awaiting save resolution", {
    "dice": dice_data,
    "save_data_list": save_data_list
})
```

**Then modify _process_apply_saves()** to check for single weapon mode:

**Add after line 1510** (at end of function, before final return):
```gdscript
# Check if this was a single weapon (no sequential mode)
var mode = resolution_state.get("mode", "")
if mode != "sequential" and active_shooter_id != "":
    # Single weapon case - show results dialog before completing

    # Build last weapon result
    var last_weapon_result = resolution_state.get("pending_single_weapon_result", {})

    # Update with final casualties count
    last_weapon_result["casualties"] = total_casualties
    last_weapon_result["saves_failed"] = save_results_list[0].get("saves_failed", 0) if save_results_list.size() > 0 else 0

    # Emit signal with EMPTY remaining_weapons (signals completion)
    emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

    # Return with pause indicator (completion will happen when user clicks button)
    return create_result(true, all_diffs, "Single weapon complete - awaiting confirmation", {
        "sequential_pause": true,
        "remaining_weapons": [],
        "last_weapon_result": last_weapon_result
    })
```

### 4.4 Change #4: Handle "Complete Shooting" in Dialog

**NextWeaponDialog._on_continue_pressed()** (lines 251-269)

**BEFORE:**
```gdscript
func _on_continue_pressed() -> void:
    # Always emit with remaining_weapons
    emit_signal("continue_confirmed", remaining_weapons, false)
    hide()
    queue_free()
```

**AFTER:**
```gdscript
func _on_continue_pressed() -> void:
    print("╔═══════════════════════════════════════════════════════════════")
    print("║ NEXT WEAPON DIALOG: CONTINUE PRESSED")
    print("║ remaining_weapons.size(): ", remaining_weapons.size())

    if remaining_weapons.is_empty():
        # No weapons remaining - this is the completion case
        print("║ No remaining weapons - completing shooting")
        print("╚═══════════════════════════════════════════════════════════════")

        # Emit signal to complete shooting (ShootingController will handle)
        emit_signal("shooting_complete_confirmed")
        hide()
        queue_free()
    else:
        # More weapons remain - continue sequence
        print("║ %d weapons remaining - continuing sequence" % remaining_weapons.size())
        print("╚═══════════════════════════════════════════════════════════════")

        emit_signal("continue_confirmed", remaining_weapons, false)
        hide()
        queue_free()
```

**Add new signal at top of file:**
```gdscript
signal continue_confirmed(weapon_order: Array, fast_roll: bool)
signal shooting_complete_confirmed  # NEW: Signals shooting is complete
```

### 4.5 Change #5: Handle Completion Signal

**ShootingController._on_next_weapon_confirmation_required()** (lines 1359-1449)

**Add connection for new signal** (after line 1435):
```gdscript
# Connect to confirmation signal - when user clicks Continue, show WeaponOrderDialog
dialog.continue_confirmed.connect(_on_show_weapon_order_from_next_weapon_dialog)

# NEW: Connect to completion signal
dialog.shooting_complete_confirmed.connect(_on_shooting_complete)
```

**Add new handler:**
```gdscript
func _on_shooting_complete() -> void:
    """Handle shooting completion after final weapon"""
    print("╔═══════════════════════════════════════════════════════════════")
    print("║ SHOOTING CONTROLLER: SHOOTING COMPLETE")
    print("║ User confirmed completion after viewing final weapon results")
    print("╚═══════════════════════════════════════════════════════════════")

    # Emit action to mark shooter as complete
    emit_signal("shoot_action_requested", {
        "type": "COMPLETE_SHOOTING_FOR_UNIT",
        "actor_unit_id": active_shooter_id
    })

    # Clear local state
    active_shooter_id = ""
    weapon_assignments.clear()
    _clear_visuals()
```

### 4.6 Change #6: Add COMPLETE_SHOOTING_FOR_UNIT Action

**ShootingPhase.validate_action()** (add new case):
```gdscript
"COMPLETE_SHOOTING_FOR_UNIT":
    return _validate_complete_shooting_for_unit(action)
```

**ShootingPhase.process_action()** (add new case):
```gdscript
"COMPLETE_SHOOTING_FOR_UNIT":
    return _process_complete_shooting_for_unit(action)
```

**Add new methods:**
```gdscript
func _validate_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    if unit_id == "":
        return {"valid": false, "errors": ["Missing actor_unit_id"]}

    if unit_id != active_shooter_id:
        return {"valid": false, "errors": ["Unit is not the active shooter"]}

    return {"valid": true, "errors": []}

func _process_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
    """Mark shooter as done and clear state"""
    var unit_id = action.get("actor_unit_id", "")

    var changes = [{
        "op": "set",
        "path": "units.%s.flags.has_shot" % unit_id,
        "value": true
    }]

    units_that_shot.append(unit_id)

    # Clear state
    active_shooter_id = ""
    confirmed_assignments.clear()
    resolution_state.clear()
    pending_save_data.clear()

    log_phase_message("Shooting complete for unit %s" % unit_id)

    # Emit signal to clear visuals
    emit_signal("shooting_resolved", unit_id, "", {"casualties": 0})

    return create_result(true, changes, "Shooting complete")
```

---

## 5. Implementation Tasks

### 5.1 Task Breakdown

**Task 1: Modify Signal Emission in _resolve_next_weapon**
- [ ] Remove `if resolution_state.current_index < weapon_order.size()` check
- [ ] Always build remaining_weapons array (may be empty)
- [ ] Always emit `next_weapon_confirmation_required` signal
- [ ] Return with pause indicator instead of completing
- **File**: `40k/phases/ShootingPhase.gd`
- **Lines**: 785-858
- **Estimated Time**: 1.5 hours

**Task 2: Modify Signal Emission in _process_apply_saves**
- [ ] Remove `if resolution_state.current_index < weapon_order.size()` check
- [ ] Always build remaining_weapons array (may be empty)
- [ ] Always emit `next_weapon_confirmation_required` signal
- [ ] Return with pause indicator instead of completing
- **File**: `40k/phases/ShootingPhase.gd`
- **Lines**: 1422-1487
- **Estimated Time**: 1.5 hours

**Task 3: Handle Single Weapon Case**
- [ ] Modify `_process_resolve_shooting()` to track single weapon result
- [ ] Modify `_process_apply_saves()` to emit signal for single weapon
- [ ] Test that single weapon shows dialog
- **File**: `40k/phases/ShootingPhase.gd`
- **Lines**: 427-510, 1278-1511
- **Estimated Time**: 2 hours

**Task 4: Add Completion Signal to NextWeaponDialog**
- [ ] Add `shooting_complete_confirmed` signal
- [ ] Modify `_on_continue_pressed()` to check for empty remaining_weapons
- [ ] Emit completion signal when no weapons remain
- **File**: `40k/scripts/NextWeaponDialog.gd`
- **Lines**: 1-270
- **Estimated Time**: 1 hour

**Task 5: Handle Completion in ShootingController**
- [ ] Connect to `shooting_complete_confirmed` signal
- [ ] Add `_on_shooting_complete()` handler
- [ ] Emit `COMPLETE_SHOOTING_FOR_UNIT` action
- **File**: `40k/scripts/ShootingController.gd`
- **Lines**: 1359-1551
- **Estimated Time**: 1 hour

**Task 6: Add COMPLETE_SHOOTING_FOR_UNIT Action**
- [ ] Add validation method
- [ ] Add processing method
- [ ] Handle in validate_action() and process_action()
- [ ] Mark unit as done and clear state
- **File**: `40k/phases/ShootingPhase.gd`
- **Lines**: Add new methods
- **Estimated Time**: 1.5 hours

**Task 7: Testing & Validation**
- [ ] Test multi-weapon sequential (3 weapons)
- [ ] Test multi-weapon sequential (2 weapons)
- [ ] Test single weapon
- [ ] Test final weapon shows results
- [ ] Test button text changes correctly
- [ ] Test multiplayer sync
- **Estimated Time**: 3 hours

---

## 6. Testing Strategy

### 6.1 Manual Test Scenarios

**Scenario 1: Single Weapon**
```
Setup:
- Unit with 1 weapon type (e.g., Space Marine with bolt rifles)
- Target enemy unit

Steps:
1. Select shooter unit
2. Assign weapon to target
3. Confirm targets
4. Weapon fires → Dice rolled → Saves allocated
5. ✓ CHECK: NextWeaponDialog appears
6. ✓ CHECK: Dialog shows last weapon's results (hits, wounds, casualties)
7. ✓ CHECK: Remaining weapons list shows "No remaining weapons"
8. ✓ CHECK: Button text is "Complete Shooting"
9. Click button
10. ✓ CHECK: Unit marked as has_shot, state cleared

Expected Result: Dialog shows even for single weapon
```

**Scenario 2: Two Weapons Sequential**
```
Setup:
- Unit with 2 weapon types
- Target enemy unit

Steps:
1-3. Same as Scenario 1
4. WeaponOrderDialog appears → Choose "Start Sequence"
5. First weapon fires
6. ✓ CHECK: NextWeaponDialog shows with 1 remaining weapon
7. ✓ CHECK: Button text is "Continue to Next Weapon"
8. Click Continue
9. Second weapon fires (FINAL weapon)
10. ✓ CHECK: NextWeaponDialog appears
11. ✓ CHECK: Dialog shows second weapon's results
12. ✓ CHECK: Remaining weapons shows "No remaining weapons"
13. ✓ CHECK: Button text is "Complete Shooting"
14. Click Complete
15. ✓ CHECK: Unit completes shooting

Expected Result: Dialog shows after final weapon
```

**Scenario 3: Three Weapons Sequential**
```
Setup:
- Unit with 3 weapon types (e.g., Battlewagon)
- Target enemy unit

Steps:
1-4. Same as Scenario 2
5. First weapon fires
6. ✓ CHECK: Dialog shows 2 remaining
7. Second weapon fires
8. ✓ CHECK: Dialog shows 1 remaining
9. Third weapon fires (FINAL)
10. ✓ CHECK: Dialog shows 0 remaining
11. ✓ CHECK: Button is "Complete Shooting"
12. Click Complete
13. ✓ CHECK: Unit completes

Expected Result: Dialog shows after all 3 weapons
```

**Scenario 4: Multiplayer - Single Weapon**
```
Setup:
- 2 players connected
- Player 1 shooting, Player 2 defending

Steps:
1. Player 1 selects unit with 1 weapon
2. Assigns target (Player 2's unit)
3. Confirms
4. Weapon fires
5. Player 2 allocates saves
6. ✓ CHECK: Player 1 sees NextWeaponDialog
7. ✓ CHECK: Player 2 does NOT see dialog
8. ✓ CHECK: Player 2 sees "Player 1 reviewing results..." in dice log
9. Player 1 clicks Complete
10. ✓ CHECK: Both players see unit complete

Expected Result: Only attacker sees dialog
```

### 6.2 Edge Cases

**Edge Case 1: Weapon Misses Entirely**
```
Scenario: First weapon rolls all misses (0 hits)
Expected: Dialog still shows with 0 hits, 0 wounds, 0 casualties
Result: User sees "No damage caused" clearly
```

**Edge Case 2: Weapon Hits But No Casualties**
```
Scenario: Weapon causes wounds, but all saves are passed
Expected: Dialog shows hits, wounds, but 0 casualties
Result: User sees "All wounds saved" clearly
```

**Edge Case 3: Save/Load During Dialog**
```
Scenario: Save game while NextWeaponDialog is open
Expected: On load, dialog reappears with same state
Result: User can continue from where they left off
```

---

## 7. Validation Gates

### 7.1 Syntax Validation
```bash
# Check modified scripts for syntax errors
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

godot --check-only --path . phases/ShootingPhase.gd
godot --check-only --path . scripts/ShootingController.gd
godot --check-only --path . scripts/NextWeaponDialog.gd

echo "✓ All scripts have valid syntax"
```

### 7.2 Functional Validation
```bash
# Manual testing checklist
echo "1. Single weapon: Dialog shows? [Y/N]"
echo "2. Final weapon (2-weapon seq): Dialog shows? [Y/N]"
echo "3. Final weapon (3-weapon seq): Dialog shows? [Y/N]"
echo "4. Button text correct ('Complete Shooting')? [Y/N]"
echo "5. Multiplayer: Only attacker sees dialog? [Y/N]"
echo "6. Results displayed correctly? [Y/N]"
echo "7. State cleared after completion? [Y/N]"
```

### 7.3 Success Criteria

- [ ] Single weapon shows dialog with results
- [ ] Final weapon in sequence shows dialog
- [ ] Button text is "Complete Shooting" when no weapons remain
- [ ] Button text is "Continue to Next Weapon" when weapons remain
- [ ] Multiplayer sync works correctly
- [ ] No crashes or errors
- [ ] State is properly cleared after completion
- [ ] User can clearly see results of every weapon

---

## 8. Data Structures

### 8.1 Enhanced Signal Payload

**Signal emission (when no weapons remain):**
```gdscript
emit_signal("next_weapon_confirmation_required",
    [],  # remaining_weapons is EMPTY
    current_index,  # Equals weapon_order.size()
    last_weapon_result  # Contains final weapon's data
)
```

### 8.2 Dialog State (No Weapons Remaining)

```gdscript
{
    "remaining_weapons": [],  # Empty array
    "current_index": 3,  # Equals total weapon count
    "last_weapon_result": {
        "weapon_id": "battlewagon_rokkit_launcha",
        "weapon_name": "Rokkit Launcha",
        "target_unit_id": "unit_witchseekers_001",
        "target_unit_name": "Witchseekers",
        "hits": 2,
        "wounds": 1,
        "saves_failed": 1,
        "casualties": 1,
        "total_attacks": 3,
        "dice_rolls": [...]
    }
}
```

---

## 9. References

### 9.1 Warhammer 40K Rules
- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Shooting Phase**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE
- **Making Attacks**: Hit → Wound → Allocate → Save → Damage

### 9.2 Godot Documentation
- **Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- **AcceptDialog**: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html

### 9.3 Related PRPs
- `next-weapon-confirmation-enhancement.md` - Enhanced dialog with dice results (ALREADY IMPLEMENTED)
- `weapon_order_sequence_continuation_fix.md` - Fixed empty weapon dialog bug
- `weapon_order_selection_prp.md` - Original weapon ordering system

### 9.4 Related Files
- `40k/phases/ShootingPhase.gd` (1593 lines)
  - Lines 785-858: `_resolve_next_weapon()` - Fix emission when no wounds
  - Lines 1422-1511: `_process_apply_saves()` - Fix emission after saves
  - Lines 427-510: `_process_resolve_shooting()` - Handle single weapon
  - Lines 953-977: `_get_last_weapon_result()` - Build result summary
- `40k/scripts/ShootingController.gd` (2069 lines)
  - Lines 1359-1449: `_on_next_weapon_confirmation_required()` - Connect new signal
- `40k/scripts/NextWeaponDialog.gd` (270 lines)
  - Lines 251-269: `_on_continue_pressed()` - Handle completion

---

## 10. Confidence Score

**9/10** - Very high confidence for successful implementation

### Reasoning

**Strengths:**
- ✅ Problem is well-defined and reproducible
- ✅ Root cause is clearly identified (conditional signal emission)
- ✅ Solution is straightforward (remove condition, always emit)
- ✅ Dialog already supports empty remaining_weapons (line 464-467)
- ✅ Minimal changes required (modify existing functions)
- ✅ No new files needed
- ✅ Backwards compatible with existing sequential mode
- ✅ Clear test scenarios
- ✅ Related PRP shows the dialog enhancement is already implemented

**Risks (Minor):**
- ⚠️ Multiplayer sync timing (mitigated by existing pause indicator pattern)
- ⚠️ Single weapon case requires tracking mode state (mitigated by resolution_state)
- ⚠️ New COMPLETE_SHOOTING_FOR_UNIT action needs validation (mitigated by following existing action patterns)

### Estimated Implementation Time
- **Task 1-2** (Signal emission fixes): 3 hours
- **Task 3** (Single weapon handling): 2 hours
- **Task 4-5** (Dialog completion): 2 hours
- **Task 6** (New action): 1.5 hours
- **Task 7** (Testing): 3 hours
- **Total**: 11.5 hours

### Dependencies
- No external dependencies
- Builds on existing `next-weapon-confirmation-enhancement.md` implementation (already done)
- Uses existing NextWeaponDialog infrastructure

---

## 11. Appendix

### A. Pseudocode for Core Changes

**ShootingPhase._resolve_next_weapon() fix:**
```python
def _resolve_next_weapon():
    # ... existing weapon resolution ...

    # Store weapon result
    completed_weapons.append({
        "weapon_id": weapon_id,
        "casualties": casualties,
        # ... other data ...
    })

    # Increment index
    current_index += 1

    # BUILD remaining weapons (may be empty)
    remaining_weapons = weapon_order[current_index:]
    last_weapon_result = _get_last_weapon_result()

    # ALWAYS emit signal (removed condition)
    emit_signal("next_weapon_confirmation_required",
                remaining_weapons,
                current_index,
                last_weapon_result)

    # Return with pause (removed completion logic)
    return create_result(success=True,
                        message="Awaiting confirmation",
                        data={"sequential_pause": True})
```

**NextWeaponDialog._on_continue_pressed() fix:**
```python
def _on_continue_pressed():
    if remaining_weapons.is_empty():
        # Final weapon - complete shooting
        emit_signal("shooting_complete_confirmed")
    else:
        # More weapons - continue sequence
        emit_signal("continue_confirmed", remaining_weapons, fast_roll=False)

    hide()
    queue_free()
```

### B. Migration Notes

**For Existing Saves:**
- If game is saved during shooting sequence, the fix will apply on next action
- No save file format changes required
- Existing sequential mode continues to work

**For Multiplayer:**
- Both clients need to be running the fixed version
- Network protocol unchanged (uses existing action system)
- sequential_pause indicator already exists in network sync

### C. User-Facing Changes

**Before Fix:**
```
Attacker with 2 weapons:
1. Weapon 1 fires → Dialog shows (1 remaining) ✓
2. Weapon 2 fires → No dialog, unit completes ✗
Result: Attacker doesn't see weapon 2 results!

Attacker with 1 weapon:
1. Weapon fires → No dialog, unit completes ✗
Result: Attacker doesn't see results at all!
```

**After Fix:**
```
Attacker with 2 weapons:
1. Weapon 1 fires → Dialog shows (1 remaining) ✓
2. Weapon 2 fires → Dialog shows (0 remaining) ✓
3. Click "Complete Shooting" → Unit completes ✓
Result: Attacker sees both weapon results!

Attacker with 1 weapon:
1. Weapon fires → Dialog shows (0 remaining) ✓
2. Click "Complete Shooting" → Unit completes ✓
Result: Attacker sees results!
```

---

**Version History**:
- v1.0 (2025-10-15): Initial PRP creation

**Approval**:
- [ ] Product Owner
- [ ] Tech Lead
- [ ] QA/Testing Lead
