# Multiplayer Model Drag Visual Update Fix

**Issue**: When dragging models in multiplayer mode as a client, models snap back to their original position after release, even for valid moves. The model only appears in the correct position after clicking "Confirm Move".

**Root Cause**: Client-side visual updates were not being triggered after the host validated and applied staged model moves.

## Problem Analysis

### How Multiplayer Actions Work

1. **Client** drags model and releases → sends `STAGE_MODEL_MOVE` action to host
2. **Host** receives action → validates → applies to GameState → emits `model_drop_committed` signal → visual updates
3. **Host** broadcasts result (with diffs) to client via `_broadcast_result` RPC
4. **Client** receives result → applies diffs to GameState → **BUT NO SIGNAL EMITTED** → visual not updated

### The Issue

When the host applies a `STAGE_MODEL_MOVE` action:
- `MovementPhase._process_stage_model_move()` emits `model_drop_committed` signal (line 639)
- `Main._on_model_drop_committed()` catches this signal and moves the visual token (line 2879)
- **This works on the host side**

When the client receives the result via `_broadcast_result`:
- `GameManager.apply_result()` applies the diffs to GameState
- **NO SIGNALS ARE RE-EMITTED**
- The visual token position is not updated
- Model appears to snap back because the visual hasn't moved, only GameState has

## Solution

### Changes Made

#### 1. NetworkManager.gd - Added Client Visual Update Logic

**Location**: `40k/autoloads/NetworkManager.gd`

Added `_emit_client_visual_updates()` method called after `_broadcast_result` applies the result:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
	print("NetworkManager: _broadcast_result received, is_host = ", is_host())
	if is_host():
		return  # Host already applied locally

	# Client applies the result (with diffs already computed by host)
	print("NetworkManager: Client applying result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	# Update phase snapshot so it stays in sync with GameState
	_update_phase_snapshot()

	# MULTIPLAYER FIX: Re-emit phase-specific signals for client visual updates
	# When host applies actions, it emits signals that update visuals
	# Clients need to emit the same signals after applying results
	_emit_client_visual_updates(result)

	print("NetworkManager: Client finished applying result")

func _emit_client_visual_updates(result: Dictionary) -> void:
	"""Emit phase-specific signals on client after applying result for visual updates"""
	var action_type = result.get("action_type", "")
	var action_data = result.get("action_data", {})

	# Get current phase instance
	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager or not phase_manager.current_phase_instance:
		return

	var phase = phase_manager.current_phase_instance

	# Handle movement phase visual updates
	if action_type == "STAGE_MODEL_MOVE":
		if phase.has_signal("model_drop_committed"):
			var unit_id = action_data.get("actor_unit_id", "")
			var model_id = action_data.get("payload", {}).get("model_id", "")
			var dest = action_data.get("payload", {}).get("dest", [])

			if unit_id != "" and model_id != "" and dest.size() == 2:
				var dest_vec = Vector2(dest[0], dest[1])
				print("NetworkManager: Client emitting model_drop_committed for ", unit_id, "/", model_id, " at ", dest_vec)
				phase.emit_signal("model_drop_committed", unit_id, model_id, dest_vec)
```

**Why this works**:
- When client receives the result, after applying diffs, it re-emits the `model_drop_committed` signal
- This triggers `Main._on_model_drop_committed()` which updates the visual token position
- The model now stays where it was dropped, matching the behavior on the host

#### 2. GameManager.gd - Include Action Data in Results

**Location**: `40k/autoloads/GameManager.gd`

Modified `apply_action()` to include the full action data in the result:

```gdscript
func apply_action(action: Dictionary) -> Dictionary:
	var result = process_action(action)
	if result["success"]:
		# Normalize: phases return "changes", we need "diffs" for network sync
		if result.has("changes") and not result.has("diffs"):
			result["diffs"] = result["changes"]

		# Add action type and data to result so consumers can identify what happened
		# This is needed for client-side visual updates in multiplayer
		result["action_type"] = action.get("type", "")
		result["action_data"] = action  # NEW: Include full action data

		apply_result(result)
		action_history.append(action)
	return result
```

**Why this is needed**:
- The result needs to include the original action data (unit_id, model_id, destination)
- Without this, the client can't know which model to update or where to move it
- The action_data is now available for `_emit_client_visual_updates()` to extract the necessary information

## Technical Details

### Signal Flow

**Before Fix (Client Side)**:
```
Client drags model → STAGE_MODEL_MOVE sent to host
↓
Host validates → applies → emits model_drop_committed → updates visual
↓
Host broadcasts result to client
↓
Client applies diffs to GameState
↓
NO SIGNAL EMITTED → Visual NOT updated → Model appears in old position
```

**After Fix (Client Side)**:
```
Client drags model → STAGE_MODEL_MOVE sent to host
↓
Host validates → applies → emits model_drop_committed → updates visual
↓
Host broadcasts result to client
↓
Client applies diffs to GameState
↓
_emit_client_visual_updates() → emits model_drop_committed
↓
Main._on_model_drop_committed() → Updates visual → Model stays in new position ✓
```

### Key Files Modified

1. **40k/autoloads/NetworkManager.gd**:
   - Added `_emit_client_visual_updates()` method
   - Modified `_broadcast_result()` to call the new method

2. **40k/autoloads/GameManager.gd**:
   - Modified `apply_action()` to include `action_data` in result

### Testing

✓ Scripts compile without errors
✓ Single-player mode unaffected (uses direct phase execution, not NetworkManager)
✓ Host mode unaffected (applies locally, doesn't use _broadcast_result)
✓ Client mode now properly updates visuals when dragging models

## Future Extensibility

The `_emit_client_visual_updates()` method is designed to be extensible for other action types:

```gdscript
func _emit_client_visual_updates(result: Dictionary) -> void:
	var action_type = result.get("action_type", "")
	var action_data = result.get("action_data", {})
	var phase = phase_manager.current_phase_instance

	# Movement phase
	if action_type == "STAGE_MODEL_MOVE":
		# ... emit model_drop_committed

	# Can add more action types here as needed:
	elif action_type == "SHOOT_AT_TARGET":
		# ... emit shooting_resolved
	elif action_type == "DECLARE_CHARGE":
		# ... emit charge_declared
	# etc.
```

This pattern can be used for any future actions that need client-side visual updates.

## Related Code References

- `MovementPhase._process_stage_model_move()`: 40k/phases/MovementPhase.gd:568-647
- `Main._on_model_drop_committed()`: 40k/scripts/Main.gd:2879-2903
- `NetworkIntegration.route_action()`: 40k/utils/NetworkIntegration.gd:11-79
- `GameManager.apply_result()`: 40k/autoloads/GameManager.gd:180-200

## Summary

The fix ensures that when a client drags and drops a model in multiplayer mode:
1. The action is sent to the host and validated
2. The host applies it and updates visuals
3. The result is broadcast to the client
4. **The client now re-emits the appropriate phase signal** to trigger its own visual update
5. The model stays where it was dropped, matching the host's behavior

This creates a consistent experience across both host and client in multiplayer games.
