// Codex: Orks (11e) in the army builder (WP-O5).
//
// The vendored 40kdc bundle predates Codex: Orks (11th edition): its Ork
// detachments carried the pre-codex enhancements (Wazblasta, Skwad Leader,
// Mork's Kunnin', ...) and 7 of the 15 codex detachments were missing.
// data-patches.mjs upserts the 15 codex detachments + 38 enhancements
// (orks-codex-11e-data.mjs, generated from the game's dataset by
// scripts/40kdc/gen_orks_builder_patch.py); the WP-C46 bearer rules
// (enhancement-rules.mjs) then offer each one only to the units its printed
// restriction allows — Upgrades on CHARACTER or non-CHARACTER units.
//
// Run: node --test server/tests/orks-codex-builder.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { ORKS_CODEX_DETACHMENTS, ORKS_CODEX_ENHANCEMENTS } =
  await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

const CODEX = ['Blitz Brigade', 'Brute Bosses', 'Bully Boyz', 'Da Big Hunt', 'Dread Mob', 'Flyboyz', 'Green Tide',
  'Kult of Speed', 'Madcap Meks', 'Runt Swarm', 'Shoota Boyz', 'Taktikal Brigade', 'War Horde', 'Wreckas', 'Wurrband'];

const fold = (s) => String(s).replace(/[‘’]/g, "'");

function freshRoster(detId) {
  S.resetRoster();
  S.setFaction('orks');
  S.setDetachment(detId);
}

function choiceNames(i) {
  return S.enhancementChoices(i).filter(c => c.eligible).map(c => fold(c.name)).sort();
}

function allNames() {
  return S.enhancementChoices().map(c => fold(c.name)).sort();
}

test('generated data: 15 codex detachments, 38 enhancements with rules text', () => {
  assert.equal(ORKS_CODEX_DETACHMENTS.length, 15);
  assert.equal(ORKS_CODEX_ENHANCEMENTS.length, 38);
  for (const e of ORKS_CODEX_ENHANCEMENTS) assert.ok(e.rules_text, `${e.name}: rules text`);
});

test('the detachment picker offers all 15 codex Ork detachments (7 were missing)', () => {
  const names = S.detachmentList('orks').map(d => fold(d.name));
  for (const want of CODEX) assert.ok(names.includes(want), `${want} offered`);
});

test('each codex detachment lists exactly its codex enhancements, at codex cost', () => {
  for (const d of ORKS_CODEX_DETACHMENTS) {
    freshRoster(d.id);
    const want = ORKS_CODEX_ENHANCEMENTS.filter(e => d.enhancement_ids.includes(e.id)).map(e => fold(e.name)).sort();
    assert.deepEqual(allNames(), want, d.name);
  }
  freshRoster('taktikal-brigade');
  const costs = Object.fromEntries(S.enhancementChoices().map(c => [fold(c.name), c.cost]));
  assert.deepEqual(costs, { 'Kill Kommanda': 20, 'Throat-slittas': 15 });
  for (const old of ['Skwad Leader', 'Mek Kaptin', "Mork's Kunnin'", 'Gob Boomer']) {
    assert.ok(!allNames().includes(old), `${old} no longer offered`);
  }
  freshRoster('blitz-brigade');
  assert.equal(S.enhancementChoices().find(c => fold(c.name) === "Targetin' Gizmos").cost, 25, "Targetin' Gizmos 25 pts");
});

test('Taktikal Brigade: Kill Kommanda on a Warboss; Throat-slittas (Upgrade) on Kommandos', () => {
  freshRoster('taktikal-brigade');
  S.addUnit('warboss');
  S.addUnit('kommandos');
  assert.deepEqual(choiceNames(0), ['Kill Kommanda'], 'Warboss');
  assert.deepEqual(choiceNames(1), ['Throat-slittas'], 'Kommandos: the Upgrade only');
});

test('Madcap Meks: Temperamental Shokka / Enhanced Runt-maw (Upgrades) accepted on a Big Mek with Shokk Attack Gun only', () => {
  freshRoster('madcap-meks');
  S.addUnit('big-mek-with-shokk-attack-gun');
  S.addUnit('big-mek');
  S.addUnit('warboss');
  S.addUnit('boyz');
  // (the codex Big Mek with Shokk Attack Gun datasheet has no BIG MEK keyword,
  // so "Big Mek model only" Mekwaaagh! Mastermind is not offered to it — same
  // as the game's OrkEnhancements11e.bearer_problem)
  assert.deepEqual(choiceNames(0), ['Enhanced Runt-maw', 'Temperamental Shokka'], 'Big Mek with SAG (a CHARACTER): both Upgrades');
  assert.deepEqual(choiceNames(1), ['Mekwaaagh! Mastermind'], 'Big Mek: not the SAG Upgrades');
  assert.deepEqual(choiceNames(2), [], 'Warboss');
  assert.deepEqual(choiceNames(3), [], 'Boyz');
  const ts = S.enhancementChoices(3).find(c => fold(c.name) === 'Temperamental Shokka');
  assert.equal(ts.eligible, false);
  assert.match(ts.reason, /Big Mek with Shokk Attack Gun model only/);
});

test('multi-word keyword alternatives: "Big Mek/Warboss Infantry", "Big Mek/bigBoss/Warboss", "Big Mek/Mek"', () => {
  freshRoster('wreckas');
  S.addUnit('warboss');
  S.addUnit('big-mek');
  S.addUnit('deffkilla-wartrike');
  assert.ok(choiceNames(0).includes("Kaptin's Hat"), 'Warboss (INFANTRY WARBOSS)');
  assert.ok(choiceNames(1).includes("Kaptin's Hat"), 'Big Mek (INFANTRY BIG MEK)');
  assert.ok(!choiceNames(2).includes("Kaptin's Hat"), 'Deffkilla Wartrike: a WARBOSS but not INFANTRY');
  freshRoster('shoota-boyz');
  S.addUnit('warboss');
  S.addUnit('big-mek');
  assert.ok(choiceNames(0).includes("Targetin' Squigs"), 'Warboss');
  assert.ok(choiceNames(1).includes("Targetin' Squigs"), 'Big Mek');
  freshRoster('dread-mob');
  S.addUnit('mek');
  S.addUnit('big-mek');
  S.addUnit('warboss');
  assert.ok(choiceNames(0).includes('Cybork Boosta'), 'Mek');
  assert.ok(choiceNames(1).includes('Cybork Boosta'), 'Big Mek');
  assert.ok(!choiceNames(2).includes('Cybork Boosta'), 'Warboss');
});

test('Green Tide: the Boyz Upgrade, not a CHARACTER enhancement, on Boyz', () => {
  freshRoster('green-tide');
  S.addUnit('boyz');
  S.addUnit('warboss');
  assert.deepEqual(choiceNames(0), ["'Ardboyz"]);
  assert.deepEqual(choiceNames(1), ['Ferocious Show-off']);
});
