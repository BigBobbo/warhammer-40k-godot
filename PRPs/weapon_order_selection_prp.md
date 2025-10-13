# Weapon Order Selection for Shooting Phase - PRP
**Version**: 1.0
**Date**: 2025-10-12
**Scope**: Sequential weapon resolution with tactical ordering control

## 1. Executive Summary

This PRP defines the implementation of weapon order selection during the Shooting Phase. Currently, when a unit shoots with multiple weapon types, all weapons are resolved simultaneously - dice are rolled for all weapons at once, and the defender makes all saves together. This implementation will allow the attacker to choose the order in which weapons fire, with saves resolved after each weapon. This adds tactical depth by allowing players to adjust their strategy based on earlier results.

**Key Features:**
- **Weapon Order Dialog**: Appears when unit has 2+ weapon types assigned to targets
- **Tactical Ordering**: Default order by highest damage first, player can reorder
- **Sequential Resolution**: Each weapon resolves completely (hit → wound → save → damage) before next weapon
- **Dynamic Reordering**: After each weapon fires, player can reorder remaining weapons
- **Fast Roll Option**: "Fast Roll All" button to use existing batch resolution
- **Progress Tracking**: Visual feedback showing completed/current/pending weapons
- **Enhanced Save Dialog**: Shows weapon number and previous casualties for context

**Design Philosophy:**
- **Preserve Speed**: Fast roll option for players who want quick resolution
- **Add Tactical Depth**: Sequential option for competitive/strategic play
- **Clear Feedback**: Always show what's happening and what's next
- **Flexible Strategy**: Allow mid-sequence adjustments based on results

## 2. Core Requirements

### 2.1 Functional Requirements
- **FR1**: Weapon order dialog appears only when unit has 2+ weapon types
- **FR2**: Weapons default to highest damage first, then by AP, then alphabetically
- **FR3**: Player can reorder weapons using up/down arrows before first weapon fires
- **FR4**: After each weapon resolves, player can reorder remaining weapons
- **FR5**: Player cannot change order of already-fired weapons
- **FR6**: "Fast Roll All" option available to skip sequential resolution
- **FR7**: "Continue to Next Weapon" button appears after each weapon's saves
- **FR8**: Save dialog shows "Weapon X of Y" and previous casualty summary
- **FR9**: Progress display shows ✓ (completed), ⚠ (current), ○ (pending) for each weapon

### 2.2 Rules Compliance (10th Edition)
- **RC1**: All targets must be declared before weapon order selection
- **RC2**: Weapon order selection does not change target assignments
- **RC3**: Each weapon's attacks are resolved completely before next weapon
- **RC4**: Defender makes saves after each weapon's wounds are determined
- **RC5**: Damage is applied immediately after saves, before next weapon
- **RC6**: Fast roll option must produce identical results to sequential resolution

### 2.3 Multiplayer Requirements
- **MR1**: Weapon order selection visible to all players (spectator mode)
- **MR2**: Dice rolls broadcast in real-time to all clients
- **MR3**: Progress updates shown to all players
- **MR4**: Save dialogs appear only for defending player
- **MR5**: Attacker's reordering actions visible to all players
- **MR6**: Defender's "Continue to Next Weapon" button click triggers next weapon

### 2.4 Architecture Requirements
- **AR1**: Follow existing Phase-Controller-RulesEngine pattern
- **AR2**: Support save/load at any point in weapon sequence
- **AR3**: Use deterministic RNG for reproducibility
- **AR4**: Emit appropriate signals for UI updates
- **AR5**: Design WeaponOrderDialog for future drag-and-drop enhancement

## 3. User Flow

### 3.1 Standard Flow (Single Weapon Type)
**UNCHANGED - No dialog appears**

1. Player selects unit with 1 weapon type
2. Player assigns target
3. Player clicks "Confirm Targets"
4. All attacks resolve at once (current behavior)
5. Save dialog appears (if wounds caused)
6. Defender makes saves
7. Shooting complete

### 3.2 New Flow (Multiple Weapon Types - Sequential)

#### 3.2.1 Weapon Order Selection

1. Player selects unit with 2+ weapon types
2. Player assigns targets to each weapon
3. Player clicks **"Confirm Targets"**
4. **WeaponOrderDialog appears** showing:
   ```
   ┌─────────────────────────────────────────────────┐
   │    SELECT WEAPON RESOLUTION ORDER               │
   ├─────────────────────────────────────────────────┤
   │ Unit: Space Marine Intercessors                 │
   │                                                  │
   │ Choose the order to resolve your weapons:       │
   │                                                  │
   │ ┌───────────────────────────────────────────┐   │
   │ │ [▲] 1. Plasma Gun x2 → Ork Boyz           │   │
   │ │ [▼]    4 shots, BS 3+, AP-3, Dmg 2        │   │
   │ ├───────────────────────────────────────────┤   │
   │ │ [▲] 2. Bolt Rifles x5 → Ork Boyz          │   │
   │ │ [▼]    10 shots, BS 3+, AP-1, Dmg 1       │   │
   │ ├───────────────────────────────────────────┤   │
   │ │ [▲] 3. Grenades x1 → Gretchin             │   │
   │ │ [▼]    D6 shots, BS 3+, Blast, Dmg 1      │   │
   │ └───────────────────────────────────────────┘   │
   │                                                  │
   │ ℹ Default order: Highest damage first            │
   │                                                  │
   │ ⚠ Saves will be made after each weapon fires    │
   │                                                  │
   │ ┌──────────────────┬──────────────────────────┐ │
   │ │ [Fast Roll All]  │  [Start Sequence]         │ │
   │ │ Roll everything  │  Resolve in order         │ │
   │ │ at once          │                           │ │
   │ └──────────────────┴──────────────────────────┘ │
   └─────────────────────────────────────────────────┘
   ```

5. Player uses ▲/▼ arrows to reorder if desired
6. Player clicks **"Start Sequence"** (or **"Fast Roll All"** to skip)

#### 3.2.2 First Weapon Resolution

7. Dialog closes
8. Right panel updates to show progress:
   ```
   ┌────────────────────────────────┐
   │ Shooting Sequence              │
   ├────────────────────────────────┤
   │ ⚠ Plasma Gun x2 → Ork Boyz     │
   │   ○ Bolt Rifles x5             │
   │   ○ Grenades x1                │
   ├────────────────────────────────┤
   │ Current Weapon:                │
   │ Plasma Gun x2                  │
   │ Target: Ork Boyz               │
   │                                │
   │ Rolling 4 attacks...           │
   └────────────────────────────────┘
   ```

9. System rolls hits and wounds for Plasma Guns
10. Dice results appear in dice log
11. If wounds caused → SaveDialog appears for defender

#### 3.2.3 First Save Resolution

12. **SaveDialog appears** (defender's screen):
    ```
    ┌─────────────────────────────────────────────────┐
    │  INCOMING ATTACK (Weapon 1 of 3)                │
    ├─────────────────────────────────────────────────┤
    │ Weapon: Plasma Gun x2                           │
    │ Stats: AP-3, Damage 2                           │
    │ Wounds to Save: 3                               │
    │                                                  │
    │ [... save UI with model allocation ...]         │
    │                                                  │
    │ [Roll All Saves]  [Apply Damage]                │
    └─────────────────────────────────────────────────┘
    ```

13. Defender rolls saves
14. Defender clicks "Apply Damage"
15. Casualties applied (e.g., "2 Ork Boyz destroyed")

#### 3.2.4 Weapon Reordering Between Weapons

16. **NEW: Weapon Reorder Dialog appears** (attacker's screen):
    ```
    ┌─────────────────────────────────────────────────┐
    │    ADJUST REMAINING WEAPON ORDER                │
    ├─────────────────────────────────────────────────┤
    │ Unit: Space Marine Intercessors                 │
    │                                                  │
    │ Previous Results:                               │
    │ ✓ Plasma Gun x2 → 2 casualties                  │
    │                                                  │
    │ Remaining Weapons:                              │
    │ ┌───────────────────────────────────────────┐   │
    │ │ [▲] 1. Bolt Rifles x5 → Ork Boyz          │   │
    │ │ [▼]    10 shots, BS 3+, AP-1, Dmg 1       │   │
    │ ├───────────────────────────────────────────┤   │
    │ │ [▲] 2. Grenades x1 → Gretchin             │   │
    │ │ [▼]    D6 shots, BS 3+, Blast, Dmg 1      │   │
    │ └───────────────────────────────────────────┘   │
    │                                                  │
    │ ℹ You can change the order of remaining weapons │
    │                                                  │
    │ [Continue with Current Order]                   │
    └─────────────────────────────────────────────────┘
    ```

17. Attacker can reorder remaining weapons (or accept current order)
18. Attacker clicks "Continue with Current Order"

#### 3.2.5 Subsequent Weapons

19. Next weapon (Bolt Rifles) resolves:
    - Progress UI updates (✓ Plasma Gun, ⚠ Bolt Rifles, ○ Grenades)
    - Dice rolls shown
    - SaveDialog appears with "Weapon 2 of 3"
    - Shows previous: "Plasma Gun: 2 casualties"

20. Process repeats for each remaining weapon

21. After last weapon completes:
    - Summary shown: "Shooting complete: 5 total casualties"
    - Unit marked as having shot
    - UI returns to unit selection

### 3.3 Fast Roll Flow (Multiple Weapon Types)

1-6. Same as sequential flow up to weapon order dialog
7. Player clicks **"Fast Roll All"**
8. Dialog closes
9. All weapons resolve at once (current behavior):
   - All hit rolls made
   - All wound rolls made
   - Single SaveDialog with all wounds combined
10. Defender makes all saves at once
11. Damage applied
12. Shooting complete

### 3.4 Edge Cases

#### 3.4.1 No Wounds Caused by a Weapon
- Weapon shows "0 casualties" in summary
- Reorder dialog still appears
- Continues to next weapon

#### 3.4.2 Target Unit Destroyed Mid-Sequence
- If target destroyed before its weapon fires:
  - Weapon auto-skips with message "Target destroyed"
  - Continues to remaining weapons with alive targets

#### 3.4.3 All Remaining Targets Destroyed
- If all targets destroyed mid-sequence:
  - Remaining weapons auto-skip
  - Shooting completes early
  - Summary shows "Remaining weapons: No valid targets"

#### 3.4.4 Save/Load During Sequence
- Game can be saved at any point
- On load, restores to exact weapon position:
  - Shows completed weapons with results
  - Shows current weapon awaiting resolution
  - Shows pending weapons

## 4. GUI Components

### 4.1 WeaponOrderDialog (New)

**Class**: `WeaponOrderDialog extends AcceptDialog`

**Purpose**: Allow player to choose resolution order for multiple weapons

**UI Elements**:
```gdscript
# Main containers
var vbox: VBoxContainer
var weapon_list_container: VBoxContainer
var completed_summary: Label  # For reordering dialog

# Weapon items (one per weapon)
class WeaponOrderItem:
    var panel: PanelContainer
    var up_button: Button
    var down_button: Button
    var weapon_label: Label
    var stats_label: Label
    var position_label: Label  # "1.", "2.", etc.

# Action buttons
var fast_roll_button: Button  # Only on initial dialog
var start_sequence_button: Button  # "Start Sequence" or "Continue with Current Order"
```

**Behavior**:
- **Up Arrow**: Moves weapon up in list (disabled if already first)
- **Down Arrow**: Moves weapon down in list (disabled if already last)
- **Fast Roll All**: Only shown on initial order selection, not on reordering
- **Start Sequence/Continue**: Confirms order and begins/continues resolution

**Styling**:
- Weapons in panels with light gray background
- Current position number prominent on left
- Stats in smaller font below weapon name
- Selected weapon (for reordering) highlights in blue

### 4.2 Enhanced Right Panel (Shooting Sequence)

**New Section**: Weapon Sequence Progress

```gdscript
# Progress tracking
var sequence_title: Label  # "Shooting Sequence"
var weapon_status_list: VBoxContainer  # List of weapons with status icons

# Status item per weapon
class WeaponStatusItem:
    var icon: Label  # ✓, ⚠, or ○
    var weapon_name: Label
    var result_label: Label  # "2 casualties" after completion
```

**Visual States**:
- ✓ Green checkmark: Completed
- ⚠ Yellow warning: Currently resolving
- ○ Gray circle: Pending

**Example**:
```
Shooting Sequence
─────────────────
✓ Plasma Gun x2 → 2 casualties
⚠ Bolt Rifles x5 → Rolling...
○ Grenades x1 → Pending

Current Weapon: Bolt Rifles x5
Target: Ork Boyz

[Dice log continues below...]
```

### 4.3 Enhanced SaveDialog

**Modifications to existing SaveDialog.gd**:

**New Properties**:
```gdscript
var weapon_number: int = 1
var total_weapons: int = 1
var previous_results: Array = []  # [{weapon: "Plasma Gun", casualties: 2}, ...]
```

**Title Bar Update**:
```
Original: "INCOMING ATTACK - DEFEND!"
Enhanced: "INCOMING ATTACK (Weapon 2 of 3) - DEFEND!"
```

**New Section Before Attack Info**:
```gdscript
# Previous results summary
var previous_results_label: Label

func _update_previous_results() -> void:
    if previous_results.is_empty():
        previous_results_label.text = "First weapon attacking"
        previous_results_label.modulate = Color.WHITE
    else:
        var summary = "Previous:\n"
        for result in previous_results:
            summary += "• %s → %d casualties\n" % [result.weapon, result.casualties]
        previous_results_label.text = summary
        previous_results_label.modulate = Color(0.7, 0.7, 1.0)  # Light blue
```

## 5. Data Structures

### 5.1 Weapon Assignment (Enhanced)

```gdscript
# Current structure (unchanged)
{
    "weapon_id": "plasma_gun",
    "target_unit_id": "U_ORK_BOYZ_1",
    "model_ids": ["m1", "m2"],
    "modifiers": {...}
}

# NEW: Add sequence metadata (optional, calculated when needed)
{
    "weapon_id": "plasma_gun",
    "target_unit_id": "U_ORK_BOYZ_1",
    "model_ids": ["m1", "m2"],
    "modifiers": {...},
    "sequence_order": 0,  # Position in resolution sequence
    "damage_priority": 2,  # Used for default sorting
    "ap_priority": 3
}
```

### 5.2 Resolution State (Enhanced)

```gdscript
# ShootingPhase.resolution_state
{
    "mode": "sequential",  # or "fast" or "single"
    "weapon_order": [  # Ordered array of assignments
        {weapon assignment 1},
        {weapon assignment 2},
        {weapon assignment 3}
    ],
    "current_index": 1,  # Currently resolving weapon (0-based)
    "completed_weapons": [
        {
            "weapon_id": "plasma_gun",
            "target_unit_id": "U_ORK_BOYZ_1",
            "casualties": 2,
            "wounds_caused": 3,
            "saves_made": 1
        }
    ],
    "awaiting_saves": false,  # Waiting for defender
    "awaiting_reorder": false,  # Waiting for attacker to confirm order
    "start_time": 1234567890  # For timeout handling
}
```

### 5.3 Action: RESOLVE_WEAPON_SEQUENCE

```gdscript
{
    "type": "RESOLVE_WEAPON_SEQUENCE",
    "actor_unit_id": "U_INTERCESSORS_1",
    "player": 0,  # Attacker player ID
    "payload": {
        "weapon_order": [
            {weapon assignment 1},
            {weapon assignment 2},
            {weapon assignment 3}
        ],
        "fast_roll": false,  # true = resolve all at once
        "is_reorder": false  # true if this is mid-sequence reordering
    }
}
```

### 5.4 Action: CONTINUE_WEAPON_SEQUENCE

```gdscript
{
    "type": "CONTINUE_WEAPON_SEQUENCE",
    "actor_unit_id": "U_INTERCESSORS_1",
    "player": 0,  # Must be the attacker
    "payload": {
        "updated_order": [  # Only remaining weapons, can be reordered
            {weapon assignment 2},
            {weapon assignment 3}
        ]
    }
}
```

### 5.5 Result: Weapon Resolution Progress

```gdscript
# Returned by _resolve_next_weapon()
{
    "success": true,
    "phase": "SHOOTING",
    "dice": [...],
    "log_text": "Plasma Gun x2: 4 shots, 3 hits, 3 wounds",
    "save_data_list": [...],  # If saves needed
    "weapon_complete": {
        "weapon_id": "plasma_gun",
        "casualties": 0,  # Updated after saves
        "wounds_caused": 3
    },
    "sequence_status": {
        "current_index": 0,
        "total_weapons": 3,
        "remaining_weapons": 2,
        "next_action": "awaiting_saves"  # or "awaiting_reorder" or "complete"
    }
}
```

## 6. State Management

### 6.1 ShootingPhase State Machine

**States**:
1. `IDLE` - No active shooter
2. `TARGET_SELECTION` - Assigning weapons to targets
3. `WEAPON_ORDERING` - Choosing resolution order (NEW)
4. `RESOLVING_WEAPON` - Dice rolls for current weapon
5. `AWAITING_SAVES` - Defender making saves
6. `AWAITING_REORDER` - Attacker choosing next weapon order (NEW)
7. `SEQUENCE_COMPLETE` - All weapons resolved

**Transitions**:
```
IDLE → TARGET_SELECTION (unit selected)
TARGET_SELECTION → WEAPON_ORDERING (confirm targets, 2+ weapons)
TARGET_SELECTION → RESOLVING_WEAPON (confirm targets, 1 weapon)
WEAPON_ORDERING → RESOLVING_WEAPON (fast roll or start sequence)
RESOLVING_WEAPON → AWAITING_SAVES (wounds caused)
RESOLVING_WEAPON → AWAITING_REORDER (no wounds, more weapons remain)
RESOLVING_WEAPON → SEQUENCE_COMPLETE (no wounds, last weapon)
AWAITING_SAVES → AWAITING_REORDER (saves complete, more weapons remain)
AWAITING_SAVES → SEQUENCE_COMPLETE (saves complete, last weapon)
AWAITING_REORDER → RESOLVING_WEAPON (order confirmed)
SEQUENCE_COMPLETE → IDLE (unit marked as shot)
```

### 6.2 Multiplayer Synchronization

**Phase 1: Weapon Order Selection**
- Attacker selects order → `RESOLVE_WEAPON_SEQUENCE` action
- Host validates → broadcasts to all clients
- All clients show weapon order dialog (read-only for non-attacker)
- Host begins resolution

**Phase 2: Weapon Resolution**
- Host rolls dice → broadcasts dice data
- All clients show dice results in real-time
- All clients update progress UI
- Host triggers saves_required → broadcasts save_data_list

**Phase 3: Save Resolution**
- Only defender sees interactive SaveDialog
- Attacker/spectators see "Awaiting defender saves..." message
- Defender submits APPLY_SAVES → host processes
- Host broadcasts damage diffs → all clients update

**Phase 4: Reordering (if more weapons remain)**
- Host triggers weapon_reorder_required → broadcasts completed_weapons data
- Only attacker sees reorder dialog
- Other players see "Attacker choosing weapon order..." message
- Attacker submits CONTINUE_WEAPON_SEQUENCE → host validates
- Host broadcasts updated order → all clients update progress UI

**Phase 5: Next Weapon**
- Loop back to Phase 2

**Key Synchronization Points**:
- `resolution_state` maintained on host only
- All clients receive sequential updates via signals/results
- Clients maintain local `weapon_progress_display` based on received data
- Save/load includes full `resolution_state` for mid-sequence restoration

### 6.3 Save/Load Support

**Save Data Structure**:
```gdscript
# In game state
"shooting_sequence": {
    "active": true,
    "shooter_unit_id": "U_INTERCESSORS_1",
    "mode": "sequential",
    "weapon_order": [...],
    "current_index": 1,
    "completed_weapons": [...],
    "state": "awaiting_saves"  # or "awaiting_reorder", "resolving"
}
```

**On Load**:
1. Restore ShootingPhase with resolution_state
2. ShootingController rebuilds progress UI from completed_weapons
3. Depending on state:
   - If `awaiting_saves`: Show save dialog again
   - If `awaiting_reorder`: Show reorder dialog again
   - If `resolving`: Continue to next weapon
4. Validate that current weapon's target still exists
5. If target destroyed, auto-skip to next weapon

## 7. Implementation Phases

### Phase 1: Core Sequential Resolution (Week 1)
**Goal**: Basic sequential weapon resolution working

**Tasks**:
- [ ] Create WeaponOrderDialog.gd with up/down arrows
- [ ] Add weapon sorting logic (damage → AP → alphabetical)
- [ ] Modify ShootingPhase._process_confirm_targets() to check weapon count
- [ ] Add new signal: weapon_order_required(assignments: Array)
- [ ] Create _resolve_weapon_sequence() function
- [ ] Implement _resolve_next_weapon() with single weapon resolution
- [ ] Add progress UI to right panel
- [ ] Test single-player sequential resolution

**Success Criteria**:
- Dialog appears when 2+ weapon types
- Weapons resolve one at a time
- Progress UI updates correctly
- Saves triggered after each weapon

### Phase 2: Reordering & Fast Roll (Week 2)
**Goal**: Complete feature with all options

**Tasks**:
- [ ] Add "Fast Roll All" button to initial dialog
- [ ] Implement fast roll path (existing batch behavior)
- [ ] Create weapon reorder dialog (between weapons)
- [ ] Add CONTINUE_WEAPON_SEQUENCE action
- [ ] Implement _process_continue_weapon_sequence()
- [ ] Prevent modification of completed weapons
- [ ] Add previous results summary to reorder dialog
- [ ] Test reordering after first weapon

**Success Criteria**:
- Fast roll produces same results as sequential
- Reorder dialog shows after each weapon
- Completed weapons cannot be reordered
- Previous results displayed correctly

### Phase 3: Save Dialog Enhancement (Week 2-3)
**Goal**: Improved context for defender

**Tasks**:
- [ ] Add weapon_number and total_weapons to SaveDialog
- [ ] Add previous_results array to SaveDialog
- [ ] Update SaveDialog title to show "Weapon X of Y"
- [ ] Add previous results section to dialog
- [ ] Style previous results with appropriate colors
- [ ] Test with multiple weapons attacking same target

**Success Criteria**:
- Defender sees which weapon is attacking
- Defender sees results of previous weapons
- Information clear and not overwhelming

### Phase 4: Multiplayer Support (Week 3)
**Goal**: Networked sequential resolution

**Tasks**:
- [ ] Add multiplayer validation for RESOLVE_WEAPON_SEQUENCE
- [ ] Add multiplayer validation for CONTINUE_WEAPON_SEQUENCE
- [ ] Broadcast weapon order to all clients
- [ ] Show read-only weapon order dialog for non-attacker
- [ ] Show "Awaiting defender..." message during saves
- [ ] Show "Attacker choosing order..." during reordering
- [ ] Broadcast progress updates to all clients
- [ ] Test host-client weapon sequence
- [ ] Test spectator view

**Success Criteria**:
- Both players see same weapon order
- Spectators see real-time progress
- No desyncs during sequence
- Disconnection handled gracefully

### Phase 5: Polish & Edge Cases (Week 4)
**Goal**: Production-ready feature

**Tasks**:
- [ ] Handle target destroyed mid-sequence
- [ ] Handle all targets destroyed mid-sequence
- [ ] Save/load during weapon sequence
- [ ] Validate loaded state (weapons still exist, targets still valid)
- [ ] Add timeout for reordering (auto-continue after 60s)
- [ ] Add visual transitions between weapons
- [ ] Add sound effects for weapon resolution
- [ ] Performance test with large units (10+ weapon types)
- [ ] Accessibility: keyboard shortcuts for dialog

**Success Criteria**:
- All edge cases handled gracefully
- Save/load works at any point
- Performance acceptable with many weapons
- No crashes or stuck states

## 8. Technical Implementation Details

### 8.1 WeaponOrderDialog.gd (New File)

```gdscript
extends AcceptDialog
class_name WeaponOrderDialog

signal order_confirmed(weapon_order: Array, fast_roll: bool)

# Data
var weapon_assignments: Array = []
var is_reordering: bool = false  # Mid-sequence reordering?
var completed_weapons: Array = []  # For context in reordering

# UI
var vbox: VBoxContainer
var info_label: Label
var previous_results_label: Label
var weapon_list_container: VBoxContainer
var weapon_items: Array = []  # Array of WeaponOrderItem
var fast_roll_button: Button
var confirm_button: Button

# Weapon order item (internal class)
class WeaponOrderItem:
    var index: int
    var assignment: Dictionary
    var panel: PanelContainer
    var hbox: HBoxContainer
    var position_label: Label
    var weapon_label: Label
    var stats_label: Label
    var up_button: Button
    var down_button: Button

func _ready() -> void:
    title = "Select Weapon Resolution Order"
    dialog_hide_on_ok = false
    min_size = Vector2(600, 500)
    get_ok_button().hide()

    _create_ui()

func _create_ui() -> void:
    vbox = VBoxContainer.new()
    add_child(vbox)

    # Info section
    info_label = Label.new()
    info_label.text = "Choose the order to resolve your weapons:"
    info_label.add_theme_font_size_override("font_size", 14)
    vbox.add_child(info_label)

    vbox.add_child(HSeparator.new())

    # Previous results (only shown during reordering)
    previous_results_label = Label.new()
    previous_results_label.visible = false
    vbox.add_child(previous_results_label)

    # Weapon list container
    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(580, 300)
    vbox.add_child(scroll)

    weapon_list_container = VBoxContainer.new()
    scroll.add_child(weapon_list_container)

    vbox.add_child(HSeparator.new())

    # Info labels
    var default_order_label = Label.new()
    default_order_label.text = "ℹ Default order: Highest damage first"
    default_order_label.add_theme_font_size_override("font_size", 12)
    default_order_label.modulate = Color(0.7, 0.7, 1.0)
    vbox.add_child(default_order_label)

    var sequential_info_label = Label.new()
    sequential_info_label.text = "⚠ Saves will be made after each weapon fires"
    sequential_info_label.add_theme_font_size_override("font_size", 12)
    sequential_info_label.modulate = Color(1.0, 1.0, 0.7)
    vbox.add_child(sequential_info_label)

    vbox.add_child(HSeparator.new())

    # Buttons
    var button_hbox = HBoxContainer.new()
    button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
    vbox.add_child(button_hbox)

    fast_roll_button = Button.new()
    fast_roll_button.text = "Fast Roll All\n(Roll everything at once)"
    fast_roll_button.custom_minimum_size = Vector2(200, 60)
    fast_roll_button.pressed.connect(_on_fast_roll_pressed)
    button_hbox.add_child(fast_roll_button)

    button_hbox.add_child(VSeparator.new())

    confirm_button = Button.new()
    confirm_button.text = "Start Sequence\n(Resolve in order)"
    confirm_button.custom_minimum_size = Vector2(200, 60)
    confirm_button.pressed.connect(_on_confirm_pressed)
    button_hbox.add_child(confirm_button)

func setup(assignments: Array, shooter_id: String, p_completed_weapons: Array = [], p_is_reordering: bool = false) -> void:
    """Setup dialog with weapon assignments"""
    weapon_assignments = assignments.duplicate(true)
    is_reordering = p_is_reordering
    completed_weapons = p_completed_weapons

    # Sort by default priority (highest damage first)
    _sort_by_priority()

    # Update title based on mode
    if is_reordering:
        title = "Adjust Remaining Weapon Order"
        confirm_button.text = "Continue with Current Order"
        fast_roll_button.hide()
        _show_previous_results()

    # Get unit name for display
    var unit = GameState.get_unit(shooter_id)
    var unit_name = unit.get("meta", {}).get("name", shooter_id)
    info_label.text = "Unit: %s\n\n%s" % [
        unit_name,
        "Choose the order to resolve your weapons:" if not is_reordering else "Remaining weapons to resolve:"
    ]

    # Build weapon list UI
    _build_weapon_list()

func _sort_by_priority() -> void:
    """Sort weapons by damage (high to low), then AP (high to low), then alphabetically"""
    weapon_assignments.sort_custom(func(a, b):
        var weapon_a = RulesEngine.get_weapon_profile(a.weapon_id)
        var weapon_b = RulesEngine.get_weapon_profile(b.weapon_id)

        # Sort by damage descending
        var dmg_a = weapon_a.get("damage", 1)
        var dmg_b = weapon_b.get("damage", 1)
        if dmg_a != dmg_b:
            return dmg_a > dmg_b

        # Then by AP descending (more negative = higher priority)
        var ap_a = weapon_a.get("ap", 0)
        var ap_b = weapon_b.get("ap", 0)
        if ap_a != ap_b:
            return ap_a < ap_b  # More negative = higher priority

        # Then alphabetically
        var name_a = weapon_a.get("name", a.weapon_id)
        var name_b = weapon_b.get("name", b.weapon_id)
        return name_a < name_b
    )

func _show_previous_results() -> void:
    """Show summary of completed weapons during reordering"""
    if completed_weapons.is_empty():
        return

    previous_results_label.visible = true
    var summary = "Previous Results:\n"
    for result in completed_weapons:
        var weapon_profile = RulesEngine.get_weapon_profile(result.weapon_id)
        var weapon_name = weapon_profile.get("name", result.weapon_id)
        summary += "✓ %s → %d casualties\n" % [weapon_name, result.get("casualties", 0)]

    previous_results_label.text = summary
    previous_results_label.modulate = Color(0.7, 1.0, 0.7)  # Light green

func _build_weapon_list() -> void:
    """Build the list of weapon items with reorder buttons"""
    # Clear existing
    for child in weapon_list_container.get_children():
        child.queue_free()
    weapon_items.clear()

    for i in range(weapon_assignments.size()):
        var item = _create_weapon_item(i)
        weapon_items.append(item)
        weapon_list_container.add_child(item.panel)

func _create_weapon_item(index: int) -> WeaponOrderItem:
    """Create a single weapon item with reorder controls"""
    var item = WeaponOrderItem.new()
    item.index = index
    item.assignment = weapon_assignments[index]

    # Panel container for styling
    item.panel = PanelContainer.new()
    item.panel.custom_minimum_size = Vector2(560, 80)

    # Main horizontal layout
    item.hbox = HBoxContainer.new()
    item.panel.add_child(item.hbox)

    # Position label (1., 2., 3., etc.)
    item.position_label = Label.new()
    item.position_label.text = "%d." % (index + 1)
    item.position_label.add_theme_font_size_override("font_size", 20)
    item.position_label.custom_minimum_size = Vector2(40, 0)
    item.hbox.add_child(item.position_label)

    # Weapon info (vertical)
    var info_vbox = VBoxContainer.new()
    info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    item.hbox.add_child(info_vbox)

    # Weapon name and target
    var weapon_profile = RulesEngine.get_weapon_profile(item.assignment.weapon_id)
    var weapon_name = weapon_profile.get("name", item.assignment.weapon_id)
    var model_count = item.assignment.model_ids.size()
    var target_unit = GameState.get_unit(item.assignment.target_unit_id)
    var target_name = target_unit.get("meta", {}).get("name", item.assignment.target_unit_id)

    item.weapon_label = Label.new()
    item.weapon_label.text = "%s x%d → %s" % [weapon_name, model_count, target_name]
    item.weapon_label.add_theme_font_size_override("font_size", 14)
    info_vbox.add_child(item.weapon_label)

    # Weapon stats
    var attacks = weapon_profile.get("attacks", 1)
    var bs = weapon_profile.get("bs", 4)
    var ap = weapon_profile.get("ap", 0)
    var damage = weapon_profile.get("damage", 1)
    var range_val = weapon_profile.get("range", 0)

    item.stats_label = Label.new()
    item.stats_label.text = "%d shots, BS %d+, Range %d\", AP%d, Dmg %d" % [
        attacks * model_count, bs, range_val, ap, damage
    ]
    item.stats_label.add_theme_font_size_override("font_size", 11)
    item.stats_label.modulate = Color(0.8, 0.8, 0.8)
    info_vbox.add_child(item.stats_label)

    # Reorder buttons (vertical)
    var button_vbox = VBoxContainer.new()
    item.hbox.add_child(button_vbox)

    item.up_button = Button.new()
    item.up_button.text = "▲"
    item.up_button.custom_minimum_size = Vector2(40, 35)
    item.up_button.disabled = (index == 0)
    item.up_button.pressed.connect(_on_move_up.bind(index))
    button_vbox.add_child(item.up_button)

    item.down_button = Button.new()
    item.down_button.text = "▼"
    item.down_button.custom_minimum_size = Vector2(40, 35)
    item.down_button.disabled = (index == weapon_assignments.size() - 1)
    item.down_button.pressed.connect(_on_move_down.bind(index))
    button_vbox.add_child(item.down_button)

    return item

func _on_move_up(index: int) -> void:
    """Move weapon up in the list"""
    if index == 0:
        return

    # Swap in array
    var temp = weapon_assignments[index]
    weapon_assignments[index] = weapon_assignments[index - 1]
    weapon_assignments[index - 1] = temp

    # Rebuild UI
    _build_weapon_list()

func _on_move_down(index: int) -> void:
    """Move weapon down in the list"""
    if index >= weapon_assignments.size() - 1:
        return

    # Swap in array
    var temp = weapon_assignments[index]
    weapon_assignments[index] = weapon_assignments[index + 1]
    weapon_assignments[index + 1] = temp

    # Rebuild UI
    _build_weapon_list()

func _on_fast_roll_pressed() -> void:
    """User chose to roll all weapons at once"""
    emit_signal("order_confirmed", weapon_assignments, true)
    hide()
    queue_free()

func _on_confirm_pressed() -> void:
    """User confirmed the current order for sequential resolution"""
    emit_signal("order_confirmed", weapon_assignments, false)
    hide()
    queue_free()
```

### 8.2 ShootingPhase.gd Modifications

**Add new signals:**
```gdscript
signal weapon_order_required(assignments: Array, shooter_id: String)
signal weapon_reorder_required(remaining_assignments: Array, completed_results: Array)
signal weapon_sequence_complete(total_casualties: int)
```

**Modify `_process_confirm_targets()`:**
```gdscript
func _process_confirm_targets(action: Dictionary) -> Dictionary:
    confirmed_assignments = pending_assignments.duplicate(true)
    pending_assignments.clear()

    emit_signal("shooting_begun", active_shooter_id)
    log_phase_message("Confirmed targets, ready to resolve shooting")

    # Check how many unique weapon types
    var unique_weapons = {}
    for assignment in confirmed_assignments:
        unique_weapons[assignment.weapon_id] = true

    if unique_weapons.size() <= 1:
        # Single weapon type - resolve immediately (no order selection needed)
        return _resolve_all_weapons_at_once(confirmed_assignments)
    else:
        # Multiple weapon types - show weapon order dialog
        emit_signal("weapon_order_required", confirmed_assignments, active_shooter_id)

        # Don't resolve yet - wait for RESOLVE_WEAPON_SEQUENCE action
        return create_result(true, [], "Awaiting weapon order selection")
```

**Add new validation:**
```gdscript
func _validate_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
    var payload = action.get("payload", {})

    if not payload.has("weapon_order"):
        return {"valid": false, "errors": ["Missing weapon_order in payload"]}

    if not payload.has("fast_roll"):
        return {"valid": false, "errors": ["Missing fast_roll flag"]}

    # Validate weapon_order matches confirmed_assignments
    var weapon_order = payload.get("weapon_order", [])
    if weapon_order.size() != confirmed_assignments.size():
        return {"valid": false, "errors": ["Weapon order size mismatch"]}

    return {"valid": true, "errors": []}

func _validate_continue_weapon_sequence(action: Dictionary) -> Dictionary:
    # Must be in sequential mode
    if not resolution_state.has("weapon_order"):
        return {"valid": false, "errors": ["Not in weapon sequence mode"]}

    # Must be attacker
    if action.get("player", -1) != get_current_player():
        return {"valid": false, "errors": ["Only attacker can continue sequence"]}

    var payload = action.get("payload", {})
    if not payload.has("updated_order"):
        return {"valid": false, "errors": ["Missing updated_order"]}

    return {"valid": true, "errors": []}
```

**Add new processing functions:**
```gdscript
func _process_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
    var payload = action.get("payload", {})
    var weapon_order = payload.get("weapon_order", [])
    var fast_roll = payload.get("fast_roll", false)

    if fast_roll:
        # Fast roll - resolve all weapons at once (current behavior)
        return _resolve_all_weapons_at_once(weapon_order)
    else:
        # Sequential - start resolving weapons one by one
        resolution_state = {
            "mode": "sequential",
            "weapon_order": weapon_order,
            "current_index": 0,
            "completed_weapons": [],
            "awaiting_saves": false,
            "awaiting_reorder": false
        }

        return _resolve_next_weapon()

func _resolve_all_weapons_at_once(weapon_order: Array) -> Dictionary:
    """Current behavior - resolve all weapons together"""
    var shoot_action = {
        "type": "SHOOT",
        "actor_unit_id": active_shooter_id,
        "payload": {
            "assignments": weapon_order
        }
    }

    var rng_service = RulesEngine.RNGService.new()
    var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

    # Emit dice results
    for dice_block in result.get("dice", []):
        dice_log.append(dice_block)
        emit_signal("dice_rolled", dice_block)

    log_phase_message(result.get("log_text", "Attack rolls complete"))

    # Handle saves
    var save_data_list = result.get("save_data_list", [])
    if save_data_list.is_empty():
        # No wounds - complete
        var changes = [{
            "op": "set",
            "path": "units.%s.flags.has_shot" % active_shooter_id,
            "value": true
        }]
        units_that_shot.append(active_shooter_id)
        active_shooter_id = ""
        confirmed_assignments.clear()
        return create_result(true, changes, "No wounds caused")

    # Store save data and emit signal
    pending_save_data = save_data_list
    emit_signal("saves_required", save_data_list)

    return create_result(true, [], "Awaiting save resolution", {
        "save_data_list": save_data_list
    })

func _resolve_next_weapon() -> Dictionary:
    """Resolve the current weapon in the sequence"""
    var idx = resolution_state.current_index
    var weapon_order = resolution_state.weapon_order

    if idx >= weapon_order.size():
        # All weapons resolved
        return _complete_weapon_sequence()

    var assignment = weapon_order[idx]

    log_phase_message("Resolving weapon %d of %d: %s" % [
        idx + 1,
        weapon_order.size(),
        RulesEngine.get_weapon_profile(assignment.weapon_id).get("name", assignment.weapon_id)
    ])

    # Check if target still exists and is alive
    var target_unit = get_unit(assignment.target_unit_id)
    if target_unit.is_empty() or _is_unit_destroyed(target_unit):
        # Target destroyed - skip this weapon
        log_phase_message("Target destroyed, skipping weapon")
        resolution_state.completed_weapons.append({
            "weapon_id": assignment.weapon_id,
            "target_unit_id": assignment.target_unit_id,
            "casualties": 0,
            "wounds_caused": 0,
            "skipped": true,
            "skip_reason": "Target destroyed"
        })
        resolution_state.current_index += 1
        return _resolve_next_weapon()

    # Resolve just this weapon
    var shoot_action = {
        "type": "SHOOT",
        "actor_unit_id": active_shooter_id,
        "payload": {
            "assignments": [assignment]
        }
    }

    var rng_service = RulesEngine.RNGService.new()
    var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

    # Emit dice results
    for dice_block in result.get("dice", []):
        dice_log.append(dice_block)
        emit_signal("dice_rolled", dice_block)

    log_phase_message(result.get("log_text", ""))

    # Check if saves needed
    var save_data_list = result.get("save_data_list", [])

    if save_data_list.is_empty():
        # No saves needed - record and check for more weapons
        resolution_state.completed_weapons.append({
            "weapon_id": assignment.weapon_id,
            "target_unit_id": assignment.target_unit_id,
            "casualties": 0,
            "wounds_caused": 0
        })

        # Check if more weapons remain
        if idx + 1 < weapon_order.size():
            # More weapons - show reorder dialog
            resolution_state.awaiting_reorder = true
            emit_signal("weapon_reorder_required",
                weapon_order.slice(idx + 1),  # Remaining weapons
                resolution_state.completed_weapons  # Completed for context
            )
            return create_result(true, [], "Awaiting weapon reorder")
        else:
            # Last weapon - complete
            resolution_state.current_index += 1
            return _complete_weapon_sequence()

    # Saves needed
    pending_save_data = save_data_list
    resolution_state.awaiting_saves = true

    # Enhance save data with sequence context
    for save_data in save_data_list:
        save_data["weapon_number"] = idx + 1
        save_data["total_weapons"] = weapon_order.size()
        save_data["previous_results"] = resolution_state.completed_weapons.duplicate(true)

    emit_signal("saves_required", save_data_list)

    return create_result(true, [], "Awaiting save resolution", {
        "save_data_list": save_data_list,
        "sequence_status": {
            "current_index": idx,
            "total_weapons": weapon_order.size(),
            "remaining_weapons": weapon_order.size() - idx - 1
        }
    })

func _process_continue_weapon_sequence(action: Dictionary) -> Dictionary:
    """Continue sequence with potentially reordered remaining weapons"""
    var payload = action.get("payload", {})
    var updated_order = payload.get("updated_order", [])

    # Update weapon_order with new order for remaining weapons
    var idx = resolution_state.current_index
    var weapon_order = resolution_state.weapon_order

    # Replace remaining weapons with updated order
    for i in range(updated_order.size()):
        weapon_order[idx + 1 + i] = updated_order[i]

    resolution_state.weapon_order = weapon_order
    resolution_state.awaiting_reorder = false

    # Move to next weapon
    resolution_state.current_index += 1

    log_phase_message("Continuing to next weapon...")

    return _resolve_next_weapon()

func _complete_weapon_sequence() -> Dictionary:
    """Complete the weapon sequence and mark unit as shot"""
    var total_casualties = 0
    for result in resolution_state.completed_weapons:
        total_casualties += result.get("casualties", 0)

    log_phase_message("Weapon sequence complete: %d total casualties" % total_casualties)

    # Mark unit as shot
    var changes = [{
        "op": "set",
        "path": "units.%s.flags.has_shot" % active_shooter_id,
        "value": true
    }]

    units_that_shot.append(active_shooter_id)

    emit_signal("weapon_sequence_complete", total_casualties)

    # Clear state
    active_shooter_id = ""
    confirmed_assignments.clear()
    resolution_state.clear()
    pending_save_data.clear()

    return create_result(true, changes, "Shooting complete")

func _is_unit_destroyed(unit: Dictionary) -> bool:
    """Check if all models in unit are dead"""
    var models = unit.get("models", [])
    for model in models:
        if model.get("alive", true):
            return false
    return true
```

**Modify `_process_apply_saves()` to handle sequences:**
```gdscript
func _process_apply_saves(action: Dictionary) -> Dictionary:
    """Process save results and apply damage"""
    var payload = action.get("payload", {})
    var save_results_list = payload.get("save_results_list", [])

    var all_diffs = []
    var total_casualties = 0

    # Process each save result
    for i in range(save_results_list.size()):
        if i >= pending_save_data.size():
            break

        var save_result = save_results_list[i]
        var save_data = pending_save_data[i]

        # Apply damage
        var damage_result = RulesEngine.apply_save_damage(
            save_result.save_results,
            save_data,
            game_state_snapshot
        )

        all_diffs.append_array(damage_result.diffs)
        total_casualties += damage_result.casualties

        # Log results
        var target_name = save_data.get("target_unit_name", "Unknown")
        log_phase_message("%s: %d casualties" % [target_name, damage_result.casualties])

    # Check if we're in sequential mode
    if resolution_state.has("weapon_order") and resolution_state.mode == "sequential":
        # Record casualties for current weapon
        var idx = resolution_state.current_index
        var current_weapon = resolution_state.weapon_order[idx]

        resolution_state.completed_weapons.append({
            "weapon_id": current_weapon.weapon_id,
            "target_unit_id": current_weapon.target_unit_id,
            "casualties": total_casualties,
            "wounds_caused": pending_save_data[0].get("wounds_to_save", 0)
        })

        resolution_state.awaiting_saves = false
        pending_save_data.clear()

        # Check if more weapons remain
        if idx + 1 < resolution_state.weapon_order.size():
            # More weapons - show reorder dialog
            resolution_state.awaiting_reorder = true
            emit_signal("weapon_reorder_required",
                resolution_state.weapon_order.slice(idx + 1),
                resolution_state.completed_weapons
            )
            return create_result(true, all_diffs, "Awaiting weapon reorder")
        else:
            # Last weapon - complete sequence
            resolution_state.current_index += 1
            var complete_result = _complete_weapon_sequence()
            complete_result.changes = all_diffs
            return complete_result
    else:
        # Not in sequential mode - original behavior (mark as shot)
        all_diffs.append({
            "op": "set",
            "path": "units.%s.flags.has_shot" % active_shooter_id,
            "value": true
        })

        units_that_shot.append(active_shooter_id)
        active_shooter_id = ""
        confirmed_assignments.clear()
        pending_save_data.clear()

        return create_result(true, all_diffs, "Saves resolved")
```

### 8.3 ShootingController.gd Modifications

**Add signal connections:**
```gdscript
func set_phase(phase: BasePhase) -> void:
    # ... existing code ...

    if not phase.weapon_order_required.is_connected(_on_weapon_order_required):
        phase.weapon_order_required.connect(_on_weapon_order_required)
    if not phase.weapon_reorder_required.is_connected(_on_weapon_reorder_required):
        phase.weapon_reorder_required.connect(_on_weapon_reorder_required)
    if not phase.weapon_sequence_complete.is_connected(_on_weapon_sequence_complete):
        phase.weapon_sequence_complete.connect(_on_weapon_sequence_complete)
```

**Add new UI elements:**
```gdscript
# Weapon sequence progress UI
var sequence_progress_container: VBoxContainer
var sequence_title_label: Label
var weapon_status_list: VBoxContainer
var weapon_status_items: Array = []  # Array of {icon: Label, name: Label, result: Label}
```

**Create sequence progress UI in `_setup_right_panel()`:**
```gdscript
func _setup_right_panel() -> void:
    # ... existing code for shooting panel ...

    # Add weapon sequence progress section (initially hidden)
    shooting_panel.add_child(HSeparator.new())

    sequence_progress_container = VBoxContainer.new()
    sequence_progress_container.visible = false
    shooting_panel.add_child(sequence_progress_container)

    sequence_title_label = Label.new()
    sequence_title_label.text = "Shooting Sequence"
    sequence_title_label.add_theme_font_size_override("font_size", 14)
    sequence_progress_container.add_child(sequence_title_label)

    sequence_progress_container.add_child(HSeparator.new())

    weapon_status_list = VBoxContainer.new()
    sequence_progress_container.add_child(weapon_status_list)
```

**Add signal handlers:**
```gdscript
func _on_weapon_order_required(assignments: Array, shooter_id: String) -> void:
    """Show weapon order dialog for initial order selection"""
    print("ShootingController: Weapon order required for %d weapons" % assignments.size())

    var dialog = preload("res://scripts/WeaponOrderDialog.gd").new()
    dialog.setup(assignments, shooter_id)
    dialog.order_confirmed.connect(_on_weapon_order_confirmed)
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

func _on_weapon_order_confirmed(weapon_order: Array, fast_roll: bool) -> void:
    """User confirmed weapon order"""
    print("ShootingController: Weapon order confirmed, fast_roll=%s" % fast_roll)

    # Show sequence progress UI if sequential
    if not fast_roll:
        _initialize_sequence_progress(weapon_order)

    # Submit action
    emit_signal("shoot_action_requested", {
        "type": "RESOLVE_WEAPON_SEQUENCE",
        "payload": {
            "weapon_order": weapon_order,
            "fast_roll": fast_roll
        }
    })

func _on_weapon_reorder_required(remaining_assignments: Array, completed_results: Array) -> void:
    """Show reorder dialog between weapons"""
    print("ShootingController: Weapon reorder required, %d remaining" % remaining_assignments.size())

    var dialog = preload("res://scripts/WeaponOrderDialog.gd").new()
    dialog.setup(remaining_assignments, active_shooter_id, completed_results, true)
    dialog.order_confirmed.connect(_on_weapon_reorder_confirmed)
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

func _on_weapon_reorder_confirmed(updated_order: Array, _fast_roll: bool) -> void:
    """User confirmed updated order for remaining weapons"""
    print("ShootingController: Reorder confirmed")

    # Update progress UI
    _update_sequence_progress(updated_order)

    # Submit action
    emit_signal("shoot_action_requested", {
        "type": "CONTINUE_WEAPON_SEQUENCE",
        "payload": {
            "updated_order": updated_order
        }
    })

func _on_weapon_sequence_complete(total_casualties: int) -> void:
    """Weapon sequence finished"""
    print("ShootingController: Sequence complete, %d casualties" % total_casualties)

    # Hide sequence progress
    if sequence_progress_container:
        sequence_progress_container.visible = false

    # Show summary in dice log
    if dice_log_display:
        dice_log_display.append_text("[color=green]✓ Shooting complete: %d total casualties[/color]\n" % total_casualties)

    # Refresh unit list
    _refresh_unit_list()

func _initialize_sequence_progress(weapon_order: Array) -> void:
    """Initialize the sequence progress UI"""
    if not sequence_progress_container or not weapon_status_list:
        return

    # Clear existing items
    for child in weapon_status_list.get_children():
        child.queue_free()
    weapon_status_items.clear()

    # Create status item for each weapon
    for i in range(weapon_order.size()):
        var assignment = weapon_order[i]
        var weapon_profile = RulesEngine.get_weapon_profile(assignment.weapon_id)
        var weapon_name = weapon_profile.get("name", assignment.weapon_id)
        var target_unit = current_phase.get_unit(assignment.target_unit_id)
        var target_name = target_unit.get("meta", {}).get("name", assignment.target_unit_id)

        var item_hbox = HBoxContainer.new()
        weapon_status_list.add_child(item_hbox)

        # Status icon
        var icon = Label.new()
        icon.text = "○"  # Pending
        icon.custom_minimum_size = Vector2(20, 0)
        icon.add_theme_font_size_override("font_size", 16)
        item_hbox.add_child(icon)

        # Weapon name
        var name_label = Label.new()
        name_label.text = "%s → %s" % [weapon_name, target_name]
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        item_hbox.add_child(name_label)

        # Result label (hidden initially)
        var result_label = Label.new()
        result_label.text = ""
        result_label.visible = false
        item_hbox.add_child(result_label)

        weapon_status_items.append({
            "icon": icon,
            "name": name_label,
            "result": result_label
        })

    # Mark first weapon as current
    if weapon_status_items.size() > 0:
        weapon_status_items[0].icon.text = "⚠"
        weapon_status_items[0].icon.modulate = Color.YELLOW

    # Show container
    sequence_progress_container.visible = true

func _update_sequence_progress(updated_order: Array) -> void:
    """Update progress UI after reordering"""
    # This is called after saves, so we need to mark current weapon complete
    # and rebuild remaining weapons

    if not current_phase or not current_phase.resolution_state.has("current_index"):
        return

    var completed_index = current_phase.resolution_state.current_index
    var completed_weapons = current_phase.resolution_state.completed_weapons

    # Mark current weapon as complete
    if completed_index < weapon_status_items.size():
        var item = weapon_status_items[completed_index]
        item.icon.text = "✓"
        item.icon.modulate = Color.GREEN

        # Show casualties
        if completed_weapons.size() > 0:
            var last_result = completed_weapons[completed_weapons.size() - 1]
            item.result.text = "%d casualties" % last_result.get("casualties", 0)
            item.result.visible = true
            item.result.modulate = Color(1.0, 0.5, 0.5)

    # Mark next weapon as current
    if completed_index + 1 < weapon_status_items.size():
        weapon_status_items[completed_index + 1].icon.text = "⚠"
        weapon_status_items[completed_index + 1].icon.modulate = Color.YELLOW
```

### 8.4 SaveDialog.gd Modifications

**Add new properties:**
```gdscript
var weapon_number: int = 1
var total_weapons: int = 1
var previous_results: Array = []
```

**Modify `setup()` to accept sequence data:**
```gdscript
func setup(p_save_data: Dictionary, p_defender_player: int = 0) -> void:
    """Setup the dialog with save resolution data from RulesEngine"""
    save_data = p_save_data
    defender_player = p_defender_player

    # Extract sequence data if present
    weapon_number = save_data.get("weapon_number", 1)
    total_weapons = save_data.get("total_weapons", 1)
    previous_results = save_data.get("previous_results", [])

    if not save_data.get("success", false):
        push_error("SaveDialog: Invalid save data received")
        return

    # Auto-allocate wounds
    allocations = RulesEngine.auto_allocate_wounds(
        save_data.wounds_to_save,
        save_data
    )

    # Update UI
    _update_title()
    _update_previous_results()
    _update_attack_info()
    _update_save_stats()
    _update_model_display()
    _add_to_dice_log("Awaiting defender to roll saves...", Color.YELLOW)

func _update_title() -> void:
    """Update dialog title with weapon sequence info"""
    if total_weapons > 1:
        title = "INCOMING ATTACK (Weapon %d of %d) - DEFEND!" % [weapon_number, total_weapons]
    else:
        title = "INCOMING ATTACK - DEFEND!"

func _update_previous_results() -> void:
    """Add previous results section if this is not the first weapon"""
    if previous_results.is_empty():
        # First weapon - show encouraging message
        var first_weapon_label = Label.new()
        first_weapon_label.text = "First weapon attacking"
        first_weapon_label.add_theme_font_size_override("font_size", 12)
        first_weapon_label.modulate = Color(0.7, 0.7, 1.0)
        vbox.add_child(first_weapon_label)
        vbox.move_child(first_weapon_label, 0)  # Move to top
        vbox.add_child(HSeparator.new())
        return

    # Show previous results
    var prev_label = Label.new()
    prev_label.text = "Previous Weapons:"
    prev_label.add_theme_font_size_override("font_size", 12)
    prev_label.add_theme_font_size_override("font_weight", 700)  # Bold
    vbox.add_child(prev_label)
    vbox.move_child(prev_label, 0)

    for result in previous_results:
        var weapon_profile = RulesEngine.get_weapon_profile(result.weapon_id)
        var weapon_name = weapon_profile.get("name", result.weapon_id)
        var casualties = result.get("casualties", 0)

        var result_hbox = HBoxContainer.new()
        vbox.add_child(result_hbox)
        vbox.move_child(result_hbox, 1 + previous_results.find(result))

        var checkmark = Label.new()
        checkmark.text = "✓"
        checkmark.modulate = Color.GREEN
        checkmark.add_theme_font_size_override("font_size", 14)
        result_hbox.add_child(checkmark)

        var result_text = Label.new()
        result_text.text = "%s → %d casualties" % [weapon_name, casualties]
        result_text.add_theme_font_size_override("font_size", 12)
        result_text.modulate = Color(0.7, 1.0, 0.7)
        result_hbox.add_child(result_text)

    vbox.add_child(HSeparator.new())
    vbox.move_child(vbox.get_child(vbox.get_child_count() - 1), previous_results.size() + 1)
```

## 9. Testing Requirements

### 9.1 Unit Tests
- [ ] Weapon sorting algorithm (damage → AP → alphabetical)
- [ ] Weapon order validation (size match, valid weapon IDs)
- [ ] Target destroyed mid-sequence handling
- [ ] Save/load during weapon sequence
- [ ] Fast roll produces same results as sequential

### 9.2 Integration Tests
- [ ] Single weapon type - no dialog appears
- [ ] 2 weapon types - dialog appears
- [ ] 5+ weapon types - dialog scrolls correctly
- [ ] Reordering weapons - up/down buttons work
- [ ] Fast roll - all weapons resolve at once
- [ ] Sequential - each weapon resolves separately
- [ ] Saves after each weapon in sequence
- [ ] Reorder dialog appears after saves
- [ ] Cannot reorder completed weapons
- [ ] Can reorder remaining weapons
- [ ] Sequence completes correctly
- [ ] Progress UI updates in real-time

### 9.3 Multiplayer Tests
- [ ] Weapon order visible to both players
- [ ] Non-attacker cannot interact with order dialog
- [ ] Dice rolls broadcast to all clients
- [ ] Save dialog appears only for defender
- [ ] Attacker sees "Awaiting defender..." message
- [ ] Reorder dialog appears only for attacker
- [ ] Defender sees "Attacker choosing order..." message
- [ ] Progress updates visible to spectators
- [ ] No desync during sequence
- [ ] Disconnection handled gracefully

### 9.4 Edge Case Tests
- [ ] Target destroyed before weapon fires
- [ ] All targets destroyed mid-sequence
- [ ] No wounds caused by any weapon
- [ ] Save/load during weapon order dialog
- [ ] Save/load during reorder dialog
- [ ] Save/load during save dialog
- [ ] Very long weapon list (10+ types)
- [ ] Same weapon type assigned to different targets
- [ ] All weapons targeting same unit

## 10. Success Metrics

- **Usability**: Weapon order selection takes < 15 seconds on average
- **Performance**: No lag with up to 10 weapon types
- **Reliability**: Zero desyncs in multiplayer testing (100 sequences)
- **Correctness**: Fast roll and sequential produce identical final results
- **User Satisfaction**: 80%+ prefer sequential option in competitive games
- **Code Quality**: 90%+ test coverage for new code

## 11. Future Enhancements (Phase 2+)

### Drag-and-Drop Reordering
- Replace up/down arrows with drag-and-drop interface
- Visual preview of new position while dragging
- Touch support for mobile/tablet

### Smart Weapon Order Suggestions
- "Optimal Order" button based on tactical analysis
- Consider target toughness, wounds remaining, etc.
- Explain why suggested order is optimal

### Animation & Polish
- Weapon icons in order dialog
- Smooth transitions between weapons
- Celebratory effects for high casualty counts
- Sound effects for weapon firing

### Advanced Settings
- Default to fast roll for specific unit types
- Auto-continue between weapons (no reorder dialog)
- Timeout for reordering (auto-continue after 30s)
- Save preferred weapon orders per unit type

## 12. Appendix

### A. Rules References
- Warhammer 40K 10th Edition Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Shooting Phase: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE
- Making Attacks: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Making-Attacks

### B. Dependencies
- Existing ShootingPhase.gd
- Existing ShootingController.gd
- Existing SaveDialog.gd
- RulesEngine.gd (resolve_shoot_until_wounds, apply_save_damage)
- NetworkManager.gd (submit_action, peer_to_player_map)
- GameState.gd (get_unit, create_snapshot)

### C. File Structure
```
40k/
├── phases/
│   └── ShootingPhase.gd (MODIFY)
├── scripts/
│   ├── ShootingController.gd (MODIFY)
│   ├── SaveDialog.gd (MODIFY)
│   └── WeaponOrderDialog.gd (NEW)
└── tests/
    └── unit/
        ├── test_weapon_ordering.gd (NEW)
        └── test_weapon_sequence.gd (NEW)
```

### D. Version History
- **v1.0** (2025-10-12): Initial PRP creation

### E. Sign-off
- [ ] Product Owner
- [ ] Tech Lead
- [ ] UX Designer
- [ ] QA Lead
- [ ] Multiplayer Engineer
