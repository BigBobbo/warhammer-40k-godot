# Hide "Continue to Next Weapon" Button from WeaponOrderDialog - PRP
**Version**: 2.0 (CORRECTED)
**Date**: 2025-10-15
**Scope**: Hide the "Continue to Next Weapon" button from WeaponOrderDialog

## 1. Executive Summary

This PRP addresses a UI cleanup request to hide the "Continue to Next Weapon" button from the WeaponOrderDialog. This button currently appears in the weapon order selection dialog but serves no clear purpose, as users should use either "Start Sequence" or "Fast Roll All" buttons to proceed.

### 1.1 Request Clarification

**Original Request**: "Hide the 'Continue to Next Weapon' button from the window that you choose the weapon shooting order for the attacker. This is both when selecting the order for the first time, and updating the order after a weapon has shot"

**CRITICAL CORRECTION**: The existing PRP v1.0 incorrectly identified this as the NextWeaponDialog button. The actual target is the **WeaponOrderDialog** button (lines 91-100 in WeaponOrderDialog.gd).

### 1.2 Two Different "Continue to Next Weapon" Buttons

**Button 1: WeaponOrderDialog (THIS IS THE ONE TO HIDE)**
- File: `40k/scripts/WeaponOrderDialog.gd`
- Location: Lines 91-100
- Context: Shown when selecting weapon firing order
- Purpose: Originally intended for mid-sequence continuation
- **Issue**: Confusing UI - users should use "Start Sequence" or "Fast Roll All" instead
- **Action**: HIDE THIS BUTTON

**Button 2: NextWeaponDialog (DO NOT MODIFY)**
- File: `40k/scripts/NextWeaponDialog.gd`
- Location: Line 30 (OK button)
- Context: Shown AFTER a weapon completes
- Purpose: Confirm viewing results before continuing to next weapon
- **Action**: KEEP AS-IS (this is working correctly)

### 1.3 Current vs. Proposed Behavior

**Current Behavior:**
1. User assigns weapons → WeaponOrderDialog appears
2. Dialog shows 4 buttons:
   - "Fast Roll All (Skip Order)"
   - "Start Sequence"
   - "Close" (hidden initially)
   - **"Continue to Next Weapon"** ← CONFUSING (appears at same time as Start Sequence)
3. User is confused about which button to click

**Proposed Behavior:**
1. User assigns weapons → WeaponOrderDialog appears
2. Dialog shows 2 buttons (Clean UI):
   - "Fast Roll All (Skip Order)"
   - "Start Sequence"
   - "Close" (hidden initially)
3. **No "Continue to Next Weapon" button** (cleaner, less confusing)

### 1.4 Why This Button Exists

Looking at the code history:
- Line 92: Comment says "NEW: Continue button for mid-sequence progression"
- Line 96: Comment says "Make it visible by default so user can always progress"
- Line 372-384: `_on_continue_next_weapon_pressed()` handler

**Original Intent**: Allow user to continue mid-sequence with new weapon order

**Problem**: This button appears at the SAME TIME as "Start Sequence" button, creating confusion. Users should:
- Use "Start Sequence" for first-time weapon order selection
- Use NextWeaponDialog's Continue button for mid-sequence progression

## 2. Core Requirements

### 2.1 Functional Requirements
- **FR1**: Hide "Continue to Next Weapon" button from WeaponOrderDialog
- **FR2**: Keep "Start Sequence" and "Fast Roll All" buttons visible
- **FR3**: Do NOT modify NextWeaponDialog (different file)
- **FR4**: Button handler (`_on_continue_next_weapon_pressed`) can remain (for potential future use)
- **FR5**: No changes to weapon resolution logic

### 2.2 UX Requirements
- **UX1**: Cleaner WeaponOrderDialog with only 2 action buttons (down from 3)
- **UX2**: Reduced confusion about which button to click
- **UX3**: No functional regression (users can still do everything they could before)

### 2.3 Architecture Requirements
- **AR1**: Modify only `40k/scripts/WeaponOrderDialog.gd`
- **AR2**: Do NOT modify `40k/scripts/NextWeaponDialog.gd`
- **AR3**: Do NOT modify `40k/scripts/ShootingController.gd`
- **AR4**: Do NOT modify `40k/phases/ShootingPhase.gd`
- **AR5**: Single-line change (set button visibility to false)

## 3. Current Implementation Analysis

### 3.1 WeaponOrderDialog.gd Structure

**File**: `40k/scripts/WeaponOrderDialog.gd`
**Lines**: 450 total

**Relevant Code (Lines 91-100)**:
```gdscript
# NEW: Continue button for mid-sequence progression
# Make it visible by default so user can always progress
var continue_button = Button.new()
continue_button.name = "ContinueButton"
continue_button.text = "Continue to Next Weapon"
continue_button.pressed.connect(_on_continue_next_weapon_pressed)
continue_button.custom_minimum_size = Vector2(220, 40)
# Make this button prominent with green color
continue_button.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
button_hbox.add_child(continue_button)
```

**Other Buttons in button_hbox**:
- Line 72-76: `fast_roll_button` ("Fast Roll All (Skip Order)")
- Line 78-82: `start_sequence_button` ("Start Sequence")
- Line 84-89: `close_button` ("Close") - **NOTE: This is hidden by default (line 88)**
- Line 93-100: `continue_button` ("Continue to Next Weapon") - **TARGET TO HIDE**

**Button Handler (Lines 372-384)**:
```gdscript
func _on_continue_next_weapon_pressed() -> void:
	"""Continue to next weapon in sequential mode (mid-sequence)"""
	print("WeaponOrderDialog: Continue to next weapon pressed")

	# Build ordered assignments based on current weapon_order
	var ordered_assignments = []
	for weapon_id in weapon_order:
		ordered_assignments.append_array(weapon_data[weapon_id].assignments)

	# Emit with fast_roll = false to continue sequential
	emit_signal("weapon_order_confirmed", ordered_assignments, false)
	hide()
	queue_free()
```

### 3.2 Similar Pattern in Codebase

**WeaponOrderDialog.gd Line 88**: `close_button.visible = false`
- This button is created but hidden initially
- Shown later during resolution via `close_button.visible = true` (line 449)
- **We'll use the same pattern for continue_button**

**SaveDialog.gd Line 33**: `get_ok_button().hide()`
- Shows pattern of hiding buttons in AcceptDialog subclasses
- Alternative method to `.visible = false`

**NextWeaponDialog.gd Line 76**: `dice_details_panel.visible = false`
- Shows pattern of hiding UI elements by default
- Similar pattern we'll apply to continue_button

### 3.3 Where This Dialog Is Shown

**ShootingController.gd** calls WeaponOrderDialog in two places:

**1. Initial weapon order selection** (Line 1267-1325):
```gdscript
func _on_weapon_order_required(assignments: Array) -> void:
	# ... validation ...
	var dialog = weapon_order_dialog_script.new()
	dialog.weapon_order_confirmed.connect(_on_weapon_order_confirmed)
	get_tree().root.add_child(dialog)
	dialog.setup(assignments, current_phase)
	dialog.popup_centered()
```

**2. Mid-sequence weapon order update** (Line 1451-1500):
```gdscript
func _on_show_weapon_order_from_next_weapon_dialog(remaining_weapons: Array, fast_roll: bool) -> void:
	# ... validation ...
	var dialog = weapon_order_dialog_script.new()
	dialog.weapon_order_confirmed.connect(_on_next_weapon_order_confirmed)
	get_tree().root.add_child(dialog)
	dialog.setup(remaining_weapons, current_phase)
	dialog.title = "Choose Next Weapon (%d remaining)" % remaining_weapons.size()
	dialog.popup_centered()
```

**Key Observation**: In BOTH cases, the dialog shows the same buttons. The user's request asks to hide "Continue to Next Weapon" in BOTH scenarios.

## 4. Proposed Solution

### 4.1 Single-Line Fix

**Add after line 100 in WeaponOrderDialog.gd**:
```gdscript
continue_button.visible = false  # Hidden - users should use "Start Sequence" or "Fast Roll All"
```

**Complete Modified Section (Lines 91-101)**:
```gdscript
# NEW: Continue button for mid-sequence progression
# Make it visible by default so user can always progress
var continue_button = Button.new()
continue_button.name = "ContinueButton"
continue_button.text = "Continue to Next Weapon"
continue_button.pressed.connect(_on_continue_next_weapon_pressed)
continue_button.custom_minimum_size = Vector2(220, 40)
# Make this button prominent with green color
continue_button.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
button_hbox.add_child(continue_button)
continue_button.visible = false  # Hidden - users should use "Start Sequence" or "Fast Roll All"
```

### 4.2 Alternative Approaches (Not Recommended)

**Option A: Remove button entirely**
```gdscript
# Delete lines 91-100 completely
```
- **Pros**: Cleaner code, no dead code
- **Cons**: Loses potential future functionality, harder to re-enable if needed

**Option B: Use .hide() instead**
```gdscript
continue_button.hide()  # Alternative to .visible = false
```
- **Pros**: Same effect as .visible = false
- **Cons**: No advantage over .visible = false

**Option C: Comment out button creation**
```gdscript
# var continue_button = Button.new()
# ...
```
- **Pros**: Easy to re-enable
- **Cons**: Leaves commented code, not clean

**Recommendation**: Use Option from 4.1 (`.visible = false`) because:
- ✅ Follows existing pattern (close_button.visible = false)
- ✅ Easy to re-enable if requirements change
- ✅ No risk of breaking anything
- ✅ Minimal code change (one line)

### 4.3 No Other Changes Required

**Files that DO NOT need changes**:
- ❌ `NextWeaponDialog.gd` (different dialog, not in scope)
- ❌ `ShootingController.gd` (no changes needed)
- ❌ `ShootingPhase.gd` (no changes needed)
- ❌ `WeaponOrderDialog._on_continue_next_weapon_pressed` (keep handler for future use)

## 5. Implementation Tasks

### 5.1 Phase 1: Hide Button (Priority: HIGH)
**Goal**: Set continue_button.visible = false

**Tasks**:
- [x] Locate WeaponOrderDialog.gd line 100
- [ ] Add new line after line 100: `continue_button.visible = false  # Hidden - users should use "Start Sequence" or "Fast Roll All"`
- [ ] Test: Launch game, assign weapons, verify button is hidden
- [ ] Test: Complete one weapon, reorder weapons, verify button is hidden

**Files Modified**:
- `40k/scripts/WeaponOrderDialog.gd` (line 101)

**Lines Modified**:
- Add line 101 (new line after current line 100)

**Estimated Time**: 5 minutes

### 5.2 Phase 2: Testing (Priority: HIGH)
**Goal**: Verify button is hidden in all scenarios

**Test Scenarios**:
- [ ] **Scenario 1**: Assign multiple weapons → WeaponOrderDialog appears → "Continue to Next Weapon" is hidden
- [ ] **Scenario 2**: Click "Start Sequence" → Weapons resolve → NextWeaponDialog appears with Continue button (THIS SHOULD STILL WORK)
- [ ] **Scenario 3**: In NextWeaponDialog, click Continue → WeaponOrderDialog appears for reordering → "Continue to Next Weapon" is hidden
- [ ] **Scenario 4**: Click "Fast Roll All" → All weapons resolve at once (no dialog changes)

**Expected Results**:
- ✅ WeaponOrderDialog only shows 2 buttons: "Fast Roll All" and "Start Sequence"
- ✅ NextWeaponDialog (different file) STILL shows "Continue to Next Weapon" button
- ✅ No crashes, no errors
- ✅ Weapon resolution works exactly as before

**Estimated Time**: 15 minutes

## 6. Testing Requirements

### 6.1 Manual Testing Checklist
- [ ] Launch game in single-player mode
- [ ] Deploy units for both players
- [ ] Enter Shooting Phase
- [ ] Select attacker unit with multiple weapon types
- [ ] Assign weapons to targets
- [ ] Click "Confirm Targets"
- [ ] ✅ **VERIFY**: WeaponOrderDialog appears with only "Fast Roll All" and "Start Sequence" buttons
- [ ] ✅ **VERIFY**: "Continue to Next Weapon" button is NOT visible
- [ ] Click "Start Sequence"
- [ ] Wait for first weapon to complete
- [ ] ✅ **VERIFY**: NextWeaponDialog appears with "Continue to Next Weapon" button (this is CORRECT)
- [ ] Click "Continue to Next Weapon" in NextWeaponDialog
- [ ] ✅ **VERIFY**: WeaponOrderDialog appears again for reordering
- [ ] ✅ **VERIFY**: "Continue to Next Weapon" is still hidden in WeaponOrderDialog
- [ ] Complete weapon sequence
- [ ] ✅ **VERIFY**: No errors in console

### 6.2 Edge Cases to Test
- [ ] Single weapon type (WeaponOrderDialog may not appear - verify)
- [ ] Fast Roll All mode (verify no dialog changes)
- [ ] Last weapon in sequence (NextWeaponDialog should show "Complete Shooting")
- [ ] Mid-sequence weapon order change (WeaponOrderDialog should hide button)
- [ ] Multiplayer: attacker sees correct dialogs, defender does not

### 6.3 Regression Testing
- [ ] Weapon resolution still works
- [ ] Fast Roll All still works
- [ ] Sequential mode still works
- [ ] Weapon ordering still works
- [ ] NextWeaponDialog Continue button still works (NOT modified)
- [ ] Save/load during weapon sequence still works

## 7. Godot Technical Reference

### 7.1 Button Visibility Control
```gdscript
# Hide button (two equivalent methods)
button.hide()               # Method 1
button.visible = false      # Method 2 (RECOMMENDED)

# Show button (two equivalent methods)
button.show()               # Method 1
button.visible = true       # Method 2 (RECOMMENDED)

# Check visibility
if button.visible:
    print("Button is visible")
```

### 7.2 Button Class Documentation
- **Godot 4.4 Button**: https://docs.godotengine.org/en/4.4/classes/class_button.html
- **Visible Property**: https://docs.godotengine.org/en/4.4/classes/class_canvasitem.html#class-canvasitem-property-visible
- **Hide/Show Methods**: https://docs.godotengine.org/en/4.4/classes/class_canvasitem.html#class-canvasitem-method-hide

### 7.3 AcceptDialog Pattern
```gdscript
# Common pattern in AcceptDialog subclasses
func _ready() -> void:
    # Hide default OK button if using custom buttons
    get_ok_button().hide()

    # Create custom buttons
    var custom_button = Button.new()
    custom_button.visible = false  # Hide initially if needed
    add_child(custom_button)
```

## 8. Documentation References

- **Godot Button Class**: https://docs.godotengine.org/en/4.4/classes/class_button.html
- **Godot CanvasItem (Visibility)**: https://docs.godotengine.org/en/4.4/classes/class_canvasitem.html
- **Godot AcceptDialog**: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
- **Warhammer 40K Shooting Phase**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE

## 9. Validation Gates

### 9.1 Code Validation
```bash
# No automated tests for UI changes, manual verification required
# Launch Godot and test manually as per Section 6.1
```

### 9.2 Success Criteria
- ✅ "Continue to Next Weapon" button is NOT visible in WeaponOrderDialog
- ✅ "Start Sequence" and "Fast Roll All" buttons ARE visible
- ✅ NextWeaponDialog Continue button still works (NOT modified)
- ✅ No console errors
- ✅ No functional regression in weapon resolution

### 9.3 AI Agent Validation Instructions

**For the AI agent implementing this PRP**:

1. **Read the file**: `40k/scripts/WeaponOrderDialog.gd`
2. **Locate line 100**: Should end with `button_hbox.add_child(continue_button)`
3. **Add new line 101**: `continue_button.visible = false  # Hidden - users should use "Start Sequence" or "Fast Roll All"`
4. **Verify syntax**: Ensure proper indentation (tabs/spaces match surrounding code)
5. **DO NOT modify**: NextWeaponDialog.gd or any other files
6. **Test manually**: Launch game and follow test scenarios in Section 6.1
7. **Verify**: Button is hidden in WeaponOrderDialog, but NextWeaponDialog Continue button still works
8. **Report**: If button is still visible, check if line was added in correct location

## 10. Confidence Score

**Self-Assessment**: 10/10

**Reasoning**:
- ✅ Extremely simple change (one line)
- ✅ Clear understanding of the problem (button in wrong dialog)
- ✅ Follows existing patterns (close_button.visible = false)
- ✅ No risk of breaking functionality (just hiding a button)
- ✅ No changes to logic or signal flow
- ✅ Easy to revert if needed
- ✅ Well-documented in codebase (comments explain intent)
- ✅ Zero dependencies
- ✅ Zero architectural complexity

**Estimated Implementation Time**: 5 minutes (coding) + 15 minutes (testing) = **20 minutes total**

**Risk Assessment**:
- **ZERO RISK**: Hiding a button cannot break functionality
- **ZERO DEPENDENCIES**: No other files reference this button
- **EASY ROLLBACK**: Just delete the line or set to `true`

**Why 10/10 Confidence**:
This is a trivial UI change with zero risk. The button should never have been visible in the first place (based on the user's clarification). Hiding it improves UX by reducing confusion, and there's no downside.

---

## 11. Appendix

### A. Comparison: v1.0 vs v2.0 PRP

**v1.0 (INCORRECT)**:
- ❌ Targeted NextWeaponDialog button
- ❌ Proposed auto-progress timer implementation
- ❌ Complex solution (timer, countdown, auto-emit)
- ❌ High risk (new functionality)
- ❌ Estimated 2-3 hours implementation

**v2.0 (CORRECT)**:
- ✅ Targets WeaponOrderDialog button
- ✅ Simple hide button implementation
- ✅ Trivial solution (one line)
- ✅ Zero risk (just hiding UI element)
- ✅ Estimated 20 minutes implementation

**Lessons Learned**:
- Always verify WHICH dialog contains the button before proposing solution
- When multiple buttons have same text, check file paths carefully
- User request mentioned "window that you choose the weapon shooting order" → WeaponOrderDialog, NOT NextWeaponDialog

### B. Referenced Files
- `40k/scripts/WeaponOrderDialog.gd` (450 lines) - **MODIFY THIS**
- `40k/scripts/NextWeaponDialog.gd` (270 lines) - **DO NOT MODIFY**
- `40k/scripts/ShootingController.gd` (2068 lines) - **DO NOT MODIFY**
- `40k/phases/ShootingPhase.gd` (1483 lines) - **DO NOT MODIFY**

### C. Related PRPs
- `weapon_order_selection_prp.md`: Initial weapon ordering implementation
- `next-weapon-confirmation-enhancement.md`: NextWeaponDialog enhancement (DIFFERENT dialog)
- `weapon_order_sequence_continuation_fix.md`: Fix for sequence continuation

---

**Version History**:
- v1.0 (2025-10-15): Initial PRP - INCORRECT (targeted wrong dialog)
- v2.0 (2025-10-15): CORRECTED PRP - Targets WeaponOrderDialog (correct)

**Approval**:
- [ ] Product Owner
- [ ] Tech Lead
- [ ] User Confirmation (verify this is the correct button to hide)

**Notes**:
- **CRITICAL**: Verify with user that WeaponOrderDialog is the correct dialog
- If user meant NextWeaponDialog instead, revert to v1.0 approach (auto-progress)
- However, based on request wording ("window that you choose the weapon shooting order"), v2.0 is correct
