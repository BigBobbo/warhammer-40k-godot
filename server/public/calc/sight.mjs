// Line of sight, benefit of cover and next-turn threat on the board planner,
// following the game's 11e terrain model (40k/autoloads/EnhancedLineOfSight.gd
// _check_single_line_of_sight_11e and TerrainManager.gd), in 2D:
//   13.10 Obscuring: a sight line crossing a LIGHT or DENSE terrain AREA is
//         blocked, unless one of the two models is within that area (any part
//         of its base; an area = the boundary piece plus the features linked
//         to it).
//   13.11 Solid: a DENSE terrain FEATURE blocks ground-level sight lines
//         through it, unless one of the two models stands in it (base centre).
//   13.08 Benefit of cover vs a ranged attack: every target model is
//         INFANTRY / BEASTS / SWARM within a terrain area, or not fully
//         visible to the attacker.
//   13.09 Hidden: INFANTRY / BEASTS / SWARM within an area holding a DENSE
//         feature is only visible within 15" (if it has not shot recently).
// Model heights, windows and floors are not modelled: answers close to the
// line are flagged "check on the table" (see sightVerdict).
//
// Units: { x, y, models: [{ dx, dy, fp, rot }], keywords: [...] } in inches.
// Pieces: terrain-11e.mjs layout pieces ({ id, cls, cat, parent, link, poly }).
// Pure module, unit-tested (tests/calc-sight.test.mjs).

import { edgeRadius } from './board.mjs';

export const HIDDEN_RANGE = 15;
const COVER_KW = /^(INFANTRY|BEASTS|SWARM)$/i;

// ---------------------------------------------------------------------------
// geometry

function inPoly(px, py, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function segsCross(ax, ay, bx, by, cx, cy, dx, dy) {
  const d1 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
  const d2 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
  const d3 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  const d4 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
  return ((d1 > 0) !== (d2 > 0)) && ((d3 > 0) !== (d4 > 0));
}

/** Segment touches the polygon: crosses an edge or starts / ends inside. */
export function segHitsPoly(a, b, poly) {
  if (inPoly(a[0], a[1], poly) || inPoly(b[0], b[1], poly)) return true;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    if (segsCross(a[0], a[1], b[0], b[1], poly[j][0], poly[j][1], poly[i][0], poly[i][1])) return true;
  }
  return false;
}

function distToSeg(px, py, ax, ay, bx, by) {
  const vx = bx - ax, vy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy || 1)));
  return Math.hypot(px - ax - t * vx, py - ay - t * vy);
}

/** A model's base overlaps the polygon (any part: the 01.04 "within" convention). */
function baseInPoly(cx, cy, r, poly) {
  if (inPoly(cx, cy, poly)) return true;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    if (distToSeg(cx, cy, poly[j][0], poly[j][1], poly[i][0], poly[i][1]) <= r) return true;
  }
  return false;
}

const baseR = (fp) => fp.r ?? Math.min(fp.rx ?? fp.hw ?? 0.6, fp.ry ?? fp.hh ?? 0.6);

/** Points a sight line may be drawn from / to on one base: centre + 4 near the rim. */
export function sightPoints(x, y, fp, rot = 0) {
  const pts = [[x, y]];
  for (const deg of [0, 90, 180, 270]) {
    const a = ((deg + rot) * Math.PI) / 180, ux = Math.cos(a), uy = Math.sin(a);
    const r = edgeRadius(fp, ux, uy, rot) * 0.85;
    pts.push([x + ux * r, y + uy * r]);
  }
  return pts;
}

// ---------------------------------------------------------------------------
// terrain areas

/** Area group key per piece: link group, else the parent area, else itself (13.01). */
export function areaGroups(pieces) {
  const byId = new Map(pieces.map(p => [p.id, p]));
  const key = (p, depth = 0) => {
    if (p.link) return `lg:${p.link}`;
    if (p.parent) return depth < 4 && byId.has(p.parent) ? key(byId.get(p.parent), depth + 1) : `id:${p.parent}`;
    return `id:${p.id}`;
  };
  return new Map(pieces.map(p => [p.id, key(p)]));
}

const obscures = (p) => p.cls !== 'feature' && (p.cat === 'light' || p.cat === 'dense');
const solid = (p) => p.cls !== 'area' && p.cat === 'dense';

function modelAbs(u, m) {
  return { x: u.x + m.dx, y: u.y + m.dy, fp: m.fp, rot: m.rot ?? 0, r: baseR(m.fp) };
}

/** Which areas / features a model is in: groups (any part of base) and features it stands in (centre). */
function modelTerrain(m, pieces, groups) {
  const g = new Set(), f = new Set();
  for (const p of pieces) {
    if (p.poly.length < 3) continue;
    const centre = inPoly(m.x, m.y, p.poly);
    if (centre || baseInPoly(m.x, m.y, m.r, p.poly)) {
      g.add(groups.get(p.id));
      if (centre) f.add(p.id);
    }
  }
  return { g, f };
}

/** Is one sight line blocked, given the pair's exclusions? */
export function lineBlocked(a, b, pieces, groups, exGroups, exFeats) {
  for (const p of pieces) {
    const ob = obscures(p) && !exGroups.has(groups.get(p.id));
    const so = solid(p) && !exFeats.has(p.id);
    if ((ob || so) && segHitsPoly(a, b, p.poly)) return true;
  }
  return false;
}

/** Can model a see model b: { any: some sight line clear, full: every sight line clear }. */
export function modelSight(ma, mb, pieces, groups, ta, tb) {
  const exG = new Set([...ta.g, ...tb.g]), exF = new Set([...ta.f, ...tb.f]);
  // quick accept / reject on the centre line keeps big units fast
  const pa = sightPoints(ma.x, ma.y, ma.fp, ma.rot), pb = sightPoints(mb.x, mb.y, mb.fp, mb.rot);
  let clear = 0, total = 0;
  for (const a of pa) for (const b of pb) {
    total++;
    if (!lineBlocked(a, b, pieces, groups, exG, exF)) clear++;
  }
  return { any: clear > 0, full: clear === total };
}

const gapBetween = (ma, mb) => {
  const d = Math.hypot(mb.x - ma.x, mb.y - ma.y);
  if (d === 0) return 0;
  const ux = (mb.x - ma.x) / d, uy = (mb.y - ma.y) / d;
  return Math.max(0, d - edgeRadius(ma.fp, ux, uy, ma.rot) - edgeRadius(mb.fp, -ux, -uy, mb.rot));
};

/**
 * Sight from one unit to another.
 * opts.range: attacker models only count when within this many inches (base to base).
 * -> { targetSeen, targetTotal, attackersSeeing, attackerTotal, cover, coverWhy, hidden }
 */
export function unitSight(att, tgt, pieces, { range = Infinity, groups = areaGroups(pieces) } = {}) {
  const A = att.models.map(m => modelAbs(att, m)), T = tgt.models.map(m => modelAbs(tgt, m));
  const tA = A.map(m => modelTerrain(m, pieces, groups)), tT = T.map(m => modelTerrain(m, pieces, groups));
  const seenBy = T.map(() => ({ any: false, full: false }));
  const seeing = A.map(() => false);
  for (const [i, ma] of A.entries()) {
    for (const [j, mb] of T.entries()) {
      if (gapBetween(ma, mb) > range) continue;
      const s = modelSight(ma, mb, pieces, groups, tA[i], tT[j]);
      if (s.any) { seeing[i] = true; seenBy[j].any = true; }
      if (s.full) seenBy[j].full = true;
    }
  }
  // 13.08: every target model in a terrain area (if it has the keyword) or not fully visible
  const kwCover = (tgt.keywords ?? []).some(k => COVER_KW.test(k));
  const inArea = T.map((m, j) => tT[j].g.size > 0 && pieces.some(p => inPoly(m.x, m.y, p.poly)));
  const coverEach = T.map((m, j) => (kwCover && inArea[j]) || !seenBy[j].full);
  const cover = T.length > 0 && coverEach.every(Boolean);
  const coverWhy = !cover ? '' : T.every((m, j) => kwCover && inArea[j]) ? 'in a terrain area' : T.every((m, j) => !seenBy[j].full) ? 'not fully visible' : 'in a terrain area / not fully visible';
  // 13.09: could the target be Hidden from this attacker?
  const denseGroups = new Set(pieces.filter(p => p.cat === 'dense' && p.cls !== 'area').map(p => groups.get(p.id)));
  const hiddenCapable = kwCover && T.every((m, j) => [...tT[j].g].some(g => denseGroups.has(g)));
  const nearest = Math.min(...A.flatMap(ma => T.map(mb => gapBetween(ma, mb))));
  return {
    targetSeen: seenBy.filter(s => s.any).length, targetTotal: T.length,
    attackersSeeing: seeing.filter(Boolean).length, attackerTotal: A.length, seeingMask: seeing,
    cover, coverWhy,
    hidden: hiddenCapable && nearest > HIDDEN_RANGE,
  };
}

/** Clear / partial / blocked from a unitSight result. */
export function sightClass(s) {
  if (s.targetSeen === 0 || s.attackersSeeing === 0) return 'blocked';
  return s.targetSeen === s.targetTotal ? 'clear' : 'partial';
}

/**
 * Sight with a robustness check: the answer is "borderline" when moving
 * either unit 0.5" any way changes it (model heights, windows and a
 * finger-placed token are all less precise than that).
 * -> { ...unitSight, verdict: 'clear' | 'partial' | 'blocked', borderline }
 */
export function sightVerdict(att, tgt, pieces, opts = {}) {
  const groups = areaGroups(pieces);
  const base = unitSight(att, tgt, pieces, { ...opts, groups });
  const v = sightClass(base);
  let borderline = false;
  const J = 0.5;
  for (const [dx, dy] of [[J, 0], [-J, 0], [0, J], [0, -J]]) {
    for (const which of ['att', 'tgt']) {
      const a2 = which === 'att' ? { ...att, x: att.x + dx, y: att.y + dy } : att;
      const t2 = which === 'tgt' ? { ...tgt, x: tgt.x + dx, y: tgt.y + dy } : tgt;
      const s = unitSight(a2, t2, pieces, { ...opts, groups });
      if (sightClass(s) !== v || s.cover !== base.cover) { borderline = true; break; }
    }
    if (borderline) break;
  }
  return { ...base, verdict: v, borderline };
}

// ---------------------------------------------------------------------------
// next-turn threat (ignores terrain and moving around it: a planning envelope)

/** P(2D6 >= n). */
export function p2d6(n) {
  let c = 0;
  for (let a = 1; a <= 6; a++) for (let b = 1; b <= 6; b++) if (a + b >= n) c++;
  return c / 36;
}

/**
 * How unit `enemy` threatens unit `me` next turn.
 * shoot: enemy's longest range reaches me after a normal move (gap <= M + range);
 * charge: P(the charge roll after a normal move ends within engagement range).
 * -> { gap, shoot: { range, margin } | null, charge: number | null }
 */
export function threatTo(enemy, me, { move, ranges = [], melee = false, engagement = 2 }) {
  let gap = Infinity;
  for (const ma of enemy.models) for (const mb of me.models) gap = Math.min(gap, gapBetween(modelAbs(enemy, ma), modelAbs(me, mb)));
  const maxR = ranges.length ? Math.max(...ranges) : 0;
  const shoot = maxR > 0 && gap <= move + maxR ? { range: maxR, margin: move + maxR - gap } : null;
  // charge: needs (gap - move - engagement) on 2D6 after moving straight in (2 is the minimum roll)
  const need = Math.max(2, Math.ceil(gap - move - engagement - 1e-9));
  const charge = melee && need <= 12 ? p2d6(need) : null;
  return { gap, shoot, charge };
}

/** Charge reach (inches from the enemy's bases) achieved with at least probability p. */
export function chargeReach(move, p, engagement = 2) {
  let best = null;
  for (let n = 2; n <= 12; n++) if (p2d6(n) >= p) best = n;
  return best == null ? null : move + best + engagement;
}
