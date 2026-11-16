// Combat Calc board planner — geometry and mission / layout lookup.
// Run: node --test server/tests/calc-board.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);
const near = (a, b, tol, l) => assert.ok(Math.abs(a - b) <= tol, `${l}: ${a} vs ${b}`);

test('bundle: 45 official layouts = 15 disposition pairs x 3 variants, each with terrain, objectives and a deployment', () => {
  assert.equal(B.LAYOUTS.length, 45);
  const pairs = new Set(B.LAYOUTS.map(l => l.matchup));
  assert.equal(pairs.size, 15);
  for (const l of B.LAYOUTS) {
    assert.ok(l.pieces.length > 10, l.id);
    assert.ok(l.objectives.length >= 4, l.id);
    assert.ok(B.DEPLOYMENTS[l.deployment], `${l.id}: deployment ${l.deployment}`);
    for (const p of l.pieces) for (const [x, y] of p.poly) assert.ok(x >= -0.5 && x <= 44.5 && y >= -0.5 && y <= 60.5, `${l.id} ${p.id} on the board`);
  }
});

test('layouts and missions by Force Disposition (either order; missions are per player)', () => {
  const tah = B.layoutsFor('take-and-hold', 'take-and-hold');
  assert.deepEqual(tah.map(l => l.variant), [1, 2, 3]);
  assert.deepEqual(B.layoutsFor('disruption', 'take-and-hold').map(l => l.id), B.layoutsFor('take-and-hold', 'disruption').map(l => l.id));
  assert.deepEqual(B.missionsFor('take-and-hold', 'disruption'), { A: 'Determined Acquisition', B: 'Death Trap' });
  assert.deepEqual(B.missionsFor('take-and-hold', 'take-and-hold'), { A: 'Battlefield Dominance', B: 'Battlefield Dominance' });
});

test('footprints: round / oval from base mm, approximate hull rectangles', () => {
  near(B.footprint({ shape: 'round', diameter: 32 }).r, 32 / 25.4 / 2, 1e-9, '32mm');
  const ov = B.footprint({ shape: 'oval', width: 90, length: 52 });
  near(ov.rx, 90 / 25.4 / 2, 1e-9, 'oval long axis');
  near(ov.ry, 52 / 25.4 / 2, 1e-9, 'oval short axis');
  const hull = B.footprint({ shape: 'hull', draft: true }, ['VEHICLE']);
  assert.equal(hull.shape, 'rect');
  assert.equal(hull.approx, true);
  near(B.edgeRadius(ov, 1, 0), ov.rx, 1e-9, 'oval edge along x');
  near(B.edgeRadius(ov, 0, 1), ov.ry, 1e-9, 'oval edge along y');
});

test('formation: rows of 5, 1" apart edge to edge (inside coherency), leader in the front row', () => {
  const fp = B.footprint({ shape: 'round', diameter: 32 });
  const f = B.formation([{ count: 10, fp, label: 'Boy' }, { count: 1, fp: B.footprint({ shape: 'round', diameter: 50 }), label: 'Boss', leader: true }]);
  assert.equal(f.length, 11);
  const rows = new Set(f.map(m => m.dy.toFixed(3)));
  assert.equal(rows.size, 3);
  assert.ok(f.slice(0, 5).some(m => m.leader), 'leader in the first row');
  // neighbours in a row: 1" gap between bases
  const r2 = f.filter(m => !m.leader).filter(m => m.dy.toFixed(3) === [...rows][1]).sort((a, b) => a.dx - b.dx);
  near(r2[1].dx - r2[0].dx - 2 * fp.r, 1, 1e-9, 'gap');
});

test('unitGap: closest base-to-base distance, 0 when touching', () => {
  const fp = B.footprint({ shape: 'round', diameter: 25.4 }); // r = 0.5"
  const one = [{ dx: 0, dy: 0, fp }];
  near(B.unitGap({ x: 0, y: 0, models: one }, { x: 3, y: 4, models: one }), 4, 1e-9, '5" centres - 2 x 0.5"');
  assert.equal(B.unitGap({ x: 0, y: 0, models: one }, { x: 0.8, y: 0, models: one }), 0);
  near(B.pointGap({ x: 0, y: 0, models: one }, 10, 0), 9.5, 1e-9, 'to a point');
});

test('objective range: 3" + the 20 mm marker radius', () => {
  near(B.OBJECTIVE_RANGE, 3.787, 0.001, 'open ground');
  assert.equal(B.ENGAGEMENT_RANGE, 2);
});

test('rotation: formation offsets and oval bases turn with the unit', () => {
  const fp = B.footprint({ shape: 'oval', width: 90, length: 52 }); // rx 1.77", ry 1.02"
  const f = B.formation([{ count: 3, fp, label: 'Bike' }]);           // one row along x
  const r = B.rotateFormation(f, 90);                                   // now a column along y
  assert.ok(Math.max(...r.map(m => Math.abs(m.dx))) < 1e-9, 'all on x = 0 after 90°');
  near(Math.max(...r.map(m => m.dy)), Math.max(...f.map(m => m.dx)), 1e-9, 'spread along y');
  // a turned oval's long axis now points along y
  near(B.edgeRadius(fp, 0, 1, 90), fp.rx, 1e-9, 'long axis vertical');
  near(B.edgeRadius(fp, 1, 0, 90), fp.ry, 1e-9, 'short axis horizontal');
  // gap between one bike and a point to its right: short side after turning
  const one = B.rotateFormation([{ dx: 0, dy: 0, fp }], 90);
  near(B.pointGap({ x: 0, y: 0, models: one }, 5, 0), 5 - fp.ry, 1e-9, 'gap uses the turned base');
});

test('11e only: Crucible of Battle zones are the official 40kdc 11e geometry (not the legacy "stepped" file)', () => {
  const z = B.DEPLOYMENTS.crucible_of_battle.zones;
  assert.deepEqual(z.find(q => q.player === 1).poly, [[44, 0], [0, 30], [0, 0]]);
  assert.deepEqual(z.find(q => q.player === 2).poly, [[0, 60], [44, 30], [44, 60]]);
});

test('11e only: objective counts match the official cards (21 layouts with 5, 24 with 6 = two central objectives)', () => {
  const counts = {};
  for (const l of B.LAYOUTS) counts[l.objectives.length] = (counts[l.objectives.length] ?? 0) + 1;
  assert.deepEqual(counts, { 5: 21, 6: 24 });
  for (const l of B.LAYOUTS) {
    const roles = l.objectives.map(o => o.role).sort().join(',');
    assert.ok(roles === 'central,expansion,expansion,home,home' || roles === 'central,central,expansion,expansion,home,home', `${l.id}: ${roles}`);
    // every home objective sits in its own deployment zone
    for (const o of l.objectives.filter(x => x.role === 'home')) {
      const zone = B.DEPLOYMENTS[l.deployment].zones.find(z => z.player === (o.zone === 'player1' ? 1 : 2));
      assert.ok(B.inPoly(o.x, o.y, zone.poly), `${l.id} ${o.id}`);
    }
  }
});
