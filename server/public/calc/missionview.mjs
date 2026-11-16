// Mission tab: secondary-card planner (matchup sheet, keep-ready list, hit
// list), objective plan, VP forecast for both players with what-ifs, and an
// in-game tracker (cards drawn / scored / discarded, score) that the forecast
// re-runs from. The simulation is forecast.mjs, run in the worker.
//
// app.js owns the shared state and calls in through initMission().

import { SECONDARIES, SECONDARY_BY_ID, FIXED_IDS, PRIMARIES, RULES } from './missions-11e.mjs';
import { armyProfile, cardDead } from './forecast.mjs';
import { abilitiesOf } from './adapter.mjs';
import { boardContext } from './boardview.mjs';

let ctx = null;            // { state, esc, seg, chip }
const LS_KEY = 'w40k_calc_mission_v1';
const other = (p) => (p === 'A' ? 'B' : 'A');
const KILL_RATES = [[0.8, 'Low'], [1.3, 'Even'], [2, 'High']];
const ACTION_P = [[0.9, 'Easy'], [0.7, 'OK'], [0.45, 'Hard']];
const SKILL = [[1.3, 'Easy'], [1, 'Normal'], [0.6, 'Hard'], [0, 'Never']];

export function initMission(c) {
  ctx = c;
  try {
    const saved = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (saved) Object.assign(ms(), saved);
  } catch { /* fresh */ }
}

function ms() {
  const s = ctx.state;
  s.mission ??= {
    me: 'A', first: null, battleReady: { A: true, B: true },
    modes: { A: { mode: 'tactical', fixed: [] }, B: { mode: 'tactical', fixed: [] } },
    killRate: { A: 1.3, B: 1.3 }, actionP: { A: 0.7, B: 0.7 }, skill: { A: {}, B: {} },
    plans: {}, game: newGame(), sheetSide: null, cardOpen: null,
  };
  return s.mission;
}
function newGame() {
  return { round: 1, next: null, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } };
}
function persist() {
  const m = ms();
  const { result, levers, busy, ...keep } = m;
  try { localStorage.setItem(LS_KEY, JSON.stringify(keep)); } catch { /* best effort */ }
}

// ---------------------------------------------------------------------------
// Armies -> what the cards care about

function unitFacts(cu) {
  let characters = 0, charactersW4 = 0, w10 = 0, bodyguard = 0, fastest = 0;
  for (const m of cu.members) {
    const n = m.ru.model_count ?? 1;
    const p = m.dcUnit.profiles?.[0] ?? {};
    const W = parseInt(p.W, 10) || 1, M = parseInt(p.M, 10) || 0;
    const kw = (m.dcUnit.keywords ?? []).map(k => k.toUpperCase());
    if (kw.includes('CHARACTER')) { characters += n; if (W >= 4) charactersW4 += n; }
    if (W >= 10) w10 += n;
    if (m.role !== 'leader') bodyguard += n;
    fastest = Math.max(fastest, M);
  }
  const kws = new Set(cu.keywords);
  const abil = abilitiesOf(cu).map(a => a.name).join('|');
  return {
    name: cu.name, models: cu.models, points: cu.points, characters, charactersW4, w10, bodyguardModels: bodyguard,
    aircraft: kws.has('AIRCRAFT'), fast: fastest >= 10 || kws.has('FLY'),
    reserves: /deep strike|infiltrators|scouts|teleport|deep-strike/i.test(abil),
  };
}
const profileCache = new Map();
function profileOf(side) {
  const army = ctx.state.armies[side];
  if (!army) return null;
  const key = `${side}|${army.units.map(u => u.key + u.models).join(',')}`;
  if (!profileCache.has(key)) profileCache.set(key, { facts: army.units.map(unitFacts), profile: armyProfile(army.units.map(unitFacts)) });
  return profileCache.get(key);
}

// ---------------------------------------------------------------------------
// Objectives from the board's layout

function objectives() {
  const bc = boardContext();
  const l = bc.layout;
  if (!l) return [];
  const sideOfZone = (z) => (z === 'player1' ? (bc.zoneA === 1 ? 'A' : 'B') : (bc.zoneA === 2 ? 'A' : 'B'));
  const homes = l.objectives.filter(o => o.zone !== 'no_mans_land').map(o => ({ ...o, side: sideOfZone(o.zone) }));
  const homeOf = (s) => homes.find(h => h.side === s);
  const out = [];
  for (const o of l.objectives) {
    if (o.zone !== 'no_mans_land') { const side = sideOfZone(o.zone); out.push({ id: o.id, cls: 'home', side, label: `${side} home` }); continue; }
    if (Math.hypot(o.x - 22, o.y - 30) <= 4) { out.push({ id: o.id, cls: 'central', side: null, label: 'Centre' }); continue; }
    const hA = homeOf('A'), hB = homeOf('B');
    const side = !hA || !hB ? null : Math.hypot(o.x - hA.x, o.y - hA.y) <= Math.hypot(o.x - hB.x, o.y - hB.y) ? 'A' : 'B';
    out.push({ id: o.id, cls: 'exp', side, label: `${side}-side` });
  }
  const order = (o) => (o.cls === 'home' ? (o.side === 'A' ? 0 : 4) : o.cls === 'central' ? 2 : o.side === 'A' ? 1 : 3);
  out.sort((a, b) => order(a) - order(b));
  // number duplicates ("Centre 1", "A-side 2")
  const counts = {};
  for (const o of out) counts[o.label] = (counts[o.label] ?? 0) + 1;
  const seen = {};
  for (const o of out) if (counts[o.label] > 1) o.label += ` ${(seen[o.label] = (seen[o.label] ?? 0) + 1)}`;
  return out;
}

function plan() {
  const m = ms();
  const l = boardContext().layout;
  if (!l) return {};
  if (!m.plans[l.id]) {
    const p = {};
    for (let r = 1; r <= RULES.rounds; r++) {
      p[r] = {};
      for (const o of objectives()) p[r][o.id] = o.cls === 'home' ? o.side : o.cls === 'exp' && r >= 2 ? o.side : 'c';
    }
    m.plans[l.id] = p;
  }
  return m.plans[l.id];
}

// ---------------------------------------------------------------------------
// Forecast request (run by the worker)

function inProgress() {
  const g = ms().game;
  return g.round > 1 || ['A', 'B'].some(X => g[X].hand.length || g[X].used.length || g[X].primary || g[X].secondary);
}

export function forecastParams(over = {}) {
  const m = ms();
  const bc = boardContext();
  const pa = profileOf('A'), pb = profileOf('B');
  if (!pa || !pb || !bc.layout) return null;
  const g = m.game;
  const live = inProgress();
  const first = m.first ?? (live ? 'A' : null);
  const player = (X) => ({
    mission: bc.missions[X], mode: m.modes[X].mode, fixed: m.modes[X].fixed,
    army: (X === 'A' ? pa : pb).profile, killRate: over.killRate?.[X] ?? m.killRate[X], actionP: m.actionP[X],
    skill: m.skill[X], battleReady: m.battleReady[X],
    start: live ? { hand: g[X].hand, used: g[X].used, primary: g[X].primary, secondary: g[X].secondary, destroyed: g[other(X)].destroyed } : null,
  });
  const next = g.next ?? first ?? 'A';
  return {
    players: { A: player('A'), B: player('B') },
    objectives: objectives().map(({ id, cls, side }) => ({ id, cls, side })),
    plan: over.plan ?? plan(), first,
    startRound: live ? g.round : 1, startTurn: live && first ? (next === first ? 0 : 1) : 0,
    trials: over.trials ?? 4000, seed: 20261116,
  };
}

// what-ifs from "my" side: each is a tweak of the plan or the trading rates
function leverParams() {
  const m = ms(), me = m.me, opp = other(me);
  const objs = objectives(), base = plan();
  const clone = () => JSON.parse(JSON.stringify(base));
  const out = [];
  // hold one more objective from round 2: the most useful one you don't already hold
  const prefer = [...objs.filter(o => o.cls === 'central'), ...objs.filter(o => o.cls === 'exp' && o.side === opp), ...objs.filter(o => o.cls === 'exp' && o.side === me), ...objs.filter(o => o.cls === 'home' && o.side === opp)];
  const p1 = clone();
  let changed = false;
  for (let r = 2; r <= RULES.rounds; r++) {
    const o = prefer.find(x => p1[r][x.id] !== me);
    if (o) { p1[r][o.id] = me; changed = true; }
  }
  if (changed) out.push({ key: 'obj', label: 'Hold one more objective (rounds 2–5)', over: { plan: p1 } });
  const home = objs.find(o => o.cls === 'home' && o.side === opp);
  if (home && base[5]?.[home.id] !== me) {
    const p2 = clone();
    p2[4][home.id] = me; p2[5][home.id] = me;
    out.push({ key: 'home', label: 'Take their home objective in rounds 4–5', over: { plan: p2 } });
  }
  const lose = clone();
  for (let r = 2; r <= RULES.rounds; r++) {
    const o = [...objs.filter(x => x.cls === 'exp' && x.side === me), ...objs.filter(x => x.cls === 'central')].find(x => lose[r][x.id] === me);
    if (o) lose[r][o.id] = opp;
  }
  out.push({ key: 'lose', label: 'Lose one objective you planned to hold', over: { plan: lose } });
  out.push({ key: 'kill', label: 'Trade harder: kill 50% more', over: { killRate: { [me]: m.killRate[me] * 1.5, [opp]: m.killRate[opp] } } });
  out.push({ key: 'safe', label: 'Play safer: lose 30% fewer units', over: { killRate: { [me]: m.killRate[me], [opp]: m.killRate[opp] * 0.7 } } });
  return out.map(l => ({ key: l.key, label: l.label, P: forecastParams({ ...l.over, trials: 1500 }) }));
}

let worker = null, reqId = 0, timer = null;
export function scheduleForecast() {
  clearTimeout(timer);
  ms().busy = true;
  timer = setTimeout(runForecast, 150);
}
function runForecast() {
  const P = forecastParams();
  const m = ms();
  reqId++;
  if (!P) { m.result = null; m.busy = false; refresh(); return; }
  if (worker && m.busy) { worker.terminate(); worker = null; }
  if (!worker) {
    worker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    worker.onmessage = (ev) => {
      if (ev.data.id !== reqId) return;
      const mm = ms();
      if (ev.data.error) { console.error('[calc] forecast error', ev.data.error); mm.busy = false; refresh(); return; }
      mm.result = ev.data.base;
      mm.levers = ev.data.variants;
      mm.busy = false;
      const r = mm.result;
      console.log(`[calc] forecast: A ${r.A.mean.toFixed(1)} (${r.A.p10}-${r.A.p90}) vs B ${r.B.mean.toFixed(1)} (${r.B.p10}-${r.B.p90}), A wins ${(r.pWinA * 100).toFixed(0)}%`);
      refresh();
    };
  }
  m.busy = true;
  worker.postMessage({ id: reqId, forecast: { base: P, variants: leverParams() } });
}

function refresh() {
  const host = document.getElementById('mission-forecast');
  if (host) host.innerHTML = forecastHtml();
  const sheet = document.getElementById('mission-cards');
  if (sheet) sheet.innerHTML = cardsHtml();
}

// ---------------------------------------------------------------------------
// Views

export function missionView() {
  const st = ctx.state, m = ms(), esc = ctx.esc;
  if (!st.armies.A || !st.armies.B) return '<p class="hint">Load both armies first.</p>';
  const bc = boardContext();
  const me = m.me, opp = other(me);
  const modeRow = (X) => `<div class="modrow"><div class="lab">${X} · ${esc(st.armies[X].faction)} secondaries</div>
      ${ctx.seg('mission-mode', m.modes[X].mode, [['tactical', 'Tactical'], ['fixed', 'Fixed']], `compact" data-side="${X}`)}
      ${m.modes[X].mode === 'fixed' ? `<div class="chips" style="margin-top:6px">${FIXED_IDS.map(id => ctx.chip('mission-fixed', m.modes[X].fixed.includes(id), SECONDARY_BY_ID[id].name, `data-side="${X}" data-id="${id}"`)).join('')}</div>` : ''}</div>`;
  return `
    <section class="section"><div class="card">
      <div class="small" id="mission-names"><b style="color:var(--side-a)">A</b> plays <b>${esc(bc.missions.A ?? '?')}</b> · <b style="color:var(--side-b)">B</b> plays <b>${esc(bc.missions.B ?? '?')}</b>
        <div class="tiny muted">${esc(bc.deployment?.name ?? '')} · layout ${bc.layout?.variant ?? '?'} — change it on the Board tab.</div></div>
      <div class="row" style="gap:8px;margin-top:8px;flex-wrap:wrap">
        <div><div class="lab tiny muted">I am</div>${ctx.seg('mission-me', me, [['A', `A · ${st.armies.A.faction}`], ['B', `B · ${st.armies.B.faction}`]], 'compact')}</div>
        <div><div class="lab tiny muted">First turn</div>${ctx.seg('mission-first', m.first ?? 'roll', [['A', 'A'], ['B', 'B'], ['roll', 'Roll-off']], 'compact')}</div>
      </div>
      <details class="more" style="margin-top:8px"><summary>Assumptions (modes, trading, actions)</summary>
        ${modeRow('A')}${modeRow('B')}
        ${['A', 'B'].map(X => `<div class="modrow"><div class="lab">${X}: units destroyed per turn</div>${ctx.seg('mission-kills', m.killRate[X], KILL_RATES, `compact" data-side="${X}`)}</div>`).join('')}
        ${['A', 'B'].map(X => `<div class="modrow"><div class="lab">${X}: mission actions (Cleanse, Plunder, ${esc(PRIMARIES[bc.missions[X]]?.action ? bc.missions[X] : 'primary actions')})</div>${ctx.seg('mission-action', m.actionP[X], ACTION_P, `compact" data-side="${X}`)}</div>`).join('')}
        <div class="chips" style="margin-top:6px">${['A', 'B'].map(X => ctx.chip('mission-ready', m.battleReady[X], `${X} Battle Ready (+10)`, `data-side="${X}"`)).join('')}</div>
      </details>
    </div></section>
    <section class="section"><h2>Forecast</h2><div id="mission-forecast">${forecastHtml()}</div></section>
    <section class="section"><h2>Objective plan</h2>${planHtml()}</section>
    <section class="section"><h2>Secondary cards</h2><div id="mission-cards">${cardsHtml()}</div></section>
    <section class="section"><h2>Game in progress</h2>${trackerHtml()}</section>`;
}

function fmt(n, d = 0) { return (Math.round(n * 10 ** d) / 10 ** d).toFixed(d); }
const pct = (p) => (p >= 0.995 ? '>99%' : p > 0 && p < 0.005 ? '<1%' : `${Math.round(p * 100)}%`);

function forecastHtml() {
  const m = ms(), r = m.result, esc = ctx.esc;
  if (!r) return `<p class="muted small">${m.busy ? 'Simulating the game…' : 'Pick a layout on the Board tab to forecast.'}</p>`;
  const me = m.me, opp = other(me);
  const R = { me: r[me], opp: r[opp] };
  const pWin = me === 'A' ? r.pWinA : r.pWinB, pLose = me === 'A' ? r.pWinB : r.pWinA;
  const margin = me === 'A' ? r.margin : { p10: -r.margin.p90, p50: -r.margin.p50, p90: -r.margin.p10 };
  const live = inProgress();
  const leadRow = r.lead.map((l, i) => {
    const ahead = me === 'A' ? l.A : l.B;
    return `<div class="cell"><b>${pct(ahead)}</b><span>R${i + 1}</span></div>`;
  }).join('');
  const roundRows = [[me, 'You'], [opp, 'Opp']].map(([X, lab]) => `<tr><td><span class="swatch" style="background:var(--side-${X.toLowerCase()})"></span>${lab} · ${X}</td>
      ${r[X].prim.map((p, i) => `<td>${fmt(p + r[X].sec[i])}<span class="tiny muted"> ${fmt(p)}+${fmt(r[X].sec[i])}</span></td>`).join('')}<td><b>${fmt(r[X].mean)}</b></td></tr>`).join('');
  const levers = (m.levers ?? []).map(l => {
    const lr = l.result;
    if (!lr) return '';
    const dWin = (me === 'A' ? lr.pWinA : lr.pWinB) - pWin;
    const dMe = lr[me].mean - R.me.mean, dOpp = lr[opp].mean - R.opp.mean;
    const sign = (x, d = 0) => `${x >= 0 ? '+' : '−'}${fmt(Math.abs(x), d)}`;
    return `<tr data-lever="${l.key}"><td>${esc(l.label)}</td><td class="${dWin >= 0 ? 'up' : 'down'}"><b>${sign(dWin * 100)}%</b></td><td>${sign(dMe, 1)}</td><td>${sign(dOpp, 1)}</td></tr>`;
  }).join('');
  return `<div class="hero" style="grid-template-columns:1fr 1fr 1fr">
      <div class="cell"><b id="fc-win">${pct(pWin)}</b><span>you win${r.pDraw >= 0.005 ? ` · draw ${pct(r.pDraw)}` : ''}</span></div>
      <div class="cell"><b id="fc-me">${fmt(R.me.mean)}</b><span>your VP (${R.me.p10}–${R.me.p90})</span></div>
      <div class="cell"><b id="fc-opp">${fmt(R.opp.mean)}</b><span>their VP (${R.opp.p10}–${R.opp.p90})</span></div>
    </div>
    <div class="small" style="margin-top:6px" id="fc-verdict">${verdict(pWin, pLose, margin)}</div>
    <div class="chart" style="margin-top:8px">${rangeChart(r, me)}</div>
    <div class="lab tiny muted" style="margin-top:8px">Chance you are ahead after each battle round</div>
    <div class="hero lead" id="fc-lead" style="grid-template-columns:repeat(5,1fr)">${leadRow}</div>
    <table class="dist" style="margin-top:8px"><thead><tr><th>VP by round</th><th>R1</th><th>R2</th><th>R3</th><th>R4</th><th>R5</th><th>Total</th></tr></thead><tbody>${roundRows}</tbody></table>
    <div class="tiny muted">Primary + secondary per round${live ? '' : ''}; totals include Battle Ready. ${r.trials.toLocaleString()} simulated games${m.busy ? ' (updating…)' : ''}.</div>
    ${levers ? `<div class="lab tiny muted" style="margin-top:10px">What changes the result</div>
      <table class="dist" id="fc-levers"><thead><tr><th>If you…</th><th>Win</th><th>You</th><th>Opp</th></tr></thead><tbody>${levers}</tbody></table>` : ''}
    <p class="hint">A planning model: objectives come from your plan below, kills from the trading rates, positional cards from army speed and size. Card VP and the 45 / 15-per-round caps are exact.</p>`;
}

function verdict(pWin, pLose, margin) {
  const m = margin.p50;
  if (pWin >= 0.65) return `<b>You're favoured</b> (typical margin ${m >= 0 ? '+' : ''}${m} VP): trade safely, deny their outs, don't over-commit.`;
  if (pLose >= 0.65) return `<b>You're behind</b> (typical margin ${m} VP): you need more objectives or kills — see what changes the result.`;
  return `<b>Close game</b> (typical margin ${m >= 0 ? '+' : ''}${m} VP): small swings decide it.`;
}

// Range chart: each player's final VP, 10th–90th percentile bar with the median dot.
function rangeChart(r, me) {
  const W = 340, rowH = 30, padL = 64, padR = 10, top = 6, H = top + 2 * rowH + 22;
  const x = (v) => padL + (v / 100) * (W - padL - padR);
  const rows = [[me, 'You'], [other(me), 'Opp']];
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Final VP range for each player">`;
  for (const t of [0, 25, 50, 75, 100]) svg += `<line class="axis" x1="${x(t)}" x2="${x(t)}" y1="${top}" y2="${top + 2 * rowH}" opacity="${t === 0 ? 1 : 0.4}"/><text class="tick" x="${x(t)}" y="${H - 6}" text-anchor="middle">${t}</text>`;
  rows.forEach(([X, lab], i) => {
    const d = r[X], y = top + i * rowH + rowH / 2;
    const col = `var(--side-${X.toLowerCase()})`;
    svg += `<text class="tick" x="4" y="${y + 4}" text-anchor="start">${lab} · ${X}</text>`;
    svg += `<g><title>${lab} (${X}): median ${d.p50} VP, 80% of games ${d.p10}–${d.p90} VP</title>`
      + `<rect x="${x(d.p10)}" y="${y - 4}" width="${Math.max(2, x(d.p90) - x(d.p10))}" height="8" rx="4" fill="${col}" opacity="0.55"/>`
      + `<circle cx="${x(d.p50)}" cy="${y}" r="6" fill="${col}" stroke="var(--surface-1)" stroke-width="2"/>`
      + `<rect x="${padL}" y="${y - rowH / 2}" width="${W - padL - padR}" height="${rowH}" fill="transparent"/></g>`;
  });
  return svg + '</svg>';
}

function planHtml() {
  const objs = objectives(), p = plan();
  if (!objs.length) return '<p class="hint">Pick a layout on the Board tab.</p>';
  const cell = (r, o) => {
    const v = p[r]?.[o.id] ?? 'c';
    return `<td><button class="plan-cell ${v === 'c' ? 'c' : v.toLowerCase()}" data-action="mission-plan" data-r="${r}" data-o="${o.id}" aria-label="${o.label} round ${r}: ${v === 'c' ? 'contested' : v}">${v === 'c' ? '½' : v}</button></td>`;
  };
  return `<table class="plan" id="mission-plan"><thead><tr><th>Objective</th>${[1, 2, 3, 4, 5].map(r => `<th>R${r}</th>`).join('')}</tr></thead>
    <tbody>${objs.map(o => `<tr><td>${ctx.esc(o.label)}</td>${[1, 2, 3, 4, 5].map(r => cell(r, o)).join('')}</tr>`).join('')}</tbody></table>
    <div class="tiny muted">Who controls each objective in each battle round: tap to cycle A → B → ½ (contested, a coin flip). Rounds already played are ignored once you track the game below.</div>`;
}

// ---- secondary cards: matchup sheet, keep-ready, hit list

const KEEP_READY = {
  'behind-enemy-lines': 'Keep a fast / Deep Strike unit to get wholly into their deployment zone (3 VP each, max 5).',
  'engage-on-all-fronts': 'Spread units into 3–4 table quarters, more than 6" from the centre.',
  'centre-ground': 'Have a unit that can reach the centre and keep enemies 6" away from it.',
  'outflank': 'Keep units near both long battlefield edges, outside your territory.',
  'display-of-might': 'Out-number them in No Man’s Land at the end of their turn (5 VP).',
  'beacon': 'Plan a durable unit to sit outside your territory (5 VP).',
  'plunder': 'Get a unit into a terrain area outside your territory in your Shooting phase.',
  'cleanse': 'Have cheap units on two non-home objectives (action in the Shooting phase).',
  'defend-stronghold': 'Keep your home objective and keep your deployment zone clear.',
  'burden-of-trust': 'Guard the objectives you hold through their turn.',
  'secure-no-mans-land': 'Hold two No Man’s Land objectives at the end of your turn.',
  'a-tempting-target': 'Be able to take any No Man’s Land objective — they pick the hardest.',
  'forward-position': 'Push onto their home objective or both expansions.',
};

function cardsHtml() {
  const m = ms(), esc = ctx.esc;
  const side = m.sheetSide ?? m.me;
  const enemy = profileOf(other(side));
  if (!enemy) return '';
  const res = m.result?.[side]?.cards ?? {};
  const rows = SECONDARIES.map(c => {
    const dead = cardDead(c.id, enemy.profile);
    const s = res[c.id];
    return { c, dead, perDraw: dead ? 0 : (s?.perDraw ?? null), quick: s?.quickRate ?? null };
  }).sort((a, b) => (a.dead - b.dead) || ((b.perDraw ?? -1) - (a.perDraw ?? -1)));
  const skill = m.skill[side] ?? {};
  const row = ({ c, dead, perDraw, quick }) => {
    const open = m.cardOpen === `${side}:${c.id}`;
    // strong = pays well AND usually scores straight away; hard = slow or low
    const tag = dead ? '<span class="pill bad">Dead</span>' : perDraw == null ? '' : perDraw >= 3.5 && quick >= 0.6 ? '<span class="pill good">Strong</span>' : perDraw >= 2.5 && quick >= 0.35 ? '<span class="pill">OK</span>' : '<span class="pill weak">Hard</span>';
    return `<tr class="card-row" data-card="${c.id}"><td><button class="linkish" data-action="mission-card" data-id="${c.id}">${esc(c.name)}</button>${c.fixed ? ' <span class="tiny muted">F</span>' : ''}</td>
      <td>${tag}</td><td>${dead ? '–' : perDraw == null ? '…' : fmt(perDraw, 1)}</td><td>${dead || quick == null ? '–' : pct(quick)}</td></tr>
      ${open ? `<tr class="card-detail"><td colspan="4"><div class="small">${esc(c.text)}</div>${c.drawn ? `<div class="tiny muted">When drawn: ${esc(c.drawn)}</div>` : ''}
        ${c.fixedText ? `<div class="tiny muted">Fixed: ${esc(c.fixedText)}</div>` : ''}
        ${dead ? `<div class="tiny" style="margin-top:4px">No targets in the ${side === m.me ? 'enemy' : 'your'} army: discard it (and draw again if the card allows).</div>`
          : c.kind === 'kill' ? '' : `<div class="modrow"><div class="lab tiny muted">How easy is this for ${side} on this table?</div>${ctx.seg('mission-skill', skill[c.id] ?? 1, SKILL, `compact" data-side="${side}" data-id="${c.id}`)}</div>`}</td></tr>` : ''}`;
  };
  // keep-ready: my best live non-kill cards by expected VP over the game
  const mine = m.result?.[m.me]?.cards ?? {};
  const ready = SECONDARIES.filter(c => KEEP_READY[c.id] && !cardDead(c.id, profileOf(other(m.me)).profile))
    .map(c => ({ c, ev: (mine[c.id]?.perDraw ?? 0) * (mine[c.id]?.drawRate ?? 0) }))
    .sort((a, b) => b.ev - a.ev).slice(0, 5);
  return `${ctx.seg('mission-sheet-side', side, [[m.me, 'My cards'], [other(m.me), 'Their cards']], 'compact')}
    <table class="dist cards" style="margin-top:6px"><thead><tr><th>Card</th><th></th><th>VP if drawn</th><th>Quick</th></tr></thead><tbody>${rows.map(row).join('')}</tbody></table>
    <div class="tiny muted">VP if drawn: average VP the card earns for ${side} when it comes up (cards stay active until scored). Quick: how often it scores by the end of the next turn. F = can be taken as Fixed. Tap a card for its text and to say how easy it is on this table.</div>
    ${side === m.me ? `<div class="lab tiny muted" style="margin-top:10px">Keep ready for</div><ul class="keep" id="mission-keep">${ready.map(x => `<li><b>${esc(x.c.name)}</b> — ${esc(KEEP_READY[x.c.id])}</li>`).join('')}</ul>` : ''}
    <div class="lab tiny muted" style="margin-top:10px">${side === m.me ? 'Hit list: enemy units worth secondary VP' : 'Your units they score from'}</div>${hitListHtml(side)}`;
}

function hitListHtml(side) {
  const esc = ctx.esc;
  const enemySide = other(side);
  const facts = profileOf(enemySide).facts;
  const rows = facts.map(u => {
    const tags = [];
    if (u.characters) tags.push(`Assassination (${u.characters} character${u.characters > 1 ? 's' : ''})`);
    if (u.w10) tags.push(`Bring It Down (W10+ ×${u.w10})`);
    if (u.bodyguardModels >= 13) tags.push('A Grievous Blow (13+ models)');
    return { u, tags, value: tags.length * 5 + u.points / 100 };
  }).filter(x => x.tags.length).sort((a, b) => b.value - a.value);
  if (!rows.length) return '<p class="muted small">No units feed the kill cards (characters, W10+ or 13+ models).</p>';
  return `<ul class="keep" id="mission-hit-${side}">${rows.map(x => `<li><b>${esc(x.u.name)}</b> <span class="muted">(${x.u.points} pts)</span> — ${x.tags.map(esc).join(' · ')}</li>`).join('')}</ul>
    <div class="tiny muted">Every kill also feeds No Prisoners (2 VP per unit) and, on objectives, Overwhelming Force.</div>`;
}

// ---- in-game tracker

function trackerHtml() {
  const m = ms(), g = m.game, esc = ctx.esc;
  const deckOf = (X) => SECONDARIES.map(c => c.id).filter(id => !g[X].hand.includes(id) && !g[X].used.includes(id));
  const playerCard = (X) => {
    const deck = deckOf(X);
    const mode = m.modes[X].mode;
    return `<div class="card" style="margin-top:8px" data-player="${X}">
      <div class="title" style="color:var(--side-${X.toLowerCase()})">${X} · ${esc(ctx.state.armies[X].faction)}</div>
      <div class="row" style="gap:8px;margin-top:6px">
        <label class="grow small">Primary VP <input class="num" type="number" inputmode="numeric" min="0" max="45" data-input="mission-score" data-side="${X}" data-k="primary" value="${g[X].primary}"></label>
        <label class="grow small">Secondary VP <input class="num" type="number" inputmode="numeric" min="0" max="45" data-input="mission-score" data-side="${X}" data-k="secondary" value="${g[X].secondary}"></label>
      </div>
      ${mode === 'tactical' ? `<div class="lab tiny muted" style="margin-top:8px">Active cards</div>
        <div class="chips" id="hand-${X}">${g[X].hand.length ? g[X].hand.map(id => `<span class="chip on nocheck">${esc(SECONDARY_BY_ID[id].name)}
          <button class="mini" data-action="mission-hand" data-side="${X}" data-id="${id}" data-do="scored" aria-label="Scored ${esc(SECONDARY_BY_ID[id].name)}">✓</button>
          <button class="mini" data-action="mission-hand" data-side="${X}" data-id="${id}" data-do="discard" aria-label="Discard ${esc(SECONDARY_BY_ID[id].name)}">✕</button></span>`).join('') : '<span class="muted small">None.</span>'}</div>
        <select class="sel" data-input="mission-draw" data-side="${X}" aria-label="Card ${X} drew" style="margin-top:6px"><option value="">＋ Drew a card…</option>${deck.map(id => `<option value="${id}">${esc(SECONDARY_BY_ID[id].name)}</option>`).join('')}</select>
        <div class="tiny muted" id="odds-${X}">${deck.length} cards left: each has a ${pct(Math.min(1, RULES.drawPerTurn / Math.max(1, deck.length)))} chance to come up next draw.${g[X].used.length ? ` Done: ${g[X].used.map(id => esc(SECONDARY_BY_ID[id].name)).join(', ')}.` : ''}</div>`
        : `<div class="tiny muted" style="margin-top:6px">Fixed: ${m.modes[X].fixed.map(id => esc(SECONDARY_BY_ID[id].name)).join(', ') || 'pick two under Assumptions'}.</div>`}
      <details class="more" style="margin-top:6px"><summary>${X}'s units destroyed (${g[X].destroyed.length})</summary>
        <div class="chips">${ctx.state.armies[X].units.map(u => ctx.chip('mission-dead', g[X].destroyed.includes(u.name), u.name, `data-side="${X}" data-name="${esc(u.name)}"`)).join('')}</div></details>
    </div>`;
  };
  return `<div class="card">
      <div class="row" style="gap:8px;flex-wrap:wrap">
        <div><div class="lab tiny muted">Battle round</div>${ctx.seg('mission-round', g.round, [1, 2, 3, 4, 5].map(r => [r, String(r)]), 'compact')}</div>
        <div><div class="lab tiny muted">Next to play</div>${ctx.seg('mission-next', g.next ?? m.first ?? 'A', [['A', 'A'], ['B', 'B']], 'compact')}</div>
      </div>
      <div class="tiny muted" style="margin-top:6px">Enter the score and cards as you play; the forecast re-runs from this point.</div>
      <button class="btn ghost" style="margin-top:6px" data-action="mission-reset">Reset game</button>
    </div>${playerCard(m.me)}${playerCard(other(m.me))}`;
}

// ---------------------------------------------------------------------------
// Actions

export function missionAction(action, el) {
  const m = ms(), g = m.game;
  const X = el.dataset.side;
  switch (action) {
    case 'mission-me': m.me = el.dataset.value; m.sheetSide = null; break;
    case 'mission-first': m.first = el.dataset.value === 'roll' ? null : el.dataset.value; break;
    case 'mission-mode': m.modes[X].mode = el.dataset.value; break;
    case 'mission-fixed': {
      const f = m.modes[X].fixed, id = el.dataset.id;
      if (f.includes(id)) f.splice(f.indexOf(id), 1); else { f.push(id); if (f.length > 2) f.shift(); }
      break;
    }
    case 'mission-kills': m.killRate[X] = Number(el.dataset.value); break;
    case 'mission-action': m.actionP[X] = Number(el.dataset.value); break;
    case 'mission-ready': m.battleReady[X] = !m.battleReady[X]; break;
    case 'mission-plan': {
      const p = plan(), r = el.dataset.r, o = el.dataset.o;
      const cur = p[r][o] ?? 'c';
      p[r][o] = cur === 'A' ? 'B' : cur === 'B' ? 'c' : 'A';
      break;
    }
    case 'mission-sheet-side': m.sheetSide = el.dataset.value; m.cardOpen = null; persist(); refresh(); return null;
    case 'mission-card': {
      const k = `${m.sheetSide ?? m.me}:${el.dataset.id}`;
      m.cardOpen = m.cardOpen === k ? null : k;
      refresh();
      return null;
    }
    case 'mission-skill': m.skill[X][el.dataset.id] = Number(el.dataset.value); break;
    case 'mission-round': g.round = Number(el.dataset.value); break;
    case 'mission-next': g.next = el.dataset.value; break;
    case 'mission-hand': {
      const id = el.dataset.id;
      g[X].hand = g[X].hand.filter(h => h !== id);
      if (!g[X].used.includes(id)) g[X].used.push(id);
      break;
    }
    case 'mission-dead': {
      const n = el.dataset.name, d = g[X].destroyed;
      if (d.includes(n)) d.splice(d.indexOf(n), 1); else d.push(n);
      break;
    }
    case 'mission-reset': m.game = newGame(); break;
    default: return null;
  }
  persist();
  scheduleForecast();
  return 'render';
}

export function missionChange(el) {
  const m = ms(), g = m.game, X = el.dataset.side;
  if (el.dataset.input === 'mission-draw') {
    const id = el.value;
    if (id && !g[X].hand.includes(id)) g[X].hand.push(id);
    persist(); scheduleForecast();
    return true;
  }
  if (el.dataset.input === 'mission-score') {
    // no re-render: the player may be moving on to the next score box
    g[X][el.dataset.k] = Math.max(0, Math.min(45, Number(el.value) || 0));
    persist(); scheduleForecast();
    return 'quiet';
  }
  return false;
}

let lastSig = '';
export function missionAfterRender() {
  // re-forecast when anything it depends on changed (lists, layout on the Board tab, plan, tracker)
  const P = forecastParams({ trials: 0 });
  const sig = P ? JSON.stringify(P) : '';
  if (sig !== lastSig || (!ms().result && !ms().busy)) { lastSig = sig; scheduleForecast(); }
}

// for tests
export function _missionDebug() {
  const m = ms();
  return { me: m.me, result: m.result, levers: m.levers, busy: !!m.busy, objectives: objectives(), plan: plan(), game: m.game, params: forecastParams({ trials: 10 }) };
}
