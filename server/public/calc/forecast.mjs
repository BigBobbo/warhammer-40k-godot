// Game VP forecast: simulates the rest of a battle many times for both
// players — the tactical secondary deck (draws, when-drawn rules, scoring),
// each player's primary mission from the objectives they plan to hold, and
// units destroyed each turn — and returns the spread of final scores.
//
// It is a planning model, not a game engine. What is exact: card VP, the
// deck, the 45 / 15-per-round caps (missions-11e.mjs). What is a model:
//  - who controls each objective at the END OF EVERY PLAYER TURN: from the
//    plan (A / B / contested), shifted by how much of each army is left and by
//    who just moved (the player who moved has the edge);
//  - units destroyed each turn: a per-turn rate (from the calculator's
//    unit-vs-unit odds, or the player's own setting) that falls as the army
//    shrinks; with a board plan, each surviving unit attacks the best target
//    it reaches from its planned position;
//  - "how the battle goes": one draw per simulated game that puts one side on
//    top (it destroys more and loses less, and that compounds) — real games
//    are decided by about 30 VP on average, not by 5;
//  - cards that depend on where units are: the player's own estimate, a board
//    plan (measured), or the real-game rate of the equivalent 10th edition
//    card (REAL_RATES) — never a silent guess.
// MODEL below holds the assumptions; tests/calc-calibration.test.mjs keeps an
// even game with the default plan inside the real 11th edition tournament
// score statistics. Pure module, unit-tested (tests/calc-forecast.test.mjs).

import { RULES, SECONDARIES, SECONDARY_BY_ID, PRIMARIES, REAL_RATES } from './missions-11e.mjs';
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
function gauss(rnd) { return Math.sqrt(-2 * Math.log(1 - rnd())) * Math.cos(2 * Math.PI * rnd()); }
// standard normal CDF (Abramowitz-Stegun 26.2.17)
function phi(x) {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804 * Math.exp(-x * x / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return x >= 0 ? 1 - p : p;
}

// ---------------------------------------------------------------------------
// The assumptions about how a battle goes (everything else is rules or the
// player's own input). Set so that an even game with the default plan gives
// the score statistics of real 11th edition tournament games (Stat Check,
// 94,739 player-games at events of 25+ players, June to mid-November 2026:
// mean 77 VP, SD 21, 15% of scores exactly 100, 13% under 50, average winning
// margin 30 VP, first player wins 51%).
export const MODEL = {
  swingSd: 0.36,      // "how the battle goes": SD of one side's log kill-rate edge in one game (luck, not skill)
  killGamma: 0.8,     // an army's kills scale with (share of it still alive) ^ killGamma
  firstR1: 0.5,       // share of the kill rate delivered in round 1 by the player going first...
  secondR1: 0.725,     // ...and by the player going second
  fightBack: 0.25,    // kills in the opponent's turn (fights, overwatch) as a share of your rate
  holdSlope: 1.0,     // chance to hold a planned objective moves with your share of what is left
  contestSlope: 1.5,  // contested objectives go to the stronger army more often
  activeEdge: 0.1,    // you hold planned objectives more surely at the end of your own turn
  contestEdge: 0.15,  // contested objectives lean to the player who just moved
  cardSlope: 0.4,     // position / action cards are easier for the stronger army
  walkOn: 0.8,        // chance to take an objective whose owner has no units left
  cardPlay: 1.4,      // "you play for the card you drew": multiplier on the real-game card rates
  hiShare: 0.7,       // share of a tiered position card's successes that pay the upper tier
  holdUntil: 4,       // score-or-hold: a card worth less than its maximum is held until this battle round
  targetBias: 3,      // you go for the units your kill cards need: their weight when choosing what dies
};

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
// c.h / c.hOpp = control at the END of this turn (end-of-turn VP); c.hC / c.hOppC
// = control at the end of the Command phase, i.e. what the previous turn left
// (in round 5 the Command-phase part is scored at the end of the turn instead).
const moreC = (ctx) => ctx.hC.total > ctx.hOppC.total;

const PRIMARY_FN = {
  'Battlefield Dominance': (c) => ({
    EOT: c.r <= 2 && more(c) ? 2 : 0,
    C: c.r >= 2 ? 3 * c.hC.total + (c.hC.home ? 2 * c.hC.nonHome : 0) : 0,
  }),
  'Determined Acquisition': (c) => ({ EOT: 2 * c.newly, C: c.r >= 2 ? 3 * c.hC.total + 3 * c.hC.oppTerritory : 0 }),
  'Immovable Object': (c) => ({ EOT: c.h.central ? 3 : 0, C: c.r >= 2 ? 5 * c.hC.nonHome : 0 }),
  'Inescapable Dominion': (c) => ({ EOT: c.h.total >= 3 ? 4 : 0, C: c.r >= 2 ? (c.hC.total >= 2 ? 5 : 0) + (moreC(c) ? 4 : 0) : 0 }),
  'Purge and Secure': (c) => ({ EOT: (killedOnObjective(c) ? 3 : 0) + (c.r >= 2 && c.newly ? 3 : 0), C: c.r >= 2 ? 4 * c.hC.nonHome : 0 }),
  'Consecrate': (c) => {
    // each kill by a unit standing near a non-home objective can consecrate it (permanent)
    const can = Math.max(0, 4 - (c.ms.consecrated ?? 0));
    const add = Math.min(can, binom(c.kills.length, 0.45 * c.pAct, c.rnd));
    c.ms.consecrated = (c.ms.consecrated ?? 0) + add;
    if (c.h.oppHome && add) c.ms.oppHomeCons = c.ms.oppHomeCons || c.rnd() < 0.5;
    const n = c.ms.consecrated;
    return { EOT: n >= 3 ? 6 : n >= 1 ? 3 : 0, C: c.r >= 2 ? (c.hC.nonHome ? 4 : 0) + (moreC(c) ? 4 : 0) : 0 };
  },
  "Destroyer's Wrath": (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 && c.kills.length > c.lostPrev ? 4 : 0), C: c.r >= 2 ? (c.hC.nonHome ? 4 : 0) + (moreC(c) ? 6 : 0) : 0 }),
  'Meatgrinder': (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 ? (c.kills.length > c.lostPrev ? 5 : 0) + (c.h.oppHome ? 5 : 0) : 0), C: c.r >= 2 && c.hC.nonHome ? 4 : 0 }),
  'Punishment': (c) => {
    // up to 3 condemned enemy units each turn: a kill hits one with probability ~3 / units left
    const pc = Math.min(1, 3 / Math.max(1, c.enemyAlive + c.kills.length));
    return { EOT: c.kills.some(() => c.rnd() < pc) ? 5 : 0, C: c.r >= 2 ? (c.hC.nonHome ? 4 : 0) + (moreC(c) ? 5 : 0) : 0 };
  },
  'Unstoppable Force': (c) => ({ EOT: (c.kills.length ? 3 : 0) + (c.r >= 2 && c.newly ? 3 : 0), C: c.r >= 2 ? 4 * c.hC.nonHome : 0 }),
  'Gather Intel': (c) => {
    let eot = c.r === 1 && c.h.central ? 6 : 0;
    if (c.r >= 2) {
      const done = binom(c.h.nml, c.pAct, c.rnd);
      c.ms.markers = (c.ms.markers ?? 0) + done;
      if (done && c.h.oppHome) c.ms.markerOppHome = true;
      eot += 7 * done;
    }
    return { EOT: eot, C: c.r >= 2 && c.hC.nonHome ? 4 : 0 };
  },
  'Reconnaissance Sweep': (c) => {
    const q = quarters(c);
    return { EOT: (q >= 4 ? 6 : q >= 3 ? 3 : 0) + c.kills.length, C: c.r >= 2 && c.hC.nonHome ? 3 : 0 };
  },
  'Search and Scour': (c) => ({ EOT: (c.h.central ? 3 : 0) + (c.kills.some(() => c.rnd() < 0.4) ? 2 : 0), C: c.r >= 2 ? 4 * c.hC.nonHome : 0 }),
  'Surveil the Foe': (c) => ({
    EOT: (c.rnd() < c.pAct ? 4 : 0) + (c.r >= 2 && c.rnd() < 0.5 * c.pAct ? 5 : 0),
    C: c.r >= 2 ? (c.hC.nonHome ? 4 : 0) + (moreC(c) ? 4 : 0) : 0,
  }),
  'Triangulation': (c) => {
    if (c.r >= 2 && c.h.total && c.rnd() < c.pAct) c.ms.tri = Math.min(c.h.total + (c.ms.tri ?? 0), (c.ms.tri ?? 0) + 1);
    const n = c.ms.tri ?? 0;
    return { EOT: c.r >= 2 ? (n >= 3 ? 10 : n === 2 ? 6 : n === 1 ? 3 : 0) : 0, C: c.r >= 2 && c.hC.nonHome ? 4 : 0 };
  },
  'Extract Relic': (c) => ({
    EOT: (c.h.central && c.rnd() < c.pAct ? 4 : 0) + (killedOnObjective(c) ? 3 : 0) + (c.r >= 4 && c.rnd() < 0.3 * c.pAct ? 4 : 0),
    C: c.r >= 2 && c.hC.nonHome ? 4 : 0,
  }),
  'Sabotage': (c) => {
    const own = binom(c.h.nonHome - c.h.oppTerritory, c.pAct, c.rnd), deep = binom(c.h.oppTerritory, c.pAct, c.rnd);
    return { EOT: 3 * own + 5 * deep, C: c.r >= 2 && c.hC.nonHome ? 4 : 0 };
  },
  'Secure Asset': (c) => ({
    EOT: (c.h.nonHome && c.rnd() < c.pAct ? 4 : 0) + (c.kills.some(() => c.rnd() < 0.25) ? 2 : 0),
    C: c.r >= 2 ? (c.hC.nonHome ? 4 : 0) + (c.hC.total >= 3 ? 4 : 0) : 0,
  }),
  'Vanguard Operation': (c) => ({
    EOT: (c.rnd() < c.pAct * (c.r === 1 ? 0.25 : c.r === 2 ? 0.55 : 0.7) ? 4 : 0) + (c.kills.length ? 2 : 0),
    C: c.r >= 2 && c.hC.nonHome ? 4 : 0,
  }),
  'Vital Link': (c) => {
    if (c.h.central && c.rnd() < c.pAct) c.ms.links = (c.ms.links ?? 0) + 1;
    return { EOT: c.h.central ? 2 + (c.ms.links ?? 0) : 0, C: c.r >= 2 && c.hC.nonHome ? 4 + (c.hC.central ? 4 : 0) : 0 };
  },
  'Death Trap': (c) => {
    let eot = 0;
    if (c.rnd() < c.pAct) { eot += 2; if (c.rnd() < 0.5) eot += 3; c.ms.traps = (c.ms.traps ?? 0) + 1; }
    if (c.ms.traps && c.kills.some(() => c.rnd() < 0.3)) eot += 3;
    return { EOT: eot, C: c.r >= 2 && c.hC.nonHome ? 4 : 0 };
  },
  'Delaying Action': (c) => ({ EOT: 2 * c.kills.length + (c.r >= 2 && c.h.central && (c.h.exp + c.h.oppExp) ? 3 : 0), C: c.r >= 2 && c.hC.nonHome ? 4 : 0 }),
  'Locate and Deny': (c) => ({
    EOT: (killedOnObjective(c) ? 4 : 0) + (c.r >= 4 && c.rnd() < 0.3 * c.pAct ? 4 : 0),
    C: c.r >= 2 && c.hC.nonHome ? 4 : 0,
  }),
  'Outmanoeuvre': (c) => ({
    EOT: (c.h.oppHome ? 10 : 0) + (c.r === 1 ? 4 * c.h.nonHome : c.r >= 4 ? 6 * c.h.nonHome : 0),
    C: c.r === 2 || c.r === 3 ? 5 * c.hC.nonHome : 0,
  }),
  'Smoke and Mirrors': (c) => {
    // decoys go on objectives you hold and stay until the enemy reaches them
    const d = binom(c.h.nonHome, c.pAct, c.rnd), deep = Math.min(d, c.h.oppTerritory);
    c.ms.decoyed = d;
    return { EOT: 2 * d + 2 * deep, C: c.r >= 2 && c.hC.nonHome ? 4 : 0 };
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

// Cards that depend on where your units are. In order of preference: the
// player's own estimate of the card (handled at draw time), a board plan
// (c.pos: measured from the planned positions), the player's rating of the
// card (c.rate), then the real-game rate of the equivalent 10th edition card
// by battle round (REAL_RATES) or, where no such card exists, 50%. Half of the
// successes pay the upper tier.
export const POSITION_CARDS = ['behind-enemy-lines', 'engage-on-all-fronts', 'outflank', 'centre-ground', 'display-of-might', 'beacon', 'plunder'];
export const RATING = { easy: 0.75, normal: 0.5, hard: 0.25, never: 0 };
/** The default per-turn chance for a position card in battle round r, and where it comes from. */
export function defaultCardRate(id, r) {
  const real = REAL_RATES[id]?.by?.[Math.max(0, Math.min(4, r - 1))];
  return real != null ? { p: real, from: 'real' } : { p: RATING.normal, from: 'none' };
}
function cardRate(c, id) {
  const own = c.rate?.[id];
  // your own rating is used as it is; the real-game rate is scaled by MODEL.cardPlay
  const base = own != null ? clamp01(own) : defaultCardRate(id, c.r).p * (c.cardPlay ?? 1);
  // easier for the army that is on top, impossible with nothing left
  return Math.min(0.97, clamp01(base * (c.ease ?? 1)));
}
// Cards scored from the objectives you hold: you get what the plan gives, and
// when that is less than the card's maximum you play for the card as often as
// tournament players scored the equivalent card (not with a board plan: there
// the positions are yours and are measured as they are).
function playFor(c, id, planVp, max = 5) {
  if (planVp >= max || c.pos) return planVp;
  return c.rnd() < cardRate(c, id) ? max : planVp;
}
function rated(c, id, lo, hi) {
  const p = cardRate(c, id);
  const x = c.rnd();
  return x < p * (c.hiShare ?? 0.5) ? hi : x < p ? lo : 0;
}
function quarters(c) {
  // Reconnaissance Sweep (a primary): from the board plan, else as Engage on All Fronts
  if (c.pos) return c.pos.quarters;
  const p = cardRate(c, 'engage-on-all-fronts');
  const x = c.rnd();
  return x < p * (c.hiShare ?? 0.5) ? 4 : x < p ? 3 : 2;
}

// ---------------------------------------------------------------------------
// Secondary card chances (positional / hold / action cards; kill cards are
// scored from the simulated kills). Returns VP for this scoring moment.

function scoreSecondary(id, c) {
  if (c.units === 0) return 0; // nothing left on the table to score with
  const r = c.r, pos = c.pos;
  const ease = c.ease ?? 1;
  const roll = (p) => c.rnd() < clamp01(p);
  switch (id) {
    case 'no-prisoners': return Math.min(5, 2 * c.kills.length);
    case 'overwhelming-force': return Math.min(5, 3 * c.kills.filter(v => v.onObj).length);
    case 'assassination': return c.kills.some(v => v.characters > 0) || (c.enemyCharsLeft === 0 && c.enemyHadChars) ? 5 : 0;
    case 'bring-it-down': return c.kills.some(v => v.w10 > 0) ? 5 : 0;
    case 'a-grievous-blow': return c.kills.some(v => v.ss13) ? 5 : 0;
    // the opponent picks the objective: the real-game rate of the card (48% / 49 / 41 / 38 / 47 by round)
    case 'a-tempting-target': return c.h.total && roll(c.temptingP != null ? c.temptingP * ease : cardRate(c, id)) ? 5 : 0;
    case 'defend-stronghold': {
      if (r < 2) return 0;
      if (!c.h.home) return playFor(c, id, 0, 3);
      // +2 if no enemy unit is in your deployment zone: from the board plan, else even odds
      const clear = pos?.dzKnown ? !pos.enemyInMyDZ : roll(0.5 * ease);
      return 3 + (clear ? 2 : 0);
    }
    case 'beacon': return pos ? (pos.outsideTerritory ? 5 : pos.outsideDZ ? 3 : 0) : rated(c, id, 3, 5);
    case 'behind-enemy-lines': return pos ? Math.min(5, 3 * pos.inEnemyDZ) : rated(c, id, 3, 5);
    case 'burden-of-trust': return playFor(c, id, Math.min(5, 2 * c.h.total));
    case 'centre-ground': {
      if (pos?.centreKnown) return pos.centre3 && !pos.enemyCentre6 ? 5 : pos.centre3 && !pos.enemyCentre3 ? 3 : 0;
      return rated(c, id, 3, 5);
    }
    case 'cleanse': { const n = binom(c.h.nonHome, c.pAct, c.rnd); return playFor(c, id, n >= 2 ? 5 : n === 1 ? 2 : 0); }
    case 'display-of-might': {
      const met = pos?.nmlKnown ? pos.nmlMine > pos.nmlEnemy : c.rnd() < cardRate(c, id);
      return met ? (c.timing === 'opp' ? 5 : 2) : 0;
    }
    case 'engage-on-all-fronts': {
      const q = pos ? pos.quarters : (rated(c, id, 3, 4) || 2);
      return c.fixedMode ? (q >= 4 ? 4 : q >= 3 ? 2 : 0) : (q >= 4 ? 5 : q >= 3 ? 3 : 0);
    }
    case 'forward-position': return playFor(c, id, c.h.oppHome || c.h.exp + c.h.oppExp >= 2 ? 5 : 0);
    case 'outflank': return pos ? (pos.flankOpposite ? 5 : pos.flank ? 3 : 0) : rated(c, id, 3, 5);
    case 'plunder': return pos ? (pos.terrainOutside && roll(c.pAct) ? 5 : 0) : (rated(c, id, 5, 5));
    case 'secure-no-mans-land': return playFor(c, id, c.h.nml >= 2 ? 5 : 0);
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

// share of the per-turn kill rate delivered in each battle round (armies are
// not in reach in round 1; the player going second answers an army that has moved up)
const roundKill = (M, second, r) => (r === 1 ? (second ? M.secondR1 : M.firstR1) : (second && r === 2 ? 1.05 : [0, 1, 1, 1.1, 1, 0.9][r]));

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
    stats[id] ??= { drawn: 0, vp: 0, net: 0, scored: 0, quick: 0 };
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

// which enemy units the killer wants most: the targets of the kill cards it holds
function wanted(s) {
  const ids = s.pl.mode === 'fixed' ? (s.pl.fixed ?? []) : s.hand;
  const ch = ids.includes('assassination'), big = ids.includes('bring-it-down'), horde = ids.includes('a-grievous-blow');
  if (!ch && !big && !horde) return null;
  return (u) => (ch && u.characters > 0) || (big && u.w10 > 0) || (horde && u.ss13);
}
function pickVictims(alive, n, rnd, want = null, bias = 1) {
  const out = [];
  for (let i = 0; i < n && alive.length; i++) {
    const w = alive.map(u => (u.characters && u.models <= u.characters ? 0.6 : u.w10 ? 0.85 : 1) * (want && want(u) ? bias : 1));
    let x = rnd() * w.reduce((a, b) => a + b, 0), j = 0;
    while (j < w.length - 1 && x > w[j]) { x -= w[j]; j++; }
    out.push(alive.splice(j, 1)[0]);
  }
  return out;
}

function simulateGame(P, rnd) {
  const M = P.model ? { ...MODEL, ...P.model } : MODEL;
  const first = P.first ?? (rnd() < 0.5 ? 'A' : 'B');
  const order = [first, other(first)];
  const S = {};
  for (const X of ['A', 'B']) {
    const pl = P.players[X];
    const start = pl.start ?? {};
    const out = new Set([...(start.used ?? []), ...(start.hand ?? [])]);
    S[X] = {
      X, pl, deck: SECONDARIES.map(c => c.id).filter(id => !out.has(id)), hand: [...(start.hand ?? [])], used: [...(start.used ?? [])],
      prim: [0, 0, 0, 0, 0], sec: [0, 0, 0, 0, 0], primEnd: 0, primTotal: start.primary ?? 0, secTotal: start.secondary ?? 0,
      fixedVp: {}, ms: {}, stats: {}, lostPrev: 0, drawnAt: {}, turnNo: 0, estWin: {},
      enemyAlive: null, enemyHadChars: false, unitsLeft: [null, null, null, null, null],
    };
  }
  for (const X of ['A', 'B']) {
    const enemy = P.players[other(X)].army;
    const dead = new Set(P.players[other(X)].start?.destroyed ?? []);
    S[X].enemyAlive = enemy.units.filter(u => !dead.has(u.name)).map(u => ({ ...u }));
    S[X].enemyHadChars = enemy.units.some(u => u.characters > 0);
  }
  const objById = Object.fromEntries(P.objectives.map(o => [o.id, o]));

  // --- what is left of each army (aircraft hold nothing and are not counted)
  const worth = (u) => (u.aircraft ? 0 : u.points > 0 ? u.points : 100);
  const mine = (X) => S[other(X)].enemyAlive;                 // X's own surviving units
  const strength = (X) => mine(X).reduce((a, u) => a + worth(u), 0);
  const ground = (X) => mine(X).reduce((a, u) => a + (u.aircraft ? 0 : 1), 0);
  const full = { A: P.players.A.army.units.reduce((a, u) => a + worth(u), 0), B: P.players.B.army.units.reduce((a, u) => a + worth(u), 0) };
  const share = (X) => { const a = strength(X), b = strength(other(X)); return a + b > 0 ? a / (a + b) : 0.5; };
  const left = (X) => (full[X] > 0 ? strength(X) / full[X] : 0);
  // position / action cards: easier for the army on top, impossible with nothing left
  const ease = (X) => (ground(X) ? Math.max(0.2, Math.min(1.6, 1 + 2 * M.cardSlope * (share(X) - 0.5))) : 0);

  // --- how the battle goes: one side gets on top (destroys more, loses less)
  const swing = (P.edge ?? 0) + (M.swingSd > 0 ? gauss(rnd) * M.swingSd : 0);
  const kmul = { A: Math.exp(swing), B: Math.exp(-swing) };

  // --- who controls each objective at the end of a player turn, from the grid plan
  const confHome = P.confidence?.home ?? 0.95, confOther = P.confidence?.other ?? 0.8;
  const lean = (rel) => clamp01(0.5 + M.contestSlope * (rel - 0.5));
  function gridSnapshot(r, active) {
    const cells = P.plan?.[r] ?? {};
    const own = {};
    let centralContested = false;
    const relA = share('A');
    const n = { A: ground('A'), B: ground('B') };
    for (const o of P.objectives) {
      const v = cells[o.id] ?? 'c';
      let w = '';
      if (v === 'c') {
        if (o.cls === 'central') centralContested = true;
        if (!n.A || !n.B) w = n.A ? 'A' : n.B ? 'B' : '';
        else w = rnd() < clamp01(lean(relA) + (active === 'A' ? M.contestEdge : active === 'B' ? -M.contestEdge : 0)) ? 'A' : 'B';
      } else if (!n[v]) {
        // the planned owner has nothing left: the other army walks on (not at once)
        w = n[other(v)] && rnd() < M.walkOn ? other(v) : '';
      } else {
        // a plan is not a certainty: a planned objective is lost now and then (home
        // objectives rarely), more often for the weaker army and after the enemy's move
        const base = o.cls === 'home' ? confHome : confOther;
        const rel = v === 'A' ? relA : 1 - relA;
        const keep = base >= 1 ? 1 : clamp01(base + (o.cls === 'home' ? 0.5 : 1) * M.holdSlope * (rel - 0.5) + (active === v ? M.activeEdge : active ? -M.activeEdge : 0));
        if (rnd() < keep) w = v;
        else w = n[other(v)] && rnd() < lean(1 - rel) ? other(v) : '';
      }
      own[o.id] = w;
    }
    // an army cannot hold more objectives than it has units left
    for (const X of ['A', 'B']) {
      const held = P.objectives.filter(o => own[o.id] === X);
      if (held.length <= n[X]) continue;
      const prio = (o) => (o.cls === 'home' ? (o.side === X ? 0 : 4) : o.cls === 'central' ? 2 : o.side === X ? 1 : 3);
      held.sort((a, b) => prio(a) - prio(b));
      for (const o of held.slice(n[X])) own[o.id] = '';
    }
    return { own, centralContested };
  }
  // before the first turn: each army holds its home objective
  function deploySnapshot() {
    const own = {};
    for (const o of P.objectives) own[o.id] = o.cls === 'home' && ground(o.side) ? o.side : '';
    return { own, centralContested: false };
  }

  // --- board plan: units at their planned positions, surviving units hold objectives.
  // Plan step s = positions after that army's move in battle round s (0 = deployment):
  // at the end of the first player's turn the second player is still at step r - 1.
  const BP = P.boardPlan ?? null;
  const stepOf = (X, r, t) => (X === first || t === 1 ? r : r - 1);
  const stepUnits = (X, step) => (BP?.rounds?.[step] ?? (step === 0 ? BP?.rounds?.[1] : null))?.[X] ?? null;
  const plannedUnits = (X, step) => {
    const us = stepUnits(X, step);
    if (!us) return null;
    const live = new Set(mine(X).map(u => u.name));
    return us.filter(u => live.has(u.name));
  };
  function boardSnapshot(stepA, stepB, cellsRound) {
    const ua = plannedUnits('A', stepA), ub = plannedUnits('B', stepB);
    if (!ua && !ub) return null;
    const cells = P.plan?.[cellsRound] ?? {};
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
        const Pl = ua ? 'A' : 'B', U = other(Pl), own1 = oc(ua ?? ub), v = cells[o.id] ?? 'c';
        const uHas = ground(U) > 0;
        w = v === Pl ? (own1 > 0 ? Pl : '') : own1 > 0 ? (uHas ? coin() : Pl) : (uHas ? U : '');
        if (o.cls === 'central' && v === 'c') centralContested = true;
      }
      own[o.id] = w;
    }
    return { own, centralContested };
  }
  const posFor = (X, r, t) => {
    const us = plannedUnits(X, stepOf(X, r, t));
    if (!us) return null;
    const en = plannedUnits(other(X), stepOf(other(X), r, t));
    return sideFacts(us.map(u => u.f), en ? en.map(u => u.f) : null);
  };
  const snap = (r, t) => boardSnapshot(stepOf('A', r, t), stepOf('B', r, t), r) ?? gridSnapshot(r, order[t]);

  // --- board kills. New form (BP.threats): each surviving attacker attacks the
  // best target it reaches that is still alive; a target dies when the combined
  // damage is enough. Old form (BP.pDie): a fixed chance per target.
  const variantFor = (Y) => (Y === first ? 'cur' : 'prev'); // has the target army already moved this round?
  function boardKills(r, X, Y, list) {
    const th = BP?.threats?.[r]?.[X]?.[variantFor(Y)];
    const facts = new Map((stepUnits(Y, Y === first ? r : r - 1) ?? stepUnits(Y, r) ?? []).map(u => [u.name, u.f]));
    if (th) {
      const liveAtk = new Set(mine(X).map(u => u.name));
      const liveTgt = new Map(list.map(u => [u.name, u]));
      const acc = new Map(); // target -> { mu, v, solo, n }
      for (const a of th) {
        if (!liveAtk.has(a.a)) continue;
        const o = a.opts.find(x => liveTgt.has(x.t));
        if (!o) continue;
        const s = acc.get(o.t) ?? { mu: 0, v: 0, solo: 1, n: 0, W: o.W };
        s.mu += o.mu * kmul[X]; s.v += o.v * kmul[X] * kmul[X]; s.solo *= 1 - o.w; s.n++;
        acc.set(o.t, s);
      }
      const out = [];
      for (const [name, s] of acc) {
        // one attacker: its own simulated odds; several: the combined damage against the unit's wounds
        const solo = 1 - Math.pow(s.solo, kmul[X]);
        const p = s.n === 1 ? solo : Math.max(solo, phi((s.mu - s.W + 0.5) / Math.sqrt(s.v + 0.25)));
        if (p > 0 && rnd() < p) {
          const v = list.splice(list.findIndex(u => u.name === name), 1)[0];
          v.onObj = (facts.get(name)?.objs.length ?? 0) > 0;
          out.push(v);
        }
      }
      return out;
    }
    let p = BP?.pDie?.[r]?.[Y];
    if (!p) return null;
    if (p.cur || p.prev) p = p[variantFor(Y)] ?? p.cur ?? p.prev;
    const out = [];
    for (let i = list.length - 1; i >= 0; i--) {
      const pr = p[list[i].name] ?? 0;
      const adj = pr > 0 ? 1 - Math.pow(1 - pr, kmul[X]) : 0;
      if (adj > 0 && rnd() < adj) {
        const v = list.splice(i, 1)[0];
        v.onObj = (facts.get(v.name)?.objs.length ?? 0) > 0;
        out.push(v);
      }
    }
    return out;
  }

  const startRound = P.startRound ?? 1, startTurn = P.startTurn ?? 0;
  // control when the simulation starts: deployment, or what the previous turn left
  let prev = startRound === 1 && startTurn === 0 ? (boardSnapshot(0, 0, 1) ?? deploySnapshot())
    : startTurn === 0 ? snap(startRound - 1, 1) : snap(startRound, 0);
  for (let r = startRound; r <= RULES.rounds; r++) {
    for (let t = 0; t < 2; t++) {
      if (r === startRound && t < startTurn) continue;
      const X = order[t], Y = other(X), sx = S[X], sy = S[Y];
      sx.turnNo++; sy.turnNo++;
      // --- Command phase: draw
      if (sx.pl.mode !== 'fixed') {
        const skipDraw = r === startRound && t === startTurn && P.startAfterDraw;
        if (!skipDraw) for (let d = 0; d < RULES.drawPerTurn; d++) drawWithRules(sx, r, P.players[Y].army, rnd, sx.stats);
      }
      // --- kills this turn (by the active player; some fight-back by the other):
      // fewer as the army shrinks, more for the side that is on top this game
      const lamX = (sx.pl.killRate ?? 1.3) * kmul[X] * roundKill(M, t === 1, r) * Math.pow(left(X), M.killGamma);
      const lamY = M.fightBack * (sy.pl.killRate ?? 1.3) * kmul[Y] * Math.pow(left(Y), M.killGamma);
      const fromBoard = boardKills(r, X, Y, sx.enemyAlive);
      const killsX = fromBoard ?? pickVictims(sx.enemyAlive, poisson(lamX, rnd), rnd, wanted(sx), M.targetBias);
      const killsY = pickVictims(sy.enemyAlive, poisson(lamY, rnd), rnd, wanted(sy), M.targetBias);
      if (!fromBoard) for (const v of killsX) v.onObj = rnd() < (P.fObj ?? 0.45);
      for (const v of killsY) v.onObj = rnd() < (P.fObj ?? 0.45);
      // --- control at the end of this turn (after the moves and the losses)
      const cur = snap(r, t);
      const hx = holdings(P.objectives, cur.own, X), hy = holdings(P.objectives, cur.own, Y);
      // Command-phase VP use what the previous turn left; in round 5 they are scored at the end of the turn
      const lastRound = r === RULES.rounds;
      const hxC = lastRound ? hx : holdings(P.objectives, prev.own, X), hyC = lastRound ? hy : holdings(P.objectives, prev.own, Y);
      const posX = posFor(X, r, t), posY = posFor(Y, r, t);
      const easeX = ease(X), easeY = ease(Y);
      // --- primary (active player): Command phase + end of turn
      // objectives you hold now that you did not hold when the turn began (your own home excluded)
      const newly = hx.ids.filter(id => prev.own[id] !== X && !(objById[id].cls === 'home' && objById[id].side === X)).length;
      const fn = PRIMARY_FN[sx.pl.mission];
      let primGain = 0, endGain = 0;
      const lastTurn = lastRound && t === 1;
      if (fn) {
        const ctx = { r, h: hx, hOpp: hy, hC: hxC, hOppC: hyC, kills: killsX, lostPrev: sx.lostPrev, newly, pAct: clamp01((sx.pl.actionP ?? 0.7) * easeX), ms: sx.ms, rnd, army: sx.pl.army, enemyAlive: sx.enemyAlive.length, rate: sx.pl.rate ?? {}, pos: posX, ease: easeX, units: ground(X), cardPlay: M.cardPlay, hiShare: M.hiShare };
        const v = fn(ctx);
        primGain += (v.C ?? 0) + (v.EOT ?? 0);
        // end of battle (after the last turn): both players' end-of-battle VP
        if (lastTurn) endGain = END_OF_BATTLE[sx.pl.mission]?.(ctx) ?? 0;
      }
      addPrimary(sx, r, primGain);
      addPrimaryEnd(sx, endGain);
      // --- secondaries at the end of this turn: active player first
      scoreSecondaries(sx, r, 'own', { h: hx, hOpp: hy, kills: killsX, centralContested: cur.centralContested, rnd, P, M, lastTurn, pos: posX, ease: easeX, units: ground(X) });
      scoreSecondaries(sy, r, 'opp', { h: hy, hOpp: hx, kills: killsY, centralContested: cur.centralContested, rnd, P, M, lastTurn, pos: posY, ease: easeY, units: ground(Y) });
      // Y's units destroyed this turn = Y's "friendly units destroyed in the previous turn" on its next turn
      sy.lostPrev = killsX.length;
      if (lastTurn) {
        // the player who went first also scores end-of-battle VP
        const fy = PRIMARY_FN[sy.pl.mission];
        if (fy) {
          const ctxY = { r, h: hy, hOpp: hx, hC: hy, hOppC: hx, kills: [], lostPrev: 0, newly: 0, pAct: clamp01((sy.pl.actionP ?? 0.7) * easeY), ms: sy.ms, rnd, army: sy.pl.army, enemyAlive: sy.enemyAlive.length, ease: easeY, units: ground(Y) };
          addPrimaryEnd(sy, END_OF_BATTLE[sy.pl.mission]?.(ctxY) ?? 0);
        }
      }
      prev = cur;
      if (t === 1) { S.A.unitsLeft[r - 1] = ground('A'); S.B.unitsLeft[r - 1] = ground('B'); }
    }
  }
  const res = {};
  for (const X of ['A', 'B']) {
    const s = S[X];
    res[X] = { prim: s.prim, sec: s.sec, primEnd: s.primEnd, primTotal: s.primTotal, secTotal: s.secTotal, total: s.primTotal + s.secTotal + (s.pl.battleReady === false ? 0 : RULES.battleReady), stats: s.stats, first: first === X, unitsLeft: s.unitsLeft, tabled: ground(X) === 0 };
  }
  return res;
}

function addPrimary(s, r, vp) {
  const room = Math.min(RULES.primaryRoundCap - s.prim[r - 1], RULES.primaryCap - s.primTotal);
  const g = Math.max(0, Math.min(room, vp));
  s.prim[r - 1] += g; s.primTotal += g;
}
// VP scored "at the end of the battle" are not under the 15 VP per battle round
// limit (Event Companion v1.2 FAQ) — only the 45 VP primary maximum.
function addPrimaryEnd(s, vp) {
  const g = Math.max(0, Math.min(RULES.primaryCap - s.primTotal, vp ?? 0));
  s.primEnd += g; s.primTotal += g;
}
function addSecondary(s, r, vp) {
  const room = Math.min(RULES.secondaryRoundCap - s.sec[r - 1], RULES.secondaryCap - s.secTotal);
  const g = Math.max(0, Math.min(room, vp));
  s.sec[r - 1] += g; s.secTotal += g;
  return g;
}

function scoreSecondaries(s, r, timing, env) {
  const pl = s.pl;
  const ease = env.ease ?? 1;
  const c = {
    r, timing, h: env.h, hOpp: env.hOpp, kills: env.kills, rnd: env.rnd, army: pl.army, rate: pl.rate ?? {}, pos: env.pos ?? null,
    pAct: clamp01((pl.actionP ?? 0.7) * ease), ease, units: env.units ?? 1, cardPlay: env.M.cardPlay, hiShare: env.M.hiShare,
    centralContested: env.centralContested, temptingP: env.P.temptingP?.[s.X] ?? null,
    enemyCharsLeft: s.enemyAlive.reduce((a, u) => a + u.characters, 0), enemyHadChars: s.enemyHadChars,
  };
  if (pl.mode === 'fixed') {
    for (const id of pl.fixed ?? []) {
      const before = s.fixedVp[id] ?? 0;
      const vp = Math.min(RULES.fixedCardCap - before, scoreFixed(id, c));
      if (vp > 0) { const g = addSecondary(s, r, vp); s.fixedVp[id] = before + g; s.stats[id] ??= { drawn: 0, vp: 0, net: 0, scored: 0 }; s.stats[id].vp += vp; s.stats[id].net += g; }
    }
    return;
  }
  // your own estimate of a card: it pays its max or nothing (decided when drawn) — but not with no units left
  const estVp = (id, card) => (s.estWin[id] && c.units !== 0 ? card.max ?? 5 : 0);
  for (const id of [...s.hand]) {
    const card = SECONDARY_BY_ID[id];
    const when = card.timing;
    // Display of Might scores at the end of either turn (2 VP yours, 5 VP theirs)
    if (!(when === 'any' || when === timing || id === 'display-of-might')) continue;
    if (card.minRound && r < card.minRound) continue;
    let vp;
    if (id in s.estWin) vp = estVp(id, card);
    else vp = scoreSecondary(id, { ...c, timing });
    // score or hold (scoring is optional): a card worth less than its maximum now is kept
    // for a better turn until late in the battle (e.g. Display of Might: 2 VP at the end
    // of your turn, 5 VP at the end of theirs; No Prisoners: 2 VP per unit destroyed)
    if (vp > 0 && vp < (card.max ?? 5) && r < env.M.holdUntil) vp = 0;
    if (vp > 0) {
      const g = addSecondary(s, r, vp);
      s.hand.splice(s.hand.indexOf(id), 1);
      s.used.push(id);
      s.stats[id] ??= { drawn: 0, vp: 0, net: 0, scored: 0, quick: 0 };
      // vp = what the card pays; net = what it added under the 15-per-round / 45 VP limits
      s.stats[id].vp += vp; s.stats[id].net = (s.stats[id].net ?? 0) + g; s.stats[id].scored++;
      if (s.turnNo - (s.drawnAt[id] ?? s.turnNo) <= 1) s.stats[id].quick++;
    }
  }
  // "end of your opponent's turn or the end of the fifth battle round": when you
  // take the last turn of the battle, those cards score at the end of it
  if (timing === 'own' && env.lastTurn) {
    for (const id of [...s.hand]) {
      const card = SECONDARY_BY_ID[id];
      if (card.timing !== 'opp') continue;
      const vp = id in s.estWin ? estVp(id, card) : scoreSecondary(id, { ...c, timing: 'opp' });
      if (vp > 0) { const g = addSecondary(s, r, vp); s.hand.splice(s.hand.indexOf(id), 1); s.used.push(id); s.stats[id] ??= { drawn: 0, vp: 0, net: 0, scored: 0 }; s.stats[id].vp += vp; s.stats[id].net = (s.stats[id].net ?? 0) + g; s.stats[id].scored++; }
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
 *   boardPlan: { rounds: { [0..5]: { A: [{ name, f }] | null, B } },
 *                threats: { [round]: { [attackerSide]: { cur, prev: [{ a, opts: [{ t, mu, v, w, W }] }] } } } },
 *   first: 'A'|'B'|null, startRound, startTurn, trials, seed, fObj,
 *   edge: A's log kill-rate edge (0 = even players), model: overrides of MODEL
 * }
 */
export function forecast(P) {
  const trials = Math.max(1, P.trials ?? 4000);
  const rnd = mulberry32(P.seed ?? 0xC0FFEE);
  const maxVp = RULES.primaryCap + RULES.secondaryCap + RULES.battleReady;
  const hist = { A: new Array(maxVp + 1).fill(0), B: new Array(maxVp + 1).fill(0) };
  const mk = () => ({ prim: [0, 0, 0, 0, 0], sec: [0, 0, 0, 0, 0], primEnd: 0, total: 0, sq: 0, primTotal: 0, secTotal: 0, units: [0, 0, 0, 0, 0], tabled: 0, whenFirst: 0, nFirst: 0 });
  const sums = { A: mk(), B: mk() };
  const lead = [0, 0, 0, 0, 0].map(() => ({ A: 0, B: 0, tie: 0 }));
  const cards = { A: {}, B: {} };
  let winA = 0, winB = 0, draw = 0, cross = 0, firstWins = 0, firstMargin = 0;
  const split = { A: { n: 0, win: 0 }, B: { n: 0, win: 0 } }; // by who took the first turn
  const diffs = [];
  for (let i = 0; i < trials; i++) {
    const g = simulateGame(P, rnd);
    for (const X of ['A', 'B']) {
      const t = Math.round(g[X].total);
      hist[X][Math.min(maxVp, t)]++;
      sums[X].total += g[X].total; sums[X].sq += g[X].total ** 2;
      sums[X].primTotal += g[X].primTotal; sums[X].secTotal += g[X].secTotal;
      for (let r = 0; r < 5; r++) { sums[X].prim[r] += g[X].prim[r]; sums[X].sec[r] += g[X].sec[r]; sums[X].units[r] += g[X].unitsLeft[r] ?? 0; }
      sums[X].primEnd += g[X].primEnd;
      if (g[X].tabled) sums[X].tabled++;
      for (const [id, s] of Object.entries(g[X].stats)) {
        const a = (cards[X][id] ??= { drawn: 0, vp: 0, net: 0, scored: 0, quick: 0 });
        a.drawn += s.drawn; a.vp += s.vp; a.net += s.net ?? 0; a.scored += s.scored; a.quick += s.quick ?? 0;
      }
    }
    let ca = P.players.A.start?.primary ?? 0, cb = P.players.B.start?.primary ?? 0;
    ca += P.players.A.start?.secondary ?? 0; cb += P.players.B.start?.secondary ?? 0;
    for (let r = 0; r < 5; r++) {
      ca += g.A.prim[r] + g.A.sec[r]; cb += g.B.prim[r] + g.B.sec[r];
      if (r === 4) { ca += g.A.primEnd; cb += g.B.primEnd; } // end-of-battle VP count after round 5
      if (ca > cb) lead[r].A++; else if (cb > ca) lead[r].B++; else lead[r].tie++;
    }
    const d = g.A.total - g.B.total;
    diffs.push(d);
    cross += g.A.total * g.B.total;
    if (d > 0) winA++; else if (d < 0) winB++; else draw++;
    const F = g.A.first ? 'A' : 'B';
    split[F].n++;
    if (d > 0) split[F].win++;                      // A's wins, by who went first
    if ((F === 'A' && d > 0) || (F === 'B' && d < 0)) firstWins++;
    firstMargin += F === 'A' ? d : -d;
  }
  const pct = (h, q) => { let acc = 0; for (let v = 0; v < h.length; v++) { acc += h[v]; if (acc >= q * trials) return v; } return h.length - 1; };
  const side = (X) => {
    const m = sums[X].total / trials;
    return {
      mean: m, sd: Math.sqrt(Math.max(0, sums[X].sq / trials - m * m)),
      p10: pct(hist[X], 0.1), p25: pct(hist[X], 0.25), p50: pct(hist[X], 0.5), p75: pct(hist[X], 0.75), p90: pct(hist[X], 0.9),
      hist: hist[X].map(c => c / trials),
      prim: sums[X].prim.map(v => v / trials), sec: sums[X].sec.map(v => v / trials), primEnd: sums[X].primEnd / trials,
      primMean: sums[X].primTotal / trials, secMean: sums[X].secTotal / trials,
      unitsLeft: sums[X].units.map(v => v / trials), pTabled: sums[X].tabled / trials,
      cards: Object.fromEntries(Object.entries(cards[X]).map(([id, a]) => [id, { perDraw: a.drawn ? a.vp / a.drawn : 0, perDrawNet: a.drawn ? a.net / a.drawn : 0, drawRate: a.drawn / trials, scoreRate: a.drawn ? a.scored / a.drawn : 0, quickRate: a.drawn ? a.quick / a.drawn : 0 }])),
    };
  };
  diffs.sort((a, b) => a - b);
  const A = side('A'), B = side('B');
  const cov = cross / trials - A.mean * B.mean;
  const meanAbs = diffs.reduce((a, d) => a + Math.abs(d), 0) / trials;
  return {
    trials, A, B,
    pWinA: winA / trials, pWinB: winB / trials, pDraw: draw / trials,
    margin: { p10: diffs[Math.floor(0.1 * trials)], p50: diffs[Math.floor(0.5 * trials)], p90: diffs[Math.floor(0.9 * trials)], meanAbs },
    corr: A.sd > 0 && B.sd > 0 ? cov / (A.sd * B.sd) : 0,
    // who takes the first turn: the first player's win share and average margin, and A's win chance either way
    firstTurn: { pWin: firstWins / trials, margin: firstMargin / trials, pWinAFirst: split.A.n ? split.A.win / split.A.n : null, pWinASecond: split.B.n ? split.B.win / split.B.n : null },
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
