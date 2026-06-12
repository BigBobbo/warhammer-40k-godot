# Debug Mode Drag Fix - Implementation Summary

## Issue
Debug mode (activated by pressing 9) was not allowing users to drag models. The feature was supposed to allow unrestricted model movement from either army, but the drag operation wasn't working.

## Root Causes Identified

### 1. Missing Ghost Visual Creation
- **Problem**: DebugManager tried to update ghost visuals but never created them
- **Location**: `40k/autoloads/DebugManager.gd` line 110 (`_highlight_dragged_model` was a stub)
- **Fix**: Implemented `_create_debug_ghost()` to properly instantiate GhostVisual scenes

### 2. No Multiplayer Synchronization
- **Problem**: Debug movements updated GameState directly without network sync
- **Location**: `40k/autoloads/DebugManager.gd` line 127-128
- **Fix**: Added `_update_model_position_networked()` to use NetworkManager.submit_action()

### 3. No Action Handler for DEBUG_MOVE
- **Problem**: GameManager didn't know how to process DEBUG_MOVE actions
- **Location**: `40k/autoloads/GameManager.gd`
- **Fix**: Added DEBUG_MOVE case to process_action() match statement and implemented process_debug_move()

### 4. No Validation for Debug Actions
- **Problem**: Phase validation might block DEBUG_MOVE actions
- **Location**: `40k/phases/BasePhase.gd` validate_action()
- **Fix**: Added DEBUG_MOVE check that validates only when debug mode is active

## Files Changed

### 1. `/40k/autoloads/DebugManager.gd`
**Changes:**
- Replaced `_highlight_dragged_model(model)` stub with `_create_debug_ghost(model)`
- Implemented `_create_debug_ghost()` to create GhostVisual instances
- Implemented `_get_full_model_data()` helper to fetch complete model data from GameState
- Updated `_end_debug_drag()` to check for multiplayer and route through NetworkManager
- Implemented `_update_model_position_networked()` to create and submit DEBUG_MOVE actions

**Key Code:**
```gdscript
func _create_debug_ghost(model_data: Dictionary) -> void:
    # Load GhostVisual.tscn
    # Set model data for proper shape/size
    # Position at model's current location
    # Add to GhostLayer

func _update_model_position_networked(unit_id: String, model_id: String, new_position: Vector2) -> void:
    var action = {
        "type": "DEBUG_MOVE",
        "unit_id": unit_id,
        "model_id": model_id,
        "position": [new_position.x, new_position.y],
        "player": GameState.get_active_player(),
        "timestamp": Time.get_ticks_msec()
    }
    NetworkManager.submit_action(action)
```

### 2. `/40k/autoloads/GameManager.gd`
**Changes:**
- Added "DEBUG_MOVE" case to process_action() match statement (line 103-104)
- Implemented `process_debug_move()` function to handle debug movement actions
- Creates diffs for position updates that sync across network

**Key Code:**
```gdscript
func process_debug_move(action: Dictionary) -> Dictionary:
    # Validate action data
    # Find model in GameState
    # Create diff for position update
    # Return success with diff for network broadcast
```

### 3. `/40k/phases/BasePhase.gd`
**Changes:**
- Updated `validate_action()` to check for DEBUG_MOVE actions
- Validates that DebugManager.is_debug_active() before allowing DEBUG_MOVE
- Bypasses normal phase-specific validation for debug actions

**Key Code:**
```gdscript
func validate_action(action: Dictionary) -> Dictionary:
    if action_type == "DEBUG_MOVE":
        if DebugManager and DebugManager.is_debug_active():
            return {"valid": true}
        else:
            return {"valid": false, "reason": "Debug mode not active"}
    # ... rest of validation
```

## Testing Checklist

### Single-Player Testing
- [ ] Press 9 to activate debug mode
- [ ] Verify "DEBUG MODE ACTIVE" overlay appears
- [ ] Verify tokens show debug styling (yellow/orange)
- [ ] Click and drag a model
- [ ] Verify ghost visual appears with correct shape/size
- [ ] Verify ghost follows mouse during drag
- [ ] Release mouse to drop model
- [ ] Verify model moves to new position
- [ ] Verify visual updates on board
- [ ] Press 9 to exit debug mode
- [ ] Verify overlay disappears
- [ ] Verify tokens return to normal colors

### Multiplayer Testing (Host)
- [ ] Host a multiplayer game
- [ ] Press 9 to enter debug mode
- [ ] Verify client sees overlay appear
- [ ] Drag a model
- [ ] Verify client sees model move
- [ ] Verify ghost visual appears during drag
- [ ] Verify position syncs to client after drop

### Multiplayer Testing (Client)
- [ ] Join a multiplayer game
- [ ] Press 9 to enter debug mode
- [ ] Verify overlay appears locally
- [ ] Drag a model
- [ ] Verify host sees model move
- [ ] Verify ghost visual appears during drag
- [ ] Verify position syncs to host after drop

### Edge Cases
- [ ] Try dragging models from both armies
- [ ] Try dragging models with non-circular bases
- [ ] Try dragging models with large bases (vehicles)
- [ ] Try rapid debug mode toggle (9 pressed multiple times)
- [ ] Try debug mode during different phases
- [ ] Try debug mode with embarked units

## How to Test

### Run the test script:
```bash
./test_debug_mode_fix.sh
```

### Or manually:
```bash
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot project.godot
```

### Check logs:
```bash
# Find latest log file
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/logs/ | grep debug

# View log
cat ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -i "debug"
```

## Expected Behavior

### Debug Mode Activation (Press 9)
```
DebugLogger: "Entering DEBUG MODE"
- Overlay appears at top of screen
- Text: "DEBUG MODE ACTIVE"
- Instructions: "Press 9 to exit | Click and drag any model"
- Background tint: semi-transparent dark blue
- All tokens show debug styling (yellow/orange borders)
```

### Model Drag Start (Click model)
```
DebugLogger: "Started dragging [model_id] from unit [unit_id]"
DebugLogger: "Created ghost visual at [position]"
- Ghost visual appears at model position
- Ghost has correct shape (circular, oval, etc.)
- Ghost has correct size (matching model base)
```

### Model Drag Update (Mouse move)
```
- Ghost position updates to follow mouse
- Ghost remains visible during drag
```

### Model Drag End (Release mouse)
```
DebugLogger: "Moved model [model_id] to [position]"
DebugLogger: "Submitting DEBUG_MOVE action..." (if multiplayer)
- Ghost visual disappears
- Model visual updates to new position
- Board refreshes to show new layout
```

### Multiplayer Sync
```
NetworkManager: "submit_action called for type: DEBUG_MOVE"
NetworkManager: "Broadcasting result to clients"
GameManager: "Applying result with 1 diffs"
- Opponent sees model move to new position
- Visual updates on both host and client
```

## Logging

Debug mode operations are logged via DebugLogger:
- `DebugLogger.info()` - Major state changes (enter/exit debug mode)
- `DebugLogger.debug()` - Detailed operation logs (drag start/end)
- `DebugLogger.error()` - Error conditions (ghost creation failure)

All logs are written to:
```
~/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
```

## Network Message Flow

### Single-Player
```
User drags model
    ↓
DebugManager._end_debug_drag()
    ↓
DebugManager._update_model_position_debug()
    ↓
GameState.state.units[unit_id]["models"][i]["position"] = new_pos
    ↓
Main._recreate_unit_visuals() refreshes display
```

### Multiplayer (Host)
```
User drags model
    ↓
DebugManager._end_debug_drag()
    ↓
DebugManager._update_model_position_networked()
    ↓
NetworkManager.submit_action(DEBUG_MOVE)
    ↓
GameManager.process_debug_move()
    ↓
GameManager.apply_result() with diffs
    ↓
NetworkManager._broadcast_result.rpc()
    ↓
Client receives and applies result
```

### Multiplayer (Client)
```
User drags model
    ↓
DebugManager._end_debug_drag()
    ↓
DebugManager._update_model_position_networked()
    ↓
NetworkManager.submit_action(DEBUG_MOVE)
    ↓
NetworkManager._send_action_to_host.rpc_id(1, action)
    ↓
Host validates and processes
    ↓
Host broadcasts result back to client
    ↓
Client applies result and updates visuals
```

## Validation Flow

```
NetworkManager.validate_action(DEBUG_MOVE)
    ↓
BasePhase.validate_action(DEBUG_MOVE)
    ↓
Check: DebugManager.is_debug_active()
    ↓
If true: return {"valid": true}
If false: return {"valid": false, "reason": "Debug mode not active"}
```

## Troubleshooting

### Ghost visual doesn't appear
**Check:**
1. Is GhostVisual.tscn loading correctly?
   - Look for error: "Could not load GhostVisual.tscn"
2. Is GhostLayer present in scene tree?
   - Look for error: "GhostLayer not found"
3. Does model have complete data?
   - Check for: base_type, base_dimensions, position, rotation

### Model doesn't move
**Check:**
1. Is DEBUG_MOVE action being submitted?
   - Look for: "Submitting DEBUG_MOVE action"
2. Is GameManager processing it?
   - Look for: "Processing DEBUG_MOVE action"
3. Are diffs being applied?
   - Look for: "Setting units.X.models.Y.position"

### Multiplayer sync fails
**Check:**
1. Is NetworkManager initialized?
   - Look for: "NetworkManager: Initialized"
2. Is action being sent to host?
   - Look for: "Client mode - sending to host"
3. Is host broadcasting result?
   - Look for: "Broadcasting result to clients"
4. Is client receiving result?
   - Look for: "_broadcast_result received"

## Related Documentation

- PRP Document: `/PRPs/gh_issue_111_debug-mode-drag-fix.md`
- Original Debug Mode PRP: `/40k/PRPs/gh_issue_14_debug-mode.md`
- Multiplayer Architecture: `/PRPs/gh_issue_89_multiplayer.md`
- Ghost Visual Fix: `/PRPs/gh_issue_drag-ghost-size-fix.md`

## Confidence Level: 9/10

Implementation follows established patterns and integrates cleanly with existing systems. The main areas of potential issues are:
- Ghost visual creation timing
- Multiplayer sync edge cases
- Visual refresh timing

All of these have been addressed with proper error handling and logging.
