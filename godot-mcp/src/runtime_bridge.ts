#!/usr/bin/env node
/**
 * Godot MCP Runtime Bridge
 *
 * Translates MCP stdio JSON-RPC calls from a host (Claude Code/Desktop) into
 * NDJSON requests over a localhost TCP socket exposed by the Godot addon at
 * 40k/addons/godot_mcp/. The addon listens on two ports:
 *
 *   - 9080 — runtime autoload, available while the game is playing
 *   - 9081 — editor bridge, available while the Godot editor is open
 *
 * This bridge auto-routes commands to whichever port is appropriate based on
 * a small allow-list of editor-only commands. Everything else goes to 9080.
 *
 * Why a separate file: the existing index.ts is the Coding-Solo godot-mcp
 * variant which spawns the godot CLI per command. This file is the live
 * companion that talks to a running Godot instance instead, matching the
 * Part 2 / Part 3 testing tools described in CLAUDE.md.
 */

import net from 'node:net';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from '@modelcontextprotocol/sdk/types.js';

const RUNTIME_HOST = process.env.GODOT_MCP_HOST ?? '127.0.0.1';
const RUNTIME_PORT = Number(process.env.GODOT_MCP_PORT ?? '9080');
const EDITOR_PORT = Number(process.env.GODOT_MCP_EDITOR_PORT ?? '9081');
const REQUEST_TIMEOUT_MS = Number(process.env.GODOT_MCP_TIMEOUT_MS ?? '30000');

const EDITOR_ONLY_COMMANDS = new Set([
  'play_scene',
  'play_main_scene',
  'stop_scene',
  'get_edited_scene',
  'reload_scripts',
]);

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (reason?: unknown) => void;
  timer: NodeJS.Timeout;
}

class GodotConnection {
  private socket: net.Socket | null = null;
  private buffer = '';
  private nextId = 1;
  private pending = new Map<number, PendingRequest>();
  private connecting: Promise<void> | null = null;

  constructor(private readonly host: string, private readonly port: number) {}

  private async ensureConnected(): Promise<void> {
    if (this.socket && !this.socket.destroyed) return;
    if (this.connecting) return this.connecting;

    this.connecting = new Promise((resolve, reject) => {
      const sock = new net.Socket();
      sock.setNoDelay(true);
      sock.once('error', err => {
        this.connecting = null;
        reject(err);
      });
      sock.once('connect', () => {
        this.socket = sock;
        sock.on('data', chunk => this.onData(chunk.toString('utf8')));
        sock.on('close', () => this.onClose());
        sock.on('error', err => this.onError(err));
        this.connecting = null;
        resolve();
      });
      sock.connect(this.port, this.host);
    });

    return this.connecting;
  }

  private onData(text: string): void {
    this.buffer += text;
    let nl: number;
    while ((nl = this.buffer.indexOf('\n')) !== -1) {
      const line = this.buffer.slice(0, nl);
      this.buffer = this.buffer.slice(nl + 1);
      const trimmed = line.trim();
      if (!trimmed) continue;
      let parsed: any;
      try {
        parsed = JSON.parse(trimmed);
      } catch {
        continue;
      }
      const id = parsed?.id;
      if (typeof id !== 'number') continue;
      const pend = this.pending.get(id);
      if (!pend) continue;
      this.pending.delete(id);
      clearTimeout(pend.timer);
      pend.resolve(parsed.result ?? {});
    }
  }

  private onClose(): void {
    this.socket = null;
    for (const [, pend] of this.pending) {
      clearTimeout(pend.timer);
      pend.reject(new Error('Godot socket closed before response'));
    }
    this.pending.clear();
  }

  private onError(err: Error): void {
    process.stderr.write(`[godot-mcp-bridge] socket error: ${err.message}\n`);
  }

  async send(command: string, params: Record<string, unknown>): Promise<unknown> {
    await this.ensureConnected();
    if (!this.socket) throw new Error('Not connected to Godot');
    const id = this.nextId++;
    const payload = JSON.stringify({ id, command, params }) + '\n';
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Godot command '${command}' timed out after ${REQUEST_TIMEOUT_MS}ms`));
      }, REQUEST_TIMEOUT_MS);
      this.pending.set(id, { resolve, reject, timer });
      this.socket!.write(payload, err => {
        if (err) {
          clearTimeout(timer);
          this.pending.delete(id);
          reject(err);
        }
      });
    });
  }
}

const runtime = new GodotConnection(RUNTIME_HOST, RUNTIME_PORT);
const editor = new GodotConnection(RUNTIME_HOST, EDITOR_PORT);

function pickConnection(command: string): GodotConnection {
  return EDITOR_ONLY_COMMANDS.has(command) ? editor : runtime;
}

interface ToolDef {
  name: string;
  description: string;
  inputSchema: { type: 'object'; properties: Record<string, any>; required?: string[] };
}

const TOOLS: ToolDef[] = [
  {
    name: 'ping',
    description: 'Verify the Godot MCP runtime is reachable.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_tools',
    description: 'List every command name registered in the Godot router.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'get_project_info',
    description: 'Return project name, main scene, engine version, and viewport size.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'get_current_scene',
    description: 'Return the path/name/type of the currently-running scene root.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'get_scene_state',
    description:
      'Dump the running scene tree with positions, visibility, and script-defined properties. Pass `max_depth` to limit recursion.',
    inputSchema: {
      type: 'object',
      properties: {
        max_depth: { type: 'number', default: 10 },
        include_script_properties: { type: 'boolean', default: true },
        include_invisible: { type: 'boolean', default: true },
        root: { type: 'string' },
      },
    },
  },
  {
    name: 'get_node_info',
    description: 'Return type, position, size, visibility, and direct children of a single node.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string' } },
      required: ['path'],
    },
  },
  {
    name: 'get_node_property',
    description: 'Read a single property of a node by path.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string' }, property: { type: 'string' } },
      required: ['path', 'property'],
    },
  },
  {
    name: 'set_node_property',
    description: 'Set a single property on a node by path.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        property: { type: 'string' },
        value: {},
      },
      required: ['path', 'property', 'value'],
    },
  },
  {
    name: 'call_node_method',
    description: 'Call a method on a node by path with optional positional args.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        method: { type: 'string' },
        args: { type: 'array', items: {} },
      },
      required: ['path', 'method'],
    },
  },
  {
    name: 'execute_script',
    description:
      'Evaluate GDScript against an optional target node. Single-line code uses an Expression (the node is visible as `self`). Multi-line code — or any code with `multiline:true` — is compiled into a throwaway script so full statements work: `var`, `if`, `for`, `return`, method calls, and autoloads (GameState, PhaseManager, …) by their global names. In compiled mode the resolved node is the `node` parameter; `return <value>` to send a result back. Runtime errors inside compiled code are not catchable — read them back with read_debug_log.',
    inputSchema: {
      type: 'object',
      properties: {
        code: { type: 'string' },
        node_path: { type: 'string', default: '/root' },
        multiline: {
          type: 'boolean',
          description: 'Force compiled multi-line mode. Auto-enabled when code contains a newline.',
        },
        input_names: { type: 'array', items: { type: 'string' }, description: 'Single-line Expression mode only.' },
        input_values: { type: 'array', description: 'Single-line Expression mode only.' },
      },
      required: ['code'],
    },
  },
  {
    name: 'read_debug_log',
    description:
      'Read the running game\'s debug log bucketed into errors/warnings/info/debug. Use this to assert "no errors fired" after driving a feature instead of grepping raw text. Reads the newest user://logs/debug_*.log by default; `since_marker` keeps only lines after a marker\'s last occurrence (log a unique marker before your action to scope the read).',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Absolute or user:// path. Default: newest debug log.' },
        tail: { type: 'number', default: 200, description: 'Keep only the last N non-empty lines (0 = all).' },
        since_marker: { type: 'string', description: "Keep only lines after this marker's last occurrence." },
        levels: { type: 'array', items: { type: 'string' }, description: 'Filter returned lines, e.g. ["ERROR"].' },
        include_lines: { type: 'boolean', default: true },
      },
    },
  },
  {
    name: 'scene_snapshot',
    description:
      'Capture a compact, diff-friendly index of the live scene tree (path -> type/position/visibility/size/script-properties) and persist it under user://mcp_snapshots/<label>.json. Take one before and one after a change, then diff_snapshot to prove only the intended nodes moved.',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string' },
        root: { type: 'string', description: 'Subtree root path. Default: current scene.' },
        max_depth: { type: 'number', default: 12 },
      },
    },
  },
  {
    name: 'diff_snapshot',
    description:
      'Diff two scene snapshots and report added / removed / changed nodes (with field-level changes). `before` is a label captured via scene_snapshot; `after` is another label, or omit / "__live__" to diff against the current live tree.',
    inputSchema: {
      type: 'object',
      properties: {
        before: { type: 'string' },
        after: { type: 'string', description: 'Label, or "__live__" / omitted to diff the live tree.' },
        root: { type: 'string' },
        max_depth: { type: 'number', default: 12 },
      },
      required: ['before'],
    },
  },
  {
    name: 'chain_verify',
    description:
      "Anti-overconfidence gate. Given a `claim` describing what you believe you delivered, returns 5 adversarial challenge questions plus automated evidence (live log error/warning counts) you must reconcile before closing the task. Mirrors the project rule that pin tests / markers are not validation.",
    inputSchema: {
      type: 'object',
      properties: { claim: { type: 'string' } },
      required: ['claim'],
    },
  },
  {
    name: 'capture_screenshot',
    description:
      'Capture the running viewport as PNG. Returns the image inline (vision-capable hosts see it as a real image) plus a saved path under user://test_screenshots/. Inline copy is downscaled to `max_dim` on the long side; the on-disk file stays at full resolution.',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string' },
        include_base64: { type: 'boolean', default: true },
        include_path: { type: 'boolean', default: true },
        max_dim: {
          type: 'number',
          description: 'Long-side cap for the inline image (default 1280). Pass 0 to disable scaling.',
          default: 1280,
        },
      },
    },
  },
  {
    name: 'simulate_click',
    description:
      'TESTING ONLY — do NOT use to play the game. Synthesizes an OS-level mouse click at a screen coordinate. Reserved for explicit UI/input regression tests where you must verify that the actual click handlers fire (drag-ghost, button states, _gui_input chains). For normal gameplay use `dispatch_action` instead — it is faster, deterministic, and skips pixel-hunting.',
    inputSchema: {
      type: 'object',
      properties: {
        x: { type: 'number' },
        y: { type: 'number' },
        button: { type: 'number', description: 'MouseButton constant; default left.' },
        double_click: { type: 'boolean', default: false },
      },
      required: ['x', 'y'],
    },
  },
  {
    name: 'simulate_mouse_move',
    description:
      'TESTING ONLY — do NOT use to play the game. Moves the mouse cursor without clicking. Reserved for hover-state UI tests. For gameplay use `dispatch_action`.',
    inputSchema: {
      type: 'object',
      properties: { x: { type: 'number' }, y: { type: 'number' } },
      required: ['x', 'y'],
    },
  },
  {
    name: 'simulate_drag',
    description:
      'TESTING ONLY — do NOT use to play the game. Press at (from_x, from_y), drag through `steps` waypoints, release at (to_x, to_y). Reserved for verifying drag-and-drop UI (model placement, drag ghost). For gameplay use `dispatch_action` with a MOVE_UNIT / STAGE_MODEL_MOVE payload.',
    inputSchema: {
      type: 'object',
      properties: {
        from_x: { type: 'number' },
        from_y: { type: 'number' },
        to_x: { type: 'number' },
        to_y: { type: 'number' },
        steps: { type: 'number', default: 10 },
        button: { type: 'number' },
      },
      required: ['from_x', 'from_y', 'to_x', 'to_y'],
    },
  },
  {
    name: 'simulate_key_press',
    description:
      'TESTING ONLY — do NOT use to play the game. Presses a keyboard key (Godot keycode int) for a duration. Reserved for keybinding regression tests. For gameplay use `dispatch_action`.',
    inputSchema: {
      type: 'object',
      properties: {
        keycode: { type: 'number' },
        duration: { type: 'number', default: 0.05 },
      },
      required: ['keycode'],
    },
  },
  {
    name: 'simulate_action',
    description:
      'TESTING ONLY — do NOT use to play the game. Triggers a named InputMap action for a duration. Reserved for input-action wiring tests. For gameplay use `dispatch_action`.',
    inputSchema: {
      type: 'object',
      properties: {
        action: { type: 'string' },
        duration: { type: 'number', default: 0.1 },
      },
      required: ['action'],
    },
  },
  {
    name: 'wait_frames',
    description: 'Yield until N process_frame ticks have elapsed.',
    inputSchema: {
      type: 'object',
      properties: { frames: { type: 'number', default: 1 } },
    },
  },
  {
    name: 'wait_seconds',
    description: 'Yield for the given number of seconds (real-time).',
    inputSchema: {
      type: 'object',
      properties: { seconds: { type: 'number', default: 1.0 } },
    },
  },
  {
    name: 'list_files',
    description: 'List files inside a res:// directory, optional glob pattern, optional recursive.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', default: 'res://' },
        pattern: { type: 'string' },
        recursive: { type: 'boolean', default: false },
      },
    },
  },
  {
    name: 'read_script',
    description: 'Read a script or text file by res:// or absolute path.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string' } },
      required: ['path'],
    },
  },
  {
    name: 'write_script',
    description:
      'Write text to a res:// path. Refuses paths outside res:// (and outside GODOT_MCP_ALLOWED_WRITE_PATHS when that env is set). Refuses to overwrite an existing file unless `overwrite:true` is passed.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        content: { type: 'string' },
        overwrite: { type: 'boolean', default: false, description: 'Required to clobber an existing file.' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'get_log_path',
    description: 'Return absolute paths for the user logs and screenshots directories.',
    inputSchema: { type: 'object', properties: {} },
  },

  // --- Editor-only ---
  {
    name: 'play_scene',
    description:
      "Editor: play a specific scene file (or main scene if `path` is omitted). Requires the Godot editor to be open with the project loaded.",
    inputSchema: { type: 'object', properties: { path: { type: 'string' } } },
  },
  {
    name: 'play_main_scene',
    description: 'Editor: play the project main scene.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'stop_scene',
    description: 'Editor: stop a running playtest.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'get_edited_scene',
    description: 'Editor: return the currently-edited scene root.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_scenes',
    description: 'List all .tscn scene files under a directory (recursive). Default root is res://.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string', default: 'res://' } },
    },
  },
  {
    name: 'reload_scripts',
    description: 'Editor: rescan the project filesystem to pick up new/changed files.',
    inputSchema: { type: 'object', properties: {} },
  },

  // --- WH40K ---
  {
    name: 'get_board_state',
    description:
      'WH40K [PRIMARY play tool]: return the full board state — phase, active player, players (CP/VP), units (id, owner, models alive, wounds), available actions. Call this at the start of every turn to ground reasoning before issuing actions.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'get_legal_actions',
    description:
      "WH40K [PRIMARY play tool]: return the contextually-valid action dicts the active player can take RIGHT NOW. For most phases each entry is shaped exactly as `dispatch_action` expects — pick one and forward it. EXCEPTION: in DEPLOYMENT, DEPLOY_UNIT entries name the deployable unit only; the caller must add `model_positions` (and optional `model_rotations`) before dispatching. Same for STAGE_MODEL_MOVE-style sub-actions in MOVEMENT — get_legal_actions surfaces the openers (BEGIN_NORMAL_MOVE, BEGIN_ADVANCE), not per-model placements.",
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_units',
    description: 'WH40K: list units, optionally filtered by owner or including destroyed.',
    inputSchema: {
      type: 'object',
      properties: {
        owner: { type: 'number' },
        include_destroyed: { type: 'boolean', default: false },
      },
    },
  },
  {
    name: 'get_unit_details',
    description:
      "WH40K: return a unit's full details — meta, models, weapons, abilities, status flags, attached/embarked.",
    inputSchema: {
      type: 'object',
      properties: { unit_id: { type: 'string' }, unit_name: { type: 'string' } },
    },
  },
  {
    name: 'get_current_phase',
    description: 'WH40K: return current phase id, name, active player, and available actions.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'advance_phase',
    description: 'WH40K: advance to the next phase via PhaseManager.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'transition_to_phase',
    description: 'WH40K: jump directly to a phase by enum id or name (e.g. "MOVEMENT").',
    inputSchema: {
      type: 'object',
      properties: { phase: { description: 'Enum int or name string' } },
      required: ['phase'],
    },
  },
  {
    name: 'select_unit',
    description:
      "WH40K [TESTING-leaning]: locate a unit token in the running scene and synthesize a left-click on it (UI selection path). Use this only when you specifically need the UI's selection signals to fire (highlights, side panel, etc.). For normal play, name the unit_id directly inside a `dispatch_action` payload — no selection step required.",
    inputSchema: {
      type: 'object',
      properties: { unit_id: { type: 'string' }, unit_name: { type: 'string' } },
    },
  },
  {
    name: 'dispatch_action',
    description:
      'WH40K [PRIMARY play tool — use this to take any in-game action]: send a phase action dictionary through `BasePhase.execute_action` on the active phase instance. This validates, processes, applies the resulting state diffs to GameState, refreshes the phase snapshot, and emits `action_taken` — i.e. exactly what the UI does. Position fields (`position`, `destination`, `dest`, `model_positions`, etc.) accept JSON `[x, y]` arrays or `{x, y}` dicts and are converted to Vector2 server-side. Call `get_legal_actions` first to see valid action dict shapes for the current phase.',
    inputSchema: {
      type: 'object',
      properties: { action: { type: 'object' } },
      required: ['action'],
    },
  },
  {
    name: 'move_unit_to',
    description:
      "WH40K [PRIMARY play tool]: convenience wrapper that builds a MOVE_UNIT action and dispatches it. The active phase must accept this action shape — if unsure, call `get_legal_actions` first.",
    inputSchema: {
      type: 'object',
      properties: {
        unit_id: { type: 'string' },
        dest_x: { type: 'number' },
        dest_y: { type: 'number' },
        model_id: { type: 'string' },
      },
      required: ['unit_id', 'dest_x', 'dest_y'],
    },
  },
  {
    name: 'verify_delivery',
    description:
      'WH40K [GATE]: one-call end-to-end verification mirroring the rule that a feature is not done until driven live. Checks (1) scene-tree integrity, (2) GameState + required autoloads present, (3) debug log has no ERROR lines (optionally since a marker), and (4) caller `assertions` — GDScript expressions evaluated over live state (autoloads reachable by name). Returns passed=false if any required check fails.',
    inputSchema: {
      type: 'object',
      properties: {
        required_autoloads: {
          type: 'array',
          items: { type: 'string' },
          description: 'Default ["GameState","PhaseManager","TurnManager"].',
        },
        expected_phase: { type: 'string', description: 'e.g. "MOVEMENT" — fails if the current phase differs.' },
        fail_on_log_error: { type: 'boolean', default: true },
        since_marker: { type: 'string', description: 'Only scan log lines after this marker.' },
        log_tail: { type: 'number', default: 500 },
        assertions: {
          type: 'array',
          description: 'Each: { expr, description?, node_path?, expect? }. expr is GDScript; bare expressions are auto-returned. Passes if expr == expect (when given) else truthy.',
          items: { type: 'object' },
        },
      },
    },
  },
];

const server = new Server(
  { name: 'godot-mcp-runtime-bridge', version: '0.1.0' },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async req => {
  const { name, arguments: args } = req.params;
  const conn = pickConnection(name);
  let result: any;
  try {
    result = await conn.send(name, args ?? {});
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new McpError(ErrorCode.InternalError, `Godot bridge error: ${msg}`);
  }

  // If Godot returned an image (e.g. capture_screenshot), surface it as a
  // real MCP image content block so vision-capable hosts can actually see
  // it. Strip the base64 from the text JSON to avoid duplicating ~MB of
  // payload as text tokens.
  const content: Array<{ type: string; [k: string]: unknown }> = [];
  if (
    result &&
    typeof result === 'object' &&
    typeof (result as any).image_base64 === 'string' &&
    (result as any).image_base64.length > 0
  ) {
    const imageData = (result as any).image_base64 as string;
    const mimeType = (result as any).image_mime_type ?? 'image/png';
    const { image_base64: _omit, ...metadata } = result as Record<string, unknown>;
    content.push({ type: 'text', text: JSON.stringify(metadata, null, 2) });
    content.push({ type: 'image', data: imageData, mimeType });
  } else {
    content.push({ type: 'text', text: JSON.stringify(result, null, 2) });
  }

  return {
    content,
    isError: result?.status === 'error',
  };
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write(
    `[godot-mcp-bridge] ready (runtime=${RUNTIME_HOST}:${RUNTIME_PORT}, editor=${RUNTIME_HOST}:${EDITOR_PORT})\n`,
  );
}

main().catch(err => {
  process.stderr.write(`[godot-mcp-bridge] fatal: ${String(err)}\n`);
  process.exit(1);
});
