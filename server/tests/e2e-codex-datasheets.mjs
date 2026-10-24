// End-to-end: the real army builder page shows the CODEX datasheets — the
// game's 40k/data/40kdc data (40kdc 1.4.5 + the Wahapedia 11e codex import),
// not the bundle's pre-codex records (WP-W3).
//
// Drives the page in headless Chromium (Playwright) against a real relay
// server:
//   Adeptus Custodes / Guardians of the Throne:
//     - the unit picker offers Custodian Guard Sodality (240) and no longer the
//       pre-codex "Custodian Guard" datasheet; Shield-Captain is listed at 180
//     - add a Shield-Captain: statline M8" T7 Sv2+/4++ W8 Ld5+ OC2 (pre-codex:
//       M6 T6 W6), 205 pts = 180 + 25 for the default Praesidium Shield; the
//       Castellan Axe swap gives the shield up (180), Reset brings it back
//     - add a Custodian Guard Sodality: 3 models, M8" T7 W5 OC3, 240 pts
//     - save to cloud: the exported army carries those numbers + data_source
//   Orks / War Horde:
//     - add a Battlewagon: T11 (pre-codex T10), 160 pts (pre-codex 150)
//     - add Boyz: sold as 10 (85 pts) or 20 (170 pts) — not 11-20
//     - save to cloud
//
// The game-side half (the Godot main menu loads the cloud Custodes army and
// the unit card shows W8) is the windowed scenario
// 40k/tests/scenarios/sp/w3_builder_codex_datasheets.json.
//
// Run standalone:  cd server && npm run test:e2e:codex
// Or against a server you started yourself (the scenario driver does this):
//   E2E_BASE=http://localhost:PORT E2E_SHOT_DIR=/some/dir node tests/e2e-codex-datasheets.mjs

import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const EXTERNAL = process.env.E2E_BASE || '';
const PORT = 19900 + Math.floor(Math.random() * 300);
const BASE = EXTERNAL || `http://localhost:${PORT}`;
const CUS_ARMY = process.env.E2E_ARMY_NAME || 'WPW3_E2E_Custodes';
const ORK_ARMY = process.env.E2E_ORK_ARMY_NAME || 'WPW3_E2E_Orks';
const SHOT_DIR = process.env.E2E_SHOT_DIR || '';
const dbDir = EXTERNAL ? '' : mkdtempSync(join(tmpdir(), 'w40k-e2e-w3-'));
import { DEFAULT_DATA_SOURCE as DATA_SOURCE } from '../public/js/lib/gameformat.mjs';

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

// The editor pane's statline as {M, T, Sv, W, Ld, OC} (cell text).
async function statline(page) {
  const heads = await page.locator('.editor-pane table.statline tr').nth(0).locator('th').allTextContents();
  const cells = await page.locator('.editor-pane table.statline tr').nth(1).locator('td').allTextContents();
  return Object.fromEntries(heads.map((h, i) => [h, cells[i]]));
}
const editorPts = async page => (await page.locator('.editor-pane .editor-pts').textContent()).trim();
const loadoutCount = async (page, name) => {
  const row = page.locator('.editor-pane .loadout-row').filter({ has: page.locator('.lo-name', { hasText: new RegExp(`^${name}$`) }) });
  return (await row.count()) ? parseInt(await row.first().locator('.step-count').textContent(), 10) : null;
};
async function addFromBrowser(page, name) {
  await page.locator('.search').fill(name);
  const row = page.locator('.browser-unit').filter({ has: page.locator('.bu-name', { hasText: new RegExp(`^${name}$`) }) }).first();
  const pts = (await row.locator('.bu-pts').textContent()).trim();
  await row.click();
  return pts;
}
async function saveToCloud(page, name) {
  await page.locator('button', { hasText: 'Export / Save' }).click();
  await page.locator('#export-name').fill(name);
  await page.locator('.modal button', { hasText: 'Save to cloud' }).click();
  await page.waitForSelector('.toast-ok', { timeout: 5000 });
  const saved = await (await fetch(`${BASE}/api/armies/${encodeURIComponent(name)}`)).json();
  return typeof saved.army_data === 'string' ? JSON.parse(saved.army_data) : saved.army_data;
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
  const consoleWarnings = [];
  page.on('console', (m) => { if (m.type() === 'warning' || m.type() === 'error') consoleWarnings.push(m.text()); });

  await page.goto(BASE, { waitUntil: 'networkidle' });
  check('page booted with topbar', await page.locator('.topbar').count() === 1);

  // ======================================================== Adeptus Custodes
  await page.locator('.topbar-config select').first().selectOption('adeptus-custodes');
  await page.locator('.topbar-config select').nth(1).selectOption('guardians-of-the-throne');

  await page.locator('.search').fill('Custodian Guard');
  const cgNames = await page.locator('.browser-unit .bu-name').allTextContents();
  console.log('  "Custodian Guard" search offers:', cgNames.join(' | '));
  check('pre-codex "Custodian Guard" datasheet not offered', !cgNames.some(n => n.trim() === 'Custodian Guard'), cgNames.join(' | '));
  check('Custodian Guard Sodality offered', cgNames.some(n => n.trim() === 'Custodian Guard Sodality'));
  await page.locator('.search').fill('Venatari');
  const venNames = (await page.locator('.browser-unit .bu-name').allTextContents()).map(s => s.trim());
  check('codex split: Venatari with Verutum Lances / with Kinetic Destroyers, not "Venatari Custodians"',
    venNames.includes('Venatari with Verutum Lances') && venNames.includes('Venatari with Kinetic Destroyers') &&
    !venNames.includes('Venatari Custodians'), venNames.join(' | '));

  const scListPts = await addFromBrowser(page, 'Shield-Captain');
  check('unit picker lists the Shield-Captain at its codex 180 pts', scListPts === '180', scListPts);
  await page.locator('.roster-unit', { hasText: 'Shield-Captain' }).first().click();
  await page.locator('.field-row', { hasText: 'Warlord' }).locator('input[type=checkbox]').check();
  const sc = await statline(page);
  console.log('  Shield-Captain statline:', JSON.stringify(sc));
  check('Shield-Captain M8" T7 Sv2+/4++ W8 Ld5+ OC2 (codex; pre-codex was M6 T6 W6)',
    sc.M === '8"' && sc.T === '7' && sc.Sv === '2+ / 4++' && sc.W === '8' && sc.Ld === '5+' && sc.OC === '2', JSON.stringify(sc));
  check('Shield-Captain carries its default Praesidium Shield', await loadoutCount(page, 'Praesidium Shield') === 1);
  check('Shield-Captain 205 pts (180 + 25 per Praesidium Shield)', await editorPts(page) === '205 pts', await editorPts(page));
  await shot(page, 'w3_builder_01_shield_captain_codex.png');

  // Castellan Axe: "Pyrithite Spear and Praesidium Shield can be replaced"
  await page.locator('.editor-pane .loadout-row').filter({ has: page.locator('.lo-name', { hasText: /^Castellan Axe$/ }) })
    .locator('.step-btn').nth(1).click();
  check('Castellan Axe taken', await loadoutCount(page, 'Castellan Axe') === 1);
  check('the swap gives up the Pyrithite Spear and the Praesidium Shield',
    await loadoutCount(page, 'Pyrithite Spear') === 0 && await loadoutCount(page, 'Praesidium Shield') === 0);
  check('without the shield the Shield-Captain is 180 pts', await editorPts(page) === '180 pts', await editorPts(page));
  await page.locator('.editor-pane button', { hasText: 'Reset to default' }).click();
  check('Reset to default: shield back, 205 pts', await loadoutCount(page, 'Praesidium Shield') === 1 && await editorPts(page) === '205 pts');

  const cgsListPts = await addFromBrowser(page, 'Custodian Guard Sodality');
  check('unit picker lists Custodian Guard Sodality at 240 pts', cgsListPts === '240', cgsListPts);
  await page.locator('.roster-unit', { hasText: 'Custodian Guard Sodality' }).first().click();
  const cg = await statline(page);
  console.log('  Custodian Guard Sodality statline:', JSON.stringify(cg));
  check('Custodian Guard Sodality M8" T7 W5 OC3', cg.M === '8"' && cg.T === '7' && cg.W === '5' && cg.OC === '3', JSON.stringify(cg));
  const cgModels = (await page.locator('.editor-pane .field-row', { hasText: 'Models' }).textContent()).trim();
  check('Custodian Guard Sodality is a 3-model unit (one codex size)', /Models\s*3$/.test(cgModels), cgModels);
  check('Custodian Guard Sodality 240 pts', await editorPts(page) === '240 pts', await editorPts(page));
  check('roster row says 3 models', (await page.locator('.roster-unit', { hasText: 'Custodian Guard Sodality' }).textContent()).includes('3 models'));
  check('the Vexilla is an option (0 taken)', await loadoutCount(page, 'Vexilla') === 0);
  const badge = await page.locator('.points-badge').textContent();
  check('army total 445 pts', /^\s*445 \//.test(badge), badge);
  check('no rule issues on either codex unit', !(await page.locator('.roster-unit .ru-tag.issue').count()),
    (await page.locator('.validation li').allTextContents()).join(' | '));
  await shot(page, 'w3_builder_02_sodality_codex.png');

  const cus = await saveToCloud(page, CUS_ARMY);
  const cSc = Object.values(cus.units).find(u => u.meta.name === 'Shield-Captain');
  const cCg = Object.values(cus.units).find(u => u.meta.name === 'Custodian Guard Sodality');
  console.log('  cloud Custodes army:', JSON.stringify(Object.values(cus.units).map(u => [u.meta.name, u.meta.points, u.meta.stats, u.models.length, u.meta.wargear])));
  check('cloud Shield-Captain: W8, 205 pts, warlord, "1x Praesidium Shield"',
    cSc?.meta?.stats?.wounds === 8 && cSc?.meta?.points === 205 && cSc?.meta?.is_warlord === true &&
    (cSc?.meta?.wargear ?? []).includes('1x Praesidium Shield'), JSON.stringify(cSc?.meta));
  check('cloud Custodian Guard Sodality: 3 models, W5, 240 pts, no Vexilla ability',
    cCg?.models?.length === 3 && cCg?.meta?.stats?.wounds === 5 && cCg?.meta?.points === 240 &&
    !(cCg?.meta?.abilities ?? []).some(a => a.name === 'Vexilla'), JSON.stringify(cCg?.meta?.stats));
  check('cloud army data_source names the codex overlay', cus.faction?.data_source === DATA_SOURCE, cus.faction?.data_source);

  // ==================================================================== Orks
  await page.locator('button', { hasText: 'New' }).click();
  page.once('dialog', d => d.accept());
  await page.locator('.topbar-config select').first().selectOption('orks');
  await page.locator('.topbar-config select').nth(1).selectOption('war-horde');

  const bwListPts = await addFromBrowser(page, 'Battlewagon');
  check('unit picker lists the Battlewagon at its codex 160 pts (pre-codex 150)', bwListPts === '160', bwListPts);
  await page.locator('.roster-unit', { hasText: 'Battlewagon' }).first().click();
  const bw = await statline(page);
  console.log('  Battlewagon statline:', JSON.stringify(bw));
  check('Battlewagon T11 (codex; pre-codex T10) W16 Sv3+/6++ OC5',
    bw.T === '11' && bw.W === '16' && bw.Sv === '3+ / 6++' && bw.OC === '5', JSON.stringify(bw));
  check('Battlewagon 160 pts', await editorPts(page) === '160 pts', await editorPts(page));

  await addFromBrowser(page, 'Boyz');
  await page.locator('.roster-unit', { hasText: 'Boyz' }).first().click();
  const sizeOpts = await page.locator('.editor-pane .field-row', { hasText: 'Models' }).locator('select option').allTextContents();
  console.log('  Boyz sizes:', sizeOpts.join(' | '));
  check('Boyz sold as 10 (85 pts) or 20 (170 pts)',
    JSON.stringify(sizeOpts) === JSON.stringify(['10 models — 85 pts', '20 models — 170 pts']), sizeOpts.join(' | '));
  await page.locator('.editor-pane .field-row', { hasText: 'Models' }).locator('select').selectOption('20');
  check('Boyz x20 = 170 pts', await editorPts(page) === '170 pts', await editorPts(page));
  // 40kdc 1.4.5's stale Boyz composition tiers used to flag every Boyz loadout
  const issues = await page.locator('.validation li').allTextContents();
  check('no rule issues on the codex units (only army-level notes)',
    !issues.some(t => /^(Boyz|Battlewagon):/.test(t.trim())) &&
    !(await page.locator('.roster-unit .ru-tag.issue').count()), issues.join(' | '));
  await page.locator('.roster-unit', { hasText: 'Battlewagon' }).first().click();
  await shot(page, 'w3_builder_03_battlewagon_codex.png');

  const ork = await saveToCloud(page, ORK_ARMY);
  const oBw = Object.values(ork.units).find(u => u.meta.name === 'Battlewagon');
  const oBz = Object.values(ork.units).find(u => u.meta.name === 'Boyz');
  check('cloud Battlewagon: T11, 160 pts', oBw?.meta?.stats?.toughness === 11 && oBw?.meta?.points === 160, JSON.stringify(oBw?.meta?.stats));
  check('cloud Boyz: 20 models, 170 pts', oBz?.models?.length === 20 && oBz?.meta?.points === 170);

  check('no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  check('no overlay/bundle version warning in the console', !consoleWarnings.some(w => /codex overlay/.test(w)), consoleWarnings.join(' | '));
  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E crashed:', err);
} finally {
  if (server) server.kill();
  if (dbDir) rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures === 0 ? '\nE2E (codex datasheets): all checks passed' : `\nE2E (codex datasheets): ${failures} check(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
