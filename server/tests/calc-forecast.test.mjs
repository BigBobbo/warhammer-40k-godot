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
// a typical 13-unit tournament list (for the statistical tests: small test armies wipe each other out)
const big = (name, pts, o = {}) => ({ name, models: 5, points: pts, ...o });
const BIG = () => F.armyProfile([
  big('Warlord', 110, { models: 1, characters: 1, charactersW4: 1 }), big('Leader + squad', 260, { models: 11, characters: 1, charactersW4: 1, bodyguardModels: 10 }),
  big('Battleline 1', 160, { models: 10 }), big('Battleline 2', 160, { models: 10 }), big('Horde', 200, { models: 20, bodyguardModels: 20 }),
  big('Elite 1', 190), big('Elite 2', 190), big('Fast 1', 120, { fast: true }), big('Fast 2', 120, { fast: true }),
  big('Tank 1', 190, { models: 1, w10: 1 }), big('Tank 2', 180, { models: 1, w10: 1 }), big('Scouts', 70, { reserves: true }), big('Cheap', 50),
]);
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
  // two equal armies: the plan is what differs
  const plan = planAll(r => ({ hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: 'c' }));
  const more = planAll(r => ({ hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: r >= 2 ? 'A' : 'c' }));
  const pl = () => ({ mission: 'Immovable Object', army: BIG(), killRate: 1.3 });
  const base = F.forecast({ players: { A: pl(), B: pl() }, objectives: OBJS, plan, trials: 3000 });
  const up = F.forecast({ players: { A: pl(), B: pl() }, objectives: OBJS, plan: more, trials: 3000 });
  assert.ok(Math.abs(base.pWinA - 0.5) < 0.05, `equal armies, mirrored plan: ${base.pWinA}`);
  assert.ok(up.pWinA > base.pWinA + 0.08, `${base.pWinA} -> ${up.pWinA}`);
  assert.ok(up.pWinA < 0.9, `not a certainty: ${up.pWinA}`);
  assert.ok(up.A.primMean > base.A.primMean + 2 && up.B.primMean < base.B.primMean - 1, `more primary for A, less for B: ${base.A.primMean}/${base.B.primMean} -> ${up.A.primMean}/${up.B.primMean}`);
});

test('deterministic for a seed', () => {
  const P = { players: { A: { mission: 'Meatgrinder', army: ARMY_A }, B: { mission: 'Punishment', army: ARMY_B } }, objectives: OBJS, plan: planAll({}), trials: 300, seed: 7 };
  assert.deepEqual(F.forecast(P).A.hist, F.forecast(P).A.hist);
});

test('your estimate of a card: the forecast gives it exactly that VP if drawn (it pays its max with estimate / max odds)', () => {
  assert.ok(M.SECONDARIES.every(c => c.max === 5), 'every 11e tactical secondary pays at most 5 VP when it scores');
  const pl = (army, vpEst, killRate = 0) => ({ mission: 'Battlefield Dominance', army, killRate, vpEst });
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  // no losses: exactly the estimate
  const r = F.forecast({ players: { A: pl(ARMY_A, { assassination: 3, 'no-prisoners': 0 }), B: pl(ARMY_B) }, objectives: OBJS, plan, trials: 4000 });
  const a = r.A.cards.assassination;
  assert.ok(Math.abs(a.perDraw - 3) < 0.2, `Assassination ${a.perDraw}`);
  assert.ok(Math.abs(a.quickRate - 0.6) < 0.04, `scores at its first chance in 3/5 of draws: ${a.quickRate}`);
  assert.equal(r.A.cards['no-prisoners']?.perDraw ?? 0, 0, 'estimate 0 = never scores');
  // in a real game (units are destroyed): still close to the estimate; a little less, because
  // a card drawn after your army is gone cannot be scored
  const g = F.forecast({ players: { A: pl(BIG(), { 'behind-enemy-lines': 3 }, 1.3), B: pl(BIG(), {}, 1.3) }, objectives: OBJS, plan, trials: 4000 });
  const b = g.A.cards['behind-enemy-lines'];
  assert.ok(b.perDraw > 2.6 && b.perDraw <= 3.1, `Behind Enemy Lines with losses: ${b.perDraw}`);
  // what a card pays (perDraw) is not cut by the 15-per-round / 45 VP limits; what it adds (perDrawNet) is
  assert.ok(b.perDrawNet <= b.perDraw + 1e-9, `${b.perDrawNet} <= ${b.perDraw}`);
});

test('kills from the calculator: same pace as the calibrated rate, tough units last, a what-if multiplier', () => {
  const names = BIG().units.map(x => x.name);
  const table = (f) => Object.fromEntries(names.map(a => [a, Object.fromEntries(names.map(d => [d, typeof f === 'function' ? f(a, d) : f]))]));
  const plan = planAll(r => ({ hA: 'A', hB: 'B', eA: r >= 2 ? 'A' : 'c', eB: r >= 2 ? 'B' : 'c', c: 'c' }));
  const pl = (o = {}) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: null, ...o });
  const run = (fa, fb, o = {}) => F.forecast({ players: { A: pl(o.A), B: pl(o.B) }, objectives: OBJS, plan, trials: 3000, seed: 11, fracs: { A: table(fa), B: table(fb) } });
  // every unit removes a third of its best target: 13 x 1/3 x 0.3 delivered = 1.3 units a turn
  const calc = run(1 / 3, 1 / 3);
  const rate = F.forecast({ players: { A: pl({ killRate: 1.3 }), B: pl({ killRate: 1.3 }) }, objectives: OBJS, plan, trials: 3000, seed: 11 });
  assert.ok(Math.abs(calc.A.mean - rate.A.mean) < 3, `mean VP ${calc.A.mean} vs ${rate.A.mean}`);
  assert.ok(Math.abs(calc.A.unitsLeft[4] - rate.A.unitsLeft[4]) < 0.8, `units left ${calc.A.unitsLeft[4]} vs ${rate.A.unitsLeft[4]}`);
  // B's two tanks are almost immune (2% a hit): A scores Bring It Down far less often
  const toughTanks = run((a, d) => (d.startsWith('Tank') ? 0.02 : 1 / 3), 1 / 3);
  assert.ok(toughTanks.A.cards['bring-it-down'].scoreRate < calc.A.cards['bring-it-down'].scoreRate / 2, `${toughTanks.A.cards['bring-it-down'].scoreRate} vs ${calc.A.cards['bring-it-down'].scoreRate}`);
  // an army that cannot hurt the enemy at all loses its units and the game
  const harmless = run(0, 1 / 3);
  assert.ok(harmless.pWinA < 0.1 && harmless.B.unitsLeft[4] > 12.9, `${harmless.pWinA}, B keeps ${harmless.B.unitsLeft[4]} units`);
  // "trade harder": 50% more damage raises the win chance
  const harder = run(1 / 3, 1 / 3, { A: { killMul: 1.5 } });
  assert.ok(harder.pWinA > calc.pWinA + 0.08, `${calc.pWinA} -> ${harder.pWinA}`);
});

test('real-game card rates: used for position cards by battle round, your own rating replaces them', () => {
  assert.deepEqual(M.REAL_RATES['behind-enemy-lines'].by, [0.14, 0.55, 0.63, 0.63, 0.69]);
  assert.deepEqual(F.defaultCardRate('behind-enemy-lines', 3), { p: 0.63, from: 'real' });
  assert.deepEqual(F.defaultCardRate('beacon', 3), { p: 0.5, from: 'none' }, 'no equivalent 10th edition card');
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const pl = (rate) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: 0, rate });
  const dflt = F.forecast({ players: { A: pl({}), B: pl({}) }, objectives: OBJS, plan, trials: 3000 });
  const never = F.forecast({ players: { A: pl({ 'behind-enemy-lines': 0 }), B: pl({}) }, objectives: OBJS, plan, trials: 3000 });
  assert.ok(dflt.A.cards['behind-enemy-lines'].scoreRate > 0.75, `kept until scored: ${dflt.A.cards['behind-enemy-lines'].scoreRate}`);
  assert.equal(never.A.cards['behind-enemy-lines']?.perDraw ?? 0, 0, 'your rating 0 = never');
});

test('cards in hand: followed from the current turn (how often each still scores, and for how much)', () => {
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const pl = (o = {}) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: 1.3, ...o });
  const run = (startA, { P: _p, ...extra } = {}) => F.forecast({ players: { A: pl({ start: { hand: ['bring-it-down', 'behind-enemy-lines'], used: [], primary: 12, secondary: 5, ...startA }, ...extra }), B: pl() }, objectives: OBJS, plan, first: 'A', startRound: 3, startTurn: 0, trials: 3000, ...(_p ?? {}) });
  const r = run({});
  const bid = r.A.cards['bring-it-down'], bel = r.A.cards['behind-enemy-lines'];
  assert.equal(bid.drawRate, 1, 'a card in hand counts as drawn in every game');
  assert.ok(bid.scoreRate > 0.3 && bid.scoreRate < 1, `two tanks to kill in three rounds: ${bid.scoreRate}`);
  assert.ok(Math.abs(bid.perDraw - 5 * bid.scoreRate) < 1e-9, 'Bring It Down pays 5 VP when it scores');
  assert.ok(bel.scoreRate > 0.3 && bel.scoreRate <= 1, `Behind Enemy Lines from round 3: ${bel.scoreRate}`);
  // both tanks are already destroyed: the card in hand has no targets and never scores
  const P2 = F.forecast({ players: { A: pl({ start: { hand: ['bring-it-down'], used: [], primary: 12, secondary: 5 } }), B: pl({ start: { destroyed: ['Tank 1', 'Tank 2'] } }) }, objectives: OBJS, plan, first: 'A', startRound: 3, startTurn: 0, trials: 800 });
  assert.equal(P2.A.cards['bring-it-down'].scoreRate, 0, 'no W10+ model left');
  assert.equal(P2.A.cards['bring-it-down'].drawRate, 1);
  // the two cards in hand ARE this turn's draw: the forecast does not draw two more this turn
  const drew = run({}, { P: { startDrawn: 2 } });
  const cardsSeen = (res) => Object.values(res.A.cards).reduce((a, c) => a + c.drawRate, 0);
  assert.ok(Math.abs((cardsSeen(r) - cardsSeen(drew)) - 2) < 0.25, `two fewer cards come up: ${cardsSeen(r)} vs ${cardsSeen(drew)}`);
  assert.ok(drew.A.secMean < r.A.secMean - 1, `so fewer secondary VP: ${drew.A.secMean} vs ${r.A.secMean}`);
  // my own estimate applies to a card that is already in my hand
  const sure = run({}, { vpEst: { 'behind-enemy-lines': 5, 'bring-it-down': 0 } });
  assert.ok(sure.A.cards['behind-enemy-lines'].scoreRate > 0.97, `estimate = max: ${sure.A.cards['behind-enemy-lines'].scoreRate}`);
  assert.equal(sure.A.cards['bring-it-down'].scoreRate, 0, 'estimate 0 = never');
  assert.ok(sure.A.secMean > run({}, { vpEst: { 'behind-enemy-lines': 0, 'bring-it-down': 0 } }).A.secMean + 3, 'and it moves the forecast');
});

test('Fixed or Tactical: Fixed cards are active all battle, pay per kill and stop at 20 VP each', () => {
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const pl = (o = {}) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: 1.3, ...o });
  const run = (modeA) => F.forecast({ players: { A: pl(modeA), B: pl() }, objectives: OBJS, plan, trials: 3000 });
  const tac = run({ mode: 'tactical' });
  // BIG has 2 CHARACTER models with W4+ (4 VP each) and 2 models with W10+ (4 VP each): 16 VP at most
  const fix = run({ mode: 'fixed', fixed: ['assassination', 'bring-it-down'] });
  assert.ok(fix.A.secMean > 3 && fix.A.secMean <= 16, `Fixed kill cards: ${fix.A.secMean}`);
  assert.ok(fix.A.p90 - fix.A.prim.reduce((a, b) => a + b, 0) <= 45, 'never above the limits');
  assert.ok(tac.A.secMean > fix.A.secMean + 5, `Tactical scores more against an army with few targets: ${tac.A.secMean} vs ${fix.A.secMean}`);
  // a tank company: Bring It Down as Fixed pays 4 VP a tank, but never more than 20
  const tanks = F.armyProfile(Array.from({ length: 9 }, (_, i) => big(`Tank ${i}`, 180, { models: 1, w10: 1 })));
  const many = F.forecast({ players: { A: pl({ mode: 'fixed', fixed: ['bring-it-down', 'assassination'], killRate: 3 }), B: { mission: 'Battlefield Dominance', army: tanks, killRate: 0.3 } }, objectives: OBJS, plan, trials: 600 });
  assert.ok(many.A.secMean > 12 && many.A.secMean <= 20 + 1e-9, `9 tanks: ${many.A.secMean}`);
  assert.equal(many.A.cards.assassination?.perDraw ?? 0, 0, 'no characters to kill');
});

test('Assassination: with every enemy CHARACTER destroyed it scores 5 VP (no "when drawn" discard); Bring It Down with no target is redrawn', () => {
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const pl = (o = {}) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: 0, ...o });
  // round 4, no more kills; both of B's CHARACTER units and both tanks are already destroyed
  const lost = { destroyed: ['Warlord', 'Leader + squad', 'Tank 1', 'Tank 2'] };
  const held = F.forecast({ players: { A: pl({ start: { hand: ['assassination'], used: [], primary: 20, secondary: 10 } }), B: pl({ start: lost }) }, objectives: OBJS, plan, first: 'A', startRound: 4, startTurn: 0, trials: 400 });
  assert.equal(held.A.cards.assassination.scoreRate, 1, 'in hand: scored at the end of the turn in every game');
  assert.equal(held.A.cards.assassination.perDraw, 5);
  const fresh = F.forecast({ players: { A: pl({ start: { hand: [], used: [], primary: 20, secondary: 10 } }), B: pl({ start: lost }) }, objectives: OBJS, plan, first: 'A', startRound: 4, startTurn: 0, trials: 3000 });
  assert.ok(fresh.A.cards.assassination.drawRate > 0.15, `still drawn: ${fresh.A.cards.assassination?.drawRate}`);
  assert.equal(fresh.A.cards.assassination.scoreRate, 1, 'drawn later: also 5 VP');
  assert.equal(fresh.A.cards['bring-it-down'], undefined, 'no W10+ model left: discarded when drawn, a new card is drawn');
});

test('battle over (start after round 5): the forecast is the final score, nothing more is simulated', () => {
  const plan = planAll({ hA: 'A', hB: 'B', eA: 'A', eB: 'B', c: 'c' });
  const pl = (start) => ({ mission: 'Battlefield Dominance', army: BIG(), killRate: 1.3, start });
  const r = F.forecast({ players: { A: pl({ hand: ['assassination'], used: [], primary: 40, secondary: 32 }), B: pl({ hand: [], used: [], primary: 35, secondary: 30 }) }, objectives: OBJS, plan, first: 'A', startRound: 6, startTurn: 0, trials: 200 });
  assert.deepEqual([r.A.mean, r.A.p10, r.A.p90, r.B.mean], [82, 82, 82, 75], 'scores + 10 for a Battle Ready army');
  assert.deepEqual([r.pWinA, r.pWinB, r.pDraw], [1, 0, 0]);
  assert.ok(Number.isFinite(r.margin.p50) && r.margin.p50 === 7);
});
