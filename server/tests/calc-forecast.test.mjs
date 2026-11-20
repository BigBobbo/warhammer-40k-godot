// Combat Calc mission forecast — 11e primary / secondary scoring, caps, deck.
// Run: node --test server/tests/calc-forecast.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const F = await import(new URL('../public/calc/forecast.mjs', import.meta.url).href);
const M = await import(new URL('../public/calc/missions-11e.mjs', import.meta.url).href);

const u = (name, o = {}) => ({ name, models: 5, ...o });
const ARMY_A = F.armyProfile([u('GH', { models: 10 }), u('Termies', { models: 12, characters: 2, charactersW4: 2 }), u('Caladius', { models: 1, w10: 1 }), u('Outriders', { fast: true }), u('Scouts', { reserves: true })]);
const ARMY_B = F.armyProfile([u('Boyz', { models: 21, bodyguardModels: 20, characters: 1, charactersW4: 1 }), u('Meganobz', { models: 3 }), u('Flash Gitz')]);
const OBJS = [{ id: 'hA', cls: 'home', side: 'A' }, { id: 'eA', cls: 'exp', side: 'A' }, { id: 'c', cls: 'central', side: null }, { id: 'eB', cls: 'exp', side: 'B' }, { id: 'hB', cls: 'home', side: 'B' }];
const planAll = (cells) => Object.fromEntries([1, 2, 3, 4, 5].map(r => [r, typeof cells === 'function' ? cells(r) : cells]));
// fixed mode with no cards = no secondaries; killRate 0 = no kills: primary only
const quiet = (mission, army) => ({ mission, army, mode: 'fixed', fixed: [], killRate: 0, battleReady: false });
const SURE = { home: 1, other: 1 }; // the plan happens exactly

test('data: 18 secondaries (4 usable as Fixed) and 25 primaries; 11e caps', () => {
  assert.equal(M.SECONDARIES.length, 18);
  assert.deepEqual(M.FIXED_IDS.sort(), ['a-grievous-blow', 'assassination', 'bring-it-down', 'engage-on-all-fronts']);
  assert.equal(Object.keys(M.PRIMARIES).length, 25);
  assert.deepEqual([M.RULES.primaryCap, M.RULES.primaryRoundCap, M.RULES.secondaryCap, M.RULES.secondaryRoundCap, M.RULES.battleReady], [45, 15, 45, 15, 10]);
});

test('Battlefield Dominance: exact VP from a fixed plan, 15 per round and 45 total caps', () => {
  // A holds home + both expansions + centre... (4); B holds its home (1)
  const plan = planAll({ hA: 'A', eA: 'A', c: 'A', eB: 'A', hB: 'B' });
  const r = F.forecast({ players: { A: quiet('Battlefield Dominance', ARMY_A), B: quiet('Battlefield Dominance', ARMY_B) }, objectives: OBJS, plan, first: 'A', trials: 20, confidence: SURE });
  // A: R1 2 (more); R2 3*4 + 2*3 = 18 + 2 -> capped 15; R3, R4 18 -> 15, 15 (=47 -> total cap 45)
  assert.deepEqual(r.A.prim.map(Math.round), [2, 15, 15, 13, 0]);
  // B: home only: R2-R5 3 VP each (no non-home bonus)
  assert.deepEqual(r.B.prim.map(Math.round), [0, 3, 3, 3, 3]);
  assert.equal(r.A.mean, 45);
  assert.equal(r.pWinA, 1);
});

test('Outmanoeuvre: 10 VP for the enemy home every turn, per-objective VP by round', () => {
  const plan = planAll({ hA: 'A', eA: 'A', c: 'B', eB: 'B', hB: 'A' });
  const r = F.forecast({ players: { A: quiet('Outmanoeuvre', ARMY_A), B: quiet('Outmanoeuvre', ARMY_B) }, objectives: OBJS, plan, first: 'B', trials: 10, confidence: SURE });
  // A non-home: eA + hB = 2. R1: 10 + 4*2 = 18 -> 15; R2-3: 10 + 5*2 -> 15; R4-5: 10 + 6*2 -> 15 (total cap 45)
  assert.deepEqual(r.A.prim.map(Math.round), [15, 15, 15, 0, 0]);
  // B non-home: c + eB = 2: R1 8, R2 10, R3 10, R4 12 -> 40, R5 12 -> capped at 45: 5
  assert.deepEqual(r.B.prim.map(Math.round), [8, 10, 10, 12, 5]);
});

test('Immovable Object: central for 3 VP every turn, 5 VP per non-home objective from round 2', () => {
  const plan = planAll({ hA: 'A', eA: 'B', c: 'A', eB: 'B', hB: 'B' });
  const r = F.forecast({ players: { A: quiet('Immovable Object', ARMY_A), B: quiet('Battlefield Dominance', ARMY_B) }, objectives: OBJS, plan, trials: 10, confidence: SURE });
  assert.deepEqual(r.A.prim.map(Math.round), [3, 8, 8, 8, 8]);
});

test('end-of-battle VP are not under the 15 VP per round limit (Event Companion FAQ), only the 45 VP maximum', () => {
  // Punishment: 4 VP for a non-home objective + 5 VP for more objectives = 9 a round from R2; end of battle 8 VP for their home
  const all = planAll({ hA: 'A', eA: 'A', c: 'A', eB: 'A', hB: 'A' });
  const r = F.forecast({ players: { A: quiet('Punishment', ARMY_A), B: quiet('Punishment', ARMY_B) }, objectives: OBJS, plan: all, first: 'A', trials: 10, confidence: SURE });
  assert.deepEqual(r.A.prim.map(Math.round), [0, 9, 9, 9, 9], 'per-round VP');
  assert.equal(Math.round(r.A.primEnd), 8, 'the 8 VP end-of-battle bonus is not cut by the round limit');
  assert.equal(r.A.mean, 44);
  // Outmanoeuvre is at 15 a round and 45 by round 3: nothing can go over 45
  const o = F.forecast({ players: { A: quiet('Vanguard Operation', ARMY_A), B: quiet('Vanguard Operation', ARMY_B) }, objectives: OBJS, plan: all, first: 'A', trials: 200, confidence: SURE });
  assert.ok(o.A.mean <= 45 + 1e-9, `primary maximum holds: ${o.A.mean}`);
});

test('kills drive kill primaries and secondaries; caps hold for every game', () => {
  const pl = (army) => ({ mission: 'Meatgrinder', army, killRate: 2, mode: 'tactical' });
  const r = F.forecast({ players: { A: pl(ARMY_A), B: pl(ARMY_B) }, objectives: OBJS, plan: planAll({ hA: 'A', hB: 'B', eA: 'c', eB: 'c', c: 'c' }), trials: 1500 });
  for (const X of ['A', 'B']) {
    assert.ok(r[X].prim.every(v => v <= 15 + 1e-9) && r[X].sec.every(v => v <= 15 + 1e-9), 'per-round caps');
    assert.ok(r[X].hist.findLastIndex(p => p > 0) <= 100, 'never above 100 VP');
    assert.ok(r[X].prim[0] > 1.5, `round-1 kills score (${r[X].prim[0]})`);
  }
  for (const l of r.lead) assert.ok(Math.abs(l.A + l.B + l.tie - 1) < 1e-9);
  assert.ok(Math.abs(r.pWinA + r.pWinB + r.pDraw - 1) < 1e-9);
});

test('dead cards: no targets in the enemy army -> card is dead and never scores', () => {
  assert.equal(F.cardDead('bring-it-down', ARMY_B), true, 'no W10+ Orks here');
  assert.equal(F.cardDead('bring-it-down', ARMY_A), false);
  assert.equal(F.cardDead('a-grievous-blow', ARMY_B), false, '20 Boyz');
  assert.equal(F.cardDead('a-grievous-blow', ARMY_A), true);
  const r = F.forecast({ players: { A: { mission: 'Meatgrinder', army: ARMY_A, killRate: 2 }, B: { mission: 'Meatgrinder', army: ARMY_B, killRate: 2 } }, objectives: OBJS, plan: planAll({}), trials: 800 });
  assert.equal(r.A.cards['bring-it-down'], undefined, 'A never holds a dead Bring It Down');
  assert.ok((r.B.cards['bring-it-down']?.perDraw ?? 0) > 1, 'B can kill the Caladius');
});

test('deck: next-draw odds and a known hand / used pile carried into the forecast', () => {
  const odds = F.nextDrawOdds(['a', 'b', 'c', 'd']);
  assert.equal(odds.a, 0.5);
  const start = { hand: ['secure-no-mans-land'], used: ['no-prisoners', 'assassination'], primary: 10, secondary: 8 };
  const plan = planAll({ hA: 'A', eA: 'A', c: 'A', eB: 'B', hB: 'B' });
  const r = F.forecast({ players: { A: { mission: 'Battlefield Dominance', army: ARMY_A, killRate: 1, start }, B: { mission: 'Battlefield Dominance', army: ARMY_B, killRate: 1 } }, objectives: OBJS, plan, startRound: 3, trials: 600 });
  assert.equal(r.A.cards['assassination'], undefined, 'used cards are out of the deck');
  assert.ok(r.A.mean >= 10 + 8 + 10, 'the current score carries over');
  assert.deepEqual(r.A.prim.slice(0, 2), [0, 0], 'rounds already played are not re-simulated');
});

test('plan uncertainty: planned objectives are sometimes lost, so one extra objective helps but does not decide everything', () => {
  const plan = planAll(r => ({ hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: 'c' }));
  const more = planAll(r => ({ hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: r >= 2 ? 'A' : 'c' }));
  const pl = (army) => ({ mission: 'Battlefield Dominance', army, killRate: 1.3 });
  const base = F.forecast({ players: { A: pl(ARMY_A), B: pl(ARMY_B) }, objectives: OBJS, plan, trials: 2000 });
  const up = F.forecast({ players: { A: pl(ARMY_A), B: pl(ARMY_B) }, objectives: OBJS, plan: more, trials: 2000 });
  assert.ok(up.pWinA > base.pWinA + 0.15, `${base.pWinA} -> ${up.pWinA}`);
  assert.ok(up.pWinA < 0.995, `not a certainty: ${up.pWinA}`);
});

test('deterministic for a seed', () => {
  const P = { players: { A: { mission: 'Meatgrinder', army: ARMY_A }, B: { mission: 'Punishment', army: ARMY_B } }, objectives: OBJS, plan: planAll({}), trials: 300, seed: 7 };
  assert.deepEqual(F.forecast(P).A.hist, F.forecast(P).A.hist);
});

test('your estimate of a card: the forecast gives it exactly that VP if drawn (it pays its max with estimate / max odds)', () => {
  assert.ok(M.SECONDARIES.every(c => c.max === 5), 'every 11e tactical secondary pays at most 5 VP when it scores');
  const pl = (army, vpEst) => ({ mission: 'Battlefield Dominance', army, killRate: 1.3, vpEst });
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const r = F.forecast({ players: { A: pl(ARMY_A, { assassination: 3, 'no-prisoners': 0 }), B: pl(ARMY_B) }, objectives: OBJS, plan, trials: 4000 });
  const a = r.A.cards.assassination;
  assert.ok(Math.abs(a.perDraw - 3) < 0.25, `Assassination ${a.perDraw}`);
  assert.ok(Math.abs(a.quickRate - 0.6) < 0.05, `scores at its first chance in 3/5 of draws: ${a.quickRate}`);
  assert.equal(r.A.cards['no-prisoners']?.perDraw ?? 0, 0, 'estimate 0 = never scores');
});
