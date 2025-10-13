# PRP: Fix Multiplayer Game Start Synchronization

## Issue Reference
GitHub Issue #96: Multi start - When the host starts a game that a non-host has joined, the non-host's screen never progresses or changes.

## Problem Statement
When a host starts a multiplayer game from the lobby by clicking "Start Game", only the host's screen transitions to the game scene. The client remains stuck in the lobby screen and never receives notification to transition to the game.

## Root Cause Analysis

### Current Implementation Flow

**Host Side** (`MultiplayerLobby.gd:95-108`):
```gdscript
func _on_start_game_button_pressed() -> void:
    print("MultiplayerLobby: Start game button pressed")

    if not is_hosting:
        _show_error("Only the host can start the game")
        return

    if connected_players < 2:
        _show_error("Waiting for player 2 to connect")
        return

    # Load the game scene
    print("MultiplayerLobby: Starting multiplayer game")
    get_tree().change_scene_to_file("res://scenes/Main.tscn")  # LOCAL ONLY!
```

**Client Side**:
- The `_on_game_started()` callback exists (lines 165-168) but does nothing
- No RPC is called to notify client about game start
- Client continues waiting in lobby indefinitely

### The Problem
`get_tree().change_scene_to_file()` is a **local** operation that only affects the machine it's called on. It does not trigger any network synchronization or RPC calls. The client has no way to know the host started the game.

## Context and Research Findings

### Existing Infrastructure

1. **NetworkManager** (`40k/autoloads/NetworkManager.gd`):
   - Lines 6-10: Signals defined including `game_started`
   - Lines 58-71: `create_host()` sets up host networking
   - Lines 73-85: `join_as_client()` sets up client networking
   - Lines 156-164: `_send_initial_state()` RPC syncs state to client
   - Lines 259-278: `_on_peer_connected()` handles connection events
   - **Missing**: RPC to notify clients when game should start

2. **MultiplayerLobby** (`40k/scripts/MultiplayerLobby.gd`):
   - Lines 38-43: Connects to NetworkManager signals including `game_started`
   - Lines 95-108: Host's start button handler (problem area)
   - Lines 165-168: `_on_game_started()` callback exists but is incomplete
   - **Missing**: Client scene transition logic

3. **Main.gd** (`40k/scripts/Main.gd:39-52`):
   - Already handles initialization for menu-started games
   - Uses `from_menu` and `from_save` flags in GameState.meta
   - No special handling for multiplayer initialization needed

### Godot Multiplayer Patterns

From Godot documentation (https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html):

**Best Practice for Scene Synchronization**:
```gdscript
# Host initiates scene change
@rpc("authority", "call_local", "reliable")
func start_game():
    get_tree().change_scene_to_file("res://scenes/Game.tscn")

# Called from button/trigger
func on_start_pressed():
    start_game.rpc()  # Calls on all peers AND local
```

Key points:
- Use `@rpc` annotation for network-synchronized functions
- `"authority"` means only server/host can call this
- `"call_local"` means it executes on the caller too
- `"reliable"` ensures guaranteed delivery
- `.rpc()` broadcasts to all peers

## Implementation Blueprint

### Step 1: Add RPC Method to NetworkManager

Add a new RPC method to handle game start synchronization:

```gdscript
# 40k/autoloads/NetworkManager.gd
# Add after line 164 (_send_initial_state method)

# Initiates game start for both host and all clients
@rpc("authority", "call_local", "reliable")
func start_multiplayer_game() -> void:
	print("NetworkManager: Starting multiplayer game - transitioning to Main scene")

	# This runs on both host and client due to call_local
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

	# Emit local signal for any cleanup
	emit_signal("game_started")
```

**Why this approach?**
- `@rpc` makes it network-aware
- `"authority"` ensures only host can call it
- `"call_local"` means host also transitions (DRY principle)
- `"reliable"` guarantees delivery (critical for game start)

### Step 2: Update MultiplayerLobby to Use RPC

Modify the start game button handler:

```gdscript
# 40k/scripts/MultiplayerLobby.gd
# Replace lines 95-108

func _on_start_game_button_pressed() -> void:
	print("MultiplayerLobby: Start game button pressed")

	if not is_hosting:
		_show_error("Only the host can start the game")
		return

	if connected_players < 2:
		_show_error("Waiting for player 2 to connect")
		return

	# Trigger game start via NetworkManager RPC
	# This will call on both host and client automatically
	var network_manager = get_node("/root/NetworkManager")
	network_manager.start_multiplayer_game.rpc()

	print("MultiplayerLobby: Game start RPC sent to all peers")
```

### Step 3: Remove Obsolete Callback (Optional Cleanup)

The `_on_game_started()` callback (lines 165-168) is no longer needed since the RPC handles everything:

```gdscript
# 40k/scripts/MultiplayerLobby.gd
# Lines 165-168 can be simplified or removed

func _on_game_started() -> void:
	print("MultiplayerLobby: Game started signal received")
	# Scene transition now handled by RPC
	# This callback can be used for cleanup if needed
```

### Step 4: Verify Game State Initialization

Ensure Main.gd properly initializes for multiplayer games:

```gdscript
# 40k/scripts/Main.gd
# The _ready() method (lines 39-52) should handle multiplayer correctly

func _ready() -> void:
	# Check if we're coming from main menu or loading a save
	var from_menu = GameState.state.meta.has("from_menu") if GameState.state.has("meta") else false
	var from_save = GameState.state.meta.has("from_save") if GameState.state.has("meta") else false
	var is_multiplayer = NetworkManager.is_networked()

	if not from_menu and not from_save:
		# For multiplayer games started from lobby, initialize default state
		if is_multiplayer:
			print("Main: Multiplayer game - waiting for state sync")
			# Client will receive state via NetworkManager._send_initial_state RPC
			# Host already has state from lobby
		else:
			# Legacy path: direct load for testing
			print("Main: Direct load detected, initializing default state")
			GameState.initialize_default_state()
	# ... rest of initialization
```

**Note**: This change may not be strictly necessary if the current flow already works, but it makes multiplayer initialization explicit.

## Implementation Tasks (In Order)

1. **Add RPC to NetworkManager**
   - Add `start_multiplayer_game()` RPC method
   - Ensure proper annotations: `@rpc("authority", "call_local", "reliable")`
   - Include logging for debugging

2. **Update MultiplayerLobby start handler**
   - Replace direct `change_scene_to_file()` call with RPC
   - Keep validation logic (host check, player count check)
   - Add logging to confirm RPC is sent

3. **Test basic flow**
   - Host creates game
   - Client joins
   - Host clicks "Start Game"
   - Verify both screens transition to Main scene

4. **Verify game state sync**
   - Ensure NetworkManager._send_initial_state still works
   - Verify client receives proper game state
   - Test that both players can take turns

5. **Add error handling**
   - Handle edge case: client disconnects during scene transition
   - Handle edge case: scene load failure
   - Add timeout detection

6. **Create integration test**
   - Write test for multiplayer game start flow
   - Mock peer connections
   - Verify RPC is called correctly

## Error Handling Strategy

### Edge Cases to Handle

1. **Client disconnects during scene transition**:
```gdscript
func _on_peer_disconnected(peer_id: int) -> void:
	# If in lobby, handle disconnect
	# If scene is changing, abort transition
	if get_tree().current_scene.name == "MultiplayerLobby":
		print("NetworkManager: Peer disconnected during lobby phase")
		# Existing disconnect handling
```

2. **Scene load failure**:
```gdscript
@rpc("authority", "call_local", "reliable")
func start_multiplayer_game() -> void:
	print("NetworkManager: Starting multiplayer game")

	var error = get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		push_error("NetworkManager: Failed to load Main scene: %d" % error)
		# Fallback: return to lobby
		get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")
		return

	emit_signal("game_started")
```

3. **RPC timeout/failure**:
   - Godot handles RPC delivery automatically with "reliable" mode
   - If client is disconnected, Godot will trigger `peer_disconnected` signal
   - Host should detect if client never transitions (via heartbeat or state check)

## Testing Strategy

### Manual Testing Checklist

1. **Basic Flow**:
   - [ ] Host creates game on port 7777
   - [ ] Client joins host's game
   - [ ] Both players see "Connected Players: 2/2"
   - [ ] Host clicks "Start Game"
   - [ ] **Both screens transition to Main scene**
   - [ ] Host sees deployment phase
   - [ ] Client sees deployment phase

2. **Edge Cases**:
   - [ ] Client disconnects before host clicks start - host should see disconnect
   - [ ] Host disconnects before clicking start - client should see disconnect
   - [ ] Client disconnects during scene transition - graceful error handling
   - [ ] Rapid start button clicks - should only start once

3. **State Verification**:
   - [ ] After transition, check NetworkManager.is_networked() == true on both
   - [ ] Verify game state is synced between host and client
   - [ ] Verify player assignments (host = player 1, client = player 2)

### Unit Tests

Create test file: `40k/tests/network/test_game_start_sync.gd`

```gdscript
extends GutTest

var network_manager: NetworkManager
var mock_tree: SceneTree

func before_each():
	network_manager = NetworkManager.new()
	add_child_autofree(network_manager)

func test_start_game_rpc_exists():
	assert_true(network_manager.has_method("start_multiplayer_game"),
		"NetworkManager should have start_multiplayer_game RPC method")

func test_start_game_is_rpc_annotated():
	# Verify the method has RPC configuration
	var rpc_config = network_manager.get_rpc_config()
	assert_true(rpc_config.has("start_multiplayer_game"),
		"start_multiplayer_game should be configured as RPC")

func test_only_host_can_call_start_game():
	network_manager.network_mode = NetworkManager.NetworkMode.CLIENT

	# Attempting to call as client should fail
	# Note: In actual implementation, Godot will reject this at network level
	# This test documents the expected behavior
	assert_false(network_manager.is_host(),
		"Client should not be able to call authority RPC")

func test_host_can_call_start_game():
	network_manager.network_mode = NetworkManager.NetworkMode.HOST

	# Host should be able to trigger game start
	assert_true(network_manager.is_host(),
		"Host should be able to call authority RPC")
```

### Integration Testing

**Two-Instance Test** (manual):
```bash
# Terminal 1: Start host
export PATH="$HOME/bin:$PATH"
godot --position 0,0 40k/project.godot

# Terminal 2: Start client
godot --position 800,0 40k/project.godot

# Steps:
# 1. In instance 1: Click Multiplayer -> Host game on port 7777
# 2. In instance 2: Click Multiplayer -> Join game at 127.0.0.1:7777
# 3. Wait for connection (should see 2/2 players)
# 4. In instance 1: Click "Start Game"
# 5. Verify BOTH instances transition to Main scene
```

## Validation Gates

```bash
# Test compilation - ensure no syntax errors
export PATH="$HOME/bin:$PATH"
godot --headless --check-only 40k/project.godot

# Run network tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/network/test_game_start_sync.gd
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/network/test_network_manager.gd

# Search for any remaining direct scene changes in multiplayer code
grep -n "change_scene_to_file.*Main.tscn" 40k/scripts/MultiplayerLobby.gd
# After fix, this should NOT appear in _on_start_game_button_pressed

# Verify RPC annotation exists
grep -A3 "@rpc.*start_multiplayer_game" 40k/autoloads/NetworkManager.gd
```

## Documentation References

### Godot 4 Networking Documentation
- **High-level Multiplayer**: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
  - Section: "Remote procedure calls (RPCs)"
  - Section: "Synchronizing game state"
- **RPC Annotations**: https://docs.godotengine.org/en/4.4/classes/class_node.html#class-node-annotation-rpc
  - Parameters: authority, call_local, reliable
- **MultiplayerAPI**: https://docs.godotengine.org/en/4.4/classes/class_multiplayerapi.html
  - Method: `rpc()` for calling remote procedures

### Related Code References
- `NetworkManager.gd` (40k/autoloads/NetworkManager.gd): Core networking system
- `MultiplayerLobby.gd` (40k/scripts/MultiplayerLobby.gd): Lobby UI and connection handling
- `Main.gd` (40k/scripts/Main.gd): Main game scene initialization
- `GameState.gd` (40k/autoloads/GameState.gd): Game state management
- Issue #89 PRPs: Original multiplayer implementation documentation

### Example Projects
- Godot Multiplayer Demo: https://github.com/godotengine/godot-demo-projects/tree/master/networking/multiplayer_bomber
  - Shows RPC usage for game state synchronization
  - Example of scene synchronization in turn-based context

## Security Considerations

### Authority Validation
The `@rpc("authority", ...)` annotation ensures only the host can call `start_multiplayer_game()`. If a client attempts to call it:
- Godot's multiplayer system rejects it at the network layer
- No validation code needed in the function itself
- Host is always peer ID 1

### Potential Exploits
1. **Race condition**: Client and host start simultaneously
   - Mitigation: "authority" mode prevents client from calling RPC

2. **Scene load hijacking**: Malicious client tries to load different scene
   - Mitigation: Scene path is hardcoded in RPC, not parameter

3. **State desync**: Client and host load different game states
   - Mitigation: NetworkManager._send_initial_state already handles this (line 156-164)

## Performance Considerations

### Network Traffic
- **Single RPC call**: ~100 bytes (minimal overhead)
- **Scene transition**: Local operation, no network traffic
- **State sync**: Already handled by existing `_send_initial_state` RPC

### Latency Impact
- RPC delivery: ~10-50ms on local network, ~50-200ms over internet
- Scene load time: ~500-1000ms (same as single-player)
- Total delay: Client sees game ~500-1200ms after host clicks start

### Optimization Opportunities
- Pre-load Main scene during lobby (future enhancement)
- Stream assets during lobby countdown (future enhancement)
- Current implementation is adequate for MVP

## Known Limitations

1. **No loading screen**: Both players see instant transition
   - Enhancement: Add loading screen for better UX

2. **No countdown**: Game starts immediately when host clicks
   - Enhancement: Add 3-2-1 countdown timer

3. **No ready check**: Host can start even if client isn't ready
   - Enhancement: Add player ready/not-ready system

4. **No cancel**: Once start is clicked, no way to abort
   - Enhancement: Add "Cancel" during scene transition

## Future Enhancements

### Phase 1: Basic Improvements
1. Add loading screen during scene transition
2. Add visual feedback when start is clicked
3. Disable start button after click to prevent double-click

### Phase 2: Enhanced UX
4. Add countdown timer (3-2-1-GO!)
5. Add ready/not-ready system for both players
6. Add "Cancel" option during countdown
7. Show loading progress for both players

### Phase 3: Robustness
8. Add timeout detection (if client doesn't transition in 10 seconds)
9. Add retry mechanism for failed transitions
10. Add automatic reconnection if disconnected during transition
11. Save game state before transition for recovery

## Confidence Score

**9/10** - Very high confidence due to:
- Clear root cause identified (missing RPC call)
- Godot's built-in RPC system handles the heavy lifting
- Minimal code changes required (2 files, ~15 lines)
- Well-established pattern in Godot multiplayer games
- Existing NetworkManager infrastructure supports this
- Clear testing strategy with manual verification

Minor uncertainty around:
- Edge case handling during scene transitions (but can be added incrementally)
- Potential timing issues with very slow connections (but "reliable" mode mitigates this)

This is a straightforward bug fix that leverages existing Godot multiplayer primitives. The implementation is clean, maintainable, and follows best practices from the Godot documentation.

## Implementation Checklist

- [ ] Add `start_multiplayer_game()` RPC to NetworkManager
- [ ] Update MultiplayerLobby start button handler to use RPC
- [ ] Test host-client game start flow
- [ ] Verify both screens transition correctly
- [ ] Test edge cases (disconnects, rapid clicks)
- [ ] Verify game state synchronization works
- [ ] Create unit tests for RPC method
- [ ] Update documentation if needed
- [ ] Verify no regressions in single-player mode
