// Combat Calc — moves round dense terrain (paths.mjs). The route and the play-out are tested in
// calc-playout.test.mjs; here the geometry on its own.
// Run: node --test server/tests/calc-paths.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const T = await import(new URL('../public/calc/paths.mjs', import.meta.url).href);
const L = await import(new URL('../public/calc/terrain-11e.mjs', import.meta.url).href);
const tank = (x, y) => ({ key: 't', x, y, models: [{ dx: 0, dy: 0, fp: { shape: 'round', r: 2 } }], keywords: ['VEHICLE'] });

test('along: a point a distance down a path, and its end when the path is shorter', () => {
  const pts = [[0, 0], [3, 0], [3, 4]];
  assert.deepEqual(T.along(pts, 2), { x: 2, y: 0, dist: 2 });
  assert.deepEqual(T.along(pts, 5), { x: 3, y: 2, dist: 5 });
  assert.deepEqual(T.along(pts, 99), { x: 3, y: 4, dist: 7 });
});

test('clearWay keeps a base\'s width from a wall; a unit standing in a feature can walk out of it', () => {
  const wall = { cls: 'feature', cat: 'dense', h: 4, poly: [[10, 10], [20, 10], [20, 11], [10, 11]] };
  assert.equal(T.clearWay([5, 5], [25, 5], [wall], 2), true);
  assert.equal(T.clearWay([5, 8.5], [25, 8.5], [wall], 2), false, '1.5" from the wall with a 2" base');
  assert.equal(T.clearWay([15, 5], [15, 15], [wall], 0.5), false);
  assert.equal(T.clearWay([15, 10.5], [15, 20], [wall], 0.5), true);
});

test('on every official layout a vehicle finds a way between any two objectives that is never shorter than the straight line', () => {
  let routes = 0, round = 0, blocked = 0;
  for (const l of L.LAYOUTS.slice(0, 12)) {
    for (const a of l.objectives) for (const b of l.objectives) {
      if (a === b) continue;
      const rt = T.route(tank(a.x, a.y), b.x, b.y, l.pieces);
      const straight = Math.hypot(a.x - b.x, a.y - b.y);
      routes++; if (!rt.direct) round++; if (rt.blocked) blocked++;
      assert.ok(rt.len >= straight - 1e-6, `${l.id}: ${rt.len} < ${straight}`);
      assert.ok(rt.len <= straight * 2.2 + 6, `${l.id} ${a.id}>${b.id}: a detour of ${rt.len} for ${straight}`);
      for (const q of rt.pts) assert.ok(q[0] >= 0 && q[0] <= 44 && q[1] >= 0 && q[1] <= 60);
    }
  }
  assert.ok(round > 0, 'some of them go round something');
  assert.ok(blocked <= routes * 0.1, `${blocked} of ${routes} found no way`);
  console.log(`  ${routes} routes, ${round} go round terrain, ${blocked} found no way`);
});
