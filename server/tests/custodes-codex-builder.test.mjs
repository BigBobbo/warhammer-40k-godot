// Codex: Adeptus Custodes (11e) in the army builder (WP-C46).
//
// The vendored 40kdc bundle predates the codex: it offered the pre-codex
// Custodes detachments (Shield Host, Talons of the Emperor, ...) and their 10e
// enhancements. data-patches.mjs injects the 13 codex detachments + 29
// enhancements (generated from the game's dataset) and hides the superseded
// detachments; the enhancement dropdown offers each enhancement only to the
// units its printed restriction allows (enhancement-rules.mjs, the JS twin of
// 40k/scripts/codex/EnhancementRules11e.gd), Upgrades on non-CHARACTER units.
//
// Run: node --test server/tests/custodes-codex-builder.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { applyDataPatches, CUSTODES_CODEX_DETACHMENTS, CUSTODES_CODEX_ENHANCEMENTS } =
  await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);
const R = await import(new URL('../public/js/lib/enhancement-rules.mjs', import.meta.url).href);

const CODEX = [
  'Aquilan Shield', 'Auric Champions', 'Dread Host', 'Emissaries Imperatus', 'Emperor’s Chosen',
  'Grav-Assault Force', 'Guardians of the Throne', 'Honoured Companions', 'Lions of the Emperor',
  'Might of the Moritoi', 'Null Maiden Vigil', 'Shadowkeepers', 'Solar Watch',
];

function freshRoster(detId) {
  S.resetRoster();
  S.setFaction('adeptus-custodes');
  S.setDetachment(detId);
}

function choiceNames(i) {
  return S.enhancementChoices(i).filter(c => c.eligible).map(c => c.name);
}

test('generated data: 13 codex detachments, 29 enhancements', () => {
  assert.equal(CUSTODES_CODEX_DETACHMENTS.length, 13);
  assert.equal(CUSTODES_CODEX_ENHANCEMENTS.length, 29);
  for (const e of CUSTODES_CODEX_ENHANCEMENTS) assert.ok(e.rules_text, `${e.name}: rules text`);
});

test('the detachment picker offers the 13 codex detachments, not the superseded ones', () => {
  const names = S.detachmentList('adeptus-custodes').map(d => d.name);
  assert.deepEqual([...names].sort(), [...CODEX].sort());
  for (const old of ['Shield Host', 'Talons of the Emperor', 'Silent Hunters', 'Solar Spearhead', 'Tharanatoi Hammerblow']) {
    assert.ok(!names.includes(old), `${old} still offered`);
  }
});

test('Guardians of the Throne: its 4 codex enhancements, no 10e ones', () => {
  freshRoster('guardians-of-the-throne');
  S.addUnit('shield-captain');
  const names = choiceNames(0);
  assert.deepEqual([...names].sort(), ["Bane of Abominations", "Castellan's Mark", "Eagle's Eye", "Emperor's Light"]);
  for (const old of ['Auric Mantle', 'Panoptispex']) assert.ok(!names.includes(old));
});

test('Lions: an Allarus-only enhancement is not offered to a foot Shield-Captain', () => {
  freshRoster('lions-of-the-emperor');
  S.addUnit('shield-captain');
  S.addUnit('shield-captain-in-allarus-terminator-armour');
  assert.deepEqual(choiceNames(0), []);
  assert.deepEqual([...choiceNames(1)].sort(), ['Leonine Ferocity', 'Lightning Descent']);
  const ld = S.enhancementChoices(0).find(c => c.name === 'Lightning Descent');
  assert.equal(ld.eligible, false);
  assert.match(ld.reason, /Shield-Captain in Allarus Terminator Armour model only/);
});

test('Null Maiden Vigil: Anathema Psykana model only', () => {
  freshRoster('null-maiden-vigil');
  S.addUnit('knight-centura');
  S.addUnit('shield-captain');
  assert.deepEqual([...choiceNames(0)].sort(), ["Huntress' Eye", 'Oblivion Knight']);
  assert.deepEqual(choiceNames(1), []);
});

test('Upgrades go on non-CHARACTER units (Solar Watch Auric Eagle), up to three', () => {
  freshRoster('solar-watch');
  S.addUnit('custodian-guard');
  S.addUnit('shield-captain');
  S.addUnit('allarus-custodians');
  S.addUnit('custodian-guard');
  S.addUnit('custodian-guard');
  S.addUnit('custodian-guard');
  assert.deepEqual(choiceNames(0), ['Auric Eagle'], 'Custodian Guard: the Upgrade only');
  assert.deepEqual(choiceNames(1), ['Sally Forth'], 'Shield-Captain: the normal enhancement only');
  assert.deepEqual(choiceNames(2), [], 'Allarus: excluded (Terminator)');
  const eagle = S.enhancementChoices(0).find(c => c.name === 'Auric Eagle').id;
  S.setEnhancement(0, eagle);
  S.setEnhancement(3, eagle);
  S.setEnhancement(4, eagle);
  const fourth = S.enhancementChoices(5).find(c => c.name === 'Auric Eagle');
  assert.notEqual(fourth.takenBy, null, 'a fourth Auric Eagle is blocked');
  assert.equal(S.enhancementChoices(4).find(c => c.name === 'Auric Eagle').takenBy, null, 'the holder keeps its own');
});

test('codex keywords fill the bundle gaps (TRUSTED SENTINEL, GRAV-ASSAULT)', () => {
  freshRoster('honoured-companions');
  S.addUnit('custodian-wardens');
  S.addUnit('allarus-custodians');
  assert.deepEqual(choiceNames(0), ['Celeritous Sentries']);
  assert.deepEqual(choiceNames(1), []);
  freshRoster('grav-assault-force');
  S.addUnit('coronus-grav-carrier');
  S.addUnit('caladius-grav-tank');
  assert.deepEqual([...choiceNames(0)].sort(), ['Anti-gravitic Mobility', 'Combat Deployment']);
  assert.deepEqual(choiceNames(1), ['Anti-gravitic Mobility'], 'Caladius is not a TRANSPORT');
});

test('one of each normal enhancement per army', () => {
  freshRoster('guardians-of-the-throne');
  S.addUnit('shield-captain');
  S.addUnit('shield-captain');
  const eye = S.enhancementChoices(0).find(c => c.name === "Eagle's Eye").id;
  S.setEnhancement(0, eye);
  assert.equal(S.enhancementChoices(1).find(c => c.name === "Eagle's Eye").takenBy, 0);
});

test('the enhancement exports to the game army with its cost', () => {
  freshRoster('guardians-of-the-throne');
  S.addUnit('shield-captain');
  const eye = S.enhancementChoices(0).find(c => c.name === "Eagle's Eye");
  S.setEnhancement(0, eye.id);
  const { army } = S.conv.rosterToGame(S.state.roster, { createdDate: '2026-10-18' });
  assert.equal(army.faction.detachment, 'Guardians of the Throne');
  const unit = Object.values(army.units)[0];
  assert.deepEqual(unit.meta.enhancements, ["Eagle's Eye"]);
  const bare = structuredClone(S.state.roster);
  bare.units[0].enhancement = null;
  bare.units[0].enhancement_points = null;
  const bareUnit = Object.values(S.conv.rosterToGame(bare, { createdDate: '2026-10-18' }).army.units)[0];
  assert.equal(unit.meta.points - bareUnit.meta.points, eye.cost);
});

test('bearer parser mirrors the game (EnhancementRules11e.gd)', () => {
  const rec = { rules_text: 'Adeptus Custodes Infantry/Mounted unit only (excluding Terminator units). This unit has +1 to advance rolls.' };
  assert.deepEqual(R.parseRestriction(rec), { phrase: 'Adeptus Custodes Infantry/Mounted', scope: 'unit', excluding: 'Terminator' });
  assert.equal(R.bearerViolation(rec, { name: 'Vertus Praetors', keywords: ['Mounted', 'Adeptus Custodes'] }), '');
  assert.match(R.bearerViolation(rec, { name: 'Allarus Custodians', keywords: ['Infantry', 'Terminator', 'Adeptus Custodes'] }), /excluding/);
  assert.match(R.bearerViolation(rec, { name: 'Caladius', keywords: ['Vehicle', 'Adeptus Custodes'] }), /only/);
});

test('applyDataPatches stays idempotent with the Custodes records', () => {
  const n = S.dc.RAW_DATA.enhancements.length;
  const d = S.dc.RAW_DATA.detachments.length;
  applyDataPatches(S.dc.RAW_DATA);
  assert.equal(S.dc.RAW_DATA.enhancements.length, n);
  assert.equal(S.dc.RAW_DATA.detachments.length, d);
});
