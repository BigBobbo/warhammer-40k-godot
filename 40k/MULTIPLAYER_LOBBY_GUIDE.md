# Multiplayer Lobby UI Guide

## Overview

The multiplayer lobby UI provides a user-friendly interface for hosting and joining multiplayer games. It is automatically hidden when `MULTIPLAYER_ENABLED = false` in FeatureFlags.gd.

## Files Created

1. **`scenes/MultiplayerLobby.tscn`** - Lobby scene with host/join UI
2. **`scripts/MultiplayerLobby.gd`** - Lobby logic and NetworkManager integration

## Files Modified

1. **`scenes/MainMenu.tscn`** - Added "Multiplayer" button
2. **`scripts/MainMenu.gd`** - Added multiplayer button handler (auto-hides when disabled)

## Features

### UI Components

**Mode Selection**:
- **Host Game** - Create a server and wait for players
- **Join Game** - Connect to an existing host

**Connection Settings**:
- **Port** - Default: 7777 (1-65535 valid range)
- **IP Address** - Default: 127.0.0.1 (localhost for testing)

**Status Display**:
- Connection status
- Informational messages
- Player count (0/2, 1/2, 2/2)

**Action Buttons**:
- **Start Game** - (Host only) Launch game when both players connected
- **Disconnect** - Leave current connection
- **Back to Menu** - Return to main menu

### User Flow

#### As Host:
1. Click "Multiplayer" from main menu
2. Enter port number (or use default 7777)
3. Click "Host Game"
4. Status shows "Hosting on port 7777"
5. Wait for player 2 to connect
6. When connected, click "Start Game"
7. Both players transition to battlefield

#### As Client:
1. Click "Multiplayer" from main menu
2. Enter host IP address (e.g., 192.168.1.100)
3. Enter host port number
4. Click "Join Game"
5. Status shows "Connecting..."
6. Wait for host to start game
7. Automatically transition to battlefield when host starts

### State Management

**Connection States**:
- **Not Connected** - Initial state, can host or join
- **Hosting** - Waiting for player 2
- **Connecting** - Attempting to join host
- **Connected** - Both players ready (2/2)

**UI State Changes**:
- Host/Join buttons disabled during connection
- Input fields locked during connection
- Start button enabled only when both players connected (host only)
- Disconnect button enabled during connection

### Error Handling

**Validation**:
- Port number must be 1-65535
- IP address required for joining
- Prevents invalid configurations

**Error Messages**:
- "Invalid port number"
- "Connection failed: [reason]"
- "Disconnected from host"
- "Only the host can start the game"
- "Waiting for player 2 to connect"

**Auto-Recovery**:
- Error messages display for 3 seconds
- UI resets to initial state after error
- Can retry connection after failure

### Integration with NetworkManager

**Signal Connections**:
- `peer_connected` - Update player count
- `peer_disconnected` - Handle disconnections
- `connection_failed` - Show error message
- `game_started` - Transition to game (clients)

**NetworkManager Methods Used**:
- `create_host(port)` - Start hosting
- `join_as_client(ip, port)` - Connect to host
- `disconnect_network()` - Leave game
- `is_networked()` - Check connection status

## Testing Locally

### Single Machine Testing (Two Instances)

1. **Enable Multiplayer**:
   ```gdscript
   # In 40k/autoloads/FeatureFlags.gd
   const MULTIPLAYER_ENABLED: bool = true  # Change to true
   ```

2. **Launch First Instance (Host)**:
   - Run game from Godot editor
   - Click "Multiplayer"
   - Click "Host Game" (port 7777)
   - Wait for connection

3. **Launch Second Instance (Client)**:
   - Open terminal
   - Navigate to project: `cd /Users/robertocallaghan/Documents/claude/godotv2/40k`
   - Run: `godot`
   - Click "Multiplayer"
   - Enter "127.0.0.1" (localhost)
   - Click "Join Game"

4. **Start Game**:
   - On host instance, click "Start Game"
   - Both instances transition to battlefield
   - Host controls Player 1, Client controls Player 2

### Network Testing (Multiple Machines)

1. **Host Machine**:
   - Find IP address: `ifconfig` (macOS/Linux) or `ipconfig` (Windows)
   - Note the local network IP (e.g., 192.168.1.100)
   - Host game on port 7777

2. **Client Machine**:
   - Enter host's IP address (e.g., 192.168.1.100)
   - Enter port 7777
   - Click "Join Game"

3. **Firewall Settings**:
   - Ensure port 7777 is open on host machine
   - Allow Godot through firewall

## Current Limitations (MVP)

1. **Two Players Only** - Hard-coded 2-player limit
2. **No Reconnection** - Disconnection ends game
3. **No Army Selection** - Uses default armies from main menu
4. **No Chat** - No communication besides game actions
5. **LAN Only** - No internet/relay server support

## Future Enhancements

- [ ] Army selection in lobby
- [ ] Player ready status indicators
- [ ] Lobby chat system
- [ ] Reconnection support
- [ ] Spectator mode
- [ ] Match history
- [ ] ELO/ranking system
- [ ] Internet play via relay servers

## Troubleshooting

**"Multiplayer button not visible"**:
- Set `MULTIPLAYER_ENABLED = true` in FeatureFlags.gd
- Restart Godot editor or reload the project
- Check console output for "MainMenu: Multiplayer button visible: true"

**"Connection failed"**:
- Verify IP address is correct
- Check port number (1-65535)
- Ensure host is running and hosting
- Check firewall settings

**"Failed to create host"**:
- Port may be in use by another application
- Try a different port number (e.g., 7778)
- Check firewall permissions

**"Player disconnected - game ending"**:
- Expected behavior in MVP
- No reconnection support yet
- Players must return to lobby and reconnect

## Architecture Notes

**Design Decisions**:
- Lobby is separate scene from main game
- NetworkManager handles all network logic
- UI is purely reactive to NetworkManager signals
- Feature flag allows safe rollout/testing

**Security**:
- Host validates all actions (see NetworkManager)
- Clients cannot cheat via UI manipulation
- RNG is deterministic via host seeds
- Turn timer enforced by host

## Code References

- **Lobby UI**: `40k/scenes/MultiplayerLobby.tscn:1`
- **Lobby Script**: `40k/scripts/MultiplayerLobby.gd:1`
- **Main Menu Button**: `40k/scenes/MainMenu.tscn:130`
- **Main Menu Handler**: `40k/scripts/MainMenu.gd:170`
- **Network Manager**: `40k/autoloads/NetworkManager.gd:1`
- **Feature Flags**: `40k/autoloads/FeatureFlags.gd:1`