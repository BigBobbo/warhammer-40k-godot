# PRP: Online Multiplayer Implementation for Warhammer 40K Game (PRODUCTION VERSION v4)

**GitHub Issue**: #89
**Feature**: Online Multiplayer Support (Two-Player Network Play)
**Review Score**: 8.5/10 (v3) → **7.5/10 (v4 - CRITICAL CORRECTIONS)**
**Status**: ⚠️ REQUIRES SIGNIFICANT REVISIONS BEFORE IMPLEMENTATION
**Reviewer**: Senior Architect (in-depth codebase analysis)
**Review Date**: 2025-09-29 (v4 comprehensive revision)

---

## 🚨 EXECUTIVE SUMMARY - v4 CRITICAL FINDINGS

After thorough analysis of the **actual codebase**, the v3 PRP contains **fundamental architectural misunderstandings** that would lead to implementation failure. The junior developer made assumptions about the architecture that do not match reality.

### **CRITICAL ISSUES DISCOVERED:**

#### 1. **FUNDAMENTAL MISUNDERSTANDING: GameState Architecture** 🔴
**v3 Assumption**: GameState could have a NetworkManager as a child node
**Reality**: GameState extends `Node` with `class_name GameStateData` and is an **autoload singleton**. It manages a `state: Dictionary` that represents game state. It's **NOT designed for child nodes**.

**Location**: `40k/autoloads/GameState.gd:1-14`
```gdscript
extends Node
class_name GameStateData

var state: Dictionary = {}
```

**Impact**: The entire v3 integration strategy of "adding NetworkManager as child" is **architecturally wrong**.

---

#### 2. **INCORRECT: PhaseManager Integration Assumptions** 🔴
**v3 Assumption**: PhaseManager.apply_state_changes() exists and can be used for network sync
**Reality**:
- PhaseManager.apply_state_changes() EXISTS at line 153 ✅
- BUT it operates on GameState.state Dictionary directly via _set_state_value()
- It's NOT designed for network message passing
- It expects path strings like "units.U_ID.models.m1.pos"

**Location**: `40k/autoloads/PhaseManager.gd:153-202`

**Impact**: The v3 sync mechanism needs complete redesign.

---

#### 3. **INCORRECT: Action Execution Flow** 🔴
**v3 Assumption**: Phases have execute_action() methods
**Reality**:
- GameManager.gd has `apply_action()` and `process_action()` methods (lines 8-48)
- GameManager processes actions and generates **diffs** (state changes)
- PhaseManager doesn't execute actions directly

**Location**: `40k/autoloads/GameManager.gd:8-70`

**Impact**: Network action handling must route through GameManager, not PhaseManager.

---

#### 4. **MISSING: Critical Autoload - GameManager** 🔴
**v3**: Completely ignores GameManager.gd
**Reality**: GameManager is a **core autoload** that:
- Processes all game actions via `apply_action()`
- Generates state diffs
- Applies results via `apply_result()`
- Has signals: `result_applied`, `action_logged`
- Is registered in project.godot at line 30

**Location**: `40k/project.godot:30` and `40k/autoloads/GameManager.gd`

**Impact**: NetworkManager MUST integrate with GameManager, not bypass it.

---

#### 5. **ARCHITECTURE MISMATCH: State Management** 🔴
**Current Architecture**:
```
Action → GameManager.apply_action() → process_action() →
generates diffs → apply_result() → apply_diff() →
modifies GameState.state (and legacy BoardState for compatibility)
```

**v3 Proposed Architecture**:
```
Action → NetworkManager → PhaseManager.execute_action() ❌ (doesn't exist)
```

**Correct Architecture Should Be**:
```
Action → NetworkManager.submit_action() → [if host] validate →
GameManager.apply_action() → broadcast result →
[all peers] GameManager.apply_result()
```

---

#### 6. **TEST FRAMEWORK CONFIRMED** ✅
**Verified**: Project uses **GUT** (Godot Unit Testing) framework
**Evidence**:
- `40k/project.godot:43` - `enabled=PackedStringArray("res://addons/gut/plugin.cfg")`
- `40k/tests/ui/test_mathhammer_ui.gd` - `extends GutTest`

**Impact**: v3 test strategy is correct for framework, but needs integration fixes.

---

#### 7. **NETWORK INTEGRATION POINT WRONG** 🔴
**v3 Proposal**: Add NetworkManager to GameState as child node
**Correct Approach**:
- NetworkManager should be a **standalone autoload** (like other managers)
- Register in project.godot after TransportManager (line 40)
- GameState should have a **reference** to NetworkManager (not parent-child)
- Use signals for communication between managers

---

## 📊 UPDATED REVIEW SCORES (v4)

| Category | v3 Score | v4 Score | Reason for Change |
|----------|----------|----------|-------------------|
| Architecture Understanding | 9/10 | 4/10 | Fundamental misunderstanding of GameManager role |
| Technical Accuracy | 9/10 | 5/10 | Line numbers correct but integration flow wrong |
| Implementation Feasibility | 7/10 | 5/10 | Would fail without major restructuring |
| Security | 8/10 | 8/10 | Validation approach still sound |
| Determinism | 9/10 | 9/10 | RNG fixes still correct |
| Edge Cases | 7/10 | 7/10 | Unchanged |
| Testing Strategy | 5/10 | 7/10 | GUT framework confirmed, approach valid |
| Maintainability | 7/10 | 6/10 | MVP size good, but wrong integration |
| Existing Code Integration | 6/10 | 3/10 | **CRITICAL**: Would break existing flow |

**Overall Score: 8.5/10 (v3) → 7.5/10 (v4)**

**Reason for Downgrade**: Despite good intentions and RNG analysis, the v3 PRP would **fail implementation** due to architectural misunderstandings. The junior developer didn't discover GameManager's central role in action processing.

---

## 🔧 CORRECTED ARCHITECTURE (v4)

### Actual Codebase Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      AUTOLOAD LAYER                         │
├─────────────────────────────────────────────────────────────┤
│ GameState (state: Dictionary)                               │
│  ├─ meta: {turn, phase, active_player, battle_round}       │
│  ├─ units: {unit_id: {...}}                                │
│  ├─ board: {deployment_zones, terrain, objectives}         │
│  └─ players: {1: {cp, vp}, 2: {cp, vp}}                   │
├─────────────────────────────────────────────────────────────┤
│ GameManager                                                 │
│  ├─ apply_action(action: Dict) → result: Dict             │
│  ├─ process_action(action: Dict) → result: Dict           │
│  ├─ apply_result(result: Dict) → void                     │
│  ├─ apply_diff(diff: Dict) → void                         │
│  └─ set_value_at_path(path: String, value) → void        │
├─────────────────────────────────────────────────────────────┤
│ PhaseManager                                                │
│  ├─ current_phase_instance: BasePhase                      │
│  ├─ transition_to_phase(phase: Phase)                     │
│  ├─ apply_state_changes(changes: Array) [LEGACY]          │
│  └─ signals: phase_changed, phase_completed               │
├─────────────────────────────────────────────────────────────┤
│ BoardState (LEGACY COMPATIBILITY)                          │
│  ├─ Provides deployment zone visuals                       │
│  ├─ Forwards active_player to GameState                    │
│  └─ Maintains legacy units dict for old UI components      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      PHASE LAYER                            │
├─────────────────────────────────────────────────────────────┤
│ BasePhase (base class)                                      │
│  ├─ enter_phase(snapshot: Dict)                            │
│  ├─ exit_phase()                                            │
│  ├─ validate_action(action: Dict) → Dict                   │
│  └─ signals: phase_completed, action_taken                 │
├─────────────────────────────────────────────────────────────┤
│ MovementPhase, ShootingPhase, ChargePhase, etc.           │
│  ├─ active_moves: Dictionary (phase-local state)          │
│  ├─ Generates actions for GameManager                      │
│  └─ Uses RulesEngine.RNGService (currently non-determistic)│
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    CONTROLLER LAYER                         │
├─────────────────────────────────────────────────────────────┤
│ MovementController, ShootingController, etc.               │
│  ├─ UI logic for player input                              │
│  ├─ Sends actions to phase instances                       │
│  └─ Uses RandomNumberGenerator (non-deterministic)         │
└─────────────────────────────────────────────────────────────┘
```

### CORRECTED: Network Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   NEW: NetworkManager                       │
│                   (Autoload - Standalone)                   │
├─────────────────────────────────────────────────────────────┤
│ Responsibilities:                                           │
│  ├─ Host/client setup via ENetMultiplayerPeer             │
│  ├─ Peer connection management                             │
│  ├─ Action submission and validation                       │
│  ├─ RNG seed generation (host only)                        │
│  ├─ Turn timer enforcement                                 │
│  └─ Initial state sync on client join                     │
│                                                            │
│ Integration Points:                                        │
│  ├─ GameManager.apply_action() - action execution         │
│  ├─ GameState.state - state snapshot/restore              │
│  ├─ PhaseManager - phase instance access (for validation) │
│  └─ TurnManager - active player queries                   │
│                                                            │
│ Signal Flow:                                               │
│  ├─ peer_connected(peer_id) → send initial state          │
│  ├─ peer_disconnected(peer_id) → handle disconnect        │
│  └─ action_validated(action) → apply via GameManager      │
└─────────────────────────────────────────────────────────────┘

ACTION FLOW (CORRECTED):
─────────────────────────────────────────────────────────────

SINGLE PLAYER MODE:
User Input → Controller → Phase Instance →
GameManager.apply_action() → GameState.state modified

MULTIPLAYER MODE (HOST):
User Input → Controller → NetworkManager.submit_action() →
validate_action() → GameManager.apply_action() →
GameState.state modified → broadcast_result.rpc() →
Client receives and applies

MULTIPLAYER MODE (CLIENT):
User Input → Controller → NetworkManager.submit_action() →
send_to_host.rpc() → [Host validates and applies] →
Client receives broadcast_result.rpc() →
GameManager.apply_result() → GameState.state modified
```

---

## 🔄 CRITICAL CORRECTIONS FROM v3 → v4

### 1. **NetworkManager Integration - COMPLETELY REWRITTEN**

**v3 Approach (WRONG)**:
```gdscript
# In GameState.gd._ready()
func _ready() -> void:
    initialize_default_state()

    if FeatureFlags.MULTIPLAYER_ENABLED:
        _initialize_network_manager()

func _initialize_network_manager() -> void:
    var nm = load("res://autoloads/NetworkManager.gd").new()
    add_child(nm)  # ❌ WRONG: GameState is not designed for child nodes
    network_manager = nm
```

**v4 Approach (CORRECT)**:
```gdscript
# In project.godot autoload section (add after line 39):
NetworkManager="*res://autoloads/NetworkManager.gd"

# In NetworkManager.gd
extends Node
class_name NetworkManager

var game_manager: GameManager = null
var game_state: GameStateData = null

func _ready() -> void:
    if not FeatureFlags.MULTIPLAYER_ENABLED:
        return

    # Get references to other autoloads
    game_manager = get_node("/root/GameManager")
    game_state = get_node("/root/GameState")

    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# No GameState modifications needed!
```

---

### 2. **Action Execution Flow - COMPLETELY REWRITTEN**

**v3 Approach (WRONG)**:
```gdscript
func _execute_locally(action: Dictionary) -> void:
    var phase = PhaseManager.get_current_phase_instance()
    if phase:
        phase.execute_action(action)  # ❌ Method doesn't exist
```

**v4 Approach (CORRECT)**:
```gdscript
func _execute_action_locally(action: Dictionary) -> Dictionary:
    # Route through GameManager (the actual action processor)
    var result = game_manager.apply_action(action)
    return result

func _execute_as_host(action: Dictionary) -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    var validation = validate_action(action, peer_id)

    if not validation.valid:
        _reject_action.rpc_id(peer_id, action.get("id", ""), validation.reason)
        return

    # Execute via GameManager
    var result = _execute_action_locally(action)

    if result.success:
        # Broadcast the RESULT (not the action)
        _broadcast_result.rpc(result)

@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
    # Clients apply the result (with diffs already computed)
    game_manager.apply_result(result)
```

---

### 3. **State Synchronization - COMPLETELY REWRITTEN**

**v3 Approach**: Sync actions and replay them
**v4 Approach**: Sync **results** with diffs already computed by host

**Why This Matters**:
- GameManager generates **diffs** (e.g., `{"op": "set", "path": "units.U1.pos", "value": [100, 200]}`)
- Host computes diffs once, broadcasts result with diffs
- Clients apply diffs directly via `GameManager.apply_result()`
- **Deterministic execution guaranteed** (no client-side action processing)

```gdscript
# Initial state sync (when client joins)
@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
    # Direct state replacement
    game_state.state = snapshot.duplicate(true)

    # Notify UI to refresh
    get_tree().call_group("ui_refresh", "refresh_from_state")

# Ongoing action sync
@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
    if is_host():
        return  # Host already applied locally

    # Apply result (which includes diffs)
    game_manager.apply_result(result)
```

---

### 4. **RNG Determinism - UNCHANGED (Still Correct)**

**v3 Analysis**: ✅ Correct line numbers
**v4 Verification**: ✅ Confirmed accurate

**Locations Verified**:
1. `MovementPhase.gd:433-435` - Advance roll ✅
2. `MovementPhase.gd:923-924` - Fall back hazardous terrain roll ✅
3. `MovementController.gd:792-793` - UI advance dice roll ✅

**Fix Strategy** (Unchanged from v3):
```gdscript
# Replace all instances with:
var rng_seed = -1
if has_node("/root/NetworkManager"):
    var net_mgr = get_node("/root/NetworkManager")
    if net_mgr.is_networked() and net_mgr.is_host():
        rng_seed = net_mgr.get_next_rng_seed()

var rng_service = RulesEngine.RNGService.new(rng_seed)
var rolls = rng_service.roll_d6(1)
var result = rolls[0]
```

---

### 5. **Validation Layer - CORRECTED**

**v3 Approach**: 6-layer validation with phase delegation
**v4 Approach**: Simplified 4-layer validation with correct delegation

```gdscript
func validate_action(action: Dictionary, peer_id: int) -> Dictionary:
    # Layer 1: Schema validation
    if not action.has("type"):
        return {"valid": false, "reason": "Missing action type"}

    # Layer 2: Authority validation
    var claimed_player = action.get("player", -1)
    var peer_player = peer_to_player_map.get(peer_id, -1)
    if claimed_player != peer_player:
        return {"valid": false, "reason": "Player ID mismatch"}

    # Layer 3: Turn validation
    if claimed_player != game_state.get_active_player():
        return {"valid": false, "reason": "Not your turn"}

    # Layer 4: Game rules validation (delegate to phase)
    var phase = get_node("/root/PhaseManager").get_current_phase_instance()
    if phase and phase.has_method("validate_action"):
        return phase.validate_action(action)

    return {"valid": true}
```

---

## 🆕 CORRECTED: MVP Implementation (v4 Revised)

### MVP Phase 0: Preparation (1-2 weeks)

**Deliverables**:
1. ✅ Create `res://autoloads/FeatureFlags.gd`
2. ✅ Add NetworkManager to `project.godot` autoload section
3. ✅ Verify GUT test framework (confirmed as GUT)
4. ✅ Establish test baseline - run existing tests
5. ✅ Create `tests/helpers/MockNetworkPeer.gd`

**Code to Add**:

```gdscript
# res://autoloads/FeatureFlags.gd
extends Node
class_name FeatureFlags

const MULTIPLAYER_ENABLED: bool = false  # Toggle for development

static func is_multiplayer_available() -> bool:
    return MULTIPLAYER_ENABLED and OS.has_feature("network")
```

**project.godot modification** (add after line 39):
```ini
NetworkManager="*res://autoloads/NetworkManager.gd"
```

---

### MVP Phase 1: Core Sync (2-3 weeks)

**Goal**: Two players connect, see synchronized state, but NO validation yet

**Deliverables**:
1. NetworkManager autoload (Tier 1 - ~100 lines)
2. Host/client connection setup
3. Initial state sync on join
4. Peer connection/disconnection detection
5. Basic lobby UI (host/join screens)

**NetworkManager Tier 1** (CORRECTED):

```gdscript
# res://autoloads/NetworkManager.gd
extends Node
class_name NetworkManager

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal game_started()

enum NetworkMode { OFFLINE, HOST, CLIENT }

var network_mode: NetworkMode = NetworkMode.OFFLINE
var peer_to_player_map: Dictionary = {}
var game_manager: GameManager = null
var game_state: GameStateData = null

func _ready() -> void:
    if not FeatureFlags.MULTIPLAYER_ENABLED:
        print("NetworkManager: Multiplayer disabled via feature flag")
        return

    # Get references to autoloads (CORRECT approach)
    game_manager = get_node("/root/GameManager")
    game_state = get_node("/root/GameState")

    # Connect to multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)

func create_host(port: int = 7777) -> int:
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, 1)  # Max 1 client (2 player game)

    if error != OK:
        print("NetworkManager: Failed to create host - ", error)
        return error

    multiplayer.multiplayer_peer = peer
    network_mode = NetworkMode.HOST
    peer_to_player_map[1] = 1  # Host is player 1

    print("NetworkManager: Hosting on port ", port)
    return OK

func join_as_client(ip: String, port: int = 7777) -> int:
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(ip, port)

    if error != OK:
        print("NetworkManager: Failed to connect to ", ip, ":", port, " - ", error)
        return error

    multiplayer.multiplayer_peer = peer
    network_mode = NetworkMode.CLIENT

    print("NetworkManager: Connecting to ", ip, ":", port)
    return OK

func is_host() -> bool:
    return network_mode == NetworkMode.HOST

func is_networked() -> bool:
    return network_mode != NetworkMode.OFFLINE

func disconnect_network() -> void:
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null

    network_mode = NetworkMode.OFFLINE
    peer_to_player_map.clear()

# MVP Phase 1: Simple action submission (no validation)
func submit_action(action: Dictionary) -> void:
    if not is_networked():
        # Single player mode - apply directly
        game_manager.apply_action(action)
        return

    if is_host():
        # Host applies and broadcasts
        var result = game_manager.apply_action(action)
        if result.success:
            _broadcast_result.rpc(result)
    else:
        # Client sends to host
        _send_action_to_host.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func _send_action_to_host(action: Dictionary) -> void:
    if not is_host():
        return

    # MVP Phase 1: No validation, just execute
    var result = game_manager.apply_action(action)
    if result.success:
        _broadcast_result.rpc(result)

@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
    if is_host():
        return  # Host already applied locally

    # Client applies the result
    game_manager.apply_result(result)

func _on_peer_connected(peer_id: int) -> void:
    print("NetworkManager: Peer connected - ", peer_id)

    if is_host():
        # Assign player 2 to new peer
        peer_to_player_map[peer_id] = 2

        # Send full game state to joining client
        var snapshot = game_state.create_snapshot()
        _send_initial_state.rpc_id(peer_id, snapshot)

        emit_signal("peer_connected", peer_id)
        emit_signal("game_started")

func _on_peer_disconnected(peer_id: int) -> void:
    print("NetworkManager: Peer disconnected - ", peer_id)

    if peer_to_player_map.has(peer_id):
        peer_to_player_map.erase(peer_id)

    emit_signal("peer_disconnected", peer_id)

    # MVP: End game on disconnect
    push_error("Player disconnected - game ending")
    get_tree().quit()

func _on_connection_failed() -> void:
    print("NetworkManager: Connection failed")
    emit_signal("connection_failed", "Could not connect to host")
    network_mode = NetworkMode.OFFLINE

@rpc("authority", "call_remote", "reliable")
func _send_initial_state(snapshot: Dictionary) -> void:
    print("NetworkManager: Receiving initial state from host")

    # Replace local state with host's state
    game_state.load_from_snapshot(snapshot)

    print("NetworkManager: State synchronized")
    emit_signal("game_started")
```

**Line Count**: ~115 lines (Tier 1 MVP)

---

### MVP Phase 2: Action Validation (2-3 weeks)

**Goal**: Host validates all actions, clients cannot cheat

**Add to NetworkManager**:

```gdscript
# Add after submit_action()
func validate_action(action: Dictionary, peer_id: int) -> Dictionary:
    # Layer 1: Schema
    if not action.has("type"):
        return {"valid": false, "reason": "Invalid action schema"}

    # Layer 2: Authority
    var claimed_player = action.get("player", -1)
    var peer_player = peer_to_player_map.get(peer_id, -1)
    if claimed_player != peer_player:
        return {"valid": false, "reason": "Player ID mismatch"}

    # Layer 3: Turn
    if claimed_player != game_state.get_active_player():
        return {"valid": false, "reason": "Not your turn"}

    # Layer 4: Game rules (delegate to phase)
    var phase_mgr = get_node("/root/PhaseManager")
    var phase = phase_mgr.get_current_phase_instance()
    if phase and phase.has_method("validate_action"):
        return phase.validate_action(action)

    return {"valid": true}

# Modify _send_action_to_host() to add validation
@rpc("any_peer", "call_remote", "reliable")
func _send_action_to_host(action: Dictionary) -> void:
    if not is_host():
        return

    # Get sender peer ID
    var peer_id = multiplayer.get_remote_sender_id()

    # Validate action
    var validation = validate_action(action, peer_id)
    if not validation.valid:
        _reject_action.rpc_id(peer_id, action.get("type", ""), validation.reason)
        return

    # Execute and broadcast
    var result = game_manager.apply_action(action)
    if result.success:
        _broadcast_result.rpc(result)

@rpc("authority", "call_remote", "reliable")
func _reject_action(action_type: String, reason: String) -> void:
    push_error("Action rejected: %s - %s" % [action_type, reason])
    # TODO: Show UI error message to player
```

**Additional Lines**: ~50 lines
**Total**: ~165 lines

---

### MVP Phase 3: Turn Timer (1 week)

**Goal**: Enforce 90-second turn limit, forfeit on timeout

```gdscript
# Add to NetworkManager
var turn_timer: Timer = null
const TURN_TIMEOUT_SECONDS: float = 90.0

func _ready() -> void:
    # ... existing code ...

    # Create turn timer
    turn_timer = Timer.new()
    turn_timer.one_shot = true
    turn_timer.timeout.connect(_on_turn_timeout)
    add_child(turn_timer)

func start_turn_timer() -> void:
    if not is_networked() or not is_host():
        return

    turn_timer.start(TURN_TIMEOUT_SECONDS)
    print("NetworkManager: Turn timer started - ", TURN_TIMEOUT_SECONDS, " seconds")

func stop_turn_timer() -> void:
    if turn_timer:
        turn_timer.stop()

func _on_turn_timeout() -> void:
    if not is_host():
        return

    print("NetworkManager: Turn timeout!")
    var current_player = game_state.get_active_player()
    var winner = 3 - current_player  # Other player wins

    _broadcast_game_over.rpc(winner, "turn_timeout")

@rpc("authority", "call_remote", "reliable")
func _broadcast_game_over(winner: int, reason: String) -> void:
    print("NetworkManager: Game over! Winner: Player %d (%s)" % [winner, reason])
    # TODO: Show game over UI

# Hook into phase changes
func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
    if not is_networked():
        return

    # Restart timer on each phase
    if is_host():
        start_turn_timer()
```

**Additional Lines**: ~40 lines
**Total**: ~205 lines (MVP complete)

---

### MVP Phase 4: Deterministic RNG (1-2 weeks)

**Goal**: Fix non-deterministic RNG, sync seeds

**Add to NetworkManager**:

```gdscript
var rng_seed_counter: int = 0
var game_session_id: String = ""

func _ready() -> void:
    # ... existing code ...
    game_session_id = str(Time.get_unix_time_from_system())

func get_next_rng_seed() -> int:
    if not is_networked():
        return -1  # Single player - non-deterministic

    if not is_host():
        push_error("NetworkManager: Only host can generate RNG seeds!")
        return -1

    rng_seed_counter += 1
    var seed_value = hash([game_session_id, rng_seed_counter, game_state.get_turn_number()])
    print("NetworkManager: Generated RNG seed: ", seed_value)
    return seed_value
```

**Fix MovementPhase.gd:433-435**:
```gdscript
# OLD:
var rng = RandomNumberGenerator.new()
rng.randomize()
var advance_roll = rng.randi_range(1, 6)

# NEW:
var rng_seed = -1
if has_node("/root/NetworkManager"):
    var net_mgr = get_node("/root/NetworkManager")
    if net_mgr.is_networked() and net_mgr.is_host():
        rng_seed = net_mgr.get_next_rng_seed()

var rng_service = RulesEngine.RNGService.new(rng_seed)
var rolls = rng_service.roll_d6(1)
var advance_roll = rolls[0]
```

**Apply same fix to**:
- MovementPhase.gd:923-924 (fall back hazardous terrain)
- MovementController.gd:792-793 (UI dice roll)

**Additional Lines**: ~20 lines in NetworkManager + ~30 lines total for fixes
**Total**: ~255 lines (Full MVP)

---

## 📋 UPDATED TIMELINE (v4 Realistic)

| Phase | Duration (Solo) | Duration (Team of 3) | Deliverable |
|-------|----------------|---------------------|-------------|
| Phase 0: Preparation | 1-2 weeks | 3-4 days | Feature flags, autoload setup, test baseline |
| Phase 1: Core Sync | 3-4 weeks | 2-3 weeks | Connect, sync state, no validation |
| Phase 2: Validation | 2-3 weeks | 1-2 weeks | Host authority, action validation |
| Phase 3: Turn Timer | 1 week | 3-4 days | 90s timeout, forfeit handling |
| Phase 4: RNG Determinism | 2 weeks | 1 week | Fix 3 RNG locations, seed sync |
| **MVP TOTAL** | **9-12 weeks** | **5-7 weeks** | Playable multiplayer |

**Buffer**: Add 20-30% for integration issues
**Realistic Estimate**: 11-16 weeks solo, 6-9 weeks team of 3

**v3 Estimate**: 3-4 weeks (team of 3)
**v4 Estimate**: 6-9 weeks (team of 3)
**Reason for Increase**: v3 underestimated complexity by not accounting for GameManager integration

---

## 🧪 CORRECTED TESTING STRATEGY

### Unit Tests (GUT Framework - Confirmed)

```gdscript
# tests/network/test_network_manager.gd
extends GutTest

var network_manager: NetworkManager
var game_manager: GameManager
var game_state: GameStateData

func before_each():
    # Create fresh instances for testing
    network_manager = NetworkManager.new()
    game_manager = GameManager.new()
    game_state = GameStateData.new()

    # Inject dependencies (since we can't use autoloads in tests)
    network_manager.game_manager = game_manager
    network_manager.game_state = game_state

    add_child_autofree(network_manager)
    add_child_autofree(game_manager)
    add_child_autofree(game_state)

func test_host_creation():
    var result = network_manager.create_host(7777)
    assert_eq(result, OK)
    assert_true(network_manager.is_host())
    assert_true(network_manager.is_networked())

func test_action_routes_through_game_manager():
    # Setup
    network_manager.network_mode = NetworkManager.NetworkMode.OFFLINE
    var action = {"type": "DEPLOY_UNIT", "unit_id": "U1", "player": 1, "models": []}

    # Execute
    network_manager.submit_action(action)

    # Verify GameManager received the action
    assert_gt(game_manager.action_history.size(), 0)
    assert_eq(game_manager.action_history[0]["type"], "DEPLOY_UNIT")

func test_validation_rejects_wrong_player():
    # Setup host
    network_manager.network_mode = NetworkManager.NetworkMode.HOST
    network_manager.peer_to_player_map[1] = 1
    network_manager.peer_to_player_map[2] = 2
    game_state.set_active_player(1)

    # Player 2 tries to act when it's Player 1's turn
    var action = {"type": "MOVE_UNIT", "player": 2, "unit_id": "U1"}
    var validation = network_manager.validate_action(action, 2)

    assert_false(validation.valid)
    assert_eq(validation.reason, "Not your turn")
```

---

## 🚨 BREAKING CHANGES FROM v3

### What v3 Got Wrong:
1. ❌ GameState child node architecture
2. ❌ PhaseManager.execute_action() (doesn't exist)
3. ❌ Direct phase action execution
4. ❌ Ignored GameManager entirely

### What v4 Fixes:
1. ✅ NetworkManager as standalone autoload
2. ✅ Route all actions through GameManager
3. ✅ Broadcast results (with diffs), not actions
4. ✅ Proper autoload reference management

---

## 📝 IMPLEMENTATION CHECKLIST (v4 Corrected)

### Phase 0: Preparation
- [ ] Create `res://autoloads/FeatureFlags.gd` (set MULTIPLAYER_ENABLED = false)
- [ ] Add NetworkManager to `project.godot` autoload section (after line 39)
- [ ] Run all existing tests to establish baseline
- [ ] Create `tests/helpers/MockNetworkPeer.gd`
- [ ] Create `tests/network/` directory

### Phase 1: Core Sync
- [ ] Create `res://autoloads/NetworkManager.gd` (Tier 1 - ~115 lines)
- [ ] Implement `create_host()`, `join_as_client()`
- [ ] Implement `submit_action()` routing to GameManager
- [ ] Implement `_broadcast_result()` with GameManager.apply_result()
- [ ] Implement `_send_initial_state()` with full state sync
- [ ] Create lobby UI (host/join buttons, IP input)
- [ ] Manual test: Two instances connect and sync

### Phase 2: Validation
- [ ] Implement `validate_action()` (4 layers)
- [ ] Add validation to `_send_action_to_host()`
- [ ] Implement `_reject_action()` RPC
- [ ] Add UI for rejection messages
- [ ] Test: Invalid actions rejected

### Phase 3: Turn Timer
- [ ] Add turn_timer Timer node
- [ ] Implement `start_turn_timer()`, `stop_turn_timer()`
- [ ] Implement `_on_turn_timeout()`
- [ ] Implement `_broadcast_game_over()` RPC
- [ ] Hook into phase changes
- [ ] Test: Turn timeout enforced

### Phase 4: Deterministic RNG
- [ ] Add `rng_seed_counter` and `game_session_id` to NetworkManager
- [ ] Implement `get_next_rng_seed()`
- [ ] Fix MovementPhase.gd:433-435
- [ ] Fix MovementPhase.gd:923-924
- [ ] Fix MovementController.gd:792-793
- [ ] Test: Same dice rolls on host and client

---

## 🎯 SUCCESS CRITERIA (v4)

### MVP Must-Haves:
1. ✅ Two players connect on LAN (host/client)
2. ✅ Initial state synchronized on join
3. ✅ Actions route through GameManager correctly
4. ✅ Results broadcast with diffs
5. ✅ Host validates all actions (4-layer validation)
6. ✅ Client cannot cheat (authority enforcement)
7. ✅ Turn timer enforced (90 seconds)
8. ✅ Disconnection ends game gracefully
9. ✅ Deterministic RNG (3 locations fixed)
10. ✅ Existing tests still pass (feature flag = false)

### Performance Targets:
- Action latency < 200ms (host validate + broadcast)
- State sync < 1 second
- Memory overhead < 5MB

---

## ⚠️ KNOWN RISKS (v4)

### High Risk 🔴
1. **GameManager Integration Complexity**
   - Risk: apply_result() may not work exactly as expected
   - Mitigation: Test thoroughly with various action types

2. **State Synchronization Edge Cases**
   - Risk: Dictionary deep copy issues, reference inconsistencies
   - Mitigation: Use GameState.create_snapshot() and load_from_snapshot()

3. **Timeline Underestimation**
   - Risk: 6-9 weeks may still be optimistic
   - Mitigation: Use phased approach, ship MVP first

### Medium Risk 🟡
1. **RNG Determinism Coverage**
   - Risk: Other non-deterministic code not yet discovered
   - Mitigation: Add checksum validation in post-MVP

2. **Existing Test Compatibility**
   - Risk: Tests may fail despite feature flag
   - Mitigation: Ensure FeatureFlags check in _ready() exits early

---

## 🏁 CONCLUSION (v4 Final Assessment)

### Why v3 Would Have Failed:
1. Fundamental misunderstanding of GameManager's role
2. Incorrect integration point (PhaseManager instead of GameManager)
3. Wrong architecture (child node instead of autoload)
4. Would have broken existing action processing flow

### Why v4 Will Succeed:
1. ✅ Correctly identifies GameManager as action processor
2. ✅ Proper autoload architecture (standalone, not child)
3. ✅ Routes actions through existing flow (no bypass)
4. ✅ Broadcasts results (with computed diffs)
5. ✅ Feature flag prevents test breakage
6. ✅ MVP-first approach (215 lines total for phases 1-3)

### Final Recommendation:
**Implement v4 with revised architecture**. The v3 PRP showed good RNG analysis and security thinking, but missed critical architectural components. v4 corrects these fundamental issues.

**Estimated Time**: 6-9 weeks (team of 3), 11-16 weeks (solo)
**Risk Level**: Medium (with proper testing)
**Confidence**: High (based on actual codebase analysis)

---

**Review Score: 7.5/10** - Architecturally sound with realistic expectations

**Reviewer Notes**: The junior developer did excellent work identifying non-deterministic RNG locations (100% accurate line numbers), but failed to discover GameManager's central role. This v4 revision fixes those gaps and provides a production-ready implementation plan.

---

## APPENDIX A: Architectural Differences (v3 vs v4)

| Component | v3 Approach | v4 Approach | Reason for Change |
|-----------|-------------|-------------|-------------------|
| NetworkManager Location | Child of GameState | Standalone autoload | GameState not designed for children |
| Action Execution | phase.execute_action() | GameManager.apply_action() | Correct existing flow |
| State Sync | Action replay | Result broadcast (with diffs) | Host-computed diffs |
| Integration Point | PhaseManager | GameManager | GameManager is action processor |
| GameState Modification | Add network_manager child | Add autoload reference | Proper singleton pattern |

---

## APPENDIX B: Code Size Comparison

| Phase | v3 Estimate | v4 Actual | Difference |
|-------|-------------|-----------|------------|
| Tier 1 (Core Sync) | 80 lines | 115 lines | +35 (GameManager integration) |
| Tier 2 (Validation) | +80 lines | +50 lines | -30 (simplified) |
| Tier 3 (Turn Timer) | N/A | +40 lines | New |
| RNG Fixes | 50 lines | 50 lines | Same |
| **Total MVP** | ~200 lines | ~255 lines | +55 lines |

**Reason for Increase**: Proper GameManager integration requires more careful routing and error handling than v3 anticipated.

---

**END OF PRP v4**