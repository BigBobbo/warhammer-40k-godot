// Combat calculator UI. State lives in localStorage; the dataset/importer
// come from the Army Builder modules (adapter.mjs); the dice run in a Web
// Worker (worker.mjs -> engine.mjs).
import {
  importArmy, attackerRows, engineWeapon, allVehicleMonster, abilitiesOf,
  defenderProfile, defenderSummary, buildDefender, DATASET_VERSION,
  setAttachments, withAttachment, attachCandidates, joinCandidates, rosterUnitLabel,
  attackerRules, attackerRuleOn, buildAttacker, describeConditions, unitIntel, armyIntel,
} from './adapter.mjs';
import { chargeOdds, chargeRollNeeded } from './engine.mjs';
import { initBoard, boardView, boardAction, boardChange, afterRender as boardAfterRender, _boardDebug } from './boardview.mjs';

const LS_KEY = 'w40k_calc_v1';
const TRIALS = 20000;
const app = document.getElementById('app');

// ---------------------------------------------------------------------------
// State

const state = {
  view: 'armies',            // 'armies' | 'attack'
  texts: { A: '', B: '' },
  armies: { A: null, B: null }, // parsed (not persisted)
  errors: { A: null, B: null },
  side: 'A',                 // attacking army
  phase: 'shooting',
  setups: {},                // `${side}:${phase}` -> { targetKey, attackers: [], ruleOverrides: {}, defManual: {} }
  attach: { A: null, B: null }, // per army: { [characterRosterIndex]: bodyguardRosterIndex } once edited (null = as listed)
  sheet: null,               // null | 'results' | 'add' | 'attach' | 'join'
  sheetArg: null,            // {side, host} for 'attach', {side, char} for 'join'
  charge: { gap: 9, mod: 0, reroll: false }, // charge odds tool
  intelSide: null,           // army shown on the Intel tab (default: the defender)
  grid: null,                // matchup grid: {sig, side, phase, metric, cells, rows, cols, running, done, total}
  gridMetric: 'damage',      // 'damage' (% of wounds) | 'kills' | 'wipe'
  saved: [],                 // saved scenarios (own localStorage key)
  library: [],               // saved army lists (tournament: one per round), own localStorage key
  threats: null,             // threat view: {side, key, rows, cells, done}
  savedNote: null,
  intelQuery: '',
  result: null, busy: false, calcError: null,
  chartMode: null,           // 'models' | 'damage' | null (auto)
  selBar: null,
};

let uidSeq = 1;

function persist() {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify({
      view: state.view, texts: state.texts, side: state.side, phase: state.phase, setups: state.setups,
      attach: state.attach, charge: state.charge, intelSide: state.intelSide,
    }));
  } catch { /* storage full / private mode: best effort */ }
}

const LIB_KEY = 'w40k_calc_lists_v1';
function persistLibrary() {
  try { localStorage.setItem(LIB_KEY, JSON.stringify(state.library)); } catch { /* best effort */ }
}
function restoreLibrary() {
  try { state.library = JSON.parse(localStorage.getItem(LIB_KEY) ?? '[]') ?? []; } catch { state.library = []; }
}

const SAVED_KEY = 'w40k_calc_saved_v1';
function persistSaved() {
  try { localStorage.setItem(SAVED_KEY, JSON.stringify(state.saved)); } catch { /* best effort */ }
}
function restoreSaved() {
  try { state.saved = JSON.parse(localStorage.getItem(SAVED_KEY) ?? '[]') ?? []; } catch { state.saved = []; }
}
// Which lists a scenario was made with (unit keys are only valid for them).
function listsSignature() {
  const str = JSON.stringify([state.texts.A, state.texts.B, state.attach]);
  let h = 5381;
  for (let i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

function restore() {
  try {
    const s = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (!s) return;
    Object.assign(state, {
      view: s.view ?? 'armies', texts: s.texts ?? { A: '', B: '' }, side: s.side ?? 'A',
      phase: s.phase ?? 'shooting', setups: s.setups ?? {}, attach: s.attach ?? { A: null, B: null },
      charge: s.charge ?? { gap: 9, mod: 0, reroll: false }, intelSide: s.intelSide ?? null,
    });
    for (const st of Object.values(state.setups)) for (const a of st.attackers ?? []) uidSeq = Math.max(uidSeq, (a.uid ?? 0) + 1);
  } catch { /* corrupt: start fresh */ }
}

const other = (s) => (s === 'A' ? 'B' : 'A');
const atkArmy = () => state.armies[state.side];
const defArmy = () => state.armies[other(state.side)];

function setup() {
  const key = `${state.side}:${state.phase}`;
  if (!state.setups[key]) state.setups[key] = { targetKey: null, attackers: [], ruleOverrides: {}, defManual: {} };
  const s = state.setups[key];
  s.ruleOverrides ??= {};
  s.defManual ??= {};
  s.defOverrides ??= {};   // targetKey -> { groupKey: {count, woundsLeftFirst} } (casualties / damage)
  return s;
}

function parseArmy(side) {
  const text = state.texts[side];
  state.armies[side] = null;
  state.errors[side] = null;
  if (!text.trim()) return;
  try {
    state.armies[side] = importArmy(text);
    if (state.attach[side]) setAttachments(state.armies[side], state.attach[side]);
    console.log(`[calc] army ${side}: ${state.armies[side].faction}, ${state.armies[side].units.length} units`);
  } catch (e) {
    state.errors[side] = e.message ?? String(e);
    console.warn(`[calc] army ${side} parse failed`, e);
  }
}

// Attach / detach a character (roster index) to a bodyguard (roster index, null = detach)
// in army `side`.
function applyAttach(side, charIdx, hostIdx) {
  const army = state.armies[side];
  if (!army) return;
  console.log(`[calc] army ${side}: ${rosterUnitLabel(army, charIdx)} ${hostIdx == null ? 'detached' : `attached to ${rosterUnitLabel(army, hostIdx)}`}`);
  applyAttachments(side, withAttachment(army, charIdx, hostIdx));
}

// Install a whole attachments map, keeping every setup that pointed at the
// affected units valid: a character that joins a unit stops being its own
// combat unit, so whatever targeted / attacked with it now uses the joined unit.
function applyAttachments(side, att, { edited = true } = {}) {
  const army = state.armies[side];
  if (!army) return;
  const before = { ...(army.attachments ?? {}) };
  setAttachments(army, att);
  state.attach[side] = edited ? army.attachments : null;
  const remap = new Map();
  for (const [c, b] of Object.entries(army.attachments)) if (before[c] !== b && b != null) remap.set(`u${c}`, `u${b}`);
  const valid = new Set(army.units.map(u => u.key));
  for (const [key, st] of Object.entries(state.setups)) {
    const [atkSide] = key.split(':');
    if (atkSide === side) {
      const seen = new Set();
      st.attackers = (st.attackers ?? []).map(a => ({ ...a, unitKey: remap.get(a.unitKey) ?? a.unitKey }))
        .filter(a => valid.has(a.unitKey) && !seen.has(a.unitKey) && seen.add(a.unitKey));
    } else if (st.targetKey) {
      st.targetKey = remap.get(st.targetKey) ?? st.targetKey;
      if (!valid.has(st.targetKey)) st.targetKey = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Derived data

function targetUnit() {
  const d = defArmy();
  const s = setup();
  if (!d) return null;
  return d.units.find(u => u.key === s.targetKey) ?? null;
}

function targetInfo() {
  const cu = targetUnit();
  if (!cu) return null;
  const profile = defenderProfile(cu, defArmy());
  return { cu, profile, summary: defenderSummary(profile) };
}

function enabledRules(profile, s) {
  const on = new Set();
  for (const r of profile.rules) {
    const o = s.ruleOverrides[r.id];
    if (o === true || (o == null && r.auto)) on.add(r.id);
  }
  return on;
}

function rowsFor(entry, tinfo, army = atkArmy(), phase = state.phase) {
  const cu = army?.units.find(u => u.key === entry.unitKey);
  if (!cu) return { cu: null, rows: [] };
  const body = bodyguardModels(cu);
  const inRange = entry.inRange != null ? Math.max(0, Math.min(body.total, entry.inRange)) : null;
  const rows = attackerRows(cu, phase, tinfo?.summary ?? null).map(r => {
    let count = r.blocked ? 0 : Math.min(r.max, entry.counts?.[r.id] ?? r.count);
    // models in range: scale the bodyguard models' weapons; attached characters stay in
    if (inRange != null && body.members.has(Number(String(r.id).split(':')[0]))) count = Math.round(count * inRange / Math.max(1, body.total));
    return { ...r, count };
  });
  return { cu, rows, inRange, bodyTotal: body.total };
}

// Casualties set on the target leave it below half strength?
function targetBelowHalfAuto(tinfo) {
  if (!tinfo?.profile) return false;
  const s = setup();
  const ovr = s.targetKey === tinfo.cu?.key ? (s.defOverrides?.[s.targetKey] ?? {}) : {};
  const start = tinfo.profile.groups.reduce((a, g) => a + g.count, 0);
  const left = tinfo.profile.groups.reduce((a, g) => a + (ovr[g.key]?.count ?? g.count), 0);
  return left * 2 < start;
}

// The non-character part of a combat unit (what "models in range" counts).
function bodyguardModels(cu) {
  const ms = cu.members.filter(m => m.role !== 'leader');
  return { members: new Set(ms.map(m => m.index)), total: ms.reduce((a, m) => a + (m.ru.model_count ?? 1), 0) };
}

// Attacker rules (abilities, detachment rule, stratagems) for an attacker entry,
// with which ones are on given its situation chips and the current target.
function rulesFor(e, cu, tinfo, army = atkArmy(), phase = state.phase) {
  const { rules, stratText } = attackerRules(cu, army);
  const m = e.mods ?? {};
  const ctx = {
    charged: !!m.charged, stationary: !!m.stationary, halfRange: !!m.halfRange,
    targetKeywords: tinfo?.profile.keywords ?? [], attackerKeywords: cu.keywords,
    // situation chips (shown only when one of this unit's rules depends on them)
    onObjective: !!m.onObjective, doctrine: m.doctrine ?? '', targetShocked: !!m.targetShocked,
    targetBelowHalf: !!m.targetBelowHalf || targetBelowHalfAuto(tinfo), selfBelowHalf: !!m.selfBelowHalf,
    ingress: !!m.ingress, distance: m.distance ?? null,
  };
  const inPhase = rules.filter(r => r.phases.includes(phase));
  const on = new Set(inPhase.filter(r => attackerRuleOn(r, e.ruleOverrides?.[r.id], ctx)).map(r => r.id));
  return { rules: inPhase, on, stratText };
}

function scenario() {
  const tinfo = targetInfo();
  const s = setup();
  if (!tinfo || !s.attackers.length) return null;
  const attackers = [];
  for (const e of s.attackers) {
    const { cu, rows } = rowsFor(e, tinfo);
    if (!cu) continue;
    const { rules, on } = rulesFor(e, cu, tinfo);
    attackers.push(buildAttacker(cu, rows, e.mods, rules, on, state.phase));
  }
  if (!attackers.some(a => a.weapons.length)) return null;
  const defender = buildDefender(tinfo.profile, enabledRules(tinfo.profile, s), state.phase, s.defManual, s.defOverrides[s.targetKey] ?? {});
  return { phase: state.phase, attackers, defender, seed: 1234567 };
}

// ---------------------------------------------------------------------------
// Worker

let worker = null, workerBusy = false, reqId = 0, calcTimer = null;

function newWorker() {
  const w = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
  w.onmessage = (ev) => {
    const { id, final, result, error } = ev.data;
    if (id !== reqId) return;
    if (final) workerBusy = false;
    if (error) { state.calcError = error; state.busy = false; console.error('[calc] engine error', error); }
    else { state.result = result; state.calcError = null; state.busy = !final; }
    renderResultViews();
  };
  return w;
}

function scheduleCalc() {
  clearTimeout(calcTimer);
  state.busy = true; // the bar dims at once; tests and players never read a stale number as fresh
  calcTimer = setTimeout(runCalc, 120);
}

function runCalc() {
  const sc = scenario();
  reqId++;
  if (!sc) { state.result = null; state.busy = false; renderResultViews(); return; }
  if (workerBusy && worker) { worker.terminate(); worker = null; }
  worker ??= newWorker();
  workerBusy = true;
  state.busy = true;
  renderResultViews();
  worker.postMessage({ id: reqId, scenario: sc, trials: TRIALS });
}

// ---------------------------------------------------------------------------
// Rendering helpers

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pct = (p) => (p >= 0.995 ? '>99%' : p > 0 && p < 0.005 ? '<1%' : `${Math.round(p * 100)}%`);
const fx = (n, d = 1) => (Math.round(n * 10 ** d) / 10 ** d).toFixed(d);

function seg(action, value, options, extra = '') {
  return `<div class="seg ${extra}">${options.map(([v, label]) =>
    `<button data-action="${action}" data-value="${esc(v)}" class="${String(v) === String(value) ? 'on' : ''}">${esc(label)}</button>`).join('')}</div>`;
}
function chip(action, on, label, attrs = '') {
  return `<button class="chip ${on ? 'on' : ''}" data-action="${action}" ${attrs} aria-pressed="${on ? 'true' : 'false'}">${esc(label)}</button>`;
}
function modSeg(label, scope, key, value, options) {
  return `<div class="modrow"><div class="lab">${esc(label)}</div>${seg('mod', value, options, 'compact').replaceAll('data-action="mod"', `data-action="mod" data-scope="${scope}" data-key="${key}"`)}</div>`;
}

// ---------------------------------------------------------------------------
// Views

function render() {
  const a = state.armies.A, b = state.armies.B;
  const ready = a && b;
  app.innerHTML = `
    <header class="top"><div class="wrap">
      <div class="brand">⚔<span class="brand-full"> Combat Calc</span></div>
      <span class="badge" title="40kdc dataset version">11e · data ${esc(DATASET_VERSION)}</span>
      <nav class="tabs">
        <button class="tab ${state.view === 'armies' ? 'on' : ''}" data-action="view" data-value="armies">Armies</button>
        <button class="tab ${state.view === 'intel' ? 'on' : ''}" data-action="view" data-value="intel" ${a || b ? '' : 'disabled'}>Intel</button>
        <button class="tab ${state.view === 'attack' ? 'on' : ''}" data-action="view" data-value="attack" ${ready ? '' : 'disabled'}>Attack</button>
        <button class="tab ${state.view === 'board' ? 'on' : ''}" data-action="view" data-value="board" ${ready ? '' : 'disabled'}>Board</button>
      </nav>
    </div></header>
    <main class="wrap">${state.view === 'attack' && ready ? attackView() : state.view === 'board' && ready ? boardView() : state.view === 'intel' && (a || b) ? intelView() : armiesView()}</main>
    <div id="resultbar"></div>
    <div id="sheet"></div>`;
  renderResultViews();
  renderSheet();
  if (state.view === 'board') boardAfterRender();
}

// ---- Intel: enemy cheat sheet

function intelSide() {
  let side = state.intelSide ?? other(state.side);
  if (!state.armies[side]) side = other(side);
  return side;
}

function intelView() {
  const side = intelSide();
  const army = state.armies[side];
  const ai = armyIntel(army);
  const byPhase = new Map();
  for (const st of ai.stratagems) {
    const key = /shooting|fight/i.test(st.phase) ? st.phase : 'Other phases';
    if (!byPhase.has(key)) byPhase.set(key, []);
    byPhase.get(key).push(st);
  }
  const stratHtml = [...byPhase.entries()].map(([ph, list]) => `<div class="lab" style="margin-top:8px">${esc(ph)}</div>${list.map(st =>
    `<div class="ability"><b>${esc(st.name)}</b> <span class="muted tiny">${st.cp}CP · ${esc(st.turn)}${st.role === 'defend' ? ' · defensive' : st.role === 'attack' ? ' · offensive' : ''}</span>
      <div class="muted">${st.missing ? 'No 11e text in the dataset.' : `<b>When:</b> ${esc(st.when)}<br><b>Effect:</b> ${esc(st.effect)}`}</div></div>`).join('')}`).join('');
  return `<section class="section">
      ${state.armies.A && state.armies.B ? seg('intel-side', side, [['A', `A · ${state.armies.A.faction}`], ['B', `B · ${state.armies.B.faction}`]]) : ''}
    </section>
    <section class="section"><div class="card">
      <div class="title">${esc(ai.faction)}</div>
      <div class="muted small">${esc(ai.detachments.join(', ') || 'No detachment found')} · ${army.units.length} units</div>
      ${ai.detachmentRules.length ? `<details class="more"><summary>Detachment rule${ai.detachmentRules.length > 1 ? 's' : ''}</summary>${ai.detachmentRules.map(d =>
        `<div class="ability"><b>${esc(d.name)}</b><div class="muted">${esc(d.text)}</div></div>`).join('')}</details>` : ''}
      <details class="more"><summary>Stratagems (${ai.stratagems.length})</summary>${stratHtml || '<div class="muted small">None found for these detachments.</div>'}</details>
    </div></section>
    <section class="section"><h2>Units</h2>
      <input class="sel" type="search" data-input="intel-search" placeholder="Search units, keywords, abilities…" value="${esc(state.intelQuery)}" aria-label="Search units">
      <div id="intel-list">${intelList(side)}</div>
    </section>`;
}

function intelList(side) {
  const army = state.armies[side];
  const q = state.intelQuery.trim().toLowerCase();
  const cards = [];
  for (const cu of army.units) {
    const it = unitIntel(cu, army);
    const hay = [it.name, ...it.keywords, ...it.abilities.map(a => `${a.name} ${a.text}`), ...it.weapons.map(w => w.label)].join(' ').toLowerCase();
    if (q && !hay.includes(q)) continue;
    const line = (p) => `<tr><td>${esc(p.member === p.name ? p.name : `${p.name}`)}</td><td>${p.M}"</td><td>${p.T}</td><td>${p.Sv}+${p.InSv ? `/${p.InSv}++` : ''}</td><td>${p.W}</td><td>${p.Ld}+</td><td>${p.OC}</td></tr>`;
    const tags = (list, cls = '') => list.map(t => `<span class="tag ${cls}">${esc(t)}</span>`).join('');
    cards.push(`<details class="card intel-unit" style="margin-top:10px"><summary class="row" style="list-style:none;cursor:pointer;min-height:40px">
        <div class="grow"><div class="title">${esc(it.name)}</div><div class="muted tiny">${it.models} models${it.points ? ` · ${it.points} pts` : ''}${it.fnp ? ` · FNP ${it.fnp}+` : ''}</div></div><span class="muted">▾</span></summary>
      <table class="dist" style="margin-top:6px"><thead><tr><th>Model</th><th>M</th><th>T</th><th>Sv</th><th>W</th><th>Ld</th><th>OC</th></tr></thead><tbody>${it.stats.map(line).join('')}</tbody></table>
      ${it.defensive.length ? `<div class="modrow" style="margin-top:8px"><div class="lab">Defences</div>${tags(it.defensive.map(d => `${d.label} · ${d.source}${d.auto ? '' : ' (situational)'}`))}</div>` : ''}
      ${it.offensive.length ? `<div class="modrow" style="margin-top:8px"><div class="lab">Attack buffs</div>${tags(it.offensive.map(o => `${o.label} · ${o.source}${o.when ? ` (${o.when})` : ''}`))}</div>` : ''}
      <div class="modrow" style="margin-top:8px"><div class="lab">Weapons</div>${it.weapons.map(w =>
        `<div class="ability"><b>${w.count}× ${esc(w.label)}</b> <span class="wstats">${esc(w.range)} · ${esc(w.stats)}</span><div>${tags(w.tags)}</div></div>`).join('') || '<div class="muted small">None</div>'}</div>
      <details class="more"><summary>Abilities (${it.abilities.length})</summary>${it.abilities.map(a =>
        `<div class="ability"><b>${esc(a.name)}</b> <span class="muted tiny">${esc(a.member)}</span><div class="muted">${esc(a.text)}</div></div>`).join('')}</details>
      <div class="tiny muted" style="margin:6px 0">${esc(it.keywords.join(', '))}</div>
      ${state.armies.A && state.armies.B ? `<div class="row" style="gap:6px">
        <button class="btn grow" data-action="target-this" data-side="${side}" data-key="${esc(cu.key)}">Attack this unit →</button>
        <button class="btn grow" data-action="open-threats" data-side="${side}" data-key="${esc(cu.key)}">⚠ Biggest threats</button></div>` : ''}
    </details>`);
  }
  return cards.join('') || '<p class="hint">No units match.</p>';
}

function attachOverview(side, army) {
  const chars = army.roster.units.map((ru, i) => i).filter(i => joinCandidates({ ...army, attachments: {} }, i).length);
  if (!chars.length) return '';
  const edited = state.attach[side] != null;
  return `<details class="more" ${edited ? 'open' : ''}><summary>Attached characters · ${Object.keys(army.attachments ?? {}).length} of ${chars.length} attached${edited ? ' (edited)' : ''}</summary>
    ${chars.map(ci => {
      const cur = army.attachments?.[ci];
      const opts = joinCandidates({ ...army, attachments: { ...army.attachments, [ci]: undefined } }, ci);
      return `<div class="modrow" style="margin:8px 0"><div class="lab">${esc(rosterUnitLabel(army, ci))}</div>
        <select class="sel" data-input="attach" data-side="${side}" data-char="${ci}">
          <option value="">Not attached</option>
          ${opts.map(o => `<option value="${o.index}" ${o.index === cur ? 'selected' : ''}>${esc(o.name)}${o.eligible ? '' : ' (not on Leader list)'}</option>`).join('')}
        </select></div>`;
    }).join('')}
    ${edited ? `<button class="btn ghost" data-action="reset-attach" data-side="${side}">Reset to the list's attachments</button>` : ''}
  </details>`;
}

function armiesView() {
  const panel = (side) => {
    const army = state.armies[side];
    const err = state.errors[side];
    return `<section class="section"><h2>Army ${side}</h2><div class="card">
      ${army ? `<div class="row"><div class="grow"><div class="title ellipsis">${esc(army.faction)}</div>
        <div class="muted small">${army.units.length} units · ${esc(army.name)}</div></div></div>` : ''}
      <textarea class="list" data-input="text" data-side="${side}" placeholder="Paste a list exported from the GW app, New Recruit, ListForge…" spellcheck="false">${esc(state.texts[side])}</textarea>
      <div class="row" style="margin-top:8px">
        <button class="btn primary grow" data-action="parse" data-side="${side}">Load army ${side}</button>
        <button class="btn" data-action="open-library" data-side="${side}" aria-label="List library for army ${side}">📚${state.library.length ? ` ${state.library.length}` : ''}</button>
        <button class="btn ghost" data-action="clear" data-side="${side}">Clear</button>
      </div>
      ${err ? `<div class="warnbox err">${esc(err)}</div>` : ''}
      ${army ? attachOverview(side, army) : ''}
      ${army ? `<details class="more"><summary>${army.units.length} units${army.warnings.length ? ` · ${army.warnings.length} import notes` : ''}</summary>
        ${army.units.map(u => `<div class="ability"><b>${esc(u.name)}</b> <span class="muted">· ${u.models} models</span></div>`).join('')}
        ${army.warnings.map(w => `<div class="tiny muted">• ${esc(w)}</div>`).join('')}
      </details>` : ''}
    </div></section>`;
  };
  const ready = state.armies.A && state.armies.B;
  return `${panel('A')}${panel('B')}
    <button class="btn primary block" data-action="view" data-value="attack" ${ready ? '' : 'disabled'}>${ready ? 'Start calculating →' : 'Load both armies to start'}</button>
    <p class="hint">Lists stay on this device. Works offline once loaded. 11th edition rules · dataset ${esc(DATASET_VERSION)}.</p>`;
}

function attackView() {
  const s = setup();
  const atk = atkArmy(), def = defArmy();
  const tinfo = targetInfo();
  return `
    <section class="section">
      ${seg('phase', state.phase, [['shooting', 'Shooting'], ['fight', 'Fight']])}
      <div class="card matchup" style="margin-top:10px">
        <div class="side"><div class="lbl">Attacker · ${state.side}</div><div class="nm">${esc(atk.faction)}</div></div>
        <button class="icon-btn" data-action="swap" aria-label="Swap attacker and defender">⇄</button>
        <div class="side right"><div class="lbl">Defender · ${other(state.side)}</div><div class="nm">${esc(def.faction)}</div></div>
      </div>
      <div class="row" style="margin-top:8px;gap:6px">
        <button class="btn ghost grow" data-action="open-charge">🎲 Charge</button>
        <button class="btn ghost grow" data-action="open-grid">📊 Grid</button>
        <button class="btn ghost grow" data-action="open-saved">💾 Saved${state.saved.length ? ` (${state.saved.length})` : ''}</button>
      </div>
    </section>
    <section class="section"><h2>Target</h2>${targetCard(tinfo, s)}</section>
    <section class="section"><h2>Attacking units${s.attackers.length > 1 ? ' · resolved in order' : ''}</h2>
      ${s.attackers.map((e, i) => attackerCard(e, i, tinfo)).join('')}
      <button class="btn block" style="margin-top:10px" data-action="open-add">＋ Add attacking unit</button>
    </section>`;
}

// Who is attached to this combat unit, with detach / attach / join controls.
function attachRow(side, cu) {
  if (!cu) return '';
  const chars = cu.members.filter(m => m.role === 'leader');
  const parts = chars.map(m => `<button class="chip on" data-action="detach" data-side="${side}" data-char="${m.index}" aria-label="Detach ${esc(m.dcUnit.name)}">${esc(m.dcUnit.name)} · ${m.attachRole === 'support' ? 'Support' : 'Leader'} ✕</button>`);
  if (cu.canHost) parts.push(`<button class="chip" data-action="open-attach" data-side="${side}" data-host="${cu.index}">＋ Attach character</button>`);
  if (cu.canJoin) parts.push(`<button class="chip" data-action="open-join" data-side="${side}" data-char="${cu.index}">＋ Join a unit</button>`);
  if (!parts.length) return '';
  return `<div class="modrow" style="margin-top:10px"><div class="lab">${chars.length ? 'Attached characters (tap ✕ to detach)' : 'Attached characters'}</div><div class="chips">${parts.join('')}</div></div>`;
}

function targetCard(tinfo, s) {
  const def = defArmy();
  const options = def.units.map(u => `<option value="${esc(u.key)}" ${u.key === s.targetKey ? 'selected' : ''}>${esc(u.name)} (${u.models})</option>`).join('');
  let body = '';
  if (tinfo) {
    const { profile } = tinfo;
    // stat line reflects the rules/modifiers switched on (e.g. a Storm Shield 4++)
    const ovr = s.defOverrides[s.targetKey] ?? {};
    const built = buildDefender(profile, enabledRules(profile, s), state.phase, s.defManual, ovr);
    const summary = defenderSummary({ ...profile, groups: built.groups.map(g => ({ ...g, InSv: g.InSv || (built.mods.invuln ?? 0) })) });
    const st = (v, l) => `<div class="stat"><b>${esc(v)}</b><span>${l}</span></div>`;
    const inv = summary.InSv ? `${summary.InSv}+` : '–';
    // FNP on the stat line = what the bodyguard models have; a character's own FNP is listed with it
    const bodyG = built.groups.filter(g => !g.character);
    const fnp = Math.min(...(bodyG.length ? bodyG : built.groups).map(g => g.fnp || 7), built.mods.fnp || 7);
    body += `<div class="stats">${st(summary.T, 'T')}${st(`${summary.Sv}+`, 'Sv')}${st(inv, 'InSv')}${st(summary.W, 'W')}${st(summary.models, 'Models')}${fnp < 7 ? st(`${fnp}+`, 'FNP') : ''}</div>`;
    const groups = built.groups.filter(g => g.character);
    if (groups.length) body += `<div class="tiny muted" style="margin-top:6px">Characters: ${groups.map(g => `${esc(g.name)} (T${g.T} W${g.W} ${g.Sv}+${g.InSv ? `/${g.InSv}++` : ''}${g.fnp ? `, FNP ${g.fnp}+` : ''})`).join(', ')} — allocated last unless Precision.</div>`;
    const nDamaged = Object.values(ovr).filter(o => o && (o.count != null || o.woundsLeftFirst != null)).length;
    body += `<details class="more" data-details="casualties" ${state.openCasualties ? 'open' : ''}><summary>Casualties & damage${nDamaged ? ' · set' : ''}</summary>
      ${profile.groups.map(g => {
        const o = ovr[g.key] ?? {};
        const left = o.count ?? g.count;
        const wl = o.woundsLeftFirst ?? g.W;
        return `<div class="weapon"><div class="grow"><div class="wname">${esc(g.name)}${g.character ? ' <span class="muted tiny">(character)</span>' : ''}</div>
          <div class="wstats">W${g.W} · models left</div></div>
          <div class="stepper"><button data-action="dmg" data-group="${esc(g.key)}" data-field="count" data-delta="-1" aria-label="One fewer ${esc(g.name)}">−</button>
          <div class="val">${left}/${g.count}</div>
          <button data-action="dmg" data-group="${esc(g.key)}" data-field="count" data-delta="1" aria-label="One more ${esc(g.name)}">+</button></div></div>
          ${g.W > 1 && left > 0 ? `<div class="weapon" style="border-top:0;padding-top:0"><div class="grow"><div class="wstats">Wounds left on one damaged ${esc(g.name)}</div></div>
          <div class="stepper"><button data-action="dmg" data-group="${esc(g.key)}" data-field="woundsLeftFirst" data-delta="-1" aria-label="Damage ${esc(g.name)}">−</button>
          <div class="val">${wl}/${g.W}</div>
          <button data-action="dmg" data-group="${esc(g.key)}" data-field="woundsLeftFirst" data-delta="1" aria-label="Heal ${esc(g.name)}">+</button></div></div>` : ''}`;
      }).join('')}
      ${nDamaged ? `<button class="btn ghost" data-action="dmg-reset">Reset to full strength</button>` : ''}
    </details>`;
    body += attachRow(other(state.side), tinfo.cu);
    const rules = profile.rules;
    const on = enabledRules(profile, s);
    if (rules.length) {
      body += `<div class="modrow" style="margin-top:10px"><div class="lab">Defensive rules & stratagems (tap to toggle)</div><div class="chips">
        ${rules.map(r => {
          const applies = r.phases.includes(state.phase);
          const whose = tinfo.cu.members.length > 1 && r.groupKeys ? `${r.member} only` : null;
          const src = r.source === r.label ? null : r.source;
          return chip('rule', on.has(r.id), [r.label, src, whose].filter(Boolean).join(' · '), `data-id="${esc(r.id)}" title="${esc(r.text)}"`).replace('class="chip', `class="chip${applies ? '' : ' dim'}`);
        }).join('')}</div>
        <div class="rule-note">Always-active rules start on; activated / conditional ones and stratagems start off. Greyed = not this phase.</div></div>`;
    }
    const m = s.defManual;
    body += `<details class="more"><summary>Defender modifiers${Object.values(m).some(v => v) ? ' · set' : ''}</summary><div class="modgrid">
      ${state.phase === 'shooting' ? `<div class="modrow"><div class="lab">Benefit of cover (BS worsened by 1)</div><div class="chips">${chip('defmod-toggle', !!m.cover, 'In cover', 'data-key="cover"')}</div></div>` : ''}
      ${modSeg('Hit rolls against it', 'def', 'hitMod', m.hitMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1']])}
      ${modSeg('Wound rolls against it', 'def', 'woundMod', m.woundMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1']])}
      ${modSeg('Save roll modifier', 'def', 'saveMod', m.saveMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1']])}
      ${modSeg('Incoming AP worsened by', 'def', 'apReduce', m.apReduce ?? 0, [[0, '0'], [1, '1'], [2, '2']])}
      ${modSeg('Damage reduction', 'def', 'damageReduction', m.damageReduction ?? 0, [[0, 'None'], [1, '−1 D'], ['half', 'Halve']])}
      ${modSeg('Invulnerable save', 'def', 'invuln', m.invuln ?? 0, [[0, 'None'], [6, '6+'], [5, '5+'], [4, '4+'], [3, '3+']])}
      ${modSeg('Feel No Pain', 'def', 'fnp', m.fnp ?? 0, [[0, 'None'], [6, '6+'], [5, '5+'], [4, '4+'], [3, '3+']])}
      ${modSeg('Feel No Pain vs mortal wounds', 'def', 'fnpMortal', m.fnpMortal ?? 0, [[0, 'None'], [6, '6+'], [5, '5+'], [4, '4+']])}
    </div></details>
    ${(() => {
      const txt = (profile.stratText ?? []).filter(st => /any/i.test(st.phase) || st.phase.toLowerCase().includes(state.phase));
      return txt.length ? `<details class="more"><summary>Other defensive stratagems — set by hand (${txt.length})</summary>${txt.map(st =>
        `<div class="ability"><b>${esc(st.name)}</b> <span class="muted tiny">${st.cp}CP · ${esc(st.detachment)}</span><div class="muted">${st.missing ? 'No 11e text in the dataset.' : esc(`${st.when} — ${st.effect}`)}</div></div>`).join('')}</details>` : '';
    })()}
    <details class="more"><summary>Target abilities</summary>${abilitiesOf(tinfo.cu).map(a =>
      `<div class="ability"><b>${esc(a.name)}</b> <span class="muted tiny">${esc(a.member)}</span><div class="muted">${esc(a.text)}</div></div>`).join('') || '<div class="muted small">None listed.</div>'}</details>`;
  }
  return `<div class="card">
    <select class="sel" data-input="target" aria-label="Target unit"><option value="">Choose a target unit…</option>${options}</select>
    ${body}</div>`;
}

function attackerCard(e, i, tinfo) {
  const { cu, rows } = rowsFor(e, tinfo);
  if (!cu) return '';
  const m = e.mods ?? {};
  const shooting = state.phase === 'shooting';
  const hasIndirect = rows.some(r => r.kw.indirect);
  const weapons = rows.length ? rows.map(r => {
    const unsupported = r.unsupported.length ? r.unsupported.map(t => `<span class="tag warn" title="Not modelled by the calculator">${esc(t)} ⚠</span>`).join('') : '';
    const tags = r.tags.filter(t => !r.unsupported.includes(t)).map(t => `<span class="tag">${esc(t)}</span>`).join('');
    return `<div class="weapon ${r.count ? '' : 'off'}">
      <div class="grow"><div class="wname">${esc(r.label)}</div>
        <div class="wstats">${esc(r.range)} · ${esc(r.stats)}</div>
        <div>${tags}${unsupported}${r.blocked ? `<span class="tag warn">${esc(r.blocked)}</span>` : ''}</div></div>
      <div class="stepper">
        <button data-action="count" data-uid="${e.uid}" data-row="${esc(r.id)}" data-delta="-1" aria-label="Fewer">−</button>
        <div class="val">${r.count}/${r.max}</div>
        <button data-action="count" data-uid="${e.uid}" data-row="${esc(r.id)}" data-delta="1" aria-label="More">+</button>
      </div></div>`;
  }).join('') : `<div class="muted small">No ${shooting ? 'ranged' : 'melee'} weapons.</div>`;
  const { inRange, bodyTotal } = rowsFor(e, tinfo);
  const rangeRow = bodyTotal > 1 ? `<div class="weapon" style="border-top:1px solid var(--line);margin-top:4px">
      <div class="grow"><div class="wname">Models in range</div><div class="wstats">${state.phase === 'fight' ? 'Bodyguard models that can fight' : 'Bodyguard models with line of sight / range'}; attached characters stay in</div></div>
      <div class="stepper"><button data-action="inrange" ${`data-uid="${e.uid}"`} data-delta="-1" aria-label="Fewer models in range">−</button>
      <div class="val">${inRange ?? bodyTotal}/${bodyTotal}</div>
      <button data-action="inrange" ${`data-uid="${e.uid}"`} data-delta="1" aria-label="More models in range">+</button></div></div>` : '';
  // situation chips: only the ones this unit's rules actually depend on
  const needs = { onObjective: false, targetShocked: false, targetBelowHalf: false, selfBelowHalf: false, ingress: false, within: false, doctrines: new Set() };
  for (const r of rulesFor(e, cu, tinfo).rules) {
    const c = r.conds ?? {};
    if (c.onObjective) needs.onObjective = true;
    if (c.targetShocked) needs.targetShocked = true;
    if (c.targetBelowHalf || c.targetNotBelowHalf) needs.targetBelowHalf = true;
    if (c.selfBelowHalf) needs.selfBelowHalf = true;
    if (c.ingress) needs.ingress = true;
    if (c.within) needs.within = true;
    if (c.doctrine) needs.doctrines.add(c.doctrine);
  }
  const autoHalf = targetBelowHalfAuto(tinfo);
  const situation = [
    needs.onObjective && chip('amod-toggle', !!m.onObjective, 'On an objective', `data-uid="${e.uid}" data-key="onObjective"`),
    ...[...needs.doctrines].map(d => chip('doctrine', m.doctrine === d, `${d[0].toUpperCase()}${d.slice(1)} doctrine active`, `data-uid="${e.uid}" data-value="${esc(d)}"`)),
    needs.targetBelowHalf && chip('amod-toggle', !!m.targetBelowHalf || autoHalf, `Target below half strength${autoHalf ? ' (casualties)' : ''}`, `data-uid="${e.uid}" data-key="targetBelowHalf"`),
    needs.targetShocked && chip('amod-toggle', !!m.targetShocked, 'Target battle-shocked', `data-uid="${e.uid}" data-key="targetShocked"`),
    needs.selfBelowHalf && chip('amod-toggle', !!m.selfBelowHalf, 'This unit below half strength', `data-uid="${e.uid}" data-key="selfBelowHalf"`),
    needs.ingress && chip('amod-toggle', !!m.ingress, 'Arrived from reserves this turn', `data-uid="${e.uid}" data-key="ingress"`),
  ].filter(Boolean).join('');
  const distRow = needs.within ? `<div class="weapon" style="border-top:0;padding-top:4px"><div class="grow"><div class="wname">Distance to target</div><div class="wstats">for "within X\"" abilities</div></div>
      <div class="stepper"><button data-action="distance" data-uid="${e.uid}" data-delta="-1" aria-label="Closer">−</button><div class="val">${m.distance != null ? `${m.distance}"` : '–'}</div><button data-action="distance" data-uid="${e.uid}" data-delta="1" aria-label="Further">+</button></div></div>` : '';
  const sit = [
    shooting && chip('amod-toggle', !!m.halfRange, 'Half range', `data-uid="${e.uid}" data-key="halfRange"`),
    chip('amod-toggle', !!m.charged, 'Charged', `data-uid="${e.uid}" data-key="charged"`),
    shooting && chip('amod-toggle', !!m.stationary, 'Stationary', `data-uid="${e.uid}" data-key="stationary"`),
    shooting && chip('amod-toggle', !!m.overwatch, 'Snap shooting', `data-uid="${e.uid}" data-key="overwatch"`),
    shooting && hasIndirect && chip('amod-toggle', !!m.indirect, 'Indirect (not visible)', `data-uid="${e.uid}" data-key="indirect"`),
  ].filter(Boolean).join('');
  const nMods = ['hitMod', 'woundMod', 'apMod', 'damageMod', 'attacksMod', 'bsMod'].filter(k => m[k]).length +
    ['lethal', 'dev', 'twin', 'ignoresCover', 'precision', 'rerollOneHit', 'rerollOneWound', 'rerollOneDamage', 'rerollDamage', 'ignoreHitMods', 'ignoreWoundMods'].filter(k => m[k]).length + (m.sustained ? 1 : 0) +
    (m.rerollHits && m.rerollHits !== 'none' ? 1 : 0) + (m.rerollWounds && m.rerollWounds !== 'none' ? 1 : 0) +
    ((m.critHit ?? 6) !== 6 ? 1 : 0) + ((m.critWound ?? 6) !== 6 ? 1 : 0);
  const sc = `data-uid="${e.uid}"`;
  const ms = (label, key, val, opts) => modSeg(label, 'atk', key, val, opts).replaceAll('data-scope="atk"', `data-scope="atk" ${sc}`);
  const abil = abilitiesOf(cu);
  const { rules, on, stratText } = rulesFor(e, cu, tinfo);
  const ruleChip = (r) => {
    const cond = describeConditions(r.conds);
    const label = [r.label, r.source, r.scope === 'model' && cu.members.length > 1 ? `${r.memberName} only` : null].filter(Boolean).join(' · ');
    return chip('arule', on.has(r.id), label, `${sc} data-id="${esc(r.id)}" title="${esc(r.text)}"`)
      .replace('</button>', `${cond && !on.has(r.id) ? ` <span class="tiny muted">(${esc(cond)})</span>` : ''}</button>`);
  };
  const abilRules = rules.filter(r => r.kind !== 'stratagem');
  const stratRules = rules.filter(r => r.kind === 'stratagem');
  const stratTextInPhase = stratText.filter(st => st.phase && (/any/i.test(st.phase) || st.phase.toLowerCase().includes(state.phase)));
  const rulesBlock = (abilRules.length || stratRules.length || stratTextInPhase.length) ? `
    ${abilRules.length ? `<div class="modrow" style="margin-top:10px"><div class="lab">Abilities & detachment rule (auto when their condition is met — tap to override)</div><div class="chips">${abilRules.map(ruleChip).join('')}</div></div>` : ''}
    ${stratRules.length ? `<div class="modrow" style="margin-top:10px"><div class="lab">Stratagems (tap to use)</div><div class="chips">${stratRules.map(ruleChip).join('')}</div></div>` : ''}
    ${stratTextInPhase.length ? `<details class="more"><summary>Other stratagems — set by hand (${stratTextInPhase.length})</summary>${stratTextInPhase.map(st =>
      `<div class="ability"><b>${esc(st.name)}</b> <span class="muted tiny">${st.cp}CP · ${esc(st.detachment)}</span><div class="muted">${st.missing ? 'No 11e text in the dataset.' : esc(`${st.when} — ${st.effect}`)}</div></div>`).join('')}</details>` : ''}` : '';
  return `<div class="card" data-attacker="${e.uid}">
    <div class="attacker-head"><div class="num">${i + 1}</div>
      <div class="grow"><div class="title ellipsis">${esc(cu.name)}</div><div class="muted tiny">${cu.models} models</div></div>
      ${i > 0 ? `<button class="icon-btn" data-action="move-up" ${sc} aria-label="Resolve earlier">↑</button>` : ''}
      <button class="icon-btn" data-action="remove" ${sc} aria-label="Remove">✕</button></div>
    ${attachRow(state.side, cu)}
    <div style="margin-top:6px">${weapons}</div>
    ${rangeRow}
    <div class="chips" style="margin-top:8px">${sit}</div>
    ${situation || distRow ? `<div class="modrow" style="margin-top:8px"><div class="lab">Situation (switches matching abilities on)</div><div class="chips">${situation}</div>${distRow}</div>` : ''}
    ${rulesBlock}
    <details class="more" ${e.openMods ? 'open' : ''} data-details="mods" ${sc}><summary>Manual modifiers &amp; re-rolls${nMods ? ` · ${nMods} set` : ''}</summary><div class="modgrid">
      ${ms('Hit roll', 'hitMod', m.hitMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1']])}
      ${ms('Wound roll', 'woundMod', m.woundMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1']])}
      ${ms('Re-roll hits', 'rerollHits', m.rerollHits ?? 'none', [['none', 'None'], ['ones', '1s'], ['fail', 'Fails'], ['noncrit', 'Fish 6s']])}
      ${ms('Re-roll wounds', 'rerollWounds', m.rerollWounds ?? 'none', [['none', 'None'], ['ones', '1s'], ['fail', 'Fails'], ['noncrit', 'Fish 6s']])}
      ${ms('Critical hits on', 'critHit', m.critHit ?? 6, [[6, '6'], [5, '5+'], [4, '4+']])}
      ${ms('Critical wounds on', 'critWound', m.critWound ?? 6, [[6, '6'], [5, '5+'], [4, '4+']])}
      ${ms('AP improved by', 'apMod', m.apMod ?? 0, [[0, '0'], [1, '+1'], [2, '+2']])}
      ${ms('Damage', 'damageMod', m.damageMod ?? 0, [[-1, '−1'], [0, '0'], [1, '+1'], [2, '+2']])}
      ${ms('Attacks per weapon', 'attacksMod', m.attacksMod ?? 0, [[0, '0'], [1, '+1'], [2, '+2']])}
      ${ms('Strength', 'strengthMod', m.strengthMod ?? 0, [[0, '0'], [1, '+1'], [2, '+2']])}
      ${ms('Sustained Hits', 'sustained', m.sustained ?? 0, [[0, 'None'], [1, '1'], [2, '2']])}
      <div class="modrow"><div class="lab">Grant weapon abilities</div><div class="chips">
        ${chip('amod-toggle', !!m.lethal, 'Lethal Hits', `${sc} data-key="lethal"`)}
        ${chip('amod-toggle', !!m.dev, 'Devastating Wounds', `${sc} data-key="dev"`)}
        ${chip('amod-toggle', !!m.twin, 'Twin-linked', `${sc} data-key="twin"`)}
        ${shooting ? chip('amod-toggle', !!m.ignoresCover, 'Ignores Cover', `${sc} data-key="ignoresCover"`) : ''}
        ${chip('amod-toggle', !!m.precision, 'Precision', `${sc} data-key="precision"`)}
      </div></div>
      <div class="modrow"><div class="lab">Single-die re-rolls & other</div><div class="chips">
        ${chip('amod-toggle', !!m.rerollOneHit, 'Re-roll one hit (Command Re-roll)', `${sc} data-key="rerollOneHit"`)}
        ${chip('amod-toggle', !!m.rerollOneWound, 'Re-roll one wound', `${sc} data-key="rerollOneWound"`)}
        ${chip('amod-toggle', !!m.rerollOneDamage, 'Re-roll one damage roll', `${sc} data-key="rerollOneDamage"`)}
        ${chip('amod-toggle', !!m.rerollDamage, 'Re-roll damage rolls', `${sc} data-key="rerollDamage"`)}
        ${chip('amod-toggle', !!m.ignoreHitMods, 'Ignore hit modifiers', `${sc} data-key="ignoreHitMods"`)}
        ${chip('amod-toggle', !!m.ignoreWoundMods, 'Ignore wound modifiers', `${sc} data-key="ignoreWoundMods"`)}
      </div></div>
    </div></details>
    ${abil.length ? `<details class="more"><summary>Unit abilities (${abil.length})</summary>${abil.map(a =>
      `<div class="ability"><b>${esc(a.name)}</b> <span class="muted tiny">${esc(a.member)}</span><div class="muted">${esc(a.text)}</div></div>`).join('')}</details>` : ''}
  </div>`;
}

// ---- result bar + results sheet

function renderResultViews() {
  const bar = document.getElementById('resultbar');
  if (!bar) return;
  const r = state.result;
  const show = state.view === 'attack' && state.armies.A && state.armies.B;
  if (!show) { bar.innerHTML = ''; return; }
  let inner;
  if (state.calcError) inner = `<div class="err small grow">Calculation failed — see console.</div>`;
  else if (!r) inner = `<div class="muted small grow">${targetUnit() ? 'Add an attacking unit with weapons selected.' : 'Choose a target and add attackers.'}</div>`;
  else {
    inner = `<div class="kpis">
      <div class="kpi"><b>${fx(r.meanKills)}</b><span>avg kills / ${r.totalModels}</span></div>
      <div class="kpi"><b>${pct(r.pWipe)}</b><span>unit destroyed</span></div>
      <div class="kpi"><b>${fx(r.meanWounds)}</b><span>avg damage</span></div>
    </div>`;
  }
  bar.innerHTML = `<div class="resultbar ${state.busy ? 'busy' : ''}"><div class="wrap">${inner}
    <button class="btn primary" data-action="open-results" ${r ? '' : 'disabled'}>Details</button></div></div>`;
  if (state.sheet === 'results') renderSheet();
}

function renderSheet() {
  const host = document.getElementById('sheet');
  if (!host) return;
  if (!state.sheet) { host.innerHTML = ''; return; }
  const content = state.sheet === 'add' ? addSheet()
    : state.sheet === 'charge' ? chargeSheet()
    : state.sheet === 'grid' ? gridSheet()
    : state.sheet === 'library' ? librarySheet()
    : state.sheet === 'threats' ? threatsSheet()
    : state.sheet === 'saved' ? savedSheet()
    : state.sheet === 'attach' ? attachSheet()
      : state.sheet === 'join' ? joinSheet() : resultsSheet();
  host.innerHTML = `<div class="sheet-backdrop" data-action="close-sheet"></div>
    <div class="sheet" role="dialog" aria-modal="true"><div class="grab"></div><div class="wrap">${content}</div></div>`;
  if (state.sheet === 'results') wireChart();
}

// ---- Matchup grid: every attacking unit against every enemy unit

// Default matchup (always-on rules only) between any two armies, in any phase.
function defaultScenarioFor(atkArmyObj, defArmyObj, atkCu, defCu, phase) {
  const profile = defenderProfile(defCu, defArmyObj);
  const tinfo = { cu: defCu, profile, summary: defenderSummary(profile) };
  const entry = { unitKey: atkCu.key, counts: {}, mods: {} };
  const { rows } = rowsFor(entry, tinfo, atkArmyObj, phase);
  if (!rows.some(r => r.count > 0)) return null;
  const { rules, on } = rulesFor(entry, atkCu, tinfo, atkArmyObj, phase);
  return {
    phase,
    attackers: [buildAttacker(atkCu, rows, {}, rules, on, phase)],
    defender: buildDefender(profile, enabledRules(profile, { ruleOverrides: {} }), phase, {}, {}),
    seed: 99,
  };
}
function defaultScenario(atkCu, defCu) {
  return defaultScenarioFor(atkArmy(), defArmy(), atkCu, defCu, state.phase);
}

let gridWorker = null;
function startGrid() {
  const sig = `${listsSignature()}|${state.side}|${state.phase}`;
  if (state.grid?.sig === sig && (state.grid.running || state.grid.done)) return;
  gridWorker?.terminate();
  const atk = atkArmy().units, def = defArmy().units;
  const batch = [];
  const rows = [];
  for (const a of atk) {
    let any = false;
    for (const d of def) {
      const sc = defaultScenario(a, d);
      if (sc) { batch.push({ key: `${a.key}|${d.key}`, scenario: sc }); any = true; }
    }
    if (any) rows.push({ key: a.key, name: a.name, points: a.points });
  }
  state.grid = { sig, side: state.side, phase: state.phase, cells: {}, rows, cols: def.map(d => ({ key: d.key, name: d.name })), running: true, done: false, total: batch.length };
  const id = Date.now();
  gridWorker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
  gridWorker.onmessage = (ev) => {
    const msg = ev.data;
    if (msg.id !== id || !state.grid || state.grid.sig !== sig) return;
    if (msg.done) { state.grid.running = false; state.grid.done = true; console.log(`[calc] grid done: ${state.grid.total} matchups`); }
    else state.grid.cells[msg.key] = msg.result ?? { error: msg.error };
    if (state.sheet === 'grid') updateGrid();
  };
  gridWorker.postMessage({ id, batch, trials: 2000 });
}

function gridValue(c, row) {
  if (!c || c.error) return null;
  if (state.gridMetric === 'points') return { v: c.meanPoints, frac: c.meanPoints / Math.max(1, c.totalPoints), text: fx(c.meanPoints, 0) };
  if (state.gridMetric === 'eff') {
    const v = row?.points ? (100 * c.meanPoints) / row.points : 0;
    return { v, frac: Math.min(1, v / 100), text: fx(v, 0) }; // shade: 100 pts removed per 100 spent = darkest
  }
  if (state.gridMetric === 'kills') return { v: c.meanKills, frac: c.meanKills / Math.max(1, c.totalModels), text: fx(c.meanKills) };
  if (state.gridMetric === 'wipe') return { v: c.pWipe, frac: c.pWipe, text: pct(c.pWipe) };
  const f = c.meanWounds / Math.max(1, c.totalWounds);
  return { v: f, frac: f, text: pct(f) };
}

// sequential blue ramp (dataviz reference palette), light -> dark
const RAMP = ['#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95'];
function rampColor(frac) {
  const i = Math.max(0, Math.min(RAMP.length - 1, Math.floor(frac * RAMP.length)));
  return { bg: RAMP[i], ink: i >= 3 ? '#ffffff' : '#0b0b0b' };
}

function gridTable() {
  const g = state.grid;
  if (!g) return '';
  const short = (n) => (n.length > 18 ? `${n.slice(0, 17)}…` : n);
  const colName = (n) => (n.length > 26 ? `${n.slice(0, 25)}…` : n); // headers wrap
  const head = `<tr><th class="corner">${state.phase === 'fight' ? 'Fight' : 'Shooting'}</th>${g.cols.map(c => `<th title="${esc(c.name)}">${esc(colName(c.name))}</th>`).join('')}</tr>`;
  const body = g.rows.map(r => `<tr><th title="${esc(r.name)}">${esc(short(r.name))}</th>${g.cols.map(c => {
    const cell = g.cells[`${r.key}|${c.key}`];
    const val = gridValue(cell, r);
    if (!val) return `<td class="empty">${cell?.error ? '!' : g.running ? '…' : '–'}</td>`;
    const col = rampColor(val.frac);
    return `<td><button class="cell" data-action="grid-pick" data-atk="${esc(r.key)}" data-def="${esc(c.key)}" style="background:${col.bg};color:${col.ink}" title="${esc(`${r.name} → ${c.name}`)}">${esc(val.text)}</button></td>`;
  }).join('')}</tr>`).join('');
  return `<table class="grid"><thead>${head}</thead><tbody>${body}</tbody></table>`;
}

function updateGrid() {
  const host = document.getElementById('grid-host');
  const prog = document.getElementById('grid-progress');
  if (host) host.innerHTML = gridTable();
  if (prog && state.grid) prog.textContent = state.grid.done ? `${state.grid.total} matchups · 2,000 rolls each` : `Calculating ${Object.keys(state.grid.cells).length}/${state.grid.total}…`;
}

function gridSheet() {
  const g = state.grid;
  return `<div class="row"><h3 class="grow">Matchup grid</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="muted small" style="margin-bottom:8px">${esc(atkArmy().faction)} (rows) attacking ${esc(defArmy().faction)} (columns) · ${state.phase}. Always-on rules only — no stratagems or situational bonuses. Tap a cell to open that matchup.</div>
    ${seg('grid-metric', state.gridMetric, [['damage', '% W'], ['kills', 'Kills'], ['wipe', 'Wipe'], ['points', 'Pts'], ['eff', 'Pts/100']], 'compact')}
    <div class="tiny muted" style="margin-top:4px">${{ damage: '% of the unit’s wounds removed', kills: 'average models destroyed', wipe: 'chance the unit is destroyed', points: 'average points of models destroyed', eff: 'points destroyed per 100 points of the attacking unit' }[state.gridMetric] ?? ''}</div>
    <div class="grid-wrap" id="grid-host">${gridTable()}</div>
    <div class="tiny muted" id="grid-progress">${g?.done ? `${g.total} matchups · 2,000 rolls each` : `Calculating ${Object.keys(g?.cells ?? {}).length}/${g?.total ?? 0}…`}</div>`;
}

// ---- List library (tournament mode: keep every opponent's list on the phone)

function librarySheet() {
  const side = state.sheetArg?.side ?? 'A';
  const army = state.armies[side];
  const defName = army ? `${army.faction}${army.name && army.name !== 'Army' ? ` – ${army.name}` : ''}` : '';
  return `<div class="row"><h3 class="grow">List library</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <p class="hint">Save each opponent's list before the event (e.g. "R3 – Necrons"), then load it into A or B in one tap. Stored on this phone.</p>
    ${army ? `<div class="row" style="gap:6px"><input class="sel grow" data-input="lib-name" value="${esc(defName)}" aria-label="List name">
      <button class="btn primary" data-action="lib-save" data-side="${side}">Save army ${side}</button></div>` : `<p class="hint">Load a list into army ${side} to save it here.</p>`}
    <div class="section">${state.library.length ? state.library.map((l, i) => `<div class="pick" style="cursor:default">
        <div class="grow"><div class="title">${esc(l.name)}</div><div class="muted tiny">${esc(l.faction ?? '')} · ${new Date(l.savedAt).toLocaleDateString()}</div></div>
        <button class="btn" data-action="lib-load" data-i="${i}" data-side="A">→ A</button>
        <button class="btn" data-action="lib-load" data-i="${i}" data-side="B">→ B</button>
        <button class="icon-btn" data-action="lib-delete" data-i="${i}" aria-label="Delete ${esc(l.name)}">🗑</button></div>`).join('') : '<p class="hint">No saved lists yet.</p>'}</div>`;
}

// Load a list into army `side`, dropping setups that referred to the old list's units.
function loadListInto(side, text) {
  state.texts[side] = text;
  state.attach[side] = null;
  parseArmy(side);
  for (const [key, st] of Object.entries(state.setups)) {
    if (key.startsWith(`${side}:`)) st.attackers = [];
    else { st.targetKey = null; st.defOverrides = {}; }
  }
  state.grid = null;
}

// ---- Threat view: which enemy units hurt this unit most (default matchups, both phases)

let threatWorker = null;
function startThreats(side, key) {
  const mine = state.armies[side], theirs = state.armies[other(side)];
  const cu = mine?.units.find(u => u.key === key);
  if (!cu || !theirs) return;
  threatWorker?.terminate();
  const batch = [];
  for (const a of theirs.units) {
    for (const phase of ['shooting', 'fight']) {
      const sc = defaultScenarioFor(theirs, mine, a, cu, phase);
      if (sc) batch.push({ key: `${a.key}|${phase}`, scenario: sc });
    }
  }
  state.threats = { side, key, name: cu.name, enemy: theirs.faction, units: theirs.units.map(u => ({ key: u.key, name: u.name, points: u.points })), cells: {}, done: false, total: batch.length };
  const id = Date.now();
  threatWorker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
  threatWorker.onmessage = (ev) => {
    const msg = ev.data;
    if (msg.id !== id || !state.threats) return;
    if (msg.done) { state.threats.done = true; console.log(`[calc] threats to ${cu.name}: ${batch.length} matchups`); }
    else state.threats.cells[msg.key] = msg.result ?? { error: msg.error };
    if (state.sheet === 'threats') renderSheet();
  };
  threatWorker.postMessage({ id, batch, trials: 2000 });
}

function threatsSheet() {
  const t = state.threats;
  if (!t) return '';
  const frac = (c) => (c && !c.error ? c.meanWounds / Math.max(1, c.totalWounds) : null);
  const rows = t.units.map(u => {
    const sh = t.cells[`${u.key}|shooting`], fi = t.cells[`${u.key}|fight`];
    return { ...u, sh, fi, best: Math.max(frac(sh) ?? -1, frac(fi) ?? -1) };
  }).filter(r => r.best >= 0).sort((a, b) => b.best - a.best);
  const cell = (c, unitKey, phase) => {
    const f = frac(c);
    if (f == null) return `<td class="muted">–</td>`;
    const col = rampColor(f);
    return `<td><button class="cell" data-action="threat-pick" data-atk="${esc(unitKey)}" data-phase="${phase}" style="background:${col.bg};color:${col.ink}">${pct(f)}</button></td>`;
  };
  return `<div class="row"><h3 class="grow">Biggest threats to ${esc(t.name)}</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="muted small" style="margin-bottom:8px">Each ${esc(t.enemy)} unit attacking it on its own: % of its wounds removed, always-on rules only. Tap a cell to open that matchup.</div>
    <div class="grid-wrap"><table class="grid threats"><thead><tr><th class="corner">Enemy unit</th><th>Shooting</th><th>Fight</th></tr></thead>
      <tbody>${rows.map(r => `<tr><th title="${esc(r.name)}">${esc(r.name.length > 22 ? `${r.name.slice(0, 21)}…` : r.name)}</th>${cell(r.sh, r.key, 'shooting')}${cell(r.fi, r.key, 'fight')}</tr>`).join('')}</tbody></table></div>
    <div class="tiny muted" id="threat-progress">${t.done ? `${t.total} matchups · 2,000 rolls each` : `Calculating ${Object.keys(t.cells).length}/${t.total}…`}</div>`;
}

// ---- Saved scenarios

function savedSheet() {
  const s = setup();
  const t = targetUnit();
  const names = s.attackers.map(e => atkArmy()?.units.find(u => u.key === e.unitKey)?.name).filter(Boolean);
  const defName = names.length && t ? `${names.join(' + ')} → ${t.name} (${state.phase})` : '';
  const sig = listsSignature();
  return `<div class="row"><h3 class="grow">Saved scenarios</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    ${defName ? `<div class="row" style="gap:6px"><input class="sel grow" data-input="save-name" value="${esc(defName)}" aria-label="Scenario name">
      <button class="btn primary" data-action="save-scenario">Save</button></div>` : '<p class="hint">Set a target and attackers to save this setup.</p>'}
    ${state.savedNote ? `<div class="warnbox">${esc(state.savedNote)}</div>` : ''}
    <div class="section">${state.saved.length ? state.saved.map((sv, i) => `<div class="pick" style="cursor:default">
        <div class="grow"><div class="title">${esc(sv.name)}</div>
          <div class="muted tiny">${sv.summary ? `${fx(sv.summary.meanKills)} avg kills · ${pct(sv.summary.pWipe)} wipe · ` : ''}${new Date(sv.savedAt).toLocaleDateString()}${sv.sig !== sig ? ' · made with other lists' : ''}</div></div>
        <button class="btn" data-action="load-scenario" data-i="${i}">Load</button>
        <button class="icon-btn" data-action="delete-scenario" data-i="${i}" aria-label="Delete ${esc(sv.name)}">🗑</button></div>`).join('') : '<p class="hint">No saved scenarios yet.</p>'}</div>`;
}

function chargeSheet() {
  const c = state.charge;
  const need = chargeRollNeeded(c.gap);
  const p = chargeOdds(need, { mod: c.mod, reroll: c.reroll });
  const rows = [];
  for (let g = 3; g <= 14; g++) {
    const n = chargeRollNeeded(g);
    rows.push(`<tr ${Math.abs(g - c.gap) < 0.01 ? 'style="font-weight:700"' : ''}><td>${g}"</td><td>${n}+</td><td>${pct(chargeOdds(n, { mod: c.mod }))}</td><td>${pct(chargeOdds(n, { mod: c.mod, reroll: true }))}</td></tr>`);
  }
  return `<div class="row"><h3 class="grow">Charge odds</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="weapon" style="border-top:0"><div class="grow"><div class="wname">Gap to the nearest target</div><div class="wstats">base to base, in inches</div></div>
      <div class="stepper"><button data-action="charge-gap" data-delta="-0.5" aria-label="Shorter">−</button><div class="val">${c.gap}"</div><button data-action="charge-gap" data-delta="0.5" aria-label="Longer">+</button></div></div>
    <div class="modrow"><div class="lab">Charge roll modifier (nets to ±1)</div>${seg('charge-mod', c.mod, [[-1, '−1'], [0, '0'], [1, '+1']], 'compact')}</div>
    <div class="chips" style="margin-top:8px">${chip('charge-reroll', c.reroll, 'Re-roll the charge (e.g. Command Re-roll)')}</div>
    <div class="hero" style="grid-template-columns:1fr 1fr;margin-top:12px">
      <div class="cell"><b id="charge-need">${need}+</b><span>needed on 2D6 (gap − 2" engagement range)</span></div>
      <div class="cell"><b id="charge-p">${pct(p)}</b><span>chance to make it</span></div>
    </div>
    <div class="section"><h2>Quick reference${c.mod ? ` · ${c.mod > 0 ? '+' : '−'}1 to the roll` : ''}</h2>
      <table class="dist"><thead><tr><th>Gap</th><th>Needs</th><th>Chance</th><th>With re-roll</th></tr></thead><tbody>${rows.join('')}</tbody></table></div>
    <p class="hint">11e: the charge roll (2D6) is the maximum move and the unit must end engaged (within 2"), so you need the gap minus 2".</p>`;
}

function attachSheet() {
  const { side, host } = state.sheetArg ?? {};
  const army = state.armies[side];
  if (!army) return '';
  const cands = attachCandidates(army, host);
  const note = (c) => [
    c.role === 'support' ? 'Support' : 'Leader',
    c.eligible ? null : 'not on its Leader list',
    c.attachedTo != null ? `now with ${rosterUnitLabel(army, c.attachedTo)}` : null,
    c.replaces != null ? `replaces ${rosterUnitLabel(army, c.replaces)}` : null,
  ].filter(Boolean).join(' · ');
  return `<div class="row"><h3 class="grow">Attach to ${esc(rosterUnitLabel(army, host))}</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <p class="hint">One Leader and one Support per unit (11e). Characters that can't normally join this unit are listed last.</p>
    ${cands.map(c => `<button class="pick ${c.eligible ? '' : 'used'}" data-action="attach" data-side="${side}" data-char="${c.index}" data-host="${host}">
      <div class="grow"><div class="title">${esc(c.name)}</div><div class="muted tiny">${esc(note(c))}</div></div><span>＋</span></button>`).join('') ||
      '<div class="muted small">This army has no characters that can be attached.</div>'}`;
}

function joinSheet() {
  const { side, char } = state.sheetArg ?? {};
  const army = state.armies[side];
  if (!army) return '';
  const cands = joinCandidates(army, char);
  return `<div class="row"><h3 class="grow">${esc(rosterUnitLabel(army, char))} joins…</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    ${cands.map(c => `<button class="pick ${c.eligible ? '' : 'used'}" data-action="attach" data-side="${side}" data-char="${char}" data-host="${c.index}">
      <div class="grow"><div class="title">${esc(c.name)}</div><div class="muted tiny">${[c.eligible ? 'on its Leader list' : 'not on its Leader list', c.replaces != null ? `replaces ${rosterUnitLabel(army, c.replaces)}` : null].filter(Boolean).map(esc).join(' · ')}</div></div><span>＋</span></button>`).join('') ||
      '<div class="muted small">No units to join.</div>'}`;
}

function addSheet() {
  const s = setup();
  const used = new Set(s.attackers.map(a => a.unitKey));
  const units = atkArmy().units;
  return `<div class="row"><h3 class="grow">Add attacking unit</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    ${units.map(u => {
      const rows = attackerRows(u, state.phase, null);
      const n = rows.length;
      return `<button class="pick ${used.has(u.key) ? 'used' : ''}" data-action="add" data-key="${esc(u.key)}" ${n ? '' : 'disabled'}>
        <div class="grow"><div class="title">${esc(u.name)}</div><div class="muted tiny">${u.models} models · ${n ? `${n} ${state.phase === 'shooting' ? 'ranged' : 'melee'} profiles` : `no ${state.phase === 'shooting' ? 'ranged' : 'melee'} weapons`}${used.has(u.key) ? ' · already added' : ''}</div></div>
        <span>＋</span></button>`;
    }).join('')}`;
}

function chartData(r) {
  const mode = state.chartMode ?? (r.totalModels <= 1 ? 'damage' : 'models');
  const exact = mode === 'models' ? r.kills : r.wounds;
  const atLeast = mode === 'models' ? r.killsAtLeast : r.woundsAtLeast;
  // trim the long empty tail on damage charts
  let last = exact.length - 1;
  while (last > 0 && exact[last] < 0.0005) last--;
  return { mode, exact: exact.slice(0, last + 1), atLeast: atLeast.slice(0, last + 1), full: exact.length - 1 };
}

function chartSvg(d) {
  const n = d.exact.length;
  const W = 340, H = 150, padL = 30, padB = 22, padT = 16;
  const plotW = W - padL - 4, plotH = H - padB - padT;
  const slot = plotW / n;
  const bw = Math.max(2, Math.min(24, slot - 2));
  const maxP = Math.max(...d.exact, 0.01);
  const top = Math.min(1, Math.ceil(maxP * 10) / 10);
  const y = (p) => padT + plotH - (p / top) * plotH;
  const ticks = [0, top / 2, top];
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Probability of each outcome">`;
  for (const t of ticks) svg += `<line class="axis" x1="${padL}" x2="${W - 4}" y1="${y(t)}" y2="${y(t)}" opacity="${t === 0 ? 1 : 0.5}"/><text class="tick" x="${padL - 4}" y="${y(t) + 4}" text-anchor="end">${Math.round(t * 100)}%</text>`;
  const labelEvery = Math.ceil(n / 12);
  const peak = d.exact.indexOf(maxP);
  d.exact.forEach((p, k) => {
    const cx = padL + slot * k + slot / 2;
    const h = Math.max(0, y(0) - y(p));
    const x = cx - bw / 2;
    const r = Math.min(4, bw / 2, h);
    const yTop = y(0) - h;
    // 4px rounded data-end, square at the baseline
    const path = h <= 0 ? '' : `M${x},${y(0)} V${yTop + r} Q${x},${yTop} ${x + r},${yTop} H${x + bw - r} Q${x + bw},${yTop} ${x + bw},${yTop + r} V${y(0)} Z`;
    svg += `<path class="bar ${state.selBar === k ? 'sel' : ''}" d="${path}"/>`;
    svg += `<rect class="hit" data-bar="${k}" x="${padL + slot * k}" y="${padT}" width="${slot}" height="${plotH + padB}"/>`;
    if (k % labelEvery === 0 || k === n - 1) svg += `<text class="tick" x="${cx}" y="${H - 6}" text-anchor="middle">${k}</text>`;
    if (k === peak && p > 0) svg += `<text class="lbl" x="${cx}" y="${yTop - 4}" text-anchor="middle">${Math.round(p * 100)}%</text>`;
  });
  return svg + '</svg>';
}

function resultsSheet() {
  const r = state.result;
  if (!r) return '<div class="muted">No result yet.</div>';
  const d = chartData(r);
  const what = d.mode === 'models' ? 'models destroyed' : 'damage dealt';
  // only the informative rows: skip the certain head (">99%" at least, ~0 exactly) and the empty tail
  const rows = d.exact.map((p, k) => ({ k, p, ge: d.atLeast[k] })).filter(x => x.p >= 0.005 || (x.ge >= 0.005 && x.ge < 0.995));
  const sc = scenario();
  const unsupported = new Set();
  const s = setup();
  const tinfo = targetInfo();
  for (const e of s.attackers) for (const row of rowsFor(e, tinfo).rows) if (row.count) for (const t of row.unsupported) unsupported.add(`${row.label}: ${t}`);
  const st = r.steps;
  return `<div class="row"><h3 class="grow">${esc(targetUnit()?.name ?? '')}</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="hero">
      <div class="cell"><b>${fx(r.meanKills)}</b><span>avg models destroyed of ${r.totalModels}</span></div>
      <div class="cell"><b>${pct(r.pWipe)}</b><span>chance unit destroyed</span></div>
      <div class="cell"><b>${fx(r.meanWounds)}</b><span>avg damage of ${r.totalWounds} W</span></div>
    </div>
    ${r.totalPoints ? (() => {
      const atkPts = s.attackers.reduce((a, e) => a + (atkArmy()?.units.find(u => u.key === e.unitKey)?.points ?? 0), 0);
      return `<div class="hero" style="grid-template-columns:1fr 1fr;margin-top:8px">
        <div class="cell"><b id="pts-removed">${fx(r.meanPoints, 0)}</b><span>avg points destroyed of ${Math.round(r.totalPoints)}</span></div>
        <div class="cell"><b id="pts-eff">${atkPts ? fx((100 * r.meanPoints) / atkPts, 0) : '–'}</b><span>points destroyed per 100 pts attacking (${atkPts} pts)</span></div>
      </div>`;
    })() : ''}
    ${st.abilityMortals > 0.005 ? `<div class="tiny muted" style="margin-top:6px">Includes ${fx(st.abilityMortals)} mortal wounds from abilities / stratagems on average.</div>` : ''}
    <div class="section"><h2>Chance of exactly N ${what}</h2>
      ${seg('chart-mode', d.mode, [['models', 'Models destroyed'], ['damage', 'Damage dealt']], 'compact')}
      <div class="readout" id="readout">${readout(d, state.selBar ?? d.exact.indexOf(Math.max(...d.exact)))}</div>
      <div class="chart" id="chart">${chartSvg(d)}</div>
      <div class="tiny muted">Tap a bar for its odds. ${r.trials.toLocaleString()} simulated attacks${state.busy ? ' (refining…)' : ''}.</div>
    </div>
    <div class="section"><h2>Odds table</h2>
      <table class="dist"><thead><tr><th>${d.mode === 'models' ? 'Models' : 'Damage'}</th><th>Exactly</th><th>At least</th></tr></thead>
      <tbody>${rows.map(x => `<tr><td>${x.k}</td><td>${pct(x.p)}</td><td>${pct(x.ge)}</td></tr>`).join('')}</tbody></table>
    </div>
    <div class="section"><h2>Average per step</h2><div class="pipeline">
      <div><b>${fx(st.attacks)}</b><span>Attacks</span></div>
      <div><b>${fx(st.hits)}</b><span>Hits</span></div>
      <div><b>${fx(st.wounds)}</b><span>Wounds</span></div>
      <div><b>${fx(st.unsaved + st.mortals)}</b><span>Unsaved</span></div>
      <div><b>${fx(r.meanWounds)}</b><span>Damage</span></div>
    </div>${st.mortals > 0.005 ? `<div class="tiny muted" style="margin-top:4px">Unsaved includes ${fx(st.mortals)} Devastating Wounds (mortal wounds; each hits one model).</div>` : ''}</div>
    ${r.perAttacker.length > 1 ? `<div class="section"><h2>Per attacking unit (in order)</h2>
      <table class="dist"><thead><tr><th>Unit</th><th>Avg kills</th><th>Avg dmg</th></tr></thead><tbody>
      ${r.perAttacker.map(p => `<tr><td>${esc(p.name)}</td><td>${fx(p.kills)}</td><td>${fx(p.wounds)}</td></tr>`).join('')}</tbody></table></div>` : ''}
    ${r.groupKills.length > 1 ? `<div class="section"><h2>By model type</h2>
      <table class="dist"><thead><tr><th>Models</th><th>Avg destroyed</th></tr></thead><tbody>
      ${r.groupKills.map(g => `<tr><td>${esc(g.name)}${g.character ? ' (character)' : ''}</td><td>${fx(g.mean, 2)} / ${g.count}</td></tr>`).join('')}</tbody></table></div>` : ''}
    ${(() => {
      const used = [];
      for (const e of s.attackers) {
        const cu = atkArmy()?.units.find(u => u.key === e.unitKey);
        if (!cu) continue;
        const { rules, on } = rulesFor(e, cu, tinfo);
        for (const ru of rules) if (on.has(ru.id)) used.push({ who: cu.name, label: ru.label, source: ru.source, cp: ru.cp ?? 0 });
      }
      if (tinfo) {
        const don = enabledRules(tinfo.profile, s);
        for (const ru of tinfo.profile.rules) if (don.has(ru.id) && ru.phases.includes(state.phase)) used.push({ who: tinfo.cu.name, label: ru.label, source: ru.source, cp: ru.cp ?? 0 });
      }
      if (!used.length) return '';
      const cp = used.reduce((a, u) => a + u.cp, 0);
      return `<div class="section"><h2>Rules applied${cp ? ` · ${cp}CP of stratagems` : ''}</h2>${used.map(u =>
        `<div class="ability"><b>${esc(u.label)}</b> <span class="muted">· ${esc(u.source)}</span> <span class="muted tiny">(${esc(u.who)})</span></div>`).join('')}</div>`;
    })()}
    ${r.hazardMW > 0 ? `<div class="warnbox">Hazardous: attacker suffers ${fx(r.hazardMW, 2)} mortal wounds on average.</div>` : ''}
    ${unsupported.size ? `<div class="warnbox">Not modelled: ${[...unsupported].map(esc).join('; ')}.</div>` : ''}
    ${sc ? `<div class="tiny muted" style="margin-top:10px">Defender allocation: non-character groups first (the one with the best save first), characters last. Rules: 11th edition core rules.</div>` : ''}`;
}

function readout(d, k) {
  if (k == null || k < 0 || k >= d.exact.length) return '';
  const unit = d.mode === 'models' ? (k === 1 ? 'model' : 'models') : 'damage';
  return `<b>${k} ${unit}</b>: exactly ${pct(d.exact[k])} · at least ${pct(d.atLeast[k])}`;
}

function wireChart() {
  const chart = document.getElementById('chart');
  if (!chart || !state.result) return;
  const d = chartData(state.result);
  chart.querySelectorAll('.hit').forEach(el => {
    const show = () => {
      const k = Number(el.dataset.bar);
      state.selBar = k;
      chart.querySelectorAll('.bar').forEach((b, i) => b.classList.toggle('sel', i === k));
      // readout line above the plot (a floating tooltip would sit under the thumb on a phone)
      const ro = document.getElementById('readout');
      if (ro) ro.innerHTML = readout(d, k);
    };
    el.addEventListener('pointerenter', show);
    el.addEventListener('click', show);
  });
}

// ---------------------------------------------------------------------------
// Events

function findEntry(uid) {
  return setup().attackers.find(a => String(a.uid) === String(uid));
}

function changed({ full = true, calc = true } = {}) {
  persist();
  if (full) render();
  if (calc) scheduleCalc();
}

function coerce(v) {
  if (v === 'true') return true;
  if (v === 'false') return false;
  if (/^-?\d+$/.test(v)) return Number(v);
  return v;
}

app.addEventListener('click', (ev) => {
  const el = ev.target.closest('[data-action]');
  if (!el || el.disabled) return;
  const a = el.dataset.action;
  const s = setup();
  if (a.startsWith('board-')) {
    if (boardAction(a, el) === 'render') changed();
    return;
  }
  switch (a) {
    case 'view':
      state.view = el.dataset.value;
      state.sheet = null;
      return changed();
    case 'parse': {
      const side = el.dataset.side;
      const ta = app.querySelector(`textarea[data-side="${side}"]`);
      state.texts[side] = ta?.value ?? '';
      state.attach[side] = null; // a (re)loaded list starts from its own attachments
      parseArmy(side);
      return changed();
    }
    case 'clear':
      state.texts[el.dataset.side] = '';
      state.attach[el.dataset.side] = null;
      state.armies[el.dataset.side] = null;
      for (const k of Object.keys(state.setups)) if (k.startsWith(el.dataset.side + ':') || k.startsWith(other(el.dataset.side) + ':')) state.setups[k] = { targetKey: null, attackers: [], ruleOverrides: {}, defManual: {} };
      return changed();
    case 'reset-attach': {
      const side = el.dataset.side;
      const army = state.armies[side];
      if (army) applyAttachments(side, army.defaultAttachments, { edited: false });
      return changed();
    }
    case 'phase':
      state.phase = el.dataset.value;
      return changed();
    case 'swap':
      state.side = other(state.side);
      state.selBar = null;
      return changed();
    case 'open-add':
      state.sheet = 'add';
      return renderSheet();
    case 'open-results':
      state.sheet = 'results';
      state.selBar = null;
      return renderSheet();
    case 'close-sheet':
      state.sheet = null;
      return renderSheet();
    case 'open-attach':
      state.sheet = 'attach';
      state.sheetArg = { side: el.dataset.side, host: Number(el.dataset.host) };
      return renderSheet();
    case 'open-join':
      state.sheet = 'join';
      state.sheetArg = { side: el.dataset.side, char: Number(el.dataset.char) };
      return renderSheet();
    case 'attach':
      applyAttach(el.dataset.side, Number(el.dataset.char), Number(el.dataset.host));
      state.sheet = null;
      return changed();
    case 'detach':
      applyAttach(el.dataset.side, Number(el.dataset.char), null);
      return changed();
    case 'dmg': {
      const tinfo = targetInfo();
      const g = tinfo?.profile.groups.find(x => x.key === el.dataset.group);
      if (!g) return;
      s.defOverrides[s.targetKey] ??= {};
      const o = (s.defOverrides[s.targetKey][g.key] ??= {});
      const d = Number(el.dataset.delta);
      if (el.dataset.field === 'count') o.count = Math.max(0, Math.min(g.count, (o.count ?? g.count) + d));
      else o.woundsLeftFirst = Math.max(1, Math.min(g.W, (o.woundsLeftFirst ?? g.W) + d));
      if (o.count === g.count) delete o.count;
      if (o.woundsLeftFirst === g.W) delete o.woundsLeftFirst;
      state.openCasualties = true;
      return changed();
    }
    case 'dmg-reset':
      delete s.defOverrides[s.targetKey];
      return changed();
    case 'inrange': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      const cu = atkArmy()?.units.find(u => u.key === e.unitKey);
      const total = cu ? bodyguardModels(cu).total : 0;
      e.inRange = Math.max(0, Math.min(total, (e.inRange ?? total) + Number(el.dataset.delta)));
      if (e.inRange === total) e.inRange = null;
      return changed();
    }
    case 'intel-side':
      state.intelSide = el.dataset.value;
      state.intelQuery = '';
      return changed({ calc: false });
    case 'target-this': {
      // the chosen unit becomes the target; the other army attacks
      state.side = other(el.dataset.side);
      const st = setup();
      st.targetKey = el.dataset.key;
      state.view = 'attack';
      window.scrollTo(0, 0);
      return changed();
    }
    case 'open-library':
      state.sheet = 'library';
      state.sheetArg = { side: el.dataset.side };
      return renderSheet();
    case 'lib-save': {
      const side = el.dataset.side;
      const army = state.armies[side];
      if (!army) return;
      const name = app.querySelector('input[data-input="lib-name"]')?.value?.trim() || army.faction;
      const existing = state.library.findIndex(l => l.name === name);
      const item = { id: Date.now(), name, faction: army.faction, text: state.texts[side], savedAt: Date.now() };
      if (existing >= 0) state.library[existing] = item; else state.library.unshift(item);
      persistLibrary();
      console.log(`[calc] list saved to library: ${name}`);
      return render();
    }
    case 'lib-load': {
      const l = state.library[Number(el.dataset.i)];
      if (!l) return;
      loadListInto(el.dataset.side, l.text);
      state.sheet = null;
      console.log(`[calc] library list "${l.name}" loaded into ${el.dataset.side}`);
      return changed();
    }
    case 'lib-delete':
      state.library.splice(Number(el.dataset.i), 1);
      persistLibrary();
      return render();
    case 'open-threats':
      state.sheet = 'threats';
      startThreats(el.dataset.side, el.dataset.key);
      return renderSheet();
    case 'threat-pick': {
      const t = state.threats;
      if (!t) return;
      state.side = other(t.side);
      state.phase = el.dataset.phase;
      const st = setup();
      st.targetKey = t.key;
      st.attackers = [{ uid: uidSeq++, unitKey: el.dataset.atk, counts: {}, mods: {} }];
      state.view = 'attack';
      state.sheet = null;
      window.scrollTo(0, 0);
      return changed();
    }
    case 'open-grid':
      state.sheet = 'grid';
      startGrid();
      return renderSheet();
    case 'grid-metric':
      state.gridMetric = el.dataset.value;
      return renderSheet();
    case 'grid-pick': {
      // open that matchup: this unit is the only attacker, the column unit the target
      s.targetKey = el.dataset.def;
      s.attackers = [{ uid: uidSeq++, unitKey: el.dataset.atk, counts: {}, mods: {} }];
      state.sheet = null;
      window.scrollTo(0, 0);
      return changed();
    }
    case 'open-saved':
      state.sheet = 'saved';
      state.savedNote = null;
      return renderSheet();
    case 'save-scenario': {
      const name = app.querySelector('input[data-input="save-name"]')?.value?.trim() || 'Scenario';
      state.saved.unshift({
        id: Date.now(), name, savedAt: Date.now(), sig: listsSignature(),
        side: state.side, phase: state.phase, setup: JSON.parse(JSON.stringify(s)),
        summary: state.result ? { meanKills: state.result.meanKills, pWipe: state.result.pWipe, meanWounds: state.result.meanWounds } : null,
      });
      state.saved = state.saved.slice(0, 50);
      persistSaved();
      state.savedNote = `Saved “${name}”.`;
      return render();
    }
    case 'load-scenario': {
      const sv = state.saved[Number(el.dataset.i)];
      if (!sv) return;
      state.side = sv.side;
      state.phase = sv.phase;
      const st = JSON.parse(JSON.stringify(sv.setup));
      for (const a of st.attackers ?? []) a.uid = uidSeq++;
      const atkKeys = new Set(atkArmy()?.units.map(u => u.key) ?? []);
      const defKeys = new Set(defArmy()?.units.map(u => u.key) ?? []);
      const before = (st.attackers ?? []).length;
      st.attackers = (st.attackers ?? []).filter(a => atkKeys.has(a.unitKey));
      const lostTarget = st.targetKey && !defKeys.has(st.targetKey);
      if (lostTarget) st.targetKey = null;
      state.setups[`${sv.side}:${sv.phase}`] = st;
      state.sheet = null;
      if (sv.sig !== listsSignature() && (lostTarget || st.attackers.length < before)) {
        console.warn('[calc] saved scenario made with other lists: some units are missing');
      }
      return changed();
    }
    case 'delete-scenario':
      state.saved.splice(Number(el.dataset.i), 1);
      persistSaved();
      return render();
    case 'open-charge':
      state.sheet = 'charge';
      return renderSheet();
    case 'charge-gap':
      state.charge.gap = Math.max(2.5, Math.min(24, state.charge.gap + Number(el.dataset.delta)));
      persist();
      return renderSheet();
    case 'charge-mod':
      state.charge.mod = Number(el.dataset.value);
      persist();
      return renderSheet();
    case 'charge-reroll':
      state.charge.reroll = !state.charge.reroll;
      persist();
      return renderSheet();
    case 'add': {
      s.attackers.push({ uid: uidSeq++, unitKey: el.dataset.key, counts: {}, mods: {} });
      state.sheet = null;
      return changed();
    }
    case 'remove':
      s.attackers = s.attackers.filter(x => String(x.uid) !== el.dataset.uid);
      return changed();
    case 'move-up': {
      const i = s.attackers.findIndex(x => String(x.uid) === el.dataset.uid);
      if (i > 0) [s.attackers[i - 1], s.attackers[i]] = [s.attackers[i], s.attackers[i - 1]];
      return changed();
    }
    case 'count': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      const row = rowsFor(e, targetInfo()).rows.find(r => r.id === el.dataset.row);
      if (!row || row.blocked) return;
      e.counts ??= {};
      e.counts[row.id] = Math.max(0, Math.min(row.max, row.count + Number(el.dataset.delta)));
      return changed();
    }
    case 'arule': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      const tinfo = targetInfo();
      const cu = atkArmy()?.units.find(u => u.key === e.unitKey);
      if (!cu) return;
      const { rules, on } = rulesFor(e, cu, tinfo);
      e.ruleOverrides ??= {};
      const id = el.dataset.id;
      const turnOn = !on.has(id);
      e.ruleOverrides[id] = turnOn;
      // choice rules ("X, or Y"): picking one option switches the others off
      const r = rules.find(x => x.id === id);
      if (turnOn && r?.group) for (const sib of rules) if (sib.group === r.group && sib.id !== id) e.ruleOverrides[sib.id] = false;
      return changed();
    }
    case 'doctrine': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      e.mods ??= {};
      e.mods.doctrine = e.mods.doctrine === el.dataset.value ? '' : el.dataset.value;
      return changed();
    }
    case 'distance': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      e.mods ??= {};
      const d = Number(el.dataset.delta);
      e.mods.distance = e.mods.distance == null ? (d > 0 ? 6 : null) : Math.max(1, Math.min(48, e.mods.distance + d));
      return changed();
    }
    case 'amod-toggle': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      e.mods ??= {};
      e.mods[el.dataset.key] = !e.mods[el.dataset.key];
      return changed();
    }
    case 'mod': {
      const v = coerce(el.dataset.value);
      if (el.dataset.scope === 'def') s.defManual[el.dataset.key] = v;
      else {
        const e = findEntry(el.dataset.uid);
        if (!e) return;
        e.mods ??= {};
        e.mods[el.dataset.key] = v;
        e.openMods = true;
      }
      return changed();
    }
    case 'defmod-toggle':
      s.defManual[el.dataset.key] = !s.defManual[el.dataset.key];
      return changed();
    case 'rule': {
      const tinfo = targetInfo();
      const r = tinfo?.profile.rules.find(x => x.id === el.dataset.id);
      if (!r) return;
      const on = enabledRules(tinfo.profile, s).has(r.id);
      s.ruleOverrides[r.id] = !on;
      return changed();
    }
    default:
  }
});

// sheet lives outside #app's main but inside it in the DOM; chart-mode buttons
document.addEventListener('click', (ev) => {
  const el = ev.target.closest('[data-action="chart-mode"]');
  if (!el) return;
  state.chartMode = el.dataset.value;
  state.selBar = null;
  renderSheet();
});

app.addEventListener('change', (ev) => {
  const el = ev.target;
  if (boardChange(el)) return changed({ calc: false });
  if (el.dataset.input === 'attach') {
    applyAttach(el.dataset.side, Number(el.dataset.char), el.value === '' ? null : Number(el.value));
    return changed();
  }
  if (el.dataset.input === 'target') {
    const s = setup();
    s.targetKey = el.value || null;
    state.selBar = null;
    changed();
  }
});
app.addEventListener('input', (ev) => {
  const el = ev.target;
  if (el.dataset.input === 'text') { state.texts[el.dataset.side] = el.value; persist(); }
  if (el.dataset.input === 'intel-search') {
    state.intelQuery = el.value;
    const list = document.getElementById('intel-list');
    if (list) list.innerHTML = intelList(intelSide());
  }
});
app.addEventListener('toggle', (ev) => {
  const el = ev.target;
  if (el.dataset?.details === 'casualties') state.openCasualties = el.open;
  if (el.dataset?.details === 'board-tray' && state.board) state.board.trayClosed = !el.open;
  if (el.dataset?.details === 'mods') {
    const e = findEntry(el.dataset.uid);
    if (e) { e.openMods = el.open; persist(); }
  }
}, true);

// ---------------------------------------------------------------------------
// Boot

restore();
restoreSaved();
restoreLibrary();
initBoard({
  state, esc, seg, chip, signature: listsSignature,
  // "Shoot / Fight ->" from the board: that unit attacks that target, with the measured gap
  openAttack({ side, phase, attacker, target, distance, halfRange }) {
    state.side = side;
    state.phase = phase;
    const st = setup();
    st.targetKey = target;
    const mods = { distance, halfRange };
    const existing = st.attackers.find(x => x.unitKey === attacker);
    if (existing) existing.mods = { ...(existing.mods ?? {}), ...mods };
    else st.attackers = [{ uid: uidSeq++, unitKey: attacker, counts: {}, mods }];
    state.view = 'attack';
    window.scrollTo(0, 0);
    console.log(`[calc] board -> calculator: ${attacker} ${phase} into ${target}, ${distance}" (half range ${halfRange})`);
  },
});
parseArmy('A');
parseArmy('B');
if (!(state.armies.A && state.armies.B)) state.view = 'armies';
render();
scheduleCalc();

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('./sw.js').catch(err => console.warn('[calc] service worker not registered', err));
}

// test / debugging hook
window.__calc = { state, scenario, runCalc, defaultScenario, atkArmy, defArmy, board: _boardDebug };
