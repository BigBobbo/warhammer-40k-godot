// Combat calculator UI. State lives in localStorage; the dataset/importer
// come from the Army Builder modules (adapter.mjs); the dice run in a Web
// Worker (worker.mjs -> engine.mjs).
import {
  importArmy, attackerRows, engineWeapon, allVehicleMonster, abilitiesOf,
  defenderProfile, defenderSummary, buildDefender, DATASET_VERSION,
  setAttachments, withAttachment, attachCandidates, joinCandidates, rosterUnitLabel,
  attackerRules, attackerRuleOn, buildAttacker, describeConditions,
} from './adapter.mjs';

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
  result: null, busy: false, calcError: null,
  chartMode: null,           // 'models' | 'damage' | null (auto)
  selBar: null,
};

let uidSeq = 1;

function persist() {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify({
      view: state.view, texts: state.texts, side: state.side, phase: state.phase, setups: state.setups,
      attach: state.attach,
    }));
  } catch { /* storage full / private mode: best effort */ }
}

function restore() {
  try {
    const s = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (!s) return;
    Object.assign(state, {
      view: s.view ?? 'armies', texts: s.texts ?? { A: '', B: '' }, side: s.side ?? 'A',
      phase: s.phase ?? 'shooting', setups: s.setups ?? {}, attach: s.attach ?? { A: null, B: null },
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

function rowsFor(entry, tinfo) {
  const cu = atkArmy()?.units.find(u => u.key === entry.unitKey);
  if (!cu) return { cu: null, rows: [] };
  const rows = attackerRows(cu, state.phase, tinfo?.summary ?? null).map(r => ({
    ...r, count: r.blocked ? 0 : Math.min(r.max, entry.counts?.[r.id] ?? r.count),
  }));
  return { cu, rows };
}

// Attacker rules (abilities, detachment rule, stratagems) for an attacker entry,
// with which ones are on given its situation chips and the current target.
function rulesFor(e, cu, tinfo) {
  const { rules, stratText } = attackerRules(cu, atkArmy());
  const ctx = {
    charged: !!e.mods?.charged, stationary: !!e.mods?.stationary, halfRange: !!e.mods?.halfRange,
    targetKeywords: tinfo?.profile.keywords ?? [], attackerKeywords: cu.keywords,
  };
  const inPhase = rules.filter(r => r.phases.includes(state.phase));
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
  const defender = buildDefender(tinfo.profile, enabledRules(tinfo.profile, s), state.phase, s.defManual);
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
      <div class="brand">⚔ Combat Calc</div>
      <span class="badge" title="40kdc dataset version">11e · data ${esc(DATASET_VERSION)}</span>
      <nav class="tabs">
        <button class="tab ${state.view === 'armies' ? 'on' : ''}" data-action="view" data-value="armies">Armies</button>
        <button class="tab ${state.view === 'attack' ? 'on' : ''}" data-action="view" data-value="attack" ${ready ? '' : 'disabled'}>Attack</button>
      </nav>
    </div></header>
    <main class="wrap">${state.view === 'attack' && ready ? attackView() : armiesView()}</main>
    <div id="resultbar"></div>
    <div id="sheet"></div>`;
  renderResultViews();
  renderSheet();
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
    <p class="hint">Lists stay on this device. Works offline once loaded.</p>`;
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
    const built = buildDefender(profile, enabledRules(profile, s), state.phase, s.defManual);
    const summary = defenderSummary({ ...profile, groups: built.groups.map(g => ({ ...g, InSv: g.InSv || (built.mods.invuln ?? 0) })) });
    const st = (v, l) => `<div class="stat"><b>${esc(v)}</b><span>${l}</span></div>`;
    const inv = summary.InSv ? `${summary.InSv}+` : '–';
    // FNP on the stat line = what the bodyguard models have; a character's own FNP is listed with it
    const bodyG = built.groups.filter(g => !g.character);
    const fnp = Math.min(...(bodyG.length ? bodyG : built.groups).map(g => g.fnp || 7), built.mods.fnp || 7);
    body += `<div class="stats">${st(summary.T, 'T')}${st(`${summary.Sv}+`, 'Sv')}${st(inv, 'InSv')}${st(summary.W, 'W')}${st(summary.models, 'Models')}${fnp < 7 ? st(`${fnp}+`, 'FNP') : ''}</div>`;
    const groups = built.groups.filter(g => g.character);
    if (groups.length) body += `<div class="tiny muted" style="margin-top:6px">Characters: ${groups.map(g => `${esc(g.name)} (T${g.T} W${g.W} ${g.Sv}+${g.InSv ? `/${g.InSv}++` : ''}${g.fnp ? `, FNP ${g.fnp}+` : ''})`).join(', ')} — allocated last unless Precision.</div>`;
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
  const sit = [
    shooting && chip('amod-toggle', !!m.halfRange, 'Half range', `data-uid="${e.uid}" data-key="halfRange"`),
    chip('amod-toggle', !!m.charged, 'Charged', `data-uid="${e.uid}" data-key="charged"`),
    shooting && chip('amod-toggle', !!m.stationary, 'Stationary', `data-uid="${e.uid}" data-key="stationary"`),
    shooting && chip('amod-toggle', !!m.overwatch, 'Snap shooting', `data-uid="${e.uid}" data-key="overwatch"`),
    shooting && hasIndirect && chip('amod-toggle', !!m.indirect, 'Indirect (not visible)', `data-uid="${e.uid}" data-key="indirect"`),
  ].filter(Boolean).join('');
  const nMods = ['hitMod', 'woundMod', 'apMod', 'damageMod', 'attacksMod', 'bsMod'].filter(k => m[k]).length +
    ['lethal', 'dev', 'twin', 'ignoresCover', 'precision'].filter(k => m[k]).length + (m.sustained ? 1 : 0) +
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
    <div class="chips" style="margin-top:8px">${sit}</div>
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
    : state.sheet === 'attach' ? attachSheet()
      : state.sheet === 'join' ? joinSheet() : resultsSheet();
  host.innerHTML = `<div class="sheet-backdrop" data-action="close-sheet"></div>
    <div class="sheet" role="dialog" aria-modal="true"><div class="grab"></div><div class="wrap">${content}</div></div>`;
  if (state.sheet === 'results') wireChart();
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
      const { on } = rulesFor(e, cu, tinfo);
      e.ruleOverrides ??= {};
      e.ruleOverrides[el.dataset.id] = !on.has(el.dataset.id);
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
});
app.addEventListener('toggle', (ev) => {
  const el = ev.target;
  if (el.dataset?.details === 'mods') {
    const e = findEntry(el.dataset.uid);
    if (e) { e.openMods = el.open; persist(); }
  }
}, true);

// ---------------------------------------------------------------------------
// Boot

restore();
parseArmy('A');
parseArmy('B');
if (!(state.armies.A && state.armies.B)) state.view = 'armies';
render();
scheduleCalc();

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('./sw.js').catch(err => console.warn('[calc] service worker not registered', err));
}

// test / debugging hook
window.__calc = { state, scenario, runCalc };
