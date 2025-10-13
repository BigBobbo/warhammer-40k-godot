# PRP: Online Multiplayer Implementation for Warhammer 40K Game
**GitHub Issue**: #89
**Feature**: Online Multiplayer Support (Two-Player Network Play)
**Confidence Level**: 8/10

## Executive Summary

Transform the current local hot-seat turn-based game into an online multiplayer experience where two players can play from separate computers. This implementation uses an **Interceptor Pattern** to wrap existing systems with minimal invasive changes, leverages Godot 4's ENetMultiplayerPeer for networking, and ensures deterministic gameplay through synchronized RNG and action-based state synchronization.

**Key Innovation**: Instead of extending autoloads or syncing full state, we intercept action execution at the PhaseManager level and synchronize validated actions with deterministic RNG seeds.

## Context and Requirements

### Current Architecture Analysis

The codebase has a robust modular architecture:

#### Core Systems (Autoloads in `40k/project.godot`):
- **GameState** (`40k/autoloads/GameState.gd`): Centralized state management
  - State stored as nested Dictionary
  - Methods: `create_snapshot()`, `load_from_snapshot()`, `set_phase()`, `set_active_player()`
  - Contains: units, board, players, phase_log, history

- **PhaseManager** (`40k/autoloads/PhaseManager.gd`): Phase orchestration
  - Instantiates phase classes dynamically
  - Methods: `transition_to_phase()`, `apply_state_changes()`, `validate_phase_action()`
  - Signals: `phase_changed`, `phase_completed`, `phase_action_taken`

- **ActionLogger** (`40k/autoloads/ActionLogger.gd`): Action tracking
  - Logs all actions with metadata (session_id, sequence, timestamp)
  - Methods: `log_action()`, `get_actions_by_phase()`, `create_replay_data()`
  - Currently used for debugging/replay, NOT for synchronization

- **TurnManager** (`40k/autoloads/TurnManager.gd`): Turn flow
  - Listens to PhaseManager signals
  - Handles player switching during deployment and scoring phases

- **TransportManager** (`40k/autoloads/TransportManager.gd`): Vehicle/transport logic
  - Embark/disembark mechanics
  - Must be network-synchronized

#### Phase System (`40k/phases/BasePhase.gd`):
All phases extend BasePhase:
```gdscript
class_name BasePhase
signal phase_completed()
signal action_taken(action: Dictionary)

func validate_action(action: Dictionary) -> Dictionary
func process_action(action: Dictionary) -> Dictionary
func execute_action(action: Dictionary) -> Dictionary
```

Example phases: MovementPhase, ShootingPhase, ChargePhase, FightPhase

#### Action Flow (Current):
```
User Input → Controller (e.g., MovementController)
    ↓
Phase.execute_action(action)
    ↓
Phase.validate_action(action)  # Returns {valid: bool, errors: []}
    ↓
Phase.process_action(action)   # Returns {success: bool, changes: []}
    ↓
PhaseManager.apply_state_changes(changes)  # Applies to GameState
    ↓
emit_signal("action_taken", action)  # Logged by ActionLogger
```

### Critical Discovery: Non-Deterministic Elements

Found via `grep -r "RandomNumberGenerator\|rng\.randomize" --include="*.gd"`:

1. **RulesEngine** (`40k/autoloads/RulesEngine.gd:11-12`):
   ```gdscript
   var rng: RandomNumberGenerator
   rng.randomize()
   ```

2. **MovementController** (`40k/scripts/MovementController.gd:1432-1433`):
   ```gdscript
   var rng = RandomNumberGenerator.new()
   rng.randomize()
   ```

3. **MovementPhase** (`40k/phases/MovementPhase.gd:433-435`):
   ```gdscript
   var rng = RandomNumberGenerator.new()
   rng.randomize()
   var advance_roll = rng.randi_range(1, 6)
   ```

**Impact**: These non-deterministic RNG calls will cause immediate desync in multiplayer. Must be replaced with deterministic seeded RNG.

### Technical Constraints

1. **Turn-Based Nature**: Advantage - no real-time sync needed
2. **Godot 4.4**: Use ENetMultiplayerPeer and @rpc annotations
3. **Existing Architecture**: Cannot break existing single-player functionality
4. **No Cloud Infrastructure**: Peer-to-peer with host authority
5. **Two Players Only**: 1v1 games (as per 40K rules)

## Implementation Approach: Interceptor Pattern with Host Authority

### Why NOT Extend Autoloads?

The junior PRP suggested `MultiplayerGameState extends GameState`, but:
- GameState is already a singleton autoload
- Godot autoloads can't be extended dynamically
- Would require massive refactoring of all references

### Selected Architecture: Interceptor + Wrapper

```
┌─────────────────────────────────────────────────────┐
│                  NetworkManager                      │
│  (New Autoload - Intercepts & Routes Actions)      │
└─────────────────────────────────────────────────────┘
                       ↓
         ┌─────────────────────────┐
         │  Action Submission      │
         │  (Client → Host)        │
         └─────────────────────────┘
                       ↓
         ┌─────────────────────────┐
         │  Host Validation         │
         │  (Phase.validate_action) │
         └─────────────────────────┘
                       ↓
         ┌─────────────────────────┐
         │  Host Processing         │
         │  (Phase.process_action)  │
         └─────────────────────────┘
                       ↓
         ┌─────────────────────────┐
         │  Broadcast Result        │
         │  (Host → All Clients)    │
         └─────────────────────────┘
                       ↓
         ┌─────────────────────────┐
         │  State Application       │
         │  (All: GameState.apply)  │
         └─────────────────────────┘
```

**Key Components**:

1. **NetworkManager** (New Autoload): Connection management, action routing, RNG authority
2. **Action Interception**: Hook into PhaseManager.execute_action via signal connections
3. **Deterministic RNG**: Seeded RNG provided by NetworkManager
4. **LobbySystem**: Connection UI, army selection, ready state
5. **Visual State Tracking**: Sync measuring tapes, selections (separate from game state)

## Core Components Design

### 1. NetworkManager (New Autoload)

**File**: `40k/autoloads/NetworkManager.gd`

```gdscript
extends Node
class_name NetworkManagerSingleton

# Networking signals
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(error: String)
signal game_started()
signal action_received(action: Dictionary)
signal action_result_received(result: Dictionary)
signal state_checksum_mismatch(local_hash: int, remote_hash: int)

# Network state
enum NetworkMode { OFFLINE, HOST, CLIENT }
var network_mode: NetworkMode = NetworkMode.OFFLINE

var peer: ENetMultiplayerPeer
var host_peer_id: int = 1
var client_peer_id: int = -1

# Game synchronization
var game_rng_seed: int = 0
var action_counter: int = 0
var pending_actions: Dictionary = {}  # action_id -> {action, timestamp}

# Deterministic RNG
var master_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# State verification
var last_state_checksum: int = 0
var checksum_interval: float = 5.0  # Verify every 5 seconds
var checksum_timer: Timer

func _ready() -> void:
    # Setup checksum verification timer
    checksum_timer = Timer.new()
    checksum_timer.wait_time = checksum_interval
    checksum_timer.timeout.connect(_verify_state_checksum)
    add_child(checksum_timer)

    # Connect to multiplayer signals
    if multiplayer:
        multiplayer.peer_connected.connect(_on_peer_connected)
        multiplayer.peer_disconnected.connect(_on_peer_disconnected)
        multiplayer.connection_failed.connect(_on_connection_failed)

# Host creates game
func create_host(port: int = 7777) -> Dictionary:
    peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, 1)  # Max 1 client (2 players total)

    if error != OK:
        return {"success": false, "error": "Failed to create server: " + str(error)}

    multiplayer.multiplayer_peer = peer
    network_mode = NetworkMode.HOST

    # Generate RNG seed for this game
    game_rng_seed = randi()
    master_rng.seed = game_rng_seed
    action_counter = 0

    print("[NetworkManager] Host created on port %d with RNG seed %d" % [port, game_rng_seed])
    return {"success": true, "port": port, "seed": game_rng_seed}

# Client joins game
func join_as_client(address: String, port: int = 7777) -> Dictionary:
    peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(address, port)

    if error != OK:
        return {"success": false, "error": "Failed to connect: " + str(error)}

    multiplayer.multiplayer_peer = peer
    network_mode = NetworkMode.CLIENT

    print("[NetworkManager] Connecting to %s:%d" % [address, port])
    return {"success": true}

# Client-side: Submit action to host for validation
func submit_action(action: Dictionary) -> void:
    if network_mode == NetworkMode.OFFLINE:
        # Offline mode: execute locally
        _execute_action_locally(action)
        return

    if network_mode == NetworkMode.HOST:
        # Host: validate and execute immediately
        _validate_and_execute_action(action, multiplayer.get_unique_id())
        return

    if network_mode == NetworkMode.CLIENT:
        # Client: send to host for validation
        var action_id = _generate_action_id()
        action["_net_id"] = action_id
        action["_net_timestamp"] = Time.get_ticks_msec()

        pending_actions[action_id] = action

        # Send to host
        rpc_id(host_peer_id, "_receive_action_for_validation", action)

        # Optional: Optimistic client-side prediction
        # _execute_action_locally(action)  # Will be corrected if host rejects

# Host-side: Receive and validate action from client
@rpc("any_peer", "call_remote", "reliable")
func _receive_action_for_validation(action: Dictionary) -> void:
    if network_mode != NetworkMode.HOST:
        push_error("[NetworkManager] Non-host received _receive_action_for_validation")
        return

    var sender_id = multiplayer.get_remote_sender_id()
    _validate_and_execute_action(action, sender_id)

# Host-side: Validate, execute, and broadcast
func _validate_and_execute_action(action: Dictionary, sender_id: int) -> void:
    print("[NetworkManager] Host validating action from peer %d: %s" % [sender_id, action.get("type", "UNKNOWN")])

    # Security: Verify sender is the active player
    var expected_player = GameState.get_active_player()
    var sender_player = _get_player_from_peer_id(sender_id)

    if sender_player != expected_player:
        var error_msg = "Action rejected: Not your turn (expected P%d, got P%d)" % [expected_player, sender_player]
        print("[NetworkManager] %s" % error_msg)
        rpc_id(sender_id, "_receive_action_result", {
            "success": false,
            "error": error_msg,
            "action_id": action.get("_net_id", "")
        })
        return

    # Inject deterministic RNG for this action
    _prepare_rng_for_action(action)

    # Execute action through PhaseManager
    var result = PhaseManager.get_current_phase_instance().execute_action(action)

    # Broadcast result to all clients
    var response = {
        "success": result.get("success", false),
        "action_id": action.get("_net_id", ""),
        "action": action,
        "result": result
    }

    if not result.get("success", false):
        response["error"] = result.get("error", "Unknown error")

    # Send to all peers (including sender)
    rpc("_receive_action_result", response)

    # Also apply locally on host
    _receive_action_result(response)

# All peers: Receive validated action result
@rpc("authority", "call_remote", "reliable")
func _receive_action_result(response: Dictionary) -> void:
    print("[NetworkManager] Received action result: %s" % str(response))

    var action_id = response.get("action_id", "")

    # Remove from pending
    if pending_actions.has(action_id):
        pending_actions.erase(action_id)

    if not response.get("success", false):
        print("[NetworkManager] Action failed: %s" % response.get("error", "Unknown"))
        # TODO: Rollback optimistic prediction if implemented
        return

    # If client predicted optimistically, verify result matches
    # For now, trust host and apply
    emit_signal("action_result_received", response)

# Execute action locally (offline mode or prediction)
func _execute_action_locally(action: Dictionary) -> void:
    if not PhaseManager.get_current_phase_instance():
        push_error("[NetworkManager] No active phase instance")
        return

    PhaseManager.get_current_phase_instance().execute_action(action)

# Deterministic RNG management
func _prepare_rng_for_action(action: Dictionary) -> void:
    # Derive action-specific seed from master seed + counter
    var action_seed = hash(game_rng_seed + action_counter)
    action_counter += 1

    # Create RNG for this action
    var action_rng = RandomNumberGenerator.new()
    action_rng.seed = action_seed

    # Store in action metadata so phases can access it
    action["_net_rng"] = action_rng

    print("[NetworkManager] Generated RNG for action %d with seed %d" % [action_counter - 1, action_seed])

# Public API: Get deterministic RNG for current action
func get_action_rng() -> RandomNumberGenerator:
    # This should be called by phases during action processing
    # The RNG was attached to the action in _prepare_rng_for_action
    # For now, return master RNG (phases need to be updated to use action["_net_rng"])
    return master_rng

# Initialization after both players connected
func initialize_game(seed: int) -> void:
    game_rng_seed = seed
    master_rng.seed = seed
    action_counter = 0

    if network_mode == NetworkMode.HOST:
        # Send seed to client
        rpc("_receive_game_initialization", seed)

    # Start state verification
    checksum_timer.start()

    emit_signal("game_started")
    print("[NetworkManager] Game initialized with seed %d" % seed)

@rpc("authority", "call_remote", "reliable")
func _receive_game_initialization(seed: int) -> void:
    game_rng_seed = seed
    master_rng.seed = seed
    action_counter = 0

    checksum_timer.start()

    emit_signal("game_started")
    print("[NetworkManager] Received game initialization with seed %d" % seed)

# State verification
func _verify_state_checksum() -> void:
    if network_mode == NetworkMode.OFFLINE:
        return

    var current_checksum = _calculate_state_checksum()

    if network_mode == NetworkMode.HOST:
        # Host sends checksum to client
        rpc("_receive_state_checksum", current_checksum)
    elif network_mode == NetworkMode.CLIENT:
        # Client compares with last received
        if last_state_checksum != 0 and current_checksum != last_state_checksum:
            print("[NetworkManager] STATE DESYNC DETECTED! Local: %d, Expected: %d" % [current_checksum, last_state_checksum])
            emit_signal("state_checksum_mismatch", current_checksum, last_state_checksum)
            # TODO: Request full state resync from host

@rpc("authority", "call_remote", "reliable")
func _receive_state_checksum(checksum: int) -> void:
    last_state_checksum = checksum

    # Verify against our local state
    var local_checksum = _calculate_state_checksum()
    if local_checksum != checksum:
        print("[NetworkManager] STATE DESYNC! Local: %d, Host: %d" % [local_checksum, checksum])
        emit_signal("state_checksum_mismatch", local_checksum, checksum)
        # TODO: Request state resync

func _calculate_state_checksum() -> int:
    # Hash critical game state for verification
    var state = GameState.create_snapshot()

    # Include only deterministic state (exclude timestamps, etc.)
    var critical_state = {
        "turn": state.meta.turn_number,
        "phase": state.meta.phase,
        "active_player": state.meta.active_player,
        "battle_round": state.meta.get("battle_round", 1),
        "units": _hash_units(state.units),
        "players": state.players
    }

    return hash(JSON.stringify(critical_state))

func _hash_units(units: Dictionary) -> Dictionary:
    var hashed = {}
    for unit_id in units:
        var unit = units[unit_id]
        # Hash only critical unit data (positions, wounds, flags)
        hashed[unit_id] = {
            "owner": unit.owner,
            "status": unit.status,
            "models": _hash_models(unit.models),
            "flags": unit.get("flags", {})
        }
    return hashed

func _hash_models(models: Array) -> Array:
    var hashed = []
    for model in models:
        hashed.append({
            "id": model.id,
            "alive": model.alive,
            "current_wounds": model.current_wounds,
            "position": model.position
        })
    return hashed

# Utility methods
func _get_player_from_peer_id(peer_id: int) -> int:
    # Map peer ID to player number
    # Host is always Player 1, first client is Player 2
    if network_mode == NetworkMode.HOST:
        if peer_id == 1:  # multiplayer.get_unique_id() for host
            return 1
        else:
            return 2
    else:
        # From client perspective
        if peer_id == multiplayer.get_unique_id():
            return 2
        else:
            return 1

func _generate_action_id() -> String:
    return "%d_%d" % [multiplayer.get_unique_id(), Time.get_ticks_msec()]

func is_networked() -> bool:
    return network_mode != NetworkMode.OFFLINE

func is_host() -> bool:
    return network_mode == NetworkMode.HOST

func is_client() -> bool:
    return network_mode == NetworkMode.CLIENT

# Disconnect handling
func disconnect_from_game() -> void:
    if peer:
        peer.close()
        multiplayer.multiplayer_peer = null

    network_mode = NetworkMode.OFFLINE
    checksum_timer.stop()

    print("[NetworkManager] Disconnected from game")

# Signal handlers
func _on_peer_connected(id: int) -> void:
    print("[NetworkManager] Peer connected: %d" % id)
    client_peer_id = id
    emit_signal("peer_connected", id)

func _on_peer_disconnected(id: int) -> void:
    print("[NetworkManager] Peer disconnected: %d" % id)
    emit_signal("peer_disconnected", id)

    # TODO: Pause game and show reconnection dialog

func _on_connection_failed() -> void:
    print("[NetworkManager] Connection failed")
    emit_signal("connection_failed", "Connection to host failed")
    network_mode = NetworkMode.OFFLINE
```

**Key Features**:
- Non-invasive: Doesn't modify existing autoloads
- Host authority: All actions validated by host
- Deterministic RNG: Seeded RNG for each action
- State verification: Periodic checksum validation
- Handles offline mode seamlessly

### 2. Deterministic RNG Integration

**Problem**: Current code uses `rng.randomize()` which will cause desyncs.

**Solution**: Replace with `NetworkManager.get_action_rng()` or use RNG from action metadata.

#### File: `40k/autoloads/RulesEngine.gd` (Modify)

**Before** (line 11-12):
```gdscript
var rng: RandomNumberGenerator
rng = RandomNumberGenerator.new()
rng.randomize()
```

**After**:
```gdscript
var rng: RandomNumberGenerator

func _ready():
    # Use NetworkManager's RNG if networked, otherwise local
    if NetworkManager and NetworkManager.is_networked():
        rng = NetworkManager.master_rng
    else:
        rng = RandomNumberGenerator.new()
        rng.randomize()
```

#### File: `40k/phases/MovementPhase.gd` (Modify)

**Before** (line 433-435):
```gdscript
var rng = RandomNumberGenerator.new()
rng.randomize()
var advance_roll = rng.randi_range(1, 6)
```

**After**:
```gdscript
# Check if action has networked RNG attached
var rng: RandomNumberGenerator
if action.has("_net_rng"):
    rng = action["_net_rng"]
else:
    # Fallback for offline mode
    rng = RandomNumberGenerator.new()
    rng.randomize()

var advance_roll = rng.randi_range(1, 6)
```

**Repeat this pattern for**:
- `40k/scripts/MovementController.gd` (line 1432-1433)
- Any other places where `rng.randomize()` is called (search entire codebase)

### 3. Lobby System

**File**: `40k/scenes/LobbyScene.tscn` + `40k/scripts/LobbyUI.gd`

The lobby handles:
1. Host/Join decision
2. Connection setup
3. Army selection sync
4. Player ready state
5. Game initialization

```gdscript
# 40k/scripts/LobbyUI.gd
extends Control

@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var address_input: LineEdit = $VBox/AddressInput
@onready var port_input: LineEdit = $VBox/PortInput
@onready var status_label: Label = $VBox/StatusLabel
@onready var army_selector: OptionButton = $VBox/ArmySelector
@onready var ready_button: Button = $VBox/ReadyButton
@onready var start_game_button: Button = $VBox/StartGameButton

var local_player_ready: bool = false
var remote_player_ready: bool = false
var remote_player_army: String = ""

func _ready() -> void:
    host_button.pressed.connect(_on_host_pressed)
    join_button.pressed.connect(_on_join_pressed)
    ready_button.pressed.connect(_on_ready_pressed)
    start_game_button.pressed.connect(_on_start_game_pressed)

    # Populate army selector
    army_selector.add_item("Space Marines")
    army_selector.add_item("Orks")
    army_selector.add_item("Adeptus Custodes")

    # Connect to NetworkManager signals
    if NetworkManager:
        NetworkManager.peer_connected.connect(_on_peer_connected)
        NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
        NetworkManager.connection_failed.connect(_on_connection_failed)

    # Hide lobby UI elements until connection established
    ready_button.visible = false
    start_game_button.visible = false

func _on_host_pressed() -> void:
    var port = int(port_input.text) if port_input.text != "" else 7777
    var result = NetworkManager.create_host(port)

    if result.success:
        status_label.text = "Hosting on port %d. Waiting for player..." % port
        host_button.disabled = true
        join_button.disabled = true
        ready_button.visible = true
    else:
        status_label.text = "Failed to host: " + result.error

func _on_join_pressed() -> void:
    var address = address_input.text if address_input.text != "" else "127.0.0.1"
    var port = int(port_input.text) if port_input.text != "" else 7777

    var result = NetworkManager.join_as_client(address, port)

    if result.success:
        status_label.text = "Connecting to %s:%d..." % [address, port]
        host_button.disabled = true
        join_button.disabled = true
    else:
        status_label.text = "Failed to connect: " + result.error

func _on_peer_connected(peer_id: int) -> void:
    status_label.text = "Player connected! Select your army and ready up."
    ready_button.visible = true

    if NetworkManager.is_host():
        start_game_button.visible = true
        start_game_button.disabled = true  # Enable when both ready

func _on_peer_disconnected(peer_id: int) -> void:
    status_label.text = "Player disconnected!"
    remote_player_ready = false
    _update_start_button()

func _on_connection_failed(error: String) -> void:
    status_label.text = "Connection failed: " + error
    host_button.disabled = false
    join_button.disabled = false

func _on_ready_pressed() -> void:
    local_player_ready = true
    ready_button.disabled = true

    var selected_army = army_selector.get_item_text(army_selector.selected)

    # Send ready state to other player
    rpc("_receive_ready_state", selected_army)

    status_label.text = "Ready! Waiting for opponent..."
    _update_start_button()

@rpc("any_peer", "call_remote", "reliable")
func _receive_ready_state(army: String) -> void:
    remote_player_ready = true
    remote_player_army = army
    status_label.text = "Opponent ready with %s!" % army
    _update_start_button()

func _update_start_button() -> void:
    if NetworkManager.is_host():
        start_game_button.disabled = not (local_player_ready and remote_player_ready)

func _on_start_game_pressed() -> void:
    if not NetworkManager.is_host():
        return

    # Initialize game with RNG seed
    var seed = randi()
    NetworkManager.initialize_game(seed)

    # Notify client to start
    rpc("_start_game")
    _start_game()

@rpc("authority", "call_remote", "reliable")
func _start_game() -> void:
    # Load armies into GameState
    var local_army = army_selector.get_item_text(army_selector.selected)

    # Clear default armies
    GameState.state.units.clear()

    # Load selected armies
    var player_num = 1 if NetworkManager.is_host() else 2
    var opponent_num = 2 if NetworkManager.is_host() else 1

    # Load local player's army
    var local_army_data = ArmyListManager.load_army_list(local_army.to_lower().replace(" ", "_"), player_num)
    if not local_army_data.is_empty():
        ArmyListManager.apply_army_to_game_state(local_army_data, player_num)

    # Load opponent's army
    var opponent_army_data = ArmyListManager.load_army_list(remote_player_army.to_lower().replace(" ", "_"), opponent_num)
    if not opponent_army_data.is_empty():
        ArmyListManager.apply_army_to_game_state(opponent_army_data, opponent_num)

    # Transition to main game
    get_tree().change_scene_to_file("res://scenes/Main.tscn")
```

### 4. Main Menu Integration

**File**: `40k/scenes/MainMenu.tscn` (Modify)

Add "Multiplayer" button alongside existing "New Game", "Load Game", "Exit" buttons.

**File**: `40k/scripts/MainMenu.gd` (Modify)

Add handler:
```gdscript
func _on_multiplayer_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/LobbyScene.tscn")
```

### 5. Visual State Synchronization

Some visual elements need synchronization but aren't part of GameState:

#### Measuring Tapes
**File**: `40k/autoloads/MeasuringTapeManager.gd` (Modify)

Add RPCs to sync tape placement:
```gdscript
# Add after existing methods
@rpc("any_peer", "call_remote", "reliable")
func _sync_tape_created(tape_id: String, start: Vector2, end: Vector2) -> void:
    # Create tape visual on remote client
    # ... implementation

func create_tape(start: Vector2, end: Vector2) -> void:
    # Existing logic...

    # If networked, sync to other player
    if NetworkManager and NetworkManager.is_networked():
        rpc("_sync_tape_created", tape_id, start, end)
```

#### Model Selection
**File**: `40k/scripts/Main.gd` or relevant controller (Modify)

Sync which unit is selected (for UI feedback):
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func _sync_unit_selected(unit_id: String) -> void:
    # Update UI to show opponent has selected this unit
    # ... visual feedback only, not game state
```

## Implementation Blueprint

### File Structure

**New Files**:
```
40k/
  autoloads/
    NetworkManager.gd                 # Core networking (detailed above)
  scripts/
    LobbyUI.gd                       # Lobby interface (detailed above)
  scenes/
    LobbyScene.tscn                  # Lobby UI scene
  tests/
    unit/
      test_network_manager.gd        # NetworkManager unit tests
      test_deterministic_rng.gd      # RNG determinism tests
    integration/
      test_multiplayer_sync.gd       # Multi-instance integration tests
      test_action_synchronization.gd # Action sync verification
```

**Modified Files**:
```
40k/
  project.godot                      # Add NetworkManager autoload
  autoloads/
    RulesEngine.gd                   # Use NetworkManager RNG
  phases/
    MovementPhase.gd                 # Use action["_net_rng"]
    ShootingPhase.gd                 # Use action["_net_rng"] (if has RNG)
    ChargePhase.gd                   # Use action["_net_rng"] (if has RNG)
    FightPhase.gd                    # Use action["_net_rng"] (if has RNG)
  scripts/
    MovementController.gd            # Use NetworkManager RNG
    Main.gd                          # Detect network mode, add status UI
    MainMenu.gd                      # Add multiplayer option
  scenes/
    Main.tscn                        # Add network status indicators
    MainMenu.tscn                    # Add multiplayer button
```

### Implementation Steps (Ordered)

#### Phase 1: Core Infrastructure (Days 1-2)
1. ✅ Create `NetworkManager.gd` skeleton with connection methods
2. ✅ Add NetworkManager to `project.godot` autoloads
3. ✅ Implement `create_host()` and `join_as_client()`
4. ✅ Test basic peer connection (two game instances)
5. ✅ Implement peer connected/disconnected signals

#### Phase 2: Lobby System (Days 3-4)
6. ✅ Create `LobbyScene.tscn` with UI elements
7. ✅ Implement `LobbyUI.gd` with host/join logic
8. ✅ Add army selection synchronization
9. ✅ Implement ready state tracking
10. ✅ Add "Start Game" flow (host initializes RNG seed)

#### Phase 3: Action Synchronization (Days 5-7)
11. ✅ Implement `submit_action()` in NetworkManager
12. ✅ Implement `_receive_action_for_validation()` RPC (host-side)
13. ✅ Implement `_validate_and_execute_action()` (host authority)
14. ✅ Implement `_receive_action_result()` RPC (all peers)
15. ✅ Test action flow: client submit → host validate → broadcast result

#### Phase 4: Deterministic RNG (Days 8-9)
16. ✅ Implement `_prepare_rng_for_action()` in NetworkManager
17. ✅ Modify `RulesEngine.gd` to use NetworkManager RNG
18. ✅ Modify `MovementPhase.gd` to use `action["_net_rng"]`
19. ✅ Find and fix all `rng.randomize()` calls in codebase
20. ✅ Test determinism: same seed + actions = same outcome

#### Phase 5: State Verification (Days 10-11)
21. ✅ Implement `_calculate_state_checksum()`
22. ✅ Implement periodic checksum verification
23. ✅ Add desync detection and warning UI
24. ✅ Test deliberate desync detection

#### Phase 6: Integration & UI (Days 12-14)
25. ✅ Add "Multiplayer" button to MainMenu
26. ✅ Add network status indicators to Main.gd HUD
27. ✅ Sync measuring tape placement (optional but nice)
28. ✅ Sync model selection visual feedback (optional)
29. ✅ Test full game flow: lobby → game → completion

#### Phase 7: Testing & Polish (Days 15-17)
30. ✅ Write unit tests for NetworkManager methods
31. ✅ Write integration tests (multi-instance)
32. ✅ Test disconnection handling
33. ✅ Test various network conditions (LAN)
34. ✅ Performance profiling and optimization

#### Phase 8: Documentation (Day 18)
35. ✅ Document multiplayer setup for players (port forwarding)
36. ✅ Document known limitations (NAT, 2 players only)
37. ✅ Update README with multiplayer instructions

## Validation Gates

### Syntax Validation
```bash
# Godot has no built-in linter, but we can check for errors
export PATH="$HOME/bin:$PATH"

# Check syntax by loading project headless
godot --headless --quit-after 1 2>&1 | grep -i error
```

### Unit Tests
```bash
# Run GUT tests for NetworkManager
export PATH="$HOME/bin:$PATH"

godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_network_manager.gd \
  -gexit

godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_deterministic_rng.gd \
  -gexit
```

### Integration Tests (Multi-Instance)
```bash
# Test requires two instances
# Terminal 1: Host
export PATH="$HOME/bin:$PATH"
godot --headless -s res://tests/integration/test_multiplayer_host.gd &

# Terminal 2: Client
export PATH="$HOME/bin:$PATH"
godot --headless -s res://tests/integration/test_multiplayer_client.gd

# Wait for both to complete, check exit codes
```

### Manual Testing Checklist
```markdown
## Connection Testing
- [ ] Host can create lobby on default port (7777)
- [ ] Client can join via 127.0.0.1:7777
- [ ] Both players see "Connected" status
- [ ] Disconnect shows error and returns to lobby

## Army Selection
- [ ] Host selects Space Marines → Client sees it
- [ ] Client selects Orks → Host sees it
- [ ] Ready button enables after selection
- [ ] Start Game only available to host

## Game Synchronization
- [ ] Both players start in Deployment phase
- [ ] Player 1 deploys unit → Player 2 sees it
- [ ] Turn switching works correctly
- [ ] Movement phase: advance roll shows same value for both
- [ ] Shooting phase: dice rolls match on both sides

## State Verification
- [ ] No desync warnings during normal play
- [ ] Deliberate state modification triggers desync warning
- [ ] Checksum verification runs every 5 seconds

## Disconnection Handling
- [ ] Client disconnect shows "Player disconnected"
- [ ] Host disconnect returns client to menu
- [ ] Reconnection window appears (if implemented)

## Performance
- [ ] No noticeable lag in turn-based actions
- [ ] Network traffic reasonable (<1 MB/minute)
- [ ] CPU usage acceptable (<50% single core)
```

## Documentation References

### Official Godot 4 Documentation

**High-Level Multiplayer**:
- URL: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- Key sections:
  - Managing connections
  - Remote procedure calls (@rpc annotations)
  - Server/client architecture

**ENetMultiplayerPeer**:
- URL: https://docs.godotengine.org/en/4.4/classes/class_enetmultiplayerpeer.html
- Methods: `create_server()`, `create_client()`, `close()`

**MultiplayerAPI**:
- URL: https://docs.godotengine.org/en/stable/classes/class_multiplayerapi.html
- Properties: `multiplayer_peer`, `get_unique_id()`, `get_remote_sender_id()`

### Community Resources

**Godot 4 Multiplayer Changes**:
- URL: https://godotengine.org/article/multiplayer-changes-godot-4-0-report-2/
- RPC syntax: `@rpc("any_peer", "call_remote", "reliable")`
- Channels and ordering

**Turn-Based Multiplayer Strategies**:
- URL: https://forum.godotengine.org/t/turn-based-multiplayer-strategies/61636
- Discusses simplified approach for turn-based games
- Server authority patterns

**Godot 4 Multiplayer Overview (GitHub Gist)**:
- URL: https://gist.github.com/Meshiest/1274c6e2e68960a409698cf75326d4f6
- Comprehensive overview with code examples

### Codebase Reference Files

**Study These Before Implementation**:
```
40k/autoloads/GameState.gd       # State management (lines 1-394)
40k/autoloads/PhaseManager.gd    # Phase orchestration (lines 1-283)
40k/autoloads/ActionLogger.gd    # Action tracking (lines 1-335)
40k/autoloads/TurnManager.gd     # Turn flow (lines 1-192)
40k/phases/BasePhase.gd          # Phase base class (lines 1-169)
40k/phases/MovementPhase.gd      # Example phase (lines 1-1851)
40k/autoloads/SaveLoadManager.gd # State serialization (lines 1-530)
40k/scripts/Main.gd              # Main game loop (lines 1-200+)
```

**RNG Locations to Fix**:
```
40k/autoloads/RulesEngine.gd:11-12        # rng.randomize()
40k/scripts/MovementController.gd:1432   # rng.randomize()
40k/phases/MovementPhase.gd:433          # rng.randomize()
```

## Error Handling Strategy

### Connection Errors

```gdscript
# In NetworkManager.gd
func _on_connection_failed() -> void:
    print("[NetworkManager] Connection failed")
    emit_signal("connection_failed", "Connection to host failed")
    network_mode = NetworkMode.OFFLINE

    # Show error dialog
    _show_error_dialog("Connection Failed",
        "Could not connect to host. Please check:\n" +
        "- Host IP address is correct\n" +
        "- Host has port forwarded (if not on LAN)\n" +
        "- Host is still running")
```

### Disconnection During Game

```gdscript
# In NetworkManager.gd
func _on_peer_disconnected(id: int) -> void:
    print("[NetworkManager] Peer disconnected: %d" % id)
    emit_signal("peer_disconnected", id)

    # Pause game
    get_tree().paused = true

    # Show reconnection dialog
    _show_reconnection_dialog()

    # Start 60-second reconnection timer
    var timer = Timer.new()
    timer.wait_time = 60.0
    timer.one_shot = true
    timer.timeout.connect(_on_reconnection_timeout)
    add_child(timer)
    timer.start()

func _on_reconnection_timeout() -> void:
    # Return to menu after timeout
    get_tree().paused = false
    get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
```

### Desync Handling

```gdscript
# In NetworkManager.gd
func _on_desync_detected(local: int, remote: int) -> void:
    print("[NetworkManager] DESYNC: Local=%d, Remote=%d" % [local, remote])

    if network_mode == NetworkMode.CLIENT:
        # Request full state resync from host
        rpc_id(host_peer_id, "_request_state_resync")
    elif network_mode == NetworkMode.HOST:
        # Send full state to client
        var state = GameState.create_snapshot()
        rpc_id(client_peer_id, "_receive_state_resync", state)

@rpc("any_peer", "call_remote", "reliable")
func _request_state_resync() -> void:
    var state = GameState.create_snapshot()
    var sender = multiplayer.get_remote_sender_id()
    rpc_id(sender, "_receive_state_resync", state)

@rpc("authority", "call_remote", "reliable")
func _receive_state_resync(state: Dictionary) -> void:
    print("[NetworkManager] Receiving state resync from host")
    GameState.load_from_snapshot(state)

    # Refresh visuals
    # TODO: Emit signal for UI to refresh
```

### Action Validation Failures

```gdscript
# In NetworkManager._validate_and_execute_action()
if not validation.valid:
    var error_msg = "Action invalid: " + ", ".join(validation.errors)
    print("[NetworkManager] %s" % error_msg)

    # Send rejection to client with reason
    rpc_id(sender_id, "_receive_action_rejection", {
        "action_id": action.get("_net_id", ""),
        "errors": validation.errors,
        "current_state_checksum": _calculate_state_checksum()
    })
    return

# Client receives rejection
@rpc("authority", "call_remote", "reliable")
func _receive_action_rejection(rejection: Dictionary) -> void:
    print("[NetworkManager] Action rejected: %s" % str(rejection.errors))

    # Show error to player
    _show_error_dialog("Action Rejected",
        "Your action was invalid:\n" + "\n".join(rejection.errors))

    # Verify state matches host
    var local_checksum = _calculate_state_checksum()
    if local_checksum != rejection.current_state_checksum:
        print("[NetworkManager] State mismatch after rejection, requesting resync")
        rpc_id(host_peer_id, "_request_state_resync")
```

## Security Considerations

### Input Validation

```gdscript
# In NetworkManager._validate_and_execute_action()
func _validate_rpc_input(action: Dictionary) -> Dictionary:
    # Validate action structure
    if not action.has("type"):
        return {"valid": false, "error": "Missing action type"}

    if not action.type is String:
        return {"valid": false, "error": "Invalid action type"}

    # Sanitize strings
    if action.has("unit_id"):
        if not action.unit_id is String or action.unit_id.length() > 50:
            return {"valid": false, "error": "Invalid unit_id"}

    # Validate positions are reasonable (on board)
    if action.has("payload") and action.payload.has("dest"):
        var dest = action.payload.dest
        if dest is Array and dest.size() == 2:
            var x = dest[0]
            var y = dest[1]

            # Board is 44x60 inches, at 25.4 px/inch = ~1117x1524 px
            if x < 0 or x > 2000 or y < 0 or y > 2000:
                return {"valid": false, "error": "Position out of bounds"}

    return {"valid": true}
```

### Turn Order Enforcement

```gdscript
# In NetworkManager._validate_and_execute_action()
var expected_player = GameState.get_active_player()
var sender_player = _get_player_from_peer_id(sender_id)

if sender_player != expected_player:
    return {
        "success": false,
        "error": "Not your turn (expected P%d, got P%d)" % [expected_player, sender_player]
    }
```

### Rate Limiting

```gdscript
# In NetworkManager
var action_timestamps: Dictionary = {}  # peer_id -> [timestamps]
const MAX_ACTIONS_PER_SECOND: int = 10

func _check_rate_limit(peer_id: int) -> bool:
    var current_time = Time.get_ticks_msec()

    if not action_timestamps.has(peer_id):
        action_timestamps[peer_id] = []

    var timestamps = action_timestamps[peer_id]

    # Remove timestamps older than 1 second
    timestamps = timestamps.filter(func(t): return current_time - t < 1000)

    if timestamps.size() >= MAX_ACTIONS_PER_SECOND:
        print("[NetworkManager] Rate limit exceeded for peer %d" % peer_id)
        return false

    timestamps.append(current_time)
    action_timestamps[peer_id] = timestamps
    return true

# Use in _receive_action_for_validation():
if not _check_rate_limit(sender_id):
    rpc_id(sender_id, "_receive_action_rejection", {
        "action_id": action.get("_net_id", ""),
        "errors": ["Rate limit exceeded"]
    })
    return
```

## Performance Optimizations

### Bandwidth Reduction

1. **Action Compression**: Send only changed fields
```gdscript
func _compress_action(action: Dictionary) -> Dictionary:
    # Remove metadata that can be regenerated
    var compressed = action.duplicate()
    compressed.erase("_net_timestamp")  # Can use server time
    return compressed
```

2. **State Checksum Optimization**: Hash only critical fields
```gdscript
# Only hash: turn, phase, player, unit positions/wounds/flags
# Skip: meta timestamps, history logs, cached data
```

3. **Batch Actions**: Group multiple model moves into one RPC
```gdscript
# For group movement, send array of moves in single action
{
    "type": "BATCH_MODEL_MOVES",
    "moves": [
        {"model_id": "m1", "dest": [100, 200]},
        {"model_id": "m2", "dest": [110, 210]}
    ]
}
```

### Latency Mitigation

1. **Client-Side Prediction**: Show immediate feedback
```gdscript
# In NetworkManager.submit_action()
if network_mode == NetworkMode.CLIENT:
    # Send to host
    rpc_id(host_peer_id, "_receive_action_for_validation", action)

    # Optimistically execute locally (will be corrected if host rejects)
    _execute_action_locally(action)
```

2. **Action Queuing**: Process multiple actions per frame
```gdscript
var action_queue: Array = []

func _process(delta: float) -> void:
    # Process up to 5 queued actions per frame
    for i in range(min(5, action_queue.size())):
        var action = action_queue.pop_front()
        _process_queued_action(action)
```

## Known Limitations

### 1. NAT Traversal
**Issue**: Players behind NAT/firewalls need port forwarding.
**Workaround**: Document port forwarding instructions for players.
**Future**: Implement STUN/TURN servers for automatic NAT traversal.

### 2. Two Players Only
**Issue**: Architecture designed for 1v1 games only.
**Why**: Warhammer 40K is a 2-player game.
**Future**: Spectator mode possible with minor modifications.

### 3. No Dedicated Server
**Issue**: One player must host (has zero latency advantage).
**Future**: Headless dedicated server for tournaments.

### 4. No Reconnection (MVP)
**Issue**: Disconnection ends the game.
**Future**: Save game state on disconnect, allow reconnection with state reload.

### 5. Platform Limitations
**Issue**: Only tested on desktop (Windows/macOS/Linux).
**Web**: Not supported (ENet doesn't work in browser).
**Mobile**: Possible but untested.

## Testing Checklist

### Unit Tests (res://tests/unit/)

```gdscript
# test_network_manager.gd
extends GutTest

func test_create_host_success():
    var nm = NetworkManager.new()
    var result = nm.create_host(7777)
    assert_true(result.success, "Host creation should succeed")
    assert_eq(nm.network_mode, NetworkManager.NetworkMode.HOST)

func test_rng_determinism():
    var nm = NetworkManager.new()
    nm.game_rng_seed = 12345
    nm.action_counter = 0

    var rng1 = nm.get_action_rng()
    nm.action_counter = 0  # Reset
    var rng2 = nm.get_action_rng()

    var roll1 = rng1.randi_range(1, 6)
    var roll2 = rng2.randi_range(1, 6)

    assert_eq(roll1, roll2, "Same seed should produce same roll")

func test_state_checksum_consistency():
    # Create identical game states
    var state1 = GameState.create_snapshot()
    var state2 = state1.duplicate(true)

    var checksum1 = NetworkManager._calculate_state_checksum()
    GameState.load_from_snapshot(state2)
    var checksum2 = NetworkManager._calculate_state_checksum()

    assert_eq(checksum1, checksum2, "Identical states should have same checksum")
```

### Integration Tests (res://tests/integration/)

```gdscript
# test_multiplayer_sync.gd
extends GutTest

# This test requires running two instances
# Use helper scripts to spawn host and client

func test_action_synchronization():
    # Host creates server
    var host = await _spawn_host_instance()

    # Client connects
    var client = await _spawn_client_instance()

    # Client submits movement action
    await client.submit_movement_action("U_INTERCESSORS_A", Vector2(100, 200))

    # Wait for synchronization
    await get_tree().create_timer(0.5).timeout

    # Verify both have same state
    var host_state = host.get_game_state()
    var client_state = client.get_state()

    assert_eq(host_state.units["U_INTERCESSORS_A"].models[0].position,
              client_state.units["U_INTERCESSORS_A"].models[0].position,
              "Unit position should match after sync")

    # Cleanup
    host.disconnect_from_game()
    client.disconnect_from_game()
```

### Manual Testing Script

```bash
#!/bin/bash
# tests/manual_multiplayer_test.sh

echo "Starting manual multiplayer test..."

# Terminal 1: Start host
export PATH="$HOME/bin:$PATH"
godot --host --port 7777 &
HOST_PID=$!

sleep 2

# Terminal 2: Start client
godot --client --address 127.0.0.1 --port 7777 &
CLIENT_PID=$!

echo "Host PID: $HOST_PID"
echo "Client PID: $CLIENT_PID"
echo "Press Ctrl+C to stop both instances"

# Wait for user interrupt
trap "kill $HOST_PID $CLIENT_PID; exit" INT
wait
```

## Migration Path

### Phase 1: MVP (Week 1-2)
- Basic connection (host/join)
- Action synchronization for Movement phase only
- Deterministic RNG for advance rolls
- No reconnection support
- LAN only (127.0.0.1)

**Success Criteria**:
- Two players can connect
- Both players can deploy units
- Movement phase works with synced dice rolls
- Game completes without desyncs

### Phase 2: Full Game Support (Week 3-4)
- All phases networked (Shooting, Charge, Fight, Scoring)
- State verification with checksums
- Basic disconnection handling (pause + timeout)
- Measuring tape synchronization
- Network status UI

**Success Criteria**:
- Complete game playable from deployment to end
- Desync detection functional
- Disconnection pauses game

### Phase 3: Production Ready (Week 5-6)
- Reconnection support
- Save/load for network games
- Performance optimizations
- Comprehensive testing
- Player-facing documentation
- Error recovery

**Success Criteria**:
- Reconnection works within 60 seconds
- Can save and resume network games
- No noticeable lag
- All tests passing

## Confidence Assessment: 8/10

### Strengths (+8 points):
1. ✅ Architecture is sound (interceptor pattern, minimal changes)
2. ✅ Existing action logging system perfect for replay/verification
3. ✅ Turn-based nature simplifies networking dramatically
4. ✅ Clear RNG determinism strategy
5. ✅ Comprehensive state verification approach
6. ✅ Godot 4 ENet APIs well-documented
7. ✅ Phased implementation with clear milestones
8. ✅ Detailed code examples provided

### Risks (-2 points):
1. ⚠️ Testing multi-instance in headless mode may be tricky
2. ⚠️ Some edge cases in action validation may be discovered during implementation

### Mitigation:
- Start with LAN testing (two computers, not two instances)
- Implement comprehensive logging for debugging
- Phased rollout (Movement phase first, then expand)

## Conclusion

This PRP provides a complete, implementable roadmap for adding online multiplayer to the Warhammer 40K game. The **Interceptor Pattern** approach is superior to the junior PRP's extension approach because:

1. **Non-invasive**: Wraps existing systems instead of modifying them
2. **Deterministic**: Synchronized RNG ensures replay consistency
3. **Scalable**: Easy to add features (spectators, reconnection) later
4. **Testable**: Clear separation between network layer and game logic
5. **Maintainable**: Multiplayer code isolated in NetworkManager

The implementation can begin immediately with Phase 1 (Core Infrastructure) and be incrementally built up through the 8 phases. Each phase has clear validation gates and success criteria.

---

**Next Steps**:
1. Review and approve this PRP
2. Create GitHub project board with tasks from implementation steps
3. Begin Phase 1: Core Infrastructure
4. Weekly progress reviews with demo of completed phases

**Estimated Timeline**: 6 weeks to production-ready multiplayer (3 developers) or 12 weeks (1 developer)

**Primary Reference Files**:
- Godot Docs: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- ENet API: https://docs.godotengine.org/en/4.4/classes/class_enetmultiplayerpeer.html
- Multiplayer Changes in 4.0: https://godotengine.org/article/multiplayer-changes-godot-4-0-report-2/
- Turn-Based Strategies: https://forum.godotengine.org/t/turn-based-multiplayer-strategies/61636

**Codebase Context**:
- Start with: `40k/autoloads/GameState.gd`, `40k/autoloads/PhaseManager.gd`, `40k/phases/BasePhase.gd`
- Study: `40k/phases/MovementPhase.gd` for action patterns
- Fix: All `rng.randomize()` calls found in codebase