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
  'list_scenes',
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
      'Parse and evaluate a one-line GDScript expression against an optional target node. The expression sees the node as `self`.',
    inputSchema: {
      type: 'object',
      properties: {
        code: { type: 'string' },
        node_path: { type: 'string', default: '/root' },
        input_names: { type: 'array', items: { type: 'string' } },
        input_values: { type: 'array' },
      },
      required: ['code'],
    },
  },
  {
    name: 'capture_screenshot',
    description:
      'Capture the running viewport as PNG. Returns base64 data plus a path under user://test_screenshots/.',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string' },
        include_base64: { type: 'boolean', default: true },
        include_path: { type: 'boolean', default: true },
      },
    },
  },
  {
    name: 'simulate_click',
    description: 'Simulate a mouse click at a screen coordinate.',
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
    description: 'Move the mouse cursor without clicking.',
    inputSchema: {
      type: 'object',
      properties: { x: { type: 'number' }, y: { type: 'number' } },
      required: ['x', 'y'],
    },
  },
  {
    name: 'simulate_drag',
    description: 'Press at (from_x, from_y), drag through `steps` waypoints, release at (to_x, to_y).',
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
    description: 'Press a keyboard key (Godot keycode int) for a duration.',
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
    description: 'Trigger a named InputMap action for a duration.',
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
    description: 'Write text to a res:// path. Refuses paths outside res://.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string' }, content: { type: 'string' } },
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
    description: 'Editor: list all .tscn / .scn files under a directory.',
    inputSchema: {
      type: 'object',
      properties: { path: { type: 'string', default: 'res://scenes' } },
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
      'WH40K: return the full board state — phase, active player, players (CP/VP), units (id, owner, models alive, wounds), available actions.',
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
      'WH40K: locate a unit token in the running scene and synthesize a left-click on it (UI selection path).',
    inputSchema: {
      type: 'object',
      properties: { unit_id: { type: 'string' }, unit_name: { type: 'string' } },
    },
  },
  {
    name: 'dispatch_action',
    description:
      'WH40K: send a phase action dictionary through the active phase instance (validate_action + process_action).',
    inputSchema: {
      type: 'object',
      properties: { action: { type: 'object' } },
      required: ['action'],
    },
  },
  {
    name: 'move_unit_to',
    description:
      "WH40K: convenience wrapper that builds a MOVE_UNIT action and dispatches it. The active phase must accept this action shape.",
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
  // Surface Godot-side errors as MCP tool content rather than rejecting; the
  // host can decide what to do with them.
  return {
    content: [
      { type: 'text', text: JSON.stringify(result, null, 2) },
    ],
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
