# Interactive Save System - Implementation Status

**Date**: 2025-10-11
**PRP**: saves_and_damage_allocation_prp.md
**Phase**: Phase 1 MVP

## ✅ Completed Components

### 1. RulesEngine Helper Functions (`40k/autoloads/RulesEngine.gd`)

**New Functions Added:**
- `prepare_save_resolution()` - Prepares save data for interactive resolution
- `auto_allocate_wounds()` - Auto-allocates wounds following 10e rules (wounded models first)
- `roll_saves_batch()` - Rolls all saves at once with results
- `apply_save_damage()` - Applies damage from failed saves
- `resolve_shoot_until_wounds()` - Resolves shooting but stops before saves
- `_resolve_assignment_until_wounds()` - Helper for above
- `_get_save_allocation_requirements()` - Determines allocation requirements

**Lines**: 1816-2056 (new section)

### 2. SaveDialog UI Component (`40k/scripts/SaveDialog.gd`)

**Features Implemented:**
- Displays incoming attack information (attacker, weapon, AP, damage)
- Shows save statistics (base save, modifiers, cover, invuln)
- Auto-allocation visualization (model grid with HP display)
- Batch save rolling with dice log
- Results display with pass/fail coloring
- Signal-based communication with phase

**Signals:**
- `saves_rolled(save_results)` - Emitted when saves are rolled
- `save_complete()` - Emitted when damage is applied

**Key Methods:**
- `setup(save_data)` - Initializes dialog with save data
- `_on_roll_saves_pressed()` - Handles save rolling
- `_on_apply_damage_pressed()` - Triggers damage application

### 3. ShootingPhase Integration (`40k/phases/ShootingPhase.gd`)

**Modifications:**

**New Signal:**
- `saves_required(save_data_list: Array)` - Emitted when saves are needed

**New State Variable:**
- `pending_save_data: Array` - Stores save data awaiting resolution

**Modified Functions:**
- `_process_resolve_shooting()` - Now uses `resolve_shoot_until_wounds()` and emits `saves_required` signal instead of auto-resolving

**New Action Type:**
- `APPLY_SAVES` - Processes save results and applies damage

**New Functions:**
- `_validate_apply_saves()` - Validates save application
- `_process_apply_saves()` - Processes save results and applies diffs

**Lines Modified/Added:**
- Line 12: Added `saves_required` signal
- Line 21: Added `pending_save_data` state
- Lines 62-87: Added APPLY_SAVES to validation
- Lines 89-114: Added APPLY_SAVES to processing
- Lines 306-365: Modified `_process_resolve_shooting()`
- Lines 686-764: Added save resolution functions

## 🔧 Remaining Work

### 1. Wire Up SaveDialog to ShootingController/Main

**What Needs to Be Done:**
Connect the `saves_required` signal from ShootingPhase to show the SaveDialog

**Location**: Likely in `ShootingController.gd` or `Main.gd`

**Implementation Approach:**
```gdscript
# In ShootingController or Main
func _ready():
    # ... existing code ...

    # Connect to shooting phase
    var phase_manager = get_node("/root/PhaseManager")
    if phase_manager:
        var shooting_phase = phase_manager.get_phase_instance(GameStateData.Phase.SHOOTING)
        if shooting_phase:
            shooting_phase.saves_required.connect(_on_saves_required)

func _on_saves_required(save_data_list: Array):
    """Show SaveDialog when saves are needed"""
    # Load and create dialog
    var save_dialog_script = load("res://scripts/SaveDialog.gd")

    # For Phase 1 MVP: Process each save data separately
    # (Later phases can handle multiple simultaneous)
    for save_data in save_data_list:
        var dialog = save_dialog_script.new()
        dialog.setup(save_data)

        # Connect completion signal
        dialog.save_complete.connect(_on_save_dialog_complete.bind(save_data_list))

        # Show dialog
        add_child(dialog)
        dialog.popup_centered()

        # For MVP, only show first one
        break

func _on_save_dialog_complete(save_data_list: Array):
    """Called when player completes save rolls"""
    # Collect save results from all dialogs
    var save_results_list = []

    # For MVP with single dialog, we need to collect the results
    # This is simplified - in production you'd track multiple dialogs

    # Create APPLY_SAVES action
    var action = {
        "type": "APPLY_SAVES",
        "player": GameState.get_active_player(),
        "payload": {
            "save_results_list": save_results_list
        }
    }

    # Submit action through network manager
    NetworkManager.submit_action(action)
```

**Alternative Simpler Approach:**
Modify SaveDialog to submit the action itself:

```gdscript
# In SaveDialog._on_apply_damage_pressed():
func _on_apply_damage_pressed() -> void:
    # Create action with results
    var action = {
        "type": "APPLY_SAVES",
        "player": GameState.get_active_player(),
        "payload": {
            "save_results_list": [save_results]  # Wrap in array
        }
    }

    # Submit directly
    NetworkManager.submit_action(action)

    emit_signal("save_complete")
    hide()
    queue_free()
```

This approach is simpler and doesn't require modifying ShootingController.

### 2. Testing & Bug Fixes

**Single-Player Testing:**
1. Load a save with two opposing units
2. Select a unit to shoot
3. Assign targets and confirm
4. Should see SaveDialog appear with attack info
5. Click "Roll All Saves"
6. Verify save rolls appear in log
7. Click "Apply Damage"
8. Verify damage is applied to target models
9. Verify shooting continues normally

**Expected Issues to Fix:**
- SaveDialog might need scene tree reference fixes
- Signal connections might need adjustment
- RulesEngine functions might have edge cases
- State management might need cleanup

### 3. Multiplayer Support

**Current State:**
- The action-based architecture supports multiplayer
- `APPLY_SAVES` action will sync across network
- Defender sees dialog, makes saves, submits action
- Attacker sees "Waiting for defender..." message

**What's Needed:**
1. Add "Waiting for defender..." UI message when `saves_required` is emitted
2. Only show SaveDialog to the defending player
3. Test network sync of APPLY_SAVES action
4. Handle timeouts/disconnections

**Implementation:**
```gdscript
func _on_saves_required(save_data_list: Array):
    var local_player = NetworkManager.peer_to_player_map.get(multiplayer.get_unique_id(), 1)
    var defending_player = _get_defending_player(save_data_list[0])

    if local_player == defending_player:
        # Show dialog to defender
        _show_save_dialog(save_data_list)
    else:
        # Show waiting message to attacker
        _show_waiting_message("Waiting for defender to make saves...")

func _get_defending_player(save_data: Dictionary) -> int:
    var target_unit_id = save_data.get("target_unit_id", "")
    var target_unit = GameState.get_unit(target_unit_id)
    return target_unit.get("owner", 0)
```

## 📋 Phase 1 MVP Checklist

From PRP Section 7 - Phase 1:

- [x] **Basic wound allocation UI** - SaveDialog displays models and allocations
- [x] **Rules-compliant auto-allocation** - RulesEngine.auto_allocate_wounds()
- [x] **Batch save rolling** - SaveDialog "Roll All Saves" button
- [x] **Simple damage application** - RulesEngine.apply_save_damage()
- [ ] **Network control transfer** - Needs wiring in ShootingController
- [x] **Result display** - SaveDialog dice log shows all results

**Status**: 5/6 core features complete (83%)

## 🔍 Architecture Overview

### Data Flow

```
1. Attacker shoots
   └─> ShootingPhase._process_resolve_shooting()
       └─> RulesEngine.resolve_shoot_until_wounds()
           └─> Returns save_data_list

2. ShootingPhase emits saves_required(save_data_list)
   └─> [NEEDS WIRING] ShootingController._on_saves_required()
       └─> Creates and shows SaveDialog
           └─> User rolls saves
               └─> SaveDialog._on_roll_saves_pressed()
                   └─> RulesEngine.roll_saves_batch()

3. User clicks "Apply Damage"
   └─> SaveDialog._on_apply_damage_pressed()
       └─> Submits APPLY_SAVES action
           └─> NetworkManager.submit_action()
               └─> ShootingPhase._process_apply_saves()
                   └─> RulesEngine.apply_save_damage()
                       └─> Returns diffs
                           └─> Applied to GameState
```

### Key Design Decisions

1. **Auto-Allocation Only in Phase 1** - Manual allocation deferred to Phase 2
2. **Batch Rolling** - All saves rolled at once for speed
3. **Signal-Based UI** - SaveDialog communicates via signals, not direct calls
4. **Action-Based State Changes** - All mutations go through validated actions
5. **RulesEngine Separation** - Pure functions, no side effects
6. **Network-Ready** - Action system works for both single and multiplayer

## 🐛 Known Limitations

1. **Single Target Only** - Phase 1 handles one target at a time
2. **No Manual Allocation** - Defender can't choose which model takes wounds
3. **No Re-Rolls** - Command re-rolls not yet implemented
4. **No Invuln Display** - UI doesn't highlight invuln saves specially
5. **No Feel No Pain** - FNP rolls deferred to Phase 3
6. **No Cover Indicators** - Cover detected but not visually shown
7. **No Multiplayer Testing** - Network sync not yet verified

## 📝 Next Steps for Developer

### Immediate (to complete Phase 1 MVP):

1. **Wire SaveDialog** - Add 20-30 lines to ShootingController.gd or Main.gd
2. **Test Locally** - Run through shooting sequence
3. **Fix Bugs** - Address any runtime errors
4. **Test Multiplayer** - Verify network sync works
5. **Update PRP** - Mark Phase 1 as complete

### Estimated Time: 2-3 hours

### Future Phases:

**Phase 2** (Enhanced):
- Manual wound allocation UI
- Individual save control (roll one at a time)
- Command re-rolls
- Visual health bars with animations

**Phase 3** (Complete):
- Feel No Pain rolls
- Invulnerable save highlighting
- Stratagem integration
- Mortal wounds

## 📄 Files Modified

1. `40k/autoloads/RulesEngine.gd` - Added interactive save functions
2. `40k/phases/ShootingPhase.gd` - Integrated interactive saves
3. `40k/scripts/SaveDialog.gd` - **NEW** UI component

## 🔗 Related PRPs

- **Base PRP**: `PRPs/saves_and_damage_allocation_prp.md`
- **Related**: Shooting Phase Enhanced (modifiers already implemented)

## ✅ Validation Checklist

Before marking Phase 1 complete:

- [ ] SaveDialog appears when shooting causes wounds
- [ ] Auto-allocation follows 10e rules (wounded models first)
- [ ] All saves can be rolled at once
- [ ] Dice log shows pass/fail results
- [ ] Damage is correctly applied to models
- [ ] Models are removed when destroyed
- [ ] Shooting sequence continues normally after saves
- [ ] Works in single-player mode
- [ ] Works in multiplayer mode
- [ ] No crashes or errors in console

## 📞 Support

If issues arise:
1. Check console for error messages
2. Verify signal connections in scene tree
3. Test RulesEngine functions in isolation
4. Review PRP Section 8 (Testing Requirements)
5. Check network logs for multiplayer issues
