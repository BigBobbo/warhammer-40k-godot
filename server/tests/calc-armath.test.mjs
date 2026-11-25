// Live AR maths (public/calc/armath.mjs): pinning the board to three tapped corners, and the shapes drawn on it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const A = await import(new URL('../public/calc/armath.mjs', import.meta.url).href);
const m = A.M_PER_IN;
const close = (a, b, e = 1e-6) => Math.abs(a - b) < e;

test('three corners of a table seen at an angle: the board maps onto them, and back', () => {
  // a 44" x 60" table, turned 30° and 0.75 m below the camera's origin
  const t = Math.PI / 6, ex = [Math.cos(t), 0, Math.sin(t)], ey = [-Math.sin(t), 0, Math.cos(t)], o = [0.2, -0.75, -1.1];
  const W = (x, y) => [o[0] + ex[0] * x * m + ey[0] * y * m, o[1], o[2] + ex[2] * x * m + ey[2] * y * m];
  const r = A.registerBoard(W(0, 0), W(44, 0), W(44, 60));
  assert.ok(close(r.edgeIn, 44, 1e-6) && close(r.sideIn, 60, 1e-6) && r.squareDeg < 1e-4);
  const p = r.toWorld(12, 20), q = W(12, 20);
  assert.ok(close(p[0], q[0]) && close(p[2], q[2]));
  const [bx, by] = r.toBoard(W(30.5, 41.25));
  assert.ok(close(bx, 30.5, 1e-6) && close(by, 41.25, 1e-6), `${bx},${by}`);
  // model matrix: board (x, y) -> world, as toWorld (plus the lift)
  const M = r.model, x = 12, y = 20;
  const w = [M[0] * x + M[4] * y + M[12], M[1] * x + M[5] * y + M[13], M[2] * x + M[6] * y + M[14]];
  assert.ok(close(w[0], q[0]) && close(w[2], q[2]) && close(w[1], q[1] + 0.002));
});

test('fit: AR that reads the table 3% long is stretched back onto the corners; true size is not', () => {
  const W = (x, y) => [x * m * 1.03, 0, y * m * 1.03];
  const fit = A.registerBoard(W(0, 0), W(44, 0), W(44, 60));
  assert.ok(close(fit.edgeIn, 44 * 1.03, 1e-6) && close(fit.sx, 1.03, 1e-9));
  const far = fit.toWorld(44, 60);
  assert.ok(close(far[0], W(44, 60)[0]) && close(far[2], W(44, 60)[2]), 'the far corner lands on the tapped corner');
  const tru = A.registerBoard(W(0, 0), W(44, 0), W(44, 60), { fit: false });
  assert.ok(tru.toWorld(44, 60)[0] < W(44, 60)[0]);
  const [bx] = fit.toBoard(W(22, 0));
  assert.ok(close(bx, 22, 1e-6), 'distances read in board inches after the fit');
});

test('corner 3 on the other side: the board is not mirrored', () => {
  const W = (x, y) => [x * m, 0, -y * m]; // the table runs away along -z
  const r = A.registerBoard(W(0, 0), W(44, 0), W(44, 60));
  const [, by] = r.toBoard(W(10, 30));
  assert.ok(close(by, 30, 1e-6), String(by));
});

test('shapes: triangulate an L-shaped zone (area kept), ribbon and disc triangle counts', () => {
  const L = [[0, 0], [44, 0], [44, 12], [22, 12], [22, 20], [0, 20]];
  const t = A.triangulate(L);
  let area = 0;
  for (let i = 0; i < t.length; i += 6) area += Math.abs((t[i + 2] - t[i]) * (t[i + 5] - t[i + 1]) - (t[i + 4] - t[i]) * (t[i + 3] - t[i + 1])) / 2;
  assert.ok(close(area, 44 * 12 + 22 * 8, 1e-6), String(area));
  assert.equal(A.triangulate([...L].reverse()).length, t.length, 'either winding');
  assert.equal(A.ribbon([[0, 0], [10, 0], [10, 10]], 0.2).length, 2 * 6 * 2);
  assert.equal(A.ribbon([[0, 0], [10, 0], [10, 10]], 0.2, true).length, 3 * 6 * 2);
  assert.equal(A.discTris(0, 0, 1, 1, 0, 32).length, 32 * 6);
});
