// Live AR on the table (Board → 🥽 AR): WebXR immersive-ar with ARCore on Chrome for Android, offline. You tap three
// table corners; the board is pinned to the real table (armath.registerBoard) and drawn over the camera view:
// deployment zones, objectives and their control range, terrain footprints, your plan's units for a step; tools to
// measure base to base, show range rings from a spot, and read where the reticle is in board inches.
// No libraries: WebGL triangles in board inches, one model matrix per frame. Data comes from boardview.arData().
//
// Accuracy: ARCore reads distances ~1-4% off (the 24 Nov test on the user's tablet: 0.51" average, worst 1.0" at
// 24"). Fitting the board to the tapped corners takes out the scale part over the table; what is left is shown as
// "about ±1"". For planning and seeing the board on the table, not for settling a measurement.

import { registerBoard, triangulate, ribbon, ellipsePts, discTris, M_PER_IN } from './armath.mjs';

const MM = 1 / 25.4;
const RINGS = [3, 6, 9, 12, 18, 24];
const BASES = [0, 25, 32, 40, 50, 60];
const log = (...a) => console.log('[ar]', ...a);
const hex = (h, a = 1) => { const n = parseInt(h.slice(1), 16); return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, a]; };

export async function arSupported() {
  try { return !!navigator.xr && await navigator.xr.isSessionSupported('immersive-ar'); } catch { return false; }
}

// ---------------------------------------------------------------------------------------------------------------
// GL
function mul4(a, b) {
  const o = new Float32Array(16);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k]; o[c * 4 + r] = s; }
  return o;
}
function makeGL(canvas) {
  const gl = canvas.getContext('webgl', { xrCompatible: true, alpha: true, antialias: true });
  const sh = (t, src) => { const s = gl.createShader(t); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, 'attribute vec2 p; uniform mat4 m; void main(){ gl_Position = m * vec4(p.x, p.y, 0.0, 1.0); }'));
  gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, 'precision mediump float; uniform vec4 c; void main(){ gl_FragColor = c; }'));
  gl.linkProgram(prog);
  return { gl, prog, loc: gl.getAttribLocation(prog, 'p'), um: gl.getUniformLocation(prog, 'm'), uc: gl.getUniformLocation(prog, 'c') };
}
/** A mesh: triangles in board inches with one colour. */
function mesh(G, tris, color) {
  const buf = G.gl.createBuffer();
  G.gl.bindBuffer(G.gl.ARRAY_BUFFER, buf);
  G.gl.bufferData(G.gl.ARRAY_BUFFER, new Float32Array(tris), G.gl.STATIC_DRAW);
  return { buf, n: tris.length / 2, color };
}
function drawMesh(G, m, mvp) {
  if (!m?.n) return;
  const gl = G.gl;
  gl.bindBuffer(gl.ARRAY_BUFFER, m.buf);
  gl.enableVertexAttribArray(G.loc);
  gl.vertexAttribPointer(G.loc, 2, gl.FLOAT, false, 0, 0);
  gl.uniformMatrix4fv(G.um, false, mvp);
  gl.uniform4fv(G.uc, m.color);
  gl.drawArrays(gl.TRIANGLES, 0, m.n);
}
const freeMesh = (G, m) => { if (m?.buf) G.gl.deleteBuffer(m.buf); };

// a model matrix for small marks at a world point before the board is pinned (inches, flat on the table)
function markModel(p) {
  const k = M_PER_IN;
  return new Float32Array([k, 0, 0, 0, 0, 0, k, 0, 0, 1, 0, 0, p[0], p[1] + 0.002, p[2], 1]);
}

// ---------------------------------------------------------------------------------------------------------------
// The overlay (WebXR dom-overlay): instructions, readouts, layers and tools
function overlayHtml() {
  return `<div class="ar-top"><div id="ar-diag" class="ar-diag"></div><div class="ar-big" id="ar-big">Find the table…</div><div id="ar-msg">Move the tablet slowly over the table until the yellow ring sits on it.</div><div class="ar-q" id="ar-q"></div></div>
  <div class="ar-bot">
    <div class="ar-row" id="ar-layers"></div>
    <div class="ar-row" id="ar-tools"></div>
    <div class="ar-row" id="ar-tool-opts"></div>
    <div class="ar-row"><button id="ar-step-prev" aria-label="Previous step">◀</button><span id="ar-step" class="ar-step"></span><button id="ar-step-next" aria-label="Next step">▶</button>
      <span class="ar-grow"></span><button id="ar-redo">↺ Corners</button><button id="ar-end">End AR</button></div>
  </div>`;
}
const OV_CSS = `
#ar-ov { display: none; position: fixed; inset: 0; color: #fff; font: 16px/1.3 system-ui, sans-serif; pointer-events: none; z-index: 9999; }
#ar-ov .ar-top, #ar-ov .ar-bot { position: absolute; left: 0; right: 0; padding: 10px 12px; background: rgba(0,0,0,.55); pointer-events: auto; }
#ar-ov .ar-top { top: 0; } #ar-ov .ar-bot { bottom: 0; padding-bottom: calc(10px + env(safe-area-inset-bottom)); }
#ar-ov .ar-big { font-size: 30px; font-weight: 800; }
#ar-ov .ar-q { font-size: 13px; opacity: .85; margin-top: 2px; }
#ar-ov .ar-row { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; margin-top: 6px; }
#ar-ov .ar-grow { flex: 1; }
#ar-ov button { font: inherit; min-height: 44px; padding: 8px 12px; border-radius: 10px; border: 1px solid rgba(255,255,255,.5); background: rgba(255,255,255,.14); color: #fff; }
#ar-ov button.on { background: #f2c200; color: #111; border-color: #f2c200; font-weight: 700; }
#ar-ov .ar-step { min-width: 90px; text-align: center; font-weight: 700; }
body.ar-on #ar-ov { display: block; }
#ar-ov .ar-diag { float: right; margin-left: 8px; background: rgba(255,255,255,.85); border-radius: 8px; padding: 4px; }
#ar-ov .ar-diag:empty { display: none; }
body.ar-on > *:not(#ar-ov) { display: none !important; }
body.ar-on { background: transparent !important; }`;

// ---------------------------------------------------------------------------------------------------------------
/**
 * Start AR. data: boardview.arData(): { w, h, zones: [{ poly, color }], objectives: [{ x, y }], objRange,
 * pieces: [{ poly, cls, cat }], steps: [{ name, units: [{ side, name, color, models: [{ x, y, fp, rot }] }] }],
 * cur, colors }. -> a handle { end(), state } (for tests); resolves after the session starts or throws.
 */
export async function startAR(data) {
  let session;
  try {
    session = await navigator.xr.requestSession('immersive-ar', {
      requiredFeatures: ['hit-test'],
      optionalFeatures: ['dom-overlay', 'anchors'],
      domOverlay: { root: ensureOverlay() },
    });
  } catch (e) { document.getElementById('ar-ov')?.remove(); throw e; }
  const ov = document.getElementById('ar-ov');
  document.body.classList.add('ar-on');
  log(`session started: features ${[...(session.enabledFeatures ?? [])].join(',') || '?'}; ${data.steps.length} plan steps`);
  const S = {
    session, data, corners: [], reg: null, hit: null, layers: { zones: true, objectives: true, terrain: true, plan: true },
    tool: 'where', meas: { a: null, b: null, mm: 32 }, ring: null, step: Math.min(data.cur ?? 0, Math.max(0, data.steps.length - 1)),
    fit: true, meshes: {}, dirty: true,
  };
  let G, refSpace, hitSource;
  try {
    const canvas = document.createElement('canvas');
    canvas.id = 'ar-canvas';
    canvas.style.display = 'none';
    document.body.appendChild(canvas);
    G = makeGL(canvas);
    try { await G.gl.makeXRCompatible?.(); } catch (e) { log('makeXRCompatible failed (carrying on)', e?.name ?? e); }
    session.updateRenderState({ baseLayer: new XRWebGLLayer(session, G.gl) });
    refSpace = await session.requestReferenceSpace('local');
    hitSource = await session.requestHitTestSource({ space: await session.requestReferenceSpace('viewer') });
  } catch (e) {
    log('AR set-up failed', e);
    session.end();
    document.getElementById('ar-ov')?.remove();
    document.body.classList.remove('ar-on');
    throw e;
  }
  S.G = G;

  // ---- UI
  for (const el of ov.querySelectorAll('.ar-top, .ar-bot')) el.addEventListener('beforexrselect', (e) => e.preventDefault());
  const $ = (id) => ov.querySelector(`#${id}`);
  const btn = (id, label, on) => `<button id="${id}" class="${on ? 'on' : ''}">${label}</button>`;
  const drawUi = () => {
    const reg = !!S.reg;
    $('ar-layers').innerHTML = reg ? [['zones', 'Zones'], ['objectives', 'Objectives'], ['terrain', 'Terrain'], ['plan', 'Plan units']].map(([k, l]) => btn(`ar-l-${k}`, l, S.layers[k])).join('') + btn('ar-fit', S.fit ? 'Fit to corners' : 'True size', S.fit) : '';
    $('ar-tools').innerHTML = reg ? [['where', '⌖ Where'], ['measure', '📐 Measure'], ['rings', '◎ Rings']].map(([k, l]) => btn(`ar-t-${k}`, l, S.tool === k)).join('') : '';
    $('ar-tool-opts').innerHTML = reg && S.tool === 'measure' ? `<span>Bases</span>${BASES.map(v => btn(`ar-mm-${v}`, v ? `${v}` : 'Point', S.meas.mm === v)).join('')}` : '';
    $('ar-step').textContent = S.data.steps[S.step]?.name ?? '–';
    $('ar-step-prev').disabled = S.step <= 0; $('ar-step-next').disabled = S.step >= S.data.steps.length - 1;
  };
  ov.addEventListener('click', (ev) => {
    const b = ev.target.closest('button');
    if (!b) return;
    const id = b.id;
    if (id === 'ar-end') return session.end();
    if (id === 'ar-redo') { S.corners = []; S.reg = null; S.meas = { a: null, b: null, mm: S.meas.mm }; S.ring = null; log('corners: start again'); }
    else if (id === 'ar-fit') { S.fit = !S.fit; log(`board ${S.fit ? 'fitted to the corners' : 'at true size'}`); }
    else if (id === 'ar-step-prev') S.step = Math.max(0, S.step - 1);
    else if (id === 'ar-step-next') S.step = Math.min(S.data.steps.length - 1, S.step + 1);
    else if (id.startsWith('ar-l-')) { const k = id.slice(5); S.layers[k] = !S.layers[k]; }
    else if (id.startsWith('ar-t-')) { S.tool = id.slice(5); S.meas = { a: null, b: null, mm: S.meas.mm }; S.ring = null; }
    else if (id.startsWith('ar-mm-')) S.meas.mm = Number(id.slice(6));
    S.dirty = true;
    drawUi();
  });

  // ---- taps on the table
  session.addEventListener('select', async () => {
    const h = S.hit;
    if (!h) return;
    if (!S.reg) {
      const c = { pos: h.pos.slice(), anchor: null };
      try { if (h.result?.createAnchor) c.anchor = await h.result.createAnchor(); } catch (e) { log('anchor failed', e?.message ?? e); }
      S.corners.push(c);
      log(`corner ${S.corners.length}: ${c.pos.map(v => v.toFixed(3)).join(',')}${c.anchor ? ' (anchored)' : ''}`);
      if (S.corners.length === 3) { pin(); drawUi(); }
      S.dirty = true;
      return;
    }
    const [x, y] = S.reg.toBoard(h.pos);
    if (S.tool === 'measure') {
      if (!S.meas.a || S.meas.b) S.meas = { a: [x, y], b: null, mm: S.meas.mm };
      else { S.meas.b = [x, y]; log(`measure ${measured().toFixed(2)}" base to base (${S.meas.mm} mm)`); }
    } else if (S.tool === 'rings') { S.ring = [x, y]; log(`rings at ${x.toFixed(1)}, ${y.toFixed(1)}`); }
    S.dirty = true;
  });

  const pin = () => {
    const [a, b, c] = S.corners.map(k => k.pos);
    S.reg = registerBoard(a, b, c, { w: data.w, h: data.h, fit: S.fit });
    log(`board pinned: corners ${S.reg.edgeIn.toFixed(1)}" x ${S.reg.sideIn.toFixed(1)}" (table ${data.w} x ${data.h}), corner 2 off square ${S.reg.squareDeg.toFixed(1)}°`);
  };
  const measured = () => {
    const { a, b, mm } = S.meas;
    if (!a || !b) return null;
    return Math.max(0, Math.hypot(b[0] - a[0], b[1] - a[1]) - 2 * (mm * MM / 2));
  };

  // ---- meshes (board inches)
  const build = () => {
    for (const m of Object.values(S.meshes)) for (const x of [].concat(m)) freeMesh(G, x);
    const M = {};
    const W = data.w, H = data.h;
    M.table = [mesh(G, ribbon([[0, 0], [W, 0], [W, H], [0, H]], 0.3, true), [1, 1, 1, 0.9])];
    M.zones = data.zones.flatMap(z => [mesh(G, triangulate(z.poly), hex(z.color, 0.22)), mesh(G, ribbon(z.poly, 0.2, true), hex(z.color, 0.9))]);
    M.objectives = data.objectives.flatMap(o => [mesh(G, discTris(o.x, o.y, 20 * MM), [0.1, 0.1, 0.1, 0.95]), mesh(G, ribbon(ellipsePts(o.x, o.y, data.objRange), 0.15, true), [0.95, 0.76, 0, 0.95])]);
    M.terrain = data.pieces.flatMap(p => (p.cls === 'feature' ? [mesh(G, triangulate(p.poly), [0.37, 0.35, 0.29, 0.35])] : [mesh(G, ribbon(p.poly, 0.15, true), [0.95, 0.95, 0.9, 0.8])]));
    const st = data.steps[S.step];
    M.plan = (st?.units ?? []).flatMap(u => u.models.flatMap(m => {
      const fp = m.fp ?? { r: 0.63 }, rx = fp.r ?? fp.rx ?? fp.hw ?? 0.6, ry = fp.r ?? fp.ry ?? fp.hh ?? 0.6;
      const shape = fp.shape === 'rect' ? (() => { const t = ((m.rot ?? 0) * Math.PI) / 180, c = Math.cos(t), s = Math.sin(t); return [[-rx, -ry], [rx, -ry], [rx, ry], [-rx, ry]].map(([x, y]) => [m.x + x * c - y * s, m.y + x * s + y * c]); })() : ellipsePts(m.x, m.y, rx, ry, m.rot ?? 0, 28);
      return [mesh(G, triangulate(shape), hex(u.color, 0.5)), mesh(G, ribbon(shape, 0.08, true), [1, 1, 1, 0.9])];
    }));
    const tool = [];
    if (S.tool === 'measure' && S.meas.a) {
      const r = (S.meas.mm || 0) * MM / 2, pts = [S.meas.a, S.meas.b].filter(Boolean);
      for (const p of pts) tool.push(mesh(G, r ? ribbon(ellipsePts(p[0], p[1], r), 0.1, true) : discTris(p[0], p[1], 0.25), [0.95, 0.76, 0, 1]));
      if (S.meas.b) {
        const [a, b] = pts, d = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, ux = (b[0] - a[0]) / d, uy = (b[1] - a[1]) / d;
        tool.push(mesh(G, ribbon([[a[0] + ux * r, a[1] + uy * r], [b[0] - ux * r, b[1] - uy * r]], 0.12), [1, 1, 1, 1]));
      }
    }
    if (S.tool === 'rings' && S.ring) {
      RINGS.forEach((R, i) => tool.push(mesh(G, ribbon(ellipsePts(S.ring[0], S.ring[1], R, R, 0, 72), 0.18, true), i % 2 ? [1, 1, 1, 0.9] : [0.95, 0.76, 0, 0.95])));
      tool.push(mesh(G, discTris(S.ring[0], S.ring[1], 0.3), [0.95, 0.76, 0, 1]));
    }
    M.tool = tool;
    S.meshes = M;
    S.dirty = false;
  };
  // marks before the board is pinned (world)
  const reticle = mesh(G, ribbon(ellipsePts(0, 0, 0.9), 0.25, true), [0.95, 0.76, 0, 1]);
  const dot = mesh(G, discTris(0, 0, 0.5), [0.16, 0.47, 0.84, 1]);

  // ---- text
  const status = () => {
    const big = $('ar-big'), msg = $('ar-msg'), q = $('ar-q');
    $('ar-diag').innerHTML = !S.reg && S.data.diagram ? S.data.diagram(Math.min(S.corners.length, 2)) : '';
    if (!S.reg) {
      const n = S.corners.length;
      big.textContent = S.hit ? `Tap corner ${n + 1} of 3` : 'Find the table…';
      msg.textContent = !S.hit ? 'Move the tablet slowly over the table until the yellow ring sits on it.'
        : ['Corner 1 on the little map (match it by the zones and terrain).', 'Corner 2: along the 44" edge from corner 1.', 'Corner 3: down the 60" edge from corner 2.'][n];
      q.textContent = '';
      return;
    }
    const r = S.reg, off = Math.max(Math.abs(r.edgeIn / data.w - 1), Math.abs(r.sideIn / data.h - 1)) * 100;
    q.textContent = `Corners ${r.edgeIn.toFixed(1)}" × ${r.sideIn.toFixed(1)}" (table ${data.w}" × ${data.h}")${off > 2 ? ' — more than 2% out: tap the corners again?' : ''}${r.squareDeg > 3 ? ` · corner 2 is ${r.squareDeg.toFixed(0)}° off square` : ''} · ${S.fit ? 'board fitted to your corners' : 'board at true size'} · AR is about ±1"`;
    const at = S.hit ? S.reg.toBoard(S.hit.pos) : null;
    if (S.tool === 'measure') {
      const d = measured();
      big.textContent = d != null ? `${d.toFixed(1)}"` : S.meas.a && at ? `${Math.max(0, Math.hypot(at[0] - S.meas.a[0], at[1] - S.meas.a[1]) - (S.meas.mm || 0) * MM).toFixed(1)}"…` : 'Measure';
      msg.textContent = d != null ? `Base to base (${S.meas.mm ? `${S.meas.mm} mm bases` : 'points'}), about ±1". Tap again to start a new one.` : S.meas.a ? 'Tap the second base.' : 'Tap the first base (the middle of it).';
    } else if (S.tool === 'rings') {
      big.textContent = S.ring ? 'Rings 3" 6" 9" 12" 18" 24"' : 'Rings';
      msg.textContent = S.ring ? 'Yellow: 3", 9", 18"; white: 6", 12", 24". Tap to move them.' : 'Tap a spot (e.g. the edge of a base) for range rings around it.';
    } else {
      big.textContent = at ? `${at[0].toFixed(1)}" · ${at[1].toFixed(1)}"` : '–';
      msg.textContent = at ? 'Where the ring is: inches from the left (corner 1–4) edge and from the top (corner 1–2) edge, as on the Board map.' : 'Point at the table.';
    }
  };

  // ---- frames
  let stepShown = -1, lastUi = 0;
  const frame = (t, xf) => {
    if (!S.session) return;
    session.requestAnimationFrame(frame);
    const pose = xf.getViewerPose(refSpace);
    const hits = hitSource ? xf.getHitTestResults(hitSource) : [];
    if (hits.length) { const p = hits[0].getPose(refSpace).transform.position; S.hit = { pos: [p.x, p.y, p.z], result: hits[0] }; } else S.hit = null;
    // anchored corners follow ARCore's corrections; re-pin when they move
    let moved = false;
    for (const c of S.corners) {
      if (!c.anchor) continue;
      const p = xf.getPose(c.anchor.anchorSpace, refSpace)?.transform.position;
      if (p && Math.hypot(p.x - c.pos[0], p.y - c.pos[1], p.z - c.pos[2]) > 0.0005) { c.pos = [p.x, p.y, p.z]; moved = true; }
    }
    if (S.reg && (moved || S.reg.fitFlag !== S.fit)) { pin(); S.reg.fitFlag = S.fit; }
    if (S.dirty || stepShown !== S.step) { build(); stepShown = S.step; }
    const gl = G.gl, layer = session.renderState.baseLayer;
    gl.bindFramebuffer(gl.FRAMEBUFFER, layer.framebuffer);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.disable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(G.prog);
    if (pose) {
      for (const view of pose.views) {
        const vp = layer.getViewport(view);
        gl.viewport(vp.x, vp.y, vp.width, vp.height);
        const pv = mul4(view.projectionMatrix, view.transform.inverse.matrix);
        if (S.reg) {
          const mvp = mul4(pv, S.reg.model);
          for (const k of ['zones', 'terrain', 'objectives', 'plan']) if (S.layers[k]) for (const m of S.meshes[k] ?? []) drawMesh(G, m, mvp);
          for (const m of S.meshes.table ?? []) drawMesh(G, m, mvp);
          for (const m of S.meshes.tool ?? []) drawMesh(G, m, mvp);
        } else {
          for (const c of S.corners) drawMesh(G, dot, mul4(pv, markModel(c.pos)));
        }
        if (S.hit) drawMesh(G, reticle, mul4(pv, markModel(S.hit.pos)));
      }
    }
    if (t - lastUi > 100) { status(); lastUi = t; }
  };
  session.addEventListener('end', () => {
    S.session = null;
    document.body.classList.remove('ar-on');
    ov.remove();
    document.getElementById('ar-canvas')?.remove();
    log('session ended');
  });
  drawUi();
  status();
  session.requestAnimationFrame(frame);
  window.__ar = S; // for tests
  return S;
}

function ensureOverlay() {
  let ov = document.getElementById('ar-ov');
  if (!ov) {
    if (!document.getElementById('ar-css')) { const st = document.createElement('style'); st.id = 'ar-css'; st.textContent = OV_CSS; document.head.appendChild(st); }
    ov = document.createElement('div');
    ov.id = 'ar-ov';
    ov.innerHTML = overlayHtml();
    document.body.appendChild(ov);
  }
  return ov;
}
