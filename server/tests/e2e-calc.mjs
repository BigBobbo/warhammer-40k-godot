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
import { mkdtempSync, existsSync, rmSync, readFileSync, mkdirSync, writeFileSync } from 'fs';
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

  // --- "Plunging fire" (22.05, +1 BS from a tall terrain section): more hits; off again afterwards
  const plungeChip = page.locator('[data-attacker]').first().locator('button[data-key="plunging"]');
  await plungeChip.tap();
  await settle(page);
  const plunged = await page.evaluate(() => ({ kills: window.__calc.state.result.meanKills, hits: window.__calc.state.result.steps.hits }));
  const hitsBefore = (await page.evaluate(() => window.__calc.scenario())).attackers[0].mods.plunging;
  check('plunging fire chip is on in the scenario and raises expected kills', hitsBefore === true && plunged.kills > after, `${after} -> ${plunged.kills}`);
  await page.screenshot({ path: join(SHOTS, 'calc_36_plunging_fire.png'), fullPage: false });
  await plungeChip.tap();
  await settle(page);
  check('plunging fire off: back to the half-range result', Math.abs((await page.evaluate(() => window.__calc.state.result.meanKills)) - after) < 1e-9);

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
  check('intel opens with the matchup brief, then the defending army (Orks)', (await page.locator('.card .title').first().textContent()) === 'Matchup brief' && (await page.locator('.card:not(.brief-card) .title').first().textContent()) === 'Orks');
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
  // 11.04: the target must be within the charge roll before the unit moves: 9" needs a 9 (28%), not a 7 (58%)
  check('9" gap needs a 9 (28%)', (await page.textContent('#charge-need')) === '9+' && (await page.textContent('#charge-p')) === '28%', `${await page.textContent('#charge-need')} ${await page.textContent('#charge-p')}`);
  await page.tap('button[data-action="charge-reroll"]');
  check('with a re-roll: 48%', (await page.textContent('#charge-p')) === '48%', await page.textContent('#charge-p'));
  // modifiers add up (02.02.01): +2 makes it a 7+ (58%; 83% with the re-roll)
  await page.tap('button[data-action="charge-mod"][data-value="2"]');
  check('+2 to the charge roll: 83% with the re-roll', (await page.textContent('#charge-p')) === '83%', await page.textContent('#charge-p'));
  await page.tap('button[data-action="charge-mod"][data-value="0"]');
  check('the charge tool states the rule (11.04) and lists "over 12" as not chargeable', /11\.04/.test(await page.textContent('#charge-rule')) && /over 12"\s*—\s*cannot be charged/.test((await page.textContent('#sheet')).replace(/\s+/g, ' ')), (await page.textContent('#sheet')).replace(/\s+/g, ' ').slice(-400));
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

  // version shown, and a new version is picked up on the next load (network first, offline copy as fallback)
  const { CALC_VERSION } = await import(new URL('../public/calc/version.mjs', import.meta.url).href);
  check('header shows the app version (under the icon on a phone)', (await page.textContent('#app-version-mini')).trim() === `v${CALC_VERSION}` && await page.isVisible('#app-version-mini'));
  const vFile = join(here, '..', 'public', 'calc', 'version.mjs');
  const vOrig = readFileSync(vFile, 'utf8');
  try {
    writeFileSync(vFile, vOrig.replace(CALC_VERSION, '9.9.9'));
    await page.reload();
    await page.waitForSelector('#app-version-mini');
    check('a new version is used on the next load even with the offline copy installed', (await page.textContent('#app-version-mini')).trim() === 'v9.9.9', await page.textContent('#app-version-mini'));
  } finally {
    writeFileSync(vFile, vOrig);
  }
  await page.reload();
  await page.waitForSelector('#app-version-mini');

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
  // the selected unit's actions are pinned at the bottom of the phone screen: the map stays put
  check('phone: a dock with the selected unit\'s actions is pinned to the bottom, map still in view', (await page.isVisible('#board-dock .dock-in')) && (await page.evaluate(() => window.scrollY)) < 200 && /Grey Hunters/.test(await page.textContent('#board-dock')));
  await page.locator('#board-dock button[data-action="board-ring"]', { hasText: 'Range 24"' }).tap();
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

  // --- table photo: a synthetic photo of the table taken from one end (perspective), corners tapped
  // anticlockwise (must not mirror), flattened under the map; a magenta "model" at board (30, 45)
  // must land at (30, 45)
  const PC = [[330, 140], [1080, 150], [1340, 930], [70, 915]]; // table corners in the 1400x1000 photo
  const photoB64 = await page.evaluate(async (pc) => {
    const { boardSvg } = await import('/calc/boardview.mjs');
    const P = await import('/calc/photo.mjs');
    const svgText = boardSvg({ forExport: true }).replace(/viewBox="[^"]*"/, 'viewBox="0 0 44 60"');
    const img = new Image();
    img.src = URL.createObjectURL(new Blob([svgText], { type: 'image/svg+xml' }));
    await img.decode();
    const bc = document.createElement('canvas'); bc.width = 880; bc.height = 1200;
    const bg = bc.getContext('2d'); bg.drawImage(img, 0, 0, 880, 1200);
    bg.fillStyle = '#ff00ff'; bg.beginPath(); bg.arc(30 * 20, 45 * 20, 15, 0, 7); bg.fill();
    const H = P.homography(pc, [[0, 0], [880, 0], [880, 1200], [0, 1200]]);
    const out = P.warpToBoard(bg.getImageData(0, 0, 880, 1200), H, { w: 1400, h: 1000 }, 1);
    for (let i = 0; i < out.data.length; i += 4) if (out.data[i + 3] === 0) { out.data[i] = 60; out.data[i + 1] = 45; out.data[i + 2] = 35; out.data[i + 3] = 255; }
    const c = document.createElement('canvas'); c.width = 1400; c.height = 1000;
    c.getContext('2d').putImageData(new ImageData(out.data, 1400, 1000), 0, 0);
    return c.toDataURL('image/jpeg', 0.92).split(',')[1];
  }, PC);
  const photoFile = join(SHOTS, 'calc_synthetic_table_photo.jpg');
  writeFileSync(photoFile, Buffer.from(photoB64, 'base64'));
  await page.locator('#board-photo-bar').scrollIntoViewIfNeeded();
  await page.setInputFiles('input[data-input="board-photo"]', photoFile);
  await page.waitForSelector('.photo-ov #photo-svg image');
  const imgToScreen = (x, y) => page.evaluate(([ix, iy]) => {
    const svg = document.getElementById('photo-svg');
    const pt = svg.createSVGPoint(); pt.x = ix; pt.y = iy;
    const q = pt.matrixTransform(svg.getScreenCTM());
    return { x: q.x, y: q.y };
  }, [x, y]);
  // the downscale keeps 1400 px (under the 1600 cap), so photo px = image px
  for (const i of [0, 3, 2, 1]) { const q = await imgToScreen(...PC[i]); await page.mouse.click(q.x, q.y); }
  check('corner screen: 4 corners placed, "Use photo" enabled', await page.isEnabled('.photo-ov [data-ov="ok"]'));
  // drag a corner a little and back: the loupe shows while the finger is down
  let q0 = await imgToScreen(...PC[2]);
  await page.mouse.move(q0.x, q0.y); await page.mouse.down(); await page.mouse.move(q0.x - 6, q0.y - 6);
  check('loupe shows while dragging a corner', await page.evaluate(() => [...document.querySelectorAll('#photo-svg g[clip-path]')].some(g => g.getAttribute('visibility') === 'visible')));
  await page.screenshot({ path: join(SHOTS, 'calc_22_photo_corners.png') });
  await page.mouse.move(q0.x, q0.y); await page.mouse.up();
  await page.tap('.photo-ov [data-ov="ok"]');
  await page.waitForSelector('#board-svg #board-photo', { timeout: 15000 });
  check('overlay closed after "Use photo"', (await page.locator('.photo-ov').count()) === 0);
  const samplePhoto = () => page.evaluate(async () => {
    const im = document.querySelector('#board-svg #board-photo');
    const img = new Image(); img.src = im.getAttribute('href'); await img.decode();
    const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data, ppi = c.width / 44;
    let n = 0, sx = 0, sy = 0;
    for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
      const o = (y * c.width + x) * 4;
      if (d[o] > 200 && d[o + 1] < 90 && d[o + 2] > 200) { n++; sx += x; sy += y; }
    }
    const px = (bx, by) => { const o = (Math.floor(by * ppi) * c.width + Math.floor(bx * ppi)) * 4; return [d[o], d[o + 1], d[o + 2]]; };
    return { w: c.width, h: c.height, magenta: n ? { x: (sx / n + 0.5) / ppi, y: (sy / n + 0.5) / ppi, n } : null, corner: px(0.6, 0.6), farCorner: px(43.4, 59.4) };
  });
  const ph = await samplePhoto();
  const err = ph.magenta ? Math.hypot(ph.magenta.x - 30, ph.magenta.y - 45) : Infinity;
  check('photo flattened onto the board: the model at (30, 45) lands within 0.25"', err <= 0.25, JSON.stringify(ph));
  check('board corners line up (table mat, not the dark floor, at both corners)', ph.corner.reduce((a, b) => a + b) > 450 && ph.farCorner.reduce((a, b) => a + b) > 450, JSON.stringify(ph));
  console.log(`  photo trace error at the marker: ${err.toFixed(3)}" (photo ${ph.w}x${ph.h})`);
  // map over the photo: Photo only -> map hidden; back to Photo + map
  await page.tap('button[data-action="board-photo-map"][data-value="photo"]');
  check('"Photo" hides the map layer', await page.getAttribute('#board-svg #board-map', 'opacity') === '0');
  await page.tap('button[data-action="board-photo-map"][data-value="both"]');
  // wrong way round? Turn cycles which corner is the map's top-left; 4 turns = back where we started
  for (let i = 1; i <= 4; i++) {
    await page.tap('button[data-action="board-photo-turn"]');
    await page.waitForFunction((n) => window.__calc.board().photo?.turn === n % 4, i);
  }
  const ph2 = await samplePhoto();
  check('Turn x4 returns to the original photo', ph2.magenta && Math.hypot(ph2.magenta.x - 30, ph2.magenta.y - 45) <= 0.25, JSON.stringify(ph2.magenta));
  // trace: drag the Grey Hunters onto the magenta model; facing survives the drag; nudge moves 0.5"
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  let ghPos = (await tokens()).find(t => t.tk === bGh.tk);
  if ((await page.evaluate(() => window.__calc.board().sel)) !== bGh.tk) { const q = await toScreen(ghPos.x, ghPos.y); await page.mouse.click(q.x, q.y); }
  await page.tap('button[data-action="board-rotate"][data-deg="45"]');
  await page.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
  p0 = await toScreen(ghPos.x, ghPos.y); p1 = await toScreen(30, 45);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  for (let i = 1; i <= 6; i++) await page.mouse.move(p0.x + (p1.x - p0.x) * i / 6, p0.y + (p1.y - p0.y) * i / 6);
  await page.mouse.up();
  ghPos = (await tokens()).find(t => t.tk === bGh.tk);
  check('dragging keeps the unit\'s facing (45°)', ghPos.rot === 45 && Math.hypot(ghPos.x - 30, ghPos.y - 45) < 0.6, JSON.stringify(ghPos));
  if ((await page.evaluate(() => window.__calc.board().sel)) !== bGh.tk) { const q = await toScreen(ghPos.x, ghPos.y); await page.mouse.click(q.x, q.y); }
  await page.tap('button[data-action="board-nudge"][data-dx="0.5"]');
  const nud = (await tokens()).find(t => t.tk === bGh.tk);
  check('nudge → moves the unit 0.5" and shows its position', Math.abs(nud.x - ghPos.x - 0.5) < 1e-6 && /from left/.test(await page.textContent('#board-pos')), JSON.stringify({ ghPos, nud }));
  await page.tap('button[data-action="board-nudge"][data-dx="-0.5"]');
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_23_board_photo.png') });
  await page.reload();
  await page.waitForSelector('#board-svg');
  await page.waitForSelector('#board-svg #board-photo', { timeout: 15000 });
  check('table photo survives a reload (stored on the device)', (await page.evaluate(() => window.__calc.board().photo?.taps?.length)) === 4);

  // --- line of sight + cover (11e terrain on the map), danger zones, threats, turn chain
  await page.tap('button[data-action="board-photo-map"][data-value="map"]');
  await page.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Meganobz' }).tap();
  const mnTk = (await tokens()).find(t => t.tk.startsWith('B:') && t.tk !== bBoyz.tk).tk;
  // find one spot where the Meganobz are hidden from the Grey Hunters behind terrain, and one in plain sight
  const spots = await page.evaluate(async ({ gh, mn }) => {
    const S = await import('/calc/sight.mjs');
    const { LAYOUTS } = await import('/calc/terrain-11e.mjs');
    const d = window.__calc.board();
    const pieces = LAYOUTS.find(l => l.id === d.layout).pieces;
    const U = Object.fromEntries(d.units.map(u => [u.tk, u]));
    const att = { ...U[gh], x: 22, y: 30, models: U[gh].models.map(m => ({ ...m })) };
    const range = Math.max(...U[gh].ranges);
    let blocked = null, clear = null;
    for (let y = 4; y <= 56 && !(blocked && clear); y += 1) for (let x = 3; x <= 41 && !(blocked && clear); x += 1) {
      const tgt = { ...U[mn], x, y };
      const v = S.sightVerdict(att, tgt, pieces, { range });
      if (!blocked && v.verdict === 'blocked' && !v.borderline && Math.hypot(x - 22, y - 30) < range) blocked = { x, y, v };
      if (!clear && v.verdict === 'clear' && !v.borderline && !v.cover && Math.hypot(x - 22, y - 30) < range - 6) clear = { x, y, v };
    }
    return { blocked, clear };
  }, { gh: bGh.tk, mn: mnTk });
  check('found a blocked and a clear spot on this layout', !!(spots.blocked && spots.clear), JSON.stringify(spots));
  const placeAt = (tk, x, y) => page.evaluate(([t, px, py]) => { const p = window.__calc.board().plan; Object.assign(p.steps[p.cur].tokens[t], { x: px, y: py }); }, [tk, x, y]);
  const pairUp = async () => {
    await page.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
    const empty = await toScreen(43, 59.5); await page.mouse.click(empty.x, empty.y);
    const toks2 = await tokens();
    for (const tk of [bGh.tk, mnTk]) { const t = toks2.find(x => x.tk === tk); const q = await toScreen(t.x, t.y); await page.mouse.click(q.x, q.y); }
  };
  await page.evaluate(([t]) => { const p = window.__calc.board().plan; p.steps[p.cur].tokens[t].rot = 0; }, [bGh.tk]);
  await placeAt(bGh.tk, 22, 30);
  await placeAt(mnTk, spots.blocked.x, spots.blocked.y);
  await pairUp();
  let sightEl = page.locator('#board-sight');
  check('pair card shows line of sight: Blocked behind terrain', await sightEl.getAttribute('data-verdict') === 'blocked' && /Blocked/.test(await sightEl.textContent()), await sightEl.textContent().catch(() => 'no #board-sight'));
  await placeAt(mnTk, spots.clear.x, spots.clear.y);
  await pairUp();
  sightEl = page.locator('#board-sight');
  check('…and Clear in the open, no cover', await sightEl.getAttribute('data-verdict') === 'clear' && /Benefit of cover: no/.test(await sightEl.textContent()), await sightEl.textContent());
  await page.locator('#board-panel').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_24_board_sight.png') });
  // danger zones from the Orks + who threatens the Grey Hunters
  await page.tap('button[data-action="board-danger"][data-value="B"]');
  check('danger zones drawn from army B (shooting + charge bands)', (await page.locator('#board-svg #danger-layer[data-from="B"] [data-dz]').count()) >= 2);
  check('Grey Hunters list the Ork units that threaten them next turn', /charge \d+%|🎯/.test(await page.textContent('#board-threats')), await page.textContent('#board-threats'));
  await page.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
  await page.screenshot({ path: join(SHOTS, 'calc_25_board_danger.png') });
  await page.tap('button[data-action="board-danger"][data-value="off"]');
  // board -> turn chain (shoot, charge, fight) with this gap; cover + models seeing passed to the calculator
  await pairUp();
  const chainGap = parseFloat((await page.textContent('#board-gap')).match(/([\d.]+)"/)[1]);
  await page.tap('button[data-action="board-attack"][data-phase="chain"]');
  await page.waitForSelector('#chain-total', { timeout: 60000 });
  const ch = await page.evaluate(() => ({ r: window.__calc.state.chainResult, c: window.__calc.state.chain, setup: window.__calc.state.setups[`${window.__calc.state.side}:shooting`] }));
  check('turn chain opens from the board: Grey Hunters shoot, charge and fight the Meganobz', ch.c.chargerKey === bGh.tk.split(':')[1] && ch.setup.targetKey === mnTk.split(':')[1] && Math.abs(ch.c.gap - Math.round(chainGap)) < 0.01, JSON.stringify({ c: ch.c, t: ch.setup.targetKey }));
  check('chain result: total = shooting + fight, odds in range', ch.r && Math.abs(ch.r.meanKills - ch.r.meanShoot - ch.r.meanFight) < 1e-9 && ch.r.pChargeGivenSurvive >= 0 && ch.r.pChargeGivenSurvive <= 1 && ch.r.pWipe <= 1, JSON.stringify(ch.r && { s: ch.r.meanShoot, f: ch.r.meanFight, p: ch.r.pChargeGivenSurvive }));
  check('board passed cover = no for a target in plain sight', ch.setup.defManual?.cover === false);
  // 11.04: the target must be within 12" and within the charge roll - from more than 12" there is no charge
  if (ch.c.gap > 12) check(`${ch.c.gap}" on the board: the chain says the charge cannot be made`, ch.r.pChargeGivenSurvive === 0 && ch.r.meanFight === 0 && /more than 12": cannot be charged/.test(await page.textContent('#chain-need')), await page.textContent('#chain-need'));
  // at 9" it is a 9+ on 2D6: 28% (the old "gap - 2" rule made it 58%)
  for (let g = ch.c.gap; g > 9; g -= 0.5) await page.tap('button[data-action="chain-gap"][data-delta="-0.5"]');
  for (let g = ch.c.gap; g < 9; g += 0.5) await page.tap('button[data-action="chain-gap"][data-delta="0.5"]');
  await page.waitForFunction(() => { const s = window.__calc.state; return s.chain.gap === 9 && s.chainResult && !s.chainBusy; }, null, { timeout: 60000 });
  const p0Charge = await page.evaluate(() => window.__calc.state.chainResult.pChargeGivenSurvive);
  check('a 9" charge in the chain lands about 28% of the time (9+ on 2D6)', Math.abs(p0Charge - 10 / 36) < 0.02 && /9\+ on 2D6/.test(await page.textContent('#chain-need')), `${p0Charge} | ${await page.textContent('#chain-need')}`);
  for (let i = 0; i < 4; i++) await page.tap('button[data-action="chain-gap"][data-delta="0.5"]');
  await page.waitForFunction((p) => { const s = window.__calc.state; return s.chain.gap === 11 && s.chainResult && !s.chainBusy && s.chainResult.pChargeGivenSurvive < p; }, p0Charge, { timeout: 60000 });
  check('a longer charge lowers the odds', true);
  await page.screenshot({ path: join(SHOTS, 'calc_26_turn_chain.png') });
  await page.tap('.sheet button[data-action="close-sheet"]');
  await page.tap('button[data-action="view"][data-value="board"]');
  await page.waitForSelector('#board-svg');

  // --- Mission tab: forecast for both players, objective plan, secondary card sheet, in-game tracker
  await page.tap('button[data-action="view"][data-value="mission"]');
  await page.waitForSelector('#fc-win', { timeout: 60000 });
  await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.levers?.length >= 4; }, null, { timeout: 60000 });
  let mi = await page.evaluate(() => window.__calc.mission());
  check('mission tab names both primaries and classifies the objectives (2 homes, centre, expansions)', /plays/.test(await page.textContent('#mission-names'))
    && mi.objectives.filter(o => o.cls === 'home').length === 2 && mi.objectives.some(o => o.cls === 'central'), JSON.stringify(mi.objectives));
  check('forecast: a VP range for each player, win chance and lead by round', mi.result.A.p10 <= mi.result.A.p50 && mi.result.A.p50 <= mi.result.A.p90
    && Math.abs(mi.result.pWinA + mi.result.pWinB + mi.result.pDraw - 1) < 1e-9 && (await page.locator('#fc-lead .cell').count()) === 5, JSON.stringify({ A: mi.result.A.mean, B: mi.result.B.mean }));
  check('caps respected (each player at most 100 VP; 15 per round per source)', ['A', 'B'].every(X => mi.result[X].p90 <= 100 && mi.result[X].prim.every(v => v <= 15) && mi.result[X].sec.every(v => v <= 15)));
  check('what-ifs listed (objectives, trading)', (await page.locator('#fc-levers tbody tr').count()) >= 4);
  await page.screenshot({ path: join(SHOTS, 'calc_27_mission_forecast.png') });
  // the forecast knows the armies: the 2,000-point list is the clear favourite over the 665-point one,
  // and its units destroyed per turn come from the calculator. (Read once the unit-vs-unit odds are in:
  // until then the forecast on screen uses the same default kill rate for both armies.)
  await page.waitForFunction(() => window.__calc.mission().pairsReady && !window.__calc.mission().busy, null, { timeout: 120000 });
  mi = await page.evaluate(() => window.__calc.mission());
  check('forecast favours the much bigger army (was a coin flip before 1.92)', mi.result.pWinA > 0.85 && mi.result.A.mean > mi.result.B.mean + 20, JSON.stringify({ win: mi.result.pWinA, A: mi.result.A.mean, B: mi.result.B.mean }));
  check('units destroyed per turn come from the calculator for both armies', mi.killRate.A.from === 'calc' && mi.killRate.B.from === 'calc' && mi.killRate.A.rate > mi.killRate.B.rate && mi.params.players.A.killRate === null && !!mi.params.fracs,
    JSON.stringify(mi.killRate));
  check('units left by round and wipe-out chance are shown', (await page.locator('#fc-units tbody tr').count()) === 2 && mi.result.B.pTabled > mi.result.A.pTabled && mi.result.B.unitsLeft[4] < mi.result.B.unitsLeft[0]);
  check('first / second turn split is shown for a roll-off', /going first/.test(await page.textContent('#fc-first')));
  await page.locator('#fc-basis summary').tap();
  const basis = await page.textContent('#fc-basis');
  check('"What this forecast is built from" names rules, your input, the calculator, real games and assumptions',
    ['Rules', 'Your input', 'Calculator', 'Real games', 'Assumption'].every(k => basis.includes(k)) && /94,739 real 11th edition/.test(basis) && /18,790 recorded 10th edition games/.test(basis), basis.slice(0, 200));
  await page.locator('#fc-basis').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_37_forecast_basis.png') });
  await page.locator('#fc-win').scrollIntoViewIfNeeded();
  // plan: give A the centre from round 2 -> A scores more primary than B by a wider gap
  const winBefore = mi.result.pWinA;
  const gapBefore = mi.result.A.primMean - mi.result.B.primMean;
  const centre = mi.objectives.find(o => o.cls === 'central').id;
  for (let r = 2; r <= 5; r++) {
    // cycle the cell until it shows A
    for (let k = 0; k < 3 && (await page.evaluate(([rr, o]) => window.__calc.mission().plan[rr][o], [r, centre])) !== 'A'; k++) {
      await page.tap(`button[data-action="mission-plan"][data-r="${r}"][data-o="${centre}"]`);
    }
  }
  await page.waitForFunction((c) => { const m = window.__calc.mission(); return m.result && !m.busy && [2, 3, 4, 5].every(r => m.params.plan[r][c] === 'A'); }, centre, { timeout: 60000 });
  await page.waitForTimeout(400);
  await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 60000 });
  {
    // (this matchup is one-sided already, so the effect is small here; the size of the effect in an
    // even game is checked in tests/calc-forecast.test.mjs "plan uncertainty")
    const fcAfter = await page.evaluate(() => window.__calc.mission().result);
    check('the plan change reaches the forecast: A\'s primary lead does not shrink, win chance holds', fcAfter.A.primMean - fcAfter.B.primMean > gapBefore - 0.3 && fcAfter.pWinA >= winBefore - 0.02,
      `primary gap ${gapBefore.toFixed(1)} -> ${(fcAfter.A.primMean - fcAfter.B.primMean).toFixed(1)}, win ${winBefore.toFixed(2)} -> ${fcAfter.pWinA.toFixed(2)}`);
  }
  // the forecast headline stays pinned in every Mission view
  check('Mission has Plan / Cards / Play views with the forecast headline pinned', (await page.locator('#mission-top .seg button[data-action="mission-tab"]').count()) === 3 && /you win/.test(await page.textContent('#fc-mini')));
  // secondary card sheet (Cards view)
  await page.tap('button[data-action="mission-tab"][data-value="cards"]');
  await page.waitForSelector('#mission-cards tr.card-row');
  check('Cards view keeps the headline and starts at the top', /you win/.test(await page.textContent('#fc-mini')) && (await page.evaluate(() => window.scrollY)) < 5);
  check('card sheet lists all 18 secondaries', (await page.locator('#mission-cards tr.card-row').count()) === 18);
  await page.tap('#mission-cards button[data-action="mission-card"][data-id="behind-enemy-lines"]');
  check('tapping a card shows its rules text', /deployment zone/.test(await page.textContent('#mission-cards tr.card-detail')));
  check('keep-ready list and hit list are filled', (await page.locator('#mission-keep li').count()) >= 3 && (await page.locator('[id^="mission-hit-"] li').count()) >= 1);
  await page.screenshot({ path: join(SHOTS, 'calc_28_mission_cards.png') });
  {
    // Fixed or Tactical? (chosen in secret before deployment): Tactical and every pair of Fixed cards that has
    // targets in this enemy army, best first, with what each does to the secondary score and the win chance
    await page.waitForSelector('#fc-modes tbody tr', { timeout: 120000 });
    const readModes = () => page.evaluate(() => [...document.querySelectorAll('#fc-modes tbody tr, #fc-modes-all tbody tr')].map(r => ({ key: r.dataset.mode, sec: parseFloat(r.children[1].textContent), chosen: /Chosen/.test(r.textContent) })));
    const modes = await readModes();
    check('Fixed or Tactical: Tactical and each pair of live Fixed cards, best first, my choice marked', modes.some(x => x.key === 'mode:tactical' && x.chosen) && modes.length >= 2
      && modes.every((x, i) => i === 0 || x.sec <= modes[i - 1].sec) && modes.every(x => x.sec >= 0 && x.sec <= 45) && /Tactical|Fixed/.test(await page.textContent('#mode-verdict')), JSON.stringify(modes));
    check('Fixed or Tactical: only the best two are on the page, the other pairs are behind a fold', (await page.locator('#fc-modes tbody tr').count()) === Math.min(2, modes.length)
      && (modes.length <= 2 || !(await page.locator('#fc-modes-all').isVisible())));
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({ path: join(SHOTS, 'calc_48_fixed_or_tactical.png') });
    // "Use" on a Fixed pair takes those two cards (the table stays: it does not depend on what is chosen now)
    const pair = modes.find(x => x.key !== 'mode:tactical');
    const useBtn = page.locator(`tr[data-mode="${pair.key}"] button[data-action="mission-mode-use"]`);
    if (!(await useBtn.isVisible())) await page.locator('details[data-details="mission-modes"] summary').tap();
    await useBtn.tap();
    await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 120000 });
    const took = await page.evaluate(() => ({ modes: window.__calc.state.mission.modes.A, sec: window.__calc.mission().result.A.secMean }));
    check('Fixed or Tactical: "Use" takes that pair as my Fixed cards and the forecast follows the table', took.modes.mode === 'fixed' && `mode:${took.modes.fixed.join('+')}` === pair.key
      && Math.abs(took.sec - pair.sec) < 2.5 && (await readModes()).find(x => x.key === pair.key)?.chosen === true, JSON.stringify({ took, pair }));
    const tacBtn = page.locator('tr[data-mode="mode:tactical"] button[data-action="mission-mode-use"]');
    if (!(await tacBtn.isVisible())) await page.locator('details[data-details="mission-modes"] summary').tap();
    await tacBtn.tap();
    await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 120000 });
    check('Fixed or Tactical: back to Tactical', await page.evaluate(() => window.__calc.state.mission.modes.A.mode === 'tactical'));
    if (await page.evaluate(() => document.querySelector('details[data-details="mission-modes"]')?.open)) await page.locator('details[data-details="mission-modes"] summary').tap();
    await page.evaluate(() => window.scrollTo(0, 0));
  }
  {
    // position cards: the default is the real-game rate of the equivalent card, or "no data" — never a silent guess
    const cg = await page.textContent('#mission-cards tr.card-row[data-card="centre-ground"]');
    const bc = await page.textContent('#mission-cards tr.card-row[data-card="beacon"]');
    check('position cards show where their default comes from (real-game rate / no data)', /Real-game rate/.test(cg) && /No data/.test(bc), `${cg} | ${bc}`);
    await page.tap('#mission-cards button[data-action="mission-card"][data-id="centre-ground"]');
    const det = await page.textContent('#mission-cards tr.card-detail');
    check('card details quote the real-game numbers and their source', /Area Denial card was scored 62% \/ 64% \/ 60% \/ 60% \/ 65%/.test(det) && /18,790 recorded 10th edition games/.test(det), det.slice(0, 300));
    await page.waitForFunction(() => !window.__calc.mission().busy, null, { timeout: 60000 });
    await page.locator('#mission-cards tr.card-detail').scrollIntoViewIfNeeded();
    await page.screenshot({ path: join(SHOTS, 'calc_38_card_real_rate.png') });
  }
  // your own estimate of a card's VP if drawn (max shown), and the Assumptions buttons work
  // the VP-if-drawn number itself is the control: pick 3 for Assassination, then back to the app's
  const estPick = '#mission-cards tr.card-row[data-card="assassination"] select[data-input="mission-est-pick"]';
  check('the VP-if-drawn number is a picker from 0 to the max (5)', (await page.locator(`${estPick} option`).count()) === 12 && await page.isVisible(estPick));
  await page.selectOption(estPick, '3');
  await page.waitForFunction(() => { const m = window.__calc.mission(); return !m.busy && m.result && Math.abs((m.result[m.me].cards.assassination?.perDraw ?? 0) - 3) < 0.35; }, null, { timeout: 60000 });
  check('picking 3 in the VP-if-drawn cell sets your estimate and the forecast uses it', (await page.inputValue(estPick)) === '3'
    && /Your estimate/.test(await page.textContent('#mission-cards tr.card-row[data-card="assassination"]')));
  await page.locator(estPick).scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_34_card_estimate_pick.png') });
  // (the app re-draws itself when the screen crosses the two-pane width)
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.waitForTimeout(400);
  await page.locator(estPick).scrollIntoViewIfNeeded();
  check('wide screen: the Cards view is two panes (sheet left; Fixed or Tactical, keep-ready and hit list right)', await page.evaluate(() => {
    const a = document.querySelector('.mlay.cards .a-sheet').getBoundingClientRect(), b = document.querySelector('.mlay.cards .a-mode').getBoundingClientRect(), c = document.querySelector('.mlay.cards .a-side').getBoundingClientRect();
    return b.left > a.right - 2 && Math.abs(a.top - b.top) < 40 && a.width > 400 && b.width > 400 && c.top >= b.bottom - 2 && Math.abs(c.left - b.left) < 2;
  }));
  check('phone order is kept in the markup: Fixed or Tactical first, then the sheet', await page.evaluate(() => getComputedStyle(document.querySelector('.a-mode')).order === '1' && getComputedStyle(document.querySelector('.a-sheet')).order === '2'));
  await page.screenshot({ path: join(SHOTS, 'calc_35_card_estimate_pick_laptop.png') });
  await page.setViewportSize({ width: 412, height: 839 });
  await page.waitForTimeout(400);
  await page.selectOption(estPick, '');
  check('picking "app" goes back to the app\'s estimate', await page.evaluate(() => window.__calc.state.mission.est[window.__calc.state.mission.me].assassination === undefined));
  await page.tap('#mission-cards button[data-action="mission-card"][data-id="assassination"]');
  check('card sheet shows each card\'s max (5)', (await page.textContent('#mission-cards tr.card-row[data-card="assassination"]')).includes('5'));
  for (let i = 0; i < 12; i++) await page.tap('#mission-cards button[data-action="mission-est"][data-id="assassination"][data-delta="-0.5"]');
  for (let i = 0; i < 6; i++) await page.tap('#mission-cards button[data-action="mission-est"][data-id="assassination"][data-delta="0.5"]');
  await page.waitForFunction(() => { const m = window.__calc.mission(); return !m.busy && m.result && Math.abs((m.result[m.me].cards.assassination?.perDraw ?? 0) - 3) < 0.35; }, null, { timeout: 60000 });
  check('setting Assassination to 3 / 5 makes the forecast use 3 VP if drawn', /3\.0/.test(await page.textContent(`#est-${(await page.evaluate(() => window.__calc.mission().me))}-assassination`))
    && /Your estimate/.test(await page.textContent('#mission-cards tr.card-row[data-card="assassination"]')));
  await page.screenshot({ path: join(SHOTS, 'calc_33_card_estimate.png') });
  await page.tap('#mission-cards button[data-action="mission-est-auto"][data-id="assassination"]');
  check('"Use the app\'s" clears your estimate', await page.evaluate(() => window.__calc.state.mission.est[window.__calc.state.mission.me].assassination === undefined));
  await page.tap('button[data-action="mission-tab"][data-value="plan"]');
  await page.locator('details.more summary', { hasText: 'Assumptions' }).tap();
  await page.tap('button[data-action="mission-mode"][data-value="fixed"]');
  await page.tap('button[data-action="mission-kills"][data-value="2"]');
  const asm = await page.evaluate(() => ({ mode: window.__calc.state.mission.modes.A.mode, kills: window.__calc.state.mission.killRate.A }));
  check('Assumptions buttons change the setting (Fixed, trading)', asm.mode === 'fixed' && asm.kills === 2, JSON.stringify(asm));
  await page.tap('button[data-action="mission-mode"][data-value="tactical"]');
  {
    // a manual rate replaces the calculator's; "Auto" brings it back
    const manual = await page.evaluate(() => window.__calc.mission().params.players.A.killRate);
    await page.tap('.modrow[data-side="A"] button[data-action="mission-kills"][data-value="auto"], button[data-action="mission-kills"][data-value="auto"]');
    const auto = await page.evaluate(() => ({ kr: window.__calc.mission().params.players.A.killRate, auto: window.__calc.state.mission.killAuto.A, label: document.querySelector('button[data-action="mission-kills"][data-value="auto"]').textContent }));
    check('units destroyed per turn: your own rate (2) replaces the calculator; Auto restores it and shows its number', manual === 2 && auto.kr === null && auto.auto === true && /Auto \d\.\d/.test(auto.label), JSON.stringify({ manual, auto }));
    // who is the stronger player
    await page.tap('button[data-action="mission-edge"][data-value="-0.43"]');
    const edged = await page.evaluate(() => window.__calc.mission().params.edge);
    await page.tap('button[data-action="mission-edge"][data-value="0"]');
    check('"Who is the stronger player?" sets the forecast edge (Opp ++ = -0.43 for me = A)', edged === -0.43 && (await page.evaluate(() => window.__calc.mission().params.edge)) === 0, String(edged));
  }

  // Play view (in-game tracker): A drew Assassination and Secure No Man's Land in round 2, scored one for 5; primary 9
  await page.tap('button[data-action="mission-tab"][data-value="play"]');
  await page.waitForSelector('#play-bar');
  await page.tap('button[data-action="mission-round"][data-value="2"]');
  await page.selectOption('select[data-input="mission-draw"][data-side="A"]', 'assassination');
  await page.selectOption('select[data-input="mission-draw"][data-side="A"]', 'secure-no-mans-land');
  await page.selectOption('select[data-input="mission-draw"][data-side="A"]', 'no-prisoners');
  check('drawn cards show in hand with what each can pay (No Prisoners: +2 / +4 / +5)', (await page.locator('#hand-A .hand-row').count()) === 3
    && (await page.locator('#hand-A .hand-row[data-card="no-prisoners"] button[data-do="scored"]').allTextContents()).join() === '+2,+4,+5');
  await page.tap('#hand-A .hand-row[data-card="assassination"] button[data-do="scored"][data-vp="5"]');
  await page.tap('#hand-A .hand-row[data-card="no-prisoners"] button[data-do="discard"]');
  check('scoring a card adds its VP to the secondary score; a discard adds nothing', (await page.inputValue('input[data-input="mission-score"][data-side="A"][data-k="secondary"]')) === '5');
  // steppers: +5 +1 +1 +1 +1 = 9 primary; typing still works without a re-draw between boxes
  await page.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="5"]');
  for (let i = 0; i < 5; i++) await page.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="1"]');
  await page.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="-1"]');
  check('score steppers (+5, +1, -1) and the running total', (await page.inputValue('input[data-input="mission-score"][data-side="A"][data-k="primary"]')) === '9' && (await page.textContent('#play-total-A')).trim() === '24');
  await page.fill('input[data-input="mission-score"][data-side="B"][data-k="primary"]', '4');
  await page.fill('input[data-input="mission-score"][data-side="B"][data-k="secondary"]', '3');
  await page.locator('#play-turn').tap();
  await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.game.A.primary === 9 && m.game.A.secondary === 5 && m.game.B.primary === 4 && m.game.B.secondary === 3 && m.result.A.prim[0] === 0; }, null, { timeout: 60000 });
  check('both score boxes keep what was typed (no re-render between them)', (await page.inputValue('input[data-input="mission-score"][data-side="B"][data-k="primary"]')) === '4' && (await page.inputValue('input[data-input="mission-score"][data-side="B"][data-k="secondary"]')) === '3');
  mi = await page.evaluate(() => window.__calc.mission());
  check('tracker: scored and discarded cards are out of the deck, the forecast restarts from round 2 with the score carried', mi.game.A.used.includes('assassination') && mi.game.A.used.includes('no-prisoners') && mi.game.A.hand.join() === 'secure-no-mans-land'
    && mi.result.A.cards['assassination'] === undefined && mi.result.A.mean >= 9 + 5 && /15 cards left/.test(await page.textContent('#odds-A')) && /from round 2/.test(await page.textContent('#fc-mini')), JSON.stringify({ g: mi.game.A, odds: await page.textContent('#odds-A') }));
  {
    // cards in hand: how often each still scores from here, what it is worth, and when to let it go
    const adv = await page.textContent('#hand-A [data-advice="secure-no-mans-land"]');
    check('a card in hand says how often it still scores and its VP from here', /\d+% to score by the end · \d\.\d VP/.test(adv), adv);
    check('the tracker counts the cards drawn this turn (the forecast draws the rest)', /Drawn this turn: 2 of 2/.test(await page.textContent('#drawn-A')), await page.textContent('#drawn-A').catch(() => 'none'));
    // B holds Assassination and Bring It Down; then every unit of A is destroyed
    await page.selectOption('select[data-input="mission-draw"][data-side="B"]', 'assassination');
    await page.selectOption('select[data-input="mission-draw"][data-side="B"]', 'bring-it-down');
    const winAll = await page.evaluate(() => window.__calc.mission().result.pWinA);
    await page.locator('details[data-details="mission-dead-A"] summary').tap();
    const nA = await page.locator('details[data-details="mission-dead-A"] button[data-action="mission-dead"]').count();
    for (let i = 0; i < nA; i++) await page.locator('details[data-details="mission-dead-A"] button[data-action="mission-dead"]').nth(i).tap();
    await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 60000 });
    {
      // units marked destroyed leave that army in the forecast: A has nothing left to hold objectives or to kill with
      const d = await page.evaluate(() => { const m = window.__calc.mission(); return { win: m.result.pWinA, own: m.params.players.A.start.destroyed.length, theirs: m.params.players.B.start.destroyed.length, left: m.result.A.unitsLeft, aPrim: m.result.A.prim, bPrim: m.result.B.prim }; });
      check('units marked destroyed reach the forecast: with all of A destroyed, A scores no more primary and its win chance falls', d.own === nA && d.theirs === 0 && d.win < winAll - 0.3
        && d.aPrim.slice(2).every(v => v < 0.5) && d.left.filter(v => v != null).every(v => v === 0), JSON.stringify({ winAll, ...d }));
      console.log('  all of A destroyed in round 2:', JSON.stringify({ winBefore: +winAll.toFixed(2), winAfter: +d.win.toFixed(2), aPrim: d.aPrim.map(v => +v.toFixed(1)), bPrim: d.bPrim.map(v => +v.toFixed(1)) }));
    }
    const advA = await page.textContent('#hand-B [data-advice="assassination"]'), advB = await page.textContent('#hand-B [data-advice="bring-it-down"]');
    check('Assassination in hand with every enemy CHARACTER destroyed: it scores 5 VP (not "discard")', /Every enemy CHARACTER is destroyed: it scores 5 VP/.test(advA), advA);
    check('Bring It Down in hand with no W10+ model left: discard it (draw a new card when drawn, 1CP later)', /No targets left: when you draw it you can discard it and draw a new card\. Later, discard it at the end of your turn for 1CP/.test(advB), advB);
    await page.locator('#hand-B').scrollIntoViewIfNeeded();
    await page.screenshot({ path: join(SHOTS, 'calc_49_cards_in_hand.png') });
    // put it back: A's units alive, B's two cards out of the hand and back in the deck
    for (let i = 0; i < nA; i++) await page.locator('details[data-details="mission-dead-A"] button[data-action="mission-dead"]').nth(i).tap();
    await page.locator('details[data-details="mission-dead-A"] summary').tap();
    await page.evaluate(() => { const g = window.__calc.state.mission.game; g.B.hand = []; g.B.used = []; });
    await page.tap('button[data-action="mission-round"][data-value="2"]');
    await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 60000 });
    check('tracker restored for the next checks', await page.evaluate(() => { const g = window.__calc.state.mission.game; return g.A.destroyed.length === 0 && g.B.hand.length === 0 && g.A.hand.join() === 'secure-no-mans-land'; }));
  }
  {
    // "Turn done": first to the other player, then (after the second turn) to the next battle round
    await page.tap('.a-bar button[data-action="mission-first"][data-value="A"]');
    await page.tap('button[data-action="mission-next"][data-value="A"]');
    await page.tap('#play-turn-done');
    const t1 = await page.evaluate(() => ({ r: window.__calc.state.mission.game.round, n: window.__calc.state.mission.game.next }));
    await page.tap('#play-turn-done');
    const t2 = await page.evaluate(() => ({ r: window.__calc.state.mission.game.round, n: window.__calc.state.mission.game.next }));
    check('"Turn done" moves A -> B in the round, then to round 3 with A to play', t1.r === 2 && t1.n === 'B' && t2.r === 3 && t2.n === 'A', JSON.stringify({ t1, t2 }));
    await page.tap('button[data-action="mission-round"][data-value="2"]');
    await page.tap('button[data-action="mission-tab"][data-value="plan"]');
    await page.tap('button[data-action="mission-first"][data-value="roll"]');
    await page.tap('button[data-action="mission-tab"][data-value="play"]');
  }
  await page.locator('[data-player="A"]').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_29_mission_tracker.png') });

  // --- board plans drive the forecast: copy a plan, put the Grey Hunters in B's deployment zone
  await page.tap('button[data-action="view"][data-value="board"]');
  await page.waitForSelector('#board-svg');
  await page.tap('button[data-action="board-plan-copy"]');
  check('Copy plan adds an "Aggressive" plan', (await page.locator('#board-variants .chip', { hasText: 'Aggressive' }).count()) === 1);
  // find a spot where the whole unit (every base) fits inside B's zone, and put it there in every step
  const into = await page.evaluate(async (gh) => {
    const { boardContext, boardPlans } = await import('/calc/boardview.mjs');
    const { baseWhollyWithin } = await import('/calc/planeval.mjs');
    const bc = boardContext();
    const z = bc.deployment.zones.find(q => q.player === bc.zoneB).poly;
    const p = window.__calc.board().plan;
    for (const st of p.steps) if (st.tokens[gh]) Object.assign(st.tokens[gh], { rot: 0, per: 5 });
    const u = boardPlans()[1].steps.flatMap(st => st.A).find(x => x.key === gh);
    const r = (fp) => fp.r ?? Math.max(fp.rx ?? 0, fp.hw ?? 0);
    for (let y = 1; y < 60; y += 0.5) for (let x = 1; x < 44; x += 0.5) {
      if (u.models.every(m => baseWhollyWithin(x + m.dx, y + m.dy, r(m.fp), z))) {
        for (const st of p.steps) if (st.tokens[gh]) Object.assign(st.tokens[gh], { x, y });
        return { x, y };
      }
    }
    return null;
  }, bGh.tk);
  // the board shows who controls each objective in this step (OC of units in range)
  const centreObj = await page.evaluate(async (gh) => {
    const { boardContext } = await import('/calc/boardview.mjs');
    const o = boardContext().layout.objectives.find(x => x.role === 'central');
    const p = window.__calc.board().plan;
    const keep = { ...p.steps[p.cur].tokens[gh] };
    Object.assign(p.steps[p.cur].tokens[gh], { x: o.x, y: o.y });
    return { id: o.id, keep };
  }, bGh.tk);
  await page.tap(`button[data-action="board-step"][data-i="${await page.evaluate(() => window.__calc.board().plan.cur)}"]`);
  const ctl = await page.evaluate((id) => { const g = document.querySelector(`#obj-control [data-obj="${id}"]`); return g && { control: g.dataset.control, oca: +g.dataset.oca, ocb: +g.dataset.ocb }; }, centreObj.id);
  check('board: the centre objective shows A in control with the Grey Hunters\' OC', ctl?.control === 'A' && ctl.oca >= 10, JSON.stringify(ctl));
  await page.locator('#board-host').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_34_board_objective_control.png') });
  await page.evaluate(([gh, keep]) => { const p = window.__calc.board().plan; Object.assign(p.steps[p.cur].tokens[gh], keep); }, [bGh.tk, centreObj.keep]);
  await page.tap('button[data-action="view"][data-value="mission"]');
  await page.tap('button[data-action="mission-tab"][data-value="plan"]');
  await page.waitForSelector('button[data-action="mission-source"][data-value="1"]');
  await page.tap('button[data-action="mission-source"][data-value="1"]');
  await page.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.pairsReady && m.board && (m.compare?.length ?? 0) >= 3; }, null, { timeout: 120000 });
  mi = await page.evaluate(() => window.__calc.mission());
  const ghFacts = mi.board.rounds[1].A?.find(u => /Grey Hunters/.test(u.name))?.f;
  check('board plan: the Grey Hunters are measured wholly inside B\'s deployment zone', ghFacts?.inEnemyDZ === true, JSON.stringify({ ghFacts, into }));
  await page.tap('button[data-action="mission-tab"][data-value="cards"]');
  check('position cards say "Board plan" instead of a rating', /Board plan/.test(await page.textContent('#mission-cards tr.card-row[data-card="behind-enemy-lines"]')));
  await page.tap('button[data-action="mission-tab"][data-value="plan"]');
  check('plans compared side by side (grid, Main, Aggressive)', (await page.locator('#fc-compare tbody tr').count()) === 3);
  check('a board plan with units missing says so in the comparison', /of 8 units placed/.test(await page.textContent('#fc-compare')), await page.textContent('#fc-compare'));
  const bel = mi.result[mi.me].cards['behind-enemy-lines'];
  const ghName = mi.board.rounds[1].A.find(u => /Grey Hunters/.test(u.name)).name;
  // what the Orks can do to the Grey Hunters from where they stand, per round (wounds they remove of the unit's total)
  const ghThreat = [1, 2, 3, 4, 5].map(r => (mi.board.threats[r]?.B?.cur ?? []).map(a => a.opts.find(o => o.t === ghName)).filter(Boolean).reduce((t, o) => t + o.mu, 0));
  console.log('  Grey Hunters in their zone: wounds the Orks can remove each round', JSON.stringify(ghThreat.map(v => +v.toFixed(1))), 'BEL', JSON.stringify(bel));
  check('board plan: the forecast knows what each unit threatens from its planned position (step 0 = deployment)', !!mi.board.rounds[0] && !!mi.board.threats[1]?.A && !!mi.board.threats[1]?.B && ghThreat.some(v => v > 0), JSON.stringify(ghThreat));
  check('Behind Enemy Lines scores from the plan (while the unit survives there)', bel && bel.perDraw > 0, JSON.stringify(bel));
  await page.locator('#mission-board-note').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_31_mission_board_plan.png') });
  await page.locator('#fc-compare').scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(SHOTS, 'calc_32_mission_plans_compared.png') });
  await page.tap('button[data-action="mission-source"][data-value="grid"]');
  await page.tap('button[data-action="mission-tab"][data-value="play"]');
  await page.tap('button[data-action="mission-reset"]');
  await page.tap('button[data-action="mission-tab"][data-value="plan"]');
  await page.tap('button[data-action="view"][data-value="board"]');
  await page.waitForSelector('#board-svg');

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

  // --- backup and other devices: save a file, send everything to a tablet with a code, undo, restore from the file
  {
    await page.tap('button[data-action="view"][data-value="armies"]');
    await page.locator('#backup-card > summary').tap();
    const [dl] = await Promise.all([page.waitForEvent('download'), page.tap('button[data-action="backup-save"]')]);
    const backupPath = join(dbDir, dl.suggestedFilename());
    await dl.saveAs(backupPath);
    const saved = JSON.parse(readFileSync(backupPath, 'utf8'));
    const BK = await import(new URL('../public/calc/backup.mjs', import.meta.url).href);
    const info = BK.describeBackup(saved);
    check('backup file holds the lists, the library and the board plans', /^combat-calc-backup-\d{4}-\d{2}-\d{2}\.json$/.test(dl.suggestedFilename()) && info.ok && info.counts.lists === 2 && info.counts.library === 2 && info.counts.plans >= 1, JSON.stringify(info));
    check('the card says the backup was saved and what it holds', /Backup saved as combat-calc-backup/.test(await page.textContent('#backup-msg')) && /Last backup:/.test(await page.textContent('#backup-card')));
    await page.tap('button[data-action="backup-send"]');
    await page.waitForSelector('#backup-code-out b');
    const code = (await page.textContent('#backup-code-out b')).trim();
    check('"Send to another device" gives a 6-character code', BK.CODE_RE.test(code), code);
    await page.locator('#backup-code-out').scrollIntoViewIfNeeded();
    await page.screenshot({ path: join(SHOTS, 'calc_43_backup_send.png') });
    // the tablet: nothing on it; type the code, confirm, and the lists and plans are there
    const tctx = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
    const t2 = await tctx.newPage();
    const asked = [];
    t2.on('dialog', (d) => { asked.push(d.message()); d.accept(); });
    await t2.goto(`${BASE}/calc/`);
    await t2.waitForSelector('#backup-card');
    await t2.locator('#backup-card > summary').tap();
    await t2.fill('#backup-code', code.toLowerCase());
    await Promise.all([t2.waitForNavigation(), t2.tap('button[data-action="backup-receive"]')]);
    await t2.waitForFunction(() => window.__calc?.state.armies.A && window.__calc.state.armies.B);
    const got = await t2.evaluate(() => ({ a: window.__calc.state.armies.A.faction, b: window.__calc.state.armies.B.faction, lib: window.__calc.state.library.length, plans: Object.keys(window.__calc.state.board?.plans ?? JSON.parse(localStorage.getItem('w40k_calc_board_v1') ?? '{}').plans ?? {}).length }));
    check('tablet: the code brings over both lists, the library and the board plans (after a confirm that says what it holds)',
      !!got.a && !!got.b && got.lib === 2 && got.plans >= 1 && /Replace everything on this device/.test(asked[0] ?? '') && /2 loaded lists/.test(asked[0] ?? ''), JSON.stringify({ got, asked }));
    await t2.tap('button[data-action="view"][data-value="armies"]');
    await t2.locator('#backup-card > summary').tap();
    await t2.screenshot({ path: join(SHOTS, 'calc_44_backup_tablet.png') });
    // undo: back to the empty tablet
    await Promise.all([t2.waitForNavigation(), t2.tap('button[data-action="backup-undo"]')]);
    await t2.waitForSelector('textarea[data-side="A"]');
    check('tablet: "Undo the last restore" puts back what was there (nothing)', await t2.evaluate(() => !window.__calc.state.armies.A && !window.__calc.state.armies.B && !localStorage.getItem('w40k_calc_before_restore_v1')));
    // restore from the file
    await t2.locator('#backup-card > summary').tap();
    await Promise.all([t2.waitForNavigation(), t2.setInputFiles('input[data-input="backup-file"]', backupPath)]);
    await t2.waitForFunction(() => window.__calc?.state.armies.A && window.__calc.state.armies.B);
    check('tablet: restore from the backup file works too', await t2.evaluate(() => window.__calc.state.library.length === 2));
    // a wrong code: a clear message, nothing changed
    await t2.tap('button[data-action="view"][data-value="armies"]');
    await t2.locator('#backup-card > summary').tap();
    await t2.fill('#backup-code', 'ZZZZZZ');
    await t2.tap('button[data-action="backup-receive"]');
    await t2.waitForFunction(() => /No backup with this code/.test(document.getElementById('backup-msg')?.textContent ?? ''));
    check('a wrong code says so and changes nothing', await t2.evaluate(() => window.__calc.state.library.length === 2));
    await tctx.close();
  }

  // --- event: opponents' lists, layout letter per round, one tap to start a round, the matchup brief, my deployment reused
  {
    await page.tap('button[data-action="view"][data-value="armies"]');
    // the list as it comes (1.113 remembers attachments per list: the Captain on Bike set on the Grey Hunters above
    // would come back, and the board plans made with it would count as this list's planned layouts)
    await page.evaluate(() => localStorage.removeItem('w40k_calc_attach_v1'));
    await page.fill('textarea[data-side="A"]', SW_LIST);
    await page.tap('button[data-action="parse"][data-side="A"]');
    await page.locator('#event-card > summary').tap();
    const before = await page.evaluate(() => window.__calc.state.library.length);
    await page.fill('#event-paste', `${ORK_LIST}\n\n${readFileSync(join(here, 'fixtures', 'gw-custodes-nbhyphen.txt'), 'utf8')}`);
    await page.tap('button[data-action="event-add"]');
    let evd = await page.evaluate(() => window.__calc.event());
    const cust = evd.roster.find(r => /Custodes/.test(r.name)), orks = evd.roster.find(r => /Calc Test Waaagh/.test(r.name));
    check('pasting two lists at once adds both opponents, with faction and Force Disposition read from the list', evd.roster.length === before + 2 && cust?.faction === 'Adeptus Custodes' && orks?.faction === 'Orks' && cust.disp === 'take-and-hold' && /2 lists added/.test(await page.textContent('#event-msg')), JSON.stringify(evd.roster.map(r => [r.name, r.faction, r.disp])));
    check('each opponent shows the primaries and the three deployments of that pairing', /You: Battlefield Dominance · they: Battlefield Dominance/.test(await page.textContent(`#event-roster [data-opp="${cust.id}"]`)) && /A Tipping Point · B Dawn of War · C Search and Destroy/.test(await page.textContent(`#event-roster [data-opp="${cust.id}"]`)));
    // round 2 is on layout B against the Custodes
    await page.tap('#event-rounds [data-round="2"] button[data-action="event-layout"][data-value="2"]');
    await page.selectOption('#event-rounds [data-round="2"] select[data-input="event-opp"]', String(cust.id));
    check('the round row says what the round will be', /You: Battlefield Dominance · they: Battlefield Dominance · Dawn of War/.test(await page.textContent('#event-rounds [data-round="2"]')));
    await page.locator('#event-rounds').scrollIntoViewIfNeeded();
    await page.screenshot({ path: join(SHOTS, 'calc_45_event.png') });
    await page.tap('#event-rounds [data-round="2"] button[data-action="event-start"]');
    await page.waitForSelector('#brief');
    const started = await page.evaluate(() => ({ view: window.__calc.state.view, b: window.__calc.state.armies.B.faction, layout: window.__calc.board().layout, round: window.__calc.event().round }));
    check('"Start" loads the opponent as army B, sets the round\'s layout and opens the matchup brief', started.view === 'intel' && started.b === 'Adeptus Custodes' && /^take_and_hold_mirror_2$/.test(started.layout) && started.round === 2
      && /Round 2 · Layout B/.test(await page.textContent('#brief-round')) && /Dawn of War · Layout B/.test(await page.textContent('#brief-deploy')), JSON.stringify(started));
    await page.waitForSelector('#brief-threats tbody tr', { timeout: 120000 });
    await page.waitForFunction(() => /you win/.test(document.getElementById('brief-forecast')?.textContent ?? ''), null, { timeout: 120000 });
    const brief = await page.evaluate(() => ({ threats: [...document.querySelectorAll('#brief-threats tbody tr')].map(r => r.textContent.replace(/\s+/g, ' ').trim()), answers: document.querySelectorAll('#brief-answers tbody tr').length, text: document.getElementById('brief-host').textContent }));
    check('brief: their biggest threats (with reach), my best answers, dead cards, the forecast headline',
      brief.threats.length >= 2 && /Caladius|Contemptor|Shield-Captain/.test(brief.threats[0]) && /M\d+"/.test(brief.threats[0]) && brief.answers >= 3 && /Dead for (you|them)|No dead cards/.test(brief.text) && /you win/.test(brief.text), JSON.stringify(brief.threats));
    await page.locator('#brief').scrollIntoViewIfNeeded();
    await page.screenshot({ path: join(SHOTS, 'calc_46_matchup_brief.png'), fullPage: true });
    // plan my deployment for this layout, then meet another opponent on the same layout: it is offered again
    await page.tap('button[data-action="view"][data-value="board"]');
    await page.waitForSelector('#board-svg');
    await page.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    const ghPos = (await tokens()).find(t => t.tk.startsWith('A:'));
    await page.tap('button[data-action="view"][data-value="armies"]');
    await page.tap('#event-rounds [data-round="3"] button[data-action="event-layout"][data-value="2"]');
    await page.selectOption('#event-rounds [data-round="3"] select[data-input="event-opp"]', String(orks.id));
    check('preparation table marks layout B against Take and Hold as planned', (await page.locator('#event-coverage button.cov.done').count()) === 1 && /deployment planned/.test(await page.getAttribute('#event-coverage button.cov.done', 'aria-label')));
    await page.tap('#event-rounds [data-round="3"] button[data-action="event-start"]');
    await page.waitForSelector('#brief');
    await page.tap('button[data-action="view"][data-value="board"]');
    await page.waitForSelector('#board-reuse');
    check('new opponent, same layout: the board offers my deployment from the other game', /against Adeptus Custodes/.test(await page.textContent('#board-reuse')) && (await tokens()).length === 0, await page.textContent('#board-reuse'));
    await page.screenshot({ path: join(SHOTS, 'calc_47_reuse_deployment.png') });
    await page.tap('button[data-action="board-reuse"]');
    const reused = (await tokens()).find(t => t.tk === ghPos.tk);
    check('"Use my deployment" puts my units where I planned them', !!reused && Math.abs(reused.x - ghPos.x) < 0.01 && Math.abs(reused.y - ghPos.y) < 0.01 && (await page.locator('#board-reuse').count()) === 0, JSON.stringify({ ghPos, reused }));
  }

  // --- table tools on the Play view: command points, the score of each turn, undo, the clock, table mode, screen on
  {
    const tctx = await browser.newContext({ ...devices['Pixel 7'] });
    // the Screen Wake Lock API is refused in a headless browser: a stand-in that counts the calls
    await tctx.addInitScript(() => {
      window.__wake = { requests: 0, releases: 0 };
      Object.defineProperty(navigator, 'wakeLock', { configurable: true, value: { request: async (type) => { window.__wake.requests++; return { type, release: async () => { window.__wake.releases++; }, addEventListener() {} }; } } });
    });
    const tp2 = await tctx.newPage();
    const terrs = [];
    tp2.on('console', m => { if (m.type() === 'error') terrs.push(m.text()); });
    tp2.on('pageerror', e => terrs.push(String(e)));
    await tp2.goto(`${BASE}/calc/`);
    await tp2.fill('textarea[data-side="A"]', SW_LIST);
    await tp2.tap('button[data-action="parse"][data-side="A"]');
    await tp2.fill('textarea[data-side="B"]', ORK_LIST);
    await tp2.tap('button[data-action="parse"][data-side="B"]');
    await tp2.tap('button[data-action="view"][data-value="mission"]');
    const idle = () => tp2.waitForFunction(() => { const m = window.__calc.mission(); return m.table || (m.result && !m.busy); }, null, { timeout: 120000 });
    await idle();
    await tp2.tap('button[data-action="mission-tab"][data-value="play"]');
    await tp2.waitForSelector('#play-bar');
    const gs = () => tp2.evaluate(() => { const s = window.__calc.state.mission, g = s.game; return { round: g.round, next: g.next, first: s.first, cp: [g.A.cp, g.B.cp], over: !!g.over, undo: s.undo.length, A: [g.A.primary, g.A.secondary], B: [g.B.primary, g.B.secondary], handA: g.A.hand.length }; });
    let st = await gs();
    check('a new game starts with 1CP each (the first Command phase) and nothing to undo', st.cp.join() === '1,1' && st.undo === 0 && await tp2.isDisabled('#play-undo') && (await tp2.textContent('#cp-A')).trim() === '1', JSON.stringify(st));
    check('the phone Play view stays short with the tools folded (under 2.7 screens)', await tp2.evaluate(() => document.documentElement.scrollHeight < 2.7 * innerHeight), String(await tp2.evaluate(() => document.documentElement.scrollHeight / innerHeight)));
    await tp2.screenshot({ path: join(SHOTS, 'calc_51_play_tools.png'), fullPage: true });

    // A's first turn: two cards, one scored, one discarded for a CP
    await tp2.selectOption('select[data-input="mission-draw"][data-side="A"]', 'assassination');
    await tp2.selectOption('select[data-input="mission-draw"][data-side="A"]', 'behind-enemy-lines');
    await tp2.tap('#hand-A .hand-row[data-card="behind-enemy-lines"] button[data-action="mission-hand-info"]');
    check('the name of a card in hand opens its rules text', /wholly within the enemy deployment zone/.test(await tp2.textContent('#hand-A [data-text="behind-enemy-lines"]')));
    await tp2.tap('#hand-A .hand-row[data-card="assassination"] button[data-do="scored"][data-vp="5"]');
    check('"scored this turn" follows the tracker', /Round 1, A's turn — scored this turn: A \+5 secondary · B nothing yet/.test((await tp2.textContent('#play-turn')).replace(/\s+/g, ' ')), await tp2.textContent('#play-turn'));
    await tp2.tap('#hand-A .hand-row[data-card="behind-enemy-lines"] button[data-do="discard"]');
    check('a discard in your own turn offers the CP for it', (await tp2.textContent('#cp-discard-A')).trim() === '+1CP for the discard');
    await tp2.tap('#cp-discard-A');
    st = await gs();
    check('the discard CP is added once', st.cp.join() === '2,1' && (await tp2.locator('#cp-discard-A').count()) === 0, JSON.stringify(st));
    // Turn done: the first player is known from it; B's Command phase gives 1CP each
    await tp2.tap('#play-turn-done');
    st = await gs();
    check('"Turn done" passes to B, works out who went first, and adds 1CP each for the Command phase', st.round === 1 && st.next === 'B' && st.first === 'A' && st.cp.join() === '3,2' && (await tp2.locator('#play-bar button[data-action="mission-first"]').count()) === 0, JSON.stringify(st));
    await tp2.tap('button[data-action="mission-score-step"][data-side="B"][data-k="primary"][data-delta="5"]');
    await tp2.tap('#play-turn-done');
    st = await gs();
    check('after the second turn: battle round 2, A to play', st.round === 2 && st.next === 'A' && st.cp.join() === '4,3', JSON.stringify(st));
    // Undo steps back through the changes, a turn included
    await tp2.tap('#play-undo');
    st = await gs();
    check('Undo takes back "Turn done" (round, turn and CP), keeping what was scored before it', st.round === 1 && st.next === 'B' && st.cp.join() === '3,2' && st.B[0] === 5, JSON.stringify(st));
    await tp2.tap('#play-undo');
    check('Undo again takes back the score', (await gs()).B[0] === 0);
    await tp2.tap('button[data-action="mission-score-step"][data-side="B"][data-k="primary"][data-delta="5"]');
    await tp2.tap('#play-turn-done');
    // a typed score is one undo step, and the turn line follows it without a re-draw
    await tp2.fill('input[data-input="mission-score"][data-side="A"][data-k="primary"]', '12');
    check('typing a score updates "scored this turn" in place', /A \+12 primary/.test(await tp2.textContent('#play-turn')) && (await tp2.inputValue('input[data-input="mission-score"][data-side="A"][data-k="primary"]')) === '12');
    // one extra CP per battle round: a second discard in round 2 gives none
    for (const id of ['cleanse', 'outflank']) await tp2.selectOption('select[data-input="mission-draw"][data-side="A"]', id);
    await tp2.tap('#hand-A .hand-row[data-card="cleanse"] button[data-do="discard"]');
    await tp2.tap('#cp-discard-A');
    await tp2.tap('#hand-A .hand-row[data-card="outflank"] button[data-do="discard"]');
    st = await gs();
    check('a second discard in the same battle round gives no CP (Event Companion: 1CP a round besides the Command phase)', st.cp.join() === '5,3' && /No CP for this discard: the one extra CP of round 2 is taken/.test(await tp2.textContent('#cp-discard-A')), JSON.stringify(st));
    // the once-per-battle card swap, and CP spent by hand
    await tp2.tap('#swap-A');
    await tp2.tap('button[data-action="mission-cp"][data-side="A"][data-delta="-1"]');
    st = await gs();
    check('card swap: 1CP, once per battle; − spends a CP', st.cp.join() === '3,3' && await tp2.isDisabled('#swap-A') && /Card swap used \(round 2\)/.test(await tp2.textContent('#swap-A')), JSON.stringify(st));
    // score sheet: per battle round, sums to the totals
    await tp2.locator('details[data-details="mission-sheet"] summary').tap();
    const rows = await tp2.$$eval('#play-sheet tbody tr', trs => trs.map(r => [...r.children].map(c => c.textContent.trim())));
    check('score sheet: round 1 = A 5 secondary, B 5 primary; round 2 = A 12 primary; totals', rows[0].join() === '1,–,5,5,–' && rows[1].join() === '2,12,–,–,–' && rows[5].join() === 'Total,12,5,5,–' && /A 27 – B 15/.test(await tp2.textContent('#play-sheet summary')), JSON.stringify(rows));
    check('the score sheet is drawn in its own card (not over the page)', await tp2.evaluate(() => { const t = document.querySelector('#play-sheet table').getBoundingClientRect(), c = document.querySelector('#play-sheet').getBoundingClientRect(); return t.top >= c.top && t.bottom <= c.bottom + 1 && getComputedStyle(document.querySelector('#play-sheet table')).position === 'static'; }));
    await tp2.locator('#play-sheet').scrollIntoViewIfNeeded();
    await tp2.screenshot({ path: join(SHOTS, 'calc_54_score_sheet.png') });
    await tp2.locator('details[data-details="mission-checklist"] summary').tap();
    check('turn checklist: the steps in rules order and both primary missions', /Draw 2 secondary cards \(2 of 2 entered\)/.test(await tp2.textContent('#play-checklist')) && /Both players gain 1CP/.test(await tp2.textContent('#play-checklist'))
      && /A · Battlefield Dominance:/.test(await tp2.textContent('details[data-details="mission-checklist"]')), await tp2.textContent('#play-checklist'));
    await tp2.locator('details[data-details="mission-checklist"] summary').tap();

    // round timer with the Grand Tournament milestones
    await tp2.tap('button[data-action="mission-clock-mode"][data-value="round"]');
    check('round timer: 3 hours, with the Grand Tournament milestones', (await tp2.textContent('#clock-round')).trim() === '3:00:00' && /2:35 deployed · 1:55 round 1 · 1:15 round 2 · 0:45 round 3 · 0:25 round 4/.test(await tp2.textContent('#clock-milestones')));
    await tp2.tap('#clock-go');
    await tp2.waitForFunction(() => document.querySelector('#clock-round').textContent.trim() !== '3:00:00', null, { timeout: 5000 });
    check('the clock runs and is on the pinned line; on pace in round 2', /^2:59:5\d$/.test((await tp2.textContent('#clock-round')).trim()) && /⏱ 2:59:5\d/.test(await tp2.textContent('#mini-clock')) && /On pace: finish battle round 2/.test(await tp2.textContent('#clock-pace')), await tp2.textContent('#clock-pace'));
    for (let i = 0; i < 22; i++) await tp2.tap('button[data-action="mission-clock"][data-do="minus"]');
    await tp2.waitForFunction(() => /behind/.test(document.querySelector('#clock-pace').textContent), null, { timeout: 5000 });
    check('with 1:10 left in battle round 2 the clock says how far behind the game is', /^1:09:\d\d$/.test((await tp2.textContent('#clock-round')).trim()) && /[56] min behind: battle round 2 should be done with 1:15 left/.test(await tp2.textContent('#clock-pace')), `${await tp2.textContent('#clock-round')} | ${await tp2.textContent('#clock-pace')}`);
    await tp2.locator('#play-clock').scrollIntoViewIfNeeded();
    await tp2.screenshot({ path: join(SHOTS, 'calc_52_clock_behind.png') });
    // it is kept as an end time: a reload does not stop or reset it
    await tp2.reload();
    await tp2.waitForSelector('#clock-round');
    check('the clock keeps running through a reload', /^1:0\d:\d\d$/.test((await tp2.textContent('#clock-round')).trim()) && (await tp2.evaluate(() => window.__calc.mission().clock.endsAt)) > Date.now(), await tp2.textContent('#clock-round'));
    st = await gs();
    check('the tracker (CP, round, undo steps) is kept through a reload', st.round === 2 && st.cp.join() === '3,3' && st.undo > 5, JSON.stringify(st));

    // chess clock: only the running player loses time; "Turn done" passes it
    await tp2.tap('button[data-action="mission-clock-mode"][data-value="chess"]');
    check('chess clock: 1:25 each (UKTC)', (await tp2.textContent('#clock-A')).trim() === '1:25:00' && (await tp2.textContent('#clock-B')).trim() === '1:25:00');
    await tp2.tap('button[data-action="mission-clock"][data-do="run"][data-side="A"]');
    await tp2.waitForFunction(() => document.querySelector('#clock-A').textContent.trim() !== '1:25:00', null, { timeout: 5000 });
    check('A\'s clock runs, B\'s waits', (await tp2.textContent('#clock-B')).trim() === '1:25:00' && /^1:24:5\d$/.test((await tp2.textContent('#clock-A')).trim()));
    await tp2.tap('#play-turn-done');
    await tp2.waitForFunction(() => document.querySelector('#clock-B').textContent.trim() !== '1:25:00', null, { timeout: 5000 });
    check('"Turn done" passes the clock to the next player', (await tp2.evaluate(() => window.__calc.mission().clock.running)) === 'B' && (await tp2.getAttribute('button[data-action="mission-clock"][data-do="run"][data-side="B"]', 'aria-pressed')) === 'true');
    await tp2.locator('#play-clock').scrollIntoViewIfNeeded();
    await tp2.screenshot({ path: join(SHOTS, 'calc_53_chess_clock.png') });
    await tp2.tap('button[data-action="mission-clock"][data-do="chess-pause"]');

    // the screen stays on in the Play view only
    const w1 = await tp2.evaluate(() => ({ ...window.__wake, on: window.__calc.mission().wake }));
    await tp2.tap('button[data-action="view"][data-value="armies"]');
    await tp2.waitForFunction(() => window.__wake.releases >= 1, null, { timeout: 5000 });
    await tp2.tap('button[data-action="view"][data-value="mission"]');
    await tp2.waitForFunction(() => window.__calc.mission().wake === true, null, { timeout: 5000 });
    await tp2.tap('button[data-action="mission-awake"]');
    await tp2.waitForFunction(() => window.__calc.mission().wake === false, null, { timeout: 5000 });
    check('screen wake lock: held on the Play view, released on another tab, off with the "Screen stays on" switch', w1.requests >= 1 && w1.on === true && (await tp2.evaluate(() => window.__wake.releases)) >= 2, JSON.stringify(w1));
    await tp2.tap('button[data-action="mission-awake"]');

    // table mode: the tracker only
    await tp2.selectOption('select[data-input="mission-draw"][data-side="B"]', 'secure-no-mans-land');
    await idle();
    check('before table mode: the card in hand has advice and the forecast is shown', (await tp2.locator('#hand-B [data-advice]').count()) === 1 && (await tp2.locator('#mission-forecast').count()) === 1);
    await tp2.tap('button[data-action="mission-table"]');
    const tm = await tp2.evaluate(() => ({ flag: !!document.querySelector('#table-flag'), score: document.querySelector('#score-mini')?.textContent.replace(/\s+/g, ' ').trim(), forecast: !!document.querySelector('#mission-forecast'), win: !!document.querySelector('#fc-mini-win'),
      advice: document.querySelectorAll('[data-advice]').length, attackOff: document.querySelector('button[data-action="view"][data-value="attack"]').dataset.locked === '1', boardOff: document.querySelector('button[data-action="view"][data-value="board"]').dataset.locked === '1', tabs: document.querySelectorAll('button[data-action="mission-tab"]').length, hand: document.querySelectorAll('#hand-B .hand-row').length }));
    check('table mode: score instead of the forecast, no card advice, Plan / Cards / Attack / Board closed, the tracker stays', tm.flag && /Score 27 – 15 VP/.test(tm.score) && !tm.forecast && !tm.win && tm.advice === 0 && tm.attackOff && tm.boardOff && tm.tabs === 0 && tm.hand === 1, JSON.stringify(tm));
    await tp2.evaluate(() => window.scrollTo(0, 0));
    await tp2.screenshot({ path: join(SHOTS, 'calc_55_table_mode.png'), fullPage: true });
    await tp2.tap('button[data-action="view"][data-value="intel"]');
    check('table mode on Intel: datasheets only (no brief, no calculator links)', /Table mode: datasheets, abilities and stratagems only/.test(await tp2.textContent('#intel-table-note')) && (await tp2.locator('#brief-host').count()) === 0 && (await tp2.locator('button[data-action="target-this"]').count()) === 0 && (await tp2.locator('.intel-unit').count()) > 3);
    await tp2.tap('button[data-action="view"][data-value="mission"]');
    await tp2.tap('button[data-action="mission-score-step"][data-side="B"][data-k="secondary"][data-delta="5"]');
    check('table mode: no forecast is worked out', await tp2.evaluate(() => window.__calc.mission().busy === false) && /Score 27 – 20 VP/.test((await tp2.textContent('#score-mini')).replace(/\s+/g, ' ')));
    // a tap on a closed tab stays on the tracker and says why; "Leave table mode" is at the top of the page
    await tp2.tap('button[data-action="view"][data-value="attack"]');
    check('table mode: a tap on Attack stays on the tracker and says the calculator is closed', (await tp2.locator('#play-bar').count()) === 1 && /The calculator is closed in table mode/.test(await tp2.textContent('#table-locked')) && (await tp2.locator('select[data-input="target"]').count()) === 0);
    await tp2.tap('button[data-action="view"][data-value="board"]');
    check('table mode: the same for Board', /The board planner is closed in table mode/.test(await tp2.textContent('#table-locked')) && (await tp2.locator('#board-svg').count()) === 0);
    await tp2.screenshot({ path: join(SHOTS, 'calc_58_table_mode_locked.png') });
    await tp2.tap('#table-leave');
    await idle();
    check('"Leave table mode" at the top: the forecast and the tabs are back', (await tp2.locator('#fc-mini-win').count()) === 1 && (await tp2.locator('button[data-action="mission-tab"]').count()) >= 3 && (await tp2.getAttribute('button[data-action="view"][data-value="attack"]', 'data-locked')) === null && (await tp2.locator('#table-leave').count()) === 0);

    // play to the end of the battle
    let guard = 0;
    while (!(await gs()).over && guard++ < 12) await tp2.tap('#play-turn-done');
    st = await gs();
    check('the battle ends after the second turn of round 5: final score, no more turns', st.over && st.round === 5 && await tp2.isDisabled('#play-turn-done') && /Battle over/.test(await tp2.textContent('#play-turn-done')) && /Final 27 – 20 VP/.test((await tp2.textContent('#score-mini')).replace(/\s+/g, ' ')) && /Battle over\. Final score: A 27 – B 20/.test(await tp2.textContent('#play-turn')), JSON.stringify(st));
    await idle();
    const fin = await tp2.evaluate(() => { const r = window.__calc.mission().result; return { a: r.A.mean, b: r.B.mean, w: r.pWinA }; });
    check('after the battle the forecast is the final score', fin.a === 27 && fin.b === 20 && fin.w === 1, JSON.stringify(fin));
    await tp2.tap('#play-reset');
    st = await gs();
    check('New game clears the tracker (1CP each, first turn open again) and can be undone', st.round === 1 && !st.over && st.cp.join() === '1,1' && st.first === null && st.A.join() === '0,0' && !(await tp2.isDisabled('#play-undo')), JSON.stringify(st));
    await tp2.tap('#play-undo');
    check('Undo brings the finished game back', (await gs()).over === true && (await gs()).A.join() === '12,5');
    check('table tools: no console errors', terrs.length === 0, terrs.slice(0, 3).join(' | '));

    // before any turn is done, the turn picker is the "First turn" question: B goes first
    await tp2.tap('#play-reset');
    check('at the start the turn picker asks for the first turn (no separate question)', /First turn/.test(await tp2.textContent('#play-bar')) && (await tp2.locator('#play-bar button[data-action="mission-first"]').count()) === 0);
    await tp2.tap('button[data-action="mission-next"][data-value="B"]');
    await tp2.tap('#play-turn-done');
    st = await gs();
    check('picking B for the first turn makes B the first player: after B\'s turn it is still round 1, A to play', st.first === 'B' && st.round === 1 && st.next === 'A' && st.cp.join() === '2,2', JSON.stringify(st));
    await tp2.tap('#play-turn-done');
    check('and after A\'s turn: battle round 2, B to play', (await gs()).round === 2 && (await gs()).next === 'B');

    // tablet: the turn bar across the top, both players side by side under it, the time on the pinned line
    await tp2.tap('#play-reset');
    await tp2.setViewportSize({ width: 1280, height: 800 });
    await tp2.waitForTimeout(400);
    await tp2.tap('button[data-action="mission-clock-mode"][data-value="round"]');
    await tp2.tap('#clock-go');
    await idle();
    await tp2.evaluate(() => window.scrollTo(0, 0));
    await tp2.waitForTimeout(200);
    const lay = await tp2.evaluate(() => { const r = (q) => { const b = document.querySelector(q).getBoundingClientRect(); return { l: Math.round(b.left), t: Math.round(b.top), b: Math.round(b.bottom), w: Math.round(b.width) }; };
      return { bar: r('.mlay.play .a-bar'), me: r('.mlay.play .a-me'), opp: r('.mlay.play .a-opp'), clock: r('.mlay.play .a-clock'), cpA: r('#cp-A'), cpB: r('#cp-B'), mini: r('#mini-clock'), vh: innerHeight, vw: innerWidth, pages: +(document.documentElement.scrollHeight / innerHeight).toFixed(2) }; });
    check('tablet Play: the turn bar spans the screen, the two players are side by side under it with scores and CP on screen, the clock is on the pinned line',
      lay.bar.w > lay.vw * 0.9 && lay.me.t >= lay.bar.b - 2 && Math.abs(lay.me.t - lay.opp.t) < 3 && lay.opp.l > lay.me.l + 300 && lay.cpA.b < lay.vh && lay.cpB.b < lay.vh && lay.mini.t > 0 && lay.mini.b < 200 && lay.clock.t >= lay.me.t, JSON.stringify(lay));
    await tp2.screenshot({ path: join(SHOTS, 'calc_56_tablet_play_tools.png') });
    await tctx.close();
  }

  // --- how current the rules data is: where each army's datasheets come from and from when, and the
  // points in the pasted list against the data (the Space Wolves list is a real export of the official app)
  {
    const dctx = await browser.newContext({ ...devices['Pixel 7'] });
    const dp = await dctx.newPage();
    await dp.goto(`${BASE}/calc/`);
    await dp.fill('textarea[data-side="A"]', SW_LIST);
    await dp.tap('button[data-action="parse"][data-side="A"]');
    await dp.fill('textarea[data-side="B"]', ORK_LIST);
    await dp.tap('button[data-action="parse"][data-side="B"]');
    const txt = async (q) => (await dp.textContent(q)).replace(/\s+/g, ' ').trim();
    check('Armies: each army says which rules data it uses and its date', /Rules data: Codex: Space Marines \(Wahapedia\), 21 Oct 2026 — all 12 datasheets\./.test(await txt('#data-A')) && /Rules data: Codex: Orks \(Wahapedia\), 16 Oct 2026 — all 6 datasheets\./.test(await txt('#data-B')), `${await txt('#data-A')} | ${await txt('#data-B')}`);
    check('Armies: a real list from the official app costs what the data says, datasheet by datasheet', /✓ Points: all 12 datasheets cost what the rules data says\./.test(await txt('#points-A')), await txt('#points-A'));
    check('Armies: other points in the list than in the data are named with both numbers', /3 of 6 datasheets cost something else in your list than in the rules data — Warboss 70 \(data 100\), Meganobz 100 \(data 105 or 145\), Flash Gitz 80 \(data 110 or 150\)\./.test(await txt('#points-B')), await txt('#points-B'));
    check('Armies: the footer names the dataset, the refresh and the newest date', /rules data: 40kdc 1\.4\.5 with codex datasheets and the points and weapon profiles of 1\.5\.1, newest 21 Oct 2026/.test(await txt('#data-footer')), await txt('#data-footer'));
    check('Armies: the dataset credit and its link are shown (licence of the data)', /Powered by 40kdc-data/.test(await txt('#data-credit')) && (await dp.getAttribute('#data-credit a', 'href')) === 'https://40kdc.alpacasoft.dev');
    await dp.locator('#data-B').scrollIntoViewIfNeeded();
    await dp.screenshot({ path: join(SHOTS, 'calc_57_rules_data.png') });
    await dp.tap('button[data-action="view"][data-value="intel"]');
    await dp.tap('button[data-action="intel-side"][data-value="B"]');
    const stamps = await dp.$$eval('.intel-unit [data-stamp]', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim()));
    check('Intel: every unit shows the date of its datasheet; the ones with other points are flagged', stamps.length === 5 && stamps.every(t => /^Rules data: Codex: Orks \(Wahapedia\), 16 Oct 2026\./.test(t)) && stamps.filter(t => /pts in your list/.test(t)).length === 3
      && stamps.some(t => /Warboss: 70 pts in your list, 100 in the data — check this datasheet/.test(t)), JSON.stringify(stamps));
    {
      // a faction without a codex import here: its points and weapon profiles are those of the newer
      // dataset release (calculator only), and the stamp says which part is older
      await dp.tap('button[data-action="view"][data-value="armies"]');
      const TYR = (pts) => `Hive (500 points)\n\nTyranids\nInvasion Fleet\nIncursion (1000 points)\n\nHive Tyrant (195 points)\n\nTermagants (${pts} points)\n  • 10x Termagant\n`;
      await dp.fill('textarea[data-side="B"]', TYR(55));
      await dp.tap('button[data-action="parse"][data-side="B"]');
      check('a faction without a codex import shows the newer release for points and weapons, and that its abilities are older',
        /Rules data: 40kdc 1\.5\.1 points and weapon profiles, 14 Oct 2026 \(abilities: 40kdc 1\.4\.5, 20 Jun 2026\)/.test(await txt('#data-B')) && /✓ Points: all 2 datasheets cost what the rules data says/.test(await txt('#points-B')), await txt('#data-B'));
      await dp.fill('textarea[data-side="B"]', TYR(60));
      await dp.tap('button[data-action="parse"][data-side="B"]');
      check('the points check uses the refreshed points (Termagants: 55 for ten, 60 before the refresh)', /Termagants 60 \(data 55\)/.test(await txt('#points-B')), await txt('#points-B'));
      const refresh = await dp.evaluate(async () => { const A = await import('/calc/adapter.mjs'); return A.ERRATA_RESULT; });
      check('the refresh was applied in the browser: every entry, none skipped', refresh.from === '1.5.1' && refresh.points > 150 && refresh.weapons > 90 && refresh.skipped.length === 0, JSON.stringify({ ...refresh, skipped: refresh.skipped.length }));
      await dp.locator('#data-B').scrollIntoViewIfNeeded();
      await dp.screenshot({ path: join(SHOTS, 'calc_59_rules_data_refresh.png') });
      await dp.fill('textarea[data-side="B"]', ORK_LIST);
      await dp.tap('button[data-action="parse"][data-side="B"]');
    }
    await dp.tap('button[data-action="view"][data-value="mission"]');
    await dp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 120000 });
    await dp.locator('details[data-details="mission-basis"] summary').tap();
    check('"What this forecast is built from" names the datasheet dates of both armies', /A: Codex: Space Marines \(Wahapedia\), 21 Oct 2026\. B: Codex: Orks \(Wahapedia\), 16 Oct 2026 \(⚠ 3 datasheets with other points/.test(await txt('#fc-basis li.basis.stamp')), await txt('#fc-basis li.basis.stamp'));
    await dctx.close();
  }

  // --- no view is wider than the screen (a page that pans sideways is hard to use one-handed):
  // every view at 360 px (most Android phones) and 412 px
  {
    const small = await browser.newContext({ ...devices['Pixel 7'], viewport: { width: 360, height: 740 } });
    const sp = await small.newPage();
    await sp.goto(`${BASE}/calc/`);
    await sp.fill('textarea[data-side="A"]', SW_LIST);
    await sp.tap('button[data-action="parse"][data-side="A"]');
    await sp.fill('textarea[data-side="B"]', ORK_LIST);
    await sp.tap('button[data-action="parse"][data-side="B"]');
    const wide = [];
    for (const w of [360, 412]) {
      await sp.setViewportSize({ width: w, height: 740 });
      await sp.waitForTimeout(300);
      for (const [v, t] of [['armies'], ['intel'], ['attack'], ['board'], ['mission', 'plan'], ['mission', 'cards'], ['mission', 'play']]) {
        await sp.tap(`button[data-action="view"][data-value="${v}"]`);
        if (t) { await sp.tap(`button[data-action="mission-tab"][data-value="${t}"]`); await sp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 120000 }); }
        if (v === 'board') await sp.waitForSelector('#board-svg');
        await sp.waitForTimeout(150);
        const m = await sp.evaluate(() => ({ sw: document.documentElement.scrollWidth, vw: document.documentElement.clientWidth, tabs: [...document.querySelectorAll('.tabs .tab')].every(b => { const r = b.getBoundingClientRect(); return r.left >= 0 && r.right <= document.documentElement.clientWidth + 0.5; }) }));
        if (m.sw > m.vw + 1 || !m.tabs) wide.push(`${w}px ${v}${t ? '/' + t : ''}: ${m.sw} > ${m.vw}${m.tabs ? '' : ' (tabs cut off)'}`);
      }
    }
    check('no view is wider than the screen at 360 px and 412 px, and all five tabs are on screen', wide.length === 0, wide.join('; '));
    await sp.setViewportSize({ width: 360, height: 740 });
    await sp.tap('button[data-action="view"][data-value="mission"]');
    await sp.tap('button[data-action="mission-tab"][data-value="cards"]');
    await sp.waitForSelector('#fc-modes tbody tr', { timeout: 120000 });
    await sp.screenshot({ path: join(SHOTS, 'calc_50_phone_360.png') });
    await small.close();
  }

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
  {
    // --- three columns on a landscape tablet (1.127.0): my army | the map | the opponent, no pinned dock
    await lp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    const rects = await lp.evaluate(() => {
      const r = (q) => { const e = document.querySelector(q); const b = e.getBoundingClientRect(); return { l: b.left, r: b.right, t: b.top, b: b.bottom, w: b.width }; };
      return { map: r('#board-host'), me: r('#board-army-A'), opp: r('#board-army-B'), panel: r('#board-army-A #board-panel'), vw: innerWidth, vh: innerHeight, dock: !!document.getElementById('board-dock') };
    });
    check('tablet Board: my army left of the map, the opponent right of it, the selected unit\'s panel in my column, all on screen',
      rects.me.r <= rects.map.l + 2 && rects.opp.l >= rects.map.r - 2 && rects.map.b <= rects.vh && rects.panel.t < rects.vh && rects.map.w > 350 && !rects.dock, JSON.stringify(rects));
    await lp.screenshot({ path: join(SHOTS, 'calc_39_tablet_board.png') });
    await lp.tap('button[data-action="view"][data-value="mission"]');
    await lp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy; }, null, { timeout: 120000 });
    const pl = await lp.evaluate(() => {
      const r = (q) => { const b = document.querySelector(q).getBoundingClientRect(); return { l: b.left, r: b.right, t: b.top, w: b.width }; };
      return { hero: r('.mlay.plan .a-hero'), grid: r('.mlay.plan .a-grid'), h: document.documentElement.scrollHeight, vh: innerHeight, rounds: document.querySelector('[data-details="mission-rounds"]').open };
    });
    check('tablet Mission: forecast on the left, objective plan on the right, round-by-round open, under 2.2 screens (was 4.7)',
      pl.grid.l >= pl.hero.r - 2 && pl.grid.w > 350 && pl.rounds === true && pl.h < 2.2 * pl.vh, JSON.stringify(pl));
    await lp.screenshot({ path: join(SHOTS, 'calc_40_tablet_mission.png') });
    await lp.tap('button[data-action="mission-tab"][data-value="play"]');
    await lp.waitForSelector('#play-bar');
    await lp.screenshot({ path: join(SHOTS, 'calc_41_tablet_play.png') });
    await lp.tap('button[data-action="view"][data-value="attack"]');
    await lp.selectOption('select[data-input="target"]', targetValue);
    await lp.tap('button[data-action="open-add"]');
    await lp.tap('.pick:has-text("Grey Hunters")');
    await lp.waitForFunction(() => window.__calc?.state.result && !window.__calc.state.busy);
    await lp.waitForSelector('#attack-pane #chart svg');
    const ap = await lp.evaluate(() => ({ pane: document.getElementById('attack-pane').getBoundingClientRect().left, bar: document.querySelector('#resultbar .resultbar') != null, sheet: document.querySelector('.sheet') != null, vw: innerWidth }));
    check('tablet Attack: the full result (chart, odds) sits beside the set-up, no bottom bar or sheet', ap.pane > ap.vw * 0.4 && !ap.bar && !ap.sheet, JSON.stringify(ap));
    await lp.locator('#attack-pane #chart .hit').nth(3).tap();
    check('tablet Attack: tapping a bar in the side pane shows its odds', /exactly .* at least/.test(await lp.textContent('#attack-pane #readout')));
    await lp.screenshot({ path: join(SHOTS, 'calc_42_tablet_attack.png') });
  }
  await land.close();
  // GW app list with U+2011 non-breaking hyphens (Contemptor‑Galatus, Grav‑Tank) imports cleanly
  await tp.tap('button[data-action="view"][data-value="armies"]');
  await tp.fill('textarea[data-side="B"]', readFileSync(join(here, 'fixtures', 'gw-custodes-nbhyphen.txt'), 'utf8'));
  await tp.tap('button[data-action="parse"][data-side="B"]');
  const custodes = await tp.evaluate(() => ({ units: window.__calc.state.armies.B.units.map(u => u.name), warnings: window.__calc.state.armies.B.warnings }));
  check('non-breaking-hyphen units resolve (Caladius, 2x Contemptor-Galatus)',
    custodes.units.includes('Caladius Annihilator Grav-Tank') && custodes.units.filter(n => /^Contemptor-Galatus/.test(n)).length === 2 &&
    !custodes.warnings.some(w => /unresolved|not recognised/.test(w)), JSON.stringify(custodes));

  // --- board and mission rules (1.101): control per model, Hidden, coherency, reserves, territory, Move bonus
  {
    const bctx = await browser.newContext({ ...devices['Pixel 7'] });
    const bp = await bctx.newPage();
    bp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`board rules: ${m.text()}`); });
    bp.on('pageerror', e => consoleErrors.push(`board rules: ${e}`));
    await bp.goto(`${BASE}/calc/`);
    await bp.waitForSelector('textarea[data-side="A"]');
    await bp.fill('textarea[data-side="A"]', SW_LIST); await bp.tap('button[data-action="parse"][data-side="A"]');
    await bp.fill('textarea[data-side="B"]', ORK_LIST); await bp.tap('button[data-action="parse"][data-side="B"]');
    await bp.tap('button[data-action="view"][data-value="board"]');
    await bp.waitForSelector('#board-svg');
    const bTokens = () => bp.evaluate(() => window.__calc.board().tokens);
    const bScreen = (x, y) => bp.evaluate(([bx, by]) => { const svg = document.getElementById('board-svg'); const pt = svg.createSVGPoint(); pt.x = bx; pt.y = by; const q = pt.matrixTransform(svg.getScreenCTM()); return { x: q.x, y: q.y }; }, [x, y]);
    const bPlace = (tk, x, y) => bp.evaluate(([t, px, py]) => { const p = window.__calc.board().plan; Object.assign(p.steps[p.cur].tokens[t], { x: px, y: py, rot: 0 }); }, [tk, x, y]);
    const bSelect = async (tk) => {
      await bp.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
      const e = await bScreen(43.5, 59.5); await bp.mouse.click(e.x, e.y);        // clear the selection (and redraw)
      const t = (await bTokens()).find(x => x.tk === tk); const q = await bScreen(t.x, t.y); await bp.mouse.click(q.x, q.y);
    };
    await bp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    const gh = (await bTokens()).find(t => t.tk.startsWith('A:'));
    // 14.02: the OC of the models within range. Find a spot where only part of the ten Grey Hunters reach an objective
    const spot = await bp.evaluate(async (tk) => {
      const E = await import('/calc/planeval.mjs');
      const { LAYOUTS } = await import('/calc/terrain-11e.mjs');
      const d = window.__calc.board();
      const l = LAYOUTS.find(x => x.id === d.layout);
      const u = d.units.find(x => x.tk === tk);
      for (const o of l.objectives) for (let dy = 2; dy <= 9; dy += 0.25) for (const sx of [0, 1.5, -1.5]) {
        const cand = { x: o.x + sx, y: o.y - dy, models: u.models };
        if (cand.y < 2 || cand.y > 58) continue;
        const total = u.models.reduce((a, m) => a + m.oc, 0);
        const oc = E.ocInRange({ ...cand, oc: total }, o, l.pieces);
        const others = l.objectives.filter(z => z.id !== o.id).some(z => E.inRange(cand, z, l.pieces));
        if (oc > 0 && oc < total && !others) return { o: o.id, x: cand.x, y: cand.y, oc, total, each: u.models[0].oc };
      }
      return null;
    }, gh.tk);
    check('found a spot where only some of the Grey Hunters are in range of an objective', !!spot, JSON.stringify(spot));
    await bPlace(gh.tk, spot.x, spot.y);
    await bSelect(gh.tk);
    const ctl = await bp.evaluate((id) => { const g = document.querySelector(`#board-svg [data-obj="${id}"]`); return g ? { a: Number(g.dataset.oca), b: Number(g.dataset.ocb), ctl: g.dataset.control, text: g.textContent.trim() } : null; }, spot.o);
    check(`objective control counts the models in range: ${spot.oc} (${spot.oc / spot.each} models x OC ${spot.each}), not the whole unit's ${spot.total}`, ctl && ctl.a === spot.oc && ctl.a < spot.total && ctl.ctl === 'A' && ctl.text === `A ${spot.oc} · B 0`, JSON.stringify({ ctl, spot }));
    await bp.screenshot({ path: join(SHOTS, 'calc_63_board_oc_models.png') });
    // 03.03 coherency: the starting formation is legal; ten in one line is not, and the board says so
    check('the starting formation is in coherency (no warning)', (await bp.locator('#board-coherency').count()) === 0);
    await bp.locator('#board-panel button[data-action="board-formation"]', { hasText: 'Line' }).tap();
    await bp.waitForSelector('#board-coherency');
    check('ten models in one line: "Not in coherency" with the distance', /Not in coherency: two models are \d+\.\d" apart \(every model must be within 9" of every other\)/.test(await bp.textContent('#board-coherency')), await bp.textContent('#board-coherency'));
    await bp.locator('#board-panel').scrollIntoViewIfNeeded();
    await bp.screenshot({ path: join(SHOTS, 'calc_64_board_coherency.png') });
    await bp.locator('#board-panel button[data-action="board-formation"][data-value="5"]').tap();
    check('back to rows of five: in coherency again', (await bp.locator('#board-coherency').count()) === 0);
    // 13.09 (errata): infantry in an area with a LIGHT feature can be Hidden - the threat list says who can still shoot it
    await bp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Scout Squad (1)' }).tap();
    const sc1 = (await bTokens()).find(t => t.tk.startsWith('A:') && t.tk !== gh.tk);
    const hide = await bp.evaluate(async (tk) => {
      const S = await import('/calc/sight.mjs');
      const { LAYOUTS } = await import('/calc/terrain-11e.mjs');
      const d = window.__calc.board();
      const l = LAYOUTS.find(x => x.id === d.layout);
      const u = d.units.find(x => x.tk === tk);
      const groups = S.areaGroups(l.pieces);
      const lightOnly = new Set(l.pieces.filter(p => p.cls === 'feature' && p.cat === 'light').map(p => groups.get(p.id)));
      const dense = new Set(l.pieces.filter(p => p.cls === 'feature' && p.cat === 'dense').map(p => groups.get(p.id)));
      let any = null;
      for (const a of l.pieces.filter(p => p.cls === 'area')) {
        const cx = a.poly.reduce((s, q) => s + q[0], 0) / a.poly.length, cy = a.poly.reduce((s, q) => s + q[1], 0) / a.poly.length;
        for (const per of [5, 3, 2, 1]) {
          const B = await import('/calc/board.mjs');
          const members = [{ count: u.models.length, fp: u.models[0].fp }];
          const cand = { x: cx, y: cy, keywords: u.keywords, models: B.coherentFormation(members, { perRow: per, keepRows: true }) };
          if (!S.canHide(cand, l.pieces)) continue;
          const g = groups.get(a.id);
          const res = { x: cx, y: cy, per, light: lightOnly.has(g) && !dense.has(g) };
          if (res.light) return res;
          any ??= res;
        }
      }
      return any;
    }, sc1.tk);
    check('found a terrain area where the Scouts can be Hidden', !!hide, JSON.stringify(hide));
    await bPlace(sc1.tk, hide.x, hide.y);
    await bp.evaluate(([t, per]) => { const p = window.__calc.board().plan; p.steps[p.cur].tokens[t].per = per; }, [sc1.tk, hide.per]);
    await bp.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Flash Gitz' }).tap();
    const gitz = (await bTokens()).find(t => t.tk.startsWith('B:'));
    // the Flash Gitz stand 30" away: in range after a move, but not within 15"
    const far = { x: Math.max(4, Math.min(40, hide.x)), y: hide.y > 30 ? hide.y - 30 : hide.y + 30 };
    await bPlace(gitz.tk, far.x, far.y);
    await bSelect(sc1.tk);
    await bp.waitForSelector('#board-threats');
    const thr = await bp.evaluate(() => { const el = document.getElementById('board-threats'); return { hide: el.dataset.hide, text: el.textContent.replace(/\s+/g, ' ').trim() }; });
    check(`Hidden${hide.light ? ' in LIGHT terrain' : ''}: the board says the unit can be Hidden here and that the Flash Gitz cannot shoot it while it is`, thr.hide === '1' && /Can be Hidden here/.test(thr.text) && /only models within 15" can see it \(13\.09\)/.test(thr.text) && (/not while Hidden/.test(thr.text) || !/Flash Gitz/.test(thr.text)), JSON.stringify(thr));
    await bp.locator('#board-panel').scrollIntoViewIfNeeded();
    await bp.screenshot({ path: join(SHOTS, 'calc_65_board_hidden.png') });
    // Stormlance "+2" M" for Mounted units reaches the board
    await bp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Thunderwolf Cavalry' }).first().tap();
    const tw = (await bTokens()).find(t => t.tk.startsWith('A:') && t.tk !== gh.tk && t.tk !== sc1.tk);
    await bSelect(tw.tk);
    const moveChip = await bp.locator('#board-panel button[data-action="board-ring"]', { hasText: 'Move' }).first().textContent();
    check('Thunderwolf Cavalry move 14" on the board: 12" + 2" from the Stormlance detachment rule', /Move 14" \(\+2" Lightning-fast Strike\)/.test(moveChip), moveChip);
    // reserves: a unit that first appears in "Turn 2"
    await bp.tap('button[data-action="board-step-add"]');
    await bp.tap('button[data-action="board-step-add"]');
    check('two more steps: Turn 1 and Turn 2', (await bp.evaluate(() => window.__calc.board().plan.steps.map(s => s.name).join(','))) === 'Deploy,Turn 1,Turn 2', await bp.evaluate(() => window.__calc.board().plan.steps.map(s => s.name).join(',')));
    await bp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Scout Squad (2)' }).tap();
    await bp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Logan Grimnar' }).tap();
    const toks3 = await bTokens();
    const names = await bp.evaluate(() => Object.fromEntries(window.__calc.board().units.map(u => [u.tk, (window.__calc.state.armies[u.tk[0]].units.find(x => `${u.tk[0]}:${x.key}` === u.tk) ?? {}).name])));
    const scoutTk = toks3.find(t => /Scout Squad \(2\)/.test(names[t.tk] ?? ''))?.tk, loganTk = toks3.find(t => /Logan/.test(names[t.tk] ?? ''))?.tk;
    check('Scouts and the Terminators (Deep Strike) are placed only in Turn 2: they arrive from reserves', !!scoutTk && !!loganTk, JSON.stringify(names));
    // both in the middle of the board, far from any edge and from the enemy
    const mid = await bp.evaluate(async () => {
      const { LAYOUTS } = await import('/calc/terrain-11e.mjs');
      const d = window.__calc.board();
      const en = d.tokens.filter(t => t.tk.startsWith('B:'));
      const ok = (x, y) => en.every(e => Math.hypot(e.x - x, e.y - y) > 16);
      const out = [];
      for (let y = 22; y <= 38 && out.length < 2; y += 4) for (let x = 12; x <= 32 && out.length < 2; x += 10) if (ok(x, y) && out.every(o => Math.hypot(o.x - x, o.y - y) > 9)) out.push({ x, y });
      return out;
    });
    await bPlace(scoutTk, mid[0].x, mid[0].y);
    await bPlace(loganTk, mid[1].x, mid[1].y);
    await bSelect(scoutTk);
    await bp.waitForSelector('#board-warnings');
    const warns = await bp.$$eval('#board-warnings li', els => els.map(e => ({ unit: e.dataset.unit, text: e.textContent.replace(/\s+/g, ' ').trim() })));
    check('the Scouts (no Deep Strike) are warned: reserves are set up wholly within 6" of a battlefield edge (20.04)', warns.some(w => /Scout Squad \(2\)/.test(w.unit) && /more than 6" from a battlefield edge/.test(w.text)), JSON.stringify(warns));
    check('the Terminators (every model has Deep Strike) are not warned in the same place (24.09)', !warns.some(w => /Logan/.test(w.unit)), JSON.stringify(warns));
    await bp.locator('#board-warnings').scrollIntoViewIfNeeded();
    await bp.screenshot({ path: join(SHOTS, 'calc_66_board_reserves.png') });
    await bctx.close();
  }

  // --- stratagem limits, shooting type, Heavy / Damaged, engaged targets, rules for named weapons (1.102)
  {
    const sctx = await browser.newContext({ ...devices['Pixel 7'] });
    const sp = await sctx.newPage();
    sp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`attack rules: ${m.text()}`); });
    sp.on('pageerror', e => consoleErrors.push(`attack rules: ${e}`));
    await sp.goto(`${BASE}/calc/`);
    await sp.waitForSelector('textarea[data-side="A"]');
    await sp.fill('textarea[data-side="A"]', SW_LIST); await sp.tap('button[data-action="parse"][data-side="A"]');
    await sp.fill('textarea[data-side="B"]', ORK_LIST); await sp.tap('button[data-action="parse"][data-side="B"]');
    await sp.tap('button[data-action="view"][data-value="attack"]');
    const done = () => sp.waitForFunction(() => { const s = window.__calc?.state; return s && !s.busy && s.result; }, null, { timeout: 30000 });
    const target = async (re) => { const v = await sp.$eval('select[data-input="target"]', (sel, src) => [...sel.options].find(o => new RegExp(src).test(o.textContent))?.value, re.source); await sp.selectOption('select[data-input="target"]', v); };
    const add = async (name) => { await sp.tap('button[data-action="open-add"]'); await sp.tap(`.pick:has-text("${name}")`); await done(); };
    const rowsOf = (card) => card.locator('.weapon[data-row]').evaluateAll(els => els.map(e => ({ name: e.querySelector('.wname').textContent.trim(), val: e.querySelector('.stepper .val').textContent.trim(), blocked: e.querySelector('.tag.warn')?.textContent.trim() ?? null, off: [...e.querySelectorAll('.tag.off')].map(t => t.textContent.trim()) })));
    const row = (rows, re) => rows.find(r => re.test(r.name));
    const wounds = () => sp.evaluate(() => window.__calc.state.result.meanWounds);
    await target(/Battlewagon/);
    await add('Scout Squad (1)');
    const card = () => sp.locator('[data-attacker]').last();
    // shooting type (10.04 - 10.06)
    let rs = await rowsOf(card());
    check('normal shooting: shotguns, krak missile and sniper rifle fire, pistols stay out', row(rs, /Shotgun/).val === '3/3' && row(rs, /Krak/).val === '1/1' && row(rs, /Sniper/).val === '1/1' && row(rs, /Bolt Pistol/).val === '0/5', JSON.stringify(rs));
    await card().locator('button[data-action="shooting-type"][data-value="assault"]').tap(); await done();
    rs = await rowsOf(card());
    check('after an advance only the Assault weapons shoot (the shotguns)', row(rs, /Shotgun/).val === '3/3' && row(rs, /Krak/).val === '0/1' && row(rs, /Krak/).blocked === 'After an advance only Assault weapons shoot' && row(rs, /Sniper/).val === '0/1', JSON.stringify(rs));
    await card().locator('button[data-action="shooting-type"][data-value="cq"]').tap(); await done();
    rs = await rowsOf(card());
    check('engaged: only the close-quarters weapons shoot (5 bolt pistols)', row(rs, /Bolt Pistol/).val === '5/5' && row(rs, /Shotgun/).blocked === 'Engaged: only Close-quarters weapons shoot', JSON.stringify(rs));
    await card().locator('button[data-action="shooting-type"][data-value="normal"]').tap(); await done();
    // Heavy (24.16): +1 to hit when no model moved more than 3"
    const w0 = await wounds();
    const heavy = card().locator('button[data-key="heavyOk"]');
    check('a unit with Heavy weapons has the "Moved 3" or less" chip', (await heavy.count()) === 1 && /Heavy: \+1 to hit/.test(await heavy.textContent()));
    await heavy.tap(); await done();
    const w1 = await wounds();
    const heavyOn = await sp.evaluate(() => window.__calc.scenario().attackers[0].mods.heavyOk);
    check('Heavy +1 to hit reaches the engine and raises the damage of the Heavy weapon in use (the sniper rifle)', heavyOn === true && w1 > w0 * 1.01, `${w0} -> ${w1}`);
    await sp.evaluate(() => document.querySelector('[data-attacker]').scrollIntoView());
    await sp.screenshot({ path: join(SHOTS, 'calc_67_shooting_type_heavy.png') });
    // an engaged Monster / Vehicle: -1 to hit for shooting, no Blast (17.03)
    await sp.locator('details.more', { hasText: 'Defender modifiers' }).locator('summary').tap();
    await sp.locator('button[data-action="defmod-toggle"][data-key="engaged"]').tap(); await done();
    const w2 = await wounds();
    const sc = await sp.evaluate(() => window.__calc.scenario());
    check('target engaged in melee: the engine gets -1 to hit for shooting at it', sc.defender.mods.engagedMV === true && w2 < w1 * 0.9, `${w1} -> ${w2}`);
    await target(/Warboss \+ Boyz/); await done();
    check('the "Engaged in melee" option is only for a Monster or Vehicle target', (await sp.locator('button[data-action="defmod-toggle"][data-key="engaged"]').count()) === 0);
    // stratagems: one on a unit in a phase, each once in a phase (15.01)
    await sp.tap('button[data-action="phase"][data-value="fight"]');
    await target(/Battlewagon/);
    await add('Thunderwolf Cavalry (1)');
    const strats = (c) => c.locator('.modrow', { hasText: 'Stratagems (tap to use)' }).locator('button[data-action="arule"]');
    const onNames = async (c) => strats(c).evaluateAll(els => els.filter(e => e.getAttribute('aria-pressed') === 'true').map(e => e.textContent.trim().slice(0, 60)));
    const c1 = card();
    const n = await strats(c1).count();
    check('Thunderwolf Cavalry have several stratagems to choose from in the Fight phase', n >= 3, String(n));
    const names = await strats(c1).evaluateAll(els => els.map(e => e.textContent.trim()));
    const idxA = names.findIndex(t => /COMMAND RE-ROLL/.test(t)), idxB = names.findIndex(t => !/COMMAND RE-ROLL/.test(t) && !/^or:/.test(t));
    await strats(c1).nth(idxB).tap(); await done();
    check('one stratagem on', (await onNames(card())).length === 1, JSON.stringify(await onNames(card())));
    await strats(card()).nth(idxA).tap(); await done();
    const after = await onNames(card());
    check('a second stratagem on the same unit switches the first off (one on a unit in a phase)', after.length === 1 && /COMMAND RE-ROLL/.test(after[0]), JSON.stringify(after));
    check('the card states the rule', /One stratagem on a unit in a phase, and each stratagem once in a phase \(15\.01\)/.test(await card().locator('[data-strat-note]').textContent()));
    // the same stratagem on a second unit: off on the first (each stratagem once in a phase)
    await add('Grey Hunters');
    const c2 = sp.locator('[data-attacker]').last(), c1b = sp.locator('[data-attacker]').first();
    await strats(c2).filter({ hasText: 'COMMAND RE-ROLL' }).first().tap(); await done();
    const first = await onNames(sp.locator('[data-attacker]').first()), second = await onNames(sp.locator('[data-attacker]').last());
    check('Command Re-roll on the second unit takes it from the first (the same stratagem once in a phase)', first.length === 0 && second.length === 1 && /COMMAND RE-ROLL/.test(second[0]), JSON.stringify({ first, second }));
    await sp.locator('[data-attacker]').last().locator('[data-strat-note]').scrollIntoViewIfNeeded();
    await sp.screenshot({ path: join(SHOTS, 'calc_68_stratagem_limit.png') });
    // the defender can re-roll one save with Command Re-roll (15.02)
    const dStrat = sp.locator('button[data-action="rule"]', { hasText: 'Re-roll one save' });
    check('the target has "Re-roll one save" (Command Re-roll) among its stratagems', (await dStrat.count()) === 1 && /COMMAND RE-ROLL \(1CP\)/.test(await dStrat.textContent()), await dStrat.textContent().catch(() => 'missing'));
    const before = await wounds();
    await dStrat.tap(); await done();
    const sc2 = await sp.evaluate(() => window.__calc.scenario());
    check('it reaches the engine and lowers the damage a little', sc2.defender.mods.rerollOneSave === true && (await wounds()) < before, `${before} -> ${await wounds()}`);
    // rules for named weapons: Terminators after a charge - Sustained Hits on the hammers against a Vehicle
    await sp.locator('[data-attacker]').last().locator('button[data-action="remove"]').tap();
    await sp.locator('[data-attacker]').last().locator('button[data-action="remove"]').tap();
    await add('Logan Grimnar');
    await card().locator('button[data-key="charged"]').tap(); await done();
    const chips = await card().locator('button[data-action="arule"]').evaluateAll(els => els.map(e => ({ t: e.textContent.replace(/\s+/g, ' ').trim(), on: e.getAttribute('aria-pressed') === 'true' })));
    const th = chips.find(c => /^Thunder Hammer: Sustained Hits 1/.test(c.t)), lc = chips.find(c => /^Lightning Claws: Sustained Hits 1/.test(c.t));
    check('Terminatus Assault after a charge: Sustained Hits 1 on the thunder hammers against the Battlewagon, not on the lightning claws', th?.on === true && lc?.on === false, JSON.stringify({ th, lc }));
    const sc3 = await sp.evaluate(() => window.__calc.scenario());
    const hammers = sc3.attackers[0].weapons.find(w => w.name === 'Thunder Hammer'), claws = sc3.attackers[0].weapons.find(w => /Lightning Claws/.test(w.name));
    check('the engine gets it on the hammers only', hammers?.mods?.sustained === 1 && !claws?.mods?.sustained, JSON.stringify({ hammers: hammers?.mods, claws: claws?.mods }));
    await sctx.close();
  }

  // --- the exchange (1.103): the target fights back, overwatch, Deadly Demise; battle-shock odds
  {
    const xctx = await browser.newContext({ ...devices['Pixel 7'] });
    const xp = await xctx.newPage();
    xp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`exchange: ${m.text()}`); });
    xp.on('pageerror', e => consoleErrors.push(`exchange: ${e}`));
    await xp.goto(`${BASE}/calc/`);
    await xp.waitForSelector('textarea[data-side="A"]');
    await xp.fill('textarea[data-side="A"]', SW_LIST); await xp.tap('button[data-action="parse"][data-side="A"]');
    await xp.fill('textarea[data-side="B"]', ORK_LIST); await xp.tap('button[data-action="parse"][data-side="B"]');
    await xp.tap('button[data-action="view"][data-value="attack"]');
    const xdone = () => xp.waitForFunction(() => { const s = window.__calc?.state; return s && !s.busy && s.result; }, null, { timeout: 30000 });
    const xtarget = async (re) => { const v = await xp.$eval('select[data-input="target"]', (sel, src) => [...sel.options].find(o => new RegExp(src).test(o.textContent))?.value, re.source); await xp.selectOption('select[data-input="target"]', v); };
    const chainReady = () => xp.waitForFunction(() => { const s = window.__calc.state; return s.chainResult && !s.chainBusy; }, null, { timeout: 60000 });
    const txt = async (q) => (await xp.textContent(q)).replace(/\s+/g, ' ').trim();
    // battle-shock odds on the result of a plain attack: Thunderwolf Cavalry into the Boyz
    await xp.tap('button[data-action="phase"][data-value="fight"]');
    await xtarget(/Warboss \+ Boyz/);
    await xp.tap('button[data-action="open-add"]'); await xp.tap('.pick:has-text("Thunderwolf Cavalry (1)")'); await xdone();
    await xp.locator('[data-attacker]').last().locator('button[data-key="charged"]').tap(); await xdone();
    await xp.tap('button[data-action="open-results"]');
    await xp.waitForSelector('.sheet #shock-target');
    const res = await xp.evaluate(() => { const r = window.__calc.state.result; return { half: r.killsAtLeast[21 - 10], wipe: r.pWipe }; });
    const shock = await txt('.sheet #shock-target');
    const m = shock.match(/half strength, and still on the table, (\d+|<1|>99)% of the time\. In its next Command phase it then tests on Ld (\d)\+ and fails (\d+)% of the time: battle-shocked (\d+|<1)%/);
    check('the result says how often the target is left at or below half strength, and how often it then fails its battle-shock test', !!m && Math.abs(Number(m[1]) / 100 - (res.half - res.wipe)) < 0.011 && ['6', '7'].includes(m[2]), JSON.stringify({ shock, res }));
    // 21 models (20 Boyz + the Warboss): half strength is 10 or fewer left = 11 or more destroyed
    check('half strength counts the attached Warboss: 11 of 21 models destroyed', res.half > 0 && res.half < 1, JSON.stringify(res));
    await xp.locator('.sheet #shock-target').scrollIntoViewIfNeeded();
    await xp.screenshot({ path: join(SHOTS, 'calc_69_battle_shock.png') });
    await xp.tap('.sheet button[data-action="close-sheet"]');
    // the turn chain with the enemy's part: the Meganobz fight back
    await xtarget(/Meganobz/); await xdone();
    await xp.tap('button[data-action="open-chain"]');
    await xp.waitForSelector('#chain-total', { timeout: 60000 });
    const twKey = await xp.evaluate(() => window.__calc.atkArmy().units.find(u => /Thunderwolf Cavalry \(1\)/.test(u.name)).key);
    await xp.selectOption('select[data-input="chain-charger"]', twKey);
    for (let g = await xp.evaluate(() => window.__calc.state.chain.gap); g > 6; g -= 0.5) await xp.tap('button[data-action="chain-gap"][data-delta="-0.5"]');
    for (let g = await xp.evaluate(() => window.__calc.state.chain.gap); g < 6; g += 0.5) await xp.tap('button[data-action="chain-gap"][data-delta="0.5"]');
    await chainReady();
    await xp.waitForSelector('#chain-own');
    const c1 = await xp.evaluate(() => { const s = window.__calc.state; return { charger: window.__calc.atkArmy().units.find(u => u.key === s.chain.chargerKey)?.name, own: s.chainResult.own, kills: s.chainResult.meanKills, pCharge: s.chainResult.pCharge }; });
    check('the chain reports what the charge costs the charging unit: the Meganobz fight back', /Thunderwolf Cavalry/.test(c1.charger) && c1.own && c1.own.totalModels === 6 && c1.own.meanBack > 0.05 && Math.abs(c1.own.meanLost - c1.own.meanBack) < 1e-9, JSON.stringify(c1));
    check('"What it costs Thunderwolf Cavalry": models lost and the chance the unit is destroyed', /What it costs Thunderwolf Cavalry/.test(await txt('#chain-own')) && (await txt('#chain-own-lost')) === c1.own.meanLost.toFixed(1) && /avg models lost of 6/.test(await txt('#chain-own')), await txt('#chain-own'));
    check('points traded are shown', /Points: you destroy \d+ and lose \d+ on average/.test(await txt('#chain-trade')), await txt('#chain-own'));
    await xp.locator('#chain-own').scrollIntoViewIfNeeded();
    await xp.screenshot({ path: join(SHOTS, 'calc_70_chain_exchange.png') });
    // without the fight back nothing is lost; with Overwatch the unit loses models before it charges
    await xp.tap('button[data-action="chain-back"]'); await chainReady();
    check('"The target fights back" off: no report for your unit', (await xp.locator('#chain-own').count()) === 0);
    await xp.tap('button[data-action="chain-back"]');
    await xp.tap('button[data-action="chain-overwatch"]'); await chainReady();
    await xp.waitForSelector('#chain-own-ow');
    const c2 = await xp.evaluate(() => window.__calc.state.chainResult);
    check('Fire Overwatch (1CP) on: snap shots (6s to hit) at the charging unit, counted before the charge', c2.own.meanOverwatch >= 0 && c2.own.meanOverwatch < 1.5 && c2.own.meanLost >= c1.own.meanLost - 0.05 && /Overwatch/.test(await txt('#chain-own')), JSON.stringify(c2.own));
    await xp.tap('button[data-action="chain-overwatch"]');
    // Deadly Demise: the Battlewagon (D6)
    await xp.tap('.sheet button[data-action="close-sheet"]');
    await xtarget(/Battlewagon/); await xdone();
    await xp.tap('button[data-action="open-chain"]');
    await xp.waitForSelector('#chain-total', { timeout: 60000 });
    await chainReady();
    await xp.waitForSelector('#chain-own-dd');
    check('the charging unit chosen before is kept for the next target', /Thunderwolf Cavalry/.test(await txt('#chain-own')), await txt('#chain-own'));
    const c3 = await xp.evaluate(() => window.__calc.state.chainResult);
    check('a Battlewagon destroyed in the fight: Deadly Demise D6 can hit the charging unit', /Deadly Demise D6/.test(await txt('#chain-own')) && c3.own.meanDemise >= 0 && c3.own.meanDemise <= c3.pWipe, JSON.stringify({ dd: c3.own.meanDemise, wipe: c3.pWipe }));
    await xctx.close();
  }

  // --- weapon choice (choose.mjs): the best legal weapons and profiles against the target, whatever the unit
  {
    const wctx = await browser.newContext({ ...devices['Pixel 7'] });
    const wp = await wctx.newPage();
    wp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`choice: ${m.text()}`); });
    wp.on('pageerror', e => consoleErrors.push(`choice: ${e}`));
    await wp.goto(`${BASE}/calc/`);
    await wp.waitForSelector('textarea[data-side="A"]');
    await wp.fill('textarea[data-side="A"]', SW_LIST); await wp.tap('button[data-action="parse"][data-side="A"]');
    await wp.fill('textarea[data-side="B"]', ORK_LIST); await wp.tap('button[data-action="parse"][data-side="B"]');
    await wp.tap('button[data-action="view"][data-value="attack"]');
    await wp.tap('button[data-action="phase"][data-value="fight"]');
    const pickTarget = async (re) => {
      const v = await wp.$eval('select[data-input="target"]', (sel, src) => [...sel.options].find(o => new RegExp(src).test(o.textContent))?.value, re.source);
      await wp.selectOption('select[data-input="target"]', v);
    };
    const rowsOf = (card) => card.locator('.weapon[data-row]').evaluateAll(els => els.map(e => ({
      name: e.querySelector('.wname').textContent.trim(), val: e.querySelector('.stepper .val').textContent.trim(),
      auto: !!e.querySelector('.tag.auto'), hand: !!e.querySelector('.tag.byhand'), blocked: e.querySelector('.tag.warn')?.textContent.trim() ?? null,
      why: e.querySelector('.choice-why')?.textContent.trim() ?? null })));
    const row = (rows, re) => rows.find(r => re.test(r.name));
    // Wulfen against Boyz: before 1.100 the app picked the Hunter profile, blocked it, and no hammer attacked
    await pickTarget(/Warboss \+ Boyz/);
    await wp.tap('button[data-action="open-add"]');
    await wp.tap('.pick:has-text("Wulfen with Storm Shields")');
    await settle(wp);
    const wulfen = wp.locator('[data-attacker]').last();
    let rs = await rowsOf(wulfen);
    check('Wulfen vs Boyz: all 10 thunder hammers attack with the normal profile (chosen by the app)',
      row(rs, /Hammer – Melee/).val === '10/10' && row(rs, /Hammer – Melee/).auto && row(rs, /Hammer – Hunter/).val === '0/10', JSON.stringify(rs));
    check('the Hunter profile says why it is not used: it only targets Monster or Vehicle units',
      row(rs, /Hammer – Hunter/).blocked === 'Hunter profile: only targets Monster or Vehicle units', JSON.stringify(row(rs, /Hunter/)));
    const scW = await wp.evaluate(() => window.__calc.scenario());
    check('the engine gets the 10 hammers (2 attacks each)', scW.attackers[0].weapons.some(w => /Thunder Hammer – Melee/.test(w.name) && w.count === 10), JSON.stringify(scW.attackers[0].weapons.map(w => [w.name, w.count])));
    const killsBoyz = await wp.evaluate(() => window.__calc.state.result.meanKills);
    check('Wulfen now kill well over 5 Boyz on average (it was 2.6 with the Captain alone)', killsBoyz > 5, String(killsBoyz));
    await wp.evaluate(() => document.querySelector('[data-attacker]').scrollIntoView());
    await wp.screenshot({ path: join(SHOTS, 'calc_60_choice_wulfen_boyz.png') });
    // the same unit against a Vehicle: the Hunter profile, without the user doing anything
    await pickTarget(/Battlewagon/);
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('Wulfen vs Battlewagon: the Hunter profile is used for all 10 (chosen by the app)',
      row(rs, /Hammer – Hunter/).val === '10/10' && row(rs, /Hammer – Hunter/).auto && row(rs, /Hammer – Melee/).val === '0/10' && /at least as good in every way/.test(row(rs, /Hammer – Melee/).why ?? ''), JSON.stringify(rs));
    await wp.screenshot({ path: join(SHOTS, 'calc_61_choice_wulfen_wagon.png') });
    // by hand: one model takes the normal profile -> the Hunter count goes down with it (10 hammers in all)
    await wp.locator('[data-attacker]').last().locator('.weapon', { hasText: 'Hammer – Melee' }).locator('button[data-delta="1"]').tap();
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('by hand: +1 on the normal profile takes one from the Hunter profile (1 + 9), both marked "set by hand"',
      row(rs, /Hammer – Melee/).val === '1/10' && row(rs, /Hammer – Hunter/).val === '9/10' && row(rs, /Hammer – Melee/).hand && row(rs, /Hammer – Hunter/).hand, JSON.stringify(rs));
    // a count set by hand is for that target: against the Boyz the app chooses again (no "0 hammers" trap)
    await pickTarget(/Warboss \+ Boyz/);
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('a new target: the app chooses again (10 normal), the hand-set split is not carried over',
      row(rs, /Hammer – Melee/).val === '10/10' && row(rs, /Hammer – Melee/).auto, JSON.stringify(rs));
    await pickTarget(/Battlewagon/);
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('back on the Battlewagon the hand-set split is still there, with the way back to "auto"',
      row(rs, /Hammer – Melee/).val === '1/10' && (await wp.locator('button[data-action="count-auto"]').count()) === 1, JSON.stringify(rs));
    await wp.tap('button[data-action="count-auto"]');
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('"Let the app choose again" restores the choice', row(rs, /Hammer – Hunter/).val === '10/10' && row(rs, /Hammer – Hunter/).auto, JSON.stringify(rs));
    // Logan Grimnar: Sweep against the horde, Strike against the vehicle - with the numbers behind it
    await wp.locator('[data-attacker]').last().locator('button[data-action="remove"]').tap();
    await pickTarget(/Warboss \+ Boyz/);
    await wp.tap('button[data-action="open-add"]');
    await wp.tap('.pick:has-text("Logan Grimnar")');
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    const sweep = row(rs, /Sweep/), strike = row(rs, /Strike/);
    const num = (s) => Number((s ?? '').match(/about ([\d.]+) wounds/)?.[1]);
    check('Logan vs Boyz: Sweep is used, Strike is not, and both rows show what they would do',
      sweep.val === '1/1' && sweep.auto && strike.val === '0/1' && /^Used/.test(sweep.why) && /^Not used/.test(strike.why) && num(sweep.why) > num(strike.why) + 2, JSON.stringify({ sweep, strike }));
    check('his squad is not part of that choice: 9 hammers and the lightning claws attack', row(rs, /^Thunder Hammer$/).val === '9/9' && row(rs, /Lightning Claws/).val === '1/1' && !row(rs, /^Thunder Hammer$/).auto, JSON.stringify(rs));
    await wp.evaluate(() => document.querySelector('[data-attacker]').scrollIntoView());
    await wp.screenshot({ path: join(SHOTS, 'calc_62_choice_logan_boyz.png') });
    await pickTarget(/Battlewagon/);
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('Logan vs Battlewagon: Strike', row(rs, /Strike/).val === '1/1' && row(rs, /Strike/).auto && row(rs, /Sweep/).val === '0/1', JSON.stringify(rs));
    // shooting: krak at the vehicle, frag at the horde
    await wp.tap('button[data-action="phase"][data-value="shooting"]');
    await pickTarget(/Battlewagon/);
    await wp.tap('button[data-action="open-add"]');
    await wp.tap('.pick:has-text("Scout Squad (1)")');
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('Scouts vs Battlewagon: the missile launcher fires krak', row(rs, /Krak/).val === '1/1' && row(rs, /Frag/).val === '0/1', JSON.stringify(rs));
    await pickTarget(/Warboss \+ Boyz/);
    await settle(wp);
    rs = await rowsOf(wp.locator('[data-attacker]').last());
    check('Scouts vs Boyz: frag; pistols stay out while the other weapons fire (24.07)', row(rs, /Frag/).val === '1/1' && row(rs, /Krak/).val === '0/1' && row(rs, /Bolt Pistol/).val === '0/5', JSON.stringify(rs));
    check('the card explains the choice once', /uses the option that removes the most wounds from this target/.test(await wp.locator('[data-attacker]').last().locator('.choice-foot').textContent()));
    // the matchup grid makes the same choice (in the worker)
    await wp.tap('button[data-action="phase"][data-value="fight"]');
    const cell = await wp.evaluate(async () => {
      const { simulate } = await import('/calc/engine.mjs');
      const { resolveScenario } = await import('/calc/choose.mjs');
      const st = window.__calc.state;
      const wulfen = st.armies.A.units.find(u => /Wulfen/.test(u.name)), boyz = st.armies.B.units.find(u => /Boyz/.test(u.name));
      const sc = window.__calc.defaultScenario(wulfen, boyz);
      const out = resolveScenario(sc);
      return { deferred: !!sc.attackers[0].choice || sc.attackers[0].weapons.some(w => /– Melee/.test(w.name)), weapons: out.attackers[0].weapons.map(w => [w.name, w.count]), kills: simulate({ ...out, trials: 2000 }).meanKills };
    });
    check('grid / forecast odds: Wulfen vs Boyz use the 10 hammers too', cell.weapons.some(([n, c]) => /Thunder Hammer – Melee/.test(n) && c === 10) && cell.kills > 5, JSON.stringify(cell));
    await wctx.close();
  }

  // --- my army, phase by phase (1.104): Intel > By phase, once-per-battle ticks
  {
    const pctx = await browser.newContext({ ...devices['Pixel 7'] });
    const pp = await pctx.newPage();
    pp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`phase sheet: ${m.text()}`); });
    pp.on('pageerror', e => consoleErrors.push(`phase sheet: ${e}`));
    await pp.goto(`${BASE}/calc/`);
    await pp.waitForSelector('textarea[data-side="A"]');
    await pp.fill('textarea[data-side="A"]', SW_LIST); await pp.tap('button[data-action="parse"][data-side="A"]');
    await pp.fill('textarea[data-side="B"]', ORK_LIST); await pp.tap('button[data-action="parse"][data-side="B"]');
    await pp.tap('button[data-action="view"][data-value="intel"]');
    await pp.waitForSelector('#intel-mode');
    const txt = async (q) => (await pp.textContent(q)).replace(/\s+/g, ' ').trim();
    const names = (phase, strat = false) => pp.$$eval(`.phase-card[data-phase="${phase}"] ${strat ? 'details' : ':scope > '} .sheet-entry > b`.replace(':scope >  ', ''), els => els.map(e => e.textContent.trim()));
    // the datasheets are the enemy's (as before); the army rule is now on its card
    // the matchup brief: what their list has that you plan around
    const trick = await txt('#brief-tricks');
    check('brief: "Plan around" names the Ork unit with a Torrent weapon and its range', /Torrent in overwatch Meganobz \(.* 6"\)/.test(trick) && /hit automatically \(24\.37\)/.test(trick) && (await pp.locator('#brief-tricks [data-trick]').count()) === 1 && /Plan around \(1\)/.test(await txt('details[data-details="brief-tricks"] > summary')), trick);
    await pp.locator('#brief-tricks').scrollIntoViewIfNeeded();
    await pp.screenshot({ path: join(SHOTS, 'calc_74_brief_tricks.png') });
    check('Intel opens on the enemy datasheets, with its army rule', /B · Orks/.test(await txt('.seg button.on[data-action="intel-side"]')) && /Army rule: Waaagh!/.test(await txt('#intel-army-rule > summary')), await txt('#intel-army-rule > summary'));
    await pp.tap('button[data-action="intel-mode"][data-value="phase"]');
    await pp.waitForSelector('#phase-sheet');
    check('"By phase" shows YOUR army first', /A · Space Wolves/.test(await txt('.seg button.on[data-action="intel-side"]')) && /Space Wolves, phase by phase/.test(await txt('#phase-sheet .title')), await txt('#phase-sheet .title'));
    const strip = await pp.$$eval('#phase-strip .chip', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim()));
    check('a chip per phase with the number of rules', strip.length === 9 && /^All 52$/.test(strip[0]) && /^Command 6$/.test(strip[2]) && /^Fight 16$/.test(strip[6]) && /^Opp\. turn 17$/.test(strip[7]), strip.join(' | '));
    // once per battle: the three doctrines, and the extra Assault doctrine of Assault Mastery
    const ticks = await pp.$$eval('#once-card .chip.tick', els => els.map(e => e.textContent.trim()));
    check('once per battle: each combat doctrine, plus the additional Assault doctrine from Assault Mastery', ticks.join('|') === 'Assault doctrine|Assault doctrine (Assault Mastery)|Devastator doctrine|Tactical doctrine' && /4 of 4/.test(await txt('#once-left')), ticks.join('|'));
    // one phase at a time
    await pp.tap('#phase-strip button[data-value="fight"]');
    await pp.waitForFunction(() => document.querySelectorAll('.phase-card').length === 1);
    const fight = await pp.$$eval('.phase-card[data-phase="fight"] > .sheet-entry > b', els => els.map(e => e.textContent.trim()));
    check('Fight phase: the rules that work after a charge are there, with their units', ['Thunderous Charge', 'Terminatus Assault', 'Full-throttle Assault', 'Into the Fray', 'Legendary Slayers (Saga of the Beastslayer)'].every(n => fight.includes(n)) && /Thunderwolf Cavalry/.test(await txt('.sheet-entry[data-entry="ab:thunderous-charge"]')), fight.join(' | '));
    const fstr = await pp.$$eval('.phase-card[data-phase="fight"] details .sheet-entry > b', els => els.map(e => e.textContent.trim()));
    check('Fight phase stratagems are open when one phase is shown', fstr.includes('EPIC CHALLENGE') && fstr.includes('ARMOUR OF CONTEMPT') && await pp.$eval('.phase-card[data-phase="fight"] details', d => d.open), fstr.join(' | '));
    await pp.screenshot({ path: join(SHOTS, 'calc_71_phase_fight.png') });
    await pp.tap('#phase-strip button[data-value="enemy"]');
    await pp.waitForSelector('.phase-card[data-phase="enemy"]');
    const opp = await pp.$$eval('.phase-card[data-phase="enemy"] details .sheet-entry > b', els => els.map(e => e.textContent.trim()));
    check('the opponent’s turn: reactions in the order of their turn', opp[0] === 'FIRE OVERWATCH' && opp.includes('COUNTEROFFENSIVE') && opp.includes('HEROIC INTERVENTION') && opp.indexOf('FIRE OVERWATCH') < opp.indexOf('SMOKESCREEN') && opp.indexOf('SMOKESCREEN') < opp.indexOf('COUNTEROFFENSIVE'), opp.join(' | '));
    // ticks: used ones are kept with the game, and a new game clears them
    await pp.tap('#phase-strip button[data-value="command"]');
    await pp.waitForSelector('.phase-card[data-phase="command"]');
    check('Command phase: the army rule first, with its ticks in place', (await pp.$$eval('.phase-card[data-phase="command"] > .sheet-entry > b', els => els.map(e => e.textContent.trim())))[0] === 'Combat Doctrines' && (await pp.locator('.phase-card[data-phase="command"] .sheet-entry[data-entry="army:combat-doctrines"] .chip.tick').count()) === 4 && /ASSAULT DOCTRINE: When this unit/.test(await txt('.sheet-entry[data-entry="army:combat-doctrines"] .ruletext')));
    await pp.locator('.phase-card[data-phase="command"] .chip.tick', { hasText: 'Devastator doctrine' }).tap();
    await pp.waitForFunction(() => /3 of 4/.test(document.querySelector('#once-left')?.textContent ?? ''));
    const pressed = await pp.$$eval('#once-card .chip.tick', els => els.map(e => e.getAttribute('aria-pressed')));
    check('a tick marks the doctrine as used, in the list at the top too', pressed.join() === 'false,false,true,false' && (await pp.locator('#once-reset').count()) === 1, pressed.join());
    await pp.evaluate(() => window.scrollTo(0, 0));
    await pp.screenshot({ path: join(SHOTS, 'calc_72_phase_once.png') });
    await pp.reload();
    await pp.waitForSelector('#phase-sheet');
    check('after a reload: still "By phase", the Command phase, and the tick', /3 of 4/.test(await txt('#once-left')) && (await pp.locator('.phase-card').count()) === 1 && (await pp.getAttribute('.phase-card', 'data-phase')) === 'command');
    // the opponent's army: Waaagh! once per battle
    await pp.tap('button[data-action="intel-side"][data-value="B"]');
    await pp.waitForFunction(() => /Orks, phase by phase/.test(document.querySelector('#phase-sheet .title')?.textContent ?? ''));
    check('the enemy army by phase: Waaagh! is once per battle', /Waaagh!/.test(await txt('#once-card')) && /1 of 1/.test(await txt('#once-left')), await txt('#once-card'));
    await pp.tap('#phase-strip button[data-value="enemy"]');
    await pp.waitForSelector('.phase-card[data-phase="enemy"]');
    const def = await pp.$$eval('.phase-card[data-phase="enemy"] > .sheet-entry > b', els => els.map(e => e.textContent.trim()));
    check('what protects the Orks when you attack them', ['Arrogant Invulnerability', 'Mobile Fortress', 'Deadly Demise D6', 'Feel No Pain 6+'].every(n => def.includes(n)), def.join(' | '));
    await pp.tap('button[data-action="intel-side"][data-value="A"]');
    await pp.waitForFunction(() => /Space Wolves, phase by phase/.test(document.querySelector('#phase-sheet .title')?.textContent ?? ''));
    // seen from the other side of the table: the Space Wolves list has three things to plan around
    await pp.tap('button[data-action="view"][data-value="mission"]');
    await pp.waitForSelector('button[data-action="mission-me"][data-value="B"]');
    await pp.tap('button[data-action="mission-me"][data-value="B"]');
    await pp.tap('button[data-action="view"][data-value="intel"]');
    await pp.tap('button[data-action="intel-mode"][data-value="units"]');
    await pp.waitForSelector('#brief-tricks');
    const tr2 = await pp.$$eval('#brief-tricks [data-trick]', els => els.map(e => `${e.dataset.trick}: ${e.querySelector('.tiny').textContent.trim()}`));
    check('as the Ork player: Deep Strike, Infiltrators and Scouts of the Space Wolves list', tr2.join(' | ') === 'deepStrike: Logan Grimnar + Ancient in Terminator Armour + Terminator Assault Squad | infiltrators: Scout Squad ×2 | scouts: Scout Squad 6" ×2', tr2.join(' | '));
    await pp.locator('#brief-tricks').scrollIntoViewIfNeeded();
    await pp.screenshot({ path: join(SHOTS, 'calc_75_brief_tricks_sw.png') });
    await pp.tap('button[data-action="view"][data-value="mission"]');
    await pp.tap('button[data-action="mission-me"][data-value="A"]');
    await pp.tap('button[data-action="view"][data-value="intel"]');
    await pp.tap('button[data-action="intel-mode"][data-value="phase"]');
    await pp.waitForSelector('#phase-sheet');
    // a new game clears the ticks
    await pp.tap('button[data-action="view"][data-value="mission"]');
    await pp.tap('button[data-action="mission-tab"][data-value="play"]');
    await pp.waitForSelector('#play-reset');
    await pp.locator('#play-reset').scrollIntoViewIfNeeded();
    pp.once('dialog', d => d.accept());
    await pp.tap('#play-reset');
    await pp.tap('button[data-action="view"][data-value="intel"]');
    await pp.waitForSelector('#phase-sheet');
    check('a new game clears the once-per-battle ticks', /4 of 4/.test(await txt('#once-left')) && (await pp.locator('#once-reset').count()) === 0, await txt('#once-left'));
    // table mode keeps the sheet (rules reference), all phases
    await pp.tap('#phase-strip button[data-value="all"]');
    await pp.waitForFunction(() => document.querySelectorAll('.phase-card').length === 8);
    check('all phases: 8 cards, stratagems folded', (await pp.locator('.phase-card').count()) === 8 && !(await pp.$eval('.phase-card[data-phase="fight"] details', d => d.open)));
    await pctx.close();
  }
  // tablet, landscape: the sheet uses the width
  {
    const tctx = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
    const tp = await tctx.newPage();
    tp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`phase sheet tablet: ${m.text()}`); });
    tp.on('pageerror', e => consoleErrors.push(`phase sheet tablet: ${e}`));
    await tp.goto(`${BASE}/calc/`);
    await tp.waitForSelector('textarea[data-side="A"]');
    await tp.fill('textarea[data-side="A"]', SW_LIST); await tp.tap('button[data-action="parse"][data-side="A"]');
    await tp.tap('button[data-action="view"][data-value="intel"]');
    await tp.tap('button[data-action="intel-mode"][data-value="phase"]');
    await tp.waitForSelector('#phase-sheet');
    check('one army loaded: the sheet works without an opponent', /Space Wolves, phase by phase/.test(await tp.textContent('#phase-sheet .title')) && (await tp.locator('.phase-card').count()) === 8);
    await tp.screenshot({ path: join(SHOTS, 'calc_73_phase_tablet.png') });
    await tctx.close();
  }

  // --- board overlays (1.105): where reserves can arrive, and from how far a hidden unit is seen
  {
    const octx = await browser.newContext({ ...devices['Pixel 7'] });
    const op = await octx.newPage();
    op.on('console', m => { if (m.type() === 'error') consoleErrors.push(`board overlays: ${m.text()}`); });
    op.on('pageerror', e => consoleErrors.push(`board overlays: ${e}`));
    await op.goto(`${BASE}/calc/`);
    await op.waitForSelector('textarea[data-side="A"]');
    await op.fill('textarea[data-side="A"]', SW_LIST); await op.tap('button[data-action="parse"][data-side="A"]');
    await op.fill('textarea[data-side="B"]', ORK_LIST); await op.tap('button[data-action="parse"][data-side="B"]');
    await op.tap('button[data-action="view"][data-value="board"]');
    await op.waitForSelector('#board-svg');
    const oTokens = () => op.evaluate(() => window.__calc.board().tokens);
    const oScreen = (x, y) => op.evaluate(([bx, by]) => { const svg = document.getElementById('board-svg'); const pt = svg.createSVGPoint(); pt.x = bx; pt.y = by; const q = pt.matrixTransform(svg.getScreenCTM()); return { x: q.x, y: q.y }; }, [x, y]);
    const oPlace = (tk, x, y) => op.evaluate(([t, px, py]) => { const p = window.__calc.board().plan; Object.assign(p.steps[p.cur].tokens[t], { x: px, y: py, rot: 0 }); }, [tk, x, y]);
    const oSelect = async (tk) => {
      await op.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
      const e = await oScreen(43.5, 59.5); await op.mouse.click(e.x, e.y);
      const t = (await oTokens()).find(x => x.tk === tk); const q = await oScreen(t.x, t.y); await op.mouse.click(q.x, q.y);
    };
    const otxt = async (q) => (await op.textContent(q)).replace(/\s+/g, ' ').trim();
    // every Ork unit on the board; of the Space Wolves the Grey Hunters and a Scout Squad (the Terminators stay in reserves)
    for (const n of ['Warboss + Boyz', 'Beastboss', 'Meganobz', 'Flash Gitz', 'Battlewagon']) await op.locator('button[data-action="board-place"][data-side="B"]', { hasText: n }).first().tap();
    await op.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    await op.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Scout Squad (1)' }).tap();
    const toks = await oTokens();
    const sc = toks.filter(t => t.tk.startsWith('A:'))[1];
    check('7 units placed', toks.length === 7, String(toks.length));
    // where the reserves of A (Space Wolves) can arrive
    await op.locator('button[data-action="board-arrive"][data-value="A"]').tap();
    await op.waitForSelector('#board-svg #arrive-layer[data-for="A"]');
    const lay = await op.$eval('#arrive-layer', g => ({ round: g.dataset.round, closed: g.dataset.closed, blocked: Number(g.dataset.blocked), ds: !!g.querySelector('[data-arr="deep-strike"]'), edge: !!g.querySelector('[data-arr="edge"]') }));
    check('overlay for the Space Wolves at Deploy: battle round 2, edge band and Deep Strike area, the Ork zone still closed, 8" around each of the 31 Ork models', lay.round === '2' && lay.closed === '1' && lay.ds && lay.edge && lay.blocked === 31, JSON.stringify(lay));
    const note = await otxt('#board-arrive-note');
    check('the note names the rules and the units still in reserves, Deep Strike marked', /Battle round 2 \(the first round reserves can arrive\)/.test(note) && /wholly within 6" of an edge/.test(note) && /not in B's deployment zone before round 3 \(20\.04\)/.test(note) && /anywhere for a Deep Strike unit \(24\.09\)/.test(note) && /Not on the board in this step: .*Logan Grimnar.*\(Deep Strike\)/.test(note), note);
    // the drawing agrees with the rule: next to an Ork model nothing arrives; far from them a Deep Strike unit does
    const probe = await op.evaluate(async () => {
      const E = await import('/calc/planeval.mjs');
      const d = window.__calc.board();
      const ork = d.units.find(u => u.tk.startsWith('B:'));
      const m = ork.models[0], r = 0.63;
      const z = d.arrive.zones;
      // the point of the board farthest from every Ork model, on a 1" grid
      let far = null;
      for (let x = 1; x < 44; x++) for (let y = 1; y < 60; y++) { const dmin = Math.min(...z.blocked.map(b => Math.hypot(x - b.x, y - b.y) - b.r)); if (!far || dmin > far.d) far = { x, y, d: dmin }; }
      return { near: E.canArrive(ork.x + m.dx + 4, ork.y + m.dy, r, z, { deepStrike: true, enemyZone: d.arrive.zone }), far: E.canArrive(far.x, far.y, r, z, { deepStrike: true, enemyZone: d.arrive.zone }), farD: far.d,
        inZone: (() => { const zc = d.arrive.zone; const cx = zc.reduce((s, q) => s + q[0], 0) / zc.length, cy = zc.reduce((s, q) => s + q[1], 0) / zc.length; return { x: cx, y: cy }; })() };
    });
    check('4" from an Ork model: no; the spot farthest from all of them: yes for a Deep Strike unit', probe.near.ok === false && /within 8"/.test(probe.near.why) && probe.far.ok === true && probe.farD > 0, JSON.stringify(probe));
    await op.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
    await op.screenshot({ path: join(SHOTS, 'calc_76_board_arrive.png') });
    // three turns on: round 3, the enemy deployment zone opens to units without Deep Strike
    for (let i = 0; i < 3; i++) await op.locator('button[data-action="board-step-add"]').tap();
    await op.waitForFunction(() => document.querySelector('#arrive-layer')?.dataset.round === '3');
    check('Turn 3: battle round 3, the enemy deployment zone is open', (await op.getAttribute('#arrive-layer', 'data-closed')) === '0' && !/before round 3/.test(await otxt('#board-arrive-note')), await otxt('#board-arrive-note'));
    // the Orks have no Deep Strike unit and are all on the board
    await op.locator('button[data-action="board-arrive"][data-value="B"]').tap();
    await op.waitForSelector('#board-svg #arrive-layer[data-for="B"]');
    const noteB = await otxt('#board-arrive-note');
    check('for the Orks: edge band only, and the note says why', (await op.locator('#arrive-layer [data-arr="deep-strike"]').count()) === 0 && (await op.locator('#arrive-layer [data-arr="edge"]').count()) === 1 && /B has no Deep Strike unit/.test(noteB) && /All of B's units are on the board in this step/.test(noteB), noteB);
    await op.locator('button[data-action="board-arrive"][data-value="off"]').tap();
    await op.waitForFunction(() => !document.querySelector('#arrive-layer'));
    check('Off removes the overlay', (await op.locator('#board-arrive-note').count()) === 0);
    // from how far a unit that can be Hidden is seen: the Scouts in a terrain area with a light or dense feature
    const hide = await op.evaluate(async (tk) => {
      const S = await import('/calc/sight.mjs');
      const B = await import('/calc/board.mjs');
      const { LAYOUTS } = await import('/calc/terrain-11e.mjs');
      const d = window.__calc.board();
      const l = LAYOUTS.find(x => x.id === d.layout);
      const u = d.units.find(x => x.tk === tk);
      for (const a of l.pieces.filter(p => p.cls === 'area')) {
        const cx = a.poly.reduce((s, q) => s + q[0], 0) / a.poly.length, cy = a.poly.reduce((s, q) => s + q[1], 0) / a.poly.length;
        for (const per of [5, 3, 2, 1]) {
          const cand = { x: cx, y: cy, keywords: u.keywords, models: B.coherentFormation([{ count: u.models.length, fp: u.models[0].fp }], { perRow: per, keepRows: true }) };
          if (S.canHide(cand, l.pieces)) return { x: cx, y: cy, per };
        }
      }
      return null;
    }, sc.tk);
    await oPlace(sc.tk, hide.x, hide.y);
    await op.evaluate(([t, per]) => { const p = window.__calc.board().plan; p.steps[p.cur].tokens[t].per = per; }, [sc.tk, hide.per]);
    await oSelect(sc.tk);
    await op.waitForSelector('#board-panel button[data-action="board-ring"][data-k="detect"]');
    check('a unit that can be Hidden offers its detection ring', /Seen only within 15" while Hidden/.test(await otxt('#board-panel button[data-action="board-ring"][data-k="detect"]')));
    await op.locator('#board-panel button[data-action="board-ring"][data-k="detect"]').tap();
    await op.waitForSelector('#board-svg [data-ring="detect"]');
    const ring = await op.$eval('#board-svg [data-ring="detect"]', g => ({ r: g.dataset.r, n: g.querySelectorAll('circle').length, radius: Number(g.querySelector('circle').getAttribute('r')) }));
    const scBase = await op.evaluate((tk) => window.__calc.board().units.find(x => x.tk === tk).models[0].fp.r, sc.tk);
    check('the ring is drawn 15" from the base of every model of the unit', ring.r === '15' && ring.n === 5 && Math.abs(ring.radius - (15 + scBase)) < 0.01, JSON.stringify({ ...ring, base: scBase }));
    await op.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
    await op.screenshot({ path: join(SHOTS, 'calc_77_board_detect.png') });
    // the Grey Hunters in the open have no such ring
    const ghTk = toks.filter(t => t.tk.startsWith('A:'))[0].tk;
    await oPlace(ghTk, 22, 30);
    await oSelect(ghTk);
    await op.waitForSelector('#board-panel');
    const canHideGh = await op.evaluate(async (tk) => { const S = await import('/calc/sight.mjs'); const { LAYOUTS } = await import('/calc/terrain-11e.mjs'); const d = window.__calc.board(); const u = d.units.find(x => x.tk === tk); return S.canHide(u, LAYOUTS.find(x => x.id === d.layout).pieces); }, ghTk);
    check('a unit that cannot be Hidden where it stands has no detection ring', canHideGh || (await op.locator('#board-panel button[data-action="board-ring"][data-k="detect"]').count()) === 0, `canHide=${canHideGh}`);
    await octx.close();
  }

  // --- going first / going second (1.105): two versions of a board plan from one deployment
  {
    const sctx = await browser.newContext({ ...devices['Pixel 7'] });
    const sp = await sctx.newPage();
    sp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`plan versions: ${m.text()}`); });
    sp.on('pageerror', e => consoleErrors.push(`plan versions: ${e}`));
    await sp.goto(`${BASE}/calc/`);
    await sp.waitForSelector('textarea[data-side="A"]');
    await sp.fill('textarea[data-side="A"]', SW_LIST); await sp.tap('button[data-action="parse"][data-side="A"]');
    await sp.fill('textarea[data-side="B"]', ORK_LIST); await sp.tap('button[data-action="parse"][data-side="B"]');
    await sp.tap('button[data-action="view"][data-value="board"]');
    await sp.waitForSelector('#board-svg');
    const stxt = async (q) => (await sp.textContent(q)).replace(/\s+/g, ' ').trim();
    for (const n of ['Grey Hunters', 'Thunderwolf Cavalry (1)', 'Scout Squad (1)']) await sp.locator('button[data-action="board-place"][data-side="A"]', { hasText: n }).tap();
    for (const n of ['Warboss + Boyz', 'Meganobz', 'Flash Gitz']) await sp.locator('button[data-action="board-place"][data-side="B"]', { hasText: n }).first().tap();
    await sp.locator('button[data-action="board-step-add"]').tap();          // Turn 1
    await sp.locator('button[data-action="board-step"][data-i="0"]').tap();  // back to Deploy
    // one tap: this plan is the going-first version, a copy is the going-second version
    await sp.locator('#board-plan-split').scrollIntoViewIfNeeded();
    await sp.locator('#board-plan-split').tap();
    await sp.waitForSelector('#board-split-note');
    const chips = await sp.$$eval('#board-variants button[data-action="board-plan-pick"]', els => els.map(e => `${e.textContent.trim()}${e.classList.contains('on') ? '*' : ''}`));
    check('the plan is split into "Going first" (kept on screen) and "Going second"', chips.join('|') === 'Going first*|Going second' && (await sp.locator('#board-plan-split').count()) === 0, chips.join('|'));
    check('both versions start from the same deployment, and the note says why', (await sp.getAttribute('#board-split-note', 'data-same')) === '1' && /you deploy before the roll-off for the first turn/.test(await stxt('#board-split-note')), await stxt('#board-split-note'));
    // the going-second version: move a unit in its Deploy step -> the deployments differ -> one tap makes them the same
    await sp.locator('#board-variants button[data-action="board-plan-pick"][data-i="1"]').tap();
    const moved = await sp.evaluate(() => { const p = window.__calc.board().plan; const tk = Object.keys(p.steps[0].tokens).find(k => k.startsWith('A:')); p.steps[0].tokens[tk].x += 3; return { tk, x: p.steps[0].tokens[tk].x }; });
    await sp.locator('button[data-action="board-step"][data-i="0"]').tap();
    await sp.waitForSelector('#board-split-note[data-same="0"]');
    check('a different deployment in the second version is flagged', /⚠ The deployment differs/.test(await stxt('#board-split-note')) && (await sp.locator('#board-plan-sync').count()) === 1, await stxt('#board-split-note'));
    await sp.locator('#board-split-note').scrollIntoViewIfNeeded();
    await sp.screenshot({ path: join(SHOTS, 'calc_78_plan_versions.png') });
    await sp.locator('#board-plan-sync').tap();
    await sp.waitForSelector('#board-split-note[data-same="1"]');
    await sp.locator('#board-variants button[data-action="board-plan-pick"][data-i="0"]').tap();
    const firstX = await sp.evaluate((tk) => window.__calc.board().plan.steps[0].tokens[tk].x, moved.tk);
    check('"Use this deployment in both" copies it to the going-first version', Math.abs(firstX - moved.x) < 1e-9, `${firstX} vs ${moved.x}`);
    // Turn 1 differs: going second, the Thunderwolves hold back 6"
    await sp.locator('#board-variants button[data-action="board-plan-pick"][data-i="1"]').tap();
    await sp.locator('button[data-action="board-step"][data-i="1"]').tap();
    await sp.evaluate(() => { const p = window.__calc.board().plan; for (const [k, t] of Object.entries(p.steps[1].tokens)) if (k.startsWith('A:')) t.y = Math.max(3, t.y - 2); });
    await sp.locator('button[data-action="board-step"][data-i="1"]').tap();
    // Mission: each version is forecast with its own first turn, and the roll-off row is their average
    await sp.tap('button[data-action="view"][data-value="mission"]');
    await sp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.pairsReady && (m.compare?.length ?? 0) >= 3; }, null, { timeout: 180000 });
    await sp.waitForSelector('#fc-compare tr[data-when="second"]');
    const cmp = await sp.evaluate(() => {
      const m = window.__calc.mission();
      const row = (w) => { const tr = document.querySelector(`#fc-compare tr[data-when="${w}"]`); return { text: tr.textContent.replace(/\s+/g, ' ').trim(), key: tr.dataset.plan }; };
      const win = (key) => m.compare.find(c => c.key === key).result.pWinA;
      const f = row('first'), s = row('second');
      return { f, s, wf: win(f.key), ws: win(s.key), roll: Number(document.querySelector('#fc-rolloff').dataset.win), rollText: document.querySelector('#fc-rolloff').textContent.replace(/\s+/g, ' ').trim(), note: document.querySelector('#fc-rolloff-note').textContent };
    });
    check('"Your plans compared" marks each version with its first turn', /Board: Going first · you go first/.test(cmp.f.text) && /Board: Going second · you go second/.test(cmp.s.text), JSON.stringify([cmp.f.text, cmp.s.text]));
    check('the roll-off row is the average of the two versions', Math.abs(cmp.roll - (cmp.wf + cmp.ws) / 2) < 1e-4 && /Roll-off: half your games each way/.test(cmp.rollText) && /winner of the roll-off takes the first turn/.test(cmp.note), JSON.stringify(cmp));
    // with the going-first version as the source of the forecast, the forecast has me take the first turn
    await sp.locator('button[data-action="mission-source"][data-value="0"]').scrollIntoViewIfNeeded();
    await sp.locator('button[data-action="mission-source"][data-value="0"]').tap();
    await sp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.params?.first === 'A'; }, null, { timeout: 120000 });
    check('forecast from the going-first version: I take the first turn, and the page says so', /your going first version: the forecast has you take the first turn/.test(await stxt('#fc-first-tag')) && (await sp.locator('#fc-first').count()) === 0, await stxt('#fc-first-tag'));
    await sp.locator('button[data-action="mission-source"][data-value="1"]').tap();
    await sp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.params?.first === 'B'; }, null, { timeout: 120000 });
    check('forecast from the going-second version: the opponent takes the first turn', /your going second version: the forecast has your opponent take the first turn/.test(await stxt('#fc-first-tag')));
    await sp.locator('#fc-compare').scrollIntoViewIfNeeded();
    await sp.screenshot({ path: join(SHOTS, 'calc_79_plan_versions_forecast.png') });
    // once the first turn is known, it wins over the label of the plan
    await sp.locator('button[data-action="mission-first"][data-value="A"]').first().scrollIntoViewIfNeeded();
    await sp.locator('button[data-action="mission-first"][data-value="A"]').first().tap();
    await sp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.first === 'A' && m.params?.first === 'A' && (m.compare?.length ?? 0) >= 3; }, null, { timeout: 120000 });
    check('first turn known (A): no roll-off row, the versions keep a plain label', (await sp.locator('#fc-rolloff').count()) === 0 && /made for going second/.test(await stxt('#fc-compare tr[data-when="second"]')) && (await sp.locator('#fc-first-tag').count()) === 0, await stxt('#fc-compare'));
    await sctx.close();
  }

  // --- event aids (1.106): layout cycle, each round's result, 15VP per round, Fixed cards, the chess clock pause
  {
    const ectx = await browser.newContext({ ...devices['Pixel 7'] });
    const ep = await ectx.newPage();
    ep.on('console', m => { if (m.type() === 'error') consoleErrors.push(`event aids: ${m.text()}`); });
    ep.on('pageerror', e => consoleErrors.push(`event aids: ${e}`));
    const dialogs = [];
    let answer = true;
    ep.on('dialog', d => { dialogs.push(d.message()); if (answer) d.accept(); else d.dismiss(); });
    await ep.goto(`${BASE}/calc/`);
    await ep.waitForSelector('textarea[data-side="A"]');
    await ep.fill('textarea[data-side="A"]', SW_LIST); await ep.tap('button[data-action="parse"][data-side="A"]');
    const etxt = async (q) => (await ep.textContent(q)).replace(/\s+/g, ' ').trim();
    const mission = () => ep.evaluate(() => window.__calc.mission());
    await ep.locator('#event-card > summary').tap();
    const letters = await ep.$$eval('#event-rounds .event-round', rows => rows.map(r => r.querySelector('button[data-action="event-layout"].on').textContent.trim()).join(''));
    check('a new event starts on layouts A, B, C, A, B (the cycle of GW events)', letters === 'ABCAB', letters);
    await ep.tap('button[data-action="event-round-add"]');
    check('a sixth round continues the cycle with C', (await ep.$eval('#event-rounds [data-round="6"] button[data-action="event-layout"].on', b => b.textContent.trim())) === 'C');
    await ep.tap('button[data-action="event-round-del"]');
    // two opponents: the Orks in round 1, the same Ork list again in round 2 (a result needs a game, not a new list)
    await ep.fill('#event-paste', ORK_LIST);
    await ep.tap('button[data-action="event-add"]');
    const oid = await ep.evaluate(() => String(window.__calc.event().roster.find(r => /Waaagh/.test(r.name)).id));
    await ep.selectOption('#event-rounds [data-round="1"] select[data-input="event-opp"]', oid);
    await ep.selectOption('#event-rounds [data-round="2"] select[data-input="event-opp"]', oid);
    await ep.tap('#event-rounds [data-round="1"] button[data-action="event-start"]');
    await ep.waitForSelector('#brief');
    // Fixed Missions for me: Assassination and Bring It Down
    await ep.tap('button[data-action="view"][data-value="mission"]');
    await ep.waitForSelector('details[data-details="mission-assume"] > summary');
    await ep.locator('details[data-details="mission-assume"] > summary').tap();
    await ep.locator('.seg[data-side="A"] button[data-action="mission-mode"][data-value="fixed"]').tap();
    const picked = await ep.evaluate(() => window.__calc.state.mission.modes.A.fixed);
    for (const id of picked) if (!['assassination', 'bring-it-down'].includes(id)) await ep.locator(`button[data-action="mission-fixed"][data-side="A"][data-id="${id}"]`).tap();
    for (const id of ['assassination', 'bring-it-down']) if (!(await ep.evaluate((x) => window.__calc.state.mission.modes.A.fixed.includes(x), id))) await ep.locator(`button[data-action="mission-fixed"][data-side="A"][data-id="${id}"]`).tap();
    check('Fixed Missions chosen for A: Assassination and Bring It Down', (await ep.evaluate(() => window.__calc.state.mission.modes.A.fixed.slice().sort().join())) === 'assassination,bring-it-down');
    await ep.tap('button[data-action="mission-tab"][data-value="play"]');
    await ep.waitForSelector('#fixed-A [data-fixed="assassination"]');
    const fx0 = await etxt('#fixed-A');
    check('Play: the two Fixed cards stay on the table, with what each pays at a time', /Assassination 0 of 20 VP \+3\+4 −1/.test(fx0) && /Bring It Down 0 of 20 VP \+4 −1/.test(fx0), fx0);
    await ep.locator('#fixed-A [data-fixed="assassination"] button[data-vp="4"]').tap();
    let g = (await mission()).game;
    check('a tap adds the VP to the card and to the secondary VP', g.A.fixedVp.assassination === 4 && g.A.secondary === 4 && /4 of 20 VP/.test(await etxt('#fixed-A [data-fixed-vp="assassination"]')) && (await etxt('#play-total-A')) === '14', JSON.stringify(g.A));
    for (let i = 0; i < 5; i++) await ep.locator('#fixed-A [data-fixed="assassination"] button[data-vp="4"]').tap({ force: true });
    g = (await mission()).game;
    check('a Fixed card stops at 20VP: the buttons close and the sixth tap adds nothing', g.A.fixedVp.assassination === 20 && g.A.secondary === 20 && /20 of 20 VP · full/.test(await etxt('#fixed-A [data-fixed-vp="assassination"]')) && await ep.locator('#fixed-A [data-fixed="assassination"] button[data-vp="4"]').isDisabled(), JSON.stringify(g.A));
    await ep.locator('#fixed-A [data-fixed="assassination"] button[data-vp="-1"]').tap();
    g = (await mission()).game;
    check('−1 takes a mistake back', g.A.fixedVp.assassination === 19 && g.A.secondary === 19);
    await ep.locator('#fixed-A').scrollIntoViewIfNeeded();
    await ep.screenshot({ path: join(SHOTS, 'calc_80_fixed_cards.png') });
    // 15VP per battle round: 19 secondary VP in round 1 is over the limit
    const cap = await etxt('#play-cap-warn');
    check('more than 15 secondary VP in a battle round is flagged, with how many do not count', /A has 19 secondary VP in battle round 1: the limit is 15 per battle round, so 4 of them do not count/.test(cap), cap);
    // typed into the box: the warning follows without the page being redrawn
    await ep.fill('input[data-input="mission-score"][data-side="B"][data-k="primary"]', '16');
    await ep.locator('input[data-input="mission-score"][data-side="B"][data-k="primary"]').blur();
    await ep.waitForSelector('#play-cap-warn [data-cap="B:1:primary"]');
    check('a typed score over the limit is flagged too', /B has 16 primary VP in battle round 1.*so 1 of them do not count/.test(await etxt('#play-cap-warn [data-cap="B:1:primary"]')));
    await ep.fill('input[data-input="mission-score"][data-side="B"][data-k="primary"]', '15');
    await ep.locator('input[data-input="mission-score"][data-side="B"][data-k="primary"]').blur();
    await ep.waitForFunction(() => !document.querySelector('#play-cap-warn [data-cap="B:1:primary"]'));
    check('15 is the limit, not over it', (await ep.locator('#play-cap-warn [data-cap]').count()) === 1);
    await ep.evaluate(() => window.scrollTo(0, 0));
    await ep.screenshot({ path: join(SHOTS, 'calc_81_cap_warning.png') });
    // the chess clock: the pause is locked
    await ep.locator('button[data-action="mission-clock-mode"][data-value="chess"]').scrollIntoViewIfNeeded();
    await ep.locator('button[data-action="mission-clock-mode"][data-value="chess"]').tap();
    await ep.locator('button.clock-tile[data-side="A"]').tap();
    check('the chess clock starts with the pause locked', (await mission()).clock.running === 'A' && /🔒 Pause \(referee\)/.test(await etxt('#chess-pause')) && (await ep.getAttribute('#chess-lock', 'aria-pressed')) === 'true' && /only a referee may pause the clock \(UKTC\)/.test(await etxt('#chess-note')));
    await ep.locator('button.clock-tile[data-side="A"]').tap();
    check('a tap on the running clock does not pause it', (await mission()).clock.running === 'A');
    await ep.locator('button.clock-tile[data-side="B"]').tap();
    check('a tap on the other player passes the clock', (await mission()).clock.running === 'B');
    answer = false; dialogs.length = 0;
    await ep.locator('#chess-pause').tap();
    check('Pause asks first, and "Cancel" leaves the clock running', dialogs.length === 1 && /only a referee may pause it \(UKTC\)/.test(dialogs[0]) && (await mission()).clock.running === 'B', dialogs.join(' | '));
    answer = true;
    await ep.locator('#chess-pause').tap();
    check('the referee pauses it: "OK" stops the clock', (await mission()).clock.running == null);
    await ep.locator('#play-clock').scrollIntoViewIfNeeded();
    await ep.screenshot({ path: join(SHOTS, 'calc_82_chess_lock.png') });
    await ep.locator('#chess-lock').tap();
    await ep.locator('button.clock-tile[data-side="A"]').tap();
    await ep.locator('button.clock-tile[data-side="A"]').tap();
    check('with the lock off, a tap on the running clock pauses it as before', (await mission()).clock.running == null && (await etxt('#chess-pause')) === 'Pause' && /A tap on the running clock pauses it/.test(await etxt('#chess-note')));
    // results of the event: round 1 ends 29 - 25 (19 + 10 Battle Ready against 15 + 10); starting round 2 keeps it
    await ep.tap('button[data-action="view"][data-value="armies"]');
    await ep.waitForSelector('#event-rounds');
    check('the round in play offers its score from the Play view', /From Play: 29 – 25/.test(await etxt('#event-take-1')));
    dialogs.length = 0;
    await ep.tap('#event-rounds [data-round="2"] button[data-action="event-start"]');
    await ep.waitForSelector('#brief');
    check('starting round 2 says that the score of round 1 is kept', dialogs.length === 1 && /its score is kept as the result of round 1/.test(dialogs[0]), dialogs.join(' | '));
    await ep.tap('button[data-action="view"][data-value="armies"]');
    await ep.waitForSelector('#event-rounds');
    const r1 = await ep.evaluate(() => window.__calc.event().rounds[0].score);
    check('round 1 has its result (29 - 25, a win) and the record counts it', r1.me === 29 && r1.opp === 25 && /Win/.test(await etxt('#event-rounds [data-round="1"] [data-result="0"]')) && /Record: 1 win · 0 losses · 29 VP for, 25 against \(1 game\)/.test(await etxt('#event-record')) && /round 2 · 1–0/.test(await etxt('#event-card > summary')), `${JSON.stringify(r1)} | ${await etxt('#event-record')} | ${await etxt('#event-card > summary')}`);
    // round 2 by hand: 61 - 74
    await ep.fill('#event-rounds [data-round="2"] input[data-k="me"]', '61');
    await ep.locator('#event-rounds [data-round="2"] input[data-k="me"]').blur();
    await ep.fill('#event-rounds [data-round="2"] input[data-k="opp"]', '74');
    await ep.locator('#event-rounds [data-round="2"] input[data-k="opp"]').blur();
    await ep.waitForFunction(() => /2 games/.test(document.getElementById('event-record')?.textContent ?? ''));
    check('a typed result: loss, and the record adds up', /Loss/.test(await etxt('#event-rounds [data-round="2"] [data-result="1"]')) && /Record: 1 win · 1 loss · 90 VP for, 99 against \(2 games\)/.test(await etxt('#event-record')), await etxt('#event-record'));
    await ep.locator('#event-rounds').scrollIntoViewIfNeeded();
    await ep.screenshot({ path: join(SHOTS, 'calc_83_event_results.png') });
    await ep.reload();
    await ep.waitForSelector('#event-card');
    check('the results are kept over a reload', (await ep.evaluate(() => JSON.stringify(window.__calc.event().rounds.slice(0, 2).map(r => r.score)))) === '[{"me":29,"opp":25},{"me":61,"opp":74}]');
    await ectx.close();
  }
  // an event saved by an older version (every round on Layout A, never used) gets the cycle once; one in use is left alone
  {
    const mctx = await browser.newContext({ ...devices['Pixel 7'] });
    const mp = await mctx.newPage();
    mp.on('pageerror', e => consoleErrors.push(`event migration: ${e}`));
    await mp.addInitScript(() => { if (!localStorage.getItem('w40k_calc_event_v1')) localStorage.setItem('w40k_calc_event_v1', JSON.stringify({ name: 'Old', rounds: [1, 2, 3, 4, 5].map(() => ({ layout: 1, opp: null })), round: null, open: false })); });
    await mp.goto(`${BASE}/calc/`);
    await mp.waitForSelector('#event-card');
    check('an untouched event from an older version moves to A, B, C, A, B', (await mp.evaluate(() => window.__calc.event().rounds.map(r => r.layout).join(''))) === '12312');
    await mp.evaluate(() => localStorage.setItem('w40k_calc_event_v1', JSON.stringify({ name: 'Used', rounds: [{ layout: 1, opp: 5 }, { layout: 1, opp: null }, { layout: 1, opp: null }], round: 1, open: false })));
    await mp.reload();
    await mp.waitForSelector('#event-card');
    check('an event that is in use keeps the layouts it has', (await mp.evaluate(() => window.__calc.event().rounds.map(r => r.layout).join(''))) === '111');
    await mctx.close();
  }

  // --- ease of use (1.107): the Play view runs a light forecast, rotation, legibility, rules in force
  const AGG_LIST = `Update Test (500 points)

Space Marines
Ultramarines
Gladius Task Force (1 Detachment Points)
Take and Hold
Incursion (1000 points)

BATTLELINE

Intercessor Squad (80 points)
  • 1x Intercessor Sergeant
    • 1x Bolt Pistol
      1x Bolt Rifle
  • 4x Intercessor
    • 4x Bolt Pistol
      4x Bolt Rifle

OTHER DATASHEETS

Aggressor Squad (95 points)
  • 1x Aggressor Sergeant
    • 1x Auto Boltstorm Gauntlets
      1x Fragstorm Grenade Launcher
      1x Twin Power Fists
  • 2x Aggressor
    • 2x Auto Boltstorm Gauntlets
      2x Fragstorm Grenade Launcher
      2x Twin Power Fists
`;
  {
    const zctx = await browser.newContext({ ...devices['Pixel 7'] });
    const zp = await zctx.newPage();
    zp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`ease of use: ${m.text()}`); });
    zp.on('pageerror', e => consoleErrors.push(`ease of use: ${e}`));
    await zp.goto(`${BASE}/calc/`);
    await zp.waitForSelector('textarea[data-side="A"]');
    await zp.fill('textarea[data-side="A"]', SW_LIST); await zp.tap('button[data-action="parse"][data-side="A"]');
    await zp.fill('textarea[data-side="B"]', ORK_LIST); await zp.tap('button[data-action="parse"][data-side="B"]');
    const ztxt = async (q) => (await zp.textContent(q)).replace(/\s+/g, ' ').trim();
    const mission = () => zp.evaluate(() => { const m = window.__calc.mission(); return { trials: m.result?.trials, busy: m.busy, levers: m.levers?.length ?? 0, compare: m.compare?.length ?? 0, primary: m.game.A.primary }; });
    // rules in force, today (before the announced update)
    const line = await ztxt('#rules-line');
    check('Armies: the rules-in-force line says what the rules were checked against, the data release and the next change',
      /Rules in force\. Checked on 20 Nov 2026 against the core rules and rules appendix, Event Companion v1\.3, the GW Grand Tournament pack 2026 and UKTC policies/.test(line) && /newest release \(40kdc 1\.5\.1, 13 Nov 2026\)/.test(line)
      && /World Championships rules updates, November 2026 \(UKTC events use it\): 5 of its 8 weapon changes are not in the numbers/.test(line) && /Next rules change: the quarterly balance update, the week beginning 7 December 2026 \(Warhammer Community, 29 Oct 2026\)/.test(line) && (await zp.locator('#rules-due').count()) === 0, line);
    await zp.locator('#rules-line').scrollIntoViewIfNeeded();
    await zp.screenshot({ path: join(SHOTS, 'calc_84_rules_in_force.png') });
    // the installed app may turn with the device
    const manifest = await (await zp.request.get(`${BASE}/calc/manifest.webmanifest`)).json();
    check('the app manifest no longer locks the screen to portrait', manifest.orientation === 'any', manifest.orientation);
    // Mission: a full run on Plan, a light run after a tap on Play
    await zp.tap('button[data-action="view"][data-value="mission"]');
    await zp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.pairsReady && m.levers?.length >= 4; }, null, { timeout: 180000 });
    const full = await mission();
    check('Plan: the full forecast (4,000 games, what-ifs, plan comparison)', full.trials === 4000 && full.levers >= 4 && full.compare >= 1, JSON.stringify(full));
    await zp.tap('button[data-action="mission-tab"][data-value="play"]');
    await zp.waitForSelector('#play-bar');
    await zp.waitForTimeout(700);
    const same = await mission();
    check('opening Play does not run the forecast again: the full one is still good', same.trials === 4000 && !same.busy, JSON.stringify(same));
    await zp.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="5"]');
    await zp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.game.A.primary === 5 && m.result.trials === 1000; }, null, { timeout: 120000 });
    const lite = await mission();
    check('a tap on Play runs the light forecast (1,000 games, no what-ifs worked out)', lite.trials === 1000 && lite.levers === full.levers && /1,000 simulated games/.test(await ztxt('#mission-forecast')), JSON.stringify(lite));
    // the controls on Play: nothing under 36 px
    const small = await zp.evaluate(() => [...document.querySelectorAll('#app main button, #app main input, #app main select, #app main summary')].filter(e => { const r = e.getBoundingClientRect(); return r.width && r.height && Math.min(r.width, r.height) < 35.5; }).map(e => `${e.tagName}.${e.className}:${Math.round(e.getBoundingClientRect().width)}x${Math.round(e.getBoundingClientRect().height)}`));
    check('Play: every control is at least 36 px wide and high', small.length === 0, small.slice(0, 8).join(' | '));
    await zp.evaluate(() => window.scrollTo(0, 0));
    await zp.screenshot({ path: join(SHOTS, 'calc_85_play_controls.png') });
    // back on Plan the what-ifs are worked out again for the new score
    await zp.tap('button[data-action="mission-tab"][data-value="plan"]');
    await zp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.result.trials === 4000; }, null, { timeout: 180000 });
    check('back on Plan: the full forecast for the new score', (await mission()).trials === 4000);
    // the rule that lets a unit arrive a round early is in the overlay's note
    await zp.tap('button[data-action="view"][data-value="board"]');
    await zp.waitForSelector('#board-svg');
    await zp.locator('button[data-action="board-arrive"][data-value="A"]').scrollIntoViewIfNeeded();
    await zp.locator('button[data-action="board-arrive"][data-value="A"]').tap();
    await zp.waitForSelector('#board-arrive-early');
    check('Board: the reserves overlay names High King of Fenris (one unit a turn arrives a battle round early)', /High King of Fenris \(Logan Grimnar\): one unit a turn arrives as if the battle round were one higher, so it can come in battle round 1/.test(await ztxt('#board-arrive-early')), await ztxt('#board-arrive-early'));
    // the ruling of the November update on Combat Doctrines, in the phase sheet
    await zp.tap('button[data-action="view"][data-value="intel"]');
    await zp.tap('button[data-action="intel-mode"][data-value="phase"]');
    await zp.waitForSelector('#phase-sheet');
    await zp.tap('#phase-strip button[data-value="command"]');
    await zp.waitForSelector('[data-ruling="army:combat-doctrines"]');
    check('By phase: Combat Doctrines carries the ruling of the November update', /Nov 2026 update \(UKTC events use it\): A doctrine made active for one unit by Strategic Acumen/.test(await ztxt('[data-ruling="army:combat-doctrines"]')));
    await zctx.close();
  }
  // light theme, and a date after the announced update: readable grey text, and the warning that the rules may be behind
  {
    const lctx = await browser.newContext({ ...devices['Pixel 7'], colorScheme: 'light' });
    const lp = await lctx.newPage();
    lp.on('pageerror', e => consoleErrors.push(`ease of use (light): ${e}`));
    await lp.addInitScript(() => {
      const Real = Date, shift = new Real(2026, 11, 9, 12).getTime() - Real.now();
      globalThis.Date = class extends Real { constructor(...a) { if (a.length) super(...a); else super(Real.now() + shift); } static now() { return Real.now() + shift; } };
    });
    await lp.goto(`${BASE}/calc/`);
    await lp.waitForSelector('textarea[data-side="A"]');
    await lp.fill('textarea[data-side="A"]', AGG_LIST); await lp.tap('button[data-action="parse"][data-side="A"]');
    await lp.fill('textarea[data-side="B"]', ORK_LIST); await lp.tap('button[data-action="parse"][data-side="B"]');
    const ltxt = async (q) => (await lp.textContent(q)).replace(/\s+/g, ' ').trim();
    check('after 7 December: the rules line warns that a rules change was due', (await lp.getAttribute('#rules-line', 'data-due')) === '1' && /A rules change was due: the quarterly balance update, the week beginning 7 December 2026.*look for an app update/.test(await ltxt('#rules-due')) && (await lp.locator('#rules-next').count()) === 0, await ltxt('#rules-line'));
    check('a list with a datasheet the November update changes says so under the list', /Nov 2026 update \(UKTC events use it\), not in the numbers: Aggressor Squad \(Auto boltstorm gauntlets: remove \[CLOSE-QUARTERS\]\)/.test(await ltxt('#update-A')), await ltxt('#data-A'));
    await lp.locator('#rules-line').scrollIntoViewIfNeeded();
    await lp.screenshot({ path: join(SHOTS, 'calc_86_rules_due_light.png') });
    await lp.tap('button[data-action="view"][data-value="intel"]');
    await lp.tap('button[data-action="intel-side"][data-value="A"]');
    await lp.waitForSelector('.intel-unit');
    await lp.locator('.intel-unit', { hasText: 'Aggressor Squad' }).locator('summary').first().tap();
    check('Intel: the datasheet carries the note', /⚠ Nov 2026 update \(UKTC events use it\): Auto boltstorm gauntlets: remove \[CLOSE-QUARTERS\] — not in the numbers here/.test(await ltxt('.update-note')), await ltxt('.update-note'));
    // grey text against what is behind it, light theme
    const low = await lp.evaluate(() => {
      const lum = (c) => { const [r, g, b] = c.map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
      const parse = (s) => { const m = /rgba?\(([^)]+)\)/.exec(s); if (!m) return null; const a = m[1].split(/[,\s/]+/).map(Number); return { rgb: a.slice(0, 3), a: a[3] ?? 1 }; };
      const bgOf = (el) => { let base = [255, 255, 255]; const chain = []; for (let e = el; e; e = e.parentElement) chain.push(e); for (const e of chain.reverse()) { const c = parse(getComputedStyle(e).backgroundColor); if (c && c.a > 0) base = c.rgb.map((v, i) => v * c.a + base[i] * (1 - c.a)); } return base; };
      const out = [];
      for (const el of document.querySelectorAll('#app *')) {
        if (![...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) continue;
        const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
        const cs = getComputedStyle(el); const fg = parse(cs.color); if (!fg || el.closest('button:disabled')) continue;
        const bg = bgOf(el), f = fg.rgb.map((v, i) => v * fg.a + bg[i] * (1 - fg.a));
        const L1 = lum(f), L2 = lum(bg), ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
        if (ratio < 4.5) out.push(`${ratio.toFixed(2)} ${el.className || el.tagName} "${el.textContent.trim().slice(0, 20)}"`);
      }
      return out;
    });
    check('light theme, Intel: no text under 4.5:1 contrast', low.length === 0, low.slice(0, 6).join(' | '));
    await lctx.close();
  }

  // --- saved games (1.108): save the game on the tracker, play another, load the first one back
  {
    const { readFileSync } = await import('fs');
    const CUST = readFileSync('/home/user/warhammer-40k-godot/server/tests/fixtures/gw-custodes-nbhyphen.txt', 'utf8');
    const gctx = await browser.newContext({ ...devices['Pixel 7'] });
    const gp = await gctx.newPage();
    gp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`saved games: ${m.text()}`); });
    gp.on('pageerror', e => consoleErrors.push(`saved games: ${e}`));
    const dialogs = [];
    gp.on('dialog', d => { dialogs.push(d.message()); d.accept(); });
    await gp.goto(`${BASE}/calc/`);
    await gp.waitForSelector('textarea[data-side="A"]');
    const gtxt = async (q) => (await gp.textContent(q)).replace(/\s+/g, ' ').trim();
    const mission = () => gp.evaluate(() => { const s = window.__calc.state; const g = s.mission.game; return { savedId: s.mission.savedId ?? null, round: g.round, next: g.next, A: { p: g.A.primary, s: g.A.secondary, cp: g.A.cp, hand: g.A.hand }, B: { p: g.B.primary, cp: g.B.cp }, over: !!g.over, clock: s.mission.clock, lists: [s.armies.A?.faction, s.armies.B?.faction], games: s.games.map(x => x.name) }; });
    await gp.fill('textarea[data-side="A"]', SW_LIST); await gp.tap('button[data-action="parse"][data-side="A"]');
    await gp.fill('textarea[data-side="B"]', ORK_LIST); await gp.tap('button[data-action="parse"][data-side="B"]');
    check('Armies: a Saved games card, empty at first', /Saved games \(0\)/.test(await gtxt('#games-card > summary')));
    // a board plan: the Grey Hunters on the board
    await gp.tap('button[data-action="view"][data-value="board"]');
    await gp.waitForSelector('#board-svg');
    await gp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    await gp.evaluate(() => { const p = window.__calc.board().plan; const tk = Object.keys(p.steps[0].tokens)[0]; Object.assign(p.steps[0].tokens[tk], { x: 12.5, y: 8.5 }); });
    await gp.locator('button[data-action="board-variant"][data-value="2"]').scrollIntoViewIfNeeded();
    // the game: A scores 5 primary, draws a card, turn done; a chess clock runs
    await gp.tap('button[data-action="view"][data-value="mission"]');
    await gp.tap('button[data-action="mission-tab"][data-value="play"]');
    await gp.waitForSelector('#play-bar');
    await gp.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="5"]');
    await gp.selectOption('select[data-input="mission-draw"][data-side="A"]', 'assassination');
    await gp.tap('#play-turn-done');
    await gp.locator('button[data-action="mission-clock-mode"][data-value="chess"]').tap();
    await gp.locator('button.clock-tile[data-side="B"]').tap();
    await gp.waitForTimeout(2200);
    check('Play: the game is not saved yet', /This game is not saved yet/.test(await gtxt('#game-status')) && (await gp.inputValue('#game-name')) === 'Space Wolves v Orks');
    await gp.fill('#game-name', 'Practice game 1');
    await gp.locator('#game-save').scrollIntoViewIfNeeded();
    await gp.tap('#game-save');
    let st = await mission();
    const order = await gp.evaluate(() => { const y = (s) => document.querySelector(s).getBoundingClientRect().top; return { bar: y('#play-bar'), games: y('#play-games'), opts: y('#play-options') }; });
    check('Play: the Saved games card sits at the end of the Play view, after the options', order.games > order.opts && order.opts > order.bar, JSON.stringify(order));
    check('Save: the game is in the list under its name, and the tracker is linked to it', st.games.join('|') === 'Practice game 1' && !!st.savedId && /Saved: “Practice game 1”/.test(await gtxt('#game-msg-play')) && /^Saved /.test(await gtxt('#game-status')), JSON.stringify(st.games));
    const saved1 = await gp.evaluate(() => window.__calc.state.games[0]);
    check('the saved game holds the lists, the board plan, the tracker and a stopped clock', saved1.armies.A === 'Space Wolves' && saved1.armies.B === 'Orks' && saved1.mission.game.A.primary === 5 && saved1.mission.game.A.hand[0] === 'assassination' && saved1.mission.game.next === 'B'
      && Object.keys(saved1.board.plans).length === 1 && saved1.mission.clock.running == null && saved1.mission.clock.left.B < 85 * 60000 && saved1.mission.clock.left.B > 84 * 60000, JSON.stringify({ plans: Object.keys(saved1.board.plans), clock: saved1.mission.clock }));
    await gp.locator('#play-games').scrollIntoViewIfNeeded();
    await gp.screenshot({ path: join(SHOTS, 'calc_87_saved_game.png') });
    // a change: "Changes since the last save"
    await gp.tap('button[data-action="mission-score-step"][data-side="B"][data-k="primary"][data-delta="5"]');
    check('a change since saving is shown', /Changes not saved yet/.test(await gtxt('#game-status')));
    // another opponent: the Custodes as army B, and a new game against them
    await gp.tap('button[data-action="view"][data-value="armies"]');
    await gp.fill('textarea[data-side="B"]', CUST); await gp.tap('button[data-action="parse"][data-side="B"]');
    await gp.tap('button[data-action="view"][data-value="mission"]');
    await gp.tap('button[data-action="mission-tab"][data-value="play"]');
    await gp.waitForSelector('#play-reset');
    st = await mission();
    const g1 = await gp.evaluate(() => window.__calc.state.games[0]);
    check('loading another list saves the game first (with the change made after saving), and a new game starts on the tracker', st.games.length === 1 && st.savedId === null && st.A.p === 0 && st.B.p === 0 && g1.mission.game.B.primary === 5 && g1.name === 'Practice game 1' && g1.armies.B === 'Orks' && /This game is not saved yet/.test(await gtxt('#game-status')) && /a list changed, so a new game starts/.test(await gtxt('#game-msg-play')), JSON.stringify({ st, B: g1.mission.game.B, armies: g1.armies }));
    await gp.tap('button[data-action="mission-score-step"][data-side="A"][data-k="secondary"][data-delta="5"]');
    // load the first game back from the Armies tab
    await gp.tap('button[data-action="view"][data-value="armies"]');
    await gp.locator('#games-card > summary').tap();
    check('Armies: the saved game is listed with its score and state', /Practice game 1 Space Wolves v Orks · Round 1, B's turn · 15–15 VP/.test(await gtxt('#game-list-armies')), await gtxt('#game-list-armies'));
    await gp.locator('#game-list-armies .game-row', { hasText: 'Practice game 1' }).locator('button[data-action="game-load"]').tap();
    await gp.waitForSelector('#play-bar');
    st = await mission();
    check('Load: the Orks list, the score, the card in hand, the CP and the turn come back, on the Play view', st.lists.join('|') === 'Space Wolves|Orks' && st.A.p === 5 && st.B.p === 5 && st.A.hand[0] === 'assassination' && st.next === 'B' && st.A.cp === 2 && st.B.cp === 2 && st.round === 1, JSON.stringify(st));
    const cg = await gp.evaluate(() => window.__calc.state.games.filter(g => /Custodes/.test(g.name)).map(g => ({ n: g.name, sec: g.mission.game.A.secondary })));
    check('… the game that was on the tracker (vs Custodes, A 5 secondary) was saved first, as its own game', cg.length === 1 && cg[0].sec === 5 && /saved as “Space Wolves v Adeptus Custodes”/.test(await gtxt('#game-msg-play')), JSON.stringify(cg) + ' | ' + await gtxt('#game-msg-play'));
    check('… the chess clock is back, stopped, with B\'s time as it was', st.clock.mode === 'chess' && st.clock.running == null && st.clock.left.B < 85 * 60000 && st.clock.left.B > 84 * 60000);
    await gp.tap('button[data-action="view"][data-value="board"]');
    await gp.waitForSelector('#board-svg');
    const tok = await gp.evaluate(() => window.__calc.board().tokens);
    check('… and the board plan: the Grey Hunters where they were', tok.length === 1 && Math.abs(tok[0].x - 12.5) < 0.01 && Math.abs(tok[0].y - 8.5) < 0.01, JSON.stringify(tok));
    // kept over a reload
    await gp.reload();
    await gp.waitForSelector('#app-version-mini');
    await gp.tap('button[data-action="view"][data-value="armies"]');
    await gp.waitForSelector('#games-card');
    check('saved games are kept over a reload', (await gp.evaluate(() => window.__calc.state.games.length)) === 2 && /Saved games \(2\)/.test(await gtxt('#games-card > summary')));
    // the end of the battle saves it
    await gp.tap('button[data-action="view"][data-value="mission"]');
    await gp.tap('button[data-action="mission-tab"][data-value="play"]');
    await gp.waitForSelector('#play-bar');
    await gp.tap('button[data-action="mission-round"][data-value="5"]');
    for (let i = 0; i < 3 && !(await mission()).over; i++) await gp.tap('#play-turn-done');
    const over = await gp.evaluate(() => window.__calc.state.games.find(g => g.name === 'Practice game 1'));
    check('the end of the battle saves the game', over.mission.game.over === true && /Battle over/.test(await gtxt('#game-status').catch(() => '')) === false, JSON.stringify(over.mission.game.round));
    // delete
    await gp.tap('button[data-action="view"][data-value="armies"]');
    await gp.locator('#games-card > summary').tap().catch(() => {});
    dialogs.length = 0;
    await gp.locator('#game-list-armies .game-row', { hasText: 'Adeptus Custodes' }).first().locator('button[data-action="game-delete"]').tap();
    check('delete asks first, then removes it', /Delete the saved game “Space Wolves v Adeptus Custodes”/.test(dialogs[0] ?? '') && (await gp.evaluate(() => window.__calc.state.games.map(g => g.name).join('|'))) === 'Practice game 1');
    await gp.locator('#games-card').scrollIntoViewIfNeeded();
    await gp.screenshot({ path: join(SHOTS, 'calc_88_saved_games_armies.png') });
    // a backup carries the saved games
    const bk = await gp.evaluate(async () => { const B = await import('/calc/backup.mjs'); return B.describeBackup(B.makeBackup(localStorage)).summary; });
    check('a backup (and a transfer code) carries the saved games', /1 saved game/.test(bk), bk);
    await gctx.close();
  }

  // --- matchup grid (1.108.1): Shooting / Fight in the grid; a tapped cell opens the matchup on the Attack tab
  {
    const mctx = await browser.newContext({ ...devices['Pixel 7'] });
    const mp = await mctx.newPage();
    mp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`grid: ${m.text()}`); });
    mp.on('pageerror', e => consoleErrors.push(`grid: ${e}`));
    await mp.goto(`${BASE}/calc/`); await mp.waitForSelector('textarea[data-side="A"]');
    await mp.fill('textarea[data-side="A"]', SW_LIST); await mp.tap('button[data-action="parse"][data-side="A"]');
    await mp.fill('textarea[data-side="B"]', ORK_LIST); await mp.tap('button[data-action="parse"][data-side="B"]');
    const st = () => mp.evaluate(() => { const s = window.__calc.state; const su = s.setups[`${s.side}:${s.phase}`]; return { view: s.view, sheet: s.sheet, phase: s.phase, side: s.side, target: su?.targetKey ?? null, attackers: (su?.attackers ?? []).map(a => a.unitKey), grid: s.grid ? { phase: s.grid.phase, done: s.grid.done } : null }; });
    // from the Intel brief
    await mp.tap('button[data-action="view"][data-value="intel"]');
    await mp.waitForSelector('button[data-action="brief-grid"]');
    await mp.tap('button[data-action="brief-grid"]');
    await mp.waitForFunction(() => window.__calc.state.grid?.done, null, { timeout: 120000 });
    check('the grid has a Shooting / Fight switch, on Shooting', (await mp.locator('#grid-phase button[data-value="shooting"].on').count()) === 1 && (await mp.textContent('#grid-host th.corner')).trim() === 'Shooting');
    await mp.tap('#grid-phase button[data-value="fight"]');
    await mp.waitForFunction(() => { const g = window.__calc.state.grid; return g?.phase === 'fight' && g.done; }, null, { timeout: 120000 });
    let s = await st();
    check('Fight: the grid is worked out again for the Fight phase', s.phase === 'fight' && s.sheet === 'grid' && (await mp.textContent('#grid-host th.corner')).trim() === 'Fight' && (await mp.locator('#grid-phase button[data-value="fight"].on').count()) === 1, JSON.stringify(s));
    await mp.screenshot({ path: join(SHOTS, 'calc_89_grid_phase.png') });
    const cell = mp.locator('#grid-host button.cell').first();
    const want = { atk: await cell.getAttribute('data-atk'), def: await cell.getAttribute('data-def') };
    await cell.tap();
    await mp.waitForFunction(() => { const s = window.__calc.state; return s.view === 'attack' && s.result && !s.busy; }, null, { timeout: 60000 });
    s = await st();
    check('a tapped cell (opened from the Intel brief) opens that matchup on the Attack tab, in the Fight phase', s.view === 'attack' && s.sheet === null && s.phase === 'fight' && s.target === want.def && s.attackers.join() === want.atk && (await mp.locator('button[data-action="phase"][data-value="fight"].on').count()) === 1, JSON.stringify({ s, want }));
    await mp.evaluate(() => window.scrollTo(0, 0));
    await mp.screenshot({ path: join(SHOTS, 'calc_90_grid_opened.png') });
    // back on Shooting from the Attack tab's grid
    await mp.tap('button[data-action="open-grid"]');
    await mp.waitForFunction(() => window.__calc.state.grid?.done, null, { timeout: 120000 });
    await mp.tap('#grid-phase button[data-value="shooting"]');
    await mp.waitForFunction(() => { const g = window.__calc.state.grid; return g?.phase === 'shooting' && g.done; }, null, { timeout: 120000 });
    await mp.locator('#grid-host button.cell').nth(2).tap();
    await mp.waitForFunction(() => window.__calc.state.sheet === null, null, { timeout: 10000 });
    s = await st();
    check('… and from the Attack tab, a Shooting cell opens a shooting matchup', s.view === 'attack' && s.phase === 'shooting' && !!s.target && s.attackers.length === 1, JSON.stringify(s));
    await mctx.close();
  }

  // --- branching plans (1.109): decisions and chances after a turn; the forecast of each branch
  {
    const tctx = await browser.newContext({ ...devices['Pixel 7'] });
    const tp = await tctx.newPage();
    tp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`branches: ${m.text()}`); });
    tp.on('pageerror', e => consoleErrors.push(`branches: ${e}`));
    tp.on('dialog', d => d.accept());
    await tp.goto(`${BASE}/calc/`); await tp.waitForSelector('textarea[data-side="A"]');
    await tp.fill('textarea[data-side="A"]', SW_LIST); await tp.tap('button[data-action="parse"][data-side="A"]');
    await tp.fill('textarea[data-side="B"]', ORK_LIST); await tp.tap('button[data-action="parse"][data-side="B"]');
    const ttxt = async (q) => (await tp.textContent(q)).replace(/\s+/g, ' ').trim();
    const dbg = () => tp.evaluate(() => { const d = window.__calc.board(); return { tokens: d.tokens, v: window.__calc.state.board.plans, steps: [...document.querySelectorAll('button[data-action="board-step"]')].map(b => `${b.textContent.trim()}${b.classList.contains('on') ? '*' : ''}`) }; });
    const pos = async (tk) => (await tp.evaluate(() => window.__calc.board().tokens)).find(t => t.tk === tk);
    const setPos = (tk, x, y) => tp.evaluate(([t, px, py]) => { const toks = window.__calc.board().stepTokens; toks[t] = { ...(toks[t] ?? {}), x: px, y: py }; }, [tk, x, y]);
    const redraw = () => tp.evaluate(() => document.querySelector('button[data-action="board-step"].on')?.click());
    await tp.tap('button[data-action="view"][data-value="board"]');
    await tp.waitForSelector('#board-svg');
    await tp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    await tp.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Meganobz' }).tap();
    const toks = await tp.evaluate(() => window.__calc.board().tokens.map(t => t.tk));
    const GH = toks.find(t => t.startsWith('A:')), MN = toks.find(t => t.startsWith('B:'));
    await setPos(GH, 22, 26); await setPos(MN, 22, 36);
    await tp.locator('button[data-action="board-step-add"]').tap();          // Turn 1
    // ⑂ after Turn 1: my decision, go left or go right
    await tp.locator('#board-branch').tap();
    await tp.waitForSelector('#board-tree .tsplit');
    let d = await dbg();
    check('⑂ Branch here: a second path that starts at Turn 2, both paths have Turn 2', d.steps.join('|') === 'Deploy|Turn 1|Turn 2*' && (await tp.locator('#board-tree .topt').count()) === 2 && /After Turn 1/.test(await ttxt('#board-tree .tsplit')), d.steps.join('|'));
    const opts = tp.locator('#board-tree .tsplit').first().locator(':scope > .topt');
    await opts.nth(0).locator('input.tlabel').fill('Go left'); await opts.nth(0).locator('input.tlabel').blur();
    await opts.nth(1).locator('input.tlabel').fill('Go right'); await opts.nth(1).locator('input.tlabel').blur();
    await tp.waitForTimeout(300);
    check('the branch shows its path: Main ▸ Go right', /◉ is on the board: Main ▸ Go right/.test(await ttxt('#board-tree')));
    // in "Go right", Turn 2: the Grey Hunters go right
    await setPos(GH, 36, 28); await redraw();
    // a shared turn: move the Meganobz in Turn 1 of "Go right" -> it is the same Turn 1 in "Go left"
    await tp.locator('button[data-action="board-step"][data-i="1"]').tap();
    await setPos(MN, 20, 34); await redraw();
    await tp.locator('#board-tree .topt').first().locator('button[data-action="board-branch-view"]').tap();
    const onLeft = /◉ is on the board: Main ▸ Go left(?! ▸)/.test(await ttxt('#board-tree'));
    await tp.locator('button[data-action="board-step"][data-i="1"]').tap();
    const leftT1 = await pos(MN);
    await tp.locator('button[data-action="board-step"][data-i="2"]').tap();
    const leftGh = await pos(GH);
    check('turns before the split are shared: Turn 1 moved in one branch is moved in the other; Turn 2 is each branch’s own', onLeft && Math.abs(leftT1.x - 20) < 0.01 && Math.abs(leftGh.x - 22) < 0.01, JSON.stringify({ onLeft, leftT1, leftGh }));
    // on "Go left", after Turn 2: a chance - their charge destroys the Grey Hunters
    await setPos(MN, 22, 33); await redraw();       // the Meganobz end Turn 2 about 5" from the Grey Hunters
    await tp.locator('#board-branch').tap();
    await tp.waitForFunction(() => document.querySelectorAll('#board-tree .tsplit').length === 2);
    const inner = tp.locator('#board-tree .tsplit').nth(1);
    await inner.locator('button[data-action="board-split-kind"][data-value="chance"]').tap();
    await tp.locator('#board-tree .tsplit').nth(1).locator('button[data-action="board-split-auto"][data-value="wipe"]').tap();
    const in2 = () => tp.locator('#board-tree .tsplit').nth(1);
    await in2().locator('select[data-input="board-split-atk"]').selectOption(MN);
    await in2().locator('select[data-input="board-split-def"]').selectOption(GH);
    await in2().locator('button[data-action="board-split-how"][data-value="charge"]').tap();
    await tp.waitForFunction(() => /From the calculator: \d+%/.test(document.querySelectorAll('#board-tree .tsplit')[1]?.textContent ?? ''), null, { timeout: 120000 });
    const why = await in2().locator('[data-auto-why]').textContent();
    const labels = await in2().locator(':scope > .topt input.tlabel').evaluateAll(els => els.map(e => e.value));
    const ph = await in2().locator(':scope > .topt input[data-input="board-branch-p"]').evaluateAll(els => els.map(e => e.placeholder));
    check('a chance from the calculator: their charge (2D6 odds of the gap) × the Grey Hunters destroyed in the fight', /From the calculator: \d+% \(charge [\d.]+" needs \d+\+: \d+% × destroyed in the fight \d+%\)/.test(why) && labels.join('|') === 'Grey Hunters survives|Grey Hunters destroyed' && Number(ph[0]) + Number(ph[1]) === 100, `${why} | ${labels} | ${ph}`);
    // the "destroyed" branch: the Grey Hunters are off the board from Turn 3
    await in2().locator(':scope > .topt').nth(1).locator('button[data-action="board-branch-view"]').tap();
    d = await dbg();
    check('in the "destroyed" branch the Grey Hunters are off the board from Turn 3', d.steps.join('|') === 'Deploy|Turn 1|Turn 2|Turn 3*' && !d.tokens.some(t => t.tk === GH) && d.tokens.some(t => t.tk === MN), JSON.stringify(d.steps));
    // my own chance: 50%
    await in2().locator(':scope > .topt').nth(1).locator('input[data-input="board-branch-p"]').fill('50');
    await in2().locator(':scope > .topt').nth(1).locator('input[data-input="board-branch-p"]').blur();
    await tp.waitForFunction(() => document.querySelectorAll('#board-tree .tsplit')[1]?.querySelector('.topt input[data-input="board-branch-p"]')?.placeholder === '50');
    check('a typed chance replaces the calculator’s (50 / 50)', (await in2().locator(':scope > .topt').nth(0).locator('input[data-input="board-branch-p"]').getAttribute('placeholder')) === '50');
    await tp.locator('#board-tree').scrollIntoViewIfNeeded();
    await tp.screenshot({ path: join(SHOTS, 'calc_91_branches_board.png') });
    // Mission: each branch forecast, the best decision
    await tp.tap('button[data-action="view"][data-value="mission"]');
    await tp.waitForFunction(() => { const m = window.__calc.mission(); return m.result && !m.busy && m.pairsReady && (m.compare?.length ?? 0) >= 4; }, null, { timeout: 240000 });
    await tp.waitForSelector('.fc-tree');
    const res = await tp.evaluate(() => {
      const m = window.__calc.mission();
      const w = (k) => m.compare.find(c => c.key === k)?.result.pWinA;
      return { rows: m.compare.map(c => c.label), w: Object.fromEntries(m.compare.map(c => [c.key, w(c.key)])), head: document.querySelector('.fc-tree .small').textContent.replace(/\s+/g, ' ').trim(), items: [...document.querySelectorAll('.fc-tree li')].map(li => li.firstElementChild.textContent.replace(/\s+/g, ' ').trim() + ' = ' + li.querySelector(':scope > b').textContent) };
    });
    const v = res.w;
    const leftVal = 0.5 * v.plan0 + 0.5 * v.plan2;
    const best = Math.max(leftVal, v.plan1);
    const shown = Number(/you win (\d+)%/.exec(res.head)?.[1]);
    check('Mission compares each path by name (Main ▸ Go right …)', res.rows.includes('Board: Main ▸ Go right') && res.rows.includes('Board: Main ▸ Go left ▸ Grey Hunters destroyed') && res.rows.includes('Board: Main ▸ Go left ▸ Grey Hunters survives'), JSON.stringify(res.rows));
    check('the plan is worth its best decision: Go left = 50% × survives + 50% × destroyed, against Go right', Math.abs(shown - Math.round(best * 100)) <= 1 && new RegExp(`best: ${leftVal >= v.plan1 ? 'Go left' : 'Go right'}`).test(res.head), JSON.stringify({ head: res.head, leftVal, right: v.plan1, items: res.items }));
    await tp.locator('.fc-tree').scrollIntoViewIfNeeded();
    await tp.screenshot({ path: join(SHOTS, 'calc_92_branches_forecast.png') });
    // at the table: the charge came in and destroyed the Grey Hunters
    await tp.tap('button[data-action="view"][data-value="board"]');
    await tp.waitForSelector('#board-tree');
    await in2().locator(':scope > .topt').nth(1).locator('button[data-action="board-branch-chosen"]').tap();
    await tp.waitForSelector('#board-tree .topt.gone');
    check('"Happened": the other outcome is greyed, the board shows the branch that happened', /✓ Happened/.test(await ttxt('#board-tree')) && (await tp.locator('#board-tree .topt.gone').count()) === 1 && /Main ▸ Go left ▸ Grey Hunters destroyed|Main ▸ Grey Hunters destroyed/.test(await ttxt('#board-tree')), await ttxt('#board-tree'));
    await tp.tap('button[data-action="view"][data-value="mission"]');
    await tp.waitForSelector('.fc-tree');
    const after = await tp.evaluate(() => [...document.querySelectorAll('.fc-tree li')].map(li => li.className + ':' + li.firstElementChild.textContent.replace(/\s+/g, ' ').trim()));
    check('Mission: only what happened counts in that branch now', after.some(x => /✓ Grey Hunters destroyed/.test(x)) && after.some(x => /^ ?gone.*Grey Hunters survives/.test(x.trim())), JSON.stringify(after));
    // kept over a reload; delete a branch
    await tp.reload(); await tp.waitForSelector('#app-version-mini');
    await tp.tap('button[data-action="view"][data-value="board"]');
    await tp.waitForSelector('#board-tree');
    check('branches are kept over a reload', (await tp.locator('#board-tree .tsplit').count()) >= 1);
    await tp.locator('#board-tree .topt', { has: tp.locator('input[value="Go right"]') }).locator('button[data-action="board-branch-delete"]').tap();
    await tp.waitForFunction(() => ![...document.querySelectorAll('#board-tree input.tlabel')].some(i => i.value === 'Go right'));
    check('a branch can be deleted', (await tp.evaluate(() => Object.values(window.__calc.state.board.plans)[0].variants.length)) === 2);
    await tctx.close();
  }

  // --- branch map (1.110): every path at a glance above the board; tap to switch; win chances; compare positions
  {
    const mctx = await browser.newContext({ ...devices['Pixel 7'] });
    const mp = await mctx.newPage();
    mp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`branch map: ${m.text()}`); });
    mp.on('pageerror', e => consoleErrors.push(`branch map: ${e}`));
    mp.on('dialog', d => d.accept());
    await mp.goto(`${BASE}/calc/`); await mp.waitForSelector('textarea[data-side="A"]');
    await mp.fill('textarea[data-side="A"]', SW_LIST); await mp.tap('button[data-action="parse"][data-side="A"]');
    await mp.fill('textarea[data-side="B"]', ORK_LIST); await mp.tap('button[data-action="parse"][data-side="B"]');
    const mtxt = async (q) => (await mp.textContent(q)).replace(/\s+/g, ' ').trim();
    const mset = (tk, x, y) => mp.evaluate(([t, px, py]) => { const toks = window.__calc.board().stepTokens; toks[t] = { ...(toks[t] ?? {}), x: px, y: py }; document.querySelector('button[data-action="board-step"].on')?.click(); }, [tk, x, y]);
    const mstate = () => mp.evaluate(() => { const d = window.__calc.board(); return { cur: d.cur, steps: [...document.querySelectorAll('button[data-action="board-step"]')].map(b => b.textContent.trim()), path: document.querySelector('.tm-row.on .tm-lab')?.textContent.trim(), tokens: d.tokens }; });
    await mp.tap('button[data-action="view"][data-value="board"]');
    await mp.waitForSelector('#board-svg');
    check('no branch map until the plan has a branch', (await mp.locator('#board-treemap').count()) === 0);
    await mp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    await mp.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Meganobz' }).tap();
    const mt = await mp.evaluate(() => window.__calc.board().tokens.map(t => t.tk));
    const GH = mt.find(t => t.startsWith('A:')), MN = mt.find(t => t.startsWith('B:'));
    await mset(GH, 22, 26); await mset(MN, 22, 36);
    await mp.locator('button[data-action="board-step-add"]').tap();                  // Turn 1
    await mp.locator('#board-branch').tap();                                          // after Turn 1: a decision
    await mp.waitForSelector('#board-treemap');
    const o1 = mp.locator('#board-tree .tsplit').first().locator(':scope > .topt');
    await o1.nth(0).locator('input.tlabel').fill('Go left'); await o1.nth(0).locator('input.tlabel').blur();
    await o1.nth(1).locator('input.tlabel').fill('Go right'); await o1.nth(1).locator('input.tlabel').blur();
    await mset(GH, 40, 28);                                                           // Go right, Turn 2
    await mp.locator('#board-tree .topt').first().locator('button[data-action="board-branch-view"]').tap();
    await mset(MN, 22, 31);                                                           // Go left, Turn 2: the Meganobz close in
    await mp.locator('#board-branch').tap();                                          // after Turn 2: a chance
    await mp.waitForFunction(() => document.querySelectorAll('#board-tree .tsplit').length === 2);
    const in2 = () => mp.locator('#board-tree .tsplit').nth(1);
    await in2().locator('button[data-action="board-split-kind"][data-value="chance"]').tap();
    await in2().locator(':scope > .topt').nth(0).locator('input.tlabel').fill('Hunters survive'); await in2().locator(':scope > .topt').nth(0).locator('input.tlabel').blur();
    await in2().locator(':scope > .topt').nth(1).locator('input.tlabel').fill('Hunters wiped'); await in2().locator(':scope > .topt').nth(1).locator('input.tlabel').blur();
    await in2().locator(':scope > .topt').nth(1).locator('input[data-input="board-branch-p"]').fill('40'); await in2().locator(':scope > .topt').nth(1).locator('input[data-input="board-branch-p"]').blur();
    await mp.evaluate(([gh]) => { const toks = window.__calc.board().stepTokens; delete toks[gh]; document.querySelector('button[data-action="board-step"].on')?.click(); }, [GH]); // wiped: off the board at Turn 3
    await mp.waitForTimeout(300);
    // the map: three paths, the one on the board highlighted
    const rows = await mp.$$eval('#board-treemap .tm-row', els => els.map(e => e.querySelector('.tm-lab').textContent.trim()));
    check('the branch map lists every path, in tree order, with the chance to get there', rows.length === 3 && /^Hunters survive 60%$/.test(rows[0]) && /^Hunters wiped 40%$/.test(rows[1]) && /^Go right$/.test(rows[2]), JSON.stringify(rows));
    check('each path names the choices before it (“after Go left”)', (await mp.$$eval('#board-treemap .tm-sub', els => els.map(e => e.textContent.trim()))).join('|') === 'after Go left|after Go left');
    check('the path on the board is highlighted on the map, at the turn on screen', /Hunters wiped/.test((await mstate()).path ?? '') && (await mp.locator('#board-treemap .tm-here').count()) === 1);
    // tap a turn on another path: that path at that turn is on the board
    const goRight = await mp.evaluate(() => Object.values(window.__calc.state.board.plans)[0].variants.find(v => v.branch?.label === 'Go right').id);
    await mp.locator(`#board-treemap g.tm-go[data-vid="${goRight}"][data-i="2"]`).tap();
    let s = await mstate();
    check('tap a turn on the map: that path, at that turn, is on the board', s.path === 'Go right' && s.cur === 2 && Math.abs(s.tokens.find(t => t.tk === GH).x - 40) < 0.01, JSON.stringify({ path: s.path, cur: s.cur }));
    // tap a path's name: the same turn on that path
    await mp.locator('#board-treemap .tm-row').nth(0).tap();
    s = await mstate();
    check('tap a path’s name: that path at the same turn', /^Hunters survive/.test(s.path) && s.cur === 2 && Math.abs(s.tokens.find(t => t.tk === MN).y - 31) < 0.01, JSON.stringify({ path: s.path, cur: s.cur }));
    // win chances worked out from here
    check('⚡ Work out win chances is offered before any forecast', (await mp.locator('#board-tree-forecast').count()) === 1);
    await mp.locator('#board-tree-forecast').tap();
    await mp.waitForFunction(() => [...document.querySelectorAll('#board-treemap .tm-win')].every(t => /^\d+%$/.test(t.textContent.trim())), null, { timeout: 240000 });
    const wins = await mp.evaluate(() => { const m = window.__calc.mission(); return Object.fromEntries(m.compare.map(c => [c.key, Math.round(c.result.pWinA * 100)])); });
    const shown = await mp.$$eval('#board-treemap .tm-win', els => els.map(e => Number(e.textContent.replace('%', ''))));
    const head = await mtxt('#board-treemap .small');
    const left = 0.6 * wins.plan0 + 0.4 * wins.plan2;
    const best = left >= wins.plan1 ? 'Go left' : 'Go right';
    const starred = await mp.$$eval('#board-treemap .tm-lab', els => els.map(e => e.textContent.trim().startsWith('★')));
    check('each path shows its win chance (the same as Mission → Plan), the plan’s worth and the best decision now', shown.join() === [wins.plan0, wins.plan2, wins.plan1].join() && new RegExp(`best now: ${best}`).test(head) && Math.abs(Number(/You win (\d+)%/.exec(head)?.[1]) - Math.max(left, wins.plan1)) <= 1.01 && (best === 'Go left' ? starred.join() === 'true,true,false' : starred.join() === 'false,false,true'), JSON.stringify({ shown, wins, head, starred }));
    await mp.locator('#board-treemap').scrollIntoViewIfNeeded();
    await mp.screenshot({ path: join(SHOTS, 'calc_93_branch_map.png') });
    // the map folds to one line (the board moves up) and opens again
    await mp.locator('#board-tree-fold').tap();
    await mp.waitForSelector('#board-treemap[data-shut="1"]');
    check('the branch map folds to one line: the path on the board and the plan’s win chance', /On the board: Main ▸ Go left ▸ Hunters survive · you win \d+%/.test(await mtxt('#board-treemap')) && (await mp.locator('#board-treemap svg').count()) === 0, await mtxt('#board-treemap'));
    await mp.locator('#board-tree-fold').tap();
    await mp.waitForSelector('#board-treemap svg');
    // compare: Go right's positions as ghost bases at this turn
    await mp.selectOption('#board-cmp', goRight);
    await mp.waitForSelector('#board-ghosts [data-ghost]');
    const info = await mtxt('#board-cmp-info');
    check('compare with another path: its units at this turn as dashed bases, and how far apart', /Dashed bases: Main ▸ Go right at Turn 2\./.test(info) && /Grey Hunters [\d.]+" away/.test(info) && /Meganobz [\d.]+" away/.test(info) && (await mp.locator('#board-ghosts [data-ghost]').count()) === 2, info);
    await mp.screenshot({ path: join(SHOTS, 'calc_94_branch_compare.png') });
    // at Turn 3, the wiped path: the Grey Hunters are gone there, a cross over them
    const wiped = await mp.evaluate(() => Object.values(window.__calc.state.board.plans)[0].variants.find(v => v.branch?.label === 'Hunters wiped').id);
    await mp.locator('#board-treemap .tm-row').nth(0).tap();
    await mp.locator('button[data-action="board-step"][data-i="3"]').tap();
    await mp.selectOption('#board-cmp', wiped);
    await mp.waitForSelector('#board-ghosts [data-ghost-gone]');
    check('a unit destroyed in the other path is crossed out', /Grey Hunters is not on the board there/.test(await mtxt('#board-cmp-info')));
    // moving a path after the forecast: its win chance is not shown until worked out again
    await mset(MN, 30, 31);
    await mp.waitForTimeout(200);
    const after = await mp.$$eval('#board-treemap .tm-win', els => els.map(e => e.textContent.trim()));
    check('a path changed after the forecast loses its win chance (no stale numbers); ⚡ is offered again', after[0] === '' && /^\d+%$/.test(after[2]) && (await mp.locator('#board-tree-forecast').count()) === 1, JSON.stringify(after));
    await mctx.close();
  }

  // --- points with an enhancement priced apart (1.110.1): a New Recruit / WTC list
  {
    const qctx = await browser.newContext({ ...devices['Pixel 7'] });
    const qp = await qctx.newPage();
    qp.on('pageerror', e => consoleErrors.push(`points: ${e}`));
    qp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`points: ${m.text()}`); });
    await qp.goto(`${BASE}/calc/`); await qp.waitForSelector('textarea[data-side="A"]');
    await qp.fill('textarea[data-side="A"]', readFileSync(join(here, 'fixtures', 'nr-custodes-1995.txt'), 'utf8'));
    await qp.tap('button[data-action="parse"][data-side="A"]');
    await qp.waitForSelector('#points-A');
    const t = (await qp.textContent('#points-A')).replace(/\s+/g, ' ').trim();
    check('a list that prices enhancements apart: every datasheet costs what the data says (Telemon 280 + 30 = 310)', /✓ Points: all 9 datasheets cost what the rules data says/.test(t), t);
    await qp.locator('#points-A').scrollIntoViewIfNeeded();
    await qp.evaluate(() => window.scrollBy(0, -260));
    await qp.screenshot({ path: join(SHOTS, 'calc_96_points_enhancement.png') });
    await qctx.close();
  }

  // --- set-up path (1.124.0): checklist on Mission, the Board's set-up locked during a game, disposition overrides shown
  {
    const uctx = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
    const up = await uctx.newPage();
    up.on('pageerror', e => consoleErrors.push(`setup: ${e}`));
    up.on('console', m => { if (m.type() === 'error') consoleErrors.push(`setup: ${m.text()}`); });
    up.on('dialog', d => d.accept());
    const utxt = async (q) => (await up.textContent(q)).replace(/\s+/g, ' ').trim();
    const settings = () => up.evaluate(() => ({ ...window.__calc.state.board.settings, layout: window.__calc.board().layout }));
    await up.goto(`${BASE}/calc/`); await up.waitForSelector('textarea[data-side="A"]');
    await up.fill('textarea[data-side="A"]', SW_LIST); await up.tap('button[data-action="parse"][data-side="A"]');
    await up.fill('textarea[data-side="B"]', ORK_LIST); await up.tap('button[data-action="parse"][data-side="B"]');
    // the checklist on Mission > Plan, open before the game
    await up.tap('button[data-action="view"][data-value="mission"]');
    await up.waitForSelector('#setup-plan');
    const rows = await up.$$eval('#setup-list-plan .setup-row', els => els.map(e => `${e.dataset.step}:${e.classList.contains('ok') ? 'ok' : e.classList.contains('warn') ? 'warn' : 'todo'}`));
    check('Mission > Plan: a set-up checklist in order (armies, dispositions, primaries, layout, deployment, secondaries, first turn), open',
      rows.join(',') === 'armies:ok,disp:ok,primary:ok,layout:ok,deploy:todo,cards:ok,first:todo' && await up.$eval('#setup-plan', d => d.open), rows.join(','));
    check('the checklist says what is left and names both primaries', /^Set-up: 2 to do/.test(await utxt('#setup-plan > summary')) && /A plays .+ · B plays/.test(await utxt('#mission-names')) && /0 of \d+ units placed/.test(await utxt('#setup-list-plan [data-step="deploy"]')));
    await up.screenshot({ path: join(SHOTS, 'calc_121_setup_checklist.png') });
    // its Board button goes to the Board; a disposition changed there is flagged on both tabs
    await up.tap('#setup-list-plan [data-step="disp"] button[data-value="board"]');
    await up.waitForSelector('#board-setup');
    await up.selectOption('select[data-input="board-disp"][data-side="B"]', 'purge-the-foe');
    await up.waitForSelector('#board-disp-override-B');
    check('Board: a disposition that is not the list\'s is flagged, with the list\'s offered back', /B is set to Purge the Foe here, but B's list says Take and Hold/.test(await utxt('#board-disp-override-B')));
    await up.tap('button[data-action="view"][data-value="mission"]');
    await up.tap('button[data-action="mission-tab"][data-value="play"]');
    check('Play shows the checklist too while something needs checking', /1 to check/.test(await utxt('#setup-play > summary')));
    await up.tap('button[data-action="mission-tab"][data-value="plan"]');
    check('…and the checklist marks dispositions to check', /⚠/.test(await utxt('#setup-list-plan [data-step="disp"]')) && /list: Take and Hold/.test(await utxt('#setup-list-plan [data-step="disp"]')) && /1 to check/.test(await utxt('#setup-plan > summary')));
    await up.tap('button[data-action="view"][data-value="board"]');
    await up.tap('#board-disp-override-B button[data-action="board-disp-list"]');
    check('"Use the list\'s" puts B back on its list\'s disposition', (await up.locator('#board-disp-override-B').count()) === 0 && (await settings()).dispB === undefined);
    // after deployment (Turn 1 on), the set-up card is gone: only Share image and a pointer to the Deploy step
    await up.tap('button[data-action="board-step-add"]');
    await up.waitForSelector('#board-setup-turn');
    check('Board, Turn 1: no dispositions / layout / zones card, Share image stays', (await up.locator('#board-setup').count()) === 0 && (await up.locator('select[data-input="board-disp"]').count()) === 0
      && (await up.locator('#board-setup-turn button[data-action="board-share"]').count()) === 1 && (await up.evaluate(() => window.__calc.board().cur)) === 1);
    await up.locator('#board-setup-turn').scrollIntoViewIfNeeded();
    await up.screenshot({ path: join(SHOTS, 'calc_124_board_turn_no_setup.png') });
    await up.tap('button[data-action="board-step"][data-i="0"]');
    check('…and back on the Deploy step it is there again', (await up.locator('#board-setup').count()) === 1 && (await up.locator('select[data-input="board-disp"]').count()) === 2);
    await up.tap('button[data-action="board-step"][data-i="1"]');
    await up.tap('button[data-action="view"][data-value="mission"]');
    await up.tap('#setup-list-plan [data-step="layout"] button[data-value="board"]');
    await up.waitForSelector('#board-setup');
    check('the checklist\'s Board button opens the Deploy step (where the set-up is)', (await up.evaluate(() => window.__calc.board().cur)) === 0);
    // the event preparation table overrides B's disposition: flagged, and a new B list drops it
    await up.tap('button[data-action="view"][data-value="armies"]');
    await up.locator('#event-card > summary').tap();
    await up.fill('#event-paste', ORK_LIST); await up.tap('button[data-action="event-add"]');
    await up.locator('#event-coverage button.cov[data-disp="reconnaissance"][data-v="2"]').tap();
    await up.waitForSelector('#board-disp-override-B');
    check('a tap on the preparation table: Board with B on that disposition, and it says so', (await settings()).dispB === 'reconnaissance' && /B is set to Reconnaissance here/.test(await utxt('#board-disp-override-B')));
    await up.screenshot({ path: join(SHOTS, 'calc_122_setup_override.png') });
    await up.tap('button[data-action="view"][data-value="armies"]');
    await up.fill('textarea[data-side="B"]', readFileSync(join(here, 'fixtures', 'gw-custodes-nbhyphen.txt'), 'utf8'));
    await up.tap('button[data-action="parse"][data-side="B"]');
    check('a different list loaded as B takes its own disposition again (the override is dropped)', (await settings()).dispB === undefined);
    // a game on the tracker: the set-up is locked on the Board
    await up.tap('button[data-action="view"][data-value="mission"]');
    await up.tap('button[data-action="mission-tab"][data-value="play"]');
    await up.waitForSelector('#play-bar');
    await up.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="5"]');
    check('Play: no checklist when nothing needs checking (the tracker stays short)', (await up.locator('#setup-play').count()) === 0);
    await up.tap('button[data-action="mission-tab"][data-value="plan"]');
    await up.waitForSelector('#setup-plan');
    check('Plan: the checklist says the set-up is locked during the game', /🔒 locked during the game/.test(await utxt('#setup-plan > summary')) && /locked while this game is on the tracker/.test(await utxt('#setup-plan')));
    await up.tap('button[data-action="view"][data-value="board"]');
    await up.waitForSelector('#board-setup-lock');
    const before = await settings();
    const disabled = await up.evaluate(() => ({ sel: document.querySelector('select[data-input="board-disp"][data-side="A"]').matches(':disabled'), lay: document.querySelector('button[data-action="board-variant"][data-value="3"]').matches(':disabled'), swap: document.querySelector('button[data-action="board-swap-zones"]').disabled }));
    await up.locator('button[data-action="board-variant"][data-value="3"]').tap({ force: true });
    check('Board during a game: dispositions, layout and zones are locked and a tap on a layout changes nothing',
      disabled.sel && disabled.lay && disabled.swap && (await settings()).layout === before.layout && /a game is on the tracker \(round 1\)/.test(await utxt('#board-setup-lock')), JSON.stringify(disabled));
    await up.locator('#board-setup').scrollIntoViewIfNeeded();
    await up.screenshot({ path: join(SHOTS, 'calc_123_setup_locked.png') });
    // the preparation table cannot change the game's mission either
    await up.tap('button[data-action="view"][data-value="armies"]');
    await up.locator('#event-coverage button.cov[data-disp="disruption"][data-v="1"]').tap();
    check('preparation table during a game: nothing changes, it says why', (await up.evaluate(() => window.__calc.state.view)) === 'armies' && (await settings()).dispB === undefined && /A game is on the tracker/.test(await utxt('#event-card')));
    // "Change anyway" unlocks it (after a confirm)
    await up.tap('button[data-action="view"][data-value="board"]');
    await up.tap('#board-setup-unlock');
    await up.tap('button[data-action="board-variant"][data-value="3"]');
    check('"Change anyway": the layout can be changed during the game', (await up.locator('#board-setup-lock').count()) === 0 && /_3$/.test((await settings()).layout), (await settings()).layout);
    await uctx.close();
  }

  // --- movement rings stay where the unit started the turn (1.111.0): drag it, the Move ring does not follow
  {
    const rctx = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
    const rp = await rctx.newPage();
    rp.on('pageerror', e => consoleErrors.push(`rings: ${e}`));
    rp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`rings: ${m.text()}`); });
    const rScreen = (x, y) => rp.evaluate(([bx, by]) => { const svg = document.getElementById('board-svg'); const pt = svg.createSVGPoint(); pt.x = bx; pt.y = by; const q = pt.matrixTransform(svg.getScreenCTM()); return { x: q.x, y: q.y }; }, [x, y]);
    const rTok = (tk) => rp.evaluate((k) => window.__calc.board().tokens.find(t => t.tk === k), tk);
    // the centre of the first circle of a ring (the first model's), in board inches
    const ringAt = (k) => rp.evaluate((kk) => { const c = document.querySelector(`#board-svg [data-ring="${kk}"] circle`); const g = c?.parentNode; return c ? { x: +c.getAttribute('cx'), y: +c.getAttribute('cy'), from: g.dataset.from } : null; }, k);
    const drag = async (from, dy) => {
      const p0 = await rScreen(from.x, from.y), p1 = await rScreen(from.x, from.y + dy);
      await rp.mouse.move(p0.x, p0.y); await rp.mouse.down();
      for (let i = 1; i <= 6; i++) await rp.mouse.move(p0.x, p0.y + (p1.y - p0.y) * i / 6);
      await rp.mouse.up();
    };
    await rp.goto(`${BASE}/calc/`); await rp.waitForSelector('textarea[data-side="A"]');
    await rp.fill('textarea[data-side="A"]', SW_LIST); await rp.tap('button[data-action="parse"][data-side="A"]');
    await rp.fill('textarea[data-side="B"]', ORK_LIST); await rp.tap('button[data-action="parse"][data-side="B"]');
    await rp.tap('button[data-action="view"][data-value="board"]');
    await rp.waitForSelector('#board-svg');
    await rp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    const gh = (await rp.evaluate(() => window.__calc.board().tokens))[0];
    // Turn 1: select it, show its Move ring
    await rp.tap('button[data-action="board-step-add"]');
    await rp.locator('#board-host').scrollIntoViewIfNeeded();
    // (placing a unit selects it; a tap on a selected unit clears the selection)
    if ((await rp.evaluate(() => window.__calc.board().sel)) !== gh.tk) { const s0 = await rScreen(gh.x, gh.y); await rp.mouse.click(s0.x, s0.y); }
    await rp.locator('#board-panel button[data-action="board-ring"][data-k="move"]').tap();
    await rp.locator('#board-panel button[data-action="board-ring"][data-k="r24"]').tap();
    const m0 = await ringAt('move');
    // drag it 5" forward, and again 3" (two drops in the same turn)
    await drag(gh, 5);
    const g1 = await rTok(gh.tk);
    await drag(g1, 3);
    const g2 = await rTok(gh.tk), m2 = await ringAt('move'), r2 = await ringAt('r24');
    check('dragging the unit in Turn 1 moves it (~8" in two drags)', Math.abs(g2.y - gh.y - 8) < 0.6, `${gh.y} -> ${g2.y}`);
    check('the Move ring stays where the unit ended the Deploy step (it does not follow the drop)', m0 && m2 && m2.from === 'start' && Math.abs(m2.x - m0.x) < 0.01 && Math.abs(m2.y - m0.y) < 0.01, JSON.stringify({ m0, m2 }));
    check('a weapon range ring follows the unit (shooting is after the move)', r2 && r2.from === 'here' && Math.abs(r2.y - m2.y - (g2.y - gh.y)) < 0.05, JSON.stringify({ r2, m2 }));
    check('the start of the turn is outlined (dashed) once the unit has moved', (await rp.locator(`#board-svg [data-start="${gh.tk}"]`).count()) === 1);
    await rp.locator('#board-panel button[data-action="board-ring"][data-k="r24"]').tap();
    await rp.locator('#board-host').scrollIntoViewIfNeeded();
    await rp.screenshot({ path: join(SHOTS, 'calc_125_move_ring_pinned.png') });
    // Turn 2: the Move ring starts from where it ended Turn 1
    await rp.tap('button[data-action="board-step-add"]');
    const m3 = await ringAt('move');
    check('Turn 2: the Move ring is measured from where the unit ended Turn 1', m3 && Math.abs(m3.y - m0.y - (g2.y - gh.y)) < 0.05 && (await rp.locator(`#board-svg [data-start="${gh.tk}"]`).count()) === 0, JSON.stringify({ m0, m3 }));
    // Deploy: no previous turn, the ring is around the unit
    await rp.tap('button[data-action="board-step"][data-i="0"]');
    { const s1 = await rScreen(gh.x, gh.y); await rp.mouse.click(s1.x, s1.y); } // a new step clears the selection
    const md = await ringAt('move');
    check('Deploy step: the Move ring is around the unit where it stands', md && md.from === 'here' && Math.abs(md.y - m0.y) < 0.01, JSON.stringify(md));
    await rctx.close();
  }

  // --- lists in the game (1.111): load a list from the game's army store; send army A / B there
  {
    const gctx = await browser.newContext({ ...devices['Pixel 7'] });
    const gp = await gctx.newPage();
    gp.on('pageerror', e => consoleErrors.push(`game lists: ${e}`));
    gp.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) consoleErrors.push(`game lists: ${m.text()}`); });
    gp.on('dialog', d => d.accept());
    await gp.goto(`${BASE}/calc/`); await gp.waitForSelector('textarea[data-side="A"]');
    await gp.fill('textarea[data-side="A"]', SW_LIST); await gp.tap('button[data-action="parse"][data-side="A"]');
    const gtxt = async (sel) => (await gp.textContent(sel)).replace(/\s+/g, ' ').trim();
    // someone else's list already in the game
    const other = await gp.evaluate(async () => (await fetch('/api/armies/Taken', { method: 'PUT', headers: { 'X-Player-ID': 'someone-else-0001', 'Content-Type': 'application/json' }, body: JSON.stringify({ army_data: { faction: { name: 'Orks', points: 500 }, units: { U_A: { meta: { name: 'Warboss', points: 70, wargear: [], enhancements: [] }, models: [{}] } } } }) })).status);
    check('(set-up) another player’s list “Taken” is in the game', other === 200);
    await gp.tap('button[data-action="open-library"][data-side="A"]');
    await gp.tap('#game-lists-btn');
    await gp.waitForSelector('[data-game-list="Taken"]');
    check('📚 → Show the game’s lists: the lists in the game, to load into A or B', (await gp.locator('#game-lists .pick').count()) === 1 && (await gp.locator('[data-game-list="Taken"] button[data-action="store-load"]').count()) === 2);
    // send army A under a name someone else uses: refused
    await gp.fill('input[data-input="store-send-name"]', 'Taken');
    await gp.tap('button[data-action="store-send"]');
    await gp.waitForSelector('#game-send-msg');
    check('a name someone else uses in the game is refused (the game finds lists by name)', /already in the game .* Pick another name/.test(await gtxt('#game-send-msg')), await gtxt('#game-send-msg'));
    // send it as "Gaelcon Wolves"
    await gp.fill('input[data-input="store-send-name"]', 'Gaelcon Wolves');
    await gp.tap('button[data-action="store-send"]');
    await gp.waitForSelector('#game-send-msg.ok');
    const stored = await gp.evaluate(async () => (await (await fetch('/api/armies/Gaelcon_Wolves')).json()).army_data);
    check('⇪ Send: army A is in the game as “Gaelcon_Wolves”, in the game’s format (12 units, its faction and detachments)', /Sent: the game lists army A as “Gaelcon_Wolves” \(12 units\)/.test(await gtxt('#game-send-msg')) && Object.keys(stored.units).length === 12 && stored.faction.name === 'Space Wolves' && (stored.detachments ?? stored.faction.detachments).length === 3 && (await gp.locator('[data-game-list="Gaelcon_Wolves"]').count()) === 1, JSON.stringify(stored.faction));
    await gp.locator('#game-send').scrollIntoViewIfNeeded();
    await gp.screenshot({ path: join(SHOTS, 'calc_97_game_lists.png') });
    // sending the same name again from this phone replaces it (after a confirm)
    await gp.tap('button[data-action="store-send"]');
    await gp.waitForSelector('#game-send-msg.ok');
    check('the same phone can replace a list it sent', (await gp.locator('[data-game-list="Gaelcon_Wolves"]').count()) === 1);
    // load it from the game into B
    await gp.locator('[data-game-list="Gaelcon_Wolves"] button[data-action="store-load"][data-side="B"]').tap();
    await gp.waitForSelector('#points-B');
    const b = await gp.evaluate(() => ({ faction: window.__calc.state.armies.B?.faction, n: window.__calc.state.armies.B?.units.length, tas: window.__calc.state.armies.B?.roster.units.find(u => u.ref?.raw_name === 'Terminator Assault Squad') }));
    check('→ B: the game’s list is army B — Space Wolves, every datasheet priced as the rules data says, enhancements kept', b.faction === 'Space Wolves' && /✓ Points: all 12 datasheets cost what the rules data says/.test(await gtxt('#points-B')) && b.tas?.enhancement?.raw_name === 'Furious Assault' && b.tas?.model_count === 10, JSON.stringify({ f: b.faction, n: b.n, pts: await gtxt('#points-B') }));
    await gp.locator('#points-B').scrollIntoViewIfNeeded();
    await gp.screenshot({ path: join(SHOTS, 'calc_98_game_list_loaded.png') });
    // no connection to the server: says so
    await gp.route('**/api/armies', r => r.abort());
    await gp.evaluate(() => { window.__calc.state.gameLists = null; });
    await gp.tap('button[data-action="open-library"][data-side="A"]');
    await gp.tap('#game-lists-btn');
    await gp.waitForSelector('#game-error');
    check('offline: the library says the game’s lists need a connection', /need a connection/.test(await gtxt('#game-error')));
    await gctx.close();
  }

  // --- 1.112: event Start says what is missing / what it set up; the page behind a sheet stays put; cards drawn as cards
  {
    const xctx = await browser.newContext({ ...devices['Pixel 7'] });
    const xp = await xctx.newPage();
    xp.on('pageerror', e => consoleErrors.push(`1.112: ${e}`));
    xp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`1.112: ${m.text()}`); });
    xp.on('dialog', d => d.accept());
    await xp.goto(`${BASE}/calc/`); await xp.waitForSelector('textarea[data-side="A"]');
    const xt = async (sel) => (await xp.textContent(sel)).replace(/\s+/g, ' ').trim();
    // the event card: Start with nothing loaded says what to do (it used to be greyed out)
    await xp.locator('summary', { hasText: 'Event' }).first().click();
    await xp.locator('.event-round[data-round="1"] button[data-action="event-start"]').tap();
    await xp.waitForSelector('#event-msg');
    check('Event: Start ▶ with no list loaded says to load your list as army A', /load your own list as army A/.test(await xt('#event-msg')), await xt('#event-msg'));
    // an opponent in the library, my list as A
    await xp.fill('textarea[data-side="B"]', ORK_LIST); await xp.tap('button[data-action="parse"][data-side="B"]');
    await xp.tap('button[data-action="open-library"][data-side="B"]');
    await xp.fill('input[data-input="lib-name"]', 'R1 Orks'); await xp.tap('button[data-action="lib-save"]');
    await xp.tap('.sheet button[data-action="close-sheet"]');
    await xp.fill('textarea[data-side="A"]', SW_LIST); await xp.tap('button[data-action="parse"][data-side="A"]');
    if (!(await xp.locator('.event-round').count())) await xp.locator('summary', { hasText: 'Event' }).first().click();
    await xp.locator('.event-round[data-round="1"] button[data-action="event-start"]').tap();
    await xp.waitForFunction(() => /pick its opponent/.test(document.querySelector('#event-msg')?.textContent ?? ''));
    check('Event: Start ▶ with no opponent picked says to pick it', true);
    await xp.selectOption('select[data-input="event-opp"][data-r="0"]', { label: 'R1 Orks' });
    await xp.locator('.event-round[data-round="1"] button[data-action="event-layout"][data-value="3"]').tap();
    await xp.locator('.event-round[data-round="1"] button[data-action="event-start"]').tap();
    await xp.waitForSelector('#round-started');
    const lay = await xp.evaluate(() => window.__calc.board().layout);
    check('Event: Start ▶ opens Intel at the top, saying what it set up (round, opponent, layout, missions); the Board has that layout', /Round 1 started against R1 Orks \(army B\) on Layout C/.test(await xt('#round-started')) && /_3$/.test(lay) && (await xp.evaluate(() => window.__calc.state.view)) === 'intel' && (await xp.evaluate(() => window.scrollY)) === 0 && (await xp.locator('#round-started').boundingBox()).y < 400, `${await xt('#round-started')} | ${lay} | scrollY ${await xp.evaluate(() => window.scrollY)}`);
    await xp.screenshot({ path: join(SHOTS, 'calc_99_round_started.png') });
    await xp.locator('#round-started button[data-value="board"]').tap();
    await xp.waitForSelector('#board-svg');
    check('the banner’s Board → opens the board on that layout', (await xp.evaluate(() => window.__calc.board().layout)) === lay);
    // the matchup grid: a scroll inside it does not move the page behind
    await xp.tap('button[data-action="view"][data-value="attack"]');
    await xp.tap('button[data-action="open-grid"]');
    await xp.waitForFunction(() => window.__calc.state.grid?.done, null, { timeout: 60000 });
    // a long page behind the open sheet (the Attack view with nothing picked fits one screen): a spacer, scrolled to 300
    await xp.evaluate(() => { const d = document.createElement('div'); d.id = 'test-spacer'; d.style.height = '3000px'; document.body.appendChild(d); window.scrollTo(0, 300); });
    const before = await xp.evaluate(() => window.scrollY);
    const locked = await xp.evaluate(() => getComputedStyle(document.documentElement).overflow + '/' + getComputedStyle(document.querySelector('.grid-wrap')).overscrollBehaviorY);
    const box = await xp.locator('#grid-host').boundingBox();
    for (let k = 0; k < 6; k++) await xp.mouse.wheel(0, 900, { x: box.x + box.width / 2, y: box.y + box.height / 2 });
    await xp.waitForTimeout(300);
    const after = await xp.evaluate(() => window.scrollY);
    check('matchup grid: the page behind stays put while the grid scrolls (the scroll stops at the grid’s edge)', before === 300 && after === before && locked.endsWith('/contain'), JSON.stringify({ before, after, locked }));
    await xp.tap('.sheet button[data-action="close-sheet"]');
    check('closing the sheet unlocks the page', (await xp.evaluate(() => document.documentElement.classList.contains('sheet-open'))) === false);
    // the secondary cards as cards
    await xp.tap('button[data-action="view"][data-value="mission"]');
    await xp.tap('button[data-action="mission-tab"][data-value="cards"]');
    await xp.waitForSelector('#mission-cards .card-row');
    await xp.locator('.card-row[data-card="engage-on-all-fronts"] button[data-action="mission-card"]').tap();
    await xp.waitForSelector('.card-detail [data-cardface="engage-on-all-fronts"]');
    const face = await xt('.card-detail [data-cardface="engage-on-all-fronts"]');
    check('tap a card: it is drawn as a card — name, Tactical / Fixed, when it scores, a VP badge per line, the Fixed version', /Engage on All Fronts/i.test(face) && /Tactical\s*Fixed/.test(face) && /End of your turn/.test(face) && (await xp.locator('.card-detail .cf-vp').count()) === 4 && /Fixed mission/.test(face), face);
    await xp.locator('.card-detail .cf').scrollIntoViewIfNeeded();
    await xp.screenshot({ path: join(SHOTS, 'calc_100_card_face.png') });
    await xp.tap('button[data-action="mission-cards-look"][data-value="faces"]');
    await xp.waitForSelector('#card-faces .cf');
    check('🂠 Cards: every secondary card drawn as a card, with the app’s numbers under it', (await xp.locator('#card-faces .cf').count()) === 18 && (await xp.locator('#card-faces .cf-foot').count()) === 18, String(await xp.locator('#card-faces .cf').count()));
    await xp.locator('#card-faces').scrollIntoViewIfNeeded();
    await xp.screenshot({ path: join(SHOTS, 'calc_101_card_gallery.png') });
    await xp.tap('button[data-action="mission-cards-look"][data-value="list"]');
    // the hand on Play
    await xp.tap('button[data-action="mission-tab"][data-value="play"]');
    await xp.selectOption('select[data-input="mission-draw"][data-side="A"]', 'behind-enemy-lines');
    await xp.locator('.hand-row[data-card="behind-enemy-lines"] button[data-action="mission-hand-info"]').tap();
    await xp.waitForSelector('.hand-row [data-cardface="behind-enemy-lines"]');
    check('a card in hand opens as a card, “When drawn” included', /When drawn/.test(await xt('.hand-row [data-cardface="behind-enemy-lines"]')));
    await xctx.close();
  }

  // --- attachments during army set-up (1.113): ask when the list says none, suggest, remember per list
  {
    const actx = await browser.newContext({ ...devices['Pixel 7'] });
    const ap = await actx.newPage();
    ap.on('pageerror', e => consoleErrors.push(`attach: ${e}`));
    ap.on('console', m => { if (m.type() === 'error') consoleErrors.push(`attach: ${m.text()}`); });
    ap.on('dialog', d => d.accept());
    const CUST = readFileSync(join(here, 'fixtures', 'nr-custodes-1995.txt'), 'utf8');
    const at = async (sel) => (await ap.textContent(sel)).replace(/\s+/g, ' ').trim();
    await ap.goto(`${BASE}/calc/`); await ap.waitForSelector('textarea[data-side="A"]');
    await ap.fill('textarea[data-side="A"]', CUST); await ap.tap('button[data-action="parse"][data-side="A"]');
    await ap.waitForSelector('#attach-ask-A');
    check('a list that does not say who leads which unit: the Attached characters fold is open and asks', (await ap.locator('#attach-A[open]').count()) === 1 && /⚠ Attached characters · 0 of 3 attached/.test(await at('#attach-A summary')) && /does not say which characters lead which units/.test(await at('#attach-ask-A')));
    await ap.locator('#attach-A').scrollIntoViewIfNeeded();
    await ap.screenshot({ path: join(SHOTS, 'calc_102_attach_ask.png') });
    await ap.tap('#attach-suggest-A');
    await ap.waitForFunction(() => /3 of 3 attached/.test(document.querySelector('#attach-A summary')?.textContent ?? ''));
    const units = await ap.evaluate(() => window.__calc.state.armies.A.units.map(u => u.name));
    check('✨ Suggest: every character joins a unit it may lead (9 datasheets -> 6 units)', units.length === 6 && units.some(n => /Trajann Valoris \+ Allarus Custodians/.test(n)) && units.filter(n => /Shield-Captain \+ Sentinel Guard Sodality/.test(n)).length === 2, JSON.stringify(units));
    // change one by hand: Trajann to the 2-model Allarus unit
    const sel = ap.locator('select[data-input="attach"]').filter({ has: ap.locator('option[selected]', { hasText: 'Allarus' }) }).first();
    const opts = await sel.locator('option').evaluateAll(os => os.map(o => [o.value, o.textContent]));
    const small = opts.find(([, t]) => /Allarus Custodians \(2\)/.test(t));
    await sel.selectOption(small[0]);
    await ap.waitForFunction(() => window.__calc.state.armies.A.units.some(u => /Trajann Valoris \+ Allarus Custodians/.test(u.name) && u.models === 3));
    check('a choice changed by hand', true);
    await ap.locator('#attach-A').scrollIntoViewIfNeeded();
    await ap.screenshot({ path: join(SHOTS, 'calc_103_attach_set.png') });
    check('it says the choice is remembered for this list', /Remembered for this list/.test(await at('#attach-remembered-A')));
    // the same list again: clear, then from the library, and as a fresh paste
    await ap.tap('button[data-action="open-library"][data-side="A"]');
    await ap.fill('input[data-input="lib-name"]', 'My Custodes'); await ap.tap('button[data-action="lib-save"]');
    await ap.tap('.sheet button[data-action="close-sheet"]');
    await ap.tap('button[data-action="clear"][data-side="A"]');
    await ap.tap('button[data-action="open-library"][data-side="B"]');
    await ap.locator('.sheet .pick', { hasText: 'My Custodes' }).locator('button[data-action="lib-load"][data-side="B"]').tap();
    await ap.waitForFunction(() => window.__calc.state.armies.B?.units.length === 6);
    const b = await ap.evaluate(() => window.__calc.state.armies.B.units.map(u => `${u.name}:${u.models}`));
    check('the same list loaded again (from the library, as army B) keeps the attachments set for it', b.includes('Trajann Valoris + Allarus Custodians:3') && b.filter(x => /Shield-Captain \+ Sentinel Guard Sodality/.test(x)).length === 2, JSON.stringify(b));
    await ap.reload(); await ap.waitForSelector('#app-version-mini');
    await ap.fill('textarea[data-side="A"]', CUST + '\n'); await ap.tap('button[data-action="parse"][data-side="A"]');
    await ap.waitForFunction(() => window.__calc.state.armies.A?.units.length === 6);
    check('…and pasted again after a reload', true);
    // a list that says its attachments: no question asked, the list's own kept
    await ap.fill('textarea[data-side="A"]', SW_LIST); await ap.tap('button[data-action="parse"][data-side="A"]');
    await ap.waitForSelector('#attach-A');
    check('a GW app list that names its attachments: no question, 4 of 4 attached from the list', (await ap.locator('#attach-ask-A').count()) === 0 && /4 of 4 attached/.test(await at('#attach-A summary')));
    await actx.close();
  }

  // --- 1.114: gap between bases, a letter on every base, transports, stratagems in full
  {
    const kctx = await browser.newContext({ ...devices['Pixel 7'] });
    const kp = await kctx.newPage();
    kp.on('pageerror', e => consoleErrors.push(`1.114: ${e}`));
    kp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`1.114: ${m.text()}`); });
    kp.on('dialog', d => d.accept());
    await kp.goto(`${BASE}/calc/`); await kp.waitForSelector('textarea[data-side="A"]');
    await kp.fill('textarea[data-side="A"]', SW_LIST); await kp.tap('button[data-action="parse"][data-side="A"]');
    await kp.fill('textarea[data-side="B"]', ORK_LIST); await kp.tap('button[data-action="parse"][data-side="B"]');
    const kt = async (sel) => (await kp.textContent(sel)).replace(/\s+/g, ' ').trim();
    // Intel: every stratagem they can use in my turn, in full
    await kp.tap('button[data-action="view"][data-value="intel"]');
    await kp.waitForSelector('#brief');
    const watch = await kp.evaluate(() => { const f = [...document.querySelectorAll('details')].find(d => /They can do this in your turn/.test(d.querySelector('summary')?.textContent ?? '')); if (f) f.open = true; return f ? { head: f.querySelector('summary').textContent.trim(), items: [...f.querySelectorAll('[data-watch]')].map(e => e.textContent.replace(/\s+/g, ' ').trim()) } : null; });
    check('"They can do this in your turn": every one, the When and the Effect in full (no “…”)', watch && watch.items.length >= 5 && watch.items.every(t => !/…$/.test(t) && /When:.*Effect:/.test(t)) && Math.max(...watch.items.map(t => t.length)) > 260, JSON.stringify(watch?.items.map(t => t.length)));
    // Board
    await kp.tap('button[data-action="view"][data-value="board"]');
    await kp.waitForSelector('#board-svg');
    const place = async (side, name) => { await kp.locator(`button[data-action="board-place"][data-side="${side}"]`, { hasText: name }).first().tap(); };
    const toks = () => kp.evaluate(() => window.__calc.board().units);
    const setPos = (tk, x, y) => kp.evaluate(([t, px, py]) => { const s = window.__calc.board().stepTokens; s[t] = { ...(s[t] ?? {}), x: px, y: py }; document.querySelector('button[data-action="board-step"].on')?.click(); }, [tk, x, y]);
    await place('B', 'Battlewagon'); await place('B', 'Meganobz'); await place('B', 'Warboss + Boyz');
    let u = await toks();
    const W = u.find(t => /B:/.test(t.tk) && t.models.length === 1 && t.keywords.includes('TRANSPORT'))?.tk ?? u.find(t => t.tk.startsWith('B:') && t.models.length === 1).tk;
    const MN = u.find(t => t.models.length === 3).tk, BOYZ = u.find(t => t.models.length === 21).tk;
    await setPos(W, 22, 14); await setPos(MN, 30, 14); await setPos(BOYZ, 14, 20);
    // a letter on every base: Meganobz M, Boyz B, the attached Warboss W
    const letters = await kp.evaluate(([mn, bz]) => ({ mn: [...document.querySelectorAll(`[data-tok="${mn}"] .tok-letters text`)].map(t => t.textContent), bz: [...document.querySelectorAll(`[data-tok="${bz}"] .tok-letters text`)].map(t => t.textContent) }), [MN, BOYZ]);
    check('a letter on every base: the first letter of its datasheet (Meganobz M ×3; Boyz B ×20 and the attached Warboss W)', letters.mn.join('') === 'MMM' && letters.bz.filter(x => x === 'B').length === 20 && letters.bz.filter(x => x === 'W').length === 1, JSON.stringify(letters));
    // gap between bases: the Boyz, touching
    const bzSel = async () => { await kp.evaluate((t) => { window.__calc.state.board.sel = t; window.__calc.state.board.sel2 = null; document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); }, BOYZ); await kp.waitForSelector('#board-spacing'); };
    await bzSel();
    const nearest = (ms) => Math.min(...ms.map((a, i) => Math.min(...ms.filter((_, j) => j !== i).map(b => Math.hypot(a.dx - b.dx, a.dy - b.dy) - a.fp.r - b.fp.r))));
    const g0 = nearest((await toks()).find(t => t.tk === BOYZ).models);
    await kp.locator('#board-spacing button[data-value="0"]').tap();
    await kp.waitForFunction((t) => window.__calc.board().stepTokens[t]?.gap === 0, BOYZ);
    const g1 = nearest((await toks()).find(t => t.tk === BOYZ).models);
    await kp.locator('#board-spacing').scrollIntoViewIfNeeded();
    check('Gap between bases → Touching: the Boyz close up (nearest bases from about 1" apart to touching)', g0 > 0.4 && Math.abs(g1) < 0.02, JSON.stringify({ g0, g1 }));
    await kp.locator('#board-host').scrollIntoViewIfNeeded();
    await kp.screenshot({ path: join(SHOTS, 'calc_104_board_letters_gap.png') });
    // transport: select the Battlewagon, embark the Meganobz
    await kp.evaluate((t) => { window.__calc.state.board.sel = t; window.__calc.state.board.sel2 = null; document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); }, W);
    await kp.waitForSelector('#board-transport');
    check('a transport shows its passengers: 0 of 22 spaces, Orks Infantry, Mega Armour take 2', /0 of 22 spaces used/.test(await kt('#board-transport')) && /Carries Orks Infantry models/.test(await kt('#board-transport')) && /Mega Armour take 2/.test(await kt('#board-transport')));
    await kp.selectOption('select[data-input="board-embark"]', MN);
    await kp.waitForFunction((t) => window.__calc.board().stepTokens[t]?.in, MN);
    const after = await kp.evaluate(([mn, w]) => ({ onBoard: window.__calc.board().tokens.some(t => t.tk === mn), label: document.querySelector(`[data-tok="${w}"]`)?.textContent ?? '', panel: document.getElementById('board-transport')?.textContent.replace(/\s+/g, ' ') }), [MN, W]);
    check('embark: the Meganobz leave the board, the Battlewagon shows 🚚+1 and 6 of 22 spaces (Mega Armour ×2)', !after.onBoard && /🚚\+1/.test(after.label) && /6 of 22 spaces used/.test(after.panel) && /Meganobz/.test(after.panel), JSON.stringify(after));
    // a unit not placed yet can deploy inside
    const fgOpt = await kp.locator('select[data-input="board-embark"] option', { hasText: 'Flash Gitz' }).getAttribute('value');
    await kp.selectOption('select[data-input="board-embark"]', fgOpt);
    await kp.waitForFunction((t) => window.__calc.board().stepTokens[t]?.in, fgOpt);
    check('a unit not on the board can start inside (Flash Gitz): it leaves the units to place', (await kp.locator('button[data-action="board-place"]', { hasText: 'Flash Gitz' }).count()) === 0 && /11 of 22 spaces used/.test(await kt('#board-transport')));
    await kp.locator('#board-transport').scrollIntoViewIfNeeded();
    await kp.screenshot({ path: join(SHOTS, 'calc_105_transport.png') });
    // next turn: still inside, moves with the transport
    await kp.locator('button[data-action="board-step-add"]').tap();
    await setPos(W, 22, 24);
    check('next turn: still embarked', await kp.evaluate((t) => !!window.__calc.board().stepTokens[t]?.in, MN));
    await kp.evaluate((t) => { window.__calc.state.board.sel = t; document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); }, W);
    await kp.waitForSelector(`[data-passenger="${MN}"] button[data-action="board-disembark"]`);
    await kp.locator(`[data-passenger="${MN}"] button[data-action="board-disembark"]`).tap();
    await kp.waitForFunction((t) => window.__calc.board().tokens.some(x => x.tk === t), MN);
    const gap = await kp.evaluate(([mn, w]) => { const u = window.__calc.board().units; const a = u.find(t => t.tk === mn), b = u.find(t => t.tk === w); const r = (m) => m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.ry ?? 0, m.fp.hw ?? 0, m.fp.hh ?? 0); let best = 99; for (const x of a.models) for (const y of b.models) best = Math.min(best, Math.hypot(a.x + x.dx - b.x - y.dx, a.y + x.dy - b.y - y.dy) - r(x) - r(y)); return best; }, [MN, W]);
    const warn = await kp.textContent('#board-warnings').catch(() => '');
    check('disembark: set up within 3" of the transport, not flagged as a reserve arrival (noted as disembarking)', gap >= 0 && gap <= 3 && /disembarks from Battlewagon/.test(warn ?? '') && !/arrives/.test(warn ?? ''), JSON.stringify({ gap, warn }));
    await kctx.close();
  }

  // --- 1.115: the score shown to the opponent, a random draw they can see, stratagems usable now + the log
  {
    const pctx = await browser.newContext({ ...devices['Pixel 7'] });
    const pp = await pctx.newPage();
    pp.on('pageerror', e => consoleErrors.push(`1.115: ${e}`));
    pp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`1.115: ${m.text()}`); });
    pp.on('dialog', d => d.accept());
    await pp.goto(`${BASE}/calc/`); await pp.waitForSelector('textarea[data-side="A"]');
    await pp.fill('textarea[data-side="A"]', SW_LIST); await pp.tap('button[data-action="parse"][data-side="A"]');
    await pp.fill('textarea[data-side="B"]', ORK_LIST); await pp.tap('button[data-action="parse"][data-side="B"]');
    const pt = async (sel) => (await pp.textContent(sel)).replace(/\s+/g, ' ').trim();
    await pp.tap('button[data-action="view"][data-value="mission"]');
    await pp.tap('button[data-action="mission-tab"][data-value="play"]');
    await pp.waitForSelector('#play-bar');
    await pp.tap('button[data-action="mission-first"][data-value="A"]').catch(() => {});
    // a random draw, full screen
    await pp.tap('#draw-random-A');
    await pp.waitForSelector('#show-draw .cf');
    const drawn = await pp.evaluate(() => window.__calc.mission().game?.A?.hand ?? []);
    const shown = await pp.getAttribute('#show-draw [data-cardface]', 'data-cardface');
    check('🎲 Draw at random: a card from the deck goes into A’s hand and is shown full screen as a card', drawn.length === 1 && drawn[0] === shown && /A · Space Wolves drew at random/.test(await pt('#show-draw .show-head')) && /From the 18 cards left/.test(await pt('#show-draw')), JSON.stringify({ drawn, shown }));
    await pp.screenshot({ path: join(SHOTS, 'calc_106_draw_random.png') });
    await pp.tap('#show-draw-again');
    await pp.waitForFunction(() => window.__calc.mission().game.A.hand.length === 2);
    check('“Draw another”: the second card of the turn, then no more offered', (await pp.locator('#show-draw-again').count()) === 0);
    await pp.tap('#show-draw button[data-action="mission-show-close"]');
    // score something, then show it to the opponent
    await pp.tap('button[data-action="mission-score-step"][data-side="A"][data-k="primary"][data-delta="5"]');
    await pp.tap('#play-show');
    await pp.waitForSelector('#show-score');
    check('📺 Show: both scores, CP and the cards in hand, the score sheet by round, nothing about odds', /5/.test(await pt('#show-total-A')) && /In hand:/.test(await pt('[data-show-side="A"]')) && /CP/.test(await pt('[data-show-side="B"]')) && /Battle round 1/.test(await pt('#show-score .show-head')) && !/%/.test(await pt('#show-score')), await pt('#show-score'));
    await pp.tap('#show-flip');
    check('↻ turns the screen to face the opponent', await pp.evaluate(() => !!document.querySelector('#show-score .show-inner.flip')));
    await pp.screenshot({ path: join(SHOTS, 'calc_107_show_opponent.png') });
    await pp.tap('#show-score button[data-action="mission-show-flip"]');
    await pp.tap('#show-close');
    // stratagems usable now: A's Shooting phase
    await pp.locator('#play-strats > summary').tap();
    await pp.tap('button[data-action="mission-phase"][data-value="shooting"]');
    await pp.waitForSelector('#play-strats[open] .strat-now');
    const sum = await pt('#play-strats > summary');
    const rowsA = await pp.$$eval('#play-strats .strat-now[data-side="A"]', els => els.map(e => e.getAttribute('data-strat')));
    const rowsB = await pp.$$eval('#play-strats .strat-now[data-side="B"]', els => els.map(e => e.getAttribute('data-strat')));
    check('Stratagems now: only the ones usable in this phase, for the player whose turn it is and for the opponent', /Shooting: A \d+, B \d+ usable/.test(sum) && rowsA.length > 0 && rowsB.length > 0, JSON.stringify({ sum, rowsA, rowsB }));
    const cpB = await pp.evaluate(() => window.__calc.mission().game.B.cp);
    const name = rowsB[0];
    await pp.locator(`#play-strats .strat-now[data-side="B"][data-strat="${name}"] button[data-action="mission-strat"]`).tap();
    await pp.waitForFunction((n) => window.__calc.mission().game.strats?.some(s => s.name === n), name);
    const after = await pp.evaluate(() => ({ cp: window.__calc.mission().game.B.cp, log: window.__calc.mission().game.strats }));
    const btn = pp.locator(`#play-strats .strat-now[data-side="B"][data-strat="${name}"] button[data-action="mission-strat"]`);
    check('Use: B spends the CP, it is logged (round, turn, phase), and it shows ✓ Used for the rest of the phase', after.cp < cpB && after.log.length === 1 && after.log[0].phase === 'shooting' && after.log[0].turn === 'A' && /✓ Used/.test(await btn.textContent()) && await btn.isDisabled(), JSON.stringify(after));
    await pp.locator('#play-strats details[data-details="mission-strat-log"] > summary').tap();
    check('the stratagem log lists it', new RegExp(`B ${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`).test(await pt('#strat-log')));
    await pp.locator('#play-strats').scrollIntoViewIfNeeded();
    await pp.screenshot({ path: join(SHOTS, 'calc_108_strats_now.png') });
    await pp.tap('#play-undo');
    await pp.waitForFunction(() => (window.__calc.mission().game.strats ?? []).length === 0);
    check('Undo takes it back (the CP too)', (await pp.evaluate(() => window.__calc.mission().game.B.cp)) === cpB);
    await pctx.close();
  }

  // --- 1.116: layouts stamped and measured for set-up, how an attack usually goes, saved lists against today's points
  {
    const vctx = await browser.newContext({ ...devices['Pixel 7'] });
    const vp = await vctx.newPage();
    vp.on('pageerror', e => consoleErrors.push(`1.116: ${e}`));
    vp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`1.116: ${m.text()}`); });
    vp.on('dialog', d => d.accept());
    await vp.goto(`${BASE}/calc/`); await vp.waitForSelector('textarea[data-side="A"]');
    // the library: an old Ork list (10th edition prices) against today's points
    await vp.fill('textarea[data-side="B"]', ORK_LIST); await vp.tap('button[data-action="parse"][data-side="B"]');
    check('army card: what the list costs with today’s points', /With today’s points the list costs 730 of 1000 \(listed 665\)/.test((await vp.textContent('#points-now-B')).replace(/\s+/g, ' ')));
    await vp.tap('button[data-action="open-library"][data-side="B"]');
    await vp.fill('input[data-input="lib-name"]', 'Old Orks'); await vp.tap('button[data-action="lib-save"]');
    const lp = vp.locator('.sheet .pick', { hasText: 'Old Orks' }).locator('[data-lib-points]');
    await lp.locator('summary').tap();
    const lt = (await lp.textContent()).replace(/\s+/g, ' ');
    check('📚 library: each saved list says which units cost something else now, and its total today', /3 units cost something else now: 665 → 730 of 1000/.test(lt) && /Warboss: 70 → 100/.test(lt), lt);
    await vp.screenshot({ path: join(SHOTS, 'calc_109_library_points.png') });
    await vp.tap('.sheet button[data-action="close-sheet"]');
    await vp.fill('textarea[data-side="A"]', SW_LIST); await vp.tap('button[data-action="parse"][data-side="A"]');
    // Attack: 9 in 10 / 1 in 2 / 1 in 10
    await vp.tap('button[data-action="view"][data-value="attack"]');
    await vp.waitForSelector('select[data-input="target"]');
    const tv = await vp.$eval('select[data-input="target"]', (sel) => [...sel.options].find(o => /Warboss \+ Boyz/.test(o.textContent))?.value);
    await vp.selectOption('select[data-input="target"]', tv);
    await vp.tap('button[data-action="open-add"]');
    await vp.tap('.pick:has-text("Grey Hunters")');
    await vp.waitForFunction(() => !!window.__calc.state.result && !window.__calc.state.busy, null, { timeout: 60000 });
    await vp.tap('button[data-action="open-results"]');
    await vp.waitForSelector('#res-spread');
    const sp = await vp.$$eval('#res-spread tbody tr', trs => trs.map(tr => [...tr.cells].map(c => c.textContent.trim())));
    const ok = sp.length === 2 && sp.every(r => { const [a, b, c] = r.slice(1).map(x => Number(x.replace('+', ''))); return a <= b && b <= c; });
    check('Attack details: at least … 9 in 10 / 1 in 2 / 1 in 10, for models destroyed and damage (in order)', ok, JSON.stringify(sp));
    await vp.locator('#res-spread').scrollIntoViewIfNeeded();
    await vp.screenshot({ path: join(SHOTS, 'calc_110_attack_spread.png') });
    await vp.tap('.sheet button[data-action="close-sheet"]');
    // Board: the layout's source, and the set-up measurements
    await vp.tap('button[data-action="view"][data-value="board"]');
    await vp.waitForSelector('#board-svg');
    check('Board: the layouts’ source is stated (Event Companion v1.3, unchanged since v1.2, how they were checked)', /Layouts: Event Companion v1\.3 \(October 2026; layouts unchanged since v1\.2, August 2026\)\. Checked 24 November 2026: 12 of 45 compared with the official PDF/.test((await vp.textContent('#board-layout-source')).replace(/\s+/g, ' ')));
    await vp.tap('#board-measure-chip');
    await vp.waitForSelector('#board-measure');
    const ms = await vp.evaluate(() => ({ pieces: document.querySelectorAll('#board-measure [data-measure]').length, objs: document.querySelectorAll('#board-measure [data-measure-obj]').length, first: document.querySelector('#board-measure [data-measure] text')?.textContent, n: window.__calc.board().layout }));
    check('📏 Table set-up measurements: every terrain piece and objective labelled in inches from the nearest edges', ms.pieces >= 10 && ms.objs >= 5 && /^↔[\d½¼¾]+" ↕[\d½¼¾]+"$/.test(ms.first ?? ''), JSON.stringify(ms));
    await vp.locator('#board-host').scrollIntoViewIfNeeded();
    await vp.screenshot({ path: join(SHOTS, 'calc_111_setup_measure.png') });
    await vctx.close();
  }

  // --- 1.117: exposure heat map — how much of the enemy can reach each square next turn; tap a square for who
  {
    const hctx = await browser.newContext({ ...devices['Pixel 7'] });
    const hp = await hctx.newPage();
    hp.on('pageerror', e => consoleErrors.push(`heat: ${e}`));
    hp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`heat: ${m.text()}`); });
    await hp.goto(`${BASE}/calc/`); await hp.waitForSelector('textarea[data-side="A"]');
    await hp.fill('textarea[data-side="A"]', SW_LIST); await hp.tap('button[data-action="parse"][data-side="A"]');
    await hp.fill('textarea[data-side="B"]', ORK_LIST); await hp.tap('button[data-action="parse"][data-side="B"]');
    await hp.tap('button[data-action="view"][data-value="board"]');
    await hp.waitForSelector('#board-svg');
    for (const n of ['Meganobz', 'Flash Gitz']) await hp.locator('button[data-action="board-place"][data-side="B"]', { hasText: n }).first().tap();
    const toks = await hp.evaluate(() => window.__calc.board().units.map(u => ({ tk: u.tk, n: u.models.length })));
    const MN = toks.find(t => t.n === 3).tk, FG = toks.find(t => t.n === 5).tk;
    await hp.evaluate(([mn, fg]) => { const s = window.__calc.board().stepTokens; s[mn] = { ...s[mn], x: 22, y: 20 }; s[fg] = { ...s[fg], x: 30, y: 14 }; document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); }, [MN, FG]);
    await hp.tap('button[data-action="board-danger"][data-value="B"]');
    await hp.tap('#board-heat-chip');
    await hp.waitForSelector('#heat-layer');
    const h = await hp.evaluate(() => ({ cells: document.querySelectorAll('#heat-layer rect').length, max: Number(document.getElementById('heat-layer').dataset.max) }));
    check('🔥 Heat map: every square the Orks can reach next turn is shaded, darkest where most of them can (shoot + charge chance)', h.cells > 200 && h.max > 1.5 && h.max <= 4, JSON.stringify(h));
    // tap an empty square next to the Meganobz (5" away): who can reach it
    await hp.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'center' }));
    const box = await hp.locator('#board-svg').boundingBox();
    const vb = await hp.evaluate(() => { const v = document.getElementById('board-svg').viewBox.baseVal; return { x: v.x, y: v.y, w: v.width, h: v.height }; });
    const sx = box.x + (22 - vb.x) / vb.w * box.width, sy = box.y + (26 - vb.y) / vb.h * box.height;
    await hp.mouse.click(sx, sy);
    await hp.waitForSelector('#heat-at');
    const info = (await hp.textContent('#board-heat-info')).replace(/\s+/g, ' ');
    check('tap a square: the units that can reach it, with each one’s charge chance', /At 2\d" across, 2\d" down:/.test(info) && /Meganobz [^·]*charge \d+%/.test(info) && /Flash Gitz shoot/.test(info), info);
    await hp.locator('#board-host').scrollIntoViewIfNeeded();
    await hp.screenshot({ path: join(SHOTS, 'calc_112_heat_map.png') });
    await hctx.close();
  }

  // --- 1.117: my statistics from saved games
  {
    const sctx = await browser.newContext({ ...devices['Pixel 7'] });
    const sp = await sctx.newPage();
    sp.on('pageerror', e => consoleErrors.push(`stats: ${e}`));
    sp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`stats: ${m.text()}`); });
    sp.on('dialog', d => d.accept());
    await sp.goto(`${BASE}/calc/`); await sp.waitForSelector('textarea[data-side="A"]');
    await sp.fill('textarea[data-side="A"]', SW_LIST); await sp.tap('button[data-action="parse"][data-side="A"]');
    await sp.fill('textarea[data-side="B"]', ORK_LIST); await sp.tap('button[data-action="parse"][data-side="B"]');
    await sp.tap('#games-card > summary').catch(() => {});
    check('no finished game yet: the stats say how they will appear', /appear here once a saved game has ended/.test(await sp.textContent('#my-stats')));
    // a game: A goes first, scores, the battle is ended (it saves itself)
    await sp.tap('button[data-action="view"][data-value="mission"]');
    await sp.tap('button[data-action="mission-table"]').catch(() => {});
    await sp.tap('button[data-action="mission-tab"][data-value="play"]').catch(() => {});
    await sp.waitForSelector('#play-bar');
    await sp.tap('button[data-action="mission-first"][data-value="A"]').catch(() => {});
    for (const [side, k] of [['A', 'primary'], ['A', 'primary'], ['A', 'secondary'], ['B', 'primary']]) await sp.tap(`button[data-action="mission-score-step"][data-side="${side}"][data-k="${k}"][data-delta="5"]`);
    for (let i = 0; i < 10; i++) { if (await sp.isDisabled('#play-turn-done')) break; await sp.tap('#play-turn-done'); }
    await sp.waitForFunction(() => window.__calc.mission().game?.over === true || window.__calc.state.mission?.game?.over === true);
    await sp.waitForFunction(() => window.__calc.state.games.length === 1);
    await sp.tap('button[data-action="view"][data-value="armies"]');
    await sp.waitForSelector('#games-card');
    if (!(await sp.evaluate(() => document.getElementById('games-card').open))) await sp.tap('#games-card > summary');
    await sp.tap('#my-stats > summary');
    const txt = (await sp.textContent('#my-stats')).replace(/\s+/g, ' ');
    const byOpp = await sp.$$eval('#my-stats [data-stats="oppFaction"] tbody tr', trs => trs.map(t => [...t.cells].map(c => c.textContent.trim()).join(' ')));
    check('📊 My statistics: the finished game counted — 1 game, 1-0-0, the score with Battle Ready, by opponent / mission / layout / going first', /1 game, 1-0-0 \(100%\)/.test(txt) && /Average score 25–15/.test(txt) && byOpp.length === 1 && /Orks 1 1-0-0 100% 25–15/.test(byOpp[0]) && /Going first/.test(txt) && /By mission \(my primary\)/.test(txt), `${txt} | ${byOpp}`);
    await sp.locator('#my-stats').scrollIntoViewIfNeeded();
    await sp.screenshot({ path: join(SHOTS, 'calc_113_my_stats.png') });
    await sctx.close();
  }

  // --- 1.118: deployment drop-order drill — one unit at a time from the Defender, in a plan of its own
  {
    const dctx = await browser.newContext({ ...devices['Pixel 7'] });
    const dp = await dctx.newPage();
    dp.on('pageerror', e => consoleErrors.push(`drill: ${e}`));
    dp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`drill: ${m.text()}`); });
    await dp.goto(`${BASE}/calc/`); await dp.waitForSelector('textarea[data-side="A"]');
    await dp.fill('textarea[data-side="A"]', SW_LIST); await dp.tap('button[data-action="parse"][data-side="A"]');
    await dp.fill('textarea[data-side="B"]', ORK_LIST); await dp.tap('button[data-action="parse"][data-side="B"]');
    await dp.tap('button[data-action="view"][data-value="board"]');
    await dp.waitForSelector('#board-svg');
    // the real deployment: one Space Wolves unit already placed
    await dp.locator('button[data-action="board-place"][data-side="A"]').first().tap();
    const realTk = await dp.evaluate(() => window.__calc.board().units[0]?.tk);
    const n = await dp.evaluate(() => ({ A: window.__calc.state.armies.A.units.length, B: window.__calc.state.armies.B.units.length }));
    await dp.tap('#board-drill-ask');
    await dp.waitForSelector('#board-drill-start');
    await dp.tap('#board-drill-start button[data-first="B"]');
    await dp.waitForSelector('#board-drill');
    const t1 = (await dp.textContent('#board-drill-turn')).replace(/\s+/g, ' ');
    const sides1 = await dp.$$eval('#board-drill-tray button[data-action="board-place"]', bs => [...new Set(bs.map(b => b.dataset.side))]);
    const empty = await dp.evaluate(() => window.__calc.board().units.length);
    check('🎯 Drop drill: the Defender (B) sets up first; only B’s units are offered; the drill board starts empty', /Drop 1: B/.test(t1) && sides1.join() === 'B' && empty === 0, `${t1} | ${sides1} | on board ${empty}`);
    const left0 = (await dp.textContent('#board-drill-left')).replace(/\s+/g, ' ');
    check('units left per side, and who finishes first', left0.includes(`A ${n.A} · B ${n.B}`) && /finishes first/.test(left0), left0);
    await dp.locator('#board-drill-tray button[data-action="board-place"]').first().tap();
    const t2 = (await dp.textContent('#board-drill-turn')).replace(/\s+/g, ' ');
    const sides2 = await dp.$$eval('#board-drill-tray button[data-action="board-place"]', bs => [...new Set(bs.map(b => b.dataset.side))]);
    check('after B’s drop it is A’s turn (A’s units only)', /Drop 2: A/.test(t2) && sides2.join() === 'A', `${t2} | ${sides2}`);
    // A puts a unit in reserves: it is not set up, so A has one fewer drop; still A's turn
    await dp.locator('#board-drill-tray button[data-action="board-drill-res"]').first().tap();
    const left1 = (await dp.textContent('#board-drill-left')).replace(/\s+/g, ' ');
    const t3 = (await dp.textContent('#board-drill-turn')).replace(/\s+/g, ' ');
    check('⤓ reserves: that unit is not set up (A has one fewer to set up); still A’s drop', left1.includes(`A ${n.A - 1} · B ${n.B - 1}`) && /Drop 2: A/.test(t3) && await dp.locator('#board-drill-res button').count() === 1, `${left1} | ${t3}`);
    await dp.locator('#board-drill-tray button[data-action="board-place"]').first().tap();
    await dp.locator('#board-drill-tray button[data-action="board-place"]').first().tap();
    const t4 = (await dp.textContent('#board-drill-turn')).replace(/\s+/g, ' ');
    const log = await dp.$$eval('#board-drill-log li', ls => ls.map(l => l.textContent.trim()[0]));
    check('the order so far: B, A, B — and A to set up next', /Drop 4: A/.test(t4) && log.join('') === 'BAB', `${t4} | ${log.join('')}`);
    await dp.tap('#board-drill-undo');
    const t5 = (await dp.textContent('#board-drill-turn')).replace(/\s+/g, ' ');
    const on5 = await dp.evaluate(() => window.__calc.board().units.length);
    check('↶ Undo takes the last unit back off the board and gives that player the drop again', /Drop 3: B/.test(t5) && on5 === 2, `${t5} | on board ${on5}`);
    // reload: the drill is kept with the plan
    await dp.reload(); await dp.waitForSelector('#board-svg');
    const t6 = await dp.textContent('#board-drill-turn').catch(() => '');
    check('the drill survives a reload', /Drop 3: B/.test(t6 ?? ''), t6);
    await dp.locator('#board-drill-tray button[data-action="board-place"]').first().tap();
    await dp.evaluate(() => document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click());
    await dp.screenshot({ path: join(SHOTS, 'calc_114_drop_drill.png') });
    // the real deployment is untouched
    await dp.locator('#board-variants button[data-action="board-plan-pick"]').first().tap();
    const main = await dp.evaluate(() => window.__calc.board().units.map(u => u.tk));
    check('your real deployment (the first plan) is untouched by the drill', main.length === 1 && main[0] === realTk, JSON.stringify(main));
    await dp.locator('#board-variants button[data-action="board-plan-pick"]', { hasText: 'Drop drill' }).tap();
    await dp.tap('#board-drill-end');
    const ended = await dp.evaluate(() => ({ drill: !!document.getElementById('board-drill'), units: window.__calc.board().units.length }));
    check('End drill: the set-up stays as a plan of its own', !ended.drill && ended.units === 3, JSON.stringify(ended));
    await dctx.close();
  }

  // --- 1.119: read-only share links — the lists, the attack set-up and the board plan inside the link
  {
    const mk = async (tag) => {
      const c = await browser.newContext({ ...devices['Pixel 7'] });
      const pg = await c.newPage();
      pg.on('pageerror', e => consoleErrors.push(`${tag}: ${e}`));
      pg.on('console', m => { if (m.type() === 'error') consoleErrors.push(`${tag}: ${m.text()}`); });
      pg.on('dialog', d => d.accept());
      return { c, pg };
    };
    // the sharer: both lists, two units on the board
    const { c: c1, pg: s1 } = await mk('share-from');
    await s1.goto(`${BASE}/calc/`); await s1.waitForSelector('textarea[data-side="A"]');
    await s1.fill('textarea[data-side="A"]', SW_LIST); await s1.tap('button[data-action="parse"][data-side="A"]');
    await s1.fill('textarea[data-side="B"]', ORK_LIST); await s1.tap('button[data-action="parse"][data-side="B"]');
    await s1.tap('button[data-action="view"][data-value="board"]');
    await s1.waitForSelector('#board-svg');
    await s1.locator('button[data-action="board-place"][data-side="A"]').first().tap();
    await s1.locator('button[data-action="board-place"][data-side="B"]').first().tap();
    const mine = await s1.evaluate(() => window.__calc.board().units.map(u => `${u.tk}@${u.x},${u.y}`).sort());
    await s1.tap('#share-board');
    await s1.waitForSelector('#share-link-url');
    const url = await s1.inputValue('#share-link-url');
    const box = (await s1.textContent('#share-link-box')).replace(/\s+/g, ' ');
    check('🔗 Board → Share link: a link with the lists and plan inside it (no server)', url.startsWith(`${BASE}/calc/#s=`) && url.length < 12000 && /board plan/.test(box), `${url.length} chars | ${box.slice(0, 120)}`);
    await s1.locator('#share-link-box').scrollIntoViewIfNeeded();
    await s1.screenshot({ path: join(SHOTS, 'calc_115_share_link.png') });
    // the attack set-up can be shared too (Saved sheet)
    await s1.tap('button[data-action="view"][data-value="attack"]');
    await s1.waitForSelector('select[data-input="target"]');
    const tv = await s1.$eval('select[data-input="target"]', (sel) => [...sel.options].find(o => /Warboss \+ Boyz/.test(o.textContent))?.value);
    await s1.selectOption('select[data-input="target"]', tv);
    await s1.tap('button[data-action="open-add"]');
    await s1.tap('.pick:has-text("Grey Hunters")');
    await s1.tap('button[data-action="open-saved"]');
    const hasAtk = await s1.locator('#share-attack').count();
    let atkUrl = '';
    if (hasAtk) { await s1.tap('#share-attack'); await s1.waitForSelector('#share-link-url'); atkUrl = await s1.inputValue('#share-link-url'); }
    check('Attack → 💾 Saved → share this set-up as a link', hasAtk === 1 && atkUrl.includes('#s='), `${hasAtk} ${atkUrl.length}`);
    await c1.close();

    // the viewer has their own list loaded; opening the link must not change it
    const { c: c2, pg: v } = await mk('share-to');
    await v.goto(`${BASE}/calc/`); await v.waitForSelector('textarea[data-side="A"]');
    await v.fill('textarea[data-side="A"]', ORK_LIST); await v.tap('button[data-action="parse"][data-side="A"]');
    const before = await v.evaluate(() => ({ main: localStorage.getItem('w40k_calc_v1'), board: localStorage.getItem('w40k_calc_board_v1') }));
    await v.goto(url);
    await v.waitForSelector('#shared-banner #shared-keep');
    await v.waitForSelector('#board-svg');
    const seen = await v.evaluate(() => window.__calc.board().units.map(u => `${u.tk}@${u.x},${u.y}`).sort());
    const banner = (await v.textContent('#shared-banner')).replace(/\s+/g, ' ');
    check('opening the link: the Board with the same units in the same places, under a read-only banner', JSON.stringify(seen) === JSON.stringify(mine) && /Shared: .*Space Wolves.*vs.*Orks.*board plan/.test(banner) && /Read-only/.test(banner), `${JSON.stringify(seen)} vs ${JSON.stringify(mine)} | ${banner.slice(0, 140)}`);
    await v.screenshot({ path: join(SHOTS, 'calc_116_shared_view.png') });
    // try something in the view (place another unit): nothing is saved
    await v.locator('button[data-action="board-place"]').first().tap();
    const during = await v.evaluate(() => ({ main: localStorage.getItem('w40k_calc_v1'), board: localStorage.getItem('w40k_calc_board_v1') }));
    check('while viewing, nothing is written to this device (own lists and plans untouched)', during.main === before.main && during.board === before.board);
    await v.tap('#shared-close');
    await v.waitForSelector('textarea[data-side="A"]');
    const after = await v.evaluate(() => ({ hash: location.hash, A: window.__calc.state.armies.A?.faction ?? null, B: window.__calc.state.armies.B?.faction ?? null, banner: !!document.getElementById('shared-banner') }));
    check('Close: back to your own lists (Orks in A, nothing in B), the link gone', after.hash === '' && /Ork/.test(after.A ?? '') && after.B === null && !after.banner, JSON.stringify(after));
    // open again and keep a copy: saved, and still there after a reload
    await v.goto(url);
    await v.waitForSelector('#shared-keep');
    await v.tap('#shared-keep');
    await v.waitForFunction(() => !document.getElementById('shared-banner'));
    await v.goto(`${BASE}/calc/`);
    await v.tap('button[data-action="view"][data-value="board"]').catch(() => {});
    await v.waitForSelector('#board-svg');
    const kept = await v.evaluate(() => window.__calc.board().units.map(u => `${u.tk}@${u.x},${u.y}`).sort());
    check('Keep a copy: the lists and the plan are saved on this device', JSON.stringify(kept) === JSON.stringify(mine), JSON.stringify(kept));
    // a cut-short link says so
    await v.goto(url.slice(0, url.indexOf('#s=') + 40));
    await v.waitForSelector('#shared-error');
    check('a link cut short when copied says so (and changes nothing)', /incomplete or damaged/.test(await v.textContent('#shared-error')));
    // the attack link opens on the Attack tab with the same attacker and target
    await v.goto(atkUrl);
    await v.waitForSelector('#shared-keep');
    await v.waitForSelector('[data-attacker]');
    const atk = await v.evaluate(() => ({ view: window.__calc.state.view, n: document.querySelectorAll('[data-attacker]').length, txt: document.querySelector('[data-attacker]')?.textContent ?? '', tgt: document.querySelector('select[data-input="target"]')?.selectedOptions[0]?.textContent ?? '' }));
    check('an attack link opens on Attack with the same attacker and target', atk.view === 'attack' && atk.n === 1 && /Grey Hunters/.test(atk.txt) && /Warboss \+ Boyz/.test(atk.tgt), JSON.stringify({ ...atk, txt: atk.txt.slice(0, 40) }));
    await c2.close();
  }

  // --- 1.120: Scout moves planned on the Deploy step — a dashed ghost you drag, checked against 24.32
  {
    const sctx = await browser.newContext({ ...devices['Pixel 7'] });
    const sp = await sctx.newPage();
    sp.on('pageerror', e => consoleErrors.push(`scout: ${e}`));
    sp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`scout: ${m.text()}`); });
    await sp.goto(`${BASE}/calc/`); await sp.waitForSelector('textarea[data-side="A"]');
    await sp.fill('textarea[data-side="A"]', SW_LIST); await sp.tap('button[data-action="parse"][data-side="A"]');
    await sp.fill('textarea[data-side="B"]', ORK_LIST); await sp.tap('button[data-action="parse"][data-side="B"]');
    await sp.tap('button[data-action="view"][data-value="board"]');
    await sp.waitForSelector('#board-svg');
    await sp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Scout Squad (1)' }).tap();
    await sp.waitForSelector('#board-scout');
    const head = (await sp.textContent('#board-scout')).replace(/\s+/g, ' ');
    await sp.tap('#board-scout-chip');
    await sp.waitForSelector('[data-scout]');
    const s1 = await sp.evaluate(() => ({ ok: document.querySelector('[data-scout]').dataset.ok, label: document.querySelector('[data-scout] text').textContent, panel: document.getElementById('board-scout').textContent.replace(/\s+/g, ' ') }));
    check('🏃 Scout Squad: “Plan a Scout move” draws a dashed ghost up to its Scouts distance toward the middle, legal', /Scouts \d+"/.test(head) && s1.ok === '1' && /^Scout \d\.\d"\/\d+"$/.test(s1.label) && /✓/.test(s1.panel), `${head.slice(0, 60)} | ${JSON.stringify(s1)}`);
    // drag the ghost a long way: too far, flagged
    await sp.evaluate(() => { document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); document.getElementById('board-host').scrollIntoView({ block: 'center' }); });
    const gb = await sp.locator('[data-scout] rect.scout-grab').boundingBox();
    const box = await sp.locator('#board-svg').boundingBox();
    const cx = gb.x + gb.width / 2, cy = gb.y + gb.height / 2, inch = box.width / 44;
    await sp.mouse.move(cx, cy); await sp.mouse.down();
    for (let i = 1; i <= 8; i++) await sp.mouse.move(cx, cy + i * 1.2 * inch);
    await sp.mouse.up();
    await sp.waitForFunction(() => document.querySelector('[data-scout]')?.dataset.ok === '0');
    const warn = (await sp.textContent('#board-warnings').catch(() => '')).replace(/\s+/g, ' ');
    check('dragged further than its Scout move: the ghost turns red and the step check says by how much', /Scout move: moves \d+\.\d": more than its \d+" Scout move/.test(warn), warn.slice(0, 200));
    await sp.screenshot({ path: join(SHOTS, 'calc_117_scout_move.png') });
    const scoutPos = await sp.evaluate(() => { const k = Object.keys(window.__calc.board().stepTokens).find(t => window.__calc.board().stepTokens[t].scout); return { k, ...window.__calc.board().stepTokens[k].scout }; });
    await sp.tap('button[data-action="board-step-add"]');
    const t1 = await sp.evaluate((k) => window.__calc.board().stepTokens[k], scoutPos.k);
    check('＋ Next turn: Turn 1 starts where the Scout move ends', Math.abs(t1.x - scoutPos.x) < 0.01 && Math.abs(t1.y - scoutPos.y) < 0.01 && !t1.scout, JSON.stringify({ t1, scoutPos }));
    const ghostT1 = await sp.locator('[data-scout]').count();
    check('no Scout ghosts on Turn 1 (pre-game only)', ghostT1 === 0, String(ghostT1));
    await sctx.close();
  }

  // --- 1.121: list gap-finder — the whole list against eight fixed reference targets
  {
    const gctx = await browser.newContext({ ...devices['Pixel 7'] });
    const gp = await gctx.newPage();
    gp.on('pageerror', e => consoleErrors.push(`gaps: ${e}`));
    gp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`gaps: ${m.text()}`); });
    await gp.goto(`${BASE}/calc/`); await gp.waitForSelector('textarea[data-side="A"]');
    await gp.fill('textarea[data-side="A"]', SW_LIST); await gp.tap('button[data-action="parse"][data-side="A"]');
    await gp.tap('#gaps-A');
    await gp.waitForSelector('#gaps-host');
    await gp.waitForFunction(() => /matchups · 1,000 rolls each/.test(document.getElementById('gaps-progress')?.textContent ?? ''), null, { timeout: 180000 });
    const rows = await gp.$$eval('.gap-row', rs => rs.map(r => ({ id: r.dataset.gap, level: r.dataset.level, txt: r.textContent.replace(/\s+/g, ' ').trim() })));
    const num = (r) => Number(r.txt.match(/A turn removes ([\d.]+) of these/)?.[1]);
    const horde = rows.find(r => r.id === 'horde'), knight = rows.find(r => r.id === 'knight');
    check('🔍 What is this list missing: eight reference targets, each with what a turn removes and the best units', rows.length === 8 && rows.every(r => /A turn removes [\d.]+ of these: shooting [\d.]+ · fight [\d.]+/.test(r.txt)) && /Best: /.test(horde.txt), JSON.stringify(rows.map(r => `${r.id}:${r.level}:${num(r)}`)));
    check('a horde of light infantry comes off far more easily than a Knight (sanity of the numbers)', num(horde) > 1.5 * num(knight) && num(knight) > 0, `${num(horde)} vs ${num(knight)}`);
    check('the weakest matchup is flagged', rows.filter(r => / · weakest/.test(r.txt)).length >= 1, rows.map(r => r.txt.slice(0, 30)).join(' | '));
    await gp.screenshot({ path: join(SHOTS, 'calc_118_list_gaps.png') });
    await gctx.close();
  }

  // --- 1.122: printable game-day sheet (Intel → 🖨): their units, tricks, stratagems, my army by phase; no rule text
  {
    const pctx = await browser.newContext({ ...devices['Pixel 7'] });
    const pp = await pctx.newPage();
    pp.on('pageerror', e => consoleErrors.push(`print: ${e}`));
    pp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`print: ${m.text()}`); });
    await pp.goto(`${BASE}/calc/`); await pp.waitForSelector('textarea[data-side="A"]');
    await pp.fill('textarea[data-side="A"]', SW_LIST); await pp.tap('button[data-action="parse"][data-side="A"]');
    await pp.fill('textarea[data-side="B"]', ORK_LIST); await pp.tap('button[data-action="parse"][data-side="B"]');
    await pp.tap('button[data-action="view"][data-value="intel"]');
    await pp.tap('#open-print');
    await pp.waitForSelector('#print-preview .ps');
    const pv = await pp.evaluate(() => {
      const el = document.getElementById('print-preview');
      return { nB: window.__calc.state.armies.B.units.length, txt: el.textContent.replace(/\s+/g, ' '), units: el.querySelectorAll('.ps-t tbody tr').length, boxes: el.querySelectorAll('.ps-box').length, h2: [...el.querySelectorAll('h2')].map(h => h.textContent) };
    });
    check('🖨 Intel → Game-day sheet: their units (one row each), plan-around notes, their stratagems by turn, your army by phase', pv.units === pv.nB && pv.h2.includes('Their units') && pv.h2.includes('Their stratagems in your turn') && pv.h2.includes('Your army, phase by phase') && /Warboss \+ Boyz/.test(pv.txt) && /M6" T5 Sv5\+ W1 OC2/.test(pv.txt), JSON.stringify({ units: pv.units, h2: pv.h2, sample: pv.txt.slice(0, 200) }));
    // no rule text: the stratagem "When:" / "Effect:" lines of the Intel tab are not on the sheet
    const strats = await pp.evaluate(() => window.__calc.state.armies.B && document.querySelector('#print-preview').textContent);
    check('names, costs and phases only: no “When:” / “Effect:” rule text on the sheet; once-per-battle rules get a ☐', !/When:|Effect:/.test(strats) && pv.boxes >= 1, `boxes ${pv.boxes}`);
    await pp.screenshot({ path: join(SHOTS, 'calc_119_print_sheet.png') });
    // the printed page: only the sheet (print media)
    await pp.evaluate(() => { window.print = () => { window.__printed = true; }; });
    await pp.tap('#print-go');
    await pp.emulateMedia({ media: 'print' });
    const printed = await pp.evaluate(() => ({ called: !!window.__printed, root: getComputedStyle(document.getElementById('print-root')).display, app: getComputedStyle(document.getElementById('app') ?? document.querySelector('main')).display, rows: document.querySelectorAll('#print-root .ps-t tbody tr').length }));
    check('Print: only the sheet is printed (the app is hidden in print)', printed.called && printed.root === 'block' && printed.rows === pv.nB, JSON.stringify(printed));
    const pdf = await pp.pdf({ format: 'A4' }).catch(() => null);
    check('it prints as a PDF', !!pdf && pdf.length > 5000, String(pdf?.length));
    if (pdf) { const { writeFileSync } = await import('fs'); writeFileSync(join(SHOTS, 'calc_119_print_sheet.pdf'), pdf); }
    await pp.emulateMedia({ media: 'screen' });
    await pctx.close();
  }

  // --- 1.123: what a unit can see (shaded squares) and hull sizes you measured
  {
    const vctx = await browser.newContext({ ...devices['Pixel 7'] });
    const vp = await vctx.newPage();
    vp.on('pageerror', e => consoleErrors.push(`see: ${e}`));
    vp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`see: ${m.text()}`); });
    await vp.goto(`${BASE}/calc/`); await vp.waitForSelector('textarea[data-side="A"]');
    await vp.fill('textarea[data-side="A"]', SW_LIST); await vp.tap('button[data-action="parse"][data-side="A"]');
    await vp.fill('textarea[data-side="B"]', ORK_LIST); await vp.tap('button[data-action="parse"][data-side="B"]');
    await vp.tap('button[data-action="view"][data-value="board"]');
    await vp.waitForSelector('#board-svg');
    await vp.locator('button[data-action="board-place"][data-side="A"]', { hasText: 'Grey Hunters' }).tap();
    await vp.tap('button[data-action="board-ring"][data-k="see"]');
    await vp.waitForSelector('#see-layer');
    const note = await vp.textContent('#board-see-note').catch(() => '');
    const seen = await vp.evaluate(() => ({ n: Number(document.getElementById('see-layer').dataset.seen), rects: document.querySelectorAll('#see-layer rect').length }));
    check('👁 What it can see: the squares where a model would be visible to the unit are shaded (terrain hides the rest)', seen.n > 200 && seen.n < 2640 && seen.rects > 10 && /not a table ruling/.test(note), JSON.stringify(seen));
    await vp.evaluate(() => { document.querySelector('button[data-action="board-zoom"][data-z="0"]')?.click(); document.getElementById('board-host').scrollIntoView({ block: 'start' }); });
    await vp.screenshot({ path: join(SHOTS, 'calc_120_what_it_sees.png') });
    // hull: the Battlewagon has no hull size in the data; enter the one you measured
    await vp.locator('button[data-action="board-place"][data-side="B"]', { hasText: 'Battlewagon' }).tap();
    await vp.waitForSelector('#board-hull');
    const before = (await vp.textContent('#board-hull')).replace(/\s+/g, ' ');
    const inp = vp.locator('#board-hull input[data-dim="l"]');
    await inp.fill('9'); await inp.dispatchEvent('change');
    await vp.waitForFunction(() => /your measurement/.test(document.getElementById('board-hull')?.textContent ?? ''));
    const fp = await vp.evaluate(() => { const u = window.__calc.board().units.find(t => t.tk.startsWith('B:') && t.models[0]?.fp?.shape === 'rect'); return u?.models[0]?.fp ?? null; });
    check('Hull: “rough size” until you enter your model’s length × width; the board then measures from it', /rough size/.test(before) && fp?.measured && Math.abs(fp.hw - 4.5) < 0.01, JSON.stringify({ before: before.slice(0, 80), fp }));
    await vp.reload(); await vp.waitForSelector('#board-svg');
    const kept = await vp.evaluate(() => JSON.parse(localStorage.getItem('w40k_calc_hulls_v1') ?? '{}'));
    check('the hull size is kept on this device', Object.values(kept).some(h => h.l === 9), JSON.stringify(kept));
    await vctx.close();
  }

  // --- tablet Board in three columns (1.127.0): me | map | opponent; portrait: map on top, armies below
  {
    const tctx3 = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
    const tp3 = await tctx3.newPage();
    tp3.on('pageerror', e => consoleErrors.push(`tri: ${e}`));
    tp3.on('console', m => { if (m.type() === 'error') consoleErrors.push(`tri: ${m.text()}`); });
    const t3 = async (q) => (await tp3.textContent(q)).replace(/\s+/g, ' ').trim();
    const bs = () => tp3.evaluate(() => ({ sel: window.__calc.board().sel, sel2: window.__calc.board().sel2, danger: window.__calc.state.board.danger ?? null, arrive: window.__calc.state.board.arrive ?? null }));
    const rect = (q) => tp3.evaluate((qq) => { const b = document.querySelector(qq)?.getBoundingClientRect(); return b ? { l: b.left, r: b.right, t: b.top, b: b.bottom, w: b.width } : null; }, q);
    await tp3.goto(`${BASE}/calc/`); await tp3.waitForSelector('textarea[data-side="A"]');
    await tp3.fill('textarea[data-side="A"]', SW_LIST); await tp3.tap('button[data-action="parse"][data-side="A"]');
    await tp3.fill('textarea[data-side="B"]', ORK_LIST); await tp3.tap('button[data-action="parse"][data-side="B"]');
    await tp3.tap('button[data-action="view"][data-value="board"]');
    await tp3.waitForSelector('#board-tri');
    // Deploy: each army's disposition and its units to place, in its own column
    check('tablet Board: three columns — my army (A) left, the map in the middle, B right; no dock',
      (await tp3.locator('#board-army-A.tri-l').count()) === 1 && (await tp3.locator('#board-army-B.tri-r').count()) === 1 && (await tp3.locator('#board-dock').count()) === 0);
    check('Deploy step: each column has its Force Disposition and the units still to place',
      (await tp3.locator('#board-army-A select[data-input="board-disp"]').count()) === 1 && (await tp3.locator('#board-army-B select[data-input="board-disp"]').count()) === 1
      && /Plays Battlefield Dominance/.test(await t3('#board-army-B')) && (await tp3.locator('#board-army-A button.tri-unit[data-action="board-place"]').count()) === 8);
    await tp3.locator('#board-army-A button[data-action="board-place"]', { hasText: 'Grey Hunters' }).tap();
    await tp3.locator('#board-army-B button[data-action="board-place"]', { hasText: 'Warboss + Boyz' }).tap();
    await tp3.evaluate(() => window.scrollTo(0, 0));
    await tp3.screenshot({ path: join(SHOTS, 'calc_126_tablet_deploy.png') });
    await tp3.tap('button[data-action="board-step-add"]');
    // the lists select units: mine, then theirs as the target -> the matchup card in their column
    const gh = await tp3.evaluate(() => window.__calc.board().tokens.find(t => t.tk.startsWith('A:')).tk);
    const wb = await tp3.evaluate(() => window.__calc.board().tokens.find(t => t.tk.startsWith('B:')).tk);
    // placing the Warboss selected it: a tap on its row again clears the selection (as on the map)
    { const cur = (await bs()).sel; if (cur) await tp3.locator(`button[data-action="board-pick"][data-tk="${cur}"]`).tap(); }
    check('a tap on the selected unit\'s row clears the selection', (await bs()).sel === null);
    await tp3.locator(`#board-army-A button[data-action="board-pick"][data-tk="${gh}"]`).tap();
    check('a tap on my unit in my list selects it: its panel opens under its row, rings first, position folded',
      (await bs()).sel === gh && (await tp3.locator('#board-army-A .tri-selbox #board-panel button[data-action="board-ring"][data-k="move"]').count()) === 1 && (await tp3.locator('#board-pos-box').count()) === 0);
    await tp3.tap('#board-pos-toggle');
    check('"Position · facing · formation" unfolds the facing, nudge and formation controls', (await tp3.locator('#board-pos-box button[data-action="board-rotate"]').count()) === 4 && (await tp3.locator('#board-pos-box button[data-action="board-formation"]').count()) > 0);
    await tp3.locator('#board-pos-box button[data-action="board-rotate"][data-deg="45"]').tap();
    check('…and stays open while I use them', (await tp3.locator('#board-pos-box').count()) === 1 && /Facing 45°/.test(await t3('#board-pos-box')));
    await tp3.tap('#board-pos-toggle');
    await tp3.locator('#board-panel button[data-action="board-ring"][data-k="move"]').tap();
    await tp3.locator(`#board-army-B button[data-action="board-pick"][data-tk="${wb}"]`).tap();
    const st3 = await bs();
    check('a tap on their unit in their list makes it the target: the matchup card is at the top of their column, with Shoot → / Fight →',
      st3.sel === gh && st3.sel2 === wb && (await tp3.locator('#board-army-B #board-pair #board-gap').count()) === 1 && (await tp3.locator('#board-army-B #board-pair button[data-action="board-attack"]').count()) >= 2
      && (await tp3.locator('#board-army-A #board-pair').count()) === 0 && (await tp3.locator('#board-army-B .tri-unit.tgt').count()) === 1, JSON.stringify(st3));
    await tp3.evaluate(() => window.scrollTo(0, 0));
    await tp3.screenshot({ path: join(SHOTS, 'calc_127_tablet_turn.png') });
    // per-army overlays
    await tp3.tap('#board-danger-B');
    check('"⚠ Danger" in B\'s column shows where B can reach next turn, with its options in that column', (await bs()).danger === 'B' && (await tp3.locator('#board-svg #danger-layer[data-from="B"]').count()) === 1 && (await tp3.locator('#board-army-B #board-heat-chip').count()) === 1);
    await tp3.tap('#board-danger-B');
    await tp3.tap('#board-arrive-A');
    check('"⇣ Reserves" in my column shows where my reserves can arrive', (await bs()).arrive === 'A' && (await tp3.locator('#board-army-A #board-arrive-note').count()) === 1);
    await tp3.tap('#board-arrive-A');
    check('…and off again', (await bs()).danger === null && (await bs()).arrive === null);
    const lay = { map: await rect('#board-host'), l: await rect('#board-army-A'), r: await rect('#board-army-B'), vh: await tp3.evaluate(() => innerHeight) };
    check('the map sits between the two armies and fits on screen', lay.l.r <= lay.map.l + 2 && lay.r.l >= lay.map.r - 2 && lay.map.b <= lay.vh && lay.map.w > 400, JSON.stringify(lay));
    // "I am B" on the Mission tab: my army moves to the left
    await tp3.tap('button[data-action="view"][data-value="mission"]');
    await tp3.tap('button[data-action="mission-tab"][data-value="plan"]');
    await tp3.tap('button[data-action="mission-me"][data-value="B"]');
    await tp3.tap('button[data-action="view"][data-value="board"]');
    await tp3.waitForSelector('#board-tri');
    check('"I am B": B is the left column, marked (me)', (await tp3.locator('#board-army-B.tri-l').count()) === 1 && (await tp3.locator('#board-army-A.tri-r').count()) === 1 && /\(me\)/.test(await t3('#board-army-B')));
    await tp3.tap('button[data-action="view"][data-value="mission"]');
    await tp3.tap('button[data-action="mission-me"][data-value="A"]');
    // portrait tablet: the map on top, the two armies side by side below it
    await tp3.setViewportSize({ width: 712, height: 1138 });
    await tp3.tap('button[data-action="view"][data-value="board"]');
    await tp3.waitForSelector('#board-tri');
    const por = { map: await rect('#board-host'), l: await rect('#board-army-A'), r: await rect('#board-army-B') };
    check('portrait tablet: the map on top, my army and theirs side by side under it', por.l.t >= por.map.b - 2 && Math.abs(por.l.t - por.r.t) < 2 && por.l.r <= por.r.l + 2 && por.map.w > 500, JSON.stringify(por));
    await tp3.locator('#board-army-A').scrollIntoViewIfNeeded();
    await tp3.evaluate(() => window.scrollBy(0, -380));
    await tp3.screenshot({ path: join(SHOTS, 'calc_128_tablet_portrait.png') });
    await tctx3.close();
    // phones keep the one-column board with the dock
    const pctx3 = await browser.newContext({ ...devices['Pixel 7'] });
    const pp3 = await pctx3.newPage();
    await pp3.goto(`${BASE}/calc/`); await pp3.waitForSelector('textarea[data-side="A"]');
    await pp3.fill('textarea[data-side="A"]', SW_LIST); await pp3.tap('button[data-action="parse"][data-side="A"]');
    await pp3.fill('textarea[data-side="B"]', ORK_LIST); await pp3.tap('button[data-action="parse"][data-side="B"]');
    await pp3.tap('button[data-action="view"][data-value="board"]');
    await pp3.waitForSelector('#board-svg');
    check('phone: the board stays one column (no army columns), with its tray of units to place', (await pp3.locator('#board-tri').count()) === 0 && (await pp3.locator('#board-tray').count()) === 1);
    await pctx3.close();
  }

  // --- 1.125: 📐 base-to-base measuring on a table photo. A synthetic tablet photo of the table taken from one end
  // (perspective, 2400 px wide) with a 32 mm base at (12, 20) and a 40 mm base at (24, 34): truth 17.02" edge to edge.
  {
    const { writeFileSync } = await import('fs');
    const mctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1, hasTouch: true });
    const mp = await mctx.newPage();
    mp.on('pageerror', e => consoleErrors.push(`meas: ${e}`));
    mp.on('console', m => { if (m.type() === 'error') consoleErrors.push(`meas: ${m.text()}`); });
    await mp.goto(`${BASE}/calc/`); await mp.waitForSelector('textarea[data-side="A"]');
    await mp.fill('textarea[data-side="A"]', SW_LIST); await mp.tap('button[data-action="parse"][data-side="A"]');
    await mp.fill('textarea[data-side="B"]', ORK_LIST); await mp.tap('button[data-action="parse"][data-side="B"]');
    await mp.tap('button[data-action="view"][data-value="board"]');
    await mp.waitForSelector('#board-svg');
    const A = { x: 12, y: 20, mm: 32 }, Bb = { x: 24, y: 34, mm: 40 };
    const truth = Math.hypot(Bb.x - A.x, Bb.y - A.y) - (A.mm + Bb.mm) / 25.4 / 2;
    const PC = [[620, 260], [1780, 270], [2330, 1640], [80, 1620]]; // table corners in the 2400x1700 photo
    const b64 = await mp.evaluate(async ([pc, a, b]) => {
      const P = await import('/calc/photo.mjs');
      const K = 40; // px per inch on the flat table image
      const bc = document.createElement('canvas'); bc.width = 44 * K; bc.height = 60 * K;
      const g = bc.getContext('2d');
      g.fillStyle = '#7d8f5a'; g.fillRect(0, 0, bc.width, bc.height);              // mat
      g.fillStyle = '#6b5b4a'; g.fillRect(16 * K, 26 * K, 8 * K, 5 * K);           // a ruin footprint
      const base = (p, col) => { g.fillStyle = '#222'; g.beginPath(); g.arc(p.x * K, p.y * K, p.mm / 25.4 / 2 * K, 0, 7); g.fill(); g.fillStyle = col; g.beginPath(); g.arc(p.x * K, p.y * K, p.mm / 25.4 / 2 * K * 0.8, 0, 7); g.fill(); };
      base(a, '#ff00ff'); base(b, '#00ffff');
      const H = P.homography(pc, [[0, 0], [44 * K, 0], [44 * K, 60 * K], [0, 60 * K]]);
      const out = P.warpToBoard(g.getImageData(0, 0, bc.width, bc.height), H, { w: 2400, h: 1700 }, 1);
      for (let i = 0; i < out.data.length; i += 4) if (out.data[i + 3] === 0) { out.data[i] = 50; out.data[i + 1] = 40; out.data[i + 2] = 32; out.data[i + 3] = 255; }
      const c = document.createElement('canvas'); c.width = 2400; c.height = 1700;
      c.getContext('2d').putImageData(new ImageData(out.data, 2400, 1700), 0, 0);
      return c.toDataURL('image/jpeg', 0.9).split(',')[1];
    }, [PC, A, Bb]);
    const file = join(SHOTS, 'calc_synthetic_measure_photo.jpg');
    writeFileSync(file, Buffer.from(b64, 'base64'));
    await mp.locator('#board-photo-bar').scrollIntoViewIfNeeded();
    await mp.setInputFiles('input[data-input="board-photo"]', file);
    await mp.waitForSelector('.photo-ov #photo-svg image');
    const imgToScreen = (x, y) => mp.evaluate(([ix, iy]) => { const svg = document.getElementById('photo-svg'); const pt = svg.createSVGPoint(); pt.x = ix; pt.y = iy; const q = pt.matrixTransform(svg.getScreenCTM()); return { x: q.x, y: q.y }; }, [x, y]);
    for (const i of [0, 1, 2, 3]) { const q = await imgToScreen(...PC[i]); await mp.mouse.click(q.x, q.y); }
    await mp.click('.photo-ov [data-ov="ok"]');
    await mp.waitForSelector('#board-svg #board-photo', { timeout: 20000 });
    await mp.click('button[data-action="board-photo-map"][data-value="photo"]');
    // where the bases show on the flattened photo (what you line the circles up with)
    const seen = await mp.evaluate(async () => {
      const im = document.querySelector('#board-svg #board-photo');
      const img = new Image(); img.src = im.getAttribute('href'); await img.decode();
      const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
      const g = c.getContext('2d'); g.drawImage(img, 0, 0);
      const d = g.getImageData(0, 0, c.width, c.height).data, ppi = c.width / 44;
      const cen = (test) => { let n = 0, sx = 0, sy = 0; for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) { const o = (y * c.width + x) * 4; if (test(d[o], d[o + 1], d[o + 2])) { n++; sx += x; sy += y; } } return n ? { x: (sx / n + 0.5) / ppi, y: (sy / n + 0.5) / ppi } : null; };
      return { a: cen((r, gg, b) => r > 190 && gg < 110 && b > 190), b: cen((r, gg, b) => r < 110 && gg > 190 && b > 190) };
    });
    await mp.click('button[data-action="board-mode"][data-value="meas"]');
    await mp.evaluate(() => document.getElementById('board-host').scrollIntoView({ block: 'start' }));
    const toScreen = (x, y) => mp.evaluate(([bx, by]) => { const svg = document.getElementById('board-svg'); const pt = svg.createSVGPoint(); pt.x = bx; pt.y = by; const q = pt.matrixTransform(svg.getScreenCTM()); return { x: q.x, y: q.y }; }, [x, y]);
    const pa = await toScreen(seen.a.x, seen.a.y); await mp.mouse.click(pa.x, pa.y);
    const pb = await toScreen(seen.b.x, seen.b.y); await mp.mouse.click(pb.x, pb.y);
    await mp.click('#board-meas-mm-b button[data-value="40"]');
    await mp.waitForSelector('#board-meas-edge');
    const edgeTxt = (await mp.textContent('#board-meas-edge')).replace(/\s+/g, ' ');
    const val = Number(edgeTxt.match(/([\d.]+)"/)?.[1]), pm = Number(edgeTxt.match(/± ([\d.]+)"/)?.[1]);
    check(`📐 Bases on a table photo: base to base ${val}" ± ${pm}" — the real distance (${truth.toFixed(2)}") is inside it`, Number.isFinite(val) && Number.isFinite(pm) && Math.abs(val - truth) <= pm + 0.05 && pm < 0.6, JSON.stringify({ edgeTxt, truth, seen }));
    const lab = await mp.textContent('#meas-label');
    check('the distance is on the map too, between the two base circles', /\d+\.\d" ±\d\.\d/.test(lab), lab);
    // Point: measuring to a spot drops the base radius
    await mp.click('#board-meas-mm-b button[data-value="0"]');
    const pt = Number((await mp.textContent('#board-meas-edge')).match(/([\d.]+)"/)?.[1]);
    check('“Point” for B measures to the spot (40 mm radius no longer taken off: +0.8")', Math.abs(pt - val - 40 / 25.4 / 2) < 0.15, `${pt} vs ${val}`);
    await mp.click('#board-meas-mm-b button[data-value="40"]');
    await mp.evaluate(() => { document.querySelector('button[data-action="board-zoom"][data-z="0.7"]')?.click(); });
    await mp.screenshot({ path: join(SHOTS, 'calc_121_photo_measure.png') });
    await mctx.close();
  }

  // --- 1.126: AR measuring test page (/calc/ar-test.html). Real AR needs a device with ARCore: here (1) a browser
  // without AR must say so, and (2) with a STAND-IN WebXR device (scripted hit-test points; no camera, no ARCore)
  // the page's own logic must measure, record and drift-test correctly. (2) is not a test of real AR accuracy.
  {
    const actx = await browser.newContext({ ...devices['Pixel 7'] });
    const ap = await actx.newPage();
    ap.on('pageerror', e => consoleErrors.push(`ar: ${e}`));
    await ap.goto(`${BASE}/calc/ar-test.html`);
    await ap.waitForFunction(() => !/Checking/.test(document.getElementById('support').textContent));
    const sup = (await ap.textContent('#support')).replace(/\s+/g, ' ');
    check('AR test page: on a browser without AR it says so, and Start AR stays off', /✗/.test(sup) && await ap.isDisabled('#start'), sup.slice(0, 160));
    await actx.close();

    const sctx = await browser.newContext({ ...devices['Pixel 7'] });
    await sctx.addInitScript(() => {
      // a stand-in WebXR device: hit-test returns window.__hit (metres); select is fired by window.__tap()
      const I = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
      window.__hit = [0, 0, -0.5];
      class FakeSession extends EventTarget {
        constructor() { super(); this.enabledFeatures = ['hit-test', 'local', 'dom-overlay']; this.renderState = {}; this.ended = false; }
        updateRenderState(s) { Object.assign(this.renderState, s); }
        async requestReferenceSpace() { return {}; }
        async requestHitTestSource() { return {}; }
        requestAnimationFrame(cb) { if (!this.ended) setTimeout(() => cb(performance.now(), frame), 16); return 1; }
        async end() { this.ended = true; this.dispatchEvent(new Event('end')); }
      }
      const frame = {
        getViewerPose: () => ({ views: [{ projectionMatrix: I, transform: { inverse: { matrix: I } } }] }),
        getHitTestResults: () => [{ getPose: () => ({ transform: { position: { x: window.__hit[0], y: window.__hit[1], z: window.__hit[2] } } }) }],
        getPose: () => null,
      };
      window.XRWebGLLayer = class { constructor() { this.framebuffer = null; } getViewport() { return { x: 0, y: 0, width: 100, height: 100 }; } };
      Object.defineProperty(navigator, 'xr', { value: { isSessionSupported: async (m) => m === 'immersive-ar', requestSession: async () => (window.__session = new FakeSession()) }, configurable: true });
      window.__tap = () => window.__session.dispatchEvent(new Event('select'));
    });
    const sp = await sctx.newPage();
    sp.on('pageerror', e => consoleErrors.push(`ar-stub: ${e}`));
    await sp.goto(`${BASE}/calc/ar-test.html`);
    await sp.waitForFunction(() => !document.getElementById('start').disabled);
    await sp.tap('#start');
    await sp.waitForFunction(() => document.getElementById('ov').classList.contains('on'));
    // a 24" tape: 0 at x = 0, the 24" mark at x = 0.6096 m; the stand-in reads 24.2"
    const M = 0.0254;
    await sp.evaluate(() => { window.__hit = [0, 0, -0.5]; });
    await sp.waitForTimeout(80); await sp.evaluate(() => window.__tap());
    await sp.evaluate((m) => { window.__hit = [24.2 * m, 0, -0.5]; }, M);
    await sp.waitForTimeout(80); await sp.evaluate(() => window.__tap());
    await sp.waitForFunction(() => /24\.20"/.test(document.getElementById('ov-dist').textContent));
    await sp.fill('#ov-true', '24');
    await sp.click('#ov-record');
    // drift: the same spot marked twice, 0.3" apart
    await sp.click('#ov-drift');
    await sp.evaluate(() => { window.__hit = [0.2, 0, -0.4]; }); await sp.waitForTimeout(80); await sp.evaluate(() => window.__tap());
    await sp.evaluate((m) => { window.__hit = [0.2 + 0.3 * m, 0, -0.4]; }, M); await sp.waitForTimeout(80); await sp.evaluate(() => window.__tap());
    await sp.waitForTimeout(80);
    await sp.screenshot({ path: join(SHOTS, 'calc_122_ar_test_stub.png') });
    await sp.click('#ov-end');
    await sp.waitForFunction(() => !document.getElementById('ov').classList.contains('on'));
    const res = await sp.evaluate(() => JSON.parse(localStorage.getItem('w40k_calc_artest_v1')));
    const sum = (await sp.textContent('#summary')).replace(/\s+/g, ' ');
    check('stand-in AR: 2 taps on a 24" tape read 24.20", Record logs +0.20"; a drift test logs 0.30"', res.length === 2 && res[0].kind === 'distance' && Math.abs(res[0].errIn - 0.2) < 0.01 && res[1].kind === 'drift' && Math.abs(res[1].measIn - 0.3) < 0.01 && /average error 0\.20"/.test(sum), JSON.stringify({ res, sum }));
    await sctx.close();
  }

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
