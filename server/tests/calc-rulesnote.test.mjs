// "Rules in force": the next announced rules change, and the November 2026 update against the rules data
// (public/calc/rulesnote.mjs). Each "the data already has it" claim is checked here on the dataset.
import { test } from 'node:test';
import assert from 'node:assert/strict';

const N = await import(new URL('../public/calc/rulesnote.mjs', import.meta.url).href);
const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);   // applies the dataset refresh
const { dc } = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const R = dc.RAW_DATA;
const unit = (name) => R.units.find(u => u.name.toLowerCase() === name);
const weaponOf = (name, re) => (unit(name).weapon_ids ?? []).map(id => R.weapons.find(w => w.id === id)).find(w => w && re.test(w.name));
const kws = (p) => (p.keywords ?? []).map(k => k.keyword_id);

test('the next rules change: due from the week beginning 7 December 2026', () => {
  const before = N.rulesStatus(new Date(2026, 10, 20));
  assert.deepEqual([before.checked, before.next.weekOf, before.next.due], ['2026-11-20', '2026-12-07', false]);
  assert.equal(N.rulesStatus(new Date(2026, 11, 6)).next.due, false);
  assert.equal(N.rulesStatus(new Date(2026, 11, 7)).next.due, true, 'the week has begun');
  assert.equal(N.rulesStatus('2027-01-15').next.due, true);
  assert.equal(N.longDate('2026-12-07'), '7 December 2026');
  assert.deepEqual(before.changes, { total: 8, missing: 5 });
});

test('the rules data refresh is at the newest dataset release', () => {
  assert.equal(A.ERRATA_RESULT.from, N.DATASET_NEWEST.version, 'adapter.applyErrata brings the points and profiles of this release');
});

test('every datasheet the November update names is in the rules data', () => {
  for (const name of Object.keys(N.UPDATE.units)) assert.ok(unit(name), name);
  assert.deepEqual(N.unitUpdates('Chaos Bikers'), [{ weapon: 'Combi-weapon', change: 'S5 and AP-1', inData: false }]);
  assert.deepEqual(N.unitUpdates('Grey Hunters'), []);
  assert.match(N.abilityUpdate('combat-doctrines'), /Strategic Acumen/);
  assert.equal(N.abilityUpdate('thunderous-charge'), null);
});

test('November update against the data: what is already there, and what is not', () => {
  const claim = (name) => N.UPDATE.units[name][0].inData;
  // already in the data
  const meph = weaponOf('chief librarian mephiston', /plasma pistol/i).profiles.find(p => /supercharge/i.test(p.name));
  assert.equal(kws(meph).includes('hazardous'), claim('chief librarian mephiston'));
  const dcc = weaponOf('death company captain with jump pack', /plasma pistol/i).profiles.find(p => /supercharge/i.test(p.name));
  assert.equal(kws(dcc).some(k => k === 'pistol' || k === 'close-quarters'), claim('death company captain with jump pack'), 'Pistol is the Close-quarters weapon of this data');
  const pc = weaponOf('deathwatch terminator squad', /plasma cannon/i).profiles;
  assert.equal(pc.find(p => /standard/i.test(p.name)).stats.S === 7 && pc.find(p => /supercharge/i.test(p.name)).stats.S === 8, claim('deathwatch terminator squad'));
  // not in the data: the note on the datasheet says so
  assert.equal(kws(weaponOf('death company dreadnought', /twin heavy bolter/i).profiles[0]).includes('rapid-fire'), claim('death company dreadnought'));
  const cb = weaponOf('chaos bikers', /combi-weapon/i).profiles[0].stats;
  assert.equal(cb.S === 5 && cb.AP === -1, claim('chaos bikers'));
  assert.equal(weaponOf('nemesis claw', /close combat weapon/i).profiles[0].stats.S === 5, claim('nemesis claw'));
  assert.equal(weaponOf('deathwatch veterans', /combi-weapon/i).profiles.some(p => /damnatus/i.test(p.name)), claim('deathwatch veterans'), 'the data has one combi-weapon profile, not Damnatus / Purgatus');
  assert.equal(!kws(weaponOf('aggressor squad', /auto boltstorm/i).profiles[0]).includes('close-quarters'), claim('aggressor squad'));
});
