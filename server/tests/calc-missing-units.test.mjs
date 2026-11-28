// Datasheets the rules data did not have: Lootas and Burna Boyz. The 11th
// edition Codex: Orks moved both to Warhammer Legends; the 40kdc bundle has no
// datasheet for them and the game's codex import skips Legends, so a list with
// either unit came in with "unit not recognised" and without the unit.
// data-patches.mjs (applyLegendsDatasheets) now carries the two datasheets,
// taken from the repository's Wahapedia 11e snapshot
// (.llm/codex_11e_wahapedia/orks/wahapedia). They are resolved here the way
// the app does it: a pasted list through adapter.importArmy, and a game army
// file through adapter.gameArmyToText.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const { dc, conv } = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const P = await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

// A GW-app style list with both units at their codex-era sizes and kits.
const LIST = `Loot (1000 points)

Orks
War Horde
Incursion (1000 points)

Warboss (100 points)

Boyz (85 points)
  • 9x Boy
  • 1x Boss Nob

Lootas (100 points)
  • 2x Spanner
     ◦ 2x Kustom Mega-blasta
     ◦ 2x Gun Stock and Fists
  • 8x Loota
     ◦ 8x Deffgun
     ◦ 8x Gun Stock and Fists

Burna Boyz (60 points)
  • 1x Spanner
     ◦ 1x Big Shoota
     ◦ 1x Gun Stock and Fists
  • 4x Burna Boy
     ◦ 4x Burna
     ◦ 4x Cuttin' Flames
`;

const army = A.importArmy(LIST);
const unitNamed = (a, name) => a.units.find(cu => cu.members.some(m => m.dcUnit.name === name));
const weapon = (id) => dc.RAW_DATA.weapons.find(w => w.faction_id === 'orks' && w.id === id);
const profile = (id) => { const p = weapon(id).profiles[0]; return [p.range, p.stats, p.keywords.map(k => k.keyword_id)]; };

test('a pasted Ork list with Lootas and Burna Boyz is recognised whole', () => {
  assert.equal(army.roster.faction_id, 'orks');
  assert.deepEqual(army.warnings.filter(w => /not recognised|unit-unresolved|weapon-unresolved: (Loota|Burna Boy|Spanner|Deffgun|Burna|Kustom|Gun Stock|Cuttin|Big Shoota)/.test(w)), []);
  assert.deepEqual(army.roster.units.map(u => u.ref?.id), ['warboss', 'boyz', 'lootas', 'burna-boyz']);
  assert.equal(army.units.length, 4, 'both units are in the calculator');
  assert.ok(conv.findUnitByName('orks', 'Lootas'), 'by name, as a game army file is read');
  assert.ok(conv.findUnitByName('orks', 'Burna Boyz'));
});

test('Lootas: profile, sizes, points and weapons of the Legends datasheet', () => {
  const cu = unitNamed(army, 'Lootas');
  const m = cu.members[0];
  assert.equal(m.dcUnit.is_legend, true);
  assert.deepEqual(m.dcUnit.profiles.map(p => [p.name, p.M, p.T, p.W, p.Sv, p.Ld, p.OC]), [['Spanner', 6, 5, 1, 5, 7, 1], ['Loota', 6, 5, 1, 5, 7, 1]]);
  assert.deepEqual(m.dcUnit.model_count, { min: 5, max: 10 });
  assert.deepEqual(m.dcUnit.base_size_mm, { shape: 'round', diameter: 32 });
  assert.deepEqual(m.dcUnit.points.map(p => [p.models, p.cost, p.unit_count_min]), [[5, 50, 1], [10, 100, 1], [5, 60, 3], [10, 110, 3]]);
  assert.deepEqual(m.dcUnit.keywords, ['Infantry', 'Lootas']);
  assert.equal(m.ru.model_count, 10);
  assert.deepEqual(m.ru.wargear.map(w => [w.ref.id, w.count]).sort(), [['deffgun', 8], ['gun-stock-and-fists', 10], ['kustom-mega-blasta-lootas', 2]]);
  assert.deepEqual(profile('deffgun'), [48, { A: 2, S: 8, AP: -1, D: 2, BS: 6 }, ['heavy', 'rapid-fire']]);
  // the Legends Kustom Mega-blasta hits on 5+; the codex one (other datasheets) on 4+
  assert.deepEqual(profile('kustom-mega-blasta-lootas'), [24, { A: 3, S: 9, AP: -2, D: 3, BS: 5 }, ['hazardous']]);
  assert.equal(weapon('kustom-mega-blasta').profiles[0].stats.BS, 4);
  assert.deepEqual(profile('gun-stock-and-fists'), ['Melee', { A: 2, S: 5, AP: 0, D: 1, WS: 3 }, []]);
  const ab = A.abilitiesOf(cu).find(a => a.name === "Dat's Our Loot");
  assert.ok(ab, JSON.stringify(A.abilitiesOf(cu).map(a => a.name)));
  assert.match(ab.text, /ranged attacks can re-roll hit rolls of 1/);
});

test('Burna Boyz: profile, sizes, points and weapons of the Legends datasheet', () => {
  const cu = unitNamed(army, 'Burna Boyz');
  const m = cu.members[0];
  assert.equal(m.dcUnit.is_legend, true);
  assert.deepEqual(m.dcUnit.profiles.map(p => [p.name, p.M, p.T, p.W, p.Sv, p.Ld, p.OC]), [['Burna Boy', 6, 5, 1, 5, 7, 1], ['Spanner', 6, 5, 1, 5, 7, 1]]);
  assert.deepEqual(m.dcUnit.model_count, { min: 5, max: 10 });
  assert.deepEqual(m.dcUnit.points.map(p => [p.models, p.cost]), [[5, 60], [10, 120]]);
  assert.equal(m.ru.model_count, 5);
  assert.deepEqual(m.ru.wargear.map(w => [w.ref.id, w.count]).sort(), [['big-shoota', 1], ['burna', 4], ['cuttin-flames', 4], ['gun-stock-and-fists', 1]]);
  assert.deepEqual(profile('burna'), [12, { A: 3, S: 4, AP: 0, D: 1, BS: null }, ['blast', 'torrent']]);
  assert.deepEqual(profile('cuttin-flames'), ['Melee', { A: 2, S: 4, AP: -2, D: 1, WS: 4 }, []]);
  const ab = A.abilitiesOf(cu).find(a => a.name === 'Pyromaniaks');
  assert.ok(ab, JSON.stringify(A.abilitiesOf(cu).map(a => a.name)));
  assert.match(ab.text, /within 6" of this unit can re-roll wound rolls of 1/);
});

test('the two units cost what the list says, and say they are Legends datasheets', () => {
  const c = A.pointsCheck(army);
  assert.equal(c.checked, 4);
  assert.deepEqual(c.mismatches, []);
  const prov = A.dataProvenance(army).units;
  for (const n of ['Lootas', 'Burna Boyz']) {
    const u = prov.find(x => x.name === n);
    assert.deepEqual([u.kind, u.label, u.date], ['codex', 'Warhammer Legends (Wahapedia)', '2026-10-16']);
  }
  assert.equal(prov.find(x => x.name === 'Boyz').label, 'Codex: Orks (Wahapedia)');
});

test('they go to the game with their weapons, and the game\'s own ability names', () => {
  const { game, warnings } = A.armyToGame(army);
  assert.deepEqual(warnings, []);
  const byName = Object.fromEntries(Object.values(game.units).map(u => [u.meta.name, u]));
  const lo = byName.Lootas, bu = byName['Burna Boyz'];
  assert.equal(lo.models.length, 10);
  assert.equal(lo.meta.points, 100);
  assert.deepEqual(lo.meta.stats, { move: 6, toughness: 5, save: 5, wounds: 1, leadership: 7, objective_control: 1 });
  assert.deepEqual(lo.meta.weapons.map(w => w.name).sort(), ['Deffgun', 'Gun Stock and Fists', 'Kustom Mega-blasta']);
  assert.ok(lo.meta.abilities.some(a => a.name === "Dat's Our Loot!"), JSON.stringify(lo.meta.abilities.map(a => a.name)));
  assert.equal(bu.models.length, 5);
  assert.equal(bu.meta.points, 60);
  assert.deepEqual(bu.meta.weapons.map(w => w.name).sort(), ['Big shoota', 'Burna', "Cuttin' Flames", 'Gun Stock and Fists']);
  assert.ok(bu.meta.abilities.some(a => a.name === 'Pyromaniaks'));
});

test('a game army file with both units (40k/armies/Orks_2000.json) loads with every unit recognised', () => {
  const file = JSON.parse(readFileSync(new URL('../../40k/armies/Orks_2000.json', import.meta.url), 'utf8'));
  const names = Object.values(file.units).map(u => u.meta.name);
  assert.ok(names.includes('Lootas') && names.includes('Burna Boyz'));
  const t = A.gameArmyToText(file, 'Orks_2000');
  assert.equal(t.recognised, t.units, `${t.recognised}/${t.units} recognised`);
  const a = A.importArmy(t.text);
  assert.deepEqual(a.warnings.filter(w => /not recognised|unit-unresolved/.test(w)), []);
  assert.equal(a.roster.units.filter(u => u.ref?.id === 'lootas').length, names.filter(n => n === 'Lootas').length);
  assert.equal(a.roster.units.filter(u => u.ref?.id === 'burna-boyz').length, names.filter(n => n === 'Burna Boyz').length);
});

test('the Legends records are applied once and leave the codex datasheets alone', () => {
  const before = JSON.stringify(dc.RAW_DATA.units.length);
  P.applyLegendsDatasheets(dc.RAW_DATA);
  assert.equal(JSON.stringify(dc.RAW_DATA.units.length), before, 'idempotent');
  assert.deepEqual(dc.RAW_DATA.units.filter(u => u.is_legend).map(u => u.id), ['lootas', 'burna-boyz']);
  // every weapon and ability the two datasheets name is in the data
  for (const u of P.LEGENDS_DATASHEET_RECORDS.units) {
    for (const w of u.weapon_ids) assert.ok(weapon(w), `${u.id}: weapon ${w}`);
    for (const a of u.ability_ids) assert.ok(dc.RAW_DATA.abilities.some(x => x.faction_id === 'orks' && x.ability_id === a), `${u.id}: ability ${a}`);
  }
  // no other datasheet uses the two replaced ability records
  const others = dc.RAW_DATA.units.filter(u => !u.is_legend && (u.ability_ids ?? []).some(a => a === 'dat-s-our-loot' || a === 'pyromaniaks'));
  assert.deepEqual(others.map(u => u.id), []);
});
