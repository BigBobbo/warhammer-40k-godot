// Board plan -> what the mission forecast needs, measured on the 11e map:
// for each battle round and each army, the objectives each unit is in range
// of (with its OC), the position checks the secondaries ask for (wholly in
// the enemy deployment zone, table quarters, battlefield edges, the centre,
// No Man's Land, territory, terrain), how exposed it is to the enemy's units,
// and plan sanity warnings (moves longer than the unit can make, reserves
// arriving where 11e does not allow).
//
// Plan steps map to battle rounds: "Deploy" = before round 1, "Turn N" = the
// positions during battle round N (the last step carries on). Pure module,
// unit-tested (tests/calc-planeval.test.mjs).

import { OBJECTIVE_RANGE, inPoly } from './board.mjs';
import { threatTo } from './sight.mjs';

const W = 44, H = 60, CX = 22, CY = 30;
const extent = (fp) => fp.r ?? Math.max(fp.rx ?? 0, fp.hw ?? 0, fp.ry ?? 0, fp.hh ?? 0);

function distToSeg(px, py, ax, ay, bx, by) {
  const vx = bx - ax, vy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy || 1)));
  return Math.hypot(px - ax - t * vx, py - ay - t * vy);
}
function edgeDist(px, py, poly) {
  let d = Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) d = Math.min(d, distToSeg(px, py, poly[j][0], poly[j][1], poly[i][0], poly[i][1]));
  return d;
}
/** Any part of the base within the polygon (the 11e "within" convention). */
export const baseWithin = (x, y, r, poly) => inPoly(x, y, poly) || edgeDist(x, y, poly) <= r;
/** The whole base within the polygon ("wholly within"). */
export const baseWhollyWithin = (x, y, r, poly) => inPoly(x, y, poly) && edgeDist(x, y, poly) >= r;

function abs(u) { return u.models.map(m => ({ x: u.x + m.dx, y: u.y + m.dy, r: extent(m.fp) })); }

/** Objective in range of a unit: hosted -> any base in the hosting terrain area; else within 3" + the 20 mm marker. */
export function inRange(u, o, pieces) {
  const ms = abs(u);
  if (o.host?.length) {
    const polys = o.host.map(id => pieces.find(p => p.id === id)?.poly).filter(Boolean);
    if (polys.length) return ms.some(m => polys.some(p => baseWithin(m.x, m.y, m.r, p)));
  }
  return ms.some(m => Math.hypot(m.x - o.x, m.y - o.y) - m.r <= OBJECTIVE_RANGE);
}

function quarterOf(ms) {
  // wholly within one table quarter and no model within 6" of the centre
  if (ms.some(m => Math.hypot(m.x - CX, m.y - CY) - m.r < 6)) return -1;
  const q = (m) => (m.x + m.r <= CX ? 0 : m.x - m.r >= CX ? 1 : -9) + (m.y + m.r <= CY ? 0 : m.y - m.r >= CY ? 2 : -9);
  const qs = new Set(ms.map(q));
  return qs.size === 1 && [...qs][0] >= 0 ? [...qs][0] : -1;
}

/**
 * Position facts for one unit of side X.
 * geo: { zones: {A, B}, territories: {A, B}, pieces, objectives }
 */
export function unitFacts(u, X, geo) {
  const Y = X === 'A' ? 'B' : 'A';
  const ms = abs(u);
  const anyIn = (poly) => poly && ms.some(m => baseWithin(m.x, m.y, m.r, poly));
  const allIn = (poly) => poly && ms.every(m => baseWhollyWithin(m.x, m.y, m.r, poly));
  const myTerr = geo.territories[X], myDZ = geo.zones[X], enDZ = geo.zones[Y];
  const outsideTerritory = myTerr ? !anyIn(myTerr) : false;
  const edges = new Set();
  if (outsideTerritory) {
    for (const m of ms) {
      if (m.x - m.r <= 6) edges.add('L');
      if (m.x + m.r >= W - 6) edges.add('R');
      if (m.y - m.r <= 6) edges.add('T');
      if (m.y + m.r >= H - 6) edges.add('B');
    }
  }
  return {
    objs: geo.objectives.filter(o => inRange(u, o, geo.pieces)).map(o => o.id),
    oc: u.oc ?? 0,
    inEnemyDZ: allIn(enDZ),
    inMyDZ: anyIn(myDZ),
    inEnemyDZany: anyIn(enDZ),
    outsideDZ: !anyIn(myDZ),
    outsideTerritory,
    quarter: quarterOf(ms),
    edges: [...edges],
    centre3: ms.some(m => Math.hypot(m.x - CX, m.y - CY) - m.r <= 3),
    centre6: ms.some(m => Math.hypot(m.x - CX, m.y - CY) - m.r <= 6),
    whollyNML: !anyIn(geo.zones.A) && !anyIn(geo.zones.B),
    terrainOutside: outsideTerritory && geo.pieces.some(p => p.cls === 'area' && ms.some(m => inPoly(m.x, m.y, p.poly))),
  };
}

/** Round-level position facts for the forecast, from the surviving units' facts. */
export function sideFacts(mine, enemy) {
  const qs = new Set(mine.map(f => f.quarter).filter(q => q >= 0));
  const edges = new Set(mine.flatMap(f => f.edges));
  const enemyKnown = Array.isArray(enemy);
  return {
    inEnemyDZ: mine.filter(f => f.inEnemyDZ).length,
    quarters: qs.size,
    flank: edges.size > 0,
    flankOpposite: (edges.has('L') && edges.has('R')) || (edges.has('T') && edges.has('B')),
    outsideDZ: mine.some(f => f.outsideDZ), outsideTerritory: mine.some(f => f.outsideTerritory),
    terrainOutside: mine.some(f => f.terrainOutside),
    centre3: mine.some(f => f.centre3),
    centreKnown: enemyKnown, enemyCentre3: enemyKnown && enemy.some(f => f.centre3), enemyCentre6: enemyKnown && enemy.some(f => f.centre6),
    nmlKnown: enemyKnown, nmlMine: mine.filter(f => f.whollyNML).length, nmlEnemy: enemyKnown ? enemy.filter(f => f.whollyNML).length : 0,
    dzKnown: enemyKnown, enemyInMyDZ: enemyKnown && enemy.some(f => f.inEnemyDZany),
  };
}

/**
 * Exposure: chance each of X's units is destroyed in the enemy's turn, from
 * where the enemy starts it. Each enemy unit attacks the one target it
 * threatens most (shooting reach after a normal move, charge odds), weighted
 * by points; pair odds come from the calculator (pair[atkKey][tgtKey] =
 * { shoot: P(destroy by shooting), fight: P(destroy in a fight) }).
 * -> { [targetKey]: P(destroyed) }
 */
export function exposure(targets, attackers, pair) {
  const take = {};
  for (const a of attackers) {
    let best = null, bestV = 0;
    for (const t of targets) {
      const th = threatTo(a, t, { move: a.move ?? 6, ranges: a.ranges ?? [], melee: !!a.melee });
      const pr = pair?.[a.key]?.[t.key] ?? { shoot: 0, fight: 0 };
      const p = 1 - (1 - (th.shoot ? pr.shoot : 0)) * (1 - (th.charge ?? 0) * pr.fight);
      const v = p * Math.max(1, t.points ?? 1);
      if (v > bestV) { bestV = v; best = { t, p }; }
    }
    if (best) take[best.t.key] = 1 - (1 - (take[best.t.key] ?? 0)) * (1 - best.p);
  }
  return take;
}

/**
 * Plan sanity: moves between consecutive steps longer than the unit can
 * make (normal move + advance or + charge), and reserves arriving in the
 * enemy deployment zone before round 3 or within 9" of enemy units.
 * steps: [{ name, A: [unit], B: [unit] }] in order; -> [{ step, side, unit, msg }]
 */
export function planWarnings(steps, geo) {
  const out = [];
  for (let i = 1; i < steps.length; i++) {
    for (const X of ['A', 'B']) {
      const prev = new Map((steps[i - 1][X] ?? []).map(u => [u.key, u]));
      for (const u of steps[i][X] ?? []) {
        const p = prev.get(u.key);
        if (p) {
          const d = Math.hypot(u.x - p.x, u.y - p.y), mv = u.move ?? 6;
          if (d > mv + 12 + 0.5) out.push({ step: steps[i].name, side: X, unit: u.name, msg: `moves ${d.toFixed(0)}" (max ${mv + 12}": move + charge)` });
          else if (d > mv + 6 + 0.5) out.push({ step: steps[i].name, side: X, unit: u.name, msg: `moves ${d.toFixed(0)}": needs a charge (move ${mv}" + advance is ${mv + 6}")`, info: true });
        } else if (i >= 1 && steps[i - 1][X]?.length) {
          // arrives from reserves
          const Y = X === 'A' ? 'B' : 'A';
          const round = i; // step i = battle round i
          const ms = abs(u);
          if (round < 3 && geo.zones[Y] && ms.some(m => baseWithin(m.x, m.y, m.r, geo.zones[Y]))) out.push({ step: steps[i].name, side: X, unit: u.name, msg: 'arrives in the enemy deployment zone before round 3 (not allowed in 11e)' });
          const near = (steps[i][Y] ?? []).some(e => abs(e).some(em => ms.some(m => Math.hypot(m.x - em.x, m.y - em.y) - m.r - em.r < 9)));
          if (near) out.push({ step: steps[i].name, side: X, unit: u.name, msg: 'arrives within 9" of an enemy unit' });
        }
      }
    }
  }
  return out;
}
