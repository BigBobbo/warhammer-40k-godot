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
  // nothing to shoot and the objective is out of reach: it Advances (Move 6 + 3)
  for (const m of mv) assert.ok(m.dist <= 9 + 1e-9, `${m.unit} moves ${m.dist}`);
  assert.equal(of['A:mid'].adv, true); assert.ok(of['A:mid'].dist > 6);
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

const T = await import(new URL('../public/calc/paths.mjs', import.meta.url).href);
const WALL = { id: 'w', cls: 'feature', cat: 'dense', h: 5, poly: [[14, 29], [30, 29], [30, 31], [14, 31]] };
const TANK = B.footprint({ shape: 'round', diameter: 100 });
const tank = (key, x, y, o = {}) => ({ key, name: key, x, y, models: [{ dx: 0, dy: 0, fp: TANK, oc: 3 }], move: 10, ranges: [36], melee: true, oc: 3, points: 150, left: 1, total: 1, keywords: ['VEHICLE'], ...o });

test('paths: infantry walks through dense terrain, a vehicle goes round it by the shorter side', () => {
  const inf = { ...unit('A:i', 22, 20), keywords: ['INFANTRY'] }, tk = tank('A:t', 26, 20);
  assert.equal(T.goesRound(inf), false); assert.equal(T.goesRound(tk), true);
  assert.equal(T.goesRound({ ...tk, keywords: ['VEHICLE', 'FLY'] }), false, 'a unit that can FLY passes over');
  assert.equal(T.route(inf, 22, 40, [WALL]).direct, true);
  const rt = T.route(tk, 26, 40, [WALL]);
  assert.equal(rt.direct, false); assert.equal(rt.blocked, false);
  assert.ok(rt.len > 20.5 && rt.len < 30, `round the wall: ${rt.len}`);
  assert.ok(rt.pts.some(q => q[0] > 30), 'by the right-hand end, the nearer one');
  for (let d = 0; d <= rt.len; d += 0.5) { const q = T.along(rt.pts, d); assert.ok(!(q.x > 14 - 1.5 && q.x < 30 + 1.5 && q.y > 29 - 1.5 && q.y < 31 + 1.5), `through the wall at ${d}`); }
  // light terrain, a low wall and an area are no obstacle
  for (const p of [{ ...WALL, cat: 'light' }, { ...WALL, h: 2 }, { ...WALL, cls: 'area' }]) assert.equal(T.route(tk, 26, 40, [p]).direct, true);
  assert.ok(Math.abs(T.detour(tk, 26, 40, [WALL]) - (rt.len - 20)) < 1e-9);
});

test('the turn cards measure a vehicle\'s move round the terrain in its way', () => {
  const obj = [{ id: 'c', cls: 'central', side: null, label: 'Centre', x: 26, y: 38, host: [] }];
  const tk = tank('A:t', 26, 26), foe = [unit('B:x', 22, 57)];
  const geo = { ...GEO, pieces: [WALL], objectives: obj };
  const reach = (pieces) => N.objectiveSwing(foe, [tk], obj, pieces, { me: 'B' })[0].movers.map(m => m.via);
  assert.deepEqual(reach([]), ['move'], 'a straight 10" move gets it in range');
  assert.deepEqual(reach([WALL]), ['advance'], 'round the wall is further than its Move');
  const far = tank('A:t', 26, 26, { move: 16 });
  const sw = N.objectiveSwing(foe, [far], obj, [WALL], { me: 'B' });
  const cd = N.moveCandidates([far], sw, [WALL]);
  assert.equal(cd.length, 1); assert.ok(cd[0].via?.length >= 1 && cd[0].dist > 10, JSON.stringify(cd[0]));
  assert.ok(N.objectiveGap({ ...far, x: cd[0].x, y: cd[0].y }, obj[0], [WALL]) <= 0);
  const mv = P.turnMoves({ me: 'A', mine: [far], theirs: foe, pair: pairOf([far], foe), objs: obj, geo, round: 2, hand: [] })[0];
  assert.equal(mv.kind, 'take'); assert.ok(mv.y > 31 + 1.9, 'it ends on the far side of the wall');
});

test('no stacking: two units sent to the same place end beside each other, both still on the objective', () => {
  const A = [unit('A:a', 20, 22), unit('A:b', 24, 22)], Bs = [unit('B:x', 22, 57)];
  const objs = [{ id: 'c', cls: 'central', side: null, label: 'Centre', x: 22, y: 30, host: [] }];
  const res = P.playOut({ A, B: Bs, objs, geo: { ...GEO, objectives: objs }, pair: pairOf(A, Bs), round: 1, turn: 'A', first: 'A', hand: {}, rounds: 3 });
  for (const st of res.steps) {
    const all = [...st.A, ...st.B].flatMap(u => u.models.map(m => ({ k: u.key, x: u.x + m.dx, y: u.y + m.dy, r: 32 / 25.4 / 2 })));
    for (const p of all) for (const q of all) if (p.k !== q.k) assert.ok(Math.hypot(p.x - q.x, p.y - q.y) >= p.r + q.r - 1e-6, `${p.k} is on ${q.k} in round ${st.round}`);
  }
  const sp = P.freeSpot(A[0], 24, 22, A[1].models.map(m => ({ x: 24 + m.dx, y: 22 + m.dy, r: 0.63, foe: false })));
  assert.ok(sp && sp.moved > 0, 'a spot on another unit is moved off it');
  assert.equal(P.freeSpot(A[0], 10, 40, []).moved, 0);
});

test('casualties: a unit more likely destroyed than not stops acting, and the log says when', () => {
  const A = [unit('A:gun', 22, 14, 5, { oc: 0 })], Bs = [unit('B:prey', 22, 34), unit('B:far', 22, 57)];
  const pair = pairOf(A, Bs, {}); pair['A:gun']['B:prey'] = cell({ shoot: 0.9, sMu: 14, sSd: 2 });
  const res = P.playOut({ A, B: Bs, objs: OBJS, geo: GEO, pair, round: 1, turn: 'A', first: 'A', hand: {} });
  assert.equal(res.gone['B:prey'], 1);
  assert.deepEqual(res.log[0].lost.map(l => l.unit), ['B:prey']); assert.ok(res.log[0].lost[0].p > 0.5);
  // it takes no further part: no move of its own after that, the other unit of B goes on
  for (const l of res.log.filter(x => x.side === 'B')) assert.ok(!l.moves.some(m => m.unit === 'B:prey'), `B:prey still acts in round ${l.round}`);
  assert.ok(res.log.filter(x => x.side === 'B').some(l => l.moves.some(m => m.unit === 'B:far')));
  // it stays in the steps where it stood (the forecast rolls its own dice for it)
  assert.equal(at(res.steps[4], 'B:prey').y, 34);
});

test('reserves come on from round 2: 6" from an edge, more than 8" from the enemy; Deep Strike anywhere', () => {
  const { A, B: Bs } = armies();
  const res1 = unit('A:res', 0, 0), deep = { ...unit('A:deep', 0, 0), deepStrike: true };
  // (an objective out on the flank that nobody walks to: a place to come down on in round 2)
  const objs = [...OBJS, { id: 'x', cls: 'exp', side: null, label: 'Flank', x: 38, y: 18, host: [] }];
  const run = (reserves) => P.playOut({ A, B: Bs, objs, geo: { ...GEO, objectives: objs }, pair: pairOf([...A, res1, deep], Bs), round: 1, turn: 'A', first: 'A', hand: {}, reserves });
  const out = run({ A: [res1, deep], B: [] });
  assert.ok(!out.steps[0].A.some(u => u.key === 'A:res' || u.key === 'A:deep'), 'nobody arrives in round 1');
  const arr = out.log.flatMap(l => l.moves.filter(m => m.kind === 'arrive').map(m => ({ ...m, round: l.round })));
  assert.deepEqual(arr.map(m => m.unit).sort(), ['A:deep', 'A:res']);
  for (const m of arr) {
    assert.ok(m.round === 2 || m.round === 3, `arrives in round ${m.round}`);
    const u = at(out.steps[m.round - 1], m.unit);
    assert.ok(u, `${m.unit} is on the table from round ${m.round}`);
    if (m.unit === 'A:res') for (const md of u.models) assert.ok(Math.min(u.x + md.dx, 44 - u.x - md.dx, u.y + md.dy, 60 - u.y - md.dy) <= 6 - 0.6 + 1e-6, 'wholly within 6" of an edge');
  }
  const d = arr.find(m => m.unit === 'A:deep'), ud = at(out.steps[d.round - 1], 'A:deep');
  assert.equal(d.round, 2); assert.ok(objs.some(o => N.objectiveGap(ud, o, []) <= 0), 'Deep Strike comes down on an objective');
  assert.deepEqual(P.arrival(res1, 'A', { objs: OBJS, geo: GEO }, { A, B: [unit('B:wall', 22, 30, 5)] }, 2, []) !== null, true);
});

test('a unit in a transport gets out beside it, by round 3 at the latest', () => {
  const car = tank('A:car', 22, 10, { keywords: ['VEHICLE', 'TRANSPORT'] });
  const boys = { ...unit('A:boys', 0, 0), in: 'A:car' };
  const Bs = [unit('B:home', 22, 54)];
  const res = P.playOut({ A: [car], B: Bs, objs: OBJS, geo: GEO, pair: pairOf([car, boys], Bs), round: 1, turn: 'A', first: 'A', hand: {}, embarked: { A: [boys], B: [] } });
  const out = res.log.flatMap(l => l.moves.filter(m => m.kind === 'disembark').map(m => ({ ...m, round: l.round })));
  assert.equal(out.length, 1); assert.ok(out[0].round <= 3); assert.equal(out[0].label, 'A:car');
  const st = res.steps[out[0].round - 1], u = at(st, 'A:boys'), c = at(st, 'A:car');
  assert.ok(u && !('in' in u));
  // (a unit keeps its formation here: it is set down as near the transport as its bases allow, not model by model)
  assert.ok(Math.min(...u.models.map(m => Math.hypot(u.x + m.dx - c.x, u.y + m.dy - c.y))) - 100 / 25.4 / 2 <= 3 + 1e-6, 'beside the transport');
  assert.ok(P.unitGap(u, c) >= 0 && Math.hypot(u.x - c.x, u.y - c.y) <= 8, 'not on it, not far from it');
  assert.ok(res.log.some(l => l.round > out[0].round && l.moves.some(m => m.unit === 'A:boys')), 'then it acts like any unit');
});

test('casualties count only what can attack from where it stands: in range and in sight, or in engagement range; one target each', () => {
  const pairFor = (A, Bs, c) => pairOf(A, Bs, c);
  const gun = unit('A:gun', 22, 14, 5, { oc: 0, melee: false }), prey = unit('B:prey', 22, 34), far = unit('B:far', 22, 57);
  const c = { shoot: 0.8, sMu: 13, sSd: 2, fight: 0.9, fMu: 15, fSd: 2 };
  // in range (20") and in sight: counted, at the calculator's figure
  const open = P.turnCasualties([prey, far], [gun], pairFor([gun], [prey, far], c), []);
  assert.deepEqual(open.map(r => [r.key, r.p, r.by]), [['B:prey', 0.8, ['A:gun']]]);
  // a wall that hides the target: the turn cards still say "likely" (it could move round), the play-out does not
  const wall = [{ id: 'ruin', cls: 'area', cat: 'dense', h: 5, parent: null, link: null, traits: ['obscuring'], poly: [[10, 22], [34, 22], [34, 26], [10, 26]] }];
  assert.ok(N.turnThreats([prey], [gun], pairFor([gun], [prey], c), { pieces: wall })[0].likely > 0.5, 'the card\'s upper bound');
  assert.deepEqual(P.turnCasualties([prey], [gun], pairFor([gun], [prey], c), wall), []);
  // out of range from where it stands (26"), though a move would bring it in: not counted
  assert.deepEqual(P.turnCasualties([prey], [{ ...gun, y: 8 }], pairFor([gun], [prey], c), []), []);
  // a unit in engagement range fights; it does not also count as charging something else
  const fist = unit('A:fist', 22, 32.2, 5, { ranges: [] });
  const melee = P.turnCasualties([prey, far], [fist], pairFor([fist], [prey, far], c), []);
  assert.deepEqual(melee.map(r => [r.key, r.p]), [['B:prey', 0.9]]);
  // it charged this turn and needed a 7 (58%): it fights that often
  const half = P.turnCasualties([prey, far], [fist], pairFor([fist], [prey, far], c), [], new Map([['A:fist', 21 / 36]]));
  assert.ok(Math.abs(half[0].p - 0.9 * 21 / 36) < 1e-9, String(half[0].p));
  // turnMoves says how likely each charge it walks is
  const runner = unit('A:run', 22, 20.2, 5, { ranges: [] });
  const cm = P.turnMoves({ me: 'A', mine: [runner], theirs: [prey], pair: pairFor([runner], [prey], c), objs: [], geo: { ...GEO, objectives: [] }, round: 2, hand: [] })[0];
  assert.equal(cm.kind, 'charge'); assert.ok(cm.chargeP > 0.2 && cm.chargeP < 1, String(cm.chargeP));
  // two shooters with two targets in reach: each attacks one, the one it is worth most against
  const g2 = unit('A:g2', 30, 14, 5, { oc: 0, melee: false }), cheap = unit('B:cheap', 30, 34, 5, { points: 40 });
  const two = P.turnCasualties([prey, cheap], [gun, g2], pairFor([gun, g2], [prey, cheap], c), []);
  assert.deepEqual(two.map(r => r.key), ['B:prey']); assert.deepEqual(two[0].by.sort(), ['A:g2', 'A:gun']);
  assert.ok(two[0].p > 0.8);
});

test('caution: a unit does not walk into a place where it is likely destroyed, unless the walk takes the objective or it is no safer where it stands', () => {
  const objs = [{ id: 'c', cls: 'central', side: null, label: 'Centre', x: 22, y: 40, host: [] }];
  const geo = { ...GEO, objectives: objs };
  const walker = unit('A:w', 22, 10, 5, { ranges: [] }), brute = unit('B:brute', 22, 46, 5, { ranges: [], oc: 0 });
  // the brute destroys what it reaches (charge reach: its Move 6 + the charge roll); 10" of walking ends inside that reach
  const deadly = pairOf([walker], [brute], { fight: 0.95, fMu: 20, fSd: 2 });
  const run = (mine, pair) => P.turnMoves({ me: 'A', mine, theirs: [brute], pair, objs, geo, round: 2, hand: [] })[0];
  const far = run([walker], deadly);
  assert.equal(far.kind, 'advance', 'out of the brute\'s reach where the walk ends: it walks');
  const near = unit('A:w', 22, 24, 5, { ranges: [] });
  const held = run([near], deadly);
  assert.equal(held.kind, 'wait'); assert.equal(held.dist, 0); assert.equal(held.label, 'Centre'); assert.ok(held.risk >= 0.5);
  // a harmless enemy: it walks on
  assert.equal(run([near], pairOf([near], [brute], { fight: 0.05, fMu: 1, fSd: 1 })).kind, 'advance');
  // the walk gets onto the objective: it is made whatever the danger
  const close = unit('A:w', 22, 31, 5, { ranges: [] });
  assert.equal(run([close], deadly).kind, 'take');
  // already as exposed where it stands: nothing is gained by waiting
  const stuck = unit('A:w', 22, 34, 5, { ranges: [], move: 1 });
  assert.notEqual(run([stuck], deadly).kind, 'wait');
});
