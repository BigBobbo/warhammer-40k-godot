// Combat calculator — rules-text parsing (abilities / stratagems -> engine
// modifiers + conditions) on real 11th edition codex wording, and the engine
// grants they feed (per-weapon mods, [LANCE], [CLEAVE], +[RAPID FIRE]).
//
// Run: node --test server/tests/calc-rules.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';

const R = await import(new URL('../public/calc/rules.mjs', import.meta.url).href);
const E = await import(new URL('../public/calc/engine.mjs', import.meta.url).href);
const { STRATAGEMS } = await import(new URL('../public/calc/stratagems-11e.mjs', import.meta.url).href);

const labels = (r) => r.effects.map(e => e.label);

test('Thunderous Charge: +1 S +1 D on melee, only after charging', () => {
  const r = R.parseOffensive('If this unit made a charge move this turn, this unit’s melee attacks have:\n• +1 S.\n• +1 D.');
  assert.deepEqual(labels(r), ['+1 S', '+1 D']);
  assert.deepEqual(r.phases, ['fight']);
  assert.equal(r.conds.charged, true);
  assert.equal(R.conditionsMet(r.conds, { charged: false }), false);
  assert.equal(R.conditionsMet(r.conds, { charged: true }), true);
});

test('target keyword conditions incl. "[Lethal Hits: non-MONSTER/VEHICLE]" and "(excluding ...)"', () => {
  const a = R.parseOffensive('This unit’s ranged attacks that target a MONSTER/VEHICLE unit have +1 to wound rolls.');
  assert.deepEqual(a.conds.targetKw, ['MONSTER', 'VEHICLE']);
  assert.equal(R.conditionsMet(a.conds, { targetKeywords: ['VEHICLE'] }), true);
  assert.equal(R.conditionsMet(a.conds, { targetKeywords: ['INFANTRY'] }), false);
  const b = R.parseOffensive('This unit’s attacks have [Lethal Hits: non-MONSTER/VEHICLE].');
  assert.deepEqual(labels(b), ['Lethal Hits']);
  assert.equal(R.conditionsMet(b.conds, { targetKeywords: ['INFANTRY'] }), true);
  assert.equal(R.conditionsMet(b.conds, { targetKeywords: ['MONSTER'] }), false);
  const c = R.parseOffensive('This unit’s ranged attacks that target a unit (excluding MONSTER/VEHICLE units) have +1 AP.');
  assert.deepEqual(c.conds.targetNotKw, ['MONSTER', 'VEHICLE']);
  assert.deepEqual(c.effects[0].apply, { apMod: 1 });
});

test('"+2 S, AP and D" splits into three stats; "this model’s" is model-scoped', () => {
  const r = R.parseOffensive('This model’s attacks that target a FORTIFICATION/MONSTER/VEHICLE unit have +2 S, AP and D.');
  assert.deepEqual(labels(r), ['+2 S', '+2 AP', '+2 D']);
  assert.equal(r.scope, 'model');
});

test('choices take the first option; re-roll wording', () => {
  const r = R.parseOffensive('This unit’s melee attacks can:\n• Re-roll wound rolls of 1.\n• Or: If the assault doctrine is active for this unit, re-roll wound rolls.');
  assert.deepEqual(r.effects.map(e => e.apply), [{ rerollWounds: 'ones' }]);
  assert.equal(r.partial, true);
  const one = R.parseOffensive('This unit’s ranged attacks that target a MONSTER/VEHICLE unit can: • Re-roll one hit roll. • Re-roll one wound roll.');
  assert.equal(one, null, 're-roll ONE die is not modelled as a full re-roll');
});

test('situational wording starts off; attacker keyword condition', () => {
  const r = R.parseOffensive('In the Fight phase, if this unit is within range of an objective, this unit’s melee attacks: • Have +1 S. • Have +1 AP.');
  assert.equal(r.conds.unknown, true);
  const g = R.parseOffensive('If the unit has the ORKS keyword, for the rest of the battle, melee weapons equipped by all friendly units gain [SUSTAINED HITS 1].');
  assert.deepEqual(labels(g), ['Sustained Hits 1']);
  assert.equal(R.conditionsMet(g.conds, { attackerKeywords: ['ORKS', 'INFANTRY'] }), true);
  assert.equal(R.conditionsMet(g.conds, { attackerKeywords: ['ADEPTUS ASTARTES'] }), false);
});

test('defensive wording is not read as an attacker buff', () => {
  assert.equal(R.parseOffensive('Attacks that target this unit have -1 to hit rolls.'), null);
  const d = R.parseDefensiveText('Attacks that target your unit have -1 AP until that enemy unit has attacked.');
  assert.deepEqual(d.map(x => x.apply), [{ apReduce: 1 }]);
  const h = R.parseDefensiveText('Ranged attacks that target your unit have -1 to hit rolls.');
  assert.deepEqual(h.map(x => [x.apply, x.phases]), [[{ hitMod: -1 }, ['shooting']]]);
});

test('stratagem role, phase and keyword eligibility (real 11e entries)', () => {
  const byName = (n) => STRATAGEMS.find(s => s.name === n);
  const hit = byName("HIT 'EM HARDER");
  assert.equal(R.stratagemRole(hit), 'attack');
  assert.deepEqual(R.stratagemPhases(hit), ['fight']);
  const mow = byName("MOW 'EM DOWN");
  assert.equal(R.stratagemEligible(mow, ['ORKS', 'VEHICLE']), true);
  assert.equal(R.stratagemEligible(mow, ['ORKS', 'VEHICLE', 'WALKER']), false, 'excluding WALKER');
  assert.equal(R.stratagemEligible(mow, ['ORKS', 'INFANTRY']), false);
  const aoc = byName('ARMOUR OF CONTEMPT');
  assert.equal(R.stratagemRole(aoc), 'defend');
  assert.deepEqual(R.stratagemPhases(aoc), ['shooting', 'fight']);
  const unb = byName('UNBRIDLED FEROCITY');
  assert.equal(R.stratagemEligible(unb, ['THUNDERWOLF CAVALRY', 'MOUNTED', 'ADEPTUS ASTARTES']), true);
  assert.equal(R.stratagemEligible(unb, ['GREY HUNTERS', 'INFANTRY', 'ADEPTUS ASTARTES']), false);
  const ht = byName('HURTLING TARGETS');
  assert.equal(R.stratagemEligible(ht, ['ADEPTUS ASTARTES', 'MOUNTED']), true);
  assert.equal(R.stratagemEligible(ht, ['ADEPTUS ASTARTES', 'INFANTRY']), false);
});

test('rapid fire / cleave grants add to an existing value (Close-Range Dakka, Mow ’Em Down)', () => {
  const r = R.parseOffensive(STRATAGEMS.find(s => s.name === 'CLOSE-RANGE DAKKA').effect);
  assert.deepEqual(r.effects[0].apply, { rapidFire: 1 });
});

// --- engine side of the grants --------------------------------------------
const run = (weapons, mods = {}, groups = [{ name: 'G', count: 400, W: 1, Sv: 7, InSv: 0, T: 4 }]) =>
  E.simulate({ attackers: [{ name: 'A', mods, weapons }], defender: { name: 'D', groups, mods: {} }, trials: 40000, seed: 7 });
const W = (o) => ({ name: 'w', count: 10, melee: false, A: '1', skill: 3, S: 4, AP: 0, D: '1', kw: {}, ...o });
const near = (a, b, tol, l) => assert.ok(Math.abs(a - b) <= tol, `${l}: ${a} vs ${b}`);

test('engine: per-weapon mods only touch that weapon', () => {
  // two torrent weapons, 10 each; only the first gets +1 to wound: S4 vs T4 -> 4/6 and 3/6
  const r = run([W({ kw: { torrent: true }, mods: { woundMod: 1 } }), W({ kw: { torrent: true } })]);
  near(r.steps.wounds, 10 * 4 / 6 + 10 * 3 / 6, 0.08, 'wounds');
});

test('engine: granted lance (+1 wound on the charge), cleave added per 5 models, rapid fire added', () => {
  near(run([W({ melee: true, count: 60, kw: { torrent: true } })], { lance: true, charged: true }).steps.wounds / 60, 4 / 6, 0.006, 'lance');
  near(run([W({ melee: true, kw: { cleave: 1 } })], { cleave: 1 }, [{ name: 'G', count: 10, W: 1, Sv: 7, T: 4 }]).steps.attacks, 10 + 10 * 2 * 2, 1e-9, 'cleave 1+1 vs 10 models');
  near(run([W({ kw: { rapidFire: 1 } })], { rapidFire: 1, halfRange: true }).steps.attacks, 10 + 20, 1e-9, 'rapid fire 1+1');
});

test('mergeMods: numbers add, re-rolls keep the stronger, crits the lower', () => {
  const m = E.mergeMods({ hitMod: 1, rerollHits: 'fail', critHit: 5 }, { hitMod: 1, rerollHits: 'ones', critHit: 6, lethal: true });
  assert.deepEqual(m, { hitMod: 2, rerollHits: 'fail', critHit: 5, lethal: true });
});
