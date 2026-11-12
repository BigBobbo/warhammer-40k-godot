// GW app exports write some datasheet names with U+2011 NON-BREAKING HYPHEN
// ("Contemptor‑Galatus Dreadnought", "Caladius Annihilator Grav‑Tank"), which
// left those units unresolved in the Army Builder and the Combat Calc.
//
// Run: node --test server/tests/import-normalize.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const I = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
const list = readFileSync(new URL('./fixtures/gw-custodes-nbhyphen.txt', import.meta.url), 'utf8');

test('fixture really contains non-breaking hyphens', () => {
  assert.ok(list.includes('‑'));
});

test('normalizeListText maps Unicode hyphens and odd spaces', () => {
  assert.equal(I.normalizeListText('Grav‑Tank x‐y z so­ft'), 'Grav-Tank x-y z soft');
  assert.equal(I.normalizeListText('Kombi-rokkit – Busta'), 'Kombi-rokkit – Busta', 'en dash kept');
});

test('GW list with non-breaking hyphens resolves every unit', () => {
  const { roster, report } = I.importText(list);
  assert.equal(roster.faction_id, 'adeptus-custodes');
  assert.deepEqual(roster.units.map(u => u.ref.id), [
    'shield-captain', 'caladius-annihilator-grav-tank',
    'contemptor-galatus-dreadnought', 'contemptor-galatus-dreadnought',
  ]);
  assert.ok(!report.warnings.some(w => /unit-unresolved/.test(w)), report.warnings.join('; '));
});
