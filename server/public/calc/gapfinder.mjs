// List gap-finder: how much of eight fixed reference targets your whole list removes in one turn (shooting and
// fighting), to see what the list is missing before you know the opponents. The stat lines are from 11th edition
// datasheets (named below); they carry no special rules, so the result is about your list, not a faction.
// Pure: tests/calc-gapfinder.test.mjs. app.js runs the attacks (worker.mjs) and draws the sheet.

export const GAP_TARGETS = [
  { id: 'horde', name: 'Light horde', like: 'Cadian Shock Troops, Termagants', n: 20, T: 3, Sv: 5, W: 1, kw: ['INFANTRY'] },
  { id: 'tough-horde', name: 'Tough horde', like: 'Ork Boyz', n: 20, T: 5, Sv: 5, W: 1, kw: ['INFANTRY'] },
  { id: 'elite', name: 'Elite infantry', like: 'Intercessor Squad', n: 5, T: 5, Sv: 3, W: 2, kw: ['INFANTRY'] },
  { id: 'heavy', name: 'Heavy infantry', like: 'Terminator Squad', n: 5, T: 6, Sv: 2, inv: 4, W: 3, kw: ['INFANTRY'] },
  { id: 'transport', name: 'Transport', like: 'Rhino', n: 1, T: 9, Sv: 3, W: 10, kw: ['VEHICLE', 'TRANSPORT'] },
  { id: 'monster', name: 'Monster', like: 'Carnifexes (one)', n: 1, T: 9, Sv: 2, W: 8, kw: ['MONSTER'] },
  { id: 'tank', name: 'Battle tank', like: 'Leman Russ Battle Tank', n: 1, T: 11, Sv: 2, W: 13, kw: ['VEHICLE'] },
  { id: 'knight', name: 'Knight', like: 'Knight Paladin', n: 1, T: 11, Sv: 3, invRanged: 5, W: 26, kw: ['VEHICLE', 'TITANIC'] },
];

/** The defender profile (adapter.defenderProfile shape) of a reference target in a phase. */
export function gapProfile(t, phase) {
  const inv = t.inv ?? (phase === 'shooting' ? t.invRanged ?? 0 : 0);
  return {
    name: t.name, keywords: [...t.kw], rules: [], stratText: '',
    groups: [{ key: `gap-${t.id}`, name: t.name, member: 0, count: t.n, W: t.W, Sv: t.Sv, InSv: inv, T: t.T, character: false, ptsPerModel: 0, wargearNames: [] }],
  };
}
/** "T5 · 3+ · W2 × 5" */
export const gapStats = (t) => `T${t.T} · ${t.Sv}+${t.inv ? ` · ${t.inv}++` : t.invRanged ? ` · ${t.invRanged}++ vs shooting` : ''} · W${t.W}${t.n > 1 ? ` × ${t.n}` : ''}`;

/**
 * cells: [{ unit, name, target, phase, frac }] — frac = share of the target's wounds one unit deals on average
 * (0..1). -> per target, in GAP_TARGETS order:
 * { id, name, shoot, fight, total, best: [{ unit, name, frac, phase }], level: 'gap' | 'thin' | 'ok', weakest }
 * shoot: how many of that target the whole list removes in one shooting phase (each unit at most one target's
 * worth); fight: the best `fighters` units in one fight phase (not every unit gets into combat in a turn);
 * level: total < 1 'gap' (not even one a turn), < 2 'thin'; meleeOnly: the shooting removes under half of one.
 */
export function gapSummary(cells, { fighters = 3 } = {}) {
  const out = GAP_TARGETS.map((t) => {
    const mine = cells.filter(c => c.target === t.id && Number.isFinite(c.frac));
    const fr = (ph) => mine.filter(c => c.phase === ph).map(c => Math.min(1, c.frac)).sort((a, b) => b - a);
    const shoot = fr('shooting').reduce((s, v) => s + v, 0), fight = fr('fight').slice(0, fighters).reduce((s, v) => s + v, 0), total = shoot + fight;
    const byUnit = new Map();
    for (const c of mine) if (!byUnit.has(c.unit) || byUnit.get(c.unit).frac < c.frac) byUnit.set(c.unit, { unit: c.unit, name: c.name, frac: Math.min(1, c.frac), phase: c.phase });
    const best = [...byUnit.values()].filter(b => b.frac > 0.005).sort((a, b) => b.frac - a.frac).slice(0, 3);
    return { id: t.id, name: t.name, shoot, fight, total, best, level: total < 1 ? 'gap' : total < 2 ? 'thin' : 'ok', meleeOnly: shoot < 0.5, weakest: false };
  });
  const low = Math.min(...out.map(o => o.total));
  for (const o of out) if (o.total === low) o.weakest = true;
  return out;
}
