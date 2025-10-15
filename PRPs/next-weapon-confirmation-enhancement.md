# Next Weapon Confirmation Enhancement - PRP
**Version**: 1.0
**Date**: 2025-10-15
**Scope**: Enhance weapon progression feedback in sequential shooting

## 1. Executive Summary

This PRP addresses a UX issue in sequential weapon resolution where attackers cannot see dice roll results before being prompted to continue to the next weapon. Currently, when a weapon completes (either by causing damage or missing entirely), the NextWeaponDialog appears immediately, potentially before the attacker has had time to process the dice roll results in the dice log.

**The Problem:**
> "The attacker rolls to shoot a weapon, if it fails then it cycles to the next weapon. This is correct but it is causing confusion as the attacker does not see the result of the dice rolls. As opposed to automatically progressing to the next weapon add a button that prompts the attacker to move to the next weapon."

**Current Behavior:**
1. Weapon fires → dice rolls displayed in dice log
2. If saves required → SaveDialog appears for defender
3. After saves (or if no hits) → NextWeaponDialog appears **immediately**
4. Attacker may not see dice results clearly before dialog appears

**Proposed Solution:**
Enhance NextWeaponDialog to display:
- Last weapon's dice roll summary (hits, wounds, saves, casualties)
- Clear visual feedback about what just happened
- More prominent "Continue" button to give attacker control
- Option to review detailed dice log before continuing

**Key Improvements:**
- **Visibility**: Dice results prominently displayed in confirmation dialog
- **Control**: Attacker must explicitly confirm before continuing
- **Context**: Shows what happened with last weapon before moving forward
- **Clarity**: Clear visual hierarchy separating completed weapon from remaining weapons

## 2. Core Requirements

### 2.1 Functional Requirements
- **FR1**: NextWeaponDialog displays last weapon's complete attack summary
- **FR2**: Summary includes: weapon name, target, hits, wounds, saves failed, casualties
- **FR3**: Dialog shows dice roll details (raw rolls, modified rolls, rerolls)
- **FR4**: "Continue" button is prominent and requires explicit click
- **FR5**: Remaining weapons list clearly separated from completed weapon summary
- **FR6**: Dialog supports both "weapon hit but caused 0 casualties" and "weapon missed entirely" states
- **FR7**: Color coding for different results (green for hits, red for misses, yellow for saves)
- **FR8**: Expandable dice log section showing full resolution details

### 2.2 Rules Compliance
- **RC1**: No changes to attack resolution mechanics
- **RC2**: Dialog does not alter weapon order or assignments
- **RC3**: Only attacker sees and interacts with dialog (multiplayer)

### 2.3 Multiplayer Requirements
- **MR1**: Dialog appears only for attacking player
- **MR2**: Defender/spectators see "Attacker reviewing results..." message
- **MR3**: Dialog state preserved across save/load
- **MR4**: Network timeout if attacker doesn't respond within 60 seconds

### 2.4 Architecture Requirements
- **AR1**: Modify existing NextWeaponDialog.gd (don't create new file)
- **AR2**: Receive dice data from ShootingPhase via signal
- **AR3**: Support save/load at any point during dialog display
- **AR4**: Follow existing dialog patterns (AcceptDialog base, popup_centered)

## 3. Current Implementation Analysis

### 3.1 Existing Files
**NextWeaponDialog.gd** (40k/scripts/NextWeaponDialog.gd):
- Currently shows: remaining weapons list, hint about reordering
- Does NOT show: dice results, casualties, hits/wounds summary
- Has basic continue button
- Lines 1-72

**ShootingPhase.gd** (40k/phases/ShootingPhase.gd):
- Emits `next_weapon_confirmation_required` signal (line 14)
- Emitted after weapon with 0 hits (line 775)
- Emitted after saves complete for current weapon (line 1362)
- Passes: remaining_weapons array, current_index

**ShootingController.gd** (40k/scripts/ShootingController.gd):
- Connects to `next_weapon_confirmation_required` signal (line 367-370)
- Handler: `_on_next_weapon_confirmation_required` (line 1359-1448)
- Creates NextWeaponDialog and calls setup()
- Connects to dialog's continue_confirmed signal

### 3.2 Signal Flow (Current)
```
ShootingPhase._resolve_next_weapon()
  ↓ (if 0 hits OR after saves complete)
emit next_weapon_confirmation_required(remaining_weapons, current_index)
  ↓
ShootingController._on_next_weapon_confirmation_required()
  ↓
Create NextWeaponDialog
  ↓
dialog.setup(remaining_weapons, current_index)
  ↓
dialog.popup_centered()
  ↓
User clicks Continue
  ↓
emit continue_confirmed(remaining_weapons)
  ↓
ShootingController._on_next_weapon_order_confirmed()
  ↓
Submit CONTINUE_SEQUENCE action
```

### 3.3 Missing Data
**Current signal payload:**
```gdscript
next_weapon_confirmation_required.emit(remaining_weapons, current_index)
```

**What's missing:**
- Last weapon's dice results (hit rolls, wound rolls, save rolls)
- Last weapon's attack summary (hits, wounds, casualties)
- Last weapon's name and target
- Whether weapon missed entirely vs. caused 0 casualties

## 4. Proposed Solution

### 4.1 Enhanced Signal Payload

**Modify ShootingPhase signal emission:**
```gdscript
# In ShootingPhase.gd, update signal definition (line 14)
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary)

# Emission points update (lines 775, 1362)
emit_signal("next_weapon_confirmation_required",
    remaining_weapons,
    resolution_state.current_index,
    _get_last_weapon_result()  # NEW: Package last weapon's complete results
)

func _get_last_weapon_result() -> Dictionary:
    """Build complete result summary for last weapon"""
    var completed = resolution_state.completed_weapons
    if completed.is_empty():
        return {}

    var last_weapon = completed[completed.size() - 1]
    var weapon_profile = RulesEngine.get_weapon_profile(last_weapon.weapon_id)

    return {
        "weapon_id": last_weapon.weapon_id,
        "weapon_name": weapon_profile.get("name", last_weapon.weapon_id),
        "target_unit_id": last_weapon.get("target_unit_id", ""),
        "target_unit_name": last_weapon.get("target_unit_name", "Unknown"),
        "hits": last_weapon.get("hits", 0),
        "wounds": last_weapon.get("wounds", 0),
        "saves_failed": last_weapon.get("saves_failed", 0),
        "casualties": last_weapon.get("casualties", 0),
        "dice_rolls": last_weapon.get("dice_rolls", []),  # Raw dice data
        "total_attacks": last_weapon.get("total_attacks", 0),
        "skipped": last_weapon.get("skipped", false),
        "skip_reason": last_weapon.get("skip_reason", "")
    }
```

### 4.2 Store Dice Data in resolution_state

**Modify ShootingPhase._resolve_next_weapon()** to capture dice data:
```gdscript
# After RulesEngine.resolve_shoot_until_wounds() call (around line 708)
var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

# Extract dice data for storage
var dice_data = result.get("dice", [])
var hit_data = {}
var wound_data = {}

for dice_block in dice_data:
    var context = dice_block.get("context", "")
    if context == "hit_roll":
        hit_data = {
            "rolls": dice_block.get("rolls_raw", []),
            "modified_rolls": dice_block.get("rolls_modified", []),
            "successes": dice_block.get("successes", 0),
            "total": dice_block.get("rolls_raw", []).size(),
            "rerolls": dice_block.get("rerolls", [])
        }
    elif context == "wound_roll":
        wound_data = {
            "rolls": dice_block.get("rolls_raw", []),
            "modified_rolls": dice_block.get("rolls_modified", []),
            "successes": dice_block.get("successes", 0),
            "total": dice_block.get("rolls_raw", []).size()
        }

# When adding to completed_weapons (lines 733-737, 1308-1312)
resolution_state.completed_weapons.append({
    "weapon_id": weapon_id,
    "target_unit_id": current_assignment.target_unit_id,
    "target_unit_name": target_unit.get("meta", {}).get("name", current_assignment.target_unit_id),
    "wounds": pending_save_data.size() if not pending_save_data.is_empty() else 0,
    "casualties": total_casualties,
    "hits": hit_data.get("successes", 0),
    "total_attacks": hit_data.get("total", 0),
    "dice_rolls": dice_data,  # Store complete dice log
    "hit_data": hit_data,
    "wound_data": wound_data
})
```

### 4.3 Enhanced NextWeaponDialog UI

**New Layout Structure:**
```
┌─────────────────────────────────────────────────────┐
│              WEAPON RESOLUTION COMPLETE              │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Last Weapon: Plasma Gun x2 → Ork Boyz              │
│                                                      │
│  ┌────────────────────────────────────────────┐     │
│  │  ATTACK SUMMARY                            │     │
│  ├────────────────────────────────────────────┤     │
│  │  🎲 Hit Rolls:    3 hits / 4 shots         │     │
│  │  🎯 Wound Rolls:  2 wounds / 3 hits        │     │
│  │  🛡️ Saves Failed: 1 failed / 2 wounds      │     │
│  │  ☠️  Casualties:   1 Ork Boy destroyed     │     │
│  └────────────────────────────────────────────┘     │
│                                                      │
│  ▼ Show Detailed Dice Rolls                         │
│  ┌────────────────────────────────────────────┐     │
│  │ Hit Rolls: [4, 2, 5, 3] → 3 successes      │     │
│  │ Wound Rolls: [5, 2, 4] → 2 successes       │     │
│  │ Saves: [3, 6] → 1 failed (6+ save)         │     │
│  └────────────────────────────────────────────┘     │
│                                                      │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Remaining Weapons (2):                              │
│  ┌────────────────────────────────────────────┐     │
│  │  1. Bolt Rifles x5 → Ork Boyz              │     │
│  │  2. Grenades x1 → Gretchin                 │     │
│  └────────────────────────────────────────────┘     │
│                                                      │
├─────────────────────────────────────────────────────┤
│                                                      │
│          [Continue to Next Weapon]                   │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**GDScript Implementation:**
```gdscript
extends AcceptDialog

# NextWeaponDialog - Enhanced to show last weapon's results before continuing

signal continue_confirmed(weapon_order: Array)

var remaining_weapons: Array = []
var current_index: int = 0
var last_weapon_result: Dictionary = {}

# UI Elements
var main_vbox: VBoxContainer
var weapon_name_label: Label
var attack_summary_panel: PanelContainer
var summary_grid: GridContainer
var dice_details_button: Button
var dice_details_panel: PanelContainer
var dice_details_log: RichTextLabel
var remaining_weapons_list: ItemList
var continue_button: Button

func _ready() -> void:
    title = "Weapon Resolution Complete"
    dialog_hide_on_ok = false
    min_size = Vector2(600, 500)
    get_ok_button().hide()

    _create_ui()

func _create_ui() -> void:
    main_vbox = VBoxContainer.new()
    main_vbox.custom_minimum_size = Vector2(580, 480)
    add_child(main_vbox)

    # Last weapon header
    weapon_name_label = Label.new()
    weapon_name_label.add_theme_font_size_override("font_size", 16)
    weapon_name_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
    weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    main_vbox.add_child(weapon_name_label)

    main_vbox.add_child(HSeparator.new())

    # Attack Summary Section
    var summary_label = Label.new()
    summary_label.text = "ATTACK SUMMARY"
    summary_label.add_theme_font_size_override("font_size", 14)
    main_vbox.add_child(summary_label)

    attack_summary_panel = PanelContainer.new()
    attack_summary_panel.custom_minimum_size = Vector2(560, 120)
    main_vbox.add_child(attack_summary_panel)

    summary_grid = GridContainer.new()
    summary_grid.columns = 2
    attack_summary_panel.add_child(summary_grid)

    # Dice Details Toggle
    dice_details_button = Button.new()
    dice_details_button.text = "▼ Show Detailed Dice Rolls"
    dice_details_button.flat = true
    dice_details_button.pressed.connect(_on_toggle_dice_details)
    main_vbox.add_child(dice_details_button)

    # Dice Details Panel (collapsible)
    dice_details_panel = PanelContainer.new()
    dice_details_panel.visible = false
    dice_details_panel.custom_minimum_size = Vector2(560, 100)
    main_vbox.add_child(dice_details_panel)

    dice_details_log = RichTextLabel.new()
    dice_details_log.bbcode_enabled = true
    dice_details_log.fit_content = true
    dice_details_panel.add_child(dice_details_log)

    main_vbox.add_child(HSeparator.new())

    # Remaining Weapons Section
    var remaining_label = Label.new()
    remaining_label.text = "Remaining Weapons:"
    remaining_label.add_theme_font_size_override("font_size", 14)
    main_vbox.add_child(remaining_label)

    remaining_weapons_list = ItemList.new()
    remaining_weapons_list.custom_minimum_size = Vector2(560, 100)
    main_vbox.add_child(remaining_weapons_list)

    main_vbox.add_child(HSeparator.new())

    # Continue Button (prominent)
    continue_button = Button.new()
    continue_button.text = "Continue to Next Weapon"
    continue_button.custom_minimum_size = Vector2(300, 50)
    continue_button.add_theme_font_size_override("font_size", 16)
    continue_button.pressed.connect(_on_continue_pressed)

    var button_container = HBoxContainer.new()
    button_container.alignment = BoxContainer.ALIGNMENT_CENTER
    button_container.add_child(continue_button)
    main_vbox.add_child(button_container)

func setup(weapons: Array, index: int, last_result: Dictionary) -> void:
    remaining_weapons = weapons
    current_index = index
    last_weapon_result = last_result

    _populate_last_weapon_summary()
    _populate_remaining_weapons()

func _populate_last_weapon_summary() -> void:
    if last_weapon_result.is_empty():
        weapon_name_label.text = "No weapon data available"
        return

    var weapon_name = last_weapon_result.get("weapon_name", "Unknown")
    var target_name = last_weapon_result.get("target_unit_name", "Unknown")
    weapon_name_label.text = "Last Weapon: %s → %s" % [weapon_name, target_name]

    # Check if weapon was skipped
    if last_weapon_result.get("skipped", false):
        var skip_reason = last_weapon_result.get("skip_reason", "Unknown reason")
        _show_skipped_message(skip_reason)
        return

    # Populate summary grid
    summary_grid.clear()

    var hits = last_weapon_result.get("hits", 0)
    var total_attacks = last_weapon_result.get("total_attacks", 0)
    var wounds = last_weapon_result.get("wounds", 0)
    var saves_failed = last_weapon_result.get("saves_failed", 0)
    var casualties = last_weapon_result.get("casualties", 0)

    # Hit Rolls Row
    _add_summary_row("🎲 Hit Rolls:", "%d hits / %d shots" % [hits, total_attacks],
        hits > 0 ? Color.GREEN : Color.RED)

    # Wound Rolls Row (only if hits > 0)
    if hits > 0:
        _add_summary_row("🎯 Wound Rolls:", "%d wounds / %d hits" % [wounds, hits],
            wounds > 0 ? Color.GREEN : Color.YELLOW)

    # Saves Row (only if wounds > 0)
    if wounds > 0:
        _add_summary_row("🛡️ Saves:", "%d failed / %d wounds" % [saves_failed, wounds],
            saves_failed > 0 ? Color.ORANGE : Color.GREEN)

    # Casualties Row
    _add_summary_row("☠️  Casualties:", "%d destroyed" % casualties,
        casualties > 0 ? Color.RED : Color.GRAY)

    # Populate dice details
    _populate_dice_details()

func _add_summary_row(label_text: String, value_text: String, color: Color) -> void:
    var label = Label.new()
    label.text = label_text
    label.add_theme_font_size_override("font_size", 14)
    summary_grid.add_child(label)

    var value = Label.new()
    value.text = value_text
    value.add_theme_font_size_override("font_size", 14)
    value.add_theme_color_override("font_color", color)
    summary_grid.add_child(value)

func _show_skipped_message(reason: String) -> void:
    summary_grid.clear()
    var message = Label.new()
    message.text = "⚠️ Weapon Skipped: %s" % reason
    message.add_theme_font_size_override("font_size", 14)
    message.add_theme_color_override("font_color", Color.YELLOW)
    summary_grid.add_child(message)

    # Hide dice details for skipped weapons
    dice_details_button.visible = false

func _populate_dice_details() -> void:
    if not dice_details_log:
        return

    dice_details_log.clear()

    var dice_rolls = last_weapon_result.get("dice_rolls", [])
    if dice_rolls.is_empty():
        dice_details_log.add_text("No dice roll data available")
        return

    for dice_block in dice_rolls:
        var context = dice_block.get("context", "Unknown")
        var rolls_raw = dice_block.get("rolls_raw", [])
        var rolls_modified = dice_block.get("rolls_modified", [])
        var successes = dice_block.get("successes", 0)
        var threshold = dice_block.get("threshold", "")
        var rerolls = dice_block.get("rerolls", [])

        # Format context name
        var display_context = context.capitalize().replace("_", " ")
        dice_details_log.append_text("[b]%s[/b] (need %s):\n" % [display_context, threshold])

        # Show rerolls if any
        if not rerolls.is_empty():
            dice_details_log.append_text("  [color=yellow]Re-rolled:[/color] ")
            for reroll in rerolls:
                dice_details_log.append_text("[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to])
            dice_details_log.append_text("\n")

        # Show rolls
        var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
        dice_details_log.append_text("  Rolls: %s\n" % str(display_rolls))
        dice_details_log.append_text("  → [b][color=green]%d successes[/color][/b]\n\n" % successes)

func _populate_remaining_weapons() -> void:
    if not remaining_weapons_list:
        return

    remaining_weapons_list.clear()

    if remaining_weapons.is_empty():
        remaining_weapons_list.add_item("No remaining weapons")
        continue_button.text = "Complete Shooting"
        return

    for i in range(remaining_weapons.size()):
        var weapon_assignment = remaining_weapons[i]
        var weapon_id = weapon_assignment.get("weapon_id", "")

        if weapon_id == "":
            push_error("NextWeaponDialog: Weapon at index %d has EMPTY weapon_id!" % i)
            continue

        var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
        var weapon_name = weapon_profile.get("name", weapon_id)
        var target_unit_id = weapon_assignment.get("target_unit_id", "")
        var target_unit = GameState.get_unit(target_unit_id)
        var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

        remaining_weapons_list.add_item("%d. %s → %s" % [i + 1, weapon_name, target_name])
        remaining_weapons_list.set_item_metadata(i, weapon_assignment)

func _on_toggle_dice_details() -> void:
    dice_details_panel.visible = not dice_details_panel.visible
    if dice_details_panel.visible:
        dice_details_button.text = "▲ Hide Detailed Dice Rolls"
    else:
        dice_details_button.text = "▼ Show Detailed Dice Rolls"

func _on_continue_pressed() -> void:
    print("NextWeaponDialog: Continue pressed")
    emit_signal("continue_confirmed", remaining_weapons)
    hide()
    queue_free()
```

### 4.4 ShootingController Updates

**Update signal connection:**
```gdscript
# In ShootingController.set_phase() (around line 367)
if phase.next_weapon_confirmation_required.is_connected(_on_next_weapon_confirmation_required):
    phase.next_weapon_confirmation_required.disconnect(_on_next_weapon_confirmation_required)
phase.next_weapon_confirmation_required.connect(_on_next_weapon_confirmation_required)
```

**Update signal handler:**
```gdscript
# In ShootingController.gd (modify _on_next_weapon_confirmation_required around line 1359)
func _on_next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary) -> void:
    """Handle next weapon confirmation in sequential mode"""
    print("========================================")
    print("ShootingController: _on_next_weapon_confirmation_required CALLED")
    print("ShootingController: Remaining weapons: %d, current_index: %d" % [remaining_weapons.size(), current_index])
    print("ShootingController: Last weapon result keys: %s" % str(last_weapon_result.keys()))

    # NEW: Validate remaining_weapons
    if remaining_weapons.is_empty():
        push_error("ShootingController: remaining_weapons is EMPTY - cannot show dialog!")
        return

    # NEW: Validate last_weapon_result
    if last_weapon_result.is_empty():
        push_warning("ShootingController: last_weapon_result is EMPTY - showing dialog without summary")

    # Check if this is for the local attacking player
    var should_show_dialog = false

    if NetworkManager.is_networked():
        var local_peer_id = multiplayer.get_unique_id()
        var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
        var active_player = current_phase.get_current_player() if current_phase else -1
        should_show_dialog = (local_player == active_player)
    else:
        should_show_dialog = true

    if not should_show_dialog:
        print("ShootingController: Not showing confirmation dialog - not the attacking player")
        return

    # Show feedback in dice log
    if dice_log_display:
        var weapon_name = last_weapon_result.get("weapon_name", "Unknown")
        var casualties = last_weapon_result.get("casualties", 0)
        dice_log_display.append_text("[b][color=yellow]>>> %s complete: %d casualties <<<[/color][/b]\n" %
            [weapon_name, casualties])

    # Close any existing dialogs
    var root_children = get_tree().root.get_children()
    for child in root_children:
        if child is AcceptDialog:
            child.hide()
            child.queue_free()

    await get_tree().process_frame

    # Load NextWeaponDialog
    var weapon_dialog_script = preload("res://scripts/NextWeaponDialog.gd")
    var dialog = weapon_dialog_script.new()

    # Connect to confirmation signal
    dialog.continue_confirmed.connect(_on_next_weapon_order_confirmed)

    # Add to scene tree
    get_tree().root.add_child(dialog)

    # Setup with enhanced data
    dialog.setup(remaining_weapons, current_index, last_weapon_result)

    # Show dialog
    dialog.popup_centered()

    print("ShootingController: NextWeaponDialog shown with last weapon results")
    print("========================================")
```

## 5. Implementation Tasks

### 5.1 Phase 1: Data Collection & Storage (Priority: HIGH)
**Goal**: Capture and store dice roll results for each weapon

**Tasks**:
- [ ] Modify `resolution_state.completed_weapons` structure to include hit_data, wound_data, dice_rolls
- [ ] Update ShootingPhase._resolve_next_weapon() to extract dice data from RulesEngine result
- [ ] Store total_attacks, hits, wounds in completed_weapons entry
- [ ] Add target_unit_name to completed_weapons for display
- [ ] Test: Verify dice data is captured correctly after weapon resolution

**Files Modified**:
- `40k/phases/ShootingPhase.gd`

**Lines to Modify**:
- Around line 733-737 (after weapon misses)
- Around line 1308-1312 (after saves complete)

### 5.2 Phase 2: Signal Enhancement (Priority: HIGH)
**Goal**: Pass complete weapon result data to NextWeaponDialog

**Tasks**:
- [ ] Add last_weapon_result parameter to next_weapon_confirmation_required signal
- [ ] Create _get_last_weapon_result() helper function
- [ ] Update all signal emission points to include last_weapon_result
- [ ] Test: Verify signal payload includes all required data

**Files Modified**:
- `40k/phases/ShootingPhase.gd` (signal definition line 14, emissions lines 775, 1362)

### 5.3 Phase 3: NextWeaponDialog Enhancement (Priority: HIGH)
**Goal**: Display attack summary and dice details in dialog

**Tasks**:
- [ ] Add last_weapon_result parameter to setup() function
- [ ] Create _populate_last_weapon_summary() function
- [ ] Add attack summary panel with hit/wound/save/casualty rows
- [ ] Add collapsible dice details section
- [ ] Add color coding for results (green/red/yellow/gray)
- [ ] Handle "weapon skipped" case
- [ ] Test: Verify all result scenarios display correctly

**Files Modified**:
- `40k/scripts/NextWeaponDialog.gd`

**UI Components to Add**:
- weapon_name_label: Label
- attack_summary_panel: PanelContainer
- summary_grid: GridContainer
- dice_details_button: Button
- dice_details_panel: PanelContainer (collapsible)
- dice_details_log: RichTextLabel

### 5.4 Phase 4: ShootingController Update (Priority: MEDIUM)
**Goal**: Update controller to handle enhanced signal

**Tasks**:
- [ ] Update _on_next_weapon_confirmation_required signature
- [ ] Add validation for last_weapon_result parameter
- [ ] Update dialog.setup() call to pass last_weapon_result
- [ ] Add fallback handling if last_weapon_result is empty
- [ ] Test: Verify controller correctly passes data to dialog

**Files Modified**:
- `40k/scripts/ShootingController.gd` (lines 1359-1448)

### 5.5 Phase 5: Testing & Polish (Priority: MEDIUM)
**Goal**: Ensure robustness and good UX

**Tasks**:
- [ ] Test scenario: Weapon hits but causes 0 casualties (all saves passed)
- [ ] Test scenario: Weapon misses entirely (0 hits)
- [ ] Test scenario: Weapon skipped (target destroyed)
- [ ] Test scenario: Last weapon in sequence
- [ ] Test scenario: Weapon with rerolls (show reroll data)
- [ ] Test scenario: Multiplayer (only attacker sees dialog)
- [ ] Test scenario: Save/load during dialog display
- [ ] Polish: Adjust colors for better readability
- [ ] Polish: Adjust panel sizes for optimal layout
- [ ] Polish: Add tooltip to dice details button

**Success Criteria**:
- All scenarios display correct information
- Dialog is readable and informative
- No crashes or missing data errors
- Multiplayer sync works correctly

## 6. Data Structures

### 6.1 Enhanced completed_weapons Entry
```gdscript
# In ShootingPhase.resolution_state.completed_weapons
{
    "weapon_id": "plasma_gun",
    "target_unit_id": "U_ORK_BOYZ_1",
    "target_unit_name": "Ork Boyz",  # NEW
    "casualties": 1,
    "wounds": 2,  # Wounds caused (before saves)
    "hits": 3,  # NEW: Successful hit rolls
    "total_attacks": 4,  # NEW: Total attack dice rolled
    "saves_failed": 1,  # NEW: Number of failed saves
    "dice_rolls": [  # NEW: Complete dice log
        {
            "context": "hit_roll",
            "rolls_raw": [4, 2, 5, 3],
            "rolls_modified": [4, 2, 5, 3],
            "successes": 3,
            "threshold": "3+",
            "rerolls": []
        },
        {
            "context": "wound_roll",
            "rolls_raw": [5, 2, 4],
            "rolls_modified": [5, 2, 4],
            "successes": 2,
            "threshold": "4+",
            "rerolls": []
        }
    ],
    "hit_data": {  # NEW: Extracted hit roll summary
        "rolls": [4, 2, 5, 3],
        "modified_rolls": [4, 2, 5, 3],
        "successes": 3,
        "total": 4,
        "rerolls": []
    },
    "wound_data": {  # NEW: Extracted wound roll summary
        "rolls": [5, 2, 4],
        "modified_rolls": [5, 2, 4],
        "successes": 2,
        "total": 3
    },
    "skipped": false,
    "skip_reason": ""
}
```

### 6.2 Signal Signature
```gdscript
# OLD (line 14 in ShootingPhase.gd)
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int)

# NEW
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary)
```

### 6.3 Dialog Setup Signature
```gdscript
# OLD (NextWeaponDialog.gd line 42)
func setup(weapons: Array, index: int) -> void:

# NEW
func setup(weapons: Array, index: int, last_result: Dictionary) -> void:
```

## 7. Edge Cases & Error Handling

### 7.1 Missing Dice Data
**Scenario**: last_weapon_result.dice_rolls is empty
**Handling**: Show summary without detailed dice section, display "Dice data not available"

### 7.2 Weapon Skipped (Target Destroyed)
**Scenario**: last_weapon_result.skipped == true
**Handling**: Show "⚠️ Weapon Skipped: [reason]" instead of attack summary

### 7.3 Last Weapon in Sequence
**Scenario**: remaining_weapons is empty
**Handling**: Change continue button text to "Complete Shooting", clear remaining weapons list

### 7.4 No Hits Caused
**Scenario**: hits == 0
**Handling**: Only show hit roll row, color it red, hide wound/save rows

### 7.5 Hits But No Casualties
**Scenario**: hits > 0, wounds > 0, but casualties == 0 (all saves passed)
**Handling**: Show all rows, color casualties gray, show "0 destroyed"

### 7.6 Multiplayer - Non-Attacker
**Scenario**: Dialog signal received but local player is not attacker
**Handling**: Don't show dialog, show "Attacker reviewing results..." in dice log

### 7.7 Save/Load During Dialog
**Scenario**: Game saved while NextWeaponDialog is open
**Handling**: On load, recreate dialog with same data, restore dialog state

## 8. Testing Requirements

### 8.1 Unit Tests
- [ ] _get_last_weapon_result() returns correct structure
- [ ] Dice data extraction from RulesEngine result
- [ ] completed_weapons entry has all required fields
- [ ] Dialog setup handles empty last_weapon_result gracefully
- [ ] Dialog setup handles skipped weapon correctly

### 8.2 Integration Tests
- [ ] Weapon hits, causes casualties → dialog shows all data
- [ ] Weapon hits, no casualties (all saves) → dialog shows 0 casualties
- [ ] Weapon misses entirely → dialog shows 0 hits
- [ ] Weapon with rerolls → dialog shows reroll data in details
- [ ] Last weapon complete → dialog shows "Complete Shooting"
- [ ] Multiple weapons in sequence → dialog appears after each
- [ ] Dice details toggle works correctly
- [ ] Continue button progresses to next weapon

### 8.3 Multiplayer Tests
- [ ] Attacker sees dialog, defender does not
- [ ] Dialog data synced correctly across clients
- [ ] Timeout if attacker doesn't respond (60s)
- [ ] Defender sees "Attacker reviewing results..." message
- [ ] Dialog state preserved across save/load

### 8.4 Visual/UX Tests
- [ ] Dialog is readable at default resolution (1920x1080)
- [ ] Colors are accessible (colorblind-friendly)
- [ ] Text is not truncated
- [ ] Panels size correctly for different content lengths
- [ ] Dialog centers on screen
- [ ] Continue button is easily clickable (large enough)

## 9. Success Metrics

- **Clarity**: 90%+ of testers can correctly identify last weapon's results from dialog
- **Speed**: Dialog display adds < 0.5s to weapon sequence time
- **Usability**: 80%+ of testers prefer enhanced dialog over old version
- **Reliability**: Zero crashes related to missing dice data
- **Accessibility**: All information readable without expanding dice details

## 10. Future Enhancements (Post-MVP)

### 10.1 Visual Improvements
- Add weapon icons to dialog
- Animated dice roll display (replay dice rolls)
- Colored backgrounds for different result severities
- Charts/graphs for hit/wound efficiency

### 10.2 Advanced Features
- "Auto-continue" option (skip dialog after reviewing results)
- Comparison with previous weapon results
- Efficiency statistics (% hits, % wounds, % casualties)
- Predicted results for next weapon based on target stats

### 10.3 Accessibility
- Screen reader support for visually impaired users
- High contrast mode
- Keyboard shortcuts (Space to continue, D to toggle details)
- Larger text option

## 11. Appendix

### A. Referenced Files
- `40k/phases/ShootingPhase.gd` (1445 lines)
- `40k/scripts/ShootingController.gd` (2002 lines)
- `40k/scripts/NextWeaponDialog.gd` (72 lines)
- `40k/scripts/WeaponOrderDialog.gd` (425 lines)

### B. Key Code Sections
**ShootingPhase signal emissions:**
- Line 14: Signal definition
- Line 775: Emission after weapon misses
- Line 1362: Emission after saves complete

**ShootingController handler:**
- Line 367-370: Signal connection
- Line 1359-1448: Handler implementation

**NextWeaponDialog:**
- Line 42-46: Current setup function
- Line 48-61: Current UI population

### C. Related PRPs
- `weapon_order_selection_prp.md`: Initial weapon ordering implementation
- `weapon_order_sequence_continuation_fix.md`: Fix for sequence continuation
- `wound_allocation_prp.md`: Save dialog implementation

### D. Godot Documentation
- AcceptDialog: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
- RichTextLabel BBCode: https://docs.godotengine.org/en/4.4/tutorials/ui/bbcode_in_richtextlabel.html
- GridContainer: https://docs.godotengine.org/en/4.4/classes/class_gridcontainer.html
- Signals: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html

### E. Warhammer 40K Rules Reference
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Shooting Phase: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE
- Making Attacks: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Making-Attacks

## 12. Confidence Score

**Self-Assessment**: 9/10

**Reasoning**:
- ✅ Complete understanding of current implementation
- ✅ Clear identification of the problem
- ✅ Minimal changes required (enhancement, not refactor)
- ✅ Follows existing patterns (AcceptDialog, signal flow)
- ✅ Data already available (just needs to be passed through)
- ✅ No new files needed (modify existing NextWeaponDialog)
- ✅ Low risk of breaking existing functionality
- ⚠️ Minor risk: Dice data structure might need adjustment
- ⚠️ Minor risk: UI layout might need tweaking for different content lengths

**Estimated Implementation Time**: 4-6 hours
- Phase 1 (Data Collection): 1-2 hours
- Phase 2 (Signal Enhancement): 0.5 hours
- Phase 3 (Dialog Enhancement): 2-3 hours
- Phase 4 (Controller Update): 0.5 hours
- Phase 5 (Testing & Polish): 1-2 hours

**Dependencies**: None (all required data is already being generated)

**Risks**:
- **LOW**: Dice data structure compatibility
- **LOW**: UI layout overflow with long weapon names
- **LOW**: Multiplayer sync timing issues

---

**Version History**:
- v1.0 (2025-10-15): Initial PRP creation

**Approval**:
- [ ] Product Owner
- [ ] Tech Lead
- [ ] UX Designer
