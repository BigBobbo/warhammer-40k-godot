// Combat Calc mission forecast — board plans measured on the 11e map.
// Run: node --test server/tests/calc-planeval.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const E = await import(new URL('../public/calc/planeval.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);
const F = await import(new URL('../public/calc/forecast.mjs', import.meta.url).href);

// Hammer and Anvil: A's zone along the top short edge, B's along the bottom
const dep = B.DEPLOYMENTS.hammer_anvil;
const layout = B.LAYOUTS.find(l => l.deployment === 'hammer_anvil');
const GEO = {
  zones: { A: dep.zones.find(z => z.player === 1).poly, B: dep.zones.find(z => z.player === 2).poly },
  territories: { A: dep.territories.find(t => t.player === 1).poly, B: dep.territories.find(t => t.player === 2).poly },
  pieces: [], objectives: [{ id: 'o1', role: 'central', x: 22, y: 30, host: [] }],
};
const INF = B.footprint({ shape: 'round', diameter: 32 });
const unit = (key, x, y, n = 5, o = {}) => ({ key, name: key, x, y, models: B.formation([{ count: n, fp: INF }]), move: 6, ranges: [24], melee: true, oc: 2 * n, points: 100, ...o });

test('objective range: within 3" + the 20 mm marker of a base edge (open ground)', () => {
  const near = unit('u', 22, 30 - 3.5, 1), far = unit('v', 22, 30 - 5, 1);
  assert.ok(E.inRange(near, GEO.objectives[0], []), '3.5" centre gap = ~2.9" edge gap');
  assert.ok(!E.inRange(far, GEO.objectives[0], []));
});

test('position facts: enemy deployment zone (wholly), territory, quarters, edges, centre', () => {
  const zB = GEO.zones.B, yIn = Math.max(...zB.map(p => p[1])) - 3;
  const deep = E.unitFacts(unit('d', 22, yIn), 'A', GEO);
  assert.equal(deep.inEnemyDZ, true);
  assert.equal(deep.outsideTerritory, true);
  const home = E.unitFacts(unit('h', 22, 3), 'A', GEO);
  assert.equal(home.inEnemyDZ, false);
  assert.equal(home.outsideDZ, false);
  // a unit at the left edge in B's half: flank (outside A's territory), quarter 2 (bottom-left)
  const flank = E.unitFacts(unit('f', 6, 45, 2), 'A', GEO);
  assert.deepEqual(flank.edges, ['L']);
  assert.equal(flank.quarter, 2);
  const mid = E.unitFacts(unit('m', 22, 30, 1), 'A', GEO);
  assert.equal(mid.centre3, true);
  assert.equal(mid.quarter, -1, 'within 6" of the centre counts for no quarter');
});

test('side facts: Behind Enemy Lines count, opposite edges, enemy near the centre', () => {
  const zB = GEO.zones.B, yIn = Math.max(...zB.map(p => p[1])) - 3;
  const mine = [unit('a', 10, yIn), unit('b', 34, yIn), unit('c', 3, 40, 1), unit('d', 41, 40, 1)].map(u => E.unitFacts(u, 'A', GEO));
  const enemy = [unit('x', 22, 33, 1)].map(u => E.unitFacts(u, 'B', GEO));
  const f = E.sideFacts(mine, enemy);
  assert.equal(f.inEnemyDZ, 2);
  assert.equal(f.flankOpposite, true);
  assert.equal(f.enemyCentre6, true);
  assert.equal(E.sideFacts(mine, null).centreKnown, false, 'no enemy plan: centre check falls back to the rating');
});

test('exposure: each enemy unit attacks its best reachable target; out of reach = safe', () => {
  const targets = [unit('A:near', 22, 20), unit('A:far', 22, 2)];
  const attackers = [unit('B:gun', 22, 40, 5, { move: 0, ranges: [24], melee: false })];
  const pair = { 'B:gun': { 'A:near': { shoot: 0.6, fight: 0 }, 'A:far': { shoot: 0.6, fight: 0 } } };
  const e = E.exposure(targets, attackers, pair);
  assert.ok(Math.abs(e['A:near'] - 0.6) < 1e-9);
  assert.equal(e['A:far'], undefined);
});

test('plan warnings: too-long moves and reserves arriving early in the enemy zone', () => {
  const zB = GEO.zones.B, yIn = Math.max(...zB.map(p => p[1])) - 3;
  const steps = [
    { name: 'Deploy', A: [unit('A:x', 22, 5)], B: [unit('B:y', 22, 55)] },
    { name: 'Turn 1', A: [unit('A:x', 22, 35), unit('A:ds', 10, yIn)], B: [unit('B:y', 22, 55)] },
  ];
  const w = E.planWarnings(steps, GEO);
  assert.ok(w.some(x => x.unit === 'A:x' && /moves 30"/.test(x.msg)), JSON.stringify(w));
  assert.ok(w.some(x => x.unit === 'A:ds' && /before round 3/.test(x.msg)), JSON.stringify(w));
});

test('forecast board mode: Behind Enemy Lines and objectives measured from the plan, not rated', () => {
  const army = (names) => F.armyProfile(names.map(n => ({ name: n, models: 5 })));
  const A = army(['a', 'b']), Bp = army(['x']);
  const zB = GEO.zones.B, yIn = Math.max(...zB.map(p => p[1])) - 3;
  const objs = [{ id: 'o1', cls: 'central', side: null }];
  const placedA = [unit('a', 10, yIn), unit('b', 34, yIn)];
  const rounds = {};
  for (let r = 1; r <= 5; r++) rounds[r] = { A: placedA.map(u => ({ name: u.name, f: E.unitFacts(u, 'A', GEO) })), B: null };
  const base = { players: { A: { mission: 'Immovable Object', army: A, killRate: 0, mode: 'tactical', rate: { 'behind-enemy-lines': 0 } }, B: { mission: 'Immovable Object', army: Bp, killRate: 0 } }, objectives: objs, plan: Object.fromEntries([1, 2, 3, 4, 5].map(r => [r, { o1: 'B' }])), trials: 800, first: 'A' };
  const rated = F.forecast(base);
  const board = F.forecast({ ...base, boardPlan: { rounds, pDie: {} } });
  // rated "Never" -> 0; with two units planned wholly in B's zone it scores 5 every time it is active
  assert.equal(rated.A.cards['behind-enemy-lines']?.perDraw ?? 0, 0);
  assert.ok((board.A.cards['behind-enemy-lines']?.perDraw ?? 0) > 4.9, JSON.stringify(board.A.cards['behind-enemy-lines']));
  // the plan holds no unit near the centre and the grid gives it to B: A never scores the central 3 VP
  assert.ok(board.A.prim.every(v => v === 0), JSON.stringify(board.A.prim));
});

test('forecast board mode: exposure kills units, and dead units stop holding objectives', () => {
  const army = (names) => F.armyProfile(names.map(n => ({ name: n, models: 5 })));
  const objs = [{ id: 'o1', cls: 'central', side: null }];
  const holder = unit('h', 22, 30, 1);
  const rounds = {}, pDie = {};
  for (let r = 1; r <= 5; r++) {
    rounds[r] = { A: [{ name: 'h', f: E.unitFacts(holder, 'A', GEO) }], B: [] };
    pDie[r] = { A: { h: r === 2 ? 1 : 0 } }; // certainly destroyed in B's round-2 turn
  }
  const P = { players: { A: { mission: 'Immovable Object', army: army(['h']), killRate: 0 }, B: { mission: 'Immovable Object', army: army(['x']), killRate: 0 } }, objectives: objs, plan: {}, trials: 50, first: 'A', boardPlan: { rounds, pDie }, confidence: { home: 1, other: 1 } };
  const r = F.forecast(P);
  // A holds the centre in round 1 and 2 (its turn comes before B's), then the unit is gone
  assert.deepEqual(r.A.prim.map(Math.round), [3, 8, 0, 0, 0]);
});
