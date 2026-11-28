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
  const adv = swing([unit('B:mob', 22, 45, 10, { melee: false })]); // needs an Advance (it has no melee weapons: no charge)
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
  assert.equal(N.MOVE_MIN_VP, 2, 'over 4x the measured noise of a difference (0.45 VP)');
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

// ---------------------------------------------------------------------------
// 1.152.0: suggestions that follow the turn sequence (one action per unit), and what the turn cards now count

const full = (o = {}) => cell({ shoot: 0.5, fight: 0.5, sMu: 6, sSd: 2, fMu: 6, fSd: 2, ...o });
const pairs = (as, ds, o) => Object.fromEntries(as.map(a => [a, Object.fromEntries(ds.map(d => [d, full(o)]))]));

test('a unit locked in combat cannot make a normal move: it Falls Back onto an objective, and then does not shoot or charge (09.05, 09.07)', () => {
  const mine = [unit('A:eng', 22, 24.5, 1)], theirs = [unit('B:tar', 22, 22.5, 1)];
  assert.equal(N.engagedWith(mine[0], theirs).length, 1, 'bases 0.74" apart: engaged');
  const my = N.myTurn({ me: 'A', mine, theirs, pair: { ...pairs(['A:eng'], ['B:tar']), ...pairs(['B:tar'], ['A:eng']) }, objs: OBJS, geo: GEO, round: 2, hand: [] });
  const u = my.units[0];
  assert.equal(u.job.kind, 'take'); assert.equal(u.job.via, 'fallback'); assert.match(u.job.note, /Fall Back/);
  assert.equal(u.attack, null, 'no attack after a Fall Back');
  assert.equal(my.swing.find(o => o.id === 'c').movers[0].via, 'fallback');
});

test('a unit locked in combat threatens only what it is engaged with', () => {
  const mine = [unit('A:near', 22, 24.5, 1), unit('A:other', 22, 40, 1)], theirs = [unit('B:eng', 22, 22.5, 1)];
  const t = N.turnThreats(mine, theirs, pairs(['B:eng'], ['A:near', 'A:other']));
  assert.equal(t.find(x => x.key === 'A:other').by.length, 0, 'it would have to Fall Back first: no shooting, no charge');
  assert.equal(t.find(x => x.key === 'A:near').by[0].engaged, true);
});

test('a secured objective stays its player\'s with nobody in range; a tie goes to who secured it (14.03)', () => {
  const sw = (mine, theirs, secured) => N.objectiveSwing(mine, theirs, OBJS, [], { me: 'A', secured }).find(x => x.id === 'c');
  assert.equal(sw([], [], {}).holder, null);
  assert.equal(sw([], [], { c: 'A' }).holder, 'me');
  assert.equal(sw([], [], { c: 'A' }).verdict, 'safe', 'nothing of theirs can reach it');
  assert.equal(sw([], [unit('B:far', 22, 40, 1)], { c: 'A' }).verdict, 'lose', 'any OC of theirs is more than none of mine');
  assert.equal(sw([unit('A:two', 22, 30, 2)], [unit('B:two', 22, 40, 2, { melee: false })], { c: 'A' }).verdict, 'safe', '4 against 4: a tie leaves a secured objective with me');
  assert.equal(sw([unit('A:two', 22, 30, 2)], [unit('B:two', 22, 40, 2, { melee: false })], {}).verdict, 'contest');
  assert.equal(sw([], [], { c: 'B' }).verdict, 'theirs');
});

test('my turn: a secured objective nothing can reach frees its holders; a tied objective keeps mine on it', () => {
  const c = (o) => ({ me: 'A', pair: {}, objs: OBJS, geo: GEO, round: 2, hand: [], ...o });
  const free = N.myTurn(c({ mine: [unit('A:h', 22, 30, 2)], theirs: [unit('B:far', 22, 58, 2, { melee: false, ranges: [] })], secured: { c: 'A' } }));
  assert.equal(free.units[0].job.kind, 'none'); assert.equal(free.units[0].job.freed, 'Centre');
  const kept = N.myTurn(c({ mine: [unit('A:h', 22, 30, 2)], theirs: [unit('B:far', 22, 58, 2, { melee: false, ranges: [] })] }));
  assert.equal(kept.units[0].job.kind, 'hold', 'not secured: one unit stays');
  const tie = N.myTurn(c({ mine: [unit('A:h', 22, 28, 1)], theirs: [unit('B:h', 22, 32, 1)] }));
  assert.equal(tie.units[0].job.kind, 'hold'); assert.match(tie.units[0].job.note, /tied/);
});

test('objectives: a charge onto my holders brings their OC (then 3" + 3" onto it); only with a charge is said so', () => {
  const mine = [unit('A:hold', 22, 30, 2)];
  const sw = (theirs) => N.objectiveSwing(mine, theirs, OBJS, [], { me: 'A' }).find(x => x.id === 'c');
  const ch = sw([unit('B:mob', 22, 45, 10)]);
  assert.equal(ch.verdict, 'charge'); assert.equal(ch.movers[0].via, 'charge'); assert.ok(ch.movers[0].p > 0.2 && ch.movers[0].p < 1);
  assert.equal(ch.maxCharge, 20); assert.equal(ch.max, 0);
  assert.equal(sw([unit('B:mob', 22, 45, 10, { melee: false })]).verdict, 'advance', 'no melee weapons: it can only Advance there');
  assert.equal(sw([unit('B:mob', 22, 52, 10)]).verdict, 'safe', 'more than a move and 12" away');
});

test('my turn: one action per unit - a unit on an objective does not charge a target away from it, a free unit does', () => {
  const pr = { ...pairs(['A:h', 'A:free'], ['B:t'], { shoot: 0 , sMu: 0 }), ...pairs(['B:t'], ['A:h', 'A:free']) };
  const my = N.myTurn({ me: 'A', mine: [unit('A:h', 22, 30, 1, { ranges: [] }), unit('A:free', 14, 40, 1, { ranges: [] })], theirs: [unit('B:t', 22, 40, 1)], pair: pr, objs: OBJS, geo: GEO, round: 2, hand: [] });
  const h = my.units.find(u => u.key === 'A:h'), f = my.units.find(u => u.key === 'A:free');
  assert.equal(h.job.kind, 'hold'); assert.equal(h.attack, null, 'the target is 8.7" from the objective: charging it gives the objective up');
  assert.match(f.attack.how, /charge/); assert.ok(f.attack.back > 0, 'what is left of the target fights back');
  // the same target standing next to the objective: the holder can charge it and stay
  const near = N.myTurn({ me: 'A', mine: [unit('A:h', 22, 30, 1, { ranges: [] })], theirs: [unit('B:t', 22, 35.5, 1, { oc: 0 })], pair: pr, objs: OBJS, geo: GEO, round: 2, hand: [] });
  assert.match(near.units[0].attack.how, /charge/);
});

test('shooting counts the weapons that reach, not everything at the longest range', () => {
  const gun = unit('B:gun', 22, 5, 1, { ranges: [12, 48], bands: [{ range: 12, share: 0.8 }, { range: 48, share: 0.2 }], melee: false });
  assert.equal(N.rangeShare(gun, 40), 0.2); assert.equal(N.rangeShare(gun, 10), 1); assert.equal(N.rangeShare(gun, 50), 0);
  const far = N.turnThreats([unit('A:t', 22, 55, 1)], [gun], pairs(['B:gun'], ['A:t'], { sMu: 5, shoot: 0.9 }))[0].by[0];
  assert.ok(Math.abs(far.mu - 1) < 1e-9, `only the 48" gun reaches: a fifth of 5 wounds (${far.mu})`);
  assert.ok(far.p < 0.9, 'and the kill chance is worked out again from those wounds');
  const close = N.turnThreats([unit('A:t', 22, 20, 1)], [gun], pairs(['B:gun'], ['A:t'], { sMu: 5, shoot: 0.9 }))[0].by[0];
  assert.equal(close.mu, 5); assert.equal(close.p, 0.9);
});

test('a target in cover is shot with the in-cover odds (13.08); my own attacks need a sight line', () => {
  const area = { id: 'w', cls: 'area', cat: 'light', poly: [[16, 16], [28, 16], [28, 24], [16, 24]] };
  const t = unit('A:t', 22, 20, 1, { keywords: ['INFANTRY'] });
  assert.equal(N.areaCover(t, [area]), true); assert.equal(N.areaCover({ ...t, keywords: ['VEHICLE'] }, [area]), false);
  const pr = pairs(['B:gun'], ['A:t'], { sMu: 6, shoot: 0.6, sMuC: 4, shootC: 0.3, sSdC: 2 });
  const row = N.turnThreats([t], [unit('B:gun', 22, 40, 1, { melee: false })], pr, { pieces: [area] })[0];
  assert.equal(row.by[0].mu, 4); assert.ok(Math.abs(row.by[0].p - 0.3) < 1e-9); assert.equal(row.by[0].shoot.cover, true);
  // a dense wall between the two: no sight line where it stands or after a move -> not counted for my own attack
  const wall = { id: 'x', cls: 'feature', cat: 'dense', poly: [[0, 29], [44, 29], [44, 31], [0, 31]] };
  const open = N.turnThreats([unit('A:t', 22, 20, 1)], [unit('B:gun', 22, 40, 1, { melee: false })], pr, { pieces: [wall] })[0];
  const strict = N.turnThreats([unit('A:t', 22, 20, 1)], [unit('B:gun', 22, 40, 1, { melee: false })], pr, { pieces: [wall], strictSight: true })[0];
  assert.equal(open.by.length, 1, 'their threats stay the worst case'); assert.equal(strict.by.length, 0);
});

test('half-strength: the wounds that leave a unit at half or less, and the battle-shock roll that follows (08.03, 01.07)', () => {
  assert.equal(N.halfStrength({ left: 5, total: 10 }), true); assert.equal(N.halfStrength({ left: 6, total: 10 }), false); assert.equal(N.halfStrength({ left: 1, total: 1 }), false);
  assert.ok(Math.abs(N.shockFail(7) - 15 / 36) < 1e-9, 'Ld 7+: 2D6 under 7'); assert.equal(N.shockFail(null), 0);
  const row = N.turnThreats([unit('A:ten', 22, 20, 10, { ld: 7 })], [unit('B:gun', 22, 40, 1, { melee: false })], pairs(['B:gun'], ['A:ten'], { sMu: 6, sSd: 2, shoot: 0.02, W: 10 }))[0];
  assert.ok(row.half > 0.6 && row.likely < 0.1, `6 +/- 2 wounds into ten 1-wound models: half-strength likely (${row.half}), destroyed not (${row.likely})`);
  assert.ok(Math.abs(row.shockFail - 15 / 36) < 1e-9);
  // the kill plan gives credit for it on a unit that holds an objective
  const hits = N.turnThreats([unit('B:hold', 22, 30, 10, { ld: 7 }), unit('B:other', 30, 30, 10, { ld: 7, points: 100 })], [unit('A:gun', 26, 12, 1, { melee: false })],
    pairs(['A:gun'], ['B:hold', 'B:other'], { sMu: 6, sSd: 2, shoot: 0.02, W: 10 }));
  assert.equal(N.killPlan(hits, {}, { halfWorth: { 'B:hold': 160 } })[0].key, 'B:hold');
});

test('reserves are counted from battle round 2: guns, a 9+ charge, and an objective they can land on', () => {
  const mine = [unit('A:t', 22, 30, 1)];
  const ds = { key: 'B:ds', name: 'Terminators', oc: 5, ranges: [24], melee: true, deepStrike: true, base: 0.8, points: 200 };
  const edge = { ...ds, key: 'B:edge', name: 'Outriders', deepStrike: false };
  const pr = pairs(['B:ds', 'B:edge'], ['A:t']);
  const by = (r) => N.turnThreats(mine, [], pr, { reserves: [r] })[0].by[0];
  assert.ok(by(ds).reserve && by(ds).shoot && Math.abs(by(ds).charge - 10 / 36) < 1e-9, 'Deep Strike: set up just over 8" away, a 9 to charge');
  assert.equal(by(edge).charge, 0, 'from a battlefield edge the centre is too far to charge');
  assert.ok(by(edge).shoot, 'but 24" guns reach it from within 6" of an edge');
  const r1 = N.nextTurn({ me: 'A', mine, theirs: [], pair: pr, geo: GEO, objs: OBJS, round: 1, theirRound: 1, reserves: { theirs: [ds] } });
  assert.equal(r1.threats[0].by.length, 0, 'not in battle round 1 (20.03)');
  const r2 = N.nextTurn({ me: 'A', mine, theirs: [], pair: pr, geo: GEO, objs: OBJS, round: 2, theirRound: 2, reserves: { theirs: [ds] } });
  assert.equal(r2.threats[0].by.length, 1);
  assert.equal(r2.swing.find(o => o.id === 'e1').verdict, 'reserves', 'an empty objective more than 8" from my units');
  assert.equal(r2.swing.find(o => o.id === 'c').movers.length, 0, 'not the one my unit stands on');
  assert.equal(N.arrivalSpot(OBJS[1], ds, mine, [], { round: 2 }), null); assert.ok(N.arrivalSpot(OBJS[2], ds, mine, [], { round: 3 }));
  assert.equal(N.arrivalSpot(OBJS[2], ds, mine, [], { round: 4 }), null, 'a unit still in reserves after round 3 is destroyed');
});

test('my turn: my reserves arrive on an objective; a free unit screens one their reserves can land on; a unit in a transport is measured from it', () => {
  const ds = { key: 'A:ds', name: 'Wolf Guard', oc: 5, ranges: [24], melee: true, deepStrike: true, base: 0.8, points: 200 };
  const c = { me: 'A', pair: {}, objs: OBJS, geo: GEO, hand: [] };
  const my = N.myTurn({ ...c, round: 2, mine: [unit('A:h', 22, 6, 1)], theirs: [unit('B:h', 22, 54, 1)], reserves: { mine: [ds] } });
  const r = my.units.find(u => u.key === 'A:ds');
  assert.equal(r.reserve, true); assert.equal(r.job.kind, 'arrive'); assert.ok(r.job.obj, 'onto an objective nobody holds');
  assert.equal(N.myTurn({ ...c, round: 1, mine: [unit('A:h', 22, 6, 1)], theirs: [unit('B:h', 22, 54, 1)], reserves: { mine: [ds] } }).units.find(u => u.key === 'A:ds').job.wait, true);
  // their Deep Strike unit can land on an empty objective (one a unit of mine stands on is always within 8" of it):
  // a unit with no OC, too far to stand on it, moves close enough to shut them out
  const their = { ...ds, key: 'B:ds', name: 'Kommandos' };
  const tank = () => unit('A:tank', 18.6, 22, 1, { oc: 0 });
  const sc = N.myTurn({ ...c, round: 2, theirRound: 2, mine: [unit('A:h', 22, 6, 1), tank()], theirs: [unit('B:h', 22, 54, 1)], reserves: { theirs: [their] } });
  assert.equal(sc.danger.find(o => o.id === 'e1').verdict, 'reserves');
  assert.equal(sc.danger.find(o => o.id === 'hA').movers.length, 0, 'not onto the objective my unit holds');
  const f = sc.units.find(u => u.key === 'A:tank');
  assert.equal(f.job.kind, 'screen'); assert.equal(f.job.obj, 'e1'); assert.ok(f.job.dist <= 6 + 1e-9);
  assert.equal(N.arrivalSpot(OBJS[2], their, [{ ...tank(), x: f.job.x, y: f.job.y }], [], { round: 2 }), null, 'from there nothing lands in range');
  assert.ok(sc.warnings.some(w => w.kind === 'rapid-ingress'));
  // a unit inside a transport holds nothing where the transport stands, and reaches further (3" out, then its move)
  const rider = unit('B:in', 22, 38, 5, { embarked: 'Trukk', move: 6 + 3 + 2 });
  const sw = N.objectiveSwing([], [rider], OBJS, [], { me: 'A' }).find(o => o.id === 'c');
  assert.equal(sw.theirs, 0); assert.equal(sw.movers[0].via, 'move'); assert.equal(sw.movers[0].embarked, 'Trukk');
});

test('a kill is worth victory points: what the unit holds, what it can take or score next turn, and its points only for the turns still to come', () => {
  const pr = pairs(['A:gun'], ['B:holder', 'B:big', 'B:runner'], { sMu: 6, shoot: 0.5 });
  const mine = [unit('A:gun', 22, 26, 1, { melee: false, oc: 1 })];
  const theirs = [unit('B:holder', 8, 22, 1, { points: 60 }), unit('B:big', 30, 26, 1, { points: 240, oc: 0 }), unit('B:runner', 22, 48, 1, { points: 60, ranges: [] })];
  const c = { me: 'A', mine, theirs, pair: pr, objs: OBJS, geo: GEO, hand: [] };
  const early = N.myTurn({ ...c, round: 1, theirTurnsLeft: 5 });
  assert.equal(early.kills[0].key, 'B:big', '240 points with the whole game to come');
  const late = N.myTurn({ ...c, round: 5, theirTurnsLeft: 0 });
  assert.equal(late.kills[0].key, 'B:holder', 'the last turn: only the unit on an objective is worth anything');
  assert.deepEqual(late.kills[0].why, ['holds A-side']);
  assert.ok(late.kills[0].value > 10 * (late.kills.find(k => k.key === 'B:big')?.value ?? 0));
  // their card: the only unit that can score it is worth its VP
  const bel = N.myTurn({ ...c, round: 3, theirTurnsLeft: 2, theirHand: ['behind-enemy-lines'], theirs: [unit('B:big', 30, 26, 1, { points: 100, oc: 0 }), unit('B:runner', 22, 17, 1, { points: 100, oc: 0, ranges: [] })] });
  assert.equal(bel.theirCards[0].verdict, 'yes'); assert.deepEqual(bel.theirCards[0].units, ['B:runner']);
  assert.equal(bel.kills[0].key, 'B:runner'); assert.match(bel.kills[0].why[0], /scores their Behind Enemy Lines/);
});

test('my turn: OC is added to an objective they can take next turn; the stratagems they can answer with, by their CP', () => {
  const pr = { ...pairs(['A:h', 'A:free'], ['B:mob']), ...pairs(['B:mob'], ['A:h', 'A:free']) };
  const c = { me: 'A', mine: [unit('A:h', 22, 30, 1), unit('A:free', 22, 23, 2, { melee: true })], theirs: [unit('B:mob', 22, 40, 2)], pair: pr, objs: OBJS, geo: GEO, round: 2, hand: [] };
  const my = N.myTurn(c);
  assert.equal(my.danger.find(o => o.id === 'c').verdict, 'lose', '2 OC of mine against 4 a move away');
  assert.equal(my.units.find(u => u.key === 'A:free').job.kind, 'reinforce'); assert.match(my.units.find(u => u.key === 'A:free').job.note, /they can bring 4 OC/);
  assert.equal(N.myTurn({ ...c, theirTurnsLeft: 0 }).units.find(u => u.key === 'A:free').job.kind, 'none', 'not in the last turn of the battle: they do not move again');
  assert.ok(my.warnings.some(w => w.kind === 'overwatch'), 'CP not known: every core stratagem is named');
  const kinds = (cp) => N.myTurn({ ...c, mine: [unit('A:free', 14, 39, 1)], pair: { ...pr, ...pairs(['A:free'], ['B:mob']) }, cp: { them: cp } }).warnings.map(w => w.kind);
  assert.deepEqual(kinds(0), []); assert.ok(kinds(1).includes('overwatch') || kinds(1).length === 0); assert.ok(!kinds(1).includes('counteroffensive'));
  assert.ok(kinds(2).includes('counteroffensive'), 'a charge or a fight is planned and they have 2 CP');
});

test('their turn: what I can answer with; a unit that holds its fire where it can be Hidden is seen from 15" only', () => {
  const mine = [unit('A:h', 22, 30, 1), unit('A:near', 26, 30, 1)], theirs = [unit('B:mob', 22, 40, 2)];
  const pr = { ...pairs(['A:h', 'A:near'], ['B:mob']), ...pairs(['B:mob'], ['A:h', 'A:near']) };
  const r = N.nextTurn({ me: 'A', mine, theirs, pair: pr, geo: GEO, objs: OBJS, round: 2, cp: { me: 2 } });
  assert.ok(r.answers.some(a => a.kind === 'overwatch') && r.answers.some(a => a.kind === 'heroic') && r.answers.some(a => a.kind === 'counteroffensive'), JSON.stringify(r.answers.map(a => a.kind)));
  assert.deepEqual(N.nextTurn({ me: 'A', mine, theirs, pair: pr, geo: GEO, objs: OBJS, round: 2, cp: { me: 0 } }).answers, []);
  const pieces = [{ id: 'w', cls: 'area', cat: 'light', poly: [[16, 16], [28, 16], [28, 24], [16, 24]] }, { id: 'f', cls: 'feature', cat: 'light', parent: 'w', poly: [[21, 21.5], [23, 21.5], [23, 22], [21, 22]] }];
  const hid = unit('A:hid', 22, 19, 1, { keywords: ['INFANTRY'] }), gun = unit('B:gun', 22, 46, 1, { melee: false });
  const p2 = pairs(['B:gun'], ['A:hid'], { sMuC: 6, shootC: 0.5, sSdC: 2 });
  assert.equal(N.turnThreats([hid], [gun], p2, { pieces })[0].by.length, 1, 'it has guns: it is taken to shoot, so it is seen');
  assert.equal(N.turnThreats([hid], [gun], p2, { pieces, quiet: new Set(['A:hid']) })[0].by.length, 0, '27" away after their move: more than 15"');
  const my = N.myTurn({ me: 'A', mine: [hid], theirs: [gun], pair: { ...p2, ...pairs(['A:hid'], ['B:gun']) }, objs: OBJS, geo: { ...GEO, pieces }, round: 2, hand: [] });
  assert.ok(my.units[0].hide && my.units[0].hide.quiet < my.units[0].hide.loud);
});

test('move candidates: the least exposed place for a unit at risk (on its objective when it holds one), and the place a card is scored from', () => {
  const u = unit('A:h', 22, 30, 1);
  // their gun reaches 30" after its move: the unit stands at 29.7" - one step back and it is out of reach
  const g2 = unit('B:gun', 22, 59, 1, { melee: false, move: 4 });
  const pr = pairs(['B:gun'], ['A:h'], { shoot: 0.6 });
  const sp = N.safeSpot(u, [g2], pr, [], OBJS[1]);
  assert.ok(sp && sp.risk === 0 && sp.here === 0.6 && sp.y < 30, JSON.stringify(sp));
  assert.ok(N.objectiveGap({ ...u, x: sp.x, y: sp.y }, OBJS[1], []) <= 0, 'still in range of the objective it holds');
  const swing = N.objectiveSwing([g2], [u], OBJS, [], { me: 'B' });
  const cands = N.moveCandidates([u], swing, [], { risk: { 'A:h': 0.6 }, theirs: [g2], pair: pr, keep: { 'A:h': OBJS[1] }, cards: [{ unit: 'A:h', name: 'A:h', label: 'Centre Ground', x: 22, y: 28, dist: 2 }] });
  assert.ok(cands.some(x => x.kind === 'safe' && /still on Centre/.test(x.label)) && cands.some(x => x.kind === 'card'));
  assert.equal(N.safeSpot(u, [g2], pairs(['B:gun'], ['A:h'], { shoot: 0.05, sMu: 0.5 }), [], OBJS[1]), null, 'hardly at risk: nothing to gain');
});
