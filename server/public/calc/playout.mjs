// "Play it out": the rest of the game with BOTH players doing what the Board's turn cards suggest, turn after
// turn. From where the armies stand now, the player whose turn it is moves as "Your turn" would have it
// (take the objectives in reach, hold the ones held with the units that takes, charge the best target, else walk
// towards an objective that is not held); then the other player does the same from what they then see; and so on to the end of
// battle round 5. The result is a plan in the Board's shape (a step per battle round), which the mission
// forecast then scores like any plan: who stands on what, who reaches whom, the cards, the dice.
//
// It is a second opinion next to the usual forecast, not a replacement and not a search:
//  - the moves follow one fixed rule; nobody looks ahead, baits, screens or trades;
//  - a move is a straight line (terrain and other models are not in the way) and nobody Advances;
//  - units destroyed on the way do not change where the others walk: the forecast removes them when it scores
//    the plan, the walk itself is worked out with everybody alive;
//  - cards count for the round in progress only (the hands of later rounds are not known).
// Pure module (no DOM), unit-tested (tests/calc-playout.test.mjs).

import { myTurn, moveCandidates, objectiveGap } from './nextturn.mjs';

const W = 44, H = 60, ROUNDS = 5;
const CHARGE = 7;          // the average charge roll: a charge is walked when a move and this get the unit there
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
/** `dist` inches from the unit towards (tx, ty), shortened until every model is on the table. -> { x, y, dist } */
function towards(u, tx, ty, dist) {
  const len = Math.hypot(tx - u.x, ty - u.y);
  if (!(len > 1e-9) || !(dist > 0)) return { x: u.x, y: u.y, dist: 0 };
  for (let d = Math.min(dist, len); d > 0.05; d -= 0.5) {
    const x = u.x + (tx - u.x) / len * d, y = u.y + (ty - u.y) / len * d;
    if (onTable(u, x, y)) return { x, y, dist: d };
  }
  return { x: u.x, y: u.y, dist: 0 };
}

/**
 * What every unit of one player does in a turn of theirs, by the rule of the "Your turn" card.
 * c: as nextturn.myTurn ({ me, mine, theirs, pair, objs, geo, round, hand }).
 * -> [{ unit, name, kind: 'take' | 'hold' | 'charge' | 'shoot' | 'fight' | 'advance' | 'stay', label (the objective or the
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
      if (cd) { out.set(u.key, { unit: u.key, name: u.name, kind: 'take', label: job.label, x: cd.x, y: cd.y, dist: cd.dist }); busy.set(job.obj, (busy.get(job.obj) ?? 0) + 1); continue; }
    }
    if (job.kind === 'hold' && keeps.has(u.key)) { out.set(u.key, stay(u, 'hold', job.label)); continue; }
    if (job.kind === 'hold') busy.set(job.obj, Math.max(0, (busy.get(job.obj) ?? 0) - 1));
    const t = r?.attack ? foe.get(r.attack.key) : null;
    const M = u.move ?? 6;
    if (t && /charge/.test(r.attack.how)) {
      // into engagement range of its target when a move and an average charge get there (the roll itself is in
      // the odds, not in the walk); else its move towards it
      const gap = Math.max(0, unitGap(u, t) - 0.5);
      const p = towards(u, t.x, t.y, gap <= M + CHARGE ? gap : M);
      out.set(u.key, { unit: u.key, name: u.name, kind: gap <= M + CHARGE ? 'charge' : 'advance', label: t.name, ...p });
    } else if (t) {
      // it shoots (or is fighting already): a step forward first if its target is beyond its longest range
      const need = r.attack.how === 'fight' ? 0 : unitGap(u, t) - Math.max(1, reachOf(u) - 1);
      const p = need > 0 ? towards(u, t.x, t.y, Math.min(M, need)) : { x: u.x, y: u.y, dist: 0 };
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
      const p = towards(u, best.o.x, best.o.y, Math.min(M, best.gap + 0.75));
      busy.set(best.o.id, (busy.get(best.o.id) ?? 0) + 1);
      out.set(u.key, { unit: u.key, name: u.name, kind: p.dist > 0 ? 'advance' : 'stay', label: best.o.label, ...p });
      continue;
    }
    if (shot) { out.set(u.key, shot); continue; }
    // nothing to take: close with the nearest enemy unit, to just inside its longest range (or into reach of a charge)
    let near = null;
    for (const t of c.theirs) { const g = unitGap(u, t); if (!near || g < near.g) near = { t, g }; }
    const want = near ? Math.max(0, near.g - Math.max(1, reachOf(u) - 1)) : 0;
    if (near && want > 0) { const p = towards(u, near.t.x, near.t.y, Math.min(M, want)); out.set(u.key, { unit: u.key, name: u.name, kind: p.dist > 0 ? 'advance' : 'stay', label: near.t.name, ...p }); }
    else out.set(u.key, stay(u, 'stay', ''));
  }
  return c.mine.map(u => out.get(u.key));
}

/**
 * The rest of the game, both players following turnMoves in turn.
 * s: { A, B (the units on the table now), objs, geo, pair, round (the battle round in progress), turn (whose
 *      turn it is), first (who has the first turn of each round; null: the player whose turn it is),
 *      moved (the player whose turn it is has already moved this turn), hand: { A, B }, rounds }
 * -> { steps: [{ round, A: units, B: units }] (the table at the end of each battle round from `round` on),
 *      log: [{ round, side, moves (turnMoves, without the units that do nothing), done (the turn was over already) }] }
 */
export function playOut(s) {
  const last = s.rounds ?? ROUNDS, F = s.first ?? s.turn ?? 'A', turn = s.turn ?? F;
  const pos = { A: s.A.map(u => ({ ...u })), B: s.B.map(u => ({ ...u })) };
  const steps = [], log = [];
  for (let r = Math.max(1, s.round ?? 1); r <= last; r++) {
    for (const X of [F, other(F)]) {
      if (r === s.round) {
        if (X === F && turn !== F) continue;                                   // the first player's turn of this round is over
        if (X === turn && s.moved) { log.push({ round: r, side: X, moves: [], done: true }); continue; }
      } else if (X === F) {
        // a new battle round: battle-shock has ended by the time a unit matters again
        for (const Y of ['A', 'B']) pos[Y] = pos[Y].map(u => (u.shocked ? { ...u, shocked: false } : u));
      }
      const moves = turnMoves({ me: X, mine: pos[X], theirs: pos[other(X)], pair: s.pair, objs: s.objs, geo: s.geo, round: r, hand: r === s.round ? s.hand?.[X] ?? [] : [] });
      const by = new Map(moves.map(m => [m.unit, m]));
      pos[X] = pos[X].map(u => { const m = by.get(u.key); return m && (m.x !== u.x || m.y !== u.y) ? { ...u, x: m.x, y: m.y } : u; });
      log.push({ round: r, side: X, moves: moves.filter(m => m.kind !== 'stay') });
    }
    steps.push({ round: r, A: pos.A, B: pos.B });
  }
  return { steps, log };
}
