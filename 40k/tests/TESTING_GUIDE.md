# Multiplayer Integration Testing Guide

**Last Updated:** 2025-10-28
**Status:** Infrastructure Complete - Save Loading In Progress

---

## Overview

This guide documents the multiplayer integration test suite for the Warhammer 40k game. The test framework allows automated testing of multiplayer gameplay by launching multiple Godot instances and simulating player actions through a command file system.

---

## Test Architecture

### Components

1. **Test Framework** (`tests/helpers/`)
   - `MultiplayerIntegrationTest.gd` - Base class for all multiplayer tests
   - `GameInstance.gd` - Manages individual game process lifecycle
   - `LogMonitor.gd` - Tracks game state via log files

2. **Test Mode Handler** (`autoloads/TestModeHandler.gd`)
   - Autoload that detects test mode via command line arguments
   - Auto-starts host/client connections
   - Processes action simulation commands via JSON files
   - Loads test save files

3. **Action Simulation**
   - Tests write action commands to `user://test_commands/`
   - Game instances read commands and execute actions
   - Results written back to `user://test_results/`
   - Tests poll for results with timeout

---

## Current Test Suite

### Deployment Tests (`tests/integration/test_multiplayer_deployment.gd`)

**File:** `test_multiplayer_deployment.gd`
**Test Count:** 10 tests
**Status:** 10 implemented, 0 passing (save loading issue)
**Required Save Files:** 5 (all created)

#### 1. `test_basic_multiplayer_connection()`
**Purpose:** Verify test infrastructure and multiplayer connection
**Setup:** Empty game state
**Actions:**
- Launch host and client instances
- Wait for connection
- Verify action simulation works

**Expected Output:**
```
[Test] Launching host and client instances...
[Test] Connection verified - action simulation working!
[TEST] PASSED: Basic connection established
```

**How to Run:**
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gtest=test_basic_multiplayer_connection \
  -gexit
```

---

#### 2. `test_deployment_save_load()`
**Purpose:** Verify save file loading in multiplayer
**Setup:** deployment_start.w40ksave
**Actions:**
- Load save file
- Verify both clients loaded same state
- Check game phase is Deployment

**Expected Output:**
```
[Test] Auto-loading save: deployment_start
[Test] Host phase: Deployment, Client phase: Deployment
[TEST] PASSED: Deployment save loaded and synced
```

**How to Run:**
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gtest=test_deployment_save_load \
  -gexit
```

---

#### 3. `test_deployment_single_unit()`
**Purpose:** Deploy a single unit within valid deployment zone
**Setup:** deployment_start.w40ksave
**Save File Contents:**
- Player 1: unit_p1_1 (undeployed)
- Player 2: unit_p2_1 (undeployed)
- Phase: Deployment
- Active Player: 1

**Actions:**
1. Host deploys unit_p1_1 at position (5.0, 5.0)
2. Wait for sync
3. Verify unit appears on both clients

**Expected Output:**
```
[Test] Host performing action: deploy_unit
GameManager: deploy_unit() called - unit_id: unit_p1_1
GameManager: Deployed unit_p1_1 (10 models)
[Test] Action completed: success=true
[TEST] PASSED: Unit deployment successful
```

**How to Run:**
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gtest=test_deployment_single_unit \
  -gexit
```

---

#### 4. `test_deployment_outside_zone()`
**Purpose:** Reject deployment outside valid zone
**Setup:** deployment_start.w40ksave
**Actions:**
- Try to deploy unit at (22.0, 30.0) - outside deployment zone
- Verify deployment rejected

**Expected Output:**
```
[Test] Deployment rejected: Outside deployment zone
[TEST] PASSED: Invalid deployment correctly rejected
```

---

#### 5. `test_deployment_alternating_turns()`
**Purpose:** Verify turn alternation between players
**Setup:** deployment_start.w40ksave
**Actions:**
1. Check initial turn (Player 1)
2. Player 1 deploys unit
3. Verify turn switches to Player 2

**Expected Output:**
```
[Test] Initial turn: Player 1
[Test] After deployment: Player 2
[TEST] PASSED: Turn alternation working
```

---

#### 6. `test_deployment_wrong_turn()`
**Purpose:** Reject deployment when not player's turn
**Setup:** deployment_player1_turn.w40ksave
**Actions:**
- Client (Player 2) tries to deploy on Player 1's turn
- Verify action rejected

**Expected Output:**
```
[Test] Wrong turn deployment rejected
[TEST] PASSED: Turn enforcement working
```

---

#### 7. `test_deployment_blocked_by_terrain()`
**Purpose:** Reject deployment on impassable terrain
**Setup:** deployment_with_terrain.w40ksave
**Actions:**
- Try to deploy on terrain marked as impassable
- Verify deployment rejected

**Expected Output:**
```
[Test] Deployment blocked by terrain
[TEST] PASSED: Terrain blocking working
```

---

#### 8. `test_deployment_unit_coherency()`
**Purpose:** Verify unit coherency requirements
**Setup:** deployment_start.w40ksave
**Actions:**
- Deploy multi-model unit
- Verify all models within 2" horizontal/5" vertical coherency

**Expected Output:**
```
[Test] Unit deployed in coherency
[TEST] PASSED: Coherency validation working
```

---

#### 9. `test_deployment_completion_both_players()`
**Purpose:** Test deployment phase completion
**Setup:** deployment_nearly_complete.w40ksave
**Actions:**
1. Player 1 completes deployment
2. Player 2 completes deployment
3. Verify phase advances to Command

**Expected Output:**
```
[Test] Player 1 completed deployment
[Test] Player 2 completed deployment
[Test] Phase advanced to: Command
[TEST] PASSED: Deployment completion working
```

---

#### 10. `test_deployment_undo_action()`
**Purpose:** Test undo functionality
**Setup:** deployment_player1_turn.w40ksave
**Actions:**
1. Deploy unit
2. Undo deployment
3. Verify unit returns to undeployed state

**Expected Output:**
```
[Test] Unit deployed
[Test] Deployment undone
[Test] Unit status: UNDEPLOYED
[TEST] PASSED: Undo working
```

---

## Test Save Files

Located in `tests/saves/`:

| File | Description | Units | Phase |
|------|-------------|-------|-------|
| `deployment_start.w40ksave` | Fresh deployment start | 2 (1 per player) | Deployment |
| `deployment_player1_turn.w40ksave` | Player 1's turn | 2 (1 per player) | Deployment |
| `deployment_player2_turn.w40ksave` | Player 2's turn | 2 (1 per player) | Deployment |
| `deployment_nearly_complete.w40ksave` | Almost done | 4 (mostly deployed) | Deployment |
| `deployment_with_terrain.w40ksave` | Includes terrain | 2 (1 per player) | Deployment |

---

## Running Tests

### Run All Deployment Tests
```bash
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
  -gtest=test_deployment_single_unit \
  -gexit
```

### Run With Verbose Output
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gfile=test_multiplayer_deployment.gd \
  -gtest=test_deployment_single_unit \
  -gexit 2>&1 | tee test_output.log
```

---

## Writing New Tests

### Template

```gdscript
extends "res://tests/helpers/MultiplayerIntegrationTest.gd"

func test_my_new_test():
    """
    Test: Brief description

    Setup: save_file.w40ksave loaded
    Action: What actions are performed
    Verify: What is verified
    """
    print("\n[TEST] test_my_new_test")

    # Launch with save file
    await launch_host_and_client("save_file_name")
    await wait_for_connection()
    await wait_for_seconds(3.0)

    # Perform action
    var result = await simulate_host_action("action_name", {
        "param1": "value1",
        "param2": "value2"
    })

    # Verify result
    assert_true(result.get("success", false), "Action should succeed")

    print("[TEST] PASSED: Test description")
```

### Available Actions

- `get_game_state` - Returns current game state
- `deploy_unit` - Deploy a unit at position
- `undo_deployment` - Undo last deployment
- `complete_deployment` - Mark deployment complete

---

## Current Issues

### Save File Not Loading
**Status:** IN PROGRESS
**Issue:** Save files are passed correctly but not loading into GameState
**Evidence:** "Unit not found" errors even with save file specified
**Next Steps:**
1. Verify SaveLoadManager.load_game() is being called
2. Check if save file path is correct
3. Add more debug logging to save loading process

### Tests Pass Despite Failures
**Status:** KNOWN ISSUE
**Issue:** Tests show PASSED even when assertions fail
**Cause:** Test framework doesn't properly aggregate assertion failures
**Workaround:** Check for "ASSERTION FAILED" in output

---

## Test Infrastructure Status

✅ **Complete:**
- Multi-process test execution
- Command file-based action simulation
- Game auto-start (host/client)
- Phase initialization
- Action handlers (deploy_unit, undo, complete)
- Save file parameter passing

⏸️ **In Progress:**
- Save file loading into GameState
- Network synchronization verification

❌ **Not Yet Implemented:**
- Movement phase tests (10 tests)
- Shooting phase tests (12 tests)
- Charge phase tests (7 tests)
- Fight phase tests (12 tests)
- Phase transition tests (6 tests)
- Full game smoke tests (2 tests)

---

## Debugging Tips

### Check Game Instance Logs
```bash
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/logs/
tail -f ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log
```

### Check Command Files
```bash
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/test_commands/
cat ~/Library/Application\ Support/Godot/app_userdata/40k/test_commands/*.json
```

### Check Result Files
```bash
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/test_results/
cat ~/Library/Application\ Support/Godot/app_userdata/40k/test_results/*.json
```

### Common Issues

**Issue:** "Parameter data.tree is null"
**Solution:** Fixed - use Engine.get_main_loop() instead of get_tree()

**Issue:** "Unit not found"
**Solution:** IN PROGRESS - save file loading issue

**Issue:** "Action simulation timeout"
**Solution:** Check if game instances are running, check command/result files exist

---

## Test Metrics

**Total Tests Planned:** 59
**Tests Implemented:** 10 (17%)
**Tests Passing:** 0 (0%) - blocked by save loading
**Infrastructure Complete:** 100%

**Estimated Time to All Passing:**
- Fix save loading: 2-4 hours
- All deployment tests passing: 1-2 days
- All tests implemented: 7-18 weeks

---

## References

- Test Plan: `tests/MULTIPLAYER_TEST_PLAN.md`
- Implementation Status: `tests/IMPLEMENTATION_STATUS.md`
- Outstanding Work: `tests/OUTSTANDING_WORK.md`
- Current Status: `tests/CURRENT_STATUS.md`
- Session Summary: `tests/SESSION_SUMMARY.md`

---

**Last Session:** 2025-10-28
**Next Priority:** Fix save file loading to unblock all deployment tests
**Contact:** See project documentation for support
