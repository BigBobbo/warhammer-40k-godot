// Table photo under the board map: pick a photo, tap the four table corners
// (with a loupe for precision), and the photo is flattened onto the 44 x 60
// board at true scale so tokens can be dragged onto the real models.
// Photos stay on the device (IndexedDB), one per plan step.

import { homography, orderCorners, cornersUsable, warpToBoard, boardCorners } from './photo.mjs';

const DB = 'w40k_calc_photos';
const STORE = 'photos';
const MAX_SRC = 1600;       // longest edge kept from the camera photo (px)
const PPI = 16;             // warped photo resolution (px per board inch)
const MAT = [230, 225, 211]; // board mat colour where the photo does not reach

const cache = new Map();    // key -> { url, dataUrl, rec } | { loading: true } | { none: true }

// ---------------------------------------------------------------------------
// IndexedDB

function db() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE);
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
async function tx(mode, fn) {
  const d = await db();
  return new Promise((res, rej) => {
    const t = d.transaction(STORE, mode);
    const req = fn(t.objectStore(STORE));
    t.oncomplete = () => { res(req?.result); d.close(); };
    t.onerror = () => { rej(t.error); d.close(); };
  });
}
const idbGet = (k) => tx('readonly', s => s.get(k));
const idbPut = (k, v) => tx('readwrite', s => s.put(v, k));
const idbDel = (k) => tx('readwrite', s => s.delete(k));

// ---------------------------------------------------------------------------
// Public API (boardview.mjs)

/** Cached photo for a plan step: { url, dataUrl } once loaded; starts the load and calls onLoad when ready. */
export function photoFor(key, board, onLoad) {
  if (!key) return null;
  const c = cache.get(key);
  if (c?.url) return c;
  if (c) return null;
  cache.set(key, { loading: true });
  idbGet(key).then(async (rec) => {
    if (!rec) { cache.set(key, { none: true }); return; }
    await build(key, rec, board);
    onLoad?.();
  }).catch((err) => { console.warn('[calc] photo load failed', err); cache.set(key, { none: true }); });
  return null;
}

export function photoInfo(key) {
  const c = cache.get(key);
  return c?.rec ? { taps: c.rec.taps, turn: c.rec.turn ?? 0, sw: c.rec.sw, sh: c.rec.sh, w: c.w, h: c.h } : null;
}

/** New photo from a file input: downscale, ask for the corners, save and warp. */
export async function startPhoto(file, key, board, opts) {
  const bmp = await createImageBitmap(file);
  const k = Math.min(1, MAX_SRC / Math.max(bmp.width, bmp.height));
  const sw = Math.round(bmp.width * k), sh = Math.round(bmp.height * k);
  const cv = document.createElement('canvas');
  cv.width = sw; cv.height = sh;
  cv.getContext('2d').drawImage(bmp, 0, 0, sw, sh);
  bmp.close?.();
  const src = await new Promise(res => cv.toBlob(res, 'image/jpeg', 0.9));
  console.log(`[calc] photo picked: ${sw}x${sh}, ${src.size} bytes`);
  const taps = await askCorners(src, sw, sh, null, opts);
  if (!taps) return false;
  const rec = { src, sw, sh, taps, turn: 0 };
  await idbPut(key, rec);
  await build(key, rec, board);
  return true;
}

/** Re-open the corner screen on the stored photo. */
export async function adjustPhoto(key, board, opts) {
  const c = cache.get(key);
  if (!c?.rec) return false;
  const taps = await askCorners(c.rec.src, c.rec.sw, c.rec.sh, c.rec.taps, opts);
  if (!taps) return false;
  const rec = { ...c.rec, taps, turn: 0 };
  await idbPut(key, rec);
  await build(key, rec, board);
  return true;
}

/** Which tapped corner is the map's top-left (fixes a photo that came out turned). */
export async function turnPhoto(key, board) {
  const c = cache.get(key);
  if (!c?.rec) return false;
  const rec = { ...c.rec, turn: ((c.rec.turn ?? 0) + 1) % 4 };
  await idbPut(key, rec);
  await build(key, rec, board);
  return true;
}

export async function removePhoto(key) {
  const c = cache.get(key);
  if (c?.url) URL.revokeObjectURL(c.url);
  cache.set(key, { none: true });
  await idbDel(key);
}

// ---------------------------------------------------------------------------
// Warp

async function build(key, rec, board) {
  const t0 = performance.now();
  const bmp = await createImageBitmap(rec.src);
  const cv = document.createElement('canvas');
  cv.width = rec.sw; cv.height = rec.sh;
  const g = cv.getContext('2d', { willReadFrequently: true });
  g.drawImage(bmp, 0, 0);
  bmp.close?.();
  const src = g.getImageData(0, 0, rec.sw, rec.sh);
  const H = homography(boardCorners(board), orderCorners(rec.taps, rec.turn ?? 0));
  const out = warpToBoard(src, H, board, PPI);
  for (let i = 0; i < out.data.length; i += 4) {
    if (out.data[i + 3] === 0) { out.data[i] = MAT[0]; out.data[i + 1] = MAT[1]; out.data[i + 2] = MAT[2]; out.data[i + 3] = 255; }
  }
  const oc = document.createElement('canvas');
  oc.width = out.width; oc.height = out.height;
  oc.getContext('2d').putImageData(new ImageData(out.data, out.width, out.height), 0, 0);
  const blob = await new Promise(res => oc.toBlob(res, 'image/jpeg', 0.88));
  const old = cache.get(key);
  if (old?.url) URL.revokeObjectURL(old.url);
  cache.set(key, { url: URL.createObjectURL(blob), dataUrl: oc.toDataURL('image/jpeg', 0.85), rec, w: out.width, h: out.height });
  console.log(`[calc] photo warped onto the board: ${out.width}x${out.height} in ${Math.round(performance.now() - t0)} ms (turn ${rec.turn ?? 0})`);
}

// ---------------------------------------------------------------------------
// Corner screen

const SVGNS = 'http://www.w3.org/2000/svg';
function el(tag, attrs = {}, parent) {
  const e = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  parent?.appendChild(e);
  return e;
}

/**
 * Full-screen corner picker. Resolves with 4 taps (photo px, tap order) or
 * null when cancelled. opts.diagram(next) -> SVG string of the mini map with
 * corner `next` (0-3) highlighted.
 */
function askCorners(blob, sw, sh, initial, opts = {}) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(blob);
    const taps = initial ? initial.map(p => [...p]) : [];
    const ov = document.createElement('div');
    ov.className = 'photo-ov';
    ov.setAttribute('role', 'dialog');
    ov.setAttribute('aria-label', 'Mark the table corners');
    ov.innerHTML = `
      <div class="photo-ov-head">
        <div class="photo-ov-diag" id="photo-diag"></div>
        <div class="grow small" id="photo-msg"></div>
      </div>
      <div class="photo-ov-stage" id="photo-stage"></div>
      <div class="photo-ov-foot">
        <button class="btn ghost" data-ov="cancel">Cancel</button>
        <button class="btn ghost" data-ov="undo">↶ Undo corner</button>
        <button class="btn primary grow" data-ov="ok" disabled>Use photo</button>
      </div>`;
    document.body.appendChild(ov);
    const stage = ov.querySelector('#photo-stage');
    const svg = el('svg', { id: 'photo-svg', viewBox: `0 0 ${sw} ${sh}`, preserveAspectRatio: 'xMidYMid meet' }, stage);
    svg.style.touchAction = 'none';
    el('image', { href: url, x: 0, y: 0, width: sw, height: sh }, svg);
    const quad = el('polygon', { fill: 'rgba(242,194,0,0.12)', stroke: '#f2c200', 'stroke-width': 3, 'vector-effect': 'non-scaling-stroke' }, svg);
    const handles = el('g', {}, svg);
    // loupe: magnified photo around the finger, drawn away from it
    const clipId = 'photo-loupe-clip';
    const defs = el('defs', {}, svg);
    const clip = el('clipPath', { id: clipId }, defs);
    const clipC = el('circle', {}, clip);
    const loupe = el('g', { 'clip-path': `url(#${clipId})`, visibility: 'hidden' }, svg);
    const loupeBg = el('rect', { fill: '#000' }, loupe);
    const loupeInner = el('g', {}, loupe);
    el('image', { href: url, x: 0, y: 0, width: sw, height: sh }, loupeInner);
    const loupeRing = el('circle', { fill: 'none', stroke: '#fff', 'stroke-width': 3, 'vector-effect': 'non-scaling-stroke', visibility: 'hidden' }, svg);
    const cross = el('path', { stroke: '#f2c200', 'stroke-width': 1.5, 'vector-effect': 'non-scaling-stroke', fill: 'none', visibility: 'hidden' }, svg);

    const scale = () => { const r = svg.getBoundingClientRect(); return Math.max(sw / r.width, sh / r.height) || 1; };
    const toImg = (cx, cy) => {
      const pt = svg.createSVGPoint(); pt.x = cx; pt.y = cy;
      const m = svg.getScreenCTM();
      const p = pt.matrixTransform(m.inverse());
      return [Math.max(0, Math.min(sw, p.x)), Math.max(0, Math.min(sh, p.y))];
    };
    const draw = () => {
      const s = scale();
      quad.setAttribute('points', taps.map(p => p.join(',')).join(' '));
      quad.setAttribute('visibility', taps.length >= 2 ? 'visible' : 'hidden');
      // once all 4 are down, number them as the map's corners (taps may have gone either way round)
      const ord = taps.length === 4 ? orderCorners(taps) : null;
      const num = (p, i) => ord ? ord.findIndex(q => q[0] === p[0] && q[1] === p[1]) + 1 : i + 1;
      handles.innerHTML = taps.map((p, i) => `<g><circle cx="${p[0]}" cy="${p[1]}" r="${14 * s}" fill="rgba(0,0,0,0.35)" stroke="#f2c200" stroke-width="${3 * s}"/>`
        + `<circle cx="${p[0]}" cy="${p[1]}" r="${2.5 * s}" fill="#f2c200"/>`
        + `<text x="${p[0] + (p[0] > sw - 50 * s ? -30 : 18) * s}" y="${p[1] + (p[1] < 40 * s ? 34 : -14) * s}" font-size="${20 * s}" font-weight="700" fill="#f2c200" stroke="#000" stroke-width="${3 * s}" paint-order="stroke" font-family="system-ui,sans-serif">${num(p, i)}</text></g>`).join('');
      const next = Math.min(taps.length, 3);
      ov.querySelector('#photo-diag').innerHTML = opts.diagram ? opts.diagram(taps.length < 4 ? next : -1) : '';
      const ok = taps.length === 4 && cornersUsable(orderCorners(taps));
      ov.querySelector('[data-ov="ok"]').disabled = !ok;
      ov.querySelector('[data-ov="undo"]').disabled = !taps.length;
      ov.querySelector('#photo-msg').innerHTML = taps.length < 4
        ? `<b>Tap table corner ${taps.length + 1}</b> (matches <b>${taps.length + 1}</b> on the little map).${taps.length ? ' Then carry on round the table.' : ' Photo from as high and square-on as you can.'}`
        : ok ? '<b>Drag a corner to fine-tune</b> — the loupe shows what is under your finger. Then <b>Use photo</b>.'
          : '<b>Those corners cross over</b> — drag them to the 4 table corners.';
    };
    const showLoupe = (p) => {
      const s = scale();
      const r = svg.getBoundingClientRect();
      const tl = toImg(r.left, r.top), br = toImg(r.right, r.bottom);
      const R = 60 * s, Z = 3;
      // opposite side from the finger
      const cx = p[0] > (tl[0] + br[0]) / 2 ? tl[0] + R + 8 * s : br[0] - R - 8 * s;
      const cy = tl[1] + R + 8 * s;
      clipC.setAttribute('cx', cx); clipC.setAttribute('cy', cy); clipC.setAttribute('r', R);
      loupeBg.setAttribute('x', cx - R); loupeBg.setAttribute('y', cy - R); loupeBg.setAttribute('width', 2 * R); loupeBg.setAttribute('height', 2 * R);
      loupeInner.setAttribute('transform', `translate(${cx} ${cy}) scale(${Z}) translate(${-p[0]} ${-p[1]})`);
      loupeRing.setAttribute('cx', cx); loupeRing.setAttribute('cy', cy); loupeRing.setAttribute('r', R);
      const k = 14 * s;
      cross.setAttribute('d', `M${cx - k} ${cy}H${cx + k}M${cx} ${cy - k}V${cy + k}`);
      for (const e of [loupe, loupeRing, cross]) e.setAttribute('visibility', 'visible');
    };
    const hideLoupe = () => { for (const e of [loupe, loupeRing, cross]) e.setAttribute('visibility', 'hidden'); };

    let drag = null;
    svg.addEventListener('pointerdown', (ev) => {
      svg.setPointerCapture(ev.pointerId);
      const p = toImg(ev.clientX, ev.clientY);
      const hit = 34 * scale();
      let best = -1, bd = Infinity;
      taps.forEach((q, i) => { const d = Math.hypot(q[0] - p[0], q[1] - p[1]); if (d < bd) { bd = d; best = i; } });
      if (best >= 0 && bd <= hit) drag = { i: best, off: [taps[best][0] - p[0], taps[best][1] - p[1]] };
      else if (taps.length < 4) { taps.push(p); drag = { i: taps.length - 1, off: [0, 0] }; }
      else return;
      draw();
      showLoupe(taps[drag.i]);
    });
    svg.addEventListener('pointermove', (ev) => {
      if (!drag) return;
      const p = toImg(ev.clientX, ev.clientY);
      taps[drag.i] = [Math.max(0, Math.min(sw, p[0] + drag.off[0])), Math.max(0, Math.min(sh, p[1] + drag.off[1]))];
      draw();
      showLoupe(taps[drag.i]);
    });
    const up = () => { drag = null; hideLoupe(); };
    svg.addEventListener('pointerup', up);
    svg.addEventListener('pointercancel', up);
    const close = (val) => {
      ov.remove();
      URL.revokeObjectURL(url);
      resolve(val);
    };
    ov.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-ov]');
      if (!b) return;
      if (b.dataset.ov === 'cancel') close(null);
      else if (b.dataset.ov === 'undo') { taps.pop(); draw(); }
      else if (b.dataset.ov === 'ok') close(taps.map(p => [Math.round(p[0] * 10) / 10, Math.round(p[1] * 10) / 10]));
    });
    // the SVG's on-screen size is only known once laid out
    requestAnimationFrame(draw);
    draw();
  });
}

// for tests
export function _photoDebug() {
  return [...cache.entries()].map(([k, v]) => ({ key: k, loaded: !!v.url, taps: v.rec?.taps ?? null, turn: v.rec?.turn ?? null, w: v.w, h: v.h }));
}
