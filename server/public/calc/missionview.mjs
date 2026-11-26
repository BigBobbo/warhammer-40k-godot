// Mission tab: secondary-card planner (matchup sheet, keep-ready list, hit
// list), objective plan, VP forecast for both players with what-ifs, and an
// in-game tracker (cards drawn / scored / discarded, score) that the forecast
// re-runs from. The simulation is forecast.mjs, run in the worker.
//
// app.js owns the shared state and calls in through initMission().

import { SECONDARIES, SECONDARY_BY_ID, FIXED_IDS, PRIMARIES, RULES, REAL_RATES, REAL_RATES_SOURCE } from './missions-11e.mjs';
import { armyProfile, cardDead, POSITION_CARDS, RATING, MODEL } from './forecast.mjs';
import { abilitiesOf, armyData, fmtDataDate, earlyArrival, armyIntel } from './adapter.mjs';
import { boardContext, boardPlans, boardTrees, boardSetupInfo, boardTurnDone, boardNewGame } from './boardview.mjs';
import { evaluate as evalTree } from './plantree.mjs';
import { cardFace } from './cardface.mjs';
import { layoutLetter, objectiveSides, LAYOUTS, DEPLOYMENTS, dispositionName } from './board.mjs';
import { unitFacts as positionFacts, planWarnings, killPressure, threatOptions, ENGAGE } from './planeval.mjs';
import * as PT from './playtools.mjs';

let ctx = null;            // { state, esc, seg, chip }
const LS_KEY = 'w40k_calc_mission_v1';
const other = (p) => (p === 'A' ? 'B' : 'A');
const KILL_RATES = [[0.8, 'Low'], [1.3, 'Even'], [2, 'High']];
const ACTION_P = [[0.9, 'Easy'], [0.7, 'OK'], [0.45, 'Hard']];
// who is the stronger player: "+" wins about 64% of otherwise even games, "++" about 77%
const EDGES = [[-0.43, 'Opp ++'], [-0.2, 'Opp +'], [0, 'Even'], [0.2, 'Me +'], [0.43, 'Me ++']];


export function initMission(c) {
  ctx = c;
  try {
    const saved = JSON.parse(localStorage.getItem(LS_KEY) ?? 'null');
    if (saved) {
      Object.assign(ms(), saved);
      // saves from before 1.92: keep a kill rate the player chose by hand, else use the calculator's
      if (!saved.killAuto) ms().killAuto = { A: (saved.killRate?.A ?? 1.3) === 1.3, B: (saved.killRate?.B ?? 1.3) === 1.3 };
      if (saved.edge == null) ms().edge = 0;
      // panel memory moved to one map in 1.93
      ms().open ??= { ...(saved.openAssume ? { 'mission-assume': true } : {}), ...(saved.openBasis ? { 'mission-basis': true } : {}) };
    }
  } catch { /* fresh */ }
  // table tools (1.97): clock, command points, score sheet, undo — added to what was saved, nothing rewritten
  const m = ms();
  m.clock = { ...PT.newClock(), ...(m.clock ?? {}) };
  m.undo = Array.isArray(m.undo) ? m.undo : [];
  m.table ??= false;
  m.awake ??= true;
  PT.ensureGame(m.game, { fresh: !inProgress() });
  migratePlanSides(m);
}

function ms() {
  const s = ctx.state;
  s.mission ??= {
    me: 'A', first: null, battleReady: { A: true, B: true },
    modes: { A: { mode: 'tactical', fixed: [] }, B: { mode: 'tactical', fixed: [] } },
    killRate: { A: 1.3, B: 1.3 }, actionP: { A: 0.7, B: 0.7 }, rate: { A: {}, B: {} }, est: { A: {}, B: {} },
    killAuto: { A: true, B: true },   // units destroyed per turn from the calculator (false = the manual rate above)
    edge: 0,                 // who is the stronger player: the log kill-rate edge of "me" (0 = even)
    plans: {}, game: newGame(), sheetSide: null, cardOpen: null,
    source: 'grid',          // objectives / positions from the grid, or a board plan (its index)
    enemyFrom: 'board',      // enemy positions from the board plan, or the grid toggles
  };
  return s.mission;
}
function newGame() {
  return PT.ensureGame({ round: 1, next: null, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } }, { fresh: true });
}
// before a change to the tracker: keep what it was (Undo)
let lastTyped = { label: '', at: 0 };
function remember(label, typed = false) {
  const m = ms();
  // a number typed digit by digit is one change, not one per key
  if (typed && lastTyped.label === label && Date.now() - lastTyped.at < 4000 && m.undo.length) { lastTyped.at = Date.now(); return; }
  lastTyped = typed ? { label, at: Date.now() } : { label: '', at: 0 };
  PT.pushUndo(m.undo, { game: m.game, first: m.first }, label);
}
const turnOf = () => ms().game.next ?? ms().first ?? 'A';
const isOpening = () => { const g = ms().game; return g.round === 1 && !g.turnsDone && !g.over; };
const totalVp = (X) => { const m = ms(), g = m.game; return g[X].primary + g[X].secondary + (m.battleReady[X] ? RULES.battleReady : 0); };
function persist() {
  const m = ms();
  const { result, levers, busy, compare, pairs, modeCompare, handOpen, tableNotice, show, ...keep } = m;
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
  // an expansion objective is on the side of the player whose TERRITORY it is in (board.mjs objectiveSides)
  const out = objectiveSides(l, bc.deployment, bc.zoneA).map(o => ({ ...o, label: o.cls === 'home' ? `${o.side} home` : o.cls === 'central' ? 'Centre' : `${o.side}-side` }));
  const order = (o) => (o.cls === 'home' ? (o.side === 'A' ? 0 : 4) : o.cls === 'central' ? 2 : o.side === 'A' ? 1 : 3);
  out.sort((a, b) => order(a) - order(b));
  // number duplicates ("Centre 1", "A-side 2")
  const counts = {};
  for (const o of out) counts[o.label] = (counts[o.label] ?? 0) + 1;
  const seen = {};
  for (const o of out) if (counts[o.label] > 1) o.label += ` ${(seen[o.label] = (seen[o.label] ?? 0) + 1)}`;
  return out;
}

/** The plan a layout starts with: each player holds its home objective, and from round 2 the expansion objective in its territory. */
function defaultPlan(objs) {
  const p = {};
  for (let r = 1; r <= RULES.rounds; r++) {
    p[r] = {};
    for (const o of objs) p[r][o.id] = o.cls === 'home' ? o.side : o.cls === 'exp' && r >= 2 ? o.side : 'c';
  }
  return p;
}

function plan() {
  const m = ms();
  const l = boardContext().layout;
  if (!l) return {};
  if (!m.plans[l.id]) m.plans[l.id] = defaultPlan(objectives());
  return m.plans[l.id];
}

/**
 * Before 1.101 an expansion objective's side was "the nearer home objective", which is the wrong
 * player's territory in 18 of the 45 layouts. A stored plan that is still the old starting plan
 * (never edited) becomes the new starting plan; a plan the player edited is left as it is.
 */
function migratePlanSides(m) {
  if (m.sidesV === 2) return;
  let changed = 0;
  for (const [id, p] of Object.entries(m.plans ?? {})) {
    const l = LAYOUTS.find(x => x.id === id);
    if (!l) continue;
    const dep = DEPLOYMENTS[l.deployment];
    for (const zoneA of [1, 2]) {
      const old = defaultPlan(objectiveSides(l, dep, zoneA, { byNearestHome: true }));
      if (JSON.stringify(old) !== JSON.stringify(p)) continue;
      const now = defaultPlan(objectiveSides(l, dep, zoneA));
      if (JSON.stringify(now) !== JSON.stringify(p)) { m.plans[id] = now; changed++; }
      break;
    }
  }
  m.sidesV = 2;
  if (changed) console.log(`[mission] ${changed} starting plan(s) updated: expansion objectives now follow the territory they are in`);
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
    early: { A: earlyArrival(ctx.state.armies.A)?.name ?? null, B: earlyArrival(ctx.state.armies.B)?.name ?? null },
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
      const cell = ((table[atk] ??= {})[def] ??= { shoot: 0, fight: 0, sMu: 0, sSd: 0, fMu: 0, fSd: 0, W: 0 });
      const sh = phase === 'shooting';
      cell[sh ? 'shoot' : 'fight'] = v.pWipe ?? 0;        // P(destroyed by this unit alone)
      cell[sh ? 'sMu' : 'fMu'] = v.meanWounds ?? 0;       // mean wounds removed
      cell[sh ? 'sSd' : 'fSd'] = v.sdWounds ?? 0;
      cell.W = v.totalWounds ?? cell.W;
    }
    ms().pairs = { sig, table };
    pairsPending = false;
    refresh();
    scheduleForecast();
  });
  return false;
}

// ---- for the matchup brief (briefview.mjs) and the event card (eventview.mjs)
export function matchupData() {
  const m = ms(), st = ctx.state;
  if (st.armies.A && st.armies.B) ensurePairs();
  const ready = m.pairs?.table && m.pairs.sig === pairSig();
  return {
    me: m.me, pairs: ready ? m.pairs.table : null, result: m.result ?? null, busy: !!m.busy,
    dead: (X) => SECONDARIES.filter(c => cardDead(c.id, profileOf(other(X)).profile)).map(c => c.name),
    hitList: (X) => hitListHtml(X),
  };
}
export function registerHost(id, fn) { HOSTS[id] = fn; }
/**
 * For a chance branch on the Board: the chance that unit atkTk destroys unit defTk on its own ({ shoot, fight }),
 * from the unit-vs-unit odds of the two lists (null while they are being worked out; asking starts the work).
 */
export function pairWipe(atkTk, defTk) {
  const st = ctx.state;
  if (!st.armies.A || !st.armies.B) return null;
  const m = ms();
  if (!ensurePairs()) return null;
  const c = m.pairs.table[atkTk]?.[defTk];
  return c ? { shoot: c.shoot ?? 0, fight: c.fight ?? 0 } : { shoot: 0, fight: 0 };
}
/**
 * Models lost in the game on the tracker, by battle round (see app.js lossesOf): each change is kept with the
 * round it happened in, so a Board turn shows the models left by its round. change: { side, unit, unitName, group,
 * groupName, field: 'count' | 'woundsLeftFirst', delta (±1), count, W, round } | { side, unit, unitName, reset }
 * | { side, clearSide }. Each change can be taken back with the tracker's Undo.
 */
export function missionLoss(c) {
  const m = ms(), g = m.game;
  const L = (g.lossLog ??= { A: {}, B: {} });
  L[c.side] ??= {};
  if (c.clearSide) { if (Object.keys(L[c.side]).length) { console.log(`[mission] models left: ${c.side}'s list changed, its record is cleared`); L[c.side] = {}; persist(); } return; }
  if (c.reset) {
    remember(`${c.unitName}: back to full strength`);
    delete L[c.side][c.unit];
    console.log(`[mission] models left: ${c.side} ${c.unitName} back to full strength (every round)`);
    persist();
    return;
  }
  const R = Math.max(0, Math.round(c.round ?? g.round ?? 1));
  const U = (L[c.side][c.unit] ??= {}), G = (U[c.group] ??= {});
  const upTo = (r) => Object.entries(G).filter(([k]) => Number(k) <= r);
  if (c.field === 'count') {
    const left = Math.max(0, c.count - upTo(R).reduce((a, [, e]) => a + (e.lost ?? 0), 0));
    if (c.delta < 0) {
      if (left <= 0) return;
      remember(`${c.unitName}: one ${c.groupName} lost (round ${R})`);
      const e = (G[R] ??= {}); e.lost = (e.lost ?? 0) + 1;
    } else {
      if (left >= c.count) return;
      // a model back: the most recent loss at or before this round is taken back
      const back = upTo(R).filter(([, e]) => (e.lost ?? 0) > 0).sort((a, b) => Number(b[0]) - Number(a[0]))[0];
      if (!back) return;
      remember(`${c.unitName}: one ${c.groupName} back`);
      back[1].lost -= 1;
      if (!back[1].lost) delete back[1].lost;
    }
    console.log(`[mission] models left: ${c.side} ${c.unitName} ${c.groupName} ${left} -> ${left + (c.delta < 0 ? -1 : 1)} at round ${R}`);
  } else {
    const wlAt = (r) => { const e = upTo(r).filter(([, x]) => x.wl != null).sort((a, b) => Number(b[0]) - Number(a[0]))[0]; return e ? e[1].wl : c.W; };
    const before = wlAt(R), after = Math.max(1, Math.min(c.W, before + c.delta));
    if (after === before) return;
    remember(`${c.unitName}: ${c.groupName} on ${after}W (round ${R})`);
    const e = (G[R] ??= {}); e.wl = after;
    const inherited = (() => { const p = Object.entries(G).filter(([k, x]) => Number(k) < R && x.wl != null).sort((a, b) => Number(b[0]) - Number(a[0]))[0]; return p ? p[1].wl : c.W; })();
    if (after === inherited) delete e.wl;
    console.log(`[mission] models left: ${c.side} ${c.unitName} ${c.groupName} wounds ${before} -> ${after} at round ${R}`);
  }
  for (const [k, e] of Object.entries(G)) if (!Object.keys(e).length) delete G[k];
  if (!Object.keys(G).length) delete U[c.group];
  if (!Object.keys(U).length) delete L[c.side][c.unit];
  persist();
}
export function missionNewGame() { ctx.autoSave?.('a new game'); const m = ms(); remember('new game'); m.game = newGame(); m.first = null; m.savedId = null; m.tab = m.table ? 'play' : 'plan'; persist(); boardNewGame(); }
/** The game on the tracker as the Board's live table needs it: the round, whose turn, the phase, each player's hand. */
export function missionNow() {
  const g = ms().game;
  return { round: g.round, turn: turnOf(), phase: g.phase ?? 'command', started: inProgress(), over: !!g.over, hand: { A: [...g.A.hand], B: [...g.B.hand] } };
}
/**
 * Weigh moves with the forecast (the Board's "Your turn"): the rest of the game from the tracker's state, once
 * for the table as it stands (base) and once for each variant - the same plan with one or more units moved.
 * base / variants[].plan: a plan in boardPlans() shape. Run in a worker of its own; a newer call drops the older.
 * -> Promise<{ base: result, variants: { [key]: result } } | null (dropped, or no forecast possible)>
 */
export const MOVE_TRIALS = 1500;
let moveWorker = null, moveReq = 0;
export function moveForecasts(base, variants) {
  return new Promise((resolve) => {
    const P0 = forecastParams({ boardSteps: base, trials: MOVE_TRIALS });
    if (!P0 || typeof Worker === 'undefined') { resolve(null); return; }
    const vs = variants.map(v => ({ key: v.key, P: forecastParams({ boardSteps: v.plan, trials: MOVE_TRIALS }) }));
    const id = ++moveReq;
    moveWorker ??= new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    const t0 = Date.now();
    const onMsg = (ev) => {
      if (ev.data.id !== id) { if (ev.data.id > id) { moveWorker.removeEventListener('message', onMsg); resolve(null); } return; }
      moveWorker.removeEventListener('message', onMsg);
      if (ev.data.error) { console.log(`[mission] move forecasts failed: ${ev.data.error}`); resolve(null); return; }
      console.log(`[mission] move forecasts: ${vs.length} variants x ${MOVE_TRIALS} games in ${Date.now() - t0} ms`);
      resolve({ base: ev.data.base, variants: Object.fromEntries(ev.data.variants.map(v => [v.key, v.result])) });
    };
    moveWorker.addEventListener('message', onMsg);
    moveWorker.postMessage({ id, forecast: { base: P0, variants: vs } });
  });
}
/** The unit-vs-unit odds of the two lists (null while they are being worked out; asking starts the work). */
export function pairTable() {
  const st = ctx.state;
  if (!st.armies.A || !st.armies.B) return null;
  return ensurePairs() ? ms().pairs.table : null;
}
/** The mission state (for a saved game) and the saved game it came from. */
export const missionState = () => ms();
export function missionSetSavedId(id) { ms().savedId = id; persist(); }
/**
 * Put a saved game on the tracker (games.mjs missionPart): its tracker, first turn, choices, objective plan and
 * clock. Undo starts empty; the forecast is worked out again. Opens the Play view.
 */
export function missionLoadGame(part, id, fields) {
  const m = ms();
  for (const k of fields) if (part[k] !== undefined) m[k] = JSON.parse(JSON.stringify(part[k]));
  m.clock = { ...PT.newClock(), ...(m.clock ?? {}) };
  PT.ensureGame(m.game);
  m.undo = []; m.savedId = id; m.tab = 'play';
  m.result = null; m.levers = []; m.compare = []; m.modeCompare = null;
  toTop = true;
  persist();
  scheduleForecast();
}
export const missionInProgress = () => inProgress();
/** The score on the tracker (Battle Ready included), for the event card. */
export const missionScore = () => ({ A: totalVp('A'), B: totalVp('B'), over: !!ms().game.over, started: inProgress() });

// units destroyed per turn, from the calculator (null until the unit-vs-unit odds are in)
function autoKill() {
  const m = ms(), st = ctx.state;
  if (!m.pairs?.table || m.pairs.sig !== pairSig()) return null;
  const keys = (X) => st.armies[X].units.map(u => `${X}:${u.key}`);
  return { A: killPressure(keys('A'), keys('B'), m.pairs.table), B: killPressure(keys('B'), keys('A'), m.pairs.table) };
}
// the calculator's results as the forecast wants them: share of each target's wounds each unit removes
function killFracs() {
  const m = ms(), st = ctx.state;
  if (!m.pairs?.table || m.pairs.sig !== pairSig()) return null;
  const out = {};
  for (const X of ['A', 'B']) {
    const Y = other(X);
    out[X] = {};
    for (const a of st.armies[X].units) {
      const row = (out[X][a.name] = {});
      for (const d of st.armies[Y].units) {
        const pr = m.pairs.table[`${X}:${a.key}`]?.[`${Y}:${d.key}`];
        if (pr && pr.W > 0) row[d.name] = Math.min(1, Math.max(pr.sMu ?? 0, pr.fMu ?? 0) / pr.W);
      }
    }
  }
  return out;
}
function killRateOf(X) {
  const m = ms();
  if (m.killAuto?.[X] === false) return { rate: m.killRate[X], from: 'you' };
  const auto = autoKill();
  return auto ? { rate: auto[X].rate, from: 'calc', raw: auto[X].raw } : { rate: 1.3, from: 'wait' };
}

/** The forecast's board model for plan `vi`: units per step with measured facts, and what each unit threatens. */
function boardModel(vi, given = null) {
  const m = ms(), g = geo();
  // (given: a plan in boardPlans() shape that is not on the Board - a move being weighed, moveForecasts)
  const plan = given ?? boardPlans()[vi];
  if (!g || !plan) return null;
  const steps = plan.steps;
  const rounds = {}, threats = {};
  // step 0 = deployment, step r = positions after that army's move in battle round r (the last step carries on)
  const stepFor = (r) => steps[Math.min(r, steps.length - 1)];
  const used = (st, X) => st[X].length && (X === m.me || m.enemyFrom === 'board');
  for (let r = 0; r <= RULES.rounds; r++) {
    const st = stepFor(r);
    rounds[r] = {};
    for (const X of ['A', 'B']) rounds[r][X] = used(st, X) ? st[X].map(u => ({ name: u.name, f: positionFacts(u, X, g) })) : null;
    if (r === 0 || !m.pairs?.table) continue;
    threats[r] = {};
    for (const X of ['A', 'B']) {
      const Y = other(X);
      const prevSt = stepFor(r - 1);
      if (!used(st, X) || !used(st, Y)) continue;
      // X attacks in round r from its round-r positions; the targets have already moved this
      // round (cur: they went first) or are still where round r - 1 left them (prev)
      // (a Lone Operative, and infantry without guns that can be Hidden where it stands, must be approached: planeval detectRange)
      const opts = (targets) => threatOptions(st[X], targets, m.pairs.table, 3, g?.pieces ?? null);
      threats[r][X] = { cur: opts(st[Y]), prev: used(prevSt, Y) ? opts(prevSt[Y]) : opts(st[Y]) };
    }
  }
  return { rounds, threats, warnings: planWarnings(steps, g), stepsPlanned: steps.length, name: plan.name };
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
  return g.round > 1 || !!g.over || !!g.log?.length || ['A', 'B'].some(X => g[X].hand.length || g[X].used.length || g[X].primary || g[X].secondary);
}

export function forecastParams(over = {}) {
  const m = ms();
  const bc = boardContext();
  const pa = profileOf('A'), pb = profileOf('B');
  if (!pa || !pb || !bc.layout) return null;
  const g = m.game;
  const live = inProgress();
  const vi = over.boardPlan === undefined ? sourcePlan() : over.boardPlan;
  // a board plan made for going first (or second) is forecast that way, until the first turn is known
  const tag = vi == null ? null : boardPlans()[vi]?.when ?? null;
  const first = m.first ?? (tag ? (tag === 'first' ? m.me : other(m.me)) : null) ?? (live ? 'A' : null);
  const fracs = killFracs();
  const player = (X) => ({
    mission: bc.missions[X], mode: over.mode?.[X]?.mode ?? m.modes[X].mode, fixed: over.mode?.[X]?.fixed ?? m.modes[X].fixed,
    // units destroyed: the player's own rate, else from the calculator (null = use fracs below)
    army: (X === 'A' ? pa : pb).profile, killRate: m.killAuto?.[X] === false ? m.killRate[X] : (fracs ? null : 1.3), killMul: over.killMul?.[X] ?? 1, actionP: m.actionP[X],
    rate: m.rate[X], vpEst: m.est?.[X] ?? {}, battleReady: m.battleReady[X],
    // (destroyed: this player's OWN units that are gone, by name — the forecast removes them from this army)
    start: live ? { hand: g[X].hand, used: g[X].used, primary: g[X].primary, secondary: g[X].secondary, destroyed: g[X].destroyed, fixedVp: g[X].fixedVp ?? {} } : null,
  });
  const next = g.next ?? first ?? 'A';
  return {
    players: { A: player('A'), B: player('B') },
    objectives: objectives().map(({ id, cls, side }) => ({ id, cls, side })),
    plan: over.plan ?? plan(), first,
    boardPlan: over.boardSteps ? boardModel(null, over.boardSteps) : vi == null ? null : boardModel(vi), fracs,
    startRound: g.over ? RULES.rounds + 1 : live ? g.round : 1, startTurn: live && first && !g.over ? (next === first ? 0 : 1) : 0,
    // cards the player whose turn it is has already drawn this turn (the forecast draws the rest)
    startDrawn: live ? Math.min(RULES.drawPerTurn, g.drawn ?? 0) : 0,
    // who is the stronger player (0 = even): the forecast's edge is A's
    edge: (m.me === 'A' ? 1 : -1) * (m.edge ?? 0),
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
  out.push({ key: 'kill', label: 'Trade harder: kill 50% more', over: { killMul: { [me]: 1.5 } } });
  out.push({ key: 'safe', label: 'Play safer: lose 30% fewer units', over: { killMul: { [opp]: 0.7 } } });
  return out.map(l => ({ key: l.key, label: l.label, P: forecastParams({ ...l.over, trials: 1500 }) }));
}

// Fixed or Tactical? A choice made before the battle: my secondaries as Tactical and as
// each pair of Fixed cards that has targets in this enemy army (worked out on the Cards view).
// (the table does not depend on the mode chosen now: its inputs are everything else)
function modeSig() {
  const P = forecastParams({ trials: 0, mode: { [ms().me]: { mode: 'tactical', fixed: [] } } });
  return P ? JSON.stringify(P) : '';
}
const modeWanted = () => ms().tab === 'cards' && !inProgress() && !!profileOf(other(ms().me))?.profile;
function modeParams() {
  const m = ms(), me = m.me;
  if (!modeWanted() || m.modeCompare?.sig === modeSig()) return [];
  const enemy = profileOf(other(me)).profile;
  const live = FIXED_IDS.filter(id => !cardDead(id, enemy));
  const out = [{ key: 'mode:tactical', label: 'Tactical', P: forecastParams({ mode: { [me]: { mode: 'tactical', fixed: [] } }, trials: 1500 }) }];
  for (let i = 0; i < live.length; i++) for (let j = i + 1; j < live.length; j++) {
    out.push({ key: `mode:${live[i]}+${live[j]}`, label: `Fixed: ${SECONDARY_BY_ID[live[i]].name} + ${SECONDARY_BY_ID[live[j]].name}`, P: forecastParams({ mode: { [me]: { mode: 'fixed', fixed: [live[i], live[j]] } }, trials: 1500 }) });
  }
  return out;
}

// The Play view shows the headline and the advice on the cards in hand. It does not show the what-ifs or the
// plan comparison, so a change made there (a score, a card, a turn) runs the forecast alone, with fewer
// simulated games: about 1,000 instead of about 14,000 per tap. Plan and Cards get the full run.
export const PLAY_TRIALS = 1000;
const liteRun = () => ms().tab === 'play' && !forceFull;
let forceFull = false;     // a full run asked for from outside the Plan view (the Board's branch map)
let compareSigs = {};     // plan key -> the inputs its row was worked out from (a board plan changed since: no value)
let runLite = false;      // the run in progress is a Play-view run
let lastSig = '';         // the inputs of the last run asked for
let lastFull = '';        // the inputs of the last full run (what-ifs and plan comparison included)
let worker = null, reqId = 0, timer = null;
let planNotes = {};   // plan key -> "3 of 8 units placed" for board plans that miss part of my army
let runModes = null;  // the inputs of the Fixed / Tactical table the run in progress works out (null: it has none)
export function scheduleForecast(sig = null) {
  clearTimeout(timer);
  // table mode: tracker only (no forecast is worked out, nothing to show it)
  if (ms().table) { ms().busy = false; return; }
  // what this run is for: the next render does not ask for the same run again
  if (sig == null) { const P0 = forecastParams({ trials: 0 }); sig = P0 ? JSON.stringify(P0) : ''; }
  lastSig = sig;
  if (!liteRun()) lastFull = sig;
  ms().busy = true;
  timer = setTimeout(runForecast, 150);
}

/** The Board's branch map: work out every path's win chance now (a full run with the plan comparison). */
export function forecastBranches() {
  if (ms().table) return false;
  forceFull = true;
  scheduleForecast();
  return true;
}

/**
 * My win chance on each board path from the last plan comparison, by variant index, only for the paths whose
 * forecast inputs are still the same (a path moved since then has none). busy: a run is going on.
 */
export function branchWins() {
  const m = ms(), wins = {};
  for (const c of m.compare ?? []) {
    if (!c.result || !String(c.key).startsWith('plan')) continue;
    const vi = Number(c.key.slice(4));
    const P = forecastParams({ boardPlan: vi, trials: 1500 });
    if (P && compareSigs[c.key] === JSON.stringify(P)) wins[vi] = m.me === 'A' ? c.result.pWinA : c.result.pWinB;
  }
  return { wins, busy: !!m.busy, table: !!m.table };
}
function runForecast() {
  // unit-vs-unit odds from the calculator: kill rates, and what each unit threatens on a board plan
  if (ctx.state.armies.A && ctx.state.armies.B) ensurePairs();
  const lite = liteRun();
  forceFull = false;
  const P = forecastParams(lite ? { trials: PLAY_TRIALS } : {});
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
      const modes = ev.data.variants.filter(v => String(v.key).startsWith('mode:'));
      // a Play-view run has no what-ifs and no plan comparison: the ones on the Plan view stay until its next full run
      if (!runLite) {
        mm.levers = ev.data.variants.filter(v => !v.compare && !String(v.key).startsWith('mode:'));
        mm.compare = ev.data.variants.filter(v => v.compare);
      }
      if (modes.length) mm.modeCompare = { sig: runModes, rows: modes };
      mm.busy = false;
      const r = mm.result;
      console.log(`[calc] forecast: A ${r.A.mean.toFixed(1)} (${r.A.p10}-${r.A.p90}) vs B ${r.B.mean.toFixed(1)} (${r.B.p10}-${r.B.p90}), A wins ${(r.pWinA * 100).toFixed(0)}%`);
      refresh();
    };
  }
  m.busy = true;
  runLite = lite;
  if (lite) { runModes = null; worker.postMessage({ id: reqId, forecast: { base: P, variants: [] } }); return; }
  // a board plan only knows the units placed on it: say so when part of my army is missing
  const nMine = ctx.state.armies[m.me]?.units.length ?? 0;
  // a unit inside a transport counts as placed (it is on the battlefield, embarked)
  const placed = (p) => new Set(p.steps.flatMap(st => [...st[m.me].map(u => u.name), ...(st.embarked?.[m.me] ?? []).map(e => e.name)])).size;
  const compare = [{ key: 'grid', label: 'Objective grid', P: forecastParams({ boardPlan: null, trials: 1500 }) },
    ...boardPlans().map(p => ({ key: `plan${p.index}`, label: `Board: ${p.name}`, note: placed(p) < nMine ? `${placed(p)} of ${nMine} units placed` : '', P: forecastParams({ boardPlan: p.index, trials: 1500 }) }))];
  planNotes = Object.fromEntries(compare.map(c => [c.key, c.note ?? '']));
  compareSigs = Object.fromEntries(compare.map(c => [c.key, JSON.stringify(c.P)]));
  const modes = modeParams();
  runModes = modes.length ? modeSig() : null;
  worker.postMessage({ id: reqId, forecast: { base: P, variants: [...leverParams(), ...modes, ...compare.map(({ note, ...c }) => ({ ...c, compare: true }))] } });
}

// the parts of the page that follow the forecast: re-drawn in place when a run finishes
const HOSTS = {
  'fc-mini': () => miniHtml(), 'mission-forecast': () => heroHtml(), 'mission-more': () => moreHtml(), 'mission-rounds': () => roundsHtml(),
  'mission-basis-host': () => basisHtml(), 'mission-cards': () => cardsHtml(), 'mission-cards-side': () => cardsSideHtml(),
  'mission-mode-host': () => modeHtml(), 'hand-A': () => handHtml('A'), 'hand-B': () => handHtml('B'),
};
function refresh() {
  for (const [id, html] of Object.entries(HOSTS)) {
    const host = document.getElementById(id);
    if (host) host.innerHTML = html();
  }
}

// ---------------------------------------------------------------------------
// Views

const TABS = [['plan', 'Plan'], ['cards', 'Cards'], ['play', 'Play']];
// collapsible panels keep their state while the page re-draws (app.js records the toggles)
const isOpen = (k, dflt = false) => ms().open?.[k] ?? dflt;

export function missionView() {
  const st = ctx.state, m = ms();
  if (!st.armies.A || !st.armies.B) return '<p class="hint">Load both armies first.</p>';
  // table mode: the tracker only
  const tab = m.table ? 'play' : TABS.some(t => t[0] === m.tab) ? m.tab : 'plan';
  const closed = m.tableNotice === 'attack' ? 'The calculator is' : m.tableNotice === 'board' ? 'The board planner is' : null;
  const top = m.table ? `<div class="seg table-top"><button class="on" disabled id="table-flag">Play · table mode</button><button data-action="mission-table" id="table-leave">Leave table mode</button></div>
      ${closed ? `<div class="tiny table-locked" id="table-locked">${closed} closed in table mode.</div>` : ''}` : ctx.seg('mission-tab', tab, TABS);
  return `<div class="mission-top" id="mission-top">${top}<div id="fc-mini">${miniHtml()}</div></div>
    ${tab === 'plan' ? planView() : tab === 'cards' ? cardsView() : playView()}${showHtml()}`;
}

// ---- shown to the opponent: the score (tournament packs: a private score sheet "holds no weight", the score must be
// "mutually accessible"), and a secondary card drawn at random where they can see it. No forecast, no odds.
function showHtml() {
  const m = ms(), g = m.game, esc = ctx.esc, sh = m.show;
  if (!sh) return '';
  const flip = m.flip ? ' flip' : '';
  const bar = `<div class="show-bar"><button class="btn" data-action="mission-show-flip" id="show-flip">↻ Turn to face ${m.flip ? 'me' : 'them'}</button><span class="grow"></span><button class="icon-btn" data-action="mission-show-close" id="show-close" aria-label="Close">✕</button></div>`;
  if (sh.draw) {
    const c = SECONDARY_BY_ID[sh.draw.id];
    const more = sh.draw.X === turnOf() && (g.drawn ?? 0) < RULES.drawPerTurn;
    return `<div class="show-layer" id="show-draw" role="dialog" aria-modal="true"><div class="show-inner${flip}">${bar}
      <div class="show-head">${esc(sh.draw.X)} · ${esc(ctx.state.armies[sh.draw.X]?.faction ?? '')} drew at random</div>
      ${c ? cardFace(c, { esc }) : ''}
      <div class="tiny muted" style="margin-top:6px">From the ${sh.draw.left} cards left in the deck (${esc(sh.draw.at)}).</div>
      <div class="row" style="gap:8px;margin-top:10px">${more ? `<button class="btn" data-action="mission-draw-random" data-side="${sh.draw.X}" id="show-draw-again">🎲 Draw another</button>` : ''}<button class="btn primary grow" data-action="mission-show-close">Done</button></div></div></div>`;
  }
  const s = PT.scoreSheet(g, RULES.rounds);
  const side = (X) => {
    const total = g[X].primary + g[X].secondary + (m.battleReady[X] ? RULES.battleReady : 0);
    return `<div class="show-side" data-show-side="${X}"><div class="show-army" style="color:var(--side-${X.toLowerCase()}-ink)">${X} · ${esc(ctx.state.armies[X].faction)}</div>
      <div class="show-total" id="show-total-${X}">${total}<small> VP</small></div>
      <div class="small">Primary <b>${g[X].primary}</b> · Secondary <b>${g[X].secondary}</b>${m.battleReady[X] ? ` · Battle Ready <b>${RULES.battleReady}</b>` : ''} · CP <b>${g[X].cp ?? 0}</b></div>
      ${m.modes[X].mode === 'tactical' ? `<div class="tiny" style="margin-top:4px">In hand: ${g[X].hand.length ? g[X].hand.map(id => `<b>${esc(SECONDARY_BY_ID[id]?.name ?? id)}</b>`).join(', ') : '<span class="muted">none</span>'}</div>
        <div class="tiny muted">Scored or discarded: ${g[X].used.length}</div>`
        : `<div class="tiny" style="margin-top:4px">Fixed: ${(m.modes[X].fixed ?? []).map(id => `<b>${esc(SECONDARY_BY_ID[id]?.name ?? id)}</b> ${g[X].fixedVp?.[id] ?? 0}`).join(' · ')}</div>`}</div>`;
  };
  const cell = (v) => (v ? String(v) : '–');
  return `<div class="show-layer" id="show-score" role="dialog" aria-modal="true"><div class="show-inner${flip}">${bar}
    <div class="show-head">${g.over ? 'Battle over' : `Battle round ${g.round} · ${esc(turnOf())}'s turn`}</div>
    <div class="show-sides">${side('A')}${side('B')}</div>
    <table class="dist scoresheet" style="margin-top:10px"><thead><tr><th>Round</th><th>A prim.</th><th>A sec.</th><th>B prim.</th><th>B sec.</th></tr></thead><tbody>
      ${s.rows.map(r => `<tr${r.round === g.round && !g.over ? ' class="cur"' : ''}><td>${r.round}</td><td>${cell(r.A.primary)}</td><td>${cell(r.A.secondary)}</td><td>${cell(r.B.primary)}</td><td>${cell(r.B.secondary)}</td></tr>`).join('')}
      <tr class="total"><td>Total</td><td>${cell(s.total.A.primary)}</td><td>${cell(s.total.A.secondary)}</td><td>${cell(s.total.B.primary)}</td><td>${cell(s.total.B.secondary)}</td></tr></tbody></table>
    ${(g.strats ?? []).some(s => s.round === g.round) ? `<div class="small" style="margin-top:8px" id="show-strats"><b>Stratagems this round:</b> ${(g.strats ?? []).filter(s => s.round === g.round).map(s => `${esc(s.side)} ${esc(s.name)} (${s.cp}CP)`).join(' · ')}</div>` : ''}
    <div class="tiny muted" style="margin-top:6px">The score as entered on this phone, for both players to check.</div></div></div>`;
}
/** A secondary card at random from what is left of X's deck (crypto random), shown full screen. */
function drawRandom(X) {
  const m = ms(), g = m.game;
  const deck = SECONDARIES.map(c => c.id).filter(id => !g[X].hand.includes(id) && !g[X].used.includes(id));
  if (!deck.length) return false;
  const r = new Uint32Array(1);
  (globalThis.crypto ?? window.crypto).getRandomValues(r);
  const id = deck[r[0] % deck.length];
  remember(`${SECONDARY_BY_ID[id]?.name ?? 'card'} drawn`);
  g[X].hand.push(id);
  if (X === (g.next ?? m.first ?? 'A')) g.drawn = (g.drawn ?? 0) + 1;
  m.show = { draw: { X, id, left: deck.length, at: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) } };
  console.log(`[mission] ${X} drew ${id} at random from ${deck.length} cards`);
  return true;
}

// the running clock, for the pinned line
function clockMiniText(now = Date.now()) {
  const c = ms().clock;
  if (c.mode === 'round' && PT.roundStarted(c)) return `⏱ ${PT.fmtClock(PT.roundLeft(c, now))}`;
  if (c.mode === 'chess' && PT.chessStarted(c)) { const X = c.running ?? turnOf(); return `⏱ ${X} ${PT.fmtClock(PT.chessLeft(c, X, now))}`; }
  return '';
}

// one line that stays on screen in every Mission view: the forecast headline
// (table mode, or the battle is over: the score)
function miniHtml() {
  const m = ms(), r = m.result, g = m.game;
  const clock = clockMiniText();
  const clockSpan = clock ? `<span class="muted clock-mini" id="mini-clock">${clock}</span>` : '';
  if (m.table || g.over) {
    return `<div class="fc-mini" id="score-mini"><span>${g.over ? 'Final' : 'Score'} <b>${totalVp(m.me)}</b> – <b>${totalVp(other(m.me))}</b> VP</span>
      ${clockSpan || `<span class="muted">${g.over ? 'battle over' : `round ${g.round} · ${turnOf()}'s turn`}</span>`}</div>`;
  }
  if (!r) return `<div class="fc-mini muted">${m.busy ? 'Simulating the game…' : 'No forecast yet: pick a layout on the Board tab.'}</div>`;
  const me = m.me, opp = other(me);
  const pWin = me === 'A' ? r.pWinA : r.pWinB;
  return `<button class="fc-mini" data-action="mission-tab" data-value="plan" aria-label="Forecast headline: open the plan">
    <span><b id="fc-mini-win">${pct(pWin)}</b> you win</span><span><b>${fmt(r[me].mean)}</b> – <b>${fmt(r[opp].mean)}</b> VP</span>
    ${clockSpan || `<span class="muted">${inProgress() ? `from round ${m.game.round}` : 'whole game'}${m.busy ? ' · updating…' : ''}</span>`}</button>`;
}

// ---- Set-up checklist: everything that decides the game, in the order it is set, and where to change it.
// Armies -> dispositions (from the lists) -> primaries -> layout + zones -> deployment -> secondaries -> first turn.
function setupRows() {
  const st = ctx.state, m = ms(), bc = boardContext(), si = boardSetupInfo();
  // Board: opens on the Deploy step, where dispositions, layout and zones are set
  const go = (view, label) => `<button class="btn ghost setup-go" data-action="${view === 'board' ? 'board-open-setup' : 'view'}" data-value="${view}">${label}</button>`;
  const toCards = '<button class="btn ghost setup-go" data-action="mission-tab" data-value="cards">Cards</button>';
  const disp = (X) => `${X} ${dispositionName(X === 'A' ? bc.dispA : bc.dispB)}${si.overridden[X] ? ` (list: ${dispositionName(si.listDisp[X])})` : ''}`;
  const ev = st.event, round = ev?.round ? ev.rounds?.[ev.round - 1] : null;
  const evLayout = round?.layout ?? null;
  const v = bc.layout?.variant ?? null;
  const placedN = si.placed.A + si.placed.B, totalN = si.total.A + si.total.B;
  const fixedShort = ['A', 'B'].filter(X => m.modes[X].mode === 'fixed' && m.modes[X].fixed.length < 2);
  const modeText = (X) => `${X} ${m.modes[X].mode === 'fixed' ? `Fixed${m.modes[X].fixed.length ? ` (${m.modes[X].fixed.map(id => SECONDARY_BY_ID[id]?.name ?? id).join(', ')})` : ''}` : 'Tactical'}`;
  return [
    { id: 'armies', step: 'Armies', status: 'ok', text: `A ${st.armies.A.faction} · B ${st.armies.B.faction}`, go: go('armies', 'Armies') },
    { id: 'disp', step: 'Force Dispositions', status: si.overridden.A || si.overridden.B ? 'warn' : 'ok',
      text: `${disp('A')} · ${disp('B')}${si.overridden.A || si.overridden.B ? ' — changed on the Board, not what the list says' : ' — from the lists'}`, go: go('board', 'Board') },
    { id: 'primary', step: 'Primary missions', status: bc.missions.A && bc.missions.B ? 'ok' : 'warn',
      html: `<span id="mission-names"><b style="color:var(--side-a-ink)">A</b> plays <b>${ctx.esc(bc.missions.A ?? '?')}</b> · <b style="color:var(--side-b-ink)">B</b> plays <b>${ctx.esc(bc.missions.B ?? '?')}</b></span>` },
    { id: 'layout', step: 'Layout', status: !bc.layout ? 'warn' : evLayout && evLayout !== v ? 'warn' : 'ok',
      text: `${bc.layout ? `Layout ${layoutLetter(v)} · ${bc.deployment?.name ?? ''}` : 'none for these dispositions'}${si.swapped ? ' · zones swapped' : ''}${evLayout && evLayout !== v ? ` — round ${ev.round} of the event is Layout ${layoutLetter(evLayout)}` : evLayout ? ` — round ${ev.round} of the event` : ''}`, go: go('board', 'Board') },
    { id: 'deploy', step: 'Deployment', status: totalN && placedN >= totalN ? 'ok' : 'todo',
      text: `${placedN} of ${totalN} units placed (A ${si.placed.A}/${si.total.A} · B ${si.placed.B}/${si.total.B})`, go: go('board', 'Board') },
    { id: 'cards', step: 'Secondaries', status: fixedShort.length ? 'todo' : 'ok',
      text: `${modeText('A')} · ${modeText('B')}${fixedShort.length ? ` — ${fixedShort.join(' and ')}: pick 2 Fixed cards` : ''}`, go: toCards },
    { id: 'first', step: 'First turn', status: m.first ? 'ok' : 'todo',
      text: m.first ? `${m.first} goes first · I am ${m.me}` : `roll-off after deployment · I am ${m.me}` },
  ];
}
function setupHtml(where) {
  const rows = setupRows(), si = boardSetupInfo(), live = inProgress();
  const todo = rows.filter(r => r.status === 'todo').length, warn = rows.filter(r => r.status === 'warn').length;
  const icon = { ok: '✓', todo: '•', warn: '⚠' };
  const head = warn || todo ? `${warn ? `${warn} to check` : ''}${warn && todo ? ' · ' : ''}${todo ? `${todo} to do` : ''}` : 'ready';
  return `<details class="more setup" data-details="mission-setup-${where}" ${isOpen(`mission-setup-${where}`, !live && where === 'plan') ? 'open' : ''} id="setup-${where}">
    <summary>Set-up: ${head}${live ? (si.locked ? ' · 🔒 locked during the game' : ' · unlocked') : ''}</summary>
    <ol class="setup-list" id="setup-list-${where}">${rows.map(r => `<li class="setup-row ${r.status}" data-step="${r.id}"><span class="setup-ic" aria-label="${r.status}">${icon[r.status]}</span>
      <span class="grow"><b>${r.step}</b> <span class="small">${r.html ?? ctx.esc(r.text)}</span></span>${r.go ?? ''}</li>`).join('')}</ol>
    <div class="tiny muted">${live ? (si.locked ? 'Dispositions, layout and zones are locked while this game is on the tracker. New game (Play) unlocks them; so does Change anyway on the Board.' : 'Unlocked: changes on the Board change this game\'s missions and map.')
      : 'Set in this order. A new disposition or layout is a new map with its own board plans; the forecast counts only units on the board.'}</div>
  </details>`;
}

// ---- Plan: set-up, forecast, objective plan, what-ifs
function planView() {
  const st = ctx.state, m = ms(), esc = ctx.esc;
  const bc = boardContext();
  const me = m.me;
  const modeRow = (X) => `<div class="modrow"><div class="lab">${X} · ${esc(st.armies[X].faction)} secondaries</div>
      ${ctx.seg('mission-mode', m.modes[X].mode, [['tactical', 'Tactical'], ['fixed', 'Fixed']], `compact" data-side="${X}`)}
      ${m.modes[X].mode === 'fixed' ? `<div class="chips" style="margin-top:6px">${FIXED_IDS.map(id => ctx.chip('mission-fixed', m.modes[X].fixed.includes(id), SECONDARY_BY_ID[id].name, `data-side="${X}" data-id="${id}"`)).join('')}</div>` : ''}</div>`;
  return `<div class="mlay plan"><div class="col">
    <section class="section a-setup o1"><div class="card">
      ${setupHtml('plan')}
      <div class="row" style="gap:8px;margin-top:8px;flex-wrap:wrap">
        <div><div class="lab tiny muted">I am</div>${ctx.seg('mission-me', me, [['A', `A · ${st.armies.A.faction}`], ['B', `B · ${st.armies.B.faction}`]], 'compact')}</div>
        <div><div class="lab tiny muted">First turn</div>${ctx.seg('mission-first', m.first ?? 'roll', [['A', 'A'], ['B', 'B'], ['roll', 'Roll-off']], 'compact')}</div>
      </div>
      <details class="more" style="margin-top:8px" data-details="mission-assume" ${isOpen('mission-assume') ? 'open' : ''}><summary>Assumptions (modes, trading, actions, skill)</summary>
        ${modeRow('A')}${modeRow('B')}
        ${['A', 'B'].map(X => { const k = killRateOf(X); return `<div class="modrow"><div class="lab">${X}: units destroyed per turn${k.from === 'calc' ? ' — Auto is from the calculator' : ''}</div>${ctx.seg('mission-kills', m.killAuto?.[X] === false ? m.killRate[X] : 'auto', [['auto', k.from === 'calc' ? `Auto ${fmt(k.rate, 1)}` : 'Auto'], ...KILL_RATES], `compact" data-side="${X}`)}</div>`; }).join('')}
        <div class="modrow"><div class="lab">Who is the stronger player? (+ slightly, ++ clearly)</div>${ctx.seg('mission-edge', m.edge ?? 0, EDGES, 'compact')}</div>
        ${['A', 'B'].map(X => `<div class="modrow"><div class="lab">${X}: mission actions (Cleanse, Plunder, ${esc(PRIMARIES[bc.missions[X]]?.action ? bc.missions[X] : 'primary actions')})</div>${ctx.seg('mission-action', m.actionP[X], ACTION_P, `compact" data-side="${X}`)}</div>`).join('')}
        <div class="chips" style="margin-top:6px">${['A', 'B'].map(X => ctx.chip('mission-ready', m.battleReady[X], `${X} Battle Ready (+10)`, `data-side="${X}"`)).join('')}</div>
      </details>
    </div></section>
    <section class="section a-hero o2"><h2>Forecast</h2><div id="mission-forecast">${heroHtml()}</div></section>
    <section class="section a-rounds o5"><div id="mission-rounds">${roundsHtml()}</div></section>
    <section class="section a-basis o6"><div id="mission-basis-host">${basisHtml()}</div></section>
    </div><div class="col">
    <section class="section a-grid o3"><h2>Objective plan</h2>${sourceHtml()}${planHtml()}</section>
    <section class="section a-more o4"><div id="mission-more">${moreHtml()}</div></section>
  </div></div>`;
}

// ---- Cards: the secondary deck against this army, what to keep ready, what to kill
function cardsView() {
  // phone: the pre-battle choice first, then the sheet; two panes: the sheet on the left, the rest beside it
  return `<div class="mlay cards">
    <div class="col"><section class="section a-sheet o2"><h2>Secondary cards</h2><div id="mission-cards">${cardsHtml()}</div></section></div>
    <div class="col">${inProgress() ? '' : `<section class="section a-mode o1"><h2>Fixed or Tactical?</h2><div id="mission-mode-host">${modeHtml()}</div></section>`}
      <section class="section a-side o3"><div id="mission-cards-side">${cardsSideHtml()}</div></section></div>
  </div>`;
}

// my secondaries as Tactical and as each Fixed pair, best first
function modeHtml() {
  const m = ms(), me = m.me, esc = ctx.esc;
  const mc = m.modeCompare;
  if (!mc || mc.sig !== modeSig() || !mc.rows.every(r => r.result)) return '<p class="muted small" id="mode-wait">Comparing Tactical with each pair of Fixed cards…</p>';
  const rows = mc.rows.map(r => ({ key: r.key, label: r.label, sec: r.result[me].secMean, win: me === 'A' ? r.result.pWinA : r.result.pWinB, total: r.result[me].mean }))
    .sort((a, b) => b.sec - a.sec);
  const cur = m.modes[me].mode === 'tactical' ? 'mode:tactical' : `mode:${[...m.modes[me].fixed].sort((a, b) => FIXED_IDS.indexOf(a) - FIXED_IDS.indexOf(b)).join('+')}`;
  const tac = rows.find(r => r.key === 'mode:tactical'), bestFixed = rows.find(r => r.key !== 'mode:tactical');
  const verdict = !bestFixed ? 'No Fixed card has targets in this army: Tactical.'
    : tac.sec >= bestFixed.sec ? `<b>Tactical</b> scores about <b>${fmt(tac.sec - bestFixed.sec)} VP</b> more than your best Fixed pair here (${esc(bestFixed.label.replace('Fixed: ', ''))}).`
      : `<b>${esc(bestFixed.label)}</b> is ahead of Tactical by about <b>${fmt(bestFixed.sec - tac.sec)} VP</b> against this army: worth taking if both cards keep scoring.`;
  const use = (r) => (r.key === cur ? '<span class="pill mine">Chosen</span>' : `<button class="mini" data-action="mission-mode-use" data-key="${r.key}" aria-label="Use ${esc(r.label)}">Use</button>`);
  const tr = (r, i) => `<tr data-mode="${r.key}"><td>${esc(r.label)}${i === 0 ? ' ★' : ''}</td><td><b>${fmt(r.sec, 1)}</b></td><td>${pct(r.win)}</td><td>${use(r)}</td></tr>`;
  // the best two on the page; the rest behind a fold (a phone screen is short)
  const head = '<thead><tr><th>Your secondaries</th><th>Secondary VP</th><th>You win</th><th></th></tr></thead>';
  return `<div class="small" id="mode-verdict">${verdict}</div>
    <table class="dist" id="fc-modes" style="margin-top:6px">${head}<tbody>${rows.slice(0, 2).map(tr).join('')}</tbody></table>
    ${rows.length > 2 ? `<details class="more" data-details="mission-modes" ${isOpen('mission-modes') ? 'open' : ''}><summary>The other ${rows.length - 2} Fixed pairs</summary>
      <table class="dist" id="fc-modes-all">${head}<tbody>${rows.slice(2).map((r, i) => tr(r, i + 2)).join('')}</tbody></table></details>` : ''}
    <div class="tiny muted">Average secondary VP over the simulated games (maximum 45; a Fixed card pays at most 20). Both players choose in secret before deployment and cannot change it.</div>`;
}

// the cards in hand of one player, each with how often it still scores from here
function handHtml(X) {
  const m = ms(), g = m.game, esc = ctx.esc;
  if (!g[X].hand.length) return '<span class="muted small">None.</span>';
  const res = m.result?.[X]?.cards ?? {};
  // no targets left for a kill card once those units are destroyed
  const enemy = profileOf(other(X))?.profile;
  const gone = new Set(g[other(X)].destroyed);
  const alive = enemy ? { units: enemy.units.filter(u => !gone.has(u.name)) } : null;
  const row = (id) => {
    const c = SECONDARY_BY_ID[id], s = res[id];
    const dead = alive && cardDead(id, alive);
    // Assassination also scores when every enemy CHARACTER model has been destroyed during the battle
    const allChars = dead && id === 'assassination' && !cardDead(id, enemy);
    // what the forecast says about this card from the current turn to the end of the battle
    const tip = allChars ? `<span class="good">Every enemy CHARACTER is destroyed: it scores ${c.max} VP at the end of this turn.</span>`
      : dead ? `<span class="warn">No targets left${c.drawn ? ': when you draw it you can discard it and draw a new card. Later,' : ':'} discard it at the end of your turn for 1CP.</span>`
      : !s ? '<span class="muted">…</span>'
        : s.scoreRate < 0.3 ? `<span class="warn">${pct(s.scoreRate)} to score by the end: discard for 1CP unless you can play for it.</span>`
          : `<span class="muted">${pct(s.scoreRate)} to score by the end · ${fmt(s.perDraw, 1)} VP${c.vps.length > 1 && g.round < MODEL.holdUntil ? ` · before round ${MODEL.holdUntil}, hold a part score for the full ${c.max}` : ''}</span>`;
    const open = m.handOpen === `${X}:${id}`;
    return `<div class="hand-row" data-card="${id}"><span class="grow"><button class="linkish" data-action="mission-hand-info" data-side="${X}" data-id="${id}" aria-expanded="${open}">${esc(c.name)}</button>
        ${open ? `<div data-text="${id}" style="margin:6px 0">${cardFace(c, { esc })}</div>` : ''}
        ${m.table ? '' : `<div class="tiny" data-advice="${id}">${tip}</div>`}</span>
      ${c.vps.map(v => `<button class="mini score" data-action="mission-hand" data-side="${X}" data-id="${id}" data-do="scored" data-vp="${v}" aria-label="${esc(c.name)} scored ${v} VP">+${v}</button>`).join('')}
      <button class="mini" data-action="mission-hand" data-side="${X}" data-id="${id}" data-do="discard" aria-label="Discard ${esc(c.name)}">✕</button></div>`;
  };
  return g[X].hand.map(row).join('');
}

// ---- Play: the game on the table (round, scores, cards in hand), and the forecast from here
function playView() {
  const m = ms(), g = m.game, me = m.me, opp = other(me);
  const who = (X) => `${X}${X === me ? ' · me' : ''}`;
  const cur = turnOf();
  const lastTurn = m.first != null && g.round >= RULES.rounds && cur !== m.first;
  // before any turn of round 1 is done, the player whose turn it is IS the player who goes first
  const opening = isOpening();
  return `<div class="mlay play"><div class="col">
    <section class="section a-bar o1"><div class="card" id="play-bar">
      <div class="bar-main">
        <div class="row" style="gap:8px;flex-wrap:wrap;align-items:flex-end">
          <div><div class="lab tiny muted">Battle round</div>${ctx.seg('mission-round', g.round, [1, 2, 3, 4, 5].map(r => [r, String(r)]), 'compact')}</div>
          <div><div class="lab tiny muted">${opening ? 'First turn' : 'Turn of'}</div>${ctx.seg('mission-next', cur, [['A', who('A')], ['B', who('B')]], 'compact')}</div>
        </div>
        <div class="row acts" style="gap:8px">
          <button class="btn primary grow" data-action="mission-turn-done" id="play-turn-done" ${g.over ? 'disabled' : ''}>${g.over ? 'Battle over' : lastTurn ? 'End the battle ▶' : 'Turn done ▶'}</button>
          <button class="btn" data-action="mission-show" id="play-show" aria-label="Show the score to the opponent">📺 Show</button>
          <button class="btn" data-action="mission-undo" id="play-undo" ${m.undo.length ? '' : 'disabled'} aria-label="Undo the last change${m.undo.length ? `: ${ctx.esc(m.undo[m.undo.length - 1].label)}` : ''}">↶ Undo</button>
        </div>
      </div>
      ${m.first == null && !opening ? `<div class="row" style="gap:8px;margin-top:8px;align-items:center"><span class="small">Who took the first turn?</span>${ctx.seg('mission-first', 'roll', [['A', who('A')], ['B', who('B')]], 'compact')}</div>` : ''}
      <div class="small" id="play-turn" style="margin-top:8px">${turnLineHtml()}</div>
      <div id="play-caps">${capsHtml()}</div>
      ${checklistHtml()}
      <div id="play-strats-host">${stratNowHtml()}</div>
    </div></section>
    <section class="section a-me o3">${playerCard(me)}</section>
    </div><div class="col">
    <section class="section a-opp o4">${playerCard(opp)}</section>
    <section class="section a-clock o2">${clockHtml()}</section>
    <section class="section a-score o5">${sheetHtml()}</section>
    ${m.table ? '' : `<section class="section a-fc o6"><h2>From here</h2><div id="mission-forecast">${heroHtml()}</div></section>`}
    <section class="section a-opts o7"><div class="card" id="play-options">
      ${!m.table && setupRows().some(r => r.status === 'warn') ? `<div style="margin-bottom:8px">${setupHtml('play')}</div>` : ''}
      <div class="chips">${ctx.chip('mission-table', !!m.table, 'Table mode: tracker only')}${ctx.chip('mission-awake', m.awake !== false, 'Screen stays on')}</div>
      <div class="tiny muted" id="table-note" style="margin-top:6px">${m.table ? 'Table mode is on: the forecast, the card advice, the calculator and the board planner are closed.' : 'Table mode leaves only the tracker: no forecast, card advice, calculator or board.'} Some events ban decision aids during games: check your pack.</div>
      <button class="btn ghost" style="margin-top:10px" data-action="mission-reset" id="play-reset">New game (clear the tracker)</button>
    </div></section>
    <section class="section a-games o8" id="play-games-host">${ctx.gamesCard?.('play') ?? ''}</section>
  </div></div>`;
}

// ---- stratagems in play: what each player can use in this phase, Use (spends the CP, once per phase), the log
const stratCache = new Map();
function stratsOf(X) {
  const army = ctx.state.armies[X];
  if (!army) return [];
  if (!stratCache.has(army)) {
    const seen = new Set();
    stratCache.set(army, armyIntel(army).stratagems.filter(s => !seen.has(s.name) && seen.add(s.name)));
  }
  return stratCache.get(army);
}
function stratNowHtml() {
  const m = ms(), g = m.game, esc = ctx.esc, cur = turnOf();
  const phaseName = PT.PHASES.find(p => p[0] === (g.phase ?? 'command'))?.[1] ?? '';
  const block = (X) => {
    const list = stratsOf(X).filter(s => PT.stratUsable(s, g.phase ?? 'command', X === cur));
    const rows = list.map(s => {
      const used = PT.stratUsedThisPhase(g, X, s.name, cur), cp = Number(s.cp) || 0, short = (g[X].cp || 0) < cp;
      return `<div class="strat-now" data-strat="${esc(s.name)}" data-side="${X}"><details><summary><b>${esc(s.name)}</b> <span class="tiny muted">${cp}CP${s.detachment ? ` · ${esc(s.detachment)}` : ''}</span></summary>
        <div class="tiny muted">${s.missing ? 'No 11e text in the rules data.' : `<b>When:</b> ${esc(s.when ?? '')}<br><b>Effect:</b> ${esc(s.effect ?? '')}`}</div></details>
        <button class="mini${used ? ' on' : ''}" data-action="mission-strat" data-side="${X}" data-name="${esc(s.name)}" ${used || short ? 'disabled' : ''}>${used ? '✓ Used' : short ? `${cp}CP` : `Use · ${cp}CP`}</button></div>`;
    }).join('');
    counts[X] = list.length;
    return `<div class="strat-side"><div class="lab tiny muted">${X}${X === m.me ? ' (me)' : ''} · ${X === cur ? 'their turn' : 'opponent’s turn'} · ${g[X].cp ?? 0}CP · ${list.length} usable</div>${rows || '<div class="tiny muted">None in this phase.</div>'}</div>`;
  };
  const log = (g.strats ?? []).slice().reverse();
  const counts = {};
  const body = block(cur) + block(other(cur));
  return `<details class="more" id="play-strats" data-details="mission-strats" ${isOpen('mission-strats') ? 'open' : ''}><summary><b>Stratagems now</b> <span class="tiny muted">· ${esc(phaseName)}: ${esc(cur)} ${counts[cur]}, ${esc(other(cur))} ${counts[other(cur)]} usable · ${log.length} used</span></summary>
    <div style="margin-top:6px"><div class="lab tiny muted">Phase of ${esc(cur)}'s turn</div>${ctx.seg('mission-phase', g.phase ?? 'command', PT.PHASE_SHORT, 'compact')}</div>
    ${body}
    <div class="tiny muted" style="margin-top:4px">Use spends the CP and logs it; the same stratagem once per phase. Move the phase on as the turn goes; “Turn done” starts the next turn in the Command phase.</div>
    <details class="more" data-details="mission-strat-log" ${isOpen('mission-strat-log') ? 'open' : ''}><summary>Stratagems used (${log.length})</summary>
      ${log.length ? `<ul class="keep" id="strat-log">${log.map(s => `<li><b>${esc(s.side)}</b> ${esc(s.name)} <span class="tiny muted">${s.cp}CP · round ${s.round}, ${esc(s.turn ?? '?')}'s turn, ${esc(PT.PHASES.find(p => p[0] === s.phase)?.[1] ?? s.phase)}</span></li>`).join('')}</ul>` : '<div class="tiny muted">None yet. Undo takes back the last one.</div>'}</details></details>`;
}

// what was scored since the turn began (a check before "Turn done")
function turnLineHtml() {
  const m = ms(), g = m.game;
  if (g.over) return `<b>Battle over.</b> Final score: A ${totalVp('A')} – B ${totalVp('B')}.`;
  const d = PT.turnDelta(g);
  const sign = (v) => `${v > 0 ? '+' : ''}${v}`;
  const part = (X) => (d[X].primary || d[X].secondary
    ? `<b>${X}</b> ${[d[X].primary ? `${sign(d[X].primary)} primary` : '', d[X].secondary ? `${sign(d[X].secondary)} secondary` : ''].filter(Boolean).join(', ')}`
    : `<span class="muted">${X} nothing yet</span>`);
  return `Round ${g.round}, ${turnOf()}'s turn — scored this turn: ${part('A')} · ${part('B')}`;
}

// more than 15VP of primary, or of secondary, in one battle round (Event Companion: "Up to 15VP per battle round")
function capsHtml() {
  const g = ms().game;
  const ws = PT.capWarnings(g, RULES.rounds, RULES.primaryRoundCap);
  if (!ws.length) return '';
  return `<div class="warnbox" id="play-cap-warn" style="margin-top:8px">${ws.map(w => `<div data-cap="${w.side}:${w.round}:${w.kind}">⚠ <b>${w.side}</b> has ${w.vp} ${w.kind} VP in battle round ${w.round}: the limit is ${RULES.primaryRoundCap} per battle round, so ${w.over} of them do not count${w.last ? ' (VP scored at the end of the battle are outside this limit)' : ''}.</div>`).join('')}</div>`;
}

// what to do in a turn, in the order of the rules (core rules 08, Event Companion step 6)
function checklistHtml() {
  const m = ms(), g = m.game, bc = boardContext(), esc = ctx.esc;
  const cur = turnOf();
  const tactical = m.modes[cur].mode === 'tactical';
  const prim = (X) => (bc.missions[X] ? `<div class="tiny" style="margin-top:4px"><b>${X} · ${esc(bc.missions[X])}:</b> ${esc(PRIMARIES[bc.missions[X]]?.text ?? '')}</div>` : '');
  return `<details class="more" style="margin-top:6px" data-details="mission-checklist" ${isOpen('mission-checklist') ? 'open' : ''}><summary>Turn checklist and primary missions</summary>
    <div class="lab tiny muted" style="margin-top:4px">${cur}'s Command phase</div>
    <ol class="checklist" id="play-checklist">
      ${tactical ? `<li>Draw 2 secondary cards <span class="muted">(${Math.min(RULES.drawPerTurn, g.drawn ?? 0)} of ${RULES.drawPerTurn} entered)</span></li>` : ''}
      <li>Both players gain 1CP <span class="muted">(the app adds it at “Turn done”)</span></li>
      <li>Battle-shock tests: units at or below half strength</li>
      <li>End of the phase: primary VP that are scored in the Command phase</li>
      ${tactical ? '<li>Once per battle, at the end of the phase: 1CP to discard a card and draw a new one</li>' : ''}
    </ol>
    <div class="lab tiny muted">End of ${cur}'s turn</div>
    <ol class="checklist">
      <li>Secondary cards: ${cur} first, then ${other(cur)} <span class="muted">(scoring is optional: you can hold a card)</span></li>
      ${tactical ? `<li>${cur} can discard cards for 1CP in total <span class="muted">(events: 1CP a battle round from anything but the Command phase)</span></li>` : ''}
      <li>Primary VP that are scored at the end of the turn</li>
      <li>Mark the units destroyed, then “Turn done”</li>
    </ol>
    ${prim('A')}${prim('B')}
  </details>`;
}

// pace against the milestones (round timer)
function paceHtml(now = Date.now()) {
  const m = ms(), c = m.clock, g = m.game;
  if (!PT.roundStarted(c)) return '<span class="muted">Start it when the round starts.</span>';
  if (g.over) return 'Battle over.';
  const left = PT.roundLeft(c, now);
  if (left <= 0) return '<span class="warn"><b>Time is up.</b></span>';
  const p = PT.paceStatus(c.len, left, g.round);
  if (p.noNewRound) return '<span class="warn"><b>Under 5 minutes:</b> do not start a new battle round without a judge.</span>';
  return p.behind ? `<span class="warn"><b>${p.behind} min behind:</b> battle round ${p.round} should be done with ${PT.fmtHm(p.target)} left.</span>`
    : `On pace: finish battle round ${p.round} in the next <b>${Math.floor(p.dueIn)} min</b> (with ${PT.fmtHm(p.target)} left).`;
}

// round timer with the tournament milestones, or a chess clock
function clockHtml() {
  const m = ms(), c = m.clock, now = Date.now(), hm = PT.fmtHm;
  const who = (X) => `${X}${X === m.me ? ' · me' : ''}`;
  let body = '';
  if (c.mode === 'round') {
    const running = PT.roundRunning(c), started = PT.roundStarted(c), list = PT.milestones(c.len);
    body = `<div class="row" style="gap:8px;margin-top:8px;align-items:center">
        <div class="clock-big grow" id="clock-round">${PT.fmtClock(PT.roundLeft(c, now))}</div>
        <button class="btn primary" data-action="mission-clock" data-do="${running ? 'pause' : 'start'}" id="clock-go">${running ? 'Pause' : started ? 'Resume' : 'Start'}</button></div>
      <div class="row" style="gap:8px;margin-top:8px">
        <button class="btn" data-action="mission-clock" data-do="minus" aria-label="5 minutes less">−5 min</button>
        <button class="btn" data-action="mission-clock" data-do="plus" aria-label="5 minutes more">+5 min</button>
        <span class="grow"></span>
        <button class="btn ghost" data-action="mission-clock" data-do="reset">Reset</button></div>
      <div class="small" id="clock-pace" style="margin-top:6px">${paceHtml(now)}</div>
      ${started ? '' : `<div class="modrow"><div class="lab">Round length</div>${ctx.seg('mission-clock-len', c.len, PT.ROUND_LENGTHS.map(v => [v, hm(v)]), 'compact')}</div>`}
      <div class="tiny muted" style="margin-top:6px" id="clock-milestones">Time left when each step should be done${c.len === PT.GT_ROUND_MIN ? ' (Games Workshop Grand Tournament pack, 3-hour round)' : ` (the Games Workshop 3-hour milestones scaled to ${hm(c.len)})`}:
        ${list.map((x, i) => `${hm(x.left)} ${x.round ? `round ${x.round}` : i === 0 ? 'pre-game' : 'deployed'}`).join(' · ')}. −5 / +5 to match the hall clock.</div>`;
  } else if (c.mode === 'chess') {
    const tile = (X) => `<button class="clock-tile ${c.running === X ? 'on' : ''}" data-action="mission-clock" data-do="run" data-side="${X}" aria-label="Run the clock of ${X}" aria-pressed="${c.running === X}">
        <span class="tiny">${who(X)}</span><b id="clock-${X}">${PT.fmtClock(PT.chessLeft(c, X, now))}</b></button>`;
    body = `<div class="row" style="gap:8px;margin-top:8px">${tile('A')}${tile('B')}</div>
      <div class="row" style="gap:8px;margin-top:8px;flex-wrap:wrap;align-items:center"><button class="btn" data-action="mission-clock" data-do="chess-pause" id="chess-pause" ${c.running ? '' : 'disabled'}>${PT.chessLocked(c) ? '🔒 Pause (referee)' : 'Pause'}</button>
        <button class="btn ghost" data-action="mission-clock" data-do="chess-reset">Reset</button>
        ${ctx.chip('mission-clock-lock', PT.chessLocked(c), 'Pause locked', 'id="chess-lock"')}</div>
      ${PT.chessStarted(c) ? '' : `<div class="modrow"><div class="lab">Time each</div>${ctx.seg('mission-clock-bank', c.bank, PT.CHESS_BANKS.map(v => [v, hm(v)]), 'compact')}</div>`}
      <div class="tiny muted" style="margin-top:6px" id="chess-note">Tap a player to run that player's clock (and the other player when it passes, for example for saves). “Turn done” passes it to the next player. UKTC recommends 1:25 each. ${PT.chessLocked(c) ? 'Pause locked: once started, only a referee may pause the clock (UKTC); a player with under 5 minutes left may pause it to call one. A tap on the running clock does nothing, and Pause asks first.' : 'A tap on the running clock pauses it.'} The event's own clock is the one that counts.</div>`;
  }
  return `<div class="card" id="play-clock"><div class="row" style="align-items:center;gap:8px;flex-wrap:wrap"><div class="title grow">Clock</div>
      ${ctx.seg('mission-clock-mode', c.mode, [['off', 'Off'], ['round', 'Round timer'], ['chess', 'Chess clock']], 'compact')}</div>${body}</div>`;
}

// per battle round: what each player scored (for the event's score sheet)
function sheetHtml() {
  const m = ms(), g = m.game;
  const s = PT.scoreSheet(g, RULES.rounds);
  const cell = (v) => (v ? String(v) : '<span class="muted">–</span>');
  const tr = (label, r, cls = '') => `<tr class="${cls}"><td>${label}</td><td>${cell(r.A.primary)}</td><td>${cell(r.A.secondary)}</td><td>${cell(r.B.primary)}</td><td>${cell(r.B.secondary)}</td></tr>`;
  return `<details class="more card" data-details="mission-sheet" ${isOpen('mission-sheet') ? 'open' : ''} id="play-sheet"><summary>Score sheet: A ${totalVp('A')} – B ${totalVp('B')}</summary>
    <table class="dist scoresheet" style="margin-top:6px"><thead><tr><th>Round</th><th>A prim.</th><th>A sec.</th><th>B prim.</th><th>B sec.</th></tr></thead><tbody>
    ${s.hasBefore ? tr('Earlier', s.before) : ''}
    ${s.rows.map(r => tr(String(r.round), r, r.round === g.round && !g.over ? 'cur' : '')).join('')}
    ${tr('Total', s.total, 'total')}
    </tbody></table>
    <div class="tiny muted" style="margin-top:6px">Filled in from the scores you enter (“Turn done” closes a turn).${m.battleReady.A || m.battleReady.B ? ' The totals above add 10 VP for a Battle Ready army.' : ''} The event's own score sheet or app is the record: copy it there.</div>
  </details>`;
}

function fmt(n, d = 0) { return (Math.round(n * 10 ** d) / 10 ** d).toFixed(d); }
const pct = (p) => (p >= 0.995 ? '>99%' : p > 0 && p < 0.005 ? '<1%' : `${Math.round(p * 100)}%`);

function fcParts() {
  const m = ms(), r = m.result;
  if (!r) return null;
  const me = m.me, opp = other(me);
  return { m, r, me, opp, pWin: me === 'A' ? r.pWinA : r.pWinB, pLose: me === 'A' ? r.pWinB : r.pWinA,
    margin: me === 'A' ? r.margin : { p10: -r.margin.p90, p50: -r.margin.p50, p90: -r.margin.p10 } };
}

// the headline: win chance, both scores with their ranges, what it means
function heroHtml() {
  const f = fcParts(), m = ms();
  if (!f) return `<p class="muted small">${m.busy ? 'Simulating the game…' : 'Pick a layout on the Board tab to forecast.'}</p>`;
  const { r, me, opp, pWin, pLose, margin } = f;
  const ft = r.firstTurn;
  const mine = (p) => (p == null ? null : me === 'A' ? p : 1 - p);
  const pFirst = mine(me === 'A' ? ft?.pWinAFirst : ft?.pWinASecond), pSecond = mine(me === 'A' ? ft?.pWinASecond : ft?.pWinAFirst);
  return `<div class="hero" style="grid-template-columns:1fr 1fr 1fr">
      <div class="cell"><b id="fc-win">${pct(pWin)}</b><span>you win${r.pDraw >= 0.005 ? ` · draw ${pct(r.pDraw)}` : ''}</span></div>
      <div class="cell"><b id="fc-me">${fmt(r[me].mean)}</b><span>your VP (${r[me].p10}–${r[me].p90})</span></div>
      <div class="cell"><b id="fc-opp">${fmt(r[opp].mean)}</b><span>their VP (${r[opp].p10}–${r[opp].p90})</span></div>
    </div>
    <div class="small" style="margin-top:6px" id="fc-verdict">${verdict(pWin, pLose, margin)}</div>
    <div class="chart" style="margin-top:8px">${rangeChart(r, me)}</div>
    ${m.first == null && !inProgress() && pFirst != null && pSecond != null ? `<div class="small" style="margin-top:6px" id="fc-first">First turn is a roll-off after deployment: you win <b>${pct(pFirst)}</b> going first, <b>${pct(pSecond)}</b> going second.</div>` : ''}
    ${(() => { const vi = sourcePlan(), tag = m.first == null && vi != null ? boardPlans()[vi]?.when : null; return tag ? `<div class="small" style="margin-top:6px" id="fc-first-tag">This board plan is your <b>going ${tag}</b> version: the forecast has ${tag === 'first' ? 'you' : 'your opponent'} take the first turn. “Your plans compared” has both versions.</div>` : ''; })()}
    <div class="tiny muted" style="margin-top:4px">${r.trials.toLocaleString()} simulated games${m.busy ? ' (updating…)' : ''}. The range is where 8 games in 10 end.</div>`;
}

// round by round: who leads, VP per round, units left
function roundsHtml() {
  const f = fcParts();
  if (!f) return '';
  const { r, me, opp } = f;
  const leadRow = r.lead.map((l, i) => `<div class="cell"><b>${pct(me === 'A' ? l.A : l.B)}</b><span>R${i + 1}</span></div>`).join('');
  // end-of-battle primary VP (not under the 15 VP per round limit) get their own column when a mission has them
  const hasEnd = (r.A.primEnd ?? 0) > 0.05 || (r.B.primEnd ?? 0) > 0.05;
  const roundRows = [[me, 'You'], [opp, 'Opp']].map(([X, lab]) => `<tr><td><span class="swatch" style="background:var(--side-${X.toLowerCase()})"></span>${lab} · ${X}</td>
      ${r[X].prim.map((p, i) => `<td>${fmt(p + r[X].sec[i])}<span class="tiny muted"> ${fmt(p)}+${fmt(r[X].sec[i])}</span></td>`).join('')}${hasEnd ? `<td>${fmt(r[X].primEnd ?? 0)}</td>` : ''}<td><b>${fmt(r[X].mean)}</b></td></tr>`).join('');
  return `<details class="more" data-details="mission-rounds" ${isOpen('mission-rounds', ctx.wide?.() ?? false) ? 'open' : ''}><summary>Round by round (who leads, VP, units left)</summary>
    <div class="lab tiny muted" style="margin-top:8px">Chance you are ahead after each battle round</div>
    <div class="hero lead" id="fc-lead" style="grid-template-columns:repeat(5,1fr)">${leadRow}</div>
    <table class="dist" style="margin-top:8px"><thead><tr><th>VP by round</th><th>R1</th><th>R2</th><th>R3</th><th>R4</th><th>R5</th>${hasEnd ? '<th>End</th>' : ''}<th>Total</th></tr></thead><tbody>${roundRows}</tbody></table>
    <div class="tiny muted">Primary + secondary per round${hasEnd ? '; End = primary VP scored at the end of the battle (not under the 15 VP per round limit)' : ''}; totals include Battle Ready.</div>
    ${battleHtml(r, me)}
  </details>`;
}

// what would change the result: the what-ifs, and your plans side by side
function moreHtml() {
  const f = fcParts();
  if (!f) return '';
  const { m, r, me, opp, pWin } = f;
  const esc = ctx.esc;
  const levers = (m.levers ?? []).map(l => {
    const lr = l.result;
    if (!lr) return '';
    const dWin = (me === 'A' ? lr.pWinA : lr.pWinB) - pWin;
    const dMe = lr[me].mean - r[me].mean, dOpp = lr[opp].mean - r[opp].mean;
    const sign = (x, d = 0) => `${x >= 0 ? '+' : '−'}${fmt(Math.abs(x), d)}`;
    return `<tr data-lever="${l.key}"><td>${esc(l.label)}</td><td class="${dWin >= 0 ? 'up' : 'down'}"><b>${sign(dWin * 100)}%</b></td><td>${sign(dMe, 1)}</td><td>${sign(dOpp, 1)}</td></tr>`;
  }).join('');
  return `${levers ? `<h2 class="sub">What changes the result</h2>
      <table class="dist" id="fc-levers"><thead><tr><th>If you…</th><th>Win</th><th>You</th><th>Opp</th></tr></thead><tbody>${levers}</tbody></table>` : ''}
    ${compareHtml(me, opp)}`;
}

// how the simulated battles go: units left, wipe-outs, first / second turn
function battleHtml(r, me) {
  const m = ms(), opp = other(me);
  const total = (X) => profileOf(X)?.profile.count ?? 0;
  const leftRow = (X, lab) => `<tr><td><span class="swatch" style="background:var(--side-${X.toLowerCase()})"></span>${lab}</td>${r[X].unitsLeft.map(v => `<td>${fmt(v, 1)}</td>`).join('')}<td>${pct(r[X].pTabled)}</td></tr>`;
  return `<div class="lab tiny muted" style="margin-top:8px">Units left at the end of each battle round (you start with ${total(me)}, they with ${total(opp)})</div>
    <table class="dist" id="fc-units"><thead><tr><th></th><th>R1</th><th>R2</th><th>R3</th><th>R4</th><th>R5</th><th>Wiped out</th></tr></thead><tbody>${leftRow(me, 'You')}${leftRow(opp, 'Opp')}</tbody></table>
`;
}

// where every part of the forecast comes from: rules, your input, the calculator, or an assumption
function basisHtml() {
  const m = ms(), me = m.me, opp = other(me), esc = ctx.esc;
  const vi = sourcePlan();
  const plans = boardPlans();
  const kr = { [me]: killRateOf(me), [opp]: killRateOf(opp) };
  const killLine = (X, lab) => {
    const k = kr[X];
    return k.from === 'calc' ? `${lab} <b>${fmt(k.rate, 1)}</b> units a turn (calculator: ${fmt(k.raw, 1)} with everything in reach × ${ENGAGE} delivered in a typical turn)`
      : k.from === 'you' ? `${lab} <b>${fmt(k.rate, 1)}</b> units a turn (your setting)` : `${lab} 1.3 units a turn until the calculator has run`;
  };
  const nEst = Object.keys(m.est?.[me] ?? {}).length;
  const noData = POSITION_CARDS.filter(id => !REAL_RATES[id]).map(id => SECONDARY_BY_ID[id].name);
  const row = (kind, title, text) => `<li class="basis ${kind}"><span class="pill ${kind === 'rule' ? 'good' : kind === 'you' ? 'mine' : kind === 'calc' ? '' : 'ask'}">${kind === 'rule' ? 'Rules' : kind === 'you' ? 'Your input' : kind === 'calc' ? 'Calculator' : kind === 'data' ? 'Real games' : kind === 'stamp' ? 'Rules data' : 'Assumption'}</span> <b>${title}</b> — ${text}</li>`;
  // how old the datasheets behind the calculator's numbers are
  const stamp = (X) => { const d = armyData(ctx.state.armies[X]); return `${X}: ${d.prov.groups.map(g => `${esc(g.label)}, ${fmtDataDate(g.date)}`).join(' and ')}${d.pts.mismatches.length ? ` <span style="color:var(--warn-ink)">(⚠ ${d.pts.mismatches.length} datasheet${d.pts.mismatches.length > 1 ? 's' : ''} with other points in the list than in the data: see the Armies tab)</span>` : ''}`; };
  return `<details class="more" data-details="mission-basis" ${isOpen('mission-basis') ? 'open' : ''} id="fc-basis"><summary>What this forecast is built from</summary>
    <ul class="keep basis-list">
      ${row('rule', 'Scoring', 'card VP and timing, the deck (draw two a turn, cards stay until scored), the 15 VP per round and 45 VP limits, end-of-battle VP, Battle Ready. Exact.')}
      ${row('you', 'Objectives', vi != null ? `measured from your board plan “${esc(plans[vi]?.name ?? '')}”: the units you placed hold what they are in range of, at the end of every turn.` : 'your objective grid below. A planned objective is not certain: you lose it now and then, more often when your army is the weaker one.')}
      ${row(kr[me].from === 'you' && kr[opp].from === 'you' ? 'you' : 'calc', 'Units destroyed', `${killLine(me, 'you destroy')}; ${killLine(opp, 'they destroy')}. ${vi != null && m.enemyFrom === 'board' ? 'With both armies on the board plan, each unit attacks the best target it reaches from where you put it (range and charge reach; line of sight is not checked).' : 'An army destroys less as it shrinks, and a destroyed unit holds nothing.'}`)}
      ${row('data', 'Cards that depend on where units are', `${nEst ? `${nEst} use your own estimate; the others` : 'they'} use how often tournament players scored the equivalent 10th edition card (${esc(REAL_RATES_SOURCE)}), × ${MODEL.cardPlay} because 11th edition cards are kept until scored. No such data for ${esc(noData.join(', '))}: ${Math.round(50 * MODEL.cardPlay)}%. Set your own value on any card.`)}
      ${row('assume', 'How the battle goes', `in every simulated game one side gets on top and that compounds. Set so that the scores match 94,739 real 11th edition tournament results: average 77 VP, average winning margin 30 VP, 13% of scores under 50. ${(m.edge ?? 0) === 0 ? 'Both players are taken as equally good (change it under Assumptions).' : `You set ${m.edge > 0 ? 'yourself' : 'your opponent'} as the stronger player.`}`)}
      ${row('stamp', 'Datasheets', `${stamp(me)}. ${stamp(opp)}. Stats and points changed after these dates are not in the numbers.`)}
      ${row('assume', 'Not in the forecast', 'stratagems and command points, army rules that change scoring, and how well each unit does a mission action (one chance for all: Assumptions).')}
    </ul></details>`;
}

function compareHtml(me, opp) {
  const m = ms(), esc = ctx.esc;
  const rows = (m.compare ?? []).filter(c => c.result);
  if (rows.length < 2) return '';
  const win = (c) => (me === 'A' ? c.result.pWinA : c.result.pWinB);
  // the best complete plan gets the star: a plan with units missing is not comparable
  const complete = rows.filter(c => !planNotes[c.key]);
  const best = Math.max(...(complete.length ? complete : rows).map(win));
  // versions made for going first / going second: each is forecast with that first turn (until it is known)
  const plans = boardPlans();
  const whenOf = (c) => { const x = /^plan(\d+)$/.exec(c.key); return x ? plans[Number(x[1])]?.when ?? null : null; };
  const tagHtml = (c) => (whenOf(c) ? ` <span class="tiny muted">· ${m.first == null ? `you go ${whenOf(c)}` : `made for going ${whenOf(c)}`}</span>` : '');
  const pf = rows.find(c => whenOf(c) === 'first'), ps = rows.find(c => whenOf(c) === 'second');
  const rollOff = pf && ps && m.first == null ? `<tr id="fc-rolloff" data-win="${((win(pf) + win(ps)) / 2).toFixed(4)}"><td>Roll-off: half your games each way, the right plan for each</td><td><b>${pct((win(pf) + win(ps)) / 2)}</b></td><td>${fmt((pf.result[me].mean + ps.result[me].mean) / 2)}</td><td>${fmt((pf.result[opp].mean + ps.result[opp].mean) / 2)}</td></tr>` : '';
  return `<h2 class="sub" style="margin-top:14px">Your plans compared</h2>
    <table class="dist" id="fc-compare"><thead><tr><th>Plan</th><th>Win</th><th>You</th><th>Opp</th></tr></thead><tbody>
    ${rows.map(c => { const w = win(c), note = planNotes[c.key]; return `<tr data-plan="${c.key}" data-when="${whenOf(c) ?? ''}"><td>${esc(c.label)}${tagHtml(c)}${!note && w === best ? ' ★' : ''}${note ? `<div class="tiny" style="color:var(--warn-ink)">${esc(note)}: the rest hold and score nothing</div>` : ''}</td><td><b>${pct(w)}</b></td><td>${fmt(c.result[me].mean)} <span class="tiny muted">${c.result[me].p10}–${c.result[me].p90}</span></td><td>${fmt(c.result[opp].mean)}</td></tr>`; }).join('')}${rollOff}
    </tbody></table>${treesHtml(me)}${rollOff ? '<div class="tiny muted" id="fc-rolloff-note">The winner of the roll-off takes the first turn (Event Companion), so each version is used in half your games.</div>' : ''}`;
}

// Branching board plans: the chance to win down each branch, the best option at each of my decisions, the
// chance outcomes weighted by their chance, and what already happened (plantree.mjs evaluate)
function treesHtml(me) {
  const trees = boardTrees();
  if (!trees.length) return '';
  const m = ms(), esc = ctx.esc;
  const win = (vi) => { const c = (m.compare ?? []).find(r => r.key === `plan${vi}`)?.result; return c ? (me === 'A' ? c.pWinA : c.pWinB) : null; };
  const val = (n) => (n.value == null ? '…' : `${pct(n.value)}${n.partial ? '*' : ''}`);
  const nodeHtml = (n, t) => {
    if (!n.split) return '';
    const s = n.split;
    const head = `After <b>${esc(t.stepName(s.pi, s.at))}</b> · ${s.kind === 'chance' ? '● chance' : '◆ your decision'}${s.chosen ? ' · <b>known</b>' : ''}`;
    return `<div class="ftsplit" data-kind="${s.kind}"><div class="tiny muted">${head}</div><ul class="ftree">${n.options.map(o => {
      const hit = s.chosen === o.id, gone = s.chosen && !hit, best = !s.chosen && s.kind === 'decision' && n.best === o.id;
      return `<li data-opt="${esc(o.id)}" class="${gone ? 'gone' : ''}${best ? ' best' : ''}"><span>${hit ? '✓ ' : ''}${esc(o.label)}${s.kind === 'chance' && !s.chosen ? ` <span class="tiny muted">(${pct(o.p)})</span>` : ''}</span> <b>${val(o.node)}</b>${best ? ' ★' : ''}
        ${gone ? '' : nodeHtml(o.node, t)}</li>`;
    }).join('')}</ul></div>`;
  };
  return `<h2 class="sub" style="margin-top:14px">Your branching plans</h2>${trees.map(t => {
    const ev = evalTree(t.tree, win);
    const lead = ev.split?.kind === 'decision' && !ev.split.chosen && ev.best ? ` · best: <b>${esc(ev.options.find(o => o.id === ev.best)?.label ?? '')}</b>` : '';
    return `<div class="card fc-tree" data-root="${t.ri}" style="margin-top:6px"><div class="small"><b>${esc(t.name)}</b>: you win <b>${val(ev)}</b>${lead}</div>${nodeHtml(ev, t)}</div>`;
  }).join('')}
  <div class="tiny muted" id="fc-tree-note">At your decisions the better option counts (★); chance outcomes are weighted by their chance; once you mark an option on the Board as chosen or happened, only it counts. * = some branches not worked out yet.</div>`;
}

function verdict(pWin, pLose, margin) {
  const m = margin.p50, sg = (v) => `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(v)}`;
  // real games are rarely close on the scoreboard: say how wide the result can be
  const span = `8 games in 10 end between ${sg(margin.p10)} and ${sg(margin.p90)} VP for you`;
  if (pWin >= 0.65) return `<b>You're favoured</b> (typical margin ${sg(m)} VP; ${span}): trade safely, deny their outs, don't over-commit.`;
  if (pLose >= 0.65) return `<b>You're behind</b> (typical margin ${sg(m)} VP; ${span}): you need more objectives or kills — see what changes the result.`;
  return `<b>Even game</b>: it is decided on the table (${span}).`;
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
      <div class="tiny muted" id="mission-board-note">Measured on the board plan <b>${esc(bm?.name ?? '')}</b>: who controls each objective (OC of units in range), Behind Enemy Lines, quarters, edges, centre and No Man's Land, and what each unit can attack from where it stands (range and charge reach; several units on one target add up). Steps map to battle rounds (Turn 1 = round 1; the last step carries on).${bm && bm.stepsPlanned < 2 ? ' <b>Only the deployment is planned</b> — add turns on the Board tab.' : ''}${m.pairs?.table ? '' : ' Working out unit-vs-unit odds…'}</div>
      ${missing.length ? `<div class="small" style="color:var(--warn-ink);margin-top:4px" id="mission-plan-missing">Only units placed on the board count (${missing.join(' · ')}) — place the rest on the Board tab or they hold nothing and score nothing.</div>` : ''}
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
  'outflank': 'Two units within 6" of opposite battlefield edges, one or more of them outside your territory (5 VP); one unit on an edge outside your territory is 3 VP.',
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
    const onBoard = sourcePlan() != null && (side === m.me || m.enemyFrom === 'board');
    const real = REAL_RATES[c.id];
    const tag = dead ? '<span class="pill bad">Dead</span>'
      // where-your-units-are cards: your estimate, the board plan, or the real-game rate — never a silent guess
      : est[c.id] != null && !fixedMode ? '<span class="pill mine">Your estimate</span>'
      : position && onBoard ? '<span class="pill good">Board plan</span>'
      : position ? `<span class="pill ask">${real ? 'Real-game rate' : 'No data'}</span>`
      : perDraw == null ? '' : perDraw >= 4 ? '<span class="pill good">Strong</span>' : perDraw >= 3 ? '<span class="pill">OK</span>' : '<span class="pill weak">Hard</span>';
    const pcts = (by) => by.map(v => (v == null ? '–' : `${Math.round(v * 100)}%`)).join(' / ');
    const realLine = real ? `<div class="tiny muted" style="margin-top:4px">Real games: the 10th edition ${esc(real.like)} card was scored ${pcts(real.by)} of the times it was drawn in rounds 1 to 5 (${esc(REAL_RATES_SOURCE)}). No 11th edition card statistics are published yet.</div>` : '';
    // (the tag follows the name and wraps under it on a narrow phone: no column of its own)
    return `<tr class="card-row" data-card="${c.id}"><td><button class="linkish" data-action="mission-card" data-id="${c.id}">${esc(c.name)}</button>${c.fixed ? ' <span class="tiny muted">F</span>' : ''} ${tag}</td>
      <td>${dead ? '–' : fixedMode ? (perDraw == null ? '…' : fmt(perDraw, 1)) : estPickHtml(c, side, est[c.id], perDraw)}</td><td class="muted">${fixedMode && c.fixed ? c.fixedMax : c.max}</td><td>${dead || quick == null ? '–' : pct(quick)}</td></tr>
      ${open ? `<tr class="card-detail"><td colspan="4">${cardFace(c, { esc })}
        ${dead ? `<div class="tiny" style="margin-top:4px">No targets in the ${side === m.me ? 'enemy' : 'your'} army: discard it (and draw again if the card allows).</div>`
          : `<div class="tiny muted" style="margin-top:4px">${est[c.id] != null ? 'Using your estimate.'
              : c.kind === 'kill' ? 'App estimate: from units destroyed in the forecast and which enemy units are valid targets.'
              : position ? (onBoard ? 'App estimate: measured from the board plan.' : real ? `Depends on where units are, which the grid does not show: the app uses the real-game rate below × ${MODEL.cardPlay} (11th edition cards are kept until scored). Set your own estimate if you know better.` : `Depends on where units are, which the grid does not show, and no real-game data exists for this card: the app assumes ${Math.round(50 * MODEL.cardPlay)}% a turn. Set your own estimate.`)
              : onBoard ? 'App estimate: from the objectives your units hold on the board plan.' : 'App estimate: from your objective plan; when the plan does not give it, you play for the card at the real-game rate.'}</div>${realLine}
            ${fixedMode ? '<div class="tiny muted">Taken as Fixed: your estimate applies to Tactical play only.</div>' : estimateHtml(c, side, est[c.id], perDraw)}`}</td></tr>` : ''}`;
  };
  if (m.cardsLook === 'faces') {
    // every card drawn as a card, best first, with the app's numbers under each
    const face = (r) => cardFace(r.c, { esc, foot: `${r.dead ? '<span class="pill bad">Dead</span> no targets in this army' : `VP if drawn <b>${r.perDraw == null ? '…' : fmt(r.perDraw, 1)}</b> · quick <b>${r.quick == null ? '–' : pct(r.quick)}</b>`}` });
    return `<div class="row" style="gap:6px;flex-wrap:wrap">${ctx.seg('mission-sheet-side', side, [[m.me, 'My cards'], [other(m.me), 'Their cards']], 'compact')}${ctx.seg('mission-cards-look', 'faces', [['list', '☰ List'], ['faces', '🂠 Cards']], 'compact')}</div>
      <div class="cf-grid" id="card-faces" style="margin-top:8px">${rows.map(face).join('')}</div>
      <div class="tiny muted">The cards in the app's words (a summary, not the printed text). Best first for ${side}.</div>`;
  }
  return `<div class="row" style="gap:6px;flex-wrap:wrap">${ctx.seg('mission-sheet-side', side, [[m.me, 'My cards'], [other(m.me), 'Their cards']], 'compact')}${ctx.seg('mission-cards-look', 'list', [['list', '☰ List'], ['faces', '🂠 Cards']], 'compact')}</div>
    <table class="dist cards" style="margin-top:6px"><thead><tr><th>Card</th><th>VP if drawn</th><th>Max</th><th>Quick</th></tr></thead><tbody>${rows.map(row).join('')}</tbody></table>
    <div class="tiny muted">VP if drawn: average VP the card earns for ${side} when it comes up (the app's estimate, or yours). Max: the most it can pay when it scores. Quick: how often it scores by the end of the next turn. F = can be taken as Fixed. Tap a VP if drawn number to set your own (0 up to Max) — e.g. Assassination 3 of 5 if you are only fairly sure you can kill a character; pick “app” to go back. Tap a card name for its rules.</div>
`;
}

// beside the sheet: what to keep ready for, and the units that feed the kill cards
function cardsSideHtml() {
  const m = ms(), esc = ctx.esc;
  const side = m.sheetSide ?? m.me;
  if (!profileOf(other(m.me)) || !profileOf(m.me)) return '';
  // keep-ready: my best live non-kill cards by expected VP over the game
  const mine = m.result?.[m.me]?.cards ?? {};
  const ready = SECONDARIES.filter(c => KEEP_READY[c.id] && !cardDead(c.id, profileOf(other(m.me)).profile) && (m.est?.[m.me]?.[c.id] ?? 1) > 0)
    .map(c => ({ c, ev: (mine[c.id]?.perDraw ?? 0) * (mine[c.id]?.drawRate ?? 0) }))
    .sort((a, b) => b.ev - a.ev).slice(0, 5);
  return `${side === m.me ? `<h2 class="sub">Keep ready for</h2><ul class="keep" id="mission-keep">${ready.map(x => `<li><b>${esc(x.c.name)}</b> — ${esc(KEEP_READY[x.c.id])}</li>`).join('')}</ul>` : ''}
    <h2 class="sub" style="margin-top:14px">${side === m.me ? 'Hit list: enemy units worth secondary VP' : 'Your units they score from'}</h2>${hitListHtml(side)}`;
}

// the VP-if-drawn cell: tap the number to pick your own value (0 to max in 0.5
// steps) or go back to the app's estimate
function estPickHtml(c, side, value, appValue) {
  const app = appValue == null ? '…' : fmt(appValue, 1);
  const opts = [`<option value=""${value == null ? ' selected' : ''}>${app} app</option>`];
  for (let v = 0; v <= c.max + 1e-9; v += 0.5) opts.push(`<option value="${v}"${value != null && Math.abs(value - v) < 1e-9 ? ' selected' : ''}>${fmt(v, 1)}</option>`);
  return `<select class="est-pick${value != null ? ' mine' : ''}" data-input="mission-est-pick" data-side="${side}" data-id="${c.id}" aria-label="${ctx.esc(c.name)}: your VP if drawn (max ${c.max})" title="Tap to set your own VP if drawn (max ${c.max})">${opts.join('')}</select>`;
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
    if (u.models >= 13) tags.push('A Grievous Blow (13+ models, leaders counted)');
    return { u, tags, value: tags.length * 5 + u.points / 100 };
  }).filter(x => x.tags.length).sort((a, b) => b.value - a.value);
  if (!rows.length) return '<p class="muted small">No units feed the kill cards (characters, W10+ or 13+ models).</p>';
  return `<ul class="keep" id="mission-hit-${side}">${rows.map(x => `<li><b>${esc(x.u.name)}</b> <span class="muted">(${x.u.points} pts)</span> — ${x.tags.map(esc).join(' · ')}</li>`).join('')}</ul>
    <div class="tiny muted">Every kill also feeds No Prisoners (2 VP per unit) and, on objectives, Overwhelming Force.</div>`;
}

// ---- in-game tracker

// Fixed Missions: the two cards are active all battle and cannot be discarded; each pays at most 20VP in a game
function fixedHtml(X) {
  const m = ms(), g = m.game, esc = ctx.esc;
  const ids = m.modes[X].fixed;
  if (!ids.length) return '<div class="tiny muted" style="margin-top:6px">Fixed: pick two cards under Plan → Assumptions.</div>';
  const row = (id) => {
    const c = SECONDARY_BY_ID[id], vp = g[X].fixedVp?.[id] ?? 0, full = vp >= RULES.fixedCardCap;
    const open = m.handOpen === `${X}:${id}`;
    return `<div class="hand-row" data-fixed="${id}"><span class="grow"><button class="linkish" data-action="mission-hand-info" data-side="${X}" data-id="${id}" aria-expanded="${open}">${esc(c.name)}</button>
        <span class="tiny ${full ? 'good' : 'muted'}" data-fixed-vp="${id}"> ${vp} of ${RULES.fixedCardCap} VP${full ? ' · full' : ''}</span>
        ${open ? `<div class="tiny" data-text="${id}">${esc(c.fixedText ?? c.text)}</div>` : ''}</span>
      ${PT.fixedSteps(c.fixedText).map(v => `<button class="mini score" data-action="mission-fixed-score" data-side="${X}" data-id="${id}" data-vp="${v}" ${full ? 'disabled' : ''} aria-label="${esc(c.name)} scored ${v} VP">+${v}</button>`).join('')}
      <button class="mini" data-action="mission-fixed-score" data-side="${X}" data-id="${id}" data-vp="-1" ${vp ? '' : 'disabled'} aria-label="${esc(c.name)}: take 1 VP back">−1</button></div>`;
  };
  return `<div class="lab tiny muted" style="margin-top:10px">Fixed Missions — active all battle, never discarded, at most ${RULES.fixedCardCap} VP each. Tap what a card scored (it is added to the secondary VP)</div>
    <div id="fixed-${X}">${ids.map(row).join('')}</div>`;
}

// one player's side of the table: scores (steppers), the cards in hand with what
// they can pay, the draw box, units destroyed
function playerCard(X) {
  const m = ms(), g = m.game, esc = ctx.esc;
  const deck = SECONDARIES.map(c => c.id).filter(id => !g[X].hand.includes(id) && !g[X].used.includes(id));
  const mode = m.modes[X].mode;
  const score = (k, label) => `<div class="grow"><div class="lab tiny muted">${label}</div><div class="stepper score">
      <button data-action="mission-score-step" data-side="${X}" data-k="${k}" data-delta="-1" aria-label="${X} ${label} minus 1">−</button>
      <input class="num" type="number" inputmode="numeric" min="0" max="45" data-input="mission-score" data-side="${X}" data-k="${k}" value="${g[X][k]}" aria-label="${X} ${label}">
      <button data-action="mission-score-step" data-side="${X}" data-k="${k}" data-delta="1" aria-label="${X} ${label} plus 1">+</button>
      <button data-action="mission-score-step" data-side="${X}" data-k="${k}" data-delta="5" aria-label="${X} ${label} plus 5">+5</button></div></div>`;
  const total = g[X].primary + g[X].secondary + (m.battleReady[X] ? RULES.battleReady : 0);
  return `<div class="card" data-player="${X}">
      <div class="row"><div class="title grow" style="color:var(--side-${X.toLowerCase()}-ink)">${X} · ${esc(ctx.state.armies[X].faction)}${X === m.me ? ' (me)' : ''}</div>
        <div class="small"><b id="play-total-${X}">${total}</b> VP${m.battleReady[X] ? ' <span class="tiny muted">incl. 10</span>' : ''}</div></div>
      <div class="row" style="gap:10px;margin-top:6px;flex-wrap:wrap">${score('primary', 'Primary VP')}${score('secondary', 'Secondary VP')}</div>
      <div class="row cp-row" style="gap:8px;margin-top:8px;align-items:center;flex-wrap:wrap"><span class="lab tiny muted">Command points</span>
        <div class="stepper cp"><button data-action="mission-cp" data-side="${X}" data-delta="-1" aria-label="${X} spends 1CP">−</button>
          <div class="val" id="cp-${X}">${g[X].cp ?? 0}</div>
          <button data-action="mission-cp" data-side="${X}" data-delta="1" aria-label="${X} gains 1CP">+</button></div>
        ${g[X].cpAsk ? (PT.canExtraCp(g, X) ? `<button class="mini cpx" data-action="mission-cp-discard" data-side="${X}" id="cp-discard-${X}">+1CP for the discard</button>`
          : `<span class="tiny muted" id="cp-discard-${X}">No CP for this discard: the one extra CP of round ${g.round} is taken.</span>`) : ''}
        ${mode === 'tactical' ? `<button class="mini cpx" data-action="mission-swap" data-side="${X}" id="swap-${X}" ${g[X].swapped ? 'disabled' : ''}>${g[X].swapped ? `Card swap used (round ${g[X].swapped})` : '↻ New card for 1CP (once)'}</button>` : ''}
      </div>
      ${mode === 'tactical' ? `<div class="lab tiny muted" style="margin-top:10px">Cards in hand — tap the VP it scored, ✕ to discard, its name to see it</div>
        <div id="hand-${X}">${handHtml(X)}</div>
        <div class="row" style="gap:6px;margin-top:6px;align-items:center"><select class="sel grow" data-input="mission-draw" data-side="${X}" aria-label="Card ${X} drew"><option value="">＋ Drew a card…</option>${deck.map(id => `<option value="${id}">${esc(SECONDARY_BY_ID[id].name)}</option>`).join('')}</select><button class="btn" data-action="mission-draw-random" data-side="${X}" id="draw-random-${X}" ${deck.length ? '' : 'disabled'} title="Draw at random, shown full screen for both players">🎲 Random</button></div>
        ${X === (g.next ?? m.first ?? 'A') && inProgress() ? `<div class="tiny muted" id="drawn-${X}">Drawn this turn: ${Math.min(RULES.drawPerTurn, g.drawn ?? 0)} of ${RULES.drawPerTurn}${(g.drawn ?? 0) < RULES.drawPerTurn && !m.table ? ` — the forecast draws the other ${RULES.drawPerTurn - (g.drawn ?? 0)} at random` : ''}.</div>` : ''}
        <div class="tiny muted" id="odds-${X}">${deck.length} cards left${m.table ? '.' : `: each has a ${pct(Math.min(1, RULES.drawPerTurn / Math.max(1, deck.length)))} chance to come up next draw.`}${g[X].used.length ? ` Done: ${g[X].used.map(id => esc(SECONDARY_BY_ID[id].name)).join(', ')}.` : ''}</div>`
        : fixedHtml(X)}
      <details class="more" style="margin-top:6px" data-details="mission-dead-${X}" ${isOpen(`mission-dead-${X}`) ? 'open' : ''}><summary>${X}'s units destroyed (${g[X].destroyed.length})</summary>
        <div class="chips">${ctx.state.armies[X].units.map(u => ctx.chip('mission-dead', g[X].destroyed.includes(u.name), u.name, `data-side="${X}" data-name="${esc(u.name)}"`)).join('')}</div></details>
    </div>`;
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
    case 'mission-show': m.show = 'score'; persist(); return 'render';
    case 'mission-phase': g.phase = el.dataset.value; persist(); return 'render';
    case 'mission-strat': {
      const st = stratsOf(X).find(s => s.name === el.dataset.name);
      if (!st) return null;
      remember(`${X} ${st.name}`);
      const r = PT.useStrat(g, X, st, turnOf());
      console.log(`[mission] ${X} uses ${st.name} (${st.cp}CP): ${r.ok ? 'ok' : r.why}`);
      persist();
      return 'render';
    }
    case 'mission-show-flip': m.flip = !m.flip; persist(); return 'render';
    case 'mission-show-close': m.show = null; persist(); return 'render';
    case 'mission-draw-random': if (!drawRandom(X)) return null; break;
    case 'mission-first':
      m.first = el.dataset.value === 'roll' ? null : el.dataset.value;
      // (before any turn is done the turn shown is the first player's)
      if (isOpening()) g.next = null;
      break;
    case 'mission-mode': m.modes[X].mode = el.dataset.value; break;
    case 'mission-fixed': {
      const f = m.modes[X].fixed, id = el.dataset.id;
      if (f.includes(id)) f.splice(f.indexOf(id), 1); else { f.push(id); if (f.length > 2) f.shift(); }
      break;
    }
    case 'mission-kills':
      m.killAuto ??= { A: true, B: true };
      if (el.dataset.value === 'auto') m.killAuto[X] = true;
      else { m.killAuto[X] = false; m.killRate[X] = Number(el.dataset.value); }
      break;
    case 'mission-edge': m.edge = Number(el.dataset.value); break;
    case 'mission-mode-use': {
      const key = el.dataset.key.slice(5);
      m.modes[m.me] = key === 'tactical' ? { mode: 'tactical', fixed: m.modes[m.me].fixed } : { mode: 'fixed', fixed: key.split('+') };
      break;
    }
    case 'mission-action': m.actionP[X] = Number(el.dataset.value); break;
    case 'mission-ready': m.battleReady[X] = !m.battleReady[X]; break;
    case 'mission-plan': {
      const p = plan(), r = el.dataset.r, o = el.dataset.o;
      const cur = p[r][o] ?? 'c';
      p[r][o] = cur === 'A' ? 'B' : cur === 'B' ? 'c' : 'A';
      break;
    }
    case 'mission-sheet-side': m.sheetSide = el.dataset.value; m.cardOpen = null; persist(); refresh(); return null;
    case 'mission-cards-look': m.cardsLook = el.dataset.value; persist(); refresh(); return null;
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
    // a round or turn picked by hand: what was scored so far stays under the round it was scored in
    case 'mission-round': remember('battle round'); PT.flushTurn(g, turnOf()); g.round = Number(el.dataset.value); g.drawn = 0; g.over = false; break;
    case 'mission-next':
      remember('turn'); PT.flushTurn(g, turnOf());
      if (isOpening()) m.first = el.dataset.value;
      g.next = el.dataset.value; g.drawn = 0; g.over = false;
      break;
    case 'mission-hand': {
      const id = el.dataset.id;
      remember(`${SECONDARY_BY_ID[id]?.name ?? 'card'} ${el.dataset.do === 'scored' ? 'scored' : 'discarded'}`);
      g[X].hand = g[X].hand.filter(h => h !== id);
      if (!g[X].used.includes(id)) g[X].used.push(id);
      // "+5": the card was scored for that much (✕ = discarded, no VP)
      if (el.dataset.do === 'scored' && el.dataset.vp) g[X].secondary = Math.min(RULES.secondaryCap, g[X].secondary + Number(el.dataset.vp));
      // a discard in your own turn can be the one for 1CP (not the discard of a card swap)
      else if (el.dataset.do === 'discard' && X === turnOf()) { if (g[X].swapPending) g[X].swapPending = false; else g[X].cpAsk = true; }
      break;
    }
    case 'mission-fixed-score': {
      remember(`${X} ${SECONDARY_BY_ID[el.dataset.id]?.name ?? 'Fixed card'}`);
      const got = PT.scoreFixed(g, X, el.dataset.id, Number(el.dataset.vp));
      console.log(`[mission] Fixed card ${el.dataset.id}: ${got >= 0 ? '+' : ''}${got} VP for ${X} (${g[X].fixedVp[el.dataset.id]} of ${RULES.fixedCardCap})`);
      break;
    }
    case 'mission-score-step': {
      const k = el.dataset.k === 'primary' ? 'primary' : 'secondary';
      remember(`${X} ${k} VP`);
      g[X][k] = Math.max(0, Math.min(45, (g[X][k] || 0) + Number(el.dataset.delta)));
      break;
    }
    // command points: + / − by hand (stratagems, army rules); the Command phase CP comes with "Turn done"
    case 'mission-cp': remember(`${X} CP`); g[X].cp = Math.max(0, (g[X].cp || 0) + Number(el.dataset.delta)); persist(); return 'render';
    case 'mission-cp-discard': remember(`${X} CP for a discard`); PT.extraCp(g, X); g[X].cpAsk = false; persist(); return 'render';
    case 'mission-swap': remember(`${X} card swap`); g[X].swapped = g.round; g[X].swapPending = true; g[X].cp = Math.max(0, (g[X].cp || 0) - 1); persist(); return 'render';
    // once-per-battle rules ticked as used (Intel > By phase)
    case 'mission-once': { const o = (g.once ??= { A: {}, B: {} }); const id = el.dataset.tick; if (o[X][id]) delete o[X][id]; else o[X][id] = true; persist(); return 'render'; }
    case 'mission-once-reset': (g.once ??= { A: {}, B: {} })[X] = {}; persist(); return 'render';
    case 'mission-undo': {
      const u = PT.popUndo(m.undo);
      if (!u) return 'render';
      m.game = PT.ensureGame(u.game.game); m.first = u.game.first ?? null;
      console.log(`[mission] undo: ${u.label}`);
      break;
    }
    case 'mission-hand-info': { const k = `${X}:${el.dataset.id}`; m.handOpen = m.handOpen === k ? null : k; return 'render'; }
    case 'mission-table': m.table = !m.table; if (m.table) m.tab = 'play'; toTop = true; persist(); if (!m.table) scheduleForecast(); return 'render';
    case 'mission-awake': m.awake = m.awake === false; persist(); return 'render';
    case 'mission-clock-mode': m.clock.mode = el.dataset.value; persist(); return 'render';
    case 'mission-clock-lock': m.clock.lock = !PT.chessLocked(m.clock); persist(); return 'render';
    case 'mission-clock-len': PT.roundSetLen(m.clock, Number(el.dataset.value)); persist(); return 'render';
    case 'mission-clock-bank': PT.chessSetBank(m.clock, Number(el.dataset.value)); persist(); return 'render';
    case 'mission-clock': {
      const c = m.clock, now = Date.now();
      switch (el.dataset.do) {
        case 'start': PT.roundStart(c, now); break;
        case 'pause': PT.roundPause(c, now); break;
        case 'reset': PT.roundReset(c); break;
        case 'minus': PT.roundSetLeft(c, PT.roundLeft(c, now) / 60000 - 5, now); break;
        case 'plus': PT.roundSetLeft(c, PT.roundLeft(c, now) / 60000 + 5, now); break;
        // a tap on the running player's own tile pauses the clock - not while the pause is locked
        case 'run': if (c.running !== X) PT.chessRun(c, X, now); else if (!PT.chessLocked(c)) PT.chessPause(c, now); break;
        case 'chess-pause':
          // UKTC: "Once started, only a referee may pause the chess clock" (under 5 minutes a player may, to call one)
          if (PT.chessLocked(c) && !PT.chessMayPause(c, now) && !(globalThis.confirm?.('Pause the chess clock?\n\nOnce started, only a referee may pause it (UKTC). A player with under 5 minutes left may pause it to call a referee.') ?? true)) return null;
          PT.chessPause(c, now);
          break;
        case 'chess-reset': PT.chessReset(c); break;
        default:
      }
      persist();
      return 'render';
    }
    case 'mission-turn-done': {
      // to the other player; after the second turn of a round, to the next battle round;
      // that player's Command phase starts: 1CP each
      if (g.over) return 'render';
      remember('turn done');
      // the player whose turn ends before any other turn of round 1 took the first turn
      if (m.first == null && g.round === 1 && !g.turnsDone) m.first = turnOf();
      const before = { round: g.round, turn: turnOf() };
      const res = PT.endTurn(g, m.first, RULES.rounds);
      // the Board's live table keeps the position of the turn that ended and follows the new one
      boardTurnDone(before, { round: g.round, turn: turnOf() });
      for (const P of ['A', 'B']) { g[P].cpAsk = false; g[P].swapPending = false; }
      if (m.clock.mode === 'chess' && m.clock.running) { if (res.ended) PT.chessPause(m.clock, Date.now()); else PT.chessRun(m.clock, g.next, Date.now()); }
      console.log(`[mission] turn done -> round ${g.round}, ${g.next}'s turn${res.ended ? ' (battle over)' : ''}; CP A ${g.A.cp} B ${g.B.cp}`);
      // the end of the battle: the game is saved (Saved games), under its name if it has one
      if (res.ended) ctx.autoSave?.('the battle is over');
      break;
    }
    case 'mission-tab': m.tab = el.dataset.value; toTop = true; persist(); return 'render';
    case 'mission-dead': {
      remember(`${el.dataset.name} destroyed`);
      const n = el.dataset.name, d = g[X].destroyed;
      if (d.includes(n)) d.splice(d.indexOf(n), 1); else d.push(n);
      break;
    }
    // a new game: the tracker is cleared (Undo brings it back) and the first turn is rolled for again
    case 'mission-reset': ctx.autoSave?.('a new game'); remember('new game'); m.game = newGame(); m.first = null; m.savedId = null; boardNewGame(); break;
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
    if (id && !g[X].hand.includes(id)) {
      remember(`${SECONDARY_BY_ID[id]?.name ?? 'card'} drawn`);
      g[X].hand.push(id);
      // the player whose turn it is draws two cards in the Command phase: the forecast draws the rest
      if (X === (g.next ?? m.first ?? 'A')) g.drawn = (g.drawn ?? 0) + 1;
    }
    persist(); scheduleForecast();
    return true;
  }
  if (el.dataset.input === 'mission-est-pick') {
    // tap the VP-if-drawn number: blank = the app's estimate
    m.est ??= { A: {}, B: {} };
    const id = el.dataset.id, max = SECONDARY_BY_ID[id]?.max ?? 5;
    if (el.value === '') delete m.est[X][id];
    else m.est[X][id] = Math.max(0, Math.min(max, Number(el.value)));
    console.log(`[mission] estimate ${X} ${id} -> ${m.est[X][id] ?? 'app'}`);
    persist(); scheduleForecast();
    return true;
  }
  if (el.dataset.input === 'mission-score') {
    // no re-render: the player may be moving on to the next score box
    remember(`${X} ${el.dataset.k} VP typed`, true);
    g[X][el.dataset.k] = Math.max(0, Math.min(45, Number(el.value) || 0));
    persist(); scheduleForecast();
    // the parts of the page that follow the score, re-drawn in place
    const set = (id, html) => { const n = document.getElementById(id); if (n) n.innerHTML = html; };
    set('play-turn', turnLineHtml());
    set('play-caps', capsHtml());
    for (const P of ['A', 'B']) set(`play-total-${P}`, String(totalVp(P)));
    const sheet = document.getElementById('play-sheet');
    if (sheet) sheet.outerHTML = sheetHtml();
    const undo = document.getElementById('play-undo');
    if (undo) undo.disabled = !m.undo.length;
    if (m.table || g.over) set('fc-mini', miniHtml());
    return 'quiet';
  }
  return false;
}

// ---- the clock on screen: only the numbers are re-drawn, twice a second
let ticker = null;
function tick() {
  const c = ms().clock, now = Date.now();
  const set = (id, text) => { const el = document.getElementById(id); if (el && el.textContent !== text) el.textContent = text; };
  if (c.mode === 'round') {
    set('clock-round', PT.fmtClock(PT.roundLeft(c, now)));
    const pace = document.getElementById('clock-pace');
    if (pace) { const h = paceHtml(now); if (pace.dataset.h !== h) { pace.dataset.h = h; pace.innerHTML = h; } }
  } else if (c.mode === 'chess') { set('clock-A', PT.fmtClock(PT.chessLeft(c, 'A', now))); set('clock-B', PT.fmtClock(PT.chessLeft(c, 'B', now))); }
  set('mini-clock', clockMiniText(now));
}
function syncTicker() {
  const c = ms().clock;
  const live = (c.mode === 'round' && PT.roundRunning(c)) || (c.mode === 'chess' && !!c.running);
  if (live && !ticker) ticker = setInterval(tick, 500);
  else if (!live && ticker) { clearInterval(ticker); ticker = null; }
}

// ---- the screen stays on while the Play view is open (the phone lies on the table)
let wake = null, wakeBusy = false, wakeAgain = false, wakeWhy = '';
export async function syncWake() {
  if (!ctx) return;
  // a request or a release is under way: look again when it is done
  if (wakeBusy) { wakeAgain = true; return; }
  const m = ctx.state.mission;
  const want = !!m && ctx.state.view === 'mission' && (m.tab === 'play' || m.table) && m.awake !== false && document.visibilityState === 'visible';
  wakeBusy = true;
  try {
    if (want && !wake && navigator.wakeLock) {
      wake = await navigator.wakeLock.request('screen');
      wake.addEventListener?.('release', () => { wake = null; });
      console.log('[calc] screen wake lock on');
    } else if (!want && wake) { const w = wake; wake = null; await w.release(); console.log('[calc] screen wake lock off'); }
  } catch (e) { const why = String(e?.name ?? e); if (why !== wakeWhy) { wakeWhy = why; console.log(`[calc] screen wake lock not available: ${why}`); } }
  wakeBusy = false;
  if (wakeAgain) { wakeAgain = false; syncWake(); }
}
if (typeof document !== 'undefined') document.addEventListener('visibilitychange', () => { syncWake(); });

let toTop = false;   // a new Mission view starts at its top
export function missionAfterRender() {
  if (toTop) { toTop = false; window.scrollTo(0, 0); }
  syncTicker();
  // ("closed in table mode" is said once: it is on screen now, the next change removes it)
  if (ms().tableNotice) { delete ms().tableNotice; window.scrollTo(0, 0); }
  if (ms().table) return;
  // re-forecast when anything it depends on changed (lists, layout on the Board tab, plan, tracker)
  const P = forecastParams({ trials: 0 });
  const sig = P ? JSON.stringify(P) : '';
  // the Fixed / Tactical table is worked out when the Cards view is open (not with every forecast)
  let needModes = false;
  if (P && modeWanted()) { const want = modeSig(); needModes = ms().modeCompare?.sig !== want && !(ms().busy && runModes === want); }
  // Plan and Cards need a full run of these inputs; Play only needs a run of them (a full one will do)
  const due = liteRun() ? sig !== lastSig : sig !== lastFull;
  if (due || (!ms().result && !ms().busy) || needModes) scheduleForecast(sig);
}

// for tests
export function _missionDebug() {
  const m = ms();
  return { me: m.me, first: m.first, table: !!m.table, clock: m.clock, undo: m.undo.length, wake: !!wake, result: m.result, levers: m.levers, compare: m.compare, busy: !!m.busy, objectives: objectives(), plan: plan(), game: m.game, source: m.source, pairsReady: !!m.pairs?.table && m.pairs.sig === pairSig(), kill: autoKill(), killRate: { A: killRateOf('A'), B: killRateOf('B') }, board: sourcePlan() != null ? boardModel(sourcePlan()) : null, params: forecastParams({ trials: 10 }) };
}
