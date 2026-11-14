// Table-photo tracing for the board planner: the four table corners tapped on
// a photo give a perspective transform (homography) from board inches to
// photo pixels; warping the photo through it lays it flat under the map at
// true scale. Pure module (no DOM) so it is unit-tested
// (tests/calc-photo.test.mjs).

/**
 * Homography mapping four source points onto four destination points.
 * src, dst: [[x, y] x 4] -> H as a flat 3x3 array (row-major, h33 = 1).
 */
export function homography(src, dst) {
  // 8 equations, 8 unknowns (h11..h32): Gaussian elimination with pivoting
  const A = [];
  for (let i = 0; i < 4; i++) {
    const [x, y] = src[i], [u, v] = dst[i];
    A.push([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    A.push([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  const n = 8;
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r;
    if (Math.abs(A[p][c]) < 1e-12) throw new Error('corners are degenerate (three in a line?)');
    [A[c], A[p]] = [A[p], A[c]];
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const f = A[r][c] / A[c][c];
      if (f) for (let k = c; k <= n; k++) A[r][k] -= f * A[c][k];
    }
  }
  const h = A.map((row, i) => row[n] / row[i]);
  return [...h, 1];
}

/** Apply H to a point. */
export function applyH(H, x, y) {
  const w = H[6] * x + H[7] * y + H[8];
  return [(H[0] * x + H[1] * y + H[2]) / w, (H[3] * x + H[4] * y + H[5]) / w];
}

/** Signed area (shoelace, y down): > 0 when the points run clockwise on screen. */
export function signedArea(pts) {
  let s = 0;
  for (let i = 0; i < pts.length; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length];
    s += x1 * y2 - x2 * y1;
  }
  return s / 2;
}

/**
 * The tapped corners in board order (top-left, top-right, bottom-right,
 * bottom-left of the map): the first tap is corner 1, the rest go round the
 * table either way (taps made anticlockwise are reversed so the photo is
 * never mirrored); `turn` shifts which tapped corner is the map's top-left.
 */
export function orderCorners(taps, turn = 0) {
  if (taps.length !== 4) throw new Error('need 4 corners');
  let c = taps.map(p => [p[0], p[1]]);
  if (signedArea(c) < 0) c = [c[0], c[3], c[2], c[1]];
  const k = ((turn % 4) + 4) % 4;
  return [...c.slice(k), ...c.slice(0, k)];
}

/** True when no three corners are in a line and the quadrilateral is convex. */
export function cornersUsable(c) {
  if (c.length !== 4) return false;
  let sign = 0;
  for (let i = 0; i < 4; i++) {
    const [ax, ay] = c[i], [bx, by] = c[(i + 1) % 4], [cx, cy] = c[(i + 2) % 4];
    const cr = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
    if (Math.abs(cr) < 1e-6) return false;
    if (sign && Math.sign(cr) !== sign) return false;
    sign = Math.sign(cr);
  }
  return true;
}

/**
 * Warp a photo onto the board: for each output pixel (board inches at
 * `ppi` pixels per inch) sample the photo through H (board -> photo),
 * bilinear. src: { data: RGBA, width, height }. Pixels outside the photo
 * are transparent.
 * -> { data: Uint8ClampedArray, width, height }
 */
export function warpToBoard(src, H, board, ppi) {
  const W = Math.round(board.w * ppi), Ht = Math.round(board.h * ppi);
  const out = new Uint8ClampedArray(W * Ht * 4);
  const { data, width: sw, height: sh } = src;
  for (let j = 0; j < Ht; j++) {
    const by = (j + 0.5) / ppi;
    for (let i = 0; i < W; i++) {
      const bx = (i + 0.5) / ppi;
      const w = H[6] * bx + H[7] * by + H[8];
      const x = (H[0] * bx + H[1] * by + H[2]) / w - 0.5, y = (H[3] * bx + H[4] * by + H[5]) / w - 0.5;
      if (x < -0.5 || y < -0.5 || x > sw - 0.5 || y > sh - 0.5) continue;
      const x0 = Math.max(0, Math.min(sw - 1, Math.floor(x))), y0 = Math.max(0, Math.min(sh - 1, Math.floor(y)));
      const x1 = Math.min(sw - 1, x0 + 1), y1 = Math.min(sh - 1, y0 + 1);
      const fx = Math.max(0, Math.min(1, x - x0)), fy = Math.max(0, Math.min(1, y - y0));
      const o = (j * W + i) * 4;
      const a = (y0 * sw + x0) * 4, b = (y0 * sw + x1) * 4, c = (y1 * sw + x0) * 4, d = (y1 * sw + x1) * 4;
      for (let k = 0; k < 4; k++) {
        out[o + k] = (data[a + k] * (1 - fx) + data[b + k] * fx) * (1 - fy) + (data[c + k] * (1 - fx) + data[d + k] * fx) * fy;
      }
    }
  }
  return { data: out, width: W, height: Ht };
}

/** Board corners in map order (inches). */
export function boardCorners(board) {
  return [[0, 0], [board.w, 0], [board.w, board.h], [0, board.h]];
}
