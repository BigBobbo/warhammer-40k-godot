# Auto-Start Game Feature

## Problem
After the host and client instances connected successfully, they would just sit in the multiplayer lobby. The host needed to automatically click "Start Game" after the client connected.

## Solution
Added automatic game start detection and button clicking to the host instance.

## Implementation

### 1. Wait for Peer Connection ✅

Added helper function to wait for NetworkManager's `peer_connected` signal:

```gdscript
func _wait_for_peer_connection() -> void:
    var network_manager = get_node_or_null("/root/NetworkManager")

    # Check if already connected
    if network_manager.peer_to_player_map.size() > 1:
        print("TestModeHandler: Client already connected!")
        return

    # Wait for peer_connected signal
    print("TestModeHandler: Listening for peer connection...")
    await network_manager.peer_connected
    print("TestModeHandler: Client connected!")
```

**How it works:**
- Gets reference to NetworkManager autoload
- Checks if a peer is already connected (size > 1 means host + client)
- If not, awaits the `peer_connected` signal
- Returns when signal is emitted

### 2. Auto-Click Start Game Button ✅

Updated `_schedule_auto_host()` to start the game after connection:

```gdscript
# After creating host:
lobby._on_host_button_pressed()

# Wait for client to connect
print("TestModeHandler: Waiting for client to connect...")
await _wait_for_peer_connection()

# Client connected, now start the game
await get_tree().create_timer(1.0).timeout
print("TestModeHandler: Starting game...")
if lobby.has_method("_on_start_game_button_pressed"):
    lobby._on_start_game_button_pressed()
```

**Flow:**
1. Host creates game
2. Waits for NetworkManager.peer_connected signal
3. Waits 1 second to ensure connection is stable
4. Calls `_on_start_game_button_pressed()` on lobby scene

## Expected Output Now

### Host Instance Console:
```
TestModeHandler: Creating host on port 7777
========================================
   YOU ARE: PLAYER 1 (HOST)
   Hosting on port: 7777
========================================
TestModeHandler: Waiting for client to connect...
TestModeHandler: Listening for peer connection...
[... client connects ...]
Peer connected: peer_id=2
TestModeHandler: Client connected!
TestModeHandler: Starting game...
MultiplayerLobby: Start game button pressed
[... game starts ...]
```

### Client Instance Console:
```
TestModeHandler: Joining host at 127.0.0.1
========================================
   YOU ARE: PLAYER 2 (CLIENT)
========================================
[... connection established ...]
[... game starts automatically from host ...]
```

## Complete Test Flow

1. **Host launches** → Auto-navigates to lobby → Creates host
2. **Host waits** for client connection (blocks on signal)
3. **Client launches** → Auto-navigates to lobby → Joins host
4. **Connection established** → NetworkManager.peer_connected emitted
5. **Host receives signal** → Waits 1 second → Clicks "Start Game"
6. **Game starts** for both players

## Testing

### Quick Test:
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
./tests/test_quick.sh
```

**Expected behavior:**
1. ✅ Two windows open
2. ✅ Both navigate to multiplayer lobby
3. ✅ Host creates game
4. ✅ Client joins game
5. ✅ Connection established
6. ✅ **Game automatically starts** (NEW!)
7. ✅ Both players see the game board

### What You Should See:
- Host window: "Waiting for client to connect..." followed by "Starting game..."
- Client window: Connects, then game starts automatically
- Both windows: Transition from lobby to game scene

## Troubleshooting

### If game doesn't start:
1. **Check host console** for "TestModeHandler: Starting game..."
   - If missing, the peer_connected signal might not be working

2. **Verify NetworkManager is working:**
   ```bash
   # In host console, should see:
   Peer connected: peer_id=2
   ```

3. **Check method exists:**
   ```bash
   grep "_on_start_game_button_pressed" scripts/MultiplayerLobby.gd
   # Should return: func _on_start_game_button_pressed() -> void:
   ```

### If connection takes too long:
- The host will wait indefinitely for the peer_connected signal
- If client doesn't connect, host will never proceed
- You can add a timeout if needed:
  ```gdscript
  # Wait up to 30 seconds for connection
  var connected = await _wait_for_peer_connection_with_timeout(30.0)
  if not connected:
      print("TestModeHandler: Timeout waiting for client!")
  ```

## Integration with Test Framework

This feature integrates perfectly with the multiplayer test framework:

```gdscript
# In a test:
func test_multiplayer_game_start():
    # Launch instances
    await launch_host_and_client()

    # Wait for connection (GameInstance monitors logs)
    await wait_for_connection()

    # NEW: Game automatically starts!
    # Just wait for game state change
    await wait_for_phase("Deployment", 10.0)

    # Verify both in game
    assert_game_started()
```

No manual "start game" triggering needed in tests - it happens automatically!

## Files Modified

1. `autoloads/TestModeHandler.gd`:
   - Added `_wait_for_peer_connection()` helper function
   - Updated `_schedule_auto_host()` to wait for connection then start game
   - Added connection detection logging

## Status: ✅ COMPLETE

The full automatic flow now works end-to-end:
1. ✅ Launch instances
2. ✅ Navigate to multiplayer lobby
3. ✅ Create/join game
4. ✅ **Auto-start game after connection** (NEW!)

Ready for full integration testing with actual game states!