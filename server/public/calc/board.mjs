// Board planner geometry for the combat calculator: model footprints, unit
// formations, base-to-base gaps and mission / layout lookup. Pure module
// (no DOM) so it is unit-tested (tests/calc-board.test.mjs).
//
// Units: inches, board 44" x 60" portrait, origin top-left (the game's
// convention; see terrain-11e.mjs).

import { BOARD, LAYOUTS, DEPLOYMENTS, MATCHUPS, DISPOSITIONS } from './terrain-11e.mjs';

export { BOARD, LAYOUTS, DEPLOYMENTS, MATCHUPS, DISPOSITIONS };

const MM = 1 / 25.4;
// 11e objective range in open ground: 3" + the 40 mm marker's 20 mm radius
// (MissionManager.gd: control_radius = 3.78740157"). An objective hosted by a
// terrain area is in range when a base overlaps that area (14.01).
export const OBJECTIVE_RANGE = 3 + 20 * MM;
export const ENGAGEMENT_RANGE = 2;

/**
 * Footprint of one model from a datasheet's base_size_mm. Round / oval bases
 * are exact; hulls without dimensions get an approximate rectangle.
 * -> { shape: 'round', r } | { shape: 'oval', rx, ry } | { shape: 'rect', hw, hh, approx: true }
 */
export function footprint(base, keywords = []) {
  const kw = new Set(keywords.map(k => String(k).toUpperCase()));
  if (base?.shape === 'round' && base.diameter) return { shape: 'round', r: (base.diameter * MM) / 2 };
  if (base?.shape === 'oval' && base.width && base.length) {
    // the long axis runs across the token (x)
    const a = Math.max(base.width, base.length) * MM / 2, b = Math.min(base.width, base.length) * MM / 2;
    return { shape: 'oval', rx: a, ry: b };
  }
  if (base?.shape === 'flying-base') return { shape: 'round', r: (60 * MM) / 2 };
  // hull / unknown: rough size by role
  if (kw.has('VEHICLE')) return kw.has('TITANIC') ? { shape: 'rect', hw: 5, hh: 3.5, approx: true } : { shape: 'rect', hw: 2.6, hh: 1.6, approx: true };
  if (kw.has('MONSTER')) return { shape: 'round', r: 1.8, approx: true };
  return { shape: 'round', r: (32 * MM) / 2, approx: !base };
}

/** Half extents of a footprint (for layout). */
function halfSize(fp) {
  if (fp.shape === 'round') return { hx: fp.r, hy: fp.r };
  if (fp.shape === 'oval') return { hx: fp.rx, hy: fp.ry };
  return { hx: fp.hw, hy: fp.hh };
}

/** Distance from a footprint's centre to its edge in direction (ux, uy) (unit vector), footprint turned by `rot` degrees. */
export function edgeRadius(fp, ux, uy, rot = 0) {
  if (fp.shape === 'round') return fp.r;
  if (rot) {
    const a = (-rot * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
    [ux, uy] = [ux * c - uy * s, ux * s + uy * c];
  }
  const { hx, hy } = halfSize(fp);
  if (fp.shape === 'oval') return (hx * hy) / Math.sqrt((hy * ux) ** 2 + (hx * uy) ** 2);
  // rectangle: distance to the boundary along the ray
  const tx = ux ? hx / Math.abs(ux) : Infinity, ty = uy ? hy / Math.abs(uy) : Infinity;
  return Math.min(tx, ty);
}

/**
 * A unit's starting formation: models in rows (up to `perRow`), 1" apart edge
 * to edge (well inside 11e coherency: 2" to one model, 9" to all), centred on
 * (0, 0). members: [{ count, fp, label }]. Characters (leaders) go in the
 * middle of the front row.
 * -> [{ dx, dy, fp, label }]
 */
export function formation(members, { gap = 1, perRow = 5 } = {}) {
  const models = [];
  const leaders = members.filter(m => m.leader);
  const rest = members.filter(m => !m.leader);
  for (const m of rest) for (let i = 0; i < m.count; i++) models.push({ fp: m.fp, label: m.label });
  // leaders into the middle of the first row
  const firstRow = Math.min(perRow, models.length + leaders.length);
  for (const [i, l] of leaders.entries()) models.splice(Math.max(0, Math.floor(firstRow / 2) - Math.floor(leaders.length / 2) + i), 0, { fp: l.fp, label: l.label, leader: true });
  const rows = [];
  for (let i = 0; i < models.length; i += perRow) rows.push(models.slice(i, i + perRow));
  const out = [];
  let y = 0;
  const rowHeights = rows.map(r => Math.max(...r.map(m => halfSize(m.fp).hy * 2)));
  for (const [ri, row] of rows.entries()) {
    const widths = row.map(m => halfSize(m.fp).hx * 2);
    const total = widths.reduce((a, b) => a + b, 0) + gap * (row.length - 1);
    let x = -total / 2;
    for (const [i, m] of row.entries()) {
      out.push({ dx: x + widths[i] / 2, dy: y + rowHeights[ri] / 2, fp: m.fp, label: m.label, leader: !!m.leader });
      x += widths[i] + gap;
    }
    y += rowHeights[ri] + gap;
  }
  const midY = (y - gap) / 2;
  for (const m of out) m.dy -= midY;
  return out;
}

/**
 * A formation turned by `rot` degrees (clockwise on screen): offsets rotate
 * about the unit's centre and every base turns with it.
 */
export function rotateFormation(models, rot) {
  const a = (rot * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
  return models.map(m => ({ ...m, dx: m.dx * c - m.dy * s, dy: m.dx * s + m.dy * c, rot }));
}

/** Closest base-to-base distance between two placed units (0 when touching / overlapping). */
export function unitGap(a, b) {
  let best = Infinity;
  for (const ma of a.models) {
    for (const mb of b.models) {
      const ax = a.x + ma.dx, ay = a.y + ma.dy, bx = b.x + mb.dx, by = b.y + mb.dy;
      const d = Math.hypot(bx - ax, by - ay);
      if (d === 0) return 0;
      const ux = (bx - ax) / d, uy = (by - ay) / d;
      best = Math.min(best, d - edgeRadius(ma.fp, ux, uy, ma.rot) - edgeRadius(mb.fp, -ux, -uy, mb.rot));
    }
  }
  return Math.max(0, best);
}

/** Closest base edge of a placed unit to a point. */
export function pointGap(u, px, py) {
  let best = Infinity;
  for (const m of u.models) {
    const x = u.x + m.dx, y = u.y + m.dy, d = Math.hypot(px - x, py - y);
    if (d === 0) return 0;
    best = Math.min(best, d - edgeRadius(m.fp, (px - x) / d, (py - y) / d, m.rot));
  }
  return Math.max(0, best);
}

/** Layouts for two Force Dispositions (either order), by variant. */
export function layoutsFor(dispA, dispB) {
  const ids = new Set([`${dispA}-vs-${dispB}`, `${dispB}-vs-${dispA}`]);
  return LAYOUTS.filter(l => ids.has(l.matchup)).sort((x, y) => x.variant - y.variant);
}

/** Each player's primary mission: { A, B } (from their own disposition vs the other's). */
export function missionsFor(dispA, dispB) {
  const m = (a, b) => MATCHUPS.find(x => x.mine === a && x.theirs === b)?.mission ?? null;
  return { A: m(dispA, dispB), B: m(dispB, dispA) };
}

export function dispositionName(id) {
  return DISPOSITIONS.find(d => d.id === id)?.name ?? id;
}

/** Point-in-polygon (ray casting). poly: [[x, y], ...] */
export function inPoly(px, py, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
