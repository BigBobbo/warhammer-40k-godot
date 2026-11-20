// Parity fixtures for the GDScript port of the Combat Calc forecast
// (40k/scripts/AIForecast.gd). Builds a set of scenarios in the GAME's form
// (card ids with underscores, players 1/2), runs each through the original
// server/public/calc/forecast.mjs, and writes scenarios + JS results to
// 40k/tests/fixtures/forecast_parity.json. tests/unit/test_ai_forecast.gd
// replays the scenarios through AIForecast.gd and compares the statistics.
//
//   node tools/ai_lab/forecast_parity.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { forecast } from '../../server/public/calc/forecast.mjs';
import { PRIMARIES } from '../../server/public/calc/missions-11e.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '../../40k/tests/fixtures/forecast_parity.json');
const TRIALS = 20000;

const army = (tag) => ({ units: [
  { name: `${tag}_warboss`, models: 1, characters: 1, characters_w4: 1, w10: 0, ss13: false, aircraft: false },
  { name: `${tag}_mek`, models: 1, characters: 1, characters_w4: 0, w10: 0, ss13: false, aircraft: false },
  { name: `${tag}_boyz`, models: 20, characters: 0, characters_w4: 0, w10: 0, ss13: true, aircraft: false },
  { name: `${tag}_tank`, models: 1, characters: 0, characters_w4: 0, w10: 1, ss13: false, aircraft: false },
  { name: `${tag}_gretchin`, models: 11, characters: 0, characters_w4: 0, w10: 0, ss13: false, aircraft: false },
  { name: `${tag}_nobz`, models: 5, characters: 0, characters_w4: 0, w10: 0, ss13: false, aircraft: false },
  { name: `${tag}_bikes`, models: 3, characters: 0, characters_w4: 0, w10: 0, ss13: false, aircraft: false },
  { name: `${tag}_kans`, models: 3, characters: 0, characters_w4: 0, w10: 0, ss13: false, aircraft: false },
] });
const OBJ = [
  { id: 'home1', cls: 'home', side: 1 }, { id: 'home2', cls: 'home', side: 2 },
  { id: 'exp1', cls: 'exp', side: 1 }, { id: 'exp2', cls: 'exp', side: 2 },
  { id: 'centre', cls: 'central', side: 0 },
];
const basePlan = () => {
  const p = {};
  for (let r = 1; r <= 5; r++) p[r] = { home1: 1, home2: 2, exp1: 1, exp2: r >= 4 ? 1 : 2, centre: 0 };
  return p;
};
const pl = (mission, extra = {}) => ({ mission, mode: 'tactical', army: null, kill_rate: 1.3, action_p: 0.7, rate: {}, start: {}, ...extra });

const scenarios = [];
const names = Object.keys(PRIMARIES);
// every primary card once as P1, against a rotating opponent card
names.forEach((m, i) => scenarios.push({
  name: `primary_${m}`, first: 1, seed: 1,
  players: { 1: pl(m), 2: pl(names[(i + 7) % names.length], { kill_rate: 1.1 }) },
  objectives: OBJ, plan: basePlan(), trials: TRIALS,
}));
// mid-game: round 3, second player's turn, hands/used/VP carried in
scenarios.push({
  name: 'midgame_r3', first: 2, start_round: 3, start_turn: 1, start_after_draw: true, seed: 2,
  players: {
    1: pl('Battlefield Dominance', { start: { hand: ['secure_no_mans_land', 'behind_enemy_lines'], used: ['no_prisoners', 'cleanse', 'beacon'], primary: 18, secondary: 12, destroyed: ['A_boyz'] }, rate: { behind_enemy_lines: 0.2 } }),
    2: pl('Meatgrinder', { start: { hand: ['assassination'], used: ['outflank', 'plunder'], primary: 14, secondary: 9, destroyed: ['B_warboss', 'B_tank'] }, kill_rate: 1.8 }),
  },
  objectives: OBJ, plan: basePlan(), trials: TRIALS,
});
// fixed missions vs tactical
scenarios.push({
  name: 'fixed_vs_tactical', first: 1, seed: 3,
  players: { 1: pl('Gather Intel', { mode: 'fixed', fixed: ['assassination', 'bring_it_down'] }), 2: pl('Outmanoeuvre') },
  objectives: OBJ, plan: basePlan(), trials: TRIALS,
});
// confidence + all-contested plan, first player random
const contested = {}; for (let r = 1; r <= 5; r++) contested[r] = { home1: 1, home2: 2, exp1: 0, exp2: 0, centre: 0 };
scenarios.push({
  name: 'contested_random_first', first: 0, seed: 4, confidence: { home: 0.9, other: 0.6 },
  players: { 1: pl('Consecrate', { rate: { engage_on_all_fronts: 0.75, centre_ground: 0.25 } }), 2: pl('Triangulation', { action_p: 0.5 }) },
  objectives: OBJ, plan: contested, trials: TRIALS,
});

// --- game form -> JS form
const pid = (p) => (p === 1 || p === '1' ? 'A' : p === 2 || p === '2' ? 'B' : null);
const cid = (id) => id.replace(/_/g, '-');
const cids = (a) => (a ?? []).map(cid);
function toJs(s) {
  const P = { objectives: s.objectives.map(o => ({ id: o.id, cls: o.cls, side: pid(o.side) })), plan: {}, trials: s.trials, seed: s.seed,
    first: pid(s.first), startRound: s.start_round, startTurn: s.start_turn, startAfterDraw: s.start_after_draw, confidence: s.confidence, players: {} };
  for (const [r, cells] of Object.entries(s.plan)) P.plan[r] = Object.fromEntries(Object.entries(cells).map(([k, v]) => [k, pid(v) ?? 'c']));
  for (const k of [1, 2]) {
    const p = s.players[k];
    const a = army(k === 1 ? 'A' : 'B');
    P.players[pid(k)] = {
      mission: p.mission, mode: p.mode, fixed: cids(p.fixed), killRate: p.kill_rate, actionP: p.action_p,
      rate: Object.fromEntries(Object.entries(p.rate ?? {}).map(([id, v]) => [cid(id), v])),
      army: { units: a.units.map(u => ({ ...u, charactersW4: u.characters_w4 })) },
      start: { hand: cids(p.start?.hand), used: cids(p.start?.used), primary: p.start?.primary, secondary: p.start?.secondary, destroyed: p.start?.destroyed ?? [] },
    };
  }
  return P;
}
const out = { generated_by: 'tools/ai_lab/forecast_parity.mjs', trials_js: TRIALS, armies: { 1: army('A'), 2: army('B') }, scenarios: [] };
for (const s of scenarios) {
  const r = forecast(toJs(s));
  out.scenarios.push({ ...s, js: { mean1: r.A.mean, mean2: r.B.mean, sd1: r.A.sd, sd2: r.B.sd, p_win1: r.pWinA, p_win2: r.pWinB } });
}
writeFileSync(OUT, JSON.stringify(out, null, 1));
console.log(`wrote ${out.scenarios.length} scenarios -> ${OUT}`);
for (const s of out.scenarios) console.log(s.name.padEnd(40), s.js.mean1.toFixed(2), s.js.mean2.toFixed(2), s.js.p_win1.toFixed(3));
