# Godot MCP

In-game MCP (Model Context Protocol) server for the Warhammer 40K project.
Gives an AI assistant (Claude Code, Claude Desktop, Cline, etc.) "eyes and
hands" inside the running game so it can verify code changes by capturing
screenshots, simulating input, inspecting scene state, and running domain
commands like `get_board_state` or `select_unit`.

## Architecture

```
┌────────────┐   stdio MCP    ┌──────────────────────┐   NDJSON / TCP   ┌─────────────────────┐
│ Claude /   │ ─────────────▶ │ godot-mcp-bridge     │ ───────────────▶ │ MCPServer autoload  │  port 9080
│ MCP host   │ ◀───────────── │ (Node.js, see        │ ◀─────────────── │ (running game)      │
└────────────┘                │  ../../godot-mcp/)   │                  └─────────────────────┘
                              │                      │   NDJSON / TCP   ┌─────────────────────┐
                              │                      │ ───────────────▶ │ Editor bridge       │  port 9081
                              │                      │ ◀─────────────── │ (Godot editor)      │
                              └──────────────────────┘                  └─────────────────────┘
```

- The Godot addon registers an autoload `MCPServer` that listens on
  `127.0.0.1:9080` whenever the game runs (editor playtest or exported build).
- The same plugin starts a small editor bridge on `127.0.0.1:9081` so commands
  like `play_scene` / `stop_scene` / `list_scenes` work even when the game is
  not running.
- The Node.js bridge in `godot-mcp/src/runtime_bridge.ts` translates between
  MCP stdio and the TCP NDJSON protocol, routing each command to the right
  port.

The wire protocol is one JSON object per line:

```
→ { "id": 1, "command": "ping", "params": {} }
← { "id": 1, "command": "ping", "result": { "status": "ok", "pong": 1234567 } }
```

## Setup

1. Enable the plugin

   The plugin is enabled by default in `40k/project.godot`. If you fork the
   addon into another project, enable it via
   `Project → Project Settings → Plugins → Godot MCP`.

2. Build the bridge

   ```bash
   cd godot-mcp
   npm install
   npm run build
   ```

3. Configure your MCP host

   For Claude Desktop / Claude Code, add an entry under `mcpServers`:

   ```json
   {
     "mcpServers": {
       "godot-mcp-bridge": {
         "command": "node",
         "args": ["/absolute/path/to/godot-mcp/build/runtime_bridge.js"]
       }
     }
   }
   ```

   For Claude Code CLI specifically:

   ```bash
   claude mcp add godot-mcp-bridge node /absolute/path/to/godot-mcp/build/runtime_bridge.js
   ```

4. Run the game (editor playtest or exported binary). You should see
   `[GodotMCP] Listening on 127.0.0.1:9080` in the log.

5. From Claude, call any tool, e.g. `ping` or `get_board_state`.

## Environment variables

| Var                          | Default        | Purpose                                  |
|-----------------------------:|:---------------|:-----------------------------------------|
| `GODOT_MCP_HOST`             | `127.0.0.1`    | Bridge → Godot host.                     |
| `GODOT_MCP_PORT`             | `9080`         | Runtime autoload port.                   |
| `GODOT_MCP_EDITOR_PORT`      | `9081`         | Editor bridge port.                      |
| `GODOT_MCP_TIMEOUT_MS`       | `30000`        | Request timeout in the Node bridge.      |
| `GODOT_MCP_DISABLED=1`       | unset          | Skip starting the runtime server. Useful in CI when only specific scenes need it. |

## Tool catalogue

### Generic / project / scene
- `ping`, `list_tools`
- `get_project_info`, `get_project_setting`, `list_files`
- `get_current_scene`, `get_node_info`, `get_node_property`, `set_node_property`,
  `call_node_method`
- `read_script`, `write_script` — `write_script` refuses paths outside `res://`
  (and outside `GODOT_MCP_ALLOWED_WRITE_PATHS` when that env is set), and
  refuses to overwrite an existing file unless `overwrite: true` is passed.

### Core testing
- `capture_screenshot` — PNG to `user://test_screenshots/<label>.png` plus an
  inline image content block. Vision-capable MCP hosts (Claude Code/Desktop)
  see it as a real image they can reason over, not as base64 text. Inline
  copy is downscaled to `max_dim` on the long side (default 1280); the
  on-disk file is full resolution.
- `simulate_click`, `simulate_mouse_move`, `simulate_drag`,
  `simulate_key_press`, `simulate_action`
- `get_scene_state` — recursive tree dump with positions, visibility, and
  script-defined properties
- `execute_script` — evaluate GDScript against an optional target node.
  Single-line code uses an `Expression` (node visible as `self`); multi-line
  code, or any call with `multiline: true`, is compiled into a throwaway
  script so full statements work (`var`/`if`/`for`/`return`, method calls,
  autoloads by global name). In compiled mode the node is the `node` param;
  `return <value>` to send a result back.
- `wait_frames`, `wait_seconds`
- `get_log_path` — returns absolute paths of `user://logs` and
  `user://test_screenshots`
- `read_debug_log` — read the newest `user://logs/debug_*.log` bucketed into
  errors/warnings/info/debug so you can assert "no errors fired" after driving
  a feature. Supports `tail`, `since_marker` (only lines after a marker's last
  occurrence), and `levels` filtering. Flushes DebugLogger's buffer first.
- `scene_snapshot` / `diff_snapshot` — capture a compact path→state index of
  the live tree to `user://mcp_snapshots/<label>.json`, then diff two
  snapshots (or one snapshot vs. the live tree) to prove only the intended
  nodes moved. Reports added / removed / changed nodes with field-level diffs.
- `chain_verify` — anti-overconfidence gate: given a `claim`, returns 5
  adversarial challenge questions plus live log error/warning counts to
  reconcile before closing a task. Encodes the "pin tests aren't validation"
  rule from `CLAUDE.md`.

### Editor-only (port 9081)
- `play_scene`, `play_main_scene`, `stop_scene`, `get_edited_scene`,
  `list_scenes`, `reload_scripts`

### WH40K
- `get_board_state` — phase, active player, players (CP/VP), unit roster
- `list_units`, `get_unit_details`
- `get_current_phase`, `advance_phase`, `transition_to_phase`
- `select_unit` — locates the token in the running scene and synthesizes a
  click on its screen position (UI selection path)
- `dispatch_action` — runs a phase action through `validate_action` /
  `process_action` on the active phase instance
- `move_unit_to` — convenience wrapper that builds a `MOVE_UNIT` action
- `verify_delivery` — one-call end-to-end gate. Checks (1) scene-tree
  integrity, (2) `GameState` + required autoloads present, (3) the debug log
  has no `ERROR` lines (optionally `since_marker`), and (4) caller
  `assertions` — GDScript expressions evaluated over live state (autoloads
  reachable by name; bare expressions auto-returned; pass `expect` for
  equality or rely on truthiness). Returns `passed: false` if any required
  check fails. Use it as the final gate after driving a feature live.

## Security model

The addon's threat model is **trusted localhost** — the only client is the
MCP bridge on `127.0.0.1`, and requests are correlated to responses by `id`
over a private TCP socket, so there is no response-forgery vector to defend
against (this is why the addon does *not* need the random output markers that
stdout-scraping MCP servers like `godot-mcp-enhanced` use). The applicable
hardening, borrowed from that project's security model, is:

- **Path confinement.** `write_script` only writes under `res://`, and under
  `GODOT_MCP_ALLOWED_WRITE_PATHS` (comma-separated `res://` prefixes) when set
  — mirroring `ALLOWED_PROJECT_PATHS`. Unset = all `res://` allowed.
- **Overwrite confirmation.** `write_script` refuses to clobber an existing
  file unless `overwrite: true` — the "confirmation token for destructive
  operations" pattern. Overwriting source is the main destructive risk the
  bridge exposes.

## Implementation notes

- **NDJSON over TCP, not WebSocket.** The implementation guide in `CLAUDE.md`
  describes a WebSocket server; on localhost between two trusted processes
  WebSocket framing adds complexity for no benefit, so the addon uses
  newline-delimited JSON over plain TCP. The Node.js bridge handles that
  difference.
- **Two ports.** Editor commands (`play_scene` etc.) need access to
  `EditorInterface`, which only exists in the editor. They go to port 9081.
  Runtime tools (`capture_screenshot` etc.) go to port 9080 because they need
  the running game's viewport / input system.
- **Action dispatch.** `dispatch_action` and `move_unit_to` route through the
  current phase instance's `validate_action` / `process_action`, so any
  in-game validation and side effects fire normally — exactly as if the human
  UI had triggered the action.
- **Token discovery.** `select_unit` searches the running scene for a
  `Node2D` whose name matches `unit_id` or that exposes a `unit_id` script
  property / metadata. Adapt your token nodes accordingly if necessary.
- **Logs.** All addon `print` lines also land in
  `user://logs/debug_*.log` via Godot's standard logging — same path as the
  rest of the project (see `CLAUDE.md`).

## Test workflow example

```
# Claude:
1. play_scene { path: "res://scenes/Main.tscn" }
2. wait_seconds { seconds: 1.0 }
3. get_board_state
4. select_unit { unit_id: "U_INTERCESSORS_A" }
5. capture_screenshot { label: "selected" }
6. transition_to_phase { phase: "MOVEMENT" }
7. move_unit_to { unit_id: "U_INTERCESSORS_A", dest_x: 600, dest_y: 800 }
8. wait_seconds { seconds: 1.5 }
9. capture_screenshot { label: "moved" }
10. get_unit_details { unit_id: "U_INTERCESSORS_A" }
```
