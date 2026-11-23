// Saved games (public/calc/games.mjs): what a saved game keeps, its summary, the list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const G = await import(new URL('../public/calc/games.mjs', import.meta.url).href);
const T = await import(new URL('../public/calc/playtools.mjs', import.meta.url).href);
const MIN = 60000;

const mission = () => {
  const game = T.ensureGame({ round: 1, next: null, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } }, { fresh: true });
  return { me: 'A', first: 'A', battleReady: { A: true, B: true }, modes: { A: { mode: 'tactical', fixed: [] }, B: { mode: 'fixed', fixed: ['assassination', 'bring-it-down'] } },
    game, plans: { lay1: { 1: { o1: 'A' } } }, clock: T.newClock(), source: 'grid',
    result: { big: true }, undo: [{ g: 'x' }], table: true, open: { x: true } };   // not part of a game
};
const parts = (m) => ({ lists: { A: 'list A', B: 'list B' }, attach: { A: { 0: 2 }, B: null }, armies: { A: 'Space Wolves', B: 'Orks' }, board: { settings: { variant: 2 }, plans: { k: { variants: [] } } }, mission: m, app: '1.108.0' });

test('a saved game keeps the lists, the board and the game; not the caches, undo or table mode', () => {
  const m = mission();
  m.game.A.primary = 10; m.game.B.cp = 4; m.game.A.hand = ['assassination']; m.game.once.A['army:combat-doctrines|Assault doctrine|0'] = true;
  T.endTurn(m.game, 'A');
  const rec = G.makeGame(parts(m), new Date('2026-11-22T10:00:00Z'));
  assert.deepEqual(Object.keys(rec.mission).sort(), ['battleReady', 'clock', 'first', 'game', 'me', 'modes', 'plans', 'source']);
  assert.equal(rec.mission.game.A.primary, 10);
  assert.equal(rec.mission.game.B.cp, 5, 'CP after Turn done');
  assert.deepEqual(rec.mission.game.A.hand, ['assassination']);
  assert.ok(rec.mission.game.once.A['army:combat-doctrines|Assault doctrine|0'], 'once-per-battle ticks');
  assert.deepEqual([rec.lists.A, rec.attach.A, rec.board.settings.variant, rec.armies.B], ['list A', { 0: 2 }, 2, 'Orks']);
  assert.equal(rec.name, 'Space Wolves v Orks');
  assert.equal(rec.saved, '2026-11-22T10:00:00.000Z');
  // a copy: later changes to the tracker do not change the saved game
  m.game.A.primary = 30;
  assert.equal(rec.mission.game.A.primary, 10);
  assert.deepEqual(G.checkGame(rec), { ok: true });
  assert.equal(G.checkGame({ lists: { A: 'x', B: '' }, mission: { game: {} } }).ok, false);
  assert.equal(G.checkGame({ format: 9, lists: { A: 'x', B: 'y' }, mission: { game: {} } }).why, 'This game was saved by a newer version of the app. Update the app first.');
});

test('a running clock is stopped in the saved game, with the time it had', () => {
  const now = 1_000_000;
  const round = T.roundStart(T.newClock(), now);           // 3:00:00 running
  const r = G.stillClock(round, now + 30 * MIN);
  assert.deepEqual([r.endsAt, r.pausedLeft], [null, 150 * MIN]);
  const chess = T.chessRun(T.newClock(), 'B', now);
  chess.mode = 'chess';
  const c = G.stillClock(chess, now + 5 * MIN);
  assert.deepEqual([c.running, c.left.A, c.left.B], [null, 85 * MIN, 80 * MIN]);
  assert.equal(T.chessLeft(c, 'B', now + 999 * MIN), 80 * MIN, 'loaded later: no time has passed');
});

test('summary and state line', () => {
  const m = mission();
  let rec = G.makeGame(parts(m));
  assert.equal(G.stateText(rec), 'Not started');
  m.game.A.primary = 8; m.game.B.secondary = 5;
  T.endTurn(m.game, 'A'); T.endTurn(m.game, 'A'); T.endTurn(m.game, 'A');
  rec = G.makeGame(parts(m));
  assert.equal(G.stateText(rec), "Round 2, B's turn");
  assert.deepEqual(G.summarize(rec).score, { A: 18, B: 15 }, 'Battle Ready counted');
  m.game.over = true;
  assert.equal(G.stateText(G.makeGame(parts(m))), 'Battle over');
  assert.equal(G.defaultName({ armies: { A: 'Space Wolves', B: 'Orks' }, event: { name: 'Club GT', round: 3 } }), 'Club GT R3: Space Wolves v Orks');
});

test('the list: newest first, one entry per id, at most MAX_GAMES; changed or not', () => {
  const m = mission();
  const a = G.makeGame({ ...parts(m), id: 'a' }, new Date('2026-11-20T10:00:00Z'));
  const b = G.makeGame({ ...parts(m), id: 'b' }, new Date('2026-11-21T10:00:00Z'));
  let { games } = G.upsertGame([], a);
  ({ games } = G.upsertGame(games, b));
  assert.deepEqual(games.map(g => g.id), ['b', 'a']);
  const a2 = G.makeGame({ ...parts(m), id: 'a', name: 'renamed' }, new Date('2026-11-22T10:00:00Z'));
  ({ games } = G.upsertGame(games, a2));
  assert.deepEqual(games.map(g => `${g.id}:${g.name}`), ['a:renamed', 'b:Space Wolves v Orks'], 'saving again replaces, and moves it to the top');
  const r = G.upsertGame(games, G.makeGame({ ...parts(m), id: 'c' }), 2);
  assert.deepEqual([r.games.length, r.dropped.map(g => g.id)], [2, ['b']]);
  assert.deepEqual(G.removeGame(games, 'a').map(g => g.id), ['b']);
  // changed since saved?
  assert.equal(G.sameGame(a, parts(m)), true);
  m.game.A.primary = 3;
  assert.equal(G.sameGame(a, parts(m)), false);
  assert.equal(G.sameGame(null, parts(m)), false);
});
