// Event set-up on the Armies tab: your list (army A), the opponents' lists
// (the list library — paste one or many), the layout letter of each round from
// the event pack, and "Start round": the opponent becomes army B, the board
// gets the round's layout, and you land on the matchup brief.
//
// In 11th edition a list's Force Disposition is fixed for the event, your
// primary mission comes from your disposition against the opponent's, and each
// pair of dispositions has three layouts (A / B / C); the organiser names the
// letter for each round. So everything about a round is known once you know
// the opponent — this card works it out for every list in the roster.
//
// app.js owns the shared state and calls in through initEvent().

import { importArmy } from './adapter.mjs';
import { DISPOSITIONS, DEPLOYMENTS, dispositionName, layoutLetter, matchupFor } from './board.mjs';
import { splitLists } from './lists.mjs';
import { boardSetup, plannedLayouts } from './boardview.mjs';

let ctx = null;            // { state, esc, seg, loadList(side, text), persistLibrary(), sideSig(side), newGame() }
export const EVENT_KEY = 'w40k_calc_event_v1';

export function initEvent(c) {
  ctx = c;
  try {
    const saved = JSON.parse(localStorage.getItem(EVENT_KEY) ?? 'null');
    if (saved) Object.assign(ev(), saved);
  } catch { /* fresh */ }
}
function ev() {
  const s = ctx.state;
  s.event ??= { name: '', rounds: [1, 2, 3, 4, 5].map(() => ({ layout: 1, opp: null })), round: null, open: false };
  return s.event;
}
function persist() {
  try { localStorage.setItem(EVENT_KEY, JSON.stringify(ev())); } catch { /* best effort */ }
}

// ---------------------------------------------------------------------------
// Roster (the list library) with what each list means for my rounds

const infoCache = new Map();
/** { faction, name, disp, units, points, error } for a library item (parsed once). */
export function listInfo(l) {
  const key = `${l.id}|${l.text.length}`;
  if (!infoCache.has(key)) {
    try {
      const a = importArmy(l.text);
      infoCache.set(key, { faction: a.faction, name: a.name, disp: a.roster?.force_disposition ?? 'take-and-hold', units: a.units.length, points: a.units.reduce((n, u) => n + (u.points || 0), 0) });
    } catch (e) { infoCache.set(key, { error: e?.message ?? String(e), faction: l.faction ?? '?', disp: 'take-and-hold', units: 0, points: 0 }); }
  }
  return infoCache.get(key);
}
const myArmy = () => ctx.state.armies.A;
const myDisp = () => myArmy()?.roster?.force_disposition ?? null;
const depName = (l) => (l ? DEPLOYMENTS[l.deployment]?.name ?? l.deployment : '?');

// ---------------------------------------------------------------------------
// View

export function eventCard() {
  const e = ev(), st = ctx.state, esc = ctx.esc;
  const lib = st.library;
  const me = myArmy(), mine = myDisp();
  const oppOptions = (cur) => `<option value="">Opponent…</option>${lib.map(l => `<option value="${l.id}" ${String(l.id) === String(cur) ? 'selected' : ''}>${esc(l.name)}</option>`).join('')}`;
  const roundRow = (r, i) => {
    const o = lib.find(l => String(l.id) === String(r.opp));
    const mu = o && mine ? matchupFor(mine, listInfo(o).disp) : null;
    const lay = mu?.layouts[r.layout - 1];
    return `<div class="event-round ${e.round === i + 1 ? 'on' : ''}" data-round="${i + 1}">
      <div class="row" style="gap:8px;align-items:center">
        <b style="min-width:26px">R${i + 1}</b>
        <span class="tiny muted">Layout</span>${ctx.seg('event-layout', r.layout, [[1, 'A'], [2, 'B'], [3, 'C']], `compact" data-r="${i}`)}
        <span class="grow"></span>
        <button class="btn primary" data-action="event-start" data-r="${i}" ${o && me ? '' : 'disabled'} aria-label="Start round ${i + 1}">Start ▶</button>
      </div>
      <select class="sel" style="margin-top:6px" data-input="event-opp" data-r="${i}" aria-label="Opponent in round ${i + 1}">${oppOptions(r.opp)}</select>
      ${mu ? `<div class="tiny muted" style="margin-top:3px">You: <b>${esc(mu.mine ?? '?')}</b> · they: <b>${esc(mu.theirs ?? '?')}</b> · ${esc(depName(lay))}</div>` : ''}
    </div>`;
  };
  const sig = me ? ctx.sideSig('A') : null;
  const planned = sig ? plannedLayouts('A', sig) : new Set();
  const rosterRow = (l, i) => {
    const info = listInfo(l);
    const mu = mine ? matchupFor(mine, info.disp) : null;
    return `<div class="pick" style="cursor:default;align-items:flex-start" data-opp="${l.id}">
      <div class="grow"><div class="title">${esc(l.name)}</div>
        <div class="muted tiny">${esc(info.faction)} · ${esc(dispositionName(info.disp))}${info.points ? ` · ${info.points} pts` : ''}${info.units ? ` · ${info.units} units` : ''}${info.error ? ' · could not read this list' : ''}</div>
        ${mu ? `<div class="tiny">You: <b>${esc(mu.mine ?? '?')}</b> · they: <b>${esc(mu.theirs ?? '?')}</b><span class="muted"> · ${mu.layouts.map((x, k) => `${'ABC'[k]} ${esc(depName(x))}${x && planned.has(x.id) ? ' ✓' : ''}`).join(' · ')}</span></div>` : ''}</div>
      <button class="btn" data-action="event-load" data-i="${i}" aria-label="Load ${esc(l.name)} as army B">→ B</button>
      <button class="icon-btn" data-action="event-remove" data-i="${i}" aria-label="Remove ${esc(l.name)}">🗑</button></div>`;
  };
  // coverage: for each disposition an opponent can have, the three layouts and whether I have a deployment for them
  const coverage = mine ? `<table class="dist" id="event-coverage" style="margin-top:6px"><thead><tr><th>Their disposition</th><th>A</th><th>B</th><th>C</th></tr></thead><tbody>${DISPOSITIONS.map(d => {
    const mu = matchupFor(mine, d.id);
    const n = lib.filter(l => listInfo(l).disp === d.id).length;
    return `<tr><td>${esc(d.name)}${n ? ` <span class="tiny muted">(${n})</span>` : ''}<div class="tiny muted">you: ${esc(mu.mine ?? '?')}</div></td>${mu.layouts.map((x, k) => `<td><button class="cov ${x && planned.has(x.id) ? 'done' : ''}" data-action="event-cover" data-disp="${d.id}" data-v="${k + 1}" aria-label="${esc(d.name)} layout ${'ABC'[k]}: ${x && planned.has(x.id) ? 'deployment planned' : 'no deployment yet'}">${x && planned.has(x.id) ? '✓' : '+'}<span class="tiny">${esc(depName(x))}</span></button></td>`).join('')}</tr>`;
  }).join('')}</tbody></table>
    <div class="tiny muted">✓ = you have a deployment for that layout with this list (it is offered again against any opponent). Tap a cell to plan it on the Board.</div>` : '';
  return `<details class="more card" style="margin-top:12px" data-details="event" ${e.open ? 'open' : ''} id="event-card">
    <summary>Event${e.name ? ` · ${esc(e.name)}` : ''}${e.round ? ` · round ${e.round}` : ''} — ${lib.length} opponent list${lib.length === 1 ? '' : 's'}</summary>
    <input class="sel" data-input="event-name" value="${esc(e.name)}" placeholder="Event name (optional)" aria-label="Event name" style="margin-top:6px">
    <div class="small" style="margin-top:8px" id="event-me">${me ? `You: <b>${esc(me.faction)}</b> · ${esc(dispositionName(mine))} (army A)` : '<span class="muted">Load your own list into Army A first: it is “you” for the whole event.</span>'}</div>
    <div class="lab tiny muted" style="margin-top:10px">Rounds — the layout letter (A / B / C) is in the event pack</div>
    <div id="event-rounds">${e.rounds.map(roundRow).join('')}</div>
    <div class="row" style="gap:6px;margin-top:6px"><button class="btn ghost" data-action="event-round-add">＋ Round</button>${e.rounds.length > 1 ? '<button class="btn ghost" data-action="event-round-del">－ Round</button>' : ''}</div>
    <div class="lab tiny muted" style="margin-top:12px">Opponents — paste one list or many (GW app, New Recruit, ListForge)</div>
    <textarea class="list" data-input="event-paste" id="event-paste" style="min-height:90px" placeholder="Paste the lists you may face. Separate lists with a line of ----- if they are not GW app exports." spellcheck="false"></textarea>
    <button class="btn block" style="margin-top:6px" data-action="event-add">Add to the opponents</button>
    ${e.msg ? `<div class="small" id="event-msg" style="margin-top:6px">${esc(e.msg)}</div>` : ''}
    <div id="event-roster" style="margin-top:8px">${lib.length ? lib.map(rosterRow).join('') : '<p class="hint">No opponent lists yet.</p>'}</div>
    ${coverage ? `<div class="lab tiny muted" style="margin-top:12px">Your preparation — ${esc(dispositionName(mine))} against each disposition</div>${coverage}` : ''}
  </details>`;
}

// ---------------------------------------------------------------------------
// Actions

function note(msg) { ev().msg = msg; ev().open = true; console.log(`[event] ${msg}`); }

/** Add every list in `text` to the roster; returns { added, failed }. */
export function addLists(text) {
  const st = ctx.state;
  let added = 0, failed = 0;
  for (const t of splitLists(text)) {
    try {
      const a = importArmy(t);
      const base = `${a.faction}${a.name && a.name !== 'Army' ? ` – ${a.name}` : ''}`;
      let name = base, n = 2;
      while (st.library.some(l => l.name === name && l.text !== t)) name = `${base} (${n++})`;
      const item = { id: Date.now() + added, name, faction: a.faction, text: t, savedAt: Date.now() };
      const same = st.library.findIndex(l => l.text === t || l.name === name);
      if (same >= 0) st.library[same] = { ...item, id: st.library[same].id }; else st.library.push(item);
      added++;
    } catch { failed++; }
  }
  ctx.persistLibrary();
  return { added, failed };
}

export function eventAction(action, el) {
  const e = ev(), st = ctx.state;
  switch (action) {
    case 'event-layout': e.rounds[Number(el.closest('[data-r]').dataset.r)].layout = Number(el.dataset.value); break;
    case 'event-round-add': e.rounds.push({ layout: 1, opp: null }); break;
    case 'event-round-del': e.rounds.pop(); if (e.round > e.rounds.length) e.round = null; break;
    case 'event-add': {
      const ta = document.getElementById('event-paste');
      const { added, failed } = addLists(ta?.value ?? '');
      note(added || failed ? `${added} list${added === 1 ? '' : 's'} added${failed ? `, ${failed} could not be read` : ''}.` : 'Paste at least one list first.');
      break;
    }
    case 'event-remove': {
      const l = st.library[Number(el.dataset.i)];
      if (!l) return null;
      st.library.splice(Number(el.dataset.i), 1);
      for (const r of e.rounds) if (String(r.opp) === String(l.id)) r.opp = null;
      ctx.persistLibrary();
      break;
    }
    case 'event-load': {
      const l = st.library[Number(el.dataset.i)];
      if (!l) return null;
      ctx.loadList('B', l.text);
      boardSetup({ listDispositions: true });
      note(`${l.name} loaded as army B.`);
      break;
    }
    case 'event-start': {
      const i = Number(el.dataset.r), r = e.rounds[i];
      const l = st.library.find(x => String(x.id) === String(r?.opp));
      if (!l || !myArmy()) return null;
      if (ctx.gameInProgress() && !window.confirm(`Start round ${i + 1} against ${l.name}? The game tracked on the Play view is cleared.`)) return null;
      ctx.loadList('B', l.text);
      boardSetup({ variant: r.layout, listDispositions: true });
      ctx.newGame();
      e.round = i + 1;
      st.view = 'intel';
      st.intelSide = 'B';
      e.msg = '';
      console.log(`[event] round ${i + 1}: ${l.name}, layout ${layoutLetter(r.layout)}`);
      break;
    }
    case 'event-cover': {
      // plan a deployment for "my disposition vs that disposition" on that layout (needs any army B on the board)
      if (!st.armies.B) { note('Load any list as army B first (an opponent from the list above): the Board needs two armies.'); break; }
      const b = st.board;
      b.settings.dispB = el.dataset.disp;
      boardSetup({ variant: Number(el.dataset.v) });
      st.view = 'board';
      break;
    }
    default: return null;
  }
  persist();
  return 'render';
}

export function eventChange(el) {
  const e = ev();
  if (el.dataset.input === 'event-opp') { e.rounds[Number(el.dataset.r)].opp = el.value || null; persist(); return true; }
  if (el.dataset.input === 'event-name') { e.name = el.value.trim(); persist(); return true; }
  return false;
}

/** "Round 2 · Layout B · vs Orks – Waaagh" for the brief, when the loaded army B is this round's opponent. */
export function roundLabel() {
  const e = ev(), st = ctx.state;
  if (!e.round) return '';
  const r = e.rounds[e.round - 1];
  const l = st.library.find(x => String(x.id) === String(r?.opp));
  if (!l || l.text !== st.texts.B) return '';
  return `${e.name ? `${e.name} · ` : ''}Round ${e.round} · Layout ${layoutLetter(r.layout)}`;
}

export function _eventDebug() { return { ...ev(), roster: ctx.state.library.map(l => ({ id: l.id, name: l.name, ...listInfo(l) })) }; }
