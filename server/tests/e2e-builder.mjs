// End-to-end test of the army builder page against a real relay server.
//
// Boots relay-server.js on an ephemeral port with a temp SQLite DB, drives
// the page in headless Chromium (Playwright), and asserts the full player
// path: pick faction -> add units -> edit -> save to cloud -> re-open from
// the cloud -> import pasted GW text.
//
// Run: cd server && npm run test:e2e
// (uses the preinstalled browser at /opt/pw-browsers/chromium when present)

import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const PORT = 19080 + Math.floor(Math.random() * 500);
const BASE = `http://localhost:${PORT}`;
const dbDir = mkdtempSync(join(tmpdir(), 'w40k-e2e-'));

let failures = 0;
function check(label, cond, detail = '') {
  if (cond) {
    console.log(`  ok   ${label}`);
  } else {
    failures++;
    console.error(`  FAIL ${label}${detail ? ' — ' + detail : ''}`);
  }
}

// --- boot server ------------------------------------------------------------
const server = spawn(process.execPath, [join(here, '..', 'relay-server.js')], {
  env: { ...process.env, PORT: String(PORT), DB_PATH: join(dbDir, 'e2e.db') },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let serverLog = '';
server.stdout.on('data', (d) => { serverLog += d; });
server.stderr.on('data', (d) => { serverLog += d; });

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`${BASE}/api/health`);
      if (res.ok) return;
    } catch (e) { /* not up yet */ }
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('relay server did not come up:\n' + serverLog);
}

const PREINSTALLED = '/opt/pw-browsers/chromium';

try {
  await waitForServer();
  console.log(`server up on :${PORT}`);

  const browser = await chromium.launch(
    existsSync(PREINSTALLED) ? { executablePath: PREINSTALLED } : {});
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(err.message));

  // --- build a list ---------------------------------------------------------
  await page.goto(BASE, { waitUntil: 'networkidle' });
  check('page booted with topbar', await page.locator('.topbar').count() === 1);

  await page.locator('.topbar-config select').first().selectOption('orks');
  await page.locator('.browser-unit', { hasText: 'Beastboss' }).first().click();
  await page.locator('.search').fill('boyz');
  await page.locator('.browser-unit', { hasText: /^Boyz/ }).first().click();
  check('two units in roster', await page.locator('.roster-unit').count() === 2);

  // warlord + enhancement on the Beastboss
  await page.locator('.roster-unit').first().click();
  await page.locator('.field-row', { hasText: 'Warlord' }).locator('input[type=checkbox]').check();
  await page.locator('.field-row', { hasText: 'Enhancement' }).locator('select').selectOption({ index: 1 });

  // Boyz to 20 models, take a big shoota
  await page.locator('.roster-unit').nth(1).click();
  await page.locator('.field-row', { hasText: 'Models' }).locator('select').selectOption({ index: 1 });
  await page.locator('.loadout-row', { hasText: 'Big shoota' }).locator('.step-btn').nth(1).click();

  const badge = await page.locator('.points-badge').textContent();
  check('points badge shows a real total', /\d+ \/ 2000 pts/.test(badge), badge);

  // --- save to cloud ---------------------------------------------------------
  await page.locator('button', { hasText: 'Export / Save' }).click();
  await page.locator('#export-name').fill('E2E_Orks');
  await page.locator('.modal button', { hasText: 'Save to cloud' }).click();
  await page.waitForSelector('.toast-ok', { timeout: 5000 });

  const saved = await (await fetch(`${BASE}/api/armies/E2E_Orks`)).json();
  const army = typeof saved.army_data === 'string' ? JSON.parse(saved.army_data) : saved.army_data;
  check('cloud army is schema 2', army.faction.schema === 2);
  check('cloud army has both units', Object.keys(army.units).length === 2, Object.keys(army.units).join(','));
  const bb = Object.values(army.units).find(u => u.meta.name === 'Beastboss');
  const bz = Object.values(army.units).find(u => u.meta.name === 'Boyz');
  check('warlord flag exported', bb?.meta?.is_warlord === true);
  check('enhancement exported', (bb?.meta?.enhancements ?? []).length === 1, JSON.stringify(bb?.meta?.enhancements));
  check('boyz sized to 20 models', bz?.models?.length === 20);
  check('big shoota in wargear strings', (bz?.meta?.wargear ?? []).some(w => /big shoota/i.test(w)),
    JSON.stringify(bz?.meta?.wargear));
  check('weapons carry structured abilities', bz.meta.weapons.every(w =>
    (w.abilities ?? []).every(a => typeof a.id === 'string')));

  // --- edit it back from the cloud -------------------------------------------
  await page.locator('button', { hasText: 'New' }).click();
  page.once('dialog', d => d.accept());
  await page.locator('button', { hasText: 'My Lists' }).click();
  await page.waitForSelector('.cloud-table');
  await page.locator('.cloud-table tr', { hasText: 'E2E_Orks' }).locator('button', { hasText: 'Edit' }).click();
  await page.waitForSelector('.roster-unit');
  check('cloud edit loads both units', await page.locator('.roster-unit').count() === 2);
  const badge2 = await page.locator('.points-badge').textContent();
  check('points survive the round-trip', badge2 === badge, `${badge2} vs ${badge}`);

  // --- import pasted GW text ---------------------------------------------------
  await page.locator('button', { hasText: 'Import' }).click();
  await page.locator('.import-text').fill(`Waaagh E2E (1000 Points)

Orks
War Horde
Incursion (1000 Points)

CHARACTERS

Beastboss (80 Points)
  • 1x Beast Snagga klaw

BATTLELINE

Boyz (150 Points)
  • 19x Boy
  • 1x Boss Nob
`);
  await page.locator('.modal button', { hasText: 'Parse' }).click();
  await page.waitForSelector('.import-report .sev-ok');
  await page.locator('.modal button', { hasText: 'Apply' }).click();
  await page.waitForSelector('.roster-unit');
  check('import applied two units', await page.locator('.roster-unit').count() === 2);
  check('imported boyz snapped to 20 models',
    (await page.locator('.roster-unit', { hasText: 'Boyz' }).textContent()).includes('20 models'));
  check('imported detachment selected',
    (await page.locator('.topbar-config select').nth(1).inputValue()) === 'war-horde');

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));

  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E crashed:', err);
} finally {
  server.kill();
  rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nE2E: all checks passed' : `\nE2E: ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
