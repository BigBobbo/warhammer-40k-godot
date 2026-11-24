// Lists from the game's shared army store (server: GET /api/armies, /api/armies/:name; the Army Builder's "Save to
// cloud" and the game write there) as list text the calculator reads (adapter.importArmy), and the calculator's
// lists back into the store in the game's format (PUT /api/armies/:name, as the Army Builder does).
//
// Game army file (schema 2): { faction: { name, points, detachment, detachments, force_disposition, ... },
//   detachments: [{ name, dp_cost }], units: { U_X_A: { meta: { name, points, is_warlord, enhancements: [name],
//   wargear: ['10x Bolt Carbine', ...] }, models: [...] } } }. It has no attached characters: the game attaches
// them at deployment. meta.points is the unit with its enhancement.
//
// The text is the WTC compact format: one line per unit with its total wargear, which is what the file keeps (the
// GW app format needs the wargear per model). Pure module: tests/calc-gamelists.test.mjs.

const titleCase = (s) => String(s ?? '').replace(/[-_]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
const clean = (s) => String(s ?? '').replace(/[\r\n]+/g, ' ').trim();

/** The models in a game unit: its model list, else the counts in its composition, else 1. */
export function modelCount(u) {
  if (Array.isArray(u?.models) && u.models.length) return u.models.length;
  if (u?.models && typeof u.models === 'object' && Object.keys(u.models).length) return Object.keys(u.models).length;
  return 1;
}

/** A game army file -> list text. name: the store's name for it. */
export function gameArmyText(army, name = '') {
  const f = army?.faction ?? {};
  const units = Object.values(army?.units ?? {}).filter(u => u?.meta?.name);
  if (!units.length) throw new Error('This army has no units.');
  const dets = (army.detachments?.length ? army.detachments.map(d => d.name) : f.detachments?.length ? f.detachments : [f.detachment]).filter(Boolean);
  const total = units.reduce((s, u) => s + (Number(u.meta.points) || 0), 0);
  const warlord = units.find(u => u.meta.is_warlord);
  const head = [
    `+ LIST NAME: ${clean(name || f.name || 'Army')}`,
    `+ FACTION KEYWORD: ${clean(f.name)}`,
    ...dets.map(d => `+ DETACHMENT: ${clean(d)}`),
    ...(f.force_disposition ? [`+ FORCE DISPOSITION: ${titleCase(f.force_disposition)}`] : []),
    `+ TOTAL ARMY POINTS: ${total}pts`,
    ...(f.points ? [`+ POINTS LIMIT: ${f.points}pts`] : []),
    '+',
    ...(warlord ? [`+ WARLORD: ${clean(warlord.meta.name)}`] : []),
    `+ NUMBER OF UNITS: ${units.length}`,
  ];
  const bar = '+'.repeat(47);
  const lines = [];
  for (const u of units) {
    const m = u.meta;
    const gear = (m.wargear ?? []).map(clean).filter(Boolean);
    if (m.is_warlord) gear.push('Warlord');
    lines.push(`${modelCount(u)}x ${clean(m.name)} (${Number(m.points) || 0} pts)${gear.length ? `: ${gear.join(', ')}` : ''}`);
    for (const e of m.enhancements ?? []) if (clean(e)) lines.push(`Enhancement: ${clean(e)}`);
  }
  return [bar, ...head, bar, '', ...lines, ''].join('\n');
}

/** A store name the game accepts: letters, digits, space, _ and - (as the Army Builder makes them). */
export const storeName = (s) => String(s ?? '').replace(/[^a-zA-Z0-9 _-]/g, '').trim().replace(/\s+/g, '_').slice(0, 60) || 'army';
