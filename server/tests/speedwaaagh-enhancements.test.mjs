// Regression test for the missing Orks "Speedwaaagh!" detachment enhancements.
//
// Upstream 40kdc ships Speedwaaagh! with an empty enhancement list, so the army
// builder offered no "Enhancement" dropdown for that detachment and dropped any
// imported enhancement (e.g. "Kustom Shokk Box") as unresolved. data-patches.mjs
// injects the four official enhancements; this test drives the real builder
// store + importer to prove they now surface, resolve on import, and export.
//
// Run: node --test server/tests/speedwaaagh-enhancements.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { importText } = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
const { applyDataPatches, SPEEDWAAAGH_ENHANCEMENTS } =
  await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

const EXPECTED = new Map([
  ['Kustom Shokk Box', 10],
  ['Dakkamek', 25],
  ['Supa-burny Fuel', 15],
  ['Master Meknologist', 20],
]);

test('data patch registers the four Speedwaaagh! enhancements in RAW_DATA', () => {
  const enh = S.dc.RAW_DATA.enhancements;
  for (const [name, cost] of EXPECTED) {
    const e = enh.find(x => x.name === name && x.detachment_id === 'speedwaaagh');
    assert.ok(e, `missing enhancement record: ${name}`);
    assert.equal(e.cost, cost, `${name}: cost`);
  }
  const det = S.dc.RAW_DATA.detachments.find(d => d.id === 'speedwaaagh');
  for (const e of SPEEDWAAAGH_ENHANCEMENTS) {
    assert.ok(det.enhancement_ids.includes(e.id), `detachment not wired to ${e.id}`);
  }
});

test('enhancementChoices() exposes them to the builder dropdown', () => {
  S.setFaction('orks');
  S.setDetachment('speedwaaagh');
  S.addUnit('deffkilla-wartrike');
  const choices = S.enhancementChoices();
  assert.equal(choices.length, EXPECTED.size, 'choice count');
  for (const [name, cost] of EXPECTED) {
    const c = choices.find(x => x.name === name);
    assert.ok(c, `dropdown missing ${name}`);
    assert.equal(c.cost, cost, `${name}: cost in dropdown`);
  }
});

test('importing a Speedwaaagh! list resolves "Kustom Shokk Box" and exports it', () => {
  const pasted = [
    'Speed Freeks (80 Points)',
    '',
    'Orks',
    'Speedwaaagh!',
    'Strike Force (2000 Points)',
    '',
    'CHARACTERS',
    '',
    'Deffkilla Wartrike (80 Points)',
    '  • 1x Boomstikks',
    '  • 1x Killa jet',
    '  • 1x Snagga klaw',
    '  • Enhancement: Kustom Shokk Box',
    '',
  ].join('\n');

  const { roster, report } = importText(pasted);
  const u = roster.units[0];
  assert.equal(roster.detachments[0].ref.id, 'speedwaaagh', 'detachment resolved');
  assert.equal(u.enhancement?.resolved, true, 'enhancement resolved');
  assert.equal(u.enhancement?.id, 'kustom-shokk-box-speedwaaagh', 'enhancement id');
  assert.ok(
    !report.warnings.some(w => /enhancement-unresolved|not found|unresolved/i.test(w)),
    `no unresolved-enhancement warning, got: ${JSON.stringify(report.warnings)}`,
  );

  // The enhancement survives export into the game army JSON, with its points.
  const { army } = S.conv.rosterToGame(roster, { createdDate: '2026-01-01' });
  const unit = Object.values(army.units)[0];
  assert.ok(
    (unit.meta.enhancements ?? []).some(n => /kustom shokk box/i.test(n)),
    `exported unit missing enhancement: ${JSON.stringify(unit.meta.enhancements)}`,
  );

  // Its +10 cost is added on top of the datasheet base (Deffkilla Wartrike is
  // 70 base, so 80 here). Assert the delta vs. the same unit without the
  // enhancement rather than a hard-coded total, so a base-points change can't
  // silently mask a dropped enhancement cost.
  const bare = structuredClone(roster);
  bare.units[0].enhancement = null;
  bare.units[0].enhancement_points = null;
  const { army: bareArmy } = S.conv.rosterToGame(bare, { createdDate: '2026-01-01' });
  const bareUnit = Object.values(bareArmy.units)[0];
  assert.equal(unit.meta.points - bareUnit.meta.points, 10, 'enhancement adds its +10 cost');
});

test('the BUILDER total prices an imported enhancement (repriceAll)', () => {
  // Regression: text import resolved the enhancement but left
  // enhancement_points null, so the builder's running total (and the unit
  // row) showed the bearer at base cost — Kustom Shokk Box was free.
  const pasted = [
    'Speed Freeks (80 Points)',
    '',
    'Orks',
    'Speedwaaagh!',
    'Strike Force (2000 Points)',
    '',
    'CHARACTERS',
    '',
    'Deffkilla Wartrike (80 Points)',
    '  • 1x Boomstikks',
    '  • 1x Killa jet',
    '  • 1x Snagga klaw',
    '  • Enhancement: Kustom Shokk Box',
    '',
  ].join('\n');

  const { roster } = importText(pasted);
  S.loadRoster(roster); // the real import flow: dialogs.js hands off to loadRoster -> repriceAll

  const u = S.state.roster.units[0];
  assert.equal(u.enhancement_points, 10, 'enhancement_points priced from the dataset');
  assert.equal(
    S.totalPoints(), (u.points ?? 0) + 10,
    'roster total includes the enhancement cost');

  // Clearing the enhancement in the builder drops its cost from the total.
  S.setEnhancement(0, null);
  assert.equal(u.enhancement_points, null, 'cleared enhancement no longer priced');
  assert.equal(S.totalPoints(), u.points ?? 0, 'total back to the base cost');
});

test('applyDataPatches is idempotent', () => {
  const before = S.dc.RAW_DATA.enhancements.length;
  const detBefore = S.dc.RAW_DATA.detachments.find(d => d.id === 'speedwaaagh').enhancement_ids.length;
  applyDataPatches(S.dc.RAW_DATA);
  applyDataPatches(S.dc.RAW_DATA);
  assert.equal(S.dc.RAW_DATA.enhancements.length, before, 'no duplicate enhancement records');
  assert.equal(
    S.dc.RAW_DATA.detachments.find(d => d.id === 'speedwaaagh').enhancement_ids.length,
    detBefore, 'no duplicate ids on the detachment');
});
