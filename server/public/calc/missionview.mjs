// Mission tab: secondary-card planner (matchup sheet, keep-ready list, hit
// list), objective plan, VP forecast for both players with what-ifs, and an
// in-game tracker (cards drawn / scored / discarded, score) that the forecast
// re-runs from. The simulation is forecast.mjs, run in the worker.
//
// app.js owns the shared state and calls in through initMission().

import { SECONDARIES, SECONDARY_BY_ID, FIXED_IDS, PRIMARIES, RULES } from './missions-11e.mjs';
import { armyProfile, cardDead, POSITION_CARDS, RATING } from './forecast.mjs';
import { abilitiesOf } from './adapter.mjs';
import { boardContext, boardPlans } from './boardview.mjs';
import { unitFacts as positionFacts, exposure, planWarnings } from './planeval.mjs';

let ctx = null;            // { state, esc, seg, chip }
const LS_KEY = 'w40k_calc_mission_v1';
const other = (p) => (p === 'A' ? 'B' : 'A');
const KILL_RATES = [[0.8, 'Low'], [1.3, 'Even'], [2, 'High']];
const ACTION_P = [[0.9, 'Easy'], [0.7, 'OK'], [0.45, 'Hard']];


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
    killRate: { A: 1.3, B: 1.3 }, actionP: { A: 0.7, B: 0.7 }, rate: { A: {}, B: {} }, est: { A: {}, B: {} },
    plans: {}, game: newGame(), sheetSide: null, cardOpen: null,
    source: 'grid',          // objectives / positions from the grid, or a board plan (its index)
    enemyFrom: 'board',      // enemy positions from the board plan, or the grid toggles
  };
  return s.mission;
}
function newGame() {
  return { round: 1, next: null, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } };
}
function persist() {
  const m = ms();
  const { result, levers, busy, compare, pairs, ...keep } = m;
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
    // roles come from the official 11e cards (home / central / expansion); some layouts have two centrals
    if (o.role === 'home' || o.zone !== 'no_mans_land') { const side = sideOfZone(o.zone); out.push({ id: o.id, cls: 'home', side, label: `${side} home` }); continue; }
    if (o.role === 'central') { out.push({ id: o.id, cls: 'central', side: null, label: 'Centre' }); continue; }
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
// Board plans -> forecast board model

function geo() {
  const bc = boardContext();
  const l = bc.layout, dep = bc.deployment;
  if (!l || !dep) return null;
  const pick = (list, X) => list?.find(z => z.player === (X === 'A' ? bc.zoneA : bc.zoneB))?.poly ?? null;
  return {
    zones: { A: pick(dep.zones, 'A'), B: pick(dep.zones, 'B') },
    territories: { A: pick(dep.territories, 'A'), B: pick(dep.territories, 'B') },
    pieces: l.pieces, objectives: l.objectives,
  };
}

// unit-vs-unit odds (P destroyed by shooting / in a fight), worked out once per pair of lists
function pairSig() {
  const st = ctx.state;
  return ['A', 'B'].map(X => st.armies[X]?.units.map(u => u.key + u.name + u.models).join(',')).join('|');
}
let pairsPending = false;
function ensurePairs() {
  const m = ms();
  const sig = pairSig();
  if (m.pairs?.sig === sig || pairsPending || !ctx.pairOdds) return m.pairs?.sig === sig;
  const st = ctx.state, jobs = [];
  for (const X of ['A', 'B']) for (const a of st.armies[X].units) for (const d of st.armies[other(X)].units)
    for (const phase of ['shooting', 'fight']) jobs.push({ key: `${X}:${a.key}>${other(X)}:${d.key}|${phase}`, atkSide: X, atkKey: a.key, defKey: d.key, phase });
  pairsPending = true;
  ctx.pairOdds(jobs).then((res) => {
    const table = {};
    for (const [k, v] of Object.entries(res)) {
      const [ad, phase] = k.split('|');
      const [atk, def] = ad.split('>');
      ((table[atk] ??= {})[def] ??= { shoot: 0, fight: 0 })[phase === 'shooting' ? 'shoot' : 'fight'] = v.pWipe ?? 0;
    }
    ms().pairs = { sig, table };
    pairsPending = false;
    scheduleForecast();
  });
  return false;
}

/** The forecast's board model for plan `vi`: units per round with measured facts, and exposure. */
function boardModel(vi) {
  const m = ms(), g = geo();
  const plan = boardPlans()[vi];
  if (!g || !plan) return null;
  const steps = plan.steps;
  const rounds = {}, pDie = {};
  const stepFor = (r) => steps[Math.min(r, steps.length - 1)];
  for (let r = 1; r <= RULES.rounds; r++) {
    const st = stepFor(r);
    rounds[r] = {};
    for (const X of ['A', 'B']) {
      const use = st[X].length && (X === m.me || m.enemyFrom === 'board');
      rounds[r][X] = use ? st[X].map(u => ({ name: u.name, f: positionFacts(u, X, g) })) : null;
    }
    pDie[r] = {};
    if (m.pairs?.table) {
      for (const X of ['A', 'B']) {
        const Y = other(X);
        if (!rounds[r][X] || !rounds[r][Y]) continue;
        // planned positions are where units are after moving: no extra move
        const atk = st[Y].map(u => ({ ...u, move: 0 }));
        const e = exposure(st[X], atk, m.pairs.table);
        pDie[r][X] = Object.fromEntries(st[X].map(u => [u.name, e[u.key] ?? 0]));
      }
    }
  }
  return { rounds, pDie, warnings: planWarnings(steps, g), stepsPlanned: steps.length, name: plan.name };
}
function sourcePlan() {
  const m = ms();
  if (m.source === 'grid') return null;
  const plans = boardPlans();
  return plans[Number(m.source)] ? Number(m.source) : null;
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
    rate: m.rate[X], vpEst: m.est?.[X] ?? {}, battleReady: m.battleReady[X],
    start: live ? { hand: g[X].hand, used: g[X].used, primary: g[X].primary, secondary: g[X].secondary, destroyed: g[other(X)].destroyed } : null,
  });
  const next = g.next ?? first ?? 'A';
  const vi = over.boardPlan === undefined ? sourcePlan() : over.boardPlan;
  return {
    players: { A: player('A'), B: player('B') },
    objectives: objectives().map(({ id, cls, side }) => ({ id, cls, side })),
    plan: over.plan ?? plan(), first,
    boardPlan: vi == null ? null : boardModel(vi),
    startRound: live ? g.round : 1, startTurn: live && first ? (next === first ? 0 : 1) : 0,
    trials: over.trials ?? 4000, seed: 20261116,
  };
}

// what-ifs from "my" side: each is a tweak of the plan or the trading rates
function leverParams() {
  const m = ms(), me = m.me, opp = other(me);
  // with a board plan the comparison between plans is the "what if"
  if (sourcePlan() != null) return [];
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
  if (boardPlans().length) ensurePairs();
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
      mm.levers = ev.data.variants.filter(v => !v.compare);
      mm.compare = ev.data.variants.filter(v => v.compare);
      mm.busy = false;
      const r = mm.result;
      console.log(`[calc] forecast: A ${r.A.mean.toFixed(1)} (${r.A.p10}-${r.A.p90}) vs B ${r.B.mean.toFixed(1)} (${r.B.p10}-${r.B.p90}), A wins ${(r.pWinA * 100).toFixed(0)}%`);
      refresh();
    };
  }
  m.busy = true;
  const compare = [{ key: 'grid', label: 'Objective grid', P: forecastParams({ boardPlan: null, trials: 1500 }) },
    ...boardPlans().map(p => ({ key: `plan${p.index}`, label: `Board: ${p.name}`, P: forecastParams({ boardPlan: p.index, trials: 1500 }) }))];
  worker.postMessage({ id: reqId, forecast: { base: P, variants: [...leverParams(), ...compare.map(c => ({ ...c, compare: true }))] } });
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
      <details class="more" style="margin-top:8px" data-details="mission-assume" ${m.openAssume ? 'open' : ''}><summary>Assumptions (modes, trading, actions)</summary>
        ${modeRow('A')}${modeRow('B')}
        ${['A', 'B'].map(X => `<div class="modrow"><div class="lab">${X}: units destroyed per turn</div>${ctx.seg('mission-kills', m.killRate[X], KILL_RATES, `compact" data-side="${X}`)}</div>`).join('')}
        ${['A', 'B'].map(X => `<div class="modrow"><div class="lab">${X}: mission actions (Cleanse, Plunder, ${esc(PRIMARIES[bc.missions[X]]?.action ? bc.missions[X] : 'primary actions')})</div>${ctx.seg('mission-action', m.actionP[X], ACTION_P, `compact" data-side="${X}`)}</div>`).join('')}
        <div class="chips" style="margin-top:6px">${['A', 'B'].map(X => ctx.chip('mission-ready', m.battleReady[X], `${X} Battle Ready (+10)`, `data-side="${X}"`)).join('')}</div>
      </details>
    </div></section>
    <section class="section"><h2>Forecast</h2><div id="mission-forecast">${forecastHtml()}</div></section>
    <section class="section"><h2>Plan</h2>${sourceHtml()}${planHtml()}</section>
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
    ${compareHtml(me, opp)}
    <p class="hint">A planning model: objectives and positions come from your plan (grid or board), kills from the trading rates or the planned positions, and cards that depend on positions from your ratings when no board plan is used. Card VP and the 45 / 15-per-round caps are exact.</p>`;
}

function compareHtml(me, opp) {
  const m = ms(), esc = ctx.esc;
  const rows = (m.compare ?? []).filter(c => c.result);
  if (rows.length < 2) return '';
  const best = Math.max(...rows.map(c => (me === 'A' ? c.result.pWinA : c.result.pWinB)));
  return `<div class="lab tiny muted" style="margin-top:10px">Your plans compared</div>
    <table class="dist" id="fc-compare"><thead><tr><th>Plan</th><th>Win</th><th>You</th><th>Opp</th></tr></thead><tbody>
    ${rows.map(c => { const w = me === 'A' ? c.result.pWinA : c.result.pWinB; return `<tr data-plan="${c.key}"><td>${esc(c.label)}${w === best ? ' ★' : ''}</td><td><b>${pct(w)}</b></td><td>${fmt(c.result[me].mean)} <span class="tiny muted">${c.result[me].p10}–${c.result[me].p90}</span></td><td>${fmt(c.result[opp].mean)}</td></tr>`; }).join('')}
    </tbody></table>`;
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

function sourceHtml() {
  const m = ms(), esc = ctx.esc;
  const plans = boardPlans();
  const opts = [['grid', 'Objective grid'], ...plans.map(p => [String(p.index), `Board: ${p.name}`])];
  const vi = sourcePlan();
  let extra = '';
  if (vi != null) {
    const bm = boardModel(vi);
    const warn = (bm?.warnings ?? []).filter(w => w.side === m.me || m.enemyFrom === 'board');
    // only placed units count: say so when part of an army is missing from the plan
    const plan = boardPlans()[vi];
    const placedNames = (X) => new Set(plan.steps.flatMap(st => st[X].map(u => u.name)));
    const missing = ['A', 'B'].filter(X => X === m.me || m.enemyFrom === 'board').map(X => {
      const n = ctx.state.armies[X].units.length, p = placedNames(X).size;
      return p < n ? `${X}: ${p} of ${n} units placed` : null;
    }).filter(Boolean);
    extra = `<div class="modrow" style="margin-top:6px"><div class="lab tiny muted">Enemy (${other(m.me)}) positions</div>
        ${ctx.seg('mission-enemy-from', m.enemyFrom, [['board', 'From the board plan'], ['toggles', 'From the grid below']], 'compact')}</div>
      <div class="tiny muted" id="mission-board-note">Measured on the board plan <b>${esc(bm?.name ?? '')}</b>: who controls each objective (OC of units in range), Behind Enemy Lines, quarters, edges, centre and No Man's Land, and how exposed each unit is to the enemy's planned units. Steps map to battle rounds (Turn 1 = round 1; the last step carries on).${bm && bm.stepsPlanned < 2 ? ' <b>Only the deployment is planned</b> — add turns on the Board tab.' : ''}${m.pairs?.table ? '' : ' Working out unit-vs-unit odds…'}</div>
      ${missing.length ? `<div class="small" style="color:var(--warn);margin-top:4px" id="mission-plan-missing">Only units placed on the board count (${missing.join(' · ')}) — place the rest on the Board tab or they hold nothing and score nothing.</div>` : ''}
      ${warn.length ? `<ul class="keep warn" id="mission-plan-warnings">${warn.slice(0, 8).map(w => `<li${w.info ? ' class="info"' : ''}>${esc(w.step)} · ${w.side} ${esc(w.unit)}: ${esc(w.msg)}</li>`).join('')}</ul>` : ''}`;
  }
  return `<div class="modrow"><div class="lab tiny muted">Objectives and positions from</div>${ctx.seg('mission-source', m.source, opts, 'compact')}</div>
    ${plans.length ? '' : '<div class="tiny muted">Plan unit positions per turn on the Board tab (＋ Next turn, ＋ Copy plan) to forecast from them.</div>'}${extra}`;
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
    <div class="tiny muted">${sourcePlan() != null
      ? `With a board plan this grid is only used for the enemy when their positions come “from the grid” (or a round where a side has no units placed): ${other(ms().me)}'s cells say where they will be.`
      : 'Who controls each objective in each battle round: tap to cycle A → B → ½ (contested, a coin flip).'} Rounds already played are ignored once you track the game below.</div>`;
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
  const est = m.est?.[side] ?? {};
  const fixedMode = m.modes[side].mode === 'fixed';
  const row = ({ c, dead, perDraw, quick }) => {
    const open = m.cardOpen === `${side}:${c.id}`;
    // strong = pays well AND usually scores straight away; hard = slow or low
    const position = POSITION_CARDS.includes(c.id);
    const tag = dead ? '<span class="pill bad">Dead</span>'
      // where-your-units-are cards: never guessed, the player rates them
      : est[c.id] != null && !fixedMode ? '<span class="pill mine">Your estimate</span>'
      : position && sourcePlan() != null && (side === m.me || m.enemyFrom === 'board') ? '<span class="pill good">Board plan</span>'
      : position ? '<span class="pill ask">You rate it</span>'
      : perDraw == null ? '' : perDraw >= 3.5 && quick >= 0.6 ? '<span class="pill good">Strong</span>' : perDraw >= 2.5 && quick >= 0.35 ? '<span class="pill">OK</span>' : '<span class="pill weak">Hard</span>';
    return `<tr class="card-row" data-card="${c.id}"><td><button class="linkish" data-action="mission-card" data-id="${c.id}">${esc(c.name)}</button>${c.fixed ? ' <span class="tiny muted">F</span>' : ''}</td>
      <td>${tag}</td><td>${dead ? '–' : perDraw == null ? '…' : fmt(perDraw, 1)}</td><td class="muted">${fixedMode && c.fixed ? c.fixedMax : c.max}</td><td>${dead || quick == null ? '–' : pct(quick)}</td></tr>
      ${open ? `<tr class="card-detail"><td colspan="5"><div class="small">${esc(c.text)}</div>${c.drawn ? `<div class="tiny muted">When drawn: ${esc(c.drawn)}</div>` : ''}
        ${c.fixedText ? `<div class="tiny muted">Fixed: ${esc(c.fixedText)}</div>` : ''}
        ${dead ? `<div class="tiny" style="margin-top:4px">No targets in the ${side === m.me ? 'enemy' : 'your'} army: discard it (and draw again if the card allows).</div>`
          : `<div class="tiny muted" style="margin-top:4px">${est[c.id] != null ? 'Using your estimate.'
              : c.kind === 'kill' ? 'App estimate: from units destroyed in the forecast and which enemy units are valid targets.'
              : position ? (sourcePlan() != null && (side === m.me || m.enemyFrom === 'board') ? 'App estimate: measured from the board plan.' : 'Depends on where units are, which is not measured here: the app assumes it scores about half the turns it is active. Set your own estimate.')
              : 'App estimate: from the objective plan.'}</div>
            ${fixedMode ? '<div class="tiny muted">Taken as Fixed: your estimate applies to Tactical play only.</div>' : estimateHtml(c, side, est[c.id], perDraw)}`}</td></tr>` : ''}`;
  };
  // keep-ready: my best live non-kill cards by expected VP over the game
  const mine = m.result?.[m.me]?.cards ?? {};
  const ready = SECONDARIES.filter(c => KEEP_READY[c.id] && !cardDead(c.id, profileOf(other(m.me)).profile) && (m.est?.[m.me]?.[c.id] ?? 1) > 0)
    .map(c => ({ c, ev: (mine[c.id]?.perDraw ?? 0) * (mine[c.id]?.drawRate ?? 0) }))
    .sort((a, b) => b.ev - a.ev).slice(0, 5);
  return `${ctx.seg('mission-sheet-side', side, [[m.me, 'My cards'], [other(m.me), 'Their cards']], 'compact')}
    <table class="dist cards" style="margin-top:6px"><thead><tr><th>Card</th><th></th><th>VP if drawn</th><th>Max</th><th>Quick</th></tr></thead><tbody>${rows.map(row).join('')}</tbody></table>
    <div class="tiny muted">VP if drawn: average VP the card earns for ${side} when it comes up (the app's estimate, or yours). Max: the most it can pay when it scores. Quick: how often it scores by the end of the next turn. F = can be taken as Fixed. Tap a card to set your own estimate — e.g. Assassination 3 of 5 if you are only fairly sure you can kill a character.</div>
    ${side === m.me ? `<div class="lab tiny muted" style="margin-top:10px">Keep ready for</div><ul class="keep" id="mission-keep">${ready.map(x => `<li><b>${esc(x.c.name)}</b> — ${esc(KEEP_READY[x.c.id])}</li>`).join('')}</ul>` : ''}
    <div class="lab tiny muted" style="margin-top:10px">${side === m.me ? 'Hit list: enemy units worth secondary VP' : 'Your units they score from'}</div>${hitListHtml(side)}`;
}

// your own estimate of a card's VP if drawn, from 0 up to its max, in 0.5 VP steps
function estimateHtml(c, side, value, appValue) {
  const v = value ?? null;
  const shown = v ?? (appValue == null ? null : Math.round(appValue * 2) / 2);
  return `<div class="row est" style="gap:8px;margin-top:6px;align-items:center" data-side="${side}" data-id="${c.id}">
      <span class="lab small grow">Your estimate: VP if drawn</span>
      <div class="stepper"><button data-action="mission-est" data-delta="-0.5" data-side="${side}" data-id="${c.id}" aria-label="Less">−</button>
        <div class="val" id="est-${side}-${c.id}">${shown == null ? '–' : fmt(shown, 1)}<span class="tiny muted"> / ${c.max}</span></div>
        <button data-action="mission-est" data-delta="0.5" data-side="${side}" data-id="${c.id}" aria-label="More">+</button></div>
      ${v != null ? `<button class="btn ghost" data-action="mission-est-auto" data-side="${side}" data-id="${c.id}">Use the app's</button>` : ''}
    </div>
    <div class="tiny muted">${v != null ? `The forecast now gives this card ${fmt(v, 1)} of its ${c.max} VP on average when drawn (it pays ${c.max} VP in ${Math.round((100 * v) / c.max)}% of games).` : `Starts from the app's estimate${appValue == null ? '' : ` (${fmt(appValue, 1)})`}; + / − to set your own.`}</div>`;
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
      <details class="more" style="margin-top:6px" data-details="mission-dead-${X}" ${m.openDead?.[X] ? 'open' : ''}><summary>${X}'s units destroyed (${g[X].destroyed.length})</summary>
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
  // segmented buttons carry the army / card on their row, not on the button
  const X = el.dataset.side ?? el.closest('[data-side]')?.dataset.side;
  if (!el.dataset.id && el.closest('[data-id]')) el.dataset.id = el.closest('[data-id]').dataset.id;
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
    case 'mission-rate': m.rate[X][el.dataset.id] = Number(el.dataset.value); break;
    case 'mission-est': {
      // first press starts from the app's current estimate (rounded to 0.5)
      m.est ??= { A: {}, B: {} };
      const id = el.dataset.id, max = SECONDARY_BY_ID[id]?.max ?? 5;
      const app = m.result?.[X]?.cards?.[id]?.perDraw;
      const cur = m.est[X][id] ?? (app == null ? max / 2 : Math.round(app * 2) / 2);
      m.est[X][id] = Math.max(0, Math.min(max, cur + Number(el.dataset.delta)));
      break;
    }
    case 'mission-est-auto': delete m.est[X][el.dataset.id]; break;
    case 'mission-source': m.source = el.dataset.value; break;
    case 'mission-enemy-from': m.enemyFrom = el.dataset.value; break;
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
  return { me: m.me, result: m.result, levers: m.levers, compare: m.compare, busy: !!m.busy, objectives: objectives(), plan: plan(), game: m.game, source: m.source, pairsReady: !!m.pairs?.table, board: sourcePlan() != null ? boardModel(sourcePlan()) : null, params: forecastParams({ trials: 10 }) };
}
