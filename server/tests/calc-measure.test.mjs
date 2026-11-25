// Base-to-base measuring (public/calc/measure.mjs) and photo pixel density (photo.localScale).
import { test } from 'node:test';
import assert from 'node:assert/strict';
const M = await import(new URL('../public/calc/measure.mjs', import.meta.url).href);
const P = await import(new URL('../public/calc/photo.mjs', import.meta.url).href);

test('base to base: centre distance minus both radii; points give the centre distance', () => {
  const r = M.baseToBase({ x: 0, y: 0, mm: 32 }, { x: 10, y: 0, mm: 40 });
  assert.equal(r.centre, 10);
  assert.ok(Math.abs(r.edge - (10 - 16 / 25.4 - 20 / 25.4)) < 1e-9);
  assert.ok(Math.abs(r.p[0] - 16 / 25.4) < 1e-9 && Math.abs(r.q[0] - (10 - 20 / 25.4)) < 1e-9);
  assert.equal(M.baseToBase({ x: 0, y: 0, mm: 0 }, { x: 3, y: 4, mm: 0 }).edge, 5);
  assert.equal(M.baseToBase({ x: 0, y: 0, mm: 60 }, { x: 1, y: 0, mm: 60 }).edge, 0, 'overlapping bases: 0');
});

test('photo pixels per inch: a straight-down photo is even; the far side of an angled one is coarser', () => {
  const board = { w: 44, h: 60 };
  const flat = P.homography(P.boardCorners(board), [[0, 0], [880, 0], [880, 1200], [0, 1200]]);
  assert.ok(Math.abs(P.localScale(flat, 22, 30) - 20) < 1e-6);
  // taken from the bottom edge: the top (far) edge is squeezed
  const angled = P.homography(P.boardCorners(board), [[300, 100], [580, 100], [880, 1200], [0, 1200]]);
  assert.ok(P.localScale(angled, 22, 2) < P.localScale(angled, 22, 58) / 2);
});

test('error estimate grows with coarser photos and longer distances', () => {
  const fine = M.measureError({ sA: 30, sB: 30, sCorner: 25, dist: 12 });
  const coarse = M.measureError({ sA: 8, sB: 8, sCorner: 6, dist: 12 });
  const far = M.measureError({ sA: 30, sB: 30, sCorner: 25, dist: 40 });
  assert.ok(fine < 0.2, String(fine));
  assert.ok(coarse > fine && far > fine);
});
