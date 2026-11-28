// Moves around terrain. Core rules 13.06: every model moves through exposed and light terrain; through DENSE
// terrain only INFANTRY, BEASTS, SWARM and MOBILE models do (and a unit that can FLY, 21.03). Any other model -
// a VEHICLE, a MONSTER, bikes and cavalry - goes round a dense terrain feature more than 2" high.
//
// The turn cards measured a move as a straight line. For a unit that has to go round, this finds the shortest
// way: a straight line where one is clear, else from corner to corner of the features in the way (a visibility
// graph over the corners, pushed out by the unit's largest base). Climbing is not modelled: a wall is gone round.
// Pure module (no DOM), unit-tested (tests/calc-paths.test.mjs).

const THROUGH = /^(INFANTRY|BEASTS?|SWARM|MOBILE|FLY)$/i;
const extent = (fp) => fp?.r ?? Math.max(fp?.rx ?? 0, fp?.hw ?? 0, fp?.ry ?? 0, fp?.hh ?? 0);

/** Does this unit have to go round dense terrain? (keywords: the datasheet's; none known = it does not) */
export function goesRound(u) {
  const kw = u.keywords ?? [];
  return kw.length > 0 && !kw.some(k => THROUGH.test(String(k).trim()));
}
/** The terrain features a model that cannot pass dense terrain has to go round: dense, not an area, over 2" high. */
export function walls(pieces) {
  return (pieces ?? []).filter(p => p.cls !== 'area' && p.cat === 'dense' && (p.h ?? 0) > 2 && (p.poly?.length ?? 0) >= 3);
}
/** The radius a unit needs clear to either side of its path: its largest base. */
export const clearance = (u) => Math.max(0.5, ...(u.models ?? []).map(m => extent(m.fp)));

function segSegDist(ax, ay, bx, by, cx, cy, dx, dy) {
  const cross = (x1, y1, x2, y2) => x1 * y2 - y1 * x2;
  const d1 = cross(dx - cx, dy - cy, ax - cx, ay - cy), d2 = cross(dx - cx, dy - cy, bx - cx, by - cy);
  const d3 = cross(bx - ax, by - ay, cx - ax, cy - ay), d4 = cross(bx - ax, by - ay, dx - ax, dy - ay);
  if (((d1 > 0) !== (d2 > 0)) && ((d3 > 0) !== (d4 > 0))) return 0;
  const pt = (px, py, qx, qy, rx, ry) => {
    const vx = rx - qx, vy = ry - qy, l2 = vx * vx + vy * vy;
    const t = l2 > 0 ? Math.max(0, Math.min(1, ((px - qx) * vx + (py - qy) * vy) / l2)) : 0;
    return Math.hypot(px - qx - t * vx, py - qy - t * vy);
  };
  return Math.min(pt(ax, ay, cx, cy, dx, dy), pt(bx, by, cx, cy, dx, dy), pt(cx, cy, ax, ay, bx, by), pt(dx, dy, ax, ay, bx, by));
}
function inPoly(px, py, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
/** Is the way from a to b clear of these features by `r` to either side? (a path that starts inside a feature may leave it) */
export function clearWay(a, b, feats, r) {
  for (const p of feats) {
    const poly = p.poly;
    if (inPoly(a[0], a[1], poly)) continue;      // standing in it already: it can walk out
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      if (segSegDist(a[0], a[1], b[0], b[1], poly[j][0], poly[j][1], poly[i][0], poly[i][1]) < r - 1e-6) return false;
    }
  }
  return true;
}
/** The corners to steer by: each corner of each feature pushed out from the feature by `r` and a little more. */
function waypoints(feats, r) {
  const out = [];
  for (const p of feats) {
    const poly = p.poly, n = poly.length;
    const cx = poly.reduce((a, q) => a + q[0], 0) / n, cy = poly.reduce((a, q) => a + q[1], 0) / n;
    for (let i = 0; i < n; i++) {
      const [x, y] = poly[i], [px, py] = poly[(i + n - 1) % n], [nx, ny] = poly[(i + 1) % n];
      // away from both edges that meet here (the bisector, pointing out of the feature)
      const e1 = Math.hypot(x - px, y - py) || 1, e2 = Math.hypot(x - nx, y - ny) || 1;
      let bx = (x - px) / e1 + (x - nx) / e2, by = (y - py) / e1 + (y - ny) / e2;
      const bl = Math.hypot(bx, by);
      if (bl < 1e-6) { bx = x - cx; by = y - cy; }
      const l = Math.hypot(bx, by) || 1, push = (r + 0.3) * Math.SQRT2;
      const wx = x + bx / l * push, wy = y + by / l * push;
      if (!inPoly(wx, wy, poly)) out.push([wx, wy]);
    }
  }
  return out;
}

/**
 * The way from where a unit stands to (tx, ty), its centre along the path.
 * -> { pts: [[x, y], ...] (from the unit to the target), len, direct (a straight line), blocked (no way was found:
 *      pts is the straight line and len its length, so the caller can still use it) }
 */
export function route(u, tx, ty, pieces, { w = 44, h = 60 } = {}) {
  const a = [u.x, u.y], b = [tx, ty], straight = { pts: [a, b], len: Math.hypot(tx - u.x, ty - u.y), direct: true, blocked: false };
  if (!goesRound(u)) return straight;
  const feats = walls(pieces);
  if (!feats.length) return straight;
  const r = clearance(u);
  if (legClear(a, b, feats, r, true, true)) return straight;
  // only the features near the corridor matter (a detour is rarely wider than this)
  const near = feats.filter(p => p.poly.some(q => segSegDist(a[0], a[1], b[0], b[1], q[0], q[1], q[0], q[1]) < straight.len * 0.75 + 8));
  const nodes = [a, ...waypoints(near, r).filter(q => q[0] >= r && q[1] >= r && q[0] <= w - r && q[1] <= h - r), b];
  const n = nodes.length, goal = n - 1;
  const dist = new Array(n).fill(Infinity), prev = new Array(n).fill(-1), done = new Array(n).fill(false);
  dist[0] = 0;
  for (;;) {
    let k = -1;
    for (let i = 0; i < n; i++) if (!done[i] && dist[i] < Infinity && (k < 0 || dist[i] < dist[k])) k = i;
    if (k < 0 || k === goal) break;
    done[k] = true;
    for (let j = 1; j < n; j++) {
      if (done[j]) continue;
      const d = dist[k] + Math.hypot(nodes[j][0] - nodes[k][0], nodes[j][1] - nodes[k][1]);
      if (d >= dist[j]) continue;
      if (legClear(nodes[k], nodes[j], near, r, k === 0, j === goal)) { dist[j] = d; prev[j] = k; }
    }
  }
  if (!(dist[goal] < Infinity)) return { ...straight, direct: false, blocked: true };
  const pts = [];
  for (let k = goal; k >= 0; k = prev[k]) pts.unshift(nodes[k]);
  return { pts, len: dist[goal], direct: false, blocked: false };
}
/**
 * One leg of the way: clear by `r`, except for the first `r` inches from where the unit stands and the last `r`
 * inches before the target - a unit may stand against a wall, and its target may be next to one.
 */
function legClear(a, b, feats, r, fromStart, toGoal) {
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]), tight = Math.min(r, 0.05);
  const cutA = fromStart ? Math.min(r, len / 2) : 0, cutB = toGoal ? Math.min(r, len / 2) : 0;
  const at = (d) => [a[0] + (b[0] - a[0]) * (len > 0 ? d / len : 0), a[1] + (b[1] - a[1]) * (len > 0 ? d / len : 0)];
  if (cutA > 0 && !clearWay(a, at(cutA), feats, tight)) return false;
  if (cutB > 0 && !clearWay(at(len - cutB), b, feats, tight)) return false;
  return len - cutA - cutB <= 1e-9 || clearWay(at(cutA), at(len - cutB), feats, r);
}
/** The point `dist` inches along a path (its end if the path is shorter). -> { x, y, dist (moved) } */
export function along(pts, dist) {
  let left = Math.max(0, dist), moved = 0;
  for (let i = 1; i < pts.length; i++) {
    const [ax, ay] = pts[i - 1], [bx, by] = pts[i], l = Math.hypot(bx - ax, by - ay);
    if (left <= l + 1e-9) { const t = l > 0 ? Math.min(1, left / l) : 0; return { x: ax + (bx - ax) * t, y: ay + (by - ay) * t, dist: moved + Math.min(left, l) }; }
    left -= l; moved += l;
  }
  const e = pts[pts.length - 1];
  return { x: e[0], y: e[1], dist: moved };
}
/** How much further than the straight line a unit has to go to get from where it stands to (tx, ty). */
export function detour(u, tx, ty, pieces) {
  const rt = route(u, tx, ty, pieces);
  return rt.direct || rt.blocked ? 0 : Math.max(0, rt.len - Math.hypot(tx - u.x, ty - u.y));
}
