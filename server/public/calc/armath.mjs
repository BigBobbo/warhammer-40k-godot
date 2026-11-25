// Live AR on the table (arview.mjs): the maths, pure so it is unit-tested (tests/calc-armath.test.mjs).
//
// Board coordinates are inches, x across the 44" edge, y down the 60" edge, origin at the map's corner 1 (top-left;
// see terrain-11e.mjs). World coordinates are WebXR metres, y up. You tap three table corners in AR: corner 1
// (map top-left), corner 2 (top-right, along the 44" edge) and corner 3 (bottom-right). They pin the board to the
// table; with `fit` the board is stretched to your corners (which also cancels most of ARCore's scale error over
// the table), else it is drawn at true size from corner 1.

export const M_PER_IN = 0.0254;

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const norm = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

/**
 * The board pinned to the table from three tapped corners (world points [x, y, z]).
 * -> { origin, ex, ey, up, sx, sy, edgeIn, sideIn, squareDeg, toWorld(x, y), toBoard(p), model (4x4 column-major,
 *      board inches -> world metres, lifted `lift` metres off the table) }
 * edgeIn / sideIn: the 1-2 and 2-3 distances as AR measured them (true: 44" and 60"); squareDeg: how far the
 * corner at 2 is from a right angle (a check of the taps).
 */
export function registerBoard(p1, p2, p3, { w = 44, h = 60, fit = true, lift = 0.002 } = {}) {
  const up = [0, 1, 0];
  const hgt = (p1[1] + p2[1] + p3[1]) / 3;
  const flat = (p) => [p[0], hgt, p[2]];
  const a = flat(p1), b = flat(p2), c = flat(p3);
  const ex = norm(sub(b, a));
  // across the table: horizontal, at right angles to the 44" edge, toward corner 3
  let ey = norm([-ex[2], 0, ex[0]]);
  if (dot(sub(c, b), ey) < 0) ey = mul(ey, -1);
  const edgeM = len(sub(b, a)), sideM = Math.abs(dot(sub(c, b), ey));
  const edgeIn = edgeM / M_PER_IN, sideIn = sideM / M_PER_IN;
  const sx = fit ? edgeIn / w : 1, sy = fit ? sideIn / h : 1;
  const bc = norm(sub(c, b));
  const squareDeg = Math.abs(90 - (Math.acos(Math.max(-1, Math.min(1, dot(mul(ex, -1), bc)))) * 180) / Math.PI);
  const origin = a;
  const kx = M_PER_IN * sx, ky = M_PER_IN * sy;
  const toWorld = (x, y) => add(add(origin, mul(ex, x * kx)), mul(ey, y * ky));
  const toBoard = (p) => { const d = sub(flat(p), origin); return [dot(d, ex) / kx, dot(d, ey) / ky]; };
  const o = add(origin, mul(up, lift));
  const model = new Float32Array([ex[0] * kx, ex[1] * kx, ex[2] * kx, 0, ey[0] * ky, ey[1] * ky, ey[2] * ky, 0, 0, 1, 0, 0, o[0], o[1], o[2], 1]);
  return { origin, ex, ey, up, sx, sy, edgeIn, sideIn, squareDeg, toWorld, toBoard, model, w, h };
}

/** Triangles of a simple polygon (ear clipping; either winding) -> flat [x, y, x, y, ...] */
export function triangulate(poly) {
  const pts = poly.map(p => [p[0], p[1]]);
  if (pts.length < 3) return [];
  let area = 0;
  for (let i = 0; i < pts.length; i++) { const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length]; area += x1 * y2 - x2 * y1; }
  const idx = pts.map((_, i) => i);
  if (area < 0) idx.reverse();
  const out = [];
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const inside = (p, a, b, c) => cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0;
  let guard = 0;
  while (idx.length > 3 && guard++ < 10000) {
    let cut = false;
    for (let i = 0; i < idx.length; i++) {
      const ia = idx[(i + idx.length - 1) % idx.length], ib = idx[i], ic = idx[(i + 1) % idx.length];
      const a = pts[ia], b = pts[ib], c = pts[ic];
      if (cross(a, b, c) <= 1e-12) continue; // reflex
      if (idx.some(j => j !== ia && j !== ib && j !== ic && inside(pts[j], a, b, c))) continue;
      out.push(...a, ...b, ...c);
      idx.splice(i, 1);
      cut = true;
      break;
    }
    if (!cut) break; // degenerate: give up on the rest
  }
  if (idx.length === 3) out.push(...pts[idx[0]], ...pts[idx[1]], ...pts[idx[2]]);
  return out;
}

/** A thick line (triangles, board inches) along a polyline; closed joins the end to the start. */
export function ribbon(pts, width, closed = false) {
  const out = [], hw = width / 2;
  const n = pts.length, segs = closed ? n : n - 1;
  for (let i = 0; i < segs; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % n];
    const dx = x2 - x1, dy = y2 - y1, l = Math.hypot(dx, dy) || 1, nx = -dy / l * hw, ny = dx / l * hw;
    // a little past each end so corners close
    const ex = dx / l * hw, ey = dy / l * hw;
    const a = [x1 - ex + nx, y1 - ey + ny], b = [x1 - ex - nx, y1 - ey - ny], c = [x2 + ex + nx, y2 + ey + ny], d = [x2 + ex - nx, y2 + ey - ny];
    out.push(...a, ...b, ...c, ...b, ...d, ...c);
  }
  return out;
}

/** Points round an ellipse (rx, ry) at (cx, cy), turned rot degrees. */
export function ellipsePts(cx, cy, rx, ry = rx, rot = 0, n = 40) {
  const t = (rot * Math.PI) / 180, c = Math.cos(t), s = Math.sin(t), out = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2, x = Math.cos(a) * rx, y = Math.sin(a) * ry; out.push([cx + x * c - y * s, cy + x * s + y * c]); }
  return out;
}
/** A filled disc / ellipse as triangles (a fan). */
export function discTris(cx, cy, rx, ry = rx, rot = 0, n = 32) {
  const p = ellipsePts(cx, cy, rx, ry, rot, n), out = [];
  for (let i = 0; i < n; i++) out.push(cx, cy, ...p[i], ...p[(i + 1) % n]);
  return out;
}
