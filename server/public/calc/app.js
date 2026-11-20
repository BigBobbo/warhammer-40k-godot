// Combat calculator UI. State lives in localStorage; the dataset/importer
// come from the Army Builder modules (adapter.mjs); the dice run in a Web
// Worker (worker.mjs -> engine.mjs).
import {
  importArmy, attackerRows, engineWeapon, allVehicleMonster, abilitiesOf,
  defenderProfile, defenderSummary, buildDefender, DATASET_VERSION, armyData, fmtDataDate, dataNewest, ERRATA_RESULT,
  setAttachments, withAttachment, attachCandidates, joinCandidates, rosterUnitLabel,
  attackerRules, attackerRuleOn, buildAttacker, choiceProblem, describeConditions, unitIntel, armyIntel, coreFlags, shockFacts,
  phaseSheetInput,
} from './adapter.mjs';
import { phaseSheet, ticksOf, usageLabel } from './phasesheet.mjs';
import { chargeOdds, chargeRollNeeded, CHARGE_MAX } from './engine.mjs';
import { chooseWeapons, families, decisions, adjustCount, overSidearms } from './choose.mjs';
import { CALC_VERSION } from './version.mjs';
import { makeBackup, describeBackup, applyBackup, undoRestore, backupFileName, normalizeCode, CODE_RE, UNDO_KEY, LAST_KEY } from './backup.mjs';
import { initBoard, boardView, boardAction, boardChange, afterRender as boardAfterRender, _boardDebug } from './boardview.mjs';
import { initMission, missionView, missionAction, missionChange, missionAfterRender, scheduleForecast, missionNewGame, missionInProgress, missionScore, syncWake, _missionDebug } from './missionview.mjs';
import { initEvent, eventCard, eventAction, eventChange, _eventDebug } from './eventview.mjs';
import { initBrief, briefHtml } from './briefview.mjs';

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
  intelSide: null,           // army shown on the Intel tab (default: the defender; "By phase": your own army)
  intelMode: 'units',        // 'units' (datasheets) | 'phase' (what the army does, phase by phase)
  intelPhase: 'all',         // the phase shown in "By phase": 'all' or a phase id of phasesheet.mjs
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
      intelMode: state.intelMode, intelPhase: state.intelPhase,
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

function hashStr(str) {
  let h = 5381;
  for (let i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}
// one army's list and attachments (a plan made with this list can be reused against another opponent)
function sideSig(X) { return hashStr(JSON.stringify([state.texts[X], state.attach[X]])); }
// "Orks – Calc Test Waaagh"
function listLabel(X) {
  const a = state.armies[X];
  return a ? `${a.faction}${a.name && a.name !== 'Army' ? ` – ${a.name}` : ''}` : '';
}

function restore() {
  try {
    const s = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (!s) return;
    Object.assign(state, {
      view: s.view ?? 'armies', texts: s.texts ?? { A: '', B: '' }, side: s.side ?? 'A',
      phase: s.phase ?? 'shooting', setups: s.setups ?? {}, attach: s.attach ?? { A: null, B: null },
      charge: s.charge ?? { gap: 9, mod: 0, reroll: false }, intelSide: s.intelSide ?? null,
      intelMode: s.intelMode === 'phase' ? 'phase' : 'units', intelPhase: s.intelPhase ?? 'all',
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

// The engine defender of the target as it is set up on the Attack tab (rules on, casualties, manual modifiers).
function currentDefender(tinfo, phase = state.phase) {
  const s = setup();
  return buildDefender(tinfo.profile, enabledRules(tinfo.profile, s), phase, s.defManual, s.defOverrides[s.targetKey] ?? {});
}

// Weapon choice (choose.mjs): the engine scores every legal option against this target. Remembered per
// problem (unit + rules + situation + target as set up), so a re-render costs nothing.
const choiceCache = new Map();
function chooseCached(problem) {
  const key = JSON.stringify(problem);
  let hit = choiceCache.get(key);
  if (!hit) {
    hit = chooseWeapons(problem, { context: 'always' });     // one unit, on the page: always checked with its whole attack
    if (hit.sims) console.log(`[calc] weapon choice: ${problem.attacker?.name} (${problem.phase}) - ${hit.sims} option run(s)`);
    choiceCache.set(key, hit);
    if (choiceCache.size > 400) choiceCache.delete(choiceCache.keys().next().value);
  }
  return hit;
}

/**
 * The weapon rows of an attacker entry with the number of weapons that attack.
 * A count set by hand wins; the others are chosen (the best legal weapons and
 * profiles against this target). opt.defer: do not choose here (the worker does,
 * for the grid and the unit-against-unit odds) - rows then carry the first guess.
 * Each row: count (after "models in range"), full (before it), manual, fam
 * (family of rows whose counts depend on each other, or null), note (the
 * scores behind the choice).
 */
function rowsFor(entry, tinfo, army = atkArmy(), phase = state.phase, opt = {}) {
  const cu = army?.units.find(u => u.key === entry.unitKey);
  if (!cu) return { cu: null, rows: [] };
  const body = bodyguardModels(cu);
  const inRange = entry.inRange != null ? Math.max(0, Math.min(body.total, entry.inRange)) : null;
  if (tinfo) tinfo.defender ??= currentDefender(tinfo, phase);
  const base = attackerRows(cu, phase, tinfo?.summary ?? null, { shooting: entry.mods?.shootingType ?? 'normal', targetEngaged: !!tinfo?.defender?.mods?.engagedMV });
  let problem = null, auto = null;
  if (tinfo && base.length) {
    const { rules, on } = rulesFor(entry, cu, tinfo, army, phase);
    problem = choiceProblem(cu, base, entry.mods, rules, on, phase, tinfo.defender, tinfo.summary);
    if (!opt.defer) auto = chooseCached(problem);
  }
  const fam = auto?.families ?? (problem ? families(problem) : new Map());
  // Which profile or weapon is best depends on the target: counts set by hand for rows that are a choice
  // hold for the target they were set against only (a Hunter profile set by hand would otherwise make no
  // attacks against the next target). Counts of weapons with nothing to choose stay.
  const tkey = tinfo?.cu?.key ?? null;
  const stale = entry.countsFor != null && tkey != null && entry.countsFor !== tkey;
  const manualOf = (r) => { const v = entry.counts?.[r.id]; return v == null || (stale && fam.get(r.id) != null) ? null : v; };
  // a family with one count set by hand is set by hand as a whole (its other rows: 0)
  const byHand = new Set(base.filter(r => fam.get(r.id) != null && manualOf(r) != null).map(r => fam.get(r.id)));
  const rows = base.map(r => {
    const f = fam.get(r.id) ?? null;
    const manual = manualOf(r);
    const chosen = f != null && byHand.has(f) ? 0 : (auto?.counts[r.id] ?? r.count);
    const full = r.blocked ? 0 : Math.min(r.max, manual ?? chosen);
    // models in range: scale the bodyguard models' weapons; attached characters stay in
    const count = inRange != null && body.members.has(Number(String(r.id).split(':')[0])) ? Math.round(full * inRange / Math.max(1, body.total)) : full;
    return { ...r, count, full, manual: manual != null || (f != null && byHand.has(f)), fam: f, note: auto?.notes.get(r.id) ?? null };
  });
  return { cu, rows, inRange, bodyTotal: body.total, problem, stale };
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
    if (final) workerBusy = false;
    if (id !== reqId) return;   // an answer for an older set-up: never shown as the current one
    if (error) { state.calcError = error; state.busy = false; console.error('[calc] engine error', error); }
    else { state.result = result; state.calcError = null; state.busy = !final; }
    renderResultViews();
  };
  return w;
}

function scheduleCalc() {
  clearTimeout(calcTimer);
  // The set-up changed: whatever is still being calculated is for the old one. Dim the bar
  // at once and drop that answer when it arrives, so a stale number is never read as fresh
  // (before 1.95 it could be, for the 120 ms until the new run started).
  reqId++;
  state.busy = true;
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

// tablet / laptop: two panes side by side (the phone keeps one column)
const WIDE_Q = window.matchMedia('(min-width: 900px)');
const wide = () => WIDE_Q.matches;
WIDE_Q.addEventListener?.('change', () => { console.log(`[calc] layout: ${wide() ? 'two panes' : 'one column'}`); render(); });

// table mode (Mission > Play): the tracker only — the calculator and the board planner are closed
const tableMode = () => !!state.mission?.table;

function render() {
  const a = state.armies.A, b = state.armies.B;
  const ready = a && b;
  const table = tableMode() && ready;
  if (table && (state.view === 'attack' || state.view === 'board')) state.view = 'mission';
  // (not disabled: a tap on a closed tab says why, on the Play view)
  const lock = table ? 'data-locked="1" title="Closed in table mode (Mission > Play)"' : '';
  app.innerHTML = `
    <header class="top"><div class="wrap">
      <div class="brand">⚔<span class="brand-full"> Combat Calc</span><span class="ver-mini" id="app-version-mini">v${esc(CALC_VERSION)}</span></div>
      <span class="badge" id="app-version" title="App version · 40kdc dataset ${esc(DATASET_VERSION)}">v${esc(CALC_VERSION)}</span>
      <nav class="tabs">
        <button class="tab ${state.view === 'armies' ? 'on' : ''}" data-action="view" data-value="armies">Armies</button>
        <button class="tab ${state.view === 'intel' ? 'on' : ''}" data-action="view" data-value="intel" ${a || b ? '' : 'disabled'}>Intel</button>
        <button class="tab ${state.view === 'attack' ? 'on' : ''} ${table ? 'locked' : ''}" data-action="view" data-value="attack" ${ready ? lock : 'disabled'}>Attack</button>
        <button class="tab ${state.view === 'board' ? 'on' : ''} ${table ? 'locked' : ''}" data-action="view" data-value="board" ${ready ? lock : 'disabled'}>Board</button>
        <button class="tab ${state.view === 'mission' ? 'on' : ''}" data-action="view" data-value="mission" ${ready ? '' : 'disabled'}>Mission</button>
      </nav>
    </div></header>
    <main class="wrap">${state.view === 'attack' && ready ? attackView() : state.view === 'board' && ready ? boardView() : state.view === 'mission' && ready ? missionView() : state.view === 'intel' && (a || b) ? intelView() : armiesView()}</main>
    <div id="resultbar"></div>
    <div id="sheet"></div>`;
  // Intel > By phase: the strip of phases is one row that scrolls sideways; keep the chosen phase in view
  const strip = document.getElementById('phase-strip'), chosen = strip?.querySelector('.chip.on');
  if (chosen) strip.scrollLeft = Math.max(0, chosen.offsetLeft - strip.offsetLeft - (strip.clientWidth - chosen.offsetWidth) / 2);
  renderResultViews();
  renderSheet();
  if (state.view === 'board') boardAfterRender();
  if (state.view === 'mission' || (state.view === 'intel' && a && b)) missionAfterRender();
  syncWake();
}

// ---- Intel: enemy cheat sheet

function intelSide() {
  // the datasheets are an enemy cheat sheet; "By phase" is first of all for your own army
  let side = state.intelSide ?? (state.intelMode === 'phase' ? (state.mission?.me ?? 'A') : other(state.side));
  if (!state.armies[side]) side = other(side);
  return side;
}

// ---- Intel > By phase: what the army does in each phase, with ticks for once-per-battle rules

const SHEETS = new WeakMap();      // army.units (replaced when attachments change) -> sheet
function sheetOf(army) {
  let s = SHEETS.get(army.units);
  if (!s) { s = phaseSheet(phaseSheetInput(army)); SHEETS.set(army.units, s); }
  return s;
}
const usedOnce = (side) => state.mission?.game?.once?.[side] ?? {};

/** "Scout Squad ×2, Grey Hunters" */
function sheetUnits(e) {
  if (e.all) return 'all units';
  const n = new Map();
  for (const u of e.units) { const k = u.name.replace(/ \(\d+\)$/, ''); n.set(k, (n.get(k) ?? 0) + 1); }
  return [...n].map(([k, c]) => (c > 1 ? `${k} ×${c}` : k)).join(', ');
}
function tickChips(e, side) {
  const used = usedOnce(side);
  return `<div class="chips ticks">${ticksOf(e).map(t => `<button class="chip tick ${used[t.id] ? 'on' : ''}" data-action="mission-once" data-side="${side}" data-tick="${esc(t.id)}" aria-pressed="${used[t.id] ? 'true' : 'false'}">${esc(t.label || 'Used')}</button>`).join('')}</div>`;
}
function sheetEntry(e, side) {
  const once = e.usage?.per === 'battle';
  const tags = `${e.kind === 'army' ? `<span class="tag">${e.armyRule ? 'army rule' : e.key.startsWith('det:') ? 'detachment rule' : 'army'}</span>` : e.kind === 'core' ? '<span class="tag">core</span>' : ''}${e.usage ? `<span class="tag ${once ? 'auto' : ''}">${esc(usageLabel(e.usage))}</span>` : ''}`;
  if (e.kind === 'stratagem') {
    return `<div class="ability sheet-entry" data-entry="${esc(e.key)}"><b>${esc(e.name)}</b> <span class="muted tiny">${e.cp}CP · ${esc(e.turn || '')} · ${esc(e.phaseText)} · ${esc(e.detachment || '')}</span>${tags}
      <div class="muted">${e.missing ? 'No 11th edition text in the rules data.' : `<b>When:</b> ${esc(e.when)}<br><b>Target:</b> ${esc(e.target)}<br><b>Effect:</b> ${esc(e.effect)}`}</div>${once ? tickChips(e, side) : ''}</div>`;
  }
  const units = sheetUnits(e);
  return `<div class="ability sheet-entry" data-entry="${esc(e.key)}"><b>${esc(e.name)}</b> ${tags}${units ? ` <span class="muted tiny">${esc(units)}</span>` : ''}
    <div class="muted ruletext">${esc(e.raw)}</div>${e.by === 'data' ? '<div class="tiny muted">The rule’s words do not name a phase: this one comes from the rules data (provisional).</div>' : ''}${once ? tickChips(e, side) : ''}</div>`;
}
function phaseSheetHtml(side) {
  const army = state.armies[side];
  const sheet = sheetOf(army);
  const used = usedOnce(side);
  const shown = sheet.phases.some(p => p.id === state.intelPhase) ? state.intelPhase : 'all';
  const ticks = sheet.once.flatMap(e => ticksOf(e));
  const left = ticks.filter(t => !used[t.id]).length;
  const strip = `<div class="chips" id="phase-strip">${[{ id: 'all', short: 'All', n: sheet.count }, ...sheet.phases.map(p => ({ id: p.id, short: p.short, n: p.entries.length }))].map(p =>
    `<button class="chip nocheck ${p.id === shown ? 'on' : ''}" data-action="intel-phase" data-value="${p.id}" aria-pressed="${p.id === shown}" ${p.n ? '' : 'disabled'}>${esc(p.short)} <span class="muted">${p.n}</span></button>`).join('')}</div>`;
  const card = (p) => {
    const rules = p.entries.filter(e => e.kind !== 'stratagem'), strats = p.entries.filter(e => e.kind === 'stratagem');
    if (!p.entries.length) return '';
    return `<div class="card phase-card" data-phase="${p.id}" style="margin-top:10px"><div class="title">${esc(p.name)} <span class="muted small">· ${p.entries.length}</span></div>
      ${p.hint ? `<div class="muted tiny">${esc(p.hint)}</div>` : ''}
      ${rules.map(e => sheetEntry(e, side)).join('')}
      ${strats.length ? `<details class="more" ${shown === 'all' ? '' : 'open'}><summary>Stratagems (${strats.length})</summary>${strats.map(e => sheetEntry(e, side)).join('')}</details>` : ''}</div>`;
  };
  return `<section class="section" id="phase-sheet"><div class="card">
      <div class="title">${esc(army.faction)}, phase by phase</div>
      <div class="muted small">${sheet.count} rules of this list: army and detachment rules, abilities, core abilities and stratagems, by the phase they are used in. The phase is read from each rule’s own words.</div>
      ${sheet.once.length ? `<div class="modrow" id="once-card" style="margin-top:10px"><div class="lab">Once per battle · <b id="once-left">${left} of ${ticks.length}</b> left · tap when used</div>
        ${sheet.once.map(e => `<div class="once-row" data-entry="${esc(e.key)}"><b>${esc(e.name)}</b>${tickChips(e, side)}</div>`).join('')}
        ${left < ticks.length ? `<button class="btn ghost" data-action="mission-once-reset" data-side="${side}" id="once-reset">New battle: clear the ticks</button>` : ''}</div>` : ''}
    </div></section>
    <section class="section">${strip}${sheet.phases.filter(p => shown === 'all' || p.id === shown).map(card).join('')}</section>`;
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
  const phaseMode = state.intelMode === 'phase';
  return `<section class="section" id="intel-mode">${seg('intel-mode', state.intelMode, [['units', 'Datasheets'], ['phase', 'By phase']])}</section>
    ${tableMode() ? '<p class="hint" id="intel-table-note">Table mode: datasheets, abilities and stratagems only.</p>' : state.armies.A && state.armies.B && !phaseMode ? `<section class="section"><div id="brief-host">${briefHtml()}</div></section>` : ''}
    <section class="section">
      ${state.armies.A && state.armies.B ? seg('intel-side', side, [['A', `A · ${state.armies.A.faction}`], ['B', `B · ${state.armies.B.faction}`]]) : ''}
    </section>
    ${phaseMode ? phaseSheetHtml(side) : `<section class="section"><div class="card">
      <div class="title">${esc(ai.faction)}</div>
      <div class="muted small">${esc(ai.detachments.join(', ') || 'No detachment found')} · ${army.units.length} units</div>
      ${ai.armyRules.length ? `<details class="more" id="intel-army-rule"><summary>Army rule${ai.armyRules.length > 1 ? 's' : ''}: ${esc(ai.armyRules.map(d => d.name).join(', '))}</summary>${ai.armyRules.map(d =>
        `<div class="ability"><b>${esc(d.name)}</b><div class="muted ruletext">${esc(d.text)}</div></div>`).join('')}</details>` : ''}
      ${ai.detachmentRules.length ? `<details class="more"><summary>Detachment rule${ai.detachmentRules.length > 1 ? 's' : ''}</summary>${ai.detachmentRules.map(d =>
        `<div class="ability"><b>${esc(d.name)}</b><div class="muted">${esc(d.text)}</div></div>`).join('')}</details>` : ''}
      <details class="more"><summary>Stratagems (${ai.stratagems.length})</summary>${stratHtml || '<div class="muted small">None found for these detachments.</div>'}</details>
    </div></section>
    <section class="section"><h2>Units</h2>
      <input class="sel" type="search" data-input="intel-search" placeholder="Search units, keywords, abilities…" value="${esc(state.intelQuery)}" aria-label="Search units">
      <div id="intel-list" class="intel-grid">${intelList(side)}</div>
    </section>`}`;
}

function intelList(side) {
  const army = state.armies[side];
  const q = state.intelQuery.trim().toLowerCase();
  const cards = [];
  const { prov, pts } = armyData(army);
  for (const cu of army.units) {
    const it = unitIntel(cu, army);
    const stamps = [...new Map(prov.units.filter(u => u.unit === cu.key).map(u => [`${u.label}|${u.date}`, u])).values()];
    const off = pts.mismatches.filter(m => m.unit === cu.key);
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
      <div class="tiny muted" data-stamp="${esc(cu.key)}">Rules data: ${stamps.map(u => `${esc(u.label)}, ${fmtDataDate(u.date)}${u.note ? ` (${esc(u.note)})` : ''}`).join(' · ')}.${off.length ? ` <span class="tag warn">⚠ ${off.map(m => `${esc(m.name)}: ${m.list} pts in your list, ${orList(m.data)} in the data`).join('; ')} — check this datasheet</span>` : ''}</div>
      ${state.armies.A && state.armies.B && !tableMode() ? `<div class="row" style="gap:6px">
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
      ${army ? dataStampHtml(side, army) : ''}
      ${army ? attachOverview(side, army) : ''}
      ${army ? `<details class="more"><summary>${army.units.length} units${army.warnings.length ? ` · ${army.warnings.length} import notes` : ''}</summary>
        ${army.units.map(u => `<div class="ability"><b>${esc(u.name)}</b> <span class="muted">· ${u.models} models</span></div>`).join('')}
        ${army.warnings.map(w => `<div class="tiny muted">• ${esc(w)}</div>`).join('')}
      </details>` : ''}
    </div></section>`;
  };
  const ready = state.armies.A && state.armies.B;
  return `<div class="lay2"><div class="col">${panel('A')}</div><div class="col">${panel('B')}</div></div>
    <button class="btn primary block" data-action="view" data-value="attack" ${ready ? '' : 'disabled'}>${ready ? 'Start calculating →' : 'Load both armies to start'}</button>
    ${eventCard()}
    ${backupCard()}
    <p class="hint" id="data-footer">Lists stay on this device. Works offline once loaded. App version ${esc(CALC_VERSION)} · 11th edition rules · rules data: 40kdc ${esc(DATASET_VERSION)} with codex datasheets${ERRATA_RESULT.points || ERRATA_RESULT.weapons ? ` and the points and weapon profiles of ${esc(ERRATA_RESULT.from)}` : ''}, newest ${fmtDataDate(dataNewest())}. Rules changed after the date shown for an army are not in the numbers.
      <br><span id="data-credit">Powered by <a href="https://40kdc.alpacasoft.dev" target="_blank" rel="noopener">40kdc-data</a> (Alpaca Software and the 40kdc community, CC BY 4.0).</span></p>`;
}

// ---- how current the rules data behind an army is (adapter.mjs armyData)
const orList = (xs) => (xs.length > 1 ? `${xs.slice(0, -1).join(', ')} or ${xs[xs.length - 1]}` : String(xs[0]));
function dataStampHtml(side, army) {
  const { prov, pts } = armyData(army);
  const n = prov.units.length;
  const groups = prov.groups.map(g => `${prov.groups.length > 1 ? `${g.count} ` : ''}${esc(g.label)}, ${fmtDataDate(g.date)}${g.note ? ` (${esc(g.note)})` : ''}`).join(' · ');
  const bad = pts.mismatches;
  const points = !pts.checked ? '<div class="muted">Points: the list gives no points to check.</div>'
    : !bad.length ? `<div class="ok" id="points-${side}">✓ Points: ${pts.checked === n ? `all ${n}` : `${pts.checked} of ${n}`} datasheets cost what the rules data says${pts.checked === n ? '' : ' (the others cannot be checked)'}.</div>`
      : `<div class="warn" id="points-${side}">⚠ Points: ${bad.length} of ${pts.checked} datasheets cost something else in your list than in the rules data —
          ${bad.map(m => `<b>${esc(m.name)}</b> ${m.list} (data ${orList(m.data)})`).join(', ')}.
          Points change when the rules change, so these datasheets may be out of date (or the list was written by hand): check them against your codex before you trust their numbers.</div>`;
  return `<div class="small datastamp" id="data-${side}" style="margin-top:8px"><div><b>Rules data:</b> ${groups}${prov.groups.length === 1 && n > 1 ? ` — all ${n} datasheets` : ''}.</div>${points}</div>`;
}

// ---- backup / restore / move to another device (backup.mjs)
function backupCard() {
  let last = null, undo = false;
  try { last = localStorage.getItem(LAST_KEY); undo = !!localStorage.getItem(UNDO_KEY); } catch { /* private mode */ }
  const t = state.transfer;
  return `<details class="more card" style="margin-top:12px" data-details="backup" ${state.openBackup ? 'open' : ''} id="backup-card"><summary>Backup and other devices</summary>
    <p class="small muted" style="margin:6px 0">Lists, plans and games are kept on this device only. Save a backup file to keep a copy, or send everything to your tablet or phone with a code.${last ? ` Last backup: ${esc(new Date(last).toLocaleString())}.` : ' No backup made yet.'}${state.persisted === true ? ' The browser has agreed to keep this data.' : ''}</p>
    <div class="row" style="gap:6px;flex-wrap:wrap">
      <button class="btn grow" data-action="backup-save">⬇ Save a backup file</button>
      <label class="btn grow" style="cursor:pointer;display:flex;align-items:center;justify-content:center">⬆ Restore from a file<input type="file" accept="application/json,.json" data-input="backup-file" hidden></label>
    </div>
    <button class="btn block" style="margin-top:8px" data-action="backup-send">📲 Send to another device (gives a code)</button>
    <div class="row" style="gap:6px;margin-top:8px"><input class="sel grow" id="backup-code" autocapitalize="characters" autocomplete="off" spellcheck="false" maxlength="8" placeholder="Code from the other device" aria-label="Transfer code">
      <button class="btn" data-action="backup-receive">Get</button></div>
    ${t ? `<div class="warnbox" id="backup-code-out">Code: <b style="font-size:22px;letter-spacing:.14em">${esc(t.code)}</b><br>On the other device: Armies → Backup and other devices → type the code → Get. It works for ${Math.round(t.ttl / 60)} minutes.</div>` : ''}
    ${state.backupMsg ? `<div class="small" id="backup-msg" style="margin-top:6px">${esc(state.backupMsg)}</div>` : ''}
    ${undo ? '<button class="btn ghost" style="margin-top:8px" data-action="backup-undo">↩ Undo the last restore</button>' : ''}
    <div class="tiny muted" style="margin-top:6px">Table photos are not part of a backup. Restoring replaces what is on this device; the previous data is kept for one undo.</div>
  </details>`;
}
function backupNote(msg) {
  state.backupMsg = msg;
  state.openBackup = true;
  console.log(`[calc] backup: ${msg}`);
  if (state.view === 'armies') render();
}
function currentBackup() {
  persist();
  return makeBackup(localStorage, { version: CALC_VERSION });
}
async function saveBackupFile() {
  const b = currentBackup();
  const info = describeBackup(b);
  if (!info.ok) return backupNote('Nothing to back up yet: load a list first.');
  const name = backupFileName();
  const blob = new Blob([JSON.stringify(b)], { type: 'application/json' });
  try {
    const file = new File([blob], name, { type: 'application/json' });
    // phones / tablets: the share sheet (Drive, Files, Quick Share to the tablet, e-mail)
    if (navigator.canShare?.({ files: [file] }) && /Android|iPhone|iPad/i.test(navigator.userAgent)) {
      await navigator.share({ files: [file], title: 'Combat Calc backup' });
    } else {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = name;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    }
    try { localStorage.setItem(LAST_KEY, new Date().toISOString()); } catch { /* best effort */ }
    backupNote(`Backup saved as ${name}: ${info.summary}.`);
  } catch (err) {
    if (err?.name !== 'AbortError') backupNote(`Could not save the backup (${err?.message ?? err}).`);
  }
}
function restoreBackup(b, from) {
  const info = describeBackup(b);
  if (!info.ok) return backupNote(info.why);
  const when = info.exported ? new Date(info.exported).toLocaleString() : 'an unknown date';
  if (!window.confirm(`Replace everything on this device with the backup ${from} (made ${when})?\n\nIt holds: ${info.summary}.\n\nWhat is on this device now is kept for one undo.`)) return backupNote('Restore cancelled: nothing was changed.');
  try {
    applyBackup(localStorage, b);
    console.log(`[calc] backup restored ${from}: ${info.summary}`);
    location.reload();
  } catch (err) { backupNote(`Could not restore (${err?.message ?? err}).`); }
}
async function sendBackup() {
  const b = currentBackup();
  if (!describeBackup(b).ok) return backupNote('Nothing to send yet: load a list first.');
  backupNote('Sending…');
  try {
    const res = await fetch('/api/calc-transfer', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ data: b }) });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) return backupNote(`Could not send (${j.error ?? res.status}). A backup file works without a connection.`);
    state.transfer = { code: j.code, ttl: j.expires_in };
    backupNote(`Ready: ${describeBackup(b).summary}.`);
  } catch { backupNote('No connection to the server. Save a backup file instead and move the file.'); }
}
async function receiveBackup() {
  const code = normalizeCode(document.getElementById('backup-code')?.value);
  if (!CODE_RE.test(code)) return backupNote('A code is 6 letters and digits (no 0, O, 1, I or L).');
  backupNote('Looking for the backup…');
  try {
    const res = await fetch(`/api/calc-transfer/${code}`);
    const j = await res.json().catch(() => ({}));
    if (!res.ok) return backupNote(j.error ?? `Could not get the backup (${res.status}).`);
    restoreBackup(j.data, `with code ${code}`);
  } catch { backupNote('No connection to the server.'); }
}

function attackView() {
  const s = setup();
  const atk = atkArmy(), def = defArmy();
  const tinfo = targetInfo();
  return `<div class="lay2 attack"><div class="col">
    <section class="section">
      ${seg('phase', state.phase, [['shooting', 'Shooting'], ['fight', 'Fight']])}
      <div class="card matchup" style="margin-top:10px">
        <div class="side"><div class="lbl">Attacker · ${state.side}</div><div class="nm">${esc(atk.faction)}</div></div>
        <button class="icon-btn" data-action="swap" aria-label="Swap attacker and defender">⇄</button>
        <div class="side right"><div class="lbl">Defender · ${other(state.side)}</div><div class="nm">${esc(def.faction)}</div></div>
      </div>
      <div class="row" style="margin-top:8px;gap:6px">
        <button class="btn ghost grow" data-action="open-charge">🎲 Charge</button>
        <button class="btn ghost grow" data-action="open-chain">⚡ Turn</button>
        <button class="btn ghost grow" data-action="open-grid">📊 Grid</button>
        <button class="btn ghost grow" data-action="open-saved">💾 Saved${state.saved.length ? ` (${state.saved.length})` : ''}</button>
      </div>
    </section>
    <section class="section"><h2>Target</h2>${targetCard(tinfo, s)}</section>
    <section class="section"><h2>Attacking units${s.attackers.length > 1 ? ' · resolved in order' : ''}</h2>
      ${s.attackers.map((e, i) => attackerCard(e, i, tinfo)).join('')}
      <button class="btn block" style="margin-top:10px" data-action="open-add">＋ Add attacking unit</button>
    </section></div>
    ${wide() ? '<aside class="col pane" id="attack-pane" aria-label="Result"></aside>' : ''}</div>`;
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
      ${state.phase === 'shooting' && (profile.keywords ?? []).some(k => /^(MONSTER|VEHICLE)$/i.test(k)) ? `<div class="modrow"><div class="lab">Engaged Monster / Vehicle (17.03): −1 to hit for shooting at it, no Blast</div><div class="chips">${chip('defmod-toggle', !!m.engaged, 'Engaged in melee', 'data-key="engaged"')}</div></div>` : ''}
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

// How a weapon row that is a choice (several profiles, one melee weapon per model, sidearm or main weapon)
// got its count: chosen by the app (with what it was compared on) or set by hand.
function choiceTag(r) {
  if (r.fam == null || r.blocked) return '';
  if (r.manual) return '<span class="tag byhand">set by hand</span>';
  return r.full > 0 ? '<span class="tag auto" title="Chosen by the app: the best legal option against this target, with this unit\'s rules and situation">✓ auto: best here</span>' : '';
}
function choiceWhy(r) {
  const n = r.note;
  if (r.fam == null || r.blocked || r.manual || !n) return '';
  if (!n.sim) return r.full > 0 ? '' : '<div class="tiny muted choice-why">Not used: another option is at least as good in every way</div>';
  const haz = n.hazard > 0.005 ? `, after ${fx(n.hazard)} of your own expected from Hazardous` : '';
  return `<div class="tiny muted choice-why">${r.full > 0 ? 'Used' : 'Not used'}: about ${fx(n.net)} wounds here if all ${r.max > 1 ? `${r.max} ` : ''}attack with it${haz}</div>`;
}

// Under the weapons of an attacker: what "auto" means (once, when the unit has a choice), the way back to
// it after a change by hand, and a warning for a set-up the rules do not allow.
function choiceFoot(e, rows, problem) {
  const hasChoice = rows.some(r => r.fam != null);
  const byHand = rows.some(r => r.manual);
  const both = problem && overSidearms(problem, Object.fromEntries(rows.map(r => [r.id, r.full])));
  if (!hasChoice && !byHand) return '';
  const inContext = rows.some(r => r.note?.inContext && !r.manual);
  return `<div class="choice-foot tiny muted">${hasChoice ? 'Where a model must choose (one profile of a weapon, one melee weapon, its close-quarters weapons or its other weapons) the app uses the option that removes the most wounds from this target. Change a count to choose yourself.' : ''}
    ${inContext ? ' <span class="choice-ctx">This unit is likely to destroy the target, so the choice was checked with all its attacks together: damage that is not needed does not count.</span>' : ''}
    ${byHand ? ` <button class="linkish" data-action="count-auto" data-uid="${e.uid}">↺ Let the app choose again</button>` : ''}
    ${both ? '<div class="warn" style="color:var(--warn-ink)">⚠ A model shoots its close-quarters weapons or its other ranged weapons, not both (24.07).</div>' : ''}</div>`;
}

// 15.01: "Each player cannot use the same stratagem more than once in the same phase" and "cannot target the
// same unit with more than one stratagem in the same phase". The options of one stratagem share a key.
const stratKey = (r) => r.group ?? String(r.id).replace(/:alt\d+$/, '');
const defStratKey = (id) => String(id).split(':').slice(0, 2).join(':');

function attackerCard(e, i, tinfo) {
  const { cu, rows, problem } = rowsFor(e, tinfo);
  if (!cu) return '';
  const m = e.mods ?? {};
  const shooting = state.phase === 'shooting';
  const hasIndirect = rows.some(r => r.kw.indirect);
  const weapons = rows.length ? rows.map(r => {
    const unsupported = r.unsupported.length ? r.unsupported.map(t => `<span class="tag warn" title="Not modelled by the calculator">${esc(t)} ⚠</span>`).join('') : '';
    // an ability limited to other targets is shown struck through (24.01)
    const tags = r.tags.filter(t => !r.unsupported.includes(t)).map(t => (r.tagsOff?.includes(t)
      ? `<span class="tag off" title="Does not apply against this target (24.01)">${esc(t)}</span>` : `<span class="tag">${esc(t)}</span>`)).join('');
    return `<div class="weapon ${r.count ? '' : 'off'}" data-row="${esc(r.id)}"${r.fam != null ? ` data-fam="${esc(r.fam)}"` : ''}>
      <div class="grow"><div class="wname">${esc(r.label)}</div>
        <div class="wstats">${esc(r.range)} · ${esc(r.stats)}</div>
        <div>${tags}${unsupported}${r.blocked ? `<span class="tag warn">${esc(r.blocked)}</span>` : ''}${choiceTag(r)}</div>${choiceWhy(r)}</div>
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
  const flags = coreFlags(cu);
  const shootType = m.shootingType ?? 'normal';
  const hasHeavy = rows.some(r => r.kw.heavy);
  const sit = [
    shooting && chip('amod-toggle', !!m.halfRange, 'Half range', `data-uid="${e.uid}" data-key="halfRange"`),
    chip('amod-toggle', !!m.charged, 'Charged', `data-uid="${e.uid}" data-key="charged"`),
    shooting && shootType === 'normal' && chip('amod-toggle', !!m.stationary, 'Stationary', `data-uid="${e.uid}" data-key="stationary"`),
    // 24.16 Heavy: +1 to hit when unengaged, not set up this turn and no model moved more than 3"
    shooting && shootType === 'normal' && hasHeavy && !m.stationary && chip('amod-toggle', !!m.heavyOk, 'Moved 3" or less (Heavy: +1 to hit)', `data-uid="${e.uid}" data-key="heavyOk" title="Heavy (24.16): +1 to hit when this unit is unengaged, was not set up this turn, and no model moved more than 3 inches."`),
    // 24.39 Damaged X: -1 to hit at X wounds or fewer
    flags.damaged && chip('amod-toggle', !!m.damaged, `Damaged (${flags.damaged} wounds or fewer left): −1 to hit`, `data-uid="${e.uid}" data-key="damaged"`),
    shooting && chip('amod-toggle', !!m.overwatch, 'Snap shooting', `data-uid="${e.uid}" data-key="overwatch"`),
    // 22.05: from a terrain section 3"+ high (or TOWERING within 12") at models on ground level
    shooting && chip('amod-toggle', !!m.plunging, 'Plunging fire (+1 BS)', `data-uid="${e.uid}" data-key="plunging" title="Plunging Fire: this unit shoots from a terrain section 3 inches or more high (or is TOWERING within 12 inches) at a unit with models on ground level. BS improves by 1."`),
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
    ${stratRules.length ? `<div class="modrow" style="margin-top:10px"><div class="lab">Stratagems (tap to use)</div><div class="chips">${stratRules.map(ruleChip).join('')}</div>
      <div class="rule-note${new Set(stratRules.filter(r => on.has(r.id)).map(stratKey)).size > 1 ? ' warn' : ''}" data-strat-note>One stratagem on a unit in a phase, and each stratagem once in a phase (15.01).${new Set(stratRules.filter(r => on.has(r.id)).map(stratKey)).size > 1 ? ' ⚠ More than one is on for this unit.' : ''}</div></div>` : ''}
    ${stratTextInPhase.length ? `<details class="more"><summary>Other stratagems — set by hand (${stratTextInPhase.length})</summary>${stratTextInPhase.map(st =>
      `<div class="ability"><b>${esc(st.name)}</b> <span class="muted tiny">${st.cp}CP · ${esc(st.detachment)}</span><div class="muted">${st.missing ? 'No 11e text in the dataset.' : esc(`${st.when} — ${st.effect}`)}</div></div>`).join('')}</details>` : ''}` : '';
  return `<div class="card" data-attacker="${e.uid}">
    <div class="attacker-head"><div class="num">${i + 1}</div>
      <div class="grow"><div class="title ellipsis">${esc(cu.name)}</div><div class="muted tiny">${cu.models} models</div></div>
      ${i > 0 ? `<button class="icon-btn" data-action="move-up" ${sc} aria-label="Resolve earlier">↑</button>` : ''}
      <button class="icon-btn" data-action="remove" ${sc} aria-label="Remove">✕</button></div>
    ${attachRow(state.side, cu)}
    ${shooting ? `<div class="modrow" style="margin-top:6px"><div class="lab tiny muted">This unit ${shootType === 'assault' ? 'advanced: only Assault weapons shoot (10.05)' : shootType === 'cq' ? 'is engaged: close-quarters weapons only, Monsters and Vehicles excepted (10.06)' : 'did not advance and is not engaged'}</div>
      ${seg('shooting-type', shootType, [['normal', 'Normal'], ['assault', 'Advanced'], ['cq', 'Engaged']], `compact" data-uid="${e.uid}`)}</div>` : ''}
    <div style="margin-top:6px">${weapons}</div>
    ${choiceFoot(e, rows, problem)}
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
  // wide screens: the full result sits beside the set-up instead of a bar + sheet
  const pane = document.getElementById('attack-pane');
  if (pane) {
    bar.innerHTML = '';
    pane.className = `col pane ${state.busy ? 'busy' : ''}`;
    pane.innerHTML = r && !state.calcError ? resultsSheet() : `<div class="card">${inner}</div>`;
    if (r) wireChart();
    return;
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
    : state.sheet === 'chain' ? chainSheet()
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
  const defender = buildDefender(profile, enabledRules(profile, { ruleOverrides: {} }), phase, {}, {});
  const tinfo = { cu: defCu, profile, summary: defenderSummary(profile), defender };
  const entry = { unitKey: atkCu.key, counts: {}, mods: {} };
  // the weapon choice is left to the worker (choose.mjs resolveScenario): hundreds of matchups, none on the page's thread
  const { rows, problem } = rowsFor(entry, tinfo, atkArmyObj, phase, { defer: true });
  if (!rows.some(r => r.usable !== false && r.max > 0)) return null;
  const { rules, on } = rulesFor(entry, atkCu, tinfo, atkArmyObj, phase);
  const attacker = buildAttacker(atkCu, rows, {}, rules, on, phase);
  if (problem && decisions(problem).length) attacker.choice = { groups: problem.groups, rows: problem.rows, shooting: problem.shooting, target: problem.target };
  else if (!attacker.weapons.length) return null;
  return { phase, attackers: [attacker], defender, seed: 99 };
}
// Unit-vs-unit odds for the Mission tab's board plans: P(target destroyed)
// when one unit shoots / fights another, default rules, a quick batch run.
let pairWorker = null, pairReq = 0;
function pairOdds(jobs) {
  return new Promise((resolve) => {
    const items = [];
    for (const j of jobs) {
      const A = state.armies[j.atkSide], D = state.armies[other(j.atkSide)];
      const ac = A?.units.find(u => u.key === j.atkKey), dc = D?.units.find(u => u.key === j.defKey);
      const sc = ac && dc ? defaultScenarioFor(A, D, ac, dc, j.phase) : null;
      if (sc) items.push({ key: j.key, scenario: sc });
    }
    const res = {};
    const id = ++pairReq;
    if (!items.length) { resolve(res); return; }
    pairWorker ??= new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    pairWorker.onmessage = (ev) => {
      if (ev.data.id !== id) return;
      if (ev.data.done) { console.log(`[calc] unit-vs-unit odds: ${Object.keys(res).length} pairs`); resolve(res); } else if (ev.data.result) res[ev.data.key] = ev.data.result;
    };
    pairWorker.postMessage({ id, batch: items, trials: 400 });
  });
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

// ---- Turn chain: this side's shooting into the target, then one unit charges it and fights

// a scenario for another phase / setup than the one on screen (the builders read state.phase + setup())
function scenarioFor(phase, tempSetup = null) {
  const savedPhase = state.phase, key = `${state.side}:${phase}`, savedSetup = state.setups[key];
  state.phase = phase;
  if (tempSetup) state.setups[key] = tempSetup;
  try { return scenario(); } finally {
    state.phase = savedPhase;
    if (tempSetup) { if (savedSetup) state.setups[key] = savedSetup; else delete state.setups[key]; }
  }
}

function chainChargers() {
  return (atkArmy()?.units ?? []).filter(cu => attackerRows(cu, 'fight', null).length > 0);
}

function chainInputs() {
  const shootKey = `${state.side}:shooting`;
  const ss = state.setups[shootKey] ?? { targetKey: null, attackers: [] };
  const c = state.chain;
  const targetKey = ss.targetKey ?? setup().targetKey;
  if (!targetKey || !c?.chargerKey) return null;
  const fightKey = `${state.side}:fight`;
  const fs = state.setups[fightKey] ?? {};
  const prev = (fs.attackers ?? []).find(e => e.unitKey === c.chargerKey);
  const entry = { ...(prev ?? { uid: -1, unitKey: c.chargerKey, counts: {} }), mods: { ...(prev?.mods ?? {}), charged: true } };
  const fightSetup = {
    targetKey, attackers: [entry], ruleOverrides: fs.ruleOverrides ?? {}, defManual: { ...(fs.defManual ?? {}) },
    defOverrides: ss.defOverrides ?? {},
  };
  const shoot = ss.targetKey === targetKey && ss.attackers?.length ? scenarioFor('shooting', { ...ss, ruleOverrides: ss.ruleOverrides ?? {}, defManual: ss.defManual ?? {}, defOverrides: ss.defOverrides ?? {} }) : null;
  const fight = scenarioFor('fight', fightSetup);
  if (!fight) return null;
  // what the turn costs the charging unit: the target fights back (always, unless switched off), the
  // enemy may Fire Overwatch at it (1CP, its choice), and a destroyed target may have Deadly Demise
  const tgtCu = defArmy()?.units.find(u => u.key === targetKey), chCu = atkArmy()?.units.find(u => u.key === c.chargerKey);
  let back = null, overwatch = null, demise = null;
  if (tgtCu && chCu) {
    if (c.back !== false) back = defaultScenarioFor(defArmy(), atkArmy(), tgtCu, chCu, 'fight');
    if (c.overwatch) {
      overwatch = defaultScenarioFor(defArmy(), atkArmy(), tgtCu, chCu, 'shooting');
      if (overwatch) overwatch.attackers[0].mods = { ...overwatch.attackers[0].mods, overwatch: true };     // snap shooting (15.09)
    }
    demise = coreFlags(tgtCu).deadlyDemise;
  }
  return { shoot, fight, back, overwatch, demise: back || overwatch ? demise : null, charge: { gap: c.gap, mod: c.mod, reroll: c.reroll }, seed: 4242 };
}

let chainWorker = null, chainReq = 0;
function runChain() {
  const inp = chainInputs();
  chainReq++;
  state.chainResult = null;
  if (!inp) { state.chainBusy = false; return; }
  if (chainWorker && state.chainBusy) { chainWorker.terminate(); chainWorker = null; }
  if (!chainWorker) {
    chainWorker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    chainWorker.onmessage = (ev) => {
      if (ev.data.id !== chainReq) return;
      state.chainBusy = false;
      if (ev.data.error) console.error('[calc] chain error', ev.data.error);
      state.chainResult = ev.data.result ?? null;
      console.log(`[calc] turn chain: shoot ${state.chainResult?.meanShoot?.toFixed(2)} + fight ${state.chainResult?.meanFight?.toFixed(2)}, charge ${state.chainResult?.pChargeGivenSurvive?.toFixed(3)}, destroyed ${state.chainResult?.pWipe?.toFixed(3)}`);
      if (state.sheet === 'chain') renderSheet();
    };
  }
  state.chainBusy = true;
  chainWorker.postMessage({ id: chainReq, chain: inp, trials: 20000 });
}

function openChain(opts = {}) {
  const ss = state.setups[`${state.side}:shooting`];
  const chargers = chainChargers();
  const prefer = opts.chargerKey ?? state.chain?.chargerKey;
  const fromShoot = (ss?.attackers ?? []).map(e => e.unitKey).find(k => chargers.some(cu => cu.key === k));
  const chargerKey = chargers.some(cu => cu.key === prefer) ? prefer : (fromShoot ?? chargers[0]?.key ?? null);
  const entry = (ss?.attackers ?? []).find(e => e.unitKey === chargerKey);
  state.chain = { mod: 0, reroll: false, ...(state.chain ?? {}), chargerKey, gap: opts.gap ?? entry?.mods?.distance ?? state.chain?.gap ?? 6 };
  state.sheet = 'chain';
  runChain();
  renderSheet();
}

function chainSheet() {
  const c = state.chain ?? {};
  const r = state.chainResult;
  const ss = state.setups[`${state.side}:shooting`];
  const tgt = defArmy()?.units.find(u => u.key === (ss?.targetKey ?? setup().targetKey));
  const shooters = (ss?.targetKey === tgt?.key ? ss?.attackers ?? [] : []).map(e => atkArmy()?.units.find(u => u.key === e.unitKey)?.name).filter(Boolean);
  const chargers = chainChargers();
  const need = chargeRollNeeded(c.gap ?? 0);
  let body;
  if (!tgt) body = '<p class="hint">Pick a target on the Attack tab (Shooting) first.</p>';
  else if (!chargers.length) body = '<p class="hint">No unit in this army has melee weapons.</p>';
  else if (!r) body = `<p class="muted small">${state.chainBusy ? 'Simulating…' : 'Nothing to simulate.'}</p>`;
  else {
    const d = { mode: 'models', exact: r.kills, atLeast: r.killsAtLeast, full: r.totalModels };
    let last = d.exact.length - 1;
    while (last > 0 && d.exact[last] < 0.0005) last--;
    const dd = { ...d, exact: d.exact.slice(0, last + 1), atLeast: d.atLeast.slice(0, last + 1) };
    body = `<div class="hero">
        <div class="cell"><b id="chain-total">${fx(r.meanKills)}</b><span>avg models destroyed this turn of ${r.totalModels}</span></div>
        <div class="cell"><b id="chain-wipe">${pct(r.pWipe)}</b><span>chance it is destroyed this turn</span></div>
        <div class="cell"><b id="chain-charge">${pct(r.pChargeGivenSurvive)}</b><span id="chain-need">${need > CHARGE_MAX ? `more than ${CHARGE_MAX}": cannot be charged` : `charge lands (${need}+ on 2D6${c.mod ? `, ${fmtMod(c.mod)}` : ''}${c.reroll ? ', re-roll' : ''})`}</span></div>
      </div>
      <div class="pipeline" style="margin-top:8px">
        <div><b>${fx(r.meanShoot)}</b><span>Shooting kills</span></div>
        <div><b>${pct(r.pWipeShoot)}</b><span>Destroyed by shooting</span></div>
        <div><b>${fx(r.meanFight)}</b><span>Fight kills (avg over all turns)</span></div>
        <div><b>${fx(r.meanKills)}</b><span>Total</span></div>
      </div>
      ${chainOwnHtml(r, c, tgt)}
      ${shockHtml('the target is', shockOdds(tgt, { alive: r.totalModels, lostAtLeast: r.killsAtLeast, pWipe: r.pWipe }), 'chain-shock-target')}
      <div class="section"><h2>Chance of exactly N models destroyed this turn</h2><div class="chart">${chartSvg(dd)}</div></div>
      <table class="dist"><thead><tr><th>Models</th><th>Exactly</th><th>At least</th></tr></thead><tbody>
      ${dd.exact.map((p, k) => ({ k, p, ge: dd.atLeast[k] })).filter(x => x.p >= 0.005 || (x.ge >= 0.005 && x.ge < 0.995)).map(x => `<tr><td>${x.k}</td><td>${pct(x.p)}</td><td>${pct(x.ge)}</td></tr>`).join('')}</tbody></table>`;
  }
  return `<div class="row"><h3 class="grow">⚡ Shoot → Charge → Fight</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="small">Target: <b>${esc(tgt?.name ?? '—')}</b> · Shooting: <b>${shooters.length ? shooters.map(esc).join(', ') : 'none'}</b></div>
    <div class="tiny muted">Shooting uses the units, weapons and rules set on the Attack tab (Shooting). The charger's fight uses its Fight setup, with "charged this turn" on.</div>
    ${chargers.length ? `<div class="modrow" style="margin-top:8px"><div class="lab">Charging unit</div>
      <select class="sel" data-input="chain-charger" aria-label="Charging unit">${chargers.map(cu => `<option value="${esc(cu.key)}" ${cu.key === c.chargerKey ? 'selected' : ''}>${esc(cu.name)}</option>`).join('')}</select></div>
    <div class="weapon" style="border-top:0"><div class="grow"><div class="wname">Charge distance</div><div class="wstats">closest bases after shooting, in inches</div></div>
      <div class="stepper"><button data-action="chain-gap" data-delta="-0.5" aria-label="Shorter">−</button><div class="val" id="chain-gap">${c.gap}"</div><button data-action="chain-gap" data-delta="0.5" aria-label="Longer">+</button></div></div>
    <div class="modrow"><div class="lab">Charge roll modifiers, added up</div>${seg('chain-mod', c.mod ?? 0, CHARGE_MODS, 'compact')}</div>
    <div class="chips" style="margin-top:6px">${chip('chain-reroll', !!c.reroll, 'Re-roll the charge')}</div>
    <div class="modrow" style="margin-top:8px"><div class="lab">What the enemy does</div><div class="chips">
      ${chip('chain-back', c.back !== false, 'The target fights back')}
      ${chip('chain-overwatch', !!c.overwatch, 'It fires Overwatch at the charging unit (1CP)')}</div></div>` : ''}
    <div style="margin-top:10px">${body}</div>
    <p class="hint">Casualties and a damaged model carry from the shooting into the fight; a unit destroyed by shooting can't be charged. The enemy's attacks use its default weapons and always-on rules against your unit at full strength. Overwatch (15.08) comes at the end of your Movement phase, before your shooting; your unit fights first because it charged (12.04).</p>`;
}

// The other side of the exchange: what the turn costs the charging unit.
function chainOwnHtml(r, c, tgt) {
  const o = r.own;
  if (!o) return '';
  const ch = atkArmy()?.units.find(u => u.key === c.chargerKey);
  const dd = coreFlags(tgt).deadlyDemise;
  const parts = [
    c.overwatch ? `<div><b id="chain-own-ow">${fx(o.meanOverwatch)}</b><span>Overwatch</span></div>` : '',
    c.back !== false ? `<div><b id="chain-own-back">${fx(o.meanBack)}</b><span>Fight back</span></div>` : '',
    dd ? `<div><b id="chain-own-dd">${fx(o.meanDemise, 2)}</b><span>Deadly Demise ${esc(dd)}</span></div>` : '',
    `<div><b>${fx(o.meanLost)}</b><span>Total</span></div>`,
  ].filter(Boolean).join('');
  const sh = ch ? shockOdds(ch, { alive: o.totalModels, lostAtLeast: o.lostAtLeast, pWipe: o.pWipe }) : null;
  return `<div class="section" id="chain-own"><h2>What it costs ${esc(ch?.name ?? 'your unit')}</h2>
    <div class="hero" style="grid-template-columns:1fr 1fr">
      <div class="cell"><b id="chain-own-lost">${fx(o.meanLost)}</b><span>avg models lost of ${o.totalModels}</span></div>
      <div class="cell"><b id="chain-own-wipe">${pct(o.pWipe)}</b><span>chance it is destroyed</span></div>
    </div>
    <div class="pipeline" style="margin-top:8px">${parts}</div>
    ${o.pStoppedByOverwatch > 0.005 ? `<div class="tiny muted">Overwatch destroys it before it charges ${pct(o.pStoppedByOverwatch)} of the time.</div>` : ''}
    ${o.meanPoints > 0 && r.meanPoints > 0 ? `<div class="small" id="chain-trade" style="margin-top:6px">Points: you destroy <b>${fx(r.meanPoints, 0)}</b> and lose <b>${fx(o.meanPoints, 0)}</b> on average.</div>` : ''}
    ${shockHtml('your unit is', sh, 'chain-shock-own')}
    ${coreFlags(tgt).fightsFirst ? '<div class="tiny muted">The target has Fights First. In your turn your charging unit is still selected first (12.04).</div>' : ''}
  </div>`;
}

/** Charge-roll modifiers add up (02.02.01: only hit and wound rolls are limited to ±1). */
const CHARGE_MODS = [[-2, '−2'], [-1, '−1'], [0, '0'], [1, '+1'], [2, '+2']];
const fmtMod = (m) => `${m > 0 ? '+' : '−'}${Math.abs(m)}`;

function chargeSheet() {
  const c = state.charge;
  const need = chargeRollNeeded(c.gap);
  const p = chargeOdds(need, { mod: c.mod, reroll: c.reroll });
  const rows = [];
  for (let g = 3; g <= CHARGE_MAX; g++) {
    const n = chargeRollNeeded(g);
    rows.push(`<tr ${Math.abs(g - c.gap) < 0.01 ? 'style="font-weight:700"' : ''}><td>${g}"</td><td>${n}+</td><td>${pct(chargeOdds(n, { mod: c.mod }))}</td><td>${pct(chargeOdds(n, { mod: c.mod, reroll: true }))}</td></tr>`);
  }
  rows.push(`<tr ${c.gap > CHARGE_MAX ? 'style="font-weight:700"' : ''}><td>over ${CHARGE_MAX}"</td><td>—</td><td colspan="2">cannot be charged</td></tr>`);
  return `<div class="row"><h3 class="grow">Charge odds</h3><button class="icon-btn" data-action="close-sheet" aria-label="Close">✕</button></div>
    <div class="weapon" style="border-top:0"><div class="grow"><div class="wname">Gap to the nearest target</div><div class="wstats">base to base, in inches</div></div>
      <div class="stepper"><button data-action="charge-gap" data-delta="-0.5" aria-label="Shorter">−</button><div class="val">${c.gap}"</div><button data-action="charge-gap" data-delta="0.5" aria-label="Longer">+</button></div></div>
    <div class="modrow"><div class="lab">Charge roll modifiers, added up</div>${seg('charge-mod', c.mod, CHARGE_MODS, 'compact')}</div>
    <div class="chips" style="margin-top:8px">${chip('charge-reroll', c.reroll, 'Re-roll the charge (e.g. Command Re-roll)')}</div>
    <div class="hero" style="grid-template-columns:1fr 1fr;margin-top:12px">
      <div class="cell"><b id="charge-need">${need > CHARGE_MAX ? '—' : `${need}+`}</b><span>${need > CHARGE_MAX ? `more than ${CHARGE_MAX}": cannot be charged` : 'needed on 2D6: the gap, rounded up'}</span></div>
      <div class="cell"><b id="charge-p">${pct(p)}</b><span>chance to make it</span></div>
    </div>
    <div class="section"><h2>Quick reference${c.mod ? ` · ${fmtMod(c.mod)} to the roll` : ''}</h2>
      <table class="dist"><thead><tr><th>Gap</th><th>Needs</th><th>Chance</th><th>With re-roll</th></tr></thead><tbody>${rows.join('')}</tbody></table></div>
    <p class="hint" id="charge-rule">11th edition (11.04): the charge roll is the maximum distance, and the target must be within that distance — and within ${CHARGE_MAX}" — before the unit moves. A roll that would only bring the unit to within 2" is not enough. Modifiers to the charge roll add up (the ±1 limit is for hit and wound rolls); the roll cannot be more than 12. A FLY unit that takes to the skies to move over models or terrain has −2" (21.03).</p>`;
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

/**
 * Battle-shock after an attack. A unit at or below half strength (01.02.01: half its starting models,
 * leaders counted; a single model: half its wounds) takes a battle-shock roll in its player's next
 * Command phase (08.03): 2D6 against its best Leadership (01.06). Failed: OC "-", its player cannot use
 * stratagems on it, it cannot start actions, and it can only fall back by Desperate Escape (01.07, 09.07).
 * dist: { alive: models now, lostAtLeast, pWipe } or for one model { wounds: wounds now, woundsAtLeast, pWipe }
 * -> { pHalf: at or below half and not destroyed, pFail, pShocked, ld } or null
 */
function shockOdds(cu, dist) {
  if (!cu) return null;
  const f = shockFacts(cu);
  let pHalf;
  if (f.single) {
    if (!dist.woundsAtLeast) return null;
    const need = Math.max(0, (dist.wounds ?? f.single) - Math.floor(f.single / 2));
    pHalf = need <= 0 ? 1 : (dist.woundsAtLeast[need] ?? 0);
  } else {
    const need = Math.max(0, dist.alive - Math.floor(f.start / 2));
    pHalf = need <= 0 ? 1 : (dist.lostAtLeast[need] ?? 0);
  }
  const pTest = Math.max(0, pHalf - (dist.pWipe ?? 0));
  const pFail = 1 - chargeOdds(f.ld);          // P(2D6 < Ld)
  return { pHalf: pTest, pFail, pShocked: pTest * pFail, ld: f.ld };
}
function shockHtml(who, sh, id) {
  if (!sh || sh.pHalf < 0.005) return '';
  return `<div class="shock small" id="${id}"><b>Battle-shock:</b> ${who} at or below half strength, and still on the table, <b>${pct(sh.pHalf)}</b> of the time. In its next Command phase it then tests on Ld ${sh.ld}+ and fails ${pct(sh.pFail)} of the time: <b>battle-shocked ${pct(sh.pShocked)}</b>.
    <span class="tiny muted">A battle-shocked unit has OC “–”, cannot be the target of its player's stratagems, cannot start actions and can only fall back by Desperate Escape.</span></div>`;
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
    ${shockHtml('the target is', shockOdds(tinfo?.cu, { alive: r.totalModels, lostAtLeast: r.killsAtLeast, wounds: r.totalWounds, woundsAtLeast: r.woundsAtLeast, pWipe: r.pWipe }), 'shock-target')}
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
  if (a.startsWith('mission-')) {
    if (missionAction(a, el) === 'render') changed({ calc: false });
    return;
  }
  if (a.startsWith('board-')) {
    if (boardAction(a, el) === 'render') changed();
    return;
  }
  if (a.startsWith('event-')) {
    if (eventAction(a, el) === 'render') changed();
    return;
  }
  switch (a) {
    case 'brief-grid':
      // "every unit vs every unit": my army attacking theirs, from the brief
      state.side = state.mission?.me ?? 'A';
      state.sheet = 'grid';
      startGrid();
      return renderSheet();
    case 'backup-save': return void saveBackupFile();
    case 'backup-send': return void sendBackup();
    case 'backup-receive': return void receiveBackup();
    case 'backup-undo':
      if (window.confirm('Put back what was on this device before the last restore?')) { try { if (undoRestore(localStorage)) location.reload(); } catch (err) { backupNote(`Could not undo (${err?.message ?? err}).`); } }
      return;
    case 'view':
      // table mode: the calculator and the board planner are closed — say so on the Play view
      if (tableMode() && (el.dataset.value === 'attack' || el.dataset.value === 'board')) {
        state.mission.tableNotice = el.dataset.value;
        state.view = 'mission';
        state.sheet = null;
        return changed({ calc: false });
      }
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
      if (document.getElementById('attack-pane')) return;   // already on screen (wide layout)
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
    case 'intel-mode':
      state.intelMode = el.dataset.value === 'phase' ? 'phase' : 'units';
      return changed({ calc: false });
    case 'intel-phase': {
      state.intelPhase = el.dataset.value;
      changed({ calc: false });
      // the chosen phase starts right under the strip
      const strip = document.getElementById('phase-strip');
      if (strip) {
        const top = strip.getBoundingClientRect().top + window.scrollY - (document.querySelector('header.top')?.offsetHeight ?? 53);
        if (window.scrollY > top) window.scrollTo(0, top);
      }
      return;
    }
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
    case 'open-chain':
      return openChain();
    case 'chain-gap':
      state.chain.gap = Math.max(1, Math.min(24, state.chain.gap + Number(el.dataset.delta)));
      runChain();
      return renderSheet();
    case 'chain-mod':
      state.chain.mod = Number(el.dataset.value);
      runChain();
      return renderSheet();
    case 'chain-reroll':
      state.chain.reroll = !state.chain.reroll;
      runChain();
      return renderSheet();
    case 'chain-back':
      state.chain.back = state.chain.back === false;
      runChain();
      return renderSheet();
    case 'chain-overwatch':
      state.chain.overwatch = !state.chain.overwatch;
      runChain();
      return renderSheet();
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
      const tinfo = targetInfo();
      const { rows, problem, stale } = rowsFor(e, tinfo);
      const row = rows.find(r => r.id === el.dataset.row);
      if (!row || row.blocked) return;
      e.counts ??= {};
      const delta = Number(el.dataset.delta);
      if (problem && row.fam != null) {
        // rows of one family share weapons or models (profiles of one weapon, the melee weapons of one model):
        // from the first change by hand the whole family is set by hand, and a count that goes up takes from the others
        if (stale) for (const r of rows) if (r.fam != null) delete e.counts[r.id];   // set for another target
        e.countsFor = tinfo?.cu?.key ?? null;
        const cur = Object.fromEntries(rows.map(r => [r.id, r.full]));
        Object.assign(e.counts, adjustCount(problem, cur, row.id, delta));
      } else e.counts[row.id] = Math.max(0, Math.min(row.max, row.full + delta));
      return changed();
    }
    case 'count-auto': {
      const e = findEntry(el.dataset.uid);
      if (!e) return;
      e.counts = {};
      delete e.countsFor;
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
      if (turnOn && r?.kind === 'stratagem') {
        // 15.01: one stratagem on a unit in a phase ...
        const key = stratKey(r);
        for (const sib of rules) if (sib.kind === 'stratagem' && stratKey(sib) !== key && on.has(sib.id)) e.ruleOverrides[sib.id] = false;
        // ... and the same stratagem once in a phase: off on the other attacking units
        for (const o of setup().attackers) {
          if (o === e) continue;
          for (const [rid, v] of Object.entries(o.ruleOverrides ?? {})) if (v === true && String(rid).replace(/:alt\d+$/, '') === key) o.ruleOverrides[rid] = false;
        }
      }
      return changed();
    }
    case 'shooting-type': {
      const e = findEntry(el.closest('[data-uid]')?.dataset.uid);
      if (!e) return;
      e.mods ??= {};
      e.mods.shootingType = el.dataset.value;
      e.mods.engaged = el.dataset.value === 'cq';         // 17.03: its close-quarters weapons have no -1 against the unit it is engaged with
      if (el.dataset.value !== 'normal') { e.mods.stationary = false; e.mods.heavyOk = false; }
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
      const enabled = enabledRules(tinfo.profile, s);
      const on = enabled.has(r.id);
      s.ruleOverrides[r.id] = !on;
      // 15.01: one stratagem on the target in a phase (the effects of one stratagem go together)
      if (!on && r.kind === 'stratagem') for (const x of tinfo.profile.rules) if (x.kind === 'stratagem' && defStratKey(x.id) !== defStratKey(r.id) && enabled.has(x.id)) s.ruleOverrides[x.id] = false;
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
  if (el.dataset?.input === 'backup-file') {
    const file = el.files?.[0];
    if (!file) return;
    file.text().then((txt) => { let b = null; try { b = JSON.parse(txt); } catch { /* not JSON */ } restoreBackup(b, `“${file.name}”`); });
    el.value = '';
    return;
  }
  const evr = eventChange(el);      // 'quiet': the card has already updated itself in place (a result typed in)
  if (evr) return el.dataset.input === 'event-name' || evr === 'quiet' ? undefined : changed({ calc: false });
  if (boardChange(el)) return changed({ calc: false });
  const mc = missionChange(el);
  if (mc === 'quiet') return persist();
  if (mc) return changed({ calc: false });
  if (el.dataset.input === 'chain-charger') {
    state.chain.chargerKey = el.value;
    runChain();
    return renderSheet();
  }
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
  if (el.dataset.input === 'mission-score') { missionChange(el); return; }
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
  if (el.dataset?.details === 'backup') state.openBackup = el.open;
  if (el.dataset?.details === 'event' && state.event) state.event.open = el.open;
  if (el.dataset?.details?.startsWith('brief-')) (state.briefOpen ??= {})[el.dataset.details.slice(6)] = el.open;
  if (el.dataset?.details === 'board-tray' && state.board) state.board.trayClosed = !el.open;
  // Mission tab panels stay open while their buttons re-draw the page
  if (el.dataset?.details?.startsWith('mission-') && state.mission) (state.mission.open ??= {})[el.dataset.details] = el.open;
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
  state, esc, seg, chip, signature: listsSignature, wide,
  // one army's list (for "use my deployment against another opponent")
  sideSig, listName: (X) => listLabel(X), me: () => state.mission?.me ?? 'A',
  // "Shoot / Fight ->" from the board: that unit attacks that target, with the measured gap
  // cover / inRange (shooting): from the board's 11e line of sight — inRange = models that can see and reach
  openAttack({ side, phase, attacker, target, distance, halfRange, cover, inRange, chain }) {
    state.side = side;
    state.phase = phase;
    const st = setup();
    st.targetKey = target;
    const mods = { distance, halfRange };
    let entry = st.attackers.find(x => x.unitKey === attacker);
    if (entry) entry.mods = { ...(entry.mods ?? {}), ...mods };
    else { entry = { uid: uidSeq++, unitKey: attacker, counts: {}, mods }; st.attackers = [entry]; }
    if (cover !== undefined) {
      st.defManual = { ...(st.defManual ?? {}), cover: !!cover };
      entry.inRange = inRange ?? null;
    }
    state.view = 'attack';
    window.scrollTo(0, 0);
    if (chain) setTimeout(() => openChain({ chargerKey: attacker, gap: distance }), 0);
    console.log(`[calc] board -> calculator: ${attacker} ${phase} into ${target}, ${distance}" (half range ${halfRange}${cover !== undefined ? `, cover ${cover}, models seeing ${inRange ?? 'all'}` : ''})`);
  },
});
initMission({ state, esc, seg, chip, pairOdds, wide });
initEvent({ state, esc, seg, loadList: loadListInto, persistLibrary, sideSig, newGame: missionNewGame, gameInProgress: missionInProgress, gameScore: missionScore });
initBrief({ state, esc, wide });
parseArmy('A');
parseArmy('B');
if (!(state.armies.A && state.armies.B)) state.view = 'armies';
render();
scheduleCalc();

// ask the browser not to clear the saved lists and plans when the device runs low on space
if (navigator.storage?.persist && (state.armies.A || state.armies.B)) {
  navigator.storage.persisted().then(p => p || navigator.storage.persist()).then((p) => { state.persisted = !!p; console.log(`[calc] storage persistent: ${!!p}`); }).catch(() => {});
}

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  const hadController = !!navigator.serviceWorker.controller;
  navigator.serviceWorker.register('./sw.js', { updateViaCache: 'none' }).then((reg) => {
    // check for a new version whenever the app comes back to the foreground
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') reg.update().catch(() => {}); });
  }).catch(err => console.warn('[calc] service worker not registered', err));
  // a new version took over: offer to reload into it (lists and plans are saved)
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController || document.getElementById('update-banner')) return;
    const bar = document.createElement('div');
    bar.id = 'update-banner';
    bar.className = 'update-banner';
    bar.innerHTML = '<span class="grow">A new version of the app is ready.</span><button class="btn primary" id="update-reload">Reload</button>';
    document.body.appendChild(bar);
    bar.querySelector('#update-reload').addEventListener('click', () => location.reload());
    console.log('[calc] new version available');
  });
}

// test / debugging hook
window.__calc = { state, scenario, runCalc, defaultScenario, atkArmy, defArmy, board: _boardDebug, mission: _missionDebug, event: _eventDebug };
