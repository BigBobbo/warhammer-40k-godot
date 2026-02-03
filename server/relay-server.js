const WebSocket = require('ws');

const PORT = parseInt(process.env.PORT || '9080', 10);

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

const wss = new WebSocket.Server({ port: PORT });

console.log(`Relay server started on port ${PORT}`);

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

// Stats logging
setInterval(() => {
  console.log(`Stats: ${wss.clients.size} clients, ${games.size} games`);
}, 60000);
