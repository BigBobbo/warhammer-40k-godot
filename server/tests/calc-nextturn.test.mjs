// Combat Calc — "Their next turn": threats to my units, objectives they can take, the cards they can score.
// Run: node --test server/tests/calc-nextturn.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const N = await import(new URL('../public/calc/nextturn.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);

// Hammer and Anvil: A's zone along the top short edge, B's along the bottom. I am A; "they" are B.
const dep = B.DEPLOYMENTS.hammer_anvil;
const GEO = {
  zones: { A: dep.zones.find(z => z.player === 1).poly, B: dep.zones.find(z => z.player === 2).poly },
  territories: { A: dep.territories.find(t => t.player === 1).poly, B: dep.territories.find(t => t.player === 2).poly },
  pieces: [], objectives: [],
};
const OBJS = [
  { id: 'hA', cls: 'home', side: 'A', label: 'A home', x: 22, y: 6, host: [] },
  { id: 'c', cls: 'central', side: null, label: 'Centre', x: 22, y: 30, host: [] },
  { id: 'e1', cls: 'exp', side: 'A', label: 'A-side', x: 8, y: 22, host: [] },
  { id: 'e2', cls: 'exp', side: 'B', label: 'B-side', x: 36, y: 38, host: [] },
  { id: 'hB', cls: 'home', side: 'B', label: 'B home', x: 22, y: 54, host: [] },
];
GEO.objectives = OBJS;
const INF = B.footprint({ shape: 'round', diameter: 32 });
const unit = (key, x, y, n = 5, o = {}) => ({ key, name: key, x, y, models: B.formation([{ count: n, fp: INF, oc: 2 }]), move: 6, ranges: [24], melee: true, oc: 2 * n, points: 100, left: n, total: n, ...o });
const cell = (o = {}) => ({ shoot: 0, fight: 0, sMu: 0, sSd: 0, fMu: 0, fSd: 0, W: 10, ...o });

test('kill chance: one attack is the calculator figure; several add their wounds up', () => {
  assert.equal(N.killChance([{ mu: 4, v: 4, p: 0.2 }], 10), 0.2);
  // two attacks of 6 +/- 2 wounds into 10: the sum (12 +/- 2.8) gets there most of the time, far more than "one alone"
  const two = N.killChance([{ mu: 6, v: 4, p: 0.05 }, { mu: 6, v: 4, p: 0.05 }], 10);
  assert.ok(two > 0.75 && two < 0.9, String(two));
  assert.equal(N.killChance([], 10), 0);
  assert.ok(Math.abs(N.phi(0) - 0.5) < 1e-6 && Math.abs(N.phi(1.96) - 0.975) < 1e-3);
});

test('threats: in reach after a move = shot at; out of reach = safe; most at risk first', () => {
  const mine = [unit('A:near', 22, 20), unit('A:far', 22, 2)];
  // a gun line 34" from A:near (move 6 + range 24 does not reach) and one 20" away (it does)
  const theirs = [unit('B:gun', 22, 41.5, 5, { melee: false }), unit('B:back', 22, 57, 5, { melee: false })];
  const pair = { 'B:gun': { 'A:near': cell({ shoot: 0.6, sMu: 8, sSd: 2 }), 'A:far': cell({ shoot: 0.6, sMu: 8, sSd: 2 }) }, 'B:back': { 'A:near': cell({ shoot: 0.6, sMu: 8, sSd: 2 }), 'A:far': cell({ shoot: 0.6 }) } };
  const t = N.turnThreats(mine, theirs, pair);
  assert.equal(t[0].key, 'A:near');
  assert.ok(Math.abs(t[0].likely - 0.6) < 1e-9 && Math.abs(t[0].focus - 0.6) < 1e-9);
  assert.deepEqual(t[0].by.map(b => b.key), ['B:gun']);
  assert.equal(t[1].focus, 0);
});

test('threats: "likely" sends each of their units at one target, "if focused" sends everything in reach', () => {
  const mine = [unit('A:cheap', 18, 20, 5, { points: 50 }), unit('A:dear', 26, 20, 5, { points: 300 })];
  const theirs = [unit('B:g1', 18, 36, 5, { melee: false }), unit('B:g2', 26, 36, 5, { melee: false })];
  const c = cell({ shoot: 0.3, sMu: 6, sSd: 2 });
  const pair = { 'B:g1': { 'A:cheap': c, 'A:dear': c }, 'B:g2': { 'A:cheap': c, 'A:dear': c } };
  const t = N.turnThreats(mine, theirs, pair);
  const dear = t.find(x => x.key === 'A:dear'), cheap = t.find(x => x.key === 'A:cheap');
  assert.ok(dear.likely > 0.5, 'both guns pick the 300-point unit');
  assert.equal(cheap.likely, 0);
  assert.ok(Math.abs(cheap.focus - dear.focus) < 1e-9 && cheap.focus > 0.5, 'but either could be destroyed if they chose it');
});

test('threats: models lost scale the damage (attacker) and the wounds to remove (target)', () => {
  const pair = { 'B:g': { 'A:t': cell({ shoot: 0.1, sMu: 5, sSd: 2 }) } };
  const full = N.turnThreats([unit('A:t', 22, 20)], [unit('B:g', 22, 36, 5, { melee: false })], pair)[0];
  const hurt = N.turnThreats([unit('A:t', 22, 20, 5, { left: 2, total: 5 })], [unit('B:g', 22, 36, 5, { melee: false })], pair)[0];
  const weak = N.turnThreats([unit('A:t', 22, 20)], [unit('B:g', 22, 36, 5, { melee: false, left: 1, total: 5 })], pair)[0];
  assert.ok(Math.abs(full.focus - 0.1) < 1e-9);
  assert.ok(hurt.focus > 0.5, `2 of 5 models left (4 wounds) against 5 +/- 2: ${hurt.focus}`);
  assert.ok(weak.focus < 0.01, `1 of 5 attackers left: ${weak.focus}`);
});

test('threats: a charge counts by its odds; a unit without melee does not charge', () => {
  const pair = { 'B:m': { 'A:t': cell({ fight: 0.8, fMu: 9, fSd: 2 }) } };
  // 13" away: move 6, then a 7+ charge (58%)
  const t = N.turnThreats([unit('A:t', 22, 20, 1)], [unit('B:m', 22, 34.2, 1, { ranges: [] })], pair)[0];
  assert.ok(Math.abs(t.by[0].charge - 21 / 36) < 1e-9, String(t.by[0].charge));
  assert.ok(Math.abs(t.focus - 0.8 * 21 / 36) < 1e-9);
  assert.equal(N.turnThreats([unit('A:t', 22, 20, 1)], [unit('B:m', 22, 34.2, 1, { ranges: [], melee: false })], pair)[0].focus, 0);
});

test('objectives: they can take, tie, need an Advance, or cannot reach', () => {
  const mine = [unit('A:hold', 22, 30, 2)];                         // two models, OC 4, both on the centre
  const swing = (theirs, o = {}) => N.objectiveSwing(mine, theirs, OBJS, [], { me: 'A', ...o }).find(x => x.id === 'c');
  const big = swing([unit('B:mob', 22, 40, 10)]);                   // 20 OC, a normal move from being in range
  assert.equal(big.holder, 'me'); assert.equal(big.mine, 4);
  assert.equal(big.verdict, 'lose'); assert.equal(big.movers[0].via, 'move');
  assert.equal(swing([unit('B:two', 22, 40, 2)]).verdict, 'contest', '4 OC against 4: nobody controls it');
  assert.equal(swing([unit('B:one', 22, 40, 1)]).verdict, 'safe');
  const adv = swing([unit('B:mob', 22, 45, 10)]);                   // needs an Advance
  assert.equal(adv.verdict, 'advance'); assert.equal(adv.movers[0].via, 'advance'); assert.ok(adv.movers[0].need >= 1 && adv.movers[0].need <= 6);
  assert.equal(swing([unit('B:mob', 22, 58, 10)]).verdict, 'safe', 'out of reach');
});

test('objectives: a battle-shocked holder has no OC; an empty objective in reach is theirs to take', () => {
  const sw = N.objectiveSwing([unit('A:hold', 22, 30, 5, { shocked: true })], [unit('B:two', 22, 40, 2)], OBJS, [], { me: 'A' });
  const c = sw.find(x => x.id === 'c');
  assert.equal(c.mine, 0); assert.equal(c.verdict, 'take');
  assert.equal(sw.find(x => x.id === 'e2').verdict, 'advance', 'about 10" off: only with an Advance');
  assert.equal(sw.find(x => x.id === 'hA').verdict, 'open', 'out of a move and an Advance');
  const there = N.objectiveSwing([], [unit('B:on', 36, 38, 5)], OBJS, [], { me: 'A' }).find(x => x.id === 'e2');
  assert.equal(there.holder, 'them'); assert.equal(there.verdict, 'theirs');
});

test('a unit goes to one objective: two objectives need two units', () => {
  // one mob between the centre and the B-side objective can reach both, but hold only one
  const one = N.objectiveSwing([], [unit('B:mob', 29, 34, 5)], OBJS, [], { me: 'A' });
  assert.equal(one.find(x => x.id === 'c').verdict, 'take'); assert.equal(one.find(x => x.id === 'e2').verdict, 'take');
  assert.equal(N.controllable(one, ['c', 'e2']).n, 1);
  const two = N.objectiveSwing([], [unit('B:mob', 29, 34, 5), unit('B:b', 36, 44, 5)], OBJS, [], { me: 'A' });
  assert.equal(N.controllable(two, ['c', 'e2']).n, 2);
});

test('reach: what a unit can be after a normal move', () => {
  const zA = GEO.zones.A, edge = Math.max(...zA.map(p => p[1]));     // the open edge of my deployment zone
  const near = N.reachFacts(unit('B:x', 22, edge + 4, 1), 'B', GEO);
  assert.equal(near.now.inEnemyDZ, false); assert.equal(near.canEnemyDZ, true);
  assert.equal(N.reachFacts(unit('B:y', 22, edge + 12, 1), 'B', GEO).canEnemyDZ, false);
  assert.equal(N.reachFacts(unit('B:z', 22, 35, 1), 'B', GEO).centre3, true);
  assert.equal(N.maxQuarters([[0], [0], [1, 2]]), 2);
  assert.equal(N.maxQuarters([[0, 1], [0], [2], [3, 2]]), 4);
});

test('cards: scored by moving, only by destroying something, or out of reach', () => {
  const zA = GEO.zones.A, edge = Math.max(...zA.map(p => p[1]));
  const mine = [unit('A:hold', 22, 30, 5), unit('A:boss', 22, 10, 1, { chars: 1 })];
  const theirs = [unit('B:deep', 22, edge + 4, 1), unit('B:mob', 22, 40, 10)];
  const pair = { 'B:mob': { 'A:hold': cell({ shoot: 0.4, sMu: 7, sSd: 2 }), 'A:boss': cell({ W: 5 }) }, 'B:deep': { 'A:hold': cell(), 'A:boss': cell({ shoot: 0.25, sMu: 3, sSd: 1.5, W: 5 }) } };
  const r = N.nextTurn({ me: 'A', mine, theirs, pair, geo: GEO, objs: OBJS, round: 2,
    hand: ['behind-enemy-lines', 'assassination', 'bring-it-down', 'engage-on-all-fronts', 'centre-ground', 'no-prisoners'] });
  const card = (id) => r.cards.find(c => c.id === id);
  assert.equal(card('behind-enemy-lines').verdict, 'yes'); assert.equal(card('behind-enemy-lines').vp, 3);
  assert.equal(card('assassination').verdict, 'kill'); assert.ok(Math.abs(card('assassination').p - 0.25) < 1e-9);
  assert.equal(card('bring-it-down').verdict, 'no');
  assert.equal(card('engage-on-all-fronts').verdict, 'no');
  assert.equal(card('centre-ground').verdict, 'kill', 'my unit is within 3" of the centre');
  assert.equal(card('no-prisoners').verdict, 'kill');
  assert.equal(r.vpAtStake, 3);
  assert.equal(r.cards[0].id, 'behind-enemy-lines', 'what they can score by moving comes first');
  assert.equal(r.swing.find(o => o.id === 'c').verdict, 'lose');
  assert.ok(r.swing.find(o => o.id === 'c').holders[0].risk > 0, 'the holder\'s own risk is on the objective row');
});

test('cards scored at the end of MY turn are read as the table stands', () => {
  const theirs = [unit('B:home', 22, 54, 5), unit('B:out', 22, 20, 1)];
  const r = N.nextTurn({ me: 'A', mine: [unit('A:x', 22, 6, 5)], theirs, pair: {}, geo: GEO, objs: OBJS, round: 2, hand: ['defend-stronghold', 'beacon', 'burden-of-trust'] });
  const ds = r.cards.find(c => c.id === 'defend-stronghold');
  assert.equal(ds.when, 'mine'); assert.equal(ds.verdict, 'now'); assert.equal(ds.vp, 5);
  assert.equal(r.cards.find(c => c.id === 'beacon').verdict, 'ask');
  assert.equal(r.cards.find(c => c.id === 'burden-of-trust').vp, 2);
  const r1 = N.nextTurn({ me: 'A', mine: [], theirs, pair: {}, geo: GEO, objs: OBJS, round: 1, hand: ['defend-stronghold'] });
  assert.equal(r1.cards[0].verdict, 'no');
});

// ---- "My turn" (1.136.0)

test('my voice: a sentence about them, said about me', () => {
  assert.equal(N.myVoice('they can control your home objective'), 'you can control their home objective');
  assert.equal(N.myVoice('They must destroy 2 of yours there'), 'You must destroy 2 of theirs there');
  assert.equal(N.myVoice('nothing of theirs can destroy your CHARACTER units'), 'nothing of yours can destroy their CHARACTER units');
});

test('kill plan: units are sent where they add the most; a kill that is already sure gets no more', () => {
  const theirs = [unit('B:dear', 18, 30, 5, { points: 300 }), unit('B:cheap', 26, 30, 5, { points: 60 })];
  const mine = [unit('A:g1', 18, 14, 5, { melee: false }), unit('A:g2', 22, 14, 5, { melee: false }), unit('A:g3', 26, 14, 5, { melee: false })];
  const sure = cell({ shoot: 1, sMu: 10, sSd: 0.1 }), half = cell({ shoot: 0.5, sMu: 6, sSd: 3 });
  const pair = { 'A:g1': { 'B:dear': sure, 'B:cheap': half }, 'A:g2': { 'B:dear': sure, 'B:cheap': half }, 'A:g3': { 'B:dear': half, 'B:cheap': half } };
  const k = N.killPlan(N.turnThreats(theirs, mine, pair));
  const dear = k.find(x => x.key === 'B:dear'), cheap = k.find(x => x.key === 'B:cheap');
  assert.equal(k[0].key, 'B:dear');
  assert.equal(dear.by.length, 1, 'one unit destroys it for sure: the others go elsewhere');
  assert.equal(cheap.by.length, 2);
  assert.ok(cheap.p > 0.5);
});

test('kill plan: a card of mine makes its target worth more', () => {
  const theirs = [unit('B:mob', 18, 30, 5, { points: 120 }), unit('B:boss', 26, 30, 1, { points: 80, chars: 1 })];
  const mine = [unit('A:g', 22, 14, 5, { melee: false })];
  const c = cell({ shoot: 0.5, sMu: 6, sSd: 3 });
  const pair = { 'A:g': { 'B:mob': c, 'B:boss': c } };
  const base = { me: 'A', mine, theirs, pair, geo: GEO, objs: OBJS, round: 2 };
  assert.equal(N.myTurn({ ...base, hand: [] }).kills[0].key, 'B:mob');
  assert.equal(N.myTurn({ ...base, hand: ['assassination'] }).kills[0].key, 'B:boss');
});

test('my turn: a unit holds what it stands on, a free unit takes what is in reach, each has a target', () => {
  const mine = [unit('A:home', 22, 6, 5), unit('A:mid', 22, 22, 5), unit('A:far', 4, 4, 1)];
  const theirs = [unit('B:two', 22, 32, 2, { points: 90 })];          // on the centre with 2 models (OC 4)
  const pair = { 'A:mid': { 'B:two': cell({ shoot: 0.7, sMu: 9, sSd: 2, fight: 0.5, fMu: 7, fSd: 2 }) }, 'A:home': { 'B:two': cell({ shoot: 0.2, sMu: 4, sSd: 2 }) } };
  const r = N.myTurn({ me: 'A', mine, theirs, pair, geo: GEO, objs: OBJS, round: 2, hand: ['secure-no-mans-land', 'no-prisoners'], risk: { 'A:mid': 0.4 } });
  const u = (k) => r.units.find(x => x.key === k);
  assert.equal(u('A:home').job.kind, 'hold'); assert.equal(u('A:home').job.label, 'A home');
  assert.equal(u('A:mid').job.kind, 'take'); assert.equal(u('A:mid').job.label, 'Centre');
  assert.equal(u('A:mid').attack.key, 'B:two'); assert.ok(/shoot/.test(u('A:mid').attack.how));
  assert.equal(u('A:mid').risk, 0.4);
  assert.equal(u('A:far').job.kind, 'none'); assert.equal(u('A:far').attack, null);
  assert.equal(r.units[0].key, 'A:mid', 'units with something to take come first');
  assert.equal(r.swing.find(o => o.id === 'c').verdict, 'lose', 'seen from their side: they lose the centre');
  const np = r.cards.find(x => x.id === 'no-prisoners');
  assert.equal(np.verdict, 'kill'); assert.ok(!/\bthey\b/i.test(r.cards.find(x => x.id === 'secure-no-mans-land').why));
});

// ---- moves weighed with the forecast (1.137.0)

test('move candidates: onto each objective a normal move reaches; back towards home only for a unit at risk', () => {
  const mine = [unit('A:mid', 22, 22, 5), unit('A:far', 4, 4, 1)];
  const swing = N.objectiveSwing([], mine, OBJS, [], { me: 'B' });
  const home = OBJS[0];
  const c = N.moveCandidates(mine, swing, [], { risk: { 'A:mid': 0.6 }, home });
  const k = c.map(x => x.key);
  assert.ok(k.includes('A:mid>c') && k.includes('A:mid>e1') && k.includes('A:mid>back'), k.join());
  assert.ok(!k.some(x => x.startsWith('A:far')), 'nothing in reach of the far unit, and it is not at risk');
  const toC = c.find(x => x.key === 'A:mid>c');
  assert.ok(toC.dist <= 6 + 1e-9 && N.objectiveGap({ ...mine[0], x: toC.x, y: toC.y }, OBJS[1], []) === 0, 'after the move a model is in range');
  assert.ok(c.find(x => x.key === 'A:mid>back').y < 22, 'back = towards my home objective');
  assert.equal(c[c.length - 1].kind, 'back', 'moves onto objectives are tried first');
});

test('best moves: the best candidate of each unit, only when it beats standing still by the noise margin', () => {
  const res = (a, b, w) => ({ A: { mean: a }, B: { mean: b }, pWinA: w, pWinB: 1 - w });
  const cands = [{ key: 'u1>c', unit: 'u1' }, { key: 'u1>e1', unit: 'u1' }, { key: 'u2>c', unit: 'u2' }, { key: 'u3>back', unit: 'u3' }];
  const base = res(50, 45, 0.6);
  const m = N.bestMoves(cands, base, { 'u1>c': res(56, 44, 0.7), 'u1>e1': res(53, 45, 0.65), 'u2>c': res(51, 45, 0.61), 'u3>back': res(49, 40, 0.68) }, 'A');
  assert.deepEqual(m.map(x => x.key), ['u1>c', 'u3>back'], 'u2 gains 1 VP: within the noise');
  assert.equal(N.MOVE_MIN_VP, 3, 'about 3x the measured noise of a difference (0.95 VP)');
  assert.ok(Math.abs(m[0].dVp - 7) < 1e-9 && Math.abs(m[0].dWin - 0.1) < 1e-9);
  assert.ok(Math.abs(N.bestMoves(cands, base, { 'u1>c': res(56, 44, 0.7) }, 'B').length) === 0, 'for B the same move is worse');
});

test('moves made together: one that adds nothing on top of the others is dropped', () => {
  const res = (a, b, w) => ({ A: { mean: a }, B: { mean: b }, pWinA: w, pWinB: 1 - w });
  const moves = [{ key: 'u1>c' }, { key: 'u2>c' }, { key: 'u3>e1' }];
  const k = N.keepMoves(moves, res(50, 45, 0.6), [res(56, 44, 0.7), res(56.5, 44, 0.71), res(60, 43, 0.8)], 'A');
  assert.deepEqual(k.moves.map(x => x.key), ['u1>c', 'u3>e1'], 'the second unit onto the same objective adds 0.5 VP');
  assert.ok(Math.abs(k.vp - 17) < 1e-9 && k.win === 0.8);
});

test('a move candidate says whether the objective is in a terrain area (a base in that area is in range)', () => {
  const mine = [unit('A:mid', 22, 22, 5)];
  const open = N.moveCandidates(mine, N.objectiveSwing([], mine, OBJS, [], { me: 'B' }), []);
  assert.equal(open.find(x => x.obj === 'c').hosted, false);
  const area = { id: 't1', cls: 'area', poly: [[17, 26], [27, 26], [27, 34], [17, 34]] };
  const objs = OBJS.map(o => (o.id === 'c' ? { ...o, host: ['t1'] } : o));
  const c = N.moveCandidates(mine, N.objectiveSwing([], mine, objs, [area], { me: 'B' }), [area]).find(x => x.obj === 'c');
  assert.equal(c.hosted, true);
  assert.ok(c.dist < 5, `the edge of the area is nearer than the marker: ${c.dist}`);
});

test('risk after a move: their next turn worked out again with the unit where the move ends', () => {
  const mine = [unit('A:u', 22, 6, 5)], theirs = [unit('B:g', 22, 50, 5, { melee: false })];
  const pair = { 'B:g': { 'A:u': cell({ shoot: 0.4, sMu: 7, sSd: 2 }) } };
  assert.equal(N.turnThreats(mine, theirs, pair)[0].likely, 0, 'out of reach where it stands (44" away, move 6 + range 24)');
  const r = N.riskAfterMove(mine, theirs, pair, { unit: 'A:u', x: 22, y: 24 });
  assert.ok(Math.abs(r.likely - 0.4) < 1e-9 && Math.abs(r.focus - 0.4) < 1e-9, 'in reach where the move ends');
  assert.equal(N.riskAfterMove(mine, theirs, pair, { unit: 'A:u', x: 22, y: 8 }).likely, 0);
});
