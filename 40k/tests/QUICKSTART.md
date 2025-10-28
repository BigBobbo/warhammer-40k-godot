# Multiplayer Testing Quick Start

## 5-Minute Setup

### 1. Verify Installation
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
export PATH="$HOME/bin:$PATH"
which godot  # Should show /Users/robertocallaghan/bin/godot
```

### 2. Try Manual Launch (Sanity Check)
```bash
# From the 40k directory:
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Terminal 1: Launch host
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100 &

# Wait 5 seconds, then Terminal 2: Launch client
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-join --position=800,100 &
```

**Note**: The `--path` argument MUST be the absolute path to the 40k project directory (where project.godot is located).

**Expected result**: Two windows side-by-side, connected in multiplayer

### 3. Run First Automated Test
```bash
./tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd
```

## If Something Goes Wrong

### Test fails with "Failed to launch host instance"
```bash
# Check godot path
echo $PATH
which godot

# Try setting explicitly in GameInstance.gd line 46-47
# Change: var godot_path = OS.get_executable_path()
# To: var godot_path = "/Users/robertocallaghan/bin/godot"
```

### Test fails with "Connection timeout"
```bash
# Check ports aren't blocked
lsof -i :7777

# Check logs for errors
ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/logs/ | head -5
tail ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log
```

### Processes don't terminate
```bash
# Kill all test instances
pkill -f "godot.*test-mode"
```

### Can't find test files
```bash
# Verify structure
ls -R tests/
# Should show:
# - tests/helpers/GameInstance.gd
# - tests/helpers/LogMonitor.gd
# - tests/helpers/MultiplayerIntegrationTest.gd
# - tests/integration/test_multiplayer_deployment.gd
# - tests/saves/deployment_test.w40ksave
```

## Quick Test Commands

```bash
# All multiplayer tests
./tests/run_multiplayer_tests.sh

# Specific test
./tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd

# With verbose output
./tests/run_multiplayer_tests.sh -v

# Using GUT GUI (in Godot Editor)
# Open Godot → Bottom panel → GUT → Select test_multiplayer_deployment.gd → Run
```

## Writing Your First Test

Create `tests/integration/test_my_feature.gd`:

```gdscript
extends MultiplayerIntegrationTest

func test_basic_connection():
    # Launch both instances
    var launched = await launch_host_and_client()
    assert_true(launched)

    # Wait for connection
    var connected = await wait_for_connection()
    assert_true(connected)

    # Test passed!
    print("✓ Connected successfully!")
```

Then run:
```bash
./tests/run_multiplayer_tests.sh -f test_my_feature.gd
```

## Files You Care About

**To write tests:**
- `tests/integration/test_multiplayer_*.gd` - Your test files

**To configure:**
- `tests/helpers/MultiplayerIntegrationTest.gd` - Base class, adjust timeouts here

**To debug:**
- `~/Library/Application Support/Godot/app_userdata/40k/logs/` - Debug logs
- `~/Library/Application Support/Godot/app_userdata/40k/test_screenshots/` - Screenshots

**Don't touch (unless framework issues):**
- `tests/helpers/GameInstance.gd`
- `tests/helpers/LogMonitor.gd`
- `autoloads/TestModeHandler.gd`

## What's Working vs. Placeholder

✅ **Fully Functional:**
- Process launching
- Window positioning
- Command-line argument handling
- Log monitoring
- Connection detection
- Basic state checking
- Test lifecycle management

⚠️ **Placeholder (Implement Later):**
- Screenshot capture (returns path, doesn't actually capture)
- Action simulation (methods exist but don't trigger real actions)
- Detailed state verification (needs game-specific logic)

## Need Help?

1. Read `tests/RUN_MULTIPLAYER_TESTS.md` - Comprehensive guide
2. Read `tests/MULTIPLAYER_TESTING_SUMMARY.md` - Implementation details
3. Check example test: `tests/integration/test_multiplayer_deployment.gd`

## Success Criteria

Your framework is working if:
- ✅ Two Godot windows launch side-by-side
- ✅ Client connects to host (see in window titles)
- ✅ Test passes with "All Tests Passed" message
- ✅ Processes terminate cleanly after test

Ready to test your multiplayer! 🚀