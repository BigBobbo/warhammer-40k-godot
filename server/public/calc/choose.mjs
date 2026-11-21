// Which weapons and weapon profiles a unit attacks with: the calculator's
// defaults, for every unit, weapon and target.
//
// The rules that make this a choice (core rules, Wahapedia wh40k11ed):
//  04.01    Select Weapons. "WHILE SHOOTING You can select one or more ranged
//           weapons that model has. WHILE FIGHTING You must select one melee
//           weapon that model has."
//  24.11    [EXTRA ATTACKS]: all of the model's Extra Attacks weapons, plus
//           "One of that model's other melee weapons".
//  04.01.03 Multiple Weapon Profiles. "if a selected weapon has more than one
//           profile, then the controlling player must also select one of
//           those profiles. ... Hunter profiles can only target units with
//           the specified keywords. ... a different profile can be selected
//           for each model within that unit."
//  24.07    [CLOSE-QUARTERS] (and [PISTOL], 24.27): outside close-quarters
//           shooting, a model that is not a MONSTER / VEHICLE shoots either
//           its [CLOSE-QUARTERS] weapons or its other ranged weapons.
//  10.05    Assault shooting (after an advance): only [ASSAULT] weapons.
//  10.06    Close-quarters shooting (engaged): models that are not MONSTER /
//           VEHICLE shoot only [CLOSE-QUARTERS] weapons.
//
// How the choice is made. Every option that is legal against THIS target is
// scored with the calculator's own engine (simulate() in engine.mjs), with the
// unit's rules, modifiers and situation and the target as it is set up. The
// option that removes the most wounds is used. So the choice cannot disagree
// with the result that is shown, and a rule the engine learns later is part of
// the choice at once. There is no separate formula to keep in step.
//
//  - Score: mean wounds removed from the target, minus the mortal wounds the
//    attacker is expected to take from its own [HAZARDOUS] weapons (06.03: a
//    hazard roll fails on 1-2). A Hazardous profile is used only when it does
//    more damage than it is expected to cost.
//  - A profile that cannot target the unit (Hunter) is never an option.
//  - A ranged weapon need not be fired (04.02: "if you choose not to select a
//    target for a ranged weapon, the model with that weapon will not make
//    attacks with it"): a Hazardous gun that is expected to cost more than it
//    adds stays silent. (In a fight a model must use one melee weapon.)
//  - Options that are equal within the noise of the simulation: the one more
//    likely to destroy the target, then the one that is not Hazardous, then
//    the first in datasheet order.
//  - When one option is at least as good as the other in every characteristic
//    and ability, it wins without a simulation (same answer, no cost).
//  - Options are first scored on their own against the fresh target. Then the
//    choice is checked with the WHOLE unit's attack: each decision is switched
//    in turn and kept only if the unit then does better. That catches what a
//    weapon on its own cannot show: damage that is wasted because the rest of
//    the unit already destroys the target (no Hazardous profile for damage
//    that is not needed), and damage 2 shots landing on models another weapon
//    has already wounded.
//    The Attack tab always makes this check (opts.context 'always'). The
//    matchup grid and the forecast's unit-against-unit odds - hundreds of
//    choices at once - make it when it can matter (opts.context 'auto'): the
//    target or one of its groups is likely to be destroyed, or two options
//    are within 10% of each other on their own.
//
// Pure module: no DOM, no dataset. Used by the page (Attack tab) and by the
// Web Worker (matchup grid, unit-against-unit odds for the forecast).
//
// problem = {
//   phase: 'shooting' | 'fight',
//   shooting: 'normal' | 'assault' | 'cq',   // shooting type; 'normal' when absent
//   groups: [{ id, count, vm }],             // identical models; vm: MONSTER / VEHICLE models
//   rows: [{                                 // one weapon profile of one datasheet in the unit
//     id, wkey,                              // wkey: the weapon (its profiles share the same weapons)
//     extra, cq,                             // [EXTRA ATTACKS]; [CLOSE-QUARTERS] / [PISTOL]
//     usable,                                // false: cannot attack this target / in this situation
//     max,                                   // weapons of this kind in the unit
//     parts: [{ g, n }],                     // how many of them each group of models carries
//     w,                                     // engine weapon (count is set by the choice)
//   }],
//   attacker: { name, mods, allVehicleMonster }, defender,   // engine scenario parts (engine-based choice)
// }

import { simulate, parseDice, diceMean, expectedDamageQuick } from './engine.mjs';

export const CHOICE = {
  trials0: 500,        // first pass, per option
  trialsMax: 8000,     // options that stay close are simulated again with 4x the trials, up to this
  context: 'auto',     // second pass (whole unit): 'always', or 'auto' = when one of the next three holds
  wipe: 0.01,          //   the target is destroyed this often ...
  groupKill: 0.5,      //   ... or the unit removes this share of the models of one of its groups on average ...
  close: 0.10,         //   ... or two options are within this share of each other on their own
  fullRuns: 60,        // most whole-unit simulations of one choice
  tieSe: 2,            // options within this many standard errors are "equal"
  tieRel: 0.004,       // ... or within this share of the better one
  seed: 0xC401CE,
};

const mainSide = (problem) => (problem.shooting ?? 'normal') === 'normal';
const isHaz = (r) => !!(r.w ?? r).kw?.hazardous;

// ---------------------------------------------------------------------------
// Structure: which rows compete with each other

/**
 * The decisions of a problem:
 *  { kind: 'profile', wkey, rows }      two or more usable profiles of one weapon
 *  { kind: 'melee', g, rows }           a group whose models have two or more usable melee weapons / profiles
 *  { kind: 'sidearm', g, cq, main }     a group that shoots its close-quarters weapons or its other weapons
 *  { kind: 'optional', wkey, rows }     a ranged weapon with a Hazardous profile: fire it, or not
 */
export function decisions(problem) {
  const out = [];
  const rows = problem.rows.filter(r => r.usable !== false && r.max > 0);
  const byW = new Map();
  for (const r of rows) (byW.get(r.wkey) ?? byW.set(r.wkey, []).get(r.wkey)).push(r);
  for (const [wkey, list] of byW) if (list.length > 1) out.push({ kind: 'profile', wkey, rows: list.map(r => r.id) });
  if (problem.phase !== 'fight') for (const [wkey, list] of byW) if (list.some(isHaz)) out.push({ kind: 'optional', wkey, rows: list.filter(isHaz).map(r => r.id) });
  for (const g of problem.groups) {
    const mine = rows.filter(r => r.parts.some(p => p.g === g.id && p.n > 0));
    if (problem.phase === 'fight') {
      const main = mine.filter(r => !r.extra);
      if (main.length > 1) out.push({ kind: 'melee', g: g.id, rows: main.map(r => r.id) });
    } else if (!g.vm && mainSide(problem)) {
      const cq = mine.filter(r => r.cq), main = mine.filter(r => !r.cq);
      if (cq.length && main.length) out.push({ kind: 'sidearm', g: g.id, cq: cq.map(r => r.id), main: main.map(r => r.id) });
    }
  }
  return out;
}

/**
 * Families: rows whose counts depend on each other (profiles of one weapon,
 * the melee weapons of one model, close-quarters or other weapons). Usable or
 * not: a blocked Hunter profile is still in the family of its weapon.
 * -> Map(row id -> family id); a row on its own gets no entry.
 */
export function families(problem) {
  const parent = new Map(problem.rows.map(r => [r.id, r.id]));
  const find = (x) => { while (parent.get(x) !== x) { parent.set(x, parent.get(parent.get(x))); x = parent.get(x); } return x; };
  const join = (a, b) => { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(rb, ra); };
  const rows = problem.rows.filter(r => r.max > 0);
  const byW = new Map();
  for (const r of rows) { if (byW.has(r.wkey)) join(byW.get(r.wkey), r.id); else byW.set(r.wkey, r.id); }
  for (const g of problem.groups) {
    const mine = rows.filter(r => r.parts.some(p => p.g === g.id && p.n > 0));
    if (problem.phase === 'fight') {
      const main = mine.filter(r => !r.extra);
      for (let i = 1; i < main.length; i++) join(main[0].id, main[i].id);
    } else if (!g.vm && mainSide(problem) && mine.some(r => r.cq) && mine.some(r => !r.cq)) {
      for (let i = 1; i < mine.length; i++) join(mine[0].id, mine[i].id);
    }
  }
  const size = new Map();
  for (const r of rows) size.set(find(r.id), (size.get(find(r.id)) ?? 0) + 1);
  const out = new Map();
  // (a Hazardous gun on its own is a choice too: fire it or not)
  for (const r of rows) if (size.get(find(r.id)) > 1 || (problem.phase !== 'fight' && isHaz(r))) out.set(r.id, find(r.id));
  return out;
}

// ---------------------------------------------------------------------------
// "At least as good in every respect" (no simulation needed)

function diceGE(x, y) {
  const a = parseDice(x), b = parseDice(y);
  if (a.n === b.n && a.sides === b.sides) return a.plus >= b.plus;
  return a.n + a.plus >= b.n * b.sides + b.plus;      // the least of a is at least the most of b
}

/**
 * Is engine weapon `a` at least as good as `b` against any target, weapon for
 * weapon? Conservative: false whenever it is not obvious.
 */
export function dominates(a, b) {
  if (!a || !b || !!a.melee !== !!b.melee) return false;
  if (JSON.stringify(a.mods ?? null) !== JSON.stringify(b.mods ?? null)) return false;
  const ka = a.kw ?? {}, kb = b.kw ?? {};
  const torA = !!ka.torrent || a.skill == null, torB = !!kb.torrent || b.skill == null;
  if (!torA && (torB || Number(a.skill) > Number(b.skill))) return false;
  if (!diceGE(a.A, b.A) || !diceGE(a.D, b.D)) return false;
  if (Number(a.S) < Number(b.S) || Math.abs(Number(a.AP) || 0) < Math.abs(Number(b.AP) || 0)) return false;
  // abilities that help: a must have each one b has, at least as strong
  for (const k of ['lethal', 'dev', 'twin', 'lance', 'ignoresCover', 'heavy']) if (kb[k] && !ka[k]) return false;
  for (const k of ['blast', 'cleave', 'rapidFire', 'melta']) if ((kb[k] || 0) > (ka[k] || 0)) return false;
  if ((kb.sustained || 0) > 0) {
    const same = (ka.sustained || 0) === kb.sustained && !!ka.sustainedDice === !!kb.sustainedDice;
    const more = (ka.sustained || 0) >= kb.sustained && !ka.sustainedDice;   // a fixed value at least b's highest
    if (!same && !more) return false;
  }
  for (const an of kb.anti ?? []) {
    if (!(ka.anti ?? []).some(x => String(x.keyword).toUpperCase() === String(an.keyword).toUpperCase() && x.threshold <= an.threshold)) return false;
  }
  // abilities that change more than the damage, or that cost something: the same on both
  for (const k of ['hazardous', 'psychic', 'precision', 'indirect', 'extraAttacks']) if (!!ka[k] !== !!kb[k]) return false;
  return true;
}

/**
 * Does every weapon of `weak` have its own partner in `strong` that is at least
 * as good, in at least the same number? ({ r: row, n } items)
 */
function covers(strong, weak) {
  const left = strong.slice();
  return weak.every(wk => {
    const i = left.findIndex(s => s.n >= wk.n && dominates(s.r.w ?? s.r, wk.r.w ?? wk.r));
    if (i < 0) return false;
    left.splice(i, 1);
    return true;
  });
}

// ---------------------------------------------------------------------------
// Solve: counts from a value per weapon

const TIE = (A, B) => Math.max(CHOICE.tieSe * Math.hypot(A.se ?? 0, B.se ?? 0), CHOICE.tieRel * Math.max(Math.abs(A.v), Math.abs(B.v)));

/** Is option a (stats A) better than option b (stats B)? Equal within the noise: see the header. */
function better(a, b, A, B) {
  const wa = a.w ?? a, wb = b.w ?? b;      // a row carries its engine weapon, or is weapon-shaped itself
  const ab = dominates(wa, wb), ba = dominates(wb, wa);
  if (ab !== ba) return ab;
  if (Math.abs(A.v - B.v) > TIE(A, B)) return A.v > B.v;
  if (Math.abs((A.pWipe ?? 0) - (B.pWipe ?? 0)) > 0.01) return (A.pWipe ?? 0) > (B.pWipe ?? 0);
  if (!!wa.kw?.hazardous !== !!wb.kw?.hazardous) return !wa.kw?.hazardous;
  return false;
}

/** Best first (a selection sort with `better`, which is not a strict order when values are close). */
function ranked(items, stat) {
  const left = items.slice(), out = [];
  while (left.length) {
    let bi = 0;
    for (let i = 1; i < left.length; i++) if (better(left[i].r, left[bi].r, stat(left[i].r), stat(left[bi].r))) bi = i;
    out.push(left.splice(bi, 1)[0]);
  }
  return out;
}

/**
 * Counts for every row from `stat(row)` -> { v: value of ONE weapon of this row, se?, pWipe? }.
 * -> { [row id]: number of weapons that attack }
 */
export function solveCounts(problem, stat, force = {}, made = null) {
  // force: decisions that are fixed - { profile: { [wkey]: row id }, melee: { [group]: row id }, side: { [group]: 'cq' | 'main' } }
  // made: filled with the decisions taken, in the same shape
  const fp = force.profile ?? {}, fm = force.melee ?? {}, fs = force.side ?? {}, fo = force.off ?? {};
  if (made) { made.profile = {}; made.melee = {}; made.side = {}; made.off = {}; }
  const counts = Object.fromEntries(problem.rows.map(r => [r.id, 0]));
  const usable = problem.rows.filter(r => r.usable !== false && r.max > 0 && (fp[r.wkey] == null || fp[r.wkey] === r.id));
  for (const g of problem.groups) {
    const items = usable.map(r => ({ r, n: r.parts.find(p => p.g === g.id)?.n ?? 0 })).filter(x => x.n > 0);
    if (!items.length) continue;
    if (problem.phase === 'fight') {
      // every Extra Attacks weapon, with its best profile
      const extraByW = new Map();
      for (const it of items.filter(x => x.r.extra)) (extraByW.get(it.r.wkey) ?? extraByW.set(it.r.wkey, []).get(it.r.wkey)).push(it);
      for (const list of extraByW.values()) { const top = ranked(list, stat)[0]; counts[top.r.id] += top.n; if (made) made.profile[top.r.wkey] = top.r.id; }
      // one other melee weapon per model: the best weapons first
      let models = g.count;
      const used = new Map();
      let order = ranked(items.filter(x => !x.r.extra), stat);
      if (fm[g.id] != null) order = [...order.filter(x => x.r.id === fm[g.id]), ...order.filter(x => x.r.id !== fm[g.id])];
      for (const it of order) {
        if (models <= 0) break;
        const take = Math.min(it.n - (used.get(it.r.wkey) ?? 0), models);
        if (take <= 0) continue;
        counts[it.r.id] += take;
        used.set(it.r.wkey, (used.get(it.r.wkey) ?? 0) + take);
        models -= take;
        if (made) { made.melee[g.id] ??= it.r.id; made.profile[it.r.wkey] ??= it.r.id; }
      }
    } else {
      // every ranged weapon, with its best profile ...
      const byW = new Map();
      for (const it of items) (byW.get(it.r.wkey) ?? byW.set(it.r.wkey, []).get(it.r.wkey)).push(it);
      const best = (list) => (list.length ? ranked(list, stat)[0] : null);
      let picks;
      // ... but close-quarters weapons or the others, not both (24.07). A weapon can have a profile on each
      // side (e.g. "Ranged" and "Close Quarters"): each side is taken with its own best profiles.
      if (!g.vm && mainSide(problem) && items.some(x => x.r.cq) && items.some(x => !x.r.cq)) {
        const side = (cq) => [...byW.values()].map(list => best(list.filter(x => !!x.r.cq === cq))).filter(Boolean);
        const total = (list) => list.reduce((acc, p) => { const s = stat(p.r); return { v: acc.v + p.n * s.v, se: Math.hypot(acc.se, p.n * (s.se ?? 0)) }; }, { v: 0, se: 0 });
        const cqs = side(true), mains = side(false);
        const C = total(cqs), M = total(mains);
        const domC = covers(cqs, mains), domM = covers(mains, cqs);
        const cq = fs[g.id] != null ? fs[g.id] === 'cq' : (domC !== domM ? domC : C.v - M.v > TIE(C, M));     // equal: the main weapons
        picks = cq ? cqs : mains;
        if (made) made.side[g.id] = cq ? 'cq' : 'main';
      } else picks = [...byW.values()].map(best).filter(Boolean);
      for (const p of picks) {
        if (isHaz(p.r)) {
          // a Hazardous gun stays silent when it is expected to cost more than it adds (a simulated score only)
          const s = stat(p.r);
          const off = fo[p.r.wkey] != null ? fo[p.r.wkey] === true : !!s.sim && s.v <= 0;
          if (made) made.off[p.r.wkey] = off;
          if (off) continue;
        }
        counts[p.r.id] += p.n;
        if (made) made.profile[p.r.wkey] = p.r.id;
      }
    }
  }
  return counts;
}

/** The analytic value used when there is no target or no engine context (lists, first guess). */
export function quickStat(row, target = {}) {
  const w = row.w ?? row;
  return { v: expectedDamageQuick(w, target.T ?? 4, target.Sv ?? 3, target.InSv ?? 0) };
}

// ---------------------------------------------------------------------------
// The engine-based choice

function simRow(problem, row, trials) {
  const a = problem.attacker ?? {};
  const mods = { ...(a.mods ?? {}) };
  delete mods.mortals;            // ability mortal wounds do not depend on the weapon
  const r = simulate({
    phase: problem.phase,
    attackers: [{ name: a.name ?? 'unit', mods, allVehicleMonster: !!a.allVehicleMonster, weapons: [{ ...row.w, count: row.max }] }],
    defender: problem.defender, trials, seed: CHOICE.seed,
  });
  let varW = 0;
  for (let i = 0; i < r.wounds.length; i++) varW += r.wounds[i] * (i - r.meanWounds) ** 2;
  const net = r.meanWounds - r.hazardMW;
  return {
    v: net / row.max, se: Math.sqrt(varW / trials) / row.max,
    net, wounds: r.meanWounds, kills: r.meanKills, hazard: r.hazardMW, pWipe: r.pWipe, trials, sim: true,
  };
}

/** Can every decision of these rows be settled by "at least as good in every respect"? */
function settledByDominance(problem, ds, byId) {
  for (const d of ds) {
    if (d.kind === 'optional') return false;       // Hazardous: what it costs against what it adds
    if (d.kind === 'sidearm') {
      const pickN = (ids) => ids.map(id => byId.get(id)).map(r => ({ r, n: r.parts.find(p => p.g === d.g)?.n ?? 0 }));
      // every profile of the weaker side needs a partner (stricter than needed: then it is simulated instead)
      if (!covers(pickN(d.main), pickN(d.cq)) && !covers(pickN(d.cq), pickN(d.main))) return false;
    } else {
      const list = d.rows.map(id => byId.get(id));
      // a chain: one option at least as good as every other, and so on down
      const W = (r) => r.w ?? r;
      const order = list.slice().sort((x, y) => (dominates(W(x), W(y)) ? -1 : dominates(W(y), W(x)) ? 1 : 0));
      for (let i = 0; i < order.length; i++) for (let j = i + 1; j < order.length; j++) if (!dominates(W(order[i]), W(order[j]))) return false;
    }
  }
  return true;
}

/**
 * The weapons a unit attacks with, chosen with the engine.
 * -> { counts: { [row id]: n }, notes: Map(row id -> { v, net, wounds, hazard, pWipe, sim, settled, fam }), sims }
 */
export function chooseWeapons(problem, opts = {}) {
  const cfg = { ...CHOICE, ...opts };
  const byId = new Map(problem.rows.map(r => [r.id, r]));
  const fam = families(problem);
  const ds = decisions(problem);
  const stats = new Map();
  let sims = 0;
  const target = problem.target ?? {};
  for (const r of problem.rows) stats.set(r.id, quickStat(r, target));
  const canSim = !!problem.defender && problem.rows.every(r => !!r.w);
  // decisions grouped by family
  const famOf = (d) => fam.get(d.kind === 'sidearm' ? d.cq[0] : d.rows[0]);
  const byFam = new Map();
  for (const d of ds) (byFam.get(famOf(d)) ?? byFam.set(famOf(d), []).get(famOf(d))).push(d);
  const notes = new Map();
  const open = [];        // decisions that are a real trade-off (not settled by "at least as good in every way")
  let closeCall = false;  // ... and one of them is close on the options' own scores
  for (const [f, list] of byFam) {
    const ids = [...new Set(list.flatMap(d => (d.kind === 'sidearm' ? [...d.cq, ...d.main] : d.rows)))];
    const settled = settledByDominance(problem, list, byId);
    if (!settled) open.push(...list);
    if (canSim && !settled) {
      let trials = cfg.trials0, todo = new Set(ids);
      for (;;) {
        for (const id of todo) { stats.set(id, simRow(problem, byId.get(id), trials)); sims++; }
        if (trials >= cfg.trialsMax) break;
        // which options are still too close to call?
        todo = new Set();
        for (const d of list) {
          if (d.kind === 'optional') {
            // fire or not: is the score clearly above or below zero?
            for (const id of d.rows) { const s = stats.get(id); if (s.se > 0 && Math.abs(s.v) <= 1.5 * CHOICE.tieSe * s.se) todo.add(id); }
          } else if (d.kind === 'sidearm') {
            const sum = (idsOf) => idsOf.reduce((acc, id) => { const s = stats.get(id), n = byId.get(id).parts.find(p => p.g === d.g)?.n ?? 0; return { v: acc.v + n * s.v, se: Math.hypot(acc.se, n * (s.se ?? 0)) }; }, { v: 0, se: 0 });
            const C = sum(d.cq), M = sum(d.main);
            if ((C.se > 0 || M.se > 0) && Math.abs(C.v - M.v) <= 1.5 * TIE(C, M)) for (const id of [...d.cq, ...d.main]) todo.add(id);
          } else {
            const order = d.rows.slice().sort((x, y) => stats.get(y).v - stats.get(x).v);
            for (let i = 1; i < order.length; i++) {
              const A = stats.get(order[0]), B = stats.get(order[i]);
              // (no spread at all: the same fixed result, e.g. nothing can be wounded - more trials change nothing)
              if ((A.se > 0 || B.se > 0) && Math.abs(A.v - B.v) <= 1.5 * TIE(A, B)) { todo.add(order[0]); todo.add(order[i]); }
            }
          }
        }
        if (!todo.size) break;
        trials = Math.min(cfg.trialsMax, trials * 4);
      }
      // a close call on the options' own scores?
      const near = (a, b) => Math.abs(a - b) <= cfg.close * Math.max(Math.abs(a), Math.abs(b), 1e-9);
      for (const d of list) {
        if (d.kind === 'optional') { if (d.rows.some(id => { const s = stats.get(id); return Math.abs(s.net) <= 0.3 * (s.hazard || 0); })) closeCall = true; }
        else if (d.kind === 'sidearm') {
          const sum = (idsOf) => idsOf.reduce((acc, id) => acc + (byId.get(id).parts.find(p => p.g === d.g)?.n ?? 0) * stats.get(id).v, 0);
          if (near(sum(d.cq), sum(d.main))) closeCall = true;
        } else {
          const vs = d.rows.map(id => stats.get(id).v).sort((x, y) => y - x);
          if (near(vs[0], vs[1])) closeCall = true;
        }
      }
    }
    for (const id of ids) notes.set(id, { ...stats.get(id), fam: f, settled: settled || !canSim });
  }
  const stat = (r) => stats.get(r.id);
  const made = {};
  let counts = solveCounts(problem, stat, {}, made);
  // second pass: the whole unit's attack, when it is likely to destroy the target or one of its groups
  // (an option that is at least as good in every way stays at least as good there: only the trade-offs)
  let fullRuns = 0, inContext = false;
  if (canSim && open.length) {
    const seen = new Map();
    const full = (c, trials) => {
      const key = `${trials}|${JSON.stringify(c)}`;
      if (!seen.has(key)) { seen.set(key, simFull(problem, c, trials)); fullRuns++; }
      return seen.get(key);
    };
    const cur = cfg.context === 'always' || closeCall ? null : full(counts, cfg.trials0);
    if (!cur || cur.pWipe > cfg.wipe || cur.groupKill > cfg.groupKill) {
      inContext = true;
      let force = { profile: { ...made.profile }, melee: { ...made.melee }, side: { ...made.side }, off: { ...made.off } };
      for (let sweep = 0, moved = true; moved && sweep < 3; sweep++) {
        moved = false;
        for (const step of neighbours(open, force, byId)) {
          if (fullRuns >= cfg.fullRuns) break;
          const f2 = { profile: { ...force.profile, ...step.profile }, melee: { ...force.melee, ...step.melee }, side: { ...force.side, ...step.side }, off: { ...force.off, ...step.off } };
          const m2 = {};
          const c2 = solveCounts(problem, stat, f2, m2);
          if (JSON.stringify(c2) === JSON.stringify(counts)) continue;
          // the same trials for both; closer than the noise: again with more
          let trials = cfg.trials0, A = full(c2, trials), B = full(counts, trials);
          while (trials < cfg.trialsMax && (A.se > 0 || B.se > 0) && Math.abs(A.v - B.v) <= 1.5 * TIE(A, B)) { trials = Math.min(cfg.trialsMax, trials * 4); A = full(c2, trials); B = full(counts, trials); }
          const wins = Math.abs(A.v - B.v) > TIE(A, B) ? A.v > B.v : A.pWipe - B.pWipe > 0.01;
          if (wins) { counts = c2; force = { profile: { ...f2.profile, ...m2.profile }, melee: { ...f2.melee, ...m2.melee }, side: { ...f2.side, ...m2.side }, off: { ...f2.off, ...m2.off } }; moved = true; }
        }
      }
    }
  }
  if (inContext) for (const [id, n] of notes) notes.set(id, { ...n, inContext: true });
  return { counts, notes, sims: sims + fullRuns, families: fam, inContext };
}

/** The whole unit's attack with these counts. */
function simFull(problem, counts, trials) {
  const a = problem.attacker ?? {};
  const weapons = weaponsFor(problem, counts);
  if (!weapons.length) return { v: 0, se: 0, pWipe: 0, groupKill: 0 };
  const r = simulate({
    phase: problem.phase,
    attackers: [{ name: a.name ?? 'unit', mods: a.mods ?? {}, allVehicleMonster: !!a.allVehicleMonster, weapons }],
    defender: problem.defender, trials, seed: CHOICE.seed + 1,
  });
  let varW = 0;
  for (let i = 0; i < r.wounds.length; i++) varW += r.wounds[i] * (i - r.meanWounds) ** 2;
  return {
    v: r.meanWounds - r.hazardMW, se: Math.sqrt(varW / trials), pWipe: r.pWipe,
    groupKill: Math.max(0, ...r.groupKills.map(g => (g.count > 0 ? g.mean / g.count : 0))),
  };
}

/** One decision switched to another option: the overrides to try. */
function neighbours(ds, force, byId) {
  const out = [];
  for (const d of ds) {
    if (d.kind === 'profile') {
      const cur = force.profile[d.wkey];
      if (cur == null) continue;        // that weapon is not in use (the other side, or another melee weapon)
      for (const id of d.rows) if (id !== cur) out.push({ profile: { [d.wkey]: id } });
    } else if (d.kind === 'melee') {
      for (const id of d.rows) if (id !== force.melee[d.g]) out.push({ melee: { [d.g]: id }, profile: { [byId.get(id).wkey]: id } });
    } else if (d.kind === 'optional') {
      out.push({ off: { [d.wkey]: force.off?.[d.wkey] !== true } });       // silent <-> firing
    } else {
      // the other side, with that side's own best profiles (the profiles fixed for this side are released)
      const free = Object.fromEntries([...d.cq, ...d.main].map(id => [byId.get(id).wkey, undefined]));
      out.push({ side: { [d.g]: force.side[d.g] === 'cq' ? 'main' : 'cq' }, profile: free });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Counts set by hand: what is possible

/**
 * Can these counts be fielded? Each weapon is used with one profile, and in a
 * fight each model uses one melee weapon besides its Extra Attacks weapons.
 * (Close-quarters or other weapons is not checked here: see overSidearms.)
 */
export function feasible(problem, counts) {
  // max-flow: source -> row (count) -> (group, weapon) (weapons carried) -> group (models; fight, not Extra Attacks) -> sink
  const N = [], idx = new Map();
  const node = (k) => { if (!idx.has(k)) { idx.set(k, N.length); N.push([]); } return idx.get(k); };
  const edge = (u, v, c) => { const a = { to: v, cap: c, rev: null }, b = { to: u, cap: 0, rev: a }; a.rev = b; N[u].push(a); N[v].push(b); };
  const S = node('S'), T = node('T');
  let want = 0;
  const seenGW = new Set(), seenG = new Set();
  for (const r of problem.rows) {
    const c = Math.max(0, counts[r.id] ?? 0);
    if (!c) continue;
    if (c > r.max) return false;
    want += c;
    edge(S, node(`r:${r.id}`), c);
    const grouped = problem.phase === 'fight' && !r.extra;
    for (const p of r.parts) {
      const gw = `gw:${p.g}:${r.wkey}`;
      edge(node(`r:${r.id}`), node(gw), p.n);
      if (!seenGW.has(gw)) {
        seenGW.add(gw);
        if (grouped) {
          edge(node(gw), node(`g:${p.g}`), p.n);
          if (!seenG.has(p.g)) { seenG.add(p.g); edge(node(`g:${p.g}`), T, problem.groups.find(g => g.id === p.g)?.count ?? 0); }
        } else edge(node(gw), T, p.n);
      }
    }
  }
  let flow = 0;
  for (;;) {
    const seen = new Array(N.length).fill(false);
    const dfs = (u, f) => {
      if (u === T) return f;
      seen[u] = true;
      for (const e of N[u]) {
        if (e.cap > 0 && !seen[e.to]) { const d = dfs(e.to, Math.min(f, e.cap)); if (d > 0) { e.cap -= d; e.rev.cap += d; return d; } }
      }
      return 0;
    };
    const f = dfs(S, Infinity);
    if (!f) break;
    flow += f;
  }
  return flow === want;
}

/**
 * Change one count by hand and keep the set possible: a count that goes up
 * takes weapons from the other rows of its family (the largest first).
 * -> the new counts of the family rows, { [row id]: n }
 */
export function adjustCount(problem, counts, rowId, delta) {
  const fam = families(problem);
  const row = problem.rows.find(r => r.id === rowId);
  if (!row || row.usable === false) return {};
  const mates = problem.rows.filter(r => fam.has(rowId) && fam.get(r.id) === fam.get(rowId));
  const next = { ...counts };
  next[rowId] = Math.max(0, Math.min(row.max, (counts[rowId] ?? 0) + delta));
  if (delta > 0) {
    for (let guard = 0; guard < 400 && !feasible(problem, next); guard++) {
      const donor = mates.filter(r => r.id !== rowId && (next[r.id] ?? 0) > 0).sort((a, b) => (next[b.id] ?? 0) - (next[a.id] ?? 0))[0];
      if (donor) next[donor.id]--; else { next[rowId]--; if (next[rowId] <= (counts[rowId] ?? 0)) break; }
    }
  }
  const out = { [rowId]: next[rowId] };
  for (const r of mates) out[r.id] = next[r.id] ?? 0;
  return out;
}

/**
 * 24.07: models (not MONSTER / VEHICLE) that are set to shoot both their
 * close-quarters weapons and their other weapons. -> true when the counts
 * need more models than the unit has.
 */
export function overSidearms(problem, counts) {
  if (problem.phase !== 'shooting' || !mainSide(problem)) return false;
  const vm = new Set(problem.groups.filter(g => g.vm).map(g => g.id));
  const rows = problem.rows.filter(r => r.parts.some(p => p.n > 0 && !vm.has(p.g)));
  if (!rows.some(r => r.cq) || !rows.some(r => !r.cq)) return false;
  // the largest count on each side is at least the number of models that use that side
  const most = (cq) => Math.max(0, ...rows.filter(r => !!r.cq === cq).map(r => counts[r.id] ?? 0));
  const models = problem.groups.filter(g => !g.vm).reduce((a, g) => a + g.count, 0);
  return most(true) > 0 && most(false) > 0 && most(true) + most(false) > models;
}

// ---------------------------------------------------------------------------
// Engine scenario parts

/** Engine weapons for these counts. */
export function weaponsFor(problem, counts) {
  return problem.rows.filter(r => (counts[r.id] ?? 0) > 0 && r.w).map(r => ({ ...r.w, count: counts[r.id] }));
}

/**
 * A scenario whose attackers may carry `choice` (a problem without attacker /
 * defender / phase: they are the scenario's own): choose, and return a plain
 * engine scenario. The Web Worker calls this for the matchup grid and the
 * forecast's unit-against-unit odds, so the page does not wait for it.
 */
export function resolveScenario(sc, opts = {}) {
  if (!sc?.attackers?.some(a => a.choice)) return sc;
  return {
    ...sc,
    attackers: sc.attackers.map(a => {
      if (!a.choice) return a;
      const { choice, ...rest } = a;
      const problem = { ...choice, phase: sc.phase, defender: sc.defender, attacker: { name: a.name, mods: a.mods, allVehicleMonster: a.allVehicleMonster } };
      const { counts } = chooseWeapons(problem, opts);
      return { ...rest, weapons: weaponsFor(problem, { ...counts, ...(choice.fixed ?? {}) }) };
    }),
  };
}
