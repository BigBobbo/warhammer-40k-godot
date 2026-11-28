// "Play it out": the rest of the game with BOTH players doing what the Board's turn cards suggest, turn after
// turn. From where the armies stand now, the player whose turn it is moves as "Your turn" would have it
// (take the objectives in reach, hold the ones held with the units that takes, charge the best target, else walk
// towards an objective that is not held); then the other player does the same from what they then see; and so on
// to the end of battle round 5. The result is a plan in the Board's shape (a step per battle round), which the
// mission forecast then scores like any plan: who stands on what, who reaches whom, the cards, the dice.
//
// It is a second opinion next to the usual forecast, not a replacement and not a search:
//  - the moves follow one fixed rule; nobody looks ahead, baits, screens or trades;
//  - a unit that cannot pass dense terrain goes round it (paths.mjs); climbing is not modelled;
//  - a unit with nothing to shoot or charge Advances (its Move + 3", the D6's average less a half);
//  - a unit does not walk into a place where it is likely destroyed next turn, unless the walk takes an objective;
//  - units do not stand on each other: a unit that would end on other bases ends beside them;
//  - a unit that is more likely destroyed than not by then stops acting, holding and being a target in the walk
//    (the forecast still rolls its own dice for it when it scores the plan). What destroys it is what can attack
//    it from where the other player's units ended their move: in range and in sight, or in engagement range;
//  - reserves arrive from battle round 2 (20.03 / 20.04: 6" from a battlefield edge, more than 8" from the enemy,
//    not in the opponent's deployment zone before round 3; Deep Strike 24.09: anywhere more than 8" away), units
//    in a TRANSPORT get out within 3" of it (18.04) when it is near an objective or by round 3;
//  - cards count for the round in progress only (the hands of later rounds are not known).
// Pure module (no DOM), unit-tested (tests/calc-playout.test.mjs).

import { myTurn, moveCandidates, objectiveGap, turnThreats, killChance } from './nextturn.mjs';
import { route, along, goesRound } from './paths.mjs';
import { inPoly } from './board.mjs';
import { p2d6 } from './sight.mjs';

const W = 44, H = 60, ROUNDS = 5;
const CHARGE = 7;          // the average charge roll: a charge is walked when a move and this get the unit there
const ADVANCE = 3;         // an Advance adds a D6: counted as 3"
const RISKY = 0.5;          // a walk is not made to where the unit is this likely to be destroyed next turn
const ENGAGE = 1;          // a unit that does not charge ends more than this from enemy bases (engagement range)
const other = (X) => (X === 'A' ? 'B' : 'A');
const extent = (fp) => fp?.r ?? Math.max(fp?.rx ?? 0, fp?.hw ?? 0, fp?.ry ?? 0, fp?.hh ?? 0);
const abs = (u, x = u.x, y = u.y) => u.models.map(m => ({ x: x + m.dx, y: y + m.dy, r: extent(m.fp) }));
const onTable = (u, x, y) => abs(u, x, y).every(m => m.x - m.r >= 0 && m.y - m.r >= 0 && m.x + m.r <= W && m.y + m.r <= H);
const reachOf = (u) => Math.max(0, ...(u.ranges ?? []));
/** The gap between the nearest bases of two units. */
export function unitGap(a, b) {
  let d = Infinity;
  for (const p of abs(a)) for (const q of abs(b)) d = Math.min(d, Math.hypot(p.x - q.x, p.y - q.y) - p.r - q.r);
  return Math.max(0, d);
}
/** `dist` inches from the unit towards (tx, ty) - round dense terrain if it has to - shortened until every model is on the table. -> { x, y, dist } */
function towards(u, tx, ty, dist, pieces) {
  if (!(dist > 0)) return { x: u.x, y: u.y, dist: 0 };
  const rt = pieces && goesRound(u) ? route(u, tx, ty, pieces) : null;
  const pts = rt && !rt.blocked ? rt.pts : [[u.x, u.y], [tx, ty]];
  const len = rt && !rt.blocked ? rt.len : Math.hypot(tx - u.x, ty - u.y);
  if (!(len > 1e-9)) return { x: u.x, y: u.y, dist: 0 };
  for (let d = Math.min(dist, len); d > 0.05; d -= 0.5) {
    const p = along(pts, d);
    if (onTable(u, p.x, p.y)) return { x: p.x, y: p.y, dist: d };
  }
  return { x: u.x, y: u.y, dist: 0 };
}

/**
 * Where a unit can stand near (x, y) without its bases on other bases: the spot itself, else the nearest one
 * on rings around it. others: [{ x, y, r, foe }] (every other model on the table); a base stays more than
 * `clear` from enemy bases unless `engage`. ok(x, y): what the spot must still do (stay on its objective).
 */
export function freeSpot(u, x, y, others, { engage = false, ok = null, reach = 5 } = {}) {
  const rel = u.models.map(m => ({ dx: m.dx, dy: m.dy, r: extent(m.fp) }));
  const fits = (px, py) => {
    if (!onTable(u, px, py)) return false;
    for (const m of rel) {
      const mx = px + m.dx, my = py + m.dy;
      for (const o of others) {
        const need = m.r + o.r + (o.foe ? (engage ? 0 : ENGAGE) : 0);
        const ddx = mx - o.x, ddy = my - o.y;
        if (ddx * ddx + ddy * ddy < need * need - 1e-9) return false;
      }
    }
    return true;
  };
  if (fits(x, y) && (!ok || ok(x, y))) return { x, y, moved: 0 };
  let loose = null;
  for (let rad = 1; rad <= reach; rad += 1) {
    const n = Math.max(8, Math.round(rad * 6));
    for (let k = 0; k < n; k++) {
      const a = (2 * Math.PI * k) / n, px = x + Math.cos(a) * rad, py = y + Math.sin(a) * rad;
      if (!fits(px, py)) continue;
      if (!ok || ok(px, py)) return { x: px, y: py, moved: rad };
      loose ??= { x: px, y: py, moved: rad };
    }
  }
  return loose;      // free but no longer where it wanted to be; null: nowhere free nearby
}

/**
 * What every unit of one player does in a turn of theirs, by the rule of the "Your turn" card.
 * c: as nextturn.myTurn ({ me, mine, theirs, pair, objs, geo, round, hand }).
 * -> [{ unit, name, kind: 'take' | 'hold' | 'charge' | 'shoot' | 'fight' | 'advance' | 'wait' (it holds back: the way on is too dangerous) | 'stay', label (the objective or the
 *       target), x, y (the unit's centre after the turn), dist }], in the order of c.mine
 */
export function turnMoves(c) {
  const pieces = c.geo?.pieces ?? [];
  const my = myTurn({ ...c, hand: c.hand ?? [] });
  const cands = moveCandidates(c.mine, my.swing, pieces, { max: Infinity });
  const row = new Map(my.units.map(u => [u.key, u])), foe = new Map(c.theirs.map(t => [t.key, t]));
  // how many of my units stand on, or walk to, each objective (the walkers spread out over the ones not held)
  const busy = new Map(my.swing.map(o => [o.id, o.there.filter(t => t.oc > 0).length]));
  const out = new Map();
  const stay = (u, kind, label) => ({ unit: u.key, name: u.name, kind, label, x: u.x, y: u.y, dist: 0 });
  // an objective I hold keeps the units it needs: the one with the most OC there, and more only while the other
  // player's OC there is not beaten. The rest of the units standing on it are free to go.
  const keeps = new Set();
  for (const o of my.swing) {
    let oc = 0;
    for (const t of [...o.there].filter(t => t.oc > 0).sort((a, b) => b.oc - a.oc)) { if (oc > 0 && oc > o.mine) break; keeps.add(t.key); oc += t.oc; }
  }
  const shooters = new Map();
  for (const u of c.mine) {
    const r = row.get(u.key), job = r?.job ?? { kind: 'none' };
    if (job.kind === 'take') {
      const cd = cands.find(x => x.unit === u.key && x.obj === job.obj);
      if (cd) { out.set(u.key, { unit: u.key, name: u.name, kind: 'take', label: job.label, obj: job.obj, x: cd.x, y: cd.y, dist: cd.dist }); busy.set(job.obj, (busy.get(job.obj) ?? 0) + 1); continue; }
    }
    if (job.kind === 'hold' && keeps.has(u.key)) { out.set(u.key, { ...stay(u, 'hold', job.label), obj: job.obj }); continue; }
    if (job.kind === 'hold') busy.set(job.obj, Math.max(0, (busy.get(job.obj) ?? 0) - 1));
    const t = r?.attack ? foe.get(r.attack.key) : null;
    const M = u.move ?? 6;
    if (t && /charge/.test(r.attack.how)) {
      // into engagement range of its target when a move and an average charge get there (the roll itself is in
      // the odds, not in the walk); else its move towards it
      const gap = Math.max(0, unitGap(u, t) - 0.5);
      const p = towards(u, t.x, t.y, gap <= M + CHARGE ? gap : M, pieces);
      // (chargeP: the chance the charge roll covers what the normal move leaves; 1 when the move alone gets there)
      out.set(u.key, { unit: u.key, name: u.name, kind: gap <= M + CHARGE ? 'charge' : 'advance', label: t.name, target: t.key, ...(gap <= M + CHARGE ? { chargeP: gap <= M ? 1 : p2d6(Math.ceil(gap - M - 1e-9)) } : {}), ...p });
    } else if (t) {
      // it shoots (or is fighting already): a step forward first if its target is beyond its longest range
      const need = r.attack.how === 'fight' ? 0 : unitGap(u, t) - Math.max(1, reachOf(u) - 1);
      const p = need > 0 ? towards(u, t.x, t.y, Math.min(M, need), pieces) : { x: u.x, y: u.y, dist: 0 };
      const mv = { unit: u.key, name: u.name, kind: r.attack.how === 'fight' ? 'fight' : 'shoot', label: t.name, ...p };
      // (a unit that shoots where it stands can walk and shoot: it may still be sent to an objective below)
      if (mv.kind === 'shoot' && !(need > 0)) shooters.set(u.key, mv); else out.set(u.key, mv);
    }
  }
  // the rest walk: towards the nearest objective I do not hold, the ones nobody of mine is going to first
  for (const u of c.mine) {
    if (out.has(u.key)) continue;
    const M = u.move ?? 6, shot = shooters.get(u.key);
    let best = null;
    for (const o of my.swing) {
      if (o.verdict === 'theirs' || !((u.oc ?? 0) > 0)) continue;      // ('theirs' seen from the other side: I hold it)
      if (shot && (busy.get(o.id) ?? 0) > 0) continue;                 // a shooter only leaves its spot for an objective nobody is going to
      const gap = objectiveGap(u, o, pieces), score = gap + 12 * (busy.get(o.id) ?? 0);
      if (!best || score < best.score) best = { o, gap, score };
    }
    if (best) {
      // out of reach of it with a normal move and nothing to shoot: it Advances (it gives up no shot or charge)
      const adv = !shot && best.gap + 0.75 > M;
      const p = towards(u, best.o.x, best.o.y, Math.min(M + (adv ? ADVANCE : 0), best.gap + 0.75), pieces);
      // caution (1.152.0): a walk that does not get onto the objective is not made into a place where the unit is
      // likely destroyed in the other player's next turn, unless it is no safer where it stands
      if (p.dist > 0 && c.pair && !(objectiveGap({ ...u, x: p.x, y: p.y }, best.o, pieces) <= 0)) {
        const riskAt = (x, y) => turnThreats([{ ...u, x, y }], c.theirs, c.pair, { pieces })[0]?.likely ?? 0;
        const there = riskAt(p.x, p.y);
        if (there >= RISKY && there > riskAt(u.x, u.y) + 0.15) { out.set(u.key, shot ?? { ...stay(u, 'wait', best.o.label), risk: there }); continue; }
      }
      busy.set(best.o.id, (busy.get(best.o.id) ?? 0) + 1);
      out.set(u.key, { unit: u.key, name: u.name, kind: p.dist > 0 ? 'advance' : 'stay', label: best.o.label, obj: best.o.id, ...(adv && p.dist > M ? { adv: true } : {}), ...p });
      continue;
    }
    if (shot) { out.set(u.key, shot); continue; }
    // nothing to take: close with the nearest enemy unit, to just inside its longest range (or into reach of a charge)
    let near = null;
    for (const t of c.theirs) { const g = unitGap(u, t); if (!near || g < near.g) near = { t, g }; }
    const want = near ? Math.max(0, near.g - Math.max(1, reachOf(u) - 1)) : 0;
    if (near && want > 0) { const p = towards(u, near.t.x, near.t.y, Math.min(M, want), pieces); out.set(u.key, { unit: u.key, name: u.name, kind: p.dist > 0 ? 'advance' : 'stay', label: near.t.name, ...p }); }
    else out.set(u.key, stay(u, 'stay', ''));
  }
  return c.mine.map(u => out.get(u.key));
}

/**
 * What a player's turn does to the other player's units, once its units have moved (1.152.0). The turn cards'
 * "likely destroyed" is an upper bound - everything that could get into range or charge counts. Here the units
 * stand where their move ended, so only what can really attack from there counts: a unit shoots if its target is
 * in range and in sight from where it stands, fights if it is in engagement range, and attacks one target - the
 * one it is worth most against. A unit that charged this turn fights with the chance its charge roll came off.
 * -> [{ key, name, p (destroyed this turn), by: [attacker keys] }], p > 0 only
 */
export function turnCasualties(targets, attackers, pair, pieces, charged = null) {
  const rows = turnThreats(targets, attackers, pair, { pieces });
  const pts = new Map(targets.map(t => [t.key, t.points ?? 0]));
  const best = new Map();                 // attacker -> { row, part, value }
  for (const row of rows) {
    for (const b of row.by) {
      let part = b.engaged ? b.fp : b.shoot?.now ? b.sp : null;
      if (!part) continue;
      // a unit that charged this turn fights only if its charge roll came off (charged: Map attacker -> that chance)
      const cp = b.engaged ? charged?.get(b.key) ?? 1 : 1;
      if (cp < 1) part = { mu: part.mu * cp, v: part.v * cp + cp * (1 - cp) * part.mu ** 2, p: part.p == null ? undefined : part.p * cp };
      const alone = killChance([part], row.wounds), value = alone * Math.max(1, pts.get(row.key) ?? 1) + 1e-6 * part.mu;
      if (value > (best.get(b.key)?.value ?? 0)) best.set(b.key, { row, part, value });
    }
  }
  const on = new Map();
  for (const [ak, x] of best) { if (!on.has(x.row)) on.set(x.row, { parts: [], by: [] }); on.get(x.row).parts.push(x.part); on.get(x.row).by.push(ak); }
  return [...on].map(([row, x]) => ({ key: row.key, name: row.name, p: killChance(x.parts, row.wounds), by: x.by })).filter(r => r.p > 0);
}

/**
 * Where a unit from reserves comes on in a turn of player X (20.04 / 24.09): the legal spot nearest to an
 * objective X does not hold (in range of it if one is). -> { x, y, label, gap } | null (nowhere legal)
 */
export function arrival(u, X, s, pos, round, others) {
  const foes = pos[other(X)].flatMap(t => abs(t)), pieces = s.geo?.pieces ?? [];
  const enemyZone = s.geo?.zones?.[other(X)] ?? null;
  const deep = !!(u.deepStrike || u.flags?.deepStrike);
  const rel = u.models.map(m => ({ dx: m.dx, dy: m.dy, r: extent(m.fp) }));
  const open = (s.objs ?? []).filter(o => !pos[X].some(t => (t.oc ?? 0) > 0 && objectiveGap(t, o, pieces) <= 0));
  let best = null;
  for (let x = 1; x <= W - 1; x += 1.5) {
    for (let y = 1; y <= H - 1; y += 1.5) {
      if (!onTable(u, x, y)) continue;
      let legal = true;
      for (const m of rel) {
        const mx = x + m.dx, my = y + m.dy;
        // wholly within 6" of a battlefield edge, unless it has Deep Strike
        if (!deep && Math.min(mx + m.r, W - (mx - m.r), my + m.r, H - (my - m.r)) > 6 + 1e-9) { legal = false; break; }
        if (round < 3 && enemyZone && inPoly(mx, my, enemyZone)) { legal = false; break; }
        for (const f of foes) if (Math.hypot(mx - f.x, my - f.y) - m.r - f.r <= 8) { legal = false; break; }
        if (!legal) break;
        for (const o of others) if (!o.foe && Math.hypot(mx - o.x, my - o.y) < m.r + o.r - 1e-9) { legal = false; break; }
        if (!legal) break;
      }
      if (!legal) continue;
      for (const o of open.length ? open : s.objs ?? []) {
        const gap = objectiveGap({ ...u, x, y }, o, pieces);
        if (!best || gap < best.gap - 1e-9) best = { x, y, gap, label: o.label, obj: o.id };
      }
      if (!(s.objs ?? []).length && !best) best = { x, y, gap: Infinity, label: '', obj: null };
    }
  }
  return best;
}

/**
 * The rest of the game, both players following turnMoves in turn.
 * s: { A, B (the units on the table now), objs, geo, pair, round (the battle round in progress), turn (whose
 *      turn it is), first (who has the first turn of each round; null: the player whose turn it is),
 *      moved (the player whose turn it is has already moved this turn), hand: { A, B }, rounds,
 *      reserves: { A: [unit], B: [unit] } (not on the table yet: the unit without a position; deepStrike),
 *      embarked: { A: [{ ...unit, in: the transport's key }], B } (inside a TRANSPORT on the table) }
 * -> { steps: [{ round, A: units, B: units }] (the table at the end of each battle round from `round` on; a unit
 *        that came on or got out is in the steps from then on),
 *      log: [{ round, side, moves (turnMoves, without the units that do nothing; plus kind 'arrive' / 'disembark'),
 *              done (the turn was over already), lost: [{ unit, name, p }] (units of the OTHER player more likely
 *              destroyed than not from this turn on) }],
 *      gone: { [unitKey]: round } }
 */
export function playOut(s) {
  const last = s.rounds ?? ROUNDS, F = s.first ?? s.turn ?? 'A', turn = s.turn ?? F;
  const pieces = s.geo?.pieces ?? [];
  const pos = { A: s.A.map(u => ({ ...u })), B: s.B.map(u => ({ ...u })) };
  const wait = { A: (s.reserves?.A ?? []).map(u => ({ ...u })), B: (s.reserves?.B ?? []).map(u => ({ ...u })) };
  const inside = { A: (s.embarked?.A ?? []).map(u => ({ ...u })), B: (s.embarked?.B ?? []).map(u => ({ ...u })) };
  const alive = {}, gone = {};                       // P(still there) of each unit; the round it stopped acting
  const live = (X) => pos[X].filter(u => !(u.key in gone));
  const bases = (X, skip) => ['A', 'B'].flatMap(Y => pos[Y].filter(u => u.key !== skip).flatMap(u => abs(u).map(m => ({ ...m, foe: Y !== X }))));
  const steps = [], log = [];
  for (let r = Math.max(1, s.round ?? 1); r <= last; r++) {
    for (const X of [F, other(F)]) {
      if (r === s.round) {
        if (X === F && turn !== F) continue;                                   // the first player's turn of this round is over
        if (X === turn && s.moved) { log.push({ round: r, side: X, moves: [], done: true, lost: [] }); continue; }
      } else if (X === F) {
        // a new battle round: battle-shock has ended by the time a unit matters again
        for (const Y of ['A', 'B']) pos[Y] = pos[Y].map(u => (u.shocked ? { ...u, shocked: false } : u));
      }
      const Y = other(X), extra = [];
      const c = { me: X, mine: live(X), theirs: live(Y), pair: s.pair, objs: s.objs, geo: s.geo, round: r, hand: r === s.round ? s.hand?.[X] ?? [] : [] };
      const moves = turnMoves(c);
      // each unit ends where no other base is: the units that hold first, then the ones that take, then the rest
      const rank = { hold: 0, fight: 0, shoot: 1, take: 2, charge: 3, advance: 4, stay: 5, wait: 5 };
      const order = [...moves].sort((a, b) => rank[a.kind] - rank[b.kind]);
      const where = new Map(pos[X].map(u => [u.key, u]));
      for (const m of order) {
        const u = where.get(m.unit);
        if (m.x === u.x && m.y === u.y) continue;
        const o = m.obj ? (s.objs ?? []).find(q => q.id === m.obj) : null;
        const sp = freeSpot(u, m.x, m.y, bases(X, u.key), { engage: m.kind === 'charge', ok: o && m.kind === 'take' ? (x, y) => objectiveGap({ ...u, x, y }, o, pieces) <= 0 : null });
        if (sp) { m.x = sp.x; m.y = sp.y; }
        const nu = { ...u, x: m.x, y: m.y };
        pos[X] = pos[X].map(q => (q.key === u.key ? nu : q)); where.set(u.key, nu);
      }
      // out of a transport (18.04: wholly within 3" of it). A unit keeps its formation here, so it is set down
      // as near the transport as its bases allow, on the side of the objective it is for
      for (const p of [...inside[X]]) {
        const t = pos[X].find(u => u.key === p.in);
        if (!t || t.key in gone) { inside[X] = inside[X].filter(q => q !== p); gone[p.key] ??= r; continue; }
        const tm = moves.find(m => m.unit === t.key);
        if (tm?.adv) continue;                                                // the transport Advanced: nobody gets out
        const open = (s.objs ?? []).filter(o => !live(X).some(q => (q.oc ?? 0) > 0 && objectiveGap(q, o, pieces) <= 0));
        let near = null;
        for (const o of open) { const g = objectiveGap({ ...p, x: t.x, y: t.y }, o, pieces); if (!near || g < near.g) near = { o, g }; }
        const foeNear = live(Y).some(q => unitGap(t, q) <= 12);
        if (!(r >= 3 || foeNear || (near && near.g <= (p.move ?? 6) + 3))) continue;
        const hull = abs(t), tr = Math.max(...hull.map(m => m.r));
        const aim = near?.o ?? { x: W / 2, y: H / 2 };
        const len = Math.hypot(aim.x - t.x, aim.y - t.y) || 1;
        const within3 = (x, y) => abs(p, x, y).every(m => hull.some(q => Math.hypot(m.x - q.x, m.y - q.y) + m.r - q.r <= 3 + 1e-9));
        const sp = freeSpot({ ...p, x: t.x, y: t.y }, t.x + (aim.x - t.x) / len * (tr + 1), t.y + (aim.y - t.y) / len * (tr + 1), bases(X, p.key), { reach: 5, ok: within3 });
        if (!sp) continue;
        const { in: _in, ...nu } = { ...p, x: sp.x, y: sp.y };
        pos[X].push(nu); inside[X] = inside[X].filter(q => q !== p);
        extra.push({ unit: p.key, name: p.name, kind: 'disembark', label: t.name, x: sp.x, y: sp.y, dist: 0 });
      }
      // reserves: from battle round 2; a unit waits for round 3 only if it cannot come on in range of an objective now
      if (r >= 2) {
        for (const u of [...wait[X]]) {
          const sp = arrival(u, X, s, { A: live('A'), B: live('B') }, r, bases(X, u.key));
          if (!sp || (r < 3 && !(sp.gap <= 0))) continue;
          pos[X].push({ ...u, x: sp.x, y: sp.y }); wait[X] = wait[X].filter(q => q !== u);
          extra.push({ unit: u.key, name: u.name, kind: 'arrive', label: sp.label, x: sp.x, y: sp.y, dist: 0 });
        }
      }
      // what this turn does to the other player: a unit more likely destroyed than not stops acting from here on
      const lost = [];
      if (s.pair) {
        const charged = new Map(moves.filter(m => m.kind === 'charge').map(m => [m.unit, m.chargeP ?? 1]));
        for (const t of turnCasualties(live(Y), live(X), s.pair, pieces, charged)) {
          alive[t.key] = (alive[t.key] ?? 1) * (1 - t.p);
          if (alive[t.key] < 0.5) { gone[t.key] = r; lost.push({ unit: t.key, name: t.name, p: 1 - alive[t.key] }); }
        }
      }
      log.push({ round: r, side: X, moves: [...moves.filter(m => m.kind !== 'stay'), ...extra], lost });
    }
    // (reserves not on the table by the end of round 3 are destroyed, 20.03)
    if (r === 3) for (const X of ['A', 'B']) { for (const u of wait[X]) gone[u.key] ??= r; wait[X] = []; }
    steps.push({ round: r, A: pos.A, B: pos.B });
  }
  return { steps, log, gone };
}
