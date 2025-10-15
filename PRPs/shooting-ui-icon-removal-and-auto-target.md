# 🎯 Shooting Phase UI Improvements - Icon Removal & Auto-Target Selection

## Problem Statement

### Issue 1: Godot Icon Making Weapon Rows Too Tall
In the shooting phase right-hand panel, each weapon row displays a Godot icon button that allows auto-assigning the first available target. This icon is causing the rows to be much taller than necessary, wasting valuable screen space and making the weapon list harder to read.

**Current Behavior** (ShootingController.gd:506):
```gdscript
weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

This adds a large icon button to column 1 of each weapon row, which:
- Increases row height unnecessarily
- Uses the default Godot icon which doesn't fit the UI aesthetic
- Takes up valuable space in the compact right panel
- Duplicates functionality that could be better implemented

### Issue 2: No Bulk Target Assignment Option
When a player selects a target for the first weapon, there's no option to automatically assign the same target to all remaining weapons. This forces players to manually select the same target multiple times when all weapons are firing at the same enemy unit - a common scenario in Warhammer 40k.

**Current Workflow** (Time-consuming):
1. Select weapon 1 → Click enemy unit A
2. Select weapon 2 → Click enemy unit A
3. Select weapon 3 → Click enemy unit A
4. Repeat for all N weapons

**Desired Workflow** (Efficient):
1. Select weapon 1 → Click enemy unit A
2. Click "Apply to All" → All remaining weapons auto-assign to unit A

## Requirements

### Primary Requirements
1. **Remove Icon Button**: Eliminate the Godot icon from weapon rows to reduce row height
2. **Add Auto-Target Feature**: After first weapon target selection, provide option to apply same target to all remaining weapons
3. **Maintain Functionality**: Weapon selection and target assignment must continue to work correctly
4. **Preserve User Choice**: Users can still manually assign different targets to different weapons if desired

### Secondary Requirements
1. **Improved UX**: Weapon list should be more compact and readable
2. **Clear Visual Feedback**: User should clearly understand when auto-target option is available
3. **Godot Best Practices**: Follow standard Godot UI patterns for compact, efficient interfaces
4. **Backward Compatibility**: Don't break existing shooting phase functionality

## Implementation Context

### Current Architecture Analysis

#### Weapon Tree Structure
From `ShootingController.gd:214-222`:
```gdscript
weapon_tree = Tree.new()
weapon_tree.custom_minimum_size = Vector2(230, 120)
weapon_tree.columns = 2
weapon_tree.set_column_title(0, "Weapon")
weapon_tree.set_column_title(1, "Target")
weapon_tree.hide_root = true
weapon_tree.item_selected.connect(_on_weapon_tree_item_selected)
weapon_tree.button_clicked.connect(_on_weapon_tree_button_clicked)
```

The weapon tree has:
- **Column 0**: Weapon name with count (e.g., "Bolt Rifle (x5)")
- **Column 1**: Target selection indicator or assigned target name

#### Current Target Assignment Flow
From `ShootingController.gd:1655-1704`:

1. User selects a weapon from the tree (`_on_weapon_tree_item_selected`)
2. Selected weapon is stored in `selected_weapon_id`
3. User clicks on an enemy unit on the board
4. `_select_target_for_current_weapon()` assigns the target
5. UI updates to show the assigned target name in column 1
6. Process repeats for each weapon

#### Icon Button Implementation
From `ShootingController.gd:486-506`:
```gdscript
if eligible_targets.size() == 1:
    # Auto-assign if only one target
    var only_target_id = eligible_targets.keys()[0]
    var only_target_name = eligible_targets[only_target_id].unit_name
    weapon_item.set_text(1, only_target_name + " [AUTO]")
    weapon_item.set_custom_bg_color(1, Color(0.2, 0.6, 0.2, 0.3))
    _auto_assign_target(weapon_id, only_target_id)
else:
    weapon_item.set_text(1, "[Click to Select]")
    weapon_item.set_selectable(0, true)
    weapon_item.set_selectable(1, false)
    # THIS IS THE PROBLEMATIC LINE:
    weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

#### Button Click Handler
From `ShootingController.gd:1514-1524`:
```gdscript
func _on_weapon_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
    if not item or column != 1:
        return

    var weapon_id = item.get_metadata(0)
    if not weapon_id or eligible_targets.is_empty():
        return

    # Auto-assign first available target
    var first_target = eligible_targets.keys()[0]
    _select_target_for_current_weapon(first_target)
```

### Similar Patterns in Codebase

#### FightController Uses Same Pattern
From `FightController.gd:431`:
```gdscript
weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

**Note**: This solution should be applied to FightController as well for consistency.

### Files Requiring Modification

1. **ShootingController.gd** (Primary)
   - Remove icon button from `_refresh_weapon_tree()` (line 506)
   - Add "Apply to All" button UI element
   - Implement auto-target logic for bulk assignment
   - Handle user preference between bulk and individual assignment

2. **FightController.gd** (Consistency)
   - Apply same icon removal for melee weapon selection

## External Documentation References

### Godot UI Best Practices
- **Tree Control Documentation**: https://docs.godotengine.org/en/4.4/classes/class_tree.html
  - Tree widget for hierarchical data display
  - Column management and item selection
  - Button handling in tree items

- **TreeItem Documentation**: https://docs.godotengine.org/en/4.4/classes/class_treeitem.html
  - `add_button()` method and parameters
  - Text and color customization methods
  - Selection and interaction patterns

- **UI Best Practices**: https://docs.godotengine.org/en/4.4/tutorials/ui/index.html
  - Compact UI design principles
  - Button and control sizing
  - Visual hierarchy and user flow

### Warhammer 40k Rules Context
- **Shooting Phase Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE
  - Target selection principles
  - Weapon firing restrictions
  - Common tactical patterns (multiple weapons → same target)

## Implementation Blueprint

### Strategy Overview

**Two-Part Solution**:
1. **Part 1 (Icon Removal)**: Remove the icon button to make weapon rows compact
2. **Part 2 (Auto-Target)**: Add "Apply to All" functionality after first target selection

### Part 1: Remove Icon Button

#### Task 1: Remove Icon from Weapon Tree Creation

**File**: `40k/scripts/ShootingController.gd`
**Location**: `_refresh_weapon_tree()` function around line 500-506

**Current Code**:
```gdscript
else:
    weapon_item.set_text(1, "[Click to Select]")
    weapon_item.set_selectable(0, true)
    weapon_item.set_selectable(1, false)

    # Add a button to auto-assign the first available target
    weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

**New Code**:
```gdscript
else:
    weapon_item.set_text(1, "[Click to Select]")
    weapon_item.set_selectable(0, true)
    weapon_item.set_selectable(1, false)
    # REMOVED: Icon button that was making rows too tall
    # Users can select weapon, then click enemy unit to assign target
```

**Rationale**:
- Users already have a clear workflow: select weapon → click enemy
- The icon button was redundant and took up valuable space
- Tree rows will now be much more compact

#### Task 2: Remove Redundant Button Click Handler

**File**: `40k/scripts/ShootingController.gd`
**Location**: `_on_weapon_tree_button_clicked()` function around line 1514-1524

**Action**:
```gdscript
# This function is no longer needed since we removed the button
# However, KEEP it for now in case we need it for Part 2 implementation
# We can repurpose it for the "Apply to All" button later
```

**Note**: Don't delete the function yet - we'll repurpose it for the "Apply to All" feature.

#### Task 3: Apply Same Fix to FightController

**File**: `40k/scripts/FightController.gd`
**Location**: Around line 431

**Current Code**:
```gdscript
# Add auto-assign button
weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

**New Code**:
```gdscript
# REMOVED: Icon button for consistency with ShootingController
# Users can select weapon, then click enemy unit to assign target
```

### Part 2: Add "Apply to All" Auto-Target Feature

#### Task 4: Add UI Button for Auto-Target

**File**: `40k/scripts/ShootingController.gd`
**Location**: `_setup_right_panel()` function, after weapon tree creation (around line 222)

**Add New UI Element**:
```gdscript
# After weapon_tree creation and before shooting_panel.add_child(weapon_tree)

# Create "Apply to All" button container (initially hidden)
var auto_target_container = HBoxContainer.new()
auto_target_container.name = "AutoTargetContainer"
auto_target_container.visible = false  # Hidden until first weapon assigned

var auto_target_label = Label.new()
auto_target_label.text = "Same target for all:"
auto_target_container.add_child(auto_target_label)

var apply_to_all_button = Button.new()
apply_to_all_button.name = "ApplyToAllButton"
apply_to_all_button.text = "Apply to All Weapons"
apply_to_all_button.custom_minimum_size = Vector2(150, 30)
apply_to_all_button.pressed.connect(_on_apply_to_all_pressed)
auto_target_container.add_child(apply_to_all_button)

shooting_panel.add_child(auto_target_container)
shooting_panel.add_child(weapon_tree)

# Store reference for later access
auto_target_button_container = auto_target_container
```

**Add to Class Variables** (around line 40):
```gdscript
var auto_target_button_container: HBoxContainer  # Reference to auto-target UI
var last_assigned_target_id: String = ""  # Track last assigned target for "Apply to All"
```

#### Task 5: Show Auto-Target Button After First Assignment

**File**: `40k/scripts/ShootingController.gd`
**Location**: `_select_target_for_current_weapon()` function (around line 1655-1704)

**Enhance Function**:
```gdscript
func _select_target_for_current_weapon(target_id: String) -> void:
    # ... existing code ...

    # Assign target
    weapon_assignments[weapon_id] = target_id

    # NEW: Store last assigned target for "Apply to All" feature
    last_assigned_target_id = target_id

    # NEW: Show "Apply to All" button if:
    # 1. This is not the last weapon
    # 2. There are unassigned weapons remaining
    var unassigned_count = _count_unassigned_weapons()
    if unassigned_count > 0 and auto_target_button_container:
        auto_target_button_container.visible = true

        # Update button text to show how many weapons will be affected
        var apply_button = auto_target_button_container.get_node_or_null("ApplyToAllButton")
        if apply_button:
            apply_button.text = "Apply to %d Remaining Weapons" % unassigned_count

    # ... rest of existing code ...
```

#### Task 6: Implement "Apply to All" Logic

**File**: `40k/scripts/ShootingController.gd`
**Location**: New function

**Add New Function**:
```gdscript
func _on_apply_to_all_pressed() -> void:
    """Apply the last assigned target to all unassigned weapons"""
    if last_assigned_target_id == "" or not eligible_targets.has(last_assigned_target_id):
        print("ERROR: No valid target to apply")
        return

    var target_name = eligible_targets.get(last_assigned_target_id, {}).get("unit_name", last_assigned_target_id)

    # Get all weapons from the tree
    var root = weapon_tree.get_root()
    if not root:
        return

    var assigned_count = 0
    var child = root.get_first_child()

    while child:
        var weapon_id = child.get_metadata(0)

        # Check if this weapon is not yet assigned
        if weapon_id and not weapon_assignments.has(weapon_id):
            # Get model IDs for this weapon
            var model_ids = []
            var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
            for model_id in unit_weapons:
                if weapon_id in unit_weapons[model_id]:
                    model_ids.append(model_id)

            # Assign target
            weapon_assignments[weapon_id] = last_assigned_target_id

            # Update UI for this weapon
            child.set_text(1, target_name)
            child.set_custom_bg_color(1, Color(0.4, 0.2, 0.2, 0.5))

            # Build payload for network sync
            var payload = {
                "weapon_id": weapon_id,
                "target_unit_id": last_assigned_target_id,
                "model_ids": model_ids
            }

            # Add modifiers if they exist
            if weapon_modifiers.has(weapon_id):
                payload["modifiers"] = weapon_modifiers[weapon_id]

            # Emit assignment action
            emit_signal("shoot_action_requested", {
                "type": "ASSIGN_TARGET",
                "payload": payload
            })

            assigned_count += 1

        child = child.get_next()

    # Hide the "Apply to All" button since all weapons are now assigned
    if auto_target_button_container:
        auto_target_button_container.visible = false

    # Show feedback
    if dice_log_display:
        dice_log_display.append_text("[color=green]✓ Applied target %s to %d weapons[/color]\n" %
            [target_name, assigned_count])

    # Update UI state
    _update_ui_state()

func _count_unassigned_weapons() -> int:
    """Count how many weapons don't have targets assigned yet"""
    var root = weapon_tree.get_root()
    if not root:
        return 0

    var unassigned = 0
    var child = root.get_first_child()

    while child:
        var weapon_id = child.get_metadata(0)
        if weapon_id and not weapon_assignments.has(weapon_id):
            unassigned += 1
        child = child.get_next()

    return unassigned
```

#### Task 7: Hide Button When Appropriate

**File**: `40k/scripts/ShootingController.gd`
**Location**: Update various functions

**Clear Button on New Unit Selection**:
```gdscript
func _on_unit_selected_for_shooting(unit_id: String) -> void:
    # ... existing code ...

    # NEW: Hide auto-target button when selecting new shooter
    if auto_target_button_container:
        auto_target_button_container.visible = false
    last_assigned_target_id = ""

    # ... rest of existing code ...
```

**Clear Button on Clear All**:
```gdscript
func _on_clear_pressed() -> void:
    emit_signal("shoot_action_requested", {
        "type": "CLEAR_ALL_ASSIGNMENTS"
    })
    weapon_assignments.clear()

    # NEW: Hide auto-target button
    if auto_target_button_container:
        auto_target_button_container.visible = false
    last_assigned_target_id = ""

    _update_ui_state()
```

## Validation Gates

### Syntax & Runtime Checks
```bash
# Godot syntax validation
export PATH="$HOME/bin:$PATH"
godot --check-only

# Runtime validation
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH" && godot --headless --quit-after 3
```

### Manual Testing Scenarios

#### Test 1: Icon Removal Verification
1. Start game and enter shooting phase
2. Select a unit with multiple weapons (e.g., Intercessors with 5 bolt rifles)
3. **Verify**: Weapon tree rows are compact, no large icons visible
4. **Verify**: Tree is easier to read with smaller row height
5. Click on a weapon → click on enemy unit
6. **Verify**: Target assignment still works correctly

#### Test 2: "Apply to All" Feature - Basic Usage
1. Enter shooting phase
2. Select unit with 3+ different weapons
3. Select first weapon in tree
4. Click on enemy unit A to assign target
5. **Verify**: "Apply to X Remaining Weapons" button appears
6. Click "Apply to All" button
7. **Verify**: All remaining weapons now show enemy unit A as target
8. **Verify**: Dice log shows confirmation message
9. **Verify**: "Apply to All" button is now hidden

#### Test 3: "Apply to All" Feature - Partial Assignment
1. Select unit with 4 weapons
2. Assign weapon 1 → enemy unit A
3. Assign weapon 2 → enemy unit B (different target)
4. **Verify**: "Apply to 2 Remaining Weapons" button visible
5. Click "Apply to All"
6. **Verify**: Only weapons 3 and 4 are assigned to unit B
7. **Verify**: Weapons 1 and 2 retain their original assignments

#### Test 4: Edge Cases
1. **Single Weapon Unit**: Select unit with only 1 weapon
   - **Verify**: No "Apply to All" button appears (nothing to apply to)
2. **Single Target Available**: Unit with auto-assigned targets
   - **Verify**: All weapons auto-assigned, no "Apply to All" needed
3. **Clearing Assignments**: Click "Clear All"
   - **Verify**: "Apply to All" button disappears
4. **Changing Shooter**: Select different unit
   - **Verify**: "Apply to All" button resets/hides

#### Test 5: Multiplayer Sync
1. Start multiplayer game
2. Player 1 assigns targets using "Apply to All"
3. **Verify**: Player 2 sees all weapon assignments synced correctly
4. **Verify**: No duplicate assignments or state desync

### Automated Testing (Future Enhancement)
```gdscript
# Test case for _count_unassigned_weapons()
func test_count_unassigned_weapons():
    # Setup weapon tree with 3 weapons
    # Assign 1 weapon
    # Assert count returns 2

# Test case for _on_apply_to_all_pressed()
func test_apply_to_all():
    # Setup weapon tree with 3 weapons
    # Assign weapon 1 to target A
    # Call _on_apply_to_all_pressed()
    # Assert weapons 2 and 3 now assigned to target A
```

## Tasks to Complete (In Order)

### Phase 1: Icon Removal (Quick Win)
1. **Remove icon button from ShootingController** (Task 1)
   - Locate `_refresh_weapon_tree()` around line 506
   - Comment out or remove `weapon_item.add_button()` line
   - Test weapon tree display is more compact
   - Verify target assignment still works

2. **Remove icon button from FightController** (Task 3)
   - Apply same change to maintain consistency
   - Test melee weapon selection works correctly

3. **Test icon removal** (Test 1)
   - Verify compact UI
   - Verify functionality unchanged
   - No visual artifacts or layout issues

### Phase 2: Auto-Target Feature (Enhanced UX)
4. **Add UI components** (Task 4)
   - Add class variables for container and last target
   - Create HBoxContainer with button
   - Position below weapon tree
   - Initially hidden

5. **Implement visibility logic** (Task 5)
   - Show button after first assignment
   - Update button text with count
   - Hide when appropriate

6. **Implement bulk assignment logic** (Task 6)
   - Create `_on_apply_to_all_pressed()` function
   - Create `_count_unassigned_weapons()` helper
   - Handle network sync properly
   - Update UI feedback

7. **Add cleanup handlers** (Task 7)
   - Hide button on new unit selection
   - Hide button on clear all
   - Reset last_assigned_target_id

8. **Comprehensive testing** (Tests 2-5)
   - Test basic usage
   - Test partial assignment
   - Test edge cases
   - Test multiplayer sync

## Success Criteria

### Part 1: Icon Removal
- [ ] Weapon tree rows are visibly more compact (smaller height)
- [ ] No Godot icon visible in weapon rows
- [ ] Weapon selection and target assignment still works perfectly
- [ ] FightController also has compact weapon rows
- [ ] Visual appearance is cleaner and more professional

### Part 2: Auto-Target Feature
- [ ] "Apply to All" button appears after first weapon target assignment
- [ ] Button text shows accurate count of remaining weapons
- [ ] Clicking button assigns same target to all unassigned weapons
- [ ] Button disappears when all weapons assigned or assignments cleared
- [ ] Dice log shows confirmation of bulk assignment
- [ ] Works correctly in both single-player and multiplayer
- [ ] Partial assignments work (some weapons already assigned to different targets)
- [ ] Edge cases handled gracefully (single weapon, single target, etc.)

## Error Handling Strategy

1. **Null Safety**: Check container and button existence before operations
2. **State Validation**: Verify `last_assigned_target_id` is valid before applying
3. **Empty Tree Handling**: Gracefully handle case where weapon tree is empty
4. **Network Sync**: Ensure all assignments emit proper signals for multiplayer
5. **Defensive Programming**: Validate weapon_id and target_id before assignment

## Expected Outcome

### Visual Improvements
**Before**:
- Weapon rows are tall due to large icon buttons
- Tree takes up excessive vertical space
- Only 3-4 weapons visible without scrolling

**After**:
- Weapon rows are compact, text-only (except when auto-assigned)
- More weapons visible in same space
- Cleaner, more professional appearance

### UX Improvements
**Before**:
- Must manually assign each weapon to same target
- 5 weapons → 5 individual clicks on enemy unit
- Repetitive and time-consuming

**After**:
- Assign first weapon → click "Apply to All"
- 5 weapons → 2 clicks total (first assignment + apply)
- Fast, efficient, less repetitive

## Confidence Score: 9/10

**High Confidence Factors**:
- Clear understanding of the problem and current implementation
- Existing code patterns to follow (weapon assignment, UI updates)
- Well-defined UI hierarchy and component structure
- Similar patterns exist in codebase (auto-assignment for single target)
- Straightforward DOM manipulation with Godot Tree/TreeItem

**Minor Risk Factors**:
- Need to ensure multiplayer sync for bulk assignments (multiple signals)
- Button visibility logic must handle all edge cases correctly
- UI layout changes might need minor adjustments for perfect fit

**Mitigation**:
- Reuse existing `emit_signal("shoot_action_requested", ...)` pattern
- Comprehensive edge case testing in Test 4
- Godot's automatic layout should handle button sizing well

This PRP provides a clear, implementable solution to both issues with minimal risk and maximum UX improvement.
