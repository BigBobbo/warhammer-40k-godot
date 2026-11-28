// Combat Calc — the prediction record (gamelog.mjs): turns kept, the game closed, the calls read against what happened.
// Run: node --test server/tests/calc-gamelog.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const G = await import(new URL('../public/calc/gamelog.mjs', import.meta.url).href);
const units = (left = {}) => [['A:a', 'Alpha'], ['A:b', 'Bravo'], ['B:x', 'Xray'], ['B:y', 'Yankee']].filter(([tk]) => left[tk] !== null).map(([tk, name]) => ({ tk, name, x: 10.04, y: 20.06, left: left[tk] ?? 5, total: 5 }));
const game = () => {
  const rec = G.newRecord({ me: 'A', factions: { A: 'Space Wolves', B: 'Orks' }, first: 'A', version: '9.9.9', started: 1 });
  // A's turn 1 ends: the cards expect B to destroy Alpha (70%) and Bravo (30%) in its turn
  G.addTurn(rec, { round: 1, turn: 'A', at: 2, vp: { A: 0, B: 0 }, units: units(), forecast: { win: 0.7, margin: 8.04 }, moves: [{ unit: 'A:a', name: 'Alpha', label: 'Centre', obj: 'c', vp: 5, made: true }, { unit: 'A:b', name: 'Bravo', label: 'Their side', obj: 'e', vp: 3.2, made: false }],
    ahead: { side: 'B', destroyed: [{ tk: 'A:a', name: 'Alpha', p: 0.7 }, { tk: 'A:b', name: 'Bravo', p: 0.3 }] } });
  // B's turn 1 ends: Alpha is gone, Bravo lost two models; the cards expect A to destroy Xray (90%)
  G.addTurn(rec, { round: 1, turn: 'B', at: 3, vp: { A: 4, B: 6 }, units: units({ 'A:a': null, 'A:b': 3 }), forecast: { win: 0.45, margin: -2 }, playout: { win: 0.3, vpMe: 50, vpOpp: 60 }, ahead: { side: 'A', destroyed: [{ tk: 'B:x', name: 'Xray', p: 0.9 }, { tk: 'B:y', name: 'Yankee', p: 0.1 }] } });
  // A's turn 2 ends: Xray has no models left (still listed), Yankee untouched
  G.addTurn(rec, { round: 2, turn: 'A', at: 4, vp: { A: 12, B: 6 }, units: units({ 'A:a': null, 'A:b': 3, 'B:x': 0 }), forecast: null, ahead: null });
  return rec;
};

test('a turn is kept with what was said; a turn recorded again replaces the first and what followed it', () => {
  const rec = game();
  assert.deepEqual(rec.turns.map(t => `${t.round}${t.turn}`), ['1A', '1B', '2A']);
  assert.equal(rec.turns[0].units[0].x, 10); assert.equal(rec.turns[0].units[0].y, 20.1); assert.equal(rec.turns[0].forecast.margin, 8);
  assert.deepEqual(rec.turns[0].moves.map(m => m.made), [true, false]);
  G.addTurn(rec, { round: 1, turn: 'B', vp: { A: 5, B: 5 }, units: units() });
  assert.deepEqual(rec.turns.map(t => `${t.round}${t.turn}`), ['1A', '1B'], 'the tracker stepped back: the later turn is gone');
  assert.equal(rec.turns[1].vp.A, 5);
});

test('review: each call against what happened', () => {
  const rec = G.finish(game(), { A: 71, B: 58 }, 9);
  const rv = G.review(rec);
  assert.equal(rv.result, 'win'); assert.equal(rv.margin, 13);
  assert.deepEqual(rv.wins, [{ round: 1, turn: 'A', said: 0.7, margin: 8, playout: null }, { round: 1, turn: 'B', said: 0.45, margin: -2, playout: 0.3 }]);
  // B's turn: Alpha destroyed (gone from the table), Bravo not; A's turn 2: Xray destroyed (no models left); Yankee was under 20%... still read
  assert.deepEqual(rv.kills.map(k => [k.round, k.turn, k.tk, k.happened]), [[1, 'B', 'A:a', true], [1, 'B', 'A:b', false], [2, 'A', 'B:x', true], [2, 'A', 'B:y', false]]);
  assert.deepEqual(rv.moves, { backed: 2, made: 1 });
  assert.equal(G.review(game()).result, null, 'a game still going has no result');
  const lost = G.review(G.finish(game(), { A: 40, B: 58 })); assert.equal(lost.result, 'loss');
});

test('calibration over the finished games: how often what was said happened; unfinished games are left out', () => {
  const cal = G.calibration([G.finish(game(), { A: 71, B: 58 }), G.finish(game(), { A: 40, B: 58 }), game()]);
  assert.equal(cal.games, 2);
  // the forecast said 70% twice (one win, one loss) and 45% twice
  assert.equal(cal.win.n, 4);
  const b70 = cal.win.bands.find(b => b.lo === 0.6), b45 = cal.win.bands.find(b => b.lo === 0.4);
  assert.deepEqual([b70.n, b70.hit, b70.rate], [2, 1, 0.5]); assert.deepEqual([b45.n, b45.hit], [2, 1]);
  assert.ok(Math.abs(cal.win.brier - ((0.3 ** 2 + 0.7 ** 2 + 0.55 ** 2 + 0.45 ** 2) / 4)) < 1e-9);
  assert.equal(cal.playout.n, 2);
  // "destroyed" calls: 0.9 happened twice, 0.7 twice, 0.3 and 0.1 never
  assert.equal(cal.kills.n, 8);
  assert.deepEqual(cal.kills.bands.map(b => [b.n, b.hit]), [[2, 0], [2, 0], [0, 0], [2, 2], [2, 2]]);
  assert.deepEqual(cal.moves, { backed: 4, made: 2 });
  assert.deepEqual(G.calibration([]).win, { n: 0, brier: null, bands: G.calibration([]).win.bands });
});

test('what is sent: the record without times of day; only a finished, well-formed record is accepted', () => {
  const rec = G.finish(game(), { A: 71, B: 58 }, 9), body = G.uploadBody(rec);
  assert.equal(body.format, 'combat-calc-gamelog'); assert.ok(!('started' in body)); assert.ok(body.turns.every(t => !('at' in t))); assert.deepEqual(body.final, { A: 71, B: 58 });
  assert.deepEqual(Object.keys(body).sort(), ['factions', 'final', 'first', 'format', 'layout', 'me', 'missions', 'turns', 'v', 'version']);
  assert.equal(G.validUpload(body).ok, true);
  assert.equal(G.validUpload(JSON.parse(JSON.stringify(body))).ok, true);
  assert.equal(G.validUpload(G.uploadBody(game())).ok, false, 'not finished');
  assert.equal(G.validUpload({ ...body, format: 'x' }).ok, false);
  assert.equal(G.validUpload({ ...body, turns: [] }).ok, false);
  assert.equal(G.validUpload({ ...body, turns: [{ ...body.turns[0], round: 9 }] }).ok, false);
  assert.equal(G.validUpload(null).ok, false);
});

test('half-strength calls (1.153.0): kept with the turn, read against the models left; older records without them still read', () => {
  const rec = G.newRecord({ me: 'A', first: 'A', started: 1 });
  G.addTurn(rec, { round: 1, turn: 'A', vp: { A: 0, B: 0 }, units: units(), ahead: { side: 'B', destroyed: [], halved: [{ tk: 'A:a', name: 'Alpha', p: 0.7 }, { tk: 'A:b', name: 'Bravo', p: 0.4 }] } });
  G.addTurn(rec, { round: 1, turn: 'B', vp: { A: 0, B: 0 }, units: units({ 'A:a': 2, 'A:b': 3 }), ahead: null });
  G.finish(rec, { A: 60, B: 50 });
  const rv = G.review(rec);
  assert.deepEqual(rv.halves.map(h => [h.name, h.p, h.happened]), [['Alpha', 0.7, true], ['Bravo', 0.4, false]], '2 of 5 left is half or less; 3 of 5 is not');
  assert.equal(G.calibration([rec]).halves.n, 2);
  assert.deepEqual(G.review(game()).halves, [], 'a record from before has no such calls');
  assert.equal(G.calibration([G.finish(game(), { A: 1, B: 0 })]).halves.n, 0);
});
