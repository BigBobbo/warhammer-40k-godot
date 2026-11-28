// "Their next turn": from where the two armies stand on the table now, what the other player can do in
// their next turn - which of my units they can shoot or charge and how likely each is destroyed, which
// objectives they can take, and which of the cards in their hand they can score. No search and no
// guessing at a plan: it is the worst case and the likely case of what is in reach, from the calculator's
// unit-vs-unit odds and the 11e map. Pure module (no DOM), unit-tested (tests/calc-nextturn.test.mjs).
//
// A unit here is the Board's unit: { key, name, x, y, models: [{ dx, dy, fp, oc }], move, ranges, melee, oc,
// points, keywords, lone, left, total (models now / at the start), shocked, chars, w10, ss13 }.
// What it does not know: terrain in the way of a move (a move is a straight line here), units arriving from
// reserves or stepping out of a transport, stratagems and abilities that are not in the unit-vs-unit odds.

import { OBJECTIVE_RANGE, inPoly } from './board.mjs';
import { threatTo, unitSight, p2d6, canHide, HIDDEN_RANGE } from './sight.mjs';
import { detectRange, unitFacts, ocInRange, inRange, arrivalZones, canArrive } from './planeval.mjs';
import { SECONDARIES } from './missions-11e.mjs';
import { route, along, goesRound, detour } from './paths.mjs';

const W = 44, H = 60;
const extent = (fp) => fp.r ?? Math.max(fp.rx ?? 0, fp.hw ?? 0, fp.ry ?? 0, fp.hh ?? 0);
const abs = (u) => u.models.map(m => ({ x: u.x + m.dx, y: u.y + m.dy, r: extent(m.fp) }));
const clamp01 = (v) => Math.max(0, Math.min(1, v));

/** Standard normal CDF (Abramowitz-Stegun 7.1.26, error < 1e-7 on what is used here). */
export function phi(z) {
  const t = 1 / (1 + 0.3275911 * Math.abs(z) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-z * z / 2);
  return z >= 0 ? 0.5 * (1 + y) : 0.5 * (1 - y);
}

/**
 * P(a unit with `wounds` wounds is destroyed) by several attacks together.
 * parts: [{ mu, v (mean and variance of the wounds each removes), p (P it destroys the target alone; optional) }]
 * The wounds add up (a normal curve on the sum), and it is never less than "one of them does it alone".
 */
export function killChance(parts, wounds) {
  const live = parts.filter(x => x.mu > 0);
  if (!live.length || !(wounds > 0)) return 0;
  const alone = 1 - live.reduce((a, x) => a * (1 - clamp01(x.p ?? 0)), 1);
  const M = live.reduce((a, x) => a + x.mu, 0), V = live.reduce((a, x) => a + (x.v ?? 0), 0);
  const sum = V > 1e-9 ? 1 - phi((wounds - 0.5 - M) / Math.sqrt(V)) : (M >= wounds ? 1 : 0);
  // one attack on a unit at full strength: the calculator's own figure
  if (live.length === 1 && live[0].p != null) return clamp01(live[0].p);
  return clamp01(Math.max(alone, sum));
}

// ---------------------------------------------------------------------------
// Rules the suggestions follow (core rules, Wahapedia wh40k11ed)

/** 03.04: engagement range, horizontally. */
export const ENGAGEMENT = 2;
/** 20.04 / 24.09: a unit arriving from reserves is set up more than this far from all enemy units. */
export const ARRIVE_GAP = 8;
/** 15.09 snap shooting (Fire Overwatch): one visible enemy unit within this range; hits on unmodified 6s only. */
export const OVERWATCH_RANGE = 24;
/** 15.11 Heroic Intervention: an unengaged unit within this range of an enemy unit. */
export const HEROIC_RANGE = 12;
/** 12.08 consolidation, Objective mode: a unit within this range of an objective ends within range of it. */
export const CONSOLIDATE = 3;
/** Snap shooting hits on a 6 only: about this share of a unit's usual shooting (a 3+ to hit; 0.33 for a 4+). */
export const SNAP_SHARE = 0.25;
/** What controlling one objective for one more scoring is counted as when a kill or a move is weighed (primaries pay 3 to 5 VP an objective). */
export const OBJ_VP = 4;

/** The gap between the nearest bases of two units (inches). */
export function unitGap(a, b) {
  let d = Infinity;
  for (const p of abs(a)) for (const q of abs(b)) d = Math.min(d, Math.hypot(p.x - q.x, p.y - q.y) - p.r - q.r);
  return Math.max(0, d);
}
/** The units of `others` this unit is engaged with (03.04). */
export const engagedWith = (u, others) => (u.embarked ? [] : others.filter(o => !o.embarked && unitGap(u, o) <= ENGAGEMENT + 1e-9));
const isVM = (u) => (u.keywords ?? []).some(k => /^(MONSTER|VEHICLE)$/i.test(k));
/**
 * 01.02.01 / 08.03: is the unit at or below half-strength (it takes a battle-shock roll in its Command phase)?
 * Two or more models at the start: models left <= half. One model: wounds left <= half (u.wLeft / u.W1, when known).
 */
export function halfStrength(u) {
  if ((u.total ?? 0) >= 2) return u.left != null && u.left * 2 <= u.total;
  // one model at the start: its wounds (u.wFrac = the share it has left)
  if (u.wFrac != null) return u.wFrac <= 0.5 + 1e-9;
  return u.wLeft != null && u.W1 > 0 && u.wLeft * 2 <= u.W1;
}
/** 01.07: P(a battle-shock roll fails) = P(2D6 < Ld). 0 when the Leadership is not known. */
export const shockFail = (ld) => (ld >= 2 ? 1 - p2d6(ld) : 0);
/**
 * The share of a unit's shooting that reaches a target `need` inches away (after its move): u.bands =
 * [{ range, share }] (the share of its ranged damage from weapons of each range; adapter.boardUnit). A unit
 * without bands shoots with everything once its longest range reaches (as before).
 */
export function rangeShare(u, need) {
  if (!u.bands?.length) return Math.max(0, ...(u.ranges ?? [])) >= need - 1e-9 ? 1 : 0;
  return Math.min(1, u.bands.reduce((a, b) => a + (b.range >= need - 1e-9 ? b.share : 0), 0));
}
/** 13.08, the part that does not depend on the attacker: every model is INFANTRY / BEASTS / SWARM within a terrain area. */
export function areaCover(u, pieces) {
  if (!pieces?.length || !(u.keywords ?? []).some(k => /^(INFANTRY|BEASTS|SWARM)$/i.test(k))) return false;
  const areas = pieces.filter(p => p.poly?.length >= 3);
  return abs(u).every(m => areas.some(p => inPoly(m.x, m.y, p.poly)));
}
/** A unit's first, middle and last model (a quick sight check). */
const few = (u) => (u.models.length <= 3 ? u : { ...u, models: [u.models[0], u.models[Math.floor(u.models.length / 2)], u.models[u.models.length - 1]] });
/** Can the attacker see the target after a move of up to `mv` inches (in a straight line: 8 directions at full and half move, and where it stands)? */
function sightAfterMove(a, t, pieces, mv, range) {
  const sees = (x, y) => { const s = unitSight(few({ ...a, x, y }), few(t), pieces, { range }); return s.attackersSeeing > 0 && s.targetSeen > 0; };
  if (sees(a.x, a.y)) return true;
  if (!(mv > 0)) return false;
  for (const k of [1, 0.5]) for (let i = 0; i < 8; i++) {
    const x = a.x + Math.cos(i * Math.PI / 4) * mv * k, y = a.y + Math.sin(i * Math.PI / 4) * mv * k;
    if (x < 1 || y < 1 || x > W - 1 || y > H - 1) continue;
    if (sees(x, y)) return true;
  }
  return false;
}
/** How far a point is from the band a unit arriving without Deep Strike is set up in (wholly within 6" of an edge; 20.04). */
const edgeBandGap = (x, y) => Math.max(0, Math.min(x, W - x, y, H - y) - 6);
/**
 * What a unit still in reserves can do to a unit of mine in the turn it arrives (20.04 / 24.09): it is set up
 * more than 8" from every enemy unit (a unit without Deep Strike: wholly within 6" of a battlefield edge), then
 * shoots, and can declare a charge (11.02 does not bar it): at least a 9. -> as sight.threatTo
 */
function reserveThreat(a, t) {
  const far = a.deepStrike ? 0 : Math.min(...abs(t).map(m => edgeBandGap(m.x, m.y) - m.r));
  const gap = Math.max(ARRIVE_GAP + 0.01, far);
  const maxR = Math.max(0, ...(a.ranges ?? []));
  const need = Math.max(9, Math.ceil(gap - 1e-9));
  return { gap, shoot: maxR >= gap ? { range: maxR, margin: maxR - gap } : null, unseen: false, charge: a.melee && need <= 12 ? p2d6(need) : null, engaged: false };
}

/** Up to 6 of a unit's models for a sight check: its outermost ones, the first and the middle one. */
function outer(u, n = 6) {
  const ms = u.models;
  if (ms.length <= n) return u;
  const by = (f) => ms.reduce((a, m) => (f(m) < f(a) ? m : a));
  return { ...u, models: [...new Set([by(m => m.dx), by(m => -m.dx), by(m => m.dy), by(m => -m.dy), ms[0], ms[Math.floor(ms.length / 2)]])] };
}
const share = (u) => (u.total > 0 && u.left != null ? Math.max(0, Math.min(1, u.left / u.total)) : 1);
/** The share of a unit's wounds it still has: models lost and the wounds a damaged model has lost (u.wFrac, when the table tracks them). */
const wshare = (u) => (u.wFrac != null ? Math.max(0, Math.min(1, u.wFrac)) : share(u));

/**
 * What each of their units can do to each of mine in their next turn.
 * pair[atkKey][defKey] = { shoot, fight (P destroyed alone), sMu, sSd, fMu, fSd, W } (full-strength units);
 * models lost since scale it: the attacker's damage by its models left, the target's wounds by its models left.
 * opts.pieces: the layout's terrain (who is Hidden / a Lone Operative, and who has a sight line now).
 * -> [{ key, name, points, wounds, focus (P destroyed if everything in reach attacks it), likely (P destroyed
 *       when each of their units attacks the target it is worth most against), by: [{ key, name, shoot: { range,
 *       now (in range and in sight without moving) } | null, charge (P), engaged, mu, p }] }], most at risk first
 */
export function turnThreats(mine, theirs, pair, { pieces = null, strictSight = false, reserves = [], quiet = null, cache = null } = {}) {
  const rows = mine.map(t => ({ key: t.key, name: t.name, points: t.points ?? 0, wounds: 0, focus: 0, likely: 0, by: [], parts: [], scaled: false }));
  const best = new Map();   // attacker key -> { row, value, part }
  // (03.04, 09.05, 10.04, 11.02) a unit that starts the turn engaged fights what it is engaged with: it cannot make a
  // normal move, shoot (MONSTER / VEHICLE models excepted, 10.06) or declare a charge
  const locked = new Map(theirs.map(a => [a.key, new Set(engagedWith(a, mine).map(t => t.key))]));
  const attackers = [...theirs.map(a => ({ a, off: false })), ...reserves.map(a => ({ a, off: true }))];
  for (const [ti, t] of mine.entries()) {
    const row = rows[ti];
    const ts = wshare(t);
    const cover0 = areaCover(t, pieces);
    // (13.09) a unit that can be Hidden where it stands and holds its fire is seen from 15" only
    const detect = Math.min(detectRange(t, pieces), quiet?.has(t.key) && pieces?.length && canHide(t, pieces) ? HIDDEN_RANGE : Infinity);
    for (const { a, off } of attackers) {
      const pr = pair?.[a.key]?.[t.key];
      const mv = a.moveLeft ?? a.move ?? 6;
      const lock = off ? null : locked.get(a.key);
      const stuck = !!lock?.size && !lock.has(t.key);         // engaged with another unit
      const th = off ? reserveThreat(a, t) : threatTo(a, t, { move: stuck ? 0 : mv, ranges: a.ranges ?? [], melee: !!a.melee, detect });
      if (off && th.shoot && detect < th.gap) th.shoot = null;
      const mayShoot = !a.noShoot && (!lock?.size || isVM(a));
      const mayCharge = !a.noCharge && !stuck && (!a.chargeOnly || a.chargeOnly.has(t.key) || th.engaged);
      let shoot = mayShoot ? th.shoot : null;
      const ch = mayCharge ? th.charge ?? 0 : 0;
      if (!shoot && ch < 0.03) continue;
      let now = false, cover = cover0;
      if (shoot && pieces && !off) {
        if (th.gap <= shoot.range) {
          const s = unitSight(outer(a), outer(t), pieces, { range: shoot.range });
          now = s.attackersSeeing > 0 && s.targetSeen > 0 && !s.hidden;
          if (now && s.cover) cover = true;
        }
        // my own attacks are only counted when a sight line is found, where it stands or after its move
        if (!now && strictSight && pieces.length) {
          const smv = lock?.size ? 0 : (a.shootMove ?? mv), ck = `${a.key}:${a.x.toFixed(1)},${a.y.toFixed(1)}:${smv}>${t.key}:${t.x.toFixed(1)},${t.y.toFixed(1)}`;
          let sees = cache?.get(ck);
          if (sees == null) { sees = sightAfterMove(a, t, pieces, smv, shoot.range); cache?.set(ck, sees); }
          if (!sees) shoot = null;
        }
      }
      if (!shoot && ch < 0.03) continue;
      const as = share(a);
      const Wt = (pr?.W ?? 0) * ts;
      if (Wt > 0) row.wounds = Wt;
      // the weapons that reach (a unit with one long gun does not shoot with everything from afar); in cover: BS worse by 1 (13.08)
      const rs = shoot ? (off ? rangeShare(a, th.gap) : rangeShare(a, th.gap - (lock?.size ? 0 : (a.shootMove ?? mv)))) * (lock?.size ? 0.8 : 1) : 0;
      const inCover = !!shoot && cover && pr?.sMuC != null;
      const sMu0 = inCover ? pr.sMuC : pr?.sMu ?? 0, sSd0 = inCover ? pr.sSdC ?? pr.sSd ?? 0 : pr?.sSd ?? 0, sP0 = inCover ? pr.shootC ?? pr.shoot ?? 0 : pr?.shoot ?? 0;
      // where the attack is made from: standing still within range and in sight ([HEAVY] +1 to hit, 24.16: no model
      // moved more than 3", not set up this turn), or close enough for half range ([RAPID FIRE], [MELTA]) - one or the other
      const base0 = pr?.sMu ?? 0;
      const still = !!shoot && !off && !a.movedFar && pr?.sMuH != null && th.gap <= shoot.range + 1e-9 && (pieces ? now : true);
      const close = !!shoot && pr?.sMuR != null && a.halfAt > 0 && th.gap - (off || lock?.size ? 0 : (a.shootMove ?? mv)) <= a.halfAt + 1e-9;
      const sit = base0 > 0 ? Math.max(1, still ? pr.sMuH / base0 : 1, close ? pr.sMuR / base0 : 1) : 1;
      const sMu = sMu0 * as * rs * sit, fMu = (pr?.fMu ?? 0) * as;
      const mu = sMu + ch * fMu;
      const v = (shoot ? (sSd0 * as * rs) ** 2 : 0) + ch * ((pr?.fSd ?? 0) * as) ** 2 + ch * (1 - ch) * fMu ** 2;
      const less = as < 1 || ts < 1 || (shoot && rs < 0.999), scaled = less || sit > 1.001;
      // on its own: the calculator's figure at full strength, else from the wounds it removes (a better situation
      // never makes it less likely than the calculator's own figure)
      const pCalc = pr ? 1 - (1 - (shoot ? sP0 : 0)) * (1 - ch * (pr.fight ?? 0)) : 0;
      const p = !pr || !(Wt > 0) ? 0 : less ? killChance([{ mu, v }], Wt) : scaled ? Math.max(pCalc, killChance([{ mu, v }], Wt)) : pCalc;
      if (!(mu > 0) && !(p > 0) && !th.engaged) continue;
      const part = { mu, v, p: scaled ? undefined : p };
      row.by.push({ key: a.key, name: a.name, shoot: shoot ? { range: shoot.range, now, share: rs, cover: inCover, ...(sit > 1.001 ? { boost: sit, how: still && pr.sMuH >= (close ? pr.sMuR : 0) ? 'still' : 'half' } : {}) } : null, charge: ch >= 0.03 ? ch : 0, engaged: th.engaged, mu, p, part,
        ...(off ? { reserve: true } : {}), ...(a.embarked ? { embarked: a.embarked } : {}) });
      row.parts.push(part);
      const value = p * Math.max(1, t.points ?? 1);
      if (value > (best.get(a.key)?.value ?? 0)) best.set(a.key, { row, value, part });
    }
  }
  const likelyParts = new Map();
  for (const { row, part } of best.values()) { if (!likelyParts.has(row)) likelyParts.set(row, []); likelyParts.get(row).push(part); }
  for (const [ti, row] of rows.entries()) {
    const t = mine[ti];
    row.focus = killChance(row.parts, row.wounds);
    row.likely = killChance(likelyParts.get(row) ?? [], row.wounds);
    // (08.03) at or below half-strength it takes a battle-shock roll in its next Command phase: the wounds that get it there
    row.ld = t.ld ?? null; row.shockFail = shockFail(t.ld);
    row.isHalf = halfStrength(t);
    // (a unit of one model: half of the wounds it started with)
    row.halfWounds = (t.total ?? 0) >= 2 && t.left > 0 && row.wounds > 0 ? Math.max(0, t.left - Math.floor(t.total / 2)) * (row.wounds / t.left)
      : t.total === 1 && row.wounds > 0 ? Math.max(0, row.wounds - 0.5 * row.wounds / Math.max(1e-9, t.wFrac ?? 1)) : 0;
    row.half = row.isHalf ? 1 : row.halfWounds > 0 ? killChance((likelyParts.get(row) ?? []).map(x => ({ mu: x.mu, v: x.v })), row.halfWounds) : row.likely;
    row.by.sort((x, y) => y.p - x.p || y.mu - x.mu);
    delete row.parts; delete row.scaled;
  }
  return rows.sort((x, y) => y.likely - x.likely || y.focus - x.focus || y.points - x.points);
}

// ---------------------------------------------------------------------------
// Objectives

function distToSeg(px, py, ax, ay, bx, by) {
  const vx = bx - ax, vy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy || 1)));
  return Math.hypot(px - ax - t * vx, py - ay - t * vy);
}
function polyDist(px, py, poly) {
  if (inPoly(px, py, poly)) return 0;
  let d = Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) d = Math.min(d, distToSeg(px, py, poly[j][0], poly[j][1], poly[i][0], poly[i][1]));
  return d;
}
/** How far a unit is from being in range of an objective (0: a model is in range). */
export function objectiveGap(u, o, pieces) {
  const polys = (o.host ?? []).map(id => pieces?.find(p => p.id === id)?.poly).filter(Boolean);
  let d = Infinity;
  for (const m of abs(u)) {
    d = Math.min(d, polys.length ? Math.min(...polys.map(p => polyDist(m.x, m.y, p))) - m.r : Math.hypot(m.x - o.x, m.y - o.y) - m.r - OBJECTIVE_RANGE);
  }
  return Math.max(0, d);
}
const ocOf = (u) => (u.shocked ? 0 : u.oc ?? 0);           // a battle-shocked unit has OC "-"
const ocAt = (u, o, pieces) => (u.shocked ? 0 : ocInRange(u, o, pieces));

/**
 * Where a unit arriving from reserves can stand in range of an objective (20.04 / 24.09), or null.
 * r: { deepStrike, base (the radius of its largest base) }; enemies: the other player's units on the table;
 * round: the battle round it arrives in (2 or 3); enemyZone: the other player's deployment zone.
 * One base is placed (the rest of the unit is set up behind it): a planning answer, checked on the table.
 */
export function arrivalSpot(o, r, enemies, pieces, { round = 2, enemyZone = null } = {}) {
  if (round < 2 || round > 3) return null;
  const zones = arrivalZones(enemies, round), rr = r.base ?? 0.63;
  const fp = { shape: 'round', r: rr };
  const ok = (x, y) => canArrive(x, y, rr, zones, { deepStrike: !!r.deepStrike, enemyZone }).ok && objectiveGap({ x, y, models: [{ dx: 0, dy: 0, fp }] }, o, pieces) <= 0;
  if (ok(o.x, o.y)) return { x: o.x, y: o.y };
  const polys = (o.host ?? []).map(id => pieces?.find(p => p.id === id)?.poly).filter(Boolean);
  const reach = polys.length ? Math.max(...polys.flat().map(q => Math.hypot(q[0] - o.x, q[1] - o.y))) : OBJECTIVE_RANGE + rr - 0.05;
  for (const k of [1, 0.66, 0.33]) for (let i = 0; i < 16; i++) {
    const x = o.x + Math.cos(i * Math.PI / 8) * reach * k, y = o.y + Math.sin(i * Math.PI / 8) * reach * k;
    if (ok(x, y)) return { x, y };
  }
  return null;
}

/**
 * Each objective: who controls it now, and what they can bring to it in their turn.
 * objs: the layout's objectives with { cls: 'home' | 'central' | 'exp', side, label } (board.objectiveSides);
 * me: my side. risk: { [myUnitKey]: P(destroyed) } (turnThreats' likely) for the units of mine that hold it.
 * How a unit of theirs gets its OC there (14.02: control is worked out at the end of every phase):
 *  - 'move': a normal move in a straight line; 'advance': with an Advance (the D6 it needs);
 *  - 'fallback': it is engaged, so it can only Fall Back there (09.07: no shooting, charge or action after);
 *  - 'charge': it charges a unit of mine that stands on the objective (11.04), then piles in and consolidates
 *    onto it (12.03 / 12.08, 3" each); 'fight': it is already engaged with one;
 *  - 'reserves': it arrives there from reserves (opts.reserves, in battle round opts.round: 20.04 / 24.09).
 * secured: { [objectiveId]: side } - 14.03: a secured objective stays its player's, with no unit in range too,
 * until the other player's level of control is greater.
 * -> [{ id, label, cls, side, mine, theirs (OC in range now), holder: 'me' | 'them' | null, secured: 'me' | 'them' | null,
 *       holders: [{ key, name, oc, risk }] (mine), there: [{ key, name, oc, full (the whole unit's OC) }] (theirs in range now),
 *       movers: [{ key, name, oc, via, need (D6 / 2D6), p }],
 *       max (their OC with everything a normal move or a Fall Back brings), maxCharge (with charges too),
 *       maxAdvance (with Advances), maxAll (with everything, reserves included),
 *       verdict: 'theirs' | 'lose' | 'contest' | 'charge' | 'advance' | 'reserves' | 'safe' | 'take' | 'open' }]
 */
export function objectiveSwing(mine, theirs, objs, pieces, { me = 'A', risk = {}, secured = {}, reserves = [], round = 0, enemyZone = null } = {}) {
  const lockedBy = new Map(theirs.map(u => [u.key, engagedWith(u, mine)]));
  return objs.map(o => {
    const holders = mine.filter(u => !u.embarked).map(u => ({ key: u.key, name: u.name, oc: ocAt(u, o, pieces), in: inRange(u, o, pieces), risk: risk[u.key] ?? 0 })).filter(h => h.in).map(({ in: _in, ...h }) => h);
    const myOc = holders.reduce((a, h) => a + h.oc, 0);
    const sec = secured[o.id] ? (secured[o.id] === me ? 'me' : 'them') : null;
    const there = [], movers = [];
    let now = 0, max = 0, maxAdvance = 0, maxCharge = 0, maxAll = 0;
    const onIt = mine.filter(u => holders.some(h => h.key === u.key));
    for (const u of theirs) {
      // (a unit inside a transport is measured from the transport: it has to get out first, 18.04)
      const d0 = Math.max(objectiveGap(u, o, pieces), u.embarked ? 0.01 : 0), full = u.shocked ? 0 : u.oc ?? 0, M = u.moveLeft ?? u.move ?? 6;
      // (a unit that has to go round dense terrain - 13.06 - has further to go than the straight line)
      const d = d0 > 0 && full > 0 && d0 <= M + 6 && goesRound(u) ? d0 + detour(u, o.x, o.y, pieces) : d0;
      const locked = lockedBy.get(u.key).length > 0;
      if (d <= 0) {
        const oc = u.shocked ? 0 : ocInRange(u, o, pieces);
        there.push({ key: u.key, name: u.name, oc, full });
        now += oc; max += full; maxAdvance += full; maxCharge += full; maxAll += full;     // the rest of the unit can close up
        continue;
      }
      if (!(full > 0)) continue;
      const tag = u.embarked ? { embarked: u.embarked } : {};
      if (d <= M + 1e-9) { movers.push({ key: u.key, name: u.name, oc: full, via: locked ? 'fallback' : 'move', need: 0, p: 1, ...tag }); max += full; maxAdvance += full; maxCharge += full; maxAll += full; continue; }
      // a charge onto a unit of mine that stands on it (or the fight it is already in), then 3" + 3" onto the objective
      let cp = 0, cNeed = 0, fight = false;
      if (u.melee && !u.noCharge && d <= M + 12 + 2 * CONSOLIDATE) for (const h of onIt) {
        if (locked && !lockedBy.get(u.key).includes(h)) continue;
        const th = threatTo(u, h, { move: M, ranges: [], melee: true });
        if ((th.charge ?? 0) > cp) { cp = th.charge; fight = th.engaged; cNeed = Math.max(3, Math.ceil(th.gap - M - 1e-9)); }
      }
      const aNeed = !locked && d <= M + 6 + 1e-9 ? Math.max(1, Math.ceil(d - M - 1e-9)) : 0, ap = aNeed ? (7 - aNeed) / 6 : 0;
      if (cp >= 0.03) maxCharge += full;
      if (aNeed) maxAdvance += full;
      if (cp >= 0.03 || aNeed) {
        maxAll += full;
        movers.push(cp >= ap ? { key: u.key, name: u.name, oc: full, via: fight ? 'fight' : 'charge', need: fight ? 0 : cNeed, p: cp, ...(aNeed ? { advance: aNeed } : {}), ...tag }
          : { key: u.key, name: u.name, oc: full, via: 'advance', need: aNeed, p: ap, ...(cp >= 0.03 ? { charge: cp } : {}), ...tag });
      }
    }
    for (const r of reserves) {
      if (!((r.oc ?? 0) > 0)) continue;
      const at = arrivalSpot(o, r, mine, pieces, { round, enemyZone });
      if (at) { movers.push({ key: r.key, name: r.name, oc: r.oc, via: 'reserves', need: 0, p: 1, x: at.x, y: at.y, deepStrike: !!r.deepStrike }); maxAll += r.oc; }
    }
    const ORDER = { move: 0, fallback: 1, fight: 2, charge: 3, advance: 4, reserves: 5 };
    movers.sort((a, b) => ORDER[a.via] - ORDER[b.via] || a.need - b.need || b.oc - a.oc);
    // a tie leaves the objective with nobody (14.02), or with the player who secured it (14.03)
    const holder = myOc > now ? 'me' : now > myOc ? 'them' : myOc > 0 || sec ? sec : null;
    const beats = (x) => (sec === 'them' ? x >= myOc && (x > 0 || holder === 'them') : x > myOc);
    // an Advance, a charge or reserves are only named when a normal move is not enough
    const verdict = holder === 'them' ? 'theirs'
      : beats(max) ? (holder === 'me' ? 'lose' : 'take')
        : holder === 'me' ? (max === myOc && max > now && sec !== 'me' ? 'contest' : maxCharge > myOc ? 'charge' : maxAdvance >= myOc && maxAdvance > max && (sec !== 'me' || maxAdvance > myOc) ? 'advance' : maxAll > myOc ? 'reserves' : 'safe')
          : maxAdvance > myOc ? 'advance' : maxAll > myOc ? 'reserves' : 'open';
    return { id: o.id, label: o.label ?? o.id, cls: o.cls, side: o.side ?? null, x: o.x, y: o.y, host: o.host ?? [], mine: myOc, theirs: now, holder, secured: sec, holders, there, movers, max, maxCharge, maxAdvance, maxAll, verdict, mySide: me };
  });
}

/**
 * How many of these objectives they can control at the end of their turn, a unit going to one objective only
 * (the easiest objectives first; normal moves first, then a Fall Back; no Advance, charge or reserves). -> { n, ids, picks }
 */
export function controllable(swing, ids) {
  const used = new Set(), got = [], picks = {};
  const rows = swing.filter(o => ids.includes(o.id)).map(o => ({ o, short: o.mine - o.theirs })).sort((a, b) => a.short - b.short);
  for (const { o } of rows) {
    let oc = o.theirs;
    // their units in range stay (their full OC closes up), then the nearest movers
    const pick = [];
    for (const t of o.there) if (!used.has(t.key)) pick.push(t.key);
    oc = o.there.filter(t => !used.has(t.key)).reduce((a, t) => a + Math.max(t.oc, t.full ?? 0), 0);
    const beat = () => (o.secured === 'them' ? oc >= o.mine && oc > 0 : oc > o.mine);
    for (const m of o.movers) {
      if (beat()) break;
      if ((m.via !== 'move' && m.via !== 'fallback') || used.has(m.key)) continue;
      oc += m.oc; pick.push(m.key);
    }
    if (beat()) { got.push(o.id); picks[o.id] = pick; for (const k of pick) used.add(k); }
  }
  return { n: got.length, ids: got, picks };
}

// ---------------------------------------------------------------------------
// Where a unit can stand after a normal move (for the cards that ask where units are)

/**
 * What a unit can be after a normal move in a straight line (no terrain, other models not in the way):
 * the position facts of planeval.unitFacts, over where it stands and a grid of places within its Move.
 * -> { now: facts, canEnemyDZ, quarters: Set, centre3, whollyNML, flankEdges: Set (near an edge and not within
 *      its territory), edges: Set (near an edge at all), terrainOutside }
 */
export function reachFacts(u, X, geo, { step = 2 } = {}) {
  const now = unitFacts(u, X, geo);
  const out = { now, canEnemyDZ: false, quarters: new Set(), centre3: false, whollyNML: false, flankEdges: new Set(), edges: new Set(), terrainOutside: false, at: {} };
  // at: where each of these is first true, the nearest such place ({ x, y, dist }; dist 0 = where it stands)
  const mark = (k, x, y) => { const d = Math.hypot(x - u.x, y - u.y); if (!out.at[k] || d < out.at[k].dist) out.at[k] = { x, y, dist: d }; };
  const take = (f, x = u.x, y = u.y) => {
    if (f.inEnemyDZ) mark('canEnemyDZ', x, y);
    if (f.centre3) mark('centre3', x, y);
    if (f.terrainOutside) mark('terrainOutside', x, y);
    if (f.outsideTerritory && f.edges.length) mark('flank', x, y);
    if (f.inEnemyDZ) out.canEnemyDZ = true;
    if (f.quarter >= 0) out.quarters.add(f.quarter);
    if (f.centre3) out.centre3 = true;
    if (f.whollyNML) out.whollyNML = true;
    for (const e of f.edges) { out.edges.add(e); if (f.outsideTerritory) out.flankEdges.add(e); }
    if (f.terrainOutside) out.terrainOutside = true;
  };
  take(now);
  const M = u.move ?? 6;
  const rel = u.models.map(m => ({ dx: m.dx, dy: m.dy, r: extent(m.fp) }));
  for (let dx = -Math.floor(M / step) * step; dx <= M; dx += step) {
    for (let dy = -Math.floor(M / step) * step; dy <= M; dy += step) {
      if ((dx === 0 && dy === 0) || Math.hypot(dx, dy) > M + 1e-9) continue;
      const x = u.x + dx, y = u.y + dy;
      if (rel.some(m => x + m.dx - m.r < 0 || y + m.dy - m.r < 0 || x + m.dx + m.r > W || y + m.dy + m.r > H)) continue;
      take(unitFacts({ ...u, x, y }, X, geo), x, y);
    }
  }
  return out;
}

/** The most different table quarters a set of units can be in, one unit to a quarter. */
export function maxQuarters(sets) {
  const taken = new Array(4).fill(-1);
  const tryUnit = (i, seen) => {
    for (const q of sets[i]) {
      if (seen.has(q)) continue;
      seen.add(q);
      if (taken[q] < 0 || tryUnit(taken[q], seen)) { taken[q] = i; return true; }
    }
    return false;
  };
  let n = 0;
  for (let i = 0; i < sets.length; i++) if (tryUnit(i, new Set())) n++;
  return n;
}

// ---------------------------------------------------------------------------
// The cards in their hand

const OPP = { L: 'R', R: 'L', T: 'B', B: 'T' };
const pct = (p) => `${Math.round(p * 100)}%`;
const names = (list, n = 2) => list.slice(0, n).join(', ') + (list.length > n ? ` and ${list.length - n} more` : '');

/**
 * Each card in their hand: can they score it in their turn?
 * c: { hand: [cardId], round, me, mine, theirs (units), threats (turnThreats), swing (objectiveSwing), geo }
 * -> [{ id, name, when: 'theirs' (end of their turn) | 'mine' (end of my turn, as it stands now), vp, max,
 *       verdict: 'yes' (by moving alone) | 'kill' (they must destroy something; p) | 'now' | 'no' | 'ask'
 *       (it depends on a pick this app does not know), p, why }]
 */
export function cardOutlook(c) {
  const X = c.me, Y = X === 'A' ? 'B' : 'A';
  const myF = c.mine.map(u => unitFacts(u, X, c.geo));
  // (worked out only when a card in the hand asks where their units can be)
  let reachMemo = null;
  const R = () => (reachMemo ??= c.theirs.map(u => reachFacts(u, Y, c.geo)));
  const swing = c.swing, byId = new Map(swing.map(o => [o.id, o]));
  const riskOf = new Map(c.threats.map(t => [t.key, t]));
  const theirCtl = (o) => o.verdict === 'theirs' || o.verdict === 'lose' || o.verdict === 'take';
  // kill cards: my units that count, and how likely each is destroyed if they go for it
  const kill = (pick, what) => {
    const el = c.mine.filter(pick).map(u => ({ name: u.name, p: riskOf.get(u.key)?.focus ?? 0 })).sort((a, b) => b.p - a.p);
    if (!el.length) return { verdict: 'no', vp: 0, why: `no ${what} of yours left on the table` };
    if (!(el[0].p >= 0.005)) return { verdict: 'no', vp: 0, why: `nothing of theirs can destroy ${el.length === 1 ? el[0].name : `your ${what}s`} this turn` };
    return { verdict: 'kill', vp: 5, p: el[0].p, why: `if they destroy ${el[0].name} (${pct(el[0].p)} with everything in reach)${el.length > 1 ? `; ${el.length - 1} more target${el.length > 2 ? 's' : ''}` : ''}` };
  };
  const out = [];
  for (const id of c.hand ?? []) {
    const card = SECONDARIES.find(s => s.id === id);
    if (!card) continue;
    let r = { verdict: 'no', vp: 0, why: '' };
    switch (id) {
      case 'assassination': r = kill(u => (u.chars ?? 0) > 0, 'CHARACTER unit'); break;
      case 'bring-it-down': r = kill(u => (u.w10 ?? 0) > 0, 'model with 10+ wounds'); break;
      case 'a-grievous-blow': r = kill(u => !!u.ss13, 'unit of 13+ models'); break;
      case 'no-prisoners': case 'overwhelming-force': {
        const onObj = (u) => swing.some(o => o.holders.some(h => h.key === u.key));
        const el = c.mine.filter(u => id === 'no-prisoners' || onObj(u)).map(u => ({ name: u.name, p: riskOf.get(u.key)?.likely ?? 0 })).filter(e => e.p >= 0.005).sort((a, b) => b.p - a.p);
        const each = id === 'no-prisoners' ? 2 : 3;
        if (!el.length) { r = { verdict: 'no', vp: 0, why: id === 'no-prisoners' ? 'nothing of yours is likely to be destroyed this turn' : 'no unit of yours on an objective is likely to be destroyed' }; break; }
        const any = 1 - el.reduce((a, e) => a * (1 - e.p), 1), exp = el.reduce((a, e) => a + e.p, 0);
        r = { verdict: 'kill', vp: Math.min(5, each * Math.max(1, Math.round(exp))), p: any, why: `${each} VP per unit${id === 'no-prisoners' ? '' : ' that started the turn on an objective'}: ${names(el.map(e => `${e.name} ${pct(e.p)}`), 3)}` };
        break;
      }
      case 'a-tempting-target': {
        const el = swing.filter(o => o.cls !== 'home' && theirCtl(o));
        r = { verdict: 'ask', vp: 5, why: el.length ? `the objective you picked for it: they can control ${names(el.map(o => o.label), 3)}` : 'they cannot control an objective in No Man’s Land this turn' };
        if (!el.length) { r.verdict = 'no'; r.vp = 0; }
        break;
      }
      case 'beacon': {
        const outT = R().filter(f => f.now.outsideTerritory).length, outD = R().filter(f => f.now.outsideDZ).length;
        r = outD ? { verdict: 'ask', vp: outT ? 5 : 3, why: `their beacon unit: ${outT} of their units are outside their territory now (5 VP), ${outD - outT} more outside their deployment zone (3 VP)` }
          : { verdict: 'no', vp: 0, why: 'none of their units is outside their deployment zone' };
        break;
      }
      case 'behind-enemy-lines': {
        const n = R().filter(f => f.canEnemyDZ).length, nowN = R().filter(f => f.now.inEnemyDZ).length;
        r = n ? { verdict: 'yes', vp: Math.min(5, 3 * n), units: c.theirs.filter((u, i) => R()[i].canEnemyDZ).map(u => u.key), why: `${n} unit${n > 1 ? 's' : ''} can be wholly within your deployment zone (${nowN} there now): ${names(c.theirs.filter((u, i) => R()[i].canEnemyDZ).map(u => u.name))}` }
          : { verdict: 'no', vp: 0, why: 'none of their units can get wholly within your deployment zone with a normal move' };
        break;
      }
      case 'burden-of-trust': {
        const n = swing.filter(o => o.holder === 'them').length;
        r = n ? { verdict: 'now', vp: Math.min(5, 2 * n), why: `they control ${n} objective${n > 1 ? 's' : ''} now: 2 VP each one they still control with its guard in range` } : { verdict: 'no', vp: 0, why: 'they control no objective now' };
        break;
      }
      case 'centre-ground': {
        const can = R().some(f => f.centre3), my3 = myF.some(f => f.centre3), my6 = myF.some(f => f.centre6);
        r = !can ? { verdict: 'no', vp: 0, why: 'none of their units can get within 3" of the centre' }
          : my3 ? { verdict: 'kill', vp: 3, p: null, why: 'they can reach the centre, but you have a unit within 3" of it: they must destroy or move it' }
            : { verdict: 'yes', vp: my6 ? 3 : 5, units: c.theirs.filter((u, i) => R()[i].centre3).map(u => u.key), why: my6 ? 'they can reach the centre; your unit within 6" of it holds them to 3 VP' : 'they can reach the centre and you have no unit within 6" of it' };
        break;
      }
      case 'cleanse': {
        const k = controllable(swing, swing.filter(o => !(o.cls === 'home' && o.side === Y)).map(o => o.id));
        r = k.n ? { verdict: 'yes', vp: k.n >= 2 ? 5 : 2, units: Object.values(k.picks).flat(), action: true, why: `an action on ${k.n} objective${k.n > 1 ? 's' : ''} they can control outside their home (${names(k.ids.map(i => byId.get(i).label), 3)}); those units do not shoot` }
          : { verdict: 'no', vp: 0, why: 'they cannot control an objective outside their home this turn' };
        break;
      }
      case 'defend-stronghold': {
        const home = swing.find(o => o.cls === 'home' && o.side === Y);
        const inDZ = myF.some(f => f.inEnemyDZany);
        r = c.round < 2 ? { verdict: 'no', vp: 0, why: 'not scored in battle round 1' }
          : home?.holder === 'them' ? { verdict: 'now', vp: inDZ ? 3 : 5, why: inDZ ? 'they control their home objective; your unit in their deployment zone holds them to 3 VP' : 'they control their home objective and you have no unit in their deployment zone' }
            : { verdict: 'no', vp: 0, why: 'they do not control their home objective now' };
        break;
      }
      case 'display-of-might': {
        const theirsN = R().filter(f => f.whollyNML).length, mineN = myF.filter(f => f.whollyNML).length;
        r = theirsN > mineN ? { verdict: 'yes', vp: 2, why: `${theirsN} of their units can be wholly in No Man’s Land against your ${mineN} (2 VP at the end of their turn, 5 VP if it still holds at the end of yours)` }
          : { verdict: 'kill', vp: 2, p: null, why: `they can have ${theirsN} units wholly in No Man’s Land, you have ${mineN}: they must destroy ${mineN - theirsN + 1} of yours there` };
        if (!theirsN) r = { verdict: 'no', vp: 0, why: 'none of their units can be wholly in No Man’s Land' };
        break;
      }
      case 'engage-on-all-fronts': {
        const q = maxQuarters(R().map(f => [...f.quarters]));
        r = q >= 3 ? { verdict: 'yes', vp: q >= 4 ? 5 : 3, why: `they can have units wholly in ${q} table quarters` } : { verdict: 'no', vp: 0, why: `they can be wholly in ${q} table quarter${q === 1 ? '' : 's'} at most (three are needed)` };
        break;
      }
      case 'forward-position': {
        const myHome = swing.find(o => o.cls === 'home' && o.side === X), exps = swing.filter(o => o.cls === 'exp');
        const both = exps.length >= 2 && controllable(swing, exps.map(o => o.id)).n >= 2;
        r = myHome && theirCtl(myHome) ? { verdict: 'yes', vp: 5, why: 'they can control your home objective' }
          : both ? { verdict: 'yes', vp: 5, why: 'they can control both expansion objectives' } : { verdict: 'no', vp: 0, why: 'they can control neither your home objective nor both expansion objectives' };
        break;
      }
      case 'outflank': {
        const flank = R().some(f => f.flankEdges.size > 0);
        const opposite = R().some((a, i) => [...a.flankEdges].some(e => R().some((b, j) => i !== j && b.edges.has(OPP[e]))));
        const fl = c.theirs.filter((u, i) => R()[i].flankEdges.size > 0).map(u => u.key);
        r = opposite ? { verdict: 'yes', vp: 5, why: 'they can have units within 6" of opposite battlefield edges, one of them outside their territory' }
          : flank ? { verdict: 'yes', vp: 3, units: fl, why: 'a unit of theirs can be within 6" of a battlefield edge outside their territory' } : { verdict: 'no', vp: 0, why: 'none of their units can be near a battlefield edge outside their territory' };
        break;
      }
      case 'plunder': {
        const el = c.theirs.filter((u, i) => R()[i].terrainOutside);
        r = el.length ? { verdict: 'yes', vp: 5, units: el.map(u => u.key), action: true, why: `an action in a terrain area outside their territory: ${names(el.map(u => u.name))} can be in one (that unit does not shoot)` } : { verdict: 'no', vp: 0, why: 'none of their units can be in a terrain area outside their territory' };
        break;
      }
      case 'secure-no-mans-land': {
        const k = controllable(swing, swing.filter(o => o.cls !== 'home').map(o => o.id));
        r = k.n >= 2 ? { verdict: 'yes', vp: 5, units: k.n === 2 ? Object.values(k.picks).flat() : [], why: `they can control ${k.n} objectives in No Man’s Land (${names(k.ids.map(i => byId.get(i).label), 3)})` } : { verdict: 'no', vp: 0, why: `they can control ${k.n} objective${k.n === 1 ? '' : 's'} in No Man’s Land (two are needed)` };
        break;
      }
      default: r = { verdict: 'ask', vp: card.max ?? 5, why: 'not worked out for this card' };
    }
    out.push({ id, name: card.name, when: card.timing === 'opp' ? 'mine' : 'theirs', max: card.max ?? 5, p: null, ...r });
  }
  const order = { yes: 0, now: 1, kill: 2, ask: 3, no: 4 };
  return out.sort((a, b) => order[a.verdict] - order[b.verdict] || b.vp - a.vp);
}

/**
 * The whole picture for the card on the Board.
 * in: { me, mine, theirs (units on the battlefield), pair, geo: { zones, territories, pieces, objectives },
 *       objs (objectives with cls / side / label), hand (their card ids), round }
 * -> { threats, swing, cards, vpAtStake (VP of the cards they can score by moving alone) }
 */
export function nextTurn(c) {
  const pieces = c.geo?.pieces ?? null, opp = c.me === 'A' ? 'B' : 'A';
  const theirRound = c.theirRound ?? c.round ?? 1, arrive = theirRound >= 2 && theirRound <= 3;
  const reserves = arrive ? c.reserves?.theirs ?? [] : [];
  const theirs = [...c.theirs, ...(c.riders?.theirs ?? [])];
  const threats = turnThreats(c.mine, theirs, c.pair, { pieces, reserves });
  const risk = Object.fromEntries(threats.map(t => [t.key, t.likely]));
  const swing = objectiveSwing(c.mine, theirs, c.objs ?? [], pieces ?? [], { me: c.me, risk, secured: c.secured ?? {}, reserves, round: theirRound, enemyZone: c.geo?.zones?.[c.me] ?? null });
  const cards = cardOutlook({ hand: c.hand ?? [], round: theirRound, me: c.me, mine: c.mine, theirs: c.theirs, threats, swing, geo: c.geo });
  // what I can answer with in their turn (core stratagems, by the CP I have)
  const answers = [], myCp = c.cp?.me ?? null, can = (n) => myCp == null || myCp >= n;
  const sh = (u) => (u.total > 0 && u.left != null ? Math.max(0, Math.min(1, u.left / u.total)) : 1);
  if (can(1)) {
    // (15.08) Fire Overwatch on a unit of theirs that moves onto an objective, by the unit of mine that hurts it most
    let top = null;
    for (const o of swing) if (o.verdict === 'lose' || o.verdict === 'take' || o.verdict === 'contest') for (const m of o.movers.filter(x => x.via === 'move')) for (const u of c.mine) {
      const t = theirs.find(x => x.key === m.key), pr = c.pair?.[u.key]?.[m.key];
      const mu = (pr?.sMu ?? 0) * sh(u) * SNAP_SHARE;
      if (!t || !(mu > 0) || engagedWith(u, c.theirs).length || unitGap(u, { x: o.x, y: o.y, models: [{ dx: 0, dy: 0, fp: { r: 0 } }] }) > OVERWATCH_RANGE + OBJECTIVE_RANGE) continue;
      if (!top || mu / (pr.W || 1) > top.frac) top = { u, t, o, mu, frac: mu / (pr.W || 1) };
    }
    if (top && top.mu >= 0.3) answers.push({ kind: 'overwatch', cp: 1, unit: top.u.key, on: top.t.key, text: `Fire Overwatch (1 CP): ${top.u.name} snap-shoots ${top.t.name} when it moves onto ${top.o.label} (hits on 6s only: about ${top.mu.toFixed(1)} wounds)` });
    // (15.11) Heroic Intervention: an unengaged unit of mine within 12" of one that is likely charged
    for (const t of threats) {
      const ch = t.by.find(b => b.charge >= 0.3 && !b.engaged);
      const tu = c.mine.find(u => u.key === t.key);
      const el = ch && tu ? c.mine.filter(u => u.key !== t.key && u.melee && unitGap(u, tu) <= HEROIC_RANGE - ENGAGEMENT && !engagedWith(u, c.theirs).length && !(isVM(u) && !(u.keywords ?? []).some(k => /^(CHARACTER|WALKER)$/i.test(k)))) : [];
      if (el.length) { answers.push({ kind: 'heroic', cp: 1, unit: el[0].key, on: ch.key, text: `Heroic Intervention (1 CP): ${el[0].name} charges ${ch.name} if it charges ${t.name}` }); break; }
    }
    if (arrive && (c.reserves?.mine ?? []).length) answers.push({ kind: 'rapid-ingress', cp: 1, text: `Rapid Ingress (1 CP): ${names((c.reserves.mine).map(r => r.name))} can arrive at the end of their Movement phase, more than 8" from their units` });
  }
  if (can(2) && threats.some(t => t.by.some(b => b.charge >= 0.3 || b.engaged))) answers.push({ kind: 'counteroffensive', cp: 2, text: 'Counteroffensive (2 CP): after one of their units has fought, a unit of yours that can fight does so next' });
  return { threats, swing, cards, answers, theirRound, vpAtStake: cards.filter(x => x.verdict === 'yes').reduce((a, x) => a + x.vp, 0) };
}

// ---------------------------------------------------------------------------
// "My turn": the same measurements from my side, turned into one suggestion per unit

/** Points a victory point is counted as when a kill is weighed against a card (2,000 points to about 50 VP of a game). */
export const VP_POINTS = 40;

const SWAP = { they: 'you', their: 'your', theirs: 'yours', them: 'you', you: 'they', your: 'their', yours: 'theirs' };
/** A sentence written about "them" (cardOutlook) said about me instead. */
export function myVoice(text) {
  return String(text ?? '').replace(/\b(they|theirs|their|them|yours|your|you)\b/gi, (w) => {
    const r = SWAP[w.toLowerCase()];
    return w[0] === w[0].toUpperCase() ? r[0].toUpperCase() + r.slice(1) : r;
  });
}

/**
 * Who should attack what: one target per unit of mine, chosen pair by pair for the most added value (the
 * target's points x the chance it is destroyed, plus what its death is worth: bonus[targetKey] in points).
 * hits: turnThreats(theirs, mine) - for each of THEIR units, which of mine reach it and the wounds they remove.
 * opts.pointsFactor: what a unit's points still count for (1 early in the game, 0 when it will not act again);
 * opts.halfWorth: { [targetKey]: points } - what it is worth to leave that unit at or below half-strength and
 * have it fail its battle-shock roll (08.03 / 01.07: no OC); opts.why: { [targetKey]: [reason] }.
 * -> [{ key, name, points, p (P destroyed by the units sent), half (P it ends at or below half-strength), shockFail,
 *       by: [{ key, name, shoot, charge }], value, why }], best first
 */
export function killPlan(hits, bonus = {}, { pointsFactor = 1, halfWorth = {}, why = {} } = {}) {
  const worth = (t) => Math.max(1, t.points ?? 1) * Math.max(0.02, pointsFactor) + (bonus[t.key] ?? 0);
  const sent = new Map(hits.map(t => [t.key, []]));
  const free = new Set(hits.flatMap(t => t.by.map(b => b.key)));
  const pOf = (t, list) => killChance(list.map(b => b.part), t.wounds);
  const halfOf = (t, list) => (t.isHalf ? 1 : !list.length ? 0 : t.halfWounds > 0 ? Math.max(pOf(t, list), killChance(list.map(b => ({ mu: b.part.mu, v: b.part.v })), t.halfWounds)) : pOf(t, list));
  const valueOf = (t, list) => { const p = pOf(t, list); return p * worth(t) + (t.isHalf ? 0 : Math.max(0, halfOf(t, list) - p) * (t.shockFail ?? 0) * (halfWorth[t.key] ?? 0)); };
  for (;;) {
    let top = null;
    for (const t of hits) {
      const cur = sent.get(t.key);
      if (pOf(t, cur) >= 0.995) continue;
      const v0 = valueOf(t, cur);
      for (const b of t.by) {
        if (!free.has(b.key)) continue;
        const gain = valueOf(t, [...cur, b]) - v0;
        if (gain > (top?.gain ?? 1e-6)) top = { t, b, gain };
      }
    }
    if (!top) break;
    sent.get(top.t.key).push(top.b);
    free.delete(top.b.key);
  }
  // a unit that adds nothing anywhere still shoots: at the target it hurts most
  for (const k of free) {
    let top = null;
    for (const t of hits) { const b = t.by.find(x => x.key === k); if (b && b.mu > (top?.b.mu ?? 0)) top = { t, b }; }
    if (top) sent.get(top.t.key).push(top.b);
  }
  return hits.filter(t => sent.get(t.key).length).map(t => {
    const by = sent.get(t.key), p = pOf(t, by);
    return { key: t.key, name: t.name, points: t.points, p, half: halfOf(t, by), isHalf: !!t.isHalf, shockFail: t.shockFail ?? 0, ld: t.ld ?? null,
      by: by.map(b => ({ key: b.key, name: b.name, shoot: b.shoot, charge: b.charge, engaged: b.engaged, mu: b.mu, ...(b.reserve ? { reserve: true } : {}) })), value: valueOf(t, by), why: why[t.key] ?? [] };
  }).sort((a, b) => b.value - a.value);
}

/** Where a unit of mine can stand, within its Move, so that none of these units can arrive in range of the objective (20.04 / 24.09), or null. */
export function screenSpot(u, o, mine, reserves, pieces, { round = 2, enemyZone = null, step = 2 } = {}) {
  const M = u.moveLeft ?? u.move ?? 6;
  const others = mine.filter(x => x.key !== u.key);
  const shut = (x, y) => reserves.every(r => !arrivalSpot(o, r, [...others, { ...u, x, y }], pieces, { round, enemyZone }));
  let best = null;
  for (let dx = -Math.floor(M / step) * step; dx <= M; dx += step) for (let dy = -Math.floor(M / step) * step; dy <= M; dy += step) {
    const d = Math.hypot(dx, dy);
    if (d > M + 1e-9 || (best && d >= best.dist)) continue;
    const x = u.x + dx, y = u.y + dy;
    if (abs({ ...u, x, y }).some(m => m.x - m.r < 0 || m.y - m.r < 0 || m.x + m.r > W || m.y + m.r > H)) continue;
    if (shut(x, y)) best = { x, y, dist: d };
  }
  return best;
}

/**
 * My turn, from the table as it stands: one consistent action per unit - where it goes, then what it can still
 * attack from there.
 * in: as nextTurn, with hand = MY cards and risk = { [myUnitKey]: P(destroyed in their next turn where it stands) }; and,
 *   all optional: theirHand (their card ids), threats (nextTurn's, for their kill cards), cp: { me, them },
 *   reserves: { mine, theirs } (units not on the table: { key, name, oc, ranges, melee, deepStrike, base, points }),
 *   secured: { [objectiveId]: side }, theirTurnsLeft (their turns still to come; 0 = this is the last turn of the
 *   battle), theirRound (the battle round of their next turn).
 * -> { units: [{ key, name, risk, job: { kind: 'take' | 'reinforce' | 'hold' | 'screen' | 'card' | 'arrive' | 'none', obj, label,
 *               card, note, via, x, y, dist }, attack: { key, name, p, how, with, back (P it is destroyed when the target
 *               fights back) } | null, shock (P it fails a battle-shock roll at half-strength), hide: { loud, quiet } }],
 *      kills (killPlan), swing (objectives from my side: 'lose' / 'take' = I can take it), danger (the same objectives
 *      in their next turn), cards (mine), theirCards, warnings: [{ kind, cp, text }] (what they can answer with), vp }
 * Order: the objectives decide where a unit goes (keep what I hold with the OC it needs, take what I can, add OC
 * where they can take one from me, shut their reserves out); then the targets are chosen from where each unit
 * ends: a unit that stays on an objective shoots from it and only charges what stands next to that objective, a
 * unit that Falls Back or starts an action does not attack (09.07, 16.01).
 */
export function myTurn(c) {
  const me = c.me, opp = me === 'A' ? 'B' : 'A';
  const pieces = c.geo?.pieces ?? [], round = c.round ?? 1, cp = c.cp ?? {};
  const turnsLeft = c.theirTurnsLeft ?? Math.max(0, 5 - round + 0.5), last = turnsLeft <= 0;
  const theirRound = c.theirRound ?? round;
  const arriveNow = round >= 2 && round <= 3, arriveNext = theirRound >= 2 && theirRound <= 3;
  const myRes = arriveNow ? c.reserves?.mine ?? [] : [], theirRes = arriveNext ? c.reserves?.theirs ?? [] : [];
  const cache = new Map();
  // (units inside a transport: measured from it, 18.04 - they get out within 3" and then move)
  const all = [...c.mine, ...(c.riders?.mine ?? [])], theirAll = [...c.theirs, ...(c.riders?.theirs ?? [])];
  const hits0 = turnThreats(c.theirs, all, c.pair, { pieces, strictSight: true, cache });
  const hitRisk = Object.fromEntries(hits0.map(t => [t.key, t.likely]));
  // the objectives seen from their side: "mine" there = their OC, movers = my units
  const swing = objectiveSwing(c.theirs, all, c.objs ?? [], pieces, { me: opp, risk: hitRisk, secured: c.secured ?? {}, reserves: myRes, round, enemyZone: c.geo?.zones?.[opp] ?? null });
  // ... and what they can do to the same objectives in their next turn
  const danger = objectiveSwing(c.mine, theirAll, c.objs ?? [], pieces, { me, secured: c.secured ?? {}, reserves: theirRes, round: theirRound, enemyZone: c.geo?.zones?.[me] ?? null });
  const dOf = new Map(danger.map(o => [o.id, o]));
  const cards = cardOutlook({ hand: c.hand ?? [], round, me: opp, mine: c.theirs, theirs: c.mine, threats: hits0, swing, geo: c.geo })
    .map(x => ({ ...x, why: myVoice(x.why), offTurn: x.when === 'mine', when: x.when === 'mine' ? 'theirs' : 'mine' }));
  const theirCards = (c.theirHand ?? []).length && c.geo ? cardOutlook({ hand: c.theirHand, round: theirRound, me, mine: c.mine, theirs: c.theirs, threats: c.threats ?? [], swing: danger, geo: c.geo }) : [];
  const has = (id) => (c.hand ?? []).includes(id);
  const byKey = new Map(all.map(u => [u.key, u]));

  // ---- where each unit goes
  const jobs = new Map();
  const ocAfter = new Map(swing.map(o => [o.id, 0]));       // my OC on each objective with the jobs given so far
  const give = (k, job) => { jobs.set(k, job); if (job.obj && ['hold', 'take', 'reinforce'].includes(job.kind)) ocAfter.set(job.obj, (ocAfter.get(job.obj) ?? 0) + (job.oc ?? 0)); };
  // what they can bring to an objective of mine next turn (nothing, in the last turn of the battle)
  const threatTo_ = (d) => (last || !d ? 0 : d.maxAll);
  for (const o of swing) {
    if (o.verdict !== 'theirs') continue;
    const d = dOf.get(o.id), need = Math.max(o.mine, threatTo_(d));
    const mineThere = o.there.filter(t => t.oc > 0).sort((a, b) => b.oc - a.oc);
    // (14.03) a secured objective nothing of theirs can reach needs nobody on it
    if (d?.secured === 'me' && need <= 0) { for (const t of mineThere) if (!jobs.has(t.key)) jobs.set(t.key, { kind: 'none', freed: o.label }); continue; }
    let oc = 0;
    for (const t of mineThere) {
      if (jobs.has(t.key)) continue;
      // one unit always stays; more only while what they can bring is not beaten
      if (oc > 0 && oc > need) { jobs.set(t.key, { kind: 'none', freed: o.label }); continue; }
      const sure = !last && d && d.max >= o.theirs && (d.verdict === 'lose' || d.verdict === 'contest');
      give(t.key, { kind: 'hold', obj: o.id, label: o.label, oc: t.oc, note: `${o.theirs} OC against ${o.mine}${sure ? `; they can bring ${d.max}` : ''}` });
      oc += t.oc;
    }
  }
  // a tie: the units of mine on it stay (nobody controls it, 14.02)
  for (const o of swing) if (o.holder == null && o.theirs > 0 && o.mine > 0) for (const t of o.there) if (t.oc > 0 && !jobs.has(t.key)) give(t.key, { kind: 'hold', obj: o.id, label: o.label, oc: t.oc, note: `tied at ${o.theirs} OC each: nobody controls it` });
  // take what I can, a unit to one objective (the easiest first; an objective they hold before an empty one:
  // taking it also takes it from them)
  for (const verdict of ['lose', 'take']) {
    const open = swing.filter(o => o.verdict === verdict);
    const isFree = (k) => !jobs.has(k) || (jobs.get(k).kind === 'hold' && open.some(o => o.id === jobs.get(k).obj));
    const freeSwing = open.map(o => ({ ...o, there: o.there.filter(t => isFree(t.key)), movers: o.movers.filter(m => isFree(m.key) && byKey.has(m.key)) }));
    const got = controllable(freeSwing, open.map(o => o.id));
    for (const o of open) for (const k of got.picks[o.id] ?? []) {
      const on = o.there.find(t => t.key === k), m = o.movers.find(x => x.key === k);
      if (jobs.has(k) && jobs.get(k).kind !== 'hold') continue;
      if (jobs.has(k)) { jobs.get(k).note = 'with the units sent it is yours'; continue; }
      give(k, on ? { kind: 'hold', obj: o.id, label: o.label, oc: on.full ?? on.oc, note: 'with the units sent it is yours' }
        : { kind: 'take', obj: o.id, label: o.label, oc: m?.oc ?? 0, via: m?.via ?? 'move', note: `${o.mine > 0 ? `they have ${o.mine} OC there` : 'nobody holds it'}${m?.via === 'fallback' ? '; it must Fall Back to get there: no shooting or charge after' : ''}` });
    }
  }
  // an objective of mine they can take next turn: more OC onto it from the units still free
  if (!last) for (const tier of [['lose', 'contest'], ['charge', 'advance']]) for (const o of swing) {
    const d = dOf.get(o.id);
    if (!d || !tier.includes(d.verdict) || o.verdict !== 'theirs') continue;
    const need = d.verdict === 'charge' ? d.maxCharge : d.verdict === 'advance' ? d.maxAdvance : d.max;
    for (const m of o.movers) {
      if ((ocAfter.get(o.id) ?? 0) > need) break;
      if (m.via !== 'move' || jobs.has(m.key) || !byKey.has(m.key)) continue;
      give(m.key, { kind: 'reinforce', obj: o.id, label: o.label, oc: m.oc, via: 'move', note: `they can bring ${need} OC ${d.verdict === 'charge' ? 'with a charge' : d.verdict === 'advance' ? 'with an Advance' : 'next turn'}, you have ${o.theirs}` });
    }
    if ((ocAfter.get(o.id) ?? 0) <= need) for (const t of o.there) { const j = jobs.get(t.key); if (j?.kind === 'hold' && j.obj === o.id && (d.verdict === 'lose' || d.verdict === 'contest')) j.short = need; }
  }
  // their reserves can land on an objective of mine: a free unit that shuts them out (more than 8" from every unit of mine)
  // (my home first, then my side of the table, then the centre)
  const mineFirst = (o) => (o.cls === 'home' && o.side === me ? 0 : o.side === me ? 1 : o.cls === 'central' ? 2 : 3);
  if (!last && theirRes.length) for (const o of [...swing].sort((x, y) => mineFirst(x) - mineFirst(y))) {
    const d = dOf.get(o.id);
    if (!d || d.verdict !== 'reserves' || (o.cls === 'home' && o.side !== me)) continue;
    const landing = theirRes.filter(r => d.movers.some(m => m.key === r.key));
    const near = c.mine.filter(u => !jobs.has(u.key) && unitGap(u, { x: o.x, y: o.y, models: [{ dx: 0, dy: 0, fp: { r: 0 } }] }) <= (u.move ?? 6) + ARRIVE_GAP + OBJECTIVE_RANGE + 2);
    for (const u of near) {
      const at = screenSpot(u, o, c.mine, landing, pieces, { round: theirRound, enemyZone: c.geo?.zones?.[me] ?? null });
      if (at) { jobs.set(u.key, { kind: 'screen', obj: o.id, label: o.label, ...at, note: `${names(landing.map(r => r.name))} can arrive on it from reserves: from here nothing of theirs can be set up in range (more than 8" from your units)` }); break; }
    }
  }
  // then the cards I can score by where a unit stands (the units still free)
  const Y = me;
  const place = (id, at, note, action = false) => {
    const card = cards.find(x => x.id === id && x.verdict === 'yes');
    if (!card) return;
    for (const u of c.mine) {
      if (jobs.has(u.key) && jobs.get(u.key).kind !== 'none') continue;
      if (engagedWith(u, c.theirs).length) continue;
      const f = reachFacts(u, Y, c.geo);
      if (f.at[at]) { jobs.set(u.key, { kind: 'card', card: card.name, label: card.name, note, action, ...f.at[at] }); if (id !== 'behind-enemy-lines') break; }
    }
  };
  if (c.geo) {
    place('behind-enemy-lines', 'canEnemyDZ', 'wholly within their deployment zone');
    place('centre-ground', 'centre3', 'within 3" of the centre');
    place('plunder', 'terrainOutside', 'an action in a terrain area outside your territory (it does not shoot or charge)', true);
    place('outflank', 'flank', 'within 6" of a battlefield edge outside your territory');
  }
  // my reserves: onto an objective they can win, else just "can arrive"
  const resJobs = new Map();
  for (const r of c.reserves?.mine ?? []) {
    if (round < 2) { resJobs.set(r.key, { kind: 'arrive', wait: true, note: 'cannot arrive before battle round 2 (20.03)' }); continue; }
    if (round > 3) continue;
    const o = swing.filter(x => x.verdict !== 'theirs' && x.movers.some(m => m.key === r.key && m.via === 'reserves') && (ocAfter.get(x.id) ?? 0) + (r.oc ?? 0) > x.mine && (ocAfter.get(x.id) ?? 0) <= x.mine)
      .sort((a, b) => a.mine - b.mine)[0];
    const lastCall = round === 3 ? '; battle round 3 is the last it can arrive in (20.03: destroyed at the end of it)' : '';
    if (o) { const m = o.movers.find(x => x.key === r.key); resJobs.set(r.key, { kind: 'arrive', obj: o.id, label: o.label, oc: r.oc, x: m.x, y: m.y, note: `${r.deepStrike ? 'Deep Strike' : 'from a battlefield edge'}: set up more than 8" from their units, in range of it${lastCall}` }); ocAfter.set(o.id, (ocAfter.get(o.id) ?? 0) + (r.oc ?? 0)); }
    else resJobs.set(r.key, { kind: 'arrive', note: `can arrive this turn${r.deepStrike ? ' by Deep Strike' : ' within 6" of a battlefield edge'}, more than 8" from their units${lastCall}` });
  }

  // ---- what each unit can still attack from where its job leaves it
  const nearObj = (id) => { const o = (c.objs ?? []).find(x => x.id === id); return new Set(o ? c.theirs.filter(t => objectiveGap(t, o, pieces) <= CONSOLIDATE).map(t => t.key) : []); };
  const endOf = (u, j) => {
    if (j.x != null) return { x: j.x, y: j.y, dist: j.dist ?? Math.hypot(j.x - u.x, j.y - u.y) };
    const o = swing.find(x => x.id === j.obj);
    const cd = o ? moveCandidates([u], [{ ...o, movers: [{ key: u.key, via: 'move' }] }], pieces, { max: 1 })[0] : null;
    return cd ? { x: cd.x, y: cd.y, dist: cd.dist } : { x: u.x, y: u.y, dist: 0 };
  };
  const actions = new Set();
  const build = () => all.map(u => {
    const j = jobs.get(u.key) ?? { kind: 'none' };
    const act = actions.has(u.key) || j.action;
    if (j.kind === 'hold') return { ...u, moveLeft: Math.min(u.move ?? 6, OBJECTIVE_RANGE), chargeOnly: nearObj(j.obj), noShoot: act, noCharge: act };
    if (j.kind === 'take' || j.kind === 'reinforce') { const e = endOf(u, j); Object.assign(j, e); return { ...u, x: e.x, y: e.y, moveLeft: 0, movedFar: e.dist > 3, chargeOnly: nearObj(j.obj), noShoot: act || j.via === 'fallback', noCharge: act || j.via === 'fallback' }; }
    if (j.kind === 'screen' || j.kind === 'card') return { ...u, x: j.x, y: j.y, moveLeft: 0, movedFar: (j.dist ?? 0) > 3, noCharge: true, noShoot: !!act };
    return u;
  });
  // what a kill is worth beyond the unit's points (in points: VP_POINTS a victory point), and why
  const bonus = {}, why = {}, halfWorth = {};
  const add = (t, vp, reason) => { if (!(vp > 0)) return; bonus[t.key] = (bonus[t.key] ?? 0) + vp * VP_POINTS; (why[t.key] ??= []).push(reason); };
  for (const t of c.theirs) {
    for (const o of swing) {
      const h = o.holders.find(x => x.key === t.key && x.oc > 0);
      if (!h) continue;
      const flips = o.mine - h.oc < Math.max(o.theirs, ocAfter.get(o.id) ?? 0) || (o.mine - h.oc === 0 && o.holder === 'me');
      add(t, OBJ_VP * (flips ? 1 : 0.5) + (has('overwhelming-force') ? 3 : 0), `holds ${o.label}`);
      if (!t.shocked) halfWorth[t.key] = OBJ_VP * VP_POINTS;
    }
    if (!last) for (const d of danger) {
      if (d.verdict !== 'lose' && d.verdict !== 'contest' && d.verdict !== 'take') continue;
      const bring = [...d.movers.filter(m => m.via === 'move' || m.via === 'fallback'), ...d.there.map(x => ({ key: x.key, oc: x.full }))];
      const m = bring.find(x => x.key === t.key), sum = bring.reduce((a, x) => a + x.oc, 0);
      // only when without it they no longer get there
      if (m && sum - m.oc <= d.mine) add(t, OBJ_VP, `${d.verdict === 'take' ? 'takes' : 'can take'} ${d.label} next turn`);
    }
    for (const x of theirCards) if (x.verdict === 'yes' && x.units?.includes(t.key)) add(t, x.vp / x.units.length, `${x.units.length === 1 ? 'scores' : 'helps score'} their ${x.name}`);
    if (has('assassination') && (t.chars ?? 0) > 0) add(t, 5, 'your Assassination');
    if (has('bring-it-down') && (t.w10 ?? 0) > 0) add(t, 5, 'your Bring It Down');
    if (has('a-grievous-blow') && t.ss13) add(t, 5, 'your A Grievous Blow');
    if (has('no-prisoners')) add(t, 2, 'your No Prisoners');
  }
  const plan = () => killPlan(turnThreats(c.theirs, build(), c.pair, { pieces, strictSight: true, reserves: myRes, cache }), bonus, { pointsFactor: Math.min(1, turnsLeft / 5), halfWorth, why });
  let kills = plan();
  // Cleanse: the action is started by the units on non-home objectives that give up the least shooting (16.01: no shooting or charge)
  if (cards.some(x => x.id === 'cleanse' && x.verdict === 'yes')) {
    const mu = new Map();
    for (const k of kills) for (const b of k.by) mu.set(b.key, (b.charge || b.engaged ? 1e6 : 0) + b.mu);
    const el = [...jobs].filter(([, j]) => ['hold', 'take'].includes(j.kind) && j.via !== 'fallback' && swing.find(o => o.id === j.obj)?.cls !== 'home').sort((a, b) => (mu.get(a[0]) ?? 0) - (mu.get(b[0]) ?? 0));
    const seen = new Set();
    for (const [k, j] of el) { if (seen.size >= 2 || seen.has(j.obj)) continue; seen.add(j.obj); actions.add(k); j.act = 'Cleanse'; }
    if (actions.size) kills = plan();
  }
  // the cards paid per unit destroyed: by the targets of this plan (not by "each unit at its own best target")
  for (const x of cards) {
    if (x.id !== 'no-prisoners' && x.id !== 'overwhelming-force') continue;
    const onObj = (k) => swing.some(o => o.holders.some(h => h.key === k));
    const el = kills.filter(k => k.p >= 0.005 && (x.id === 'no-prisoners' || onObj(k.key)));
    const each = x.id === 'no-prisoners' ? 2 : 3;
    if (!el.length) { Object.assign(x, { verdict: 'no', vp: 0, p: null, why: x.id === 'no-prisoners' ? 'nothing of theirs is in reach to destroy' : 'no unit of theirs on an objective is in reach to destroy' }); continue; }
    const exp = el.reduce((a, k) => a + k.p, 0);
    Object.assign(x, { verdict: 'kill', vp: Math.min(5, each * Math.max(1, Math.round(exp))), p: 1 - el.reduce((a, k) => a * (1 - k.p), 1),
      why: `${each} VP per unit${x.id === 'no-prisoners' ? '' : ' that started the turn on an objective'}: ${names(el.map(k => `${k.name} ${pct(k.p)}`), 3)}` });
  }
  const sh = (u) => (u.total > 0 && u.left != null ? Math.max(0, Math.min(1, u.left / u.total)) : 1);
  const foe = new Map(c.theirs.map(t => [t.key, t]));
  const atk = new Map();
  for (const k of kills) for (const b of k.by) {
    const melee = b.engaged || b.charge > 0;
    // (12.04) what is left of the target fights back
    const back = melee ? (1 - k.p) * (c.pair?.[k.key]?.[b.key]?.fight ?? 0) * sh(foe.get(k.key) ?? {}) : 0;
    atk.set(b.key, { key: k.key, name: k.name, p: k.p, with: k.by.length, how: [b.shoot ? 'shoot' : '', b.engaged ? 'fight' : b.charge ? 'charge' : ''].filter(Boolean).join(' + '), charge: b.engaged ? 0 : b.charge || 0, back,
      ...(b.shoot?.cover ? { cover: true } : {}), ...(b.shoot && b.shoot.share < 0.95 ? { share: b.shoot.share } : {}), ...(b.shoot?.how ? { boost: b.shoot.how } : {}) });
  }
  const after = new Map(build().map(u => [u.key, u]));
  const units = all.map(u => {
    const j0 = jobs.get(u.key) ?? { kind: 'none' }, a = atk.get(u.key) ?? null, au = after.get(u.key);
    const out = { key: u.key, name: u.name, risk: c.risk?.[u.key] ?? 0, job: j0, attack: a, ...(u.embarked ? { embarked: u.embarked } : {}) };
    if (halfStrength(u) && !u.shocked && (u.oc ?? 0) > 0 && shockFail(u.ld) > 0) out.shock = shockFail(u.ld);
    // (13.09) holding its fire keeps it Hidden: seen from 15" only
    if (!last && (u.ranges ?? []).length && pieces.length && canHide(au, pieces) && !(a?.charge > 0)) {
      const loud = turnThreats([au], c.theirs, c.pair, { pieces })[0]?.focus ?? 0;
      if (loud >= 0.1) { const quiet = turnThreats([au], c.theirs, c.pair, { pieces, quiet: new Set([u.key]) })[0]?.focus ?? 0; if (loud - quiet >= 0.1) out.hide = { loud, quiet }; }
    }
    return out;
  });
  for (const r of c.reserves?.mine ?? []) if (resJobs.has(r.key)) units.push({ key: r.key, name: r.name, risk: 0, reserve: true, job: resJobs.get(r.key), attack: resJobs.get(r.key).wait ? null : atk.get(r.key) ?? null });

  // ---- what they can answer with (core stratagems, by the CP they have)
  const warnings = [];
  const theirCp = cp.them ?? null, can = (n) => theirCp == null || theirCp >= n;
  const open = units.filter(u => !u.reserve && !u.embarked && !engagedWith(after.get(u.key), c.theirs).length);
  if (can(1) && open.length) {
    // (15.08 / 15.09) one unengaged unit of theirs snap-shoots a visible, unengaged unit within 24" at the end of my
    // Movement phase, whether it moved or not: the unit of mine it costs most
    let top = null;
    for (const u of open) for (const t of c.theirs) {
      const au = after.get(u.key), mu = (c.pair?.[t.key]?.[u.key]?.sMu ?? 0) * sh(t) * SNAP_SHARE;
      if (!(mu > 0) || unitGap(au, t) > OVERWATCH_RANGE || engagedWith(t, c.mine).length) continue;
      if (!top || mu > top.mu) top = { u, t, mu, W: (c.pair[t.key][u.key].W ?? 0) * sh(byKey.get(u.key)) };
    }
    if (top && top.mu >= 0.3) warnings.push({ kind: 'overwatch', cp: 1, unit: top.u.key, by: top.t.key, mu: top.mu, text: `Fire Overwatch (1 CP): ${top.t.name} can snap-shoot ${top.u.name}${top.u.job.dist > 0 ? ' where its move ends,' : ''} at the end of your Movement phase (hits on 6s only: about ${top.mu.toFixed(1)} of its ${Math.round(top.W)} wounds)` });
  }
  const chargers = units.filter(u => u.attack && (u.attack.charge > 0 || /fight/.test(u.attack.how)));
  if (can(1)) for (const u of chargers.filter(x => x.attack.charge > 0)) {
    // (15.11) an unengaged unit of theirs within 12" charges back at the end of my Charge phase
    const t = foe.get(u.attack.key);
    const el = c.theirs.filter(e => e.key !== t?.key && e.melee && t && unitGap(e, t) <= HEROIC_RANGE - ENGAGEMENT && !engagedWith(e, c.mine).length && !(isVM(e) && !(e.keywords ?? []).some(k => /^(CHARACTER|WALKER)$/i.test(k))));
    if (el.length) { warnings.push({ kind: 'heroic', cp: 1, unit: u.key, by: el[0].key, text: `Heroic Intervention (1 CP): ${names(el.map(e => e.name))} can charge ${u.name} after it charges ${t.name}` }); break; }
  }
  if (can(2) && chargers.length) warnings.push({ kind: 'counteroffensive', cp: 2, text: `Counteroffensive (2 CP): after your first unit has fought, one of theirs that can fight does so before your next (fight with the unit that must not be hit back first)` });
  if (can(1) && round >= 2 && round <= 3 && (c.reserves?.theirs ?? []).length) warnings.push({ kind: 'rapid-ingress', cp: 1, text: `Rapid Ingress (1 CP): ${names(c.reserves.theirs.map(r => r.name))} can arrive at the end of your Movement phase, more than 8" from your units` });

  const rank = { take: 0, reinforce: 0.5, arrive: 1, card: 1, screen: 1.5, hold: 2, none: 3 };
  const rk = (u) => (u.job.kind === 'arrive' && !u.job.obj ? 2.5 : rank[u.job.kind]);
  units.sort((a, b) => rk(a) - rk(b) || (b.attack?.p ?? 0) - (a.attack?.p ?? 0) || b.risk - a.risk);
  return { units, kills, swing, danger, cards, theirCards, warnings, turnsLeft, vp: cards.filter(x => x.verdict === 'yes').reduce((a, x) => a + x.vp, 0) };
}

// ---------------------------------------------------------------------------
// Moves to weigh with the mission forecast (the view runs the forecast; this picks what to try and reads it)

/**
 * The moves worth trying for each of my units: onto each objective a normal move reaches (a straight line,
 * just far enough for a model to be in range), and - for a unit likely to be destroyed where it stands - a
 * normal move back towards my home objective.
 * swing: myTurn().swing (its movers are my units). -> [{ key: `${unitKey}>${what}`, unit, name, kind: 'obj' | 'back',
 *   obj (id), label, x, y (the unit's centre after the move), dist, hosted (the objective is in a terrain area:
 *   a base in that area is in range), via ([[x, y]]: the corners it goes round, for a unit that cannot pass dense
 *   terrain) }], at most `max` (nearest objectives first).
 * With opts.theirs / pair: also kind 'safe' (a unit at risk: the least exposed place within its Move, on its
 * objective when opts.keep names one); with opts.cards ([{ unit, name, label, x, y, dist }]): kind 'card'.
 */
export function moveCandidates(mine, swing, pieces, { risk = {}, home = null, max = 24, theirs = null, pair = null, keep = {}, cards = [] } = {}) {
  const out = [];
  for (const u of mine) {
    const M = u.move ?? 6;
    for (const o of swing) {
      const mv = o.movers.find(m => m.key === u.key && m.via === 'move');
      if (!mv) continue;
      const d = objectiveGap(u, o, pieces);
      let x, y, step, via = null;
      const rt = goesRound(u) ? route(u, o.x, o.y, pieces) : null;
      if (rt && !rt.direct && !rt.blocked) {
        // round the terrain in the way: along that path, just far enough for a model to be in range
        const most = Math.min(M, rt.len);
        for (step = Math.min(most, Math.max(0.5, d)); ; step = Math.min(most, step + 0.5)) {
          ({ x, y } = along(rt.pts, step));
          if (objectiveGap({ ...u, x, y }, o, pieces) <= 0 || step >= most - 1e-9) break;
        }
        if (!(objectiveGap({ ...u, x, y }, o, pieces) <= 0)) continue;
        via = rt.pts.slice(1, -1).filter((q, i) => { let l = 0; for (let k = 1; k <= i + 1; k++) l += Math.hypot(rt.pts[k][0] - rt.pts[k - 1][0], rt.pts[k][1] - rt.pts[k - 1][1]); return l < step; });
      } else {
        // towards the objective, from the model nearest to it
        let near = null;
        for (const m of u.models) { const dd = Math.hypot(u.x + m.dx - o.x, u.y + m.dy - o.y); if (!near || dd < near.dd) near = { dd, m }; }
        const len = Math.hypot(o.x - (u.x + near.m.dx), o.y - (u.y + near.m.dy)) || 1;
        // just far enough for a model to be in range: the gap is to the nearest edge of the objective's area, the line
        // goes towards its marker, so a slanting approach needs a little more than the gap
        const ux = (o.x - (u.x + near.m.dx)) / len, uy = (o.y - (u.y + near.m.dy)) / len, most = Math.min(M, len);
        step = Math.min(most, d + 0.75); x = u.x + ux * step; y = u.y + uy * step;
        while (!(objectiveGap({ ...u, x, y }, o, pieces) <= 0) && step < most - 1e-9) { step = Math.min(most, step + 0.5); x = u.x + ux * step; y = u.y + uy * step; }
        if (!(objectiveGap({ ...u, x, y }, o, pieces) <= 0)) continue;     // the straight line does not get it in range
      }
      out.push({ key: `${u.key}>${o.id}`, unit: u.key, name: u.name, kind: 'obj', obj: o.id, label: o.label, x, y, dist: step, hosted: (o.host ?? []).length > 0, ...(via?.length ? { via } : {}) });
    }
    if (home && (risk[u.key] ?? 0) >= 0.25) {
      const len = Math.hypot(home.x - u.x, home.y - u.y);
      if (len > 3) { const step = Math.min(M, len - 1); out.push({ key: `${u.key}>back`, unit: u.key, name: u.name, kind: 'back', obj: null, label: 'back towards your home', x: u.x + (home.x - u.x) / len * step, y: u.y + (home.y - u.y) / len * step, dist: step }); }
    }
  }
  // a unit at risk: the place within its Move where the least of theirs reaches it - still in range of the
  // objective it holds (opts.keep[unitKey] = objective), or anywhere for a unit with no objective
  if (theirs?.length) for (const u of mine) {
    if ((risk[u.key] ?? 0) < 0.25 || engagedWith(u, theirs).length) continue;
    const sp = safeSpot(u, theirs, pair, pieces, keep[u.key] ?? null);
    if (sp) out.push({ key: `${u.key}>safe`, unit: u.key, name: u.name, kind: 'safe', obj: keep[u.key]?.id ?? null, label: keep[u.key] ? `out of reach, still on ${keep[u.key].label}` : 'out of their reach', x: sp.x, y: sp.y, dist: sp.dist, riskThere: sp.risk, riskHere: sp.here });
  }
  // a card scored by where a unit stands (myTurn's card jobs: the nearest place that does it)
  for (const j of cards) if (j.dist > 0.05) out.push({ key: `${j.unit}>card`, unit: j.unit, name: j.name, kind: 'card', obj: null, label: j.label, x: j.x, y: j.y, dist: j.dist });
  const order = (k) => (k === 'back' ? 2 : k === 'safe' || k === 'card' ? 1 : 0);
  return out.sort((a, b) => order(a.kind) - order(b.kind) || a.dist - b.dist).slice(0, max);
}

/**
 * The place within a unit's Move where it is least likely to be destroyed in their next turn (everything of theirs
 * that reaches it attacks it), if that is at least 15 points better than where it stands. keep: the objective it
 * must stay in range of (or null). -> { x, y, dist, risk, here } | null
 */
export function safeSpot(u, theirs, pair, pieces, keep = null, { step = 2, min = 0.15 } = {}) {
  const at = (x, y) => turnThreats([{ ...u, x, y }], theirs, pair, { pieces })[0]?.focus ?? 0;
  const here = at(u.x, u.y), M = u.move ?? 6;
  if (here < min) return null;
  let best = null;
  for (let dx = -Math.floor(M / step) * step; dx <= M; dx += step) for (let dy = -Math.floor(M / step) * step; dy <= M; dy += step) {
    const d = Math.hypot(dx, dy);
    if ((dx === 0 && dy === 0) || d > M + 1e-9) continue;
    const x = u.x + dx, y = u.y + dy, moved = { ...u, x, y };
    if (abs(moved).some(m => m.x - m.r < 0 || m.y - m.r < 0 || m.x + m.r > W || m.y + m.r > H)) continue;
    if (keep && !(objectiveGap(moved, keep, pieces) <= 0)) continue;
    if (engagedWith(moved, theirs).length) continue;
    const r = at(x, y);
    if (!best || r < best.risk - 1e-9 || (Math.abs(r - best.risk) <= 1e-9 && d < best.dist)) best = { x, y, dist: d, risk: r };
  }
  return best && here - best.risk >= min ? { ...best, here } : null;
}

/**
 * How exposed a unit of mine is after a suggested move: their next turn worked out again with that unit at the
 * end of the move (every other unit where it stands). -> { likely, focus } (as turnThreats)
 */
export function riskAfterMove(mine, theirs, pair, move, pieces = null) {
  const moved = mine.map(u => (u.key === move.unit ? { ...u, x: move.x, y: move.y } : u));
  const row = turnThreats(moved, theirs, pair, { pieces }).find(t => t.key === move.unit);
  return { likely: row?.likely ?? 0, focus: row?.focus ?? 0 };
}

/** What a forecast result is worth to player X: { win (P), vp (X's mean VP minus the other player's) }. */
export function worthOf(result, X) {
  const Y = X === 'A' ? 'B' : 'A';
  return { win: result?.[`pWin${X}`] ?? 0, vp: (result?.[X]?.mean ?? 0) - (result?.[Y]?.mean ?? 0) };
}
/**
 * A move counts as better than standing still from this many VP of margin: about 3.4x the noise of a move's VP
 * gain between two runs of 1,500 games. Measured again for 1.153.0 with the other player's reply played in
 * (boardview moveNoise: 5 moves x 8 seeds on a live table): SD 0.59 VP, 0.69 at most; so a move with no worth
 * passes about 3 times in 10,000, under 1 in 100 over the 24 moves tried at most. It was 3 while the table counted
 * for one round only (noise 0.95 VP). Most cards and objectives are worth 2 to 5 VP: a higher bar hid moves worth making.
 */
export const MOVE_MIN_VP = 2;
/**
 * The best move of each unit, from the forecasts of each candidate alone.
 * results: { [candidateKey]: forecast result }. -> [{ ...candidate, dVp, dWin }], the biggest gain first;
 * only moves that gain at least MOVE_MIN_VP.
 */
export function bestMoves(cands, base, results, X) {
  const b = worthOf(base, X), top = new Map();
  for (const c of cands) {
    if (!results[c.key]) continue;
    const w = worthOf(results[c.key], X), row = { ...c, dVp: w.vp - b.vp, dWin: w.win - b.win };
    if (row.dVp >= MOVE_MIN_VP && row.dVp > (top.get(c.unit)?.dVp ?? -Infinity)) top.set(c.unit, row);
  }
  return [...top.values()].sort((x, y) => y.dVp - x.dVp);
}
/**
 * Which of those moves to make together: results[i] is the forecast with moves[0..i] all made; a move stays
 * only if adding it gains at least MOVE_MIN_VP over the moves kept before it. -> { moves: kept, vp, win } (the last kept forecast)
 */
export function keepMoves(moves, base, stacked, X) {
  let cur = worthOf(base, X);
  const kept = [];
  for (const [i, m] of moves.entries()) {
    if (!stacked[i]) continue;
    const w = worthOf(stacked[i], X);
    if (w.vp - cur.vp >= MOVE_MIN_VP || i === 0) { kept.push({ ...m, addVp: w.vp - cur.vp }); cur = w; }
  }
  return { moves: kept, ...cur };
}
