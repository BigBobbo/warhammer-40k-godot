// End-to-end: build a Codex: Orks (11e) army with codex enhancements through
// the real army builder page and save it to the cloud (WP-O5).
//
// Drives the page in headless Chromium (Playwright) against a real relay
// server and asserts the player path:
//   faction Orks -> the detachment picker offers all 15 codex detachments
//   (Madcap Meks, Wreckas, ... were missing from the bundle) -> Taktikal
//   Brigade -> add a Warboss (warlord) and Kommandos -> the Warboss's
//   Enhancement dropdown offers the codex Kill Kommanda (not the pre-codex
//   Skwad Leader / Mek Kaptin / Mork's Kunnin'), the Kommandos' offers the
//   Throat-slittas Upgrade -> pick both -> save to cloud -> the cloud army
//   carries them; then Madcap Meks: the Big Mek with Shokk Attack Gun is
//   offered Temperamental Shokka + Enhanced Runt-maw (Upgrades on a
//   CHARACTER), a plain Big Mek is not.
//
// The game-side half (the Godot main menu loads that cloud army) is the
// windowed scenario 40k/tests/scenarios/sp/ork11e_enh_builder_cloud_army.json,
// driven together with this file by 40k/tests/run_ork11e_builder_cloud.sh.
//
// Run standalone:  cd server && npm run test:e2e:orks
// Or against a server you started yourself:
//   E2E_BASE=http://localhost:PORT E2E_SHOT_DIR=/some/dir node tests/e2e-orks-codex.mjs

import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const EXTERNAL = process.env.E2E_BASE || '';
const PORT = 19300 + Math.floor(Math.random() * 300);
const BASE = EXTERNAL || `http://localhost:${PORT}`;
const ARMY_NAME = process.env.E2E_ARMY_NAME || 'WPO5_E2E_Orks';
const SHOT_DIR = process.env.E2E_SHOT_DIR || '';
const dbDir = EXTERNAL ? '' : mkdtempSync(join(tmpdir(), 'w40k-e2e-ork-'));

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

const fold = (s) => String(s ?? '').replace(/[‘’]/g, "'");
const PREINSTALLED = '/opt/pw-browsers/chromium';

async function addUnit(page, nameRe, search) {
  await page.locator('.search').fill(search);
  await page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: nameRe }) }).first().click();
}

async function enhancementOptions(page) {
  const row = page.locator('.field-row', { hasText: 'Enhancement' });
  if (await row.count() === 0) return { row, options: [] };
  const options = (await row.locator('select option').allTextContents()).filter(o => !/none/i.test(o)).map(fold);
  return { row, options };
}

try {
  await waitForServer();
  console.log(`server up at ${BASE}`);

  const browser = await chromium.launch(existsSync(PREINSTALLED) ? { executablePath: PREINSTALLED } : {});
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(err.message));

  await page.goto(BASE, { waitUntil: 'networkidle' });
  check('page booted with topbar', await page.locator('.topbar').count() === 1);

  // --- faction + detachment --------------------------------------------------
  await page.locator('.topbar-config select').first().selectOption('orks');
  const detSelect = page.locator('.topbar-config select').nth(1);
  const detLabels = (await detSelect.locator('option').allTextContents()).map(fold);
  console.log('  detachments offered:', detLabels.join(' | '));
  for (const want of ['Taktikal Brigade', 'Madcap Meks', 'Wreckas', 'Brute Bosses', 'Flyboyz', 'Runt Swarm', 'Shoota Boyz', 'Wurrband']) {
    check(`codex detachment offered: ${want}`, detLabels.some(l => l.includes(want)));
  }
  await detSelect.selectOption('taktikal-brigade');

  // --- Taktikal Brigade: Warboss (Kill Kommanda) + Kommandos (Throat-slittas)
  await addUnit(page, /^Warboss$/, 'Warboss');
  await addUnit(page, /^Kommandos$/, 'Kommandos');
  check('two units in roster', await page.locator('.roster-unit').count() === 2);

  await page.locator('.roster-unit', { hasText: 'Warboss' }).first().click();
  await page.locator('.field-row', { hasText: 'Warlord' }).locator('input[type=checkbox]').check();
  let { row, options } = await enhancementOptions(page);
  console.log('  Warboss enhancements offered:', options.join(' | '));
  check('Warboss: Kill Kommanda offered', options.some(o => o.startsWith('Kill Kommanda (20 pts)')), options.join(' | '));
  for (const old of ['Skwad Leader', 'Mek Kaptin', "Mork's Kunnin'", 'Gob Boomer']) {
    check(`pre-codex ${old} not offered`, !options.some(o => o.includes(old)));
  }
  check('Warboss: the Throat-slittas Upgrade (KOMMANDOS/STORMBOYZ only) is not offered', !options.some(o => o.startsWith('Throat-slittas')), options.join(' | '));
  await row.locator('select').selectOption({ label: (await row.locator('select option').allTextContents()).find(o => fold(o).startsWith('Kill Kommanda')) });
  check('Kill Kommanda selected', fold(await row.locator('select option:checked').textContent()).startsWith('Kill Kommanda'));
  await shot(page, 'ork11e_builder_01_kill_kommanda_selected.png');

  await page.locator('.roster-unit', { hasText: 'Kommandos' }).first().click();
  ({ row, options } = await enhancementOptions(page));
  console.log('  Kommandos enhancements offered:', options.join(' | '));
  check('Kommandos (not a CHARACTER): only the Throat-slittas Upgrade', options.length === 1 && options[0].startsWith('Throat-slittas'), options.join(' | '));
  if (options.length) {
    await row.locator('select').selectOption({ label: (await row.locator('select option').allTextContents()).find(o => fold(o).startsWith('Throat-slittas')) });
  }
  await shot(page, 'ork11e_builder_02_throat_slittas_selected.png');

  // --- save to cloud -----------------------------------------------------------
  await page.locator('button', { hasText: 'Export / Save' }).click();
  await page.locator('#export-name').fill(ARMY_NAME);
  await page.locator('.modal button', { hasText: 'Save to cloud' }).click();
  await page.waitForSelector('.toast-ok', { timeout: 5000 });
  const saved = await (await fetch(`${BASE}/api/armies/${encodeURIComponent(ARMY_NAME)}`)).json();
  const army = typeof saved.army_data === 'string' ? JSON.parse(saved.army_data) : saved.army_data;
  const wb = Object.values(army.units).find(u => u.meta.name === 'Warboss');
  const ko = Object.values(army.units).find(u => u.meta.name === 'Kommandos');
  console.log('  exported faction:', JSON.stringify(army.faction));
  check('cloud army detachment is Taktikal Brigade', JSON.stringify(army.faction).includes('Taktikal Brigade'));
  check('Warboss is the warlord', wb?.meta?.is_warlord === true);
  const names = (u) => (u?.meta?.enhancements ?? []).map(e => fold(typeof e === 'string' ? e : e?.name ?? ''));
  check('Kill Kommanda exported on the Warboss', names(wb).includes('Kill Kommanda'), JSON.stringify(wb?.meta?.enhancements));
  // (the exporter canonicalises names to the game's spelling — canon.mjs maps
  // "Throat-slittas" to "Throat Slittas"; the game folds punctuation the same
  // way, OrkAbilities11e.fold, so both name the codex Upgrade)
  const loose = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  check('Throat-slittas exported on the Kommandos', names(ko).map(loose).includes('throat slittas'), JSON.stringify(ko?.meta?.enhancements));

  // --- Madcap Meks: the SAG Upgrades on their CHARACTER bearer ---------------
  await page.locator('.topbar-config select').nth(1).selectOption('madcap-meks');
  await addUnit(page, /^Big Mek with Shokk Attack Gun$/, 'Shokk');
  await addUnit(page, /^Big Mek$/, 'Big Mek');
  await page.locator('.roster-unit', { hasText: 'Big Mek with Shokk Attack Gun' }).first().click();
  ({ options } = await enhancementOptions(page));
  console.log('  Big Mek with SAG enhancements offered:', options.join(' | '));
  check('Big Mek with SAG: Temperamental Shokka offered', options.some(o => o.startsWith('Temperamental Shokka')), options.join(' | '));
  check('Big Mek with SAG: Enhanced Runt-maw offered', options.some(o => o.startsWith('Enhanced Runt-maw')), options.join(' | '));
  {
    const sagRow = page.locator('.field-row', { hasText: 'Enhancement' });
    await sagRow.locator('select').selectOption({ label: (await sagRow.locator('select option').allTextContents()).find(o => fold(o).startsWith('Temperamental Shokka')) });
    check('Temperamental Shokka selected on the Big Mek with SAG (a CHARACTER)', fold(await sagRow.locator('select option:checked').textContent()).startsWith('Temperamental Shokka'));
  }
  await shot(page, 'ork11e_builder_03_sag_upgrades_offered.png');
  await page.locator('.roster-unit').filter({ has: page.locator('text=/^Big Mek$/') }).first().click().catch(async () => {
    await page.locator('.roster-unit', { hasText: /Big Mek(?! with)/ }).last().click();
  });
  ({ options } = await enhancementOptions(page));
  console.log('  Big Mek enhancements offered:', options.join(' | '));
  check('Big Mek: the SAG Upgrades are not offered', !options.some(o => /Temperamental Shokka|Enhanced Runt-maw/.test(o)), options.join(' | '));
  check('Big Mek: Mekwaaagh! Mastermind offered', options.some(o => o.startsWith('Mekwaaagh! Mastermind')), options.join(' | '));

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E crashed:', err);
} finally {
  if (server) server.kill();
  if (dbDir) rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nE2E (Orks codex): all checks passed' : `\nE2E (Orks codex): ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
