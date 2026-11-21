// Shared by tests/calc-choose.test.mjs (a sample) and tests/audit-weapon-choice.mjs (every datasheet):
// build an attacking unit from ANY datasheet of the rules data, let choose.mjs pick its weapons against a
// panel of targets, and check the pick against an independent, larger simulation of the whole unit's attack.
//
// The check: no single change makes the unit better.
//  - leave out a weapon row that was picked (the app then picks the best replacement) -> not better;
//  - force in a row that was not picked (its rivals are removed) -> not better.
// "Better" is judged on mean wounds removed minus the attacker's own expected Hazardous wounds, with a
// different seed and more trials than the choice used.
import { simulate } from '../../public/calc/engine.mjs';
import * as C from '../../public/calc/choose.mjs';
import * as A from '../../public/calc/adapter.mjs';
import * as dc from '../../public/js/vendor/40kdc-data.mjs';

export const RAW = dc.RAW_DATA;

/** Targets that pull the choice in different directions (and carry every Hunter keyword in the data). */
export const PANEL = [
  { name: 'horde: 20 x T3 W1 Sv5+', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 20, W: 1, Sv: 5, InSv: 0, T: 3 }] },
  { name: 'marines: 10 x T4 W2 Sv3+', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 10, W: 2, Sv: 3, InSv: 0, T: 4 }] },
  { name: 'terminators: 5 x T5 W3 Sv2+ 4++', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 5, W: 3, Sv: 2, InSv: 4, T: 5 }] },
  { name: 'custodes: 4 x T6 W4 Sv2+ 4++', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 4, W: 4, Sv: 2, InSv: 4, T: 6 }] },
  { name: 'character: 1 x T4 W5 Sv3+ 4++', keywords: ['INFANTRY', 'CHARACTER'], groups: [{ name: 'g', count: 1, W: 5, Sv: 3, InSv: 4, T: 4, character: true }] },
  { name: 'vehicle: T10 W13 Sv3+', keywords: ['VEHICLE'], groups: [{ name: 'g', count: 1, W: 13, Sv: 3, InSv: 0, T: 10 }] },
  { name: 'monster: T11 W18 Sv2+ 5++', keywords: ['MONSTER'], groups: [{ name: 'g', count: 1, W: 18, Sv: 2, InSv: 5, T: 11 }] },
  { name: 'flyer: T9 W12 Sv3+', keywords: ['VEHICLE', 'FLY', 'AIRCRAFT'], groups: [{ name: 'g', count: 1, W: 12, Sv: 3, InSv: 0, T: 9 }] },
];

const summaryOf = (t) => ({ T: t.groups[0].T, Sv: t.groups[0].Sv, InSv: t.groups[0].InSv, W: t.groups[0].W, models: t.groups[0].count, keywords: t.keywords });
const defenderOf = (t) => ({ name: t.name, keywords: t.keywords, groups: t.groups, mods: {} });

/** A combat unit with every weapon its datasheet lists, on every model (the hardest case for the choice). */
export function unitOf(unit) {
  const mc = unit.model_count;
  const n = Math.max(1, Number(typeof mc === 'object' ? mc?.max ?? mc?.min : mc) || 1);
  const roster = { faction_id: unit.faction_id, detachments: [], units: [{ ref: { id: unit.id }, model_count: n, points: 100, wargear: (unit.weapon_ids ?? []).map(id => ({ ref: { id }, count: n })) }] };
  return A.combatUnits(roster)[0] ?? null;
}

/** The choice problem of `cu` in `phase` against panel target `t` (weapons only: no unit rules). */
export function problemOf(cu, phase, t) {
  const rows = A.attackerRows(cu, phase, summaryOf(t));
  if (!rows.length) return null;
  return A.choiceProblem(cu, rows, {}, [], new Set(), phase, defenderOf(t), summaryOf(t));
}

function oracle(problem, counts, trials, seed) {
  const weapons = C.weaponsFor(problem, counts);
  if (!weapons.length) return { net: 0, se: 0 };
  const r = simulate({ phase: problem.phase, attackers: [{ name: 'u', mods: problem.attacker?.mods ?? {}, weapons, allVehicleMonster: !!problem.attacker?.allVehicleMonster }], defender: problem.defender, trials, seed });
  let v = 0;
  for (let i = 0; i < r.wounds.length; i++) v += r.wounds[i] * (i - r.meanWounds) ** 2;
  return { net: r.meanWounds - r.hazardMW, se: Math.sqrt(v / trials) };
}

/**
 * Check one problem. -> { decisions, sims, worst: largest shortfall found (wounds), fails: [...] }
 * tol: a pick may be worse than an alternative by at most max(rel * alternative, abs) + 3 standard errors.
 */
export function auditProblem(problem, { trials = 6000, seed = 20261120, rel = 0.03, abs = 0.05, context = 'always' } = {}) {
  const ds = C.decisions(problem);
  if (!ds.length) return { decisions: 0, sims: 0, worst: 0, fails: [] };
  const res = C.chooseWeapons(problem, { context });
  const base = oracle(problem, res.counts, trials, seed);
  const fails = [];
  let worst = 0;
  const judge = (label, p2, c2) => {
    if (JSON.stringify(c2) === JSON.stringify(res.counts)) return false;
    const alt = oracle(p2, c2, trials, seed);
    const short = alt.net - base.net;
    const allow = Math.max(rel * Math.abs(alt.net), abs) + 3 * Math.hypot(alt.se, base.se);
    if (short > worst) worst = short;
    if (short > allow) fails.push({ label, picked: +base.net.toFixed(3), alternative: +alt.net.toFixed(3), allow: +allow.toFixed(3), counts: res.counts, altCounts: c2 });
    return true;
  };
  const variant = (label, rowsUsable) => {
    const p2 = { ...problem, rows: problem.rows.map(r => ({ ...r, usable: rowsUsable(r) })) };
    return judge(label, p2, C.chooseWeapons(p2, { context }).counts);
  };
  const fam = res.families;
  for (const r of problem.rows) {
    if (r.usable === false || !fam.has(r.id)) continue;
    if ((res.counts[r.id] ?? 0) > 0) variant(`without ${r.w.name}`, (x) => x.usable !== false && x.id !== r.id);
    else {
      // force it in: its rivals are the other profiles of its weapon, the other melee weapons of its models,
      // and the other side of "close-quarters or other weapons"
      const rivals = new Set();
      for (const d of ds) {
        if (d.kind === 'sidearm') { if (d.cq.includes(r.id)) d.main.forEach(id => rivals.add(id)); else if (d.main.includes(r.id)) d.cq.forEach(id => rivals.add(id)); } else if (d.rows.includes(r.id)) d.rows.forEach(id => { if (id !== r.id) rivals.add(id); });
      }
      const tried = variant(`forcing ${r.w.name}`, (x) => x.usable !== false && !rivals.has(x.id));
      // a Hazardous gun the app left silent: fire it all the same (with this profile)
      if (!tried && problem.phase !== 'fight' && r.w.kw?.hazardous) {
        const c2 = { ...res.counts, [r.id]: r.max };
        for (const x of problem.rows) if (x.wkey === r.wkey && x.id !== r.id) c2[x.id] = 0;
        if (C.feasible(problem, c2) && !C.overSidearms(problem, c2)) judge(`firing ${r.w.name}`, problem, c2);
      }
    }
  }
  return { decisions: ds.length, sims: res.sims, worst, fails };
}
