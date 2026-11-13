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

  // --- Intel tab: enemy cheat sheet, search, jump to target
  await page.tap('button[data-action="view"][data-value="intel"]');
  await page.waitForSelector('#intel-list');
  check('intel opens on the defending army (Orks)', (await page.locator('.card .title').first().textContent()) === 'Orks');
  check('intel lists the detachment rule', (await page.locator('summary', { hasText: 'Detachment rule' }).count()) === 1);
  await page.fill('input[data-input="intel-search"]', 'meganob');
  check('search narrows to Meganobz', (await page.locator('#intel-list .intel-unit').count()) === 1);
  await page.locator('#intel-list .intel-unit summary').first().tap();
  const intelText = await page.locator('#intel-list .intel-unit').first().textContent();
  check('cheat sheet shows stats, defences and weapons', /Meganob/.test(intelText) && /2\+/.test(intelText) && /-1 AP \(incoming\)/.test(intelText) && /Power Klaw/i.test(intelText), intelText.slice(0, 160));
  await page.screenshot({ path: join(SHOTS, 'calc_10_intel.png') });
  await page.locator('#intel-list button[data-action="target-this"]').first().tap();
  await page.waitForSelector('select[data-input="target"]');
  const tgtAfterIntel = await page.$eval('select[data-input="target"]', sel => sel.selectedOptions[0].textContent);
  check('"Calculate attacks into this unit" sets the target', /^Meganobz/.test(tgtAfterIntel), tgtAfterIntel);

  // --- casualties & damage on the target
  await page.locator('details[data-details="casualties"] > summary').tap();
  await page.tap('button[data-action="dmg"][data-field="count"][data-delta="-1"]');
  await page.tap('button[data-action="dmg"][data-field="woundsLeftFirst"][data-delta="-1"]');
  await page.tap('button[data-action="dmg"][data-field="woundsLeftFirst"][data-delta="-1"]');
  await settle(page);
  const scD = await page.evaluate(() => window.__calc.scenario());
  const megaG = scD.defender.groups[0];
  check('casualties reach the engine (2 Meganobz left, one on 1 wound)', megaG.count === 2 && megaG.woundsLeftFirst === 1, JSON.stringify(megaG));
  const rD = await page.evaluate(() => window.__calc.state.result);
  check('result counts 2 models / 4 wounds', rD.totalModels === 2 && rD.totalWounds === 4, `${rD.totalModels} models, ${rD.totalWounds} W`);
  await page.screenshot({ path: join(SHOTS, 'calc_11_casualties.png') });

  // --- models in range on the first attacker (Grey Hunters: 10 models)
  const ghCard = page.locator('[data-attacker]').first();
  for (let i = 0; i < 5; i++) await ghCard.locator('button[data-action="inrange"][data-delta="-1"]').tap();
  await settle(page);
  const scR = await page.evaluate(() => window.__calc.scenario());
  const carb = scR.attackers[0].weapons.find(w => /Bolt Carbine/.test(w.name));
  check('5 of 10 Grey Hunters in range -> 5 bolt carbines fire', carb?.count === 5, JSON.stringify(scR.attackers[0].weapons.map(w => [w.name, w.count])));

  // --- charge odds
  await page.tap('button[data-action="open-charge"]');
  await page.waitForSelector('#charge-need');
  for (let g = Number((await page.evaluate(() => window.__calc.state.charge.gap))); g < 9; g += 0.5) await page.tap('button[data-action="charge-gap"][data-delta="0.5"]');
  for (let g = Number((await page.evaluate(() => window.__calc.state.charge.gap))); g > 9; g -= 0.5) await page.tap('button[data-action="charge-gap"][data-delta="-0.5"]');
  check('9" gap needs a 7 (58%)', (await page.textContent('#charge-need')) === '7+' && (await page.textContent('#charge-p')) === '58%');
  await page.tap('button[data-action="charge-reroll"]');
  check('with a re-roll: 83%', (await page.textContent('#charge-p')) === '83%', await page.textContent('#charge-p'));
  await page.screenshot({ path: join(SHOTS, 'calc_12_charge.png') });
  await page.tap('.sheet button[data-action="close-sheet"]');

  // --- matchup grid (Space Wolves shooting at Orks)
  await page.tap('button[data-action="open-grid"]');
  await page.waitForFunction(() => window.__calc.state.grid?.done, null, { timeout: 60000 });
  const g = await page.evaluate(() => { const g = window.__calc.state.grid; return { rows: g.rows.length, cols: g.cols.length, total: g.total, cells: Object.keys(g.cells).length }; });
  check('grid filled every matchup', g.cells === g.total && g.total === g.rows * g.cols && g.rows >= 5 && g.cols === 5, JSON.stringify(g));
  check('grid cells rendered as buttons', (await page.locator('#grid-host .cell').count()) === g.total);
  // a cell equals the engine on the same default scenario (oracle)
  const cellCheck = await page.evaluate(() => {
    const c = window.__calc; const g = c.state.grid;
    const atk = c.atkArmy().units.find(u => u.key === g.rows[0].key);
    const def = c.defArmy().units.find(u => u.key === g.cols[0].key);
    return { cell: g.cells[`${atk.key}|${def.key}`], sc: c.defaultScenario(atk, def) };
  });
  const oracleCell = E.simulate({ ...cellCheck.sc, trials: 2000 });
  check('grid cell = engine on the same scenario', Math.abs(oracleCell.meanWounds - cellCheck.cell.meanWounds) < 1e-9, `${cellCheck.cell.meanWounds} vs ${oracleCell.meanWounds}`);
  await page.tap('button[data-action="grid-metric"][data-value="wipe"]');
  check('metric switch to wipe %', /%/.test(await page.locator('#grid-host .cell').first().textContent()));
  await page.tap('button[data-action="grid-metric"][data-value="damage"]');
  await page.screenshot({ path: join(SHOTS, 'calc_13_grid.png') });
  const pick = page.locator('#grid-host .cell').nth(1);
  const pickDef = await pick.getAttribute('data-def');
  const pickAtk = await pick.getAttribute('data-atk');
  await pick.tap();
  await page.waitForSelector('select[data-input="target"]');
  const scP = await page.evaluate(() => ({ t: window.__calc.state.setups['A:shooting'].targetKey, a: window.__calc.state.setups['A:shooting'].attackers.map(x => x.unitKey) }));
  check('tapping a cell opens that matchup', scP.t === pickDef && scP.a.length === 1 && scP.a[0] === pickAtk, JSON.stringify(scP));
  await settle(page);

  // --- saved scenarios
  await page.tap('button[data-action="open-saved"]');
  await page.fill('input[data-input="save-name"]', 'E2E matchup');
  await page.tap('button[data-action="save-scenario"]');
  check('scenario saved', await page.evaluate(() => window.__calc.state.saved.some(s => s.name === 'E2E matchup')));
  await page.tap('.sheet button[data-action="close-sheet"]');
  await page.locator('[data-attacker] button[data-action="remove"]').first().tap();
  check('attacker removed before reload of scenario', (await page.locator('[data-attacker]').count()) === 0);
  await page.tap('button[data-action="open-saved"]');
  await page.locator('.sheet .pick', { hasText: 'E2E matchup' }).locator('button[data-action="load-scenario"]').tap();
  await page.waitForSelector('[data-attacker]');
  const scL = await page.evaluate(() => ({ t: window.__calc.state.setups['A:shooting'].targetKey, a: window.__calc.state.setups['A:shooting'].attackers.map(x => x.unitKey) }));
  check('loading the scenario restores target and attacker', scL.t === pickDef && scL.a[0] === pickAtk, JSON.stringify(scL));
  await settle(page);
  await page.tap('button[data-action="open-saved"]');
  await page.screenshot({ path: join(SHOTS, 'calc_14_saved.png') });
  await page.tap('.sheet button[data-action="close-sheet"]');

  // --- points efficiency in the results sheet
  await page.tap('button[data-action="open-results"]');
  await page.waitForSelector('#pts-removed');
  const ptsTxt = [await page.textContent('#pts-removed'), await page.textContent('#pts-eff')];
  const rP = await page.evaluate(() => window.__calc.state.result);
  check('results show points destroyed and per-100-pts efficiency', rP.totalPoints > 0 && /^\d+$/.test(ptsTxt[0]) && /^\d+$/.test(ptsTxt[1]), JSON.stringify({ ptsTxt, mp: rP.meanPoints, tp: rP.totalPoints }));
  await page.tap('.sheet button[data-action="close-sheet"]');

  // --- Explosives (core stratagem): mortal wounds from a Thunderwolf Cavalry unit (EXPLOSIVES keyword)
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Thunderwolf Cavalry (2)")');
  const twc2 = page.locator('[data-attacker]').last();
  const expl = twc2.locator('button[data-action="arule"]', { hasText: 'EXPLOSIVES' });
  check('Explosives offered as a stratagem to an EXPLOSIVES unit', (await expl.count()) === 1 && (await expl.getAttribute('aria-pressed')) === 'false');
  await expl.tap();
  await settle(page);
  const scX = await page.evaluate(() => window.__calc.scenario());
  const rX = await page.evaluate(() => window.__calc.state.result);
  check('Explosives reaches the engine (6D6, 4+) and inflicts mortal wounds', scX.attackers.at(-1).mods.mortals?.[0]?.dice === 6 && rX.steps.abilityMortals > 2.5 && rX.steps.abilityMortals < 3.5,
    JSON.stringify({ m: scX.attackers.at(-1).mods.mortals, mw: rX.steps.abilityMortals }));
  await twc2.locator('button[data-action="remove"]').tap();

  // --- grid: points efficiency metric
  await page.tap('button[data-action="open-grid"]');
  await page.waitForFunction(() => window.__calc.state.grid?.done, null, { timeout: 60000 });
  await page.tap('button[data-action="grid-metric"][data-value="eff"]');
  const effTxt = await page.locator('#grid-host .cell').first().textContent();
  check('grid shows points destroyed per 100 pts', /^\d+$/.test(effTxt.trim()), effTxt);
  await page.screenshot({ path: join(SHOTS, 'calc_15_grid_efficiency.png') });
  await page.tap('button[data-action="grid-metric"][data-value="damage"]');
  await page.tap('.sheet button[data-action="close-sheet"]');

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
  // choice stratagem: picking the second option switches the first off
  const gwm1 = twCard.locator('button[data-action="arule"]', { hasText: 'GENE-WROUGHT MIGHT' }).first();
  const gwm2 = twCard.locator('button[data-action="arule"]', { hasText: 'or: ' }).filter({ hasText: 'GENE-WROUGHT MIGHT' });
  await gwm1.tap();
  check('choice option 1 on', (await twCard.locator('button[data-action="arule"]', { hasText: 'GENE-WROUGHT MIGHT' }).first().getAttribute('aria-pressed')) === 'true');
  await page.locator('[data-attacker]').last().locator('button[data-action="arule"]', { hasText: 'or: ' }).filter({ hasText: 'GENE-WROUGHT MIGHT' }).tap();
  const gw = page.locator('[data-attacker]').last().locator('button[data-action="arule"]', { hasText: 'GENE-WROUGHT MIGHT' });
  check('picking "or:" option 2 switches option 1 off', (await gw.nth(0).getAttribute('aria-pressed')) === 'false' && (await gw.nth(1).getAttribute('aria-pressed')) === 'true');
  await gw.nth(1).tap();
  check('Thunderous Charge on after ticking Charged', (await twCard.locator('button[data-action="arule"]', { hasText: 'Thunderous Charge' }).getAttribute('aria-pressed')) === 'true');
  await settle(page);
  await page.screenshot({ path: join(SHOTS, 'calc_09_thunderous_charge.png') });
  await page.tap('button[data-action="open-add"]');
  await page.tap('.pick:has-text("Grey Hunters")');
  const ghF = page.locator('[data-attacker]').last();
  const objChip = ghF.locator('button[data-action="amod-toggle"][data-key="onObjective"]');
  const cunning = () => ghF.locator('button[data-action="arule"]', { hasText: 'Cunning Hunters' });
  check('"On an objective" chip offered because Cunning Hunters needs it', (await objChip.count()) === 1 && (await cunning().getAttribute('aria-pressed')) === 'false');
  await objChip.tap();
  check('ticking "On an objective" switches Cunning Hunters on', (await cunning().getAttribute('aria-pressed')) === 'true');
  await settle(page);
  await page.screenshot({ path: join(SHOTS, 'calc_16_situation.png') });
  await ghF.locator('button[data-action="remove"]').tap();
  await page.tap('button[data-action="swap"]');

  // --- state survives a reload (localStorage)
  await page.reload();
  await page.waitForSelector('[data-attacker]', { timeout: 30000 });
  check('setup restored after reload', (await page.locator('[data-attacker]').count()) === 1);
  check('saved scenarios survive a reload', await page.evaluate(() => window.__calc.state.saved.length) === 1);
  check('used stratagem remembered after reload', (await page.locator('[data-attacker]').first().locator('button[data-action="arule"]', { hasText: "HIT 'EM HARDER" }).getAttribute('aria-pressed')) === 'true');
  const unitsB = await page.evaluate(() => window.__calc.state.armies.B.units.map(u => u.name));
  check('edited attachments survive a reload', unitsB.includes('Beastboss + Boyz') && unitsB.includes('Warboss'), unitsB.join(' | '));

  // --- offline (PWA): once the service worker has cached the shell + dataset, a reload with no network still works
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.evaluate(async () => {
    for (let i = 0; i < 100 && !(await caches.has('w40k-calc-v9') && (await (await caches.open('w40k-calc-v9')).keys()).length >= 20); i++) {
      await new Promise(r => setTimeout(r, 200));
    }
  });
  await ctx.setOffline(true);
  await page.reload();
  await page.waitForSelector('[data-attacker]', { timeout: 30000 });
  await settle(page);
  check('works offline after first visit', (await kpi(page)).every(Boolean));
  await ctx.setOffline(false);

  // --- board planner: official GW layout, tokens, rings, gap -> calculator, steps, ruler, export
  const toScreen = (x, y) => page.evaluate(([bx, by]) => {
    const svg = document.getElementById('board-svg');
    const pt = svg.createSVGPoint(); pt.x = bx; pt.y = by;
    const q = pt.matrixTransform(svg.getScreenCTM());
    return { x: q.x, y: q.y };
  }, [x, y]);
  const tokens = () => page.evaluate(() => window.__calc.board().tokens);
  await page.tap('button[data-action="view"][data-value="board"]');
  await page.waitForSelector('#board-svg');
  const missionTxt = (await page.textContent('#board-mission')).replace(/\s+/g, ' ');
  check('board picks the mission from both lists (Take and Hold vs Take and Hold)', /Battlefield Dominance/.test(missionTxt) && /Tipping Point/.test(missionTxt), missionTxt);
  check('official layout drawn (terrain + zones)', (await page.locator('#board-svg polygon').count()) > 40);
  await page.tap('button[data-action="board-variant"][data-value="2"]');
  check('layout 2 uses Dawn of War', /Dawn of War/.test(await page.textContent('#board-mission')));
  await page.tap('button[data-action="board-variant"][data-value="1"]');
  await page.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
  await page.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Beastboss + Boyz' }).first().tap();
  let bTk = await tokens();
  const bGh = bTk.find(t => t.tk.startsWith('A:')), bBoyz = bTk.find(t => t.tk.startsWith('B:'));
  check('two units placed in their own deployment zones', bTk.length === 2 && bGh.y < 30 && bBoyz.y > 30, JSON.stringify(bTk));
  // drag the Grey Hunters 12" towards the Orks
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  let p0 = await toScreen(bGh.x, bGh.y), p1 = await toScreen(bGh.x, bGh.y + 12);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  for (let i = 1; i <= 6; i++) await page.mouse.move(p0.x, p0.y + (p1.y - p0.y) * i / 6);
  await page.mouse.up();
  bTk = await tokens();
  const bGh2 = bTk.find(t => t.tk === bGh.tk);
  check('dragging moves the unit (~12")', Math.abs(bGh2.y - bGh.y - 12) < 0.5, `${bGh.y} -> ${bGh2.y}`);
  // select it (tap) and show its 24" range
  const empty = await toScreen(40, 30);
  await page.mouse.click(empty.x, empty.y); // tap empty board: clear the selection
  p0 = await toScreen(bGh2.x, bGh2.y);
  await page.mouse.click(p0.x, p0.y);
  check('tap selects the unit', (await page.evaluate(() => window.__calc.board().sel)) === bGh.tk);
  await page.locator('button[data-action="board-ring"]', { hasText: 'Range 24"' }).tap();
  check('24" range ring drawn', (await page.locator('#board-svg [data-ring="r24"]').count()) === 1);
  // tap the Boyz: gap + Shoot -> calculator with that distance
  const b0 = await toScreen(bBoyz.x, bBoyz.y);
  await page.mouse.click(b0.x, b0.y);
  const gapTxt = await page.textContent('#board-gap');
  const gapIn = parseFloat(gapTxt.match(/([\d.]+)"/)[1]);
  check('second tap measures the gap between the units', gapIn > 0 && gapIn < 40, gapTxt);
  await page.screenshot({ path: join(SHOTS, 'calc_19_board.png') });
  await page.tap('button[data-action="board-attack"][data-phase="shooting"]');
  await page.waitForSelector('select[data-input="target"]');
  const fromBoard = await page.evaluate(() => { const st = window.__calc.state.setups['A:shooting']; return { t: st.targetKey, a: st.attackers.map(x => [x.unitKey, x.mods.distance]) }; });
  check('"Shoot →" opens the calculator: that unit into that target at the measured distance',
    fromBoard.t === bBoyz.tk.split(':')[1] && fromBoard.a.some(([k, d]) => k === bGh.tk.split(':')[1] && Math.abs(d - gapIn) <= 0.51), JSON.stringify({ fromBoard, gapIn, boyz: bBoyz.tk, gh: bGh.tk }));
  // plan steps: Turn 1 copies Deploy; moving in Turn 1 leaves Deploy untouched
  await page.tap('button[data-action="view"][data-value="board"]');
  await page.waitForSelector('#board-svg');
  await page.tap('button[data-action="board-step-add"]');
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  p0 = await toScreen(bGh2.x, bGh2.y); p1 = await toScreen(bGh2.x + 6, bGh2.y);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  for (let i = 1; i <= 4; i++) await page.mouse.move(p0.x + (p1.x - p0.x) * i / 4, p0.y);
  await page.mouse.up();
  const t1 = (await tokens()).find(t => t.tk === bGh.tk);
  await page.tap('button[data-action="board-step"][data-i="0"]');
  const d0 = (await tokens()).find(t => t.tk === bGh.tk);
  check('Turn 1 is its own step (Deploy keeps the old position)', Math.abs(t1.x - bGh2.x - 6) < 0.5 && Math.abs(d0.x - bGh2.x) < 0.01, JSON.stringify({ t1, d0 }));
  // rotate the Grey Hunters 90° (two 45° taps): rows of 5 become a column; then a 10-wide line
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  p0 = await toScreen(bGh2.x, bGh2.y);
  await page.mouse.click(p0.x, p0.y);
  await page.tap('button[data-action="board-rotate"][data-deg="45"]');
  await page.tap('button[data-action="board-rotate"][data-deg="45"]');
  const spread = () => page.evaluate((tk) => {
    const g = document.querySelector(`#board-svg [data-tok="${tk}"]`).getBBox();
    return { w: g.width, h: g.height };
  }, bGh.tk);
  const rotated = await spread();
  check('rotating 90° turns the formation (taller than wide)', rotated.h > rotated.w && /Facing 90°/.test(await page.textContent('#board-panel')), JSON.stringify(rotated));
  await page.tap('button[data-action="board-rotate"][data-deg="-45"]');
  await page.tap('button[data-action="board-rotate"][data-deg="-45"]');
  await page.tap('button[data-action="board-formation"][data-value="10"]');
  const line = await spread();
  check('formation of 10 per row = a single line', line.w > 3 * line.h, JSON.stringify(line));
  await page.tap('button[data-action="board-formation"][data-value="5"]');
  // zoom out past the board: whole board in view, centred, and the board fits the screen
  for (let i = 0; i < 4; i++) await page.tap('button[data-action="board-zoom"][data-z="1.4"]');
  const zo = await page.evaluate(() => { const svg = document.getElementById('board-svg'); const [x, y, w] = svg.getAttribute('viewBox').split(' ').map(Number); return { x, w, h: svg.getBoundingClientRect().height, vh: innerHeight }; });
  check('zooming out goes past the whole board and keeps it centred', zo.w > 45 && Math.abs(zo.x + (zo.w - 44) / 2) < 0.6 && zo.h <= zo.vh, JSON.stringify(zo));
  await page.tap('button[data-action="board-zoom"][data-z="0"]');

  // ruler: 20" straight down
  await page.tap('button[data-action="board-mode"][data-value="ruler"]');
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  p0 = await toScreen(4, 20); p1 = await toScreen(4, 40);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  for (let i = 1; i <= 5; i++) await page.mouse.move(p0.x, p0.y + (p1.y - p0.y) * i / 5);
  await page.mouse.up();
  const rulerTxt = await page.locator('#board-svg #ruler-label text').textContent();
  check('ruler measures 20.0"', rulerTxt === '20.0"', rulerTxt);
  await page.tap('button[data-action="board-mode"][data-value="move"]');
  // export the plan as an image (download on desktop browsers)
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }), page.tap('button[data-action="board-share"]')]);
  check('plan exports as a PNG', /\.png$/.test(dl.suggestedFilename()), dl.suggestedFilename());
  await dl.saveAs(join(SHOTS, 'calc_20_board_export.png'));
  await page.reload();
  await page.waitForSelector('#board-svg');
  check('board plan survives a reload (2 steps, 2 units)', await page.evaluate(() => { const b = window.__calc.board(); return b.plan.steps.length === 2 && b.tokens.length === 2; }));

  // --- threat view: what in the Ork army hurts the Grey Hunters most
  await page.tap('button[data-action="view"][data-value="intel"]');
  await page.tap('button[data-action="intel-side"][data-value="A"]');
  await page.fill('input[data-input="intel-search"]', 'grey hunters');
  await page.locator('#intel-list .intel-unit summary').first().tap();
  await page.locator('#intel-list button[data-action="open-threats"]').first().tap();
  await page.waitForFunction(() => window.__calc.state.threats?.done, null, { timeout: 60000 });
  const thr = await page.evaluate(() => { const t = window.__calc.state.threats; return { n: Object.keys(t.cells).length, total: t.total, units: t.units.length }; });
  check('threat view ran every enemy unit in both phases', thr.n === thr.total && thr.total >= thr.units, JSON.stringify(thr));
  const firstVals = await page.$$eval('.sheet table.threats tbody tr', trs => trs.map(tr => Math.max(...[...tr.querySelectorAll('.cell')].map(b => parseInt(b.textContent, 10) || 0))));
  check('threats sorted, biggest first', firstVals.every((v, i) => i === 0 || v <= firstVals[i - 1]), firstVals.join(','));
  await page.screenshot({ path: join(SHOTS, 'calc_17_threats.png') });
  await page.locator('.sheet table.threats .cell').first().tap();
  await page.waitForSelector('select[data-input="target"]');
  const scT = await page.evaluate(() => ({ side: window.__calc.state.side, t: window.__calc.scenario()?.defender?.name }));
  check('tapping a threat opens that matchup (Orks attacking the Grey Hunters)', scT.side === 'B' && scT.t === 'Grey Hunters', JSON.stringify(scT));

  // --- list library: save both lists, load one into the other slot
  await page.tap('button[data-action="view"][data-value="armies"]');
  await page.tap('button[data-action="open-library"][data-side="A"]');
  await page.fill('input[data-input="lib-name"]', 'R1 – Wolves');
  await page.tap('button[data-action="lib-save"][data-side="A"]');
  check('saved list shows in the library sheet', (await page.locator('.sheet .pick', { hasText: 'R1 – Wolves' }).count()) === 1);
  await page.tap('.sheet button[data-action="close-sheet"]');
  await page.tap('button[data-action="open-library"][data-side="B"]');
  await page.fill('input[data-input="lib-name"]', 'R2 – Orks');
  await page.tap('button[data-action="lib-save"][data-side="B"]');
  check('library holds both lists', await page.evaluate(() => window.__calc.state.library.map(l => l.name).join('|')) === 'R2 – Orks|R1 – Wolves');
  await page.screenshot({ path: join(SHOTS, 'calc_18_library.png') });
  await page.locator('.sheet .pick', { hasText: 'R1 – Wolves' }).locator('button[data-action="lib-load"][data-side="B"]').tap();
  check('loading from the library replaces army B', await page.evaluate(() => window.__calc.state.armies.B.faction) === 'Space Wolves');
  await page.reload();
  await page.waitForSelector('textarea[data-side="A"]');
  check('library survives a reload', await page.evaluate(() => window.__calc.state.library.length) === 2);

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
  const land = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
  const lp = await land.newPage();
  await lp.goto(`${BASE}/calc/`);
  await lp.fill('textarea[data-side="A"]', SW_LIST);
  await lp.tap('button[data-action="parse"][data-side="A"]');
  await lp.fill('textarea[data-side="B"]', ORK_LIST);
  await lp.tap('button[data-action="parse"][data-side="B"]');
  await lp.tap('button[data-action="view"][data-value="board"]');
  await lp.waitForSelector('#board-svg');
  const fitL = await lp.evaluate(() => ({ h: document.getElementById('board-svg').getBoundingClientRect().height, vh: innerHeight }));
  check('landscape tablet: the whole board fits on screen', fitL.h <= fitL.vh, JSON.stringify(fitL));
  await lp.locator('#board-host').scrollIntoViewIfNeeded();
  await lp.screenshot({ path: join(SHOTS, 'calc_21_board_tablet_landscape.png') });
  await land.close();
  // GW app list with U+2011 non-breaking hyphens (Contemptor‑Galatus, Grav‑Tank) imports cleanly
  await tp.tap('button[data-action="view"][data-value="armies"]');
  await tp.fill('textarea[data-side="B"]', readFileSync(join(here, 'fixtures', 'gw-custodes-nbhyphen.txt'), 'utf8'));
  await tp.tap('button[data-action="parse"][data-side="B"]');
  const custodes = await tp.evaluate(() => ({ units: window.__calc.state.armies.B.units.map(u => u.name), warnings: window.__calc.state.armies.B.warnings }));
  check('non-breaking-hyphen units resolve (Caladius, 2x Contemptor-Galatus)',
    custodes.units.includes('Caladius Annihilator Grav-Tank') && custodes.units.filter(n => /^Contemptor-Galatus/.test(n)).length === 2 &&
    !custodes.warnings.some(w => /unresolved|not recognised/.test(w)), JSON.stringify(custodes));

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
