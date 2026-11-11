// Combat calculator engine — validation against hand-computed 11th edition
// expectations. Every expected value below is derived on paper in the
// comment beside it (independent oracle), then compared with the Monte Carlo
// mean within a tolerance.
//
// Run: node --test server/tests/calc-engine.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const E = await import(new URL('../public/calc/engine.mjs', import.meta.url).href);

const TRIALS = 100000;

function near(actual, expected, tol, label) {
  assert.ok(Math.abs(actual - expected) <= tol,
    `${label}: expected ≈${expected.toFixed(4)} (±${tol}), got ${actual.toFixed(4)}`);
}

// Helpers -------------------------------------------------------------------
const weapon = (o) => ({ name: 'W', count: 1, melee: false, A: '1', skill: 3, S: 4, AP: 0, D: '1', kw: {}, ...o });
const group = (o) => ({ name: 'G', count: 10, W: 1, Sv: 7, InSv: 0, T: 4, character: false, ...o });
function run({ weapons, groups, amods = {}, dmods = {}, keywords = [], trials = TRIALS, phase = 'shooting', attackers = null }) {
  return E.simulate({
    phase,
    attackers: attackers ?? [{ name: 'A', mods: amods, weapons }],
    defender: { name: 'D', keywords, groups, mods: dmods },
    trials,
    seed: 12345,
  });
}
// A big pool of 1-wound models so the target never runs out.
const pool = (o = {}) => [group({ count: 400, ...o })];

// ---------------------------------------------------------------------------

test('wound chart (05.02)', () => {
  assert.equal(E.woundThreshold(8, 4), 2);
  assert.equal(E.woundThreshold(5, 4), 3);
  assert.equal(E.woundThreshold(4, 4), 4);
  assert.equal(E.woundThreshold(3, 4), 5);
  assert.equal(E.woundThreshold(2, 4), 6);
  assert.equal(E.woundThreshold(4, 8), 6);
});

test('dice expressions', () => {
  assert.deepEqual(E.parseDice('2D6+3'), { n: 2, sides: 6, plus: 3 });
  assert.deepEqual(E.parseDice('D3'), { n: 1, sides: 3, plus: 0 });
  assert.equal(E.diceMean(E.parseDice('D6+1')), 4.5);
  assert.equal(E.diceMean(E.parseDice('3')), 3);
});

test('baseline: 10 bolt rifles (A2 BS3+ S4 AP-1 D1) into Sv3 T4', () => {
  // 20 attacks; hit 4/6 -> 13.333; wound 4+ = 1/2 -> 6.667; save 3+ at AP-1 = 4+ fails 1/2 -> 3.333
  const r = run({ weapons: [weapon({ count: 10, A: '2', AP: -1 })], groups: pool({ Sv: 3 }) });
  near(r.steps.attacks, 20, 1e-9, 'attacks');
  near(r.steps.hits, 13.333, 0.05, 'hits');
  near(r.steps.wounds, 6.667, 0.05, 'wounds');
  near(r.meanWounds, 3.333, 0.04, 'damage');
});

test('lethal hits: critical hits auto-wound (24.23)', () => {
  // 20 attacks: crits 20/6 = 3.333 auto-wound; normal hits 20*3/6 = 10 -> 5 wounds; total 8.333
  const r = run({ weapons: [weapon({ count: 10, A: '2', kw: { lethal: true } })], groups: pool() });
  near(r.steps.wounds, 8.333, 0.05, 'wounds');
});

test('sustained hits 1 (24.36)', () => {
  // hits 13.333 + crits 3.333 = 16.667; wounds 8.333
  const r = run({ weapons: [weapon({ count: 10, A: '2', kw: { sustained: 1 } })], groups: pool() });
  near(r.steps.hits, 16.667, 0.06, 'hits');
  near(r.steps.wounds, 8.333, 0.05, 'wounds');
});

test('sustained hits D3', () => {
  // 60 torrent? no — 60 attacks BS3: crits 10, each +2 (mean D3) -> 20 extra; hits 40 + 20 = 60
  const r = run({ weapons: [weapon({ count: 60, kw: { sustained: 3, sustainedDice: true } })], groups: pool() });
  near(r.steps.hits, 60, 0.15, 'hits');
});

test('devastating wounds bypass saves, after normal damage (24.10)', () => {
  // 20 attacks BS3 -> 13.333 hits. Wound 4+: crits 1/6 -> 2.222 mortal; normal 2/6 -> 4.444
  // vs Sv2 InSv2 (only natural 1 fails) -> 0.741 unsaved. Total damage 2.963.
  const r = run({ weapons: [weapon({ count: 10, A: '2', kw: { dev: true } })], groups: pool({ Sv: 2, InSv: 2 }) });
  near(r.meanWounds, 2.963, 0.04, 'damage');
});

test('devastating wounds do NOT spill over: each critical wound damages one model', () => {
  // 6 torrent attacks S8 (wound 2+), D3, dev vs 1W models with Sv2 InSv2.
  // crit wounds 6/6*... = 6 * 1/6 = 1 -> 1 kill each (3 MW, 2 wasted)
  // normal wounds 6 * 4/6 = 4, unsaved 1/6 -> 0.667 kills. Total 1.667 (10e spill-over would be ~3.67).
  const r = run({ weapons: [weapon({ count: 6, kw: { torrent: true, dev: true }, S: 8, D: '3' })], groups: pool({ Sv: 2, InSv: 2 }) });
  near(r.meanKills, 1.667, 0.03, 'kills');
});

test('excess damage is lost per model (05.04)', () => {
  // 10 torrent attacks S8 AP-4 D3 vs 10 W2 models Sv3: wound 5/6 -> 8.333 unsaved (save impossible)
  // each kills one model and wastes 1 damage: kills 8.333, wounds lost 16.667
  const r = run({ weapons: [weapon({ count: 10, kw: { torrent: true }, S: 8, AP: -4, D: '3' })], groups: [group({ count: 10, W: 2, Sv: 3 })] });
  near(r.meanKills, 8.333, 0.03, 'kills');
  near(r.meanWounds, 16.667, 0.06, 'wounds');
});

test('feel no pain per wound lost (24.12)', () => {
  // 12 torrent S8 AP-6: 10 unsaved D1, FNP 5+ keeps 1/3 -> 6.667 lost
  const r = run({ weapons: [weapon({ count: 12, kw: { torrent: true }, S: 8, AP: -6 })], groups: pool({ Sv: 3 }), dmods: { fnp: 5 } });
  near(r.meanWounds, 6.667, 0.04, 'wounds lost');
});

test('FNP rolls for each point of damage (D3 vs W3, FNP 5+)', () => {
  // one unsaved D3 attack (torrent, S8, AP-6 -> wound 5/6) on a W3 model:
  // P(kill) = 5/6 * (2/3)^3 = 0.2469
  const r = run({ weapons: [weapon({ kw: { torrent: true }, S: 8, AP: -6, D: '3' })], groups: [group({ count: 1, W: 3, Sv: 3 })], dmods: { fnp: 5 } });
  near(r.pWipe, 0.2469, 0.006, 'P(kill)');
});

test('damage reduction: -1 D (min 1) and half', () => {
  const base = { weapons: [weapon({ count: 12, kw: { torrent: true }, S: 8, AP: -6, D: '2' })], groups: pool({ W: 10, count: 50 }) };
  near(run({ ...base, dmods: { damageReduction: 1 } }).meanWounds, 10, 0.05, 'D2-1');
  // D3 halved -> 2
  const r = run({ ...base, weapons: [weapon({ count: 12, kw: { torrent: true }, S: 8, AP: -6, D: '3' })], dmods: { damageReduction: 'half' } });
  near(r.meanWounds, 20, 0.08, 'half');
});

test('benefit of cover worsens BS by 1 (13.08), ignores cover negates it', () => {
  // BS3 -> BS4: 20 * 3/6 = 10 hits
  const r = run({ weapons: [weapon({ count: 20 })], groups: pool(), dmods: { cover: true } });
  near(r.steps.hits, 10, 0.05, 'cover hits');
  const r2 = run({ weapons: [weapon({ count: 20, kw: { ignoresCover: true } })], groups: pool(), dmods: { cover: true } });
  near(r2.steps.hits, 13.333, 0.05, 'ignores cover');
  // cover does nothing in melee
  const r3 = run({ weapons: [weapon({ count: 20, melee: true })], groups: pool(), dmods: { cover: true } });
  near(r3.steps.hits, 13.333, 0.05, 'melee unaffected');
});

test('cover stacks with a -1 hit modifier (characteristic is not dice-capped)', () => {
  // BS3 -> 4+ (cover) and -1 to hit -> needs 5+ : 20 * 2/6 = 6.667
  const r = run({ weapons: [weapon({ count: 20 })], groups: pool(), dmods: { cover: true, hitMod: -1 } });
  near(r.steps.hits, 6.667, 0.05, 'hits');
});

test('hit modifiers cap at +1 (heavy + buff)', () => {
  // BS3, +1 from heavy (stationary) and +1 buff -> capped +1 -> 2+ : 20 * 5/6 = 16.667
  const r = run({ weapons: [weapon({ count: 20, kw: { heavy: true } })], groups: pool(), amods: { stationary: true, hitMod: 1 } });
  near(r.steps.hits, 16.667, 0.05, 'hits');
});

test('re-roll hit rolls of 1 / failed', () => {
  // ones: 4/6 + 1/6*4/6 = 0.7778 ; failed: 4/6 + 2/6*4/6 = 0.8889
  near(run({ weapons: [weapon({ count: 60 })], groups: pool(), amods: { rerollHits: 'ones' } }).steps.hits / 60, 0.7778, 0.004, 'ones');
  near(run({ weapons: [weapon({ count: 60 })], groups: pool(), amods: { rerollHits: 'fail' } }).steps.hits / 60, 0.8889, 0.004, 'fail');
});

test('twin-linked re-rolls the wound roll (24.38)', () => {
  // torrent, S4 vs T4: 1/2 + 1/2*1/2 = 0.75
  const r = run({ weapons: [weapon({ count: 60, kw: { torrent: true, twin: true } })], groups: pool() });
  near(r.steps.wounds / 60, 0.75, 0.004, 'wound rate');
});

test('lance: +1 to wound after charging (24.21)', () => {
  // S4 vs T4 4+ -> 3+ : 4/6
  const r = run({ weapons: [weapon({ count: 60, melee: true, kw: { torrent: true, lance: true } })], groups: pool(), amods: { charged: true } });
  near(r.steps.wounds / 60, 0.6667, 0.004, 'wound rate');
});

test('wound modifiers net and cap at ±1; -1 only when S > T', () => {
  // S5 vs T4 (3+) with defender -1 if S>T -> 4+ : 0.5
  const r = run({ weapons: [weapon({ count: 60, S: 5, kw: { torrent: true } })], groups: pool(), dmods: { woundModIfSGreaterT: -1 } });
  near(r.steps.wounds / 60, 0.5, 0.004, 'S>T');
  // S4 vs T4 unaffected
  const r2 = run({ weapons: [weapon({ count: 60, S: 4, kw: { torrent: true } })], groups: pool(), dmods: { woundModIfSGreaterT: -1 } });
  near(r2.steps.wounds / 60, 0.5, 0.004, 'S=T');
});

test('anti-X Y+: critical wounds on Y+ vs keyword (24.03)', () => {
  // torrent S3 vs T6 (6+), anti-infantry 4+, dev wounds: crit wounds 3/6, all mortal
  const w = weapon({ count: 60, S: 3, kw: { torrent: true, dev: true, anti: [{ keyword: 'INFANTRY', threshold: 4 }] } });
  const r = run({ weapons: [w], groups: pool({ T: 6, Sv: 2, InSv: 2 }), keywords: ['INFANTRY'] });
  near(r.steps.mortals / 60, 0.5, 0.005, 'mortals');
  const r2 = run({ weapons: [w], groups: pool({ T: 6, Sv: 2, InSv: 2 }), keywords: ['VEHICLE'] });
  near(r2.steps.mortals / 60, 1 / 6, 0.005, 'no keyword');
});

test('saves: invulnerable uses the unmodified roll, armour takes AP', () => {
  // AP-3 vs Sv3 InSv4 -> 4+ invuln: fail 1/2
  const r = run({ weapons: [weapon({ count: 60, S: 8, AP: -3, kw: { torrent: true } })], groups: pool({ Sv: 3, InSv: 4 }) });
  near(r.steps.unsaved / 60, (5 / 6) * 0.5, 0.005, 'unsaved');
  // natural 1 always fails even with a +1 save modifier on a 2+
  const r2 = run({ weapons: [weapon({ count: 60, S: 8, kw: { torrent: true } })], groups: pool({ Sv: 2 }), dmods: { saveMod: 1 } });
  near(r2.steps.unsaved / 60, (5 / 6) / 6, 0.004, 'nat 1');
});

test('snap shooting: hits only on 6, no critical hits (15.09)', () => {
  const r = run({ weapons: [weapon({ count: 60, kw: { lethal: true } })], groups: pool(), amods: { overwatch: true, rerollHits: 'fail' } });
  near(r.steps.hits / 60, 1 / 6, 0.004, 'hit rate');
  // lethal never triggers: wounds = hits * 1/2
  near(r.steps.wounds / 60, 1 / 12, 0.004, 'wound rate');
});

test('blast adds X dice per 5 target models; rapid fire and melta at half range', () => {
  const blast = run({ weapons: [weapon({ A: 'D6', kw: { blast: 1 } })], groups: [group({ count: 10 })] });
  near(blast.steps.attacks, 5.5, 0.02, 'blast vs 10');
  const rf = run({ weapons: [weapon({ count: 5, kw: { rapidFire: 1 } })], groups: pool(), amods: { halfRange: true } });
  near(rf.steps.attacks, 10, 1e-9, 'rapid fire');
  // melta 2: D6+2 at half range vs W20 models, torrent S8 AP-4 -> 5/6 * 5.5
  const m = run({ weapons: [weapon({ kw: { torrent: true, melta: 2 }, S: 8, AP: -4, D: 'D6' })], groups: [group({ count: 1, W: 20, Sv: 3 })], amods: { halfRange: true } });
  near(m.meanWounds, (5 / 6) * 5.5, 0.03, 'melta');
});

test('kill distribution matches the binomial', () => {
  // 6 torrent S8 AP-6 into 10 W1 models: kills ~ Binomial(6, 5/6)
  const r = run({ weapons: [weapon({ count: 6, S: 8, AP: -6, kw: { torrent: true } })], groups: [group({ count: 10, Sv: 3 })] });
  const p = 5 / 6;
  const C = (n, k) => { let c = 1; for (let i = 0; i < k; i++) c = c * (n - i) / (i + 1); return c; };
  for (let k = 0; k <= 6; k++) near(r.kills[k], C(6, k) * p ** k * (1 - p) ** (6 - k), 0.006, `P(${k})`);
});

test('allocation: characters last, Precision picks the character group (05.03, 24.28)', () => {
  const groups = [group({ name: 'Boyz', count: 5, W: 1, Sv: 5 }), group({ name: 'Boss', count: 1, W: 5, Sv: 4, character: true })];
  // 5 guaranteed D1 unsaved: all bodyguards die first, leader untouched
  const w = weapon({ count: 5, S: 8, AP: -6, kw: { torrent: true } });
  const r = run({ weapons: [w], groups, trials: 20000 });
  assert.ok(r.groupKills[1].mean === 0, 'leader not killed while bodyguards live');
  // Precision: damage goes to the character first
  const r2 = run({ weapons: [{ ...w, kw: { torrent: true, precision: true } }], groups, trials: 20000 });
  near(r2.groupKills[1].mean, 0.4019, 0.01, 'leader killed (P(5 of 5 wound) = (5/6)^5)');
});

test('attached unit uses the bodyguard toughness (19.02)', () => {
  // S5: bodyguard T4 -> 3+ (leader T6 would be 5+)
  const groups = [group({ count: 100, T: 4 }), group({ count: 1, T: 6, character: true, W: 5 })];
  const r = run({ weapons: [weapon({ count: 60, S: 5, kw: { torrent: true } })], groups });
  near(r.steps.wounds / 60, 4 / 6, 0.005, 'wound rate');
});

test('damage carries over between attacking units, attacks stop at the last model', () => {
  const w = weapon({ count: 3, S: 8, AP: -6, kw: { torrent: true }, D: '2' });
  const r = run({
    attackers: [
      { name: 'First', mods: {}, weapons: [w] },
      { name: 'Second', mods: {}, weapons: [w] },
    ],
    groups: [group({ count: 1, W: 6, Sv: 3 })],
  });
  // 6 attacks, each wounds 5/6 for 2 dmg: kill needs >= 3 wounding -> P = 1 - P(X<=2), X~Bin(6,5/6)
  const p = 5 / 6, q = 1 / 6;
  const pLe2 = q ** 6 + 6 * p * q ** 5 + 15 * p * p * q ** 4;
  near(r.pWipe, 1 - pLe2, 0.006, 'P(kill)');
  assert.ok(r.perAttacker[1].wounds < r.perAttacker[0].wounds + 1, 'second unit only finishes what is left');
});

test('hazardous: one roll per weapon, 1-2 fails', () => {
  const r = run({ weapons: [weapon({ count: 3, kw: { hazardous: true } })], groups: pool() });
  near(r.hazardMW, 1, 0.02, 'mortal wounds to attacker');
});

test('damaged model is finished first (wounded model priority)', () => {
  // one W3 model already on 1 wound + one fresh: a single D1 unsaved kills the damaged one
  const r = run({ weapons: [weapon({ S: 8, AP: -6, kw: { torrent: true } })], groups: [group({ count: 2, W: 3, Sv: 3, woundsLeftFirst: 1 })] });
  near(r.meanKills, 5 / 6, 0.01, 'kills');
});
