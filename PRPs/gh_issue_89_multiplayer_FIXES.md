# PRP CRITICAL FIXES: Issues 1-5

## Summary of Issues Found in Original PRP

All 5 issues identified are **VALID** and require fixes before implementation:

1. ✅ RNG Integration Flaw - RulesEngine uses `class RNGService`, not `var rng`
2. ✅ Missing Security Validations - No ownership/phase checks
3. ✅ Input Lag Not Addressed - Critical for UX, needs optimistic prediction + rollback
4. ✅ Checksum Design Weakness - JSON stringify unreliable, needs XOR-based approach
5. ✅ Transport System Omitted - Embark/disembark not synchronized

---

## FIX 1: RNG Integration (RulesEngine.gd)

### Problem
```gdscript
# RulesEngine.gd:88-97
class RNGService:
    var rng: RandomNumberGenerator

    func _init(seed_value: int = -1):
        rng = RandomNumberGenerator.new()
        if seed_value >= 0:
            rng.seed = seed_value
        else:
            rng.randomize()  # ← Non-deterministic!
```

PRP suggested modifying `_ready()`, but RulesEngine is **static** - methods are called directly without instance.

### Correct Solution

**File**: `40k/autoloads/RulesEngine.gd` (Modify lines 88-108)

```gdscript
# RNG Service for deterministic dice rolling
class RNGService:
    var rng: RandomNumberGenerator

    func _init(seed_value: int = -1):
        rng = RandomNumberGenerator.new()
        if seed_value >= 0:
            # Deterministic mode (multiplayer)
            rng.seed = seed_value
            print("[RNGService] Initialized with seed: %d" % seed_value)
        else:
            # Non-deterministic mode (offline)
            # Check if NetworkManager exists and is networked
            if Engine.has_singleton("NetworkManager"):
                var nm = Engine.get_singleton("NetworkManager")
                if nm and nm.has_method("is_networked") and nm.is_networked():
                    # Get action-specific seed from NetworkManager
                    var action_seed = nm.get_current_action_seed()
                    rng.seed = action_seed
                    print("[RNGService] Using NetworkManager seed: %d" % action_seed)
                    return

            # Fallback to random (offline mode)
            rng.randomize()
            print("[RNGService] Using random seed (offline mode)")

    func roll_d6(count: int) -> Array:
        var rolls = []
        for i in count:
            rolls.append(rng.randi_range(1, 6))
        return rolls

    func roll_d3(count: int) -> Array:
        var rolls = []
        for i in count:
            rolls.append(rng.randi_range(1, 3))
        return rolls

    func roll_2d6() -> int:
        return rng.randi_range(1, 6) + rng.randi_range(1, 6)

# Main shooting resolution entry point
static func resolve_shoot(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
    if not rng_service:
        # Create RNG service with seed from action metadata (if networked)
        var seed = action.get("_net_rng_seed", -1)
        rng_service = RNGService.new(seed)

    # ... rest of implementation
```

**Key Changes**:
1. Constructor checks for NetworkManager singleton
2. Falls back to randomize() only in offline mode
3. Static methods accept optional seed via action metadata
4. Added `get_current_action_seed()` to NetworkManager

**NetworkManager Addition**:
```gdscript
# In NetworkManager.gd
var current_action_seed: int = -1

func get_current_action_seed() -> int:
    return current_action_seed

func _prepare_rng_for_action(action: Dictionary) -> void:
    # Derive action-specific seed from master seed + counter
    var action_seed = hash(game_rng_seed + action_counter)
    action_counter += 1

    # Store for RNGService to access
    current_action_seed = action_seed

    # Also store in action metadata
    action["_net_rng_seed"] = action_seed

    print("[NetworkManager] Action %d RNG seed: %d" % [action_counter - 1, action_seed])
```

### Usage in Phases

**File**: `40k/phases/MovementPhase.gd` (Line 433-435 fix)

**Before**:
```gdscript
var rng = RandomNumberGenerator.new()
rng.randomize()
var advance_roll = rng.randi_range(1, 6)
```

**After**:
```gdscript
# Get seed from action or NetworkManager
var seed = action.get("_net_rng_seed", -1)
var rng_service = RulesEngine.RNGService.new(seed)
var advance_roll = rng_service.roll_d6(1)[0]
```

---

## FIX 2: Missing Security Validations

### Problem
Current PRP only validates turn order. Missing:
- **Ownership validation**: Client could move opponent's units
- **Phase-appropriate actions**: Client could shoot during movement phase
- **Bounds validation**: Weak position checks

### Correct Solution

**File**: `40k/autoloads/NetworkManager.gd` (Add to _validate_and_execute_action)

```gdscript
func _validate_and_execute_action(action: Dictionary, sender_id: int) -> void:
    print("[NetworkManager] Host validating action from peer %d: %s" % [sender_id, action.get("type", "UNKNOWN")])

    # SECURITY CHECK 1: Turn order
    var expected_player = GameState.get_active_player()
    var sender_player = _get_player_from_peer_id(sender_id)

    if sender_player != expected_player:
        _reject_action(action, sender_id, "Not your turn (expected P%d, got P%d)" % [expected_player, sender_player])
        return

    # SECURITY CHECK 2: Rate limiting
    if not _check_rate_limit(sender_id):
        _reject_action(action, sender_id, "Rate limit exceeded")
        return

    # SECURITY CHECK 3: Input sanitization
    var input_validation = _validate_rpc_input(action)
    if not input_validation.valid:
        _reject_action(action, sender_id, input_validation.error)
        return

    # SECURITY CHECK 4: Ownership validation
    var ownership_check = _validate_action_ownership(action, sender_player)
    if not ownership_check.valid:
        _reject_action(action, sender_id, ownership_check.error)
        return

    # SECURITY CHECK 5: Phase-appropriate action
    var phase_check = _validate_phase_action_type(action)
    if not phase_check.valid:
        _reject_action(action, sender_id, phase_check.error)
        return

    # SECURITY CHECK 6: Bounds validation
    var bounds_check = _validate_action_bounds(action)
    if not bounds_check.valid:
        _reject_action(action, sender_id, bounds_check.error)
        return

    # All security checks passed - prepare deterministic RNG
    _prepare_rng_for_action(action)

    # Execute action through PhaseManager
    var result = PhaseManager.get_current_phase_instance().execute_action(action)

    # Broadcast result
    var response = {
        "success": result.get("success", false),
        "action_id": action.get("_net_id", ""),
        "action": action,
        "result": result
    }

    if not result.get("success", false):
        response["error"] = result.get("error", "Unknown error")

    # Send to all peers
    rpc("_receive_action_result", response)
    _receive_action_result(response)

# NEW: Validate action ownership
func _validate_action_ownership(action: Dictionary, player: int) -> Dictionary:
    var action_type = action.get("type", "")

    # Actions that target specific units
    var unit_actions = [
        "BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK",
        "STAGE_MODEL_MOVE", "CONFIRM_UNIT_MOVE", "RESET_UNIT_MOVE",
        "REMAIN_STATIONARY", "SELECT_TARGET", "DECLARE_CHARGE",
        "DISEMBARK_UNIT", "EMBARK_UNIT"
    ]

    if action_type in unit_actions:
        var unit_id = action.get("actor_unit_id", "")
        if unit_id == "":
            return {"valid": false, "error": "Missing actor_unit_id"}

        var unit = GameState.get_unit(unit_id)
        if unit.is_empty():
            return {"valid": false, "error": "Unit not found: " + unit_id}

        if unit.get("owner", 0) != player:
            return {
                "valid": false,
                "error": "Cannot control opponent's unit (unit owner: P%d, sender: P%d)" % [unit.get("owner", 0), player]
            }

    # Actions that target opponent's units (allowed)
    var targeting_actions = ["SELECT_TARGET", "ALLOCATE_WOUND"]
    if action_type in targeting_actions:
        # These are allowed to target opponent's units
        return {"valid": true}

    return {"valid": true}

# NEW: Validate phase-appropriate actions
func _validate_phase_action_type(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")
    var current_phase = GameState.get_current_phase()

    # Define allowed actions per phase
    var phase_actions = {
        GameStateData.Phase.DEPLOYMENT: [
            "DEPLOY_UNIT", "END_DEPLOYMENT"
        ],
        GameStateData.Phase.COMMAND: [
            "USE_STRATAGEM", "SPEND_CP", "END_COMMAND"
        ],
        GameStateData.Phase.MOVEMENT: [
            "BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK",
            "STAGE_MODEL_MOVE", "CONFIRM_UNIT_MOVE", "RESET_UNIT_MOVE",
            "REMAIN_STATIONARY", "DISEMBARK_UNIT", "EMBARK_UNIT",
            "END_MOVEMENT"
        ],
        GameStateData.Phase.SHOOTING: [
            "SELECT_TARGET", "RESOLVE_SHOOTING", "ALLOCATE_WOUND",
            "END_SHOOTING"
        ],
        GameStateData.Phase.CHARGE: [
            "DECLARE_CHARGE", "ROLL_CHARGE", "RESOLVE_OVERWATCH",
            "END_CHARGE"
        ],
        GameStateData.Phase.FIGHT: [
            "SELECT_FIGHT_TARGET", "RESOLVE_FIGHT", "PILE_IN",
            "CONSOLIDATE", "END_FIGHT"
        ],
        GameStateData.Phase.SCORING: [
            "SCORE_OBJECTIVE", "END_SCORING"
        ],
        GameStateData.Phase.MORALE: [
            "ROLL_BATTLESHOCK", "END_MORALE"
        ]
    }

    var allowed_actions = phase_actions.get(current_phase, [])

    if action_type not in allowed_actions:
        return {
            "valid": false,
            "error": "Action '%s' not allowed in %s phase" % [action_type, GameStateData.Phase.keys()[current_phase]]
        }

    return {"valid": true}

# NEW: Enhanced bounds validation
func _validate_action_bounds(action: Dictionary) -> Dictionary:
    # Board dimensions: 44x60 inches = ~1117x1524 px at 25.4 px/inch
    const BOARD_WIDTH_PX = 1117.6
    const BOARD_HEIGHT_PX = 1524.0
    const MARGIN_PX = 50.0  # Allow small margin for edge cases

    # Check positions in payload
    if action.has("payload"):
        var payload = action.payload

        # Single position
        if payload.has("dest") and payload.dest is Array and payload.dest.size() == 2:
            var x = payload.dest[0]
            var y = payload.dest[1]

            if x < -MARGIN_PX or x > BOARD_WIDTH_PX + MARGIN_PX or \
               y < -MARGIN_PX or y > BOARD_HEIGHT_PX + MARGIN_PX:
                return {
                    "valid": false,
                    "error": "Position out of bounds: (%.1f, %.1f)" % [x, y]
                }

        # Multiple positions (e.g., disembark)
        if payload.has("positions") and payload.positions is Array:
            for pos in payload.positions:
                if pos is Array and pos.size() == 2:
                    var x = pos[0]
                    var y = pos[1]

                    if x < -MARGIN_PX or x > BOARD_WIDTH_PX + MARGIN_PX or \
                       y < -MARGIN_PX or y > BOARD_HEIGHT_PX + MARGIN_PX:
                        return {
                            "valid": false,
                            "error": "Position out of bounds: (%.1f, %.1f)" % [x, y]
                        }

    # Validate numeric ranges (e.g., dice values, CP costs)
    if action.has("payload"):
        if action.payload.has("dice_value"):
            var dice_value = action.payload.dice_value
            if dice_value < 1 or dice_value > 6:
                return {"valid": false, "error": "Invalid dice value: %d" % dice_value}

        if action.payload.has("cp_cost"):
            var cp_cost = action.payload.cp_cost
            if cp_cost < 0 or cp_cost > 10:
                return {"valid": false, "error": "Invalid CP cost: %d" % cp_cost}

    return {"valid": true}

# Helper to reject actions consistently
func _reject_action(action: Dictionary, sender_id: int, error: String) -> void:
    print("[NetworkManager] Action rejected: %s" % error)

    rpc_id(sender_id, "_receive_action_result", {
        "success": false,
        "action_id": action.get("_net_id", ""),
        "error": error,
        "current_state_checksum": _calculate_state_checksum()
    })
```

---

## FIX 3: Input Lag - Optimistic Prediction + Rollback

### Problem
Without prediction: **110-450ms delay** per action (client → host → validation → broadcast → client).

For turn-based games, this feels sluggish. Players expect **instant visual feedback**.

### Correct Solution: Optimistic Client Prediction with Rollback

**File**: `40k/autoloads/NetworkManager.gd` (Modify submit_action)

```gdscript
# Client-side prediction state
var predicted_actions: Dictionary = {}  # action_id -> {action, snapshot}
var enable_client_prediction: bool = true

func submit_action(action: Dictionary) -> void:
    if network_mode == NetworkMode.OFFLINE:
        _execute_action_locally(action)
        return

    if network_mode == NetworkMode.HOST:
        _validate_and_execute_action(action, multiplayer.get_unique_id())
        return

    if network_mode == NetworkMode.CLIENT:
        var action_id = _generate_action_id()
        action["_net_id"] = action_id
        action["_net_timestamp"] = Time.get_ticks_msec()

        # OPTIMISTIC PREDICTION: Execute locally before host validates
        if enable_client_prediction:
            # Save snapshot for potential rollback
            var snapshot = GameState.create_snapshot()
            predicted_actions[action_id] = {
                "action": action.duplicate(),
                "snapshot": snapshot,
                "timestamp": Time.get_ticks_msec()
            }

            print("[NetworkManager] Optimistically executing action %s" % action_id)
            _execute_action_locally(action)

        pending_actions[action_id] = action

        # Send to host for validation
        rpc_id(host_peer_id, "_receive_action_for_validation", action)

# All peers: Receive validated action result
@rpc("authority", "call_remote", "reliable")
func _receive_action_result(response: Dictionary) -> void:
    var action_id = response.get("action_id", "")
    print("[NetworkManager] Received action result for %s: success=%s" % [action_id, response.get("success", false)])

    # Remove from pending
    if pending_actions.has(action_id):
        pending_actions.erase(action_id)

    # Check if we predicted this action
    var was_predicted = predicted_actions.has(action_id)

    if not response.get("success", false):
        print("[NetworkManager] Action REJECTED: %s" % response.get("error", "Unknown"))

        if was_predicted:
            # ROLLBACK: Restore state from before prediction
            print("[NetworkManager] Rolling back failed prediction")
            var prediction = predicted_actions[action_id]
            GameState.load_from_snapshot(prediction.snapshot)

            # Emit signal for UI to refresh
            emit_signal("prediction_rolled_back", action_id)

            # Show error to player
            _show_prediction_error(response.get("error", "Action rejected by host"))

        predicted_actions.erase(action_id)
        return

    # Action succeeded
    if was_predicted:
        # Verify predicted result matches host result
        var local_checksum = _calculate_state_checksum()
        var expected_checksum = response.get("result", {}).get("state_checksum", 0)

        if expected_checksum != 0 and local_checksum != expected_checksum:
            print("[NetworkManager] PREDICTION MISMATCH! Rolling back and reapplying")

            # Rollback to pre-prediction state
            var prediction = predicted_actions[action_id]
            GameState.load_from_snapshot(prediction.snapshot)

            # Apply host's validated result
            var action = response.get("action", {})
            _execute_action_locally(action)

            emit_signal("prediction_corrected", action_id)
        else:
            print("[NetworkManager] Prediction matched! (latency hidden)")

        predicted_actions.erase(action_id)
    else:
        # We didn't predict, so apply host's result
        var action = response.get("action", {})
        _execute_action_locally(action)

    emit_signal("action_result_received", response)

# Show prediction error to player
func _show_prediction_error(error: String) -> void:
    # Create a temporary notification
    var notification = Label.new()
    notification.text = "Action Invalid: " + error
    notification.add_theme_color_override("font_color", Color.RED)
    notification.position = Vector2(400, 50)

    get_tree().root.add_child(notification)

    # Auto-remove after 3 seconds
    await get_tree().create_timer(3.0).timeout
    notification.queue_free()

# Cleanup old predictions (in case of lost packets)
func _process(delta: float) -> void:
    var current_time = Time.get_ticks_msec()
    var timeout_ms = 5000  # 5 second timeout

    for action_id in predicted_actions.keys():
        var prediction = predicted_actions[action_id]
        if current_time - prediction.timestamp > timeout_ms:
            print("[NetworkManager] Prediction timeout for %s, rolling back" % action_id)
            GameState.load_from_snapshot(prediction.snapshot)
            predicted_actions.erase(action_id)
            emit_signal("prediction_timeout", action_id)
```

**Key Changes**:
1. **Optimistic execution**: Client shows action immediately
2. **Snapshot storage**: Save pre-action state for rollback
3. **Rollback on rejection**: Restore snapshot if host rejects
4. **Prediction correction**: If result differs, rollback and reapply
5. **Timeout handling**: Cleanup stale predictions

**Result**: Player sees instant feedback, with corrections only on errors (rare).

---

## FIX 4: Checksum Design - XOR-Based Deterministic Hash

### Problem
```gdscript
# Original (BROKEN)
var checksum = hash(JSON.stringify(critical_state))
```

Issues:
- Dictionary key ordering not guaranteed
- Float precision differences (32.0 vs 32.00000001)
- Platform-specific JSON implementation

### Correct Solution: XOR-Based Checksum

**File**: `40k/autoloads/NetworkManager.gd` (Replace _calculate_state_checksum)

```gdscript
func _calculate_state_checksum() -> int:
    """
    Calculate deterministic checksum using XOR of critical game state.
    Avoids JSON stringify issues by explicitly ordering and rounding.
    """
    var state = GameState.create_snapshot()
    var checksum: int = 0

    # 1. Meta state (turn, phase, player, round)
    checksum ^= _hash_int(state.meta.turn_number)
    checksum ^= _hash_int(state.meta.phase)
    checksum ^= _hash_int(state.meta.active_player)
    checksum ^= _hash_int(state.meta.get("battle_round", 1))

    # 2. Player state (CP, VP) - sorted by player number
    var players = state.players
    for player_num in [1, 2]:  # Explicit ordering
        var player_str = str(player_num)
        if players.has(player_str):
            checksum ^= _hash_int(players[player_str].get("cp", 0))
            checksum ^= _hash_int(players[player_str].get("vp", 0))

    # 3. Units - sorted by unit_id
    var unit_ids = state.units.keys()
    unit_ids.sort()  # Deterministic ordering

    for unit_id in unit_ids:
        var unit = state.units[unit_id]

        # Hash unit metadata
        checksum ^= _hash_string(unit_id)
        checksum ^= _hash_int(unit.get("owner", 0))
        checksum ^= _hash_int(unit.get("status", 0))

        # Hash unit flags (sorted keys)
        if unit.has("flags"):
            var flag_keys = unit.flags.keys()
            flag_keys.sort()
            for flag_key in flag_keys:
                checksum ^= _hash_string(flag_key)
                checksum ^= _hash_bool(unit.flags[flag_key])

        # Hash models (sorted by id)
        var models = unit.get("models", [])
        for i in range(models.size()):
            var model = models[i]

            checksum ^= _hash_string(model.get("id", "m%d" % (i + 1)))
            checksum ^= _hash_bool(model.get("alive", true))
            checksum ^= _hash_int(model.get("current_wounds", 0))

            # Hash position with rounding to avoid float precision issues
            if model.has("position") and model.position != null:
                var pos = model.position
                if pos is Dictionary:
                    checksum ^= _hash_float_rounded(pos.get("x", 0.0))
                    checksum ^= _hash_float_rounded(pos.get("y", 0.0))
                elif pos is Vector2:
                    checksum ^= _hash_float_rounded(pos.x)
                    checksum ^= _hash_float_rounded(pos.y)

            # Hash rotation (rounded)
            if model.has("rotation"):
                checksum ^= _hash_float_rounded(model.get("rotation", 0.0))

            # Hash embarked status
            if unit.has("embarked_in"):
                checksum ^= _hash_string(unit.get("embarked_in", ""))

    # 4. Transport data - sorted by transport_id
    var transport_ids = []
    for unit_id in unit_ids:
        var unit = state.units[unit_id]
        if unit.has("transport_data"):
            transport_ids.append(unit_id)

    for transport_id in transport_ids:
        var transport = state.units[transport_id]
        var transport_data = transport.transport_data

        # Hash embarked units (sorted)
        if transport_data.has("embarked_units"):
            var embarked = transport_data.embarked_units.duplicate()
            embarked.sort()
            for embarked_unit_id in embarked:
                checksum ^= _hash_string(embarked_unit_id)

    return checksum

# Helper: Hash integer
func _hash_int(value: int) -> int:
    return hash(value)

# Helper: Hash string
func _hash_string(value: String) -> int:
    return hash(value)

# Helper: Hash boolean
func _hash_bool(value: bool) -> int:
    return hash(1 if value else 0)

# Helper: Hash float with rounding (to 0.01 precision)
func _hash_float_rounded(value: float) -> int:
    # Round to 2 decimal places to avoid precision issues
    var rounded = round(value * 100.0) / 100.0
    return hash(int(rounded * 100.0))  # Convert to int to avoid float hash issues
```

**Key Improvements**:
1. **Explicit ordering**: Sort all arrays/dictionaries
2. **Float rounding**: Round positions to 0.01 precision
3. **XOR accumulation**: Order-independent for same values
4. **No JSON**: Direct hashing of primitive types
5. **Transport data**: Include embarked units in checksum

**Testing Determinism**:
```gdscript
func test_checksum_determinism():
    var state1 = GameState.create_snapshot()
    var checksum1 = _calculate_state_checksum()

    # Save and reload
    var serialized = JSON.stringify(state1)
    var state2 = JSON.parse_string(serialized)
    GameState.load_from_snapshot(state2)
    var checksum2 = _calculate_state_checksum()

    assert(checksum1 == checksum2, "Checksums must match for identical state")
```

---

## FIX 5: Transport System Synchronization

### Problem
TransportManager directly modifies GameState (lines 87-96):
```gdscript
unit["embarked_in"] = transport_id
transport.transport_data.embarked_units.append(unit_id)
GameState.state.units[unit_id] = unit  # ← Direct mutation!
```

These changes bypass action system and won't be synchronized.

### Correct Solution: Transport Actions via NetworkManager

**File**: `40k/autoloads/TransportManager.gd` (Modify embark_unit and disembark_unit)

```gdscript
# Embark a unit into a transport
func embark_unit(unit_id: String, transport_id: String) -> void:
    var validation = can_embark(unit_id, transport_id)
    if not validation.valid:
        print("Cannot embark: ", validation.reason)
        return

    # MULTIPLAYER FIX: Submit embark action instead of direct state modification
    if NetworkManager and NetworkManager.is_networked():
        var action = {
            "type": "EMBARK_UNIT",
            "actor_unit_id": unit_id,
            "payload": {
                "transport_id": transport_id
            }
        }

        NetworkManager.submit_action(action)
        return

    # OFFLINE MODE: Direct modification (original behavior)
    _embark_unit_local(unit_id, transport_id)

# Disembark a unit from its transport
func disembark_unit(unit_id: String, positions: Array) -> void:
    var validation = can_disembark(unit_id)
    if not validation.valid:
        print("Cannot disembark: ", validation.reason)
        return

    # MULTIPLAYER FIX: Submit disembark action
    if NetworkManager and NetworkManager.is_networked():
        var action = {
            "type": "CONFIRM_DISEMBARK",
            "actor_unit_id": unit_id,
            "payload": {
                "positions": positions
            }
        }

        NetworkManager.submit_action(action)
        return

    # OFFLINE MODE: Direct modification
    _disembark_unit_local(unit_id, positions)

# NEW: Local embark (called by action processing)
func _embark_unit_local(unit_id: String, transport_id: String) -> void:
    var unit = GameState.get_unit(unit_id)
    var transport = GameState.get_unit(transport_id)

    # Set embarked status on unit
    unit["embarked_in"] = transport_id

    # Add unit to transport's embarked list
    if not transport.transport_data.has("embarked_units"):
        transport.transport_data["embarked_units"] = []
    transport.transport_data.embarked_units.append(unit_id)

    # Update GameState directly
    GameState.state.units[unit_id] = unit
    GameState.state.units[transport_id] = transport

    emit_signal("embark_completed", transport_id, unit_id)
    print("Unit %s embarked in transport %s" % [unit_id, transport_id])

# NEW: Local disembark (called by action processing)
func _disembark_unit_local(unit_id: String, positions: Array) -> void:
    var unit = GameState.get_unit(unit_id)
    var transport_id = unit.get("embarked_in", null)

    if not transport_id:
        print("Unit not embarked")
        return

    var transport = GameState.get_unit(transport_id)

    # Remove from transport's embarked list
    if transport.transport_data.has("embarked_units"):
        transport.transport_data.embarked_units.erase(unit_id)

    # Clear embarked status
    unit.erase("embarked_in")

    # Set unit positions
    for i in range(min(positions.size(), unit.models.size())):
        if unit.models[i].alive:
            unit.models[i]["position"] = {
                "x": positions[i].x if positions[i] is Vector2 else positions[i][0],
                "y": positions[i].y if positions[i] is Vector2 else positions[i][1]
            }

    # Mark as disembarked this phase
    if not unit.has("flags"):
        unit["flags"] = {}
    unit.flags["disembarked_this_phase"] = true

    # Check if transport moved (restrict unit movement)
    if transport.get("flags", {}).get("moved", false):
        unit.flags["cannot_move"] = true

    # Update GameState
    GameState.state.units[unit_id] = unit
    GameState.state.units[transport_id] = transport

    emit_signal("disembark_completed", unit_id)
    print("Unit %s disembarked from transport %s" % [unit_id, transport_id])
```

**File**: `40k/phases/MovementPhase.gd` (Add transport action handlers)

```gdscript
# In validate_action() - ADD:
"EMBARK_UNIT":
    return _validate_embark_unit(action)

# In process_action() - ADD:
"EMBARK_UNIT":
    return _process_embark_unit(action)

# NEW: Validate embark
func _validate_embark_unit(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var transport_id = action.get("payload", {}).get("transport_id", "")

    if unit_id == "" or transport_id == "":
        return {"valid": false, "errors": ["Missing unit_id or transport_id"]}

    # Use TransportManager's validation
    var validation = TransportManager.can_embark(unit_id, transport_id)
    if not validation.valid:
        return {"valid": false, "errors": [validation.reason]}

    return {"valid": true, "errors": []}

# NEW: Process embark
func _process_embark_unit(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var transport_id = action.get("payload", {}).get("transport_id", "")

    # Call TransportManager's local embark method
    TransportManager._embark_unit_local(unit_id, transport_id)

    var unit = get_unit(unit_id)
    log_phase_message("%s embarked in transport %s" % [
        unit.meta.get("name", unit_id),
        transport_id
    ])

    # Return state changes for GameState
    return create_result(true, [
        {
            "op": "set",
            "path": "units.%s.embarked_in" % unit_id,
            "value": transport_id
        },
        {
            "op": "add",
            "path": "units.%s.transport_data.embarked_units" % transport_id,
            "value": unit_id
        }
    ])
```

**File**: `40k/autoloads/NetworkManager.gd` (Add to phase action validation)

```gdscript
# In _validate_phase_action_type(), add to MOVEMENT phase:
GameStateData.Phase.MOVEMENT: [
    "BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK",
    "STAGE_MODEL_MOVE", "CONFIRM_UNIT_MOVE", "RESET_UNIT_MOVE",
    "REMAIN_STATIONARY", "DISEMBARK_UNIT", "CONFIRM_DISEMBARK",
    "EMBARK_UNIT",  # ← ADD THIS
    "END_MOVEMENT"
],
```

**Key Changes**:
1. **TransportManager checks NetworkManager**: Routes to actions if networked
2. **Local methods**: `_embark_unit_local()` and `_disembark_unit_local()` for offline/processing
3. **Phase handlers**: MovementPhase validates and processes transport actions
4. **State changes**: Embark/disembark return proper state change arrays
5. **Signals maintained**: All existing signals still fire

---

## Summary of Fixes

| Issue | Status | Impact | Complexity |
|-------|--------|--------|------------|
| 1. RNG Integration | ✅ Fixed | CRITICAL (immediate desync) | Medium |
| 2. Security Validations | ✅ Fixed | CRITICAL (exploitable) | Medium |
| 3. Input Lag | ✅ Fixed | HIGH (poor UX) | High |
| 4. Checksum Design | ✅ Fixed | HIGH (false desyncs) | Medium |
| 5. Transport System | ✅ Fixed | CRITICAL (desync in transport games) | High |

**Total Implementation Impact**: +3-4 days to original estimate

**New Confidence Score**: 9/10 (was 8/10)
- Fixed all critical issues
- Security hardened
- Better UX with prediction
- Deterministic checksum

**Updated Timeline**:
- **Solo Developer**: 13-14 weeks (was 12)
- **Team of 3**: 7 weeks (was 6)

---

## Integration Order

Apply fixes in this sequence:

1. **Fix 4 (Checksum)** - Foundation for all validation
2. **Fix 1 (RNG)** - Required before any dice rolls
3. **Fix 2 (Security)** - Prevents exploitation
4. **Fix 5 (Transport)** - Synchronizes critical system
5. **Fix 3 (Prediction)** - UX improvement (can be last)

---

## Updated Validation Gate

```bash
# Test all fixes
export PATH="$HOME/bin:$PATH"

# 1. Test deterministic RNG
godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_deterministic_rng.gd -gexit

# 2. Test security validations
godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_network_security.gd -gexit

# 3. Test optimistic prediction
godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_optimistic_prediction.gd -gexit

# 4. Test checksum determinism
godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_state_checksum.gd -gexit

# 5. Test transport synchronization
godot --headless -s res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_transport_sync.gd -gexit

# Integration test with all fixes
godot --headless -s res://tests/integration/test_multiplayer_complete.gd
```

All tests must pass before multiplayer is production-ready.