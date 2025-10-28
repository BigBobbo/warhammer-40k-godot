# Multiplayer Integration Testing Guide

## Overview

This framework allows you to run integration tests that launch multiple Godot instances to test multiplayer functionality in realistic conditions.

## Architecture

The multiplayer testing framework consists of:

1. **GameInstance** (`tests/helpers/GameInstance.gd`) - Manages individual Godot processes
2. **LogMonitor** (`tests/helpers/LogMonitor.gd`) - Monitors debug logs for connection events
3. **MultiplayerIntegrationTest** (`tests/helpers/MultiplayerIntegrationTest.gd`) - Base class for tests
4. **TestModeHandler** (`autoloads/TestModeHandler.gd`) - Handles command-line arguments
5. **Test Saves** (`tests/saves/`) - Dedicated save files for testing

## Running Tests

### Using GUT GUI (Recommended for development)

1. Open Godot editor
2. Navigate to the GUT panel (bottom panel)
3. Select "tests/integration/test_multiplayer_deployment.gd"
4. Click "Run Tests"
5. Watch both game windows appear side-by-side

### Using Command Line

```bash
# Run all multiplayer tests
godot --path 40k -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/ -gprefix=test_multiplayer

# Run specific test
godot --path 40k -s addons/gut/gut_cmdln.gd -gtest=test_multiplayer_deployment.gd
```

## Test Configuration

Each test can be configured via the base class properties:

```gdscript
func before_each():
    super.before_each()

    # Configure test behavior
    use_dynamic_ports = true              # Use random available ports
    visual_debugging = true               # Show game windows
    capture_screenshots_on_failure = true # Save screenshots on failure
    connection_timeout = 15.0             # Max wait time for connection
    sync_timeout = 10.0                   # Max wait time for state sync
```

## Writing New Tests

### Basic Template

```gdscript
extends MultiplayerIntegrationTest

func test_my_multiplayer_feature():
    # Launch host and client
    await launch_host_and_client()

    # Wait for connection
    await wait_for_connection()

    # Perform test actions
    simulate_host_action("some_action")
    await wait_for_seconds(2.0)

    # Verify results
    var synced = await verify_game_state_sync()
    assert_true(synced, "Game state should be synchronized")
```

### Available Helper Methods

**Instance Management:**
- `launch_host_and_client()` - Launches both instances
- `wait_for_connection()` - Waits for client to connect to host
- `_cleanup_instances()` - Terminates both instances

**Game State:**
- `verify_game_state_sync(timeout)` - Checks if game states match
- `wait_for_phase(phase_name, timeout)` - Waits for specific phase
- `load_test_save(save_name, on_host)` - Loads a test save file

**Actions:**
- `simulate_host_action(action)` - Triggers action on host
- `simulate_client_action(action)` - Triggers action on client

**Assertions:**
- `assert_connection_established(msg)` - Verifies connection
- `assert_game_started(msg)` - Verifies game started
- `assert_same_phase(msg)` - Verifies both in same phase

## Test Saves

Test saves are located in `tests/saves/` and have known game states:

- `deployment_test.w40ksave` - Deployment phase, no units deployed
- `deployment_nearly_complete.w40ksave` - Deployment almost done
- `deployment_with_terrain.w40ksave` - Deployment with terrain obstacles

### Creating New Test Saves

1. Play the game to the desired state
2. Save the game
3. Copy the save file to `tests/saves/`
4. Rename it with a descriptive name
5. Edit the JSON to mark it as a test save:
   ```json
   "_serialization": {
       "test_save": true,
       "description": "What this tests"
   }
   ```

## How It Works

### Process Launch

When you run a multiplayer test:

1. Test creates a `GameInstance` for the host
2. GameInstance launches Godot with special args:
   ```
   --test-mode --auto-host --port=7777 --position=100,100
   ```
3. TestModeHandler in the launched instance reads these args
4. TestModeHandler automatically navigates menus and hosts game
5. LogMonitor starts watching debug logs for events

6. Same process for client with `--auto-join` flag

### Connection Detection

LogMonitor watches for patterns in logs like:
- `"YOU ARE: PLAYER 1 (HOST)"`
- `"Peer connected: peer_id=2"`
- `"YOU ARE: PLAYER 2 (CLIENT)"`

When detected, it emits signals that the test can await.

### Synchronization

Tests use log monitoring to verify state:
- Wait for both instances to log same phase
- Wait for both to log same turn number
- Wait for action confirmations

## Debugging Failed Tests

When a test fails:

1. **Screenshots** - Check `user://test_screenshots/`
   - `Host_<timestamp>.png`
   - `Client_<timestamp>.png`

2. **Debug Logs** - Check `user://logs/`
   - Find logs matching test run time
   - Search for ERROR or WARNING messages

3. **Visual Debugging** - Set `visual_debugging = true`
   - Watch both game windows during test
   - See what's happening in real-time

4. **Increase Timeouts** - If timing issues:
   ```gdscript
   connection_timeout = 30.0  # Give more time
   sync_timeout = 20.0
   ```

## Current Test Coverage

### Implemented (MVP):
- ✅ Basic connection establishment
- ✅ Save loading in deployment phase
- ✅ Turn order during deployment
- ✅ Deployment completion sync
- ✅ Terrain visibility

### Planned (Post-MVP):
- ⏸ Disconnection handling
- ⏸ Network latency simulation
- ⏸ Save corruption recovery
- ⏸ Movement phase sync
- ⏸ Shooting phase sync
- ⏸ Fight phase sync

## Limitations

### Current Limitations:

1. **Action Simulation** - Currently simulates actions via methods, not actual UI clicks
2. **Screenshot Capture** - Placeholder implementation (needs OS-specific code)
3. **IPC** - No direct inter-process communication (relies on logs)
4. **Headless Mode** - Not tested in headless environments

### Design Decisions:

- **Separate Processes** - More realistic than mocking, catches race conditions
- **Log Monitoring** - Simpler than IPC, works well for MVP
- **Visual Windows** - Helps debugging, can disable for CI/CD later
- **Dynamic Ports** - Avoids conflicts when running multiple test suites

## Tips

### Speeding Up Tests

- Reduce wait times after verifying sync:
  ```gdscript
  await wait_for_seconds(0.5)  # Instead of 2.0
  ```

- Use dynamic ports to run tests in parallel (future):
  ```gdscript
  use_dynamic_ports = true
  ```

### Handling Flaky Tests

- Increase timeouts for slower machines
- Add retry logic for connection attempts
- Use `gut.pending()` to skip flaky tests temporarily

### CI/CD Integration (Future)

When ready for CI/CD:

1. Disable visual debugging:
   ```gdscript
   visual_debugging = false
   ```

2. Use headless mode:
   ```bash
   godot --headless --path 40k -s addons/gut/gut_cmdln.gd
   ```

3. Implement Xvfb or similar for Linux CI

## Troubleshooting

**Problem: Tests timeout on connection**
- Check firewall settings
- Verify port 7777 is available
- Check debug logs for NetworkManager errors

**Problem: GameInstance fails to launch**
- Verify godot is in PATH or `$HOME/bin/godot`
- Check file permissions on `godot` executable
- Try running godot manually with test args

**Problem: LogMonitor doesn't detect events**
- Verify debug logging is enabled
- Check log file permissions
- Ensure logs directory exists

**Problem: Screenshots not captured**
- Currently placeholder - needs OS-specific implementation
- Would use tools like `screencapture` on macOS

## Questions or Issues?

See the GUT documentation: https://github.com/bitwes/Gut/wiki
Report framework bugs in your issue tracker