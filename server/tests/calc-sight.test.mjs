// Combat Calc board planner — 11e line of sight, cover and next-turn threat.
// Run: node --test server/tests/calc-sight.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const S = await import(new URL('../public/calc/sight.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);

const rect = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
const INF32 = B.footprint({ shape: 'round', diameter: 32 });
// a unit of n 32 mm models in a row, centred on (x, y)
const unit = (x, y, n = 1, keywords = ['INFANTRY']) => ({ x, y, keywords, models: B.formation([{ count: n, fp: INF32 }], { perRow: 5 }) });

// a dense ruin AREA (10..16 x 20..30) with a solid dense wall FEATURE inside it, and a light area elsewhere
const PIECES = [
  { id: 'ruin', cls: 'area', cat: 'dense', poly: rect(10, 20, 16, 30) },
  { id: 'wall', cls: 'feature', cat: 'dense', parent: 'ruin', poly: rect(12.8, 21, 13.2, 29) },
  { id: 'crater', cls: 'area', cat: 'exposed', poly: rect(30, 20, 36, 30) },
  { id: 'woods', cls: 'area', cat: 'light', poly: rect(20, 40, 26, 46) },
];

test('open ground: clear, no cover', () => {
  const v = S.sightVerdict(unit(5, 5, 5), unit(35, 5, 5), PIECES);
  assert.equal(v.verdict, 'clear');
  assert.equal(v.targetSeen, 5);
  assert.equal(v.cover, false);
  assert.equal(v.borderline, false);
});

test('13.10: a dense area between the units blocks sight', () => {
  const v = S.sightVerdict(unit(5, 25), unit(22, 25), PIECES);
  assert.equal(v.verdict, 'blocked');
});

test('13.10: the area does not block a model that is within it (exclusion) — but its Solid wall still does (13.11)', () => {
  // target inside the ruin, on the near side of the wall: visible, and in cover (INFANTRY within an area)
  const near = S.sightVerdict(unit(5, 25), unit(11.5, 25), PIECES);
  assert.equal(near.verdict, 'clear');
  assert.equal(near.cover, true);
  assert.equal(near.coverWhy, 'in a terrain area');
  // target inside the ruin behind the wall: the Solid feature blocks
  const behind = S.sightVerdict(unit(5, 25), unit(14.8, 25), PIECES);
  assert.equal(behind.verdict, 'blocked');
});

test('exposed areas never block sight; cover only for INFANTRY / BEASTS / SWARM within one', () => {
  const inf = S.unitSight(unit(22, 25), unit(33, 25), PIECES);
  assert.equal(S.sightClass(inf), 'clear');
  assert.equal(inf.cover, true);
  const tank = S.unitSight(unit(22, 25), unit(33, 25, 1, ['VEHICLE']), PIECES);
  assert.equal(tank.cover, false);
});

test('13.08: a target only partly visible (not fully visible) has cover even in the open', () => {
  // target just past the ruin's corner: some sight lines clip the area, some do not
  const v = S.unitSight(unit(5, 31), unit(22, 29.6, 1, ['VEHICLE']), PIECES);
  assert.equal(S.sightClass(v), 'clear');
  assert.equal(v.cover, true);
  assert.equal(v.coverWhy, 'not fully visible');
});

test('borderline: a sight line skimming an area corner is flagged "check on the table"', () => {
  const v = S.sightVerdict(unit(5, 31), unit(22, 30.6, 1, ['VEHICLE']), PIECES);
  assert.equal(v.borderline, true);
});

test('13.09: infantry in an area with a dense feature can be Hidden beyond 15"', () => {
  const far = S.unitSight(unit(40, 25), unit(11.5, 25), PIECES);
  assert.equal(far.hidden, true);
  const close = S.unitSight(unit(5, 25), unit(11.5, 25), PIECES);
  assert.equal(close.hidden, false);
});

test('range: only attacker models within range count', () => {
  const att = { ...unit(5, 5, 10), x: 5 };
  const s = S.unitSight(att, unit(30, 5), PIECES, { range: 20 });
  assert.ok(s.attackersSeeing > 0 && s.attackersSeeing < 10, `${s.attackersSeeing} of 10 in range`);
});

test('threat next turn: shooting envelope and charge odds after a normal move', () => {
  const enemy = unit(20, 5), me = unit(20, 25);
  const gap = 20 - 32 / 25.4; // centre gap minus two 16 mm radii
  const t = S.threatTo(enemy, me, { move: 6, ranges: [12, 18], melee: true });
  assert.ok(Math.abs(t.gap - gap) < 1e-9);
  assert.ok(t.shoot && Math.abs(t.shoot.margin - (24 - gap)) < 1e-9, 'M6 + 18" reaches');
  // 11.04: the roll must be at least what is left after the move. 18.74" - 6" = 12.74": more than 12", no charge
  assert.equal(t.charge, null, String(t.charge));
  // with an 8" move 10.74" are left: an 11 on 2D6 = 3/36 (the old "gap - 2" rule gave a 9: 28%)
  const t8 = S.threatTo(enemy, me, { move: 8, ranges: [], melee: true });
  assert.ok(Math.abs(t8.charge - 3 / 36) < 1e-12, String(t8.charge));
  // a normal move cannot end engaged: more than 2" are always left, so at least a 3 is needed
  const close = S.threatTo(unit(20, 5), unit(20, 5 + 32 / 25.4 + 4), { move: 10, ranges: [], melee: true });
  assert.ok(Math.abs(close.gap - 4) < 1e-9 && Math.abs(close.charge - 35 / 36) < 1e-12 && !close.engaged, JSON.stringify(close));
  // already engaged: no charge needed
  const eng = S.threatTo(unit(20, 5), unit(20, 5 + 32 / 25.4 + 1.5), { move: 6, ranges: [], melee: true });
  assert.ok(eng.engaged && eng.charge === 1, JSON.stringify(eng));
  assert.equal(S.threatTo(enemy, me, { move: 6, ranges: [12] }).shoot, null, '6 + 12 = 18 < gap');
  assert.equal(S.p2d6(7), 21 / 36);
  assert.equal(S.chargeReach(6, 0.8), 6 + 5, '2D6 >= 5 is 83%: targets up to 5" from where the move ends');
  assert.equal(S.chargeReach(6, 0.4), 6 + 8, '2D6 >= 8 is 42%');
});

test('performance: 10 vs 20 models across a real GW layout in well under a second', () => {
  const l = B.LAYOUTS[0];
  const t0 = Date.now();
  const v = S.sightVerdict(unit(10, 8, 10), unit(30, 50, 20), l.pieces);
  const ms = Date.now() - t0;
  assert.ok(['clear', 'partial', 'blocked'].includes(v.verdict));
  assert.ok(ms < 1500, `${ms} ms`);
});

// ---- round 3 fixes (1.101): Hidden in light terrain, gone to ground, detection range in threats

test('13.09 with its errata: an area with a LIGHT feature hides infantry too; 13.11.01 gone to ground is 12"', () => {
  const pieces = [
    { id: 'wood', cls: 'area', cat: 'light', poly: rect(20, 20, 26, 30) },
    { id: 'trees', cls: 'feature', cat: 'light', parent: 'wood', poly: rect(22, 22, 23, 28) },
    { id: 'bare', cls: 'area', cat: 'light', poly: rect(30, 40, 36, 50) },        // an area with no feature
  ];
  const inWood = unit(21, 25);
  assert.equal(S.canHide(inWood, pieces), true, 'infantry in an area that holds a light feature');
  assert.equal(S.canHide(unit(33, 45), pieces), false, 'an area without a light or dense feature does not hide');
  assert.equal(S.canHide(unit(5, 5), pieces), false, 'open ground');
  assert.equal(S.canHide(unit(21, 25, 1, ['VEHICLE']), pieces), false, 'only INFANTRY / BEASTS / SWARM');
  const far = S.unitSight(unit(21, 5), inWood, pieces), near = S.unitSight(unit(21, 12), inWood, pieces);
  assert.deepEqual([far.hiddenCapable, far.hidden, far.detect], [true, true, 15], `${far.nearest.toFixed(1)}" away`);
  assert.deepEqual([near.hidden, near.detect], [false, 15], `${near.nearest.toFixed(1)}" away: inside the detection range`);
  // the dense ruin of PIECES: behind its wall the unit is not fully visible -> gone to ground, 3" less
  const behind = S.unitSight(unit(5, 25), unit(14.5, 25), PIECES);
  assert.deepEqual([behind.hiddenCapable, behind.goneToGround, behind.detect], [true, true, 12]);
});

test('a unit that can only be seen from close by must be approached: detection range in the threat', () => {
  const enemy = unit(20, 5), me = unit(20, 35);            // 28.7" apart
  const open = S.threatTo(enemy, me, { move: 6, ranges: [36] });
  assert.ok(open.shoot && !open.unseen, 'a 36" gun reaches after a 6" move');
  const hidden = S.threatTo(enemy, me, { move: 6, ranges: [36], detect: S.HIDDEN_RANGE });
  assert.deepEqual([hidden.shoot, hidden.unseen], [null, true], 'in range, but 6" + 15" does not bring it within the detection range');
  const close = S.threatTo(unit(20, 16), me, { move: 6, ranges: [36], detect: S.HIDDEN_RANGE });
  assert.ok(close.shoot && Math.abs(close.shoot.margin - (6 + 15 - close.gap)) < 1e-9, 'it can move to within 15"');
  assert.equal(S.threatTo(enemy, me, { move: 6, ranges: [36], detect: S.LONE_OPERATIVE }).shoot, null, 'a Lone Operative: 12"');
});
