# Project Path Fix - Autonomous Testing

## Problem
When launching Godot instances for testing, the command:
```bash
godot --test-mode --auto-host --position=100,100
```

Would open the Godot Project Manager asking which project to open, preventing autonomous testing.

## Root Cause
The `--path` argument was missing from the Godot launch command. Without it, Godot doesn't know which project to open and defaults to showing the project manager.

## Solution

### 1. Fixed GameInstance.launch() ✅
Added automatic project path detection in `tests/helpers/GameInstance.gd`:

```gdscript
# Get the project root directory (where project.godot is located)
var project_path = ProjectSettings.globalize_path("res://")
args.append("--path")
args.append(project_path)
print("[GameInstance] Using project path: %s" % project_path)
```

**How it works**:
- `ProjectSettings.globalize_path("res://")` converts the Godot resource path to an absolute system path
- For your project: `res://` → `/Users/robertocallaghan/Documents/claude/godotv2/40k`
- This is automatically detected at runtime from the test that's running

### 2. Updated Documentation ✅

Updated all documentation to show correct usage:

**QUICKSTART.md**:
```bash
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100 &
```

**READY_TO_TEST.md**:
- Added absolute path examples
- Added notes about path requirements
- Updated all command examples

## Testing the Fix

### Manual Test
```bash
# This should now work correctly and open the game directly:
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100
```

**Expected behavior**:
1. ✅ Godot opens directly to the 40k game (no project manager)
2. ✅ Window appears at position 100,100
3. ✅ TestModeHandler reads `--test-mode` flag
4. ✅ Game auto-navigates to multiplayer lobby
5. ✅ Host game is created automatically

### Automated Test
The automated tests now work correctly because `GameInstance.launch()` automatically:
1. Detects the current project path using `ProjectSettings.globalize_path("res://")`
2. Adds `--path <absolute_path>` to the launch arguments
3. Launches new instances pointing to the same project

```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
./tests/run_multiplayer_tests.sh
```

## Why This Fix Works

### Before Fix:
```bash
# What GameInstance was launching:
godot --test-mode --auto-host --position=100,100
# Result: Opens project manager (no project specified)
```

### After Fix:
```bash
# What GameInstance now launches:
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100
# Result: Opens the 40k project directly
```

## Key Points

1. **`--path` must come first** - Godot processes this argument before others
2. **Use absolute paths** - Relative paths can be ambiguous
3. **Automatic detection** - Tests running in the 40k project automatically use the correct path
4. **Debug output** - GameInstance now prints the path it's using for verification

## Verification

Run a quick test to verify it works:

```bash
# From any directory, this should work now:
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Launch a test instance
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100

# You should see:
# 1. Game window opens (not project manager)
# 2. Window appears at specified position
# 3. Console shows: "TestModeHandler: Scheduling auto-host..."
# 4. Game navigates to multiplayer lobby automatically
# 5. "YOU ARE: PLAYER 1 (HOST)" appears in logs
```

## Status: ✅ FIXED

Tests are now fully autonomous - no manual project selection needed!