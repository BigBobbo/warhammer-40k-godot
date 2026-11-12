// End-to-end test of the combat calculator (/calc/) on an emulated phone.
//
// Boots relay-server.js, opens /calc/ as a Pixel 7, pastes two GW-app lists,
// then drives the player path through real taps: load armies -> Attack tab ->
// pick a target -> add two attacking units -> toggle a modifier -> read the
// sticky result bar -> open the results sheet -> swap attacker/defender ->
// fight phase. Asserts the numbers against the engine run headlessly on the
// same scenario, and that no console errors fired. Screenshots go to
// $CALC_SHOTS (default: server/tests/screenshots/).
//
// Run: cd server && npm run test:e2e:calc
import { spawn } from 'child_process';
import { mkdtempSync, existsSync, rmSync, readFileSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
let pw;
try { pw = await import('playwright'); } catch { pw = require('playwright'); }
const { chromium, devices } = pw;

const here = dirname(fileURLToPath(import.meta.url));
const PORT = 19600 + Math.floor(Math.random() * 300);
const BASE = `http://localhost:${PORT}`;
const dbDir = mkdtempSync(join(tmpdir(), 'w40k-calc-e2e-'));
const SHOTS = process.env.CALC_SHOTS ?? join(here, 'screenshots');
mkdirSync(SHOTS, { recursive: true });

let failures = 0;
function check(label, cond, detail = '') {
  if (cond) console.log(`  ok   ${label}`);
  else { failures++; console.error(`  FAIL ${label}${detail ? ' — ' + detail : ''}`); }
}

const server = spawn(process.execPath, [join(here, '..', 'relay-server.js')], {
  env: { ...process.env, PORT: String(PORT), DB_PATH: join(dbDir, 'e2e.db') },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let serverLog = '';
server.stdout.on('data', (d) => { serverLog += d; });
server.stderr.on('data', (d) => { serverLog += d; });

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try { if ((await fetch(`${BASE}/api/health`)).ok) return; } catch { /* not up */ }
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error('relay server did not come up:\n' + serverLog);
}

const PREINSTALLED = '/opt/pw-browsers/chromium';
const SW_LIST = readFileSync(join(here, 'fixtures', 'gw-space-wolves-2000.txt'), 'utf8');
const ORK_LIST = readFileSync(join(here, 'fixtures', 'gw-orks-1000.txt'), 'utf8');

async function settle(page) {
  // wait for the worker's final pass
  await page.waitForFunction(() => {
    const s = window.__calc?.state;
    return s && !s.busy && s.result;
  }, null, { timeout: 30000 });
}

const kpi = async (page) => page.$$eval('.resultbar .kpi b', els => els.map(e => e.textContent.trim()));

try {
  await waitForServer();
  console.log(`server up on :${PORT}`);
  const browser = await chromium.launch(existsSync(PREINSTALLED) ? { executablePath: PREINSTALLED } : {});
  const ctx = await browser.newContext({ ...devices['Pixel 7'] });
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', e => consoleErrors.push(String(e)));

  // --- /calc redirects / serves its own index
  const res = await page.goto(`${BASE}/calc`);
  check('/calc serves the calculator', res.ok() && (await page.title()) === '40K Combat Calc');
  await page.waitForSelector('textarea[data-side="A"]', { timeout: 30000 });

  // --- load both armies through the UI
  await page.fill('textarea[data-side="A"]', SW_LIST);
  await page.tap('button[data-action="parse"][data-side="A"]');
  await page.fill('textarea[data-side="B"]', ORK_LIST);
  await page.tap('button[data-action="parse"][data-side="B"]');
  const titles = await page.$$eval('.card .title', els => els.map(e => e.textContent));
  check('army A parsed as Space Wolves', titles.includes('Space Wolves'), titles.join(','));
  check('army B parsed as Orks', titles.includes('Orks'), titles.join(','));
  await page.screenshot({ path: join(SHOTS, 'calc_01_armies.png') });

  await page.tap('button[data-action="view"][data-value="attack"]');
  await page.waitForSelector('select[data-input="target"]');

  // --- target: Warboss + Boyz (attached unit)
  const targetValue = await page.$eval('select[data-input="target"]', (sel) =>
    [...sel.options].find(o => /Warboss \+ Boyz/.test(o.textContent))?.value);
  check('attached Warboss + Boyz offered as one target', !!targetValue);
  await page.selectOption('select[data-input="target"]', targetValue);
  const stats = await page.$$eval('.stats .stat', els => els.map(e => `${e.querySelector('b').textContent} ${e.querySelector('span').textContent}`));
  check('target stat line shows T5 / Sv5+ / W1 / 21 models', ['5 T', '5+ Sv', '1 W', '21 Models'].every(x => stats.includes(x)), stats.join(' | '));

  // --- add Grey Hunters and Thunderwolf Cavalry (1)
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Grey Hunters")');
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Thunderwolf Cavalry (1)")');
  check('two attacker cards', (await page.locator('[data-attacker]').count()) === 2);
  await settle(page);
  const bar1 = await kpi(page);
  check('result bar shows kills / wipe / damage', bar1.length === 3 && bar1.every(Boolean), bar1.join(' '));

  // the same scenario headlessly (oracle): numbers must match exactly (same seed, same trials)
  const sc = await page.evaluate(() => window.__calc.scenario());
  const E = await import(new URL('../public/calc/engine.mjs', import.meta.url).href);
  const oracle = E.simulate({ ...sc, trials: 20000 });
  const uiResult = await page.evaluate(() => window.__calc.state.result);
  check('UI result equals the engine on the same scenario', Math.abs(uiResult.meanKills - oracle.meanKills) < 1e-9,
    `${uiResult.meanKills} vs ${oracle.meanKills}`);
  check('scenario carries 2 attackers vs 3 allocation groups (Nob/Boyz merged? no: W differs)',
    sc.attackers.length === 2 && sc.defender.groups.length === 3, JSON.stringify(sc.defender.groups.map(g => g.name)));

  // --- toggle "Half range" on the Grey Hunters: rapid fire -> more kills
  const before = uiResult.meanKills;
  await page.locator('[data-attacker]').first().locator('button[data-key="halfRange"]').tap();
  await settle(page);
  const after = await page.evaluate(() => window.__calc.state.result.meanKills);
  check('half range raises expected kills', after > before, `${before} -> ${after}`);
  await page.screenshot({ path: join(SHOTS, 'calc_02_attack.png'), fullPage: false });

  // --- results sheet
  await page.tap('button[data-action="open-results"]');
  await page.waitForSelector('.sheet #chart svg');
  const nBars = await page.locator('#chart .hit').count();
  check('histogram rendered', nBars > 3, `${nBars} bars`);
  await page.locator('#chart .hit').nth(Math.min(5, nBars - 1)).tap();
  const tip = await page.locator('#readout').textContent();
  check('tapping a bar shows its odds', /exactly .* at least/.test(tip), tip);
  check('odds table rendered', (await page.locator('table.dist tbody tr').count()) > 2);
  await page.screenshot({ path: join(SHOTS, 'calc_03_results.png') });
  await page.tap('.sheet button[data-action="close-sheet"]');

  // --- attached characters: defender side (detach the Warboss, attach the Beastboss)
  const boyzKey = await page.$eval('select[data-input="target"]', sel => sel.value);
  await page.tap('button[data-action="detach"]:has-text("Warboss")');
  let tgtName = await page.$eval('select[data-input="target"]', sel => sel.selectedOptions[0].textContent);
  check('detaching the Warboss leaves Boyz (20) as the target', /^Boyz \(20\)/.test(tgtName), tgtName);
  check('Warboss is now its own target option', await page.$eval('select[data-input="target"]', sel => [...sel.options].some(o => /^Warboss \(1\)/.test(o.textContent))));
  await page.tap('button[data-action="open-attach"]');
  await page.waitForSelector('.sheet .pick');
  const attachList = await page.$$eval('.sheet .pick .title', els => els.map(e => e.textContent));
  check('attach sheet lists the army characters', attachList.includes('Beastboss') && attachList.includes('Warboss'), attachList.join(','));
  await page.tap('.sheet .pick:has-text("Beastboss")');
  tgtName = await page.$eval('select[data-input="target"]', sel => sel.selectedOptions[0].textContent);
  check('target is now Beastboss + Boyz (21)', /^Beastboss \+ Boyz \(21\)/.test(tgtName), tgtName);
  check('target key kept (still the Boyz unit)', (await page.$eval('select[data-input="target"]', sel => sel.value)) === boyzKey);
  await settle(page);
  const scB = await page.evaluate(() => window.__calc.scenario());
  check('Beastboss reaches the engine as a character group (W6, T6 kept off the bodyguard T)',
    scB.defender.groups.some(g => g.character && g.name === 'Beastboss' && g.W === 6) && scB.defender.groups.filter(g => !g.character).every(g => g.T === 5),
    JSON.stringify(scB.defender.groups.map(g => [g.name, g.character, g.T, g.W])));
  const statB = await page.$$eval('.stats .stat span', els => els.map(e => e.textContent));
  check("the Beastboss's own FNP is not shown as the unit's", !statB.includes('FNP'), statB.join(','));
  check('chip says the FNP is the Beastboss only', await page.locator('button[data-action="rule"]', { hasText: 'Beastboss only' }).count() === 1);
  await page.screenshot({ path: join(SHOTS, 'calc_06_defender_attach.png') });

  // --- attached characters: attacker side (the Captain on Bike joins the Grey Hunters)
  const gh = page.locator('[data-attacker]').first();
  await gh.locator('button[data-action="open-attach"]').tap();
  await page.waitForSelector('.sheet .pick');
  await page.tap('.sheet .pick:has-text("Captain on Bike")');
  const ghTitle = await page.locator('[data-attacker]').first().locator('.title').textContent();
  check('attacker card becomes Captain on Bike + Grey Hunters', ghTitle === 'Captain on Bike + Grey Hunters', ghTitle);
  await settle(page);
  const scA = await page.evaluate(() => window.__calc.scenario());
  check("the Captain's guns join the attack", scA.attackers[0].weapons.some(w => /^Captain on Bike: /.test(w.name)),
    JSON.stringify(scA.attackers[0].weapons.map(w => w.name)));
  await page.screenshot({ path: join(SHOTS, 'calc_07_attacker_attach.png') });
  // detach again via the chip on the attacker card
  await page.locator('[data-attacker]').first().locator('button[data-action="detach"]').tap();
  check('detach restores Grey Hunters', (await page.locator('[data-attacker]').first().locator('.title').textContent()) === 'Grey Hunters');

  // --- Armies tab overview: the Captain goes back to the Wulfen via the select
  await page.tap('button[data-action="view"][data-value="armies"]');
  const capSel = page.locator('select[data-input="attach"][data-side="A"]').filter({ has: page.locator('option', { hasText: 'Wulfen with Storm Shields' }) });
  check('armies tab lists attachable characters', (await page.locator('select[data-input="attach"][data-side="A"]').count()) >= 4);
  const capIdx = await page.$$eval('select[data-input="attach"][data-side="A"]', sels => sels.findIndex(s => s.closest('.modrow').textContent.includes('Captain on Bike')));
  const sel = page.locator('select[data-input="attach"][data-side="A"]').nth(capIdx);
  const wulfenVal = await sel.evaluate(s => [...s.options].find(o => /Wulfen/.test(o.textContent)).value);
  await sel.selectOption(wulfenVal);
  await page.tap('button[data-action="view"][data-value="attack"]');
  await page.tap('button[data-action="swap"]');
  const opts = await page.$$eval('select[data-input="target"] option', os => os.map(o => o.textContent));
  check('swapped: Captain on Bike + Wulfen is a target again', opts.some(o => /^Captain on Bike \+ Wulfen/.test(o)), opts.join(' | '));
  await page.tap('button[data-action="swap"]');

  // --- swap: Orks attack Space Wolves; fight phase; Thunderwolf storm shields auto-on
  await page.tap('button[data-action="swap"]');
  await page.tap('button[data-action="phase"][data-value="fight"]');
  await page.waitForSelector('select[data-input="target"]');
  const tw = await page.$eval('select[data-input="target"]', (sel) =>
    [...sel.options].find(o => /Thunderwolf Cavalry \(1\)/.test(o.textContent))?.value);
  await page.selectOption('select[data-input="target"]', tw);
  const ruleChip = page.locator('button[data-action="rule"]', { hasText: '4+ invulnerable save' });
  check('Storm Shield 4+ invuln detected and on', (await ruleChip.getAttribute('aria-pressed')) === 'true');
  const invStat = await page.$$eval('.stats .stat', els => els.map(e => `${e.querySelector('b').textContent} ${e.querySelector('span').textContent}`));
  check('stat line shows the enabled 4+ InSv', invStat.includes('4+ InSv'), invStat.join(' | '));
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Meganobz")');
  await settle(page);
  const scF = await page.evaluate(() => window.__calc.scenario());
  check('fight phase uses the power klaws', scF.phase === 'fight' && scF.attackers[0].weapons.some(w => /Power Klaw/i.test(w.name)),
    JSON.stringify(scF.attackers[0].weapons.map(w => w.name)));
  check('storm shield invuln reaches the engine', scF.defender.groups.every(g => g.InSv === 4), JSON.stringify(scF.defender.groups));
  const withShield = await page.evaluate(() => window.__calc.state.result.meanWounds);
  await ruleChip.tap();
  await settle(page);
  const noShield = await page.evaluate(() => window.__calc.state.result.meanWounds);
  check('turning the invuln off increases damage (AP-2 vs Sv3: 5+ armour < 4++)', noShield > withShield, `${withShield} -> ${noShield}`);
  await ruleChip.tap();
  await settle(page);
  await page.screenshot({ path: join(SHOTS, 'calc_04_swap_fight.png') });

  // --- abilities, detachment rule and stratagems (Meganobz into Thunderwolves, fight)
  const mega = page.locator('[data-attacker]').first();
  const gsi = mega.locator('button[data-action="arule"]', { hasText: 'Get Stuck In' });
  check('War Horde detachment rule (Sustained Hits 1) is on automatically', (await gsi.getAttribute('aria-pressed')) === 'true');
  const scG = await page.evaluate(() => window.__calc.scenario());
  check('Get Stuck In reaches the engine', scG.attackers[0].mods.sustained === 1, JSON.stringify(scG.attackers[0].mods));
  const hitEm = mega.locator('button[data-action="arule"]', { hasText: "HIT 'EM HARDER" });
  check("Hit 'Em Harder offered, off until used", (await hitEm.count()) === 1 && (await hitEm.getAttribute('aria-pressed')) === 'false');
  check('vehicle-only Mow ’Em Down not offered to Meganobz', (await mega.locator('button[data-action="arule"]', { hasText: "MOW 'EM DOWN" }).count()) === 0);
  const beforeStrat = await page.evaluate(() => window.__calc.state.result.meanWounds);
  await hitEm.tap();
  await settle(page);
  const scH = await page.evaluate(() => window.__calc.scenario());
  const afterStrat = await page.evaluate(() => window.__calc.state.result.meanWounds);
  check("using Hit 'Em Harder grants Lethal Hits and raises damage", scH.attackers[0].mods.lethal === true && afterStrat > beforeStrat, `${beforeStrat} -> ${afterStrat}`);
  // defender stratagem: Armour of Contempt (-1 AP) on the Thunderwolves
  const aoc = page.locator('button[data-action="rule"]', { hasText: 'ARMOUR OF CONTEMPT' });
  check('Armour of Contempt offered to the defender, off', (await aoc.count()) === 1 && (await aoc.getAttribute('aria-pressed')) === 'false');
  await aoc.tap();
  await settle(page);
  const withAoc = await page.evaluate(() => window.__calc.state.result.meanWounds);
  const scAoc = await page.evaluate(() => window.__calc.scenario());
  check('Armour of Contempt reaches the engine (-1 AP)', scAoc.defender.mods.apReduce === 1, JSON.stringify(scAoc.defender.mods));
  // vs the 4++ Storm Shield, AP-2 -> AP-1 still leaves 4+ as the best save: no change (correct)
  check('vs a 4++ the -1 AP changes nothing', Math.abs(withAoc - afterStrat) < 1e-9, `${afterStrat} -> ${withAoc}`);
  await ruleChip.tap(); await settle(page);
  const noShieldAoc = await page.evaluate(() => window.__calc.state.result.meanWounds);
  await aoc.tap(); await settle(page);
  const noShieldNoAoc = await page.evaluate(() => window.__calc.state.result.meanWounds);
  check('without the shield, Armour of Contempt lowers the damage', noShieldAoc < noShieldNoAoc, `${noShieldNoAoc} -> ${noShieldAoc}`);
  await aoc.tap(); await ruleChip.tap(); await settle(page);
  await page.screenshot({ path: join(SHOTS, 'calc_08_stratagems.png') });
  await page.tap('button[data-action="open-results"]');
  await page.waitForSelector('.sheet #chart svg');
  const applied = await page.locator('.sheet .section', { hasText: 'Rules applied' }).textContent();
  check('results list the rules applied and 2CP spent', /2CP/.test(applied) && /HIT 'EM HARDER/.test(applied) && /ARMOUR OF CONTEMPT/.test(applied), applied.slice(0, 200));
  await page.tap('.sheet button[data-action="close-sheet"]');
  // Thunderous Charge follows the Charged chip (Thunderwolves attacking, fight)
  await page.tap('button[data-action="swap"]');
  await page.waitForSelector('select[data-input="target"]');
  const mnz = await page.$eval('select[data-input="target"]', (sel) => [...sel.options].find(o => /^Meganobz/.test(o.textContent))?.value);
  await page.selectOption('select[data-input="target"]', mnz);
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Thunderwolf Cavalry (1)")');
  const twCard = page.locator('[data-attacker]').last();
  const tc = twCard.locator('button[data-action="arule"]', { hasText: 'Thunderous Charge' });
  check('Thunderous Charge off before charging', (await tc.getAttribute('aria-pressed')) === 'false');
  await twCard.locator('button[data-key="charged"]').tap();
  check('Thunderous Charge on after ticking Charged', (await twCard.locator('button[data-action="arule"]', { hasText: 'Thunderous Charge' }).getAttribute('aria-pressed')) === 'true');
  await settle(page);
  await page.screenshot({ path: join(SHOTS, 'calc_09_thunderous_charge.png') });
  await page.tap('button[data-action="swap"]');

  // --- state survives a reload (localStorage)
  await page.reload();
  await page.waitForSelector('[data-attacker]', { timeout: 30000 });
  check('setup restored after reload', (await page.locator('[data-attacker]').count()) === 1);
  check('used stratagem remembered after reload', (await page.locator('[data-attacker]').first().locator('button[data-action="arule"]', { hasText: "HIT 'EM HARDER" }).getAttribute('aria-pressed')) === 'true');
  const unitsB = await page.evaluate(() => window.__calc.state.armies.B.units.map(u => u.name));
  check('edited attachments survive a reload', unitsB.includes('Beastboss + Boyz') && unitsB.includes('Warboss'), unitsB.join(' | '));

  // --- offline (PWA): once the service worker has cached the shell + dataset, a reload with no network still works
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.evaluate(async () => {
    for (let i = 0; i < 100 && !(await caches.has('w40k-calc-v2') && (await (await caches.open('w40k-calc-v2')).keys()).length >= 20); i++) {
      await new Promise(r => setTimeout(r, 200));
    }
  });
  await ctx.setOffline(true);
  await page.reload();
  await page.waitForSelector('[data-attacker]', { timeout: 30000 });
  await settle(page);
  check('works offline after first visit', (await kpi(page)).every(Boolean));
  await ctx.setOffline(false);

  // --- tablet layout
  const tab = await browser.newContext({ ...devices['Galaxy Tab S4'], colorScheme: 'dark' });
  const tp = await tab.newPage();
  await tp.goto(`${BASE}/calc/`);
  await tp.fill('textarea[data-side="A"]', SW_LIST);
  await tp.tap('button[data-action="parse"][data-side="A"]');
  await tp.fill('textarea[data-side="B"]', ORK_LIST);
  await tp.tap('button[data-action="parse"][data-side="B"]');
  await tp.tap('button[data-action="view"][data-value="attack"]');
  await tp.selectOption('select[data-input="target"]', targetValue);
  await tp.tap('button[data-action="open-add"]');
  await tp.tap('.pick:has-text("Grey Hunters")');
  await tp.waitForFunction(() => window.__calc?.state.result && !window.__calc.state.busy);
  await tp.screenshot({ path: join(SHOTS, 'calc_05_tablet_dark.png') });

  check('no console errors', consoleErrors.length === 0, consoleErrors.join(' | '));
  await browser.close();
} catch (err) {
  failures++;
  console.error('E2E error:', err);
} finally {
  server.kill();
  rmSync(dbDir, { recursive: true, force: true });
}

console.log(failures ? `\n${failures} failure(s)` : '\nall checks passed');
console.log(`screenshots: ${SHOTS}`);
process.exit(failures ? 1 : 0);
