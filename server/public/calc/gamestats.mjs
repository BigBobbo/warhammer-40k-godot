// Personal statistics from the saved games (games.mjs): win / loss / draw and average VP, overall and by opponent
// faction, mission, layout, and going first or second. Only games whose battle was ended on the tracker count.
// Pure: tests/calc-gamestats.test.mjs.

const other = (X) => (X === 'A' ? 'B' : 'A');
const total = (g, br, X) => (g?.[X]?.primary || 0) + (g?.[X]?.secondary || 0) + (br?.[X] ? 10 : 0);

/**
 * One row per finished game: { name, myFaction, oppFaction, my, opp, primary, secondary, result: 'W'|'L'|'D',
 * first: 'first'|'second'|null, layout: 'A'|'B'|'C'|null, mission: string|null, saved }.
 * missionOf(rec) -> my primary mission's name (the app works it out from the two dispositions), or null.
 */
export function gameRows(games, missionOf = () => null) {
  const rows = [];
  for (const rec of games ?? []) {
    const m = rec.mission ?? {}, g = m.game ?? {};
    if (!g.over) continue;
    const me = m.me ?? 'A', opp = other(me);
    const my = total(g, m.battleReady, me), them = total(g, m.battleReady, opp);
    const v = rec.board?.settings?.variant;
    rows.push({
      name: rec.name ?? '', saved: rec.saved ?? '',
      myFaction: rec.armies?.[me] ?? '?', oppFaction: rec.armies?.[opp] ?? '?',
      my, opp: them, primary: g[me]?.primary || 0, secondary: g[me]?.secondary || 0,
      result: my > them ? 'W' : my < them ? 'L' : 'D',
      first: m.first == null ? null : m.first === me ? 'first' : 'second',
      layout: v ? 'ABC'[v - 1] ?? null : null,
      mission: missionOf(rec),
    });
  }
  return rows;
}

/** Totals of some rows: { n, w, l, d, winRate, vpFor, vpAgainst, primary, secondary } (averages per game). */
export function tally(rows) {
  const n = rows.length, avg = (f) => (n ? rows.reduce((a, r) => a + f(r), 0) / n : 0);
  const w = rows.filter(r => r.result === 'W').length, l = rows.filter(r => r.result === 'L').length;
  return { n, w, l, d: n - w - l, winRate: n ? (w + 0.5 * (n - w - l)) / n : null, vpFor: avg(r => r.my), vpAgainst: avg(r => r.opp), primary: avg(r => r.primary), secondary: avg(r => r.secondary) };
}

/** Rows grouped by `key` (a field name), each with its tally, most games first. Rows without that key are left out. */
export function statsBy(rows, key) {
  const groups = new Map();
  for (const r of rows) { const k = r[key]; if (k == null || k === '') continue; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
  return [...groups].map(([k, rs]) => ({ key: k, ...tally(rs) })).sort((a, b) => (b.n - a.n) || String(a.key).localeCompare(String(b.key)));
}
