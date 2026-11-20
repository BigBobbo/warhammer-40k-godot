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
 * Whose side each objective of a layout is on.
 *  - home objectives: the player whose deployment zone they are in;
 *  - central objectives: nobody's;
 *  - expansion objectives (the rest): the player whose TERRITORY they are in. The mission cards
 *    score objectives "within your opponent's territory" (Determined Acquisition, Sabotage, Smoke
 *    and Mirrors), and a territory is not "the half nearer my home objective": in 18 of the 45
 *    layouts the expansion objective in a player's territory is nearer the OTHER player's home
 *    objective (36 of 90 expansion objectives; measured on the bundled layouts, 20 Nov 2026).
 *    opts.byNearestHome: the rule the app used before 1.101 (kept to recognise plans made with it).
 * zoneA: the zone / territory number (1 or 2) of player A.
 * -> [{ id, cls: 'home' | 'central' | 'exp', side: 'A' | 'B' | null }] in the layout's order
 */
export function objectiveSides(layout, deployment, zoneA = 1, { byNearestHome = false } = {}) {
  const sideOf = (player) => (player === zoneA ? 'A' : 'B');
  const sideOfZone = (z) => sideOf(z === 'player1' ? 1 : 2);
  const objs = layout?.objectives ?? [];
  const homes = objs.filter(o => o.zone !== 'no_mans_land').map(o => ({ ...o, side: sideOfZone(o.zone) }));
  const hA = homes.find(h => h.side === 'A'), hB = homes.find(h => h.side === 'B');
  const nearest = (o) => (!hA || !hB ? null : Math.hypot(o.x - hA.x, o.y - hA.y) <= Math.hypot(o.x - hB.x, o.y - hB.y) ? 'A' : 'B');
  return objs.map(o => {
    // roles come from the official 11e cards (home / central / expansion); some layouts have two centrals
    if (o.role === 'home' || o.zone !== 'no_mans_land') return { id: o.id, cls: 'home', side: sideOfZone(o.zone) };
    if (o.role === 'central') return { id: o.id, cls: 'central', side: null };
    const terr = byNearestHome ? null : (deployment?.territories ?? []).find(t => inPoly(o.x, o.y, t.poly));
    return { id: o.id, cls: 'exp', side: terr ? sideOf(terr.player) : nearest(o) };
  });
}

/**
 * A unit's starting formation: models in rows (up to `perRow`), 1" apart edge
 * to edge (well inside 11e coherency: 2" to one model, 9" to all), centred on
 * (0, 0). members: [{ count, fp, label, oc }]. Characters (leaders) go in the
 * middle of the front row.
 * -> [{ dx, dy, fp, label, oc }]  (oc: that model's Objective Control, when the member gives it)
 */
export function formation(members, { gap = 1, perRow = 5 } = {}) {
  const models = [];
  const leaders = members.filter(m => m.leader);
  const rest = members.filter(m => !m.leader);
  for (const m of rest) for (let i = 0; i < m.count; i++) models.push({ fp: m.fp, label: m.label, oc: m.oc });
  // leaders into the middle of the first row
  const firstRow = Math.min(perRow, models.length + leaders.length);
  for (const [i, l] of leaders.entries()) models.splice(Math.max(0, Math.floor(firstRow / 2) - Math.floor(leaders.length / 2) + i), 0, { fp: l.fp, label: l.label, leader: true, oc: l.oc });
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
      out.push({ dx: x + widths[i] / 2, dy: y + rowHeights[ri] / 2, fp: m.fp, label: m.label, leader: !!m.leader, ...(m.oc != null ? { oc: m.oc } : {}) });
      x += widths[i] + gap;
    }
    y += rowHeights[ri] + gap;
  }
  const midY = (y - gap) / 2;
  for (const m of out) m.dy -= midY;
  return out;
}

/**
 * 03.03 Coherency of one unit's models: every model is within 2" (horizontally) of at least one other
 * model of the unit AND within 9" of every other model. Base edge to base edge.
 * -> { ok, widest: the largest gap between two models, alone: models with no other within 2" }
 */
export const COHERENCY = { near: 2, all: 9 };
export function coherency(models) {
  if (models.length < 2) return { ok: true, widest: 0, alone: 0 };
  const gap = (ma, mb) => {
    const d = Math.hypot(mb.dx - ma.dx, mb.dy - ma.dy);
    if (d === 0) return 0;
    const ux = (mb.dx - ma.dx) / d, uy = (mb.dy - ma.dy) / d;
    return Math.max(0, d - edgeRadius(ma.fp, ux, uy, ma.rot) - edgeRadius(mb.fp, -ux, -uy, mb.rot));
  };
  let widest = 0, alone = 0;
  for (const [i, a] of models.entries()) {
    let nearest = Infinity;
    for (const [j, b] of models.entries()) {
      if (i === j) continue;
      const g = gap(a, b);
      if (g < nearest) nearest = g;
      if (j > i && g > widest) widest = g;
    }
    if (nearest > COHERENCY.near + 1e-9) alone++;
  }
  return { ok: widest <= COHERENCY.all + 1e-9 && alone === 0, widest, alone };
}

/**
 * A starting formation that is in coherency: rows of up to `perRow`, 1" apart when that keeps every
 * model within 9" of every other, else closer together; if base contact is still too wide (a row of
 * large bases), fewer models per row (unless the player chose the row width: keepRows).
 * The plain 1" grid broke the 9" rule for units of ten 40 mm bases and for every unit on 60 mm bases.
 */
export function coherentFormation(members, { perRow = 5, keepRows = false } = {}) {
  let last = null;
  for (let per = perRow; per >= 1; per--) {
    for (const gap of [1, 0.75, 0.5, 0.25, 0]) {
      last = formation(members, { gap, perRow: per });
      if (coherency(last).ok) return last;
    }
    if (keepRows) break;
  }
  return last ?? [];
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

/**
 * A round against an opponent with disposition `opp`, for a list with
 * disposition `mine`: both primaries and the three layouts (A, B, C) of that
 * pairing (null where the data has none).
 */
export function matchupFor(mine, opp) {
  const ms = missionsFor(mine, opp);
  const lays = layoutsFor(mine, opp);
  return { mine: ms.A, theirs: ms.B, layouts: [1, 2, 3].map(v => lays.find(l => l.variant === v) ?? null) };
}

/** The official name of a layout variant: 1 / 2 / 3 = Layout A / B / C (Event Companion). */
export const layoutLetter = (variant) => 'ABC'[(variant ?? 1) - 1] ?? String(variant);

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
