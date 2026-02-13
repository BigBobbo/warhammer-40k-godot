const http = require('http');
const fs = require('fs');
const WebSocket = require('ws');
const path = require('path');

const PORT = parseInt(process.env.PORT || '9080', 10);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'persistence.db');
const MAX_BODY_SIZE = 2 * 1024 * 1024; // 2MB
const PUBLIC_DIR = path.join(__dirname, 'public');

// ============================================================================
// SQLite Setup
// ============================================================================

const Database = require('better-sqlite3');
const db = new Database(DB_PATH);

// Enable WAL mode for better concurrent read performance
db.pragma('journal_mode = WAL');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS players (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS game_saves (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT NOT NULL REFERENCES players(id),
    save_name TEXT NOT NULL,
    metadata TEXT NOT NULL,
    game_data TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(player_id, save_name)
  );

  CREATE TABLE IF NOT EXISTS army_lists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT NOT NULL REFERENCES players(id),
    army_name TEXT NOT NULL,
    army_data TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(player_id, army_name)
  );

  CREATE TABLE IF NOT EXISTS game_participants (
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    joined_at INTEGER NOT NULL,
    PRIMARY KEY(game_id, player_id)
  );
`);

// Migrate: add game_id column to game_saves if it doesn't exist
try {
  db.prepare("SELECT game_id FROM game_saves LIMIT 1").get();
} catch (e) {
  console.log('Migrating game_saves: adding game_id column...');
  db.exec(`ALTER TABLE game_saves ADD COLUMN game_id TEXT`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_game_saves_game_id ON game_saves(game_id)`);
  console.log('Migration complete: game_id column added to game_saves');
}

console.log(`Database initialized at ${DB_PATH}`);

// Prepared statements
const stmts = {
  upsertPlayer: db.prepare(`
    INSERT INTO players (id, created_at, last_seen_at) VALUES (?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET last_seen_at = excluded.last_seen_at
  `),
  getPlayer: db.prepare('SELECT * FROM players WHERE id = ?'),

  listOwnSaves: db.prepare(`
    SELECT save_name, metadata, created_at, updated_at, player_id AS owner_id, 'own' AS ownership
    FROM game_saves WHERE player_id = ? ORDER BY updated_at DESC
  `),
  listSharedSaves: db.prepare(`
    SELECT gs.save_name, gs.metadata, gs.created_at, gs.updated_at, gs.player_id AS owner_id, 'shared' AS ownership
    FROM game_saves gs
    INNER JOIN game_participants gp1 ON gs.game_id = gp1.game_id AND gs.player_id = gp1.player_id
    INNER JOIN game_participants gp2 ON gs.game_id = gp2.game_id AND gp2.player_id = ?
    WHERE gs.player_id != ?
    AND gs.game_id IS NOT NULL
    ORDER BY gs.updated_at DESC
  `),
  getSave: db.prepare(`
    SELECT save_name, metadata, game_data, created_at, updated_at
    FROM game_saves WHERE player_id = ? AND save_name = ?
  `),
  getSharedSave: db.prepare(`
    SELECT gs.save_name, gs.metadata, gs.game_data, gs.created_at, gs.updated_at
    FROM game_saves gs
    INNER JOIN game_participants gp1 ON gs.game_id = gp1.game_id AND gs.player_id = gp1.player_id
    INNER JOIN game_participants gp2 ON gs.game_id = gp2.game_id AND gp2.player_id = ?
    WHERE gs.player_id = ? AND gs.save_name = ?
    AND gs.game_id IS NOT NULL
  `),
  upsertSave: db.prepare(`
    INSERT INTO game_saves (player_id, save_name, metadata, game_data, game_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(player_id, save_name) DO UPDATE SET
      metadata = excluded.metadata,
      game_data = excluded.game_data,
      game_id = excluded.game_id,
      updated_at = excluded.updated_at
  `),
  deleteSave: db.prepare('DELETE FROM game_saves WHERE player_id = ? AND save_name = ?'),

  upsertGameParticipant: db.prepare(`
    INSERT OR IGNORE INTO game_participants (game_id, player_id, joined_at)
    VALUES (?, ?, ?)
  `),

  listArmies: db.prepare(`
    SELECT army_name, created_at, updated_at
    FROM army_lists WHERE player_id = ? ORDER BY army_name ASC
  `),
  getArmy: db.prepare(`
    SELECT army_name, army_data, created_at, updated_at
    FROM army_lists WHERE player_id = ? AND army_name = ?
  `),
  upsertArmy: db.prepare(`
    INSERT INTO army_lists (player_id, army_name, army_data, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(player_id, army_name) DO UPDATE SET
      army_data = excluded.army_data,
      updated_at = excluded.updated_at
  `),
  deleteArmy: db.prepare('DELETE FROM army_lists WHERE player_id = ? AND army_name = ?'),
};

// ============================================================================
// CORS Headers
// ============================================================================

function setCORSHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Player-ID');
}

function sendJSON(res, statusCode, data) {
  setCORSHeaders(res);
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function sendError(res, statusCode, message) {
  sendJSON(res, statusCode, { error: message });
}

// ============================================================================
// Body Parser
// ============================================================================

function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;

    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_SIZE) {
        reject(new Error('Request body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString();
      if (!raw) {
        resolve(null);
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(new Error('Invalid JSON body'));
      }
    });

    req.on('error', reject);
  });
}

// ============================================================================
// Player Authentication (lightweight - just X-Player-ID header)
// ============================================================================

function authenticatePlayer(req, res) {
  const playerId = req.headers['x-player-id'];
  if (!playerId || playerId.length < 8) {
    sendError(res, 401, 'Missing or invalid X-Player-ID header');
    return null;
  }
  // Upsert player record
  const now = Date.now();
  stmts.upsertPlayer.run(playerId, now, now);
  return playerId;
}

// ============================================================================
// Route Parsing
// ============================================================================

function parseRoute(url) {
  // Remove query string
  const path = url.split('?')[0];
  const parts = path.split('/').filter(Boolean);
  // Expected: ['api', resource, ...params]
  return parts;
}

// ============================================================================
// Static File Serving
// ============================================================================

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

function serveStaticFile(req, res) {
  // Only serve GET requests
  if (req.method !== 'GET') {
    sendError(res, 405, 'Method not allowed');
    return;
  }

  let urlPath = req.url.split('?')[0];
  if (urlPath === '/') urlPath = '/index.html';

  // Prevent directory traversal
  const filePath = path.normalize(path.join(PUBLIC_DIR, urlPath));
  if (!filePath.startsWith(PUBLIC_DIR)) {
    sendError(res, 403, 'Forbidden');
    return;
  }

  // Check if file exists
  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Fall back to index.html for SPA-style routing
      const indexPath = path.join(PUBLIC_DIR, 'index.html');
      fs.stat(indexPath, (err2, stats2) => {
        if (err2 || !stats2.isFile()) {
          sendJSON(res, 200, { service: 'w40k-relay-server', status: 'running' });
          return;
        }
        streamFile(res, indexPath, '.html');
      });
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    streamFile(res, filePath, ext);
  });
}

function streamFile(res, filePath, ext) {
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';
  const stream = fs.createReadStream(filePath);

  stream.on('error', () => {
    sendError(res, 500, 'Failed to read file');
  });

  res.writeHead(200, {
    'Content-Type': contentType,
    'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=86400',
  });
  stream.pipe(res);
}

// ============================================================================
// HTTP Request Handler
// ============================================================================

async function handleHTTPRequest(req, res) {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    setCORSHeaders(res);
    res.writeHead(204);
    res.end();
    return;
  }

  const parts = parseRoute(req.url);

  // Non-API requests: serve static files
  if (parts[0] !== 'api') {
    serveStaticFile(req, res);
    return;
  }

  const resource = parts[1];
  const param = parts[2] ? decodeURIComponent(parts[2]) : null;

  try {
    switch (resource) {
      case 'health':
        return handleHealth(req, res);
      case 'players':
        return handlePlayers(req, res);
      case 'saves':
        return handleSaves(req, res, param);
      case 'armies':
        return handleArmies(req, res, param);
      case 'games':
        return handleGames(req, res, param, parts[3]);
      default:
        sendError(res, 404, 'Not found');
    }
  } catch (err) {
    console.error('HTTP error:', err.message);
    sendError(res, 500, 'Internal server error');
  }
}

// ============================================================================
// API Handlers
// ============================================================================

function handleHealth(req, res) {
  sendJSON(res, 200, {
    status: 'ok',
    games: games.size,
    clients: wss.clients.size,
    uptime: process.uptime(),
  });
}

function handlePlayers(req, res) {
  if (req.method !== 'POST') {
    sendError(res, 405, 'Method not allowed');
    return;
  }

  const playerId = authenticatePlayer(req, res);
  if (!playerId) return;

  const player = stmts.getPlayer.get(playerId);
  sendJSON(res, 200, { id: player.id, created_at: player.created_at });
}

async function handleSaves(req, res, saveName) {
  const playerId = authenticatePlayer(req, res);
  if (!playerId) return;

  if (!saveName) {
    // GET /api/saves - list all saves (own + shared)
    if (req.method !== 'GET') {
      sendError(res, 405, 'Method not allowed');
      return;
    }
    const ownSaves = stmts.listOwnSaves.all(playerId);
    const sharedSaves = stmts.listSharedSaves.all(playerId, playerId);
    const allSaves = [...ownSaves, ...sharedSaves];
    // Parse metadata JSON for each save
    const result = allSaves.map((s) => ({
      save_name: s.save_name,
      metadata: JSON.parse(s.metadata),
      created_at: s.created_at,
      updated_at: s.updated_at,
      ownership: s.ownership,
      owner_id: s.owner_id,
    }));
    sendJSON(res, 200, { saves: result });
    return;
  }

  switch (req.method) {
    case 'GET': {
      // Check for owner_id query param (shared save access)
      const urlObj = new URL(req.url, `http://${req.headers.host}`);
      const ownerId = urlObj.searchParams.get('owner_id');
      let save;
      if (ownerId && ownerId !== playerId) {
        // Loading a shared save — verify participation
        save = stmts.getSharedSave.get(playerId, ownerId, saveName);
      } else {
        save = stmts.getSave.get(playerId, saveName);
      }
      if (!save) {
        sendError(res, 404, 'Save not found');
        return;
      }
      sendJSON(res, 200, {
        save_name: save.save_name,
        metadata: JSON.parse(save.metadata),
        game_data: save.game_data,
        created_at: save.created_at,
        updated_at: save.updated_at,
      });
      break;
    }
    case 'PUT': {
      const body = await parseBody(req);
      if (!body || !body.metadata || !body.game_data) {
        sendError(res, 400, 'Missing metadata or game_data in request body');
        return;
      }
      const now = Date.now();
      const metadataStr = typeof body.metadata === 'string' ? body.metadata : JSON.stringify(body.metadata);
      // Extract game_id from metadata for the indexed column
      let gameId = null;
      try {
        const metaObj = typeof body.metadata === 'string' ? JSON.parse(body.metadata) : body.metadata;
        gameId = metaObj?.game_state?.game_id || null;
        if (gameId === '') gameId = null;
      } catch (e) {
        // Ignore parse errors, gameId stays null
      }
      stmts.upsertSave.run(playerId, saveName, metadataStr, body.game_data, gameId, now, now);
      sendJSON(res, 200, { save_name: saveName, updated_at: now });
      console.log(`Save upserted: ${saveName} for player ${playerId.substring(0, 8)}... (game_id: ${gameId || 'none'})`);
      break;
    }
    case 'DELETE': {
      const result = stmts.deleteSave.run(playerId, saveName);
      if (result.changes === 0) {
        sendError(res, 404, 'Save not found');
        return;
      }
      sendJSON(res, 200, { deleted: true });
      console.log(`Save deleted: ${saveName} for player ${playerId.substring(0, 8)}...`);
      break;
    }
    default:
      sendError(res, 405, 'Method not allowed');
  }
}

async function handleArmies(req, res, armyName) {
  const playerId = authenticatePlayer(req, res);
  if (!playerId) return;

  if (!armyName) {
    // GET /api/armies - list all armies
    if (req.method !== 'GET') {
      sendError(res, 405, 'Method not allowed');
      return;
    }
    const armies = stmts.listArmies.all(playerId);
    sendJSON(res, 200, { armies });
    return;
  }

  switch (req.method) {
    case 'GET': {
      const army = stmts.getArmy.get(playerId, armyName);
      if (!army) {
        sendError(res, 404, 'Army not found');
        return;
      }
      sendJSON(res, 200, {
        army_name: army.army_name,
        army_data: JSON.parse(army.army_data),
        created_at: army.created_at,
        updated_at: army.updated_at,
      });
      break;
    }
    case 'PUT': {
      const body = await parseBody(req);
      if (!body || !body.army_data) {
        sendError(res, 400, 'Missing army_data in request body');
        return;
      }
      const now = Date.now();
      const armyDataStr = typeof body.army_data === 'string' ? body.army_data : JSON.stringify(body.army_data);
      stmts.upsertArmy.run(playerId, armyName, armyDataStr, now, now);
      sendJSON(res, 200, { army_name: armyName, updated_at: now });
      console.log(`Army upserted: ${armyName} for player ${playerId.substring(0, 8)}...`);
      break;
    }
    case 'DELETE': {
      const result = stmts.deleteArmy.run(playerId, armyName);
      if (result.changes === 0) {
        sendError(res, 404, 'Army not found');
        return;
      }
      sendJSON(res, 200, { deleted: true });
      console.log(`Army deleted: ${armyName} for player ${playerId.substring(0, 8)}...`);
      break;
    }
    default:
      sendError(res, 405, 'Method not allowed');
  }
}

// ============================================================================
// Game Participants
// ============================================================================

async function handleGames(req, res, gameId, subResource) {
  const playerId = authenticatePlayer(req, res);
  if (!playerId) return;

  if (!gameId) {
    sendError(res, 400, 'Missing game_id');
    return;
  }

  // POST /api/games/:game_id/join
  if (subResource === 'join' && req.method === 'POST') {
    const now = Date.now();
    stmts.upsertGameParticipant.run(gameId, playerId, now);
    sendJSON(res, 200, { game_id: gameId, joined: true });
    console.log(`Player ${playerId.substring(0, 8)}... joined game ${gameId.substring(0, 8)}...`);
    return;
  }

  sendError(res, 404, 'Not found');
}

// ============================================================================
// WebSocket Relay (unchanged logic)
// ============================================================================

// Game code generation (excludes confusable chars: 0/O, 1/I/L)
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;

function generateCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
}

// Game sessions: code -> { host: ws, guest: ws }
const games = new Map();

// Client to game mapping: ws -> code
const clientGames = new Map();

// Create HTTP server and WebSocket server on the same port
const server = http.createServer(handleHTTPRequest);
const wss = new WebSocket.Server({ noServer: true });

// Handle WebSocket upgrade
server.on('upgrade', (req, socket, head) => {
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});

wss.on('connection', (ws) => {
  console.log('Client connected');

  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch (e) {
      console.log('Invalid JSON:', data.toString());
      return;
    }

    console.log('Received:', msg.type);

    switch (msg.type) {
      case 'create':
        handleCreate(ws);
        break;
      case 'join':
        handleJoin(ws, msg.code);
        break;
      case 'relay':
        handleRelay(ws, msg.data);
        break;
      default:
        console.log('Unknown message type:', msg.type);
    }
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('error', (err) => {
    console.log('WebSocket error:', err.message);
  });
});

function handleCreate(ws) {
  // Generate unique code
  let code;
  let attempts = 0;
  do {
    code = generateCode();
    attempts++;
  } while (games.has(code) && attempts < 100);

  if (attempts >= 100) {
    send(ws, { type: 'error', message: 'Could not generate game code' });
    return;
  }

  // Create game session
  games.set(code, { host: ws, guest: null });
  clientGames.set(ws, code);

  send(ws, { type: 'created', code });
  console.log(`Game created: ${code}`);
}

function handleJoin(ws, code) {
  if (!code) {
    send(ws, { type: 'error', message: 'No code provided' });
    return;
  }

  code = code.toUpperCase().trim();
  const game = games.get(code);

  if (!game) {
    send(ws, { type: 'error', message: 'Game not found' });
    return;
  }

  if (game.guest) {
    send(ws, { type: 'error', message: 'Game is full' });
    return;
  }

  // Join the game
  game.guest = ws;
  clientGames.set(ws, code);

  // Notify both players
  send(ws, { type: 'joined', code });
  send(game.host, { type: 'guest_joined' });

  console.log(`Player joined game: ${code}`);
}

function handleRelay(ws, data) {
  const code = clientGames.get(ws);
  if (!code) return;

  const game = games.get(code);
  if (!game) return;

  // Send to the other player
  const target = ws === game.host ? game.guest : game.host;
  if (target && target.readyState === WebSocket.OPEN) {
    send(target, { type: 'relay', data });
  }
}

function handleDisconnect(ws) {
  const code = clientGames.get(ws);
  if (!code) return;

  const game = games.get(code);
  if (!game) {
    clientGames.delete(ws);
    return;
  }

  // Notify the other player
  const other = ws === game.host ? game.guest : game.host;
  if (other && other.readyState === WebSocket.OPEN) {
    send(other, { type: 'opponent_disconnected' });
  }

  // If host disconnects, remove the game
  if (ws === game.host) {
    if (game.guest) {
      clientGames.delete(game.guest);
    }
    games.delete(code);
    console.log(`Game removed: ${code}`);
  } else {
    // Guest disconnected, keep game open
    game.guest = null;
  }

  clientGames.delete(ws);
  console.log('Client disconnected');
}

function send(ws, msg) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

// ============================================================================
// Start Server
// ============================================================================

server.listen(PORT, () => {
  console.log(`Relay server started on port ${PORT}`);
  console.log(`HTTP API: http://localhost:${PORT}/api/health`);
  console.log(`WebSocket: ws://localhost:${PORT}`);
});

// Stats logging
setInterval(() => {
  console.log(`Stats: ${wss.clients.size} clients, ${games.size} games`);
}, 60000);

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  db.close();
  server.close();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down...');
  db.close();
  server.close();
  process.exit(0);
});
