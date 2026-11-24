// Printable game-day sheet: one page per player to take to the table on paper (a flat battery, an event that bans
// devices). Only what the app works out or names itself — stat lines, the app's own rule labels and notes, rule and
// stratagem NAMES with their cost and phase — never Games Workshop's rule text. Pure: tests/calc-printsheet.test.mjs.

const sv = (n) => (n ? `${n}+` : '–');
const box = '<span class="ps-box">☐</span>';

/**
 * p: {
 *   title, me: { faction, label }, them: { faction, label }, setting: 'Layout A · Tipping Point · ...',
 *   theirUnits: [unitIntel()], tricks: [{ name, units, note }], theirStrats: [{ name, cp, phase, turn }],
 *   myPhases: [{ name, entries: [{ name, kind, units, cp, once }] }], esc
 * } -> HTML of the sheet (class ps-*)
 */
export function printSheetHtml(p) {
  const esc = p.esc;
  const unitRow = (u) => {
    const s = u.stats.map(x => `M${x.M}" T${x.T} Sv${sv(x.Sv)}${x.InSv ? ` ${x.InSv}++` : ''} W${x.W} OC${x.OC}${u.stats.length > 1 ? ` <span class="ps-m">(${esc(x.name)})</span>` : ''}`).join('<br>');
    const guns = u.weapons.filter(w => !w.melee).map(w => `${esc(w.label)} ${esc(String(w.range ?? ''))}`);
    const melee = u.weapons.filter(w => w.melee).map(w => esc(w.label));
    const def = [u.fnp ? `FNP ${u.fnp}+` : '', ...u.defensive.filter(d => d.auto).map(d => esc(d.label))].filter(Boolean);
    return `<tr><td><b>${esc(u.name)}</b><div class="ps-m">${u.models} models${u.points ? ` · ${u.points} pts` : ''}</div></td><td>${s}</td>
      <td>${[...new Set(guns)].join(', ') || '–'}${melee.length ? `<div class="ps-m">Melee: ${[...new Set(melee)].join(', ')}</div>` : ''}</td><td>${def.join('; ') || '–'}</td></tr>`;
  };
  const stratLine = (s) => `<li>${esc(s.name)} <span class="ps-m">${s.cp}CP · ${esc(s.phase ?? '')}</span></li>`;
  const inMyTurn = p.theirStrats.filter(s => /opponent/i.test(s.turn ?? ''));
  const inTheirs = p.theirStrats.filter(s => !/opponent/i.test(s.turn ?? ''));
  return `<div class="ps" id="print-sheet-body">
    <h1>${esc(p.title)}</h1>
    <div class="ps-m">${esc(p.me.label)} (you) vs ${esc(p.them.label)}${p.setting ? ` · ${esc(p.setting)}` : ''}</div>
    <h2>Their units</h2>
    <table class="ps-t"><thead><tr><th>Unit</th><th>Profile</th><th>Shooting</th><th>Protection</th></tr></thead><tbody>${p.theirUnits.map(unitRow).join('')}</tbody></table>
    ${p.tricks.length ? `<h2>Plan around</h2><ul>${p.tricks.map(t => `<li><b>${esc(t.name)}</b>: ${esc(t.units.join(', '))}. <span class="ps-m">${esc(t.note)}</span></li>`).join('')}</ul>` : ''}
    <div class="ps-2"><div><h2>Their stratagems in your turn</h2><ul>${inMyTurn.map(stratLine).join('') || '<li>none</li>'}</ul></div>
      <div><h2>…and in theirs</h2><ul>${inTheirs.map(stratLine).join('') || '<li>none</li>'}</ul></div></div>
    <h2>Your army, phase by phase</h2>
    <div class="ps-2">${p.myPhases.filter(ph => ph.entries.length).map(ph => `<div class="ps-ph"><h3>${esc(ph.name)}</h3><ul>${ph.entries.map(e =>
      `<li>${e.once ? box + ' ' : ''}${esc(e.name)}${e.kind === 'stratagem' ? ` <span class="ps-m">${e.cp}CP</span>` : e.units ? ` <span class="ps-m">${esc(e.units)}</span>` : ''}</li>`).join('')}</ul></div>`).join('')}</div>
    <div class="ps-m ps-foot">Combat Calc · names, costs and phases only: check each rule's own text in your codex or the app. ☐ = once per battle.</div>
  </div>`;
}
