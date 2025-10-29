# Product Requirements Document: Action Simulation System
## For Multiplayer Integration Testing

**Version:** 1.0
**Date:** 2025-10-28
**Status:** 📋 Planning
**Owner:** Testing Infrastructure
**Priority:** HIGH (Blocking 51/53 tests)

---

## Executive Summary

The Action Simulation System enables automated integration tests to trigger game actions in running Godot instances. This system is critical for testing multiplayer functionality, as it allows tests to simulate player actions (deploy units, move units, attack, etc.) and verify that these actions synchronize correctly across multiple game instances.

**Problem:** Tests can launch game instances and verify connection, but cannot trigger actual gameplay actions to test synchronization and game logic.

**Solution:** A file-based command queue system where tests write command files, game instances execute them, and results are written back for verification.

**Impact:** Unblocks 51/53 tests (96% of test suite), enabling comprehensive multiplayer testing.

---

## Table of Contents

1. [Background & Context](#background--context)
2. [Goals & Non-Goals](#goals--non-goals)
3. [User Stories](#user-stories)
4. [Architecture](#architecture)
5. [Command Format Specification](#command-format-specification)
6. [Supported Actions](#supported-actions)
7. [Implementation Plan](#implementation-plan)
8. [Success Metrics](#success-metrics)
9. [Security Considerations](#security-considerations)
10. [Future Enhancements](#future-enhancements)

---

## Background & Context

### Current State

The multiplayer testing framework can:
- ✅ Launch separate Godot instances (host and client)
- ✅ Establish network connections
- ✅ Monitor logs for state changes
- ✅ Verify game phase synchronization

But it **cannot**:
- ❌ Trigger player actions (deploy, move, shoot, etc.)
- ❌ Simulate UI interactions programmatically
- ❌ Verify action results across instances

### Problem Statement

To test multiplayer synchronization, we need tests to:
1. Command the host to "deploy unit X at position Y"
2. Wait for action to complete
3. Verify the client sees the same unit at the same position

Currently, all tests that need to simulate actions are marked as `gut.pending()` because this capability doesn't exist.

### Why File-Based Commands?

**Alternatives Considered:**
1. **Network API**: Requires implementing test-specific network protocol
2. **Direct Method Calls**: Requires tight coupling between test and game
3. **File-Based Queue**: Simple, debuggable, no protocol needed

**File-based chosen because:**
- ✅ Simple to implement (no network protocol)
- ✅ Easy to debug (can inspect command files)
- ✅ Works with existing process isolation
- ✅ No security concerns (test-only feature)
- ✅ Can be disabled in production builds

---

## Goals & Non-Goals

### Goals

**Primary:**
1. ✅ Enable tests to trigger any game action programmatically
2. ✅ Provide reliable action execution confirmation
3. ✅ Support both host and client actions independently
4. ✅ Handle action success and failure states
5. ✅ Integrate seamlessly with existing test framework

**Secondary:**
1. ✅ Provide clear error messages for debugging
2. ✅ Support action queuing for complex sequences
3. ✅ Minimal performance impact on game
4. ✅ Easy to extend with new actions

### Non-Goals

**Explicitly NOT in scope:**
1. ❌ Production game communication system
2. ❌ UI automation beyond test mode
3. ❌ Performance testing tools
4. ❌ AI player simulation
5. ❌ Replay/recording system
6. ❌ Network latency simulation

---

## User Stories

### As a Test Developer...

**Story 1: Basic Action Execution**
```
Given I have a running game instance
When I execute simulate_host_action("deploy_unit:unit_p1_1:position:5,5")
Then the unit should deploy at position (5,5)
And the result should indicate success
And I should receive confirmation within 2 seconds
```

**Story 2: Action Failure Handling**
```
Given I have a running game instance
When I execute simulate_host_action("deploy_unit:unit_p1_1:position:99,99")
Then the action should be rejected (out of bounds)
And the result should indicate failure
And I should receive an error message explaining why
```

**Story 3: Multi-Instance Actions**
```
Given I have host and client instances
When I execute simulate_host_action("deploy_unit:unit_p1_1:position:5,5")
And I execute simulate_client_action("deploy_unit:unit_p2_1:position:5,52")
Then both units should deploy on their respective instances
And both instances should see both units
```

**Story 4: Action Sequences**
```
Given I have a running game instance
When I execute a sequence of actions:
  - deploy_unit:unit_p1_1:position:5,5
  - undo_deployment
  - deploy_unit:unit_p1_1:position:10,5
Then each action should execute in order
And I should receive results for each action
```

**Story 5: Debugging Failed Tests**
```
Given a test fails due to action execution
When I inspect the command/result files
Then I should see:
  - The exact command that was sent
  - The timestamp of execution
  - The result (success/failure)
  - Any error messages
  - The game state at time of execution
```

---

## Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Test Process                          │
│  ┌────────────────────────────────────────────────────┐     │
│  │  MultiplayerIntegrationTest                        │     │
│  │                                                     │     │
│  │  simulate_host_action("deploy_unit:...")          │     │
│  │         │                                          │     │
│  │         ├─> Write command file                     │     │
│  │         ├─> Wait for result file                   │     │
│  │         └─> Return result                          │     │
│  └────────────────────────────────────────────────────┘     │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    │ File System (user://test_commands/)
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                   Host Game Instance                         │
│  ┌────────────────────────────────────────────────────┐     │
│  │  TestModeHandler (Autoload)                        │     │
│  │                                                     │     │
│  │  _process(delta):                                  │     │
│  │    ├─> Check for command files                     │     │
│  │    ├─> Parse command                               │     │
│  │    ├─> Execute action                              │     │
│  │    ├─> Write result file                           │     │
│  │    └─> Delete command file                         │     │
│  └────────────────────────────────────────────────────┘     │
│                                                               │
│  ┌────────────────────────────────────────────────────┐     │
│  │  GameManager / PhaseManager                        │     │
│  │  (Actual game logic)                               │     │
│  └────────────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
user://test_commands/
├── commands/
│   ├── host_12345_cmd_001.json     # Command files (input)
│   ├── client_12346_cmd_001.json
│   └── ...
├── results/
│   ├── host_12345_cmd_001.json     # Result files (output)
│   ├── client_12346_cmd_001.json
│   └── ...
└── .gitignore                       # Ignore test command files
```

### File Naming Convention

**Command Files:**
```
{role}_{process_id}_cmd_{sequence}.json

Examples:
- host_12345_cmd_001.json
- client_12346_cmd_001.json
- host_12345_cmd_002.json
```

**Result Files:**
```
{role}_{process_id}_cmd_{sequence}_result.json

Examples:
- host_12345_cmd_001_result.json
- client_12346_cmd_001_result.json
```

### Data Flow

1. **Test writes command:**
   ```
   Test → user://test_commands/commands/host_12345_cmd_001.json
   ```

2. **Game detects command:**
   ```
   TestModeHandler._process() → Polls commands/ directory
   ```

3. **Game executes command:**
   ```
   TestModeHandler → Parse JSON → Execute action → Capture result
   ```

4. **Game writes result:**
   ```
   TestModeHandler → user://test_commands/results/host_12345_cmd_001_result.json
   ```

5. **Test reads result:**
   ```
   Test polls for result file → Parse JSON → Return to test
   ```

6. **Cleanup:**
   ```
   Test deletes command file
   Test deletes result file (after reading)
   ```

---

## Command Format Specification

### Command File Format

```json
{
  "version": "1.0",
  "timestamp": 1730123456789,
  "sequence": 1,
  "timeout_ms": 5000,
  "command": {
    "action": "deploy_unit",
    "parameters": {
      "unit_id": "unit_p1_1",
      "position": {"x": 5.0, "y": 5.0}
    }
  }
}
```

**Fields:**
- `version` (string): Command format version (for future compatibility)
- `timestamp` (int): Unix timestamp in milliseconds when command created
- `sequence` (int): Monotonic sequence number for this instance
- `timeout_ms` (int): Max time to wait for command execution (default: 5000)
- `command` (object): The actual command to execute
  - `action` (string): Action type (see Supported Actions)
  - `parameters` (object): Action-specific parameters

### Result File Format

```json
{
  "version": "1.0",
  "timestamp": 1730123456890,
  "sequence": 1,
  "execution_time_ms": 45,
  "result": {
    "success": true,
    "message": "Unit deployed successfully",
    "data": {
      "unit_id": "unit_p1_1",
      "position": {"x": 5.0, "y": 5.0},
      "deployed": true
    }
  }
}
```

**Fields:**
- `version` (string): Result format version
- `timestamp` (int): Unix timestamp when result written
- `sequence` (int): Matches command sequence
- `execution_time_ms` (int): How long command took to execute
- `result` (object): Execution result
  - `success` (bool): Whether command succeeded
  - `message` (string): Human-readable result message
  - `data` (object, optional): Action-specific result data
  - `error` (string, optional): Error details if success=false

### Error Result Format

```json
{
  "version": "1.0",
  "timestamp": 1730123456890,
  "sequence": 1,
  "execution_time_ms": 12,
  "result": {
    "success": false,
    "message": "Deployment failed: position out of bounds",
    "error": "POSITION_OUT_OF_BOUNDS",
    "data": {
      "unit_id": "unit_p1_1",
      "attempted_position": {"x": 99.0, "y": 99.0},
      "deployment_zone": {
        "min": {"x": 0.0, "y": 0.0},
        "max": {"x": 44.0, "y": 12.0}
      }
    }
  }
}
```

---

## Supported Actions

### Phase 1: Deployment Actions (MVP)

#### 1. deploy_unit

**Purpose:** Deploy a unit to the board

**Command:**
```json
{
  "action": "deploy_unit",
  "parameters": {
    "unit_id": "unit_p1_1",
    "position": {"x": 5.0, "y": 5.0}
  }
}
```

**Success Result:**
```json
{
  "success": true,
  "message": "Unit deployed successfully",
  "data": {
    "unit_id": "unit_p1_1",
    "position": {"x": 5.0, "y": 5.0},
    "model_count": 5,
    "model_positions": [
      {"x": 5.0, "y": 5.0},
      {"x": 6.0, "y": 5.0},
      ...
    ]
  }
}
```

**Error Codes:**
- `UNIT_NOT_FOUND`: Unit ID doesn't exist
- `UNIT_ALREADY_DEPLOYED`: Unit already deployed
- `POSITION_OUT_OF_BOUNDS`: Position outside deployment zone
- `POSITION_BLOCKED_BY_TERRAIN`: Terrain at position
- `WRONG_TURN`: Not player's turn
- `INVALID_PHASE`: Not in deployment phase

#### 2. undo_deployment

**Purpose:** Undo last deployment action

**Command:**
```json
{
  "action": "undo_deployment",
  "parameters": {}
}
```

**Success Result:**
```json
{
  "success": true,
  "message": "Deployment undone",
  "data": {
    "undone_unit_id": "unit_p1_1",
    "previous_position": {"x": 5.0, "y": 5.0}
  }
}
```

**Error Codes:**
- `NO_ACTION_TO_UNDO`: No previous deployment to undo
- `WRONG_TURN`: Not player's turn

#### 3. complete_deployment

**Purpose:** Mark player's deployment as complete

**Command:**
```json
{
  "action": "complete_deployment",
  "parameters": {
    "player_id": 1
  }
}
```

**Success Result:**
```json
{
  "success": true,
  "message": "Player 1 deployment complete",
  "data": {
    "player_id": 1,
    "deployment_complete": true,
    "waiting_for_opponent": true,
    "phase_will_transition": false
  }
}
```

#### 4. get_game_state

**Purpose:** Query current game state (for verification)

**Command:**
```json
{
  "action": "get_game_state",
  "parameters": {}
}
```

**Success Result:**
```json
{
  "success": true,
  "message": "Game state retrieved",
  "data": {
    "current_phase": "Deployment",
    "current_turn": 1,
    "player_turn": 1,
    "units": {
      "player_1": [
        {
          "id": "unit_p1_1",
          "deployed": true,
          "position": {"x": 5.0, "y": 5.0}
        }
      ],
      "player_2": [...]
    }
  }
}
```

### Phase 2: Movement Actions (Future)

```json
{
  "action": "move_unit",
  "parameters": {
    "unit_id": "unit_p1_1",
    "destination": {"x": 15.0, "y": 10.0},
    "move_type": "normal"  // "normal", "advance", "fall_back"
  }
}
```

### Phase 3: Shooting Actions (Future)

```json
{
  "action": "shoot",
  "parameters": {
    "attacker_id": "unit_p1_1",
    "target_id": "unit_p2_1",
    "weapon": "bolt_rifle"
  }
}
```

### Phase 4: Charge Actions (Future)

```json
{
  "action": "declare_charge",
  "parameters": {
    "unit_id": "unit_p1_1",
    "target_ids": ["unit_p2_1"]
  }
}
```

### Phase 5: Fight Actions (Future)

```json
{
  "action": "fight",
  "parameters": {
    "attacker_id": "unit_p1_1",
    "target_id": "unit_p2_1"
  }
}
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (4-6 hours)

**Goal:** Basic command/result system working for deployment tests

**Tasks:**
1. **TestModeHandler Enhancements** (2 hours)
   - Add command file polling in `_process()`
   - Implement command file parsing
   - Implement result file writing
   - Add command execution dispatcher

2. **MultiplayerIntegrationTest Helpers** (1 hour)
   - Implement `simulate_host_action()`
   - Implement `simulate_client_action()`
   - Add result polling logic
   - Add timeout handling

3. **Deployment Action Handlers** (2 hours)
   - Implement `deploy_unit` handler
   - Implement `undo_deployment` handler
   - Implement `complete_deployment` handler
   - Implement `get_game_state` handler

4. **Testing & Debugging** (1 hour)
   - Test each action type
   - Verify error handling
   - Test timeout scenarios
   - Fix any issues

**Deliverable:** Deployment tests unblocked and passing

### Phase 2: Movement Actions (2-3 hours)

**Goal:** Support movement phase testing

**Tasks:**
1. Implement `move_unit` handler
2. Implement `undo_move` handler
3. Implement movement validation
4. Test movement actions

**Deliverable:** Movement tests unblocked

### Phase 3: Combat Actions (4-6 hours)

**Goal:** Support shooting, charge, and fight phases

**Tasks:**
1. Implement shooting action handlers
2. Implement charge action handlers
3. Implement fight action handlers
4. Complex action sequences

**Deliverable:** All combat tests unblocked

### Phase 4: Polish & Optimization (2-3 hours)

**Goal:** Production-ready quality

**Tasks:**
1. Add comprehensive error messages
2. Optimize file polling (use file system notifications if available)
3. Add action execution metrics
4. Documentation and examples

**Deliverable:** Robust, maintainable system

---

## Technical Specification

### TestModeHandler Implementation

```gdscript
# In autoloads/TestModeHandler.gd

var _command_dir: String = "user://test_commands/commands/"
var _result_dir: String = "user://test_commands/results/"
var _check_interval: float = 0.1  # Check every 100ms
var _time_since_check: float = 0.0
var _sequence_counter: int = 0

func _ready():
    # Existing code...

    # Setup command directories
    if is_test_mode:
        _setup_command_directories()

func _setup_command_directories():
    var dir = DirAccess.open("user://")
    if not dir.dir_exists("test_commands"):
        dir.make_dir("test_commands")
    if not dir.dir_exists("test_commands/commands"):
        dir.make_dir("test_commands/commands")
    if not dir.dir_exists("test_commands/results"):
        dir.make_dir("test_commands/results")

    print("TestModeHandler: Command directories ready")

func _process(delta: float):
    if not is_test_mode:
        return

    _time_since_check += delta
    if _time_since_check >= _check_interval:
        _time_since_check = 0.0
        _check_for_commands()

func _check_for_commands():
    var dir = DirAccess.open(_command_dir)
    if not dir:
        return

    dir.list_dir_begin()
    var file_name = dir.get_next()

    while file_name != "":
        if file_name.ends_with(".json"):
            _execute_command_file(file_name)
        file_name = dir.get_next()

func _execute_command_file(file_name: String):
    var file_path = _command_dir + file_name
    var file = FileAccess.open(file_path, FileAccess.READ)

    if not file:
        push_error("TestModeHandler: Failed to open command file: " + file_name)
        return

    var json_string = file.get_as_text()
    file.close()

    var json = JSON.new()
    var error = json.parse(json_string)

    if error != OK:
        push_error("TestModeHandler: Failed to parse command JSON: " + file_name)
        return

    var command_data = json.data
    var start_time = Time.get_ticks_msec()

    # Execute the command
    var result = _execute_command(command_data["command"])

    var execution_time = Time.get_ticks_msec() - start_time

    # Write result
    _write_result(file_name, command_data["sequence"], result, execution_time)

    # Delete command file
    DirAccess.remove_absolute(file_path)

func _execute_command(command: Dictionary) -> Dictionary:
    var action = command["action"]
    var params = command.get("parameters", {})

    match action:
        "deploy_unit":
            return _handle_deploy_unit(params)
        "undo_deployment":
            return _handle_undo_deployment(params)
        "complete_deployment":
            return _handle_complete_deployment(params)
        "get_game_state":
            return _handle_get_game_state(params)
        _:
            return {
                "success": false,
                "message": "Unknown action: " + action,
                "error": "UNKNOWN_ACTION"
            }

func _handle_deploy_unit(params: Dictionary) -> Dictionary:
    # TODO: Implement actual deployment logic
    # For now, return success
    return {
        "success": true,
        "message": "Unit deployed successfully",
        "data": {
            "unit_id": params.get("unit_id"),
            "position": params.get("position")
        }
    }

func _write_result(command_file: String, sequence: int, result: Dictionary, execution_time: int):
    var result_file_name = command_file.replace(".json", "_result.json")
    var result_path = _result_dir + result_file_name

    var result_data = {
        "version": "1.0",
        "timestamp": Time.get_ticks_msec(),
        "sequence": sequence,
        "execution_time_ms": execution_time,
        "result": result
    }

    var file = FileAccess.open(result_path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(result_data, "\t"))
        file.close()
```

### MultiplayerIntegrationTest Implementation

```gdscript
# In tests/helpers/MultiplayerIntegrationTest.gd

func simulate_host_action(action: String, params: Dictionary = {}) -> Dictionary:
    return await _simulate_action(host_instance, action, params)

func simulate_client_action(action: String, params: Dictionary = {}) -> Dictionary:
    return await _simulate_action(client_instance, action, params)

func _simulate_action(instance: GameInstance, action: String, params: Dictionary) -> Dictionary:
    # Generate command file
    var sequence = instance._next_sequence()
    var command_file = "host_%d_cmd_%03d.json" % [instance.process_id, sequence]

    var command_data = {
        "version": "1.0",
        "timestamp": Time.get_ticks_msec(),
        "sequence": sequence,
        "timeout_ms": 5000,
        "command": {
            "action": action,
            "parameters": params
        }
    }

    # Write command file
    var command_path = "user://test_commands/commands/" + command_file
    var file = FileAccess.open(command_path, FileAccess.WRITE)
    file.store_string(JSON.stringify(command_data, "\t"))
    file.close()

    # Wait for result
    var result = await _wait_for_result(command_file, 5.0)

    return result

func _wait_for_result(command_file: String, timeout: float) -> Dictionary:
    var result_file = command_file.replace(".json", "_result.json")
    var result_path = "user://test_commands/results/" + result_file
    var start_time = Time.get_ticks_msec() / 1000.0

    while (Time.get_ticks_msec() / 1000.0) - start_time < timeout:
        if FileAccess.file_exists(result_path):
            var file = FileAccess.open(result_path, FileAccess.READ)
            var json_string = file.get_as_text()
            file.close()

            var json = JSON.new()
            json.parse(json_string)

            # Delete result file
            DirAccess.remove_absolute(result_path)

            return json.data.get("result", {})

        await wait_for_seconds(0.1)

    return {
        "success": false,
        "message": "Command timeout",
        "error": "TIMEOUT"
    }
```

---

## Success Metrics

### Functionality Metrics
- ✅ All 4 deployment actions working
- ✅ Success/failure states correctly reported
- ✅ Error messages clear and actionable
- ✅ Timeout handling works correctly

### Performance Metrics
- ⏱️ Command execution < 100ms (95th percentile)
- ⏱️ Result availability < 200ms (95th percentile)
- ⏱️ File polling overhead < 1% CPU
- ⏱️ No memory leaks after 1000 commands

### Quality Metrics
- ✅ 0 false positives (incorrect success)
- ✅ 0 false negatives (incorrect failure)
- ✅ 100% of errors have clear messages
- ✅ Command/result files cleaned up properly

### Test Coverage
- ✅ 51/53 tests unblocked (96%)
- ✅ All deployment tests passing
- ✅ Basic movement tests passing (Phase 2)

---

## Security Considerations

### Test-Only Feature

**Critical:** This system MUST NEVER be enabled in production builds.

**Safeguards:**
1. Only active when `--test-mode` flag present
2. Disabled when `FeatureFlags.TESTING_ENABLED == false`
3. All command handling in `if is_test_mode:` blocks
4. Consider compile-time flag to remove code entirely from release builds

### File System Access

**Risks:**
- Tests could read/write any `user://` files
- Command files could contain malicious data

**Mitigations:**
- Commands isolated to `user://test_commands/` directory
- JSON parsing has error handling
- Invalid commands logged but don't crash game
- File paths validated (no directory traversal)

### Resource Exhaustion

**Risks:**
- Tests could create thousands of command files
- Memory leaks from unprocessed commands

**Mitigations:**
- Command directory cleaned on test startup
- Stale commands (> 60s old) automatically deleted
- Maximum command file size limit (10KB)
- File count limit in command directory (100 files)

---

## Future Enhancements

### Phase 2: Network-Based Commands (Optional)

If file-based proves limiting, consider HTTP REST API:

```
POST http://localhost:9999/test/command
{
  "action": "deploy_unit",
  "parameters": {...}
}

Response:
{
  "success": true,
  "data": {...}
}
```

**Pros:**
- Faster (no file I/O)
- Real-time responses
- Better for CI/CD

**Cons:**
- More complex implementation
- Network port management
- Security concerns

### Phase 3: Action Recording/Replay

Record sequences of actions for:
- Regression testing
- Bug reproduction
- Performance profiling

### Phase 4: Visual Debugging

- Screenshot capture on action execution
- Action visualization in game
- Timeline view of actions

### Phase 5: Parallel Action Execution

Support multiple commands in flight:
- Batch actions
- Concurrent host/client actions
- Performance optimization

---

## Open Questions

1. **Should we support action batching?**
   - Single command file with multiple actions?
   - Or always one action per file?
   - **Decision:** Start with one action per file (simpler)

2. **How to handle async game actions?**
   - Some actions take multiple frames (animations, etc.)
   - Should result wait for animation complete?
   - **Decision:** Result returns immediately, tests wait for state change

3. **Should commands be queued or rejected if game busy?**
   - If action already in progress, queue or error?
   - **Decision:** Queue with max size of 10

4. **How to handle multiplayer sync delays?**
   - Action completes on host, when is it visible on client?
   - **Decision:** Tests use `wait_for_seconds()` or poll game state

5. **Should we support undo for all actions?**
   - Deployment has undo, what about movement/shooting?
   - **Decision:** Phase 1 only deployment, evaluate later

---

## Appendix A: Example Test Usage

```gdscript
func test_deployment_single_unit():
    # Launch and connect
    await launch_host_and_client()
    await wait_for_connection()
    await wait_for_seconds(3.0)

    # Deploy unit
    var result = await simulate_host_action("deploy_unit", {
        "unit_id": "unit_p1_1",
        "position": {"x": 5.0, "y": 5.0}
    })

    # Verify success
    assert_true(result["success"], "Deployment should succeed")
    assert_eq(result["data"]["unit_id"], "unit_p1_1", "Correct unit deployed")

    # Verify sync
    await wait_for_seconds(1.0)
    var host_state = host_instance.get_game_state()
    var client_state = client_instance.get_game_state()

    assert_unit_deployed(host_state, "unit_p1_1", Vector2(5, 5))
    assert_unit_deployed(client_state, "unit_p1_1", Vector2(5, 5))
```

---

## Appendix B: Error Code Reference

| Error Code | Description | Typical Cause |
|------------|-------------|---------------|
| `UNKNOWN_ACTION` | Action not recognized | Typo in action name |
| `UNIT_NOT_FOUND` | Unit ID doesn't exist | Invalid unit_id |
| `UNIT_ALREADY_DEPLOYED` | Unit already on board | Deploying twice |
| `POSITION_OUT_OF_BOUNDS` | Position outside map | Invalid coordinates |
| `POSITION_BLOCKED_BY_TERRAIN` | Terrain at position | Collision detection |
| `WRONG_TURN` | Not player's turn | Turn order violation |
| `INVALID_PHASE` | Wrong game phase | Phase check failed |
| `NO_ACTION_TO_UNDO` | Nothing to undo | Undo without action |
| `TIMEOUT` | Command took too long | System overload or hang |
| `PARSE_ERROR` | Invalid JSON | Malformed command file |

---

## Approval & Sign-Off

**Approved By:**
- [ ] Test Infrastructure Lead
- [ ] Game Systems Lead
- [ ] Technical Lead

**Implementation Start Date:** TBD
**Target Completion Date:** TBD
**Estimated Effort:** 4-6 hours (Phase 1)

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-28 | Claude Code | Initial PRD created |

---

**Next Steps:**
1. Review and approve PRD
2. Begin Phase 1 implementation
3. Test with deployment phase
4. Iterate based on findings