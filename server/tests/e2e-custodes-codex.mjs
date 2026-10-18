// End-to-end: build a Codex: Adeptus Custodes (11e) army with a codex
// enhancement through the real army builder page, save it to the cloud
// (WP-C46).
//
// Drives the page in headless Chromium (Playwright) against a real relay
// server and asserts the player path:
//   faction Adeptus Custodes -> the detachment picker offers the 13 codex
//   detachments, not the superseded 10e ones -> Guardians of the Throne ->
//   add a Shield-Captain (warlord) and a Custodian Guard unit -> the
//   Shield-Captain's Enhancement dropdown offers exactly the 4 Guardians of
//   the Throne enhancements (no 10e Auric Mantle / Panoptispex) -> pick
//   Eagle's Eye -> the Custodian Guard (not a CHARACTER) gets no normal
//   enhancement -> save to cloud -> the cloud army carries meta.enhancements
//   ["Eagle's Eye"] and detachment "Guardians of the Throne".
//
// The game-side half (the Godot main menu loads that cloud army and the
// list-build pass gives the Shield-Captain +1 W) is the windowed scenario
// 40k/tests/scenarios/sp/cus11e_enh_builder_cloud_army.json.
//
// Run standalone:  cd server && npm run test:e2e:custodes
// Or against a server you started yourself (the scenario driver does this):
//   E2E_BASE=http://localhost:PORT E2E_SHOT_DIR=/some/dir node tests/e2e-custodes-codex.mjs

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
const ARMY_NAME = process.env.E2E_ARMY_NAME || 'WPC46_E2E_Custodes';
const SHOT_DIR = process.env.E2E_SHOT_DIR || '';
const dbDir = EXTERNAL ? '' : mkdtempSync(join(tmpdir(), 'w40k-e2e-cus-'));

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
  check('page booted with topbar', await page.locator('.topbar').count() === 1);

  // --- faction + detachment --------------------------------------------------
  await page.locator('.topbar-config select').first().selectOption('adeptus-custodes');
  const detSelect = page.locator('.topbar-config select').nth(1);
  const detLabels = await detSelect.locator('option').allTextContents();
  const detValues = await detSelect.locator('option').evaluateAll(os => os.map(o => o.value));
  console.log('  detachments offered:', detLabels.join(' | '));
  for (const want of ['Guardians of the Throne', 'Aquilan Shield', 'Null Maiden Vigil', 'Grav-Assault Force']) {
    check(`codex detachment offered: ${want}`, detLabels.some(l => l.includes(want)));
  }
  for (const old of ['Shield Host', 'Talons of the Emperor', 'Silent Hunters', 'Solar Spearhead', 'Tharanatoi Hammerblow']) {
    check(`superseded 10e detachment hidden: ${old}`, !detLabels.some(l => l.includes(old)));
  }
  check('Guardians of the Throne selectable', detValues.includes('guardians-of-the-throne'), detValues.join(','));
  await detSelect.selectOption('guardians-of-the-throne');

  // --- units -----------------------------------------------------------------
  await page.locator('.search').fill('Shield-Captain');
  await page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: /^Shield-Captain$/ }) }).first().click();
  await page.locator('.search').fill('Custodian Guard');
  await page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: /^Custodian Guard/ }) }).first().click();
  check('two units in roster', await page.locator('.roster-unit').count() === 2);

  // Shield-Captain: warlord + the codex enhancement dropdown
  await page.locator('.roster-unit', { hasText: 'Shield-Captain' }).first().click();
  await page.locator('.field-row', { hasText: 'Warlord' }).locator('input[type=checkbox]').check();
  const enhRow = page.locator('.field-row', { hasText: 'Enhancement' });
  check('Shield-Captain shows an Enhancement row', await enhRow.count() === 1);
  const enhOptions = (await enhRow.locator('select option').allTextContents()).filter(o => !o.includes('none'));
  console.log('  enhancements offered:', enhOptions.join(' | '));
  const enhNames = enhOptions.map(o => o.replace(/\s*\(\d+ pts\).*$/, ''));
  check('exactly the 4 Guardians of the Throne enhancements',
    JSON.stringify([...enhNames].sort()) === JSON.stringify(["Bane of Abominations", "Castellan’s Mark", "Eagle’s Eye", "Emperor’s Light"].sort())
      || JSON.stringify([...enhNames].map(n => n.replace(/’/g, "'")).sort()) === JSON.stringify(["Bane of Abominations", "Castellan's Mark", "Eagle's Eye", "Emperor's Light"].sort()),
    enhNames.join(' | '));
  for (const old of ['Auric Mantle', 'Panoptispex', 'Admonimortis']) {
    check(`10e enhancement not offered: ${old}`, !enhOptions.some(o => o.includes(old)));
  }
  const eagle = enhOptions.find(o => /Eagle.s Eye/.test(o));
  await enhRow.locator('select').selectOption({ label: eagle });
  check('Eagle\'s Eye selected', /Eagle.s Eye/.test(await enhRow.locator('select option:checked').textContent()));
  await shot(page, 'cus11e_builder_01_eagles_eye_selected.png');

  // Custodian Guard: not a CHARACTER — no normal enhancement is offered
  await page.locator('.roster-unit', { hasText: 'Custodian Guard' }).first().click();
  const cgRow = page.locator('.field-row', { hasText: 'Enhancement' });
  const cgOptions = (await cgRow.count()) ? await cgRow.locator('select option').allTextContents() : [];
  check('Custodian Guard is offered no Guardians enhancement',
    !cgOptions.some(o => /Eagle.s Eye|Bane of Abominations|Emperor.s Light|Castellan.s Mark/.test(o) && !/—/.test(o)),
    cgOptions.join(' | '));

  // --- save to cloud -----------------------------------------------------------
  await page.locator('button', { hasText: 'Export / Save' }).click();
  await page.locator('#export-name').fill(ARMY_NAME);
  await shot(page, 'cus11e_builder_02_save_dialog.png');
  await page.locator('.modal button', { hasText: 'Save to cloud' }).click();
  await page.waitForSelector('.toast-ok', { timeout: 5000 });

  const saved = await (await fetch(`${BASE}/api/armies/${encodeURIComponent(ARMY_NAME)}`)).json();
  const army = typeof saved.army_data === 'string' ? JSON.parse(saved.army_data) : saved.army_data;
  const sc = Object.values(army.units).find(u => u.meta.name === 'Shield-Captain');
  console.log('  exported faction:', JSON.stringify(army.faction));
  check('cloud army detachment is Guardians of the Throne',
    JSON.stringify(army.faction).includes('Guardians of the Throne'), JSON.stringify(army.faction));
  check('Shield-Captain is the warlord', sc?.meta?.is_warlord === true);
  check('Eagle\'s Eye exported on the Shield-Captain',
    (sc?.meta?.enhancements ?? []).some(e => /Eagle.s Eye/.test(typeof e === 'string' ? e : e?.name ?? '')),
    JSON.stringify(sc?.meta?.enhancements));

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E crashed:', err);
} finally {
  if (server) server.kill();
  if (dbDir) rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nE2E (Custodes codex): all checks passed' : `\nE2E (Custodes codex): ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
