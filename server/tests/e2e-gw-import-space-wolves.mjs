// End-to-end: import a GW app (v2.8) Space Wolves list through the builder's
// Import dialog.
//
// The list (tests/fixtures/gw-space-wolves-2000.txt) is a legal 2000 pt
// Codex: Space Marines army: three 1 DP detachments on one line (Assault
// Brethren, Saga of the Beastslayer, Stormlance Task Force), "Attached Unit"
// blocks with "• Attached as: Leader (Character)" lines (padded with
// invisible U+2060 word joiners), an "(Upgrade)" enhancement and an
// enhancement-granted Leader target (Wolf-Touched -> Wulfen). It used to
// import as "Adepta Sororitas" in the faction dropdown, with unresolved
// detachments, wrong points, 11-model squads and illegal attachments.
//
// Run: cd server && npm run test:e2e:gw-import
//   (E2E_SHOT_DIR=/some/dir to keep screenshots)

import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync, mkdirSync, readFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const EXTERNAL = process.env.E2E_BASE || '';
const PORT = 19600 + Math.floor(Math.random() * 300);
const BASE = EXTERNAL || `http://localhost:${PORT}`;
const SHOT_DIR = process.env.E2E_SHOT_DIR || '';
const LIST = readFileSync(join(here, 'fixtures', 'gw-space-wolves-2000.txt'), 'utf8');
const dbDir = EXTERNAL ? '' : mkdtempSync(join(tmpdir(), 'w40k-e2e-gw-'));

let failures = 0;
function check(label, cond, detail = '') {
  if (cond) {
    console.log(`  ok   ${label}`);
  } else {
    failures++;
    console.error(`  FAIL ${label}${detail ? ' — ' + detail : ''}`);
  }
}

let server = null;
let serverLog = '';
if (!EXTERNAL) {
  server = spawn(process.execPath, [join(here, '..', 'relay-server.js')], {
    env: { ...process.env, PORT: String(PORT), DB_PATH: join(dbDir, 'e2e.db') },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  server.stdout.on('data', (d) => { serverLog += d; });
  server.stderr.on('data', (d) => { serverLog += d; });
}

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

async function shot(page, name) {
  if (!SHOT_DIR) return;
  mkdirSync(SHOT_DIR, { recursive: true });
  const p = join(SHOT_DIR, name);
  await page.screenshot({ path: p, fullPage: false });
  console.log(`  shot ${p}`);
}

const PREINSTALLED = '/opt/pw-browsers/chromium';

try {
  await waitForServer();
  console.log(`server up at ${BASE}`);

  const browser = await chromium.launch(
    existsSync(PREINSTALLED) ? { executablePath: PREINSTALLED } : {});
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(err.message));

  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.locator('button', { hasText: 'Import' }).first().click();
  await page.locator('textarea.import-text').fill(LIST);
  await page.locator('.modal button', { hasText: 'Parse' }).click();
  const parsed = await page.locator('.import-report').textContent();
  console.log('  parse report:', parsed.replace(/\s+/g, ' ').slice(0, 300));
  check('parse: 12 units, all matched, faction space-wolves', /12 unit\(s\), 12 matched, faction space-wolves/.test(parsed), parsed);
  await shot(page, 'gw_import_01_parsed.png');
  await page.locator('.modal button.btn-primary').click();

  // --- topbar ---------------------------------------------------------------
  const factionSel = page.locator('.topbar-config select').first();
  check('faction dropdown shows Space Wolves', (await factionSel.inputValue()) === 'space-wolves',
    await factionSel.inputValue());
  check('selected option label is Space Wolves',
    /Space Wolves/.test(await factionSel.evaluate(s => s.options[s.selectedIndex]?.textContent ?? '')));
  check('points 2000 / 2000', /2000\s*\/\s*2000/.test(await page.locator('.points-badge').textContent()),
    await page.locator('.points-badge').textContent());
  check('3 / 3 DP', (await page.locator('#dp-badge').textContent()) === '3 / 3 DP', await page.locator('#dp-badge').textContent());
  const primary = page.locator('#detachment-picker select').first();
  check('primary detachment Assault Brethren', (await primary.inputValue()) === 'assault-brethren', await primary.inputValue());
  const chips = (await page.locator('.det-chip').allTextContents()).join(' | ');
  check('Saga of the Beastslayer + Stormlance Task Force added', /Saga of the Beastslayer/.test(chips) && /Stormlance Task Force/.test(chips), chips);
  check('disposition Take and Hold', (await page.locator('#disposition-select').inputValue()) === 'take-and-hold');

  // --- roster + validation ---------------------------------------------------
  check('12 units in the roster', (await page.locator('.roster-unit').count()) === 12);
  const validation = (await page.locator('.validation-details, .validation-ok').first().textContent()).replace(/\s+/g, ' ');
  console.log('  validation:', validation.slice(0, 400));
  check('no errors', /0 error\(s\)/.test(validation) || /List is legal/.test(validation), validation);
  check('no "not from a detachment in this roster"', !/not from a detachment/.test(validation));
  check('no "must attach to a unit"', !/must attach/.test(validation));
  check('no "not a purchasable size"', !/purchasable/.test(validation));
  check('no unresolved notes', !/unresolved/.test(validation), validation);

  // Terminator Assault Squad: 10 models, led by Logan + the Ancient
  await page.locator('.roster-unit', { hasText: 'Terminator Assault Squad' }).click();
  const editor = page.locator('.editor-pane');
  const editorText = (await editor.textContent()).replace(/\s+/g, ' ');
  check('Terminator Assault Squad: Furious Assault enhancement', /Furious Assault/.test(await editor.locator('.field-row', { hasText: 'Enhancement' }).locator('select').evaluate(s => s.options[s.selectedIndex]?.textContent ?? '')));
  check('Terminator Assault Squad at 10 models', /10 models/.test(editorText) ||
    (await editor.locator('select').evaluateAll(ss => ss.some(s => s.value === '10'))), editorText.slice(0, 200));

  await page.locator('.roster-unit', { hasText: 'Captain on Bike' }).click();
  const leads = page.locator('.editor-pane .field-row', { hasText: 'Leads' }).locator('select');
  check('Captain on Bike leads Wulfen with Storm Shields (Wolf-Touched)',
    (await leads.inputValue()) === 'wulfen-with-storm-shields', await leads.inputValue());
  await page.locator('.roster-unit', { hasText: 'Logan Grimnar' }).click();
  check('Logan Grimnar leads the Terminator Assault Squad',
    (await page.locator('.editor-pane .field-row', { hasText: 'Leads' }).locator('select').inputValue()) === 'terminator-assault-squad');
  await shot(page, 'gw_import_02_loaded.png');

  // Space Wolves see Space Marine + Space Wolves datasheets, not other chapters'.
  await page.locator('.search').fill('');
  const browserNames = await page.locator('.browser-unit .bu-name').allTextContents();
  check('unit browser offers Grey Hunters', browserNames.includes('Grey Hunters'));
  check('unit browser offers Intercessor Squad', browserNames.includes('Intercessor Squad'));
  check('unit browser hides Death Company Marines', !browserNames.some(n => /^Death Company Marines/.test(n)));

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
} catch (e) {
  failures++;
  console.error('E2E crashed:', e);
} finally {
  if (server) server.kill();
  if (dbDir) rmSync(dbDir, { recursive: true, force: true });
}

if (failures) {
  console.error(`\nE2E (GW import, Space Wolves): ${failures} check(s) FAILED`);
  process.exit(1);
}
console.log('\nE2E (GW import, Space Wolves): all checks passed');
