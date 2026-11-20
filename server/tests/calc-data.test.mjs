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

const TYRANIDS = (termagants = 55) => `Hive (500 points)\n\nTyranids\nInvasion Fleet\nIncursion (1000 points)\n\nHive Tyrant (195 points)\n\nTermagants (${termagants} points)\n  • 10x Termagant\n`;

test('a datasheet without a codex import carries the points and weapon profiles of the newer release, and says so', () => {
  const tyr = A.importArmy(TYRANIDS());
  const p = A.dataProvenance(tyr);
  assert.ok(p.units.length >= 2, JSON.stringify(tyr.warnings));
  for (const u of p.units) {
    assert.deepEqual([u.kind, u.date, u.label], ['errata', '2026-10-14', '40kdc 1.5.1 points and weapon profiles'], JSON.stringify(u));
    assert.match(u.note, /^abilities: 40kdc 1\.4\.5, 20 Jun 2026$/, 'the abilities are still the bundle\'s: said plainly');
  }
  assert.equal(p.groups.length, 1);
  assert.equal(p.groups[0].note, 'abilities: 40kdc 1.4.5, 20 Jun 2026');
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

// ---------------------------------------------------------------------------
// Points and weapon profiles of a newer 40kdc release, for the calculator only
// (calc/errata-data.mjs, made by scripts/40kdc/gen_calc_errata.mjs)

const { ERRATA } = await import(new URL('../public/calc/errata-data.mjs', import.meta.url).href);
const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { CODEX_OVERLAY_FACTIONS } = await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

test('data refresh: every entry was applied to the calculator\'s data, none to a faction with a codex import', () => {
  const r = A.ERRATA_RESULT;
  assert.deepEqual([r.from, r.date, r.why], ['1.5.1', '2026-10-14', null]);
  assert.equal(r.points, Object.keys(ERRATA.points).length);
  assert.equal(r.weapons, Object.keys(ERRATA.weapons).length);
  assert.deepEqual(r.skipped, [], 'every entry found the record it was made for');
  assert.ok(r.points > 150 && r.weapons > 90 && r.units > 700, JSON.stringify(r));
  assert.equal(ERRATA.base, A.DATASET_VERSION, 'made against the bundle that is vendored');
  assert.deepEqual(ERRATA.skipped, Object.keys(CODEX_OVERLAY_FACTIONS).sort());
  for (const key of [...Object.keys(ERRATA.points), ...Object.keys(ERRATA.weapons)]) {
    assert.ok(!ERRATA.skipped.includes(key.split('::')[0]), `${key}: a faction with a codex import keeps its codex data`);
  }
  // nothing with a codex import was marked as refreshed
  assert.ok(S.dc.RAW_DATA.units.every(u => !(u.source && u.errata)));
  assert.ok(S.dc.RAW_DATA.units.filter(u => Object.keys(CODEX_OVERLAY_FACTIONS).includes(u.faction_id)).every(u => !u.errata));
});

test('data refresh: the new values reach the calculator (points check, weapon rows)', () => {
  // Termagants cost 55 for ten in 1.5.1 (60 in the bundle)
  assert.deepEqual(A.pointsCheck(A.importArmy(TYRANIDS(55))).mismatches, []);
  const old = A.pointsCheck(A.importArmy(TYRANIDS(60))).mismatches;
  assert.deepEqual(old.map(m => [m.name, m.list, m.data]), [['Termagants', 60, [55]]]);
  assert.equal(old[0].kind, 'errata');
  // Grey Knights storm bolter: Strength 5, AP -1 in 1.5.1 (S4 AP0 in the bundle's provisional profile) —
  // read through the resolver the calculator's weapon rows use
  const bolter = S.conv.wres.resolve('grey-knights', 'storm-bolter-brother-captain');
  assert.deepEqual([bolter.profiles[0].stats.S, bolter.profiles[0].stats.AP, bolter.profiles[0].range], [5, -1, 24]);
  assert.equal(A.weaponKw(bolter.profiles[0].keywords).kw.rapidFire, 2);
  // a weapon keyword the refresh adds is read by the calculator: Tyranid Prime lash whip [EXTRA ATTACKS]
  const whip = S.conv.wres.resolve('tyranids', 'lash-whip');
  assert.equal(A.weaponKw(whip.profiles[0].keywords).kw.extraAttacks, true);
});

test('data refresh: only shapes the calculator already reads (keywords, ranges, stats)', () => {
  const unsupported = new Set();
  for (const [key, e] of Object.entries(ERRATA.weapons)) {
    assert.ok(Array.isArray(e.now) && e.now.length > 0 && typeof e.was === 'string', key);
    for (const p of e.now) {
      assert.ok(p.range === 'Melee' || (typeof p.range === 'number' && p.range > 0), `${key}: range ${p.range}`);
      for (const k of ['A', 'S', 'AP', 'D']) assert.ok(typeof p.stats[k] === 'number' || /^\d*D\d+(\+\d+)?$/.test(String(p.stats[k])), `${key}: ${k} = ${p.stats[k]}`);
      assert.ok((p.range === 'Melee' ? 'WS' : 'BS') in p.stats, `${key}: skill`);
      for (const u of A.weaponKw(p.keywords).unsupported) unsupported.add(u);
    }
  }
  assert.deepEqual([...unsupported], [], 'every weapon ability in the refresh is one the engine models');
  for (const [key, e] of Object.entries(ERRATA.points)) {
    assert.ok(e.now.length > 0 && e.now.every(t => Number.isInteger(t.models) && Number.isInteger(t.cost) && t.cost > 0), key);
  }
});

test('data refresh: guarded — wrong bundle version, a codex record or a changed value are left alone', () => {
  const raw = () => ({ units: [{ id: 'x', faction_id: 'f', points: [{ models: 1, cost: 10 }] }, { id: 'y', faction_id: 'f', points: [{ models: 1, cost: 10 }], source: 'wahapedia-11e@2026-10-21' }, { id: 'z', faction_id: 'f', points: [{ models: 1, cost: 99 }] }],
    weapons: [{ id: 'w', faction_id: 'f', profiles: [{ name: 'W', range: 12, stats: { A: 1, S: 4, AP: 0, D: 1, BS: 3 }, keywords: [] }] }] });
  const was = A.errataHash([{ models: 1, cost: 10 }]);
  const E = { base: '1.4.5', from: '9.9.9', dataslate: { id: 's', date: '2027-01-01', label: 'test' }, skipped: [], checked: { f: ['x', 'y', 'z'] },
    points: { 'f::x': { was, now: [{ models: 1, cost: 12 }] }, 'f::y': { was, now: [{ models: 1, cost: 12 }] }, 'f::z': { was, now: [{ models: 1, cost: 12 }] }, 'f::gone': { was, now: [] } },
    weapons: { 'f::w': { was: A.errataHash(raw().weapons[0].profiles), now: [{ name: 'W', range: 18, stats: { A: 2, S: 4, AP: 0, D: 1, BS: 3 }, keywords: [] }] } } };
  const other = raw();
  const no = A.applyErrata(other, E, '1.4.6');
  assert.match(no.why, /made for bundle 1\.4\.5, the bundle is 1\.4\.6/);
  assert.equal(other.units[0].points[0].cost, 10, 'another bundle: nothing is touched');
  const r = raw();
  const res = A.applyErrata(r, E, '1.4.5');
  assert.deepEqual([res.points, res.weapons, res.units], [1, 1, 2]);
  assert.deepEqual(res.skipped.sort(), ['points f::gone', 'points f::y', 'points f::z']);
  assert.deepEqual([r.units[0].points[0].cost, r.units[1].points[0].cost, r.units[2].points[0].cost], [12, 10, 99], 'codex record and changed record keep their value');
  assert.equal(r.weapons[0].profiles[0].range, 18);
  assert.deepEqual([r.units[0].errata, r.units[1].errata], ['40kdc-9.9.9@2027-01-01', undefined]);
  assert.equal(A.applyErrata(r, E, '1.4.5'), res, 'applied once per data set');
});

test('data refresh: the Army Builder does not get it (its data is the bundle plus the codex overlay, as before)', async () => {
  const { execFileSync } = await import('node:child_process');
  const storeUrl = new URL('../public/js/builder/store.js', import.meta.url).href;
  // a fresh process that loads the builder's store only (no calculator module)
  const out = execFileSync(process.execPath, ['--input-type=module', '-e',
    `const S = await import(${JSON.stringify(storeUrl)}); const R = S.dc.RAW_DATA;
     const t = R.units.find(u => u.faction_id === 'tyranids' && u.id === 'termagants');
     const w = R.weapons.find(x => x.faction_id === 'grey-knights' && x.id === 'close-combat-weapon');
     console.log(JSON.stringify({ termagants: t.points[0].cost, errata: R.units.filter(u => u.errata).length, gkS: w.profiles[0].stats.S }));`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  assert.deepEqual(JSON.parse(out.trim().split('\n').pop()), { termagants: 60, errata: 0, gkS: 4 });
  // and in this process (calculator loaded) the same records hold the refreshed values
  const R = S.dc.RAW_DATA;
  assert.equal(R.units.find(u => u.faction_id === 'tyranids' && u.id === 'termagants').points[0].cost, 55);
  assert.equal(R.weapons.find(x => x.faction_id === 'grey-knights' && x.id === 'close-combat-weapon').profiles[0].stats.S, 5);
});
