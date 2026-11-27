// Open a Godot save (.w40ksave) in the Combat Calc as a Live table, to look at the Board's advice on a real game
// position. A development tool: it drives the page with Playwright, it is not part of the app.
//
//   cd server && node tools/save-to-calc.mjs <save.w40ksave> <out dir> <name>
//
// Writes <name>.board.png (the map), <name>.page.png (the whole Board), <name>.request.json (what "Ask for a plan"
// would send: public/calc/advise.mjs) and <name>.report.json (what was converted, and what could not be).
//
// What it carries over: both armies (through gamelists.gameArmyText), attached leaders, every living model's
// position (40 px = 1"), models lost, units in reserve or embarked, the layout and deployment zones, the battle
// round and whose turn, CP, VP and the secondary cards in hand. "Me" is the player whose turn it is in the save.
// What it does not: wounds on a damaged model, which model of a unit died (the plain ones are taken off first),
// units the calc's data does not have (they are listed under "unresolved" and left off the board).
// The report's "fidelity" compares every living model's position with the calc's board.
import { spawn } from 'child_process';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, existsSync } from 'fs';
import { gunzipSync } from 'zlib';
import { tmpdir } from 'os';
import { join } from 'path';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let pw; try { pw = await import('playwright'); } catch { pw = require('playwright'); }
const { chromium, devices } = pw.chromium ? pw : pw.default;
import { dirname } from 'path';
import { fileURLToPath } from 'url';
const SRV = join(dirname(fileURLToPath(import.meta.url)), '..');
const G = await import(`${SRV}/public/calc/gamelists.mjs`);
const [, , SAVE, OUT, NAME] = process.argv;
mkdirSync(OUT, { recursive: true });
const save = JSON.parse(gunzipSync(Buffer.from(readFileSync(SAVE, 'utf8'), 'base64')).toString('utf8'));
const PX = 40, log = (...a) => console.log(...a);
const P = save.meta.active_player, Q = P === 1 ? 2 : 1;          // me = the player whose turn it is
const sideOf = (pl) => (pl === P ? 'A' : 'B');
const disp = (pl) => String(save.meta.dispositions_11e?.[pl] ?? save.meta.dispositions_11e?.[String(pl)] ?? 'take_and_hold');
const unitsOf = (pl) => Object.entries(save.units).filter(([, u]) => u.owner === pl);
const text = (pl) => G.gameArmyText({ faction: { ...save.factions[pl], force_disposition: disp(pl) }, units: Object.fromEntries(unitsOf(pl)) }, `${save.factions[pl].name} (save)`);
const PHASES = ['formations', 'deployment', 'redeployment', 'roll_off', 'scout', 'scout_moves', 'command', 'movement', 'shooting', 'charge', 'fight', 'scoring', 'morale'];
log(`save: round ${save.meta.battle_round}, player ${P}'s turn (${save.factions[P].name}), phase ${PHASES[save.meta.phase] ?? save.meta.phase}, layout ${save.board.terrain_layout}, first turn player ${save.meta.first_turn_player}`);

const PORT = 19960 + Math.floor(Math.random() * 30), BASE = `http://localhost:${PORT}`;
const server = spawn(process.execPath, [join(SRV, 'relay-server.js')], { env: { ...process.env, PORT: String(PORT), DB_PATH: join(mkdtempSync(join(tmpdir(), 'sv-')), 'x.db') }, stdio: 'ignore' });
for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch {} await new Promise(r => setTimeout(r, 200)); }
const PREINSTALLED = '/opt/pw-browsers/chromium';   // (as tests/e2e-calc.mjs: the browser of a managed environment)
const browser = await chromium.launch(existsSync(PREINSTALLED) ? { executablePath: PREINSTALLED } : {});
const errs = [], report = { save: SAVE, issues: [] };
try {
  const ctx = await browser.newContext({ ...devices['Galaxy Tab S4 landscape'] });
  const p = await ctx.newPage();
  p.on('pageerror', e => errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  p.on('dialog', d => d.accept());
  await p.goto(`${BASE}/calc/`); await p.waitForSelector('textarea[data-side="A"]');
  await p.fill('textarea[data-side="A"]', text(P)); await p.tap('button[data-action="parse"][data-side="A"]');
  await p.fill('textarea[data-side="B"]', text(Q)); await p.tap('button[data-action="parse"][data-side="B"]');
  // attached leaders as in the save (leader -> bodyguard), by their place in the list; then the list is read again
  const attach = {};
  for (const pl of [P, Q]) {
    const ids = unitsOf(pl).map(([id]) => id), la = save.meta.formations?.[pl]?.leader_attachments ?? save.meta.formations?.[String(pl)]?.leader_attachments ?? {};
    const a = {};
    for (const [id, u] of unitsOf(pl)) { const host = la[id] ?? u.attached_to; if (host && ids.includes(host)) a[ids.indexOf(id)] = ids.indexOf(host); }
    attach[sideOf(pl)] = a;
  }
  // (loading a list resets its attachments, so they are set on the armies as read)
  const merged = await p.evaluate(async (attach) => { const A = await import('/calc/adapter.mjs'), st = window.__calc.state; const out = {};
    for (const X of ['A', 'B']) { A.setAttachments(st.armies[X], attach[X]); st.attach[X] = st.armies[X].attachments; out[X] = st.armies[X].units.filter(u => u.members.length > 1).map(u => u.name); }
    return out; }, attach);
  report.attached = merged;
  await p.tap('button[data-action="view"][data-value="attack"]'); await p.tap('button[data-action="view"][data-value="armies"]').catch(() => {});
  // save units <-> calc units: a calc unit names the list lines it is made of (members[].index)
  const calcUnits = await p.evaluate(() => Object.fromEntries(['A', 'B'].map(X => [X, (window.__calc.state.armies[X]?.units ?? []).map(u => ({ key: u.key, name: u.name, models: u.models, idx: u.members.map(m => m.index), leaders: u.members.filter(m => m.role === 'leader').map(m => m.index) }))])));
  const map = {};   // save unit id -> { tk, side, key, name, leader }
  report.unresolved = [];
  for (const pl of [P, Q]) {
    const X = sideOf(pl);
    unitsOf(pl).forEach(([id, u], i) => {
      const c = calcUnits[X].find(c => c.idx.includes(i));
      if (!c) { report.unresolved.push(`${X}: ${u.meta.name} (${u.models.length} models, ${u.meta.points} pts)`); return; }
      map[id] = { tk: `${X}:${c.key}`, side: X, key: c.key, name: c.name, leader: c.leaders.includes(i) };
    });
    for (const c of calcUnits[X]) { const n = unitsOf(pl).filter(([id]) => map[id]?.key === c.key).reduce((a, [, u]) => a + u.models.length, 0); if (n !== c.models) report.issues.push(`${X}: ${c.name}: ${n} models in the save, ${c.models} in the calc`); }
  }
  // the tracker: who went first, the round and turn, CP and VP, the cards in hand
  const first = sideOf(save.meta.first_turn_player), round = save.meta.battle_round;
  const taps = (round - 1) * 2 + (first === 'A' ? 0 : 1);
  await p.tap('button[data-action="view"][data-value="mission"]');
  await p.tap('button[data-action="mission-tab"][data-value="play"]');
  await p.evaluate((f) => { const m = window.__calc.state.mission; m.me = 'A'; m.first = f; m.game.next = f; }, first);
  for (let k = 0; k < taps; k++) await p.tap('#play-turn-done');
  const cardId = (id) => String(id).replace(/_/g, '-');
  const hands = { A: (save.secondary_missions?.player_state?.[P]?.active ?? []).map(c => cardId(c.id)), B: (save.secondary_missions?.player_state?.[Q]?.active ?? []).map(c => cardId(c.id)) };
  for (const X of ['A', 'B']) for (const id of hands[X]) {
    const ok = await p.evaluate(([X, id]) => !![...document.querySelectorAll(`select[data-input="mission-draw"][data-side="${X}"] option`)].find(o => o.value === id), [X, id]);
    if (ok) await p.selectOption(`select[data-input="mission-draw"][data-side="${X}"]`, id); else report.issues.push(`${X}: card "${id}" is not in the calc's deck`);
  }
  await p.evaluate(([a, b]) => { const g = window.__calc.state.mission.game; for (const [X, s] of [['A', a], ['B', b]]) { g[X].cp = s.cp ?? 0; g[X].primary = s.primary_vp ?? 0; g[X].secondary = s.secondary_vp ?? 0; } }, [save.players[P], save.players[Q]]);
  // the board: layout and zones from the save, then the Live table
  await p.tap('button[data-action="view"][data-value="board"]');
  await p.waitForSelector('#board-tri');
  const variant = Number(/_(\d)$/.exec(save.board.terrain_layout)?.[1] ?? 1);
  await p.evaluate((v) => { window.__calc.state.board.settings.variant = v; }, variant);
  await p.tap('button[data-action="view"][data-value="attack"]'); await p.tap('button[data-action="view"][data-value="board"]');
  const layout = await p.evaluate(() => window.__calc.board().layout);
  if (layout !== save.board.terrain_layout) report.issues.push(`layout: the save has ${save.board.terrain_layout}, the calc shows ${layout}`);
  // A's zone must be the zone of the save's player P: compare the centres
  const cen = (poly) => [poly.reduce((a, q) => a + (q.x ?? q[0]), 0) / poly.length, poly.reduce((a, q) => a + (q.y ?? q[1]), 0) / poly.length];
  const want = cen(save.board.deployment_zones.find(z => Number(z.player) === P).poly);
  const zones = await p.evaluate(async () => { const B = await import('/calc/boardview.mjs'); const bc = B.boardContext(); return { a: bc.zoneA, zs: bc.deployment.zones.map(z => ({ player: z.player, poly: z.poly })) }; });
  const d2 = (z) => { const c = cen(z.poly); return Math.hypot(c[0] - want[0], c[1] - want[1]); };
  const nearest = [...zones.zs].sort((x, y) => d2(x) - d2(y))[0];
  if (nearest.player !== zones.a) {
    await p.evaluate(() => { const s = window.__calc.state.board.settings; s.swapZones = !s.swapZones; });
    await p.tap('button[data-action="view"][data-value="attack"]'); await p.tap('button[data-action="view"][data-value="board"]');
    const now = await p.evaluate(async () => (await import('/calc/boardview.mjs')).boardContext().zoneA);
    if (now !== nearest.player) report.issues.push(`zones: A should be in zone ${nearest.player}, the calc has it in ${now}`);
  }
  await p.tap('#board-live');
  await p.waitForSelector('#board-live-bar');
  // tokens: every unit on the battlefield at the centre of its living models, each model where the save has it
  const DEPLOYED = new Set([2, 3, 4, 5, 6]);
  const tokens = {}, losses = [], off = { reserves: [], embarked: [], destroyed: [] }, where = {};
  const byTk = new Map();
  for (const [id, u] of Object.entries(save.units)) { const m = map[id]; if (!m) continue; if (!byTk.has(m.tk)) byTk.set(m.tk, { ...m, parts: [] }); byTk.get(m.tk).parts.push({ id, u, leader: m.leader }); }
  for (const [tk, g] of byTk) {
    const all = g.parts.flatMap(q => q.u.models), dead = all.filter(x => x.alive === false).length;
    const host = g.parts.find(q => !q.leader) ?? g.parts[0];
    if (dead > 0) losses.push({ tk, side: g.side, key: g.key, name: g.name, dead });
    if (dead >= all.length) { off.destroyed.push(g.name); continue; }
    if (host.u.embarked_in) { off.embarked.push(g.name); tokens[tk] = { in: map[host.u.embarked_in]?.tk }; continue; }
    const alive = g.parts.flatMap(q => q.u.models.filter(x => x.alive !== false && x.position).map(x => ({ x: x.position.x / PX, y: x.position.y / PX, leader: q.leader })));
    if (!DEPLOYED.has(host.u.status) || !alive.length) { off.reserves.push(g.name); continue; }
    const cx = alive.reduce((a, x) => a + x.x, 0) / alive.length, cy = alive.reduce((a, x) => a + x.y, 0) / alive.length;
    tokens[tk] = { x: cx, y: cy, rot: 0 };
    where[tk] = { cx, cy, alive };
  }
  const setTokens = (toks) => p.evaluate((toks) => { const st = window.__calc.state.board; const root = Object.values(st.plans).find(r => r.variants?.some(v => v.live)); const lv = root.variants.find(v => v.live); const step = lv.steps[lv.steps.length - 1]; step.tokens = toks; lv.steps[0].tokens = JSON.parse(JSON.stringify(toks)); }, toks);
  const rerender = async () => { await p.tap('button[data-action="view"][data-value="attack"]'); await p.tap('button[data-action="view"][data-value="board"]'); await p.waitForSelector('#board-live-bar'); };
  // losses first (the models left decide how many bases a token has): the unit placed, selected, its stepper tapped
  const temp = { ...tokens };
  for (const l of losses) if (!temp[l.tk]) temp[l.tk] = { x: 2, y: 2, rot: 0 };
  await setTokens(temp); await rerender();
  for (const l of losses) {
    await p.evaluate((tk) => { const bs = window.__calc.state.board; bs.sel = null; bs.sel2 = null; const b = document.querySelector(`button[data-action="board-pick"][data-tk="${tk}"]`); b?.click(); return { pick: !!b, sel: window.__calc.board().sel, loss: [...document.querySelectorAll('[data-action="loss"],[data-action="loss-unit"]')].slice(0, 3).map(e => e.outerHTML.slice(0, 160)) }; }, l.tk);
    const done = await p.evaluate(async ([key, side, n]) => {
      let k = 0;
      for (; k < n; k++) {
        const b = document.querySelector(`button[data-action="loss-unit"][data-side="${side}"][data-unit="${key}"][data-delta="-1"]`) ?? document.querySelector(`button[data-action="loss"][data-side="${side}"][data-unit="${key}"][data-field="count"][data-delta="-1"]`);
        if (!b) break;
        b.click(); await new Promise(r => setTimeout(r, 15));
      }
      return k;
    }, [l.key, l.side, l.dead]);
    if (done !== l.dead) report.issues.push(`${l.name}: ${l.dead} models lost in the save, ${done} taken off in the calc`);
  }
  await setTokens(tokens); await rerender();
  // each model where the save has it: the calc's own model order says which bases are the leader's
  const order = await p.evaluate(() => Object.fromEntries(window.__calc.board().units.map(t => [t.tk, t.models.map(m => !!m.leader)])));
  for (const [tk, w] of Object.entries(where)) {
    const flags = order[tk];
    if (!flags) { report.issues.push(`${byTk.get(tk).name}: not on the calc's board`); continue; }
    if (flags.length !== w.alive.length) { report.issues.push(`${byTk.get(tk).name}: ${w.alive.length} models alive in the save, ${flags.length} on the calc's board`); }
    const L = w.alive.filter(a => a.leader), R = w.alive.filter(a => !a.leader), mo = {};
    flags.forEach((isL, i) => { const a = (isL ? L.shift() : R.shift()) ?? R.shift() ?? L.shift(); if (a) mo[i] = [a.x - w.cx, a.y - w.cy]; });
    tokens[tk].mo = mo;
  }
  await setTokens(tokens); await rerender();
  // fidelity: every living model of the save has a base of its unit at the same place on the calc's board
  const onBoard = await p.evaluate(() => Object.fromEntries(window.__calc.board().units.map(t => [t.tk, t.models.map(m => [t.x + m.dx, t.y + m.dy])])));
  let worst = 0, nModels = 0;
  for (const [tk, w] of Object.entries(where)) for (const a of w.alive) { nModels++; const d = Math.min(...(onBoard[tk] ?? []).map(q => Math.hypot(q[0] - a.x, q[1] - a.y)), 99); if (d > worst) worst = d; }
  report.fidelity = { modelsCompared: nModels, worstPositionErrorInches: Math.round(worst * 1000) / 1000 };
  // objective control: the game's own record at the start of the turn against what the calc works out
  const ctl = save.secondary_missions?.objective_control_at_turn_start ?? {};
  report.gameControl = ctl;
  await p.waitForFunction(() => window.__calc.board().next?.moves?.state === 'done', null, { timeout: 120000 });
  await p.tap('#board-live-confirm');
  await p.evaluate(() => window.scrollTo(0, 0));
  await p.locator('#board-host').screenshot({ path: join(OUT, `${NAME}.board.png`) });
  await p.screenshot({ path: join(OUT, `${NAME}.page.png`), fullPage: true });
  // the app's own request (what "Ask for a plan" would send), with the phase of the save on the tracker
  await p.evaluate((ph) => { window.__calc.state.mission.game.phase = ph; }, ['command', 'movement', 'shooting', 'charge', 'fight'].includes(PHASES[save.meta.phase]) ? PHASES[save.meta.phase] : 'command');
  const appReq = await p.evaluate(() => window.__calc.board().next.advise.request());
  writeFileSync(join(OUT, `${NAME}.request.json`), JSON.stringify(appReq));
  report.rows = await p.$$eval('#board-my-units .next-unit', els => els.map(e => e.textContent.replace(/\s+/g, ' ').trim().slice(0, 260)));
  report.movesLine = await p.textContent('#board-my-moves').catch(() => null);
  Object.assign(report, { round, first, hands, off, placed: Object.keys(tokens).length, lossesApplied: losses.length, requestChars: { static: JSON.stringify(appReq.static).length, dynamic: JSON.stringify(appReq.dynamic).length }, forecast: appReq.dynamic.computed.forecast, objectives: appReq.dynamic.computed.objectives.map(o => [o.name, o.myOC, o.theirOC, o.inTheirTurn]) });
  // (the calc's control per objective id, to compare with the game's record: 0 nobody, else the player number)
  const ids = await p.evaluate(() => window.__calc.board().next.res.swing.map(o => [o.id, o.mine > o.theirs ? 'A' : o.theirs > o.mine ? 'B' : null]));
  report.controlCompare = ids.map(([id, X]) => ({ id, calc: X === 'A' ? P : X === 'B' ? Q : 0, game: Number(report.gameControl[id] ?? -1) }));
  report.controlAgrees = report.controlCompare.filter(c => c.calc === c.game).length + ' of ' + report.controlCompare.length;
} catch (e) { report.issues.push(`ERROR ${e?.stack ?? e}`); }
report.consoleErrors = errs.slice(0, 5);
writeFileSync(join(OUT, `${NAME}.report.json`), JSON.stringify(report, null, 1));
log(JSON.stringify(report, null, 1).slice(0, 3500));
await browser.close(); server.kill();
