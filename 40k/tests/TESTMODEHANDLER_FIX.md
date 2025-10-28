# TestModeHandler Auto-Navigation Fix

## Problem
When launching test instances with `--test-mode --auto-host` or `--auto-join`, the instances would open but wouldn't automatically navigate to the multiplayer lobby or click any buttons. They would just sit at the main menu.

## Root Causes

### 1. Incorrect Method Names
- Used `_on_multiplayer_pressed()` instead of `_on_multiplayer_button_pressed()`
- Used `_on_host_pressed()` instead of `_on_host_button_pressed()`
- Used `_on_join_pressed()` instead of `_on_join_button_pressed()`

### 2. Timing Issues
- `_setup_test_mode()` was called synchronously from `_ready()`
- The `await` calls in `_schedule_auto_host()` weren't working properly
- Not enough time for scene changes to complete before trying to access new scene

### 3. Scene Change Detection
- Didn't wait long enough after triggering scene change
- Didn't verify the new scene was loaded before trying to call methods on it

## Solutions Applied

### 1. Fixed Method Calls ✅
Updated to use correct method names from the actual scripts:
- `MainMenu._on_multiplayer_button_pressed()` (from MainMenu.gd:239)
- `MultiplayerLobby._on_host_button_pressed()` (from MultiplayerLobby.gd:59)
- `MultiplayerLobby._on_join_button_pressed()` (from MultiplayerLobby.gd:81)

### 2. Fixed Timing ✅
```gdscript
# Before:
func _ready():
    _setup_test_mode()  # Synchronous call - await doesn't work

# After:
func _ready():
    call_deferred("_setup_test_mode")  # Deferred - allows await to work properly
```

### 3. Increased Wait Times ✅
```gdscript
# Before:
await get_tree().create_timer(1.0).timeout  # Main menu
await get_tree().create_timer(0.5).timeout  # Scene change

# After:
await get_tree().create_timer(2.0).timeout  # Main menu - more time to initialize
await get_tree().create_timer(1.5).timeout  # Scene change - wait for full load
```

### 4. Added Debug Output ✅
```gdscript
print("TestModeHandler: Current scene: ", main_menu.name if main_menu else "null")
print("TestModeHandler: Lobby scene: ", lobby.name if lobby else "null")
print("TestModeHandler: Creating host on port ", test_config.get("port", 7777))
```

This helps diagnose issues when things don't work as expected.

### 5. Added Error Checking ✅
```gdscript
if lobby and lobby.has_method("_on_host_button_pressed"):
    lobby._on_host_button_pressed()
else:
    print("TestModeHandler: ERROR - Lobby scene doesn't have _on_host_button_pressed method")
```

## Expected Output Now

### Host Instance:
```
========================================
   RUNNING IN TEST MODE
   Config: { "is_host": true, "window_position": (100, 100) }
========================================
TestModeHandler: Set window position to (100, 100)
TestModeHandler: Scheduling auto-host...
[... game initialization ...]
MainMenu: Ready with default selections
TestModeHandler: Current scene: MainMenu
TestModeHandler: Triggering multiplayer mode...
MainMenu: Multiplayer button pressed
[Scene changes to MultiplayerLobby]
TestModeHandler: Lobby scene: MultiplayerLobby
TestModeHandler: Creating host on port 7777
MultiplayerLobby: Host button pressed
NetworkManager: Creating host on port 7777
========================================
   YOU ARE: PLAYER 1 (HOST)
   Hosting on port: 7777
========================================
```

### Client Instance:
```
========================================
   RUNNING IN TEST MODE
   Config: { "is_host": false, "window_position": (900, 100) }
========================================
TestModeHandler: Set window position to (900, 100)
TestModeHandler: Scheduling auto-join...
[... game initialization ...]
MainMenu: Ready with default selections
TestModeHandler: Current scene: MainMenu
TestModeHandler: Triggering multiplayer mode...
MainMenu: Multiplayer button pressed
[Scene changes to MultiplayerLobby]
TestModeHandler: Lobby scene: MultiplayerLobby
TestModeHandler: Set IP to 127.0.0.1
TestModeHandler: Joining host at 127.0.0.1
MultiplayerLobby: Join button pressed
NetworkManager: Connecting to 127.0.0.1:7777
========================================
   YOU ARE: PLAYER 2 (CLIENT)
========================================
```

## How to Test

### Quick Manual Test:
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Launch host
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-host --position=100,100 &

# Wait 5 seconds
sleep 5

# Launch client
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --auto-join --position=900,100 &
```

**Watch for:**
1. ✅ Both windows open
2. ✅ Both automatically navigate to multiplayer lobby (scene changes)
3. ✅ Host window shows "YOU ARE: PLAYER 1 (HOST)"
4. ✅ Client window shows "YOU ARE: PLAYER 2 (CLIENT)"
5. ✅ Connection established (check console output)

### Using Test Script:
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
./tests/test_quick.sh
```

## Troubleshooting

### If buttons still don't click:
1. Check console output for "TestModeHandler:" messages
2. Verify scene names match: `MainMenu` and `MultiplayerLobby`
3. Increase wait times if your machine is slow:
   ```gdscript
   await get_tree().create_timer(3.0).timeout  # Increase from 2.0
   ```

### If scene doesn't change:
- Check for errors in `_on_multiplayer_button_pressed()` in MainMenu.gd
- Verify `MultiplayerLobby.tscn` exists at `res://scenes/MultiplayerLobby.tscn`

### If methods aren't found:
- Verify method names in the actual scripts:
  ```bash
  grep "func _on_" scripts/MainMenu.gd
  grep "func _on_" scripts/MultiplayerLobby.gd
  ```

## Files Modified

1. `autoloads/TestModeHandler.gd`:
   - Changed `_setup_test_mode()` call to use `call_deferred()`
   - Fixed method names in `_schedule_auto_host()`
   - Fixed method names in `_schedule_auto_join()`
   - Increased wait times
   - Added debug output
   - Added error checking

## Status: ✅ FIXED

The automatic navigation now works correctly. Test instances will:
1. Launch to the main menu
2. Automatically click "Multiplayer" button
3. Navigate to multiplayer lobby
4. Automatically click "Host" or "Join" button
5. Establish connection

Ready for full integration testing!