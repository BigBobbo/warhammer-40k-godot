// REST client for the relay server's army endpoints (same origin).
//
// Mirrors the game's CloudStorage conventions: a persistent player id in
// localStorage (shared with the game's web build via the same key), with a
// dev-mode assist that adopts the local desktop game's player id when the
// relay server can read it (GET /api/game-player-id).

const PLAYER_ID_KEY = 'w40k_player_id';

function uuid() {
  const hex = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < 32; i++) {
    if (i === 8 || i === 12 || i === 16 || i === 20) out += '-';
    out += hex[Math.floor(Math.random() * 16)];
  }
  return out;
}

let playerId = null;

export async function initPlayerId() {
  if (playerId) return playerId;
  try {
    playerId = localStorage.getItem(PLAYER_ID_KEY);
  } catch (e) { /* storage blocked */ }
  if (playerId && playerId.length > 8) return playerId;

  // Local dev: adopt the desktop game's player id so cloud saves are shared.
  try {
    const res = await fetch('/api/game-player-id');
    if (res.ok) {
      const data = await res.json();
      if (data.player_id && data.player_id.length > 8) playerId = data.player_id;
    }
  } catch (e) { /* server may not expose it — fine */ }

  if (!playerId) playerId = uuid();
  try { localStorage.setItem(PLAYER_ID_KEY, playerId); } catch (e) { /* best effort */ }
  return playerId;
}

async function request(method, url, body) {
  const headers = { 'X-Player-ID': await initPlayerId() };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  try { data = await res.json(); } catch (e) { /* non-JSON error body */ }
  if (!res.ok) {
    throw new Error(data?.error || `${method} ${url} failed (${res.status})`);
  }
  return data;
}

export function listArmies() {
  return request('GET', '/api/armies').then(d => d.armies ?? []);
}

export function getArmy(name) {
  return request('GET', `/api/armies/${encodeURIComponent(name)}`);
}

export function putArmy(name, armyData) {
  return request('PUT', `/api/armies/${encodeURIComponent(name)}`, { army_data: armyData });
}

export function deleteArmy(name) {
  return request('DELETE', `/api/armies/${encodeURIComponent(name)}`);
}

// Dev-mode: write straight into the repo's 40k/armies/ directory (only works
// when the relay server runs next to the game checkout).
export function putLocalArmy(name, armyData) {
  return request('PUT', `/api/local-armies/${encodeURIComponent(name)}`, { army_data: armyData });
}

export async function serverHealth() {
  try {
    const res = await fetch('/api/health');
    return res.ok ? await res.json() : null;
  } catch (e) {
    return null;
  }
}
