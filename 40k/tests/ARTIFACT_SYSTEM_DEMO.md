# Test Artifact System - Expected Output Demo

**Status:** Framework implemented, pending action handler completion
**Created:** 2025-10-29

---

## What You'll See When Running Tests

### During Test Execution

When you run a test with artifact capture enabled:

```bash
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gfile=test_multiplayer_deployment.gd \
    -gtest=test_deployment_single_unit \
    -gexit
```

### Console Output Example

```
========================================
Starting Multiplayer Integration Test
========================================

[TEST] test_deployment_single_unit
[Test] Launching host and client instances...
[Test] Host instance launched successfully on port 7777
[Test] Client instance launched successfully
[Test] Waiting for client to connect to host...
[Test] Connection verified - action simulation working!
[TEST] Loading save file: deployment_start
[TEST] Save loaded: 6 units available
[TEST] Player 1 undeployed units: ["unit_p1_blade_champion", "unit_p1_custodian_guard", "unit_p1_witchseekers"]
[TEST] Using unit: unit_p1_blade_champion
TestModeHandler: Unit deployed successfully
[TEST] PASSED: Unit deployment successful

========================================
Cleaning up Multiplayer Test
========================================

[Test Artifacts] Capturing screenshots...
[Test Artifacts] Host screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T16-45-23_host_PASSED.png
[Test Artifacts] Client screenshot: user://test_artifacts/screenshots/test_deployment_single_unit_2025-10-29T16-45-23_client_PASSED.png

[Test Artifacts] Capturing game state save...
[Test Artifacts] Save state captured: user://test_artifacts/saves/test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED.w40ksave
[Test Artifacts] Load with: SaveLoadManager.load_game('test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED')

[Test Artifacts] Report saved: user://test_artifacts/reports/test_deployment_single_unit_2025-10-29T16-45-23.json
```

---

## Generated Artifacts

### 1. Directory Structure

After running tests, you'll find:

```
~/Library/Application Support/Godot/app_userdata/40k/test_artifacts/
├── screenshots/
│   ├── test_deployment_single_unit_2025-10-29T16-45-23_host_PASSED.png
│   ├── test_deployment_single_unit_2025-10-29T16-45-23_client_PASSED.png
│   ├── test_deployment_outside_zone_2025-10-29T16-46-10_host_FAILED.png
│   └── test_deployment_outside_zone_2025-10-29T16-46-10_client_FAILED.png
├── saves/
│   ├── test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED.w40ksave
│   └── test_test_deployment_outside_zone_2025-10-29T16-46-10_FAILED.w40ksave
└── reports/
    ├── test_deployment_single_unit_2025-10-29T16-45-23.json
    └── test_deployment_outside_zone_2025-10-29T16-46-10.json
```

### 2. Screenshot Example

**File:** `test_deployment_single_unit_2025-10-29T16-45-23_host_PASSED.png`

**Contents:** PNG image showing:
- Game board with deployment zones
- Unit positioned at (5, 5)
- UI elements (phase indicator, turn counter)
- Player information
- Host window perspective

### 3. Save State Example

**File:** `test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED.w40ksave`

**Contents:** Binary save file containing:
```json
{
  "phase": "Deployment",
  "turn": 1,
  "active_player": 1,
  "units": {
    "unit_p1_blade_champion": {
      "id": "unit_p1_blade_champion",
      "owner": 1,
      "position": {"x": 5.0, "y": 5.0},
      "status": "DEPLOYED",
      "models": [...]
    },
    "unit_p1_custodian_guard": {...},
    "unit_p1_witchseekers": {...},
    ...
  },
  "terrain": [...],
  "objectives": [...]
}
```

**How to Load:**
1. Launch game
2. Load Game menu
3. Navigate to `test_artifacts/saves/`
4. Select file
5. Examine exact test state interactively

### 4. JSON Report Example

**File:** `test_deployment_single_unit_2025-10-29T16-45-23.json`

```json
{
	"test_name": "test_deployment_single_unit",
	"timestamp": "2025-10-29T16-45-23",
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
		"units": {
			"unit_p1_blade_champion": {
				"id": "unit_p1_blade_champion",
				"owner": 1,
				"status": "DEPLOYED",
				"position": {"x": 5.0, "y": 5.0}
			},
			"unit_p1_custodian_guard": {
				"id": "unit_p1_custodian_guard",
				"owner": 1,
				"status": "UNDEPLOYED"
			}
		}
	}
}
```

---

## Examining Artifacts

### Quick Visual Check

```bash
# Open screenshots directory
open ~/Library/Application\ Support/Godot/app_userdata/40k/test_artifacts/screenshots/

# View specific screenshot
open test_deployment_single_unit_2025-10-29T16-45-23_host_PASSED.png
```

### Load Save State

**Option 1: In-Game**
1. Run game normally
2. Main Menu → Load Game
3. Browse to test_artifacts/saves/
4. Load: `test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED`
5. Interact with exact test state

**Option 2: Programmatically**
```gdscript
# In Godot console or test
SaveLoadManager.load_game("test_test_deployment_single_unit_2025-10-29T16-45-23_PASSED")
```

### Analyze JSON Report

```bash
# Pretty print
cat test_deployment_single_unit_2025-10-29T16-45-23.json | python3 -m json.tool

# Extract specific data
cat report.json | grep "status"
cat report.json | grep "current_phase"
cat report.json | grep "failure_message"
```

---

## Expected Workflow: Debugging a Failed Test

### Step 1: Test Fails

```
[TEST] test_deployment_outside_zone
ERROR: Deployment should have been rejected but succeeded
[TEST] FAILED: Test assertion failed

[Test Artifacts] Capturing screenshots...
[Test Artifacts] Host screenshot: .../test_deployment_outside_zone_2025-10-29T16-46-10_host_FAILED.png
[Test Artifacts] Client screenshot: .../test_deployment_outside_zone_2025-10-29T16-46-10_client_FAILED.png
[Test Artifacts] Save state captured: .../test_test_deployment_outside_zone_2025-10-29T16-46-10_FAILED.w40ksave
[Test Artifacts] Report saved: .../test_deployment_outside_zone_2025-10-29T16-46-10.json
```

### Step 2: Quick Screenshot Check

```bash
open test_deployment_outside_zone_2025-10-29T16-46-10_host_FAILED.png
```

**What You See:**
- Unit appears at position (22, 30)
- Position is in middle of board (should be rejected)
- Visual confirms the bug: deployment validation not working

### Step 3: Deep Investigation - Load Save

Launch game and load:
`test_test_deployment_outside_zone_2025-10-29T16-46-10_FAILED`

**Interactive Examination:**
- Click on unit to see full stats
- Examine deployment zone boundaries
- Check terrain interactions
- Reproduce the bug manually
- Test potential fixes

### Step 4: Review JSON Report

```bash
cat test_deployment_outside_zone_2025-10-29T16-46-10.json | python3 -m json.tool
```

**Key Findings:**
```json
{
  "failure_message": "Deployment outside zone should be rejected",
  "final_game_state": {
    "current_phase": "Deployment",
    "units": {
      "unit_p1_blade_champion": {
        "position": {"x": 22.0, "y": 30.0},  // Outside zone!
        "status": "DEPLOYED"  // But still deployed!
      }
    }
  }
}
```

### Step 5: Fix and Verify

1. Fix deployment validation code
2. Re-run test
3. Compare new artifacts with old ones
4. Verify screenshots show proper rejection
5. Confirm JSON report shows PASSED status

---

## Current Implementation Status

### ✅ Implemented
- Artifact directory creation
- Configuration options
- Test lifecycle hooks (before_each/after_each)
- Artifact capture functions
- JSON report generation
- Screenshot capture framework
- Save state capture framework
- Documentation

### ⏳ Pending (Next Steps)
Two action handlers need to be added to TestModeHandler.gd:

1. **`capture_screenshot` action:**
```gdscript
func _handle_capture_screenshot(params: Dictionary) -> Dictionary:
    var filename = params.get("filename", "screenshot.png")
    var screenshot_path = OS.get_user_data_dir() + "/test_artifacts/screenshots/" + filename

    # Capture viewport to image
    var img = get_viewport().get_texture().get_image()
    img.save_png(screenshot_path)

    return {
        "success": true,
        "path": screenshot_path
    }
```

2. **`save_game_state` action:**
```gdscript
func _handle_save_game_state(params: Dictionary) -> Dictionary:
    var save_name = params.get("save_name", "test_save")
    var save_dir = params.get("save_dir", "saves/")

    # Use existing SaveLoadManager
    var full_path = OS.get_user_data_dir() + "/" + save_dir + save_name + ".w40ksave"
    SaveLoadManager.save_game(save_name, full_path)

    return {
        "success": true,
        "path": full_path
    }
```

---

## Benefits Demonstrated

| Artifact Type | Use Case | Time to Examine |
|--------------|----------|-----------------|
| **Screenshot** | Quick visual verification | 5 seconds |
| **Save State** | Deep debugging, reproduce bug | 30 seconds |
| **JSON Report** | Automated analysis, trending | 10 seconds |

**Combined Power:**
When a test fails, you get EVERYTHING needed to investigate:
1. Visual evidence (screenshots)
2. Interactive state (save files)
3. Structured data (JSON reports)

No more "I can't reproduce the issue" - you have the exact state captured!

---

## Next Session Tasks

To fully activate the artifact system:

1. **Add action handlers to TestModeHandler.gd:**
   - `_handle_capture_screenshot()`
   - `_handle_save_game_state()`

2. **Add to `_execute_command()` match statement:**
```gdscript
match action:
    "capture_screenshot":
        return _handle_capture_screenshot(params)
    "save_game_state":
        return _handle_save_game_state(params)
    # ... existing actions ...
```

3. **Run integration tests to verify**

4. **Enjoy comprehensive test artifacts!**

---

## Documentation References

- **Full Guide:** [TEST_ARTIFACTS_GUIDE.md](./TEST_ARTIFACTS_GUIDE.md)
- **Test Guide:** [MULTIPLAYER_TEST_GUIDE.md](./MULTIPLAYER_TEST_GUIDE.md)
- **Action System:** See MULTIPLAYER_TEST_GUIDE.md#action-simulation-system
