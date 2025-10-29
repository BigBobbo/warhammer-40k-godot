# Multiplayer Integration Test Guide

**Last Updated:** 2025-10-29
**Test Suite:** Deployment Phase Multiplayer Tests
**Location:** `/tests/integration/test_multiplayer_deployment.gd`

## Overview

This guide documents the multiplayer integration tests for the Warhammer 40k game. These tests verify that the multiplayer system works correctly during deployment and subsequent game phases.

---

## Prerequisites

1. **Godot Engine** must be in your PATH
   ```bash
   export PATH="$HOME/bin:$PATH"
   ```

2. **Test Save Files** must exist in `tests/saves/`:
   - `deployment_start.w40ksave`
   - `deployment_player1_turn.w40ksave`
   - `deployment_player2_turn.w40ksave`
   - `deployment_nearly_complete.w40ksave`
   - `deployment_with_terrain.w40ksave`

3. **Network Ports** 7777-8999 should be available for testing

---

## Running Tests

### Run All Tests in File
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gfile=test_multiplayer_deployment.gd \
    -gexit
```

### Run Single Test
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gfile=test_multiplayer_deployment.gd \
    -gtest=test_basic_multiplayer_connection \
    -gexit
```

### Available Test Names
- `test_basic_multiplayer_connection`
- `test_deployment_save_load`
- `test_deployment_single_unit`
- `test_deployment_outside_zone`
- `test_deployment_alternating_turns`
- `test_deployment_wrong_turn`
- `test_deployment_blocked_by_terrain`
- `test_deployment_unit_coherency`
- `test_deployment_completion_both_players`
- `test_deployment_undo_action`

---

## Test Descriptions

### 1. test_basic_multiplayer_connection

**Purpose:** Verify basic multiplayer connection without game actions

**What It Does:**
1. Launches a host instance on port 7777
2. Launches a client instance
3. Client connects to host
4. Verifies connection is stable

**Expected GUI Behavior:**
- Two game windows appear (labeled "Host" and "Client")
- Both windows show the main menu, then multiplayer lobby
- Host creates a server
- Client joins automatically
- Both enter deployment phase

**Expected Console Output:**
```
[TEST] test_basic_multiplayer_connection
[Test] Launching host and client instances...
[Test] Host instance launched successfully on port 7777
[Test] Client instance launched successfully
[Test] Waiting for client to connect to host...
[Test] Connection verified - action simulation working!
[TEST] PASSED: Basic connection established
```

**Success Criteria:**
- Both instances launch without errors
- Client connects to host within 15 seconds
- `get_game_state` action succeeds on both instances

---

### 2. test_deployment_save_load

**Purpose:** Verify loading deployment phase save file in multiplayer

**What It Does:**
1. Launches host and client
2. Waits for connection
3. Game auto-starts via TestModeHandler
4. Verifies both clients enter deployment phase
5. Checks phase synchronization

**Expected GUI Behavior:**
- Both windows load into deployment phase
- Game board appears with deployment zones visible
- Units are visible on both clients

**Expected Console Output:**
```
[TEST] test_deployment_save_load
TestModeHandler: Starting game...
TestModeHandler: Game successfully in Deployment phase
[TEST] PASSED: Deployment save loaded and synced
```

**Success Criteria:**
- Both instances report "Deployment" as current phase
- Game states are synchronized

---

### 3. test_deployment_single_unit

**Purpose:** Deploy a single unit and verify it appears on both clients

**What It Does:**
1. Launches host and client instances
2. Loads `deployment_start.w40ksave`
3. **Dynamically queries available units** from GameState
4. Deploys the first available Player 1 unit at position (5, 5)
5. Verifies deployment succeeded
6. Checks unit appears on both clients

**Expected GUI Behavior:**
- Save file loads on both instances
- A unit appears at coordinates (5, 5) on the game board
- Unit is visible on BOTH host and client windows
- Unit placement is synchronized

**Expected Console Output:**
```
[TEST] test_deployment_single_unit
[TEST] Loading save file: deployment_start
[TEST] Save loaded: 6 units available
[TEST] Player 1 undeployed units: ["unit_p1_blade_champion", "unit_p1_custodian_guard", "unit_p1_witchseekers"]
[TEST] Using unit: unit_p1_blade_champion
TestModeHandler: Handling deploy_unit action
TestModeHandler: Unit deployed successfully
[TEST] Host units count: 6
[TEST] Client units count: 6
[TEST] PASSED: Unit deployment successful
```

**Success Criteria:**
- Save file loads successfully
- At least one Player 1 unit is available for deployment
- `deploy_unit` action returns success
- Both clients show the same unit count

**Key Implementation Detail:**
This test uses **dynamic unit discovery** rather than hardcoded IDs:
```gdscript
# Get available units dynamically
var units_result = await simulate_host_action("get_available_units", {})
var p1_units = units_result.get("data", {}).get("player_1_undeployed", [])
var test_unit_id = p1_units[0]  # Use first available

# Deploy using discovered unit ID
var result = await simulate_host_action("deploy_unit", {
    "unit_id": test_unit_id,
    "position": {"x": 5.0, "y": 5.0}
})
```

---

### 4. test_deployment_outside_zone

**Purpose:** Verify deployment is rejected outside valid zones

**What It Does:**
1. Launches host and client
2. Queries available units dynamically
3. Attempts to deploy unit at (22, 30) - middle of board
4. Verifies deployment is rejected

**Expected GUI Behavior:**
- No unit appears at the invalid position
- Error message may appear in game UI
- Game state remains unchanged

**Expected Console Output:**
```
[TEST] test_deployment_outside_zone
ERROR: Deployment outside valid zone
[TEST] Deployment correctly rejected: Position (22.0, 30.0) outside deployment zone
```

**Success Criteria:**
- `deploy_unit` action returns `success: false`
- Error message indicates invalid position
- No unit is deployed

---

### 5. test_deployment_alternating_turns

**Purpose:** Verify turn alternates between players during deployment

**What It Does:**
1. Launches multiplayer game
2. Checks initial turn (should be Player 1)
3. Player 1 deploys a unit
4. Checks if turn switched to Player 2

**Expected GUI Behavior:**
- Turn indicator shows Player 1 initially
- After deployment, turn indicator shows Player 2
- Only current player can perform actions

**Expected Console Output:**
```
[TEST] test_deployment_alternating_turns
[TEST] Initial turn: Player 1
[TEST] Turn after deployment: Player 2
[TEST] Turn alternation test completed
```

**Success Criteria:**
- Initial turn is Player 1
- Turn changes after successful deployment
- Turn state is synchronized across clients

---

### 6. test_deployment_wrong_turn

**Purpose:** Verify player cannot deploy when it's not their turn

**What It Does:**
1. Loads save file with Player 1's turn active
2. Client (Player 2) attempts to deploy a unit
3. Verifies action is rejected

**Expected GUI Behavior:**
- Client window shows it's Player 1's turn
- Attempting to deploy as Player 2 shows error
- No unit is deployed

**Expected Console Output:**
```
[TEST] test_deployment_wrong_turn
[TEST] Current turn: Player 1
ERROR: Not your turn
[TEST] Wrong turn deployment result: success=false message=Not Player 2's turn
```

**Success Criteria:**
- Action returns `success: false`
- Error indicates turn violation
- Game state unchanged

---

### 7. test_deployment_blocked_by_terrain

**Purpose:** Verify units cannot deploy on impassable terrain

**What It Does:**
1. Loads `deployment_with_terrain.w40ksave`
2. Attempts to deploy unit on terrain at (8, 15)
3. Verifies deployment is rejected

**Expected GUI Behavior:**
- Terrain pieces visible on game board
- Unit placement attempt shows error
- No unit appears on terrain

**Expected Console Output:**
```
[TEST] test_deployment_blocked_by_terrain
ERROR: Cannot deploy on impassable terrain
[TEST] Terrain blocking result: success=false message=Position blocked by terrain
```

**Success Criteria:**
- Deployment returns `success: false`
- Error indicates terrain collision
- Unit is not placed

---

### 8. test_deployment_unit_coherency

**Purpose:** Verify multi-model units maintain coherency

**What It Does:**
1. Deploys a 10-model Tactical Squad
2. Checks all models are within 2" of each other
3. Verifies coherency rules are enforced

**Expected GUI Behavior:**
- All 10 models appear in formation
- Models are clustered within 2" of each other
- Formation looks cohesive

**Expected Console Output:**
```
[TEST] test_deployment_unit_coherency
[TEST] Multi-model deployment result: success=true
[TEST] Unit coherency test completed
```

**Success Criteria:**
- All models deploy successfully
- Maximum distance between any two models ≤ 2"
- Coherency maintained during deployment

---

### 9. test_deployment_completion_both_players

**Purpose:** Verify deployment completes only when both players finish

**What It Does:**
1. Loads `deployment_nearly_complete.w40ksave`
2. Player 1 marks deployment complete
3. Verifies still in Deployment phase (waiting for P2)
4. Player 2 marks deployment complete
5. Verifies phase transitions to Movement

**Expected GUI Behavior:**
- After P1 completes: "Waiting for Player 2" message
- After P2 completes: Phase transitions to Movement
- Both clients show Movement phase

**Expected Console Output:**
```
[TEST] test_deployment_completion_both_players
[TEST] Player 1 complete: success=true
[TEST] Phase after P1 complete: Deployment
[TEST] Player 2 complete: success=true
[TEST] Phase after both complete: Movement
[TEST] Deployment completion test finished
```

**Success Criteria:**
- Phase remains Deployment after single player completes
- Phase transitions after both players complete
- Phase transition synchronized across clients

---

### 10. test_deployment_undo_action

**Purpose:** Verify players can undo deployment actions

**What It Does:**
1. Deploys a unit using dynamic unit discovery
2. Calls `undo_deployment` action
3. Verifies unit is removed
4. Checks state is synchronized

**Expected GUI Behavior:**
- Unit appears after deployment
- Unit disappears after undo
- Both clients show unit removed

**Expected Console Output:**
```
[TEST] test_deployment_undo_action
TestModeHandler: Unit deployed successfully
TestModeHandler: Deployment undone
[TEST] Undo result: success=true message=Last action undone
[TEST] Undo test completed
```

**Success Criteria:**
- Deployment succeeds initially
- Undo returns `success: true`
- Unit is removed from game state
- State synchronized across clients

---

## Action Simulation System

Tests use an **action simulation** system to interact with game instances:

### Available Actions

#### `get_game_state`
Returns current game state including phase, turn, and units.

**Parameters:** `{}`

**Returns:**
```json
{
  "success": true,
  "data": {
    "current_phase": "Deployment",
    "current_turn": 1,
    "player_turn": 1,
    "units": {...}
  }
}
```

#### `get_available_units`
Returns units organized by player and deployment status.

**Parameters:** `{}`

**Returns:**
```json
{
  "success": true,
  "data": {
    "player_1_units": ["unit_p1_blade_champion", "unit_p1_custodian_guard"],
    "player_2_units": ["unit_p2_boyz", "unit_p2_warboss"],
    "player_1_undeployed": ["unit_p1_blade_champion"],
    "player_2_undeployed": ["unit_p2_boyz"],
    "total_units": 4
  }
}
```

#### `deploy_unit`
Deploys a unit at specified position.

**Parameters:**
```json
{
  "unit_id": "unit_p1_blade_champion",
  "position": {"x": 5.0, "y": 5.0}
}
```

**Returns:**
```json
{
  "success": true,
  "message": "Unit deployed successfully",
  "data": {
    "unit_id": "unit_p1_blade_champion",
    "position": {"x": 5.0, "y": 5.0}
  }
}
```

#### `load_save`
Loads a saved game file.

**Parameters:**
```json
{
  "save_name": "deployment_start"
}
```

**Returns:**
```json
{
  "success": true,
  "message": "Save file loaded successfully",
  "data": {
    "save_path": "res://tests/saves/deployment_start.w40ksave",
    "unit_count": 6,
    "unit_ids": ["unit_p1_blade_champion", ...]
  }
}
```

#### `undo_deployment`
Undoes the last deployment action.

**Parameters:** `{}`

**Returns:**
```json
{
  "success": true,
  "message": "Last action undone"
}
```

#### `complete_deployment`
Marks a player's deployment as complete.

**Parameters:**
```json
{
  "player_id": 1
}
```

**Returns:**
```json
{
  "success": true,
  "message": "Player 1 deployment complete",
  "data": {
    "player_id": 1,
    "deployment_complete": true
  }
}
```

---

## Troubleshooting

### Issue: "Unit not found: unit_p1_1"

**Cause:** Test is using hardcoded unit IDs that don't match actual game units.

**Solution:** Tests now use dynamic unit discovery. Ensure you're running the latest version:
```gdscript
var units_result = await simulate_host_action("get_available_units", {})
var p1_units = units_result.get("data", {}).get("player_1_undeployed", [])
```

### Issue: "Failed to parse result JSON"

**Cause:** Result file is malformed or being read before fully written.

**Solution:** Retry logic has been implemented (3 attempts with 0.1s delay).

### Issue: "Connection timeout"

**Cause:** Client failed to connect to host within 15 seconds.

**Solution:**
1. Check network ports are available
2. Verify firewall allows local connections
3. Check for conflicting Godot instances

### Issue: "Save file not found"

**Cause:** Test save files missing from `tests/saves/` directory.

**Solution:** Generate test saves using:
```bash
godot --path . -s tests/run_save_generator.gd
```

---

## Recent Fixes (2025-10-29)

### ✅ Dynamic Unit Discovery
Tests now query available units at runtime instead of hardcoding IDs.

**Files Modified:**
- `tests/integration/test_multiplayer_deployment.gd`
- `autoloads/TestModeHandler.gd` (added `get_available_units` action)

### ✅ JSON Parsing Retry Logic
Result file parsing now retries up to 3 times with delays.

**Files Modified:**
- `tests/helpers/MultiplayerIntegrationTest.gd:284-362`

### ✅ Test Infrastructure
Added `add_child_autofree()` helper to prevent memory leaks.

**Files Modified:**
- `tests/helpers/MultiplayerIntegrationTest.gd:440-447`

---

## Expected Test Results

When all tests pass, you should see:

```
=== Test Results ===
Total: 10, Passed: 10, Failed: 0

test_basic_multiplayer_connection .................... PASSED
test_deployment_save_load ............................ PASSED
test_deployment_single_unit .......................... PASSED
test_deployment_outside_zone ......................... PASSED
test_deployment_alternating_turns .................... PASSED
test_deployment_wrong_turn ........................... PASSED
test_deployment_blocked_by_terrain ................... PASSED
test_deployment_unit_coherency ....................... PASSED
test_deployment_completion_both_players .............. PASSED
test_deployment_undo_action .......................... PASSED
```

---

## Debug Logging

Test output is logged to:
```
/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
```

You can also find command/result files in:
```
/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/test_commands/
├── commands/     # Action command files
└── results/      # Action result files
```

---

## Contributing

When adding new tests:

1. Extend `MultiplayerIntegrationTest` class
2. Use action simulation system for game interactions
3. Use dynamic unit discovery for unit-based tests
4. Add comprehensive docstrings
5. Update this guide with new test descriptions

Example template:
```gdscript
func test_my_new_test():
    """
    Test: Brief description

    Setup: Initial conditions
    Action: What the test does
    Verify: Expected outcomes
    """
    print("\n[TEST] test_my_new_test")

    await launch_host_and_client()
    await wait_for_connection()

    # Use action simulation
    var result = await simulate_host_action("my_action", {})
    assert_true(result.get("success", false), "Action should succeed")

    print("[TEST] PASSED: Test description")
```

---

## Test Artifacts System

### Overview

The test framework automatically captures artifacts after each test to help you examine and debug test results:

- **Screenshots** - Visual snapshots of host and client windows
- **Save States** - Complete game state that can be loaded and examined
- **JSON Reports** - Structured test metadata and results

### Artifact Locations

All artifacts are saved to:
```
~/Library/Application Support/Godot/app_userdata/40k/test_artifacts/
├── screenshots/     # PNG screenshots
├── saves/          # Game save states (.w40ksave)
└── reports/        # JSON test reports
```

### Configuration

Configure artifact capture in your test's `before_each()`:

```gdscript
func before_each():
    super.before_each()

    # Screenshots (default: only on failure)
    capture_screenshots_on_failure = true
    capture_screenshots_on_success = false

    # Save states (default: always capture)
    save_state_on_completion = true

    # Optional: Custom test name for artifacts
    current_test_name = "my_custom_test_name"
```

### Using Artifacts

#### Quick Visual Check - Screenshots
```bash
# Open screenshots folder
open ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/screenshots/

# View specific test screenshots
open test_deployment_single_unit_*_FAILED.png
```

#### Deep Debugging - Load Save State
1. Launch the game normally
2. Go to Load Game menu
3. Navigate to `test_artifacts/saves/`
4. Load the save file from your test
5. Examine unit positions, game state, etc.

Or load programmatically:
```gdscript
SaveLoadManager.load_game("test_test_deployment_single_unit_2025-10-29T15-30-45_FAILED")
```

#### Automated Analysis - JSON Reports
```bash
# View report
cat ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/reports/test_name.json | python3 -m json.tool

# Extract status
cat report.json | grep "status"
```

### Example Console Output

When artifacts are captured, you'll see:

```
[Test Artifacts] Capturing screenshots...
[Test Artifacts] Host screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T15-30-45_host_PASSED.png
[Test Artifacts] Client screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T15-30-45_client_PASSED.png
[Test Artifacts] Capturing game state save...
[Test Artifacts] Save state captured: user://test_artifacts/saves/test_test_deployment_single_unit_2025-10-29T15-30-45_PASSED.w40ksave
[Test Artifacts] Load with: SaveLoadManager.load_game('test_test_deployment_single_unit_2025-10-29T15-30-45_PASSED')
[Test Artifacts] Report saved: user://test_artifacts/reports/test_deployment_single_unit_2025-10-29T15-30-45.json
```

### Detailed Guide

For complete documentation on the artifact system, see:
- **[Test Artifacts Guide](./TEST_ARTIFACTS_GUIDE.md)** - Complete guide with examples, workflows, and advanced usage

---
