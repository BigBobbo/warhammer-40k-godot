// Regression tests for imported Ork enhancements in the army builder.
//
// History: upstream 40kdc 1.0.19 shipped the Orks "Speedwaaagh!" detachment
// with an empty enhancement list, so the builder offered no "Enhancement"
// dropdown for it and dropped an imported "Kustom Shokk Box" as unresolved;
// data-patches.mjs injected the four enhancements. The builder now runs on
// 40kdc 1.4.5 + the Codex: Orks overlay (WP-W3), and neither has a
// Speedwaaagh! detachment any more (scripts/40kdc/local-patches.mjs: "the
// Speedwaaagh! detachment does not exist in Codex: Orks (11e) / dataset
// 1.4.5"), so that patch is a no-op: it attaches nothing and adds no orphan
// records. The behaviour the old tests protected — a pasted list's
// enhancement resolves, exports with its cost, and is priced in the builder
// total — is pinned on a detachment the data has (War Horde).
//
// Run: node --test server/tests/speedwaaagh-enhancements.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { importText } = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
const { applyDataPatches, SPEEDWAAAGH_ENHANCEMENTS } =
  await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

const ENH_ID = 'headwoppas-killchoppa-war-horde';
const enhRecord = () => S.dc.RAW_DATA.enhancements.find(e => e.id === ENH_ID);

const PASTED = [
  'Waaagh Test (100 Points)',
  '',
  'Orks',
  'War Horde',
  'Strike Force (2000 Points)',
  '',
  'CHARACTERS',
  '',
  'Warboss (100 Points)',
  '  • 1x Kustom shoota',
  '  • 1x Big choppa',
  "  • Enhancement: Headwoppa's Killchoppa",
  '',
].join('\n');

test('the Speedwaaagh! patch is a no-op on a dataset without that detachment', () => {
  assert.equal(S.dc.RAW_DATA.detachments.find(d => d.id === 'speedwaaagh'), undefined,
    'no Speedwaaagh! detachment in 40kdc 1.4.5 / Codex: Orks');
  for (const e of SPEEDWAAAGH_ENHANCEMENTS) {
    assert.ok(!S.dc.RAW_DATA.enhancements.some(x => x.id === e.id), `orphan ${e.id} injected`);
  }
});

test("enhancementChoices() offers the detachment's enhancements with their dataset costs", () => {
  S.resetRoster();
  S.setFaction('orks');
  S.setDetachment('war-horde');
  S.addUnit('warboss');
  const det = S.dc.RAW_DATA.detachments.find(d => d.faction_id === 'orks' && d.id === 'war-horde');
  const choices = S.enhancementChoices();
  assert.deepEqual(choices.map(c => c.id), det.enhancement_ids, 'one choice per detachment enhancement');
  for (const c of choices) {
    const e = S.dc.RAW_DATA.enhancements.find(x => x.id === c.id);
    assert.equal(c.cost, e.cost, `${c.name}: cost in dropdown`);
  }
});

test('importing a pasted list resolves the enhancement and exports it with its cost', () => {
  const { roster, report } = importText(PASTED);
  const u = roster.units[0];
  assert.equal(roster.detachments[0].ref.id, 'war-horde', 'detachment resolved');
  assert.equal(u.enhancement?.resolved, true, 'enhancement resolved');
  assert.equal(u.enhancement?.id, ENH_ID, 'enhancement id');
  assert.ok(
    !report.warnings.some(w => /enhancement-unresolved|enhancement .*not found/i.test(w)),
    `no unresolved-enhancement warning, got: ${JSON.stringify(report.warnings)}`,
  );

  const { army } = S.conv.rosterToGame(roster, { createdDate: '2026-01-01' });
  const unit = Object.values(army.units)[0];
  assert.deepEqual(unit.meta.enhancements, ["Headwoppa's Killchoppa"], 'exported under the name the game keys on');

  // Its cost is added on top of the datasheet base: assert the delta vs. the
  // same unit without the enhancement, so a base-points change can't mask a
  // dropped enhancement cost.
  const bare = structuredClone(roster);
  bare.units[0].enhancement = null;
  bare.units[0].enhancement_points = null;
  const { army: bareArmy } = S.conv.rosterToGame(bare, { createdDate: '2026-01-01' });
  const bareUnit = Object.values(bareArmy.units)[0];
  assert.equal(unit.meta.points - bareUnit.meta.points, enhRecord().cost, 'enhancement adds its cost');
});

test('the BUILDER total prices an imported enhancement (repriceAll)', () => {
  // Regression: text import resolved the enhancement but left
  // enhancement_points null, so the builder's running total (and the unit
  // row) showed the bearer at base cost.
  const { roster } = importText(PASTED);
  S.loadRoster(roster); // the real import flow: dialogs.js hands off to loadRoster -> repriceAll

  const u = S.state.roster.units[0];
  const cost = enhRecord().cost;
  assert.equal(u.enhancement_points, cost, 'enhancement_points priced from the dataset');
  assert.equal(S.totalPoints(), (u.points ?? 0) + cost, 'roster total includes the enhancement cost');

  // Clearing the enhancement in the builder drops its cost from the total.
  S.setEnhancement(0, null);
  assert.equal(u.enhancement_points, null, 'cleared enhancement no longer priced');
  assert.equal(S.totalPoints(), u.points ?? 0, 'total back to the base cost');
});

test('applyDataPatches is idempotent', () => {
  const lengths = () => ['units', 'weapons', 'abilities', 'unitCompositions', 'wargearOptions',
    'leaderAttachments', 'enhancements', 'detachments'].map(c => S.dc.RAW_DATA[c].length);
  const before = lengths();
  const det = () => S.dc.RAW_DATA.detachments.find(d => d.faction_id === 'orks' && d.id === 'war-horde');
  const detBefore = det().enhancement_ids.length;
  applyDataPatches(S.dc.RAW_DATA);
  applyDataPatches(S.dc.RAW_DATA);
  assert.deepEqual(lengths(), before, 'no duplicate records');
  assert.equal(det().enhancement_ids.length, detBefore, 'no duplicate ids on the detachment');
});
