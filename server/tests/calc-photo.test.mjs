// Combat Calc board planner — table-photo perspective maths.
// Run: node --test server/tests/calc-photo.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const P = await import(new URL('../public/calc/photo.mjs', import.meta.url).href);
const near = (a, b, tol, l) => assert.ok(Math.abs(a - b) <= tol, `${l}: ${a} vs ${b}`);
const BOARD = { w: 44, h: 60 };

// a table photographed from one end: the far edge looks narrower
const PHOTO = [[310, 120], [890, 130], [1150, 860], [60, 850]];

test('homography maps the four board corners onto the tapped photo corners', () => {
  const H = P.homography(P.boardCorners(BOARD), PHOTO);
  for (const [i, [x, y]] of P.boardCorners(BOARD).entries()) {
    const [u, v] = P.applyH(H, x, y);
    near(u, PHOTO[i][0], 1e-6, `corner ${i} x`);
    near(v, PHOTO[i][1], 1e-6, `corner ${i} y`);
  }
  // round trip through the inverse direction
  const Hi = P.homography(PHOTO, P.boardCorners(BOARD));
  const [u, v] = P.applyH(H, 12.5, 40);
  const [x, y] = P.applyH(Hi, u, v);
  near(x, 12.5, 1e-6, 'round trip x');
  near(y, 40, 1e-6, 'round trip y');
});

test('perspective: the board centre is NOT the photo quad centroid (far half looks smaller)', () => {
  const H = P.homography(P.boardCorners(BOARD), PHOTO);
  const [, v] = P.applyH(H, 22, 30);
  const centroidY = PHOTO.reduce((s, p) => s + p[1], 0) / 4;
  assert.ok(v < centroidY, `centre ${v} should sit above the centroid ${centroidY} (further from the camera)`);
});

test('corner order: first tap is corner 1, anticlockwise taps are not mirrored, turn rotates the start', () => {
  const cw = PHOTO;
  const acw = [PHOTO[0], PHOTO[3], PHOTO[2], PHOTO[1]];
  assert.deepEqual(P.orderCorners(cw), cw);
  assert.deepEqual(P.orderCorners(acw), cw);
  assert.deepEqual(P.orderCorners(cw, 2), [cw[2], cw[3], cw[0], cw[1]]);
  assert.ok(P.signedArea(cw) > 0);
  assert.ok(P.cornersUsable(cw));
  assert.ok(!P.cornersUsable([[0, 0], [10, 0], [20, 0], [0, 10]]), 'three in a line');
  assert.ok(!P.cornersUsable([[0, 0], [10, 10], [10, 0], [0, 10]]), 'bow-tie');
});

test('warp: a marker painted at a board position in the photo lands at that board position', () => {
  // synthesise a 1200x900 "photo" of the table: grey, with a red disc where board (10, 15) is and a green one at (34, 50)
  const sw = 1200, sh = 900;
  const data = new Uint8ClampedArray(sw * sh * 4).fill(128);
  const H = P.homography(P.boardCorners(BOARD), PHOTO);
  const paint = (bx, by, rgb) => {
    const [u, v] = P.applyH(H, bx, by);
    for (let y = Math.floor(v - 6); y <= v + 6; y++) for (let x = Math.floor(u - 6); x <= u + 6; x++) {
      const o = (y * sw + x) * 4;
      data[o] = rgb[0]; data[o + 1] = rgb[1]; data[o + 2] = rgb[2]; data[o + 3] = 255;
    }
  };
  for (let i = 3; i < data.length; i += 4) data[i] = 255;
  paint(10, 15, [255, 0, 0]);
  paint(34, 50, [0, 200, 0]);
  const out = P.warpToBoard({ data, width: sw, height: sh }, H, BOARD, 8);
  assert.equal(out.width, 352);
  assert.equal(out.height, 480);
  const px = (bx, by) => { const o = (Math.floor(by * 8) * out.width + Math.floor(bx * 8)) * 4; return [...out.data.slice(o, o + 4)]; };
  const red = px(10, 15), green = px(34, 50), grey = px(22, 30);
  assert.ok(red[0] > 200 && red[1] < 60, `red marker at (10,15): ${red}`);
  assert.ok(green[1] > 150 && green[0] < 60, `green marker at (34,50): ${green}`);
  assert.ok(Math.abs(grey[0] - 128) < 3, `plain table elsewhere: ${grey}`);
});
