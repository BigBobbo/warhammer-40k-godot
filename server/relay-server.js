// Simple WebSocket Relay Server for Warhammer 40K
// Handles game code matchmaking and message relay between players

const WebSocket = require('ws');

const PORT = process.env.PORT || 9080;

// Game sessions: code -> { host: ws, guest: ws, created: timestamp }
const games = new Map();

// Client to game mapping: ws -> code
const clientGames = new Map();

// Generate 6-character game code
function generateCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// Clean up stale games (older than 10 minutes with no guest)
function cleanupGames() {
  const now = Date.now();
  for (const [code, game] of games) {
    if (!game.guest && now - game.created > 600000) {
      console.log(`Cleaning up stale game: ${code}`);
      if (game.host && game.host.readyState === WebSocket.OPEN) {
        game.host.close();
      }
      games.delete(code);
    }
  }
}

setInterval(cleanupGames, 60000);

const wss = new WebSocket.Server({ port: PORT });

console.log(`Relay server started on port ${PORT}`);

wss.on('connection', (ws) => {
  console.log('Client connected');

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);
      handleMessage(ws, msg);
    } catch (e) {
      console.error('Invalid message:', e);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    handleDisconnect(ws);
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
  });
});

function handleMessage(ws, msg) {
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
}

function handleCreate(ws) {
  // Generate unique code
  let code;
  do {
    code = generateCode();
  } while (games.has(code));

  games.set(code, {
    host: ws,
    guest: null,
    created: Date.now()
  });
  clientGames.set(ws, code);

  console.log(`Game created: ${code}`);

  ws.send(JSON.stringify({
    type: 'created',
    code: code
  }));
}

function handleJoin(ws, code) {
  code = code.toUpperCase().trim();

  if (!games.has(code)) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Game not found'
    }));
    return;
  }

  const game = games.get(code);

  if (game.guest) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Game is full'
    }));
    return;
  }

  game.guest = ws;
  clientGames.set(ws, code);

  console.log(`Player joined game: ${code}`);

  // Notify both players
  ws.send(JSON.stringify({
    type: 'joined',
    code: code,
    role: 'guest'
  }));

  game.host.send(JSON.stringify({
    type: 'guest_joined'
  }));
}

function handleRelay(ws, data) {
  const code = clientGames.get(ws);
  if (!code) return;

  const game = games.get(code);
  if (!game) return;

  // Forward to the other player
  const target = (ws === game.host) ? game.guest : game.host;
  if (target && target.readyState === WebSocket.OPEN) {
    target.send(JSON.stringify({
      type: 'relay',
      data: data
    }));
  }
}

function handleDisconnect(ws) {
  const code = clientGames.get(ws);
  if (!code) return;

  const game = games.get(code);
  if (!game) return;

  // Notify other player
  const other = (ws === game.host) ? game.guest : game.host;
  if (other && other.readyState === WebSocket.OPEN) {
    other.send(JSON.stringify({
      type: 'opponent_disconnected'
    }));
  }

  // Clean up
  clientGames.delete(ws);
  if (game.guest) clientGames.delete(game.guest);
  if (game.host) clientGames.delete(game.host);
  games.delete(code);

  console.log(`Game ended: ${code}`);
}

// Stats endpoint for health check
const http = require('http');
http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
  } else if (req.url === '/stats') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      games: games.size,
      clients: clientGames.size
    }));
  } else {
    res.writeHead(404);
    res.end();
  }
}).listen(PORT + 1);

console.log(`Health check on port ${PORT + 1}`);
