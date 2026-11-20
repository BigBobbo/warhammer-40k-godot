// How current the rules data behind an army is: where each datasheet comes
// from and from when, and the points in the pasted list against the data
// (public/calc/adapter.mjs dataProvenance / pointsCheck).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const list = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');
const SW = list('gw-space-wolves-2000.txt');

test('every datasheet says where its rules data comes from and from when', () => {
  const army = A.importArmy(SW);
  const p = A.dataProvenance(army);
  assert.equal(p.dataset, A.DATASET_VERSION);
  assert.equal(p.units.length, 12, 'one entry per datasheet in the list (attached characters included)');
  assert.ok(p.units.every(u => /^\d{4}-\d{2}-\d{2}$/.test(u.date)), JSON.stringify(p.units.filter(u => !u.date)));
  const gh = p.units.find(u => u.name === 'Grey Hunters');
  assert.deepEqual([gh.kind, gh.label, gh.date], ['codex', 'Codex: Space Marines (Wahapedia)', '2026-10-21']);
  assert.equal(p.groups.reduce((a, g) => a + g.count, 0), 12);
  assert.deepEqual([p.oldest, p.newest], ['2026-10-21', '2026-10-21']);
  assert.equal(A.fmtDataDate(p.newest), '21 Oct 2026');
  assert.equal(A.fmtDataDate(null), 'date not known');
  assert.ok(A.dataNewest() >= '2026-10-21', A.dataNewest());
});

test('a datasheet from the 40kdc dataset carries the date of its rules snapshot', () => {
  // (a faction without a codex import in this project: the dataset's launch data)
  const tyr = A.importArmy('Hive (500 points)\n\nTyranids\nInvasion Fleet\nIncursion (1000 points)\n\nHive Tyrant (195 points)\n\nTermagants (60 points)\n  • 10x Termagant\n');
  const p = A.dataProvenance(tyr);
  assert.ok(p.units.length >= 1, JSON.stringify(tyr.warnings));
  assert.ok(p.units.every(u => u.kind === 'base' && u.date === '2026-06-20' && /^40kdc \d+\.\d+\.\d+: 11th edition launch data$/.test(u.label)), JSON.stringify(p.units));
});

test('points check: a real list from the official app costs exactly what the data says (wargear and enhancements included)', () => {
  const army = A.importArmy(SW);
  const c = A.pointsCheck(army);
  assert.equal(c.checked, 12);
  // e.g. Terminator Assault Squad 395 = 340 for ten + 45 of priced wargear + 10 for Furious Assault;
  // Chaplain on Bike 95 = 75 + 20 for Imperium's Sword
  assert.deepEqual(c.mismatches, []);
});

test('points check: other points in the list than in the data are reported with both numbers', () => {
  // the same list with two units re-priced (as after a points update the data does not have yet)
  const changed = SW.replace('Grey Hunters (180 points)', 'Grey Hunters (165 points)').replace('Chaplain on Bike (95 points)', 'Chaplain on Bike (100 points)');
  assert.notEqual(changed, SW);
  const c = A.pointsCheck(A.importArmy(changed));
  assert.deepEqual(c.mismatches.map(m => [m.name, m.list, m.data]), [['Chaplain on Bike', 100, [95]], ['Grey Hunters', 165, [180]]]);
  assert.match(c.mismatches[0].enhancement.name, /^Imperium.s Sword$/);
  assert.equal(c.mismatches[0].enhancement.cost, 20);
  assert.equal(c.mismatches[1].date, '2026-10-21', 'with the date of the datasheet that may be out of date');
  // a unit whose size has a higher price from the third copy on: both prices are accepted
  const twc = A.pointsCheck(A.importArmy(SW.replaceAll('Thunderwolf Cavalry (260 points)', 'Thunderwolf Cavalry (290 points)')));
  assert.deepEqual(twc.mismatches, [], '230 + 30 of wargear, or 260 + 30 from the third unit');
});

test('the result is worked out once per set of units', () => {
  const army = A.importArmy(SW);
  assert.equal(A.armyData(army), A.armyData(army));
  const before = A.armyData(army);
  A.setAttachments(army, {});
  assert.notEqual(A.armyData(army), before, 'new units after the attachments change');
  assert.equal(A.armyData(army).prov.units.length, 12);
});
