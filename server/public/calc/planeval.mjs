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
import { threatTo, canHide, HIDDEN_RANGE } from './sight.mjs';

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

function abs(u) { return u.models.map(m => ({ x: u.x + m.dx, y: u.y + m.dy, r: extent(m.fp), oc: m.oc })); }

/** The models of a unit that are within range of an objective: hosted -> base in the hosting terrain area; else within 3" + the 20 mm marker. */
function modelsInRange(u, o, pieces) {
  const ms = abs(u);
  if (o.host?.length) {
    const polys = o.host.map(id => pieces.find(p => p.id === id)?.poly).filter(Boolean);
    if (polys.length) return ms.filter(m => polys.some(p => baseWithin(m.x, m.y, m.r, p)));
  }
  return ms.filter(m => Math.hypot(m.x - o.x, m.y - o.y) - m.r <= OBJECTIVE_RANGE);
}

/** Objective in range of a unit: one of its models is. */
export function inRange(u, o, pieces) {
  return modelsInRange(u, o, pieces).length > 0;
}

/**
 * The Objective Control a unit brings to an objective. 14.02: a player's level of control is the
 * sum of the OC of their MODELS within range - a unit with one model of ten on the objective
 * counts that one model. (Models without their own OC: the unit's OC, by the share in range.)
 */
export function ocInRange(u, o, pieces) {
  const inR = modelsInRange(u, o, pieces);
  if (!inR.length) return 0;
  if (inR.every(m => m.oc != null)) return inR.reduce((a, m) => a + m.oc, 0);
  return (u.oc ?? 0) * inR.length / Math.max(1, u.models.length);
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
  // battlefield edges the unit is within 6" of - whether it is in its territory or not: Outflank's 5 VP
  // asks for two units on OPPOSITE edges of which "one or more ... is not within your territory"
  const edges = new Set();
  for (const m of ms) {
    if (m.x - m.r <= 6) edges.add('L');
    if (m.x + m.r >= W - 6) edges.add('R');
    if (m.y - m.r <= 6) edges.add('T');
    if (m.y + m.r >= H - 6) edges.add('B');
  }
  const objOc = {};
  for (const o of geo.objectives) { const v = ocInRange(u, o, geo.pieces); if (v > 0 || inRange(u, o, geo.pieces)) objOc[o.id] = v; }
  return {
    objs: Object.keys(objOc),
    oc: u.oc ?? 0,          // the whole unit's OC
    objOc,                  // per objective in range: the OC of the models within range of it (14.02)
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
  const enemyKnown = Array.isArray(enemy);
  // Outflank. 3 VP: a unit within 6" of a battlefield edge and not within your territory. 5 VP: two units
  // within 6" of opposite edges, one or more of them not within your territory.
  const opposite = (a, b) => (a.edges.includes('L') && b.edges.includes('R')) || (a.edges.includes('R') && b.edges.includes('L')) ||
    (a.edges.includes('T') && b.edges.includes('B')) || (a.edges.includes('B') && b.edges.includes('T'));
  const flankOpposite = mine.some((a, i) => mine.some((b, j) => i < j && (a.outsideTerritory || b.outsideTerritory) && opposite(a, b)));
  return {
    inEnemyDZ: mine.filter(f => f.inEnemyDZ).length,
    quarters: qs.size,
    flank: mine.some(f => f.outsideTerritory && f.edges.length > 0),
    flankOpposite,
    outsideDZ: mine.some(f => f.outsideDZ), outsideTerritory: mine.some(f => f.outsideTerritory),
    terrainOutside: mine.some(f => f.terrainOutside),
    centre3: mine.some(f => f.centre3),
    centreKnown: enemyKnown, enemyCentre3: enemyKnown && enemy.some(f => f.centre3), enemyCentre6: enemyKnown && enemy.some(f => f.centre6),
    nmlKnown: enemyKnown, nmlMine: mine.filter(f => f.whollyNML).length, nmlEnemy: enemyKnown ? enemy.filter(f => f.whollyNML).length : 0,
    dzKnown: enemyKnown, enemyInMyDZ: enemyKnown && enemy.some(f => f.inEnemyDZany),
  };
}

/**
 * From how far a unit can be seen where it stands (Infinity = no limit): a Lone Operative from 12"
 * (24.24, u.lone); infantry that can be Hidden there from 15" (13.09) - counted only for a unit
 * without ranged weapons, which never shoots and so stays hidden.
 */
export function detectRange(u, pieces) {
  let d = Infinity;
  if (u.lone) d = Math.min(d, u.lone);
  if (pieces?.length && !(u.ranges ?? []).length && canHide(u, pieces)) d = Math.min(d, HIDDEN_RANGE);
  return d;
}

/**
 * Exposure: chance each of X's units is destroyed in the enemy's turn, from
 * where the enemy starts it. Each enemy unit attacks the one target it
 * threatens most (shooting reach after a normal move, charge odds), weighted
 * by points; pair odds come from the calculator (pair[atkKey][tgtKey] =
 * { shoot: P(destroy by shooting), fight: P(destroy in a fight) }).
 * -> { [targetKey]: P(destroyed) }
 */
export function exposure(targets, attackers, pair, pieces = null) {
  const take = {};
  for (const a of attackers) {
    let best = null, bestV = 0;
    for (const t of targets) {
      const th = threatTo(a, t, { move: a.move ?? 6, ranges: a.ranges ?? [], melee: !!a.melee, detect: detectRange(t, pieces) });
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
 * Kill pressure: how many enemy units an army destroys in a turn, from the
 * calculator. Each unit attacks the target it damages most (shooting, or a
 * fight if that is better; default rules, no stratagems); the shares of the
 * targets' wounds removed are added up (a target cannot lose more than all of
 * its wounds). That is the army's damage "on paper" with everything in reach;
 * ENGAGE is the share of it an army delivers in a typical turn (range, line of
 * sight, charges that fail, units busy holding objectives). ENGAGE is set so
 * that typical 2,000-point lists come out near 1.3 units a turn, the rate the
 * forecast is calibrated at (tests/calc-calibration.test.mjs).
 * pair[atkKey][defKey] = { sMu, fMu, W } (mean wounds by shooting / fighting, target wounds)
 * -> { raw, rate, by: [{ key, target, frac }] }
 */
export const ENGAGE = 0.3;
export function killPressure(attackerKeys, targetKeys, pair) {
  const taken = Object.fromEntries(targetKeys.map(k => [k, 0]));
  const best = (a) => {
    let top = null;
    for (const t of targetKeys) {
      const pr = pair?.[a]?.[t];
      if (!pr || !(pr.W > 0)) continue;
      const frac = Math.min(1, Math.max(pr.sMu ?? 0, pr.fMu ?? 0) / pr.W);
      const gain = Math.min(frac, 1 - taken[t]);
      if (!top || gain > top.gain) top = { t, frac, gain };
    }
    return top;
  };
  // the hardest hitters choose first
  const order = attackerKeys.map(a => ({ a, top: best(a) })).filter(x => x.top).sort((x, y) => y.top.frac - x.top.frac);
  const by = [];
  let raw = 0;
  for (const { a } of order) {
    const top = best(a);
    if (!top || top.gain <= 0) { by.push({ key: a, target: null, frac: 0 }); continue; }
    taken[top.t] += top.gain; raw += top.gain;
    by.push({ key: a, target: top.t, frac: top.gain });
  }
  return { raw, rate: Math.max(0.3, Math.min(3.5, raw * ENGAGE)), by };
}

/**
 * Board plan: what each attacker can do to each target from where it stands
 * (planned positions are after the move: no extra move). For each attacker the
 * best three targets, by share of the target destroyed x its points.
 * pair[atkKey][defKey] = { shoot, fight (P destroyed alone), sMu, sSd, fMu, fSd, W }
 * -> [{ a: attackerName, opts: [{ t: targetName, mu, v, w, W }] }]
 *    mu / v = mean and variance of the wounds it removes, w = P(it destroys the target alone)
 */
export function threatOptions(attackers, targets, pair, top = 3, pieces = null) {
  const out = [];
  for (const a of attackers) {
    const opts = [];
    for (const t of targets) {
      const pr = pair?.[a.key]?.[t.key];
      if (!pr || !(pr.W > 0)) continue;
      const th = threatTo(a, t, { move: 0, ranges: a.ranges ?? [], melee: !!a.melee, detect: detectRange(t, pieces) });
      const sh = th.shoot ? 1 : 0, ch = th.charge ?? 0;
      const mu = sh * (pr.sMu ?? 0) + ch * (pr.fMu ?? 0);
      if (mu <= 0) continue;
      // variance: the shooting roll, plus the fight (which only happens if the charge is made)
      const v = sh * (pr.sSd ?? 0) ** 2 + ch * (pr.fSd ?? 0) ** 2 + ch * (1 - ch) * (pr.fMu ?? 0) ** 2;
      const w = 1 - (1 - sh * (pr.shoot ?? 0)) * (1 - ch * (pr.fight ?? 0));
      opts.push({ t: t.name, mu, v, w, W: pr.W, value: Math.min(1, mu / pr.W) * Math.max(1, t.points ?? 1) });
    }
    opts.sort((x, y) => y.value - x.value);
    if (opts.length) out.push({ a: a.name, opts: opts.slice(0, top).map(({ value, ...o }) => o) });
  }
  return out;
}

/** Shortest distance from a point to a polygon (0 inside it). */
function polyDist(px, py, poly) { return inPoly(px, py, poly) ? 0 : edgeDist(px, py, poly); }

/**
 * Plan sanity, by the 11th edition rules:
 *  - deployment (the first step): a unit is wholly within its deployment zone, unless every model has
 *    Infiltrators (24.20: anywhere more than 8" from the enemy deployment zone and enemy units) or it
 *    made a Scout move (24.32: up to X" out of the zone, more than 8" from enemy units);
 *  - moves between steps longer than the unit can make (normal move + advance or + charge);
 *  - arriving from reserves (20.03 / 20.04, ingress move): not in battle round 1; wholly within 6" of
 *    a battlefield edge; no model in the enemy deployment zone before round 3; more than 8" from all
 *    enemy units; a unit still in reserves at the end of round 3 is destroyed. A unit whose models
 *    all have Deep Strike (24.09) can arrive anywhere more than 8" from enemy units, "even if that
 *    is within your opponent's deployment zone" - no edge and no zone restriction.
 * steps: [{ name, A: [unit], B: [unit] }] in order (unit.flags: adapter coreFlags);
 * -> [{ step, side, unit, msg, info? }]
 */
export function planWarnings(steps, geo) {
  const out = [];
  const gap8 = (ms, enemies) => enemies.some(e => abs(e).some(em => ms.some(m => Math.hypot(m.x - em.x, m.y - em.y) - m.r - em.r <= 8)));
  // deployment
  if (steps.length) {
    for (const X of ['A', 'B']) {
      const Y = X === 'A' ? 'B' : 'A';
      const myDZ = geo.zones?.[X], enDZ = geo.zones?.[Y];
      if (!myDZ) continue;
      for (const u of steps[0][X] ?? []) {
        const ms = abs(u);
        if (ms.every(m => baseWhollyWithin(m.x, m.y, m.r, myDZ))) continue;
        const f = u.flags ?? {};
        if (f.infiltrators) {
          const nearDZ = enDZ && ms.some(m => polyDist(m.x, m.y, enDZ) - m.r <= 8);
          if (nearDZ || gap8(ms, steps[0][Y] ?? [])) out.push({ step: steps[0].name, side: X, unit: u.name, msg: `Infiltrators: must be set up more than 8" from the enemy deployment zone and enemy units (24.20)` });
        } else if (f.scouts) {
          const far = ms.some(m => polyDist(m.x, m.y, myDZ) + m.r > f.scouts + 0.5);
          if (far) out.push({ step: steps[0].name, side: X, unit: u.name, msg: `is more than its ${f.scouts}" Scout move outside its deployment zone (24.32)` });
          else if (gap8(ms, steps[0][Y] ?? [])) out.push({ step: steps[0].name, side: X, unit: u.name, msg: 'a Scout move must end more than 8" from enemy units (24.32)' });
        } else out.push({ step: steps[0].name, side: X, unit: u.name, msg: 'is not wholly within its deployment zone (it has no Infiltrators or Scouts)', info: true });
      }
    }
  }
  for (let i = 1; i < steps.length; i++) {
    for (const X of ['A', 'B']) {
      const prev = new Map((steps[i - 1][X] ?? []).map(u => [u.key, u]));
      for (const u of steps[i][X] ?? []) {
        const p = prev.get(u.key);
        if (p) {
          const d = Math.hypot(u.x - p.x, u.y - p.y), mv = u.move ?? 6;
          if (d > mv + 12 + 0.5) out.push({ step: steps[i].name, side: X, unit: u.name, msg: `moves ${d.toFixed(0)}" (max ${mv + 12}": move + charge)` });
          else if (d > mv + 6 + 0.5) out.push({ step: steps[i].name, side: X, unit: u.name, msg: `moves ${d.toFixed(0)}": needs a charge (move ${mv}" + advance is ${mv + 6}")`, info: true });
        } else if (steps[i - 1][X]?.length) {
          // arrives from reserves
          const Y = X === 'A' ? 'B' : 'A';
          const round = i; // step i = battle round i
          const ms = abs(u);
          const ds = !!u.flags?.deepStrike;
          const warn = (msg, info = false) => out.push({ step: steps[i].name, side: X, unit: u.name, msg, ...(info ? { info } : {}) });
          if (round < 2) warn('arrives in battle round 1: reserves arrive from the second battle round (20.03)');
          if (round > 3) warn(`arrives in battle round ${round}: a unit still in reserves at the end of round 3 is destroyed (20.04)`);
          if (!ds) {
            if (!ms.every(m => m.x + m.r <= 6 || m.x - m.r >= W - 6 || m.y + m.r <= 6 || m.y - m.r >= H - 6)) warn('arrives more than 6" from a battlefield edge: without Deep Strike a unit is set up wholly within 6" of an edge (20.04)');
            if (round < 3 && geo.zones[Y] && ms.some(m => baseWithin(m.x, m.y, m.r, geo.zones[Y]))) warn('arrives in the enemy deployment zone before round 3 (20.04; only a Deep Strike unit can)');
          }
          if (gap8(ms, steps[i][Y] ?? [])) warn(`arrives within 8" of an enemy unit (it must be more than 8" away${ds ? ', Deep Strike too' : ''})`);
        }
      }
    }
  }
  return out;
}
