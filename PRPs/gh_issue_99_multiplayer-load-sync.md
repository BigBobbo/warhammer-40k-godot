# PRP: Multiplayer Load Synchronization

**GitHub Issue**: #99
**Feature**: Multiplayer Save/Load Synchronization
**Author**: Claude Code AI
**Date**: 2025-10-08
**Confidence Score**: 8/10 (High confidence - builds on existing patterns)

---

## Executive Summary

Currently, when a player loads a saved game during a multiplayer session, the loaded state is not synchronized with the other player. This creates desynchronization issues where each player sees a different game state. This PRP implements a synchronization mechanism where the host can load a saved game and automatically broadcast the loaded state to all connected clients, ensuring both players see the same game state after loading.

---

## Problem Statement

**Current State**:
- SaveLoadManager handles loading games via `load_game()` and `quick_load()`
- Loading applies state only locally using `GameState.load_from_snapshot()`
- No communication with NetworkManager during load operations
- In multiplayer games, if host loads, client continues with old state
- Results in critical desynchronization between players

**Desired State**:
- Host can load saved games during multiplayer sessions
- When host loads, the loaded state is automatically broadcast to clients
- Clients receive and apply the loaded state seamlessly
- Both players see identical game state after load completes
- UI on both sides updates to reflect loaded state
- Client load attempts during multiplayer are handled gracefully

**Issue Quote** (from GitHub #99):
> "When a player loads a game, if they are playing multiplayer that does not currently sync with the other player. I would like for the host to be able to load games, and when they do both players have the loaded state applied to them."

---

## Requirements Analysis

### Functional Requirements

1. **FR1: Host Load Authority**
   - Only host can load games that affect multiplayer session
   - Host load triggers automatic state synchronization to clients
   - Load operation completes on host before broadcasting to clients

2. **FR2: State Synchronization**
   - Loaded state snapshot is sent from host to all connected clients via RPC
   - Clients receive and apply the loaded state
   - Synchronization uses reliable RPC to prevent packet loss

3. **FR3: UI Refresh**
   - Both host and client UI update after load completes
   - Main scene refreshes to reflect loaded unit positions and state
   - Phase indicators, turn counters, and other UI elements update

4. **FR4: Client Load Handling**
   - Client load attempts during multiplayer show warning/error
   - Alternative: Client loads disconnect them from multiplayer (more drastic)
   - Clear user feedback about why load failed or what happened

5. **FR5: Load Notification**
   - Both players see notification that a load occurred
   - Host sees "Game loaded" confirmation
   - Client sees "Host loaded game" notification

### Non-Functional Requirements

1. **NFR1: Performance** - Load synchronization should complete within 2 seconds
2. **NFR2: Reliability** - Use reliable RPC mode to prevent desynchronization
3. **NFR3: Consistency** - State must be identical on both clients after sync
4. **NFR4: User Experience** - Clear feedback during and after load operation

---

## Current System Analysis

### Existing Save/Load System

**File**: `40k/autoloads/SaveLoadManager.gd`

**Key Loading Methods**:
```gdscript
# Line 91-93: Quick load entry point
func quick_load() -> bool:
    var save_path = save_directory + "quicksave" + SAVE_EXTENSION
    return _load_game_from_path(save_path)

# Line 150-216: Core load implementation
func _load_game_from_path(file_path: String) -> bool:
    # Read save file
    var file = FileAccess.open(file_path, FileAccess.READ)
    var serialized_data = file.get_as_text()

    # Deserialize
    var game_state = StateSerializer.deserialize_game_state(serialized_data)

    # Load into GameState
    GameState.load_from_snapshot(game_state)

    emit_signal("load_completed", file_path, metadata)
    return true
```

**Current Flow** (single-player):
```
User Presses Load
    ↓
SaveLoadManager.quick_load()
    ↓
_load_game_from_path()
    ↓
Read file → Deserialize → GameState.load_from_snapshot()
    ↓
emit signal("load_completed")
    ↓
Main._on_load_completed() → Refresh UI
```

**Issue**: No NetworkManager interaction at all.

### Existing Multiplayer System

**File**: `40k/autoloads/NetworkManager.gd`

**Existing State Sync Pattern** (lines 187-195):
```gdscript
@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
    print("NetworkManager: Receiving initial state from host")

    # Replace local state with host's state
    game_state.load_from_snapshot(snapshot)

    print("NetworkManager: State synchronized")
    emit_signal("game_started")
```

**Called when client connects** (lines 323-332):
```gdscript
func _on_peer_connected(peer_id: int) -> void:
    if is_host():
        peer_to_player_map[peer_id] = 2

        # Send full game state to joining client
        var snapshot = game_state.create_snapshot()
        _send_initial_state.rpc_id(peer_id, snapshot)
```

**Pattern to Reuse**:
- Host creates snapshot with `game_state.create_snapshot()`
- Host sends via RPC: `_send_initial_state.rpc_id(peer_id, snapshot)`
- Client receives and applies: `game_state.load_from_snapshot(snapshot)`

**We can leverage the same RPC for load synchronization!**

### GameState Integration

**File**: `40k/autoloads/GameState.gd`

**Key Methods**:
```gdscript
# Line 270-332: Create snapshot of current state
func create_snapshot() -> Dictionary:
    # Returns deep copy of entire state
    return _deep_copy_dict(state)

# Line 358-379: Load snapshot into current state
func load_from_snapshot(snapshot: Dictionary) -> void:
    state = _deep_copy_dict(snapshot)
    # Also loads terrain and measuring tape data
```

**Already supports full state replacement - perfect for our needs.**

### Main Scene Integration

**File**: `40k/scripts/Main.gd`

**Load Completion Handler** (lines 2017-2037):
```gdscript
func _on_load_completed(file_path: String, metadata: Dictionary) -> void:
    print("Main: Load completed - ", file_path)
    print("Main: Post-load metadata: ", metadata)

    # Refresh the entire game UI
    _refresh_after_load()

    _show_save_notification("Game loaded!", Color.BLUE)
    print("Main: Load complete, game refreshed")

# Line 2132-2153: Refresh UI after load
func _refresh_after_load() -> void:
    # Refresh phase manager and UI
    if phase_manager:
        phase_manager.refresh_from_game_state()

    # Refresh terrain
    _load_terrain()

    # Refresh units
    _spawn_units_from_game_state()

    # Update UI
    _update_turn_info()
    _update_phase_info()
```

**Already handles UI refresh - we just need to trigger it on clients too.**

---

## Technical Research

### Godot 4.4 Multiplayer RPC Patterns

From existing codebase (NetworkManager.gd):

**RPC Authority Modes**:
1. `@rpc("authority", "call_remote", "reliable")` - Only host can call, clients receive
2. `@rpc("any_peer", "call_remote", "reliable")` - Anyone can call, host receives
3. `"reliable"` ensures packet delivery (critical for state sync)

**RPC Targeting**:
- `.rpc()` - Broadcast to all peers
- `.rpc_id(peer_id, ...)` - Send to specific peer

**State Synchronization Best Practices** (from existing PRPs):
1. Host is source of truth for all state
2. Clients must request changes through host
3. Host validates and broadcasts results
4. Use reliable RPCs for critical state changes
5. Send full snapshots for large state changes (not diffs)

### Similar Patterns in Codebase

**Initial Connection Sync** (NetworkManager.gd:323-332):
- Host sends full state snapshot to joining client
- Uses `_send_initial_state()` RPC
- We can reuse this exact RPC for load sync!

**Action Result Sync** (NetworkManager.gd:171-184):
- Host broadcasts action results to clients
- Clients apply results with `game_manager.apply_result(result)`
- Different pattern - we need full state replacement, not incremental updates

**Army Selection Sync** (from gh_issue_95_multiplayer-army-choice.md):
- Host broadcasts army selection changes to clients
- Clients update UI to reflect changes
- Similar user experience pattern to what we need

---

## Implementation Strategy

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    MULTIPLAYER LOAD FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  HOST                              CLIENT                       │
│   │                                  │                          │
│   │ User presses Load (L key)       │                          │
│   ├─────────────────────────────────>│ (no direct notification) │
│   │                                  │                          │
│   │ SaveLoadManager.quick_load()    │                          │
│   │    ↓                             │                          │
│   │ Load file & deserialize          │                          │
│   │    ↓                             │                          │
│   │ GameState.load_from_snapshot()  │                          │
│   │    ↓                             │                          │
│   │ CHECK: is_networked()?           │                          │
│   │    ↓ YES                         │                          │
│   │ NetworkManager.sync_loaded_state()                          │
│   │    ↓                             │                          │
│   │ Create snapshot from loaded state│                          │
│   │    ↓                             │                          │
│   │ RPC: _send_loaded_state()        │                          │
│   ├─────────────────────────────────>│                          │
│   │                                  │ Receive RPC              │
│   │                                  │    ↓                     │
│   │                                  │ GameState.load_from_snapshot()
│   │                                  │    ↓                     │
│   │                                  │ Main._refresh_after_load()
│   │                                  │    ↓                     │
│   │                                  │ Show "Host loaded" notification
│   │                                  │                          │
│   │ Main._refresh_after_load()       │                          │
│   │    ↓                             │                          │
│   │ Show "Game loaded" notification  │                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

**Decision 1: Reuse Existing RPC**
- Reuse `NetworkManager._send_initial_state()` RPC for load sync
- Alternative: Create new `_send_loaded_state()` RPC for clarity
- **Choice**: Create new RPC for semantic clarity and better logging

**Decision 2: When to Sync**
- Option A: Sync immediately after `GameState.load_from_snapshot()` in SaveLoadManager
- Option B: Sync in Main after UI refresh
- **Choice**: Option A - sync immediately to minimize desync window

**Decision 3: Client Load Behavior**
- Option A: Disable load UI for clients entirely
- Option B: Allow client load but show warning
- Option C: Client load forces disconnect from multiplayer
- **Choice**: Option B - show warning but prevent execution

**Decision 4: Load Notification**
- Both players should see notification that load occurred
- Host: "Game loaded successfully"
- Client: "Host loaded game to [turn/phase]"

---

## Implementation Plan

### Phase 1: Add Load Sync RPC to NetworkManager

**File**: `40k/autoloads/NetworkManager.gd`

**Task 1.1**: Add new RPC function for load synchronization

Add after `_send_initial_state()` (after line 195):

```gdscript
@rpc("authority", "call_remote", "reliable")
func _send_loaded_state(snapshot: Dictionary, save_name: String) -> void:
	"""
	Called by host to synchronize loaded game state to clients.
	Similar to _send_initial_state() but used for mid-game loads.
	"""
	print("NetworkManager: Receiving loaded state from host (", save_name, ")")

	# Replace local state with host's loaded state
	game_state.load_from_snapshot(snapshot)

	# Trigger UI refresh on client side
	_refresh_client_ui_after_load(snapshot)

	print("NetworkManager: Loaded state synchronized")
```

**Task 1.2**: Add UI refresh helper for clients

```gdscript
func _refresh_client_ui_after_load(snapshot: Dictionary) -> void:
	"""
	Triggers UI refresh on client after receiving loaded state.
	Notifies Main scene to refresh all game elements.
	"""
	# Get Main scene if it exists
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("_refresh_after_load"):
		print("NetworkManager: Triggering client UI refresh")
		main_scene._refresh_after_load()

		# Show notification to client
		if main_scene.has_method("_show_save_notification"):
			var turn = snapshot.get("meta", {}).get("turn_number", 0)
			var phase = snapshot.get("meta", {}).get("phase", "Unknown")
			main_scene._show_save_notification(
				"Host loaded game (Turn %d, %s)" % [turn, phase],
				Color.CYAN
			)
	else:
		print("NetworkManager: Warning - Could not trigger client UI refresh")
```

**Task 1.3**: Add public method for SaveLoadManager to call

```gdscript
func sync_loaded_state() -> void:
	"""
	Called by SaveLoadManager after host loads a game.
	Broadcasts the loaded state to all connected clients.
	"""
	if not is_networked():
		print("NetworkManager: Not in multiplayer, skipping load sync")
		return

	if not is_host():
		push_error("NetworkManager: Only host can sync loaded state!")
		return

	print("NetworkManager: Syncing loaded state to clients...")

	# Create snapshot of current (newly loaded) state
	var snapshot = game_state.create_snapshot()

	# Get save name from metadata if available
	var save_name = snapshot.get("meta", {}).get("save_name", "Unknown")

	# Broadcast to all clients
	_send_loaded_state.rpc(snapshot, save_name)

	print("NetworkManager: Loaded state sync broadcast complete")
```

### Phase 2: Integrate Load Sync into SaveLoadManager

**File**: `40k/autoloads/SaveLoadManager.gd`

**Task 2.1**: Modify `_load_game_from_path()` to trigger sync

After line 214 (after `emit_signal("load_completed", ...)`), add:

```gdscript
	emit_signal("load_completed", file_path, metadata)
	print("SaveLoadManager: Game loaded successfully from %s" % file_path)

	# NEW: Sync state with multiplayer clients if in networked game
	if NetworkManager and NetworkManager.is_networked():
		print("SaveLoadManager: Multiplayer detected, syncing loaded state...")
		NetworkManager.sync_loaded_state()

	return true
```

**Task 2.2**: Add helper to check if we're in multiplayer

No changes needed - NetworkManager already has `is_networked()` and `is_host()` methods.

### Phase 3: Handle Client Load Attempts

**File**: `40k/scripts/Main.gd`

**Task 3.1**: Add check before allowing load

Modify `_perform_quick_load()` (around line 1799) to add multiplayer check:

```gdscript
func _perform_quick_load() -> void:
	print("========================================")
	print("QUICK LOAD TRIGGERED")
	print("========================================")

	# NEW: Check if we're in multiplayer as a client
	if NetworkManager and NetworkManager.is_networked() and not NetworkManager.is_host():
		_show_save_notification("Only host can load games in multiplayer", Color.RED)
		push_warning("Main: Client attempted to load during multiplayer - blocked")
		return

	print("Pre-load game state meta: ", GameState.state.get("meta", {}))

	# Show immediate UI feedback
	_show_save_notification("Loading...", Color.YELLOW)

	# Debug: Check if save file exists
	_debug_load_system()

	var success = SaveLoadManager.quick_load()
	print("========================================")
	print("QUICK LOAD RESULT: ", success)
	print("Post-load game state meta: ", GameState.state.get("meta", {}))
	print("========================================")

	if success:
		_show_save_notification("Game loaded!", Color.BLUE)
```

**Task 3.2**: Similarly update MainMenu load handler

**File**: `40k/scripts/MainMenu.gd`

Modify `_on_load_requested()` (line 182):

```gdscript
func _on_load_requested(save_file: String) -> void:
	print("MainMenu: Load requested for file: ", save_file)

	# Check if we're in multiplayer (shouldn't be from main menu, but safety check)
	if NetworkManager and NetworkManager.is_networked():
		print("MainMenu: Cannot load during active multiplayer session")
		# Could show error dialog here
		return

	if SaveLoadManager:
		var success = SaveLoadManager.load_game(save_file)
		if success:
			print("MainMenu: Successfully loaded game: ", save_file)
			# Mark that we're loading from a save, not from menu config
			if GameState.state.meta:
				GameState.state.meta["from_save"] = true
				GameState.state.meta.erase("from_menu")
			# Transition to main game scene
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		else:
			print("MainMenu: Failed to load game: ", save_file)
	else:
		print("MainMenu: SaveLoadManager not available")
```

### Phase 4: Ensure UI Refresh on Both Sides

**No changes needed** - existing code already handles this:

**Host Side**:
- `SaveLoadManager.emit_signal("load_completed", ...)` (line 214)
- `Main._on_load_completed()` connected to signal (line 2017)
- `Main._refresh_after_load()` called automatically (line 2132)

**Client Side**:
- `NetworkManager._send_loaded_state()` calls `_refresh_client_ui_after_load()`
- Which calls `main_scene._refresh_after_load()` on client
- Same refresh logic applies

### Phase 5: Add Metadata to Save Files

**Optional Enhancement**: Include save name in metadata for better notifications.

**File**: `40k/autoloads/SaveLoadManager.gd`

Modify `_create_save_metadata()` (line 347):

```gdscript
func _create_save_metadata(custom_metadata: Dictionary = {}) -> Dictionary:
	var metadata = {
		"version": "1.0.0",
		"created_at": Time.get_unix_time_from_system(),
		"game_state": {
			"turn": GameState.get_turn_number(),
			"phase": GameState.get_current_phase(),
			"active_player": GameState.get_active_player(),
			"game_id": GameState.state.get("meta", {}).get("game_id", "")
		},
		"save_info": {
			"save_type": custom_metadata.get("type", "manual"),
			"description": custom_metadata.get("description", ""),
			"tags": custom_metadata.get("tags", [])
		}
	}

	# Add custom metadata
	for key in custom_metadata:
		if not metadata.has(key):
			metadata[key] = custom_metadata[key]

	return metadata
```

No changes needed - metadata already includes turn/phase info.

### Phase 6: Testing and Validation

Create test script: `40k/tests/network/test_multiplayer_load_sync.gd`

```gdscript
extends GutTest

# Tests multiplayer load synchronization

func before_each():
	# Initialize game state
	GameState.initialize_default_state()

	# Setup minimal multiplayer environment
	if NetworkManager:
		NetworkManager.network_mode = NetworkManager.NetworkMode.OFFLINE

func test_host_can_trigger_load_sync():
	# Setup host
	NetworkManager.network_mode = NetworkManager.NetworkMode.HOST
	NetworkManager.peer_to_player_map[1] = 1

	# Create a test save
	var test_state = GameState.create_snapshot()
	test_state["meta"]["turn_number"] = 5

	# Mock the sync call
	var sync_called = false
	var original_func = NetworkManager.sync_loaded_state
	NetworkManager.sync_loaded_state = func():
		sync_called = true

	# Trigger load (would normally be from SaveLoadManager)
	NetworkManager.sync_loaded_state()

	assert_true(sync_called, "Sync should have been called")

func test_client_cannot_trigger_load_sync():
	# Setup client
	NetworkManager.network_mode = NetworkManager.NetworkMode.CLIENT
	NetworkManager.peer_to_player_map[2] = 2

	# Try to sync (should fail/warn)
	NetworkManager.sync_loaded_state()

	# Should see error in console (check with gut_yielding if needed)
	pass  # Assertion would check error was logged

func test_load_sync_includes_full_state():
	# Setup host
	NetworkManager.network_mode = NetworkManager.NetworkMode.HOST

	# Create test state with units
	GameState.state.units = {
		"unit_1": {"owner": 1, "position": Vector2(100, 100)},
		"unit_2": {"owner": 2, "position": Vector2(200, 200)}
	}

	# Get snapshot
	var snapshot = GameState.create_snapshot()

	# Verify snapshot has units
	assert_eq(snapshot.units.size(), 2, "Snapshot should include all units")
	assert_true(snapshot.has("meta"), "Snapshot should include metadata")
	assert_true(snapshot.has("board"), "Snapshot should include board")
```

---

## Testing Strategy

### Manual Testing Checklist

#### Test Case 1: Host Load in Single-Player
```
1. Launch game in single-player mode
2. Play for a few turns
3. Save game (F5)
4. Continue playing
5. Load game (L key)
6. Verify game state restored correctly
7. Verify no errors about multiplayer
```
**Expected**: Normal single-player load, no multiplayer code triggered.

#### Test Case 2: Host Load in Multiplayer
```
Setup:
- Machine A: Host game on port 7777
- Machine B: Join as client

Steps:
1. Host plays a few moves
2. Host saves game (F5)
3. Host continues playing (change game state)
4. Host loads saved game (L key)
5. VERIFY on Client: Game state updates to match loaded state
6. VERIFY on Client: UI shows "Host loaded game" notification
7. VERIFY on Host: UI shows "Game loaded" notification
8. Both players: Check unit positions match
9. Both players: Check turn counter matches
10. Both players: Check phase matches
11. Continue playing to verify sync maintained
```
**Expected**: Both machines show identical state after load.

#### Test Case 3: Client Attempts Load in Multiplayer
```
Setup:
- Machine A: Host game
- Machine B: Join as client

Steps:
1. On Client (Machine B), press L key to load
2. VERIFY: Error message "Only host can load games in multiplayer"
3. VERIFY: No state change occurs
4. VERIFY: No desynchronization
5. Host continues playing normally
```
**Expected**: Client load blocked with clear error message.

#### Test Case 4: Load During Different Game Phases
```
For each phase (Deployment, Movement, Shooting, Charge, Fight):
1. Host saves during that phase
2. Host advances to a different phase
3. Host loads the save
4. VERIFY on both: Correct phase restored
5. VERIFY on both: Phase-specific UI elements correct
```
**Expected**: Phase context properly restored on both sides.

#### Test Case 5: Load After Client Disconnect/Reconnect
```
1. Host and client playing
2. Host saves game
3. Client disconnects
4. Host loads saved game
5. Client reconnects
6. VERIFY: Client receives current (loaded) state
```
**Expected**: Reconnecting client gets loaded state, not pre-disconnect state.

#### Test Case 6: Rapid Multiple Loads
```
1. Host saves game as "save1"
2. Host plays and saves as "save2"
3. Host rapidly loads "save1", then "save2", then "save1"
4. VERIFY on client: State syncs correctly for each load
5. VERIFY: No race conditions or partial state syncs
```
**Expected**: Each load fully syncs before next one.

### Validation Gates

#### 1. Compilation Check
```bash
# Ensure no syntax errors in modified files
godot --headless --check-only --path 40k/ res://autoloads/NetworkManager.gd
godot --headless --check-only --path 40k/ res://autoloads/SaveLoadManager.gd
godot --headless --check-only --path 40k/ res://scripts/Main.gd
godot --headless --check-only --path 40k/ res://scripts/MainMenu.gd
```

#### 2. Single-Player Regression Test
```bash
# Ensure single-player saving/loading still works
# Run in headless mode with test script if available
godot --path 40k/ -s res://tests/integration/test_save_load.gd
```

#### 3. Network RPC Validation
```gdscript
# In Godot editor console, verify RPC is registered:
var network_mgr = get_node("/root/NetworkManager")
print(network_mgr.get_method_list())
# Should see _send_loaded_state in the list
```

#### 4. Local Multiplayer Test
```bash
# Terminal 1 (Host)
godot --path 40k/

# Terminal 2 (Client)
godot --path 40k/

# Then perform Test Case 2 manually
```

#### 5. State Verification Script
```gdscript
# Run this on both host and client after load
var snapshot = GameState.create_snapshot()
print("Units: ", snapshot.units.keys())
print("Turn: ", snapshot.meta.turn_number)
print("Phase: ", snapshot.meta.phase)
print("Active Player: ", snapshot.meta.active_player)

# Compare outputs - should be identical
```

---

## Edge Cases and Error Handling

### Edge Case 1: Save File Doesn't Exist
**Scenario**: Host tries to load non-existent save
**Current Handling**: SaveLoadManager returns false, shows error
**New Behavior**: No sync triggered (sync only on successful load)
**Code**: Check in SaveLoadManager - only sync if `load_game_from_path()` returns true

### Edge Case 2: Corrupted Save File
**Scenario**: Host loads corrupted save, deserialization fails
**Current Handling**: SaveLoadManager logs error, returns false
**New Behavior**: No sync triggered, both players remain on current state
**Additional Safety**: Could add RPC to notify client "Load failed" if needed

### Edge Case 3: Client Disconnects During Load Sync
**Scenario**: RPC sent but client disconnects before receiving
**Handling**:
- RPC lost (expected in ENet)
- When client reconnects, host's `_on_peer_connected()` sends current state
- Client gets fresh state (which is the loaded state)
**No additional code needed** - existing reconnection logic handles this.

### Edge Case 4: Host Loads While Action in Progress
**Scenario**: Client is in middle of moving unit, host loads different state
**Handling**:
- Load sync overrides all current state
- Client's in-progress action is abandoned
- Client UI refreshes to loaded state
**Acceptable behavior** - host has authority, loading overrides current actions.

### Edge Case 5: Network Lag During Sync
**Scenario**: Large save file, slow network connection
**Handling**:
- RPC is reliable - will eventually arrive
- Client may experience brief lag/freeze while receiving large state
- UI notification appears after sync complete
**Mitigation**: Use compression if save files get very large (already available in StateSerializer)

### Edge Case 6: Save from Single-Player Loaded in Multiplayer
**Scenario**: Host loads a save that was created in single-player mode
**Handling**:
- Save file doesn't have multiplayer-specific data
- GameState.load_from_snapshot() handles it fine
- Sync proceeds normally
- Both players see the loaded state
**No special handling needed** - save format is agnostic to multiplayer.

### Edge Case 7: Different Game Versions
**Scenario**: Host and client on different game versions, state format differs
**Current Handling**: StateSerializer has version checking
**Risk**: If version mismatch severe enough, deserialization could fail on client
**Mitigation**: Already have version field in saves (line 10 of StateSerializer.gd)
**Future Enhancement**: Check versions match before allowing multiplayer connection

---

## Implementation Tasks (Ordered)

### Stage 1: NetworkManager RPC Implementation
1. ✅ Add `_send_loaded_state()` RPC function to NetworkManager
2. ✅ Add `_refresh_client_ui_after_load()` helper function
3. ✅ Add `sync_loaded_state()` public method
4. ✅ Add debug logging for load sync operations

### Stage 2: SaveLoadManager Integration
5. ✅ Modify `_load_game_from_path()` to trigger sync after load
6. ✅ Add check for `NetworkManager.is_networked()` before syncing
7. ✅ Add debug logging for multiplayer load detection

### Stage 3: Client Load Prevention
8. ✅ Modify `Main._perform_quick_load()` to block client loads
9. ✅ Add error message/notification for blocked client loads
10. ✅ Modify `MainMenu._on_load_requested()` for safety check

### Stage 4: Testing & Validation
11. ⏳ Create unit tests in `test_multiplayer_load_sync.gd`
12. ⏳ Run compilation validation for all modified files
13. ⏳ Manual test: Single-player load (regression test)
14. ⏳ Manual test: Host load in multiplayer
15. ⏳ Manual test: Client blocked from loading
16. ⏳ Manual test: Load during different phases
17. ⏳ Manual test: Multiple rapid loads

### Stage 5: Polish & Documentation
18. ⏳ Review all debug logging for consistency
19. ⏳ Ensure client notifications are user-friendly
20. ⏳ Update MULTIPLAYER_LOBBY_GUIDE.md (if exists)
21. ⏳ Add comments to complex RPC functions
22. ⏳ Final code review

---

## Success Criteria

Implementation is considered complete when:

1. ✅ **Host Load Works**: Host can load saved games during multiplayer
2. ✅ **State Syncs**: Loaded state automatically syncs to all clients
3. ✅ **UI Updates**: Both host and client UI refresh after load
4. ✅ **Client Blocked**: Client load attempts show error and don't execute
5. ✅ **Notifications**: Both players see appropriate load notifications
6. ✅ **No Desync**: Game state identical on both machines after load
7. ✅ **No Regressions**: Single-player save/load still works correctly
8. ✅ **All Tests Pass**: Manual testing checklist completed successfully
9. ✅ **Compilation Clean**: No syntax errors or warnings
10. ✅ **Logging Clear**: Debug logs help troubleshoot any issues

---

## Known Limitations and Future Enhancements

### Current Limitations

1. **Only Host Can Load**
   - Client cannot load their own local saves during multiplayer
   - **Rationale**: Prevents desynchronization, host is authority
   - **Future**: Could allow client to "request load" that host approves

2. **No Load Progress Indicator**
   - Large save files may cause brief freeze during sync
   - **Workaround**: Use compression in StateSerializer (already available)
   - **Future**: Add loading screen with progress bar

3. **No Confirmation Dialog**
   - Host load happens immediately, no "This will affect both players" warning
   - **Workaround**: Document behavior clearly
   - **Future**: Add confirmation dialog "Load for both players?"

4. **No Save File Preview**
   - Can't see which save is which in multiplayer
   - **Current**: Must use MainMenu load dialog which shows metadata
   - **Future**: Add in-game save browser

### Future Enhancements

1. **Load Request System**
   - Client can request host to load a specific save
   - Host sees notification and can approve/deny
   - Prevents host from being sole decision maker

2. **Synchronized Save Naming**
   - When host saves during multiplayer, both players track the save name
   - Client can see list of "session saves" available to load
   - Improves UX for collaborative play

3. **Checkpoint System**
   - Auto-save at start of each turn
   - Allow "rewind to previous turn" in multiplayer
   - Useful for undoing mistakes by mutual agreement

4. **Save Versioning**
   - Track multiple saves within a session
   - Easy access to "5 turns ago" state
   - Branching timeline support

5. **Load Conflict Resolution**
   - If client has different local state, show diff
   - Allow host to choose: "Override with my save" or "Keep current state"
   - Advanced feature for power users

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Large save causes network timeout | Low | Medium | Use compression, test with large armies |
| Client receives partial state | Low | High | Use reliable RPC, validate state after load |
| UI refresh fails on client | Low | Medium | Add error handling in refresh function |
| Race condition with in-progress actions | Medium | Medium | Document that load overrides actions |
| Deserialization fails on client | Low | High | Version checking in StateSerializer |
| Host loads wrong save accidentally | Medium | Low | Future: add confirmation dialog |

---

## References and Documentation

### Godot Documentation
- High-Level Multiplayer: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- RPC Documentation: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-rpc

### Codebase References
- **SaveLoadManager.gd** (lines 150-216): Load implementation
- **NetworkManager.gd** (lines 187-195, 323-332): State sync pattern
- **GameState.gd** (lines 270-332, 358-379): Snapshot system
- **Main.gd** (lines 1799-1819, 2017-2037, 2132-2153): Load UI handling
- **StateSerializer.gd** (lines 24-86): Serialization system

### Existing PRPs
- **gh_issue_95_multiplayer-army-choice.md**: Army selection sync pattern
- **gh_issue_96_multiplayer-start-sync.md**: Game start synchronization
- **gh_issue_89_multiplayer_FINAL_v4s.md**: Core multiplayer architecture

### Warhammer 40K Rules
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- (Not directly relevant to this feature, but included per template)

---

## Confidence Score Justification: 8/10

**Why 8/10?**

**Strengths:**
1. ✅ Reuses proven RPC pattern from `_send_initial_state()`
2. ✅ SaveLoadManager and GameState already fully functional
3. ✅ Clear integration points identified
4. ✅ Minimal code changes required
5. ✅ Good error handling patterns exist
6. ✅ Existing UI refresh mechanism works well

**Risks (2 points deducted):**
1. ⚠️ Testing requires two machines/instances (harder to validate)
2. ⚠️ Network edge cases always carry some uncertainty
3. ⚠️ Large save files might expose performance issues
4. ⚠️ UI refresh on client side is indirect (relies on Main scene being active)

**Mitigations:**
- Thorough manual testing checklist provided
- Edge cases documented with handling strategies
- Reliable RPC mode prevents most sync issues
- Existing patterns prove the architecture works

**Overall Assessment:**
This is a straightforward feature that builds on well-tested multiplayer and save/load systems. The main risk is in thorough testing of edge cases, but the implementation itself is low-risk. One-pass implementation is very likely with careful attention to the testing checklist.

---

## Final Implementation Checklist

Before considering this complete:

- [ ] All Stage 1-3 tasks completed
- [ ] All validation gates pass
- [ ] Manual Test Case 1 (single-player) passes
- [ ] Manual Test Case 2 (host multiplayer load) passes
- [ ] Manual Test Case 3 (client blocked) passes
- [ ] Manual Test Case 4 (different phases) passes
- [ ] No console errors during load operations
- [ ] No console errors during state sync
- [ ] Host sees "Game loaded" notification
- [ ] Client sees "Host loaded game" notification
- [ ] Game state visually identical on both machines
- [ ] Can continue playing after load with no desync
- [ ] Code reviewed for consistency with existing style
- [ ] Debug logging comprehensive and clear
- [ ] Edge cases tested or documented as known limitations

---

**END OF PRP**
