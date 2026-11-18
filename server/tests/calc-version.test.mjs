// Combat Calc: the version shown in the app, the changelog and the offline cache agree.
// Run: node --test server/tests/calc-version.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const { CALC_VERSION } = await import(new URL('../public/calc/version.mjs', import.meta.url).href);
const history = JSON.parse(readFileSync(new URL('../../40k/data/version_history.json', import.meta.url), 'utf8'));
const sw = readFileSync(new URL('../public/calc/sw.js', import.meta.url), 'utf8');

test('app version = newest changelog entry = service worker cache name', () => {
  assert.equal(CALC_VERSION, history.releases[0].version);
  assert.ok(sw.includes(`const CACHE = 'w40k-calc-${CALC_VERSION}'`), 'bump the cache name in sw.js with the version');
  assert.ok(sw.includes("'./version.mjs'"), 'version.mjs is part of the offline shell');
});
