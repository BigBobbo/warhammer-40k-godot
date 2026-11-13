// Board planner view for the combat calculator: the official 11e GW layout
// for the two armies' Force Dispositions, deployment zones, objectives, and
// draggable unit tokens at real base size, with a ruler, range rings, a link
// into the calculator and saved plan steps (Deploy, Turn 1, ...).
//
// The view is plain SVG in board inches (44 x 60); pan / pinch-zoom change
// the viewBox. app.js owns the shared state and calls in through initBoard().

import {
  BOARD, DEPLOYMENTS, OBJECTIVE_RANGE, ENGAGEMENT_RANGE,
  footprint, formation, unitGap, layoutsFor, missionsFor, dispositionName, DISPOSITIONS, inPoly,
} from './board.mjs';
import { boardUnit } from './adapter.mjs';

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

function plan() {
  const b = boardState();
  const k = planKey();
  if (!k) return null;
  b.plans[k] ??= { steps: [{ name: 'Deploy', tokens: {} }], cur: 0 };
  return b.plans[k];
}

function stepTokens() {
  const p = plan();
  return p ? p.steps[p.cur].tokens : {};
}

// ---------------------------------------------------------------------------
// Units on the board

const unitCache = new Map();
function unitInfo(side, key) {
  const army = ctx.state.armies[side];
  const cu = army?.units.find(u => u.key === key);
  if (!cu) return null;
  const ck = `${side}|${key}|${cu.name}|${cu.models}`;
  if (!unitCache.has(ck)) {
    const bu = boardUnit(cu);
    unitCache.set(ck, { cu, ...bu, models: formation(bu.members) });
  }
  return unitCache.get(ck);
}

function placed() {
  const out = [];
  for (const [tk, pos] of Object.entries(stepTokens())) {
    const [side, key] = tk.split(':');
    const u = unitInfo(side, key);
    if (u) out.push({ tk, side, key, x: pos.x, y: pos.y, models: u.models, u });
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

function shapeSvg(fp, x, y, fill, stroke, sw) {
  if (fp.shape === 'round') return `<circle cx="${f2(x)}" cy="${f2(y)}" r="${f2(fp.r)}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`;
  if (fp.shape === 'oval') return `<ellipse cx="${f2(x)}" cy="${f2(y)}" rx="${f2(fp.rx)}" ry="${f2(fp.ry)}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`;
  return `<rect x="${f2(x - fp.hw)}" y="${f2(y - fp.hh)}" width="${f2(fp.hw * 2)}" height="${f2(fp.hh * 2)}" rx="0.3" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" ${fp.approx ? 'stroke-dasharray="0.4 0.25"' : ''}/>`;
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
  const toks = placed();
  // range rings of the selected unit (union of per-model circles, uniform tint)
  const sel = toks.find(t => t.tk === b.sel);
  if (sel && !forExport) {
    const kinds = Object.keys(b.rings).filter(k => b.rings[k]);
    for (const k of kinds) {
      const R = ringRadius(sel.u, k);
      parts.push(`<g opacity="0.16" data-ring="${k}">${sel.models.map(m => `<circle cx="${f2(sel.x + m.dx)}" cy="${f2(sel.y + m.dy)}" r="${f2(R + Math.max(m.fp.r ?? 0, m.fp.rx ?? 0, m.fp.hw ?? 0))}" fill="${C[sel.side]}"/>`).join('')}</g>`);
    }
  }
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
      + t.models.map(m => shapeSvg(m.fp, m.dx, m.dy, fill, isSel ? C.sel : '#ffffff', isSel ? 0.22 : 0.08)).join('')
      + `<text x="0" y="${f2(Math.min(...t.models.map(m => m.dy - (m.fp.r ?? m.fp.ry ?? m.fp.hh))) - 0.35)}" font-size="0.95" text-anchor="middle" fill="${C.text}" font-family="system-ui,sans-serif" font-weight="600" paint-order="stroke" stroke="${C.mat}" stroke-width="0.25">${ctx.esc(shortName(t.u.cu.name))}</text></g>`);
  }
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
  const onBoard = new Set(toks.map(t => t.tk));
  const tray = (side) => st.armies[side].units.filter(u => !onBoard.has(`${side}:${u.key}`))
    .map(u => `<button class="chip" data-action="board-place" data-side="${side}" data-key="${esc(u.key)}" style="border-color:${C[side]}">＋ ${esc(u.name)}</button>`).join('');
  return `
    <section class="section"><div class="card">
      <div class="row" style="gap:8px">
        <div class="grow"><div class="lab tiny muted">A · ${esc(st.armies.A.faction)}</div>${dispSel('A')}</div>
        <div class="grow"><div class="lab tiny muted">B · ${esc(st.armies.B.faction)}</div>${dispSel('B')}</div>
      </div>
      <div class="modrow" style="margin-top:8px"><div class="lab">Layout (official GW 11e)</div>${ctx.seg('board-variant', l?.variant ?? 1, [[1, 'Layout 1'], [2, 'Layout 2'], [3, 'Layout 3']], 'compact')}</div>
      <div class="small" style="margin-top:8px" id="board-mission"><b>A</b> plays <b>${esc(ms.A ?? '?')}</b> · <b>B</b> plays <b>${esc(ms.B ?? '?')}</b><br><span class="muted">${esc(dep?.name ?? '')} · A deploys in the <span style="color:${C.A}">blue</span> zone</span></div>
      <div class="row" style="margin-top:8px;gap:6px">
        <button class="btn ghost grow" data-action="board-swap-zones">⇅ Swap zones</button>
        <button class="btn ghost grow" data-action="board-share">⇪ Share image</button>
      </div>
    </div></section>
    <section class="section"><details class="more card" ${b.trayClosed ? '' : 'open'} data-details="board-tray" style="margin:0">
      <summary>Place units · ${st.armies.A.units.length + st.armies.B.units.length - toks.length} not on the board</summary>
      <div class="lab tiny muted">A · ${esc(st.armies.A.faction)}</div><div class="chips">${tray('A') || '<span class="muted small">All on the board.</span>'}</div>
      <div class="lab tiny muted" style="margin-top:8px">B · ${esc(st.armies.B.faction)}</div><div class="chips" style="margin-bottom:6px">${tray('B') || '<span class="muted small">All on the board.</span>'}</div>
    </details></section>
    <section class="section">
      <div class="row" style="gap:6px;flex-wrap:wrap">
        ${ctx.seg('board-mode', b.mode, [['move', '✋ Move'], ['ruler', '📏 Ruler']], 'compact')}
      </div>
      <div class="row" style="gap:6px;margin-top:6px;flex-wrap:wrap">
        ${p ? p.steps.map((s, i) => `<button class="chip ${i === p.cur ? 'on' : ''}" data-action="board-step" data-i="${i}">${esc(s.name)}</button>`).join('') : ''}
        <button class="chip" data-action="board-step-add">＋ Next turn</button>
      </div>
      <div class="board-wrap card" id="board-host" style="padding:4px;margin-top:8px">${boardSvg()}</div>
      <div class="row tiny muted" style="margin-top:4px;gap:6px"><span class="grow">Pinch or use ± to zoom · drag empty space to pan</span>
        <button class="icon-btn" data-action="board-zoom" data-z="0.7" aria-label="Zoom in">＋</button>
        <button class="icon-btn" data-action="board-zoom" data-z="1.4" aria-label="Zoom out">－</button>
        <button class="icon-btn" data-action="board-zoom" data-z="0" aria-label="Fit board">⤢</button></div>
    </section>
    <section class="section" id="board-panel">${selectionPanel()}</section>`;
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
  const rings = [
    ringChip('move', `Move ${u.move}"`),
    ringChip('advance', `Move + Advance (max ${u.move + 6}")`),
    u.melee ? ringChip('charge', `Charge threat (${u.move}" + 7" avg)`) : '',
    ringChip('engage', 'Engagement 2"'),
    ...u.ranges.map(r => ringChip(`r${r}`, `Range ${r}"`)),
  ].join('');
  let pair = '';
  if (s2) {
    const gap = unitGap(s1, s2);
    const enemy = s1.side !== s2.side;
    pair = `<div class="card" style="margin-top:8px"><div class="title">${esc(s1.u.cu.name)} → ${esc(s2.u.cu.name)}</div>
      <div class="small" id="board-gap">Gap: <b>${gap.toFixed(1)}"</b> (closest bases)${gap <= ENGAGEMENT_RANGE ? ' · engaged' : ''}</div>
      ${enemy ? `<div class="row" style="gap:6px;margin-top:8px">
        ${u.ranges.length ? `<button class="btn primary grow" data-action="board-attack" data-phase="shooting">🎯 Shoot →</button>` : ''}
        ${u.melee ? `<button class="btn primary grow" data-action="board-attack" data-phase="fight">⚔ Fight →</button>` : ''}
      </div><div class="tiny muted" style="margin-top:4px">Opens the calculator with this gap as the distance${u.halfRangeWeapons.length ? ' (half range set from it)' : ''}.</div>` : ''}
    </div>`;
  }
  return `<div class="card">
    <div class="row"><div class="grow"><div class="title" style="color:${C[s1.side]}">${esc(s1.u.cu.name)}</div>
      <div class="muted tiny">${s1.u.cu.models} models · M${u.move}"${u.ranges.length ? ` · ranges ${u.ranges.map(r => `${r}"`).join(', ')}` : ''}${s1.models.some(m => m.fp.approx) ? ' · footprint approximate' : ''}</div></div>
      <button class="icon-btn" data-action="board-remove" aria-label="Remove from board">✕</button></div>
    <div class="lab tiny muted" style="margin-top:8px">Show around this unit</div><div class="chips">${rings}</div>
    ${pair}
  </div>`;
}

// ---------------------------------------------------------------------------
// Partial re-render (keeps scroll position and the pointer gesture alive)

export function refreshBoard() {
  const host = document.getElementById('board-host');
  if (host) host.innerHTML = boardSvg();
  const panel = document.getElementById('board-panel');
  if (panel) panel.innerHTML = selectionPanel();
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
  const w = Math.max(6, Math.min(full.w, v.w));
  const h = w * (full.h / full.w);
  const x = Math.max(full.x - w * 0.25, Math.min(full.x + full.w - w * 0.75, v.x));
  const y = Math.max(full.y - h * 0.25, Math.min(full.y + full.h - h * 0.75, v.y));
  b.view = { x, y, w, h };
  const svg = document.getElementById('board-svg');
  if (svg) svg.setAttribute('viewBox', `${f2(x)} ${f2(y)} ${f2(w)} ${f2(h)}`);
}

export function zoomBoard(factor) {
  const b = boardState();
  if (!factor) { b.view = null; refreshBoard(); return; }
  const v = b.view ?? fullView();
  const cx = v.x + v.w / 2, cy = v.y + v.h / 2;
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
      stepTokens()[gesture.tk] = { x, y };
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
    case 'board-remove':
      if (b.sel) delete stepTokens()[b.sel];
      b.sel = b.sel2 = null;
      persistBoard();
      return 'render';
    case 'board-ring':
      b.rings[el.dataset.k] = !b.rings[el.dataset.k];
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
    case 'board-step-add': {
      const p = plan();
      if (!p) return null;
      const last = p.steps[p.steps.length - 1];
      p.steps.push({ name: `Turn ${p.steps.length}`, tokens: JSON.parse(JSON.stringify(p.steps[p.cur].tokens ?? last.tokens)) });
      p.cur = p.steps.length - 1;
      persistBoard();
      return 'render';
    }
    case 'board-attack': {
      const toks = placed();
      const s1 = toks.find(t => t.tk === b.sel), s2 = toks.find(t => t.tk === b.sel2);
      if (!s1 || !s2 || s1.side === s2.side) return null;
      const gap = unitGap(s1, s2);
      const half = s1.u.halfRangeWeapons.length ? gap <= Math.min(...s1.u.halfRangeWeapons) / 2 : false;
      ctx.openAttack({ side: s1.side, phase: el.dataset.phase, attacker: s1.key, target: s2.key, distance: Math.round(gap), halfRange: half });
      return 'render';
    }
    case 'board-share':
      shareImage();
      return null;
    default:
      return null;
  }
}

export function boardChange(el) {
  const b = boardState();
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
    g.fillText(`${p?.steps[p.cur]?.name ?? 'Plan'} · ${dispositionName(dispOf('A'))} vs ${dispositionName(dispOf('B'))} · Layout ${l?.variant ?? ''} · ${dep ?? ''}`, 16, 28);
    g.font = '18px system-ui, sans-serif';
    g.fillStyle = C.A; g.fillText(`■ A ${ctx.state.armies.A?.faction ?? ''}: ${ms.A ?? ''}`, 16, 54);
    g.fillStyle = C.B; g.fillText(`■ B ${ctx.state.armies.B?.faction ?? ''}: ${ms.B ?? ''}`, 450, 54);
    const blob = await new Promise(res => canvas.toBlob(res, 'image/png'));
    const name = `${l?.id ?? 'board'}-${(p?.steps[p.cur]?.name ?? 'plan').replace(/\s+/g, '-').toLowerCase()}.png`;
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

// for tests
export function _boardDebug() {
  return { layout: currentLayout()?.id, tokens: placed().map(t => ({ tk: t.tk, x: t.x, y: t.y })), plan: plan(), sel: boardState().sel, sel2: boardState().sel2 };
}
export { footprint };
