// What the Event Companion v1.3 (October 2026) changed, as the app applies it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const R = await import(new URL('../public/calc/rulesnote.mjs', import.meta.url).href);
const G = await import(new URL('../public/js/lib/gameformat.mjs', import.meta.url).href);
const T = await import(new URL('../public/calc/terrain-11e.mjs', import.meta.url).href);

test('the layouts are stamped with their source: v1.3, unchanged since v1.2, and how they were checked', () => {
  assert.equal(R.LAYOUTS_SOURCE.version, 'Event Companion v1.3');
  assert.match(R.LAYOUTS_SOURCE.note, /unchanged since v1\.2/);
  assert.ok(R.RULES_SOURCES.includes('Event Companion v1.3'));
  assert.equal(T.LAYOUTS.length, 45, 'the 45 official layouts (15 pairings x A, B, C)');
});

test('v1.3 "Base Size Guide: Wazbom Blastajet updated": 120x92mm oval', () => {
  assert.deepEqual(G.BASE_SIZE_OVERRIDES['wazbom-blastajet'], { shape: 'oval', width: 120, length: 92 });
});
