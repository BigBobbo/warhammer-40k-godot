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
