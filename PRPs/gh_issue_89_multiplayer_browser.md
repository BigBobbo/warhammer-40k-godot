# PRP: Browser-Based Multiplayer Implementation for Warhammer 40K Game
**GitHub Issue**: #89 (Browser Variant)
**Feature**: Online Multiplayer Support for Web Browsers
**Confidence Level**: 6/10

## Executive Summary
Transform the current local hot-seat turn-based game into a browser-playable online multiplayer experience. This requires significant architectural changes as **ENet cannot be used in browsers** due to security restrictions. The implementation must use either WebSocket or WebRTC.

## Critical Browser Constraints

### Cannot Use in Browser:
- **ENet** - Browsers block UDP packets for security
- **Direct peer-to-peer** without signaling server
- **File system access** for saves/logs
- **Native threading**

### Must Use Instead:
- **WebSocket** (TCP-only) or **WebRTC** (TCP/UDP-like)
- **Signaling/relay server** for connections
- **IndexedDB/LocalStorage** for client persistence
- **Web Workers** for heavy processing

## Revised Architecture Decision

### RECOMMENDED: WebSocket with Authoritative Server
Given the browser constraints and turn-based nature of Warhammer 40K, **WebSocket with an authoritative server** is the optimal choice:

**Why WebSocket over WebRTC for this game:**
- **Turn-based gameplay** doesn't need low-latency UDP
- **Simpler implementation** - no STUN/TURN complexity
- **Better browser compatibility**
- **Easier debugging** - standard HTTP/WS tools work
- **Lower hosting costs** - no TURN relay needed

**Architecture:**
```
┌─────────────┐       WebSocket        ┌─────────────┐
│  Browser    │ <===================> │   Server    │
│  Client 1   │                       │   (Node.js  │
└─────────────┘                       │   or Godot) │
                                      │             │
┌─────────────┐       WebSocket        │  Authority  │
│  Browser    │ <===================> │   & State   │
│  Client 2   │                       └─────────────┘
└─────────────┘
```

## Implementation Strategy

### Server Options

#### Option 1: Godot Headless Server (RECOMMENDED)
```gdscript
# 40k/server/GameServer.gd
extends Node

var websocket_server: WebSocketMultiplayerPeer
var games: Dictionary = {} # game_id -> GameInstance
var players: Dictionary = {} # peer_id -> player_data

func start_server(port: int = 9080):
    websocket_server = WebSocketMultiplayerPeer.new()
    websocket_server.create_server(port)
    multiplayer.multiplayer_peer = websocket_server

    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
```

#### Option 2: Node.js/Deno Server
- Separate server implementation
- Can scale independently
- Requires duplicating game logic

### Client Implementation

```gdscript
# 40k/autoloads/BrowserNetworkManager.gd
extends Node

signal connected_to_server()
signal disconnected_from_server()
signal game_joined(game_id: String)

var websocket_peer: WebSocketMultiplayerPeer
var server_url: String = "wss://your-server.com:9080"

func connect_to_server():
    websocket_peer = WebSocketMultiplayerPeer.new()

    # For browser builds, use WSS (secure WebSocket)
    if OS.has_feature("web"):
        server_url = "wss://" + server_url
    else:
        server_url = "ws://" + server_url

    var error = websocket_peer.create_client(server_url)
    if error == OK:
        multiplayer.multiplayer_peer = websocket_peer
        multiplayer.connected_to_server.connect(_on_connected)
        multiplayer.connection_failed.connect(_on_connection_failed)
        multiplayer.server_disconnected.connect(_on_disconnected)
```

### Browser-Specific Adaptations

#### 1. Platform Detection
```gdscript
func _ready():
    if OS.has_feature("web"):
        # Browser-specific initialization
        setup_browser_networking()
    else:
        # Desktop can use ENet or WebSocket
        setup_desktop_networking()
```

#### 2. Save System Adaptation
```gdscript
# 40k/autoloads/BrowserSaveManager.gd
extends Node

func save_game_browser(save_data: Dictionary):
    if OS.has_feature("web"):
        # Use JavaScript interface to save to IndexedDB
        JavaScriptBridge.eval("""
            localStorage.setItem('w40k_save', JSON.stringify(%s));
        """ % JSON.stringify(save_data))
    else:
        # Use regular file system
        SaveLoadManager.save_game(save_data)
```

#### 3. Matchmaking/Lobby System
```gdscript
# 40k/scenes/BrowserLobby.gd
extends Control

@onready var game_code_input: LineEdit = $GameCodeInput
@onready var create_button: Button = $CreateButton
@onready var join_button: Button = $JoinButton

func _on_create_pressed():
    rpc_id(1, "create_game", GameState.get_army_selection())

func _on_join_pressed():
    var code = game_code_input.text
    rpc_id(1, "join_game", code, GameState.get_army_selection())

@rpc("authority", "call_local", "reliable")
func game_created(game_code: String):
    # Display code for sharing
    show_game_code(game_code)

@rpc("authority", "call_local", "reliable")
func game_joined(game_state: Dictionary):
    # Load game state and start
    GameState.load_state(game_state)
    get_tree().change_scene_to_file("res://40k/scenes/Main.tscn")
```

## Server Infrastructure Requirements

### Hosting Options

#### 1. Self-Hosted VPS
- **Pros**: Full control, cost-effective at scale
- **Cons**: Maintenance burden, scaling complexity

#### 2. Cloud Gaming Services
- **AWS GameLift**: Auto-scaling, matchmaking
- **Google Cloud Game Servers**: Kubernetes-based
- **Azure PlayFab**: Integrated backend services

#### 3. Serverless Functions + WebSocket
- **Cloudflare Workers**: Global edge network
- **AWS Lambda + API Gateway**: Pay-per-use
- **Deno Deploy**: TypeScript native

### Recommended Stack
```yaml
# docker-compose.yml
version: '3.8'
services:
  game-server:
    image: godot-headless:4.3
    command: ["--headless", "--server", "40k/server/server.tscn"]
    ports:
      - "9080:9080"  # WebSocket
    environment:
      - MAX_GAMES=100
      - MAX_PLAYERS=200

  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./ssl:/etc/nginx/ssl
      - ./nginx.conf:/etc/nginx/nginx.conf
    # Handles WSS termination and serves game files
```

## Modified Implementation Tasks

### Phase 1: Server Infrastructure
1. Set up WebSocket server (Godot headless or Node.js)
2. Implement game session management
3. Create matchmaking/lobby system
4. Deploy to cloud provider with SSL/WSS
5. Test WebSocket connectivity

### Phase 2: Client Adaptation
6. Replace ENet with WebSocketMultiplayerPeer
7. Implement browser-specific save system
8. Add connection status UI
9. Create game code sharing system
10. Test in multiple browsers

### Phase 3: State Synchronization
11. Implement authoritative server logic
12. Add client-side prediction for responsiveness
13. Create state reconciliation system
14. Add anti-cheat validation
15. Test state consistency

### Phase 4: Browser Optimizations
16. Optimize asset loading (texture atlases, audio sprites)
17. Implement progressive web app (PWA) features
18. Add offline mode with AI opponent
19. Optimize for mobile browsers
20. Add touch controls for tablets

### Phase 5: Production Readiness
21. Set up CDN for game assets
22. Implement player authentication (OAuth, etc.)
23. Add analytics and error tracking
24. Create automated deployment pipeline
25. Load testing and optimization

## Browser-Specific Code Examples

### Connection Management
```gdscript
# Handle browser tab close/refresh
func _notification(what: int):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if OS.has_feature("web"):
            # Notify server of disconnection
            rpc_id(1, "player_leaving")
            # Save game state to localStorage
            save_game_browser()
```

### Responsive Networking
```gdscript
# Adaptive quality based on connection
var latency_ms: float = 0
var packet_loss: float = 0

func measure_connection_quality():
    var start = Time.get_ticks_msec()
    rpc_id(1, "ping")

@rpc("authority", "call_local", "reliable")
func pong():
    latency_ms = Time.get_ticks_msec() - start

    if latency_ms > 200:
        # Reduce update frequency
        set_physics_process_internal(false)
```

### Browser API Integration
```gdscript
# Share game link
func share_game_link(game_code: String):
    if OS.has_feature("web"):
        var url = "https://yourgame.com/join?code=" + game_code
        JavaScriptBridge.eval("""
            if (navigator.share) {
                navigator.share({
                    title: 'Join my Warhammer 40K game!',
                    url: '%s'
                });
            } else {
                navigator.clipboard.writeText('%s');
                alert('Game link copied to clipboard!');
            }
        """ % [url, url])
```

## Security Considerations

### Browser-Specific Threats
1. **JavaScript injection**: Validate all inputs
2. **Local storage tampering**: Never trust client data
3. **Network inspection**: All game logic server-side
4. **Cross-site scripting**: Sanitize all displayed content

### Mitigation Strategies
```gdscript
# Server-side validation
@rpc("any_peer", "call_local", "reliable")
func submit_action(action: Dictionary):
    var peer_id = multiplayer.get_remote_sender_id()

    # Validate peer owns the unit
    if not validate_action_ownership(peer_id, action):
        kick_player(peer_id, "Invalid action")
        return

    # Validate action is legal
    if not PhaseManager.validate_action(action):
        sync_state_to_peer(peer_id)
        return

    # Apply and broadcast
    apply_action(action)
    rpc("receive_action", action)
```

## Performance Optimizations

### Asset Loading
```gdscript
# Progressive loading for browsers
func load_assets_progressive():
    # Load critical assets first
    await load_ui_assets()
    emit_signal("ready_to_play")

    # Load additional assets in background
    load_models_async()
    load_sounds_async()
```

### State Compression
```gdscript
# Compress state for network transfer
func compress_state(state: Dictionary) -> PackedByteArray:
    var json = JSON.stringify(state)
    return json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)

func decompress_state(data: PackedByteArray) -> Dictionary:
    var json = data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
    return JSON.parse_string(json)
```

## Testing Strategy

### Browser Compatibility Matrix
- **Chrome/Edge**: Primary target (85%+ market share)
- **Firefox**: Full support required
- **Safari**: WebSocket quirks to handle
- **Mobile browsers**: Touch controls needed

### Test Scenarios
```bash
# Automated browser tests (using Playwright)
npm install -D @playwright/test

# test/multiplayer.spec.js
test('two players can join game', async ({ browser }) => {
  const context1 = await browser.newContext();
  const context2 = await browser.newContext();

  const player1 = await context1.newPage();
  const player2 = await context2.newPage();

  await player1.goto('https://localhost:3000');
  await player1.click('#create-game');
  const gameCode = await player1.textContent('#game-code');

  await player2.goto('https://localhost:3000');
  await player2.fill('#join-code', gameCode);
  await player2.click('#join-game');

  // Verify both players in game
  await expect(player1).toHaveText('#player-count', '2/2');
  await expect(player2).toHaveText('#player-count', '2/2');
});
```

## Migration Path for Browser

### Step 1: Local Development
- Implement WebSocket networking alongside ENet
- Test locally with Godot editor

### Step 2: Browser Export Testing
- Export to HTML5
- Test on local web server
- Fix browser-specific issues

### Step 3: Server Deployment
- Deploy server to cloud
- Set up SSL certificates
- Test with remote server

### Step 4: Beta Testing
- Limited release to test group
- Monitor performance metrics
- Gather feedback

### Step 5: Production Launch
- Scale infrastructure
- Add monitoring/analytics
- Progressive rollout

## Conclusion

Browser deployment fundamentally changes the multiplayer architecture:

1. **Must use WebSocket** instead of ENet (TCP-only, higher latency acceptable for turn-based)
2. **Requires always-online server** (no peer-to-peer hosting)
3. **Need web infrastructure** (SSL, CDN, hosting)
4. **Browser limitations** require adaptations (storage, performance)

However, the benefits are substantial:
- **No installation required** - instant play
- **Cross-platform by default** - works everywhere
- **Easy sharing** - just send a link
- **Automatic updates** - no patching

**Revised Confidence Score: 6/10**

The browser requirement adds complexity but is absolutely feasible. The turn-based nature of Warhammer 40K makes it well-suited for WebSocket's TCP-only limitation. Main challenges:
- Server infrastructure setup and costs
- Browser compatibility testing
- Performance optimization for web
- Handling connection reliability

The existing action-based architecture remains ideal - just needs WebSocket transport instead of ENet.