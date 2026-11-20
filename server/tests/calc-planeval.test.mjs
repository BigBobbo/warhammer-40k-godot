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

test('plan warnings: reserves must arrive more than 8" from enemy units (11e 20.04)', () => {
  // 32 mm bases: edge gap = centre gap - 1.26"
  const enemy = unit('B:y', 22, 40, 1), held = unit('A:x', 22, 5, 1);
  const DS = { flags: { deepStrike: true } };
  const at = (gap) => [
    { name: 'Deploy', A: [held], B: [enemy] }, { name: 'Turn 1', A: [held], B: [enemy] },
    { name: 'Turn 2', A: [held, unit('A:ds', 22, 40 - gap - 1.26, 1, DS)], B: [enemy] },
  ];
  assert.ok(!E.planWarnings(at(8.4), GEO).some(w => w.unit === 'A:ds'), '8.4" away is legal (a Deep Strike unit, anywhere on the battlefield)');
  const w = E.planWarnings(at(7.6), GEO);
  assert.ok(w.some(x => x.unit === 'A:ds' && /more than 8"/.test(x.msg)), JSON.stringify(w));
});

test('plan warnings: reserves by 20.03 / 20.04, and what Deep Strike (24.09) changes', () => {
  const enemy = unit('B:y', 22, 30, 1), held = unit('A:x', 22, 5, 1);
  const arrive = (step, u) => {
    const steps = [{ name: 'Deploy', A: [held], B: [enemy] }];
    for (let r = 1; r <= step; r++) steps.push({ name: `Turn ${r}`, A: r === step ? [held, u] : [held], B: [enemy] });
    return E.planWarnings(steps, GEO).filter(x => x.unit === u.name).map(x => x.msg);
  };
  const DS = { flags: { deepStrike: true } };
  const zB = GEO.zones.B, yB = Math.min(...zB.map(p => p[1])) + 4;      // well inside B's zone, away from the edges in x
  // without Deep Strike: wholly within 6" of a battlefield edge
  assert.deepEqual(arrive(2, unit('A:r', 3, 20, 1)), [], 'on the left edge, round 2: legal');
  assert.match(arrive(2, unit('A:r', 12, 20, 1)).join('|'), /more than 6" from a battlefield edge/);
  assert.deepEqual(arrive(2, unit('A:r', 12, 20, 1, DS)), [], 'the same place with Deep Strike: legal');
  // the enemy deployment zone before round 3
  assert.match(arrive(2, unit('A:r', 3, yB, 1)).join('|'), /enemy deployment zone before round 3/);
  assert.deepEqual(arrive(3, unit('A:r', 3, yB, 1)), [], 'from round 3 it is allowed');
  assert.deepEqual(arrive(2, unit('A:r', 3, yB, 1, DS)), [], 'Deep Strike: "even if that is within your opponent\'s deployment zone"');
  // rounds
  assert.match(arrive(1, unit('A:r', 3, 20, 1)).join('|'), /battle round 1: reserves arrive from the second battle round/);
  assert.match(arrive(4, unit('A:r', 3, 20, 1)).join('|'), /end of round 3 is destroyed/);
});

test('plan warnings at deployment: wholly within the deployment zone, unless Infiltrators (24.20) or a Scout move (24.32)', () => {
  const zA = GEO.zones.A, yEdge = Math.max(...zA.map(p => p[1]));       // A's zone is the top strip
  const zB = GEO.zones.B, yBedge = Math.min(...zB.map(p => p[1]));
  const dep = (u, enemies = []) => E.planWarnings([{ name: 'Deploy', A: [u], B: enemies }], GEO).filter(x => x.unit === u.name);
  assert.deepEqual(dep(unit('A:in', 22, yEdge - 3, 1)), []);
  const out = dep(unit('A:out', 22, yEdge + 5, 1));
  assert.ok(out.length === 1 && out[0].info && /not wholly within its deployment zone/.test(out[0].msg), JSON.stringify(out));
  // Infiltrators: anywhere more than 8" from the enemy zone and enemy units
  const INF = { flags: { infiltrators: true } };
  assert.deepEqual(dep(unit('A:inf', 22, yBedge - 10, 1, INF)), [], '10" from the enemy zone');
  assert.match(dep(unit('A:inf', 22, yBedge - 6, 1, INF))[0].msg, /more than 8" from the enemy deployment zone/);
  assert.match(dep(unit('A:inf', 22, 30, 1, INF), [unit('B:e', 22, 36, 1)])[0].msg, /Infiltrators/, '4.7" from an enemy unit');
  // Scouts 6": up to 6" out of the zone
  const SC = { flags: { scouts: 6 } };
  assert.deepEqual(dep(unit('A:sc', 22, yEdge + 4, 1, SC)), []);
  assert.match(dep(unit('A:sc', 22, yEdge + 9, 1, SC))[0].msg, /more than its 6" Scout move/);
});

test('14.02: the Objective Control of the MODELS within range counts, not the whole unit\'s', () => {
  const o = GEO.objectives[0];                                           // centre of the board, 22 / 30
  // ten OC 2 models in two rows of five, 1" apart; the unit stands so that only its nearest row reaches
  const far = { ...unit('u', 22, 30 - 4.9, 10), oc: 20 };
  far.models = far.models.map(m => ({ ...m, oc: 2 }));
  const inR = far.models.filter(m => Math.hypot(far.x + m.dx - o.x, far.y + m.dy - o.y) - 16 / 25.4 <= B.OBJECTIVE_RANGE).length;
  assert.ok(inR > 0 && inR < 10, `${inR} of 10 models in range`);
  assert.equal(E.ocInRange(far, o, []), 2 * inR, 'only those models');
  assert.equal(E.unitFacts(far, 'A', GEO).objOc.o1, 2 * inR);
  assert.equal(E.unitFacts(far, 'A', GEO).oc, 20, 'the unit total is still reported');
  // models without their own OC (a plan from an older version): the unit's OC by the share in range
  const old = { ...unit('v', 22, 30 - 4.9, 10), oc: 20 };
  assert.ok(Math.abs(E.ocInRange(old, o, []) - 20 * inR / 10) < 1e-9);
  assert.equal(E.ocInRange(unit('w', 22, 10, 5), o, []), 0);
});

test('Outflank: two units on opposite edges, one of them outside your territory (5 VP); one unit on an edge outside it (3 VP)', () => {
  const tA = GEO.territories.A, yIn = Math.min(...tA.map(p => p[1])) + 8, yOut = Math.max(...tA.map(p => p[1])) + 8;
  const f = (x, y) => E.unitFacts(unit(`u${x}-${y}`, x, y, 1), 'A', GEO);
  const left = (y) => f(3, y), right = (y) => f(41, y);
  assert.deepEqual([left(yIn).outsideTerritory, left(yOut).outsideTerritory], [false, true]);
  assert.ok(left(yIn).edges.includes('L'), 'the edge is reported inside the territory too');
  let s = E.sideFacts([left(yIn), right(yOut)]);
  assert.deepEqual([s.flank, s.flankOpposite], [true, true], 'one in the territory, one outside it, on opposite edges: 5 VP (the app gave 3)');
  s = E.sideFacts([left(yIn), right(yIn)]);
  assert.deepEqual([s.flank, s.flankOpposite], [false, false], 'both inside the territory: nothing');
  s = E.sideFacts([left(yOut)]);
  assert.deepEqual([s.flank, s.flankOpposite], [true, false], 'one unit on an edge outside the territory: 3 VP');
  s = E.sideFacts([left(yOut), f(3, yOut + 6)]);
  assert.equal(s.flankOpposite, false, 'the same edge twice is not "opposite"');
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

test('kill pressure: each unit on its best target, a target cannot lose more than all of its wounds', () => {
  const pair = {
    'A:big': { 'B:soft': { sMu: 10, fMu: 2, W: 10 }, 'B:tank': { sMu: 3, fMu: 0, W: 12 } },      // kills soft outright
    'A:med': { 'B:soft': { sMu: 6, fMu: 0, W: 10 }, 'B:tank': { sMu: 6, fMu: 0, W: 12 } },       // soft is taken: goes to the tank (0.5)
    'A:melee': { 'B:soft': { sMu: 0, fMu: 4, W: 10 }, 'B:tank': { sMu: 0, fMu: 3, W: 12 } },     // 0.25 on the tank
    'A:none': {},
  };
  const k = E.killPressure(['A:big', 'A:med', 'A:melee', 'A:none'], ['B:soft', 'B:tank'], pair);
  assert.ok(Math.abs(k.raw - 1.75) < 1e-9, `raw ${k.raw}`);
  assert.ok(Math.abs(k.rate - 1.75 * E.ENGAGE) < 1e-9, `rate ${k.rate}`);
  assert.equal(k.by.find(x => x.key === 'A:med').target, 'B:tank');
  assert.equal(E.killPressure(['A:none'], ['B:soft'], pair).rate, 0.3, 'never below 0.3 units a turn');
});

test('threat options: what a unit can do from where it stands (range, charge reach), best targets first', () => {
  const gun = unit('A:gun', 22, 10, 5, { move: 6, ranges: [24], melee: false, points: 100 });
  const blade = unit('A:blade', 22, 30, 5, { move: 6, ranges: [], melee: true, points: 100 });
  const near = unit('B:near', 22, 34, 5, { points: 100 }), far = unit('B:far', 22, 58, 5, { points: 300 });
  const pr = { shoot: 0.2, fight: 0.5, sMu: 4, sSd: 2, fMu: 8, fSd: 3, W: 10 };
  const pair = { 'A:gun': { 'B:near': pr, 'B:far': pr }, 'A:blade': { 'B:near': pr, 'B:far': pr } };
  const t = E.threatOptions([gun, blade], [near, far], pair);
  const g = t.find(x => x.a === 'A:gun'), b = t.find(x => x.a === 'A:blade');
  // the gun stands still (planned position): 24" reaches "near" (about 23" away), not "far" (about 47")
  assert.deepEqual(g.opts.map(o => o.t), ['B:near']);
  assert.ok(Math.abs(g.opts[0].mu - 4) < 1e-9 && Math.abs(g.opts[0].w - 0.2) < 1e-9, JSON.stringify(g.opts[0]));
  // the blade has no gun: only the charge (2.74" to go: a 3+ on 2D6, 35 in 36 — a double 1 is never
  // enough, 11.02.01) and the fight
  assert.equal(b.opts[0].t, 'B:near');
  const ch = 35 / 36;
  assert.ok(Math.abs(b.opts[0].mu - 8 * ch) < 1e-6 && Math.abs(b.opts[0].w - 0.5 * ch) < 1e-6, JSON.stringify(b.opts[0]));
});

test('forecast board mode with threats: units attack from their planned positions; dead attackers stop, focus fire kills', () => {
  const army = (names) => F.armyProfile(names.map(n => ({ name: n, models: 5, points: 100 })));
  const objs = [{ id: 'o1', cls: 'central', side: null }];
  const f0 = { objs: [], oc: 5, inEnemyDZ: false, inMyDZ: true, inEnemyDZany: false, outsideDZ: false, outsideTerritory: false, quarter: -1, edges: [], centre3: false, centre6: false, whollyNML: false, terrainOutside: false };
  const rounds = {}, threats = {};
  for (let r = 0; r <= 5; r++) rounds[r] = { A: ['a1', 'a2', 'a3'].map(n => ({ name: n, f: f0 })), B: ['b1', 'b2'].map(n => ({ name: n, f: f0 })) };
  // each A unit removes 4 of b1's 10 wounds (SD 1) and never destroys it alone: three together do
  const opt = { t: 'b1', mu: 4, v: 1, w: 0, W: 10 };
  for (let r = 1; r <= 5; r++) threats[r] = { A: { cur: ['a1', 'a2', 'a3'].map(a => ({ a, opts: [opt] })), prev: ['a1', 'a2', 'a3'].map(a => ({ a, opts: [opt] })) }, B: { cur: [], prev: [] } };
  const P = { players: { A: { mission: 'Meatgrinder', army: army(['a1', 'a2', 'a3']), killRate: 0 }, B: { mission: 'Meatgrinder', army: army(['b1', 'b2']), killRate: 0 } }, objectives: objs, plan: {}, trials: 600, first: 'A', boardPlan: { rounds, threats }, model: { swingSd: 0 } };
  const r = F.forecast(P);
  // 12 wounds of damage on a 10-wound unit, SD about 1.7: b1 dies in A's first turn nearly always; b2 is never attacked
  assert.ok(r.B.unitsLeft[0] < 1.2 && r.B.unitsLeft[4] > 0.95, `B units left ${r.B.unitsLeft}`);
  // only two attackers planned: 8 wounds of 10 is not enough most turns
  const two = structuredClone(P);
  for (let q = 1; q <= 5; q++) for (const k of ['cur', 'prev']) two.boardPlan.threats[q].A[k] = two.boardPlan.threats[q].A[k].slice(0, 2);
  const r2 = F.forecast(two);
  assert.ok(r2.B.unitsLeft[0] > 1.7, `two attackers rarely finish it in a turn: ${r2.B.unitsLeft}`);
});

test('where reserves can arrive: 6" from an edge, more than 8" from enemy models, the enemy zone from round 3; Deep Strike anywhere', () => {
  // the defender (B) holds the middle of the bottom edge with one 32 mm model at (22, 57)
  const guard = unit('g', 22, 57, 1);
  const r = INF.r;                                   // 32 mm base: 0.63"
  const z2 = E.arrivalZones([guard], 2);
  assert.deepEqual([z2.round, z2.band, z2.zoneClosed, z2.early, z2.late], [2, 6, true, false, false]);
  assert.equal(z2.blocked.length, 1);
  assert.ok(Math.abs(z2.blocked[0].r - (8 + r)) < 1e-9, 'the 8" starts at the edge of the enemy base');
  const opt = { enemyZone: GEO.zones.B };
  // strategic reserves, round 2: the side edge in the middle of the board is fine
  assert.deepEqual(E.canArrive(3, 30, r, z2), { ok: true });
  // a base that pokes out of the 6" band is not "wholly within"
  assert.match(E.canArrive(5.6, 30, r, z2).why, /wholly within 6" of a battlefield edge/);
  assert.equal(E.canArrive(6 - r, 30, r, z2).ok, true, 'touching the 6" line from inside');
  // the open middle: only with Deep Strike
  assert.match(E.canArrive(22, 30, r, z2).why, /6" of a battlefield edge/);
  assert.deepEqual(E.canArrive(22, 30, r, z2, { deepStrike: true }), { ok: true });
  // more than 8" from the enemy model: 8" exactly is too close
  const at = (d) => E.canArrive(22 + d + 2 * r, 57, r, z2, { deepStrike: true });
  assert.match(at(8).why, /within 8" of an enemy unit/);
  assert.equal(at(8.05).ok, true);
  // the enemy deployment zone (bottom corner, far from the guard): closed before round 3, open from round 3
  const corner = [2, 58];
  assert.ok(B.inPoly(...corner, GEO.zones.B));
  assert.match(E.canArrive(...corner, r, z2, opt).why, /enemy deployment zone before the third battle round/);
  assert.deepEqual(E.canArrive(...corner, r, z2, { ...opt, deepStrike: true }), { ok: true }, '24.09: "even if that is within your opponent’s deployment zone"');
  const z3 = E.arrivalZones([guard], 3);
  assert.equal(z3.zoneClosed, false);
  assert.deepEqual(E.canArrive(...corner, r, z3, opt), { ok: true });
  // round 1: nothing arrives; after round 3 the overlay says the unit would be destroyed
  assert.match(E.canArrive(3, 30, r, E.arrivalZones([guard], 1)).why, /second battle round/);
  assert.equal(E.arrivalZones([guard], 4).late, true);
  // a screen: three models 16" apart leave no 8" gap between them on the back edge
  const screen = [unit('a', 6, 57, 1), unit('b', 22, 57, 1), unit('c', 38, 57, 1)];
  const zs = E.arrivalZones(screen, 3);
  for (let x = r; x <= 44 - r; x += 0.5) assert.equal(E.canArrive(x, 58, r, zs, { deepStrike: true }).ok, false, `x = ${x}`);
  assert.equal(E.arrivalZones([], 2).blocked.length, 0, 'nobody on the board: nothing is blocked');
  assert.equal(E.canArrive(-0.1, 30, r, z2, { deepStrike: true }).why, 'off the battlefield');
});
