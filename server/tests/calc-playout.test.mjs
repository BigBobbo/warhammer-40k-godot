// Combat Calc — "Play it out": both players follow the turn cards' suggestions to the end of the game.
// Run: node --test server/tests/calc-playout.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const P = await import(new URL('../public/calc/playout.mjs', import.meta.url).href);
const N = await import(new URL('../public/calc/nextturn.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);

const dep = B.DEPLOYMENTS.hammer_anvil;
const OBJS = [
  { id: 'hA', cls: 'home', side: 'A', label: 'A home', x: 22, y: 6, host: [] },
  { id: 'c', cls: 'central', side: null, label: 'Centre', x: 22, y: 30, host: [] },
  { id: 'e1', cls: 'exp', side: 'A', label: 'A-side', x: 8, y: 22, host: [] },
  { id: 'e2', cls: 'exp', side: 'B', label: 'B-side', x: 36, y: 38, host: [] },
  { id: 'hB', cls: 'home', side: 'B', label: 'B home', x: 22, y: 54, host: [] },
];
const GEO = {
  zones: { A: dep.zones.find(z => z.player === 1).poly, B: dep.zones.find(z => z.player === 2).poly },
  territories: { A: dep.territories.find(t => t.player === 1).poly, B: dep.territories.find(t => t.player === 2).poly },
  pieces: [], objectives: OBJS,
};
const INF = B.footprint({ shape: 'round', diameter: 32 });
const unit = (key, x, y, n = 5, o = {}) => ({ key, name: key, x, y, models: B.formation([{ count: n, fp: INF, oc: 2 }]), move: 6, ranges: [24], melee: true, oc: 2 * n, points: 100, left: n, total: n, ...o });
const cell = (o = {}) => ({ shoot: 0, fight: 0, sMu: 0, sSd: 0, fMu: 0, fSd: 0, W: 10, ...o });
const pairOf = (A, Bs, c = {}) => { const t = {}; for (const a of [...A, ...Bs]) { t[a.key] = {}; for (const d of [...A, ...Bs]) if (a.key[0] !== d.key[0]) t[a.key][d.key] = cell(c); } return t; };
const armies = () => ({
  A: [unit('A:home', 22, 6), unit('A:mid', 22, 14), unit('A:flank', 8, 12)],
  B: [unit('B:home', 22, 54), unit('B:mid', 22, 46), unit('B:flank', 36, 48)],
});
const at = (step, key) => step[key[0]].find(u => u.key === key);
const onObj = (u, id) => N.objectiveGap(u, OBJS.find(o => o.id === id), []) <= 0;

test('a turn: the unit on its objective holds, the others walk to objectives that are not held, each to its own', () => {
  const { A, B: Bs } = armies();
  const mv = P.turnMoves({ me: 'A', mine: A, theirs: Bs, pair: pairOf(A, Bs), objs: OBJS, geo: GEO, round: 1, hand: [] });
  assert.deepEqual(mv.map(m => m.unit), A.map(u => u.key), 'one row per unit, in the army\'s order');
  const of = Object.fromEntries(mv.map(m => [m.unit, m]));
  assert.equal(of['A:home'].kind, 'hold'); assert.equal(of['A:home'].dist, 0);
  assert.equal(of['A:mid'].kind, 'advance'); assert.equal(of['A:mid'].label, 'Centre');
  assert.equal(of['A:flank'].label, 'A-side');
  for (const m of mv) assert.ok(m.dist <= 6 + 1e-9, `${m.unit} moves ${m.dist}`);
  assert.ok(of['A:mid'].y > 14 && Math.abs(of['A:mid'].x - 22) < 1e-9, 'straight towards the centre');
});

test('a unit that reaches an objective takes it and stops there; nobody leaves the table', () => {
  const { A, B: Bs } = armies();
  const near = [unit('A:near', 8, 15)];
  const mv = P.turnMoves({ me: 'A', mine: near, theirs: Bs, pair: pairOf(near, Bs), objs: OBJS, geo: GEO, round: 1, hand: [] });
  assert.equal(mv[0].kind, 'take'); assert.equal(mv[0].label, 'A-side');
  assert.ok(onObj({ ...near[0], x: mv[0].x, y: mv[0].y }, 'e1'));
  const res = P.playOut({ A, B: Bs, objs: OBJS, geo: GEO, pair: pairOf(A, Bs), round: 1, turn: 'A', first: 'A', hand: {} });
  for (const st of res.steps) for (const X of ['A', 'B']) for (const u of st[X]) for (const m of u.models) {
    assert.ok(u.x + m.dx >= 0 && u.x + m.dx <= 44 && u.y + m.dy >= 0 && u.y + m.dy <= 60, `${u.key} is off the table in round ${st.round}`);
  }
});

test('the whole game: a step per battle round to round 5, both players move, and the armies end on the objectives', () => {
  const { A, B: Bs } = armies();
  const res = P.playOut({ A, B: Bs, objs: OBJS, geo: GEO, pair: pairOf(A, Bs), round: 1, turn: 'A', first: 'A', hand: {} });
  assert.deepEqual(res.steps.map(s => s.round), [1, 2, 3, 4, 5]);
  assert.deepEqual(res.log.map(l => `${l.round}${l.side}`), ['1A', '1B', '2A', '2B', '3A', '3B', '4A', '4B', '5A', '5B']);
  assert.notEqual(at(res.steps[0], 'B:mid').y, 46, 'the second player moves in round 1 too');
  const end = res.steps[4];
  assert.ok(onObj(at(end, 'A:home'), 'hA') && onObj(at(end, 'B:home'), 'hB'), 'the home objectives stay held');
  assert.ok(onObj(at(end, 'A:flank'), 'e1') && onObj(at(end, 'B:flank'), 'e2'), 'each flank unit took the objective on its side');
  assert.ok(onObj(at(end, 'A:mid'), 'c') || onObj(at(end, 'B:mid'), 'c'), 'somebody is on the centre');
  // nothing is moved in the caller's data
  assert.equal(A[1].y, 14); assert.equal(Bs[1].y, 46);
  // the same game twice is the same game
  assert.deepEqual(P.playOut({ A, B: Bs, objs: OBJS, geo: GEO, pair: pairOf(A, Bs), round: 1, turn: 'A', first: 'A', hand: {} }), res);
});

test('from the middle of a game: only the turns still to come are played', () => {
  const { A, B: Bs } = armies();
  const s = { A, B: Bs, objs: OBJS, geo: GEO, pair: pairOf(A, Bs), hand: {} };
  // round 3, the second player's turn: the first player's turn of this round is over
  const second = P.playOut({ ...s, round: 3, turn: 'B', first: 'A' });
  assert.deepEqual(second.log.map(l => `${l.round}${l.side}`), ['3B', '4A', '4B', '5A', '5B']);
  assert.deepEqual(second.steps.map(x => x.round), [3, 4, 5]);
  assert.equal(at(second.steps[0], 'A:mid').y, 14, 'A does not move again in round 3');
  // my turn, already moved (the Shooting phase): this turn's move is not made twice
  const moved = P.playOut({ ...s, round: 3, turn: 'A', first: 'A', moved: true });
  assert.equal(moved.log[0].done, true); assert.equal(at(moved.steps[0], 'A:mid').y, 14);
  assert.notEqual(at(moved.steps[1], 'A:mid').y, 14, 'it moves in round 4');
  // the last turn of the game
  assert.deepEqual(P.playOut({ ...s, round: 5, turn: 'B', first: 'A' }).log.map(l => `${l.round}${l.side}`), ['5B']);
});

test('a unit with a target in charge reach closes with it; one that can only shoot stays and shoots', () => {
  const A = [unit('A:fist', 22, 20, 5, { ranges: [] }), unit('A:gun', 34, 3, 5, { melee: false, oc: 0 })];
  const Bs = [unit('B:t', 22, 31, 5, { oc: 0 })];
  const pair = pairOf(A, Bs, { shoot: 0.3, fight: 0.6, sMu: 6, sSd: 2, fMu: 9, fSd: 3 });
  const mv = Object.fromEntries(P.turnMoves({ me: 'A', mine: A, theirs: Bs, pair, objs: [], geo: { ...GEO, objectives: [] }, round: 2, hand: [] }).map(m => [m.unit, m]));
  assert.equal(mv['A:fist'].kind, 'charge'); assert.equal(mv['A:fist'].label, 'B:t');
  assert.ok(P.unitGap({ ...A[0], x: mv['A:fist'].x, y: mv['A:fist'].y }, Bs[0]) <= 1, 'it ends in engagement range');
  // 24" guns a little over 24" away: a step forward to shoot, no further than it needs
  assert.equal(mv['A:gun'].kind, 'shoot'); assert.equal(mv['A:gun'].label, 'B:t');
  const g0 = P.unitGap(A[1], Bs[0]), g1 = P.unitGap({ ...A[1], x: mv['A:gun'].x, y: mv['A:gun'].y }, Bs[0]);
  assert.ok(g0 > 24 && g1 <= 24 && g1 >= 22 && mv['A:gun'].dist <= 6, `${g0} -> ${g1}`);
});
