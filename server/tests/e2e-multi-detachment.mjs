// End-to-end: 11e multi-detachment army building (Detachment Points pool).
//
// Custodes at 2000 pts (3 DP): primary Lions of the Emperor (1 DP) -> add
// Solar Watch and Null Maiden Vigil (1 DP each) -> the 3 DP Guardians of the
// Throne is refused, the pool reads 3 / 3 DP -> a Shield-Captain is offered
// enhancements from all three -> save to cloud -> the game army carries
// faction.detachment (primary), faction.detachments and detachments[{dp_cost}].
//
// Run: cd server && npm run test:e2e:multidet
//   (E2E_SHOT_DIR=/some/dir to keep screenshots)

import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const EXTERNAL = process.env.E2E_BASE || '';
const PORT = 19600 + Math.floor(Math.random() * 300);
const BASE = EXTERNAL || `http://localhost:${PORT}`;
const ARMY_NAME = process.env.E2E_ARMY_NAME || 'MULTI_DET_E2E_Custodes';
const SHOT_DIR = process.env.E2E_SHOT_DIR || '';
const dbDir = EXTERNAL ? '' : mkdtempSync(join(tmpdir(), 'w40k-e2e-mdet-'));

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
  page.on('console', (m) => { if (m.text().includes('[builder] detachment')) console.log('  page:', m.text()); });

  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.locator('.topbar-config select').first().selectOption('adeptus-custodes');
  const primary = page.locator('#detachment-picker select').first();
  const add = page.locator('#add-detachment-select');
  const badge = page.locator('#dp-badge');

  await primary.selectOption('lions-of-the-emperor');
  check('primary Lions of the Emperor, 1 / 3 DP', (await badge.textContent()) === '1 / 3 DP', await badge.textContent());
  await shot(page, 'multi_det_01_before.png');

  // Guardians of the Throne (3 DP) cannot be added on top of a 1 DP primary.
  const gotOpt = add.locator('option[value="guardians-of-the-throne"]');
  check('3 DP Guardians of the Throne disabled in the add list', await gotOpt.isDisabled());

  await add.selectOption('solar-watch');
  check('Solar Watch added — 2 / 3 DP', (await badge.textContent()) === '2 / 3 DP', await badge.textContent());
  // Unique: Shield Host — Solar Watch and Shadowkeepers cannot be combined.
  const skOpt = add.locator('option[value="shadowkeepers"]');
  check('Shadowkeepers disabled (shares the Shield Host tag)', await skOpt.isDisabled());
  check('…with the reason in its label', /Shield Host/.test(await skOpt.textContent()), await skOpt.textContent());
  // Force Disposition: only those the detachments give.
  const disp = page.locator('#disposition-select');
  check('disposition defaulted to the primary\'s (Disruption)', (await disp.inputValue()) === 'disruption', await disp.inputValue());
  const optDisabled = (v) => disp.locator(`option[value="${v}"]`).evaluate(o => o.disabled);
  check('Take and Hold disabled (no selected detachment gives it)', await optDisabled('take-and-hold'),
    await disp.evaluate(s => [...s.options].map(o => `${o.value}:${o.disabled}`).join(' ')));
  check('Reconnaissance (Solar Watch) selectable', !(await optDisabled('reconnaissance')));
  await disp.selectOption('reconnaissance');
  await add.selectOption('null-maiden-vigil');
  check('Null Maiden Vigil added — 3 / 3 DP', (await badge.textContent()) === '3 / 3 DP', await badge.textContent());
  check('two additional-detachment chips', await page.locator('.det-chip').count() === 2);
  check('add select disabled once the pool is full', await add.isDisabled());
  check('add select says DP pool full', (await add.locator('option').first().textContent()) === 'DP pool full');

  // Enhancements from every detachment
  await page.locator('.search').fill('Shield-Captain');
  await page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: /^Shield-Captain$/ }) }).first().click();
  await page.locator('.roster-unit', { hasText: 'Shield-Captain' }).first().click();
  await page.locator('.field-row', { hasText: 'Warlord' }).locator('input[type=checkbox]').check();
  const enhRow = page.locator('.field-row', { hasText: 'Enhancement' });
  const enhOptions = await enhRow.locator('select option').allTextContents();
  console.log('  enhancements offered:', enhOptions.join(' | '));
  check('Solar Watch enhancements offered', enhOptions.some(o => o.includes('— Solar Watch')));
  const sally = enhOptions.find(o => o.startsWith('Sally Forth'));
  await enhRow.locator('select').selectOption({ label: sally });
  // A Knight-Centura (ANATHEMA PSYKANA) gets the Null Maiden Vigil ones too.
  await page.locator('.search').fill('Knight-Centura');
  await page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: /^Knight-Centura$/ }) }).first().click();
  await page.locator('.roster-unit', { hasText: 'Knight-Centura' }).first().click();
  const kcOptions = await page.locator('.field-row', { hasText: 'Enhancement' }).locator('select option').allTextContents();
  console.log('  Knight-Centura enhancements:', kcOptions.join(' | '));
  check('Null Maiden Vigil enhancement offered to the Knight-Centura', kcOptions.some(o => o.includes('— Null Maiden Vigil')));
  await page.locator('.roster-unit', { hasText: 'Shield-Captain' }).first().click();
  await enhRow.locator('select').focus();
  await shot(page, 'multi_det_02_three_detachments.png');

  // --- save to cloud -> the game army carries all three ---------------------
  await page.locator('button', { hasText: 'Export / Save' }).click();
  await page.locator('#export-name').fill(ARMY_NAME);
  await page.locator('.modal button', { hasText: 'Save to cloud' }).click();
  await page.waitForSelector('.toast-ok', { timeout: 5000 });
  const saved = await (await fetch(`${BASE}/api/armies/${encodeURIComponent(ARMY_NAME)}`)).json();
  const army = typeof saved.army_data === 'string' ? JSON.parse(saved.army_data) : saved.army_data;
  console.log('  exported faction:', JSON.stringify(army.faction));
  console.log('  exported detachments:', JSON.stringify(army.detachments));
  check('primary detachment exported', army.faction.detachment === 'Lions of the Emperor');
  check('all detachments exported', JSON.stringify(army.faction.detachments) === JSON.stringify(['Lions of the Emperor', 'Solar Watch', 'Null Maiden Vigil']));
  check('DP costs exported', (army.detachments ?? []).reduce((s, d) => s + d.dp_cost, 0) === 3);
  check('Force Disposition exported', army.faction.force_disposition === 'reconnaissance', army.faction.force_disposition);
  const sc = Object.values(army.units).find(u => u.meta.name === 'Shield-Captain');
  check('second-detachment enhancement exported', JSON.stringify(sc?.meta?.enhancements) === '["Sally Forth"]', JSON.stringify(sc?.meta?.enhancements));

  // Remove a chip -> DP frees up
  await page.keyboard.press('Escape').catch(() => {});
  await page.locator('.modal button', { hasText: /Close|Cancel/ }).first().click().catch(() => {});
  await page.locator('.det-chip', { hasText: 'Null Maiden Vigil' }).locator('.det-chip-remove').click();
  check('chip removed — 2 / 3 DP', (await badge.textContent()) === '2 / 3 DP', await badge.textContent());

  // Incursion: the pool drops to 2 DP; a 3 DP detachment may be the only one.
  await page.locator('.topbar-config select', { has: page.locator('option[value="1000"]') }).selectOption('1000');
  check('1000 pts trims to 2 / 2 DP', (await badge.textContent()) === '2 / 2 DP', await badge.textContent());
  await primary.selectOption('guardians-of-the-throne');
  check('Guardians of the Throne alone at Incursion: legal badge', (await badge.textContent()) === '3 DP (only detachment)', await badge.textContent());
  check('…not flagged over the pool', !(await badge.getAttribute('class')).includes('over'));
  check('…no additional detachments', await page.locator('.det-chip').count() === 0);
  check('…nothing else can be added', await add.isDisabled());
  check('…and the legality footer raises no DP error', !(await page.locator('body').innerText()).includes('over the 2 budget'));
  await shot(page, 'multi_det_03_incursion_lone_3dp.png');

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E crashed:', err);
} finally {
  if (server) server.kill();
  if (dbDir) rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nE2E (multi-detachment): all checks passed' : `\nE2E (multi-detachment): ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
