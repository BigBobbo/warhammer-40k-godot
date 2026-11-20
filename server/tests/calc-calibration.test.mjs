// Combat Calc forecast — calibration against real 11th edition tournament
// results. A field of games (two typical 13-unit lists, the default objective
// plan, tactical secondaries, every primary mission, favourites and underdogs)
// must give the score statistics of real GT-level games
// (fixtures/real-11e-score-stats.json).
// If a change to forecast.mjs moves the forecast outside these bands, the
// model no longer describes real games: retune MODEL, do not widen the bands.
// Run: node --test server/tests/calc-calibration.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const F = await import(new URL('../public/calc/forecast.mjs', import.meta.url).href);
const M = await import(new URL('../public/calc/missions-11e.mjs', import.meta.url).href);
const REAL = JSON.parse(readFileSync(new URL('./fixtures/real-11e-score-stats.json', import.meta.url), 'utf8'));

// a typical list (lists that start 4-0 run 10-14 units: Goonhammer, 9 Nov 2026)
const u = (name, pts, o = {}) => ({ name, models: 5, points: pts, ...o });
const army = () => F.armyProfile([
  u('Warlord', 110, { models: 1, characters: 1, charactersW4: 1 }), u('Leader + squad', 260, { models: 11, characters: 1, charactersW4: 1, bodyguardModels: 10 }),
  u('Battleline 1', 160, { models: 10 }), u('Battleline 2', 160, { models: 10 }), u('Horde', 200, { models: 20, bodyguardModels: 20 }),
  u('Elite 1', 190), u('Elite 2', 190), u('Fast 1', 120, { fast: true }), u('Fast 2', 120, { fast: true }),
  u('Tank 1', 190, { models: 1, w10: 1 }), u('Tank 2', 180, { models: 1, w10: 1 }), u('Scouts', 70, { reserves: true }), u('Cheap', 50),
]);
const OBJS = [{ id: 'hA', cls: 'home', side: 'A' }, { id: 'eA', cls: 'exp', side: 'A' }, { id: 'c', cls: 'central', side: null }, { id: 'eB', cls: 'exp', side: 'B' }, { id: 'hB', cls: 'home', side: 'B' }];
// the app's default plan: homes held, your own expansion from round 2, the centre contested
const plan = Object.fromEntries([1, 2, 3, 4, 5].map(r => [r, { hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: 'c' }]));

// Real results are a POPULATION of matchups: in most games one player (or
// list) is the favourite. Each game here has a matchup edge drawn from
// N(0, EDGE_SD) — seven equal-probability steps — and then the forecast's own
// in-game luck. EDGE_SD is set so the favourite wins about three games in four
// (a pre-game rating alone calls 69% of real 11th edition games correctly, and
// real ratings are an imperfect measure of who the favourite is).
const EDGE_SD = 0.43;
const EDGE_Z = [-1.465, -0.792, -0.366, 0, 0.366, 0.792, 1.465];

function population(trials) {
  const A = army(), B = army(), missions = Object.keys(M.PRIMARIES);
  const hist = new Array(101).fill(0);
  let n = 0, sum = 0, sq = 0, cross = 0, absM = 0, draws = 0, firstWin = 0, firstMargin = 0, favWin = 0, favGames = 0, seed = 1;
  for (const z of EDGE_Z) for (const mA of missions) {
    // each primary against itself and against another one (the two players' primaries differ in 11e)
    for (const mB of [mA, missions[(missions.indexOf(mA) + 7) % missions.length]]) {
      const pl = (mission, a) => ({ mission, army: a, killRate: 1.3, mode: 'tactical', actionP: 0.7, battleReady: true });
      const r = F.forecast({ players: { A: pl(mA, A), B: pl(mB, B) }, objectives: OBJS, plan, trials, seed: seed++, edge: z * EDGE_SD });
      for (const X of ['A', 'B']) {
        for (let v = 0; v <= 100; v++) hist[v] += r[X].hist[v] * trials;
        sum += r[X].mean * trials; sq += (r[X].sd ** 2 + r[X].mean ** 2) * trials; n += trials;
      }
      cross += (r.corr * r.A.sd * r.B.sd + r.A.mean * r.B.mean) * trials;
      absM += r.margin.meanAbs * trials; draws += r.pDraw * trials;
      firstWin += r.firstTurn.pWin * trials; firstMargin += r.firstTurn.margin * trials;
      if (z !== 0) { favWin += (z > 0 ? r.pWinA : r.pWinB) * trials; favGames += trials * (1 - r.pDraw); }
    }
  }
  const games = n / 2, mean = sum / n, sd = Math.sqrt(sq / n - mean * mean);
  const pct = (q) => { let acc = 0; for (let v = 0; v <= 100; v++) { acc += hist[v]; if (acc >= q * n) return v; } return 100; };
  const share = (lo, hi) => hist.slice(lo, hi + 1).reduce((a, b) => a + b, 0) / n;
  return {
    mean, sd, p10: pct(0.1), p25: pct(0.25), p50: pct(0.5), p75: pct(0.75), p90: pct(0.9),
    p100: share(100, 100), p90plus: share(90, 100), pUnder50: share(0, 49),
    meanAbsMargin: absM / games, corr: (cross / games - mean * mean) / (sd * sd),
    draws: draws / games, firstWin: firstWin / games, firstMargin: firstMargin / games, favourite: favWin / favGames,
  };
}

test('a field of even and uneven games with the default plan reproduces real 11th edition tournament scores', () => {
  const m = population(100);
  const R = REAL.score;
  const within = (name, v, lo, hi) => assert.ok(v >= lo && v <= hi, `${name}: ${typeof v === 'number' ? v.toFixed(3) : v} not in ${lo}..${hi} (model ${JSON.stringify(m)})`);
  within(`mean VP (real ${R.mean})`, m.mean, R.mean - 2, R.mean + 2);
  within(`SD (real ${R.sd})`, m.sd, R.sd - 2.5, R.sd + 1.5);
  within(`P10 (real ${R.p10})`, m.p10, R.p10 - 5, R.p10 + 5);
  within(`median (real ${R.p50})`, m.p50, R.p50 - 4, R.p50 + 4);
  within(`P90 (real ${R.p90})`, m.p90, R.p90 - 4, R.p90);
  within(`scores of 90+ (real ${R.pAtLeast90})`, m.p90plus, R.pAtLeast90 - 0.06, R.pAtLeast90 + 0.04);
  within(`scores under 50 (real ${R.pUnder50})`, m.pUnder50, R.pUnder50 - 0.04, R.pUnder50 + 0.03);
  // the 100 spike is inflated in the real data (blowouts entered as 100)
  within(`exactly 100 (real ${R.pExactly100}, inflated)`, m.p100, 0.06, R.pExactly100 + 0.02);
  within(`average winning margin (real ${REAL.margin.meanAbs})`, m.meanAbsMargin, REAL.margin.meanAbs - 2.5, REAL.margin.meanAbs + 2.5);
  // when one player does well the other does badly
  within(`correlation of the two scores (real about ${REAL.margin.impliedCorrelation})`, m.corr, -0.7, -0.4);
  within(`first player wins (real ${REAL.firstTurn.pWin})`, m.firstWin, 0.495, 0.53);
  within(`first player's average margin (real +${REAL.firstTurn.meanMargin})`, m.firstMargin, 1, 4.5);
  within('draws (real 2-3%)', m.draws, 0.004, 0.04);
  within('the favourite wins (a pre-game rating is right in 69% of real games)', m.favourite, 0.7, 0.8);
});

test('the forecast knows which army is stronger and that a destroyed army scores nothing more', () => {
  const pl = (mission, a, o = {}) => ({ mission, army: a, killRate: 1.3, mode: 'tactical', actionP: 0.7, battleReady: true, ...o });
  const A = army(), B = army();
  const even = F.forecast({ players: { A: pl('Battlefield Dominance', A), B: pl('Battlefield Dominance', B) }, objectives: OBJS, plan, trials: 3000, seed: 9 });
  assert.ok(Math.abs(even.pWinA - 0.5) < 0.04, `mirror game is a coin flip: ${even.pWinA}`);
  // A destroys three times as much as B: A should win most games, by a clear margin
  const lop = F.forecast({ players: { A: pl('Battlefield Dominance', A, { killRate: 2.4 }), B: pl('Battlefield Dominance', B, { killRate: 0.8 }) }, objectives: OBJS, plan, trials: 3000, seed: 9 });
  assert.ok(lop.pWinA > 0.82, `the army that destroys 3x as much wins: ${lop.pWinA}`);
  assert.ok(lop.A.mean - lop.B.mean > 25, `and by a clear margin: ${lop.A.mean} vs ${lop.B.mean}`);
  assert.ok(lop.B.pTabled > 0.35 && lop.A.pTabled < 0.02, `B is often tabled (${lop.B.pTabled}), A almost never (${lop.A.pTabled})`);
  // B destroys nothing at all and loses 3 units a turn: it is wiped out and cannot win on a plan alone
  const none = F.forecast({ players: { A: pl('Battlefield Dominance', A, { killRate: 3 }), B: pl('Battlefield Dominance', B, { killRate: 0 }) }, objectives: OBJS, plan, trials: 3000, seed: 9 });
  assert.ok(none.pWinB < 0.02, `an army that is destroyed does not win: ${none.pWinB}`);
  assert.ok(none.B.unitsLeft[4] < 1.5 && none.B.pTabled > 0.6, `B is all but gone by the end: ${none.B.unitsLeft} tabled ${none.B.pTabled}`);
  assert.ok(none.B.prim[4] < 2 && none.B.prim[4] < none.B.prim[1] / 2, `and scores little primary in round 5: ${none.B.prim}`);
  // half the points: the smaller army loses objectives and the game
  const small = F.armyProfile(A.units.slice(0, 6).map(x => ({ ...x })));
  const half = F.forecast({ players: { A: pl('Battlefield Dominance', A), B: pl('Battlefield Dominance', small) }, objectives: OBJS, plan, trials: 3000, seed: 9 });
  assert.ok(half.pWinA > 0.62, `the bigger army is the favourite even with equal kill rates: ${half.pWinA}`);
});
