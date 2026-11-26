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
import { threatTo, unitSight } from './sight.mjs';
import { detectRange, unitFacts, ocInRange, inRange } from './planeval.mjs';
import { SECONDARIES } from './missions-11e.mjs';

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

/** Up to 6 of a unit's models for a sight check: its outermost ones, the first and the middle one. */
function outer(u) {
  const ms = u.models;
  if (ms.length <= 6) return u;
  const by = (f) => ms.reduce((a, m) => (f(m) < f(a) ? m : a));
  return { ...u, models: [...new Set([by(m => m.dx), by(m => -m.dx), by(m => m.dy), by(m => -m.dy), ms[0], ms[Math.floor(ms.length / 2)]])] };
}
const share = (u) => (u.total > 0 && u.left != null ? Math.max(0, Math.min(1, u.left / u.total)) : 1);

/**
 * What each of their units can do to each of mine in their next turn.
 * pair[atkKey][defKey] = { shoot, fight (P destroyed alone), sMu, sSd, fMu, fSd, W } (full-strength units);
 * models lost since scale it: the attacker's damage by its models left, the target's wounds by its models left.
 * opts.pieces: the layout's terrain (who is Hidden / a Lone Operative, and who has a sight line now).
 * -> [{ key, name, points, wounds, focus (P destroyed if everything in reach attacks it), likely (P destroyed
 *       when each of their units attacks the target it is worth most against), by: [{ key, name, shoot: { range,
 *       now (in range and in sight without moving) } | null, charge (P), engaged, mu, p }] }], most at risk first
 */
export function turnThreats(mine, theirs, pair, { pieces = null } = {}) {
  const rows = mine.map(t => ({ key: t.key, name: t.name, points: t.points ?? 0, wounds: 0, focus: 0, likely: 0, by: [], parts: [], scaled: false }));
  const best = new Map();   // attacker key -> { row, value, part }
  for (const [ti, t] of mine.entries()) {
    const row = rows[ti];
    const ts = share(t);
    for (const a of theirs) {
      const pr = pair?.[a.key]?.[t.key];
      const th = threatTo(a, t, { move: a.move ?? 6, ranges: a.ranges ?? [], melee: !!a.melee, detect: detectRange(t, pieces) });
      const ch = th.charge ?? 0;
      if (!th.shoot && ch < 0.03) continue;
      const as = share(a);
      const Wt = (pr?.W ?? 0) * ts;
      if (Wt > 0) row.wounds = Wt;
      const sMu = th.shoot ? (pr?.sMu ?? 0) * as : 0, fMu = (pr?.fMu ?? 0) * as;
      const mu = sMu + ch * fMu;
      const v = (th.shoot ? ((pr?.sSd ?? 0) * as) ** 2 : 0) + ch * ((pr?.fSd ?? 0) * as) ** 2 + ch * (1 - ch) * fMu ** 2;
      const scaled = as < 1 || ts < 1;
      // on its own: the calculator's figure at full strength, else from the wounds it removes
      const p = !pr || !(Wt > 0) ? 0 : scaled ? killChance([{ mu, v }], Wt)
        : 1 - (1 - (th.shoot ? pr.shoot ?? 0 : 0)) * (1 - ch * (pr.fight ?? 0));
      let now = false;
      if (th.shoot && pieces && th.gap <= th.shoot.range) {
        const s = unitSight(outer(a), outer(t), pieces, { range: th.shoot.range });
        now = s.attackersSeeing > 0 && s.targetSeen > 0 && !s.hidden;
      }
      const part = { mu, v, p: scaled ? undefined : p };
      row.by.push({ key: a.key, name: a.name, shoot: th.shoot ? { range: th.shoot.range, now } : null, charge: ch >= 0.03 ? ch : 0, engaged: th.engaged, mu, p, part });
      row.parts.push(part);
      const value = p * Math.max(1, t.points ?? 1);
      if (value > (best.get(a.key)?.value ?? 0)) best.set(a.key, { row, value, part });
    }
  }
  const likelyParts = new Map();
  for (const { row, part } of best.values()) { if (!likelyParts.has(row)) likelyParts.set(row, []); likelyParts.get(row).push(part); }
  for (const row of rows) {
    row.focus = killChance(row.parts, row.wounds);
    row.likely = killChance(likelyParts.get(row) ?? [], row.wounds);
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
 * Each objective: who controls it now, and what they can bring to it in their turn.
 * objs: the layout's objectives with { cls: 'home' | 'central' | 'exp', side, label } (board.objectiveSides);
 * me: my side. risk: { [myUnitKey]: P(destroyed) } (turnThreats' likely) for the units of mine that hold it.
 * A unit of theirs reaches an objective with a normal move (in a straight line) or with an Advance (the D6 it needs).
 * -> [{ id, label, cls, side, mine, theirs (OC in range now), holder: 'me' | 'them' | null,
 *       holders: [{ key, name, oc, risk }] (mine), there: [{ key, name, oc, full (the whole unit's OC) }] (theirs in range now),
 *       movers: [{ key, name, oc, via: 'move' | 'advance', need (D6), p }],
 *       max (their OC with everything a normal move brings), maxAdvance (with Advances too),
 *       verdict: 'theirs' | 'lose' | 'contest' | 'advance' | 'safe' | 'take' | 'open' }]
 */
export function objectiveSwing(mine, theirs, objs, pieces, { me = 'A', risk = {} } = {}) {
  return objs.map(o => {
    const holders = mine.map(u => ({ key: u.key, name: u.name, oc: ocAt(u, o, pieces), in: inRange(u, o, pieces), risk: risk[u.key] ?? 0 })).filter(h => h.in).map(({ in: _in, ...h }) => h);
    const myOc = holders.reduce((a, h) => a + h.oc, 0);
    const there = [], movers = [];
    let now = 0, max = 0, maxAdvance = 0;
    for (const u of theirs) {
      const d = objectiveGap(u, o, pieces), full = u.oc ?? 0;
      if (d <= 0) {
        const oc = ocInRange(u, o, pieces);
        there.push({ key: u.key, name: u.name, oc, full });
        now += oc; max += full; maxAdvance += full;     // the rest of the unit can close up
      } else if (!(full > 0)) continue;
      else if (d <= (u.move ?? 6) + 1e-9) { movers.push({ key: u.key, name: u.name, oc: full, via: 'move', need: 0, p: 1 }); max += full; maxAdvance += full; }
      else if (d <= (u.move ?? 6) + 6 + 1e-9) {
        const need = Math.max(1, Math.ceil(d - (u.move ?? 6) - 1e-9));
        movers.push({ key: u.key, name: u.name, oc: full, via: 'advance', need, p: (7 - need) / 6 });
        maxAdvance += full;
      }
    }
    movers.sort((a, b) => a.need - b.need || b.oc - a.oc);
    const holder = myOc > now ? 'me' : now > myOc ? 'them' : null;
    // a tie leaves the objective with nobody; an Advance is only named when a normal move is not enough
    const verdict = holder === 'them' ? 'theirs'
      : max > myOc ? (holder === 'me' ? 'lose' : 'take')
        : holder === 'me' ? (max === myOc && max > now ? 'contest' : maxAdvance >= myOc && maxAdvance > max ? 'advance' : 'safe')
          : maxAdvance > myOc ? 'advance' : 'open';
    return { id: o.id, label: o.label ?? o.id, cls: o.cls, side: o.side ?? null, x: o.x, y: o.y, host: o.host ?? [], mine: myOc, theirs: now, holder, holders, there, movers, max, maxAdvance, verdict, mySide: me };
  });
}

/**
 * How many of these objectives they can control at the end of their turn, a unit going to one objective only
 * (the easiest objectives first; normal moves, no Advance). -> { n, ids }
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
    for (const m of o.movers) {
      if (oc > o.mine) break;
      if (m.via !== 'move' || used.has(m.key)) continue;
      oc += m.oc; pick.push(m.key);
    }
    if (oc > o.mine) { got.push(o.id); picks[o.id] = pick; for (const k of pick) used.add(k); }
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
  const out = { now, canEnemyDZ: false, quarters: new Set(), centre3: false, whollyNML: false, flankEdges: new Set(), edges: new Set(), terrainOutside: false };
  const take = (f) => {
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
      take(unitFacts({ ...u, x, y }, X, geo));
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
        r = n ? { verdict: 'yes', vp: Math.min(5, 3 * n), why: `${n} unit${n > 1 ? 's' : ''} can be wholly within your deployment zone (${nowN} there now): ${names(c.theirs.filter((u, i) => R()[i].canEnemyDZ).map(u => u.name))}` }
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
            : { verdict: 'yes', vp: my6 ? 3 : 5, why: my6 ? 'they can reach the centre; your unit within 6" of it holds them to 3 VP' : 'they can reach the centre and you have no unit within 6" of it' };
        break;
      }
      case 'cleanse': {
        const k = controllable(swing, swing.filter(o => !(o.cls === 'home' && o.side === Y)).map(o => o.id));
        r = k.n ? { verdict: 'yes', vp: k.n >= 2 ? 5 : 2, why: `an action on ${k.n} objective${k.n > 1 ? 's' : ''} they can control outside their home (${names(k.ids.map(i => byId.get(i).label), 3)}); those units do not shoot` }
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
        r = opposite ? { verdict: 'yes', vp: 5, why: 'they can have units within 6" of opposite battlefield edges, one of them outside their territory' }
          : flank ? { verdict: 'yes', vp: 3, why: 'a unit of theirs can be within 6" of a battlefield edge outside their territory' } : { verdict: 'no', vp: 0, why: 'none of their units can be near a battlefield edge outside their territory' };
        break;
      }
      case 'plunder': {
        const el = c.theirs.filter((u, i) => R()[i].terrainOutside);
        r = el.length ? { verdict: 'yes', vp: 5, why: `an action in a terrain area outside their territory: ${names(el.map(u => u.name))} can be in one (that unit does not shoot)` } : { verdict: 'no', vp: 0, why: 'none of their units can be in a terrain area outside their territory' };
        break;
      }
      case 'secure-no-mans-land': {
        const k = controllable(swing, swing.filter(o => o.cls !== 'home').map(o => o.id));
        r = k.n >= 2 ? { verdict: 'yes', vp: 5, why: `they can control ${k.n} objectives in No Man’s Land (${names(k.ids.map(i => byId.get(i).label), 3)})` } : { verdict: 'no', vp: 0, why: `they can control ${k.n} objective${k.n === 1 ? '' : 's'} in No Man’s Land (two are needed)` };
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
  const threats = turnThreats(c.mine, c.theirs, c.pair, { pieces: c.geo?.pieces ?? null });
  const risk = Object.fromEntries(threats.map(t => [t.key, t.likely]));
  const swing = objectiveSwing(c.mine, c.theirs, c.objs ?? [], c.geo?.pieces ?? [], { me: c.me, risk });
  const cards = cardOutlook({ hand: c.hand ?? [], round: c.round ?? 1, me: c.me, mine: c.mine, theirs: c.theirs, threats, swing, geo: c.geo });
  return { threats, swing, cards, vpAtStake: cards.filter(x => x.verdict === 'yes').reduce((a, x) => a + x.vp, 0) };
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
 * -> [{ key, name, points, p (P destroyed by the units sent), by: [{ key, name, shoot, charge }], value }], best first
 */
export function killPlan(hits, bonus = {}) {
  const worth = (t) => Math.max(1, t.points ?? 1) + (bonus[t.key] ?? 0);
  const sent = new Map(hits.map(t => [t.key, []]));
  const free = new Set(hits.flatMap(t => t.by.map(b => b.key)));
  const pOf = (t, list) => killChance(list.map(b => b.part), t.wounds);
  for (;;) {
    let top = null;
    for (const t of hits) {
      const cur = sent.get(t.key), p0 = pOf(t, cur);
      if (p0 >= 0.995) continue;
      for (const b of t.by) {
        if (!free.has(b.key)) continue;
        const gain = (pOf(t, [...cur, b]) - p0) * worth(t);
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
    return { key: t.key, name: t.name, points: t.points, p, by: by.map(b => ({ key: b.key, name: b.name, shoot: b.shoot, charge: b.charge, engaged: b.engaged })), value: p * worth(t) };
  }).sort((a, b) => b.value - a.value);
}

/**
 * My turn, from the table as it stands: what each of my units is best used for.
 * in: as nextTurn, with hand = MY cards and risk = { [myUnitKey]: P(destroyed in their next turn where it stands) }.
 * -> { units: [{ key, name, risk, job: { kind: 'take' | 'hold' | 'card' | 'none', obj, label, card, note },
 *               attack: { key, name, p, how: 'shoot' | 'charge' | 'shoot + charge', with: n } | null }],
 *      kills (killPlan), swing (objectives from my side: 'lose' / 'take' = I can take it),
 *      cards (mine; when: 'mine' = end of my turn, 'theirs' = end of their turn, as the table stands), vp }
 * A unit's move job and its attack are worked out apart, both from where it stands now (a normal move, then
 * range / a charge): after a move to an objective its target may be out of reach - the card says so.
 */
export function myTurn(c) {
  const me = c.me, opp = me === 'A' ? 'B' : 'A';
  const pieces = c.geo?.pieces ?? [];
  const hits = turnThreats(c.theirs, c.mine, c.pair, { pieces });
  const hitRisk = Object.fromEntries(hits.map(t => [t.key, t.likely]));
  // the objectives seen from their side: "mine" there = their OC, movers = my units
  const swing = objectiveSwing(c.theirs, c.mine, c.objs ?? [], pieces, { me: opp, risk: hitRisk });
  const cards = cardOutlook({ hand: c.hand ?? [], round: c.round ?? 1, me: opp, mine: c.theirs, theirs: c.mine, threats: hits, swing, geo: c.geo })
    .map(x => ({ ...x, why: myVoice(x.why), offTurn: x.when === 'mine', when: x.when === 'mine' ? 'theirs' : 'mine' }));
  const has = (id) => (c.hand ?? []).includes(id);
  // what a kill is worth beyond the unit's points: it holds an objective; a card of mine pays for it
  const bonus = {};
  for (const t of c.theirs) {
    let b = 0;
    if (swing.some(o => o.holders.some(h => h.key === t.key && h.oc > 0))) b += 0.5 * (t.points ?? 0) + (has('overwhelming-force') ? 3 * VP_POINTS : 0);
    if (has('assassination') && (t.chars ?? 0) > 0) b += 5 * VP_POINTS;
    if (has('bring-it-down') && (t.w10 ?? 0) > 0) b += 5 * VP_POINTS;
    if (has('a-grievous-blow') && t.ss13) b += 5 * VP_POINTS;
    if (has('no-prisoners')) b += 2 * VP_POINTS;
    if (b) bonus[t.key] = b;
  }
  const kills = killPlan(hits, bonus);
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
  // objectives: keep what I hold, then take what I can, a unit to one objective (the easiest first)
  const jobs = new Map();
  for (const o of swing) if (o.verdict === 'theirs') for (const t of o.there) if (t.oc > 0 && !jobs.has(t.key)) jobs.set(t.key, { kind: 'hold', obj: o.id, label: o.label, note: `${o.theirs} OC against ${o.mine}` });
  // (an objective they hold before an empty one: taking it also takes it from them)
  for (const verdict of ['lose', 'take']) {
    const open = swing.filter(o => o.verdict === verdict);
    const freeSwing = open.map(o => ({ ...o, there: o.there.filter(t => !jobs.has(t.key)), movers: o.movers.filter(m => !jobs.has(m.key)) }));
    const got = controllable(freeSwing, open.map(o => o.id));
    for (const o of open) for (const k of got.picks[o.id] ?? []) if (!jobs.has(k)) jobs.set(k, { kind: 'take', obj: o.id, label: o.label, note: o.mine > 0 ? `they have ${o.mine} OC there` : 'nobody holds it' });
  }
  // then the cards I can score by where a unit stands (the units still free)
  const Y = me;
  const place = (id, test, note) => {
    const card = cards.find(x => x.id === id && x.verdict === 'yes');
    if (!card) return;
    for (const u of c.mine) {
      if (jobs.has(u.key)) continue;
      const f = reachFacts(u, Y, c.geo);
      if (test(f)) { jobs.set(u.key, { kind: 'card', card: card.name, label: card.name, note }); if (id !== 'behind-enemy-lines') break; }
    }
  };
  place('behind-enemy-lines', f => f.canEnemyDZ, 'wholly within their deployment zone');
  place('centre-ground', f => f.centre3, 'within 3" of the centre');
  place('plunder', f => f.terrainOutside, 'an action in a terrain area outside your territory (it does not shoot)');
  place('outflank', f => f.flankEdges.size > 0, 'within 6" of a battlefield edge outside your territory');
  const atk = new Map();
  for (const k of kills) for (const b of k.by) atk.set(b.key, { key: k.key, name: k.name, p: k.p, with: k.by.length, how: [b.shoot ? 'shoot' : '', b.engaged ? 'fight' : b.charge ? 'charge' : ''].filter(Boolean).join(' + ') });
  const units = c.mine.map(u => ({ key: u.key, name: u.name, risk: c.risk?.[u.key] ?? 0, job: jobs.get(u.key) ?? { kind: 'none' }, attack: atk.get(u.key) ?? null }));
  const rank = { take: 0, card: 1, hold: 2, none: 3 };
  units.sort((a, b) => rank[a.job.kind] - rank[b.job.kind] || (b.attack?.p ?? 0) - (a.attack?.p ?? 0) || b.risk - a.risk);
  return { units, kills, swing, cards, vp: cards.filter(x => x.verdict === 'yes').reduce((a, x) => a + x.vp, 0) };
}

// ---------------------------------------------------------------------------
// Moves to weigh with the mission forecast (the view runs the forecast; this picks what to try and reads it)

/**
 * The moves worth trying for each of my units: onto each objective a normal move reaches (a straight line,
 * just far enough for a model to be in range), and - for a unit likely to be destroyed where it stands - a
 * normal move back towards my home objective.
 * swing: myTurn().swing (its movers are my units). -> [{ key: `${unitKey}>${what}`, unit, name, kind: 'obj' | 'back',
 *   obj (id), label, x, y (the unit's centre after the move), dist }], at most `max` (nearest objectives first)
 */
export function moveCandidates(mine, swing, pieces, { risk = {}, home = null, max = 24 } = {}) {
  const out = [];
  for (const u of mine) {
    const M = u.move ?? 6;
    for (const o of swing) {
      const mv = o.movers.find(m => m.key === u.key && m.via === 'move');
      if (!mv) continue;
      const d = objectiveGap(u, o, pieces);
      // towards the objective, from the model nearest to it
      let near = null;
      for (const m of u.models) { const dd = Math.hypot(u.x + m.dx - o.x, u.y + m.dy - o.y); if (!near || dd < near.dd) near = { dd, m }; }
      const len = Math.hypot(o.x - (u.x + near.m.dx), o.y - (u.y + near.m.dy)) || 1;
      const step = Math.min(M, d + 0.75);
      const x = u.x + (o.x - (u.x + near.m.dx)) / len * step, y = u.y + (o.y - (u.y + near.m.dy)) / len * step;
      if (!(objectiveGap({ ...u, x, y }, o, pieces) <= 0)) continue;     // the straight line does not get it in range
      out.push({ key: `${u.key}>${o.id}`, unit: u.key, name: u.name, kind: 'obj', obj: o.id, label: o.label, x, y, dist: step });
    }
    if (home && (risk[u.key] ?? 0) >= 0.25) {
      const len = Math.hypot(home.x - u.x, home.y - u.y);
      if (len > 3) { const step = Math.min(M, len - 1); out.push({ key: `${u.key}>back`, unit: u.key, name: u.name, kind: 'back', obj: null, label: 'back towards your home', x: u.x + (home.x - u.x) / len * step, y: u.y + (home.y - u.y) / len * step, dist: step }); }
    }
  }
  return out.sort((a, b) => (a.kind === 'back') - (b.kind === 'back') || a.dist - b.dist).slice(0, max);
}

/** What a forecast result is worth to player X: { win (P), vp (X's mean VP minus the other player's) }. */
export function worthOf(result, X) {
  const Y = X === 'A' ? 'B' : 'A';
  return { win: result?.[`pWin${X}`] ?? 0, vp: (result?.[X]?.mean ?? 0) - (result?.[Y]?.mean ?? 0) };
}
/**
 * A move counts as better than standing still from this many VP of margin: about 3x the noise of the difference
 * between two forecasts of 1,500 games (measured 0.95 VP on a live table counted for the round in progress).
 */
export const MOVE_MIN_VP = 3;
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
