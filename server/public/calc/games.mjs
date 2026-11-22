// Saved games: a game on the Play tracker kept under a name, to load it back later
// (the next day, after playing something else, on another device through a backup).
//
// A saved game holds everything that game needs: both army lists (and who is attached
// to whom), the board set-up and plans for those lists, and the mission state: the
// tracker (round, scores, CP, cards, units destroyed, once-per-battle ticks), the first
// turn, Fixed / Tactical choices, the objective plan and the clock.
//
// Pure functions on plain objects (no DOM, no storage): unit-tested in
// tests/calc-games.test.mjs. app.js keeps the list in localStorage under GAMES_KEY.

export const GAMES_KEY = 'w40k_calc_games_v1';
export const MAX_GAMES = 100;
const FORMAT = 1;

// The mission fields that belong to a game (the rest are panels, caches and settings of the device).
export const MISSION_FIELDS = ['me', 'first', 'battleReady', 'modes', 'killRate', 'actionP', 'rate', 'est', 'killAuto', 'edge', 'plans', 'game', 'source', 'enemyFrom', 'clock'];

const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

/** A clock as it should be stored: running clocks are stopped at `now` (a saved game does not lose time). */
export function stillClock(c, now = Date.now()) {
  if (!c) return c;
  const x = clone(c);
  if (x.endsAt != null) { x.pausedLeft = Math.max(0, x.endsAt - now); x.endsAt = null; }
  if (x.running && x.left) {
    x.left[x.running] = Math.max(0, x.left[x.running] - (x.since != null ? now - x.since : 0));
    x.running = null; x.since = null;
  } else if (x.running) { x.running = null; x.since = null; }
  return x;
}

/** The mission part of a saved game. */
export function missionPart(m, now = Date.now()) {
  const out = {};
  for (const k of MISSION_FIELDS) if (m[k] !== undefined) out[k] = clone(m[k]);
  if (out.clock) out.clock = stillClock(out.clock, now);
  return out;
}

const totalOf = (g, battleReady, X) => (g?.[X]?.primary || 0) + (g?.[X]?.secondary || 0) + (battleReady?.[X] ? 10 : 0);

/** What a game is, for the list: who, where it stands, the score. */
export function summarize(rec) {
  const m = rec.mission ?? {}, g = m.game ?? {};
  const over = !!g.over;
  const turn = g.next ?? m.first ?? null;
  return {
    factions: { A: rec.armies?.A ?? '?', B: rec.armies?.B ?? '?' },
    round: g.round ?? 1, turn, over,
    score: { A: totalOf(g, m.battleReady, 'A'), B: totalOf(g, m.battleReady, 'B') },
    me: m.me ?? 'A',
  };
}

/** "Round 3, B's turn" / "Battle over" / "Not started" */
export function stateText(rec) {
  const s = summarize(rec), g = rec.mission?.game ?? {};
  if (s.over) return 'Battle over';
  const started = (g.turnsDone ?? 0) > 0 || s.round > 1 || ['A', 'B'].some(X => g[X]?.primary || g[X]?.secondary || g[X]?.hand?.length || g[X]?.used?.length);
  if (!started) return 'Not started';
  return `Round ${s.round}${s.turn ? `, ${s.turn}'s turn` : ''}`;
}

/** The default name: "Space Wolves v Orks", with the event round when there is one. */
export function defaultName({ armies, event }) {
  const base = `${armies?.A ?? 'Army A'} v ${armies?.B ?? 'Army B'}`;
  return event?.round ? `${event.name ? `${event.name} ` : ''}R${event.round}: ${base}` : base;
}

/**
 * A saved game record.
 * parts: { id, name, lists: {A, B}, attach: {A, B}, armies: {A: faction, B: faction}, board: {settings, plans},
 *          mission (the whole mission state; only MISSION_FIELDS are kept), event: {name, round} | null, app }
 */
export function makeGame(parts, now = new Date()) {
  const t = now.getTime();
  return {
    format: FORMAT,
    id: parts.id ?? `g${t.toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`,
    name: (parts.name ?? '').trim().slice(0, 80) || defaultName(parts),
    saved: now.toISOString(),
    app: parts.app ?? '',
    lists: { A: parts.lists?.A ?? '', B: parts.lists?.B ?? '' },
    attach: clone(parts.attach ?? { A: null, B: null }),
    armies: { A: parts.armies?.A ?? '?', B: parts.armies?.B ?? '?' },
    board: clone(parts.board ?? { settings: {}, plans: {} }),
    mission: missionPart(parts.mission ?? {}, t),
    event: parts.event ? { name: parts.event.name ?? '', round: parts.event.round ?? null } : null,
  };
}

/** Is this a saved game this version can load? -> { ok, why } */
export function checkGame(rec) {
  if (!rec || typeof rec !== 'object' || !rec.mission?.game || !rec.lists) return { ok: false, why: 'This is not a saved game.' };
  if ((rec.format ?? 1) > FORMAT) return { ok: false, why: 'This game was saved by a newer version of the app. Update the app first.' };
  if (!String(rec.lists.A ?? '').trim() || !String(rec.lists.B ?? '').trim()) return { ok: false, why: 'This saved game has no army lists.' };
  return { ok: true };
}

/** Put a game in the list (replacing the one with its id), newest first, at most MAX_GAMES. -> { games, dropped } */
export function upsertGame(games, rec, max = MAX_GAMES) {
  const list = (games ?? []).filter(g => g.id !== rec.id);
  list.unshift(rec);
  list.sort((a, b) => String(b.saved).localeCompare(String(a.saved)));
  const dropped = list.length > max ? list.splice(max) : [];
  return { games: list, dropped };
}
export const removeGame = (games, id) => (games ?? []).filter(g => g.id !== id);

/** Has the tracker changed since this record was saved? (lists, tracker, first turn, modes, plans) */
export function sameGame(rec, parts) {
  if (!rec) return false;
  const now = makeGame({ ...parts, id: rec.id, name: rec.name }, new Date(rec.saved));
  const pick = (r) => JSON.stringify([r.lists, r.attach, r.mission.game, r.mission.first, r.mission.modes, r.mission.plans, r.board?.plans]);
  return pick(now) === pick(rec);
}
