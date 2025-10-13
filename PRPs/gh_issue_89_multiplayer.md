# PRP: Multiplayer Implementation for Warhammer 40K Game
**GitHub Issue**: #89
**Feature**: Online Multiplayer Support
**Confidence Level**: 7/10

## Executive Summary
Transform the current local hot-seat turn-based game into an online multiplayer experience where two players can play from separate computers. This implementation will leverage Godot 4's networking capabilities while preserving the existing game architecture and state management systems.

## Context and Requirements

### Current State Analysis
The game currently operates as a single-instance application where:
- Players take turns on the same computer
- Game state is managed through a centralized `GameState` singleton (40k/autoloads/GameState.gd)
- Actions are logged via `ActionLogger` (40k/autoloads/ActionLogger.gd)
- Turn/phase management handled by `TurnManager` and `PhaseManager` autoloads
- No existing networking code in the codebase

### Key Technical Considerations
- **Turn-based nature**: Game doesn't require real-time synchronization, simplifying networking
- **Existing architecture**: Comprehensive state management and action logging systems already in place
- **Security**: Must prevent cheating and ensure fair play
- **Reliability**: Handle disconnections gracefully without losing game state
- **Performance**: Minimize bandwidth usage for smooth gameplay

## Implementation Approaches

### Approach 1: Authoritative Server Architecture
**Pros:**
- Most secure against cheating
- Central source of truth for game state
- Can support spectators and replay systems

**Cons:**
- Requires dedicated server infrastructure
- More complex to implement
- Additional hosting costs

### Approach 2: Peer-to-Peer with Host Authority
**Pros:**
- No dedicated server needed
- Host acts as authoritative server
- Simpler infrastructure

**Cons:**
- Host has slight advantage
- Game ends if host disconnects
- More complex NAT traversal

### Approach 3: State Synchronization
**Pros:**
- Simple implementation for turn-based games
- Full state verification on each turn

**Cons:**
- High bandwidth for large game states
- Slower synchronization

### Approach 4: Action-Based Synchronization (RECOMMENDED)
**Pros:**
- Efficient bandwidth usage
- Leverages existing `ActionLogger` system
- Natural fit for turn-based gameplay
- Can replay entire game from action log

**Cons:**
- Requires deterministic game logic
- Desync possible if logic differs

### Approach 5: Hybrid Host-Authority with Action Sync (SELECTED)
**Combines the best of approaches 2 and 4:**
- One player hosts and has authority
- Actions are synchronized, not full state
- Host validates all actions
- Periodic state verification for anti-cheat
- Graceful host migration if needed

## Selected Implementation: Hybrid Host-Authority with Action Synchronization

### Architecture Overview
```
┌─────────────┐                     ┌─────────────┐
│   Host      │  <-- Actions -->    │   Client    │
│ (Player 1)  │  <-- State Sync --> │ (Player 2)  │
│             │                     │             │
│ Authoritative                     │ Predictive  │
│   State     │                     │   State     │
└─────────────┘                     └─────────────┘
```

### Core Components

#### 1. NetworkManager (New Autoload)
```gdscript
# 40k/autoloads/NetworkManager.gd
extends Node

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal game_synchronized()

enum NetworkMode { OFFLINE, HOST, CLIENT }
var network_mode: NetworkMode = NetworkMode.OFFLINE
var peer: MultiplayerPeer
```

#### 2. MultiplayerGameState (Extends GameState)
```gdscript
# 40k/autoloads/MultiplayerGameState.gd
extends Node

@rpc("any_peer", "call_local", "reliable")
func submit_action(action: Dictionary) -> void:
    if multiplayer.is_server():
        validate_and_apply_action(action)

@rpc("authority", "call_local", "reliable")
func sync_state(state: Dictionary) -> void:
    GameState.load_state(state)
```

#### 3. MultiplayerPhaseManager (Extends PhaseManager)
Intercepts phase actions and routes them through network

#### 4. LobbySystem (New Scene)
- Host/Join UI
- Player readiness system
- Army selection synchronization
- Connection status display

### Implementation Blueprint

```gdscript
# Pseudocode for core multiplayer flow

# HOST SIDE
func host_game(port: int = 7000):
    peer = ENetMultiplayerPeer.new()
    peer.create_server(port, 2)  # Max 2 players
    multiplayer.multiplayer_peer = peer

    # Wait for client connection
    multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int):
    # Send initial game state to client
    rpc_id(id, "receive_initial_state", GameState.create_snapshot())

func process_client_action(action: Dictionary):
    # Validate action
    var validation = PhaseManager.validate_phase_action(action)
    if validation.valid:
        # Apply action
        PhaseManager.execute_action(action)
        # Broadcast to all clients
        rpc("apply_verified_action", action)
    else:
        # Reject and sync correct state
        rpc_id(action.peer_id, "sync_state", GameState.create_snapshot())

# CLIENT SIDE
func join_game(address: String, port: int = 7000):
    peer = ENetMultiplayerPeer.new()
    peer.create_client(address, port)
    multiplayer.multiplayer_peer = peer

func submit_turn_action(action: Dictionary):
    # Add peer identification
    action.peer_id = multiplayer.get_unique_id()

    # Send to host for validation
    rpc_id(1, "process_client_action", action)

    # Optimistic local update (will be corrected if invalid)
    PhaseManager.execute_action(action)

@rpc("authority", "call_local", "reliable")
func apply_verified_action(action: Dictionary):
    # Apply host-verified action
    PhaseManager.execute_action(action)
```

### Key Files to Reference
- `40k/autoloads/GameState.gd` - State management system
- `40k/autoloads/ActionLogger.gd` - Action tracking system
- `40k/autoloads/PhaseManager.gd` - Phase control system
- `40k/autoloads/TurnManager.gd` - Turn management
- `40k/phases/BasePhase.gd` - Base phase class
- `40k/scripts/Main.gd` - Main game scene

### Integration Points

#### Phase Controllers
Each phase controller needs network awareness:
- `DeploymentPhase.gd` - Unit placement sync
- `MovementPhase.gd` - Movement action sync
- `ShootingPhase.gd` - Combat resolution sync
- Other phase controllers follow same pattern

#### Save/Load System
Modify `SaveLoadManager.gd` to:
- Save network game state
- Support reconnection to ongoing games
- Store host/client role information

## Implementation Tasks

### Phase 1: Core Networking Infrastructure
1. Create NetworkManager autoload
2. Implement host/client connection system
3. Add RPC methods for action submission
4. Create lobby scene with connection UI
5. Test basic connectivity

### Phase 2: Action Synchronization
6. Extend ActionLogger for network actions
7. Add network validation to PhaseManager
8. Implement action broadcast system
9. Add peer identification to actions
10. Test action synchronization

### Phase 3: State Verification
11. Implement periodic state checksums
12. Add desync detection
13. Create state reconciliation system
14. Implement host migration (optional)
15. Test state consistency

### Phase 4: User Experience
16. Add connection status UI
17. Implement disconnect handling
18. Add reconnection support
19. Create in-game chat (optional)
20. Polish lobby interface

### Phase 5: Testing & Optimization
21. Comprehensive multiplayer testing
22. Optimize network traffic
23. Add lag compensation (if needed)
24. Security hardening
25. Performance profiling

## Error Handling Strategy

### Connection Issues
```gdscript
func _on_connection_failed():
    # Return to lobby
    # Show error message
    # Attempt reconnection (with backoff)

func _on_peer_disconnected(id: int):
    if GameState.is_game_in_progress():
        # Pause game
        # Show "Waiting for player" dialog
        # Start reconnection timer
        # Save game state for recovery
```

### Desync Handling
```gdscript
func detect_desync():
    # Compare state hashes periodically
    if local_hash != host_hash:
        # Request full state sync
        # Log desync for debugging
        # Restore to last known good state
```

## Validation Gates

```bash
# Create test script for multiplayer
cat > 40k/tests/multiplayer/test_network_integration.gd << 'EOF'
extends GutTest

func test_host_client_connection():
    # Test basic connectivity
    pass

func test_action_synchronization():
    # Test action sync between host/client
    pass

func test_state_verification():
    # Test state consistency checks
    pass

func test_disconnection_handling():
    # Test graceful disconnect/reconnect
    pass
EOF

# Run tests
export PATH="$HOME/bin:$PATH"
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/multiplayer/test_network_integration.gd
```

## Documentation References

### Godot 4 Networking
- High-level Multiplayer: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- RPC System: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html#remote-procedure-calls
- MultiplayerAPI: https://docs.godotengine.org/en/4.4/classes/class_multiplayerapi.html
- MultiplayerPeer: https://docs.godotengine.org/en/4.4/classes/class_multiplayerpeer.html

### Example Projects
- Godot Multiplayer Demo: https://github.com/godotengine/godot-demo-projects/tree/master/networking
- Turn-based Examples: https://github.com/db0/godot-card-game-framework (card game but similar turn structure)

## Security Considerations

### Anti-Cheat Measures
1. **Action Validation**: Host validates all client actions
2. **State Verification**: Periodic state hash comparisons
3. **Input Sanitization**: Validate all RPC parameters
4. **Authority Checks**: Only active player can submit turn actions
5. **Replay System**: All actions logged for audit

### Network Security
```gdscript
# Validate RPC calls
func _validate_rpc_caller(action: Dictionary) -> bool:
    var sender = multiplayer.get_remote_sender_id()
    var expected_player = GameState.get_active_player()
    var sender_player = get_player_from_peer_id(sender)

    return sender_player == expected_player
```

## Performance Optimizations

### Bandwidth Reduction
1. Send only actions, not full state
2. Compress large messages
3. Batch multiple actions when possible
4. Delta compression for state syncs
5. Lazy loading of non-critical data

### Latency Mitigation
1. Client-side prediction for own actions
2. Action queuing system
3. Asynchronous state verification
4. Regional server selection (future)

## Migration Path

### Phase 1: Minimal Viable Multiplayer
- Basic host/join functionality
- Action synchronization for one phase (Movement)
- No reconnection support

### Phase 2: Full Game Support
- All phases networked
- Save/load for network games
- Basic disconnection handling

### Phase 3: Production Ready
- Full error handling
- Reconnection support
- Performance optimizations
- Security hardening

## Testing Checklist

- [ ] Host can create game
- [ ] Client can join game
- [ ] Initial state syncs correctly
- [ ] Actions sync between players
- [ ] Turn switching works
- [ ] All phases function over network
- [ ] Disconnection handled gracefully
- [ ] Reconnection works
- [ ] State remains consistent
- [ ] No gameplay regressions

## Known Limitations

1. **NAT Traversal**: Players may need port forwarding
2. **Host Advantage**: Host has zero latency
3. **No Dedicated Servers**: Requires player hosting
4. **Two Players Only**: Current design limits to 2 players

## Future Enhancements

1. **Dedicated Server Mode**: Headless server for tournaments
2. **Spectator Mode**: Allow observers
3. **Replay Sharing**: Share and replay games
4. **Matchmaking**: Automatic opponent finding
5. **Multiple Game Modes**: 2v2, free-for-all, etc.

## Conclusion

This implementation leverages the existing robust state management and action logging systems to add multiplayer with minimal disruption to the current codebase. The hybrid approach balances security, performance, and implementation complexity while providing a solid foundation for future enhancements.

**Confidence Score: 7/10**

The architecture is sound and builds on existing systems. The main challenges will be:
- Ensuring deterministic game logic
- Handling edge cases in disconnection/reconnection
- Optimizing network performance
- Testing all game phases thoroughly

The comprehensive action logging and state management systems already in place significantly reduce implementation complexity compared to starting from scratch.