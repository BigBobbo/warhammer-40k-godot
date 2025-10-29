# Test Artifacts Guide

**Purpose:** Capture and examine test results through screenshots, save states, and reports
**Last Updated:** 2025-10-29

---

## Overview

The test framework now automatically captures three types of artifacts after each test:

1. **Screenshots** - Visual snapshots of both host and client windows
2. **Save States** - Complete game state that can be loaded and examined
3. **JSON Reports** - Structured test metadata and results

This allows users to:
- Quickly verify visual correctness through screenshots
- Load and interact with the exact game state after a test
- Track test history and compare results over time

---

## Artifact Locations

All test artifacts are saved to:
```
~/Library/Application Support/Godot/app_userdata/40k/test_artifacts/
├── screenshots/     # PNG screenshots from tests
├── saves/          # Game save states
└── reports/        # JSON test reports
```

**Quick Access:**
```bash
open ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/
```

---

## 1. Screenshots

### What They Capture
Screenshots capture the visual state of the game at test completion:
- Host window view
- Client window view
- Unit positions
- UI state
- Visual effects

###  File Naming
```
{test_name}_{timestamp}_{instance}_{status}.png
```

**Examples:**
```
test_deployment_single_unit_2025-10-29T15-30-45_host_PASSED.png
test_deployment_single_unit_2025-10-29T15-30-45_client_PASSED.png
test_deployment_outside_zone_2025-10-29T15-32-10_host_FAILED.png
```

### Configuration

```gdscript
# In test file (extends MultiplayerIntegrationTest)
func before_each():
    super.before_each()

    # Capture screenshots ONLY on failure (default)
    capture_screenshots_on_failure = true
    capture_screenshots_on_success = false

    # OR capture on ALL tests
    capture_screenshots_on_failure = true
    capture_screenshots_on_success = true
```

### Viewing Screenshots

Screenshots are standard PNG files - open with any image viewer:

```bash
# macOS
open ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/screenshots/

# View specific screenshot
open test_deployment_single_unit_2025-10-29T15-30-45_host_PASSED.png
```

### Use Cases

✅ **Quick visual verification** - Did the unit appear where expected?
✅ **UI state checks** - Are buttons in the correct state?
✅ **Regression testing** - Compare screenshots across runs
✅ **Bug reports** - Attach visual evidence of failures

---

## 2. Save States

### What They Capture

Save states preserve the complete game state:
- All unit positions and stats
- Game phase and turn
- Player states
- Terrain configuration
- Mission objectives
- Internal game state

### File Naming
```
test_{test_name}_{timestamp}_{status}.w40ksave
```

**Examples:**
```
test_test_deployment_single_unit_2025-10-29T15-30-45_PASSED.w40ksave
test_test_deployment_outside_zone_2025-10-29T15-32-10_FAILED.w40ksave
```

### Configuration

```gdscript
# In test file
func before_each():
    super.before_each()

    # Enable/disable save state capture (default: enabled)
    save_state_on_completion = true
```

### Loading Save States

#### Method 1: Through Game UI
1. Launch the game normally
2. Go to Load Game menu
3. Navigate to test_artifacts/saves/
4. Select the save file

#### Method 2: Via Console (for debugging)
```gdscript
# In Godot console or script
SaveLoadManager.load_game("test_test_deployment_single_unit_2025-10-29T15-30-45_PASSED")
```

#### Method 3: Programmatically in Tests
```gdscript
func test_examine_previous_state():
    # Load a save from a previous test
    var result = await simulate_host_action("load_save", {
        "save_name": "test_deployment_single_unit_2025-10-29T15-30-45_PASSED"
    })
```

### Use Cases

✅ **Deep debugging** - Examine internal state, not just visuals
✅ **Reproduce issues** - Load exact state where test failed
✅ **Manual testing** - Interact with the game post-test
✅ **State comparison** - Compare game state across test runs
✅ **Edge case exploration** - Set up complex scenarios via tests, then explore manually

---

## 3. JSON Reports

### What They Capture

JSON reports contain structured test metadata:
- Test name and timestamp
- Pass/fail status
- Failure message (if failed)
- Connection status (host/client)
- Test configuration
- Final game state snapshot

### File Naming
```
{test_name}_{timestamp}.json
```

**Example:**
```
test_deployment_single_unit_2025-10-29T15-30-45.json
```

### Report Structure

```json
{
    "test_name": "test_deployment_single_unit",
    "timestamp": "2025-10-29T15-30-45",
    "status": "PASSED",
    "failure_message": "",
    "host_connected": true,
    "client_connected": true,
    "configuration": {
        "use_dynamic_ports": true,
        "visual_debugging": true,
        "capture_screenshots_on_failure": true,
        "capture_screenshots_on_success": false,
        "save_state_on_completion": true
    },
    "final_game_state": {
        "current_phase": "Deployment",
        "current_turn": 1,
        "player_turn": 1,
        "units": {...}
    }
}
```

### Parsing Reports

```bash
# Pretty-print JSON
cat test_deployment_single_unit_2025-10-29T15-30-45.json | python3 -m json.tool

# Extract specific fields
cat report.json | grep "status"
cat report.json | grep "current_phase"
```

```python
# Python script to analyze reports
import json
import glob

# Find all test reports
reports = glob.glob("*.json")

passed = 0
failed = 0

for report_file in reports:
    with open(report_file) as f:
        data = json.load(f)
        if data["status"] == "PASSED":
            passed += 1
        else:
            failed += 1
            print(f"Failed: {data['test_name']} - {data['failure_message']}")

print(f"\nTotal: {passed + failed}, Passed: {passed}, Failed: {failed}")
```

### Use Cases

✅ **Test history tracking** - Analyze trends over time
✅ **Automated reporting** - Parse for CI/CD pipelines
✅ **Regression detection** - Compare game state across versions
✅ **Performance analysis** - Track test execution patterns

---

## Complete Example Workflow

### Scenario: Investigating a Deployment Test Failure

1. **Run the test:**
```bash
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gfile=test_multiplayer_deployment.gd \
    -gtest=test_deployment_single_unit \
    -gexit
```

2. **Test fails - Check console output:**
```
[TEST] test_deployment_single_unit
[Test Artifacts] Capturing screenshots...
[Test Artifacts] Host screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T15-30-45_host_FAILED.png
[Test Artifacts] Client screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T15-30-45_client_FAILED.png
[Test Artifacts] Capturing game state save...
[Test Artifacts] Save state captured: user://test_artifacts/saves/test_test_deployment_single_unit_2025-10-29T15-30-45_FAILED.w40ksave
[Test Artifacts] Load with: SaveLoadManager.load_game('test_test_deployment_single_unit_2025-10-29T15-30-45_FAILED')
[Test Artifacts] Report saved: user://test_artifacts/reports/test_deployment_single_unit_2025-10-29T15-30-45.json
```

3. **Quick Visual Check - Open screenshots:**
```bash
cd ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/screenshots/
open test_deployment_single_unit_2025-10-29T15-30-45_host_FAILED.png
```

4. **Detailed Investigation - Load save state:**
   - Launch the game
   - Load save: `test_test_deployment_single_unit_2025-10-29T15-30-45_FAILED`
   - Examine unit positions
   - Check game state variables
   - Reproduce the issue manually

5. **Analyze Report:**
```bash
cd ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/reports/
cat test_deployment_single_unit_2025-10-29T15-30-45.json | python3 -m json.tool
```

6. **Fix the issue, re-run test:**
```bash
# Make code changes...
godot --path . -s addons/gut/gut_cmdln.gd -gtest=test_deployment_single_unit -gexit
```

7. **Compare artifacts:**
   - Compare screenshots: Before vs After
   - Load both save states to verify fix
   - Compare JSON reports to confirm game state matches expectations

---

## Advanced Configuration

### Custom Artifact Behavior Per Test

```gdscript
extends MultiplayerIntegrationTest

func test_critical_feature():
    """
    This is a critical test - capture EVERYTHING
    """
    # Override defaults for this specific test
    capture_screenshots_on_success = true  # Capture even on success
    save_state_on_completion = true

    current_test_name = "Critical Feature Test"  # Custom name for artifacts

    # Run test...
    await launch_host_and_client()
    # ... test logic ...

func test_quick_check():
    """
    Quick sanity check - minimal artifacts
    """
    # Minimal artifact capture
    capture_screenshots_on_failure = false
    save_state_on_completion = false

    # Run test...
```

### Artifact Cleanup

Old artifacts can accumulate - clean periodically:

```bash
# Remove all test artifacts
rm -rf ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/

# Remove artifacts older than 7 days
find ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/ \
    -type f -mtime +7 -delete
```

### Automated Artifact Analysis

Create a script to automatically analyze test artifacts:

```bash
#!/bin/bash
# analyze_test_artifacts.sh

ARTIFACTS_DIR="$HOME/Library/Application Support/Godot/app_userdata/40k/test_artifacts"

echo "=== Test Artifact Summary ==="
echo "Screenshots: $(find "$ARTIFACTS_DIR/screenshots" -name "*.png" | wc -l)"
echo "Save States: $(find "$ARTIFACTS_DIR/saves" -name "*.w40ksave" | wc -l)"
echo "Reports: $(find "$ARTIFACTS_DIR/reports" -name "*.json" | wc -l)"

echo "\n=== Recent Failures ==="
find "$ARTIFACTS_DIR/screenshots" -name "*_FAILED.png" -mtime -1 -print

echo "\n=== Disk Usage ==="
du -sh "$ARTIFACTS_DIR"
```

---

## Troubleshooting

### "Screenshots not being captured"

**Cause:** Screenshot action not implemented in TestModeHandler

**Solution:** Implement `capture_screenshot` action handler in TestModeHandler (future enhancement)

### "Save state capture fails"

**Cause:** `save_game_state` action not implemented

**Solution:** Implement action handler in TestModeHandler or disable save capture:
```gdscript
save_state_on_completion = false
```

### "Artifacts directory not created"

**Cause:** Insufficient permissions or _ensure_test_directories() not called

**Solution:** Check that test framework calls `_ensure_test_directories()` in `before_each()`

### "Can't find artifacts"

**Location varies by platform:**
- **macOS:** `~/Library/Application Support/Godot/app_userdata/40k/test_artifacts/`
- **Linux:** `~/.local/share/godot/app_userdata/40k/test_artifacts/`
- **Windows:** `%APPDATA%\Godot\app_userdata\40k\test_artifacts\`

---

## Benefits Summary

| Artifact Type | Best For | File Size | Interactive |
|--------------|----------|-----------|-------------|
| **Screenshots** | Quick visual verification | Small (~1MB) | No |
| **Save States** | Deep debugging, state examination | Medium (~5MB) | Yes |
| **JSON Reports** | Automated analysis, trends | Tiny (~10KB) | No |

**Recommended Configuration:**
- Development: Capture all artifacts
- CI/CD: Screenshots on failure + JSON reports
- Quick testing: JSON reports only

---

## Future Enhancements

Planned improvements to the artifact system:

1. **Video Recording** - Capture full test execution as video
2. **Diff Reports** - Automatically compare artifacts between runs
3. **Web Dashboard** - View all artifacts in browser
4. **Automated Cleanup** - Configurable retention policies
5. **Performance Metrics** - FPS, memory usage in reports

---

## See Also

- [Multiplayer Test Guide](./MULTIPLAYER_TEST_GUIDE.md) - How to run and write tests
- [Action Simulation System](./MULTIPLAYER_TEST_GUIDE.md#action-simulation-system) - Available test actions
- [Test Configuration](./MULTIPLAYER_TEST_GUIDE.md#test-configuration) - Customizing test behavior
