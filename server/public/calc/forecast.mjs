// Game VP forecast: simulates the rest of a battle many times for both
// players — the tactical secondary deck (draws, when-drawn rules, scoring),
// each player's primary mission from the objectives they plan to hold, and
// units destroyed each turn — and returns the spread of final scores.
//
// It is a planning model, not a game engine: who controls each objective in
// each battle round comes from the plan (A / B / contested), kills come from
// a per-turn rate, and cards that depend on where units are (Behind Enemy
// Lines, Outflank, ...) from the player's own rating of them — the app does
// not guess positions. Card VP values and the caps are exact
// (missions-11e.mjs). Pure module, unit-tested (tests/calc-forecast.test.mjs).

import { RULES, SECONDARIES, SECONDARY_BY_ID, PRIMARIES } from './missions-11e.mjs';
import { sideFacts } from './planeval.mjs';

const other = (p) => (p === 'A' ? 'B' : 'A');
const clamp01 = (x) => Math.max(0, Math.min(1, x));

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function poisson(lambda, rnd) {
  if (lambda <= 0) return 0;
  const L = Math.exp(-lambda);
  let k = 0, p = 1;
  do { k++; p *= rnd(); } while (p > L);
  return k - 1;
}
function binom(n, p, rnd) { let c = 0; for (let i = 0; i < n; i++) if (rnd() < p) c++; return c; }

// ---------------------------------------------------------------------------
// Army profile (what the cards care about)

/**
 * units: [{ name, models, characters, charactersW4, w10, aircraft, fast, reserves, points, keywords }]
 * -> { units, count, fast, reserves, spread }
 */
export function armyProfile(units) {
  const us = units.map(u => ({
    name: u.name, models: u.models ?? 1, characters: u.characters ?? 0, charactersW4: u.charactersW4 ?? 0,
    w10: u.w10 ?? 0, ss13: (u.bodyguardModels ?? u.models ?? 1) >= 13, aircraft: !!u.aircraft,
    fast: !!u.fast, reserves: !!u.reserves, points: u.points ?? 0,
  }));
  const ground = us.filter(u => !u.aircraft);
  const fast = ground.filter(u => u.fast).length, reserves = ground.filter(u => u.reserves).length;
  return { units: us, count: ground.length, fast, reserves, spread: clamp01((ground.length + fast + reserves) / 14) };
}

/** Is a secondary dead against this enemy army (its targets don't exist)? */
export function cardDead(id, enemy) {
  const c = SECONDARY_BY_ID[id];
  if (c?.target === 'character') return !enemy.units.some(u => u.characters > 0);
  if (c?.target === 'w10') return !enemy.units.some(u => u.w10 > 0);
  if (c?.target === 'ss13') return !enemy.units.some(u => u.ss13);
  return false;
}

// ---------------------------------------------------------------------------
// Objectives

/**
 * Objective classes from the layout, seen by player P:
 *   home (P's), oppHome, exp (No Man's Land, P's half), oppExp (enemy half), central.
 * objectives: [{ id, cls: 'home'|'exp'|'central', side: 'A'|'B'|null }]
 */
function holdings(objs, owner, P) {
  const h = { total: 0, home: 0, oppHome: 0, exp: 0, oppExp: 0, central: 0, nonHome: 0, nml: 0, oppTerritory: 0, ids: [] };
  for (const o of objs) {
    if (owner[o.id] !== P) continue;
    h.total++; h.ids.push(o.id);
    if (o.cls === 'home') { if (o.side === P) h.home++; else { h.oppHome++; h.oppTerritory++; } }
    else if (o.cls === 'central') { h.central++; h.nml++; }
    else if (o.side === P) { h.exp++; h.nml++; } else { h.oppExp++; h.nml++; h.oppTerritory++; }
  }
  h.nonHome = h.total - h.home;
  return h;
}

// ---------------------------------------------------------------------------
// Primary missions. ctx: { r, h, hOpp, kills (victims this turn), lostPrev,
// newly (non-home objectives you hold now but did not last round), pAct,
// ms (mission state), rnd, fObj }. Returns { C, EOT } for this player's turn
// (C = end of Command phase from R2; in R5 it is scored at the end of the turn,
// same VP) and endOfBattle(ctx) for end-of-battle VP.

const killedOnObjective = (ctx) => ctx.kills.some(v => v.onObj);
const more = (ctx) => ctx.h.total > ctx.hOpp.total;

const PRIMARY_FN = {
  'Battlefield Dominance': (c) => ({
    EOT: c.r <= 2 && more(c) ? 2 : 0,
    C: c.r >= 2 ? 3 * c.h.total + (c.h.home ? 2 * c.h.nonHome : 0) : 0,
  }),
  'Determined Acquisition': (c) => ({ EOT: 2 * c.newly, C: c.r >= 2 ? 3 * c.h.total + 3 * c.h.oppTerritory : 0 }),
  'Immovable Object': (c) => ({ EOT: c.h.central ? 3 : 0, C: c.r >= 2 ? 5 * c.h.nonHome : 0 }),
  'Inescapable Dominion': (c) => ({ EOT: c.h.total >= 3 ? 4 : 0, C: c.r >= 2 ? (c.h.total >= 2 ? 5 : 0) + (more(c) ? 4 : 0) : 0 }),
  'Purge and Secure': (c) => ({ EOT: (killedOnObjective(c) ? 3 : 0) + (c.r >= 2 && c.newly ? 3 : 0), C: c.r >= 2 ? 4 * c.h.nonHome : 0 }),
  'Consecrate': (c) => {
    // each kill by a unit standing near a non-home objective can consecrate it (permanent)
    const can = Math.max(0, 4 - (c.ms.consecrated ?? 0));
    const add = Math.min(can, binom(c.kills.length, 0.45 * c.pAct, c.rnd));
    c.ms.consecrated = (c.ms.consecrated ?? 0) + add;
    if (c.h.oppHome && add) c.ms.oppHomeCons = c.ms.oppHomeCons || c.rnd() < 0.5;
    const n = c.ms.consecrated;
    return { EOT: n >= 3 ? 6 : n >= 1 ? 3 : 0, C: c.r >= 2 ? (c.h.nonHome ? 4 : 0) + (more(c) ? 4 : 0) : 0 };
  },
  "Destroyer's Wrath": (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 && c.kills.length > c.lostPrev ? 4 : 0), C: c.r >= 2 ? (c.h.nonHome ? 4 : 0) + (more(c) ? 6 : 0) : 0 }),
  'Meatgrinder': (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 ? (c.kills.length > c.lostPrev ? 5 : 0) + (c.h.oppHome ? 5 : 0) : 0), C: c.r >= 2 && c.h.nonHome ? 4 : 0 }),
  'Punishment': (c) => {
    // up to 3 condemned enemy units each turn: a kill hits one with probability ~3 / units left
    const pc = Math.min(1, 3 / Math.max(1, c.enemyAlive + c.kills.length));
    return { EOT: c.kills.some(() => c.rnd() < pc) ? 5 : 0, C: c.r >= 2 ? (c.h.nonHome ? 4 : 0) + (more(c) ? 5 : 0) : 0 };
  },
  'Unstoppable Force': (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 && c.newly ? 3 : 0), C: c.r >= 2 ? 4 * c.h.nonHome : 0 }),
  'Gather Intel': (c) => {
    let eot = c.r === 1 && c.h.central ? 6 : 0;
    if (c.r >= 2) {
      // tune.intelOnce: one token per no-man's-land objective, ever
      const can = c.tune?.intelOnce ? Math.min(c.h.nml, Math.max(0, (c.nNml ?? 3) - (c.ms.markers ?? 0))) : c.h.nml;
      const done = binom(can, c.pAct, c.rnd);
      c.ms.markers = (c.ms.markers ?? 0) + done;
      if (done && c.h.oppHome) c.ms.markerOppHome = true;
      eot += 7 * done;
    }
    return { EOT: eot, C: c.r >= 2 && c.h.nonHome ? 4 : 0 };
  },
  'Reconnaissance Sweep': (c) => {
    const q = quarters(c);
    return { EOT: (q >= 4 ? 6 : q >= 3 ? 3 : 0) + c.kills.length, C: c.r >= 2 && c.h.nonHome ? 3 : 0 };
  },
  'Search and Scour': (c) => ({ EOT: (c.h.central ? 3 : 0) + (c.kills.some(() => c.rnd() < 0.4) ? 2 : 0), C: c.r >= 2 ? 4 * c.h.nonHome : 0 }),
  'Surveil the Foe': (c) => ({
    EOT: (c.rnd() < c.pAct ? 4 : 0) + (c.r >= 2 && c.rnd() < 0.5 * c.pAct ? 5 : 0),
    C: c.r >= 2 ? (c.h.nonHome ? 4 : 0) + (more(c) ? 4 : 0) : 0,
  }),
  'Triangulation': (c) => {
    // tune.triFromRound: the action starts in round 2 (the Godot game allows it from round 1)
    if (c.r >= (c.tune?.triFromRound ?? 2) && c.h.total && c.rnd() < c.pAct) c.ms.tri = Math.min(c.h.total + (c.ms.tri ?? 0), (c.ms.tri ?? 0) + 1);
    const n = c.ms.tri ?? 0;
    return { EOT: c.r >= 2 ? (n >= 3 ? 10 : n === 2 ? 6 : n === 1 ? 3 : 0) : 0, C: c.r >= 2 && c.h.nonHome ? 4 : 0 };
  },
  'Extract Relic': (c) => ({
    EOT: (c.h.central && c.rnd() < c.pAct ? 4 : 0) + (killedOnObjective(c) ? 3 : 0) + (c.r >= 4 && c.rnd() < 0.3 * c.pAct ? 4 : 0),
    C: c.r >= 2 && c.h.nonHome ? 4 : 0,
  }),
  'Sabotage': (c) => {
    const own = binom(c.h.nonHome - c.h.oppTerritory, c.pAct, c.rnd), deep = binom(c.h.oppTerritory, c.pAct, c.rnd);
    return { EOT: 3 * own + 5 * deep, C: c.r >= 2 && c.h.nonHome ? 4 : 0 };
  },
  'Secure Asset': (c) => ({
    EOT: (c.h.nonHome && c.rnd() < c.pAct ? 4 : 0) + (c.kills.some(() => c.rnd() < 0.25) ? 2 : 0),
    C: c.r >= 2 ? (c.h.nonHome ? 4 : 0) + (c.h.total >= 3 ? 4 : 0) : 0,
  }),
  'Vanguard Operation': (c) => ({
    EOT: (c.rnd() < c.pAct * (c.r === 1 ? 0.25 : c.r === 2 ? 0.55 : 0.7) ? 4 : 0) + (c.kills.length ? 2 : 0),
    C: c.r >= 2 && c.h.nonHome ? 4 : 0,
  }),
  'Vital Link': (c) => {
    if (c.h.central && c.rnd() < c.pAct) c.ms.links = (c.ms.links ?? 0) + 1;
    return { EOT: c.h.central ? 2 + (c.ms.links ?? 0) : 0, C: c.r >= 2 && c.h.nonHome ? 4 + (c.h.central ? 4 : 0) : 0 };
  },
  'Death Trap': (c) => {
    // 2 VP per terrain area trapped this turn (+3 if it holds an objective), and
    // every unit can trap one: a burst on the first turn (the areas the army
    // starts in), one or two a turn while it spreads out, then few are left.
    // A kill only counts in terrain trapped on an EARLIER turn.
    const traps = c.ms.traps ?? 0;
    let eot = 0;
    if (traps && c.kills.some(() => c.rnd() < 0.45)) eot += 3;
    const n = c.r === 1 ? binom(4, c.pAct, c.rnd) : c.r <= 3 ? binom(2, 0.75 * c.pAct, c.rnd) : binom(1, 0.4 * c.pAct, c.rnd);
    eot += 2 * n + 3 * binom(n, 0.5, c.rnd);
    c.ms.traps = traps + n;
    return { EOT: eot, C: c.r >= 2 && c.h.nonHome ? 4 : 0 };
  },
  'Delaying Action': (c) => ({ EOT: 2 * c.kills.length + (c.r >= 2 && c.h.central && (c.h.exp + c.h.oppExp) ? 3 : 0), C: c.r >= 2 && c.h.nonHome ? 4 : 0 }),
  'Locate and Deny': (c) => ({
    EOT: (killedOnObjective(c) ? 4 : 0) + (c.r >= 4 && c.rnd() < 0.3 * c.pAct ? 4 : 0),
    C: c.r >= 2 && c.h.nonHome ? 4 : 0,
  }),
  'Outmanoeuvre': (c) => ({
    EOT: (c.h.oppHome ? 10 : 0) + (c.r === 1 ? 4 * c.h.nonHome : c.r >= 4 ? 6 * c.h.nonHome : 0),
    C: c.r === 2 || c.r === 3 ? 5 * c.h.nonHome : 0,
  }),
  'Smoke and Mirrors': (c) => {
    // decoys go on objectives you hold and stay until the enemy reaches them
    const d = binom(c.h.nonHome, c.pAct, c.rnd), deep = Math.min(d, c.h.oppTerritory);
    c.ms.decoyed = d;
    return { EOT: 2 * d + 2 * deep, C: c.r >= 2 && c.h.nonHome ? 4 : 0 };
  },
};

const END_OF_BATTLE = {
  'Inescapable Dominion': (c) => (c.h.oppHome ? 5 : 0),
  'Consecrate': (c) => (c.ms.oppHomeCons ? 5 : 0),
  'Punishment': (c) => (c.h.oppHome ? 8 : 0),
  'Unstoppable Force': (c) => (c.h.central ? 5 : 0),
  'Gather Intel': (c) => ((c.ms.markers ?? 0) >= 3 ? 5 : 0) + (c.ms.markerOppHome ? 5 : 0),
  'Search and Scour': (c) => (c.rnd() < 0.5 ? 5 : 0),
  'Triangulation': (c) => (c.h.total >= 4 ? 10 : 0),
  'Extract Relic': (c) => (c.rnd() < 0.3 * c.pAct ? 5 : 0),
  'Vanguard Operation': (c) => (c.h.oppHome ? 10 : 0),
  'Vital Link': (c) => (c.h.oppHome ? 10 : 0),
  'Locate and Deny': (c) => (c.rnd() < 0.3 * c.pAct ? 5 : 0),
  'Smoke and Mirrors': (c) => ((c.ms.decoyed ?? 0) >= 4 ? 10 : 0),
};

// Cards that depend on where your units are. Without a board plan the app does
// not guess: each scores from YOUR rating of it (default "Normal" = 50% per
// turn for its lower tier, half that for its upper tier). With a board plan
// (c.pos) they are measured from the planned positions.
export const POSITION_CARDS = ['behind-enemy-lines', 'engage-on-all-fronts', 'outflank', 'centre-ground', 'display-of-might', 'beacon', 'plunder'];
export const RATING = { easy: 0.75, normal: 0.5, hard: 0.25, never: 0 };
function rated(c, id, lo, hi) {
  const p = clamp01(c.rate?.[id] ?? RATING.normal);
  const x = c.rnd();
  return x < p / 2 ? hi : x < p ? lo : 0;
}
function quarters(c) {
  // Reconnaissance Sweep (a primary): from the board plan, else your Engage on All Fronts rating
  if (c.pos) return c.pos.quarters;
  let p = clamp01(c.rate?.['engage-on-all-fronts'] ?? RATING.normal);
  // tune.quartersShape: the chance by round; tune.quartersFull: the share of those that is all 4
  const shape = c.tune?.quartersShape;
  if (shape && shape.length >= c.r) p = clamp01(p * shape[c.r - 1]);
  const full = c.tune?.quartersFull ?? 0.5;
  const x = c.rnd();
  return x < p * full ? 4 : x < p ? 3 : 2;
}

// ---------------------------------------------------------------------------
// Secondary card chances (positional / hold / action cards; kill cards are
// scored from the simulated kills). Returns VP for this scoring moment.

function scoreSecondary(id, c) {
  const r = c.r, pos = c.pos;
  const roll = (p) => c.rnd() < clamp01(p);
  switch (id) {
    case 'no-prisoners': return Math.min(5, 2 * c.kills.length);
    case 'overwhelming-force': return Math.min(5, 3 * c.kills.filter(v => v.onObj).length);
    case 'assassination': return c.kills.some(v => v.characters > 0) || (c.enemyCharsLeft === 0 && c.enemyHadChars) ? 5 : 0;
    case 'bring-it-down': return c.kills.some(v => v.w10 > 0) ? 5 : 0;
    case 'a-grievous-blow': return c.kills.some(v => v.ss13) ? 5 : 0;
    case 'a-tempting-target': return c.h.total && roll(c.temptingP) ? 5 : 0;
    case 'defend-stronghold': {
      if (r < 2 || !c.h.home) return 0;
      // +2 if no enemy unit is in your deployment zone: from the board plan, else even odds
      const clear = pos?.dzKnown ? !pos.enemyInMyDZ : roll(0.5);
      return 3 + (clear ? 2 : 0);
    }
    case 'beacon': return pos ? (pos.outsideTerritory ? 5 : pos.outsideDZ ? 3 : 0) : rated(c, id, 3, 5);
    case 'behind-enemy-lines': return pos ? Math.min(5, 3 * pos.inEnemyDZ) : rated(c, id, 3, 5);
    case 'burden-of-trust': return Math.min(5, 2 * c.h.total);
    case 'centre-ground': {
      if (pos?.centreKnown) return pos.centre3 && !pos.enemyCentre6 ? 5 : pos.centre3 && !pos.enemyCentre3 ? 3 : 0;
      return rated(c, id, 3, 5);
    }
    case 'cleanse': { const n = binom(c.h.nonHome, c.pAct, c.rnd); return n >= 2 ? 5 : n === 1 ? 2 : 0; }
    case 'display-of-might': {
      const met = pos?.nmlKnown ? pos.nmlMine > pos.nmlEnemy : c.rnd() < clamp01(c.rate?.[id] ?? RATING.normal);
      return met ? (c.timing === 'opp' ? 5 : 2) : 0;
    }
    case 'engage-on-all-fronts': {
      const q = pos ? pos.quarters : (rated(c, id, 3, 4) || 2);
      return c.fixedMode ? (q >= 4 ? 4 : q >= 3 ? 2 : 0) : (q >= 4 ? 5 : q >= 3 ? 3 : 0);
    }
    case 'forward-position': return c.h.oppHome || c.h.exp + c.h.oppExp >= 2 ? 5 : 0;
    case 'outflank': return pos ? (pos.flankOpposite ? 5 : pos.flank ? 3 : 0) : rated(c, id, 3, 5);
    case 'plunder': return pos ? (pos.terrainOutside && roll(c.pAct) ? 5 : 0) : (rated(c, id, 5, 5));
    case 'secure-no-mans-land': return c.h.nml >= 2 ? 5 : 0;
    default: return 0;
  }
}

// fixed-mode VP for the four FIXED cards (per turn, before the 20 VP card cap)
function scoreFixed(id, c) {
  switch (id) {
    case 'assassination': return c.kills.reduce((a, v) => a + 3 * v.characters + v.charactersW4, 0);
    case 'bring-it-down': return c.kills.reduce((a, v) => a + 4 * v.w10, 0);
    case 'a-grievous-blow': return 4 * c.kills.filter(v => v.ss13).length;
    case 'engage-on-all-fronts': return c.timing === 'own' ? scoreSecondary(id, { ...c, fixedMode: true }) : 0;
    default: return 0;
  }
}

// ---------------------------------------------------------------------------
// One game

const ROUND_KILL = { first: [0.45, 1, 1.1, 1, 0.9], second: [0.75, 1.05, 1.1, 1, 0.9] };

function drawCard(st, rnd) {
  if (!st.deck.length) return null;
  const i = Math.floor(rnd() * st.deck.length);
  return st.deck.splice(i, 1)[0];
}

function drawWithRules(st, r, enemyArmy, rnd, stats) {
  let guard = 0;
  while (guard++ < 12) {
    const id = drawCard(st, rnd);
    if (!id) return;
    const c = SECONDARY_BY_ID[id];
    // when-drawn: round-1 shuffle-backs, no targets, Cleanse <-> Plunder
    const reshuffle = (r === 1 && (id === 'behind-enemy-lines' || id === 'forward-position' || id === 'defend-stronghold'))
      || (c.pair && st.hand.includes(c.pair));
    if (reshuffle) { st.deck.push(id); continue; }
    if (cardDead(id, enemyArmy) || deadNow(id, st)) { st.used.push(id); continue; }
    st.hand.push(id);
    st.drawnAt[id] = st.turnNo;
    // the player's own estimate of this card's VP if drawn: it pays its max with
    // probability estimate / max, at its first chance, so the average is the estimate
    const est = st.pl.vpEst?.[id];
    if (est != null && st.pl.mode !== 'fixed') st.estWin[id] = rnd() < Math.max(0, Math.min(1, est / (c.max ?? 5)));
    stats[id] ??= { drawn: 0, vp: 0, scored: 0, quick: 0 };
    stats[id].drawn++;
    return;
  }
}
function deadNow(id, st) {
  const t = SECONDARY_BY_ID[id]?.target;
  if (t === 'character') return !st.enemyAlive.some(u => u.characters > 0);
  if (t === 'w10') return !st.enemyAlive.some(u => u.w10 > 0);
  if (t === 'ss13') return !st.enemyAlive.some(u => u.ss13);
  return false;
}

function pickVictims(alive, n, rnd) {
  const out = [];
  for (let i = 0; i < n && alive.length; i++) {
    const w = alive.map(u => (u.characters && u.models <= u.characters ? 0.6 : u.w10 ? 0.85 : 1));
    let x = rnd() * w.reduce((a, b) => a + b, 0), j = 0;
    while (j < w.length - 1 && x > w[j]) { x -= w[j]; j++; }
    out.push(alive.splice(j, 1)[0]);
  }
  return out;
}

function simulateGame(P, rnd) {
  const first = P.first ?? (rnd() < 0.5 ? 'A' : 'B');
  const order = [first, other(first)];
  const S = {};
  for (const X of ['A', 'B']) {
    const pl = P.players[X];
    const start = pl.start ?? {};
    const out = new Set([...(start.used ?? []), ...(start.hand ?? [])]);
    S[X] = {
      X, pl, deck: SECONDARIES.map(c => c.id).filter(id => !out.has(id)), hand: [...(start.hand ?? [])], used: [...(start.used ?? [])],
      prim: [0, 0, 0, 0, 0], sec: [0, 0, 0, 0, 0], primTotal: start.primary ?? 0, secTotal: start.secondary ?? 0,
      fixedVp: {}, ms: { ...(start.ms ?? {}) }, stats: {}, lostPrev: 0, drawnAt: {}, turnNo: 0, estWin: {},
      enemyAlive: null, enemyHadChars: false,
    };
  }
  for (const X of ['A', 'B']) {
    const enemy = P.players[other(X)].army;
    const dead = new Set(P.players[other(X)].start?.destroyed ?? []);
    S[X].enemyAlive = enemy.units.filter(u => !dead.has(u.name)).map(u => ({ ...u }));
    S[X].enemyHadChars = enemy.units.some(u => u.characters > 0);
  }
  const objById = Object.fromEntries(P.objectives.map(o => [o.id, o]));
  const nNml = P.objectives.filter(o => o.cls !== 'home').length;
  const owners = [];
  const startRound = P.startRound ?? 1;
  for (let r = 1; r <= RULES.rounds; r++) {
    const cells = P.plan?.[r] ?? {};
    const own = {};
    let centralContested = false;
    for (const o of P.objectives) {
      const v = cells[o.id] ?? 'c';
      // a plan is not a certainty: a planned objective is lost to the other side
      // now and then (home objectives rarely); contested ones are a coin flip
      const keep = o.cls === 'home' ? (P.confidence?.home ?? 0.95) : (P.confidence?.other ?? 0.8);
      own[o.id] = v === 'c' ? (rnd() < 0.5 ? 'A' : 'B') : rnd() < keep ? v : other(v);
      if (o.cls === 'central' && v === 'c') centralContested = true;
    }
    owners[r] = { own, centralContested };
  }
  // board plan: units at their planned positions, surviving units hold objectives
  const BP = P.boardPlan ?? null;
  const alive = (X) => new Set(S[other(X)].enemyAlive.map(u => u.name));
  const plannedUnits = (r, X) => {
    const us = BP?.rounds?.[r]?.[X];
    if (!us) return null;
    const live = alive(X);
    return us.filter(u => live.has(u.name));
  };
  function boardOwners(r) {
    const cells = P.plan?.[r] ?? {};
    const ua = plannedUnits(r, 'A'), ub = plannedUnits(r, 'B');
    if (!ua && !ub) return null;
    const own = {};
    let centralContested = false;
    for (const o of P.objectives) {
      const oc = (us) => us.reduce((a, u) => a + (u.f.objs.includes(o.id) ? u.f.oc : 0), 0);
      const coin = () => (rnd() < 0.5 ? 'A' : 'B');
      let w;
      if (ua && ub) {
        const a = oc(ua), b = oc(ub);
        w = a > b ? 'A' : b > a ? 'B' : a > 0 ? coin() : '';
        if (a > 0 && a === b && o.cls === 'central') centralContested = true;
      } else {
        // one army planned on the board, the other from the objective plan toggles
        const Pl = ua ? 'A' : 'B', U = other(Pl), mine = oc(ua ?? ub), v = cells[o.id] ?? 'c';
        w = v === Pl ? (mine > 0 ? Pl : '') : mine > 0 ? coin() : U;
        if (o.cls === 'central' && v === 'c') centralContested = true;
      }
      own[o.id] = w;
    }
    return { own, centralContested };
  }
  const posFor = (r, X) => {
    const us = plannedUnits(r, X);
    if (!us) return null;
    const en = plannedUnits(r, other(X));
    return sideFacts(us.map(u => u.f), en ? en.map(u => u.f) : null);
  };
  // the board kills: each target dies with its exposure to the attacker's planned positions
  const boardKills = (r, Y, list) => {
    const p = BP?.pDie?.[r]?.[Y];
    if (!p) return null;
    const out = [];
    const facts = new Map((BP.rounds?.[r]?.[Y] ?? []).map(u => [u.name, u.f]));
    for (let i = list.length - 1; i >= 0; i--) {
      const pr = p[list[i].name] ?? 0;
      if (pr > 0 && rnd() < pr) {
        const v = list.splice(i, 1)[0];
        v.onObj = (facts.get(v.name)?.objs.length ?? 0) > 0;
        out.push(v);
      }
    }
    return out;
  };
  const lastOwn = { A: {}, B: {} };
  for (let r = startRound; r <= RULES.rounds; r++) {
    for (let t = 0; t < 2; t++) {
      if (r === startRound && t < (P.startTurn ?? 0)) continue;
      const X = order[t], Y = other(X), sx = S[X], sy = S[Y];
      sx.turnNo++; sy.turnNo++;
      const { own, centralContested } = boardOwners(r) ?? owners[r];
      const prevOwn = lastOwn[X];
      lastOwn[X] = own;
      const hx = holdings(P.objectives, own, X), hy = holdings(P.objectives, own, Y);
      const posX = posFor(r, X), posY = posFor(r, Y);
      // --- Command phase: draw
      if (sx.pl.mode !== 'fixed') {
        const skipDraw = r === startRound && t === (P.startTurn ?? 0) && P.startAfterDraw;
        if (!skipDraw) for (let d = 0; d < RULES.drawPerTurn; d++) drawWithRules(sx, r, P.players[Y].army, rnd, sx.stats);
      }
      // --- kills this turn (by the active player; some fight-back by the other)
      const lamX = (sx.pl.killRate ?? 1.3) * ROUND_KILL[t === 0 ? 'first' : 'second'][r - 1];
      const lamY = 0.25 * (sy.pl.killRate ?? 1.3);
      const fromBoard = boardKills(r, Y, sx.enemyAlive);
      const killsX = fromBoard ?? pickVictims(sx.enemyAlive, poisson(lamX, rnd), rnd);
      const killsY = pickVictims(sy.enemyAlive, poisson(lamY, rnd), rnd);
      if (!fromBoard) for (const v of killsX) v.onObj = rnd() < (P.fObj ?? 0.45);
      for (const v of killsY) v.onObj = rnd() < (P.fObj ?? 0.45);
      // --- primary (active player): Command phase + end of turn
      // objectives you hold now that you did not hold last round (your own home excluded)
      const newly = hx.ids.filter(id => prevOwn[id] !== X && !(objById[id].cls === 'home' && objById[id].side === X)).length;
      const fn = PRIMARY_FN[sx.pl.mission];
      let primGain = 0;
      if (fn) {
        const ctx = { r, h: hx, hOpp: hy, kills: killsX, lostPrev: sx.lostPrev, newly, pAct: sx.pl.actionP ?? 0.7, ms: sx.ms, rnd, army: sx.pl.army, enemyAlive: sx.enemyAlive.length, rate: sx.pl.rate ?? {}, pos: posX, tune: sx.pl.tune, nNml };
        const v = fn(ctx);
        primGain += (v.C ?? 0) + (v.EOT ?? 0);
        if (r === RULES.rounds && t === 1) {
          // end of battle (after the last turn): both players' end-of-battle VP
          primGain += END_OF_BATTLE[sx.pl.mission]?.(ctx) ?? 0;
        }
      }
      addPrimary(sx, r, primGain);
      // --- secondaries at the end of this turn: active player first
      const lastTurn = r === RULES.rounds && t === 1;
      scoreSecondaries(sx, r, 'own', { h: hx, hOpp: hy, kills: killsX, centralContested, rnd, P, lastTurn, pos: posX });
      scoreSecondaries(sy, r, 'opp', { h: hy, hOpp: hx, kills: killsY, centralContested, rnd, P, lastTurn, pos: posY });
      // Y's units destroyed this turn = Y's "friendly units destroyed in the previous turn" on its next turn
      sy.lostPrev = killsX.length;
      if (r === RULES.rounds && t === 1) {
        // the player who went first also scores end-of-battle VP
        const fy = PRIMARY_FN[sy.pl.mission];
        if (fy) {
          const ctxY = { r, h: hy, hOpp: hx, kills: [], lostPrev: 0, newly: 0, pAct: sy.pl.actionP ?? 0.7, ms: sy.ms, rnd, army: sy.pl.army, enemyAlive: sy.enemyAlive.length };
          addPrimary(sy, r, END_OF_BATTLE[sy.pl.mission]?.(ctxY) ?? 0);
        }
      }
    }
  }
  const res = {};
  for (const X of ['A', 'B']) {
    const s = S[X];
    res[X] = { prim: s.prim, sec: s.sec, primTotal: s.primTotal, secTotal: s.secTotal, total: s.primTotal + s.secTotal + (s.pl.battleReady === false ? 0 : RULES.battleReady), stats: s.stats, first: first === X };
  }
  return res;
}

function addPrimary(s, r, vp) {
  const room = Math.min(RULES.primaryRoundCap - s.prim[r - 1], RULES.primaryCap - s.primTotal);
  const g = Math.max(0, Math.min(room, vp));
  s.prim[r - 1] += g; s.primTotal += g;
}
function addSecondary(s, r, vp) {
  const room = Math.min(RULES.secondaryRoundCap - s.sec[r - 1], RULES.secondaryCap - s.secTotal);
  const g = Math.max(0, Math.min(room, vp));
  s.sec[r - 1] += g; s.secTotal += g;
  return g;
}

function scoreSecondaries(s, r, timing, env) {
  const pl = s.pl;
  const c = {
    r, timing, h: env.h, hOpp: env.hOpp, kills: env.kills, rnd: env.rnd, army: pl.army, rate: pl.rate ?? {}, pos: env.pos ?? null,
    pAct: pl.actionP ?? 0.7, centralContested: env.centralContested, temptingP: env.P.temptingP?.[s.X] ?? 0.45,
    enemyCharsLeft: s.enemyAlive.reduce((a, u) => a + u.characters, 0), enemyHadChars: s.enemyHadChars,
  };
  if (pl.mode === 'fixed') {
    for (const id of pl.fixed ?? []) {
      const before = s.fixedVp[id] ?? 0;
      const vp = Math.min(RULES.fixedCardCap - before, scoreFixed(id, c));
      if (vp > 0) { const g = addSecondary(s, r, vp); s.fixedVp[id] = before + g; s.stats[id] ??= { drawn: 0, vp: 0, scored: 0 }; s.stats[id].vp += g; }
    }
    return;
  }
  for (const id of [...s.hand]) {
    const card = SECONDARY_BY_ID[id];
    const when = card.timing;
    // Display of Might scores at the end of either turn (2 VP yours, 5 VP theirs)
    if (!(when === 'any' || when === timing || id === 'display-of-might')) continue;
    if (card.minRound && r < card.minRound) continue;
    let vp;
    if (id in s.estWin) vp = s.estWin[id] ? card.max ?? 5 : 0;
    else vp = scoreSecondary(id, { ...c, timing });
    // Display of Might: hold the 2 VP at the end of your turn when the 5 VP at the end of theirs is likely
    if (id === 'display-of-might' && !(id in s.estWin) && timing === 'own' && vp > 0 && r < RULES.rounds && c.rnd() < 0.5) vp = 0;
    if (vp > 0) {
      const g = addSecondary(s, r, vp);
      s.hand.splice(s.hand.indexOf(id), 1);
      s.used.push(id);
      s.stats[id] ??= { drawn: 0, vp: 0, scored: 0, quick: 0 };
      s.stats[id].vp += g; s.stats[id].scored++;
      if (s.turnNo - (s.drawnAt[id] ?? s.turnNo) <= 1) s.stats[id].quick++;
    }
  }
  // "end of your opponent's turn or the end of the fifth battle round": when you
  // take the last turn of the battle, those cards score at the end of it
  if (timing === 'own' && env.lastTurn) {
    for (const id of [...s.hand]) {
      const card = SECONDARY_BY_ID[id];
      if (card.timing !== 'opp') continue;
      const vp = id in s.estWin ? (s.estWin[id] ? card.max ?? 5 : 0) : scoreSecondary(id, { ...c, timing: 'opp' });
      if (vp > 0) { const g = addSecondary(s, r, vp); s.hand.splice(s.hand.indexOf(id), 1); s.used.push(id); s.stats[id] ??= { drawn: 0, vp: 0, scored: 0 }; s.stats[id].vp += g; s.stats[id].scored++; }
    }
  }
}

// ---------------------------------------------------------------------------
// Public: forecast

/**
 * P: {
 *   players: { A: { mission, mode: 'tactical'|'fixed', fixed: [ids], army: armyProfile(...),
 *                   killRate (enemy units / turn), actionP (0..1), rate: { positionCardId: 0..1 (RATING) },
 *                   vpEst: { cardId: the player's estimate of VP if drawn (0..max) },
 *                   battleReady, start: { hand, used, primary, secondary, destroyed: [unit names] } }, B: {...} },
 *   objectives: [{ id, cls, side }], plan: { [round]: { [objId]: 'A'|'B'|'c' } },
 *   first: 'A'|'B'|null, startRound, startTurn, trials, seed, fObj
 * }
 */
export function forecast(P) {
  const trials = Math.max(1, P.trials ?? 4000);
  const rnd = mulberry32(P.seed ?? 0xC0FFEE);
  const maxVp = RULES.primaryCap + RULES.secondaryCap + RULES.battleReady;
  const hist = { A: new Array(maxVp + 1).fill(0), B: new Array(maxVp + 1).fill(0) };
  const sums = { A: { prim: [0, 0, 0, 0, 0], sec: [0, 0, 0, 0, 0], total: 0, sq: 0 }, B: { prim: [0, 0, 0, 0, 0], sec: [0, 0, 0, 0, 0], total: 0, sq: 0 } };
  const lead = [0, 0, 0, 0, 0].map(() => ({ A: 0, B: 0, tie: 0 }));
  const cards = { A: {}, B: {} };
  let winA = 0, winB = 0, draw = 0;
  const diffs = [];
  for (let i = 0; i < trials; i++) {
    const g = simulateGame(P, rnd);
    for (const X of ['A', 'B']) {
      const t = Math.round(g[X].total);
      hist[X][Math.min(maxVp, t)]++;
      sums[X].total += g[X].total; sums[X].sq += g[X].total ** 2;
      for (let r = 0; r < 5; r++) { sums[X].prim[r] += g[X].prim[r]; sums[X].sec[r] += g[X].sec[r]; }
      for (const [id, s] of Object.entries(g[X].stats)) {
        const a = (cards[X][id] ??= { drawn: 0, vp: 0, scored: 0, quick: 0 });
        a.drawn += s.drawn; a.vp += s.vp; a.scored += s.scored; a.quick += s.quick ?? 0;
      }
    }
    let ca = P.players.A.start?.primary ?? 0, cb = P.players.B.start?.primary ?? 0;
    ca += P.players.A.start?.secondary ?? 0; cb += P.players.B.start?.secondary ?? 0;
    for (let r = 0; r < 5; r++) {
      ca += g.A.prim[r] + g.A.sec[r]; cb += g.B.prim[r] + g.B.sec[r];
      if (ca > cb) lead[r].A++; else if (cb > ca) lead[r].B++; else lead[r].tie++;
    }
    diffs.push(g.A.total - g.B.total);
    if (g.A.total > g.B.total) winA++; else if (g.B.total > g.A.total) winB++; else draw++;
  }
  const pct = (h, q) => { let acc = 0; for (let v = 0; v < h.length; v++) { acc += h[v]; if (acc >= q * trials) return v; } return h.length - 1; };
  const side = (X) => {
    const m = sums[X].total / trials;
    return {
      mean: m, sd: Math.sqrt(Math.max(0, sums[X].sq / trials - m * m)),
      p10: pct(hist[X], 0.1), p50: pct(hist[X], 0.5), p90: pct(hist[X], 0.9),
      hist: hist[X].map(c => c / trials),
      prim: sums[X].prim.map(v => v / trials), sec: sums[X].sec.map(v => v / trials),
      cards: Object.fromEntries(Object.entries(cards[X]).map(([id, a]) => [id, { perDraw: a.drawn ? a.vp / a.drawn : 0, drawRate: a.drawn / trials, scoreRate: a.drawn ? a.scored / a.drawn : 0, quickRate: a.drawn ? a.quick / a.drawn : 0 }])),
    };
  };
  diffs.sort((a, b) => a - b);
  return {
    trials, A: side('A'), B: side('B'),
    pWinA: winA / trials, pWinB: winB / trials, pDraw: draw / trials,
    margin: { p10: diffs[Math.floor(0.1 * trials)], p50: diffs[Math.floor(0.5 * trials)], p90: diffs[Math.floor(0.9 * trials)] },
    lead: lead.map(l => ({ A: l.A / trials, B: l.B / trials, tie: l.tie / trials })),
  };
}

/** Chance each card still in the deck is among the next `draws` cards. */
export function nextDrawOdds(deckIds, draws = RULES.drawPerTurn) {
  const n = deckIds.length;
  const p = n ? Math.min(1, draws / n) : 0;
  return Object.fromEntries(deckIds.map(id => [id, p]));
}

export { PRIMARIES };
