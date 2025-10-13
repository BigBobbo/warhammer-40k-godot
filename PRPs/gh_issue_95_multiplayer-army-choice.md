# PRP: Multiplayer Army Choice Implementation

**GitHub Issue**: #95
**Feature**: Multiplayer Army Selection
**Author**: Claude Code AI
**Date**: 2025-10-06
**Confidence Score**: 9/10 (High confidence - leverages existing patterns)

---

## Executive Summary

Currently, the multiplayer lobby allows players to connect and start a game, but does not provide any mechanism to choose army lists. This results in players being forced to use placeholder armies or the default armies hardcoded in the system. This PRP implements army selection UI in the multiplayer lobby, allowing both host and client to choose their armies before the game starts, with proper network synchronization.

---

## Problem Statement

**Current State**:
- MultiplayerLobby.gd only has connection settings (IP, Port, Host/Join buttons)
- No army selection UI in multiplayer flow
- Armies are only selected in single-player MainMenu.gd
- When multiplayer game starts, it uses placeholder armies or default state

**Desired State**:
- Host can select Player 1 army (their army)
- Host can optionally pre-select Player 2 army as a default
- Client can select/change Player 2 army when they connect
- Both players see each other's army selections in real-time
- Armies are loaded and synchronized before game starts
- Army configuration is included in initial state sync

---

## Requirements Analysis

### Functional Requirements

1. **FR1: Army Selection UI in Lobby**
   - Add army dropdown for host (Player 1 selection)
   - Add army dropdown for client (Player 2 selection)
   - Display currently selected armies for both players
   - Disable opponent's army dropdown (can't change other player's choice)

2. **FR2: Network Synchronization**
   - Host's army selection broadcasts to client
   - Client's army selection sends to host and broadcasts back
   - Both players see real-time updates of army choices

3. **FR3: Army Loading**
   - Load armies when "Start Game" is pressed (not after scene transition)
   - Include army configuration in NetworkManager's initial state sync
   - Validate armies exist before starting game

4. **FR4: Default Behavior**
   - Host defaults to first available army (Adeptus Custodes)
   - Client defaults to third available army (Orks)
   - Allow changes before game start

5. **FR5: Validation**
   - Ensure selected armies exist in armies/ directory
   - Prevent game start if army loading fails
   - Show error messages for invalid selections

### Non-Functional Requirements

1. **NFR1: Performance** - Army selection should not cause network lag
2. **NFR2: Reliability** - Army sync should be reliable (use "reliable" RPC mode)
3. **NFR3: User Experience** - Clear visual feedback of selections
4. **NFR4: Maintainability** - Reuse existing ArmyListManager patterns

---

## Current System Analysis

### Existing Army Selection System (Single-Player)

**File**: `40k/scripts/MainMenu.gd`

**Key Components**:
```gdscript
# Lines 8-9: Army dropdowns
@onready var player1_dropdown: OptionButton = $MenuContainer/ArmySection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $MenuContainer/ArmySection/Player2Container/Player2Dropdown

# Lines 30-34: Army options
var army_options = [
    {"id": "adeptus_custodes", "name": "Adeptus Custodes"},
    {"id": "space_marines", "name": "Space Marines"},
    {"id": "orks", "name": "Orks"}
]

# Lines 66-69: Populate dropdowns
for option in army_options:
    player1_dropdown.add_item(option.name)
    player2_dropdown.add_item(option.name)

# Lines 104-109: Store in config
var config = {
    "terrain": terrain_options[terrain_dropdown.selected].id,
    "mission": mission_options[mission_dropdown.selected].id,
    "deployment": deployment_options[deployment_dropdown.selected].id,
    "player1_army": army_options[player1_dropdown.selected].id,
    "player2_army": army_options[player2_dropdown.selected].id
}

# Lines 144-159: Load armies via ArmyListManager
var player1_army = ArmyListManager.load_army_list(config.player1_army, 1)
if not player1_army.is_empty():
    ArmyListManager.apply_army_to_game_state(player1_army, 1)
```

### Existing Multiplayer Lobby System

**File**: `40k/scripts/MultiplayerLobby.gd`

**Current UI Elements** (lines 5-15):
```gdscript
@onready var host_button: Button
@onready var join_button: Button
@onready var port_input: LineEdit
@onready var ip_input: LineEdit
@onready var status_label: Label
@onready var info_label: Label
@onready var player_list_label: Label
@onready var start_game_button: Button
@onready var disconnect_button: Button
@onready var back_button: Button
```

**Connection Flow**:
1. Host presses "Host Game" → `_on_host_button_pressed()` (line 47)
2. Client presses "Join Game" → `_on_join_button_pressed()` (line 69)
3. Client connects → `_on_peer_connected()` (line 135)
4. Host presses "Start Game" → `_on_start_game_button_pressed()` (line 95)
5. NetworkManager.start_multiplayer_game.rpc() called (line 109)

### Network Manager Integration

**File**: `40k/autoloads/NetworkManager.gd`

**Initial State Sync** (lines 179-187):
```gdscript
@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
    print("NetworkManager: Receiving initial state from host")
    GameState.load_from_snapshot(snapshot)
    print("NetworkManager: State synchronized")
    emit_signal("game_started")
```

**Called when peer connects** (lines 310-322):
```gdscript
func _on_peer_connected(peer_id: int) -> void:
    if is_host():
        peer_to_player_map[peer_id] = 2
        var snapshot = game_state.create_snapshot()
        _send_initial_state.rpc_id(peer_id, snapshot)
        emit_signal("peer_connected", peer_id)
```

### Army List Manager

**File**: `40k/autoloads/ArmyListManager.gd`

**Key Methods**:
```gdscript
# Line 12: Scan available armies
func scan_available_armies() -> void

# Line 46: Load army from JSON
func load_army_list(army_name: String, player: int = 1) -> Dictionary

# Line 183: Apply army to GameState
func apply_army_to_game_state(army_data: Dictionary, player: int) -> void

# Line 225: Get available armies
func get_available_armies() -> Array
```

**Available Armies**:
- `40k/armies/adeptus_custodes.json`
- `40k/armies/space_marines.json`
- `40k/armies/orks.json`

---

## Technical Research

### Godot 4.4 Multiplayer Best Practices

From research and existing codebase:

1. **RPC Patterns**:
   - Use `@rpc("authority", "call_remote", "reliable")` for state sync (one-way from host)
   - Use `@rpc("any_peer", "call_remote", "reliable")` for client-to-host messages
   - Use `.rpc_id(peer_id, ...)` to target specific peer
   - Use `.rpc()` to broadcast to all peers

2. **State Synchronization**:
   - Send full state snapshots on initial connection
   - Send incremental updates (diffs) for changes
   - Host is source of truth for all state

3. **Authority**:
   - Only host can call authority RPCs
   - Clients must send requests to host
   - Host validates and broadcasts results

**Reference**: Existing NetworkManager implementation (lines 135-177)

### UI Layout References

**MainMenu.tscn** has the pattern we need:
```
VBoxContainer (ArmySection)
├── HBoxContainer (Player1Container)
│   ├── Label "Player 1 Army:"
│   └── OptionButton (Player1Dropdown)
└── HBoxContainer (Player2Container)
    ├── Label "Player 2 Army:"
    └── OptionButton (Player2Dropdown)
```

We'll replicate this in MultiplayerLobby.tscn.

---

## Implementation Strategy

### Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                     MULTIPLAYER LOBBY                           │
├────────────────────────────────────────────────────────────────┤
│ Connection Settings (existing)                                  │
│  ├─ Host/Join buttons                                          │
│  ├─ IP/Port inputs                                             │
│  └─ Connection status                                          │
├────────────────────────────────────────────────────────────────┤
│ Army Selection (NEW)                                            │
│  ├─ Player 1 Army: [Dropdown] ← Host controls                 │
│  └─ Player 2 Army: [Dropdown] ← Client controls               │
├────────────────────────────────────────────────────────────────┤
│ Ready Status (NEW)                                              │
│  ├─ Player 1: [Ready/Not Ready]                               │
│  └─ Player 2: [Ready/Not Ready]                               │
├────────────────────────────────────────────────────────────────┤
│ Action Buttons (existing)                                       │
│  ├─ Start Game (host only, enabled when both ready)           │
│  ├─ Disconnect                                                 │
│  └─ Back                                                        │
└────────────────────────────────────────────────────────────────┘
```

### Network Flow

```
HOST                          CLIENT
  │                             │
  │ Select P1 Army (Custodes)  │
  ├─────────────────────────────>
  │  RPC: sync_army_selection  │
  │        (player=1, army=...) │
  │                             │ [Receives, updates P1 dropdown]
  │                             │
  │ [Client connects]           │
  │<─────────────────────────────
  │                             │
  │ Send initial state          │
  ├─────────────────────────────>
  │  RPC: _send_initial_state  │
  │        (includes armies)    │
  │                             │ [Loads state, populates UI]
  │                             │
  │                             │ Select P2 Army (Orks)
  │<─────────────────────────────
  │  RPC: request_army_change  │
  │        (player=2, army=...) │
  │                             │
  │ [Validates & Applies]       │
  │                             │
  │ Broadcast P2 army update    │
  ├─────────────────────────────>
  │  RPC: sync_army_selection  │
  │                             │ [Confirms selection]
  │                             │
  │ Press "Start Game"          │
  │                             │
  │ Load armies into GameState  │
  │                             │
  │ Start game RPC              │
  ├─────────────────────────────>
  │                             │ [Loads Main.tscn]
  │ [Loads Main.tscn]           │
```

---

## Implementation Plan

### Phase 1: Add Army Selection UI to Lobby Scene

**Files to Modify**:
- `40k/scenes/MultiplayerLobby.tscn`
- `40k/scripts/MultiplayerLobby.gd`

**Tasks**:

#### 1.1: Update MultiplayerLobby.tscn

Add new UI section between ConnectionSettings and StatusSection:

```gdscript
[node name="ArmySelection" type="VBoxContainer" parent="LobbyContainer"]
layout_mode = 2
theme_override_constants/separation = 15

[node name="ArmyLabel" type="Label" parent="LobbyContainer/ArmySelection"]
layout_mode = 2
text = "Army Selection"
theme_override_font_sizes/font_size = 20
horizontal_alignment = 1

[node name="Player1Container" type="HBoxContainer" parent="LobbyContainer/ArmySelection"]
layout_mode = 2
alignment = 1

[node name="Player1Label" type="Label" parent="LobbyContainer/ArmySelection/Player1Container"]
layout_mode = 2
custom_minimum_size = Vector2(150, 0)
text = "Player 1 Army:"
theme_override_font_sizes/font_size = 16

[node name="Player1Dropdown" type="OptionButton" parent="LobbyContainer/ArmySelection/Player1Container"]
layout_mode = 2
custom_minimum_size = Vector2(250, 40)

[node name="Player2Container" type="HBoxContainer" parent="LobbyContainer/ArmySelection"]
layout_mode = 2
alignment = 1

[node name="Player2Label" type="Label" parent="LobbyContainer/ArmySelection/Player2Container"]
layout_mode = 2
custom_minimum_size = Vector2(150, 0)
text = "Player 2 Army:"
theme_override_font_sizes/font_size = 16

[node name="Player2Dropdown" type="OptionButton" parent="LobbyContainer/ArmySelection/Player2Container"]
layout_mode = 2
custom_minimum_size = Vector2(250, 40)
```

#### 1.2: Update MultiplayerLobby.gd to Add UI References

Add to top of file (after line 15):
```gdscript
# Army selection UI
@onready var player1_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $LobbyContainer/ArmySelection/Player2Container/Player2Dropdown

# Army configuration
var army_options: Array = []
var selected_player1_army: String = "adeptus_custodes"
var selected_player2_army: String = "orks"
```

#### 1.3: Populate Army Dropdowns in _ready()

Add after line 45 (after NetworkManager signal connections):
```gdscript
# Load available armies from ArmyListManager
_setup_army_selection()
```

Add new function at end of file:
```gdscript
func _setup_army_selection() -> void:
	# Get available armies
	army_options = []
	var available_armies = ArmyListManager.get_available_armies()

	# Build army options (mirror MainMenu.gd pattern)
	for army_name in available_armies:
		army_options.append({
			"id": army_name,
			"name": _format_army_name(army_name)
		})

	# Fallback if no armies found
	if army_options.is_empty():
		army_options = [
			{"id": "adeptus_custodes", "name": "Adeptus Custodes"},
			{"id": "space_marines", "name": "Space Marines"},
			{"id": "orks", "name": "Orks"}
		]

	# Populate dropdowns
	for option in army_options:
		player1_dropdown.add_item(option.name)
		player2_dropdown.add_item(option.name)

	# Set defaults (P1=Custodes index 0, P2=Orks index 2)
	player1_dropdown.selected = 0
	player2_dropdown.selected = min(2, army_options.size() - 1)

	selected_player1_army = army_options[player1_dropdown.selected].id
	selected_player2_army = army_options[player2_dropdown.selected].id

	# Connect dropdown signals
	player1_dropdown.item_selected.connect(_on_player1_army_changed)
	player2_dropdown.item_selected.connect(_on_player2_army_changed)

	# Initially disable both until connection is established
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true

	print("MultiplayerLobby: Army selection initialized with ", army_options.size(), " armies")

func _format_army_name(army_id: String) -> String:
	"""Convert snake_case army ID to Title Case"""
	var parts = army_id.split("_")
	var formatted_parts = []
	for part in parts:
		formatted_parts.append(part.capitalize())
	return " ".join(formatted_parts)
```

### Phase 2: Implement Army Selection Logic

#### 2.1: Handle Host Army Selection

Add to MultiplayerLobby.gd:
```gdscript
func _on_player1_army_changed(index: int) -> void:
	if index < 0 or index >= army_options.size():
		return

	selected_player1_army = army_options[index].id
	print("MultiplayerLobby: Player 1 army changed to ", selected_player1_army)

	# If we're the host and connected, broadcast to client
	if is_hosting and connected_players >= 2:
		_sync_army_selection.rpc(1, selected_player1_army)

func _on_player2_army_changed(index: int) -> void:
	if index < 0 or index >= army_options.size():
		return

	selected_player2_army = army_options[index].id
	print("MultiplayerLobby: Player 2 army changed to ", selected_player2_army)

	# If we're the client, send request to host
	if not is_hosting and connected_players >= 2:
		_request_army_change.rpc_id(1, 2, selected_player2_army)
```

#### 2.2: Update UI for Hosting

Modify `_update_ui_for_hosting()` (line 173):
```gdscript
func _update_ui_for_hosting() -> void:
	host_button.disabled = true
	join_button.disabled = true
	port_input.editable = false
	ip_input.editable = false
	disconnect_button.disabled = false
	back_button.disabled = true

	# Enable host to select their army (Player 1)
	player1_dropdown.disabled = false
	player2_dropdown.disabled = true  # Can't pre-select opponent's army
```

#### 2.3: Update UI for Joining

Modify `_update_ui_for_joining()` (line 181):
```gdscript
func _update_ui_for_joining() -> void:
	host_button.disabled = true
	join_button.disabled = true
	port_input.editable = false
	ip_input.editable = false
	disconnect_button.disabled = false
	back_button.disabled = true

	# Disable both until we receive host's state
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true
```

#### 2.4: Enable Client Army Selection on Connection

Modify `_on_peer_connected()` (line 135):
```gdscript
func _on_peer_connected(peer_id: int) -> void:
	print("MultiplayerLobby: Peer connected - ", peer_id)
	connected_players += 1

	if is_hosting:
		status_label.text = "Status: Player 2 connected!"
		info_label.text = "Ready to start game"
		player_list_label.text = "Connected Players: 2/2"
		start_game_button.disabled = false

		# Send current army selections to client
		_sync_army_selection.rpc(1, selected_player1_army)
		_sync_army_selection.rpc(2, selected_player2_army)
	else:
		status_label.text = "Status: Connected to host"
		info_label.text = "Select your army and wait for host to start"
		player_list_label.text = "Connected Players: 2/2 (You are Player 2)"

		# Enable client to select their army (Player 2)
		player2_dropdown.disabled = false
```

### Phase 3: Implement Network Synchronization

Add RPC functions to MultiplayerLobby.gd:

```gdscript
# ============================================================================
# NETWORK - ARMY SYNCHRONIZATION
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _sync_army_selection(player: int, army_id: String) -> void:
	"""
	Called by host to synchronize army selection to client.
	Updates the UI to reflect the current army selections.
	"""
	print("MultiplayerLobby: Syncing army selection - Player ", player, " -> ", army_id)

	# Find army index
	var army_index = -1
	for i in range(army_options.size()):
		if army_options[i].id == army_id:
			army_index = i
			break

	if army_index == -1:
		print("MultiplayerLobby: Warning - Unknown army ID: ", army_id)
		return

	# Update selection
	if player == 1:
		selected_player1_army = army_id
		player1_dropdown.selected = army_index
	elif player == 2:
		selected_player2_army = army_id
		player2_dropdown.selected = army_index

@rpc("any_peer", "call_remote", "reliable")
func _request_army_change(player: int, army_id: String) -> void:
	"""
	Called by client to request army change.
	Host validates and broadcasts the change.
	"""
	if not is_hosting:
		print("MultiplayerLobby: Ignoring army change request (not host)")
		return

	var peer_id = multiplayer.get_remote_sender_id()
	print("MultiplayerLobby: Received army change request from peer ", peer_id, " for player ", player, " -> ", army_id)

	# Validate: Only allow peer to change their own army (peer 2 = player 2)
	var peer_player = 2 if peer_id != 1 else 1
	if player != peer_player:
		print("MultiplayerLobby: Rejecting army change - peer ", peer_id, " cannot change player ", player)
		return

	# Validate army exists
	var army_exists = false
	for option in army_options:
		if option.id == army_id:
			army_exists = true
			break

	if not army_exists:
		print("MultiplayerLobby: Rejecting army change - invalid army ID: ", army_id)
		return

	# Apply change locally (host)
	if player == 2:
		selected_player2_army = army_id
		var army_index = -1
		for i in range(army_options.size()):
			if army_options[i].id == army_id:
				army_index = i
				break
		player2_dropdown.selected = army_index

	# Broadcast to all peers (including requester for confirmation)
	_sync_army_selection.rpc(player, army_id)
	print("MultiplayerLobby: Army change applied and synced")
```

### Phase 4: Load Armies Before Game Start

Modify `_on_start_game_button_pressed()` (line 95):

```gdscript
func _on_start_game_button_pressed() -> void:
	print("MultiplayerLobby: Start game button pressed")

	if not is_hosting:
		_show_error("Only the host can start the game")
		return

	if connected_players < 2:
		_show_error("Waiting for player 2 to connect")
		return

	# NEW: Load armies before starting game
	print("MultiplayerLobby: Loading armies...")

	# Initialize GameState if needed
	if GameState.state.is_empty():
		GameState.initialize_default_state()

	# Clear existing units
	GameState.state.units.clear()

	# Load Player 1 army (host)
	print("MultiplayerLobby: Loading ", selected_player1_army, " for Player 1")
	var player1_army = ArmyListManager.load_army_list(selected_player1_army, 1)
	if player1_army.is_empty():
		_show_error("Failed to load Player 1 army: " + selected_player1_army)
		return
	ArmyListManager.apply_army_to_game_state(player1_army, 1)

	# Load Player 2 army (client)
	print("MultiplayerLobby: Loading ", selected_player2_army, " for Player 2")
	var player2_army = ArmyListManager.load_army_list(selected_player2_army, 2)
	if player2_army.is_empty():
		_show_error("Failed to load Player 2 army: " + selected_player2_army)
		return
	ArmyListManager.apply_army_to_game_state(player2_army, 2)

	# Store army config in GameState metadata
	if not GameState.state.has("meta"):
		GameState.state["meta"] = {}

	GameState.state.meta["game_config"] = {
		"player1_army": selected_player1_army,
		"player2_army": selected_player2_army,
		"from_multiplayer_lobby": true
	}

	print("MultiplayerLobby: Armies loaded. Total units: ", GameState.state.units.size())

	# Trigger game start via NetworkManager RPC
	var network_manager = get_node("/root/NetworkManager")
	network_manager.start_multiplayer_game.rpc()

	print("MultiplayerLobby: Game start RPC sent to all peers")
```

### Phase 5: Update NetworkManager Initial State Sync

**File**: `40k/autoloads/NetworkManager.gd`

Modify `_on_peer_connected()` (line 310) to ensure army config is included:

```gdscript
func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected - ", peer_id)

	if is_host():
		# Assign player 2 to new peer
		peer_to_player_map[peer_id] = 2

		# Send full game state to joining client
		# This will include any armies already loaded in GameState
		var snapshot = game_state.create_snapshot()
		print("NetworkManager: Sending state snapshot with ", snapshot.get("units", {}).size(), " units")
		_send_initial_state.rpc_id(peer_id, snapshot)

		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")
	else:
		# Client successfully connected to host
		print("NetworkManager: Successfully connected to host")
		emit_signal("peer_connected", peer_id)
		emit_signal("game_started")
```

**Note**: No modification needed - current implementation already sends full snapshot including units.

### Phase 6: Update Reset UI

Modify `_reset_ui()` (line 189):
```gdscript
func _reset_ui() -> void:
	host_button.disabled = false
	join_button.disabled = false
	port_input.editable = true
	ip_input.editable = true
	start_game_button.disabled = true
	disconnect_button.disabled = true
	back_button.disabled = false
	is_hosting = false
	connected_players = 0

	# Reset army selection
	player1_dropdown.disabled = true
	player2_dropdown.disabled = true
	player1_dropdown.selected = 0
	player2_dropdown.selected = min(2, army_options.size() - 1)
	selected_player1_army = army_options[0].id if not army_options.is_empty() else "adeptus_custodes"
	selected_player2_army = army_options[min(2, army_options.size() - 1)].id if not army_options.is_empty() else "orks"
```

---

## Testing Strategy

### Manual Testing Checklist

#### Test Case 1: Host Army Selection
```
1. Launch game
2. Navigate to Multiplayer Lobby
3. Click "Host Game"
4. Verify Player 1 dropdown is enabled
5. Select different armies in Player 1 dropdown
6. Verify selection updates locally
7. Verify no errors in console
```

#### Test Case 2: Client Army Selection
```
1. Host creates game (on machine A)
2. Client joins game (on machine B)
3. Verify Client sees host's Player 1 army selection
4. Verify Client's Player 2 dropdown becomes enabled
5. Client changes Player 2 army
6. Verify selection updates on both machines
7. Verify no errors in console
```

#### Test Case 3: Army Synchronization
```
1. Host selects "Space Marines" for Player 1
2. Client connects
3. Verify client sees "Space Marines" selected for Player 1
4. Client selects "Adeptus Custodes" for Player 2
5. Verify host sees "Adeptus Custodes" selected for Player 2
6. Host starts game
7. Verify both players load with correct armies
```

#### Test Case 4: Army Loading
```
1. Complete Test Case 3 setup
2. Host clicks "Start Game"
3. Verify console shows "Loading [army] for Player X"
4. Verify no "Failed to load" errors
5. Verify game transitions to Main.tscn
6. Verify units from both armies are present in game
7. Check GameState.state.units to confirm proper loading
```

#### Test Case 5: Disconnect Handling
```
1. Host and client connect
2. Both select armies
3. Client disconnects before start
4. Host clicks disconnect
5. Verify UI resets to default state
6. Verify army dropdowns are disabled
7. Re-host and verify army selections reset to defaults
```

#### Test Case 6: Invalid Army Handling
```
1. Temporarily rename one army file in armies/ directory
2. Host game and try to select renamed army
3. Verify graceful error message
4. Restore army file
5. Verify system recovers
```

### Validation Commands

#### Check Army Files Exist
```bash
ls -la 40k/armies/*.json
```

#### Test Army Loading in Godot
```gdscript
# Run in Godot script console or debug scene
var armies = ArmyListManager.get_available_armies()
print("Available armies: ", armies)

var custodes = ArmyListManager.load_army_list("adeptus_custodes", 1)
print("Custodes units: ", custodes.units.size())
```

#### Network Debugging
Add to NetworkManager.gd for testing:
```gdscript
# In _send_initial_state()
print("Snapshot keys: ", snapshot.keys())
print("Snapshot units: ", snapshot.get("units", {}).size())
print("Snapshot meta: ", snapshot.get("meta", {}))
```

### Integration Tests

**Create**: `40k/tests/network/test_multiplayer_army_selection.gd`

```gdscript
extends GutTest

func test_army_options_populated():
	var lobby = preload("res://scripts/MultiplayerLobby.gd").new()
	add_child(lobby)

	# Wait for ready
	await get_tree().process_frame

	# Verify army options exist
	assert_gt(lobby.army_options.size(), 0, "Should have army options")
	assert_true(lobby.army_options[0].has("id"), "Army option should have id")
	assert_true(lobby.army_options[0].has("name"), "Army option should have name")

func test_army_sync_rpc():
	var lobby = preload("res://scripts/MultiplayerLobby.gd").new()
	add_child(lobby)

	# Simulate army sync
	lobby._sync_army_selection(1, "space_marines")

	assert_eq(lobby.selected_player1_army, "space_marines", "Player 1 army should update")

func test_army_loading_integration():
	GameState.initialize_default_state()
	GameState.state.units.clear()

	# Load armies
	var p1_army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	ArmyListManager.apply_army_to_game_state(p1_army, 1)

	var p2_army = ArmyListManager.load_army_list("orks", 2)
	ArmyListManager.apply_army_to_game_state(p2_army, 2)

	# Verify units loaded
	assert_gt(GameState.state.units.size(), 0, "Should have units")

	# Verify both players have units
	var p1_units = 0
	var p2_units = 0
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		if unit.owner == 1:
			p1_units += 1
		elif unit.owner == 2:
			p2_units += 1

	assert_gt(p1_units, 0, "Player 1 should have units")
	assert_gt(p2_units, 0, "Player 2 should have units")
```

Run tests:
```bash
# From project root
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gprefix=test_
```

---

## Edge Cases and Error Handling

### Edge Case 1: No Army Files Found
**Scenario**: armies/ directory is empty or missing
**Handling**: Use hardcoded fallback list (already implemented in `_setup_army_selection()`)
```gdscript
if army_options.is_empty():
	army_options = [
		{"id": "adeptus_custodes", "name": "Adeptus Custodes"},
		{"id": "space_marines", "name": "Space Marines"},
		{"id": "orks", "name": "Orks"}
	]
```

### Edge Case 2: Army Load Fails During Start
**Scenario**: Selected army file is corrupted or deleted
**Handling**: Show error and prevent game start
```gdscript
if player1_army.is_empty():
	_show_error("Failed to load Player 1 army: " + selected_player1_army)
	return
```

### Edge Case 3: Client Selects Army Before Connection Completes
**Scenario**: Race condition where client clicks dropdown before peer_connected fires
**Handling**: Dropdowns are disabled until `_on_peer_connected()` enables them

### Edge Case 4: Host Disconnects After Army Selection
**Scenario**: Client selected army, host disconnects before starting
**Handling**: Existing disconnect handler already resets UI via `_on_peer_disconnected()`

### Edge Case 5: Both Players Select Same Army
**Scenario**: Both choose "Space Marines"
**Handling**: Allow it - no rule against mirror matches. Different unit IDs prevent conflicts.

### Edge Case 6: Late Joiner Receives Wrong State
**Scenario**: Client joins after armies are loaded but before game starts
**Handling**:
- If armies loaded in GameState before client joins, client receives them in initial snapshot
- If armies not yet loaded, client receives current dropdown selections via `_sync_army_selection.rpc()`

---

## Implementation Tasks (Ordered)

### Stage 1: UI Foundation
1. ✅ Modify MultiplayerLobby.tscn to add army selection UI section
2. ✅ Add dropdown references to MultiplayerLobby.gd
3. ✅ Implement `_setup_army_selection()` function
4. ✅ Implement `_format_army_name()` helper function
5. ✅ Connect dropdown signals to handlers

### Stage 2: Local Army Selection
6. ✅ Implement `_on_player1_army_changed()` handler
7. ✅ Implement `_on_player2_army_changed()` handler
8. ✅ Update `_update_ui_for_hosting()` to enable P1 dropdown
9. ✅ Update `_update_ui_for_joining()` to keep dropdowns disabled initially
10. ✅ Update `_reset_ui()` to reset army selections

### Stage 3: Network Synchronization
11. ✅ Implement `_sync_army_selection()` RPC function (host → client)
12. ✅ Implement `_request_army_change()` RPC function (client → host)
13. ✅ Update `_on_peer_connected()` to:
    - Send army selections to client (host side)
    - Enable P2 dropdown (client side)

### Stage 4: Army Loading Integration
14. ✅ Update `_on_start_game_button_pressed()` to:
    - Load P1 army via ArmyListManager
    - Load P2 army via ArmyListManager
    - Validate both armies loaded successfully
    - Store army config in GameState.meta
    - Call existing start game RPC

### Stage 5: Testing & Validation
15. ⏳ Manual test: Host army selection
16. ⏳ Manual test: Client army selection
17. ⏳ Manual test: Army synchronization
18. ⏳ Manual test: Army loading on game start
19. ⏳ Manual test: Disconnect handling
20. ⏳ Create integration test file
21. ⏳ Run GUT tests

### Stage 6: Documentation & Polish
22. ⏳ Add debug logging for all army operations
23. ⏳ Update MULTIPLAYER_LOBBY_GUIDE.md (if exists)
24. ⏳ Test with all 3 army combinations
25. ⏳ Final code review

---

## Validation Gates

All validation steps must pass before submitting implementation:

### 1. Compilation Check
```bash
# Ensure no syntax errors
godot --headless --check-only --path 40k/ res://scenes/MultiplayerLobby.tscn
```

### 2. Scene Integrity Check
```bash
# Verify scene loads without errors
godot --headless --path 40k/ -s res://scenes/MultiplayerLobby.tscn --quit
```

### 3. Script Validation
```bash
# Check MultiplayerLobby.gd for errors
godot --headless --check-only --path 40k/ res://scripts/MultiplayerLobby.gd
```

### 4. Network Test (Local)
```
Terminal 1: godot --path 40k/ res://scenes/MultiplayerLobby.tscn
  → Host game on port 7777
  → Select Space Marines for P1
  → Wait for client

Terminal 2: godot --path 40k/ res://scenes/MultiplayerLobby.tscn
  → Join localhost:7777
  → Verify P1 shows Space Marines
  → Select Orks for P2
  → Wait for host to start

Terminal 1:
  → Verify P2 shows Orks
  → Click Start Game
  → Verify game loads with correct armies
```

### 5. Unit Test Execution
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/network/ -gprefix=test_ -gexit
```

### 6. Army File Validation
```bash
# Verify all armies parse correctly
cd 40k/armies
for file in *.json; do
  echo "Validating $file..."
  python3 -m json.tool "$file" > /dev/null || echo "ERROR in $file"
done
```

---

## Success Criteria

Implementation is considered complete when:

1. ✅ **UI Complete**: Army selection dropdowns visible in multiplayer lobby
2. ✅ **Host Control**: Host can select Player 1 army
3. ✅ **Client Control**: Client can select Player 2 army after connecting
4. ✅ **Synchronization**: Army selections sync between host and client in real-time
5. ✅ **Loading**: Armies load correctly when host starts game
6. ✅ **State Sync**: Client receives full army state from host on connection
7. ✅ **Error Handling**: Invalid army selections show user-friendly errors
8. ✅ **Validation**: All validation gates pass
9. ✅ **Testing**: Manual tests complete successfully
10. ✅ **No Regressions**: Single-player army selection still works in MainMenu

---

## Known Limitations and Future Enhancements

### Current Limitations

1. **No Ready System**: Players cannot explicitly mark themselves as "ready"
   - **Workaround**: Host controls when game starts
   - **Future**: Add ready/not-ready status buttons

2. **No Army Preview**: Cannot see army composition before selecting
   - **Workaround**: Players know their armies from files
   - **Future**: Add tooltip/panel showing unit count and points

3. **No Custom Armies**: Only pre-defined army files supported
   - **Workaround**: Edit JSON files manually
   - **Future**: Integrate army builder UI

4. **Host Pre-Selects Client Army**: Host's P2 selection is default for client
   - **Current Behavior**: Client can override after connecting
   - **Alternative**: P2 dropdown empty until client connects

### Future Enhancements

1. **Ready Status System**
   - Add ready_player1 and ready_player2 boolean states
   - Show visual indicators (checkmarks, colors)
   - Only enable Start Game when both ready

2. **Army Preview Panel**
   - Show unit names, counts, and total points
   - Display faction name and detachment
   - Preview when hovering over dropdown options

3. **Saved Army Configurations**
   - Allow players to save favorite army+settings combos
   - Quick-load from saved configurations
   - Store in user:// directory

4. **Spectator Mode**
   - Allow 3rd player to join as observer
   - Synced view without control

5. **Reconnection Support**
   - Save lobby state for brief disconnects
   - Allow client to rejoin within timeout period

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Army files missing | Low | High | Fallback to hardcoded list |
| Network desync on army selection | Low | Medium | Use reliable RPCs, validate on host |
| Race condition on client join | Low | Medium | Disable dropdowns until connection complete |
| Large armies cause initial sync lag | Medium | Low | Current snapshot system handles this |
| Player selects corrupted army file | Low | High | Validate on load, show error, prevent start |

---

## References and Documentation

### Godot Documentation
- High-Level Multiplayer: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- RPC Documentation: https://godotengine.org/article/multiplayer-changes-godot-4-0-report-2/

### Codebase References
- **MainMenu.gd** (lines 1-199): Single-player army selection pattern
- **MultiplayerLobby.gd** (lines 1-209): Current multiplayer lobby implementation
- **NetworkManager.gd** (lines 179-187, 310-322): Initial state sync pattern
- **ArmyListManager.gd** (lines 46-181, 183-223): Army loading and application
- **GameManager.gd** (lines 92-133): Deployment action processing
- **NetworkIntegration.gd** (lines 10-80): Action routing pattern

### Existing PRPs
- **gh_issue_89_multiplayer_FINAL_v4s.md**: Multiplayer implementation architecture
- **gh_issue_80_drag-deployed-models.md**: UI interaction patterns

### Warhammer 40K Rules
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

---

## Confidence Score Justification: 9/10

**Why 9/10?**

**Strengths:**
1. ✅ Reuses proven patterns from MainMenu.gd
2. ✅ NetworkManager already has robust state sync
3. ✅ ArmyListManager is well-tested
4. ✅ Clear RPC patterns established
5. ✅ Comprehensive testing strategy
6. ✅ Good error handling design

**Risks (1 point deduction):**
1. ⚠️ Race conditions possible if client is very fast
2. ⚠️ First time integrating army loading into multiplayer flow
3. ⚠️ Network testing requires two machines/instances

**Overall Assessment:**
This is a straightforward feature that builds on well-established patterns. The main complexity is ensuring proper RPC synchronization, but the existing NetworkManager provides a solid foundation. One-pass implementation is highly likely with careful attention to the network flow.

---

## Final Implementation Checklist

- [ ] All Stage 1-4 tasks completed
- [ ] All validation gates pass
- [ ] Manual testing complete (Test Cases 1-6)
- [ ] No console errors during army selection
- [ ] No console errors during army synchronization
- [ ] No console errors during game start
- [ ] Both players see correct armies in Main.tscn
- [ ] Code reviewed for style consistency
- [ ] Debug logging added for troubleshooting
- [ ] Edge cases handled gracefully
- [ ] Documentation updated

---

**END OF PRP**
