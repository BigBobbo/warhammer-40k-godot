# Multiplayer Integration Testing Framework - Implementation Summary

## What We Built

A complete framework for running realistic multiplayer integration tests using separate Godot processes. This allows you to test your multiplayer functionality with actual network connections and catch race conditions that wouldn't appear in mock-based tests.

## Components Created

### 1. Core Framework Files

#### `tests/helpers/GameInstance.gd`
- Manages individual Godot game processes
- Handles process launching with command-line arguments
- Monitors instance logs for events
- Provides window positioning for visual debugging
- **Location**: `/40k/tests/helpers/GameInstance.gd`

**Key Features:**
- Launch instances with specific roles (host/client)
- Dynamic port allocation to avoid conflicts
- Log file monitoring for state detection
- Screenshot capture support (placeholder for OS-specific implementation)
- Signal-based event notification

#### `tests/helpers/LogMonitor.gd`
- Monitors Godot debug logs in real-time
- Parses log patterns to detect game events
- Emits signals when key events occur
- **Location**: `/40k/tests/helpers/LogMonitor.gd`

**Detects:**
- Peer connections/disconnections
- Host/client role assignment
- Game start events
- Phase transitions
- Save file loading
- Errors and warnings

#### `tests/helpers/MultiplayerIntegrationTest.gd`
- Base class for all multiplayer integration tests
- Provides helper methods and assertions
- Manages instance lifecycle
- **Location**: `/40k/tests/helpers/MultiplayerIntegrationTest.gd`

**Provides:**
- Instance launch and cleanup
- Connection verification
- State synchronization checking
- Test save management
- Screenshot capture on failure
- Helpful assertion methods

### 2. Test Mode Support

#### `autoloads/TestModeHandler.gd`
- Autoload that runs on game startup
- Parses command-line arguments
- Automatically performs actions based on test flags
- **Location**: `/40k/autoloads/TestModeHandler.gd`
- **Added to**: `/40k/project.godot` (autoload section)

**Supported Arguments:**
```bash
--test-mode                    # Enable test mode
--instance-name=<name>         # Set instance identifier
--auto-host                    # Automatically host a game
--auto-join                    # Automatically join a game
--port=<port>                  # Specify port number
--host-ip=<ip>                 # Specify host IP to connect to
--host-port=<port>             # Specify host port
--auto-load-save=<path>        # Auto-load a save file
--position=<x>,<y>             # Set window position
--resolution=<w>x<h>           # Set window resolution
```

### 3. Test Implementation

#### `tests/integration/test_multiplayer_deployment.gd`
- Example test suite for deployment phase
- Demonstrates framework usage
- **Location**: `/40k/tests/integration/test_multiplayer_deployment.gd`

**Included Tests:**
1. `test_basic_multiplayer_connection()` - Verify basic connectivity
2. `test_multiplayer_save_load_deployment()` - Test save loading
3. `test_deployment_action_sync()` - Test action synchronization
4. `test_deployment_turn_order()` - Test turn alternation
5. `test_deployment_completion_sync()` - Test phase transitions
6. `test_deployment_with_terrain()` - Test with terrain features

### 4. Test Data

#### Test Save Files
- **Location**: `/40k/tests/saves/`
- **Created**: `deployment_test.w40ksave` - Deployment phase test save

**Structure:**
- Standard W40K save format (JSON)
- Marked as test saves in metadata
- Known game states for reproducible testing
- Both players have undeployed units
- Includes terrain and objectives

### 5. Documentation & Scripts

#### `tests/RUN_MULTIPLAYER_TESTS.md`
- Comprehensive testing guide
- Architecture explanation
- Usage examples
- Troubleshooting tips

#### `tests/run_multiplayer_tests.sh`
- Shell script for running tests
- Colorized output
- Error checking
- Support for running specific tests

**Usage:**
```bash
# Run all multiplayer tests
./40k/tests/run_multiplayer_tests.sh

# Run specific test file
./40k/tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd

# Run with verbose output
./40k/tests/run_multiplayer_tests.sh -v
```

## How It Works

### Test Execution Flow

```
1. Test starts
   └─> MultiplayerIntegrationTest.before_each()
       └─> Creates GameInstance for host
       └─> Creates GameInstance for client

2. Launch instances
   └─> GameInstance.launch()
       └─> Spawns Godot process with --test-mode --auto-host
       └─> TestModeHandler reads args in new process
       └─> Auto-navigates to multiplayer and hosts
       └─> LogMonitor starts watching logs

3. Wait for connection
   └─> LogMonitor detects "Peer connected: peer_id=2" in host log
   └─> LogMonitor detects "YOU ARE: PLAYER 2 (CLIENT)" in client log
   └─> Connection verified, test proceeds

4. Run test actions
   └─> Test calls simulate_host_action("start_game")
   └─> Test calls load_test_save("deployment_test.w40ksave")
   └─> Both instances load save and enter deployment phase

5. Verify synchronization
   └─> LogMonitor checks both logs for "Phase started: Deployment"
   └─> State sync verified

6. Test cleanup
   └─> MultiplayerIntegrationTest.after_each()
       └─> Captures screenshots if test failed
       └─> Terminates both processes
```

### Log Monitoring Magic

The framework watches for specific patterns in the game's debug logs:

```gdscript
# In host log:
"YOU ARE: PLAYER 1 (HOST)"
"Hosting on port: 7777"
"Peer connected: peer_id=2"

# In client log:
"Connecting to 127.0.0.1:7777"
"YOU ARE: PLAYER 2 (CLIENT)"

# Both logs:
"Game started"
"Phase started: Deployment"
"Save loaded: deployment_test.w40ksave"
```

These patterns are detected by `LogMonitor` and converted to signals that tests can await.

## What Still Needs Work

### 1. Screenshot Capture (Placeholder)
**Status**: Implemented as placeholder in `GameInstance.capture_screenshot()`

**What's needed:**
```gdscript
# macOS implementation:
OS.execute("screencapture", ["-l", window_id, screenshot_path])

# Linux implementation:
OS.execute("import", ["-window", window_id, screenshot_path])

# Windows implementation:
OS.execute("powershell", ["-Command", "Add-Type ...; [Screenshot]::Take(...)"])
```

**Why it's tricky**: Need to get the window ID for each Godot instance.

### 2. Action Simulation
**Status**: Stubs in place via `simulate_host_action()` and `simulate_client_action()`

**Current approach**: Methods are called but don't actually trigger actions
**Better approach**:
- Option A: IPC (Inter-Process Communication) to send commands
- Option B: Network API that accepts test commands
- Option C: File-based command queue that instances watch

**Recommended**: Option C for simplicity
```gdscript
# Test writes command file
var cmd_file = "user://test_commands/host_commands.json"
var commands = [{"action": "deploy_unit", "params": {...}}]
# Host instance watches this file and executes commands
```

### 3. State Verification
**Status**: Basic framework in place, needs specific implementations

**What's missing**:
- Actual game state serialization to comparable format
- Detailed state comparison logic
- Tolerance for acceptable differences (e.g., floating point)

**Example needed:**
```gdscript
func verify_unit_positions_synced() -> bool:
    var host_units = host_instance.get_unit_positions()
    var client_units = client_instance.get_unit_positions()

    for unit_id in host_units:
        if not client_units.has(unit_id):
            return false
        if not host_units[unit_id].distance_to(client_units[unit_id]) < 0.1:
            return false
    return true
```

### 4. Additional Test Saves
**Status**: Only `deployment_test.w40ksave` created

**Needed:**
- `deployment_nearly_complete.w40ksave` - For testing completion
- `deployment_with_terrain.w40ksave` - For terrain tests
- `movement_phase.w40ksave` - Movement phase test
- `shooting_phase.w40ksave` - Shooting phase test
- `charge_phase.w40ksave` - Charge phase test

**How to create:**
1. Play game to desired state
2. Save the game
3. Copy from `40k/saves/` to `40k/tests/saves/`
4. Rename descriptively
5. Edit JSON to mark as test save

### 5. GUT Integration Verification
**Status**: Should work but untested

**Next step**: Actually run the tests!
```bash
cd 40k
./tests/run_multiplayer_tests.sh
```

**Possible issues to watch for:**
- GUT might not handle multi-process tests well
- Timing issues (increase timeouts if needed)
- Port conflicts (use dynamic ports)
- Permission issues with process spawning

## Next Steps to Make This Production-Ready

### Immediate (Before First Test Run)

1. **Test Basic Functionality**
   ```bash
   # Try launching manually with test mode
   godot --path 40k --test-mode --auto-host --position=100,100
   ```
   - Verify TestModeHandler works
   - Verify auto-navigation to multiplayer lobby
   - Verify hosting works

2. **Run Simplest Test**
   ```bash
   cd 40k/tests
   ./run_multiplayer_tests.sh -f test_multiplayer_deployment.gd
   ```
   - Watch for errors
   - Fix any class_name or autoload issues
   - Verify processes launch

### Short-Term (MVP Complete)

3. **Implement Action Simulation**
   - Choose IPC approach (recommend file-based)
   - Implement in TestModeHandler
   - Update simulate_*_action() methods
   - Test actual unit deployment

4. **Create More Test Saves**
   - Play through game phases
   - Save at key moments
   - Copy to tests/saves/
   - Document each save's purpose

5. **Improve Log Patterns**
   - Review NetworkManager for logged events
   - Add more specific patterns to LogMonitor
   - Test pattern matching with real logs

### Medium-Term (Full Coverage)

6. **Add More Test Suites**
   - `test_multiplayer_movement.gd`
   - `test_multiplayer_shooting.gd`
   - `test_multiplayer_fight.gd`
   - `test_multiplayer_command_phase.gd`

7. **Implement Screenshot Capture**
   - OS-specific implementations
   - Window ID detection
   - Automated capture on failure

8. **State Verification**
   - Detailed comparison functions
   - Per-phase state checks
   - Sync tolerance configuration

### Long-Term (Production)

9. **CI/CD Integration**
   - Headless mode support
   - Xvfb for Linux CI
   - Automated test runs on PRs

10. **Performance & Stability**
    - Optimize timeouts
    - Add retry logic
    - Parallel test execution
    - Test result caching

## Key Design Decisions

### ✅ Why Separate Processes?
- **More realistic**: Tests actual networking, not mocked connections
- **Catches race conditions**: Real timing issues surface
- **True integration**: Tests the full stack including NetworkManager

### ✅ Why Log Monitoring?
- **Simple**: No complex IPC needed for MVP
- **Non-invasive**: Doesn't require changes to production code
- **Debuggable**: Logs are already written for debugging

### ✅ Why Visual Windows?
- **Development speed**: See what's happening in real-time
- **Debugging**: Instantly spot UI issues
- **Confidence**: Watch tests execute step-by-step

### ✅ Why GUT Framework?
- **Already integrated**: You're using it for other tests
- **Familiar**: Same assertions and patterns
- **Proven**: Well-tested framework

## Files Modified

1. **Created**:
   - `40k/tests/helpers/GameInstance.gd`
   - `40k/tests/helpers/LogMonitor.gd`
   - `40k/tests/helpers/MultiplayerIntegrationTest.gd`
   - `40k/autoloads/TestModeHandler.gd`
   - `40k/tests/integration/test_multiplayer_deployment.gd`
   - `40k/tests/saves/deployment_test.w40ksave`
   - `40k/tests/RUN_MULTIPLAYER_TESTS.md`
   - `40k/tests/run_multiplayer_tests.sh`
   - `40k/tests/MULTIPLAYER_TESTING_SUMMARY.md` (this file)

2. **Modified**:
   - `40k/project.godot` - Added TestModeHandler autoload

## Testing the Framework Itself

Before writing more tests, verify the framework works:

### Manual Verification Steps

1. **Test autoload loading**
   ```bash
   godot --path 40k --headless --script-check-only
   # Should show no errors
   ```

2. **Test TestModeHandler**
   ```bash
   godot --path 40k --test-mode --auto-host &
   # Watch if it auto-navigates to lobby and hosts
   # Check window title shows "40k Test - Host"
   ```

3. **Test client joining**
   ```bash
   godot --path 40k --test-mode --auto-host --position=100,100 &
   sleep 5
   godot --path 40k --test-mode --auto-join --position=800,100 &
   # Watch if they connect
   ```

4. **Test log monitoring**
   ```gdscript
   # In a simple test script:
   var monitor = LogMonitor.new()
   monitor.connection_detected.connect(func(id, connected):
       print("Detected: ", id, " ", connected)
   )
   monitor.start_monitoring("<path to recent log>")
   await get_tree().create_timer(10.0).timeout
   monitor.stop_monitoring()
   ```

## Common Issues & Solutions

### Issue: Godot not found
**Solution**: Ensure `export PATH="$HOME/bin:$PATH"` in your shell

### Issue: Tests timeout
**Solution**: Increase timeout values in test:
```gdscript
connection_timeout = 30.0
sync_timeout = 20.0
```

### Issue: Port already in use
**Solution**: Enable dynamic ports:
```gdscript
use_dynamic_ports = true
```

### Issue: Processes don't terminate
**Solution**: Check `after_each()` is called, manually kill:
```bash
pkill -f "godot.*test-mode"
```

### Issue: Logs not found
**Solution**: Check log directory exists:
```bash
ls -la ~/Library/Application\ Support/Godot/app_userdata/40k/logs/
```

## Conclusion

This framework gives you a solid foundation for multiplayer integration testing. While some features are placeholder implementations (screenshots, action simulation), the core architecture is sound and extensible.

The next step is to run your first test and iterate based on real results. Start with the basic connection test, then gradually add more complex scenarios.

**Estimated time to fully functional:**
- Basic tests working: 2-4 hours (fixing any launch issues)
- Action simulation implemented: 4-8 hours
- Full deployment phase coverage: 8-16 hours
- All game phases covered: 40-80 hours

Good luck! 🎮🚀