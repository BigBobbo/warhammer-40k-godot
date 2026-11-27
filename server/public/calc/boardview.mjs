// Board planner view for the combat calculator: the official 11e GW layout
// for the two armies' Force Dispositions, deployment zones, objectives, and
// draggable unit tokens at real base size, with a ruler, range rings, a link
// into the calculator and saved plan steps (Deploy, Turn 1, ...).
//
// The view is plain SVG in board inches (44 x 60); pan / pinch-zoom change
// the viewBox. app.js owns the shared state and calls in through initBoard().

import {
  BOARD, DEPLOYMENTS, OBJECTIVE_RANGE, ENGAGEMENT_RANGE,
  footprint, formation, coherentFormation, coherency, COHERENCY, rotateFormation, unitGap, edgeRadius, layoutsFor, missionsFor, dispositionName, DISPOSITIONS, inPoly, layoutLetter,
} from './board.mjs';
import { boardUnit, earlyArrival, transportOf, passengerCheck, abilitiesOf, armyIntel } from './adapter.mjs';
import { advisePayload, payloadSize, promptText, tidyAnswer, parsePlan, resolveActions } from './advise.mjs';
import { SECONDARIES } from './missions-11e.mjs';
import { sightVerdict, threatTo, chargeReach, canHide, visibleCells, HIDDEN_RANGE, GONE_TO_GROUND } from './sight.mjs';
import { inRange, ocInRange, planWarnings, arrivalZones, scoutCheck } from './planeval.mjs';
import { photoFor, photoInfo, startPhoto, adjustPhoto, turnPhoto, removePhoto, photoScaleAt, _photoDebug } from './photoview.mjs';
import { BASE_SIZES, baseToBase, measureError, fmtIn as fmtBase } from './measure.mjs';
import { ensureIds, resolveSteps, rootOf, treeOf, choiceLabel, subtree, branch as branchPlan, optionsAt, chain, evaluate, treeRows } from './plantree.mjs';
import { chargeOdds, chargeRollNeeded } from './engine.mjs';
import { LAYOUTS_SOURCE, longDate } from './rulesnote.mjs';
import { dropState } from './droporder.mjs';
import { nextTurn, myTurn, moveCandidates, bestMoves, keepMoves, worthOf, riskAfterMove, objectiveGap, MOVE_MIN_VP } from './nextturn.mjs';
import { playOut } from './playout.mjs';
import { objectiveSides } from './board.mjs';

// fixed map colours (not theme tokens): the board reads the same in light and
// dark mode and exports to an image unchanged
const C = {
  mat: '#e6e1d3', edge: '#b8b09a', area: 'rgba(120,112,92,0.38)', areaEdge: '#6f6754', feature: '#5f584a',
  obj: '#1f1f1f', objRing: 'rgba(214,160,0,0.22)', objEdge: '#b88a00', text: '#2b2a26',
  A: '#2a78d6', B: '#d95926', sel: '#f2c200', ruler: '#111111',
};

let ctx = null;          // { state, esc, seg, chip, render, persist, openAttack, signature, other }
const LS_KEY = 'w40k_calc_board_v1';

// Tablets (and anything wide) get three columns: my army | the map | the opponent's army.
// A portrait tablet stacks them: the map on top, the two armies side by side below (CSS).
// Phones keep the one-column board with the dock.
const TABLET_Q = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(min-width: 600px) and (min-height: 600px)') : null;
const triMode = () => !!(ctx?.wide?.() || TABLET_Q?.matches);

export function initBoard(c) {
  ctx = c;
  TABLET_Q?.addEventListener?.('change', () => { console.log(`[board] layout: ${triMode() ? 'three columns' : 'phone'}`); ctx.rerender?.(); });
  // Ctrl/Cmd+Z undo, Ctrl/Cmd+Shift+Z or Ctrl+Y redo, on the Board (a tablet with a keyboard)
  if (typeof window !== 'undefined') window.addEventListener('keydown', (ev) => {
    if (ctx.state.view !== 'board' || !(ev.ctrlKey || ev.metaKey) || ev.target?.closest?.('input, textarea, select, [contenteditable]')) return;
    const k = ev.key.toLowerCase();
    const redo = (k === 'z' && ev.shiftKey) || k === 'y';
    if (k !== 'z' && k !== 'y') return;
    ev.preventDefault();
    if (redo ? redoBoard() : undoBoard()) ctx.rerender?.();
  });
  // the branches panel is drawn again when the unit-vs-unit odds of a chance branch are worked out
  ctx.registerHost?.('board-treemap-host', treeMapHtml);
  ctx.registerHost?.('board-next-host', nextTurnHtml);
  // "Ask for a plan": is it switched on for this server? (off without an API key on the server). Not asked while
  // offline - a request that cannot leave the device is logged by the browser as an error - but once back online.
  const askAdvise = () => {
    if (adviseInfo?.enabled || typeof fetch !== 'function' || (typeof navigator !== 'undefined' && navigator.onLine === false)) return;
    fetch('/api/calc-advise').then(r => (r.ok ? r.json() : null)).then((j) => { adviseInfo = j && j.enabled ? j : { enabled: false }; console.log(`[board] plans from Claude: ${adviseInfo.enabled ? `on (${adviseInfo.model}, ${adviseInfo.effort} effort, ${adviseInfo.perDay} a day)` : 'off on this server'}`); if (adviseInfo.enabled) ctx.rerender?.(); }).catch(() => { adviseInfo = { enabled: false }; });
  };
  askAdvise();
  // the answer being pasted is kept while the Board redraws (a forecast finishing, a unit tapped)
  if (typeof window !== 'undefined') window.addEventListener('input', (ev) => { if (ev.target?.id === 'board-advise-paste') boardState().pasteDraft = ev.target.value; });
  if (typeof window !== 'undefined') window.addEventListener('online', askAdvise);
  ctx.registerHost?.('board-tree-host', () => (document.activeElement?.closest?.('#board-tree') ? document.getElementById('board-tree-host')?.innerHTML ?? '' : treeHtml()));
  try {
    const saved = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (saved) Object.assign(boardState(), { settings: saved.settings ?? {}, plans: saved.plans ?? {} });
  } catch { /* fresh */ }
}

function boardState() {
  const s = ctx.state;
  s.board ??= { settings: {}, plans: {}, sel: null, sel2: null, mode: 'move', rings: {}, view: null, ruler: null };
  return s.board;
}

function persistBoard() {
  const b = boardState();
  recordHistory();
  try { localStorage.setItem(LS_KEY, JSON.stringify({ settings: b.settings, plans: b.plans })); } catch { /* best effort */ }
}

// ---------------------------------------------------------------------------
// Undo / redo. Every change to a plan is saved through persistBoard(); there the plan is compared with the
// copy kept at the last save, and if it changed, that copy goes on the undo list. So every kind of change
// (a drag, a nudge, a rotation, a formation, placing or removing a unit, a transport, a Scout move, a new
// turn, a branch) can be undone without each action knowing about it. What is on screen (the turn and plan
// shown, selections, rings, overlays) is not a change. Per plan (layout + lists), in memory, up to 30 steps.

const UNDO_MAX = 30;
const VIEW_KEYS = new Set(['cur', 'v', 'meta']);
const planJson = (root) => JSON.stringify(root ?? null, (k, val) => (VIEW_KEYS.has(k) ? undefined : val));
function history() {
  const b = boardState(), key = planKey();
  if (!b.hist || b.hist.key !== key) {
    const root = key ? b.plans[key] ?? null : null;
    b.hist = { key, undo: [], redo: [], last: planJson(root), full: JSON.stringify(root ?? null), note: null };
  }
  return b.hist;
}
function recordHistory() {
  const b = boardState();
  if (!planKey()) return;
  const h = history(), root = b.plans[h.key] ?? null;
  const now = planJson(root);
  if (now === h.last) return;
  // the plan's first save (an empty Deploy step being set up) is a start, not a change
  if (h.last === 'null') { h.last = now; h.full = JSON.stringify(root); return; }
  const before = JSON.parse(h.full);
  const what = planChange(before, root);
  h.undo.push({ full: h.full, ...what });
  if (h.undo.length > UNDO_MAX) h.undo.shift();
  h.redo = [];
  h.note = null;
  h.last = now;
  h.full = JSON.stringify(root);
  console.log(`[board] undo +1: ${what.label} (${h.undo.length} to undo)`);
  refreshUndo();
}
/** What changed between two copies of a plan: a label for the button, and the turn (and unit) to show on undo. */
function planChange(a, z) {
  const name = (tk) => { const [sd, k] = tk.split(':'); return unitInfo(sd, k)?.cu.name ?? tk; };
  const va = a?.variants ?? [], vz = z?.variants ?? [];
  if (va.length !== vz.length) return { label: vz.length > va.length ? 'new branch / plan' : 'removed a plan', vi: Math.min(z?.v ?? 0, Math.max(0, vz.length - 1)), si: null, tk: null };
  // the turn on screen first (that is where you were working), then the others in order
  const order = [];
  const cv = z?.v ?? 0, cs = vz[cv]?.cur ?? 0;
  order.push([cv, cs]);
  vz.forEach((vv, vi) => (vv.steps ?? []).forEach((_, si) => { if (!(vi === cv && si === cs)) order.push([vi, si]); }));
  for (const [vi, si] of order) {
    const sa = va[vi]?.steps ?? [], sz = vz[vi]?.steps ?? [];
    if (sa.length !== sz.length) return { label: sz.length > sa.length ? `added ${sz[sz.length - 1]?.name ?? 'a turn'}` : 'removed a turn', vi, si: Math.min(si, sz.length - 1), tk: null };
    const ta = sa[si]?.tokens ?? {}, tz = sz[si]?.tokens ?? {};
    const tks = [...new Set([...Object.keys(ta), ...Object.keys(tz)])].filter(tk => JSON.stringify(ta[tk] ?? null) !== JSON.stringify(tz[tk] ?? null));
    if (!tks.length) continue;
    const tk = tks.find(k => k === boardState().sel) ?? tks[0];
    const p = ta[tk], q = tz[tk];
    let label;
    if (!p) label = `placed ${name(tk)}`;
    else if (!q) label = `removed ${name(tk)}`;
    else if ((p.in ?? null) !== (q.in ?? null)) label = `${name(tk)} ${q.in ? 'embarked' : 'disembarked'}`;
    else if (JSON.stringify(p.scout ?? null) !== JSON.stringify(q.scout ?? null)) label = `${name(tk)}'s Scout move`;
    else if (p.x !== q.x || p.y !== q.y) label = `moved ${name(tk)} ${Math.hypot(q.x - p.x, q.y - p.y).toFixed(1)}"`;
    else if ((p.rot ?? 0) !== (q.rot ?? 0)) label = `turned ${name(tk)}`;
    else label = `${name(tk)}'s formation`;
    if (tks.length > 1 && !(p && q && q.in)) label += ` (+${tks.length - 1} more)`;
    return { label, vi, si, tk };
  }
  return { label: 'plan change', vi: z?.v ?? 0, si: null, tk: null };
}
/** Put a copy of the plan back (undo / redo) and show the turn where it changed, with that unit selected. */
function restorePlan(full, at) {
  const b = boardState(), h = history();
  const root = JSON.parse(full);
  if (root) {
    if (at?.vi != null && root.variants?.[at.vi]) {
      root.v = at.vi;
      if (at.si != null) root.variants[at.vi].cur = Math.max(0, Math.min(at.si, (root.variants[at.vi].steps?.length ?? 1) - 1));
    }
    b.plans[h.key] = root;
  } else delete b.plans[h.key];
  h.last = planJson(root);
  h.full = JSON.stringify(root);
  const toks = root?.variants?.[root.v ?? 0]?.steps?.[root.variants?.[root.v ?? 0]?.cur ?? 0]?.tokens ?? {};
  b.sel = at?.tk && toks[at.tk] ? at.tk : null; b.sel2 = null;
  persistBoard();
}
function undoBoard() {
  const h = history(), e = h.undo.pop();
  if (!e) return false;
  h.redo.push({ full: h.full, label: e.label, vi: e.vi, si: e.si, tk: e.tk });
  restorePlan(e.full, e);
  h.note = `↶ Undid: ${e.label}`;
  console.log(`[board] undo: ${e.label} (${h.undo.length} left, ${h.redo.length} to redo)`);
  return true;
}
function redoBoard() {
  const h = history(), e = h.redo.pop();
  if (!e) return false;
  h.undo.push({ full: h.full, label: e.label, vi: e.vi, si: e.si, tk: e.tk });
  restorePlan(e.full, e);
  h.note = `↷ Redid: ${e.label}`;
  console.log(`[board] redo: ${e.label} (${h.redo.length} left)`);
  return true;
}
function undoButtons() {
  const h = history(), u = h.undo[h.undo.length - 1], r = h.redo[h.redo.length - 1], esc = ctx.esc;
  return `<button class="icon-btn" data-action="board-undo" id="board-undo" ${u ? '' : 'disabled'} aria-label="${u ? `Undo: ${esc(u.label)}` : 'Nothing to undo'}" title="${u ? `Undo: ${esc(u.label)}` : 'Nothing to undo'}">↶</button>`
    + `<button class="icon-btn" data-action="board-redo" id="board-redo" ${r ? '' : 'disabled'} aria-label="${r ? `Redo: ${esc(r.label)}` : 'Nothing to redo'}" title="${r ? `Redo: ${esc(r.label)}` : 'Nothing to redo'}">↷</button>`
;
}
const undoNote = () => { const h = history(); return h.note ? `<span class="tiny muted" id="board-undo-note">${ctx.esc(h.note)}</span>` : ''; };
function refreshUndo() {
  const host = document.getElementById('board-undo-host');
  if (host) host.innerHTML = undoButtons();
  const nh = document.getElementById('board-undo-note-host');
  if (nh) nh.innerHTML = undoNote();
}

// ---------------------------------------------------------------------------
// Mission / layout selection

function dispOf(side) {
  const b = boardState();
  return b.settings[`disp${side}`] ?? ctx.state.armies[side]?.roster?.force_disposition ?? 'take-and-hold';
}

/** The Force Disposition the list itself names (null: the list does not say). */
function listDisp(side) {
  return ctx.state.armies[side]?.roster?.force_disposition ?? null;
}
/** A disposition picked on the Board that differs from the one the list names. */
function dispOverridden(side) {
  const v = boardState().settings[`disp${side}`], l = listDisp(side);
  return v != null && l != null && v !== l;
}
/**
 * The mission set-up (dispositions, layout, zones) is locked while a game is on the
 * tracker: changing it mid-game swaps both primaries, the deployment map and the
 * board plans under the game. "Change anyway" unlocks it until that game ends.
 */
function setupLocked() {
  const b = boardState();
  const live = !!ctx.gameInProgress?.();
  if (!live) b.unlock = false;
  return live && !b.unlock;
}

function currentLayout() {
  const b = boardState();
  const list = layoutsFor(dispOf('A'), dispOf('B'));
  const v = b.settings.variant ?? 1;
  return list.find(l => l.variant === v) ?? list[0] ?? null;
}

function zoneOf(side) {
  const swap = !!boardState().settings.swapZones;
  return side === 'A' ? (swap ? 2 : 1) : (swap ? 1 : 2);
}

function planKey() {
  const l = currentLayout();
  return l ? `${l.id}|${ctx.signature()}` : null;
}

// Plans for this layout + lists: several variants (e.g. "Main", "Aggressive"),
// each a list of steps (Deploy, Turn 1, ...).
function planRoot() {
  const b = boardState();
  const k = planKey();
  if (!k) return null;
  let root = b.plans[k] ?? { steps: [{ name: 'Deploy', tokens: {} }], cur: 0 };
  if (root.steps) root = { variants: [{ name: 'Main', steps: root.steps, cur: root.cur ?? 0 }], v: 0 }; // older single-plan saves
  ensureIds(root.variants);
  root.v = Math.min(root.v ?? 0, root.variants.length - 1);
  // which layout and lists this plan belongs to (to offer my deployment against another opponent)
  const l = currentLayout();
  if (l && ctx.sideSig) root.meta = { layout: l.id, a: ctx.sideSig('A'), b: ctx.sideSig('B'), aName: ctx.listName?.('A') ?? '', bName: ctx.listName?.('B') ?? '' };
  b.plans[k] = root;
  return root;
}

const sideTokens = (root, X) => root.variants.reduce((n, vv) => n + vv.steps.reduce((m, st) => m + Object.keys(st?.tokens ?? {}).filter(tk => tk.startsWith(`${X}:`)).length, 0), 0);
/** A plan I made on this layout with the same list of mine against another opponent (the newest with units placed). */
function reusablePlan() {
  const b = boardState(), root = planRoot(), l = currentLayout();
  const me = ctx.me?.() ?? 'A';
  if (!root || !l || !ctx.sideSig || sideTokens(root, me) > 0) return null;
  const mySig = ctx.sideSig(me), key = me === 'A' ? 'a' : 'b';
  let best = null;
  for (const [k, r] of Object.entries(b.plans)) {
    if (r === root || !r?.variants || r.meta?.layout !== l.id || r.meta[key] !== mySig) continue;
    const n = sideTokens({ variants: r.variants.filter(vv => !vv.live) }, me);
    if (n > 0 && (!best || n > best.n)) best = { k, root: r, n, vs: r.meta[me === 'A' ? 'bName' : 'aName'] || 'another opponent' };
  }
  return best;
}
/** Copy my side of that plan here (every variant and step); the enemy's tokens here stay. */
function reusePlan() {
  const src = reusablePlan();
  const root = planRoot();
  if (!src || !root) return false;
  const me = ctx.me?.() ?? 'A';
  const mineOnly = (tokens) => Object.fromEntries(Object.entries(tokens ?? {}).filter(([tk]) => tk.startsWith(`${me}:`)).map(([tk, pos]) => [tk, { ...pos }]));
  const theirs = (tokens) => Object.fromEntries(Object.entries(tokens ?? {}).filter(([tk]) => !tk.startsWith(`${me}:`)));
  const clone = (o) => (o == null ? o : JSON.parse(JSON.stringify(o)));
  root.variants = src.root.variants.filter(sv => !sv.live).map((sv, vi) => ({
    name: sv.name, cur: 0, id: sv.id, parent: sv.parent ?? null, from: sv.from ?? null, when: sv.when, splits: clone(sv.splits), branch: clone(sv.branch),
    // a shared turn of a branch stays shared (null)
    steps: sv.steps.map((st, si) => (st ? { name: st.name, tokens: { ...theirs(root.variants[vi]?.steps[si]?.tokens ?? root.variants[0]?.steps[Math.min(si, (root.variants[0]?.steps.length ?? 1) - 1)]?.tokens), ...mineOnly(st.tokens) } } : null)),
  }));
  root.v = 0;
  console.log(`[board] reused my deployment from the plan vs ${src.vs}: ${src.n} unit positions`);
  return true;
}
function plan() {
  const root = planRoot();
  return root ? root.variants[Math.min(root.v, root.variants.length - 1)] : null;
}
/** The steps of the path on screen (a branch: the shared turns resolved to its ancestors' steps). */
function curSteps() {
  const root = planRoot();
  return root ? resolveSteps(root.variants, Math.min(root.v, root.variants.length - 1)) : [];
}
const curIndex = () => { const p = plan(); return p ? Math.min(p.cur ?? 0, Math.max(0, curSteps().length - 1)) : 0; };
const VARIANT_NAMES = ['Aggressive', 'Defensive', 'Plan C', 'Plan D', 'Plan E'];

// ---------------------------------------------------------------------------
// Live table: where the models are on the real table now. A plan of its own (variant.live) that follows the game
// on the tracker: one step per battle round as every plan ("Turn N" = battle round N, so models left, reserves and
// the forecast read it like any plan), the last step being the table now. Each "Turn done" on the tracker keeps
// the position as it was (snaps: one per player turn) and, in a new battle round, starts its step.
//   stamp: { round, turn, phase } - when the player last said "the positions are current"
//   shock: { tk: true }          - battle-shocked units (OC "-"); cleared when that player's next turn starts
//   snaps: [{ round, turn, tokens, shock }] - the table at the end of each player turn (the newest 12)
const cloneJson = (o) => JSON.parse(JSON.stringify(o ?? {}));
const liveIndex = (root = planRoot()) => (root ? root.variants.findIndex(vv => vv.live) : -1);
const livePlan = () => { const p = plan(); return p?.live ? p : null; };
const gameNow = () => ctx.gameNow?.() ?? { round: 1, turn: 'A', phase: 'command', started: false, over: false, hand: { A: [], B: [] } };
const afterScout = (tokens) => { for (const pos of Object.values(tokens)) if (pos?.scout) { pos.x = pos.scout.x; pos.y = pos.scout.y; delete pos.scout; } return tokens; };
/** Is the live position confirmed for the turn the tracker is on? */
function liveFresh(lv, g = gameNow()) { return !!lv?.stamp && lv.stamp.round === g.round && lv.stamp.turn === g.turn; }

/** Show the live table; the first time it is made from the plan on screen (the table as that plan had it at the start of this battle round). */
function openLive() {
  const root = planRoot();
  if (!root) return false;
  let i = liveIndex(root);
  if (i < 0) {
    const g = gameNow(), R = Math.max(1, g.round), src = curSteps(), from = plan()?.name ?? 'Main';
    const at = (k) => cloneJson(src[Math.min(k, src.length - 1)]?.tokens);
    const steps = [{ name: 'Deploy', tokens: at(0) }];
    // the rounds played: as planned; the round in progress starts where the round before it ended
    for (let r = 1; r <= R; r++) steps.push({ name: `Turn ${r}`, tokens: afterScout(at(r < R ? r : R - 1)) });
    root.variants.push({ name: 'Live table', live: true, steps, cur: R, liveFrom: from, back: root.v, stamp: null, shock: {}, snaps: [] });
    ensureIds(root.variants);
    i = root.variants.length - 1;
    console.log(`[board] live table started from the plan "${from}": battle round ${R}, ${Object.keys(steps[R].tokens).length} units`);
  } else if (root.v !== i) root.variants[i].back = rootOf(root.variants, root.v);
  root.v = i;
  const lv = root.variants[i];
  lv.cur = Math.min(Math.max(1, gameNow().round), lv.steps.length - 1);
  return true;
}
/**
 * "Turn done" on the tracker (missionview): the table at the end of that player turn is kept, a new battle
 * round gets its step, and the battle-shock of the player whose turn starts ends (their Command phase).
 * prev / now: { round, turn } before and after.
 */
export function boardTurnDone(prev, now) {
  const root = planRoot(), i = liveIndex(root);
  if (i < 0) return;
  const lv = root.variants[i];
  const last = lv.steps[lv.steps.length - 1];
  (lv.snaps ??= []).push({ round: prev.round, turn: prev.turn, tokens: cloneJson(last.tokens), shock: { ...(lv.shock ?? {}) } });
  if (lv.snaps.length > 12) lv.snaps.splice(0, lv.snaps.length - 12);
  while (lv.steps.length <= now.round) lv.steps.push({ name: `Turn ${lv.steps.length}`, tokens: cloneJson(lv.steps[lv.steps.length - 1].tokens) });
  lv.cur = Math.min(now.round, lv.steps.length - 1);
  for (const tk of Object.keys(lv.shock ?? {})) if (tk.startsWith(`${now.turn}:`)) delete lv.shock[tk];
  console.log(`[board] live table: kept the table at the end of round ${prev.round}, ${prev.turn}'s turn (${Object.keys(last.tokens).length} units); now round ${now.round}, ${now.turn}'s turn`);
  persistBoard();
}
/**
 * A new game on the tracker: the live table belongs to the game before it. One that was used (confirmed, or a
 * turn was played on it) stays as an ordinary plan, "Last game"; an untouched one goes. The next 🔴 starts afresh.
 */
export function boardNewGame() {
  const root = planRoot(), i = liveIndex(root);
  if (i < 0) return;
  const lv = root.variants[i];
  if (lv.stamp || lv.snaps?.length) {
    const used = new Set(root.variants.map(x => x.name));
    let name = 'Last game';
    for (let n = 2; used.has(name); n++) name = `Last game ${n}`;
    delete lv.live;
    lv.name = name;
    console.log(`[board] a new game on the tracker: the live table is kept as the plan "${name}"`);
  } else {
    removePaths(root, [i]);
    console.log('[board] a new game on the tracker: the unused live table is removed');
  }
  persistBoard();
}

/** The bar above the map while the live table is on screen: the round and turn of the tracker, and how current the positions are. */
function liveBarHtml() {
  const lv = livePlan();
  if (!lv) return '';
  const esc = ctx.esc, g = gameNow(), st = ctx.state;
  const phase = { command: 'Command', movement: 'Movement', shooting: 'Shooting', charge: 'Charge', fight: 'Fight' }[g.phase] ?? '';
  const who = (X) => `${X} · ${esc(st.armies[X]?.faction ?? '')}`;
  const nowIdx = Math.min(g.round, lv.steps.length - 1), onNow = curIndex() === nowIdx;
  const fresh = liveFresh(lv, g);
  const stampTxt = lv.stamp ? `round ${lv.stamp.round}, ${lv.stamp.turn}'s turn` : null;
  const head = g.over ? 'the battle is over' : `Round <b>${g.round}</b> · <b style="color:var(--side-${g.turn.toLowerCase()}-ink)">${who(g.turn)}</b>'s turn${phase ? ` · ${phase}` : ''}`;
  return `<div class="card live-bar ${fresh ? 'fresh' : 'stale'}" id="board-live-bar" data-fresh="${fresh ? 1 : 0}" data-round="${g.round}" data-turn="${g.turn}">
    <div class="row" style="gap:8px;align-items:center;flex-wrap:wrap">
      <span class="grow small"><b>🔴 Live table</b> · ${head}${g.started ? '' : ' <span class="muted">(no game on the tracker yet: Mission → Play)</span>'}</span>
      ${onNow ? `<button class="btn ${fresh ? 'ghost' : 'primary'}" data-action="board-live-confirm" id="board-live-confirm">${fresh ? '✓ Positions current' : '✓ Positions are current'}</button>`
    : `<button class="btn primary" data-action="board-step" data-i="${nowIdx}" id="board-live-now">Go to now</button>`}
    </div>
    <div class="tiny ${fresh || !onNow ? 'muted' : ''}" id="board-live-note" style="margin-top:4px${fresh || !onNow ? '' : ';color:var(--warn-ink)'}">${!onNow ? `You are looking at <b>${esc(curSteps()[curIndex()]?.name ?? '')}</b>: how the table stood then. The table now is <b>${esc(lv.steps[nowIdx]?.name ?? '')}</b>.`
    : fresh ? `Confirmed for this turn${lv.stamp.phase && lv.stamp.phase !== g.phase ? ` (in the ${esc(lv.stamp.phase)} phase)` : ''}. Move a unit here whenever it moves on the table.`
      : stampTxt ? `⚠ Last confirmed in ${stampTxt}. Move the units to where they are on the table now, then confirm.`
        : `⚠ These positions come from your plan “${esc(lv.liveFrom ?? 'Main')}”. Move the units to where they are on the table now, then confirm.`}</div>
  </div>`;
}

// ---- "Their next turn" (nextturn.mjs): from the live table, what the other player can do in their next turn
const kindsOf = (cu) => {
  let chars = 0, w10 = 0;
  for (const m of cu.members ?? []) {
    const n = m.ru?.model_count ?? 1, Wm = parseInt(m.dcUnit?.profiles?.[0]?.W, 10) || 1;
    if ((m.dcUnit?.keywords ?? []).some(k => /^CHARACTER$/i.test(k))) chars += n;
    if (Wm >= 10) w10 += n;
  }
  return { chars, w10, ss13: (cu.models ?? 0) >= 13 };
};
let nextMemo = { key: null, v: null };
// ---- my moves weighed with the mission forecast: each candidate move alone, then the best of each unit together.
// moveMemo: { key (of the table it was worked out for), state: 'pending' | 'done', n (candidates), base: { win, vp },
//             best: [move] (each unit's best move alone), kept: { moves, win, vp } (the ones worth making together) }
let moveMemo = { key: null, state: 'idle' };
function weighMoves(key, v, mine, pieces, home, theirs = [], pair = null) {
  if (moveMemo.key === key || !ctx.moveForecasts) return;
  const li = liveIndex(), plan = li >= 0 ? boardPlans()[li] : null;
  const last = plan ? plan.steps.length - 1 : -1;
  // only for the table now (the last step), not for an earlier turn looked at
  if (!plan || curIndex() !== last) { moveMemo = { key, state: 'idle' }; return; }
  const me = v.me;
  const cands = moveCandidates(mine, v.my.swing, pieces, { risk: Object.fromEntries(v.res.threats.map(t => [t.key, t.likely])), home });
  moveMemo = { key, state: cands.length ? 'pending' : 'done', n: cands.length, best: [], kept: { moves: [] } };
  if (!cands.length) return;
  const withMoves = (ms) => ({ ...plan, steps: plan.steps.map((st, si) => (si !== last ? st : { ...st, [me]: st[me].map(u => { const m = ms.find(x => x.unit === u.key); return m ? { ...u, x: m.x, y: m.y } : u; }) })) });
  const redraw = () => { const host = document.getElementById('board-next-host'); if (host && nextMemo.key === key) host.innerHTML = nextTurnHtml(); };
  const done = (r1, stacked, best) => {
    if (moveMemo.key !== key) return;
    // how exposed each unit is where the move ends, against where it stands
    const here = Object.fromEntries(v.res.threats.map(t => [t.key, t.likely]));
    for (const m of best) { const r = riskAfterMove(mine, theirs, pair, m, pieces); m.riskThere = r.likely; m.focusThere = r.focus; m.riskHere = here[m.unit] ?? 0; }
    const kept = keepMoves(best, r1.base, stacked, me);
    moveMemo = { key, state: 'done', n: cands.length, base: worthOf(r1.base, me), best, kept };
    console.log(`[board] my moves weighed with the forecast: ${cands.length} tried, ${best.length} beat standing still by ${MOVE_MIN_VP}+ VP, ${kept.moves.length} kept together (${kept.moves.map(m => `${m.name} -> ${m.label} +${m.addVp.toFixed(1)}`).join('; ') || 'none'}); win ${Math.round(moveMemo.base.win * 100)}% -> ${Math.round((kept.moves.length ? kept.win : moveMemo.base.win) * 100)}%`);
    redraw();
  };
  // (started once the table has been still for a moment: every drop of a unit would start a run of its own)
  const start = (fn) => (typeof setTimeout === 'function' ? setTimeout(fn, 500) : fn());
  start(() => moveMemo.key === key && ctx.moveForecasts(plan, cands.map(c => ({ key: c.key, plan: withMoves([c]) }))).then((r1) => {
    if (moveMemo.key !== key) return;
    if (!r1) { moveMemo = { key, state: 'idle' }; redraw(); return; }
    const best = bestMoves(cands, r1.base, r1.variants, me);
    if (best.length < 2) { done(r1, best.map(b => r1.variants[b.key]), best); return; }
    ctx.moveForecasts(plan, best.map((b, i) => ({ key: `s${i}`, plan: withMoves(best.slice(0, i + 1)) }))).then((r2) => { if (r2) done(r1, best.map((b, i) => r2.variants[`s${i}`]), best); });
  }));
}
// ---- "Play it out" (playout.mjs): the rest of the game with both players following the turn cards, turn after
// turn, scored by the mission forecast. Asked for with a button on "Your turn"; shown next to the usual forecast,
// never in its place. playMemo.key = the table it was worked out for (nextMemo.key).
let playMemo = { key: null, state: 'idle' };
function runPlayOut() {
  const key = nextMemo.key, v = nextMemo.v, base = nextMemo.base;
  const li = liveIndex(), plan = li >= 0 ? boardPlans()[li] : null, last = plan ? plan.steps.length - 1 : -1;
  if (!key || !v?.my || !base || !plan || curIndex() !== last || !ctx.moveForecasts || moveMemo.state === 'pending') return;
  const g = gameNow(), me = v.me, opp = v.opp;
  const t0 = performance.now?.() ?? 0;
  const po = playOut({ [me]: base.mine, [opp]: base.theirs, objs: base.objs, geo: base.geo, pair: base.pair, round: last, turn: g.turn, first: g.first ?? null,
    moved: !!g.started && !['command', 'movement'].includes(g.phase), hand: g.hand ?? {} });
  // the plan the forecast scores: the game so far as on the live table, then a step per battle round played out
  const tpl = plan.steps[last];
  const place = (ps) => ({ ...tpl, A: tpl.A.map(u => { const q = ps.A.find(x => x.key === u.key); return q ? { ...u, x: q.x, y: q.y } : u; }), B: tpl.B.map(u => { const q = ps.B.find(x => x.key === u.key); return q ? { ...u, x: q.x, y: q.y } : u; }) });
  const full = { ...plan, steps: [...plan.steps.slice(0, last), ...po.steps.map(st => place(st))] };
  const turns = po.log.filter(l => !l.done).length;
  console.log(`[board] play-out: battle rounds ${last}-${last + po.steps.length - 1}, ${turns} player turns, ${po.log.reduce((a, l) => a + l.moves.filter(m => m.dist > 0).length, 0)} moves worked out in ${((performance.now?.() ?? 0) - t0).toFixed(0)} ms`);
  playMemo = { key, state: 'pending', log: po.log, steps: po.steps, from: last, me };
  const redraw = () => { const host = document.getElementById('board-next-host'); if (host && nextMemo.key === key) host.innerHTML = nextTurnHtml(); };
  redraw();
  ctx.moveForecasts(plan, [{ key: 'playout', plan: full, until: Infinity }]).then((r) => {
    if (playMemo.key !== key || playMemo.state !== 'pending') return;
    const out = r?.variants?.playout;
    if (!out) { playMemo = { key, state: 'failed' }; console.log('[board] play-out: no forecast came back (another one was started, or the mission is not set up)'); redraw(); return; }
    // the score after each battle round still to play: the final average less what is scored after that round
    const after = (res, X, rd) => { let v = res[X]?.mean ?? 0; if (rd < 5) v -= res[X]?.primEnd ?? 0; for (let k = rd; k < 5; k++) v -= (res[X]?.prim?.[k] ?? 0) + (res[X]?.sec?.[k] ?? 0); return v; };
    const perRound = (res) => po.steps.map(st => ({ round: st.round, me: after(res, me, st.round), opp: after(res, opp, st.round), ahead: res.lead?.[st.round - 1]?.[me] ?? null, behind: res.lead?.[st.round - 1]?.[opp] ?? null,
      left: { me: res[me]?.unitsLeft?.[st.round - 1] ?? null, opp: res[opp]?.unitsLeft?.[st.round - 1] ?? null } }));
    playMemo = { ...playMemo, rounds: perRound(out), baseRounds: perRound(r.base) };
    playMemo = { ...playMemo, state: 'done', base: worthOf(r.base, me), out: worthOf(out, me), vp: { me: out[me]?.mean ?? 0, opp: out[opp]?.mean ?? 0 }, baseVp: { me: r.base[me]?.mean ?? 0, opp: r.base[opp]?.mean ?? 0 } };
    console.log(`[board] play-out scored by the forecast: ${me} wins ${Math.round(playMemo.out.win * 100)}% (${playMemo.vp.me.toFixed(1)} - ${playMemo.vp.opp.toFixed(1)} VP); the usual forecast of the table as it stands: ${Math.round(playMemo.base.win * 100)}% (${playMemo.baseVp.me.toFixed(1)} - ${playMemo.baseVp.opp.toFixed(1)} VP)`);
    redraw();
  });
}
/** The played-out game as a plan of its own on the Board (a step per battle round), to look at turn by turn. */
function playOutToPlan() {
  const root = planRoot(), li = liveIndex(root);
  if (playMemo.state !== 'done' || playMemo.key !== nextMemo.key || !root || li < 0) return false;
  const lv = root.variants[li], R = playMemo.from;
  const steps = cloneJson(lv.steps.slice(0, R + 1)), now = cloneJson(lv.steps[R].tokens ?? {});
  for (const [i, st] of playMemo.steps.entries()) {
    const tokens = cloneJson(now);
    for (const X of ['A', 'B']) for (const u of st[X]) if (tokens[u.key] && !tokens[u.key].in) { tokens[u.key].x = u.x; tokens[u.key].y = u.y; }
    steps[R + i] = { name: `Turn ${R + i}`, tokens };
  }
  const old = root.variants.findIndex(x => x.playout);
  const vv = { name: 'Played out', playout: true, steps, cur: R };
  if (old >= 0) root.variants[old] = { ...vv, id: root.variants[old].id }; else root.variants.push(vv);
  ensureIds(root.variants);
  root.v = old >= 0 ? old : root.variants.length - 1;
  persistBoard();
  console.log(`[board] play-out put on the board as the plan "Played out": turns ${R}-${steps.length - 1}`);
  return true;
}
function playOutHtml(d) {
  const esc = ctx.esc, pct = (p) => `${Math.round(p * 100)}%`;
  const pm = playMemo.key === nextMemo.key ? playMemo : { state: 'idle' };
  const what = 'both players do what these cards suggest, every turn to the end of round 5';
  if (pm.state === 'pending') return `<div class="small muted" id="board-playout" data-state="pending" style="margin-top:6px">⏳ Playing the game out (${what})…</div>`;
  if (pm.state !== 'done') {
    const busy = moveMemo.key === nextMemo.key && moveMemo.state === 'pending';
    return `<div id="board-playout" data-state="${pm.state}" style="margin-top:6px"><button class="chip" data-action="board-playout" id="board-playout-run"${busy ? ' disabled' : ''}>▶ Play the game out</button>
      <span class="tiny muted">${pm.state === 'failed' ? 'It could not be scored just now. Try again. ' : ''}A second opinion next to the forecast: ${what}.</span></div>`;
  }
  const b = boardState(), open = !!b.playLog;
  const VERB = { take: 'takes', hold: 'holds', charge: 'charges', shoot: 'shoots', fight: 'fights', advance: 'walks towards' };
  const logHtml = !open ? '' : `<div id="board-playout-log" class="tiny" style="margin-top:6px">${pm.log.map(l => `<div style="margin-top:4px"><b>Round ${l.round} · <span style="color:var(--side-${l.side.toLowerCase()}-ink)">${esc(ctx.state.armies[l.side].faction)}</span></b>${l.done ? ' <span class="muted">has moved already</span>' : !l.moves.length ? ' <span class="muted">nothing to do</span>' : ''}
      ${l.moves.map(m => `<div class="muted">${esc(shortName(m.name))} ${VERB[m.kind] ?? m.kind} ${esc(shortName(m.label))}${m.dist > 0 && m.kind !== 'advance' && m.kind !== 'take' && m.kind !== 'charge' ? ` after ${fmtIn(m.dist)}` : m.dist > 0 ? ` (${fmtIn(m.dist)})` : ''}</div>`).join('')}</div>`).join('')}</div>`;
  const dv = pm.out.win - pm.base.win;
  return `<div class="small" id="board-playout" data-state="done" data-win="${pm.out.win.toFixed(3)}" data-base="${pm.base.win.toFixed(3)}" data-rounds="${pm.steps.length}" style="margin-top:6px">▶ Played out to the end of the game: you win <b>${pct(pm.out.win)}</b> of games, <b>${pm.vp.me.toFixed(0)} – ${pm.vp.opp.toFixed(0)} VP</b> on average.
    <span class="muted">The forecast of the table as it stands says ${pct(pm.base.win)} (${pm.baseVp.me.toFixed(0)} – ${pm.baseVp.opp.toFixed(0)} VP)${Math.abs(dv) >= 0.1 ? `: the two disagree by ${Math.round(Math.abs(dv) * 100)} points, so treat both as rough` : ''}.</span>
    <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:6px"><button class="chip" data-action="board-playout-plan" id="board-playout-plan">🗺 See it on the board, turn by turn</button>
      <button class="chip" data-action="board-playout-log" id="board-playout-log-btn" aria-expanded="${open}">${open ? 'Hide' : 'Show'} who did what</button>
      <button class="chip" data-action="board-playout" id="board-playout-again">↻ Again</button></div>
    <table class="tiny" id="board-playout-rounds" style="margin-top:8px;border-collapse:collapse;width:100%"><thead><tr class="muted" style="text-align:left"><th style="font-weight:400;padding:2px 8px 2px 0">After round</th><th style="font-weight:400;padding:2px 8px">Score, you – them</th><th style="font-weight:400;padding:2px 8px">You are ahead</th><th style="font-weight:400;padding:2px 8px">Units left</th><th style="font-weight:400;padding:2px 0 2px 8px">Usual forecast</th></tr></thead><tbody>
      ${pm.rounds.map((x, i) => { const bs = pm.baseRounds[i]; return `<tr data-round="${x.round}" data-me="${x.me.toFixed(1)}" data-opp="${x.opp.toFixed(1)}" data-ahead="${(x.ahead ?? 0).toFixed(3)}" style="border-top:1px solid var(--line, #ddd)"><td style="padding:3px 8px 3px 0"><b>${x.round}</b></td><td style="padding:3px 8px"><b>${x.me.toFixed(0)} – ${x.opp.toFixed(0)}</b></td><td style="padding:3px 8px">${x.ahead == null ? '' : `${pct(x.ahead)} of games`}</td><td style="padding:3px 8px">${x.left.me == null ? '' : `${x.left.me.toFixed(1)} – ${x.left.opp.toFixed(1)}`}</td><td class="muted" style="padding:3px 0 3px 8px">${bs.me.toFixed(0)} – ${bs.opp.toFixed(0)}${bs.ahead == null ? '' : ` · ${pct(bs.ahead)}`}</td></tr>`; }).join('')}
    </tbody></table>
    <div class="tiny muted" style="margin-top:4px">Averages over the 1,500 games, at the end of each battle round (the forecast scores by round, not by player turn). Round 5 includes the end-of-battle points.</div>${logHtml}
    <div class="tiny muted" style="margin-top:6px" id="board-playout-how">Here ${what}; the mission forecast then scores that game 1,500 times (dice, cards, units destroyed). The moves follow one simple rule: nobody plans ahead, a move is a straight line, nobody Advances, units destroyed on the way do not change where the others walk, and cards count for this round only.</div></div>`;
}
function nextTurnData(compute = true) {
  const lv = livePlan(), l = currentLayout(), st = ctx.state;
  if (!lv || !l) return null;
  const me = st.armies[ctx.me?.()] ? ctx.me() : 'A', opp = otherSide(me);
  const g = gameNow(), dep = DEPLOYMENTS[l.deployment];
  const toks = placed(), inside = embarkedIn(stepTokens());
  const pair = ctx.pairTable?.() ?? null;
  const hand = g.hand?.[opp] ?? [], myHand = g.hand?.[me] ?? [];
  const key = JSON.stringify([l.id, me, g.round, hand, myHand, !!pair, zoneOf('A'), lv.shock, toks.map(t => [t.tk, f2(t.x), f2(t.y), t.rot, t.per, t.gap, t.u.left, stepTokens()[t.tk]?.mo ?? 0])]);
  if (nextMemo.key === key) return { ...nextMemo.v, g, fresh: liveFresh(lv, g) };
  // (the work is put off until after the frame a unit was dropped in: see nextTurnHtml)
  if (!compute) return { pending: true, prev: nextMemo.v ? { ...nextMemo.v, g, fresh: liveFresh(lv, g) } : null };
  const unitOf = (t) => ({ key: t.tk, name: t.u.cu.name, x: t.x, y: t.y, models: t.models, move: t.u.move, ranges: t.u.ranges, melee: t.u.melee, oc: t.u.oc, points: t.u.cu.points ?? 0,
    keywords: t.u.cu.keywords ?? [], lone: t.u.flags?.loneOperative || 0, left: t.u.left, total: t.u.total, shocked: !!lv.shock?.[t.tk], ...kindsOf(t.u.cu) });
  const pick = (list, X) => list?.find(z => z.player === zoneOf(X))?.poly ?? null;
  const geo = { zones: { A: pick(dep?.zones, 'A'), B: pick(dep?.zones, 'B') }, territories: { A: pick(dep?.territories, 'A'), B: pick(dep?.territories, 'B') }, pieces: l.pieces, objectives: l.objectives };
  // the objectives by whose side they are on, named as on the Mission tab
  const sides = new Map(objectiveSides(l, dep, zoneOf('A')).map(o => [o.id, o]));
  const objs = l.objectives.map(o => { const sd = sides.get(o.id) ?? {}; return { ...o, cls: sd.cls, side: sd.side, label: sd.cls === 'home' ? (sd.side === me ? 'Your home' : 'Their home') : sd.cls === 'central' ? 'Centre' : sd.side === me ? 'Your side' : 'Their side' }; });
  const seen = {};
  for (const o of objs) if (objs.filter(x => x.label === o.label).length > 1) o.label = `${o.label} ${(seen[o.label.replace(/ \d+$/, '')] = (seen[o.label.replace(/ \d+$/, '')] ?? 0) + 1)}`;
  const t0 = performance.now?.() ?? 0;
  const base = { me, mine: toks.filter(t => t.side === me).map(unitOf), theirs: toks.filter(t => t.side === opp).map(unitOf), pair, geo, objs, round: g.round };
  const res = pair ? nextTurn({ ...base, hand }) : null;
  // my turn: the same measurements from my side; a unit's risk is what their next turn does to it where it stands
  const my = res ? myTurn({ ...base, hand: myHand, risk: Object.fromEntries(res.threats.map(t => [t.key, t.likely])) }) : null;
  const onBoard = new Set(toks.map(t => t.tk));
  const off = st.armies[opp].units.filter(u => !onBoard.has(`${opp}:${u.key}`) && !unitInfo(opp, u.key)?.dead);
  const v = { me, opp, g, res, my, hand, myHand, fresh: liveFresh(lv, g),
    embarked: off.filter(u => inside.has(`${opp}:${u.key}`)).map(u => u.name), reserves: off.filter(u => !inside.has(`${opp}:${u.key}`)).map(u => u.name),
    mineOn: toks.filter(t => t.side === me).length, theirsOn: toks.filter(t => t.side === opp).length };
  if (my) console.log(`[board] my turn (${me}): ${my.units.filter(u => u.job.kind === 'take').length} units sent to take an objective, ${my.units.filter(u => u.job.kind === 'hold').length} holding, ${my.kills.length} targets (best ${my.kills[0] ? `${my.kills[0].name} ${Math.round(my.kills[0].p * 100)}%` : '-'}), ${my.cards.filter(c => c.verdict === 'yes').length} of ${myHand.length} cards by moving (${my.vp} VP)`);
  if (res) console.log(`[board] their next turn (${opp}): ${res.threats.filter(x => x.likely >= 0.25).length} of my units likely destroyed at 25%+, ${res.swing.filter(o => o.verdict === 'lose' || o.verdict === 'take').length} objectives they can take, ${res.cards.filter(c => c.verdict === 'yes').length} of ${hand.length} cards by moving (${res.vpAtStake} VP) — ${((performance.now?.() ?? 0) - t0).toFixed(0)} ms`);
  nextMemo = { key, v, base };
  if (my) weighMoves(key, v, base.mine, l.pieces, objs.find(o => o.cls === 'home' && o.side === me) ?? null, base.theirs, pair);
  return v;
}
// ---- a suggestion tapped on a card, shown on the map: the unit ringed, its suggested move as a dashed arrow to
// dashed bases, its target (or who attacks it) as solid arrows. b.hint = { kind: 'my-unit' | 'my-kill' | 'their-unit', tk };
// what is drawn is read from the cards' own data each time, so it follows the table.
const HINT = { ring: '#f2c200', move: '#1d6fd1', hit: '#c0392b' };
/** -> { units: [tk] (ringed), move: { tk, x, y, dist, label, hosted, vp } | null, hits: [{ from, to, pct, how }], text } | null */
function hintData() {
  const b = boardState(), h = b.hint, d = nextMemo.v;
  if (!h || !d?.res || !livePlan()) return null;
  const pct = (p) => `${Math.round(p * 100)}%`;
  const full = (tk) => { const [s, k] = tk.split(':'); return ctx.state.armies[s]?.units.find(u => u.key === k)?.name ?? tk; };
  if (h.kind === 'my-unit') {
    const u = d.my?.units.find(x => x.key === h.tk);
    if (!u) return null;
    const k = moveMemo.key === nextMemo.key ? moveMemo.kept?.moves.find(x => x.unit === h.tk) : null;
    const move = k ? { tk: h.tk, x: k.x, y: k.y, dist: k.dist, label: k.label, hosted: !!k.hosted, back: k.kind === 'back', vp: k.addVp } : null;
    const hits = u.attack ? [{ from: h.tk, to: u.attack.key, pct: pct(u.attack.p), how: u.attack.how }] : [];
    const bits = [move ? (move.back ? `pull back ${fmtIn(move.dist)} towards your home` : `move ${fmtIn(move.dist)} ${move.hosted ? `into the terrain area of ${move.label}` : `to within range of ${move.label}`}`) : u.job.kind === 'hold' ? `hold ${u.job.label}` : '',
      u.attack ? `${u.attack.how} ${full(u.attack.key)} (${pct(u.attack.p)} destroyed)` : ''].filter(Boolean);
    return { units: [h.tk], move, hits, text: `${full(h.tk)}: ${bits.join('; then ') || 'nothing suggested'}` };
  }
  if (h.kind === 'my-kill') {
    const k = d.my?.kills.find(x => x.key === h.tk);
    if (!k) return null;
    return { units: [h.tk], move: null, hits: k.by.map(x => ({ from: x.key, to: h.tk, pct: '', how: '' })), text: `${full(h.tk)}: ${pct(k.p)} destroyed by ${k.by.map(x => full(x.key)).join(', ')}` };
  }
  const t = d.res.threats.find(x => x.key === h.tk);
  if (!t) return null;
  const by = t.by.slice(0, 5);
  return { units: [h.tk], move: null, hits: by.map(x => ({ from: x.key, to: h.tk, pct: '', how: '', theirs: true })), text: `${full(h.tk)}: ${pct(t.likely)} likely destroyed, ${pct(t.focus)} if focused, by ${by.map(x => full(x.key)).join(', ')}` };
}
/** An arrow on the map (board inches): a line with a head, an optional label at its middle. */
function arrowSvg(x1, y1, x2, y2, col, dash, label) {
  const len = Math.hypot(x2 - x1, y2 - y1);
  if (len < 0.3) return '';
  const ux = (x2 - x1) / len, uy = (y2 - y1) / len, hx = x2 - ux * 1.5, hy = y2 - uy * 1.5;
  const head = `${f2(x2)},${f2(y2)} ${f2(hx - uy * 0.75)},${f2(hy + ux * 0.75)} ${f2(hx + uy * 0.75)},${f2(hy - ux * 0.75)}`;
  const lab = label ? `<text x="${f2((x1 + x2) / 2)}" y="${f2((y1 + y2) / 2 - 0.5)}" font-size="1.25" font-weight="700" text-anchor="middle" fill="${col}" paint-order="stroke" stroke="${C.mat}" stroke-width="0.4" font-family="system-ui,sans-serif">${ctx.esc(label)}</text>` : '';
  return `<line x1="${f2(x1)}" y1="${f2(y1)}" x2="${f2(hx)}" y2="${f2(hy)}" stroke="${C.mat}" stroke-width="0.9" stroke-linecap="round"/><line x1="${f2(x1)}" y1="${f2(y1)}" x2="${f2(hx)}" y2="${f2(hy)}" stroke="${col}" stroke-width="0.45" stroke-linecap="round" ${dash ? 'stroke-dasharray="1 0.7"' : ''}/><polygon points="${head}" fill="${col}" stroke="${C.mat}" stroke-width="0.15"/>${lab}`;
}
function hintSvg() {
  const hd = hintData();
  if (!hd) return '';
  const toks = new Map(placed().map(t => [t.tk, t]));
  const reach = (t) => Math.max(...t.models.map(m => Math.hypot(m.dx, m.dy) + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0)));
  const arrow = (x1, y1, x2, y2, col, dash, label, id) => {
    const len = Math.hypot(x2 - x1, y2 - y1);
    if (len < 0.3) return '';
    const ux = (x2 - x1) / len, uy = (y2 - y1) / len, hx = x2 - ux * 1.5, hy = y2 - uy * 1.5;
    const head = `${f2(x2)},${f2(y2)} ${f2(hx - uy * 0.75)},${f2(hy + ux * 0.75)} ${f2(hx + uy * 0.75)},${f2(hy - ux * 0.75)}`;
    const lab = label ? `<text x="${f2((x1 + x2) / 2)}" y="${f2((y1 + y2) / 2 - 0.5)}" font-size="1.25" font-weight="700" text-anchor="middle" fill="${col}" paint-order="stroke" stroke="${C.mat}" stroke-width="0.4" font-family="system-ui,sans-serif">${ctx.esc(label)}</text>` : '';
    return `<g data-hint="${id}"><line x1="${f2(x1)}" y1="${f2(y1)}" x2="${f2(hx)}" y2="${f2(hy)}" stroke="${C.mat}" stroke-width="0.9" stroke-linecap="round"/><line x1="${f2(x1)}" y1="${f2(y1)}" x2="${f2(hx)}" y2="${f2(hy)}" stroke="${col}" stroke-width="0.45" stroke-linecap="round" ${dash ? 'stroke-dasharray="1 0.7"' : ''}/><polygon points="${head}" fill="${col}" stroke="${C.mat}" stroke-width="0.15"/>${lab}</g>`;
  };
  const out = [];
  for (const tk of hd.units) { const t = toks.get(tk); if (t) out.push(`<circle data-hint="ring" data-tk="${ctx.esc(tk)}" cx="${f2(t.x)}" cy="${f2(t.y)}" r="${f2(reach(t) + 0.8)}" fill="none" stroke="${HINT.ring}" stroke-width="0.45"/><circle cx="${f2(t.x)}" cy="${f2(t.y)}" r="${f2(reach(t) + 0.8)}" fill="none" stroke="#111" stroke-width="0.12" stroke-dasharray="0.6 0.5"/>`); }
  if (hd.move) {
    const t = toks.get(hd.move.tk);
    if (t) {
      out.push(`<g data-hint="ghost" transform="translate(${f2(hd.move.x)},${f2(hd.move.y)})" opacity="0.9">${t.models.map(m => shapeSvg(m.fp, m.dx, m.dy, 'rgba(29,111,209,0.18)', HINT.move, 0.16, m.rot)).join('')}</g>`);
      out.push(arrow(t.x, t.y, hd.move.x, hd.move.y, HINT.move, true, fmtIn(hd.move.dist), 'move'));
    }
  }
  for (const h of hd.hits) {
    const a0 = toks.get(h.from), z = toks.get(h.to);
    if (!a0 || !z) continue;
    // after its suggested move, the attack starts where the move ends
    const a = hd.move && hd.move.tk === h.from ? { x: hd.move.x, y: hd.move.y } : a0;
    const len = Math.hypot(z.x - a.x, z.y - a.y) || 1, back = Math.min(len * 0.4, reach(z) * 0.6);
    out.push(arrow(a.x, a.y, z.x - (z.x - a.x) / len * back, z.y - (z.y - a.y) / len * back, HINT.hit, false, h.pct, 'hit'));
  }
  return `<g id="hint-layer" data-kind="${boardState().hint.kind}" data-tk="${ctx.esc(boardState().hint.tk)}" pointer-events="none">${out.join('')}</g>`;
}
/** Above the map while a suggestion is shown on it: what the arrows mean, in full names, and a way to clear it. */
function hintBarHtml() {
  const hd = hintData();
  if (!hd) return '';
  return `<div class="card hint-bar" id="board-hint-bar"><div class="row" style="gap:8px;align-items:center"><span class="grow small"><b>On the map:</b> ${ctx.esc(hd.text)}.${hd.move ? ` <span class="muted">Dashed blue: the move${hd.move.hosted && !hd.move.back ? ' (a base in the terrain area the objective is in counts as in range)' : ''}.</span>` : ''}${hd.hits.length ? ' <span class="muted">Red: the attack.</span>' : ''}</span>
    <button class="icon-btn" data-action="board-hint-clear" id="board-hint-clear" aria-label="Clear the suggestion from the map">✕</button></div></div>`;
}

/** Card rows for "Their next turn" and "My turn": what it pays, by moving / by a kill / not this turn, and why. */
function cardRows(cards, offTurnNote, good = false) {
  const esc = ctx.esc, pct = (p) => `${Math.round(p * 100)}%`;
  const ICON = { yes: '✅', now: '⏳', kill: '🎯', ask: '❓', no: '—' };
  return cards.map(c => `<div class="next-card" data-card="${esc(c.id)}" data-verdict="${c.verdict}"><div class="row" style="gap:6px;align-items:baseline"><span>${ICON[c.verdict]}</span><b>${esc(c.name)}</b><span class="grow"></span>
        <span class="verd ${c.verdict === 'yes' || c.verdict === 'now' ? (good ? 'ok' : 'bad') : c.verdict === 'kill' ? 'warn' : ''}">${c.verdict === 'no' ? 'not this turn' : `${c.vp} VP${c.verdict === 'kill' && c.p != null ? ` · ${pct(c.p)}` : c.verdict === 'ask' ? ' ?' : ''}`}</span></div>
        <div class="tiny muted">${(good ? c.offTurn : c.when === 'mine') ? `<b>${esc(offTurnNote)}</b> ` : ''}${esc(c.why)}</div></div>`).join('');
}
// ---- "Ask for a plan" (advise.mjs, server/calc-advise.js): the cards' own data and both armies' rules text go to
// Claude, which writes a short plan for the turn. Off unless the server has an API key. Asked for only on a tap,
// after the player has agreed once to what is sent. b.advice = { key (the table it was asked for), state: 'asking' |
// 'done' | 'error', text, error, round, turn, ms }
let adviseInfo = null;
const ADVISE_OK_KEY = 'w40k_calc_advise_ok_v1';
const adviseAgreed = () => { try { return localStorage.getItem(ADVISE_OK_KEY) === '1'; } catch { return false; } };
/** A unit that is not on the table and not destroyed: when and where it can arrive (20.03 / 20.04, 24.09: planeval ARRIVE). */
function reserveNote(X, key, round) {
  const ds = !!unitInfo(X, key)?.flags?.deepStrike;
  if (round < 2) return 'in reserves: cannot arrive before battle round 2';
  if (round > 3) return 'in reserves: a unit still in reserves at the end of battle round 3 is destroyed';
  return ds ? 'in reserves: can arrive this turn by Deep Strike, anywhere more than 8" from all enemy units'
    : `in reserves: can arrive this turn wholly within 6" of a battlefield edge and more than 8" from all enemy units${round < 3 ? ', not in the enemy deployment zone' : ''}`;
}
/** What is sent for the table on screen (null until the cards have worked it out). */
function adviseRequest() {
  const d = nextMemo.v, st = ctx.state;
  if (!d?.res || !d.my) return null;
  const g = gameNow(), ms = missionsFor(dispOf('A'), dispOf('B')), toks = new Map(placed().map(t => [t.tk, t])), inside = embarkedIn(stepTokens());
  const armyOf = (X) => ({ faction: st.armies[X].faction, units: st.armies[X].units.map(u => ({ name: u.name, points: u.points, models: u.models, keywords: u.keywords ?? [], abilities: abilitiesOf(u).map(a => ({ name: a.name, text: a.text })) })), stratagems: armyIntel(st.armies[X]).stratagems });
  const nowOf = (X) => st.armies[X].units.map(u => { const tk = `${X}:${u.key}`, t = toks.get(tk); return { name: u.name, modelsLeft: t ? t.models.length : 0, at: t ? [t.x, t.y] : null, status: t ? undefined : unitInfo(X, u.key)?.dead ? 'destroyed' : inside.has(tk) ? 'embarked in a transport' : reserveNote(X, u.key, g.round) }; });
  const card = (id) => { const c = SECONDARIES.find(x => x.id === id); return c ? { name: c.name, text: c.text } : { name: id, text: '' }; };
  return advisePayload({
    armies: { me: armyOf(d.me), them: armyOf(d.opp) },
    game: { round: g.round, mine: g.turn === d.me || !g.started, phase: g.phase, myMission: ms[d.me], theirMission: ms[d.opp], myCP: g.cp?.[d.me] ?? 0, theirCP: g.cp?.[d.opp] ?? 0, myVP: g.vp?.[d.me] ?? 0, theirVP: g.vp?.[d.opp] ?? 0 },
    hands: { me: (g.hand?.[d.me] ?? []).map(card), them: (g.hand?.[d.opp] ?? []).map(card) },
    unitsNow: { me: nowOf(d.me), them: nowOf(d.opp) },
    res: d.res, my: d.my, moves: moveMemo.key === nextMemo.key && moveMemo.state === 'done' ? moveMemo : null,
  });
}
async function askForPlan() {
  const b = boardState(), key = nextMemo.key, g = gameNow();
  const req = adviseRequest();
  if (!req) return;
  if (typeof navigator !== 'undefined' && navigator.onLine === false) { b.advice = { key, state: 'error', error: 'you are offline, and a plan needs a connection', round: g.round, turn: g.turn }; refreshBoard(); return; }
  const size = payloadSize(req), t0 = Date.now();
  b.advice = { key, state: 'asking', round: g.round, turn: g.turn };
  console.log(`[board] asking for a plan: ${size.static} + ${size.dynamic} characters`);
  const redraw = () => { const host = document.getElementById('board-next-host'); if (host) host.innerHTML = nextTurnHtml(); };
  redraw();
  try {
    const r = await fetch('/api/calc-advise', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(req) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || `The server answered ${r.status}`);
    b.advice = { key, state: 'done', text: String(j.text ?? ''), round: g.round, turn: g.turn, ms: Date.now() - t0, left: j.left, truncated: !!j.truncated };
    b.planOnMap = true; b.planFocus = null;
    console.log(`[board] plan received in ${b.advice.ms} ms (${b.advice.text.split(/\s+/).length} words, ${j.model})`);
  } catch (err) {
    b.advice = { key, state: 'error', error: err?.message || 'Could not get a plan', round: g.round, turn: g.turn };
    console.log(`[board] no plan: ${b.advice.error}`);
  }
  // the map too: the plan's steps are drawn on it
  refreshBoard();
  if (b.advice.state === 'done') planIntoView();
}
// ---- the same by hand, with no server and no API key: the prompt is copied, pasted into Claude (claude.ai or the
// Claude app), and Claude's answer is pasted back here. The pasted plan is kept with the live table (lv.advice).
const sigOf = (key) => { let h = 5381; for (let i = 0; i < key.length; i++) h = ((h << 5) + h + key.charCodeAt(i)) | 0; return String(h >>> 0); };
/** The plan on screen: one asked for or pasted in this visit, else the one kept with the live table. */
function currentAdvice() {
  const b = boardState();
  if (b.advice) return b.advice;
  const kept = livePlan()?.advice;
  return kept ? { ...kept, state: 'done', key: kept.sig === sigOf(nextMemo.key ?? '') ? nextMemo.key : null } : null;
}
async function copyPrompt() {
  const b = boardState(), req = adviseRequest();
  if (!req) return;
  const text = promptText(req);
  b.promptCopy = { chars: text.length, ok: false, text: null };
  try { await navigator.clipboard.writeText(text); b.promptCopy.ok = true; } catch { b.promptCopy.text = text; }   // no clipboard: the prompt is shown, to select and copy
  b.pasteOpen = true;
  console.log(`[board] prompt for Claude: ${text.length} characters, ${b.promptCopy.ok ? 'copied' : 'shown (the clipboard is not available)'}`);
  refreshBoard();
  if (!b.promptCopy.ok) document.getElementById('board-advise-prompt')?.select();
}
function pasteAnswer(fromText = null) {
  const b = boardState(), lv = livePlan(), g = gameNow();
  try {
    const text = tidyAnswer(fromText ?? document.getElementById('board-advise-paste')?.value ?? b.pasteDraft ?? '');
    if (!text) { b.pasteError = 'Paste Claude’s answer into the box first, then tap Show the plan.'; refreshBoard(); return; }
    if (!lv) { b.pasteError = 'Open the Live table first: the plan is kept with it.'; refreshBoard(); return; }
    b.advice = { key: nextMemo.key, state: 'done', text, round: g.round, turn: g.turn, pasted: true };
    lv.advice = { text, round: g.round, turn: g.turn, pasted: true, sig: sigOf(nextMemo.key ?? '') };
    b.pasteOpen = false; b.promptCopy = null; b.pasteDraft = ''; b.pasteError = null; b.planOnMap = true; b.planFocus = null;
    const pd = planData();
    console.log(`[board] plan pasted in: ${text.split(/\s+/).length} words, ${pd?.actions.filter(x => x.ok).length ?? 0} of ${pd?.actions.length ?? 0} actions drawn on the map, for round ${g.round}, ${g.turn}'s turn`);
    persistBoard();
    refreshBoard();
    planIntoView();
  } catch (err) {
    b.pasteError = `Could not show the plan: ${err?.message ?? err}`;
    console.log(`[board] ${b.pasteError}`);
    refreshBoard();
  }
}
async function pasteFromClipboard() {
  const b = boardState();
  try { const t = await navigator.clipboard.readText(); b.pasteDraft = t; pasteAnswer(t); }
  catch { b.pasteError = 'Your browser did not allow reading the clipboard: press and hold in the box and choose Paste.'; refreshBoard(); }
}
/** Bring something into view if it is not (the map with the plan drawn on it; the plan's text). */
function intoView(id, block = 'center') {
  const el = document.getElementById(id), r = el?.getBoundingClientRect();
  if (r && (r.top < 70 || r.bottom > (window.innerHeight || 0))) el.scrollIntoView({ block, behavior: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
}
/** After a plan arrives: the map when the plan is drawn on it (the bar above it says so), else the plan's text. */
function planIntoView() {
  const drawn = planData()?.actions.some(x => x.ok);
  intoView(drawn ? 'board-plan-bar' : 'board-advise-text', drawn ? 'start' : 'center');
}
/** Above the map while a plan is drawn on it: that it is Claude's plan, the step picked, and where its text is. */
function planBarHtml() {
  const b = boardState(), pd = planData();
  if (!pd || b.planOnMap === false) return '';
  const ok = pd.actions.filter(x => x.ok);
  if (!ok.length) return '';
  const esc = ctx.esc, VERB = { move: 'moves to', attack: 'attacks', hold: 'holds' };
  const f = b.planFocus != null ? pd.actions[b.planFocus] : null;
  return `<div class="card hint-bar plan-bar" id="board-plan-bar" data-actions="${ok.length}" data-focus="${f ? b.planFocus + 1 : ''}"><div class="row" style="gap:8px;align-items:center;flex-wrap:wrap">
      <span class="grow small"><b>🗺 Claude’s plan is drawn on the map</b>: ${f ? `step ${b.planFocus + 1} of ${pd.actions.length}, <b>${esc(f.unit)}</b> ${VERB[f.kind]} <b>${esc(f.target)}</b>.` : `${ok.length} step${ok.length === 1 ? '' : 's'}, numbered in the plan’s order.`}
        <span class="muted">Blue dashed: a move. Red: an attack. Green ring: stays on its objective.${pd.stale ? ' <span style="color:var(--warn-ink)">The table has changed since the plan was written.</span>' : ''}</span></span>
      ${f ? '<button class="btn ghost" data-action="board-plan-focus" data-i="-1" id="board-plan-all">Show all steps</button>' : ''}
      <button class="btn" data-action="board-plan-read" id="board-plan-read">Read the plan ↓</button>
      <button class="icon-btn" data-action="board-plan-map" aria-label="Take the plan off the map">✕</button></div></div>`;
}

// ---- the plan drawn on the map: Claude's ACTIONS lines (advise.parsePlan) against the units on the table
const PLAN = { move: '#1d6fd1', attack: '#c0392b', hold: '#2e9e5b' };
let planMemo = { key: null, v: null };
/** -> { text (the plan without its ACTIONS lines), actions: [resolved, with where a move ends], stale } | null */
function planData() {
  const a = currentAdvice(), d = nextMemo.v, l = currentLayout();
  if (!a || a.state !== 'done' || !d?.my || !l) return null;
  const toks = placed(), key = `${a.text.length}|${a.text.slice(0, 80)}|${nextMemo.key}`;
  if (planMemo.key === key) return planMemo.v;
  const parsed = parsePlan(a.text);
  const names = (X) => ctx.state.armies[X].units.map(u => ({ key: `${X}:${u.key}`, name: u.name }));
  const objs = d.my.swing.map(o => ({ id: o.id, name: o.label }));
  const byTk = new Map(toks.map(t => [t.tk, t]));
  const actions = resolveActions(parsed.actions, { mine: names(d.me), theirs: names(d.opp), objectives: objs }).map((x) => {
    if (!x.ok) return x;
    const t = byTk.get(x.unitKey);
    if (!t) return { ...x, ok: false, why: `${x.unit} is not on the table` };
    if (x.kind === 'attack') return byTk.get(x.targetKey) ? x : { ...x, ok: false, why: `${x.target} is not on the table` };
    const o = d.my.swing.find(q => q.id === x.objId), unit = { key: t.tk, name: x.unit, x: t.x, y: t.y, models: t.models, move: 99 };
    const gap = objectiveGap(unit, o, l.pieces);
    if (gap <= 0) return { ...x, there: true };
    // where the move ends: a straight line, just far enough for a model to be in range of the objective
    const end = moveCandidates([unit], [{ ...o, movers: [{ key: t.tk, via: 'move' }] }], l.pieces)[0];
    return end ? { ...x, x: end.x, y: end.y, dist: end.dist, far: end.dist > t.u.move + 0.01, M: t.u.move } : { ...x, ok: false, why: `no straight move puts ${x.unit} in range of ${x.target}` };
  });
  planMemo = { key, v: { text: parsed.text, actions, stale: a.key !== nextMemo.key } };
  return planMemo.v;
}
function planSvg() {
  const b = boardState(), pd = planData();
  if (!pd || b.planOnMap === false || !pd.actions.some(x => x.ok)) return '';
  const toks = new Map(placed().map(t => [t.tk, t]));
  const reach = (t) => Math.max(...t.models.map(m => Math.hypot(m.dx, m.dy) + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0)));
  const ends = new Map(pd.actions.filter(x => x.ok && x.kind === 'move' && !x.there).map(x => [x.unitKey, x]));
  const out = [];
  const focus = b.planFocus != null && pd.actions[b.planFocus]?.ok ? b.planFocus : null;
  pd.actions.forEach((x, i) => {
    const t = x.ok ? toks.get(x.unitKey) : null;
    if (!t) return;
    const at = out.length;
    planOne(x, i, t);
    if (focus != null && focus !== i && out.length > at) out[out.length - 1] = out[out.length - 1].replace('<g data-plan=', '<g opacity="0.18" data-dim="1" data-plan=');
  });
  function planOne(x, i, t) {
    // the action's number (as in the list under the plan): on the ring, where the move ends, or along the attack
    const badge = (bx, by) => `<g data-plan-n="${i + 1}"><circle cx="${f2(bx)}" cy="${f2(by)}" r="0.95" fill="${PLAN[x.kind]}" stroke="${C.mat}" stroke-width="0.15"/><text x="${f2(bx)}" y="${f2(by)}" font-size="1.2" font-weight="700" text-anchor="middle" dominant-baseline="central" fill="#fff" font-family="system-ui,sans-serif">${i + 1}</text></g>`;
    if (x.kind === 'hold' || x.there) {
      const R = reach(t) + 0.7;
      out.push(`<g data-plan="hold" data-tk="${ctx.esc(x.unitKey)}"><circle cx="${f2(t.x)}" cy="${f2(t.y)}" r="${f2(R)}" fill="none" stroke="${PLAN.hold}" stroke-width="0.4"/>${badge(t.x - R * 0.71, t.y - R * 0.71)}</g>`);
    } else if (x.kind === 'move') {
      out.push(`<g data-plan="move" data-tk="${ctx.esc(x.unitKey)}" data-dist="${x.dist.toFixed(2)}"><g transform="translate(${f2(x.x)},${f2(x.y)})" opacity="0.9">${t.models.map(m => shapeSvg(m.fp, m.dx, m.dy, 'rgba(29,111,209,0.18)', PLAN.move, 0.16, m.rot)).join('')}</g>${arrowSvg(t.x, t.y, x.x, x.y, PLAN.move, true, `${fmtIn(x.dist)}${x.far ? ' ⚠' : ''}`)}${badge(x.x + reach(t) + 0.6, x.y)}</g>`);
    } else {
      const z = toks.get(x.targetKey), from = ends.get(x.unitKey) ?? t;
      if (!z) return;
      const len = Math.hypot(z.x - from.x, z.y - from.y) || 1, back = Math.min(len * 0.4, reach(z) * 0.6);
      const ex = z.x - (z.x - from.x) / len * back, ey = z.y - (z.y - from.y) / len * back;
      out.push(`<g data-plan="attack" data-tk="${ctx.esc(x.unitKey)}" data-target="${ctx.esc(x.targetKey)}">${arrowSvg(from.x, from.y, ex, ey, PLAN.attack, false, '')}${badge(from.x + (ex - from.x) * 0.6, from.y + (ey - from.y) * 0.6)}</g>`);
    }
  }
  return `<g id="plan-layer" data-actions="${pd.actions.filter(x => x.ok).length}" pointer-events="none">${out.join('')}</g>`;
}
/** Under the plan text: what is drawn on the map, in the plan's own order, and what could not be placed. */
function planActionsHtml(pd) {
  if (!pd?.actions.length) return `<div class="tiny muted" id="board-plan-none" style="margin-top:6px">This answer has no ACTIONS lines, so there is nothing to draw on the map. Copy a new prompt: it asks Claude for them.</div>`;
  const esc = ctx.esc, on = boardState().planOnMap !== false, VERB = { move: 'moves to', attack: 'attacks', hold: 'holds' };
  const ok = pd.actions.filter(x => x.ok).length;
  return `<div class="row" style="gap:6px;margin-top:8px;align-items:center;flex-wrap:wrap" id="board-plan-map-row">${ctx.chip('board-plan-map', on, `🗺 On the map (${ok})`, 'id="board-plan-map"')}<span class="tiny muted">Blue dashed: a move, to where it ends. Red: an attack. Green ring: stays on its objective. Numbers follow the list.</span></div>
    <div class="tiny muted" style="margin-top:4px" id="board-plan-tap">Tap a step to see only that one on the map.</div>
    <ol class="plan-actions" id="board-plan-actions">${pd.actions.map((x, i) => `<li data-ok="${x.ok ? 1 : 0}" data-kind="${x.kind}" class="${x.ok ? 'tap' : ''} ${boardState().planFocus === i ? 'on' : ''}" ${x.ok ? `role="button" data-action="board-plan-focus" data-i="${i}"` : ''} style="color:${x.ok ? 'inherit' : 'var(--text-muted)'}"><span style="color:${x.ok ? PLAN[x.kind] : 'inherit'};font-weight:600">${esc(shortName(x.unit))}</span> ${VERB[x.kind]} <b>${esc(shortName(x.target))}</b>${x.ok ? (x.kind === 'move' ? (x.there ? ' <span class="muted">(already in range)</span>' : ` <span class="muted">(${fmtIn(x.dist)}${x.far ? `: more than its ${x.M}" Move, it needs an Advance` : ''})</span>`) : '') : ` <span class="muted">— not drawn: ${esc(x.why)}</span>`}</li>`).join('')}</ol>`;
}
/** The plan section of the Your turn card: copy the prompt and paste the answer (always), or ask through the server (where it is switched on). */
function adviceHtml() {
  if (!nextMemo.v?.my) return '';
  const esc = ctx.esc, b = boardState(), a = currentAdvice(), api = !!adviseInfo?.enabled;
  const stale = a && a.key !== nextMemo.key;
  const what = 'Both army lists and the units on this table are sent to Anthropic’s Claude through this app’s server, which writes the plan. This app’s server keeps none of it; Anthropic handles it under its API terms. It takes about half a minute.';
  const ask = (label, primary = true) => (api ? `<button class="btn ${primary ? 'primary' : 'ghost'}" data-action="board-advise" id="board-advise">${label}</button>` : '');
  const copy = (label, primary = !api) => `<button class="btn ${primary ? 'primary' : 'ghost'}" data-action="board-advise-copy" id="board-advise-copy">${label}</button>`;
  const pc = b.promptCopy;
  // copied (or shown): where to paste it, and the box for the answer
  const pasteBox = b.pasteOpen ? `<div class="card" id="board-advise-pastebox" style="margin-top:6px;padding:10px">
      ${pc ? `<div class="small" id="board-advise-copied">${pc.ok ? `✓ Prompt copied (${pc.chars.toLocaleString('en')} characters).` : 'Your browser did not allow copying. Select all of this and copy it:'} Paste it into a new chat with Claude: <a href="https://claude.ai/new" target="_blank" rel="noopener">claude.ai</a> or the Claude app.</div>` : ''}
      ${pc && !pc.ok ? `<textarea id="board-advise-prompt" class="paste" readonly rows="4" aria-label="The prompt for Claude">${esc(pc.text)}</textarea>` : ''}
      <label class="lab tiny muted" for="board-advise-paste" style="display:block;margin-top:8px">Then paste Claude’s answer here</label>
      <textarea id="board-advise-paste" class="paste" rows="5" placeholder="Paste the answer">${esc(b.pasteDraft ?? '')}</textarea>
      ${b.pasteError ? `<div class="small" id="board-advise-paste-error" style="color:var(--warn-ink);margin-top:4px">${esc(b.pasteError)}</div>` : ''}
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap"><button class="btn primary" data-action="board-advise-paste" id="board-advise-show">Show the plan</button><button class="btn" data-action="board-advise-clip" id="board-advise-clip">Paste from clipboard and show</button><button class="btn ghost" data-action="board-advise-paste-cancel">Cancel</button></div></div>` : '';
  let body;
  if (b.adviseAsk && !adviseAgreed()) body = `<div class="warnbox" id="board-advise-consent"><div>${what}</div><div class="row" style="gap:6px;margin-top:6px"><button class="btn primary" data-action="board-advise-agree" id="board-advise-agree">Send and ask</button><button class="btn ghost" data-action="board-advise-cancel">Not now</button></div></div>`;
  else if (a?.state === 'asking') body = `<div class="small muted" id="board-advise-wait">⏳ Claude is reading the table… about half a minute.</div>`;
  else if (a?.state === 'done') body = `<div class="small" id="board-advise-here" style="margin-bottom:6px"><b>✓ ${a.pasted ? 'This is the plan you pasted.' : 'This is Claude’s plan.'}</b> ${planData()?.actions.some(x => x.ok) ? 'Its steps are drawn on the map above, numbered; the full text is here.' : 'Read it here.'}</div>
      <div class="plan-text" id="board-advise-text" data-stale="${stale ? 1 : 0}" data-pasted="${a.pasted ? 1 : 0}">${esc(planData()?.text ?? a.text)}</div>
      ${planActionsHtml(planData())}
      <div class="tiny ${stale ? '' : 'muted'}" id="board-advise-note" style="margin-top:4px${stale ? ';color:var(--warn-ink)' : ''}">${stale ? '⚠ The table has changed since this plan was written.' : `${a.pasted ? 'Pasted in' : 'Written'} for round ${a.round}, ${esc(a.turn)}’s turn.`}${a.truncated ? ' The answer was cut short.' : ''} A suggestion from an AI model reading the cards above: check it against the table.</div>
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap">${copy(stale ? '📋 Copy a new prompt for this table' : '📋 Copy the prompt again', !api && stale)}${ask(stale ? 'Ask again for this table' : 'Ask again', stale)}<button class="btn ghost" data-action="board-advise-clear" id="board-advise-clear">Clear</button></div>${pasteBox}`;
  else if (a?.state === 'error') body = `<div class="small" id="board-advise-error" style="color:var(--warn-ink)">No plan: ${esc(a.error)}</div><div class="row" style="gap:6px;margin-top:6px">${ask('Try again')}${copy('📋 Copy the prompt instead', false)}</div>${pasteBox}`;
  else body = `<div class="row" style="gap:8px;align-items:center;flex-wrap:wrap">${copy('📋 Copy prompt for Claude')}${ask('✨ Ask Claude directly', false)}</div>
      <div class="tiny muted" style="margin-top:4px" id="board-advise-help">Copies a prompt with the cards above and both armies’ stratagem and ability text. Paste it into Claude (claude.ai or the Claude app, with your own plan), then paste its answer back here to keep the plan with the table.${api ? ' Ask Claude directly sends it through this app’s server instead; you are asked first.' : ''}</div>${pasteBox}`;
  return `<div class="lab tiny muted" style="margin-top:10px">Plan from Claude</div><div id="board-advise-box" data-state="${a?.state ?? 'idle'}" data-api="${api ? 1 : 0}">${body}</div>`;
}

/** "My turn": one suggestion per unit of mine (take / hold an objective, a card, its target), the targets worth destroying, my cards. */
function myTurnHtml(d) {
  const m = d.my;
  if (!m) return '';
  const esc = ctx.esc, b = boardState(), st = ctx.state;
  const pct = (p) => `${Math.round(p * 100)}%`;
  const ink = (X) => `var(--side-${X.toLowerCase()}-ink)`;
  const myNow = d.g.turn === d.me || !d.g.started;
  const open = b.myOpen !== false;
  const head = `<div class="row" style="gap:6px;align-items:center"><div class="title grow" id="board-my-title">🧭 ${myNow ? 'Your turn' : 'Your next turn'} · <span style="color:${ink(d.me)}">${esc(st.armies[d.me].faction)}</span></div>
      <button class="icon-btn" data-action="board-my-toggle" aria-expanded="${open}" aria-label="${open ? 'Hide' : 'Show'} your turn">${open ? '▴' : '▾'}</button></div>`;
  if (!open) return `<div class="card" id="board-my" data-open="0">${head}</div>`;
  const pick = (tk, html) => html;
  const JOB = { take: ['bad', '→ Take'], hold: ['ok', '■ Hold'], card: ['warn', '★'], none: ['', ''] };
  // moves weighed with the forecast (for the table this card was worked out for)
  const mv = moveMemo.key === nextMemo.key ? moveMemo : { state: 'idle' };
  const keptOf = new Map((mv.kept?.moves ?? []).map(x => [x.unit, x])), aloneOf = new Map((mv.best ?? []).map(x => [x.unit, x]));
  const sgn = (n, d = 0) => `${n >= 0 ? '+' : '−'}${Math.abs(n).toFixed(d)}`;
  const movesLine = mv.state === 'pending' ? `<div class="small muted" id="board-my-moves" data-state="pending">⏳ Weighing ${mv.n} move${mv.n === 1 ? '' : 's'} with the forecast…</div>`
    : mv.state !== 'done' ? ''
      : mv.kept.moves.length ? `<div class="small" id="board-my-moves" data-state="done" data-kept="${mv.kept.moves.length}" data-win="${mv.kept.win.toFixed(3)}" data-base="${mv.base.win.toFixed(3)}">📈 Forecast: with ${mv.kept.moves.length === 1 ? 'this move' : `these ${mv.kept.moves.length} moves`} you win <b>${pct(mv.kept.win)}</b> of games instead of ${pct(mv.base.win)} (<b>${sgn(mv.kept.vp - mv.base.vp)} VP</b> of margin). The table as it stands counts for this battle round; later rounds are forecast as on the Mission tab.</div>`
        : `<div class="small muted" id="board-my-moves" data-state="done" data-kept="0">📈 Forecast: none of the ${mv.n} move${mv.n === 1 ? '' : 's'} tried beats standing still by ${MOVE_MIN_VP} VP or more (you win ${pct(mv.base?.win ?? 0)} as it stands).</div>`;
  // units the forecast moves come first
  const ordered = [...m.units].sort((x, y) => (keptOf.get(y.key)?.addVp ?? -1) - (keptOf.get(x.key)?.addVp ?? -1));
  const all = !!b.myAll, busy = ordered.filter(u => u.job.kind !== 'none' || u.attack || u.risk >= 0.25 || keptOf.has(u.key)), shown = all ? ordered : busy.slice(0, 6);
  const unitsHtml = shown.map(u => {
    const [cls, verb] = JOB[u.job.kind];
    const k = keptOf.get(u.key), alone = aloneOf.get(u.key);
    // the forecast's move for this unit; else the measured job (a "take" the forecast does not back is said so)
    const job = k ? `<span class="verd go" data-move="${esc(k.obj ?? 'back')}" data-dvp="${k.addVp.toFixed(2)}">${k.kind === 'back' ? `↩ Pull back ${fmtIn(k.dist)}` : `→ Move ${fmtIn(k.dist)} ${k.hosted ? 'into' : 'to'} ${esc(k.label)}`} · ${sgn(k.addVp)} VP</span>`
      : u.job.kind === 'none' ? '' : mv.state === 'done' && u.job.kind === 'take' ? `<span class="verd them">${verb} ${esc(u.job.label)}?</span>`
        : `<span class="verd ${cls === 'bad' ? 'go' : cls}">${verb} ${esc(u.job.label)}</span>`;
    const thereNote = k && k.riskThere != null && (k.riskThere >= 0.05 || k.riskHere >= 0.05) ? ` <span data-risk-there="${k.riskThere.toFixed(3)}" style="color:${k.riskThere >= 0.25 ? 'var(--warn-ink)' : 'inherit'}">· ${pct(k.riskThere)} destroyed in their turn after the move${Math.abs(k.riskThere - k.riskHere) >= 0.05 ? ` (${pct(k.riskHere)} where it stands)` : ''}</span>` : '';
    const fNote = k ? (k.kind === 'obj' ? ` <span class="muted">· ${k.hosted ? 'a base in the terrain area the objective is in counts as in range' : 'ends within 3" of the objective'}</span>` : '') + thereNote : alone ? ` <span class="muted">· moving onto ${esc(alone.label)} alone ${sgn(alone.dVp)} VP, little on top of the other moves</span>`
      : mv.state === 'done' && u.job.kind === 'take' ? ' <span class="muted">· the forecast sees no gain in it</span>' : '';
    const atk = u.attack ? `${esc(u.attack.how.replace(/^./, ch => ch.toUpperCase()))} <b style="color:${ink(d.opp)}">${esc(shortName(u.attack.name))}</b> <span class="muted">(${u.attack.p < 0.05 ? 'it will not destroy it; nothing better in reach' : `${pct(u.attack.p)} destroyed${u.attack.with > 1 ? ` with ${u.attack.with - 1} other${u.attack.with > 2 ? 's' : ''}` : ''}`})</span>` : '<span class="muted">nothing in reach to attack</span>';
    return `<div class="next-unit tap${boardState().hint?.kind === 'my-unit' && boardState().hint.tk === u.key ? ' on' : ''}" role="button" tabindex="0" data-action="board-hint" data-kind="my-unit" data-tk="${esc(u.key)}" data-unit="${esc(u.key)}" data-job="${u.job.kind}" data-target="${esc(u.attack?.key ?? '')}">
      <div class="row" style="gap:6px;align-items:baseline">${pick(u.key, `<b style="color:${ink(d.me)}">${esc(shortName(u.name))}</b>`)}<span class="grow"></span>${job}</div>
      <div class="tiny">${atk}${u.job.note && !k ? ` <span class="muted">· ${esc(u.job.note)}</span>` : ''}${fNote}${u.risk >= 0.25 && !(k && k.riskThere != null) ? ` <span style="color:var(--warn-ink)">· ${pct(u.risk)} destroyed in their turn where it stands</span>` : ''}</div></div>`;
  }).join('');
  const killsHtml = m.kills.slice(0, 4).map(k => `<div class="next-obj tap${boardState().hint?.kind === 'my-kill' && boardState().hint.tk === k.key ? ' on' : ''}" role="button" tabindex="0" data-action="board-hint" data-kind="my-kill" data-tk="${esc(k.key)}" data-kill="${esc(k.key)}" data-p="${k.p.toFixed(3)}"><div class="row" style="gap:6px;align-items:center">${pick(k.key, `<b style="color:${ink(d.opp)}">${esc(shortName(k.name))}</b>`)}<span class="tiny muted">${k.points} pts</span><span class="grow"></span><span class="riskbar" aria-hidden="true"><i style="width:${Math.round(Math.min(1, k.p) * 100)}%"></i></span><b class="next-pct">${pct(k.p)}</b></div>
      <div class="tiny muted">${k.by.map(x => `${esc(shortName(x.name))} ${[x.shoot ? `🎯${x.shoot.now ? '' : '→'}` : '', x.engaged ? '⚔' : x.charge ? `⚔${pct(x.charge)}` : ''].filter(Boolean).join(' ')}`).join(' · ')}</div></div>`).join('');
  const cardsHtml = !d.myHand.length ? `<div class="small muted" id="board-my-nocards">No cards in your hand on the tracker (Mission → Play).</div>` : cardRows(m.cards, 'At the end of their turn, as the table stands:', true);
  return `<div class="card" id="board-my" data-state="ready" data-vp="${m.vp}" data-moves="${mv.state}">${head}
    ${movesLine}
    ${playOutHtml(d)}
    <div class="lab tiny muted" style="margin-top:8px">Each unit <span id="board-my-tap">· tap a row to see it on the map</span></div><div id="board-my-units">${unitsHtml || '<div class="small muted">Nothing in reach of an objective or a target this turn.</div>'}</div>
    ${m.units.length > shown.length || all ? `<button class="chip" data-action="board-my-all" id="board-my-all" style="margin-top:4px">${all ? 'Fewer' : `All ${m.units.length} units`}</button>` : ''}
    ${m.kills.length ? `<div class="lab tiny muted" style="margin-top:10px">Targets, best first</div><div id="board-my-kills">${killsHtml}</div>` : ''}
    <div class="lab tiny muted" style="margin-top:10px">Your cards${d.myHand.length && m.vp ? ` · <b style="color:#2e9e5b">${m.vp} VP by moving alone</b>` : ''}</div><div id="board-my-cards">${cardsHtml}</div>
    ${adviceHtml()}
    <div class="tiny muted" style="margin-top:8px" id="board-my-how">A suggestion per unit, not a plan checked move by move. Moves (→ with VP): each move onto an objective in reach, and a pull back for a unit at risk, is played out to the end of the game by the mission forecast (1,500 games each; the positions on the table count for the battle round in progress, the rounds after it are forecast as on the Mission tab) and kept if it beats standing still by ${MOVE_MIN_VP} VP of margin or more, alone and on top of the other moves. Targets: where the unit adds most to a kill (points, more for a unit on an objective or one a card of yours pays for). Its move and its target are both worked out from where it stands now, so after a move to an objective the target may be out of reach. Stratagems, reserves and terrain in the way of a move are not counted.</div>
  </div>`;
}
let nextTimer = null;
function nextTurnHtml() {
  const lv = livePlan();
  if (!lv) return '';
  const theirs = theirTurnHtml();
  const d = nextMemo.v;
  const mine = d?.my && /data-state="(ready|updating)"/.test(theirs) ? myTurnHtml({ ...d, g: gameNow() }) : '';
  // the card of the turn that is on comes first
  const g = gameNow(), me = d?.me ?? 'A';
  return g.started && g.turn !== me ? theirs + mine : mine + theirs;
}
function theirTurnHtml() {
  let d = nextTurnData(false);
  if (!d) return '';
  let updating = false;
  if (d.pending) {
    // work it out after this frame (a drop stays snappy); until then the card shows what it had
    if (!nextTimer && typeof setTimeout === 'function') nextTimer = setTimeout(() => {
      nextTimer = null;
      nextTurnData(true);
      const host = document.getElementById('board-next-host');
      if (host) host.innerHTML = nextTurnHtml();
    }, 40);
    updating = true;
    d = d.prev ?? { pendingOnly: true };
  }
  const esc = ctx.esc, b = boardState(), st = ctx.state;
  if (d.pendingOnly) return `<div class="card" id="board-next" data-state="wait"><div class="title">🔮 Their next turn</div><p class="muted small" style="margin:6px 0 0">Working it out…</p></div>`;
  const pct = (p) => `${Math.round(p * 100)}%`;
  const ink = (X) => `var(--side-${X.toLowerCase()}-ink)`;
  const theirTurn = d.g.turn === d.opp && d.g.started;
  const title = `${theirTurn ? 'Their turn now' : 'Their next turn'} · <span style="color:${ink(d.opp)}">${esc(st.armies[d.opp].faction)}</span>`;
  const open = b.nextOpen !== false;
  const head = `<div class="row" style="gap:6px;align-items:center"><div class="title grow" id="board-next-title">🔮 ${title}</div>
      <button class="icon-btn" data-action="board-next-toggle" aria-expanded="${open}" aria-label="${open ? 'Hide' : 'Show'} their next turn">${open ? '▴' : '▾'}</button></div>`;
  if (!open) return `<div class="card" id="board-next" data-open="0">${head}</div>`;
  if (!d.mineOn || !d.theirsOn) return `<div class="card" id="board-next" data-state="empty">${head}<p class="hint" style="margin:6px 0 0">Place both armies on the live table to see what they can do next turn.</p></div>`;
  if (!d.res) return `<div class="card" id="board-next" data-state="wait">${head}<p class="muted small" id="board-next-wait" style="margin:6px 0 0">Working out the unit-vs-unit odds of these two lists…</p></div>`;
  const r = d.res;
  const pick = (tk, html) => html;
  // --- my units at risk
  const risky = r.threats.filter(t => t.by.length);
  const all = !!b.nextAll, shown = all ? risky : risky.slice(0, 5);
  const bar = (p) => `<span class="riskbar" aria-hidden="true"><i style="width:${Math.round(Math.min(1, p) * 100)}%"></i></span>`;
  const byTxt = (x) => `${esc(shortName(x.name))} ${[x.shoot ? `🎯${x.shoot.now ? '' : '→'}` : '', x.engaged ? '⚔ in combat' : x.charge ? `⚔${pct(x.charge)}` : ''].filter(Boolean).join(' ')}`;
  const unitsHtml = risky.length ? `${shown.map(t => `<div class="next-unit tap${boardState().hint?.kind === 'their-unit' && boardState().hint.tk === t.key ? ' on' : ''}" role="button" tabindex="0" data-action="board-hint" data-kind="their-unit" data-tk="${esc(t.key)}" data-unit="${esc(t.key)}" data-likely="${t.likely.toFixed(3)}" data-focus="${t.focus.toFixed(3)}">
        <div class="row" style="gap:6px;align-items:center">${pick(t.key, `<b style="color:${ink(d.me)}">${esc(shortName(t.name))}</b>`)}<span class="grow"></span>${bar(t.likely)}<b class="next-pct">${pct(t.likely)}</b><span class="tiny muted">likely · ${pct(t.focus)} if focused</span></div>
        <div class="tiny muted">${t.by.slice(0, 4).map(byTxt).join(' · ')}${t.by.length > 4 ? ` · +${t.by.length - 4}` : ''}</div></div>`).join('')}
      ${risky.length > 5 ? `<button class="chip" data-action="board-next-all" id="board-next-all" style="margin-top:4px">${all ? 'Fewer' : `All ${risky.length} units in reach`}</button>` : ''}`
    : '<div class="small muted">Nothing of theirs can shoot or charge a unit of yours next turn.</div>';
  // --- objectives
  const mv = (m) => `${esc(shortName(m.name))} (OC ${m.oc}${m.via === 'advance' ? `, Advance ${m.need}+` : ''})`;
  const VERD = {
    theirs: ['them', 'They control it'], lose: ['bad', 'They can take it'], contest: ['warn', 'They can tie it (nobody controls)'], advance: ['warn', 'Only with an Advance'],
    safe: ['ok', 'Yours unless they kill the holders'], take: ['bad', 'Empty: they can take it'], open: ['', 'Out of their reach'],
  };
  const objHtml = r.swing.map(o => {
    const [cls, text] = VERD[o.verdict] ?? ['', o.verdict];
    const moveIn = o.movers.filter(m => m.via === 'move'), adv = o.movers.filter(m => m.via === 'advance');
    const who = o.verdict === 'advance' ? adv : moveIn.length ? moveIn : adv;
    const hold = o.holders.filter(h => h.oc > 0 || h.risk > 0);
    return `<div class="next-obj" data-obj="${esc(o.id)}" data-verdict="${o.verdict}"><div class="row" style="gap:6px;align-items:baseline"><b>${esc(o.label)}</b><span class="tiny muted">you ${o.mine} · them ${o.theirs} OC</span><span class="grow"></span><span class="verd ${cls}">${text}</span></div>
      ${who.length && o.verdict !== 'theirs' && o.verdict !== 'open' ? `<div class="tiny muted">${who.slice(0, 3).map(mv).join(' · ')}${who.length > 3 ? ` · +${who.length - 3}` : ''} → up to ${o.verdict === 'advance' ? o.maxAdvance : o.max} OC</div>` : ''}
      ${hold.length && o.verdict !== 'theirs' ? `<div class="tiny muted">Held by ${hold.slice(0, 3).map(h => `${esc(shortName(h.name))}${h.risk >= 0.05 ? ` <span style="color:var(--warn-ink)">(${pct(h.risk)} destroyed)</span>` : ''}`).join(' · ')}</div>` : ''}</div>`;
  }).join('');
  // --- their cards
  const cardsHtml = !d.hand.length ? `<div class="small muted" id="board-next-nocards">No cards in ${esc(d.opp)}'s hand on the tracker (Mission → Play: draw their cards there to see which they can score).</div>`
    : cardRows(r.cards, 'At the end of your turn, as the table stands:');
  const notes = [
    d.reserves.length ? `Not on the table and not counted: ${esc(d.reserves.slice(0, 4).map(shortName).join(', '))}${d.reserves.length > 4 ? ` and ${d.reserves.length - 4} more` : ''} (reserves arrive more than 8" away: a 9" charge, and their guns).` : '',
    d.embarked.length ? `Embarked and not counted: ${esc(d.embarked.slice(0, 4).map(shortName).join(', '))} (they get out within 3" of their transport).` : '',
  ].filter(Boolean);
  return `<div class="card" id="board-next" data-state="${updating ? 'updating' : 'ready'}" data-opp="${d.opp}" data-vp="${r.vpAtStake}"${updating ? ' style="opacity:.6"' : ''}>${head}
    ${d.fresh ? '' : `<div class="tiny" id="board-next-stale" style="color:var(--warn-ink);margin-top:2px">⚠ From positions that are not confirmed for this turn.</div>`}
    <div class="lab tiny muted" style="margin-top:8px">Your units they can destroy</div><div id="board-next-units">${unitsHtml}</div>
    <div class="lab tiny muted" style="margin-top:10px">Objectives</div><div id="board-next-objs">${objHtml}</div>
    <div class="lab tiny muted" style="margin-top:10px">Their cards${d.hand.length && r.vpAtStake ? ` · <b style="color:var(--warn-ink)">${r.vpAtStake} VP by moving alone</b>` : ''}</div><div id="board-next-cards">${cardsHtml}</div>
    ${notes.length ? `<div class="tiny muted" id="board-next-off" style="margin-top:8px">${notes.join('<br>')}</div>` : ''}
    <div class="tiny muted" style="margin-top:8px" id="board-next-how">Likely: each of their units attacks the target it is worth most against. If focused: everything in reach attacks that unit. 🎯 can shoot it now, 🎯→ after a normal move, ⚔ charge odds. Moves are straight lines (terrain in the way is not checked); stratagems are not counted.</div>
  </div>`;
}

// ---- branches (plantree.mjs)
/** Show path i, at the first turn after the split at `at` (or where it was). */
function viewPath(root, i, at) {
  root.v = i;
  const n = resolveSteps(root.variants, i).length;
  root.variants[i].cur = Math.min(n - 1, Math.max(at + 1, 0));
  const b = boardState();
  b.sel = b.sel2 = null;
}
/** Remove these paths (indices); the view goes to the nearest path that is left. */
function removePaths(root, idx) {
  const curId = root.variants[root.v]?.id;
  const gone = new Set(idx.map(i => root.variants[i].id));
  let keep = root.variants[root.v];
  while (keep && gone.has(keep.id)) keep = root.variants.find(v => v.id === keep.parent);
  root.variants = root.variants.filter(v => !gone.has(v.id));
  root.v = Math.max(0, root.variants.findIndex(v => v.id === (keep?.id ?? curId)));
}
/** The split a control in the tree panel belongs to: { pi, at }. */
function treeTarget(el) {
  const box = el.closest('.tsplit');
  const root = planRoot();
  if (!box || !root) return null;
  const pi = root.variants.findIndex(v => v.id === box.dataset.pi);
  return pi < 0 ? null : { pi, at: Number(box.dataset.at) };
}
/** Where a unit stands in a step (for the charge distance of a chance split). */
function tokenAt(tokens, tk) {
  const pos = tokens?.[tk];
  if (!pos || pos.in) return null; // not on the board (or embarked)
  const [side, key] = tk.split(':');
  const u = unitInfo(side, key);
  return u ? { x: pos.x, y: pos.y, models: tokenModels(u, pos) } : null;
}
/**
 * The worked-out chance of a chance split ("a unit is destroyed"): from the calculator's unit-vs-unit odds
 * (ctx.pairWipe: { shoot, fight } = chance the attacker destroys it alone), and for a charge the 2D6 odds of
 * the gap between the two units in the turn of the split (11.04). -> { p, why } | null
 */
export function splitChance(split) {
  const root = planRoot();
  const a = split?.auto;
  if (!root || !a?.atk || !a?.def || a.atk.split(':')[0] === a.def.split(':')[0]) return null;
  const pw = ctx.pairWipe?.(a.atk, a.def);
  if (!pw) return { p: null, why: 'working out the unit-vs-unit odds…' };
  if (a.how === 'shoot') return { p: pw.shoot, why: `destroyed by its shooting: ${Math.round(pw.shoot * 100)}%` };
  if (a.how !== 'charge') return { p: pw.fight, why: `destroyed in a fight: ${Math.round(pw.fight * 100)}%` };
  const step = resolveSteps(root.variants, split.pi)[split.at];
  const s1 = tokenAt(step?.tokens, a.atk), s2 = tokenAt(step?.tokens, a.def);
  if (!s1 || !s2) return { p: null, why: `place both units on the board in ${step?.name ?? 'that turn'} for the charge distance` };
  const gap = unitGap(s1, s2);
  if (gap <= ENGAGEMENT_RANGE) return { p: pw.fight, why: `already engaged; destroyed in a fight: ${Math.round(pw.fight * 100)}%` };
  const need = chargeRollNeeded(gap), pc = chargeOdds(need);
  return { p: pc * pw.fight, why: `charge ${gap.toFixed(1)}" needs ${need}+: ${Math.round(pc * 100)}% × destroyed in the fight ${Math.round(pw.fight * 100)}%` };
}
const autoP = (split) => splitChance(split)?.p ?? null;

/** The branches panel: every split of the plan on screen, its options, their chances, and "it happened". */
function treeHtml() {
  const root = planRoot();
  if (!root) return '';
  const vs = root.variants, ri = rootOf(vs, root.v);
  if (!vs.some((v, i) => v.parent != null && rootOf(vs, i) === ri)) return '';
  const esc = ctx.esc;
  const tree = treeOf(vs, ri, autoP);
  const units = (X) => (ctx.state.armies[X]?.units ?? []).map(u => [`${X}:${u.key}`, `${X} · ${u.name}`]);
  const sel = (input, val, opts, label) => `<select class="sel" data-input="${input}" aria-label="${label}"><option value="">${label}…</option>${opts.map(([v, n]) => `<option value="${esc(v)}" ${v === val ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select>`;
  const node = (n) => {
    if (!n.split) return '';
    const s = n.split, meta = vs[s.pi].splits[s.at];
    const after = resolveSteps(vs, s.pi)[s.at]?.name ?? `step ${s.at}`;
    const ch = s.kind === 'chance' ? splitChance({ ...meta, pi: s.pi, at: s.at }) : null;
    const auto = s.kind === 'chance' ? `<div class="tauto">${ctx.seg('board-split-auto', meta.auto ? 'wipe' : 'typed', [['typed', 'Type the chances'], ['wipe', 'A unit is destroyed']], 'compact')}
      ${meta.auto ? `<div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap">${sel('board-split-atk', meta.auto.atk, [...units('A'), ...units('B')], 'Attacker')}${sel('board-split-def', meta.auto.def, [...units('A'), ...units('B')], 'Unit destroyed')}</div>
        <div style="margin-top:6px">${ctx.seg('board-split-how', meta.auto.how ?? 'fight', [['shoot', 'Shooting'], ['fight', 'Fight'], ['charge', 'Charge + fight']], 'compact')}</div>
        <div class="tiny" style="margin-top:4px" data-auto-why>${ch ? `From the calculator: <b>${ch.p == null ? '…' : `${Math.round(ch.p * 100)}%`}</b> (${esc(ch.why)}). Type a chance below to use your own.` : 'Pick the attacking unit and the unit at risk.'}</div>` : ''}</div>` : '';
    const opts = n.options.map((o, oi) => {
      const on = o.vi === root.v, gone = s.chosen && s.chosen !== o.id, hit = s.chosen === o.id;
      return `<div class="topt${on ? ' on' : ''}${gone ? ' gone' : ''}" data-vid="${esc(o.id)}">
        <div class="row" style="gap:6px;align-items:center;flex-wrap:wrap">
          <button class="chip nocheck${on ? ' on' : ''}" data-action="board-branch-view" data-vid="${esc(o.id)}" aria-label="Show ${esc(o.label)} on the board">${on ? '◉' : '○'}</button>
          <input class="sel grow tlabel" data-input="board-branch-label" data-vid="${esc(o.id)}" value="${esc(o.label)}" maxlength="40" aria-label="Name of this option">
          ${s.kind === 'chance' ? `<span class="tpct"><input class="num" type="number" min="0" max="100" inputmode="numeric" data-input="board-branch-p" data-vid="${esc(o.id)}" value="${o.typed ? Math.round(o.p * 100) : ''}" placeholder="${Math.round(o.p * 100)}" aria-label="Chance of ${esc(o.label)} (%)">%</span>` : ''}
          <button class="mini${hit ? ' on' : ''}" data-action="board-branch-chosen" data-vid="${esc(o.id)}">${hit ? '✓ ' : ''}${s.kind === 'chance' ? 'Happened' : 'Chosen'}</button>
          ${o.vi !== s.pi ? `<button class="icon-btn" data-action="board-branch-delete" data-vid="${esc(o.id)}" aria-label="Delete the branch ${esc(o.label)}">✕</button>` : ''}
        </div>
        ${o.node.split && !gone ? `<div class="tsub">${node(o.node)}</div>` : ''}</div>`;
    }).join('');
    return `<div class="tsplit" data-pi="${esc(vs[s.pi].id)}" data-at="${s.at}" data-kind="${s.kind}">
      <div class="row" style="gap:8px;align-items:center;flex-wrap:wrap"><span class="small">After <b>${esc(after)}</b></span>${ctx.seg('board-split-kind', s.kind, [['decision', '◆ My decision'], ['chance', '● Chance']], 'compact')}</div>
      ${auto}${opts}
      <button class="btn ghost" style="margin-top:4px" data-action="board-branch-add">＋ Another option</button></div>`;
  };
  return `<div class="card" id="board-tree" style="margin-top:8px"><div class="title">Branches of “${esc(vs[ri].name)}”</div>
    <div class="tiny muted" style="margin:2px 0 6px">◉ is on the board: <b>${esc(choiceLabel(vs, root.v))}</b>. Turns before a split are shared by every branch. Tap “${'Happened'}” or “Chosen” when you know; Mission → Plan compares the branches.</div>
    ${node(tree)}</div>`;
}

// ---- the branch map: every path of the plan at a glance (turns left to right, one row per path); tap a turn of a
// path to put it on the board; each path's win chance from the forecast (Mission → Plan, or ⚡ here); compare the
// positions of another path at the same turn (ghost bases on the board)
const shortStep = (name, i) => (i === 0 ? 'D' : /^Turn (\d+)/.exec(name ?? '')?.[1] ? `T${/^Turn (\d+)/.exec(name)[1]}` : String(i));
/** The part of the path on screen each variant owns: variant index -> [first step, last step]. */
function pathOwners(vs, vi) {
  const c = chain(vs, vi), out = new Map();
  c.forEach((k, j) => {
    const start = j === 0 ? 0 : vs[k].from + 1;
    const end = j === c.length - 1 ? resolveSteps(vs, k).length - 1 : vs[c[j + 1]].from;
    out.set(k, [start, end]);
  });
  return out;
}
function treeMapData() {
  const root = planRoot();
  if (!root) return null;
  const vs = root.variants, ri = rootOf(vs, root.v);
  if (!vs.some((v, k) => v.parent != null && rootOf(vs, k) === ri)) return null;
  const w = ctx.branchWins?.() ?? { wins: {}, busy: false };
  const ev = evaluate(treeOf(vs, ri, autoP), (vi) => w.wins[vi] ?? null);
  return { root, vs, ri, ev, rows: treeRows(ev), w };
}
function treeMapHtml() {
  const d = treeMapData();
  if (!d) return '';
  const { root, vs, ri, ev, rows, w } = d;
  const esc = ctx.esc;
  const steps = new Map(rows.map(r => [r.vi, resolveSteps(vs, r.vi)]));
  const ncol = Math.max(...[...steps.values()].map(s => s.length));
  const rowOf = new Map(rows.map((r, i) => [r.vi, i]));
  const twoLines = rows.some(r => r.path.length > 1);
  const W = 360, X0 = 12, RH = twoLines ? 36 : 30, Y0 = 30, CW = Math.min(30, 150 / Math.max(1, ncol - 1));
  const x = (c) => X0 + c * CW, y = (r) => Y0 + r * RH;
  const LX = x(ncol - 1) + 16, H = y(rows.length - 1) + 16;
  const own = (vi) => [vs[vi].parent != null ? vs[vi].from + 1 : 0, steps.get(vi).length - 1];
  const onPath = pathOwners(vs, root.v);
  const isOn = (vi, c) => { const r = onPath.get(vi); return !!r && c >= r[0] && c <= r[1]; };
  const cur = curIndex();
  const fullSteps = resolveSteps(vs, ri);
  const parts = [];
  // turn names along the top
  for (let c = 0; c < ncol; c++) {
    const nm = [...steps.values()].find(s => s[c])?.[c]?.name;
    parts.push(`<text class="tm-col" x="${x(c)}" y="12" text-anchor="middle">${esc(shortStep(nm, c))}</text>`);
  }
  parts.push(`<text class="tm-col" x="${W - 4}" y="12" text-anchor="end">${Object.keys(w.wins).length ? 'You win' : ''}</text>`);
  // lines: the turns of each path, and where a branch leaves its parent
  for (const r of rows) {
    const vi = r.vi, [s0, s1] = own(vi), yy = y(rowOf.get(vi));
    const fade = r.gone ? ' gone' : '';
    if (vs[vi].parent != null) {
      const pi = vs.findIndex(v => v.id === vs[vi].parent), py = y(rowOf.get(pi)), x1 = x(vs[vi].from), x2 = x(s0), xm = (x1 + x2) / 2;
      parts.push(`<path class="tm-edge${isOn(vi, s0) ? ' on' : ''}${fade}" d="M${x1} ${py} C${xm} ${py} ${xm} ${yy} ${x2} ${yy}"/>`);
    }
    for (let c = s0; c < s1; c++) parts.push(`<line class="tm-edge${isOn(vi, c + 1) ? ' on' : ''}${fade}" x1="${x(c)}" y1="${yy}" x2="${x(c + 1)}" y2="${yy}"/>`);
  }
  // the turns: tap one to put that path, at that turn, on the board
  for (const r of rows) {
    const vi = r.vi, [s0, s1] = own(vi), yy = y(rowOf.get(vi));
    for (let c = s0; c <= s1; c++) {
      const split = vs[vi].splits?.[c] && optionsAt(vs, vi, c).length > 1 ? vs[vi].splits[c] : null;
      const on = isOn(vi, c), here = on && c === cur;
      const cls = `tm-node${on ? ' on' : ''}${r.gone ? ' gone' : ''}`;
      const shape = split?.kind === 'chance' ? `<circle class="${cls}" cx="${x(c)}" cy="${yy}" r="6"/>`
        : split ? `<rect class="${cls}" x="${x(c) - 5}" y="${yy - 5}" width="10" height="10" transform="rotate(45 ${x(c)} ${yy})"/>`
          : `<circle class="${cls}" cx="${x(c)}" cy="${yy}" r="4"/>`;
      parts.push(`<g class="tm-go" data-action="board-tree-go" data-vid="${esc(vs[vi].id)}" data-i="${c}" role="button" aria-label="${esc(choiceLabel(vs, vi))}, ${esc(steps.get(vi)[c]?.name ?? '')}">
        <circle cx="${x(c)}" cy="${yy}" r="${Math.max(10, CW / 2)}" fill="transparent"/>${here ? `<circle class="tm-here" cx="${x(c)}" cy="${yy}" r="9"/>` : ''}${shape}</g>`);
    }
  }
  // one label per path: the last choice on the way there, its chance, the win chance; tap it to show that path
  for (const r of rows) {
    const vi = r.vi, yy = y(rowOf.get(vi)), last = r.path.at(-1);
    const on = vi === root.v;
    const lab = last?.label ?? vs[vi].name;
    const room = Math.max(6, Math.floor((W - LX - 46) / 6.6));
    const txt = lab.length > room ? `${lab.slice(0, room - 1)}…` : lab;
    const chance = r.path.some(c => c.kind === 'chance' && !c.hit) && !r.gone ? ` <tspan class="tm-p">${Math.round(r.reach * 100)}%</tspan>` : '';
    const mark = r.gone ? '' : r.path.length && r.path.every(c => c.hit || c.kind !== 'chance' && !c.open) && r.path.some(c => c.hit) ? '✓ ' : r.onBest ? '★ ' : '';
    const wv = w.wins[vi];
    parts.push(`<g class="tm-row${on ? ' on' : ''}${r.gone ? ' gone' : ''}" data-action="board-tree-go" data-vid="${esc(vs[vi].id)}" data-i="-1" role="button" aria-label="Show ${esc(choiceLabel(vs, vi))}">
      <rect x="${LX - 6}" y="${yy - RH / 2 + 2}" width="${W - LX + 6}" height="${RH - 4}" rx="6" class="tm-hit"/>
      <text class="tm-lab" x="${LX}" y="${yy + (r.path.length > 1 ? 0 : 4)}">${mark}${esc(txt)}${chance}</text>${r.path.length > 1 ? `<text class="tm-sub" x="${LX}" y="${yy + 12}">after ${esc(r.path.slice(0, -1).map(c => c.label).join(' ▸ ').slice(0, room + 8))}</text>` : ''}
      <text class="tm-win" x="${W - 6}" y="${yy + 4}" text-anchor="end">${wv == null ? (w.busy ? '…' : '') : `${Math.round(wv * 100)}%`}</text></g>`);
  }
  const svg = `<svg class="tm-svg" viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="The branches of this plan: turns left to right, one row per path">${parts.join('')}</svg>`;
  // the plan's worth, the best decision now; or work the win chances out
  const missing = rows.some(r => w.wins[r.vi] == null);
  const top = ev.split && !ev.split.chosen && ev.split.kind === 'decision' && ev.best ? ev.options.find(o => o.id === ev.best) : null;
  const head = ev.value != null ? `You win <b>${Math.round(ev.value * 100)}%${ev.partial ? '*' : ''}</b>${top ? ` · best now: <b>${esc(top.label)}</b>` : ''}` : 'Win chance of each path:';
  const act = w.table ? '<span class="tiny muted">(not worked out in table mode)</span>'
    : w.busy ? '<span class="tiny muted" id="board-tree-busy">working out…</span>'
      : missing ? '<button class="chip" data-action="board-tree-forecast" id="board-tree-forecast">⚡ Work out win chances</button>' : '';
  // compare: another path's units at this turn, as ghost bases on the board
  const cmpId = boardState().cmp;
  const others = rows.filter(r => r.vi !== root.v);
  const cmpSel = `<select class="sel" data-input="board-cmp" id="board-cmp" aria-label="Compare with another path"><option value="">Compare with…</option>${others.map(r => `<option value="${esc(vs[r.vi].id)}" ${vs[r.vi].id === cmpId ? 'selected' : ''}>${esc(choiceLabel(vs, r.vi))}</option>`).join('')}</select>`;
  const diff = compareInfo();
  const shut = !!boardState().tmHide;
  const fold = `<button class="icon-btn" data-action="board-tree-fold" id="board-tree-fold" aria-expanded="${!shut}" aria-label="${shut ? 'Show' : 'Hide'} the branch map">${shut ? '▸' : '▾'}</button>`;
  if (shut) {
    return `<div class="card tm" id="board-treemap" data-shut="1"><div class="row" style="gap:6px;align-items:center">${fold}<span class="small grow">⑂ On the board: <b>${esc(choiceLabel(vs, root.v))}</b>${ev.value != null ? ` · you win ${Math.round(ev.value * 100)}%` : ''}</span></div>
      ${diff ? `<div class="tiny" id="board-cmp-info" style="margin-top:4px">${diff}</div>` : ''}</div>`;
  }
  return `<div class="card tm" id="board-treemap">
    <div class="row" style="gap:6px;align-items:center;flex-wrap:wrap">${fold}<span class="small grow">⑂ <b>${esc(vs[ri].name)}</b>: ${head}</span>${act}</div>
    ${svg}
    <div class="tiny muted">Tap a turn to see it · ◆ your decision · ● chance · ★ best · % = chance to get there</div>
    <div class="row" style="gap:6px;margin-top:6px;align-items:center">${cmpSel}</div>
    ${diff ? `<div class="tiny" id="board-cmp-info" style="margin-top:4px">${diff}</div>` : ''}</div>`;
}

/** The path picked under "Compare with…": its units at the turn on screen (or its last turn). */
function compareTokens() {
  const root = planRoot(), id = boardState().cmp;
  if (!root || !id) return null;
  const k = root.variants.findIndex(v => v.id === id);
  if (k < 0 || k === root.v || rootOf(root.variants, k) !== rootOf(root.variants, root.v)) return null;
  const st = resolveSteps(root.variants, k);
  const at = Math.min(curIndex(), st.length - 1);
  const all = st[at]?.tokens ?? {};
  return { k, name: choiceLabel(root.variants, k), label: root.variants[k].branch?.label ?? root.variants[k].name, step: st[at]?.name ?? '', tokens: positioned(all), embarked: embarkedIn(all) };
}
const GHOST_MIN = 0.25; // inches: a unit nearer than this to where it is in the other path is "in the same place"
/** Tokens with a position (embarked units left out). */
const positioned = (tokens) => Object.fromEntries(Object.entries(tokens ?? {}).filter(([, p]) => !p?.in));
function compareInfo() {
  const c = compareTokens();
  if (!c) return '';
  const esc = ctx.esc, mine = positioned(stepTokens()), myEmb = embarkedIn(stepTokens()), lines = [];
  const name = (tk) => { const [s, k] = tk.split(':'); return unitInfo(s, k)?.cu.name ?? tk; };
  for (const tk of new Set([...Object.keys(mine), ...Object.keys(c.tokens)])) {
    const a = mine[tk], g = c.tokens[tk];
    if (a && g) { const dd = Math.hypot(a.x - g.x, a.y - g.y); if (dd > GHOST_MIN) lines.push(`${esc(name(tk))} ${dd.toFixed(1)}" away`); }
    else if (a) lines.push(c.embarked.has(tk) ? `${esc(name(tk))} is in a transport there` : `${esc(name(tk))} is not on the board there`);
    else lines.push(myEmb.has(tk) ? `${esc(name(tk))} is in a transport here` : `${esc(name(tk))} is only on the board there`);
  }
  return `Dashed bases: <b>${esc(c.name)}</b> at ${esc(c.step)}. ${lines.length ? lines.join(' · ') : 'Every unit is in the same place.'}`;
}
function ghostSvg() {
  const c = compareTokens();
  if (!c) return '';
  const mine = positioned(stepTokens()), out = ['<g id="board-ghosts" pointer-events="none">'];
  for (const [tk, g] of Object.entries(c.tokens)) {
    const [side, key] = tk.split(':');
    const u = unitInfo(side, key);
    if (!u) continue;
    const a = mine[tk];
    if (a && Math.hypot(a.x - g.x, a.y - g.y) <= GHOST_MIN) continue;
    if (a) out.push(`<line x1="${f2(a.x)}" y1="${f2(a.y)}" x2="${f2(g.x)}" y2="${f2(g.y)}" stroke="${C[side]}" stroke-width="0.18" stroke-dasharray="0.6 0.4" opacity="0.8"/>`);
    out.push(`<g data-ghost="${tk}" transform="translate(${f2(g.x)},${f2(g.y)})" opacity="0.85">${tokenModels(u, g).map(m => shapeSvg(m.fp, m.dx, m.dy, 'none', C[side], 0.16, m.rot)).join('').replaceAll('stroke-width="0.16"', 'stroke-width="0.16" stroke-dasharray="0.45 0.3"')}</g>`);
  }
  // a unit that is gone in the other path: a dashed cross over it
  for (const tk of Object.keys(mine)) {
    if (c.tokens[tk] || c.embarked.has(tk)) continue;
    const a = mine[tk];
    out.push(`<g data-ghost-gone="${tk}" stroke="#c0392b" stroke-width="0.25" stroke-dasharray="0.5 0.3"><line x1="${f2(a.x - 1.6)}" y1="${f2(a.y - 1.6)}" x2="${f2(a.x + 1.6)}" y2="${f2(a.y + 1.6)}"/><line x1="${f2(a.x + 1.6)}" y1="${f2(a.y - 1.6)}" x2="${f2(a.x - 1.6)}" y2="${f2(a.y + 1.6)}"/></g>`);
  }
  out.push('</g>');
  return out.join('');
}

// Going first / going second: the first turn is a roll-off AFTER both armies are deployed (Event Companion,
// "Determine first turn: roll off, the winner takes the first turn"), so the two versions of a plan share
// their deployment and differ from Turn 1 on. variant.when: 'first' | 'second' (from my side of the table).
const deployKey = (vv) => JSON.stringify(Object.entries(vv.steps?.[0]?.tokens ?? {}).map(([tk, t]) => [tk, Math.round(t.x * 10), Math.round(t.y * 10), Math.round(t.rot ?? 0), t.per ?? 0, t.in ?? null, t.gap ?? null]).sort());
function splitNote() {
  const root = planRoot();
  const f = root?.variants.find(v => v.when === 'first'), s = root?.variants.find(v => v.when === 'second');
  if (!f || !s) return '';
  const same = deployKey(f) === deployKey(s);
  return `<div class="tiny ${same ? 'muted' : ''}" id="board-split-note" data-same="${same ? 1 : 0}" style="flex-basis:100%;${same ? '' : 'color:var(--warn-ink)'}">${same
    ? `“${ctx.esc(f.name)}” and “${ctx.esc(s.name)}” start from the same deployment: you deploy before the roll-off for the first turn. Plan Turn 1 onwards in each; Mission compares them.`
    : `⚠ The deployment differs between “${ctx.esc(f.name)}” and “${ctx.esc(s.name)}”, but you deploy before the roll-off for the first turn. <button class="btn ghost" data-action="board-plan-sync-deploy" id="board-plan-sync">Use this deployment in both</button>`}</div>`;
}

// one table photo per plan step (the first plan keeps the original keys)
function photoKey() {
  const root = planRoot(), p = plan();
  return p ? (root.v ? `${planKey()}#v${root.v}#${curIndex()}` : `${planKey()}#${curIndex()}`) : null;
}
function currentPhoto() {
  return photoFor(photoKey(), BOARD, () => { refreshBoard(); });
}
// how much of the map to draw over a photo
const MAP_OVER_PHOTO = { photo: 0, both: 0.45, map: 1 };

function stepTokens() {
  const st = curSteps()[curIndex()];
  return st ? (st.tokens ??= {}) : {};
}

// ---------------------------------------------------------------------------
// Units on the board

const unitCache = new Map();
/** A unit on the board as of a plan step (models left by that step's battle round: Deploy 0, Turn N = N). */
function unitInfo(side, key, round = curIndex()) {
  const army = ctx.state.armies[side];
  const cu = army?.units.find(u => u.key === key);
  if (!cu) return null;
  const hulls = hullSizes(), mine = cu.members.map(m => hulls[m.dcUnit.name]).filter(Boolean);
  // models left (the game on the tracker): the board shows the models that are left
  const gl = ctx.groupsLeft?.(side, cu, round) ?? [];
  const aliveOf = new Map();
  for (const g of gl) aliveOf.set(g.member, (aliveOf.get(g.member) ?? 0) + g.left);
  const lostSig = gl.some(g => g.left < g.count) ? gl.map(g => g.left).join(',') : '';
  const ck = `${side}|${key}|${cu.name}|${cu.models}|${(army.roster?.detachments ?? []).map(d => d?.ref?.id).join(',')}|${JSON.stringify(mine)}|${lostSig}`;
  if (!unitCache.has(ck)) {
    const bu = boardUnit(cu, army);
    const total = bu.members.reduce((a, m) => a + m.count, 0);
    if (lostSig) bu.members = bu.members.map((m, i) => ({ ...m, count: aliveOf.get(cu.members[i].index) ?? m.count })).filter(m => m.count > 0);
    const left = bu.members.reduce((a, m) => a + m.count, 0);
    // a hull size you measured replaces the rough one (length across the token, width down it)
    for (const m of bu.members) { const h = hulls[m.label]; if (h && m.fp.approx && m.fp.shape === 'rect') m.fp = { shape: 'rect', hw: h.l / 2, hh: h.w / 2, measured: true }; }
    // Objective Control: each model's OC (datasheet), summed over the unit
    const oc = bu.members.reduce((a, m) => a + (m.oc || 0) * m.count, 0);
    unitCache.set(ck, { cu, ...bu, oc, left, total, dead: left === 0, models: left ? coherentFormation(bu.members) : [], formations: new Map() });
  }
  return unitCache.get(ck);
}

// a placed unit's models: its formation width (models per row) and facing
function tokenModels(u, pos) {
  // in coherency by default (03.03); a row width the player chose is kept, only the spacing closes up
  // pos.gap: the space between bases the player chose (inches; none = the widest coherent up to 1")
  const per = pos.per ?? 5, gap = Number.isFinite(pos.gap) ? pos.gap : null;
  const fk = `${per}${pos.per != null ? 'k' : ''}${gap != null ? `g${gap}` : ''}`;
  if (!u.formations.has(fk)) {
    u.formations.set(fk, gap != null ? formation(u.members, { gap, perRow: Math.min(per, u.members.reduce((n, m) => n + m.count, 0)) })
      : coherentFormation(u.members, { perRow: per, keepRows: pos.per != null }));
  }
  const base = u.formations.get(fk);
  const out = pos.rot ? rotateFormation(base, pos.rot) : base;
  // models moved one by one (pos.mo: { index: [dx, dy] } from the unit's centre, facing included): the rest stay
  // in formation. Moving the whole unit keeps their spacing.
  return pos.mo ? out.map((m, i) => (pos.mo[i] ? { ...m, dx: pos.mo[i][0], dy: pos.mo[i][1] } : m)) : out;
}

// ---- transports: an embarked unit is { in: transportTk } in the step's tokens (no position: it moves with the
// transport and is not on the battlefield — it controls no objective, it cannot be seen). Its transport must be on
// the board in that step, else the unit counts as not placed.
/** Embarked units of these tokens: Map passengerTk -> transportTk (only while the transport is on the board). */
function embarkedIn(tokens) {
  const out = new Map();
  for (const [tk, pos] of Object.entries(tokens ?? {})) if (pos?.in && tokens[pos.in] && !tokens[pos.in].in) out.set(tk, pos.in);
  return out;
}
/** The passengers of transport `ttk` in this step, with the spaces each takes. */
function passengersOf(ttk, tokens = stepTokens()) {
  const t = unitInfo(...ttk.split(':')), tr = t && transportOf(t.cu);
  return [...embarkedIn(tokens)].filter(([, x]) => x === ttk).map(([tk]) => {
    const u = unitInfo(...tk.split(':'));
    return { tk, name: u?.cu.name ?? tk, spaces: tr && u ? passengerCheck(tr, u.cu).spaces : 0 };
  });
}

function placed() {
  const out = [];
  for (const [tk, pos] of Object.entries(stepTokens())) {
    if (pos?.in) continue; // embarked
    const [side, key] = tk.split(':');
    const u = unitInfo(side, key);
    if (u && !u.dead) out.push({ tk, side, key, x: pos.x, y: pos.y, rot: pos.rot ?? 0, per: pos.per ?? 5, gap: Number.isFinite(pos.gap) ? pos.gap : null, models: tokenModels(u, pos), u });
  }
  return out;
}

// ---- drop-order drill (droporder.mjs): a plan of its own whose Deploy step is set up one unit at a time,
// alternating from the Defender. plan().drill = { first, log: [{ X, tk }], res: [tk] } (res = strategic reserves).
const isTitanic = (side, key) => (unitInfo(side, key)?.cu.keywords ?? []).some(k => /^TITANIC$/i.test(k));
function drillInfo() {
  const p = plan();
  if (!p?.drill || curIndex() !== 0) return null;
  const toks = stepTokens(), emb = embarkedIn(toks), res = new Set(p.drill.res ?? []);
  const totals = { A: 0, B: 0 };
  for (const side of ['A', 'B']) for (const u of ctx.state.armies[side]?.units ?? []) {
    const tk = `${side}:${u.key}`;
    if (!res.has(tk) && !emb.has(tk)) totals[side]++;
  }
  const log = (p.drill.log ?? []).filter(e => toks[e.tk] && !emb.has(e.tk) && !res.has(e.tk));
  const s = dropState(p.drill.first, totals, log, (tk) => isTitanic(...tk.split(':')));
  return { d: p.drill, s, log, res, emb, toks };
}
function drillHtml(di) {
  const esc = ctx.esc, st = ctx.state, { s, log, res } = di, X = s.next;
  const Y = (P) => (P === 'A' ? 'B' : 'A');
  const unitBtns = X ? st.armies[X].units.filter(u => !di.toks[`${X}:${u.key}`] && !res.has(`${X}:${u.key}`)).map(u => {
    const tk = `${X}:${u.key}`, ti = isTitanic(X, u.key);
    return `<span class="drill-u"><button class="chip" data-action="board-place" data-side="${X}" data-key="${esc(u.key)}" style="border-color:${C[X]}">＋ ${esc(u.name)}${ti ? ' <span class="tiny">(TITANIC: skip your next drop)</span>' : ''}</button><button class="icon-btn" data-action="board-drill-res" data-tk="${esc(tk)}" aria-label="Put ${esc(u.name)} in reserves" title="Strategic reserves: not set up">⤓</button></span>`;
  }).join('') : '';
  const resList = [...res].map(tk => { const [sd, k] = tk.split(':'); const u = unitInfo(sd, k); return u ? `<button class="chip" data-action="board-drill-res" data-tk="${esc(tk)}" style="border-color:${C[sd]}">↩ ${esc(u.cu.name)}</button>` : ''; }).join('');
  const nameOf = (tk) => { const [sd, k] = tk.split(':'); return unitInfo(sd, k)?.cu.name ?? tk; };
  const ahead = s.finishesFirst ? `${s.finishesFirst} finishes first${s.lastRun ? `; then ${s.lastRun.side} sets up its last ${s.lastRun.n} knowing where all of ${Y(s.lastRun.side)} is` : ''}.` : '';
  return `<div class="card drill" id="board-drill" style="margin-top:6px;border-color:${X ? C[X] : 'var(--line)'}">
    <div class="row" style="gap:6px;align-items:center"><span class="grow" id="board-drill-turn">${X
      ? `🎯 Drop ${log.length + 1}: <b style="color:${C[X]}">${X}</b> (${esc(st.armies[X].faction)}) sets up a unit`
      : '✓ Every unit is set up'}</span>
      ${log.length ? '<button class="chip" data-action="board-drill-undo" id="board-drill-undo">↶ Undo</button>' : ''}
      <button class="chip" data-action="board-drill-end" id="board-drill-end" title="Stop the drill; the set-up stays as a plan">End drill</button></div>
    <div class="tiny muted" id="board-drill-left" style="margin-top:2px">Units still to set up: A ${s.left.A} · B ${s.left.B}. ${esc(ahead)}</div>
    ${X ? `<div class="unit-strip drill-tray ${ctx.wide?.() ? 'wrap' : ''}" id="board-drill-tray">${unitBtns}</div>` : ''}
    ${resList ? `<div class="row tiny" style="margin-top:6px;gap:4px;flex-wrap:wrap;align-items:center" id="board-drill-res"><span class="muted">In reserves (not set up):</span>${resList}</div>` : ''}
    ${log.length ? `<details class="tiny" style="margin-top:6px" id="board-drill-log"><summary>Order so far (${log.length})</summary><ol style="margin:4px 0 0 18px;padding:0">${log.map(e => `<li><b style="color:${C[e.X]}">${e.X}</b> ${esc(nameOf(e.tk))}</li>`).join('')}</ol></details>` : ''}
    <details class="tiny muted" style="margin-top:4px"><summary>How the drops work</summary>Players set up one unit at a time, starting with the Defender; a TITANIC unit makes its player skip their next turn to set up; once one player is done the other sets up the rest. Units in reserves (⤓) and units embarked in a transport are not set up on their own.</details>
  </div>`;
}

// ---- Scout moves (24.31 / 24.32), planned on the Deploy step: pos.scout = { x, y } is where the unit ends its
// Scout move (drawn as a dashed ghost you can drag); the unit itself stays at its deployment position. Turn 1
// starts from the Scout position. A DEDICATED TRANSPORT whose passengers all have Scouts can make one too.
function scoutDist(side, key, toks = stepTokens()) {
  const u = unitInfo(side, key);
  if (!u) return 0;
  if (u.flags?.scouts) return u.flags.scouts;
  if (!(u.cu.keywords ?? []).some(k => /^DEDICATED TRANSPORT$/i.test(k))) return 0;
  const inside = [...embarkedIn(toks)].filter(([, x]) => x === `${side}:${key}`).map(([tk]) => unitInfo(...tk.split(':'))?.flags?.scouts ?? 0);
  return inside.length && inside.every(n => n > 0) ? Math.min(...inside) : 0;
}
function myZone(side) {
  const l = currentLayout();
  return (l && DEPLOYMENTS[l.deployment]?.zones.find(z => z.player === zoneOf(side))?.poly) ?? null;
}
/** Every planned Scout move in the Deploy step: [{ tk, side, name, X, moved, msgs }]. Enemies are checked where they
 * end up after their own Scout moves (players alternate them). */
function scoutMoves() {
  if (curIndex() !== 0) return [];
  const toks = placed(), raw = stepTokens(), out = [];
  const after = (t) => (raw[t.tk]?.scout ? { ...t, x: raw[t.tk].scout.x, y: raw[t.tk].scout.y } : t);
  for (const t of toks) {
    const sc = raw[t.tk]?.scout;
    if (!sc) continue;
    const X = scoutDist(t.side, t.key);
    const chk = scoutCheck({ X, from: t, to: { ...t, x: sc.x, y: sc.y } }, { myDZ: myZone(t.side), enemies: toks.filter(o => o.side !== t.side).map(after) });
    if (!X) chk.msgs.unshift('has no Scouts ability (24.31)');
    out.push({ tk: t.tk, side: t.side, name: t.u.cu.name, X, ...chk });
  }
  return out;
}
function scoutSvg() {
  const mv = scoutMoves();
  if (!mv.length) return '';
  const raw = stepTokens(), out = ['<g id="board-scouts">'];
  for (const s of mv) {
    const pos = raw[s.tk], u = unitInfo(...s.tk.split(':')), sc = pos.scout, bad = s.msgs.length > 0;
    const col = bad ? '#c0392b' : C[s.side];
    out.push(`<line x1="${f2(pos.x)}" y1="${f2(pos.y)}" x2="${f2(sc.x)}" y2="${f2(sc.y)}" stroke="${col}" stroke-width="0.22" stroke-dasharray="0.7 0.4" pointer-events="none"/>`);
    const ms = tokenModels(u, pos), ext = ms.reduce((a, m) => { const h = halfBase(m.fp); return { x0: Math.min(a.x0, m.dx - h.hx), x1: Math.max(a.x1, m.dx + h.hx), y0: Math.min(a.y0, m.dy - h.hy), y1: Math.max(a.y1, m.dy + h.hy) }; }, { x0: Infinity, x1: -Infinity, y0: Infinity, y1: -Infinity });
    out.push(`<g data-scout="${s.tk}" data-ok="${bad ? 0 : 1}" transform="translate(${f2(sc.x)},${f2(sc.y)})" opacity="0.9" style="cursor:grab">`
      // grab area over the whole formation (as for a unit)
      + `<rect class="scout-grab" x="${f2(ext.x0 - 0.4)}" y="${f2(ext.y0 - 0.4)}" width="${f2(ext.x1 - ext.x0 + 0.8)}" height="${f2(ext.y1 - ext.y0 + 0.8)}" fill="${C[s.side]}" fill-opacity="0.04"/>`
      + tokenModels(u, pos).map(m => shapeSvg(m.fp, m.dx, m.dy, C[s.side], col, 0.2, m.rot)).join('').replaceAll('stroke-width="0.2"', 'stroke-width="0.2" stroke-dasharray="0.4 0.25" fill-opacity="0.18"')
      + `<text x="0" y="${f2(-1.9)}" font-size="0.9" text-anchor="middle" fill="${col}" stroke="#ffffff" stroke-width="0.3" paint-order="stroke" font-family="system-ui,sans-serif" font-weight="700" pointer-events="none">Scout ${s.moved.toFixed(1)}"/${s.X}"${bad ? ' ✗' : ''}</text></g>`);
  }
  out.push('</g>');
  return out.join('');
}
/** Turn 1 starts where the Scout move ends: move this unit there in the next step too, if it had not been moved. */
function scoutToTurn1(tk, from, to) {
  const t1 = curSteps()[1]?.tokens?.[tk];
  if (t1 && from && Math.hypot(t1.x - from.x, t1.y - from.y) < 0.05) Object.assign(t1, { x: to.x, y: to.y });
}

// ---- "What it can see" (sight.visibleCells): squares where a 32 mm model would be visible to the selected unit
let seeCache = { key: null, v: null };
function seeOf(sel) {
  const l = currentLayout();
  if (!l) return null;
  const key = `${l.id}|${sel.tk}|${sel.x.toFixed(2)}|${sel.y.toFixed(2)}|${sel.rot}|${sel.models.length}|${sel.models.map(m => `${m.dx.toFixed(2)},${m.dy.toFixed(2)}`).join(';')}`;
  if (seeCache.key !== key) {
    const t0 = performance.now();
    seeCache = { key, v: visibleCells(sel, l.pieces) };
    const n = seeCache.v.cells.reduce((s, c) => s + c, 0);
    console.log(`[board] what ${sel.tk} can see: ${n} of ${seeCache.v.cells.length} squares (${Math.round(performance.now() - t0)} ms)`);
  }
  return seeCache.v;
}
function seeSvg(sel) {
  const v = seeOf(sel);
  if (!v) return '';
  // one rectangle per run of seen squares down a column
  const out = [`<g id="see-layer" data-seen="${v.cells.reduce((s, c) => s + c, 0)}" fill="${C[sel.side]}" fill-opacity="0.22" pointer-events="none">`];
  for (let i = 0; i < v.cols; i++) {
    let j = 0;
    while (j < v.rows) {
      if (!v.cells[i * v.rows + j]) { j++; continue; }
      let k = j;
      while (k < v.rows && v.cells[i * v.rows + k]) k++;
      out.push(`<rect x="${i * v.step}" y="${j * v.step}" width="${v.step}" height="${(k - j) * v.step}"/>`);
      j = k;
    }
  }
  out.push('</g>');
  return out.join('');
}

// ---- hull sizes you measured (vehicles and monsters without a base: the data has no hull dimensions)
const HULL_KEY = 'w40k_calc_hulls_v1';
let hullMemo = null;
function hullSizes() { if (!hullMemo) { try { hullMemo = JSON.parse(localStorage.getItem(HULL_KEY) ?? '{}') ?? {}; } catch { hullMemo = {}; } } return hullMemo; }

// ---- Live AR (arview.mjs): what is drawn on the table
function arData() {
  const l = currentLayout(), dep = l && DEPLOYMENTS[l.deployment], root = planRoot();
  const plans = boardPlans(), pv = plans[Math.min(root?.v ?? 0, plans.length - 1)];
  const unitsOf = (st) => ['A', 'B'].flatMap(side => (st?.[side] ?? []).map(u => ({ side, name: u.name, color: C[side], models: u.models.map(m => ({ x: u.x + m.dx, y: u.y + m.dy, fp: m.fp, rot: m.rot ?? 0 })) })));
  return {
    w: BOARD.w, h: BOARD.h, layout: l?.id ?? null,
    zones: (dep?.zones ?? []).map(z => ({ poly: z.poly, color: C[zoneOf('A') === z.player ? 'A' : 'B'] })),
    objectives: (l?.objectives ?? []).map(o => ({ x: o.x, y: o.y })), objRange: OBJECTIVE_RANGE,
    pieces: (l?.pieces ?? []).filter(p => p.poly?.length >= 3).map(p => ({ poly: p.poly, cls: p.cls, cat: p.cat })),
    steps: (pv?.steps ?? []).map(st => ({ name: st.name, units: unitsOf(st) })),
    cur: curIndex(), diagram: cornerDiagram,
  };
}

function zoneCentroid(side) {
  const l = currentLayout();
  const dep = l && DEPLOYMENTS[l.deployment];
  const z = dep?.zones.find(zz => zz.player === zoneOf(side));
  if (!z) return { x: BOARD.w / 2, y: side === 'A' ? 10 : 50 };
  const xs = z.poly.map(p => p[0]), ys = z.poly.map(p => p[1]);
  let cx = xs.reduce((a, b) => a + b, 0) / xs.length, cy = ys.reduce((a, b) => a + b, 0) / ys.length;
  if (!inPoly(cx, cy, z.poly)) { cx = z.poly[0][0] * 0.6 + cx * 0.4; cy = z.poly[0][1] * 0.6 + cy * 0.4; }
  return { x: cx, y: cy };
}

// First free spot for a new unit: inside its deployment zone, nearest the
// zone's centre, at least 1" from every unit already on the board.
function freeSpot(side, key) {
  const u = unitInfo(side, key);
  const l = currentLayout();
  const zone = l && DEPLOYMENTS[l.deployment]?.zones.find(z => z.player === zoneOf(side));
  const c = zoneCentroid(side);
  const others = placed();
  const ext = u ? u.models.reduce((a, m) => ({
    hx: Math.max(a.hx, Math.abs(m.dx) + (m.fp.r ?? m.fp.rx ?? m.fp.hw)),
    hy: Math.max(a.hy, Math.abs(m.dy) + (m.fp.r ?? m.fp.ry ?? m.fp.hh)),
  }), { hx: 1, hy: 1 }) : { hx: 1, hy: 1 };
  const cands = [];
  for (let x = ext.hx; x <= BOARD.w - ext.hx; x += 1) {
    for (let y = ext.hy; y <= BOARD.h - ext.hy; y += 1) cands.push({ x, y, d: Math.hypot(x - c.x, y - c.y) });
  }
  cands.sort((p, q) => p.d - q.d);
  for (const p of cands) {
    if (zone && !u?.models.every(m => inPoly(p.x + m.dx, p.y + m.dy, zone.poly))) continue;
    if (u && others.some(o => unitGap({ x: p.x, y: p.y, models: u.models }, o) < 1)) continue;
    return { x: p.x, y: p.y };
  }
  return { x: c.x, y: c.y };
}

// ---------------------------------------------------------------------------
// SVG

const f2 = (n) => Math.round(n * 100) / 100;

// ---- table set-up measurements: for each terrain piece its corner nearest a board edge, and each objective, in
// inches from the nearest side edge (↔) and the nearest short edge (↕) — to set up the real table from the layout
const fontK0 = (vb) => Math.max(0.55, Math.min(1.2, vb.w / (BOARD.w + 1)));
const fmtIn = (v) => `${Math.round(v * 4) / 4}"`.replace('.25"', '¼"').replace('.5"', '½"').replace('.75"', '¾"');
export function edgeMeasure(x, y) {
  const dx = Math.min(x, BOARD.w - x), dy = Math.min(y, BOARD.h - y);
  return { dx, dy, fromLeft: x <= BOARD.w - x, fromTop: y <= BOARD.h - y };
}
function measureSvg(l, k) {
  if (!l) return '';
  const out = ['<g id="board-measure" pointer-events="none" font-family="system-ui,sans-serif" font-weight="700">'];
  const label = (x, y, txt, col) => {
    const w = (txt.length * 0.52 + 0.6) * k, h = 1.25 * k, ox = x < BOARD.w / 2 ? 0.4 * k : -w - 0.4 * k, oy = y < BOARD.h / 2 ? 0.4 * k : -h - 0.4 * k;
    return `<circle cx="${f2(x)}" cy="${f2(y)}" r="${f2(0.28 * k)}" fill="${col}"/><rect x="${f2(x + ox)}" y="${f2(y + oy)}" width="${f2(w)}" height="${f2(h)}" rx="${f2(0.25 * k)}" fill="#ffffff" fill-opacity="0.92" stroke="${col}" stroke-width="${f2(0.08 * k)}"/>`
      + `<text x="${f2(x + ox + w / 2)}" y="${f2(y + oy + h * 0.72)}" font-size="${f2(0.85 * k)}" text-anchor="middle" fill="#222">${txt}</text>`;
  };
  // the terrain areas (a wall or feature that sits on an area is placed with it), one label each, none on top of another
  const placedAt = [];
  const free = (x, y) => !placedAt.some(q => Math.hypot(q.x - x, q.y - y) < 2.2);
  for (const p of l.pieces ?? []) {
    if (!p.poly?.length || p.parent || (p.cls && p.cls !== 'area')) continue;
    // the corner nearest a board edge (the one to measure from when setting the piece down)
    const v = p.poly.map(([x, y]) => ({ x, y, m: edgeMeasure(x, y) })).sort((a, b) => (a.m.dx + a.m.dy) - (b.m.dx + b.m.dy)).find(c => free(c.x, c.y));
    if (!v) continue;
    placedAt.push(v);
    out.push(`<g data-measure="${ctx.esc(p.id)}">${label(v.x, v.y, `↔${fmtIn(v.m.dx)} ↕${fmtIn(v.m.dy)}`, '#1f5fa8')}</g>`);
  }
  for (const o of l.objectives ?? []) {
    const m = edgeMeasure(o.x, o.y);
    out.push(`<g data-measure-obj="${ctx.esc(o.id)}">${label(o.x, o.y, `↔${fmtIn(m.dx)} ↕${fmtIn(m.dy)}`, '#a36a00')}</g>`);
  }
  out.push('</g>');
  return out.join('');
}

/** The letter on a base: the first letter of the first word of the datasheet name ("Prosecutor Squad" -> P). */
export const baseLetter = (name) => (/[A-Za-z0-9]/.exec(String(name ?? '')) ?? ['?'])[0].toUpperCase();
/** Half width / height of a base footprint (round r, oval rx/ry, hull hw/hh). */
const halfBase = (fp) => ({ hx: fp.r ?? fp.rx ?? fp.hw ?? 0.5, hy: fp.r ?? fp.ry ?? fp.hh ?? 0.5 });

function shapeSvg(fp, x, y, fill, stroke, sw, rot = 0) {
  if (rot && fp.shape !== 'round') {
    return `<g transform="rotate(${f2(rot)} ${f2(x)} ${f2(y)})">${shapeSvg(fp, x, y, fill, stroke, sw)}</g>`;
  }
  if (fp.shape === 'round') return `<circle cx="${f2(x)}" cy="${f2(y)}" r="${f2(fp.r)}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`;
  if (fp.shape === 'oval') return `<ellipse cx="${f2(x)}" cy="${f2(y)}" rx="${f2(fp.rx)}" ry="${f2(fp.ry)}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`;
  return `<rect x="${f2(x - fp.hw)}" y="${f2(y - fp.hh)}" width="${f2(fp.hw * 2)}" height="${f2(fp.hh * 2)}" rx="0.3" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" ${fp.approx ? 'stroke-dasharray="0.4 0.25"' : ''}/>`;
}

/** From how far the unit can be seen where it stands: Lone Operative (24.24), or Hidden (13.09: 15"); 0 = from anywhere. */
function detectionOf(t) {
  const l = currentLayout();
  const lone = t.u.flags?.loneOperative || 0;
  const hide = !!l && canHide({ x: t.x, y: t.y, models: t.models, keywords: t.u.cu.keywords ?? [] }, l.pieces);
  const d = Math.min(lone || Infinity, hide ? HIDDEN_RANGE : Infinity);
  return { range: Number.isFinite(d) ? d : 0, lone, hide };
}

const MOVE_RINGS = new Set(['move', 'advance', 'charge']);
/** Where a unit on the board started this turn: its position on the previous step (null on Deploy, or if it was not on the board). */
function turnStart(t) {
  const i = curIndex();
  if (i < 1) return null;
  const pos = curSteps()[i - 1]?.tokens?.[t.tk];
  if (!pos) return null;
  return { x: pos.x, y: pos.y, models: tokenModels(t.u, pos) };
}
function ringRadius(u, kind) {
  if (kind === 'move') return u.move;
  if (kind === 'advance') return u.move + 6;
  if (kind === 'charge') return u.move + 7;
  if (kind === 'engage') return ENGAGEMENT_RANGE;
  if (kind.startsWith('r')) return Number(kind.slice(1));
  return 0;
}

export function boardSvg({ forExport = false } = {}) {
  const b = boardState();
  const l = currentLayout();
  if (!l) return '';
  const dep = DEPLOYMENTS[l.deployment];
  const vb = forExport || !b.view ? { x: -0.5, y: -0.5, w: BOARD.w + 1, h: BOARD.h + 1 } : b.view;
  const parts = [];
  parts.push(`<rect x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="${C.mat}" stroke="${C.edge}" stroke-width="0.12"/>`);
  const photo = currentPhoto();
  const photoMode = photo ? (b.settings.photoMap ?? 'both') : 'map';
  if (photo && photoMode !== 'map') parts.push(`<image id="board-photo" href="${forExport ? photo.dataUrl : photo.url}" x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" preserveAspectRatio="none"/>`);
  parts.push(`<g id="board-map" opacity="${MAP_OVER_PHOTO[photoMode] ?? 1}">`);
  for (const z of dep?.zones ?? []) {
    const side = zoneOf('A') === z.player ? 'A' : 'B';
    parts.push(`<polygon points="${z.poly.map(p => p.join(',')).join(' ')}" fill="${C[side]}" fill-opacity="0.13" stroke="${C[side]}" stroke-opacity="0.55" stroke-width="0.08"/>`);
  }
  for (const p of l.pieces) {
    const tall = (p.h ?? 0) >= 5;
    parts.push(`<polygon points="${p.poly.map(q => q.join(',')).join(' ')}" fill="${p.cls === 'area' ? C.area : C.feature}" fill-opacity="${p.cls === 'area' ? 1 : (tall ? 0.85 : 0.6)}" stroke="${C.areaEdge}" stroke-width="0.06"/>`);
  }
  // objectives: hosted -> outline the hosting area; open ground -> 3.79" range
  for (const o of l.objectives) {
    const hosts = l.pieces.filter(p => o.host.includes(p.id) && p.cls === 'area');
    if (hosts.length) for (const h of hosts) parts.push(`<polygon points="${h.poly.map(q => q.join(',')).join(' ')}" fill="none" stroke="${C.objEdge}" stroke-width="0.18"/>`);
    else parts.push(`<circle cx="${o.x}" cy="${o.y}" r="${f2(OBJECTIVE_RANGE)}" fill="${C.objRing}" stroke="${C.objEdge}" stroke-width="0.08"/>`);
    parts.push(`<circle cx="${o.x}" cy="${o.y}" r="0.79" fill="${C.obj}" stroke="${C.objEdge}" stroke-width="0.12"/>`);
  }
  parts.push('</g>');
  if (b.measure && !forExport) parts.push(measureSvg(l, fontK0(vb)));
  if (!forExport || b.danger) parts.push(dangerSvg(b));
  if (b.arrive) parts.push(arriveSvg(b));
  // over a photo the bases are see-through so the real models show underneath
  const tokAlpha = photo && photoMode !== 'map' ? 0.5 : 1;
  const toks = placed();
  const fontK = Math.max(0.55, Math.min(1.2, vb.w / (BOARD.w + 1))); // label size follows the zoom
  // range rings of the selected unit (union of per-model circles, uniform tint)
  const sel = toks.find(t => t.tk === b.sel);
  if (sel && !forExport) {
    const kinds = Object.keys(b.rings).filter(k => b.rings[k]);
    const start = turnStart(sel);
    for (const k of kinds) {
      if (k === 'see') { parts.push(seeSvg(sel)); continue; }
      if (k === 'detect') {
        // who can see it: only models inside this line (dashed, in the enemy's colour)
        const det = detectionOf(sel).range;
        if (det) parts.push(`<g data-ring="detect" data-r="${det}" fill="${C[sel.side === 'A' ? 'B' : 'A']}" fill-opacity="0.05" stroke="${C[sel.side === 'A' ? 'B' : 'A']}" stroke-width="0.12" stroke-dasharray="0.6 0.4">${sel.models.map(m => `<circle cx="${f2(sel.x + m.dx)}" cy="${f2(sel.y + m.dy)}" r="${f2(det + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))}"/>`).join('')}</g>`);
        continue;
      }
      const R = ringRadius(sel.u, k);
      // movement rings (Move, Advance, Charge) are measured from where the unit started this turn:
      // its position at the end of the previous step, so they stay put while the unit is moved
      const o = MOVE_RINGS.has(k) && start ? start : { x: sel.x, y: sel.y, models: sel.models };
      parts.push(`<g opacity="0.16" data-ring="${k}" data-from="${o === start ? 'start' : 'here'}">${o.models.map(m => `<circle cx="${f2(o.x + m.dx)}" cy="${f2(o.y + m.dy)}" r="${f2(R + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))}" fill="${C[sel.side]}"/>`).join('')}</g>`);
    }
    // where it started this turn: a dashed outline, once it has been moved away from there
    if (start && kinds.some(k => MOVE_RINGS.has(k)) && Math.hypot(start.x - sel.x, start.y - sel.y) > 0.05) {
      parts.push(`<g data-start="${sel.tk}" transform="translate(${f2(start.x)},${f2(start.y)})" opacity="0.8" pointer-events="none">${start.models.map(m => shapeSvg(m.fp, m.dx, m.dy, 'none', C[sel.side], 0.14, m.rot)).join('').replaceAll('stroke-width="0.14"', 'stroke-width="0.14" stroke-dasharray="0.45 0.3"')}</g>`);
    }
  }
  if (!forExport) parts.push(ghostSvg());
  parts.push(scoutSvg());
  for (const t of toks) {
    const isSel = t.tk === b.sel || t.tk === b.sel2;
    const fill = C[t.side];
    // invisible grab area over the whole formation: a finger rarely lands exactly on a 25 mm base
    const ext = t.models.reduce((a, m) => {
      const r = m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0), ry = m.fp.r ?? Math.max(m.fp.ry ?? 0, m.fp.hh ?? 0);
      return { x0: Math.min(a.x0, m.dx - r), x1: Math.max(a.x1, m.dx + r), y0: Math.min(a.y0, m.dy - ry), y1: Math.max(a.y1, m.dy + ry) };
    }, { x0: Infinity, x1: -Infinity, y0: Infinity, y1: -Infinity });
    if (!forExport && b.modelsOf === t.tk) {
      // models mode: each base is its own handle (no grab area: a drag between bases pans the map)
      parts.push(`<g class="tok models-mode" data-tok="${t.tk}" data-models="1" transform="translate(${f2(t.x)},${f2(t.y)})">`
        + t.models.map((m, i) => {
          const h = halfBase(m.fp), fs = Math.max(0.35, Math.min(1.6, Math.min(h.hx, h.hy) * 1.25));
          return `<g data-model="${i}" transform="translate(${f2(m.dx)},${f2(m.dy)})" style="cursor:move">`
            + `<circle r="${f2(Math.max(h.hx, h.hy) + 0.45)}" fill="${fill}" fill-opacity="0.001" stroke="${C.sel}" stroke-width="0.12" stroke-dasharray="0.35 0.25"/>`
            + shapeSvg(m.fp, 0, 0, fill, C.sel, 0.22, m.rot)
            + `<text font-size="${f2(fs)}" text-anchor="middle" dominant-baseline="central" fill="#fff" font-weight="700" font-family="system-ui,sans-serif" pointer-events="none">${ctx.esc(baseLetter(m.label))}</text></g>`;
        }).join('')
        + `<text x="0" y="${f2(Math.min(...t.models.map(m => m.dy - (m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0)))) - 0.35 * fontK)}" font-size="${f2(0.95 * fontK)}" text-anchor="middle" fill="${C.text}" font-family="system-ui,sans-serif" font-weight="600" paint-order="stroke" stroke="${C.mat}" stroke-width="${f2(0.25 * fontK)}" pointer-events="none">${ctx.esc(shortName(t.u.cu.name))}</text></g>`);
      continue;
    }
    const dim = !forExport && b.modelsOf && toks.some(x => x.tk === b.modelsOf) ? ' opacity="0.35"' : '';
    parts.push(`<g class="tok" data-tok="${t.tk}" transform="translate(${f2(t.x)},${f2(t.y)})" style="cursor:grab"${dim}>`
      + `<rect x="${f2(ext.x0 - 0.4)}" y="${f2(ext.y0 - 0.4)}" width="${f2(ext.x1 - ext.x0 + 0.8)}" height="${f2(ext.y1 - ext.y0 + 0.8)}" rx="0.6" fill="${fill}" fill-opacity="${isSel ? 0.12 : 0.04}" stroke="none"/>`
      + `<g fill-opacity="${tokAlpha}">${t.models.map(m => shapeSvg(m.fp, m.dx, m.dy, fill, isSel ? C.sel : '#ffffff', isSel ? 0.22 : 0.08, m.rot)).join('')}</g>`
      // the first letter of each model's datasheet name on its base (Prosecutor Squad: P; an attached Trajann: T)
      + `<g class="tok-letters" pointer-events="none" font-family="system-ui,sans-serif" font-weight="700" text-anchor="middle" dominant-baseline="central" fill="#ffffff">${t.models.map(m => {
        const h = halfBase(m.fp), fs = Math.max(0.35, Math.min(1.6, Math.min(h.hx, h.hy) * 1.25));
        return `<text x="${f2(m.dx)}" y="${f2(m.dy)}" font-size="${f2(fs)}">${ctx.esc(baseLetter(m.label))}</text>`;
      }).join('')}</g>`
      + `<text x="0" y="${f2(Math.min(...t.models.map(m => m.dy - (m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0)))) - 0.35 * fontK)}" font-size="${f2(0.95 * fontK)}" text-anchor="middle" fill="${C.text}" font-family="system-ui,sans-serif" font-weight="600" paint-order="stroke" stroke="${C.mat}" stroke-width="${f2(0.25 * fontK)}">${plan()?.live && plan().shock?.[t.tk] ? '⚡ ' : ''}${ctx.esc(shortName(t.u.cu.name))}${(() => { const n = passengersOf(t.tk).length; return n ? ` 🚚+${n}` : ''; })()}</text></g>`);
  }
  if (!forExport) parts.push(planSvg());
  if (!forExport) parts.push(hintSvg());
  // who controls each objective in this step: OC of each army's units in range
  // (on the hosting terrain area, or within 3" + the marker); the Mission tab's
  // board-plan forecast uses the same measurement
  parts.push('<g id="obj-control" pointer-events="none">');
  for (const o of l.objectives) {
    const oc = { A: 0, B: 0 };
    // 14.02: the OC of the MODELS within range (not the whole unit's when one model is there)
    for (const t of toks) if (t.u.oc && !(plan()?.live && plan().shock?.[t.tk])) oc[t.side] += ocInRange({ ...t, oc: t.u.oc }, o, l.pieces);
    if (!oc.A && !oc.B) continue;
    const ctl = oc.A > oc.B ? 'A' : oc.B > oc.A ? 'B' : 'tie';
    const col = ctl === 'tie' ? '#777' : C[ctl];
    const w = 4.6 * fontK, h = 1.25 * fontK, y = o.y + 1.1;
    parts.push(`<g data-obj="${o.id}" data-control="${ctl}" data-oca="${oc.A}" data-ocb="${oc.B}">`
      + `<circle cx="${o.x}" cy="${o.y}" r="1.05" fill="none" stroke="${col}" stroke-width="0.3"/>`
      + `<rect x="${f2(o.x - w / 2)}" y="${f2(y)}" width="${f2(w)}" height="${f2(h)}" rx="${f2(0.3 * fontK)}" fill="#ffffff" stroke="${col}" stroke-width="0.1"/>`
      + `<text x="${o.x}" y="${f2(y + h * 0.75)}" font-size="${f2(0.8 * fontK)}" text-anchor="middle" font-family="system-ui,sans-serif" font-weight="700" fill="${C.text}">A ${oc.A} · B ${oc.B}</text></g>`);
  }
  parts.push('</g>');
  // gap line between two selected units
  const sel2 = toks.find(t => t.tk === b.sel2);
  if (sel && sel2) {
    const g = unitGap(sel, sel2);
    const [p, q] = closestCentres(sel, sel2);
    parts.push(`<line x1="${f2(p[0])}" y1="${f2(p[1])}" x2="${f2(q[0])}" y2="${f2(q[1])}" stroke="${C.ruler}" stroke-width="0.12"/>`
      + label((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, `${g.toFixed(1)}"`));
  }
  if (!forExport) parts.push(`<g id="ruler-layer">${rulerSvg(b.ruler)}</g>`, '<g id="model-drag-layer" pointer-events="none"></g>');
  if (!forExport && b.mode === 'meas') parts.push(`<g id="meas-layer">${measSvg(b.meas)}</g>`);
  const size = forExport ? 'width="880" height="1200"' : '';
  return `<svg id="board-svg" xmlns="http://www.w3.org/2000/svg" viewBox="${f2(vb.x)} ${f2(vb.y)} ${f2(vb.w)} ${f2(vb.h)}" ${size} preserveAspectRatio="xMidYMid meet" style="touch-action:none;display:block;width:100%;height:auto;background:${forExport ? '#ffffff' : 'transparent'}">${parts.join('')}</svg>`;
}

// Next-turn danger from one army: where its units can shoot after a normal
// move (M + longest range) and charge (M + the 2D6 charge roll: likely >= 80%,
// possible >= 40%). Terrain and line of sight are ignored and the edge is
// blurred ~1": a planning envelope, not a measurement.
// ---- exposure heat map: for each 1" square, how much of that army can reach it next turn — 1 for each unit that can
// shoot it after a normal move (move + range, no line of sight), plus each unit's chance to charge it (move, then a
// 2D6 charge: rule 11.04 odds). Tap a square for the list.
function threatsAt(side, x, y, toks = placed().filter(t => t.side === side)) {
  const out = [];
  for (const t of toks) {
    const maxR = t.u.ranges.length ? Math.max(...t.u.ranges) : 0;
    let dmin = Infinity;
    for (const m of t.models) dmin = Math.min(dmin, Math.hypot(x - (t.x + m.dx), y - (t.y + m.dy)) - Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0));
    const shoot = maxR > 0 && dmin <= t.u.move + maxR;
    const charge = t.u.melee ? chargeOdds(chargeRollNeeded(Math.max(0, dmin - t.u.move))) : 0;
    if (shoot || charge > 0.005) out.push({ tk: t.tk, name: t.u.cu.name, shoot, charge });
  }
  return out;
}
const heatCache = { key: null, cells: null, max: 0 };
function heatCells(side) {
  const toks = placed().filter(t => t.side === side);
  const key = side + JSON.stringify(toks.map(t => [t.tk, t.x, t.y, t.rot, t.per, t.gap]));
  if (heatCache.key === key) return heatCache;
  const cells = [];
  let max = 0;
  for (let y = 0; y < BOARD.h; y++) for (let x = 0; x < BOARD.w; x++) {
    const th = threatsAt(side, x + 0.5, y + 0.5, toks);
    const s = th.reduce((a, t) => a + (t.shoot ? 1 : 0) + t.charge, 0);
    if (s > 0) { cells.push({ x, y, s }); max = Math.max(max, s); }
  }
  Object.assign(heatCache, { key, cells, max });
  return heatCache;
}
function heatSvg(side) {
  const h = heatCells(side);
  if (!h.cells.length) return '';
  return `<g id="heat-layer" data-from="${side}" data-max="${h.max.toFixed(2)}" pointer-events="none" fill="#c0392b">${h.cells.map(c => `<rect x="${c.x}" y="${c.y}" width="1" height="1" fill-opacity="${(0.05 + 0.6 * c.s / h.max).toFixed(3)}"/>`).join('')}</g>`;
}

function dangerSvg(b) {
  const side = b.danger;
  if (!side) return '';
  const kinds = b.dangerKinds ?? { shoot: true, charge: true };
  if (kinds.heat) {
    const at = b.heatAt;
    return heatSvg(side) + (at ? `<circle id="heat-at" cx="${f2(at.x)}" cy="${f2(at.y)}" r="0.6" fill="none" stroke="#111" stroke-width="0.2" pointer-events="none"/>` : '');
  }
  const layers = { likely: [], possible: [] };
  for (const t of placed().filter(x => x.side === side)) {
    const likely = t.u.melee ? chargeReach(t.u.move, 0.8) : null, possible = t.u.melee ? chargeReach(t.u.move, 0.4) : null;
    for (const m of t.models) {
      const r = Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0);
      const cx = f2(t.x + m.dx), cy = f2(t.y + m.dy);
      if (kinds.charge && possible) layers.possible.push(`<circle cx="${cx}" cy="${cy}" r="${f2(possible + r)}"/>`);
      if (kinds.charge && likely) layers.likely.push(`<circle cx="${cx}" cy="${cy}" r="${f2(likely + r)}"/>`);
    }
  }
  const col = C[side];
  const shoot = kinds.shoot ? shootCells(side) : null;
  // shooting: hatched squares (what they can see and reach); charges: solid. All of it on the board only.
  return `<defs><filter id="dz-blur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="0.5"/></filter>`
    + `<clipPath id="dz-board"><rect x="0" y="0" width="${BOARD.w}" height="${BOARD.h}"/></clipPath>`
    + `<pattern id="dz-hatch" width="1.4" height="1.4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="0.3" height="1.4" fill="${col}"/></pattern></defs>`
    + `<g id="danger-layer" data-from="${side}" pointer-events="none" clip-path="url(#dz-board)">`
    + (shoot ? `<g data-dz="shoot" data-cells="${shoot.n}" data-total="${shoot.total}" fill="url(#dz-hatch)" opacity="0.55">${cellRects(shoot)}</g>` : '')
    + `<g filter="url(#dz-blur)">`
    + (layers.possible.length ? `<g data-dz="charge-possible" fill="#c0392b" opacity="0.12">${layers.possible.join('')}</g>` : '')
    + (layers.likely.length ? `<g data-dz="charge-likely" fill="#c0392b" opacity="0.2">${layers.likely.join('')}</g>` : '')
    + '</g></g>';
}

// Where an army can shoot next turn, square by square (1"): a square is hatched when a unit of that army can SEE
// it from where it stands now (13.x sight lines through the layout's terrain, a 32 mm base as the target) and it
// is within that unit's move + longest range. Sight is taken from up to 6 of the unit's models (its outermost
// ones), and cached per unit position, so dragging your own units does not recompute it.
const dzCache = new Map();
function repModels(models) {
  if (models.length <= 6) return models;
  const by = (f) => models.reduce((a, m) => (f(m) < f(a) ? m : a));
  const pick = new Set([by(m => m.dx), by(m => -m.dx), by(m => m.dy), by(m => -m.dy), models[0], models[Math.floor(models.length / 2)]]);
  return [...pick];
}
function shootCells(side) {
  const l = currentLayout();
  if (!l) return null;
  const t0 = performance.now();
  let fresh = 0;
  const acc = { cols: 44, rows: 60, step: 1, cells: new Uint8Array(44 * 60) };
  for (const t of placed().filter(x => x.side === side && x.u.ranges.length)) {
    const reach = t.u.move + Math.max(...t.u.ranges);
    const key = `${l.id}|${t.tk}|${t.x.toFixed(2)}|${t.y.toFixed(2)}|${t.rot}|${t.models.length}|${reach}|${t.models.map(m => `${m.dx.toFixed(1)},${m.dy.toFixed(1)}`).join(';')}`;
    let v = dzCache.get(key);
    if (!v) {
      fresh++;
      const rep = repModels(t.models);
      const seen = visibleCells({ x: t.x, y: t.y, models: rep }, l.pieces);
      const cells = new Uint8Array(seen.cells.length);
      for (let i = 0; i < seen.cols; i++) for (let j = 0; j < seen.rows; j++) {
        const k = i * seen.rows + j;
        if (!seen.cells[k]) continue;
        const x = (i + 0.5) * seen.step, y = (j + 0.5) * seen.step;
        // within move + range of any model (base edge to the middle of the square)
        if (t.models.some(m => Math.hypot(t.x + m.dx - x, t.y + m.dy - y) - Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0) <= reach)) cells[k] = 1;
      }
      v = cells;
      dzCache.set(key, v);
      if (dzCache.size > 200) dzCache.delete(dzCache.keys().next().value);
    }
    for (let k = 0; k < v.length; k++) if (v[k]) acc.cells[k] = 1;
  }
  const n = acc.cells.reduce((s, c) => s + c, 0);
  if (fresh) console.log(`[board] shooting danger from ${side}: ${n} of ${acc.cells.length} squares (${fresh} unit(s) worked out, ${Math.round(performance.now() - t0)} ms)`);
  return { ...acc, n, total: acc.cells.length };
}
/** One rectangle per run of marked squares down a column. */
function cellRects(v) {
  const out = [];
  for (let i = 0; i < v.cols; i++) {
    let j = 0;
    while (j < v.rows) {
      if (!v.cells[i * v.rows + j]) { j++; continue; }
      let k = j;
      while (k < v.rows && v.cells[i * v.rows + k]) k++;
      out.push(`<rect x="${i * v.step}" y="${j * v.step}" width="${v.step}" height="${(k - j) * v.step}"/>`);
      j = k;
    }
  }
  return out.join('');
}

// Where an army's reserves can be set up in this step (planeval.arrivalZones): hatched = within 6" of an edge
// (any unit in reserves), tinted = anywhere for a Deep Strike unit; nothing within 8" of the other army's models.
function arriveInfo(b) {
  const X = b.arrive, Y = X === 'A' ? 'B' : 'A';
  const p = plan(), l = currentLayout();
  if (!X || !p || !l) return null;
  const toks = placed();
  const round = Math.max(2, curIndex());      // step N = battle round N; at Deploy and Turn 1 it shows the first arrivals (round 2)
  const onBoard = new Set([...toks.map(t => t.tk), ...embarkedIn(stepTokens()).keys()]);
  const army = ctx.state.armies[X];
  const off = army.units.filter(u => !onBoard.has(`${X}:${u.key}`));
  const ds = (list) => list.filter(u => unitInfo(X, u.key)?.flags?.deepStrike);
  const zone = DEPLOYMENTS[l.deployment]?.zones?.find(z => z.player === zoneOf(Y))?.poly ?? null;
  return { X, Y, round, off, dsOff: ds(off), dsAny: ds(army.units).length > 0, zone, zones: arrivalZones(toks.filter(t => t.side === Y), round), early: earlyArrival(army) };
}
function arriveSvg(b) {
  const a = arriveInfo(b);
  if (!a) return '';
  const col = C[a.X], e = a.zones.band;
  const holes = a.zones.blocked.map(c => `<circle cx="${f2(c.x)}" cy="${f2(c.y)}" r="${f2(c.r)}"/>`).join('');
  const band = `<rect x="0" y="0" width="${BOARD.w}" height="${e}"/><rect x="0" y="${BOARD.h - e}" width="${BOARD.w}" height="${e}"/><rect x="0" y="0" width="${e}" height="${BOARD.h}"/><rect x="${BOARD.w - e}" y="0" width="${e}" height="${BOARD.h}"/>`;
  const closed = a.zones.zoneClosed && a.zone ? `<polygon points="${a.zone.map(q => q.join(',')).join(' ')}"/>` : '';
  return `<defs><pattern id="arr-hatch" width="1.2" height="1.2" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)"><rect width="0.3" height="1.2" fill="${col}"/></pattern>`
    + `<mask id="arr-any" maskUnits="userSpaceOnUse" x="0" y="0" width="${BOARD.w}" height="${BOARD.h}"><rect x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="#fff"/><g fill="#000">${holes}</g></mask>`
    + `<mask id="arr-edge" maskUnits="userSpaceOnUse" x="0" y="0" width="${BOARD.w}" height="${BOARD.h}"><rect x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="#000"/><g fill="#fff">${band}</g><g fill="#000">${holes}${closed}</g></mask></defs>`
    + `<g id="arrive-layer" data-for="${a.X}" data-round="${a.zones.round}" data-closed="${a.zones.zoneClosed ? 1 : 0}" data-blocked="${a.zones.blocked.length}" pointer-events="none">`
    + (a.dsAny ? `<rect data-arr="deep-strike" x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="${col}" opacity="0.13" mask="url(#arr-any)"/>` : '')
    + `<rect data-arr="edge" x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="url(#arr-hatch)" opacity="0.5" mask="url(#arr-edge)"/></g>`;
}
function arriveBar() {
  const b = boardState();
  const a = arriveInfo(b);
  const short = (u) => shortName(u.name);
  return `<span class="lab tiny muted">⇣ Reserves can arrive</span>
    ${ctx.seg('board-arrive', b.arrive ?? 'off', [['off', 'Off'], ['A', 'A'], ['B', 'B']], 'compact')}
    ${arriveDetailHtml(b)}`;
}
/** With the reserves overlay on: where that army's reserves can arrive this step. */
function arriveDetailHtml(b) {
  const a = arriveInfo(b);
  const short = (u) => shortName(u.name);
  return `${a ? `<span class="tiny muted" style="flex-basis:100%" id="board-arrive-note">Battle round ${a.round}${curIndex() < 2 ? ' (the first round reserves can arrive)' : ''}${a.zones.late ? ' — a unit still in reserves at the end of round 3 is destroyed' : ''}. Hatched: wholly within 6" of an edge, for any unit in reserves${a.zones.zoneClosed ? `; not in ${a.Y}'s deployment zone before round 3` : ''} (20.04).${a.dsAny ? ` Tinted: anywhere for a Deep Strike unit (24.09).` : ` ${a.X} has no Deep Strike unit.`} Clear: within 8" of ${a.Y}'s models. Every base must fit; a unit needs room for all its models.
      ${a.early ? `<br><span id="board-arrive-early"><b>${ctx.esc(a.early.name)}</b> (${ctx.esc(a.early.owner)}): one unit a turn arrives as if the battle round were one higher, so it can come in battle round 1${a.zones.zoneClosed ? `, and into ${a.Y}'s deployment zone now` : ''}.</span>` : ''}
      <br>${a.off.length ? `Not on the board in this step: <b>${a.off.map(u => `${ctx.esc(short(u))}${a.dsOff.includes(u) ? ' (Deep Strike)' : ''}`).join(', ')}</b>.` : `All of ${a.X}'s units are on the board in this step.`}</span>` : ''}`;
}

// ---- 📐 Bases: two base circles you line up with bases on the table photo (or anywhere on the map); the
// distance between their closest points (01.04), and how sure it is on a photo (measure.mjs)
function measInfo(m) {
  if (!m?.a || !m?.b) return null;
  const r = baseToBase(m.a, m.b);
  const key = photoKey(), shown = (boardState().settings.photoMap ?? 'both') !== 'map';
  const sa = shown && photoScaleAt(key, BOARD, m.a.x, m.a.y), sb = shown && photoScaleAt(key, BOARD, m.b.x, m.b.y);
  const err = sa && sb ? measureError({ sA: sa.s, sB: sb.s, sCorner: sa.sCorner, dist: r.edge }) : null;
  return { ...r, err, ppi: sa && sb ? Math.min(sa.s, sb.s) : null };
}
function measSvg(m) {
  if (!m?.a) return '';
  const R = (mm) => Math.max(0.18, (mm || 0) / 25.4 / 2);
  const mark = (k, p) => `<g data-meas="${k}" style="cursor:grab"><circle cx="${f2(p.x)}" cy="${f2(p.y)}" r="${f2(R(p.mm) + 0.9)}" fill="#000" fill-opacity="0.001"/>`
    + `<circle cx="${f2(p.x)}" cy="${f2(p.y)}" r="${f2(R(p.mm))}" fill="${C.ruler}" fill-opacity="0.12" stroke="${C.ruler}" stroke-width="0.1"/>`
    + `<path d="M${f2(p.x - 0.3)} ${f2(p.y)}H${f2(p.x + 0.3)}M${f2(p.x)} ${f2(p.y - 0.3)}V${f2(p.y + 0.3)}" stroke="${C.ruler}" stroke-width="0.06"/>`
    + `<text x="${f2(p.x)}" y="${f2(p.y - R(p.mm) - 0.35)}" font-size="0.8" text-anchor="middle" fill="${C.ruler}" stroke="#fff" stroke-width="0.25" paint-order="stroke" font-weight="700" font-family="system-ui,sans-serif">${k.toUpperCase()}</text></g>`;
  const i = measInfo(m);
  let line = '';
  if (i) {
    const [p, q] = [i.p, i.q], mx = (p[0] + q[0]) / 2, my = (p[1] + q[1]) / 2;
    const txt = `${fmtBase(i.edge)}${i.err != null ? ` ±${i.err.toFixed(1)}` : ''}`;
    const w = Math.max(2.6, txt.length * 0.58 + 0.4);
    line = `<line x1="${f2(p[0])}" y1="${f2(p[1])}" x2="${f2(q[0])}" y2="${f2(q[1])}" stroke="${C.ruler}" stroke-width="0.12" pointer-events="none"/>`
      + `<g id="meas-label" pointer-events="none"><rect x="${f2(mx - w / 2)}" y="${f2(my - 0.8)}" width="${f2(w)}" height="1.4" rx="0.3" fill="#fff" stroke="${C.ruler}" stroke-width="0.06"/><text x="${f2(mx)}" y="${f2(my + 0.32)}" font-size="0.95" text-anchor="middle" font-weight="700" font-family="system-ui,sans-serif" fill="#111">${txt}</text></g>`;
  }
  return line + mark('a', m.a) + (m.b ? mark('b', m.b) : '');
}
function measPanel() {
  const b = boardState(), m = b.meas ?? {}, i = measInfo(m);
  const sizeSeg = (k) => m[k] ? `<div class="modrow" style="margin-top:6px"><div class="lab tiny muted">Base ${k.toUpperCase()}</div><div class="seg compact" id="board-meas-mm-${k}">${BASE_SIZES.map(v => `<button data-action="board-meas-mm" data-which="${k}" data-value="${v}" class="${v === m[k].mm ? 'on' : ''}">${v ? `${v}` : 'Point'}</button>`).join('')}</div></div>` : '';
  return `<div class="card" id="board-meas">
    <div class="row" style="gap:6px;align-items:baseline"><span class="title grow">📐 Base to base</span>${m.a ? '<button class="chip" data-action="board-meas-clear">Clear</button>' : ''}</div>
    ${i ? `<div style="font-size:28px;font-weight:800;line-height:1.1" id="board-meas-edge">${fmtBase(i.edge)}${i.err != null ? ` <span class="small muted" style="font-weight:600">± ${i.err.toFixed(1)}"</span>` : ''}</div>
      <div class="tiny muted" id="board-meas-centre">Centre to centre ${i.centre.toFixed(1)}"${i.ppi ? ` · the photo shows ${Math.round(i.ppi)} px per inch there` : ''}</div>`
      : `<div class="small" style="margin-top:4px">${m.a ? 'Tap the second base.' : 'Tap a base, then another.'}</div>`}
    ${sizeSeg('a')}${sizeSeg('b')}
    <div class="tiny muted" style="margin-top:6px">Drag a circle onto the base in the photo (zoom in with ＋ first), and pick the base size: the number is between the closest edges, as 40k measures. <b>Point</b> measures to a spot (a hull, an objective's centre). A tap with both down starts again.
    ${i?.err != null ? ' The ± is an estimate from how sharp the photo is there and how well the corners were tapped: a photo from higher and more square-on is better. Not a table ruling.' : ' Add a table photo (below) to measure on the real table.'}</div>
    <div class="tiny" style="margin-top:6px"><a href="./ar-test.html" id="ar-test-link">Live AR measuring test →</a> <span class="muted">checks whether this tablet can measure the table in AR, and how accurately.</span></div>
  </div>`;
}

function rulerSvg(r) {
  if (!r) return '';
  const { x1, y1, x2, y2 } = r;
  return `<line x1="${f2(x1)}" y1="${f2(y1)}" x2="${f2(x2)}" y2="${f2(y2)}" stroke="${C.ruler}" stroke-width="0.12"/>`
    + `<circle cx="${f2(x1)}" cy="${f2(y1)}" r="0.25" fill="${C.ruler}"/>` + label((x1 + x2) / 2, (y1 + y2) / 2, `${Math.hypot(x2 - x1, y2 - y1).toFixed(1)}"`, 'ruler-label');
}

function label(x, y, text, id = '') {
  return `<g ${id ? `id="${id}"` : ''}><rect x="${f2(x - 1.3)}" y="${f2(y - 0.75)}" width="2.6" height="1.3" rx="0.3" fill="#ffffff" stroke="${C.ruler}" stroke-width="0.05"/><text x="${f2(x)}" y="${f2(y + 0.3)}" font-size="0.85" text-anchor="middle" font-family="system-ui,sans-serif" font-weight="700" fill="${C.ruler}">${text}</text></g>`;
}

function shortName(n) {
  // a cut name keeps its "(2)": two units of one datasheet must not read the same on the map and in the cards
  const m = / \(\d+\)$/.exec(n), tail = m ? m[0] : '', s = tail ? n.slice(0, -tail.length) : n;
  return n.length > 22 ? `${s.slice(0, 21 - tail.length)}…${tail}` : n;
}

function closestCentres(a, b) {
  let best = null, bd = Infinity;
  for (const ma of a.models) for (const mb of b.models) {
    const p = [a.x + ma.dx, a.y + ma.dy], q = [b.x + mb.dx, b.y + mb.dy];
    const d = Math.hypot(q[0] - p[0], q[1] - p[1]);
    if (d < bd) { bd = d; best = [p, q]; }
  }
  return best;
}

// ---------------------------------------------------------------------------
// HTML around the SVG

/** Plan steps (Deploy, Turn 1, ...), ＋ Next turn, ⑂ Branch here and Move / Ruler. */
function stepsRowHtml() {
  const b = boardState(), p = plan(), esc = ctx.esc;
  return `<div class="row" style="gap:6px;flex-wrap:wrap">
        ${p ? curSteps().map((s, i) => `<button class="chip ${i === curIndex() ? 'on' : ''}" data-action="board-step" data-i="${i}">${esc(s.name)}</button>`).join('') : ''}
        ${p?.live ? '' : `<button class="chip" data-action="board-step-add">＋ Next turn</button>
        <button class="chip" data-action="board-branch" id="board-branch" title="Split the plan after this turn: your decision, or a chance outcome">⑂ Branch here</button>`}
        <button class="chip ${p?.live ? 'on' : ''}" data-action="board-live" id="board-live" aria-pressed="${!!p?.live}" title="The table as it is now, following the round and turn of the game on the tracker">🔴 Live table</button>
        <button class="chip" data-action="board-ar" id="board-ar" title="Live AR: this layout and plan over the camera view of your table">🥽 AR</button>
        <span class="grow"></span>
        <span class="row board-tools"><span class="row undo-host" id="board-undo-host">${undoButtons()}</span>${ctx.seg('board-mode', b.mode, [['move', '✋ Move'], ['ruler', '📏 Ruler'], ['meas', '📐 Bases']], 'compact')}</span>
        <span class="undo-note-row" id="board-undo-note-host">${undoNote()}</span>
      </div>`;
}

export function boardView() {
  const st = ctx.state;
  const b = boardState();
  const esc = ctx.esc;
  if (!st.armies.A || !st.armies.B) return `<p class="hint">Load both armies to plan on the board.</p>`;
  if (triMode()) return triView();
  const l = currentLayout();
  const ms = missionsFor(dispOf('A'), dispOf('B'));
  const dep = l ? DEPLOYMENTS[l.deployment] : null;
  const p = plan();
  const locked = setupLocked();
  // the mission set-up (dispositions, layout, zones) only on the Deploy step: later turns are about moving units
  const onDeploy = curIndex() === 0;
  const dispSel = (side) => `<select class="sel" data-input="board-disp" data-side="${side}" aria-label="Force Disposition of army ${side}">
      ${DISPOSITIONS.map(d => `<option value="${d.id}" ${d.id === dispOf(side) ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select>`;
  const toks = placed();
  const onBoard = new Set([...toks.map(t => t.tk), ...embarkedIn(stepTokens()).keys()]);
  const tray = (side) => st.armies[side].units.filter(u => !onBoard.has(`${side}:${u.key}`) && !unitInfo(side, u.key)?.dead)
    .map(u => `<button class="chip" data-action="board-place" data-side="${side}" data-key="${esc(u.key)}" style="border-color:${C[side]}">＋ ${esc(u.name)}</button>`).join('');
  const dead = ['A', 'B'].reduce((n, X) => n + st.armies[X].units.filter(u => !onBoard.has(`${X}:${u.key}`) && unitInfo(X, u.key)?.dead).length, 0);
  const left = st.armies.A.units.length + st.armies.B.units.length - onBoard.size - dead;
  // The map comes first (one column on a phone; the left pane on a tablet): the plan
  // steps and the units still to place sit right above it, everything else below / beside.
  const wideNow = ctx.wide?.() ?? false;
  const reuse = reusablePlan();
  // plan steps, Move / Ruler and the units still to place: above the map on a phone
  // (one swipeable line), at the top of the side pane on a tablet (the map gets the height)
  const stepsRow = stepsRowHtml();
  const di = drillInfo();
  const trayHtml = di ? drillHtml(di) : left ? `<div class="unit-strip ${wideNow ? 'wrap' : ''}" id="board-tray" aria-label="Units not on the board: tap one to place it">
        <span class="tiny muted" style="flex:none">Place ${left}:</span>${tray('A')}${tray('B')}</div>` : '';
  return `<div id="board-dock" class="board-dock">${dockHtml()}</div><div class="blay"><div class="col map">
    <section class="section b-steps">
      ${wideNow ? '' : stepsRow + trayHtml}
      ${wideNow ? '' : `<div id="board-treemap-host">${treeMapHtml()}</div>`}
      ${reuse ? `<div class="warnbox" id="board-reuse" style="display:flex;gap:8px;align-items:center"><span class="grow">You planned this layout with this list against <b>${esc(reuse.vs)}</b> (${reuse.n} unit positions).</span><button class="btn primary" data-action="board-reuse">Use my deployment</button></div>` : ''}
      <div id="board-live-host" style="margin-top:8px">${liveBarHtml()}${planBarHtml()}${hintBarHtml()}</div>
      <div id="board-models-host" style="margin-top:8px">${modelsBar()}</div>
      <div class="board-wrap card" id="board-host" style="padding:4px;${wideNow ? '' : 'margin-top:8px'}">${boardSvg()}</div>
      <div class="row tiny muted" style="margin-top:4px;gap:6px"><span class="grow">Pinch or use ± to zoom · drag empty space to pan</span>
        <button class="icon-btn" data-action="board-zoom" data-z="0.7" aria-label="Zoom in">＋</button>
        <button class="icon-btn" data-action="board-zoom" data-z="1.4" aria-label="Zoom out">－</button>
        <button class="icon-btn" data-action="board-zoom" data-z="0" aria-label="Fit board">⤢</button></div>
    </section>
    </div><div class="col side">
    ${wideNow ? `<section class="section">${stepsRow}<div id="board-treemap-host">${treeMapHtml()}</div></section>` : ''}
    <section class="section" id="board-panel">${selectionPanel()}</section>
    <div id="board-next-host">${nextTurnHtml()}</div>
    <div id="board-warnings-host">${stepWarningsHtml()}</div>
    ${wideNow && trayHtml ? `<section class="section">${trayHtml}</section>` : ''}
    ${onDeploy ? '' : `<section class="section"><div class="row" style="gap:6px" id="board-setup-turn">
      <span class="tiny muted grow">Dispositions, layout and zones are set on the Deploy step.</span>
      <button class="btn ghost" data-action="board-share">⇪ Share image</button>
      <button class="btn ghost" data-action="share-link" data-from="board" id="share-board">🔗 Share link</button></div>
      ${ctx.shareLinkHtml?.('board') ?? ''}</section>`}
    ${!onDeploy ? '' : `<section class="section"><div class="card" id="board-setup">
      ${locked ? `<div class="lockbox" id="board-setup-lock"><span class="grow">🔒 Mission set-up locked: a game is on the tracker (round ${ctx.gameRound?.() ?? '?'}). Changing it now changes both primaries and the map under that game.</span>
        <button class="btn ghost" data-action="board-setup-unlock" id="board-setup-unlock">Change anyway</button></div>` : ''}
      <fieldset class="plain" ${locked ? 'disabled' : ''}>
      <div class="row" style="gap:8px">
        <div class="grow"><div class="lab tiny muted">A · ${esc(st.armies.A.faction)}</div>${dispSel('A')}</div>
        <div class="grow"><div class="lab tiny muted">B · ${esc(st.armies.B.faction)}</div>${dispSel('B')}</div>
      </div>
      ${['A', 'B'].filter(dispOverridden).map(X => `<div class="warnbox" id="board-disp-override-${X}" style="display:flex;gap:8px;align-items:center"><span class="grow"><b>${X}</b> is set to <b>${esc(dispositionName(dispOf(X)))}</b> here, but ${X}'s list says <b>${esc(dispositionName(listDisp(X)))}</b>. The missions and layouts follow the one set here.</span>
        <button class="btn" data-action="board-disp-list" data-side="${X}">Use the list's</button></div>`).join('')}
      <div class="tiny muted" id="board-layout-source" style="margin-top:8px">Layouts: ${esc(LAYOUTS_SOURCE.version)} (${esc(LAYOUTS_SOURCE.date)}; ${esc(LAYOUTS_SOURCE.note)}). Checked ${esc(longDate(LAYOUTS_SOURCE.checked))}: ${esc(LAYOUTS_SOURCE.sample)}.</div>
      <div class="row" style="margin-top:6px">${ctx.chip('board-measure', !!b.measure, '📏 Table set-up measurements', 'id="board-measure-chip"')}</div>
      <div class="modrow" style="margin-top:8px"><div class="lab">Layout (official GW 11e)</div>${ctx.seg('board-variant', l?.variant ?? 1, [[1, 'Layout A'], [2, 'Layout B'], [3, 'Layout C']], 'compact')}</div>
      <div class="small" style="margin-top:8px" id="board-mission"><b>A</b> plays <b>${esc(ms.A ?? '?')}</b> · <b>B</b> plays <b>${esc(ms.B ?? '?')}</b><br><span class="muted">${esc(dep?.name ?? '')} · A deploys in the <span style="color:var(--side-a-ink)">blue</span> zone</span></div>
      </fieldset>
      <div class="row" style="margin-top:8px;gap:6px">
        <button class="btn ghost grow" data-action="board-swap-zones" ${locked ? 'disabled' : ''}>⇅ Swap zones</button>
        <button class="btn ghost grow" data-action="board-share">⇪ Share image</button>
        <button class="btn ghost grow" data-action="share-link" data-from="board" id="share-board">🔗 Share link</button>
      </div>
      ${ctx.shareLinkHtml?.('board') ?? ''}
    </div></section>`}
    <section class="section">
      <div class="row" style="gap:6px;flex-wrap:wrap;align-items:center" id="board-danger-bar">${dangerBar()}</div>
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap;align-items:center" id="board-arrive-bar">${arriveBar()}</div>
      ${planToolsHtml()}
    </section>
  </div></div>`;
}

// ---------------------------------------------------------------------------
// Tablet: three columns — my army | steps, map and plan tools | the opponent's army

const otherSide = (X) => (X === 'A' ? 'B' : 'A');
const sideInk = (X) => `var(--side-${X.toLowerCase()}-ink)`;

function triView() {
  const st = ctx.state, b = boardState(), esc = ctx.esc;
  const me = st.armies[ctx.me?.()] ? ctx.me() : 'A', opp = otherSide(me);
  const onDeploy = curIndex() === 0;
  const reuse = reusablePlan();
  const di = drillInfo();
  return `<div class="tri ${onDeploy ? 'deploy' : ''}" id="board-tri" data-me="${me}">
    <aside class="tri-l tri-army" id="board-army-${me}" data-side="${me}" style="--side-ink:${sideInk(me)}"><div id="board-army-${me}-in">${armyColInner(me)}</div></aside>
    <div class="tri-c">
      <section class="section b-steps">${stepsRowHtml()}<div id="board-treemap-host">${treeMapHtml()}</div></section>
      ${onDeploy ? triSetupRow() : ''}
      <div id="board-meas-host">${b.mode === 'meas' ? `<div style="margin-bottom:8px">${measPanel()}</div>` : ''}</div>
      ${di ? drillHtml(di) : ''}
      ${reuse ? `<div class="warnbox" id="board-reuse" style="display:flex;gap:8px;align-items:center"><span class="grow">You planned this layout with this list against <b>${esc(reuse.vs)}</b> (${reuse.n} unit positions).</span><button class="btn primary" data-action="board-reuse">Use my deployment</button></div>` : ''}
      <div id="board-live-host">${liveBarHtml()}${planBarHtml()}${hintBarHtml()}</div>
      <div id="board-models-host">${modelsBar()}</div>
      <div class="board-wrap card" id="board-host" style="padding:4px">${boardSvg()}</div>
      <div class="row tiny muted" style="margin-top:4px;gap:6px"><span class="grow">Pinch or ± to zoom · drag to pan · tap a unit here or in its list</span>
        <button class="icon-btn" data-action="board-zoom" data-z="0.7" aria-label="Zoom in">＋</button>
        <button class="icon-btn" data-action="board-zoom" data-z="1.4" aria-label="Zoom out">－</button>
        <button class="icon-btn" data-action="board-zoom" data-z="0" aria-label="Fit board">⤢</button></div>
    </div>
    <div class="tri-t">
      <div id="board-next-host">${nextTurnHtml()}</div>
      <div id="board-warnings-host">${stepWarningsHtml()}</div>
      <section class="section">${triBelowMap(onDeploy)}${planToolsHtml()}</section>
    </div>
    <aside class="tri-r tri-army" id="board-army-${opp}" data-side="${opp}" style="--side-ink:${sideInk(opp)}"><div id="board-army-${opp}-in">${armyColInner(opp)}</div></aside>
  </div>`;
}

/** Deploy step, above the map: the layout letter, the deployment, swap zones (locked during a game). */
function triSetupRow() {
  const l = currentLayout(), dep = l ? DEPLOYMENTS[l.deployment] : null, locked = setupLocked();
  return `<div class="card tri-setup" id="board-setup">
    ${locked ? `<div class="lockbox" id="board-setup-lock"><span class="grow">🔒 Mission set-up locked: a game is on the tracker (round ${ctx.gameRound?.() ?? '?'}). Changing it now changes both primaries and the map under that game.</span>
      <button class="btn ghost" data-action="board-setup-unlock" id="board-setup-unlock">Change anyway</button></div>` : ''}
    <div class="row" style="gap:8px;align-items:center;flex-wrap:wrap">
      <fieldset class="plain row" style="gap:8px;align-items:center" ${locked ? 'disabled' : ''}><span class="lab tiny muted">Layout</span>${ctx.seg('board-variant', l?.variant ?? 1, [[1, 'A'], [2, 'B'], [3, 'C']], 'compact')}</fieldset>
      <span class="small grow">${ctx.esc(dep?.name ?? '')}</span>
      <button class="btn ghost" data-action="board-swap-zones" ${locked ? 'disabled' : ''}>⇅ Swap zones</button>
    </div></div>`;
}

/** Below the map: on Deploy the rest of the set-up (missions, measurements, sources); always Share. */
function triBelowMap(onDeploy) {
  const b = boardState(), esc = ctx.esc, l = currentLayout(), dep = l ? DEPLOYMENTS[l.deployment] : null;
  const ms = missionsFor(dispOf('A'), dispOf('B'));
  const share = `<button class="btn ghost" data-action="board-share">⇪ Share image</button>
      <button class="btn ghost" data-action="share-link" data-from="board" id="share-board">🔗 Share link</button>`;
  if (!onDeploy) return `<div class="row" style="gap:6px;align-items:center;flex-wrap:wrap" id="board-setup-turn">
      <span class="tiny muted grow">Dispositions, layout and zones are set on the Deploy step.</span>${share}</div>${ctx.shareLinkHtml?.('board') ?? ''}`;
  return `<div class="small" id="board-mission"><b>A</b> plays <b>${esc(ms.A ?? '?')}</b> · <b>B</b> plays <b>${esc(ms.B ?? '?')}</b> · <span class="muted">${esc(dep?.name ?? '')} · A deploys in the <span style="color:var(--side-a-ink)">blue</span> zone</span></div>
    <div class="row" style="gap:6px;margin-top:6px;align-items:center;flex-wrap:wrap">${ctx.chip('board-measure', !!b.measure, '📏 Table set-up measurements', 'id="board-measure-chip"')}<span class="grow"></span>${share}</div>
    ${ctx.shareLinkHtml?.('board') ?? ''}
    <details class="tiny muted" style="margin-top:6px"><summary>Where the layouts come from</summary><div id="board-layout-source">Layouts: ${esc(LAYOUTS_SOURCE.version)} (${esc(LAYOUTS_SOURCE.date)}; ${esc(LAYOUTS_SOURCE.note)}). Checked ${esc(longDate(LAYOUTS_SOURCE.checked))}: ${esc(LAYOUTS_SOURCE.sample)}.</div></details>`;
}

/** One army's column: who they are, their mission, their overlays, the matchup card when one of theirs is the target, their units. */
function armyColInner(X) {
  const st = ctx.state, b = boardState(), esc = ctx.esc;
  const a = st.armies[X];
  if (!a) return '';
  const onDeploy = curIndex() === 0, locked = setupLocked();
  const toks = placed();
  const emb = embarkedIn(stepTokens());
  const byTk = new Map(toks.map(t => [t.tk, t]));
  const ms = missionsFor(dispOf('A'), dispOf('B'));
  const pts = a.units.reduce((n, u) => n + (u.points || 0), 0);
  const me = (ctx.me?.() ?? 'A') === X;
  const score = ctx.gameScore?.(), g = st.mission?.game;
  const live = score?.started && g;
  const di = drillInfo();
  const s1 = byTk.get(b.sel) ?? null, s2 = byTk.get(b.sel2) ?? null;
  const onBoardN = a.units.filter(u => byTk.has(`${X}:${u.key}`) || emb.has(`${X}:${u.key}`)).length;
  const dispSel = `<select class="sel" data-input="board-disp" data-side="${X}" aria-label="Force Disposition of army ${X}">
      ${DISPOSITIONS.map(d => `<option value="${d.id}" ${d.id === dispOf(X) ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select>`;
  const rows = a.units.map(u => {
    const tk = `${X}:${u.key}`, t = byTk.get(tk);
    const dot = `<span class="tri-dot" aria-hidden="true"></span>`;
    const ui = unitInfo(X, u.key);
    if (ui?.dead) return `<div class="tri-unit off dead" data-dead="${esc(tk)}">${dot}<span class="nm">${esc(u.name)}</span><button class="linkish tiny" data-action="loss-reset" data-side="${X}" data-unit="${esc(u.key)}" title="Destroyed (no models left): tap to bring it back at full strength">destroyed ↺</button></div>`;
    const lost = ui && ui.left < ui.total ? `${ui.left}/${ui.total} · ` : '';
    if (t) {
      const isSel = tk === b.sel, isTgt = tk === b.sel2;
      const row = `<button class="tri-unit ${isSel ? 'sel' : ''} ${isTgt ? 'tgt' : ''}" data-action="board-pick" data-tk="${esc(tk)}" aria-pressed="${isSel || isTgt}">${dot}<span class="nm">${esc(u.name)}</span><span class="tiny muted">${lost}${isTgt ? 'target' : 'on board'}</span></button>`;
      return isSel ? `<div class="tri-selbox">${row}<div id="board-panel">${triUnitPanel(t, toks)}</div></div>` : row;
    }
    if (emb.has(tk)) return `<div class="tri-unit off">${dot}<span class="nm">${esc(u.name)}</span><span class="tiny muted">embarked</span></div>`;
    // in a drop drill the drill card in the middle sets units up, one at a time
    if (di) return `<div class="tri-unit off">${dot}<span class="nm">${esc(u.name)}</span><span class="tiny muted">${di.res.has(tk) ? 'reserves' : 'to set up'}</span></div>`;
    return `<button class="tri-unit off" data-action="board-place" data-side="${X}" data-key="${esc(u.key)}">${dot}<span class="nm">${esc(u.name)}</span><span class="tiny tri-add">${onDeploy ? '＋ Place' : 'reserves ＋'}</span></button>`;
  }).join('');
  return `<div class="row" style="align-items:baseline;gap:6px"><b class="tri-letter">${X}</b><b class="grow ellipsis">${esc(a.faction)}${me ? ' <span class="tiny muted">(me)</span>' : ''}</b><span class="tiny muted">${pts} pts</span></div>
    ${onDeploy ? `<fieldset class="plain" style="margin-top:6px" ${locked ? 'disabled' : ''}>${dispSel}</fieldset>${dispOverridden(X) ? `<div class="warnbox" id="board-disp-override-${X}"><b>${X}</b> is set to <b>${esc(dispositionName(dispOf(X)))}</b> here, but ${X}'s list says <b>${esc(dispositionName(listDisp(X)))}</b>. The missions and layouts follow the one set here.
      <button class="btn" style="margin-top:6px" data-action="board-disp-list" data-side="${X}">Use the list's</button></div>` : ''}` : ''}
    <div class="tiny" style="margin-top:4px">Plays <b>${esc(ms[X] ?? '?')}</b>${live ? ` · <span id="board-score-${X}">VP ${score[X]} · CP ${g[X]?.cp ?? 0}</span>` : ''}</div>
    <div class="chips" style="margin-top:6px">
      <button class="chip ${b.danger === X ? 'on' : ''}" data-action="board-danger" data-value="${b.danger === X ? 'off' : X}" id="board-danger-${X}" aria-pressed="${b.danger === X}" aria-label="Danger next turn from ${X}" title="Where ${X} can shoot and charge next turn">⚠ Danger</button>
      <button class="chip ${b.arrive === X ? 'on' : ''}" data-action="board-arrive" data-value="${b.arrive === X ? 'off' : X}" id="board-arrive-${X}" aria-pressed="${b.arrive === X}" aria-label="Where ${X}'s reserves can arrive" title="Where ${X}'s reserves can arrive">⇣ Reserves</button>
    </div>
    ${b.danger === X ? `<div class="row tri-detail" style="gap:6px;flex-wrap:wrap;align-items:center">${dangerDetailHtml(b)}</div>` : ''}
    ${b.arrive === X ? `<div class="row tri-detail" style="gap:6px;flex-wrap:wrap;align-items:center">${arriveDetailHtml(b)}</div>` : ''}
    ${s1 && s2 && s2.side === X ? pairHtml(s1, s2) : ''}
    <div class="lab tiny muted" style="margin-top:8px">Units · ${onBoardN}/${a.units.length} on the board</div>
    <div class="tri-list">${rows}</div>`;
}

/** The selected unit, under its row: what to show around it first; position, facing and formation folded. */
function triUnitPanel(s1, toks) {
  const b = boardState();
  return `<div class="tiny muted">${statsLine(s1)}</div>
    <div class="lab tiny muted" style="margin-top:6px">Show around it</div><div class="chips tri-rings">${ringsHtml(s1)}</div>
    ${seeNote()}
    ${coherencyHtml(s1)}
    <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap">${modelsBtn(s1)}${stepTokens()[s1.tk]?.mo && b.modelsOf !== s1.tk ? '<button class="chip" data-action="board-models-reset">↺ Formation</button>' : ''}</div>
    <div class="row" style="gap:6px;margin-top:6px">
      <button class="chip ${b.posOpen ? 'on' : ''}" data-action="board-pos-toggle" id="board-pos-toggle" aria-expanded="${!!b.posOpen}">Position · facing · formation ${b.posOpen ? '▴' : '▾'}</button>
      <span class="grow"></span><button class="icon-btn" data-action="board-remove" aria-label="Remove from board">✕</button></div>
    ${b.posOpen ? `<div id="board-pos-box">${posHtml(s1)}${spacingHtml(s1)}</div>` : ''}
    ${shockHtml(s1)}
    ${lossHtml(s1)}
    ${transportPanel(s1)}
    ${scoutPanel(s1)}
    ${hullPanel(s1)}
    ${threatHtml(s1, toks)}`;
}

/** Plans (Main, copies, going first / second), the drop drill, branches and the table photo. */
function planToolsHtml() {
  const st = ctx.state, b = boardState(), esc = ctx.esc;
  return `      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap;align-items:center" id="board-variants">
        <span class="lab tiny muted">Plan</span>
        ${planRoot() ? planRoot().variants.map((vv, i) => (vv.parent != null ? '' : `<button class="chip ${i === rootOf(planRoot().variants, planRoot().v) ? 'on' : ''}" data-action="board-plan-pick" data-i="${i}">${esc(vv.name)}</button>`)).join('') : ''}
        <button class="chip" data-action="board-plan-copy">＋ Copy plan</button>
        ${plan()?.drill ? '' : ctx.chip('board-drill-ask', !!b.drillAsk, '🎯 Drop drill', 'id="board-drill-ask" title="Practise the deployment: set up one unit at a time, alternating"')}
        ${planRoot() && !planRoot().variants.some(vv => vv.when) ? '<button class="chip" data-action="board-plan-split" id="board-plan-split">⇄ Going first / second</button>' : ''}
        ${planRoot()?.variants.length > 1 ? '<button class="icon-btn" data-action="board-plan-rename" aria-label="Rename this plan">✎</button><button class="icon-btn" data-action="board-plan-delete" aria-label="Delete this plan">✕</button>' : ''}
      </div>
      ${b.drillAsk && !plan()?.drill ? `<div class="card" id="board-drill-start" style="margin-top:6px"><div class="small">Who is the <b>Defender</b>? They set up first. The drill is a new plan with an empty Deploy step: your real deployment stays as it is.</div>
        <div class="row" style="gap:6px;margin-top:6px">${['A', 'B'].map(X => `<button class="btn grow" data-action="board-drill-start" data-first="${X}" style="border-color:${C[X]}">${X} · ${esc(st.armies[X].faction)}</button>`).join('')}</div></div>` : ''}
      ${splitNote()}
      <div id="board-tree-host">${treeHtml()}</div>
      <div id="board-photo-bar" style="margin-top:6px">${photoBar()}</div>`;
}

function heatInfoHtml(b) {
  const esc = ctx.esc, h = heatCells(b.danger), at = b.heatAt;
  const list = at ? threatsAt(b.danger, at.x, at.y).sort((p, q) => (q.charge + (q.shoot ? 1 : 0)) - (p.charge + (p.shoot ? 1 : 0))) : null;
  return `<span class="tiny" id="board-heat-info" style="flex-basis:100%">${!h.cells.length ? 'Nothing of that army is on the board in this step.'
    : `Darker = more of ${esc(b.danger)} can reach that square next turn (up to ${h.max.toFixed(1)}: 1 per unit that can shoot it after moving, plus each unit’s chance to charge it). Tap a square for who.`}
    ${list ? `<br><b>At ${at.x.toFixed(0)}" across, ${at.y.toFixed(0)}" down:</b> ${list.length ? list.map(t => `${esc(t.name)} ${[t.shoot ? 'shoot' : '', t.charge > 0.005 ? `charge ${Math.round(t.charge * 100)}%` : ''].filter(Boolean).join(' + ')}`).join(' · ') : 'nothing can reach it'}` : ''}</span>`;
}

function dangerBar() {
  const b = boardState();
  const kinds = b.dangerKinds ?? { shoot: true, charge: true };
  return `<span class="lab tiny muted">⚠ Danger next turn</span>
    ${ctx.seg('board-danger', b.danger ?? 'off', [['off', 'Off'], ['A', 'From A'], ['B', 'From B']], 'compact')}
    ${dangerDetailHtml(b)}`;
}
/** With a danger overlay on: heat map / shooting / charges and what the shading means. */
function dangerDetailHtml(b) {
  const kinds = b.dangerKinds ?? { shoot: true, charge: true };
  return `${b.danger ? `${ctx.chip('board-danger-kind', !!kinds.heat, '🔥 Heat map', 'data-k="heat" id="board-heat-chip"')}${kinds.heat ? heatInfoHtml(b) : ''}${kinds.heat ? '' : `${ctx.chip('board-danger-kind', !!kinds.shoot, 'Shooting', 'data-k="shoot"')}${ctx.chip('board-danger-kind', !!kinds.charge, 'Charges', 'data-k="charge"')}`}
    <span class="tiny muted" style="flex-basis:100%" id="board-danger-note">Hatched: squares a unit of ${ctx.esc(b.danger)} can see from where it stands and reach with its longest gun after a normal move (move + range); clear squares are out of sight or out of reach. A move can open new sight lines. Red: where it can charge (dark ≥ 80%, light ≥ 40%; ignores terrain).</span>` : ''}`;
}

function photoBar() {
  const b = boardState();
  const p = plan();
  if (!p) return '';
  const photo = currentPhoto();
  const pick = (label, cls) => `<label class="btn ${cls}" style="cursor:pointer">${label}<input type="file" accept="image/*" data-input="board-photo" hidden></label>`;
  if (!photo) {
    return `<div class="row" style="gap:6px;align-items:center">${pick('📷 Table photo', 'ghost')}
      <span class="tiny muted grow">Trace the real table: photo from above, tap the 4 corners, then drag the tokens onto the models.</span></div>`;
  }
  return `<div class="row" style="gap:6px;flex-wrap:wrap;align-items:center">
      ${ctx.seg('board-photo-map', b.settings.photoMap ?? 'both', [['photo', 'Photo'], ['both', 'Photo + map'], ['map', 'Map']], 'compact')}
      <button class="btn ghost" data-action="board-photo-adjust">✥ Corners</button>
      <button class="btn ghost" data-action="board-photo-turn" aria-label="Turn the photo">↻ Turn</button>
      ${pick('📷 New', 'ghost')}
      <button class="icon-btn" data-action="board-photo-remove" aria-label="Remove the photo">✕</button>
    </div>
    <div class="tiny muted" style="margin-top:2px">Photo for <b>${ctx.esc(curSteps()[curIndex()]?.name ?? '')}</b> · terrain on the photo not matching the map? The table differs from the GW layout — trust the photo. Tap bases, not heads: tall models lean in photos.</div>`;
}

// little map for the corner screen: zones, and corners numbered 1-4 clockwise from the top-left
function cornerDiagram(next) {
  const l = currentLayout();
  const dep = l && DEPLOYMENTS[l.deployment];
  const zones = (dep?.zones ?? []).map(z => {
    const side = zoneOf('A') === z.player ? 'A' : 'B';
    return `<polygon points="${z.poly.map(p => p.join(',')).join(' ')}" fill="${C[side]}" fill-opacity="0.35"/>`;
  }).join('');
  const terrain = (l?.pieces ?? []).map(p => `<polygon points="${p.poly.map(q => q.join(',')).join(' ')}" fill="${C.feature}" fill-opacity="0.45"/>`).join('');
  const pts = [[0, 0], [BOARD.w, 0], [BOARD.w, BOARD.h], [0, BOARD.h]];
  const marks = pts.map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${i === next ? 6 : 4.5}" fill="${i === next ? C.sel : '#ffffff'}" stroke="#000" stroke-width="0.8"/>`
    + `<text x="${x}" y="${y + 2.6}" font-size="7" font-weight="700" text-anchor="middle" font-family="system-ui,sans-serif">${i + 1}</text>`).join('');
  return `<svg viewBox="-7 -7 58 74" width="58" height="74"><rect x="0" y="0" width="${BOARD.w}" height="${BOARD.h}" fill="${C.mat}" stroke="#000" stroke-width="0.6"/>${zones}${terrain}${marks}</svg>`;
}

async function photoTask(fn, label) {
  try {
    const ok = await fn();
    if (ok !== false) persistBoard();
  } catch (err) {
    console.warn(`[calc] photo ${label} failed`, err);
    alert(`Could not use that photo (${err?.message ?? err}).`);
  }
  refreshBoard();
}

// Phone: the selected unit's main actions stay at the bottom of the screen, so the
// map does not scroll away (the full panel is below the map; on a tablet it is beside it).
function dockHtml() {
  if (triMode()) return '';
  const b = boardState();
  if (b.mode === 'meas') { const i = measInfo(b.meas); return i ? `<div class="row" style="gap:8px;align-items:baseline" id="board-meas-dock"><span class="title grow">📐 ${fmtBase(i.edge)}${i.err != null ? ` <span class="small muted">± ${i.err.toFixed(1)}"</span>` : ''}</span><span class="tiny muted">centre ${i.centre.toFixed(1)}"</span><button class="chip" data-action="board-meas-clear">Clear</button></div>` : ''; }
  const esc = ctx.esc;
  const toks = placed();
  const s1 = toks.find(t => t.tk === b.sel);
  if (!s1) return '';
  const s2 = toks.find(t => t.tk === b.sel2);
  const u = s1.u;
  const ringChip = (k, lab) => ctx.chip('board-ring', !!b.rings[k], lab, `data-k="${k}"`);
  const det = detectionOf(s1);
  const rings = [ringChip('move', `Move ${u.move}"`), u.melee ? ringChip('charge', 'Charge') : '', ...u.ranges.map(r => ringChip(`r${r}`, `Range ${r}"`)), det.range ? ringChip('detect', `Seen ${det.range}"`) : ''].join('');
  let pair = '';
  if (s2) {
    const gap = unitGap(s1, s2), enemy = s1.side !== s2.side;
    pair = `<span class="small" id="dock-gap">→ ${esc(s2.u.cu.name)}: <b>${gap.toFixed(1)}"</b></span>
      ${enemy && u.ranges.length ? '<button class="chip on nocheck" data-action="board-attack" data-phase="shooting">🎯 Shoot →</button>' : ''}
      ${enemy && u.melee ? '<button class="chip on nocheck" data-action="board-attack" data-phase="fight">⚔ Fight →</button>' : ''}`;
  }
  return `<div class="dock-in"><div class="row" style="gap:8px">
      <b class="grow ellipsis" style="color:var(--side-${s1.side.toLowerCase()}-ink)">${esc(u.cu.name)}</b>
      <button class="icon-btn" data-action="board-rotate" data-deg="-15" aria-label="Rotate 15° left">⟲</button>
      <button class="icon-btn" data-action="board-rotate" data-deg="15" aria-label="Rotate 15° right">⟳</button>
      <button class="icon-btn" data-action="board-deselect" aria-label="Clear the selection">✕</button></div>
    <div class="dock-chips">${pair}${rings}</div></div>`;
}

/** The selected transport's passengers: who is inside (spaces used / capacity), embark, disembark. */
function hullPanel(s1) {
  const esc = ctx.esc;
  const seen = new Set();
  const rows = s1.u.members.filter(m => m.fp.shape === 'rect' && (m.fp.approx || m.fp.measured) && !seen.has(m.label) && seen.add(m.label));
  if (!rows.length) return '';
  return `<div class="card" id="board-hull" style="margin-top:6px;padding:8px">${rows.map(m => `<div class="row" style="gap:6px;align-items:center;flex-wrap:wrap">
      <span class="grow small"><b>${esc(m.label)}</b> hull: ${m.fp.measured ? 'your measurement' : '<span class="bad">rough size</span> (no hull dimensions in the data)'}</span>
      <input class="sel" style="width:72px" type="number" min="1" max="30" step="0.1" inputmode="decimal" data-input="board-hull" data-label="${esc(m.label)}" data-dim="l" value="${(m.fp.hw * 2).toFixed(1)}" aria-label="Hull length in inches">
      <span class="tiny">×</span>
      <input class="sel" style="width:72px" type="number" min="1" max="30" step="0.1" inputmode="decimal" data-input="board-hull" data-label="${esc(m.label)}" data-dim="w" value="${(m.fp.hh * 2).toFixed(1)}" aria-label="Hull width in inches">
      <span class="tiny">"</span></div>`).join('')}
    <div class="tiny muted" style="margin-top:4px">Measure your model's hull (length × width, in inches) and enter it: ranges, gaps and sight lines are then measured from it, for every list with this datasheet.</div>
  </div>`;
}
function scoutPanel(s1) {
  if (curIndex() !== 0) return '';
  const X = scoutDist(s1.side, s1.key), pos = stepTokens()[s1.tk];
  if (!X && !pos?.scout) return '';
  const s = scoutMoves().find(m => m.tk === s1.tk);
  return `<div class="card" id="board-scout" style="margin-top:6px;padding:8px">
    <div class="row" style="gap:6px;align-items:center"><span class="grow small"><b>🏃 Scouts ${X}"</b>${s ? ` · moves <b>${s.moved.toFixed(1)}"</b> ${s.msgs.length ? '<span class="bad">✗</span>' : '✓'}` : ''}</span>
      ${ctx.chip('board-scout', !!pos?.scout, pos?.scout ? 'Planned' : 'Plan a Scout move', 'id="board-scout-chip"')}</div>
    ${s?.msgs.length ? `<ul class="keep warn tiny" style="margin:4px 0 0">${s.msgs.map(m => `<li>${ctx.esc(m)}</li>`).join('')}</ul>` : ''}
    <div class="tiny muted" style="margin-top:4px">${pos?.scout ? 'Drag the dashed ghost to where the move ends; the unit stays where it deployed. Turn 1 starts from the ghost.' : 'Before the first turn, from wholly within your deployment zone: up to ' + X + '", ending more than 8" from enemy units.'} Players alternate Scout moves, starting with whoever takes the first turn. Straight-line check: terrain is not.</div>
  </div>`;
}
function transportPanel(s1) {
  const tr = transportOf(s1.u.cu);
  if (!tr) return '';
  const esc = ctx.esc, toks = stepTokens(), inside = passengersOf(s1.tk, toks);
  const used = inside.reduce((n, p) => n + p.spaces, 0);
  const emb = embarkedIn(toks);
  const cands = ctx.state.armies[s1.side].units.map(cu => ({ cu, tk: `${s1.side}:${cu.key}` }))
    .filter(c => c.tk !== s1.tk && !emb.has(c.tk))
    .map(c => ({ ...c, chk: passengerCheck(tr, c.cu) }));
  const ok = cands.filter(c => c.chk.ok);
  const opt = (c) => { const fits = used + c.chk.spaces <= tr.capacity; return `<option value="${esc(c.tk)}" ${fits ? '' : 'disabled'}>${esc(c.cu.name)} — ${c.chk.spaces} space${c.chk.spaces === 1 ? '' : 's'}${fits ? '' : ' (no room)'}${toks[c.tk] ? '' : ' · not placed yet'}</option>`; };
  return `<div class="card" id="board-transport" style="margin-top:8px"><div class="row" style="align-items:center"><span class="grow"><b>🚚 Transport</b> · ${used} of ${tr.capacity} spaces used</span></div>
    <div class="tiny muted">${tr.phrase ? `Carries ${esc(tr.phrase)} models` : 'Carries Infantry of this army (the rules data names no other)'}${tr.exclude.length ? `; not ${esc(tr.exclude.join(' / '))}` : ''}${tr.multipliers.length ? `; ${esc(tr.multipliers.map(m => `${m.keyword} take ${m.spaces}`).join(', '))}` : ''}.</div>
    ${inside.map(p => `<div class="row" style="gap:6px;align-items:center;margin-top:6px" data-passenger="${esc(p.tk)}"><span class="grow">${esc(p.name)} <span class="tiny muted">${p.spaces} spaces</span></span>
      <button class="btn" data-action="board-disembark" data-tk="${esc(p.tk)}">Disembark</button></div>`).join('')}
    ${ok.length ? `<select class="sel" style="margin-top:6px" data-input="board-embark" aria-label="Embark a unit"><option value="">＋ Embark a unit…</option>${ok.map(opt).join('')}</select>` : '<div class="tiny muted" style="margin-top:6px">No other unit of this army can embark.</div>'}
    <div class="tiny muted" style="margin-top:4px">Embarked units are off the battlefield: they move with the transport, control no objective and cannot be targeted. They stay inside in later turns until they disembark (set up wholly within 3" of the transport).</div></div>`;
}

function ringsHtml(s1) {
  const b = boardState(), u = s1.u;
  const ringChip = (k, lab) => ctx.chip('board-ring', !!b.rings[k], lab, `data-k="${k}"`);
  const det = detectionOf(s1);
  return [
    det.range ? ringChip('detect', det.lone && det.lone <= det.range ? `Seen only within ${det.range}" (Lone Operative)` : `Seen only within ${det.range}" while Hidden`) : '',
    ringChip('see', '👁 What it can see'),
    ringChip('move', `Move ${u.move}"${u.moveBonus ? ` (+${u.moveBonus}" ${u.moveBonusFrom ?? 'detachment'})` : ''}`),
    ringChip('advance', `Move + Advance (max ${u.move + 6}")`),
    u.melee ? ringChip('charge', `Charge threat (${u.move}" + 7" avg)`) : '',
    ringChip('engage', 'Engagement 2"'),
    ...u.ranges.map(r => ringChip(`r${r}`, `Range ${r}"`)),
  ].join('');
}
const statsLine = (s1) => `${s1.u.left < s1.u.total ? `<b>${s1.u.left}</b> of ${s1.u.total} models left` : `${s1.u.cu.models} models`} · M${s1.u.move}"${s1.u.ranges.length ? ` · ranges ${s1.u.ranges.map(r => `${r}"`).join(', ')}` : ''}${s1.models.some(m => m.fp.approx) ? ' · footprint approximate' : ''}`;
/** Facing, nudge arrows, formation and the gap between bases. */
function posHtml(s1) {
  return `<div class="row" style="gap:6px;margin-top:8px;align-items:center">
      <span class="lab tiny muted grow">Facing ${Math.round(((s1.rot % 360) + 360) % 360)}°</span>
      <button class="icon-btn" data-action="board-rotate" data-deg="-45" aria-label="Rotate 45° left">↺</button>
      <button class="icon-btn" data-action="board-rotate" data-deg="-15" aria-label="Rotate 15° left">⟲</button>
      <button class="icon-btn" data-action="board-rotate" data-deg="15" aria-label="Rotate 15° right">⟳</button>
      <button class="icon-btn" data-action="board-rotate" data-deg="45" aria-label="Rotate 45° right">↻</button>
    </div>
    <div class="row" style="gap:6px;margin-top:6px;align-items:center">
      <span class="lab tiny muted grow" id="board-pos">${s1.x.toFixed(1)}" from left · ${s1.y.toFixed(1)}" from top</span>
      <button class="icon-btn" data-action="board-nudge" data-dx="-0.5" data-dy="0" aria-label="Nudge left">←</button>
      <button class="icon-btn" data-action="board-nudge" data-dx="0" data-dy="-0.5" aria-label="Nudge up">↑</button>
      <button class="icon-btn" data-action="board-nudge" data-dx="0" data-dy="0.5" aria-label="Nudge down">↓</button>
      <button class="icon-btn" data-action="board-nudge" data-dx="0.5" data-dy="0" aria-label="Nudge right">→</button>
    </div>
    ${s1.models.length > 2 ? (() => {
      const n = s1.models.length;
      const opts = [2, 3, 5, 10].filter(k => k < n).map(k => [k, String(k)]);
      opts.push([n, 'Line']);
      return `<div class="modrow" style="margin-top:6px"><div class="lab tiny muted">Formation (models per row)</div>${ctx.seg('board-formation', Math.min(s1.per, n), opts, 'compact')}</div>`;
    })() : ''}`;
}
/** Models left for the game on the tracker: shared with the Attack tab (attacker and target). */
/** Live table: is this unit battle-shocked? (OC "-" until its player's next Command phase) */
function shockHtml(s1) {
  const lv = livePlan();
  if (!lv) return '';
  const on = !!lv.shock?.[s1.tk];
  return `<div class="row" style="gap:6px;margin-top:6px;align-items:center" id="board-shock-row">${ctx.chip('board-shock', on, '⚡ Battle-shocked', `id="board-shock" data-tk="${ctx.esc(s1.tk)}"`)}${on ? '<span class="tiny muted">OC “–” until its next Command phase</span>' : ''}</div>`;
}
function lossHtml(s1) {
  const round = curIndex();
  const steppers = ctx.lossSteppers?.(s1.side, s1.u.cu, { round }) ?? '';
  if (!steppers) return '';
  const lost = s1.u.left < s1.u.total;
  return `<details class="more board-losses" id="board-losses" ${lost || boardState().lossOpen ? 'open' : ''} style="margin-top:6px"><summary>Models left${lost ? ` · ${s1.u.left}/${s1.u.total}` : ''}</summary>${steppers}
    <div class="tiny muted">${round ? `Lost in Turn ${round} (battle round ${round})` : 'Set at deployment'}: gone from this turn on, not in earlier turns. The same models are gone on the Attack tab for that round, whether this unit attacks or is the target. A unit with none left is taken off the board.</div></details>`;
}
const spacingHtml = (s1) => (s1.models.length > 1 ? `<div class="modrow" style="margin-top:6px" id="board-spacing"><div class="lab tiny muted">Gap between bases</div>${ctx.seg('board-spacing', s1.gap ?? 'auto', [['auto', 'Auto'], [0, 'Touching'], [0.25, '¼"'], [0.5, '½"'], [1, '1"'], [2, '2"']], 'compact')}</div>` : '');
function coherencyHtml(s1) {
  // 03.03: within 2" of one other model and within 9" of every other model of the unit
  const c = coherency(s1.models);
  return c.ok ? '' : `<div class="tiny" id="board-coherency" style="color:var(--warn-ink);margin-top:4px">⚠ Not in coherency: ${c.widest > COHERENCY.all ? `two models are ${c.widest.toFixed(1)}" apart (every model must be within ${COHERENCY.all}" of every other)` : `${c.alone} model${c.alone > 1 ? 's are' : ' is'} more than ${COHERENCY.near}" from any other`} (03.03). Use fewer models per row.</div>`;
}
const seeNote = () => (boardState().rings.see ? '<div class="tiny muted" id="board-see-note" style="margin-top:4px">👁 Shaded: where a model on a 32 mm base would be visible to this unit (any part of it, 13.x sight lines through light and dense terrain). Geometric only — no rule that changes visibility, and not a table ruling.</div>' : '');
/** The matchup card: gap, line of sight, cover, and Shoot → / Fight → into the calculator. */
function pairHtml(s1, s2) {
  const esc = ctx.esc, u = s1.u;
  const gap = unitGap(s1, s2);
  const enemy = s1.side !== s2.side;
  const sight = enemy ? pairSight(s1, s2) : null;
  return `<div class="card" id="board-pair" style="margin-top:8px"><div class="title">${esc(s1.u.cu.name)} → ${esc(s2.u.cu.name)}</div>
      <div class="small" id="board-gap">Gap: <b>${gap.toFixed(1)}"</b> (closest bases)${gap <= ENGAGEMENT_RANGE ? ' · engaged' : ''}</div>
      ${sight ? sightHtml(sight, s1, s2) : ''}
      ${enemy ? `<div class="row" style="gap:6px;margin-top:8px">
        ${u.ranges.length ? `<button class="btn primary grow" data-action="board-attack" data-phase="shooting">🎯 Shoot →</button>` : ''}
        ${u.melee ? `<button class="btn primary grow" data-action="board-attack" data-phase="fight">⚔ Fight →</button>` : ''}
      </div>${u.melee ? `<button class="btn ghost block" style="margin-top:6px" data-action="board-attack" data-phase="chain">⚡ ${u.ranges.length ? 'Shoot, charge and fight' : 'Charge and fight'} this turn →</button>` : ''}<div class="tiny muted" style="margin-top:4px">Opens the calculator with this gap as the distance${u.halfRangeWeapons.length ? ' (half range set from it)' : ''}${sight ? ', cover and the models that can see' : ''}.</div>` : ''}
    </div>`;
}

function selectionPanel() {
  const b = boardState();
  if (b.mode === 'meas') return measPanel();
  const esc = ctx.esc;
  const toks = placed();
  const s1 = toks.find(t => t.tk === b.sel);
  if (!s1) return `<p class="hint">Tap a unit on the board to see its ranges; tap a second unit to measure the gap between them and calculate the attack.</p>`;
  const s2 = toks.find(t => t.tk === b.sel2);
  return `<div class="card">
    <div class="row"><div class="grow"><div class="title" style="color:var(--side-${s1.side.toLowerCase()}-ink)">${esc(s1.u.cu.name)}</div>
      <div class="muted tiny">${statsLine(s1)}</div></div>
      <button class="icon-btn" data-action="board-remove" aria-label="Remove from board">✕</button></div>
    <div class="row" style="gap:6px;margin-top:8px;flex-wrap:wrap">${modelsBtn(s1)}${stepTokens()[s1.tk]?.mo ? '<button class="chip" data-action="board-models-reset">↺ Formation</button>' : ''}</div>
    ${posHtml(s1)}
    ${shockHtml(s1)}
    ${lossHtml(s1)}
    ${transportPanel(s1)}
    ${scoutPanel(s1)}
    ${hullPanel(s1)}
    ${spacingHtml(s1)}
    ${coherencyHtml(s1)}
    <div class="lab tiny muted" style="margin-top:8px">Show around this unit</div><div class="chips">${ringsHtml(s1)}</div>
    ${seeNote()}
    ${s2 ? pairHtml(s1, s2) : ''}
    ${threatHtml(s1, toks)}
  </div>`;
}

// line of sight from s1 to s2 (shooting): any of s1's models within its longest range
function pairSight(s1, s2) {
  const l = currentLayout();
  if (!l || !s1.u.ranges.length) return null;
  const range = Math.max(...s1.u.ranges);
  const unitOf = (t) => ({ x: t.x, y: t.y, models: t.models, keywords: t.u.cu.keywords ?? [] });
  const v = sightVerdict(unitOf(s1), unitOf(s2), l.pieces, { range });
  // models that can see AND are in range, not counting attached leaders (the calculator's "models in range")
  const body = s1.models.filter(m => !m.leader).length;
  const seeingBody = v.seeingMask.filter((on, i) => on && !s1.models[i].leader).length;
  return { ...v, range, body, seeingBody };
}

function sightHtml(v, s1, s2) {
  const lab = { clear: '✅ Clear', partial: '◐ Partly visible', blocked: '⛔ Blocked' }[v.verdict];
  return `<div class="small" id="board-sight" data-verdict="${v.verdict}" data-borderline="${v.borderline ? 1 : 0}" style="margin-top:4px">
      Line of sight: <b>${lab}</b> · ${v.targetSeen}/${v.targetTotal} target models visible · ${v.attackersSeeing}/${v.attackerTotal} of yours see them within ${v.range}"
      <br>Benefit of cover: <b>${v.cover ? `yes (${v.coverWhy})` : 'no'}</b>${v.hidden ? ` · <b id="board-hidden">Hidden</b>: ${v.nearest.toFixed(1)}" away, and infantry in an area with a light or dense feature is only visible within ${v.detect}"${v.goneToGround ? ` (${HIDDEN_RANGE}" less ${GONE_TO_GROUND}": gone to ground)` : ''} while it has not shot this turn or the turn before (13.09)` : v.hiddenCapable ? ` · can be Hidden from more than ${v.detect}"` : ''}
      ${v.borderline ? '<br><span style="color:var(--warn-ink)">⚠ Borderline — moving either unit ½" changes this. Check on the table.</span>' : ''}
      <br><span class="tiny muted">11e terrain rules on the map's footprints; model heights, windows and floors are not modelled.</span></div>`;
}

// What the 11th edition does not allow at the plan step on screen: a unit outside its deployment zone,
// Infiltrators / Scouts too close, reserves in round 1, away from an edge or in the enemy zone without
// Deep Strike, within 8" of the enemy (planeval.planWarnings - the Mission tab lists the whole plan).
function stepWarningsHtml() {
  const root = planRoot(), p = plan(), l = currentLayout();
  if (!root || !p || !l) return '';
  if (p.live) return '';   // the live table is what happened on the table, not a plan to check
  const dep = DEPLOYMENTS[l.deployment];
  const pick = (list, X) => list?.find(z => z.player === zoneOf(X))?.poly ?? null;
  const geo = { zones: { A: pick(dep?.zones, 'A'), B: pick(dep?.zones, 'B') }, territories: { A: pick(dep?.territories, 'A'), B: pick(dep?.territories, 'B') }, pieces: l.pieces, objectives: l.objectives,
    early: { A: earlyArrival(ctx.state.armies.A)?.name ?? null, B: earlyArrival(ctx.state.armies.B)?.name ?? null } };
  const steps = boardPlans()[Math.min(root.v, root.variants.length - 1)]?.steps ?? [];
  const name = curSteps()[curIndex()]?.name;
  const ws = planWarnings(steps, geo).filter(w => w.step === name);
  for (const s of scoutMoves()) for (const m of s.msgs) ws.push({ side: s.side, unit: s.name, msg: `Scout move: ${m}` });
  if (!ws.length) return '';
  return `<div class="card" id="board-warnings" style="margin-top:8px"><div class="lab tiny muted">Check this step (11th edition rules)</div>
    <ul class="keep warn">${ws.slice(0, 6).map(w => `<li${w.info ? ' class="info"' : ''} data-unit="${ctx.esc(w.unit)}"><b style="color:var(--side-${w.side.toLowerCase()}-ink)">${ctx.esc(shortName(w.unit))}</b> ${ctx.esc(w.msg)}</li>`).join('')}</ul>
    ${ws.length > 6 ? `<div class="tiny muted">and ${ws.length - 6} more</div>` : ''}</div>`;
}

// enemy units that threaten s1 next turn (normal move + shooting range / charge roll)
function threatHtml(s1, toks) {
  // who can SEE it: a Lone Operative only from 12" (24.24); infantry that can be Hidden here only from
  // 15" while it has not shot (13.09). The enemy must move that close to shoot, whatever its range.
  const l = currentLayout();
  const lone = s1.u.flags?.loneOperative || 0;
  const hide = !!l && canHide({ x: s1.x, y: s1.y, models: s1.models, keywords: s1.u.cu.keywords ?? [] }, l.pieces);
  const base = { detect: lone || Infinity };
  const rows = toks.filter(t => t.side !== s1.side).map(t => {
    const o = { move: t.u.move, ranges: t.u.ranges, melee: t.u.melee };
    const th = threatTo(t, s1, { ...o, ...base });
    // ... and when it stays hidden
    const thHid = hide ? threatTo(t, s1, { ...o, detect: Math.min(base.detect, HIDDEN_RANGE) }) : th;
    return { t, th, onlyIfShot: !!th.shoot && !thHid.shoot };
  }).filter(x => x.th.shoot || (x.th.charge ?? 0) >= 0.03)
    .sort((a, b) => (b.th.charge ?? 0) - (a.th.charge ?? 0) || a.th.gap - b.th.gap);
  if (!toks.some(t => t.side !== s1.side)) return '';
  const pct = (p) => `${Math.round(p * 100)}%`;
  const notes = [
    lone ? `<b>Lone Operative</b>: only visible within ${lone}", so only units that can move to within ${lone}" can shoot it (24.24).` : '',
    hide ? `<b id="board-can-hide">Can be Hidden here</b> (infantry in an area with a light or dense feature): while it has not shot this turn or the turn before, only models within ${HIDDEN_RANGE}" can see it (13.09).` : '',
  ].filter(Boolean).join(' ');
  return `<div class="lab tiny muted" style="margin-top:8px">Threatened next turn by</div>
    <div id="board-threats" class="small" data-hide="${hide ? 1 : 0}" data-lone="${lone}">${rows.length ? rows.map(({ t, th, onlyIfShot }) => `<div class="row" style="gap:6px"><span class="grow" style="color:var(--side-${t.side.toLowerCase()}-ink)">${ctx.esc(shortName(t.u.cu.name))}</span>
      ${th.shoot ? `<span>🎯 ${th.shoot.range}"${th.shoot.margin < 1 ? ' <span style="color:var(--warn-ink)">(just)</span>' : ''}${onlyIfShot ? ' <span class="muted">(not while Hidden)</span>' : ''}</span>` : ''}
      ${th.charge != null && th.charge >= 0.03 ? `<span>⚔ charge ${pct(th.charge)}</span>` : ''}</div>`).join('')
      : '<span class="muted">Nothing can reach it next turn (move + range / charge).</span>'}
      ${notes ? `<div class="tiny" style="margin-top:2px">${notes}</div>` : ''}
      <div class="tiny muted">After a normal move, ignoring terrain and line of sight.</div></div>`;
}

// ---------------------------------------------------------------------------
// Partial re-render (keeps scroll position and the pointer gesture alive)

export function refreshBoard() {
  const host = document.getElementById('board-host');
  if (host) host.innerHTML = boardSvg();
  refreshUndo();
  const mb = document.getElementById('board-models-host');
  if (mb) mb.innerHTML = modelsBar();
  const lb = document.getElementById('board-live-host');
  if (lb) lb.innerHTML = liveBarHtml() + planBarHtml() + hintBarHtml();
  const nx = document.getElementById('board-next-host');
  if (nx) nx.innerHTML = nextTurnHtml();
  const tri = document.getElementById('board-tri');
  if (tri) {
    // three columns: each army's column holds its units, the selected unit and the matchup card
    for (const X of ['A', 'B']) { const el = document.getElementById(`board-army-${X}-in`); if (el) el.innerHTML = armyColInner(X); }
    const mh = document.getElementById('board-meas-host');
    if (mh) { const b = boardState(); mh.innerHTML = b.mode === 'meas' ? `<div style="margin-bottom:8px">${measPanel()}</div>` : ''; }
    revealSelected();
  } else {
    const panel = document.getElementById('board-panel');
    if (panel) panel.innerHTML = selectionPanel();
  }
  const warn = document.getElementById('board-warnings-host');
  if (warn) warn.innerHTML = stepWarningsHtml();
  const dock = document.getElementById('board-dock');
  if (dock) dock.innerHTML = dockHtml();
  const bar = document.getElementById('board-photo-bar');
  if (bar) bar.innerHTML = photoBar();
  const dbar = document.getElementById('board-danger-bar');
  if (dbar) dbar.innerHTML = dangerBar();
  const abar = document.getElementById('board-arrive-bar');
  if (abar) abar.innerHTML = arriveBar();
  const tree = document.getElementById('board-tree-host');
  if (tree) tree.innerHTML = treeHtml();
  const tmap = document.getElementById('board-treemap-host');
  if (tmap) tmap.innerHTML = treeMapHtml();
  wireBoard();
}

// ---------------------------------------------------------------------------
// Pointer handling: drag tokens, pan, pinch-zoom, ruler, tap-to-select

function toBoard(svg, clientX, clientY) {
  const pt = svg.createSVGPoint();
  pt.x = clientX; pt.y = clientY;
  const m = svg.getScreenCTM();
  if (!m) return { x: 0, y: 0 };
  const p = pt.matrixTransform(m.inverse());
  return { x: p.x, y: p.y };
}

function fullView() { return { x: -0.5, y: -0.5, w: BOARD.w + 1, h: BOARD.h + 1 }; }

function setView(v) {
  const b = boardState();
  const full = fullView();
  // zoom out to 1.6x the board (room around it on any screen); once the whole
  // board is in view, keep it centred instead of drifting with the old pan
  const w = Math.max(6, Math.min(full.w * 1.6, v.w));
  const h = w * (full.h / full.w);
  let x, y;
  if (w >= full.w) {
    x = full.x + (full.w - w) / 2;
    y = full.y + (full.h - h) / 2;
  } else {
    x = Math.max(full.x - w * 0.25, Math.min(full.x + full.w - w * 0.75, v.x));
    y = Math.max(full.y - h * 0.25, Math.min(full.y + full.h - h * 0.75, v.y));
  }
  b.view = { x, y, w, h };
  const svg = document.getElementById('board-svg');
  if (svg) svg.setAttribute('viewBox', `${f2(x)} ${f2(y)} ${f2(w)} ${f2(h)}`);
}

export function zoomBoard(factor) {
  const b = boardState();
  if (!factor) { b.view = null; refreshBoard(); return; }
  const v = b.view ?? fullView();
  // zoom around the selected unit when there is one (otherwise the view's centre)
  const selPos = b.sel && stepTokens()[b.sel];
  const cx = selPos && factor < 1 ? selPos.x : v.x + v.w / 2, cy = selPos && factor < 1 ? selPos.y : v.y + v.h / 2;
  const w = v.w * factor;
  setView({ x: cx - w / 2, y: cy - (w * (fullView().h / fullView().w)) / 2, w });
}

let gesture = null;
function wireBoard() {
  const svg = document.getElementById('board-svg');
  if (!svg || svg.dataset.wired) return;
  svg.dataset.wired = '1';
  const pointers = new Map();
  svg.addEventListener('pointerdown', (ev) => {
    svg.setPointerCapture(ev.pointerId);
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    const b = boardState();
    const p = toBoard(svg, ev.clientX, ev.clientY);
    if (pointers.size === 2) {
      const [a, c] = [...pointers.values()];
      gesture = { kind: 'pinch', d0: Math.hypot(a.x - c.x, a.y - c.y), view0: { ...(b.view ?? fullView()) }, mid: toBoard(svg, (a.x + c.x) / 2, (a.y + c.y) / 2) };
      return;
    }
    const tokEl = ev.target.closest?.('[data-tok]'), scEl = ev.target.closest?.('[data-scout]');
    if (b.mode === 'meas') {
      const mEl = ev.target.closest?.('[data-meas]');
      const m = (b.meas ??= {});
      let k = mEl?.dataset.meas;
      if (!k) {
        if (!m.a || (m.a && m.b)) { m.a = { x: p.x, y: p.y, mm: m.a?.mm ?? 32 }; if (m.b) m.b = null; k = 'a'; }
        else { m.b = { x: p.x, y: p.y, mm: m.a.mm }; k = 'b'; }
      }
      gesture = { kind: 'meas', k, dx: p.x - m[k].x, dy: p.y - m[k].y };
      const layer = svg.querySelector('#meas-layer');
      if (layer) layer.innerHTML = measSvg(m);
      return;
    }
    if (b.mode !== 'ruler' && scEl) {
      const tk = scEl.dataset.scout, sc = stepTokens()[tk]?.scout;
      if (sc) { gesture = { kind: 'drag', tk, el: scEl, obj: sc, from: { ...sc }, dx: p.x - sc.x, dy: p.y - sc.y, start: p, moved: false, t0: Date.now() }; return; }
    }
    if (b.mode === 'ruler') {
      gesture = { kind: 'ruler', start: p, t0: Date.now() };
      b.ruler = { x1: p.x, y1: p.y, x2: p.x, y2: p.y };
    } else if (tokEl?.dataset.models && ev.target.closest?.('[data-model]')) {
      // models mode: this base only
      const tk = tokEl.dataset.tok, i = Number(ev.target.closest('[data-model]').dataset.model);
      const pos = stepTokens()[tk], t = placed().find(x => x.tk === tk), m = t?.models[i];
      if (!pos || !m) return;
      // every other base on the board (its own unit's and the other units'): the dragged base may not overlap them
      const others = [];
      for (const u of placed()) u.models.forEach((o, j) => { if (!(u.tk === tk && j === i)) others.push({ x: u.x + o.dx, y: u.y + o.dy, fp: o.fp, rot: o.rot ?? 0 }); });
      gesture = { kind: 'model', tk, i, el: ev.target.closest('[data-model]'), pos, t, m, others, last: [pos.x + m.dx, pos.y + m.dy], from: turnStart(t), dx: p.x - (pos.x + m.dx), dy: p.y - (pos.y + m.dy), start: p, moved: false };
    } else if (tokEl) {
      const tk = tokEl.dataset.tok;
      const pos = stepTokens()[tk];
      gesture = { kind: 'drag', tk, el: tokEl, dx: p.x - pos.x, dy: p.y - pos.y, start: p, moved: false, t0: Date.now() };
    } else {
      gesture = { kind: 'pan', start: { x: ev.clientX, y: ev.clientY }, view0: { ...(b.view ?? fullView()) }, moved: false, rect: svg.getBoundingClientRect() };
    }
  });
  svg.addEventListener('pointermove', (ev) => {
    if (!pointers.has(ev.pointerId) || !gesture) return;
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    const b = boardState();
    if (gesture.kind === 'pinch' && pointers.size === 2) {
      const [a, c] = [...pointers.values()];
      const d = Math.hypot(a.x - c.x, a.y - c.y) || 1;
      const k = gesture.d0 / d;
      const v0 = gesture.view0;
      const w = v0.w * k;
      const h = w * (fullView().h / fullView().w);
      setView({ x: gesture.mid.x - (gesture.mid.x - v0.x) * (w / v0.w), y: gesture.mid.y - (gesture.mid.y - v0.y) * (h / v0.h), w });
      return;
    }
    const p = toBoard(svg, ev.clientX, ev.clientY);
    if (gesture.kind === 'drag') {
      if (Math.hypot(p.x - gesture.start.x, p.y - gesture.start.y) > 0.2) gesture.moved = true;
      const x = Math.max(0, Math.min(BOARD.w, p.x - gesture.dx)), y = Math.max(0, Math.min(BOARD.h, p.y - gesture.dy));
      Object.assign(gesture.obj ?? stepTokens()[gesture.tk], { x, y }); // keep facing and formation
      gesture.el.setAttribute('transform', `translate(${f2(x)},${f2(y)})`);
    } else if (gesture.kind === 'model') {
      const g = gesture, pos = g.pos;
      if (Math.hypot(p.x - g.start.x, p.y - g.start.y) > 0.15) g.moved = true;
      if (!g.moved) return;
      const free = clearOfBases(g, Math.max(0, Math.min(BOARD.w, p.x - g.dx)), Math.max(0, Math.min(BOARD.h, p.y - g.dy)));
      const [ax, ay] = free ?? g.last;     // wedged in: it stays at its last free spot
      g.last = [ax, ay];
      (pos.mo ??= {})[g.i] = [Math.round((ax - pos.x) * 100) / 100, Math.round((ay - pos.y) * 100) / 100];
      g.el.setAttribute('transform', `translate(${f2(pos.mo[g.i][0])},${f2(pos.mo[g.i][1])})`);
      const layer = svg.querySelector('#model-drag-layer');
      if (layer) layer.innerHTML = modelDragLabel(g);
    } else if (gesture.kind === 'pan') {
      const v0 = gesture.view0;
      const scale = v0.w / gesture.rect.width;
      const dx = (ev.clientX - gesture.start.x) * scale, dy = (ev.clientY - gesture.start.y) * scale;
      if (Math.abs(dx) + Math.abs(dy) > 0.3) gesture.moved = true;
      if (b.view) setView({ x: v0.x - dx, y: v0.y - dy, w: v0.w });
    } else if (gesture.kind === 'meas') {
      const m = b.meas;
      Object.assign(m[gesture.k], { x: Math.max(0, Math.min(BOARD.w, p.x - gesture.dx)), y: Math.max(0, Math.min(BOARD.h, p.y - gesture.dy)) });
      const layer = svg.querySelector('#meas-layer');
      if (layer) layer.innerHTML = measSvg(m);
    } else if (gesture.kind === 'ruler') {
      b.ruler = { x1: gesture.start.x, y1: gesture.start.y, x2: p.x, y2: p.y };
      // redraw only the ruler layer: replacing the SVG would drop the pointer capture
      const layer = svg.querySelector('#ruler-layer');
      if (layer) layer.innerHTML = rulerSvg(b.ruler);
    }
  });
  const end = (ev) => {
    pointers.delete(ev.pointerId);
    if (!gesture) return;
    const b = boardState();
    const g = gesture;
    if (g.kind === 'pinch') { if (pointers.size === 0) gesture = null; return; }
    gesture = null;
    if (g.kind === 'meas') {
      const i = measInfo(b.meas);
      if (i) console.log(`[board] base to base: ${i.edge.toFixed(2)}" (centre ${i.centre.toFixed(2)}")${i.err != null ? ` ±${i.err.toFixed(2)} on the photo, ${Math.round(i.ppi)} px/inch` : ''}`);
      // three columns: the measuring panel is above the map; on a phone it is the selection panel
      const mh = document.getElementById('board-meas-host');
      if (mh) mh.innerHTML = `<div style="margin-bottom:8px">${measPanel()}</div>`;
      else { const panel = document.getElementById('board-panel'); if (panel) panel.innerHTML = selectionPanel(); }
      const dock = document.getElementById('board-dock'); if (dock) dock.innerHTML = dockHtml();
      return;
    }
    if (g.kind === 'model') {
      if (!g.moved) {
        // a double-tap on a base: leave models mode
        if (doubleTap(g.tk)) { b.modelsOf = null; console.log(`[board] models mode off: ${g.tk}`); refreshBoard(); }
        return;
      }
      const t = placed().find(x => x.tk === g.tk), c = t ? coherency(t.models) : { ok: true };
      console.log(`[board] model ${g.i} of ${g.tk} -> ${g.pos.mo[g.i].join(', ')}${c.ok ? '' : ' (not in coherency)'}`);
      persistBoard();
      refreshBoard();
      return;
    }
    if (g.kind === 'drag') {
      // a double-tap on a unit: move its models one by one (again: back to moving it as a block)
      if (!g.moved && !g.obj && doubleTap(g.tk)) {
        b.sel = g.tk; b.sel2 = null;
        b.modelsOf = b.modelsOf === g.tk ? null : g.tk;
        console.log(`[board] models mode ${b.modelsOf ? 'on' : 'off'}: ${g.tk} (double-tap)`);
        refreshBoard();
        return;
      }
      if (!g.moved && !g.obj) { selectToken(g.tk); if (b.modelsOf && b.modelsOf !== b.sel) b.modelsOf = null; }
      if (g.obj && g.moved) { scoutToTurn1(g.tk, g.from, g.obj); console.log(`[board] scout move ${g.tk} -> ${g.obj.x.toFixed(1)},${g.obj.y.toFixed(1)}`); }
      if (g.obj && !g.moved) { b.sel = g.tk; b.sel2 = null; }
      persistBoard();
      refreshBoard();
    } else if (g.kind === 'pan' && !g.moved) {
      b.sel = null; b.sel2 = null; b.modelsOf = null;
      if (b.danger && b.dangerKinds?.heat) { const p = toBoard(svg, ev.clientX, ev.clientY); b.heatAt = { x: Math.max(0, Math.min(BOARD.w, p.x)), y: Math.max(0, Math.min(BOARD.h, p.y)) }; }
      refreshBoard();
    }
  };
  svg.addEventListener('pointerup', end);
  svg.addEventListener('pointercancel', end);
  svg.addEventListener('wheel', (ev) => { ev.preventDefault(); zoomBoard(ev.deltaY > 0 ? 1.15 : 0.87); }, { passive: false });
}

// Two taps on the same unit (or base) within 400 ms
let lastTap = null;
function doubleTap(tk) {
  const now = Date.now();
  const dbl = !!lastTap && lastTap.tk === tk && now - lastTap.t < 400;
  lastTap = dbl ? null : { tk, t: now };
  return dbl;
}
/**
 * Where the dragged base can go near (x, y) without overlapping another base: pushed out of each base it would
 * overlap, along the line between their centres (it slides along the edge), a few passes; null when it cannot get
 * clear (wedged between bases). Base edges from edgeRadius: round, oval and rectangular bases alike.
 */
function clearOfBases(g, x, y) {
  const fp = g.m.fp, rot = g.m.rot ?? 0, EPS = 0.01;
  for (let pass = 0; pass < 8; pass++) {
    let moved = false;
    for (const o of g.others) {
      let ux = x - o.x, uy = y - o.y, d = Math.hypot(ux, uy);
      if (d > 12) continue;
      if (d < 1e-6) { ux = x - g.last[0]; uy = y - g.last[1]; d = Math.hypot(ux, uy); if (d < 1e-6) { ux = 1; uy = 0; d = 1; } ux /= d; uy /= d; d = 0; } else { ux /= d; uy /= d; }
      const need = edgeRadius(fp, -ux, -uy, rot) + edgeRadius(o.fp, ux, uy, o.rot) + EPS;
      if (d < need) { x = o.x + ux * need; y = o.y + uy * need; moved = true; }
    }
    if (!moved) break;
  }
  x = Math.max(0, Math.min(BOARD.w, x)); y = Math.max(0, Math.min(BOARD.h, y));
  for (const o of g.others) {
    const d = Math.hypot(x - o.x, y - o.y);
    if (d < 1e-6) return null;
    const ux = (x - o.x) / d, uy = (y - o.y) / d;
    if (d < edgeRadius(fp, -ux, -uy, rot) + edgeRadius(o.fp, ux, uy, o.rot) - 0.005) return null;
  }
  return [x, y];
}
/** While a model is dragged: how far it has moved this turn against the unit's Move, and coherency (03.03). */
function modelDragLabel(g) {
  const t = g.t, pos = g.pos, models = tokenModels(t.u, pos), m = models[g.i];
  if (!m) return '';
  const x = pos.x + m.dx, y = pos.y + m.dy;
  const s0 = g.from?.models?.[g.i];
  const moved = s0 ? Math.hypot(x - (g.from.x + s0.dx), y - (g.from.y + s0.dy)) : null;
  const c = coherency(models);
  const over = moved != null && moved > t.u.move + 0.01;
  const txt = `${moved != null ? `${moved.toFixed(1)}" / ${t.u.move}"` : 'deploying'}${c.ok ? '' : ' ⚠ coherency'}`;
  const w = 0.6 * txt.length + 0.8, h = 1.5, ly = y - (m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0)) - 2;
  const col = over || !c.ok ? '#c0392b' : '#111';
  return `<g id="model-drag-label" data-moved="${moved != null ? moved.toFixed(2) : ''}" data-coherent="${c.ok ? 1 : 0}">`
    + (s0 ? `<line x1="${f2(g.from.x + s0.dx)}" y1="${f2(g.from.y + s0.dy)}" x2="${f2(x)}" y2="${f2(y)}" stroke="${col}" stroke-width="0.12" stroke-dasharray="0.4 0.3"/>` : '')
    + `<rect x="${f2(x - w / 2)}" y="${f2(ly - h / 2)}" width="${f2(w)}" height="${h}" rx="0.35" fill="#fff" stroke="${col}" stroke-width="0.1"/>`
    + `<text x="${f2(x)}" y="${f2(ly + 0.38)}" font-size="1" text-anchor="middle" font-weight="700" font-family="system-ui,sans-serif" fill="${col}">${ctx.esc(txt)}</text></g>`;
}
/** Above the map in models mode: what is going on, back to formation, done. */
function modelsBar() {
  const b = boardState();
  const t = b.modelsOf && placed().find(x => x.tk === b.modelsOf);
  if (!t) return '';
  const pos = stepTokens()[t.tk];
  return `<div class="warnbox models-bar" id="board-models-bar" style="display:flex;gap:8px;align-items:center;margin:0 0 8px"><span class="grow">☝ <b>${ctx.esc(t.u.cu.name)}</b>: drag a base to move that model. Double-tap or Done to move the unit as a block again.</span>
    ${pos?.mo ? '<button class="btn ghost" data-action="board-models-reset" id="board-models-reset">↺ Formation</button>' : ''}
    <button class="btn primary" data-action="board-models-done" id="board-models-done">Done</button></div>`;
}
const modelsBtn = (s1) => (s1.models.length > 1 ? `<button class="chip ${boardState().modelsOf === s1.tk ? 'on' : ''}" data-action="board-models" id="board-models-btn" aria-pressed="${boardState().modelsOf === s1.tk}">☝ Move models one by one</button>` : '');

// Tap rules: a unit of the same army becomes the selection; an enemy unit is
// paired with it (gap + attack); tapping the selected unit again clears it.
function selectToken(tk) {
  const b = boardState();
  if (b.sel === tk) { b.sel = null; b.sel2 = null; return; }
  if (b.sel2 === tk) { b.sel2 = null; return; }
  if (!b.sel || b.sel.split(':')[0] === tk.split(':')[0]) { b.sel = tk; b.sel2 = null; return; }
  b.sel2 = tk;
}

// ---------------------------------------------------------------------------
// Actions (called from app.js's click / change handlers)

export function boardAction(action, el) {
  const b = boardState();
  const st = ctx.state;
  switch (action) {
    case 'board-undo':
      return undoBoard() ? 'render' : null;
    case 'board-redo':
      return redoBoard() ? 'render' : null;
    case 'board-models': {
      const tk = b.sel;
      if (!tk) return null;
      b.modelsOf = b.modelsOf === tk ? null : tk;
      console.log(`[board] models mode ${b.modelsOf ? 'on' : 'off'}: ${tk}`);
      refreshBoard();
      return null;
    }
    case 'board-models-done':
      b.modelsOf = null;
      refreshBoard();
      return null;
    case 'board-models-reset': {
      const pos = stepTokens()[b.modelsOf ?? b.sel];
      if (!pos?.mo) return null;
      delete pos.mo;
      console.log(`[board] ${b.modelsOf ?? b.sel}: models back in formation`);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-pick':
      // three columns: a tap on a unit in an army's list = a tap on it on the map
      selectToken(el.dataset.tk);
      console.log(`[board] picked ${el.dataset.tk} from the list (sel ${b.sel ?? '-'}, target ${b.sel2 ?? '-'})`);
      refreshBoard();
      return null;
    case 'board-pos-toggle':
      b.posOpen = !b.posOpen;
      refreshBoard();
      return null;
    case 'board-open-setup': {
      // from the Mission tab's set-up checklist: the Board, on the Deploy step (where the set-up is)
      const p = plan();
      if (p) p.cur = 0;
      b.sel = b.sel2 = null;
      st.view = 'board';
      st.sheet = null;
      persistBoard();
      return 'render';
    }
    case 'board-setup-unlock':
      if (!window.confirm('A game is on the tracker. Change the mission set-up anyway? The primaries, the deployment map and the board plans follow the new set-up; the scores on the tracker stay.')) return null;
      b.unlock = true;
      console.log('[board] mission set-up unlocked during a game');
      return 'render';
    case 'board-disp-list':
      if (setupLocked()) return 'render';
      console.log(`[board] ${el.dataset.side}: disposition back to the list's (${listDisp(el.dataset.side)})`);
      delete b.settings[`disp${el.dataset.side}`];
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    case 'board-measure':
      b.measure = !b.measure;
      persistBoard();
      return 'render';
    case 'board-variant':
      if (setupLocked()) { console.log('[board] layout change ignored: set-up locked during a game'); return 'render'; }
      b.settings.variant = Number(el.dataset.value);
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    case 'board-swap-zones':
      if (setupLocked()) return 'render';
      b.settings.swapZones = !b.settings.swapZones;
      persistBoard();
      return 'render';
    case 'board-mode':
      b.mode = el.dataset.value;
      b.ruler = null;
      return 'render';
    case 'board-meas-clear':
      b.meas = null;
      refreshBoard();
      return null;
    case 'board-meas-mm': {
      const m = b.meas, k = el.dataset.which === 'b' ? 'b' : 'a';
      if (!m?.[k]) return null;
      m[k].mm = Number(el.dataset.value) || 0;
      refreshBoard();
      return null;
    }
    case 'board-ar': {
      import('./arview.mjs').then(async (A) => {
        if (!(await A.arSupported())) {
          console.log('[board] AR not supported here');
          globalThis.alert?.('This device or browser cannot run AR. It needs Chrome on an Android tablet or phone with ARCore ("Google Play Services for AR"). 📐 Bases on a table photo works everywhere.');
          return;
        }
        const d = arData();
        console.log(`[board] AR: layout ${d.layout}, ${d.steps.length} plan steps, ${d.steps[d.cur]?.units.length ?? 0} units in "${d.steps[d.cur]?.name ?? '?'}"`);
        await A.startAR(d);
      }).catch((e) => {
        console.warn('[board] AR failed', e);
        globalThis.alert?.(`AR could not start: ${e?.message ?? e}`);
      });
      return null;
    }
    case 'board-place': {
      const side = el.dataset.side, key = el.dataset.key;
      const tk = `${side}:${key}`;
      const di = drillInfo();
      if (di && di.s.next !== side) { console.log(`[board] drill: not ${side}'s turn to set up (next: ${di.s.next})`); return null; }
      const spot = freeSpot(side, key);
      stepTokens()[tk] = spot;
      b.sel = tk; b.sel2 = null;
      if (di) { di.d.log = [...di.log, { X: side, tk }]; console.log(`[board] drill: drop ${di.d.log.length} ${tk}${isTitanic(side, key) ? ' (TITANIC)' : ''}`); }
      persistBoard();
      return 'render';
    }
    case 'board-rotate': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
      pos.rot = (((pos.rot ?? 0) + Number(el.dataset.deg)) % 360 + 360) % 360;
      if (pos.mo) {
        // models moved one by one turn with the unit, around its centre
        const a = Number(el.dataset.deg) * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a);
        for (const k of Object.keys(pos.mo)) { const [x, y] = pos.mo[k]; pos.mo[k] = [Math.round((x * c - y * sn) * 100) / 100, Math.round((x * sn + y * c) * 100) / 100]; }
      }
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-disembark': {
      // set up wholly within 3" of the transport: just beside it (toward the board's centre), facing as before
      const toks = stepTokens(), tk = el.dataset.tk, pos = toks[tk], t = toks[pos?.in];
      if (!pos || !t) return null;
      const tu = unitInfo(...pos.in.split(':')), pu = unitInfo(...tk.split(':'));
      const ext = (ms) => ms.reduce((a, m) => Math.max(a, Math.abs(m.dy) + (m.fp.r ?? Math.max(m.fp.ry ?? 0, m.fp.hh ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))), 0);
      const dir = t.y < BOARD.h / 2 ? 1 : -1;
      const p0 = { ...pos }; delete p0.in;
      const d = (tu ? ext(tokenModels(tu, t)) : 2) + (pu ? ext(tokenModels(pu, { ...p0, x: 0, y: 0 })) : 1) + 1;
      toks[tk] = { ...p0, x: t.x, y: Math.min(BOARD.h - 1, Math.max(1, t.y + dir * d)) };
      b.sel = tk; b.sel2 = null;
      console.log(`[board] ${tk} disembarks from ${pos.in}`);
      persistBoard();
      return 'render';
    }
    case 'board-spacing': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
      if (pos.mo && !window.confirm('Put the models moved one by one back in formation?')) return null;
      delete pos.mo;
      if (el.dataset.value === 'auto') delete pos.gap; else pos.gap = Number(el.dataset.value);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-formation': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
      if (pos.mo && !window.confirm('Put the models moved one by one back in formation?')) return null;
      delete pos.mo;
      pos.per = Number(el.dataset.value);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-remove':
      if (b.sel) { const toks = stepTokens(); for (const [tk, x] of embarkedIn(toks)) if (x === b.sel) delete toks[tk]; delete toks[b.sel]; }
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    case 'board-ring':
      b.rings[el.dataset.k] = !b.rings[el.dataset.k];
      refreshBoard();
      return null;
    case 'board-reuse':
      if (reusePlan()) persistBoard();
      return 'render';
    case 'board-deselect':
      b.sel = b.sel2 = null;
      refreshBoard();
      return null;
    case 'board-zoom':
      zoomBoard(Number(el.dataset.z));
      return null;
    case 'board-step': {
      const p = plan();
      if (!p) return null;
      p.cur = Number(el.dataset.i);
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    }
    case 'board-plan-pick': {
      const root = planRoot();
      root.v = Number(el.dataset.i);
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    }
    case 'board-drill-ask':
      b.drillAsk = !b.drillAsk;
      return 'render';
    case 'board-drill-start': {
      const root = planRoot();
      if (!root) return null;
      const used = new Set(root.variants.map(x => x.name));
      let name = 'Drop drill';
      for (let n = 2; used.has(name); n++) name = `Drop drill ${n}`;
      root.variants.push({ name, steps: [{ name: curSteps()[0]?.name ?? 'Deploy', tokens: {} }], cur: 0, drill: { first: el.dataset.first === 'B' ? 'B' : 'A', log: [], res: [] } });
      ensureIds(root.variants);
      root.v = root.variants.length - 1;
      b.drillAsk = false; b.sel = b.sel2 = null;
      persistBoard();
      console.log(`[board] drop drill started: ${el.dataset.first} is the Defender`);
      return 'render';
    }
    case 'board-drill-res': {
      const p = plan(), tk = el.dataset.tk;
      if (!p?.drill || !tk) return null;
      const res = new Set(p.drill.res ?? []);
      if (res.has(tk)) res.delete(tk); else { res.add(tk); delete stepTokens()[tk]; }
      p.drill.res = [...res];
      persistBoard();
      return 'render';
    }
    case 'board-drill-undo': {
      const p = plan(), di = drillInfo();
      if (!p?.drill || !di?.log.length) return null;
      const last = di.log[di.log.length - 1];
      delete stepTokens()[last.tk];
      for (const [ptk, x] of di.emb) if (x === last.tk) delete stepTokens()[ptk]; // its passengers too
      p.drill.log = di.log.slice(0, -1);
      if (b.sel === last.tk) b.sel = null;
      persistBoard();
      return 'render';
    }
    case 'board-drill-end': {
      const p = plan();
      if (!p?.drill) return null;
      console.log(`[board] drop drill ended after ${p.drill.log?.length ?? 0} drops`);
      delete p.drill;
      persistBoard();
      return 'render';
    }
    case 'board-scout': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos || curIndex() !== 0) return null;
      if (pos.scout) { scoutToTurn1(b.sel, pos.scout, pos); delete pos.scout; }
      else {
        // start the ghost up to X" toward the middle of the board (the player drags it from there)
        const X = scoutDist(...b.sel.split(':')) || 6, dx = BOARD.w / 2 - pos.x, dy = BOARD.h / 2 - pos.y, d = Math.hypot(dx, dy) || 1, k = Math.min(X, d) / d;
        pos.scout = { x: +(pos.x + dx * k * 0.98).toFixed(2), y: +(pos.y + dy * k * 0.98).toFixed(2) };
        scoutToTurn1(b.sel, pos, pos.scout);
      }
      console.log(`[board] scout move ${b.sel}: ${pos.scout ? 'planned' : 'removed'}`);
      persistBoard();
      return 'render';
    }
    case 'board-plan-copy': {
      // a copy of the current plan to try something else (e.g. aggressive vs defensive)
      const root = planRoot(), cur = plan();
      const used = new Set(root.variants.map(x => x.name));
      const name = VARIANT_NAMES.find(n => !used.has(n)) ?? `Plan ${root.variants.length + 1}`;
      // a copy of the path on screen, as a plan of its own (no branches)
      root.variants.push({ name, steps: JSON.parse(JSON.stringify(curSteps())), cur: curIndex() });
      ensureIds(root.variants);
      root.v = root.variants.length - 1;
      persistBoard();
      return 'render';
    }
    case 'board-plan-split': {
      // this plan becomes the going-first version; a copy of it is the going-second version
      const root = planRoot(), cur = plan();
      const base = cur.name === 'Main' ? '' : cur.name.slice(0, 15);
      cur.when = 'first';
      cur.name = base ? `${base} (first)` : 'Going first';
      root.variants.splice(root.v + 1, 0, { name: base ? `${base} (second)` : 'Going second', when: 'second', steps: JSON.parse(JSON.stringify(curSteps())), cur: curIndex() });
      ensureIds(root.variants);
      persistBoard();
      console.log(`[board] plan split into "${cur.name}" and its going-second version`);
      return 'render';
    }
    case 'board-plan-sync-deploy': {
      // the deployment on screen (this version's Deploy step) goes into the other version too
      const root = planRoot(), cur = plan();
      for (const vv of root.variants) if (vv !== cur && vv.when && vv.when !== cur.when) vv.steps[0].tokens = JSON.parse(JSON.stringify(cur.steps[0].tokens ?? {}));
      persistBoard();
      return 'render';
    }
    case 'board-plan-rename': {
      const cur = plan();
      const name = (globalThis.prompt?.('Name this plan', cur.name) ?? '').trim();
      if (name) { cur.name = name.slice(0, 24); persistBoard(); }
      return 'render';
    }
    case 'board-plan-delete': {
      // the plan picked in the row (a root path) and all its branches
      const root = planRoot(), ri = rootOf(root.variants, root.v);
      const all = subtree(root.variants, ri);
      if (root.variants.length - all.length < 1 || !(globalThis.confirm?.(`Delete the plan "${root.variants[ri].name}"${all.length > 1 ? ` and its ${all.length - 1} branch${all.length > 2 ? 'es' : ''}` : ''}?`) ?? true)) return null;
      removePaths(root, all);
      persistBoard();
      return 'render';
    }
    case 'board-live': {
      // the live table on / off (off: back to the plan that was on screen)
      const root = planRoot(), lv = livePlan();
      if (!root) return null;
      if (lv) root.v = Math.min(lv.back ?? 0, root.variants.length - 1);
      else if (!openLive()) return null;
      b.sel = b.sel2 = null; b.modelsOf = null;
      persistBoard();
      return 'render';
    }
    case 'board-live-confirm': {
      const lv = livePlan(), g = gameNow();
      if (!lv) return null;
      lv.stamp = { round: g.round, turn: g.turn, phase: g.phase };
      console.log(`[board] live table: positions confirmed for round ${g.round}, ${g.turn}'s turn (${g.phase})`);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-shock': {
      const lv = livePlan(), tk = el.dataset.tk;
      if (!lv || !tk) return null;
      lv.shock ??= {};
      if (lv.shock[tk]) delete lv.shock[tk]; else lv.shock[tk] = true;
      console.log(`[board] live table: ${tk} ${lv.shock[tk] ? 'battle-shocked' : 'no longer battle-shocked'}`);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-hint': {
      // a row of the cards: that unit selected and ringed on the map, its move and its attack drawn
      const same = b.hint && b.hint.kind === el.dataset.kind && b.hint.tk === el.dataset.tk;
      b.hint = same ? null : { kind: el.dataset.kind, tk: el.dataset.tk };
      b.sel = same ? b.sel : el.dataset.tk; b.sel2 = null; b.modelsOf = null;
      console.log(`[board] suggestion on the map: ${b.hint ? `${b.hint.kind} ${b.hint.tk} — ${hintData()?.text ?? 'nothing to draw'}` : 'cleared'}`);
      refreshBoard();
      // the map into view (on a phone the cards are below it)
      const host = document.getElementById('board-host'), r = host?.getBoundingClientRect();
      if (b.hint && r && (r.bottom < 120 || r.top > (window.innerHeight || 0) - 120)) host.scrollIntoView({ block: 'center', behavior: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
      return null;
    }
    case 'board-advise': {
      // the first time the player is told what is sent and agrees; after that a tap asks
      if (!adviseAgreed()) { b.adviseAsk = true; refreshBoard(); return null; }
      askForPlan();
      return null;
    }
    case 'board-advise-agree': {
      try { localStorage.setItem(ADVISE_OK_KEY, '1'); } catch { /* asked again next time */ }
      b.adviseAsk = false;
      askForPlan();
      return null;
    }
    case 'board-advise-cancel': b.adviseAsk = false; refreshBoard(); return null;
    case 'board-advise-copy': copyPrompt(); return null;
    case 'board-advise-paste': pasteAnswer(); return null;
    case 'board-advise-clip': pasteFromClipboard(); return null;
    case 'board-plan-map': b.planOnMap = b.planOnMap === false; b.planFocus = null; refreshBoard(); return null;
    case 'board-plan-focus': {
      const i = Number(el.dataset.i);
      b.planFocus = i < 0 || b.planFocus === i ? null : i;
      b.planOnMap = true;
      refreshBoard();
      if (b.planFocus != null) intoView('board-plan-bar', 'start');
      return null;
    }
    case 'board-plan-read': intoView('board-advise-here'); return null;
    case 'board-advise-paste-cancel': b.pasteOpen = false; b.promptCopy = null; b.pasteError = null; refreshBoard(); return null;
    case 'board-advise-clear': { const lv = livePlan(); b.advice = null; if (lv?.advice) { delete lv.advice; persistBoard(); } refreshBoard(); return null; }
    case 'board-hint-clear': b.hint = null; refreshBoard(); return null;
    case 'board-next-toggle': b.nextOpen = b.nextOpen === false; refreshBoard(); return null;
    case 'board-next-all': b.nextAll = !b.nextAll; refreshBoard(); return null;
    case 'board-playout': runPlayOut(); return null;
    case 'board-playout-log': b.playLog = !b.playLog; refreshBoard(); return null;
    case 'board-playout-plan': if (playOutToPlan()) { b.sel = b.sel2 = null; return 'render'; } return null;
    case 'board-my-toggle': b.myOpen = b.myOpen === false; refreshBoard(); return null;
    case 'board-my-all': b.myAll = !b.myAll; refreshBoard(); return null;
    case 'board-step-add': {
      const p = plan();
      if (!p) return null;
      const steps = curSteps();
      const nt = JSON.parse(JSON.stringify(steps[curIndex()]?.tokens ?? steps[steps.length - 1]?.tokens ?? {}));
      for (const pos of Object.values(nt)) if (pos?.scout) { pos.x = pos.scout.x; pos.y = pos.scout.y; delete pos.scout; } // Turn 1 starts after the Scout moves
      p.steps.push({ name: `Turn ${steps.length}`, tokens: nt });
      p.cur = curSteps().length - 1;
      persistBoard();
      return 'render';
    }
    // ---- branches: split the plan after a turn (plantree.mjs)
    case 'board-branch': {
      const root = planRoot(), vs = root.variants, at = curIndex();
      // the path that owns this turn (a shared turn of a branch belongs to an ancestor)
      let pi = root.v;
      while (vs[pi].parent != null && at <= vs[pi].from) pi = vs.findIndex(v => v.id === vs[pi].parent);
      const nb = branchPlan(vs, pi, at, { kind: 'decision' });
      viewPath(root, vs.indexOf(nb), at);
      console.log(`[board] branch after ${curSteps()[at]?.name}: "${nb.branch.label}" (${vs.length} paths)`);
      persistBoard();
      return 'render';
    }
    case 'board-branch-add': {
      const root = planRoot(), vs = root.variants, t = treeTarget(el);
      if (!t) return null;
      const nb = branchPlan(vs, t.pi, t.at);
      viewPath(root, vs.indexOf(nb), t.at);
      persistBoard();
      return 'render';
    }
    case 'board-tree-go': {
      // the branch map: that path on the board, at that turn (the row label: the turn on screen, or the path's first own turn)
      const root = planRoot();
      const i = root.variants.findIndex(v => v.id === el.dataset.vid);
      if (i < 0) return null;
      const n = resolveSteps(root.variants, i).length;
      const at = Number(el.dataset.i);
      const own = root.variants[i].parent != null ? root.variants[i].from + 1 : 0;
      const keep = i === root.v ? curIndex() : Math.max(curIndex(), own);
      root.v = i;
      root.variants[i].cur = Math.min(n - 1, at >= 0 ? at : keep);
      b.sel = b.sel2 = null;
      if (b.cmp === root.variants[i].id) b.cmp = null;
      persistBoard();
      return 'render';
    }
    case 'board-tree-fold':
      b.tmHide = !b.tmHide;
      persistBoard();
      refreshBoard();
      return null;
    case 'board-tree-forecast':
      ctx.forecastBranches?.();
      refreshBoard();
      return null;
    case 'board-branch-view': {
      const root = planRoot(), t = treeTarget(el);
      const i = root.variants.findIndex(v => v.id === el.dataset.vid);
      if (i < 0 || !t) return null;
      viewPath(root, i, t.at);
      persistBoard();
      return 'render';
    }
    case 'board-branch-chosen': {
      // at the table: this option was decided, or this outcome happened (tap again to undo)
      const root = planRoot(), t = treeTarget(el);
      if (!t) return null;
      const meta = root.variants[t.pi].splits[t.at];
      meta.chosen = meta.chosen === el.dataset.vid ? null : el.dataset.vid;
      const i = root.variants.findIndex(v => v.id === el.dataset.vid);
      if (meta.chosen && i >= 0) viewPath(root, i, t.at);
      console.log(`[board] branch ${meta.chosen ? `"${el.dataset.vid}" happened` : 'reopened'} after step ${t.at}`);
      persistBoard();
      return 'render';
    }
    case 'board-branch-delete': {
      const root = planRoot(), vs = root.variants;
      const i = vs.findIndex(v => v.id === el.dataset.vid);
      if (i < 0 || vs[i].parent == null) return null;
      const all = subtree(vs, i);
      if (!(globalThis.confirm?.(`Delete the branch "${vs[i].branch?.label ?? vs[i].name}"${all.length > 1 ? ` and the ${all.length - 1} below it` : ''}?`) ?? true)) return null;
      const pi = vs.findIndex(v => v.id === vs[i].parent), at = vs[i].from;
      removePaths(root, all);
      const p2 = root.variants.findIndex(v => v.id === (vs[pi]?.id));
      if (p2 >= 0 && optionsAt(root.variants, p2, at).length < 2) delete root.variants[p2].splits[at];
      persistBoard();
      return 'render';
    }
    case 'board-split-kind': case 'board-split-auto': case 'board-split-how': {
      const root = planRoot(), t = treeTarget(el);
      if (!t) return null;
      const meta = root.variants[t.pi].splits[t.at];
      if (action === 'board-split-kind') meta.kind = el.dataset.value;
      if (action === 'board-split-auto') meta.auto = el.dataset.value === 'wipe' ? { atk: null, def: null, how: 'fight', ...(meta.auto ?? {}) } : null;
      if (action === 'board-split-how') (meta.auto ??= {}).how = el.dataset.value;
      persistBoard();
      return 'render';
    }
    case 'board-attack': {
      const toks = placed();
      const s1 = toks.find(t => t.tk === b.sel), s2 = toks.find(t => t.tk === b.sel2);
      if (!s1 || !s2 || s1.side === s2.side) return null;
      const gap = unitGap(s1, s2);
      const half = s1.u.halfRangeWeapons.length ? gap <= Math.min(...s1.u.halfRangeWeapons) / 2 : false;
      const chain = el.dataset.phase === 'chain';
      const phase = chain ? 'shooting' : el.dataset.phase;
      const sight = phase === 'shooting' ? pairSight(s1, s2) : null;
      ctx.openAttack({
        chain, side: s1.side, phase, attacker: s1.key, target: s2.key, distance: Math.round(gap), halfRange: half, round: curIndex(),
        ...(sight ? { cover: sight.cover, inRange: sight.seeingBody < sight.body ? sight.seeingBody : null } : {}),
      });
      return 'render';
    }
    case 'board-share':
      shareImage();
      return null;
    case 'board-nudge': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
      pos.x = Math.max(0, Math.min(BOARD.w, pos.x + Number(el.dataset.dx)));
      pos.y = Math.max(0, Math.min(BOARD.h, pos.y + Number(el.dataset.dy)));
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-danger':
      b.danger = el.dataset.value === 'off' ? null : el.dataset.value;
      refreshBoard();
      return null;
    case 'board-arrive':
      b.arrive = el.dataset.value === 'off' ? null : el.dataset.value;
      refreshBoard();
      return null;
    case 'board-danger-kind': {
      b.dangerKinds ??= { shoot: true, charge: true };
      b.dangerKinds[el.dataset.k] = !b.dangerKinds[el.dataset.k];
      refreshBoard();
      return null;
    }
    case 'board-photo-map':
      b.settings.photoMap = el.dataset.value;
      persistBoard();
      refreshBoard();
      return null;
    case 'board-photo-adjust': {
      const key = photoKey();
      photoTask(() => adjustPhoto(key, BOARD, { diagram: cornerDiagram }), 'adjust');
      return null;
    }
    case 'board-photo-turn': {
      const key = photoKey();
      photoTask(() => turnPhoto(key, BOARD), 'turn');
      return null;
    }
    case 'board-photo-remove': {
      const key = photoKey();
      photoTask(() => removePhoto(key), 'remove');
      return null;
    }
    default:
      return null;
  }
}

export function boardChange(el) {
  const b = boardState();
  if (el.dataset.input === 'board-hull') {
    const v = Number(el.value), label = el.dataset.label;
    if (!label || !(v >= 1 && v <= 30)) return null;
    const hulls = hullSizes(), s = b.sel && placed().find(t => t.tk === b.sel);
    const cur = s?.u.members.find(m => m.label === label)?.fp;
    const h = hulls[label] ?? { l: +(cur?.hw * 2 || 5).toFixed(1), w: +(cur?.hh * 2 || 3).toFixed(1) };
    h[el.dataset.dim === 'w' ? 'w' : 'l'] = +v.toFixed(1);
    hulls[label] = h;
    try { localStorage.setItem(HULL_KEY, JSON.stringify(hulls)); } catch { /* best effort */ }
    hullMemo = hulls;
    unitCache.clear();
    console.log(`[board] hull of ${label}: ${h.l}" x ${h.w}"`);
    return 'render';
  }
  if (el.dataset.input === 'board-embark') {
    const tk = el.value, ttk = b.sel;
    if (!tk || !ttk) return null;
    const toks = stepTokens(), old = toks[tk] ?? {};
    toks[tk] = { in: ttk, ...(old.per != null ? { per: old.per } : {}), ...(old.rot != null ? { rot: old.rot } : {}), ...(Number.isFinite(old.gap) ? { gap: old.gap } : {}) };
    console.log(`[board] ${tk} embarks in ${ttk}`);
    persistBoard();
    return 'render'; // the units still to place (above the map) change too
  }
  if (el.dataset.input === 'board-cmp') { b.cmp = el.value || null; persistBoard(); refreshBoard(); return null; }
  if (el.dataset.input === 'board-photo') {
    const file = el.files?.[0];
    const key = photoKey();
    el.value = '';
    if (file && key) photoTask(() => startPhoto(file, key, BOARD, { diagram: cornerDiagram }), 'import');
    return false;
  }
  if (el.dataset.input === 'board-branch-label' || el.dataset.input === 'board-branch-p') {
    const root = planRoot(), t = treeTarget(el);
    if (!t) return false;
    const vs = root.variants, meta = vs[t.pi].splits[t.at];
    const isMain = el.dataset.vid === vs[t.pi].id, kid = vs.find(v => v.id === el.dataset.vid);
    if (el.dataset.input === 'board-branch-label') {
      const val = el.value.trim().slice(0, 40) || (isMain ? 'As planned' : 'Option');
      if (isMain) meta.label = val; else if (kid) { kid.branch.label = val; kid.name = val; }
    } else {
      const raw = el.value.trim();
      const p = raw === '' ? null : Math.max(0, Math.min(100, Number(raw))) / 100;
      if (isMain) meta.p = p; else if (kid) kid.branch.p = p;
    }
    persistBoard();
    return true;
  }
  if (el.dataset.input === 'board-split-atk' || el.dataset.input === 'board-split-def') {
    const root = planRoot(), t = treeTarget(el);
    if (!t) return false;
    const vs = root.variants, meta = vs[t.pi].splits[t.at];
    meta.auto ??= { how: 'fight' };
    meta.auto[el.dataset.input === 'board-split-atk' ? 'atk' : 'def'] = el.value || null;
    if (el.dataset.input === 'board-split-def' && el.value) {
      // the first branch is "it happens": that unit is taken off the board from the next turn of that branch on
      const opts = optionsAt(vs, t.pi, t.at), kid = vs[opts[1]?.vi];
      const name = ctx.state.armies[el.value[0]]?.units.find(u => `${el.value[0]}:${u.key}` === el.value)?.name ?? 'The unit';
      if (kid) {
        kid.steps.forEach((st, k) => { if (st && k > t.at) delete st.tokens?.[el.value]; });
        if (/^(It happens|Option \d+)$/.test(kid.branch.label)) { kid.branch.label = `${name} destroyed`; kid.name = kid.branch.label; }
      }
      if (/^(It does not happen|Option 1|As planned)$/.test(meta.label ?? '')) meta.label = `${name} survives`;
    }
    persistBoard();
    return true;
  }
  if (el.dataset.input === 'board-disp') {
    if (setupLocked()) { console.log('[board] disposition change ignored: set-up locked during a game'); return 'render'; }
    b.settings[`disp${el.dataset.side}`] = el.value;
    b.sel = b.sel2 = null;
    persistBoard();
    return true;
  }
  return false;
}

export function afterRender() {
  wireBoard();
  revealSelected();
}
/** Three columns: keep the selected unit (and the matchup card) in view inside its army's column. */
function revealSelected() {
  for (const q of ['#board-tri .tri-selbox', '#board-tri #board-pair']) {
    const el = document.querySelector(q), col = el?.closest('.tri-army');
    if (!el || !col || col.scrollHeight <= col.clientHeight + 1) continue;
    const r = el.getBoundingClientRect(), c = col.getBoundingClientRect();
    if (r.top < c.top || r.top > c.bottom - 60) col.scrollTop += r.top - c.top - 8;
  }
}

// ---------------------------------------------------------------------------
// Export the current step as a PNG (Web Share on phones, download elsewhere)

async function shareImage() {
  const l = currentLayout();
  const p = plan();
  const svgText = boardSvg({ forExport: true });
  const img = new Image();
  const url = URL.createObjectURL(new Blob([svgText], { type: 'image/svg+xml' }));
  try {
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
    const canvas = document.createElement('canvas');
    const HEAD = 64;
    canvas.width = 880; canvas.height = 1200 + HEAD;
    const g = canvas.getContext('2d');
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, canvas.width, canvas.height);
    g.drawImage(img, 0, HEAD, 880, 1200);
    // header: missions, layout, deployment and step, so a shared picture explains itself
    const ms = missionsFor(dispOf('A'), dispOf('B'));
    const dep = l ? DEPLOYMENTS[l.deployment]?.name : '';
    g.fillStyle = '#1b1b1a';
    g.font = '600 24px system-ui, sans-serif';
    g.fillText(`${curSteps()[curIndex()]?.name ?? 'Plan'} · ${dispositionName(dispOf('A'))} vs ${dispositionName(dispOf('B'))} · Layout ${l ? layoutLetter(l.variant) : ''} · ${dep ?? ''}`, 16, 28);
    g.font = '18px system-ui, sans-serif';
    g.fillStyle = C.A; g.fillText(`■ A ${ctx.state.armies.A?.faction ?? ''}: ${ms.A ?? ''}`, 16, 54);
    g.fillStyle = C.B; g.fillText(`■ B ${ctx.state.armies.B?.faction ?? ''}: ${ms.B ?? ''}`, 450, 54);
    const blob = await new Promise(res => canvas.toBlob(res, 'image/png'));
    const name = `${l?.id ?? 'board'}-${(curSteps()[curIndex()]?.name ?? 'plan').replace(/\s+/g, '-').toLowerCase()}.png`;
    const file = new File([blob], name, { type: 'image/png' });
    ctx.state.lastBoardImage = { name, size: blob.size };
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], title: 'Battle plan' });
    } else {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
    }
    console.log(`[calc] board image ${name}: ${blob.size} bytes`);
  } catch (err) {
    console.warn('[calc] board image failed', err);
  } finally {
    URL.revokeObjectURL(url);
  }
}

// for the Mission tab: every plan for this layout + lists, each step's units
// at their planned positions (only units placed on the board in that step)
export function boardPlans() {
  const root = planRoot();
  if (!root) return [];
  return root.variants.map((vv, vi) => ({
    index: vi, name: choiceLabel(root.variants, vi), when: vv.when ?? null, id: vv.id, parent: vv.parent ?? null,
    steps: resolveSteps(root.variants, vi).map((st, si) => {
      const out = { name: st.name, A: [], B: [], embarked: { A: [], B: [] } };
      const inside = embarkedIn(st.tokens);
      for (const [tk, x] of inside) { const [s, k] = tk.split(':'), u = unitInfo(s, k), tu = unitInfo(...x.split(':')); if (u) out.embarked[s].push({ key: tk, name: u.cu.name, in: x, transport: tu?.cu.name ?? x }); }
      for (const [tk, pos] of Object.entries(st.tokens ?? {})) {
        if (pos?.in) continue; // embarked: not on the battlefield
        const [side, key] = tk.split(':');
        const u = unitInfo(side, key, si);
        if (!u || u.dead) continue;   // no models left by this turn's round: destroyed
        out[side].push({ key: tk, name: u.cu.name, x: pos.x, y: pos.y, models: tokenModels(u, pos), move: u.move, ranges: u.ranges, melee: u.melee, oc: u.oc, points: u.cu.points ?? 0,
          keywords: u.cu.keywords ?? [], lone: u.flags?.loneOperative || 0, flags: u.flags ?? {} });
      }
      return out;
    }),
  }));
}

/** The plan trees for the Mission tab: [{ ri (root index), name, tree }] for every plan that has branches. */
export function boardTrees() {
  const root = planRoot();
  if (!root) return [];
  const vs = root.variants;
  return vs.map((v, i) => i).filter(i => vs[i].parent == null && vs.some((v, k) => v.parent != null && rootOf(vs, k) === i))
    .map(ri => ({ ri, name: vs[ri].name, tree: treeOf(vs, ri, autoP), stepName: (pi, at) => resolveSteps(vs, pi)[at]?.name ?? `step ${at}` }));
}

/** The board of a saved game: the settings, and the plans made with these two lists (signature `sig`). */
export function boardSnapshot(sig) {
  const b = boardState();
  const plans = Object.fromEntries(Object.entries(b.plans).filter(([k]) => k.endsWith(`|${sig}`)));
  const { photoMap, ...settings } = b.settings;
  return JSON.parse(JSON.stringify({ settings, plans }));
}
/** For a share link: the settings and the plan for the layout on screen (no table photo). */
export function boardShareSnap() {
  const b = boardState(), k = planKey(), root = planRoot();
  const { photoMap, ...settings } = b.settings;
  return JSON.parse(JSON.stringify({ settings, plans: k && root ? { [k]: { ...root, meta: undefined } } : {} }));
}
export function persistBoardNow() { persistBoard(); }
/** Put a saved game's board back: its layout and dispositions, and its plans (other plans stay). */
export function boardRestore(snap) {
  const b = boardState();
  b.hist = null;      // a saved game put back is not an undoable change
  b.settings = { ...(b.settings.photoMap ? { photoMap: b.settings.photoMap } : {}), ...(snap?.settings ?? {}) };
  Object.assign(b.plans, JSON.parse(JSON.stringify(snap?.plans ?? {})));
  b.sel = b.sel2 = null; b.view = null; b.danger = null; b.arrive = null;
  persistBoard();
}

// for the Mission tab: the mission, layout and which deployment zone is A's
/** Event / round set-up: the layout letter of the round, dispositions back to what the lists say. */
export function boardSetup({ variant = null, listDispositions = false } = {}) {
  const b = boardState();
  if (variant != null) b.settings.variant = variant;
  if (listDispositions) { delete b.settings.dispA; delete b.settings.dispB; }
  b.sel = b.sel2 = null;
  persistBoard();
}
/** A different list was loaded into `side`: its disposition comes from the new list again. */
export function boardListChanged(side) {
  const b = boardState();
  if (b.settings[`disp${side}`] == null) return;
  console.log(`[board] ${side}: new list, the disposition picked on the Board (${b.settings[`disp${side}`]}) is dropped`);
  delete b.settings[`disp${side}`];
  persistBoard();
}
/** For the Mission tab's set-up checklist. */
export function boardSetupInfo() {
  const st = ctx.state, b = boardState();
  const deploy = curSteps()[0]?.tokens ?? {};
  const keys = new Set(Object.keys(deploy));
  const count = (X) => (st.armies[X]?.units ?? []).filter(u => keys.has(`${X}:${u.key}`)).length;
  return {
    listDisp: { A: listDisp('A'), B: listDisp('B') },
    overridden: { A: dispOverridden('A'), B: dispOverridden('B') },
    swapped: !!b.settings.swapZones, locked: setupLocked(),
    placed: { A: count('A'), B: count('B') },
    total: { A: st.armies.A?.units.length ?? 0, B: st.armies.B?.units.length ?? 0 },
  };
}
/** Layout ids on which a plan holds units of my list (signature `sig` on side X). */
export function plannedLayouts(X, sig) {
  const out = new Set();
  for (const r of Object.values(boardState().plans)) {
    if (r?.variants && r.meta?.[X === 'A' ? 'a' : 'b'] === sig && sideTokens(r, X) > 0) out.add(r.meta.layout);
  }
  return out;
}

export function boardContext() {
  const l = currentLayout();
  return {
    layout: l, deployment: l ? DEPLOYMENTS[l.deployment] : null,
    dispA: dispOf('A'), dispB: dispOf('B'), missions: missionsFor(dispOf('A'), dispOf('B')),
    zoneA: zoneOf('A'), zoneB: zoneOf('B'), colors: { A: C.A, B: C.B },
  };
}

// for tests
export function _boardDebug() {
  return { live: (() => { const root = planRoot(), i = liveIndex(root), lv = i >= 0 ? root.variants[i] : null; return lv ? { on: !!livePlan(), steps: lv.steps.map(x => x.name), cur: lv.cur, stamp: lv.stamp, shock: lv.shock, snaps: (lv.snaps ?? []).map(x => ({ round: x.round, turn: x.turn, units: Object.keys(x.tokens).length })), from: lv.liveFrom } : null; })(),
    next: (() => { const d = nextTurnData(); return d ? { opp: d.opp, fresh: d.fresh, hand: d.hand, reserves: d.reserves, res: d.res, my: d.my, play: playMemo.key === nextMemo.key ? playMemo : { state: 'idle' }, advise: { info: adviseInfo, state: currentAdvice()?.state ?? null, text: currentAdvice()?.text ?? null, pasted: !!currentAdvice()?.pasted, plan: planData(), pasteError: boardState().pasteError ?? null, kept: livePlan()?.advice ?? null, prompt: () => { const r = adviseRequest(); return r ? promptText(r) : null; }, agreed: adviseAgreed(), size: (() => { const r = adviseRequest(); return r ? payloadSize(r) : null; })(), request: adviseRequest }, hint: boardState().hint ?? null, hintText: hintData()?.text ?? null, moves: moveMemo.key === nextMemo.key ? moveMemo : null } : null; })(),
    stepTokens: stepTokens(), cur: curIndex(), layout: currentLayout()?.id, tokens: placed().map(t => ({ tk: t.tk, x: t.x, y: t.y, rot: t.rot, per: t.per })), plan: plan(), sel: boardState().sel, sel2: boardState().sel2, photoKey: photoKey(), photo: photoInfo(photoKey()), photos: _photoDebug(),
    units: placed().map(t => ({ tk: t.tk, x: t.x, y: t.y, models: t.models, keywords: t.u.cu.keywords ?? [], ranges: t.u.ranges })), danger: boardState().danger ?? null,
    arrive: (() => { const a = arriveInfo(boardState()); return a ? { for: a.X, round: a.round, off: a.off.map(u => u.name), deepStrike: a.dsOff.map(u => u.name), zones: a.zones, zone: a.zone } : null; })() };
}
export { footprint };
