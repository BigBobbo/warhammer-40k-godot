// Combat Calc: the version shown in the app, the changelog and the offline cache agree.
// Run: node --test server/tests/calc-version.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'fs';

const { CALC_VERSION } = await import(new URL('../public/calc/version.mjs', import.meta.url).href);
const history = JSON.parse(readFileSync(new URL('../../40k/data/version_history.json', import.meta.url), 'utf8'));
const sw = readFileSync(new URL('../public/calc/sw.js', import.meta.url), 'utf8');

test('app version = newest changelog entry = service worker cache name', () => {
  assert.equal(CALC_VERSION, history.releases[0].version);
  assert.ok(sw.includes(`const CACHE = 'w40k-calc-${CALC_VERSION}'`), 'bump the cache name in sw.js with the version');
  assert.ok(sw.includes("'./version.mjs'"), 'version.mjs is part of the offline shell');
});

// The offline cache is filled as one set when a version installs, and the page is served from it alone (sw.js).
// A file missing on disk would stop the install; a module missing from the list would be fetched from the
// network instead, and could then belong to another version than the rest of the page.
const shell = [...sw.slice(sw.indexOf('const SHELL = ['), sw.indexOf('];', sw.indexOf('const SHELL = ['))).matchAll(/'([^']+)'/g)].map(m => m[1]);
const pub = new URL('../public/', import.meta.url);
test('every file of the offline set exists', () => {
  for (const f of shell) {
    if (f === './') continue;
    const url = f.startsWith('/') ? new URL(f.slice(1), pub) : new URL(`calc/${f.slice(2)}`, pub);
    assert.ok(existsSync(url), `${f} is in the SHELL list of sw.js but not on disk`);
  }
});
test('every module the app imports is part of the offline set', () => {
  const seen = new Set(), todo = [new URL('calc/app.js', pub)];
  while (todo.length) {
    const url = todo.pop();
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    const src = readFileSync(url, 'utf8');
    for (const m of src.matchAll(/(?:^|\n)\s*(?:import|export)\s[^'"\n]*?from\s*['"]([^'"]+)['"]|(?:^|\n)\s*import\s*['"]([^'"]+)['"]|import\(\s*['"]([^'"]+)['"]\s*\)|new (?:Worker|URL)\(\s*(?:new URL\(\s*)?['"](\.[^'"]+\.m?js)['"]/g)) {
      const spec = m[1] ?? m[2] ?? m[3] ?? m[4];
      if (!/^[./]/.test(spec)) continue;
      const next = spec.startsWith('/') ? new URL(spec.slice(1), pub) : new URL(spec, url);
      if (existsSync(next)) todo.push(next);
    }
  }
  const listed = new Set(shell.map(f => (f.startsWith('/') ? new URL(f.slice(1), pub) : new URL(`calc/${f.slice(2)}`, pub)).href));
  const missing = [...seen].filter(h => !listed.has(h)).map(h => h.slice(pub.href.length));
  assert.deepEqual(missing, [], 'add these to the SHELL list of sw.js');
  assert.ok(seen.size > 40, `followed ${seen.size} modules`);
});
