// Printable game-day sheet (public/calc/printsheet.mjs): the app's own numbers and names, never rule text.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const P = await import(new URL('../public/calc/printsheet.mjs', import.meta.url).href);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

test('the sheet has their units, tricks, stratagems split by whose turn, and my phases with once-per-battle boxes', () => {
  const html = P.printSheetHtml({
    esc, title: 'Round 2', me: { label: 'Space Wolves' }, them: { label: 'Orks' }, setting: 'Layout A',
    theirUnits: [{ name: 'Boyz', models: 20, points: 170, stats: [{ name: 'Boy', M: 6, T: 5, Sv: 5, InSv: null, W: 1, OC: 2 }], fnp: null, weapons: [{ label: 'Slugga', range: '12"', melee: false }, { label: 'Choppa', melee: true }], defensive: [{ label: '6+ FNP vs mortals', auto: true }] }],
    tricks: [{ name: 'Deep Strike', units: ['Stormboyz'], note: 'From battle round 2 …' }],
    theirStrats: [{ name: 'Orks Is Never Beaten', cp: 2, phase: 'Fight phase', turn: "Your opponent's turn", effect: 'GW TEXT MUST NOT APPEAR' }, { name: 'Careen', cp: 1, phase: 'Any phase', turn: 'Your turn' }],
    myPhases: [{ name: 'Before the battle', entries: [{ name: 'Scouts 6"', kind: 'core', units: 'Scout Squad ×2' }] }, { name: 'Command phase', entries: [{ name: 'Saga', kind: 'army', once: true }] }, { name: 'Movement phase', entries: [] }],
  });
  assert.match(html, /<b>Boyz<\/b>/);
  assert.match(html, /M6" T5 Sv5\+ W1 OC2/);
  assert.match(html, /Slugga 12"/);
  assert.match(html, /Melee: Choppa/);
  assert.match(html, /Their stratagems in your turn<\/h2><ul><li>Orks Is Never Beaten/);
  assert.match(html, /…and in theirs<\/h2><ul><li>Careen/);
  assert.match(html, /☐<\/span> Saga/);
  assert.doesNotMatch(html, /GW TEXT MUST NOT APPEAR/);
  assert.doesNotMatch(html, /Movement phase/, 'an empty phase is left out');
});
