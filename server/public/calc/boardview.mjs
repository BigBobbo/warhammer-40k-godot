// Board planner view for the combat calculator: the official 11e GW layout
// for the two armies' Force Dispositions, deployment zones, objectives, and
// draggable unit tokens at real base size, with a ruler, range rings, a link
// into the calculator and saved plan steps (Deploy, Turn 1, ...).
//
// The view is plain SVG in board inches (44 x 60); pan / pinch-zoom change
// the viewBox. app.js owns the shared state and calls in through initBoard().

import {
  BOARD, DEPLOYMENTS, OBJECTIVE_RANGE, ENGAGEMENT_RANGE,
  footprint, formation, coherentFormation, coherency, COHERENCY, rotateFormation, unitGap, layoutsFor, missionsFor, dispositionName, DISPOSITIONS, inPoly, layoutLetter,
} from './board.mjs';
import { boardUnit, earlyArrival, transportOf, passengerCheck } from './adapter.mjs';
import { sightVerdict, threatTo, chargeReach, canHide, HIDDEN_RANGE, GONE_TO_GROUND } from './sight.mjs';
import { inRange, ocInRange, planWarnings, arrivalZones } from './planeval.mjs';
import { photoFor, photoInfo, startPhoto, adjustPhoto, turnPhoto, removePhoto, _photoDebug } from './photoview.mjs';
import { ensureIds, resolveSteps, rootOf, treeOf, choiceLabel, subtree, branch as branchPlan, optionsAt, chain, evaluate, treeRows } from './plantree.mjs';
import { chargeOdds, chargeRollNeeded } from './engine.mjs';

// fixed map colours (not theme tokens): the board reads the same in light and
// dark mode and exports to an image unchanged
const C = {
  mat: '#e6e1d3', edge: '#b8b09a', area: 'rgba(120,112,92,0.38)', areaEdge: '#6f6754', feature: '#5f584a',
  obj: '#1f1f1f', objRing: 'rgba(214,160,0,0.22)', objEdge: '#b88a00', text: '#2b2a26',
  A: '#2a78d6', B: '#d95926', sel: '#f2c200', ruler: '#111111',
};

let ctx = null;          // { state, esc, seg, chip, render, persist, openAttack, signature, other }
const LS_KEY = 'w40k_calc_board_v1';

export function initBoard(c) {
  ctx = c;
  // the branches panel is drawn again when the unit-vs-unit odds of a chance branch are worked out
  ctx.registerHost?.('board-treemap-host', treeMapHtml);
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
  try { localStorage.setItem(LS_KEY, JSON.stringify({ settings: b.settings, plans: b.plans })); } catch { /* best effort */ }
}

// ---------------------------------------------------------------------------
// Mission / layout selection

function dispOf(side) {
  const b = boardState();
  return b.settings[`disp${side}`] ?? ctx.state.armies[side]?.roster?.force_disposition ?? 'take-and-hold';
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
    const n = sideTokens(r, me);
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
  root.variants = src.root.variants.map((sv, vi) => ({
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
function unitInfo(side, key) {
  const army = ctx.state.armies[side];
  const cu = army?.units.find(u => u.key === key);
  if (!cu) return null;
  const ck = `${side}|${key}|${cu.name}|${cu.models}|${(army.roster?.detachments ?? []).map(d => d?.ref?.id).join(',')}`;
  if (!unitCache.has(ck)) {
    const bu = boardUnit(cu, army);
    // Objective Control: each model's OC (datasheet), summed over the unit
    const oc = cu.members.reduce((a, m) => a + (parseInt(m.dcUnit.profiles?.[0]?.OC, 10) || 0) * (m.ru.model_count ?? 1), 0);
    unitCache.set(ck, { cu, ...bu, oc, models: coherentFormation(bu.members), formations: new Map() });
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
  return pos.rot ? rotateFormation(base, pos.rot) : base;
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
    if (u) out.push({ tk, side, key, x: pos.x, y: pos.y, rot: pos.rot ?? 0, per: pos.per ?? 5, gap: Number.isFinite(pos.gap) ? pos.gap : null, models: tokenModels(u, pos), u });
  }
  return out;
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
    for (const k of kinds) {
      if (k === 'detect') {
        // who can see it: only models inside this line (dashed, in the enemy's colour)
        const det = detectionOf(sel).range;
        if (det) parts.push(`<g data-ring="detect" data-r="${det}" fill="${C[sel.side === 'A' ? 'B' : 'A']}" fill-opacity="0.05" stroke="${C[sel.side === 'A' ? 'B' : 'A']}" stroke-width="0.12" stroke-dasharray="0.6 0.4">${sel.models.map(m => `<circle cx="${f2(sel.x + m.dx)}" cy="${f2(sel.y + m.dy)}" r="${f2(det + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))}"/>`).join('')}</g>`);
        continue;
      }
      const R = ringRadius(sel.u, k);
      parts.push(`<g opacity="0.16" data-ring="${k}">${sel.models.map(m => `<circle cx="${f2(sel.x + m.dx)}" cy="${f2(sel.y + m.dy)}" r="${f2(R + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))}" fill="${C[sel.side]}"/>`).join('')}</g>`);
    }
  }
  if (!forExport) parts.push(ghostSvg());
  for (const t of toks) {
    const isSel = t.tk === b.sel || t.tk === b.sel2;
    const fill = C[t.side];
    // invisible grab area over the whole formation: a finger rarely lands exactly on a 25 mm base
    const ext = t.models.reduce((a, m) => {
      const r = m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0), ry = m.fp.r ?? Math.max(m.fp.ry ?? 0, m.fp.hh ?? 0);
      return { x0: Math.min(a.x0, m.dx - r), x1: Math.max(a.x1, m.dx + r), y0: Math.min(a.y0, m.dy - ry), y1: Math.max(a.y1, m.dy + ry) };
    }, { x0: Infinity, x1: -Infinity, y0: Infinity, y1: -Infinity });
    parts.push(`<g class="tok" data-tok="${t.tk}" transform="translate(${f2(t.x)},${f2(t.y)})" style="cursor:grab">`
      + `<rect x="${f2(ext.x0 - 0.4)}" y="${f2(ext.y0 - 0.4)}" width="${f2(ext.x1 - ext.x0 + 0.8)}" height="${f2(ext.y1 - ext.y0 + 0.8)}" rx="0.6" fill="${fill}" fill-opacity="${isSel ? 0.12 : 0.04}" stroke="none"/>`
      + `<g fill-opacity="${tokAlpha}">${t.models.map(m => shapeSvg(m.fp, m.dx, m.dy, fill, isSel ? C.sel : '#ffffff', isSel ? 0.22 : 0.08, m.rot)).join('')}</g>`
      // the first letter of each model's datasheet name on its base (Prosecutor Squad: P; an attached Trajann: T)
      + `<g class="tok-letters" pointer-events="none" font-family="system-ui,sans-serif" font-weight="700" text-anchor="middle" dominant-baseline="central" fill="#ffffff">${t.models.map(m => {
        const h = halfBase(m.fp), fs = Math.max(0.35, Math.min(1.6, Math.min(h.hx, h.hy) * 1.25));
        return `<text x="${f2(m.dx)}" y="${f2(m.dy)}" font-size="${f2(fs)}">${ctx.esc(baseLetter(m.label))}</text>`;
      }).join('')}</g>`
      + `<text x="0" y="${f2(Math.min(...t.models.map(m => m.dy - (m.fp.r ?? Math.max(m.fp.rx ?? 0, m.fp.hw ?? 0)))) - 0.35 * fontK)}" font-size="${f2(0.95 * fontK)}" text-anchor="middle" fill="${C.text}" font-family="system-ui,sans-serif" font-weight="600" paint-order="stroke" stroke="${C.mat}" stroke-width="${f2(0.25 * fontK)}">${ctx.esc(shortName(t.u.cu.name))}${(() => { const n = passengersOf(t.tk).length; return n ? ` 🚚+${n}` : ''; })()}</text></g>`);
  }
  // who controls each objective in this step: OC of each army's units in range
  // (on the hosting terrain area, or within 3" + the marker); the Mission tab's
  // board-plan forecast uses the same measurement
  parts.push('<g id="obj-control" pointer-events="none">');
  for (const o of l.objectives) {
    const oc = { A: 0, B: 0 };
    // 14.02: the OC of the MODELS within range (not the whole unit's when one model is there)
    for (const t of toks) if (t.u.oc) oc[t.side] += ocInRange({ ...t, oc: t.u.oc }, o, l.pieces);
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
  if (!forExport) parts.push(`<g id="ruler-layer">${rulerSvg(b.ruler)}</g>`);
  const size = forExport ? 'width="880" height="1200"' : '';
  return `<svg id="board-svg" xmlns="http://www.w3.org/2000/svg" viewBox="${f2(vb.x)} ${f2(vb.y)} ${f2(vb.w)} ${f2(vb.h)}" ${size} preserveAspectRatio="xMidYMid meet" style="touch-action:none;display:block;width:100%;height:auto;background:${forExport ? '#ffffff' : 'transparent'}">${parts.join('')}</svg>`;
}

// Next-turn danger from one army: where its units can shoot after a normal
// move (M + longest range) and charge (M + the 2D6 charge roll: likely >= 80%,
// possible >= 40%). Terrain and line of sight are ignored and the edge is
// blurred ~1": a planning envelope, not a measurement.
function dangerSvg(b) {
  const side = b.danger;
  if (!side) return '';
  const kinds = b.dangerKinds ?? { shoot: true, charge: true };
  const layers = { shoot: [], likely: [], possible: [] };
  for (const t of placed().filter(x => x.side === side)) {
    const maxR = t.u.ranges.length ? Math.max(...t.u.ranges) : 0;
    const likely = t.u.melee ? chargeReach(t.u.move, 0.8) : null, possible = t.u.melee ? chargeReach(t.u.move, 0.4) : null;
    for (const m of t.models) {
      const r = Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0);
      const cx = f2(t.x + m.dx), cy = f2(t.y + m.dy);
      if (kinds.shoot && maxR) layers.shoot.push(`<circle cx="${cx}" cy="${cy}" r="${f2(t.u.move + maxR + r)}"/>`);
      if (kinds.charge && possible) layers.possible.push(`<circle cx="${cx}" cy="${cy}" r="${f2(possible + r)}"/>`);
      if (kinds.charge && likely) layers.likely.push(`<circle cx="${cx}" cy="${cy}" r="${f2(likely + r)}"/>`);
    }
  }
  const col = C[side];
  // shooting reach is hatched (it often covers most of the board), charges are solid
  return `<defs><filter id="dz-blur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="0.5"/></filter>`
    + `<pattern id="dz-hatch" width="1.4" height="1.4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="0.25" height="1.4" fill="${col}"/></pattern></defs>`
    + `<g id="danger-layer" data-from="${side}" pointer-events="none">`
    + (layers.shoot.length ? `<g data-dz="shoot" fill="url(#dz-hatch)" opacity="0.3">${layers.shoot.join('')}</g>` : '')
    + `<g filter="url(#dz-blur)">`
    + (layers.possible.length ? `<g data-dz="charge-possible" fill="#c0392b" opacity="0.12">${layers.possible.join('')}</g>` : '')
    + (layers.likely.length ? `<g data-dz="charge-likely" fill="#c0392b" opacity="0.2">${layers.likely.join('')}</g>` : '')
    + '</g></g>';
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
    ${a ? `<span class="tiny muted" style="flex-basis:100%" id="board-arrive-note">Battle round ${a.round}${curIndex() < 2 ? ' (the first round reserves can arrive)' : ''}${a.zones.late ? ' — a unit still in reserves at the end of round 3 is destroyed' : ''}. Hatched: wholly within 6" of an edge, for any unit in reserves${a.zones.zoneClosed ? `; not in ${a.Y}'s deployment zone before round 3` : ''} (20.04).${a.dsAny ? ` Tinted: anywhere for a Deep Strike unit (24.09).` : ` ${a.X} has no Deep Strike unit.`} Clear: within 8" of ${a.Y}'s models. Every base must fit; a unit needs room for all its models.
      ${a.early ? `<br><span id="board-arrive-early"><b>${ctx.esc(a.early.name)}</b> (${ctx.esc(a.early.owner)}): one unit a turn arrives as if the battle round were one higher, so it can come in battle round 1${a.zones.zoneClosed ? `, and into ${a.Y}'s deployment zone now` : ''}.</span>` : ''}
      <br>${a.off.length ? `Not on the board in this step: <b>${a.off.map(u => `${ctx.esc(short(u))}${a.dsOff.includes(u) ? ' (Deep Strike)' : ''}`).join(', ')}</b>.` : `All of ${a.X}'s units are on the board in this step.`}</span>` : ''}`;
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
  const s = n.replace(/ \(\d\)$/, (m) => m); // keep "(1)" suffixes
  return s.length > 22 ? `${s.slice(0, 21)}…` : s;
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

export function boardView() {
  const st = ctx.state;
  const b = boardState();
  const esc = ctx.esc;
  if (!st.armies.A || !st.armies.B) return `<p class="hint">Load both armies to plan on the board.</p>`;
  const l = currentLayout();
  const ms = missionsFor(dispOf('A'), dispOf('B'));
  const dep = l ? DEPLOYMENTS[l.deployment] : null;
  const p = plan();
  const dispSel = (side) => `<select class="sel" data-input="board-disp" data-side="${side}" aria-label="Force Disposition of army ${side}">
      ${DISPOSITIONS.map(d => `<option value="${d.id}" ${d.id === dispOf(side) ? 'selected' : ''}>${esc(d.name)}</option>`).join('')}</select>`;
  const toks = placed();
  const onBoard = new Set([...toks.map(t => t.tk), ...embarkedIn(stepTokens()).keys()]);
  const tray = (side) => st.armies[side].units.filter(u => !onBoard.has(`${side}:${u.key}`))
    .map(u => `<button class="chip" data-action="board-place" data-side="${side}" data-key="${esc(u.key)}" style="border-color:${C[side]}">＋ ${esc(u.name)}</button>`).join('');
  const left = st.armies.A.units.length + st.armies.B.units.length - onBoard.size;
  // The map comes first (one column on a phone; the left pane on a tablet): the plan
  // steps and the units still to place sit right above it, everything else below / beside.
  const wideNow = ctx.wide?.() ?? false;
  const reuse = reusablePlan();
  // plan steps, Move / Ruler and the units still to place: above the map on a phone
  // (one swipeable line), at the top of the side pane on a tablet (the map gets the height)
  const stepsRow = `<div class="row" style="gap:6px;flex-wrap:wrap">
        ${p ? curSteps().map((s, i) => `<button class="chip ${i === curIndex() ? 'on' : ''}" data-action="board-step" data-i="${i}">${esc(s.name)}</button>`).join('') : ''}
        <button class="chip" data-action="board-step-add">＋ Next turn</button>
        <button class="chip" data-action="board-branch" id="board-branch" title="Split the plan after this turn: your decision, or a chance outcome">⑂ Branch here</button>
        <span class="grow"></span>
        ${ctx.seg('board-mode', b.mode, [['move', '✋ Move'], ['ruler', '📏 Ruler']], 'compact')}
      </div>`;
  const trayHtml = left ? `<div class="unit-strip ${wideNow ? 'wrap' : ''}" id="board-tray" aria-label="Units not on the board: tap one to place it">
        <span class="tiny muted" style="flex:none">Place ${left}:</span>${tray('A')}${tray('B')}</div>` : '';
  return `<div id="board-dock" class="board-dock">${dockHtml()}</div><div class="blay"><div class="col map">
    <section class="section b-steps">
      ${wideNow ? '' : stepsRow + trayHtml}
      ${wideNow ? '' : `<div id="board-treemap-host">${treeMapHtml()}</div>`}
      ${reuse ? `<div class="warnbox" id="board-reuse" style="display:flex;gap:8px;align-items:center"><span class="grow">You planned this layout with this list against <b>${esc(reuse.vs)}</b> (${reuse.n} unit positions).</span><button class="btn primary" data-action="board-reuse">Use my deployment</button></div>` : ''}
      <div class="board-wrap card" id="board-host" style="padding:4px;${wideNow ? '' : 'margin-top:8px'}">${boardSvg()}</div>
      <div class="row tiny muted" style="margin-top:4px;gap:6px"><span class="grow">Pinch or use ± to zoom · drag empty space to pan</span>
        <button class="icon-btn" data-action="board-zoom" data-z="0.7" aria-label="Zoom in">＋</button>
        <button class="icon-btn" data-action="board-zoom" data-z="1.4" aria-label="Zoom out">－</button>
        <button class="icon-btn" data-action="board-zoom" data-z="0" aria-label="Fit board">⤢</button></div>
    </section>
    </div><div class="col side">
    ${wideNow ? `<section class="section">${stepsRow}<div id="board-treemap-host">${treeMapHtml()}</div></section>` : ''}
    <section class="section" id="board-panel">${selectionPanel()}</section>
    <div id="board-warnings-host">${stepWarningsHtml()}</div>
    ${wideNow && trayHtml ? `<section class="section">${trayHtml}</section>` : ''}
    <section class="section"><div class="card">
      <div class="row" style="gap:8px">
        <div class="grow"><div class="lab tiny muted">A · ${esc(st.armies.A.faction)}</div>${dispSel('A')}</div>
        <div class="grow"><div class="lab tiny muted">B · ${esc(st.armies.B.faction)}</div>${dispSel('B')}</div>
      </div>
      <div class="modrow" style="margin-top:8px"><div class="lab">Layout (official GW 11e)</div>${ctx.seg('board-variant', l?.variant ?? 1, [[1, 'Layout A'], [2, 'Layout B'], [3, 'Layout C']], 'compact')}</div>
      <div class="small" style="margin-top:8px" id="board-mission"><b>A</b> plays <b>${esc(ms.A ?? '?')}</b> · <b>B</b> plays <b>${esc(ms.B ?? '?')}</b><br><span class="muted">${esc(dep?.name ?? '')} · A deploys in the <span style="color:var(--side-a-ink)">blue</span> zone</span></div>
      <div class="row" style="margin-top:8px;gap:6px">
        <button class="btn ghost grow" data-action="board-swap-zones">⇅ Swap zones</button>
        <button class="btn ghost grow" data-action="board-share">⇪ Share image</button>
      </div>
    </div></section>
    <section class="section">
      <div class="row" style="gap:6px;flex-wrap:wrap;align-items:center" id="board-danger-bar">${dangerBar()}</div>
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap;align-items:center" id="board-arrive-bar">${arriveBar()}</div>
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap;align-items:center" id="board-variants">
        <span class="lab tiny muted">Plan</span>
        ${planRoot() ? planRoot().variants.map((vv, i) => (vv.parent != null ? '' : `<button class="chip ${i === rootOf(planRoot().variants, planRoot().v) ? 'on' : ''}" data-action="board-plan-pick" data-i="${i}">${esc(vv.name)}</button>`)).join('') : ''}
        <button class="chip" data-action="board-plan-copy">＋ Copy plan</button>
        ${planRoot() && !planRoot().variants.some(vv => vv.when) ? '<button class="chip" data-action="board-plan-split" id="board-plan-split">⇄ Going first / second</button>' : ''}
        ${planRoot()?.variants.length > 1 ? '<button class="icon-btn" data-action="board-plan-rename" aria-label="Rename this plan">✎</button><button class="icon-btn" data-action="board-plan-delete" aria-label="Delete this plan">✕</button>' : ''}
      </div>
      ${splitNote()}
      <div id="board-tree-host">${treeHtml()}</div>
      <div id="board-photo-bar" style="margin-top:6px">${photoBar()}</div>
    </section>
  </div></div>`;
}

function dangerBar() {
  const b = boardState();
  const kinds = b.dangerKinds ?? { shoot: true, charge: true };
  return `<span class="lab tiny muted">⚠ Danger next turn</span>
    ${ctx.seg('board-danger', b.danger ?? 'off', [['off', 'Off'], ['A', 'From A'], ['B', 'From B']], 'compact')}
    ${b.danger ? `${ctx.chip('board-danger-kind', !!kinds.shoot, 'Shooting', 'data-k="shoot"')}${ctx.chip('board-danger-kind', !!kinds.charge, 'Charges', 'data-k="charge"')}
    <span class="tiny muted" style="flex-basis:100%">Hatched: where that army can shoot after moving (move + range). Red: where it can charge (dark ≥ 80%, light ≥ 40%). Ignores terrain and line of sight; edges are ±1".</span>` : ''}`;
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
  const b = boardState();
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

function selectionPanel() {
  const b = boardState();
  const esc = ctx.esc;
  const toks = placed();
  const s1 = toks.find(t => t.tk === b.sel);
  if (!s1) return `<p class="hint">Tap a unit on the board to see its ranges; tap a second unit to measure the gap between them and calculate the attack.</p>`;
  const s2 = toks.find(t => t.tk === b.sel2);
  const u = s1.u;
  const ringChip = (k, lab) => ctx.chip('board-ring', !!b.rings[k], lab, `data-k="${k}"`);
  const det = detectionOf(s1);
  const rings = [
    det.range ? ringChip('detect', det.lone && det.lone <= det.range ? `Seen only within ${det.range}" (Lone Operative)` : `Seen only within ${det.range}" while Hidden`) : '',
    ringChip('move', `Move ${u.move}"${u.moveBonus ? ` (+${u.moveBonus}" ${u.moveBonusFrom ?? 'detachment'})` : ''}`),
    ringChip('advance', `Move + Advance (max ${u.move + 6}")`),
    u.melee ? ringChip('charge', `Charge threat (${u.move}" + 7" avg)`) : '',
    ringChip('engage', 'Engagement 2"'),
    ...u.ranges.map(r => ringChip(`r${r}`, `Range ${r}"`)),
  ].join('');
  let pair = '';
  if (s2) {
    const gap = unitGap(s1, s2);
    const enemy = s1.side !== s2.side;
    const sight = enemy ? pairSight(s1, s2) : null;
    pair = `<div class="card" style="margin-top:8px"><div class="title">${esc(s1.u.cu.name)} → ${esc(s2.u.cu.name)}</div>
      <div class="small" id="board-gap">Gap: <b>${gap.toFixed(1)}"</b> (closest bases)${gap <= ENGAGEMENT_RANGE ? ' · engaged' : ''}</div>
      ${sight ? sightHtml(sight, s1, s2) : ''}
      ${enemy ? `<div class="row" style="gap:6px;margin-top:8px">
        ${u.ranges.length ? `<button class="btn primary grow" data-action="board-attack" data-phase="shooting">🎯 Shoot →</button>` : ''}
        ${u.melee ? `<button class="btn primary grow" data-action="board-attack" data-phase="fight">⚔ Fight →</button>` : ''}
      </div>${u.melee ? `<button class="btn ghost block" style="margin-top:6px" data-action="board-attack" data-phase="chain">⚡ ${u.ranges.length ? 'Shoot, charge and fight' : 'Charge and fight'} this turn →</button>` : ''}<div class="tiny muted" style="margin-top:4px">Opens the calculator with this gap as the distance${u.halfRangeWeapons.length ? ' (half range set from it)' : ''}${sight ? ', cover and the models that can see' : ''}.</div>` : ''}
    </div>`;
  }
  return `<div class="card">
    <div class="row"><div class="grow"><div class="title" style="color:var(--side-${s1.side.toLowerCase()}-ink)">${esc(s1.u.cu.name)}</div>
      <div class="muted tiny">${s1.u.cu.models} models · M${u.move}"${u.ranges.length ? ` · ranges ${u.ranges.map(r => `${r}"`).join(', ')}` : ''}${s1.models.some(m => m.fp.approx) ? ' · footprint approximate' : ''}</div></div>
      <button class="icon-btn" data-action="board-remove" aria-label="Remove from board">✕</button></div>
    <div class="row" style="gap:6px;margin-top:8px;align-items:center">
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
    })() : ''}
    ${transportPanel(s1)}
    ${s1.models.length > 1 ? `<div class="modrow" style="margin-top:6px" id="board-spacing"><div class="lab tiny muted">Gap between bases</div>${ctx.seg('board-spacing', s1.gap ?? 'auto', [['auto', 'Auto'], [0, 'Touching'], [0.25, '¼"'], [0.5, '½"'], [1, '1"'], [2, '2"']], 'compact')}</div>` : ''}
    ${(() => {
      // 03.03: within 2" of one other model and within 9" of every other model of the unit
      const c = coherency(s1.models);
      return c.ok ? '' : `<div class="tiny" id="board-coherency" style="color:var(--warn-ink);margin-top:4px">⚠ Not in coherency: ${c.widest > COHERENCY.all ? `two models are ${c.widest.toFixed(1)}" apart (every model must be within ${COHERENCY.all}" of every other)` : `${c.alone} model${c.alone > 1 ? 's are' : ' is'} more than ${COHERENCY.near}" from any other`} (03.03). Use fewer models per row.</div>`;
    })()}
    <div class="lab tiny muted" style="margin-top:8px">Show around this unit</div><div class="chips">${rings}</div>
    ${pair}
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
  const dep = DEPLOYMENTS[l.deployment];
  const pick = (list, X) => list?.find(z => z.player === zoneOf(X))?.poly ?? null;
  const geo = { zones: { A: pick(dep?.zones, 'A'), B: pick(dep?.zones, 'B') }, territories: { A: pick(dep?.territories, 'A'), B: pick(dep?.territories, 'B') }, pieces: l.pieces, objectives: l.objectives,
    early: { A: earlyArrival(ctx.state.armies.A)?.name ?? null, B: earlyArrival(ctx.state.armies.B)?.name ?? null } };
  const steps = boardPlans()[Math.min(root.v, root.variants.length - 1)]?.steps ?? [];
  const name = curSteps()[curIndex()]?.name;
  const ws = planWarnings(steps, geo).filter(w => w.step === name);
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
  const panel = document.getElementById('board-panel');
  if (panel) panel.innerHTML = selectionPanel();
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
    const tokEl = ev.target.closest?.('[data-tok]');
    if (b.mode === 'ruler') {
      gesture = { kind: 'ruler', start: p, t0: Date.now() };
      b.ruler = { x1: p.x, y1: p.y, x2: p.x, y2: p.y };
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
      Object.assign(stepTokens()[gesture.tk], { x, y }); // keep facing and formation
      gesture.el.setAttribute('transform', `translate(${f2(x)},${f2(y)})`);
    } else if (gesture.kind === 'pan') {
      const v0 = gesture.view0;
      const scale = v0.w / gesture.rect.width;
      const dx = (ev.clientX - gesture.start.x) * scale, dy = (ev.clientY - gesture.start.y) * scale;
      if (Math.abs(dx) + Math.abs(dy) > 0.3) gesture.moved = true;
      if (b.view) setView({ x: v0.x - dx, y: v0.y - dy, w: v0.w });
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
    if (g.kind === 'drag') {
      if (!g.moved) selectToken(g.tk);
      persistBoard();
      refreshBoard();
    } else if (g.kind === 'pan' && !g.moved) {
      b.sel = null; b.sel2 = null;
      refreshBoard();
    }
  };
  svg.addEventListener('pointerup', end);
  svg.addEventListener('pointercancel', end);
  svg.addEventListener('wheel', (ev) => { ev.preventDefault(); zoomBoard(ev.deltaY > 0 ? 1.15 : 0.87); }, { passive: false });
}

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
    case 'board-variant':
      b.settings.variant = Number(el.dataset.value);
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    case 'board-swap-zones':
      b.settings.swapZones = !b.settings.swapZones;
      persistBoard();
      return 'render';
    case 'board-mode':
      b.mode = el.dataset.value;
      b.ruler = null;
      return 'render';
    case 'board-place': {
      const side = el.dataset.side, key = el.dataset.key;
      const tk = `${side}:${key}`;
      const spot = freeSpot(side, key);
      stepTokens()[tk] = spot;
      b.sel = tk; b.sel2 = null;
      persistBoard();
      return 'render';
    }
    case 'board-rotate': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
      pos.rot = (((pos.rot ?? 0) + Number(el.dataset.deg)) % 360 + 360) % 360;
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
      if (el.dataset.value === 'auto') delete pos.gap; else pos.gap = Number(el.dataset.value);
      persistBoard();
      refreshBoard();
      return null;
    }
    case 'board-formation': {
      const pos = b.sel && stepTokens()[b.sel];
      if (!pos) return null;
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
    case 'board-step-add': {
      const p = plan();
      if (!p) return null;
      const steps = curSteps();
      p.steps.push({ name: `Turn ${steps.length}`, tokens: JSON.parse(JSON.stringify(steps[curIndex()]?.tokens ?? steps[steps.length - 1]?.tokens ?? {})) });
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
        chain, side: s1.side, phase, attacker: s1.key, target: s2.key, distance: Math.round(gap), halfRange: half,
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
    b.settings[`disp${el.dataset.side}`] = el.value;
    b.sel = b.sel2 = null;
    persistBoard();
    return true;
  }
  return false;
}

export function afterRender() {
  wireBoard();
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
    steps: resolveSteps(root.variants, vi).map(st => {
      const out = { name: st.name, A: [], B: [], embarked: { A: [], B: [] } };
      const inside = embarkedIn(st.tokens);
      for (const [tk, x] of inside) { const [s, k] = tk.split(':'), u = unitInfo(s, k), tu = unitInfo(...x.split(':')); if (u) out.embarked[s].push({ key: tk, name: u.cu.name, in: x, transport: tu?.cu.name ?? x }); }
      for (const [tk, pos] of Object.entries(st.tokens ?? {})) {
        if (pos?.in) continue; // embarked: not on the battlefield
        const [side, key] = tk.split(':');
        const u = unitInfo(side, key);
        if (!u) continue;
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
/** Put a saved game's board back: its layout and dispositions, and its plans (other plans stay). */
export function boardRestore(snap) {
  const b = boardState();
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
  return { stepTokens: stepTokens(), cur: curIndex(), layout: currentLayout()?.id, tokens: placed().map(t => ({ tk: t.tk, x: t.x, y: t.y, rot: t.rot, per: t.per })), plan: plan(), sel: boardState().sel, sel2: boardState().sel2, photoKey: photoKey(), photo: photoInfo(photoKey()), photos: _photoDebug(),
    units: placed().map(t => ({ tk: t.tk, x: t.x, y: t.y, models: t.models, keywords: t.u.cu.keywords ?? [], ranges: t.u.ranges })), danger: boardState().danger ?? null,
    arrive: (() => { const a = arriveInfo(boardState()); return a ? { for: a.X, round: a.round, off: a.off.map(u => u.name), deepStrike: a.dsOff.map(u => u.name), zones: a.zones, zone: a.zone } : null; })() };
}
export { footprint };
