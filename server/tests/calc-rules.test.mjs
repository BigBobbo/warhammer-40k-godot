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
  assert.deepEqual(one.effects.map(e => e.apply), [{ rerollOneHit: true }, { rerollOneWound: true }], 're-roll ONE die is a single-die re-roll, not a full one');
  assert.equal(one.conds.unknown, false);
});

test('situational wording starts off; attacker keyword condition', () => {
  const r = R.parseOffensive('In the Fight phase, if this unit is within range of an objective, this unit’s melee attacks: • Have +1 S. • Have +1 AP.');
  assert.equal(r.conds.onObjective, true, 'objective is a situation chip, not unknown');
  assert.equal(r.conds.unknown, false);
  assert.deepEqual(r.phases, ['fight']);
  assert.equal(R.conditionsMet(r.conds, {}), false);
  assert.equal(R.conditionsMet(r.conds, { onObjective: true }), true);
  const hidden = R.parseOffensive('In your Shooting phase, when this unit has shot, select one enemy unit hit by those attacks. That unit’s ranged attacks have +1 to hit rolls.');
  assert.ok(!hidden || hidden.conds.unknown, 'truly situational wording still starts off');
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

// --- older (10e-style) wording used by the index-card factions (Wahapedia export) -----------
test('older wording: "each time a model in your unit makes an attack, add 1 to the Hit roll" etc.', () => {
  const a = R.parseOffensive('Until the end of the phase, each time a model in your unit makes an attack, add 1 to the Hit roll and add 1 to the Wound roll.');
  assert.deepEqual(a.effects.map(e => e.apply), [{ hitMod: 1 }, { woundMod: 1 }]);
  const b = R.parseOffensive('Until the end of the phase, each time a friendly TYRANIDS model makes an attack that targets that enemy unit, if the attacking model’s unit is within 6" of your SYNAPSE unit, re-roll a Hit roll of 1 and re-roll a Wound roll of 1.');
  assert.deepEqual(b.effects.map(e => e.apply), [{ rerollHits: 'ones' }, { rerollWounds: 'ones' }]);
  const c = R.parseOffensive('Until the end of the phase, each time a model in your unit makes a melee attack, improve the Armour Penetration characteristic of that attack by 1 and add 1 to the Strength characteristic of that attack.');
  assert.deepEqual(c.effects.map(e => e.label), ['+1 AP', '+1 S']);
  assert.deepEqual(c.phases, ['fight']);
  const t = R.parseOffensive('Each time a model in this unit makes an attack that targets a MONSTER or VEHICLE unit, add 1 to the Wound roll.');
  assert.deepEqual(t.conds.targetKw, ['MONSTER', 'VEHICLE']);
});

test('older wording: defensive "each time an attack targets your unit ..."', () => {
  assert.deepEqual(R.parseDefensiveText('Until the attacking unit has finished making its attacks, each time an attack targets your unit, worsen the Armour Penetration characteristic of that attack by 1.').map(x => x.apply), [{ apReduce: 1 }]);
  assert.deepEqual(R.parseDefensiveText('Until the end of the phase, each time an attack targets your unit, if the Strength characteristic of that attack is greater than the Toughness characteristic of your unit, subtract 1 from the Wound roll.').map(x => x.apply), [{ woundModIfSGreaterT: -1 }]);
  assert.deepEqual(R.parseDefensiveText('Until the end of the phase, each time a ranged attack targets your unit, subtract 1 from the Hit roll.').map(x => x.apply), [{ hitMod: -1 }]);
});

test('older wording: role from the effect, eligibility from "TARGET: One X unit from your army"', () => {
  const byName = (n) => STRATAGEMS.find(s => s.name === n && !s.missing);
  const iw = byName('IRRESISTIBLE WILL');
  assert.equal(R.stratagemRole(iw), 'attack');
  assert.equal(R.stratagemEligible(iw, ['TYRANIDS', 'SYNAPSE', 'MONSTER']), true);
  assert.equal(R.stratagemEligible(iw, ['TYRANIDS', 'INFANTRY']), false, 'needs SYNAPSE');
  const rh = byName('REINFORCED HIVE NODE');
  assert.equal(R.stratagemRole(rh), 'defend');
});

test('stratagem bundle: Wahapedia export filled the gaps for index-card factions', () => {
  const withText = (f) => STRATAGEMS.filter(s => s.faction === f && !s.missing).length;
  for (const f of ['NEC', 'TYR', 'AE', 'AM', 'CSM', 'GK', 'LoV', 'TAU']) assert.ok(withText(f) >= 30, `${f}: ${withText(f)}`);
  const keys = STRATAGEMS.map(s => `${s.detachment}|${s.name}`.toUpperCase().replace(/[^A-Z0-9|]/g, ''));
  assert.equal(new Set(keys).size, keys.length, 'no duplicate name+detachment');
});

test('choice rules: every "• Or:" option is parsed with the shared subject', () => {
  const r = R.parseOffensive('Your unit’s melee attacks have: • [Lance]. • Or: If the assault doctrine is active for your unit, [Lance] and +1 AP.');
  assert.deepEqual(r.effects.map(e => e.label), ['Lance']);
  assert.equal(r.alternatives.length, 1);
  assert.deepEqual(r.alternatives[0].effects.map(e => e.label).sort(), ['+1 AP', 'Lance']);
  assert.deepEqual(r.alternatives[0].phases, ['fight']);
});

test('damage re-rolls and ignore-modifier wording', () => {
  assert.deepEqual(R.parseOffensive('This unit’s ranged attacks can re-roll damage rolls.').effects.map(e => e.apply), [{ rerollDamage: true }]);
  const mt = R.parseOffensive(STRATAGEMS.find(s => s.name === 'MOLECULAR TARGETING' && !s.missing).effect);
  assert.deepEqual(mt.effects.map(e => e.apply), [{ ignoreHitMods: true }, { ignoreWoundMods: true }]);
});

test('engine: re-roll one hit / damage re-rolls / ignore hit modifiers', () => {
  // 10 attacks hitting on 4+: 5 hits + one re-rolled miss (if any) hits half the time
  const oneHit = run([W({ skill: 4 })], { rerollOneHit: true });
  near(oneHit.steps.hits, 5 + (1 - 0.5 ** 10) * 0.5, 0.03, 'one hit re-roll');
  // D6 damage, re-rolled when below 3.5: E = 1/2*5 + 1/2*3.5 = 4.25 (vs 3.5)
  const dmg = run([W({ count: 1, kw: { torrent: true }, S: 8, AP: -6, D: 'D6' })], { rerollDamage: true }, [{ name: 'G', count: 1, W: 50, Sv: 7, T: 4 }]);
  near(dmg.meanWounds / (5 / 6), 4.25, 0.03, 'damage re-roll');
  // BS3+ with cover (BS worsened) and -1 to hit: ignoring both -> back to 4/6
  const ign = E.simulate({ attackers: [{ name: 'A', mods: { ignoreHitMods: true }, weapons: [W({ count: 60 })] }],
    defender: { name: 'D', groups: [{ name: 'G', count: 400, W: 1, Sv: 7, T: 4 }], mods: { cover: true, hitMod: -1 } }, trials: 40000, seed: 3 });
  near(ign.steps.hits / 60, 4 / 6, 0.005, 'ignore hit mods');
});

test('bundle: a misspelt duplicate (UNBRIDLED FEROICITY) is merged into the game row', () => {
  assert.equal(STRATAGEMS.filter(s => /UNBRIDLED FERO/i.test(s.name)).length, 1);
});
