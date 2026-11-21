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

// ---- detachment rules: linked by the detachment, for the units they name

const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const { readFileSync } = await import('fs');
const fixture = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');

test('a rule for named units: "Attacks made by friendly Blood Claws/Thunderwolf Cavalry/Wulfen units have [Lethal Hits: Character/Monster/Vehicle]"', () => {
  const r = R.parseOffensive('Attacks made by friendly Blood Claws/Thunderwolf Cavalry/Wulfen units have [Lethal Hits: Character/Monster/Vehicle].');
  assert.deepEqual(labels(r), ['Lethal Hits']);
  assert.deepEqual(r.conds.selfAny, ['BLOOD CLAWS', 'THUNDERWOLF CAVALRY', 'WULFEN']);
  assert.deepEqual(r.conds.targetKw, ['CHARACTER', 'MONSTER', 'VEHICLE']);
  assert.equal(r.conds.unknown, false);
  const ctx = (own, tgt) => ({ attackerKeywords: own, targetKeywords: tgt });
  assert.equal(R.conditionsMet(r.conds, ctx(['INFANTRY', 'WULFEN'], ['VEHICLE'])), true);
  assert.equal(R.conditionsMet(r.conds, ctx(['MOUNTED', 'THUNDERWOLF CAVALRY'], ['MONSTER'])), true, 'a keyword of two words');
  assert.equal(R.conditionsMet(r.conds, ctx(['INFANTRY', 'WULFEN'], ['INFANTRY'])), false, 'only against a Character, Monster or Vehicle (24.01)');
  assert.equal(R.conditionsMet(r.conds, ctx(['INFANTRY', 'GREY HUNTERS'], ['VEHICLE'])), false, 'not for other units');
  // several keywords in a row: all of them
  const d = R.parseOffensive('Friendly Adeptus Astartes Dreadnought units can re-roll hit rolls of 1.');
  assert.deepEqual([labels(d), d.conds.selfAny], [['Re-roll hit 1s'], ['ADEPTUS ASTARTES DREADNOUGHT']]);
  assert.equal(R.phraseInKeywords('ADEPTUS ASTARTES DREADNOUGHT', new Set(['VEHICLE', 'DREADNOUGHT', 'ADEPTUS ASTARTES'])), true);
  assert.equal(R.phraseInKeywords('ADEPTUS ASTARTES DREADNOUGHT', new Set(['VEHICLE', 'ADEPTUS ASTARTES'])), false);
  assert.equal(R.phraseInKeywords('THUNDERWOLF CAVALRY', new Set(['THUNDERWOLF', 'MOUNTED'])), false, 'not half a keyword');
  // wording the parser already knew is not changed by this
  const old = R.parseOffensive('This unit’s melee attacks have [Lethal Hits].');
  assert.deepEqual([labels(old), old.conds.selfAny], [['Lethal Hits'], []]);
});

test('the detachment rules of a codex army are found by the detachment (the Space Wolves list: three detachments, three rules)', () => {
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt'));
  const rules = A.detachmentRules(sw);
  assert.deepEqual(rules.map(r => r.name), ['Assault Mastery (Assault Brethren)', 'Legendary Slayers (Saga of the Beastslayer)', 'Lightning-fast Strike (Stormlance Task Force)']);
  assert.match(rules[1].text, /Attacks made by friendly Blood Claws\/Thunderwolf Cavalry\/Wulfen units have \[Lethal Hits: Character\/Monster\/Vehicle\]/);
  assert.match(rules[2].text, /Mounted\/Speeder units have \+2" M/, 'the codex rule, not the provisional "Lightning Assault"');
  assert.ok(!rules.some(r => /Lightning Assault/.test(r.name)));
  // a faction without a codex import keeps the rule its detachment record points to
  const orks = A.importArmy(fixture('gw-orks-1000.txt'));
  assert.deepEqual(A.detachmentRules(orks).map(r => r.name), ['Get Stuck In (War Horde)']);
});

test('Legendary Slayers reaches the engine: Lethal Hits for Wulfen and Thunderwolf Cavalry against a Vehicle, not for Grey Hunters, not against Boyz without their Warboss', () => {
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt')), orks = A.importArmy(fixture('gw-orks-1000.txt'));
  const det = (cu) => A.attackerRules(cu, sw).rules.filter(r => r.kind === 'detachment');
  const unit = (re) => sw.units.find(u => re.test(u.name));
  assert.deepEqual(det(unit(/Wulfen/)).map(r => [r.source, r.label]), [['Legendary Slayers (Saga of the Beastslayer)', 'Lethal Hits']]);
  assert.equal(det(unit(/Thunderwolf Cavalry \(1\)/)).length, 1);
  assert.equal(det(unit(/Grey Hunters/)).length, 0, 'the rule is not listed on units it is not for');
  const tw = unit(/Thunderwolf Cavalry \(1\)/);
  const { rules } = A.attackerRules(tw, sw);
  const on = (tgt) => new Set(rules.filter(r => r.phases.includes('fight') && A.attackerRuleOn(r, undefined, { charged: true, targetKeywords: tgt.keywords, attackerKeywords: tw.keywords })).map(r => r.id));
  const wagon = orks.units.find(u => /Battlewagon/.test(u.name)), gretchin = orks.units.find(u => /Gretchin/.test(u.name)) ?? orks.units.find(u => !u.keywords.includes('CHARACTER') && !u.keywords.includes('VEHICLE') && !u.keywords.includes('MONSTER'));
  const rows = A.attackerRows(tw, 'fight', null);
  const vsWagon = A.buildAttacker(tw, rows, { charged: true }, rules, on(wagon), 'fight');
  assert.equal(vsWagon.mods.lethal, true, 'against the Battlewagon');
  const vsInf = A.buildAttacker(tw, rows, { charged: true }, rules, on(gretchin), 'fight');
  assert.ok(!vsInf.mods.lethal, `not against ${gretchin.name}`);
  // the size of it (the audit measured 36% -> 79% to destroy the Battlewagon on the charge)
  const profile = A.defenderProfile(wagon, orks);
  const defender = A.buildDefender(profile, new Set(profile.rules.filter(r => r.auto).map(r => r.id)), 'fight', {}, {});
  const withRule = E.simulate({ phase: 'fight', attackers: [vsWagon], defender, trials: 20000, seed: 5 });
  const without = E.simulate({ phase: 'fight', attackers: [{ ...vsWagon, mods: { ...vsWagon.mods, lethal: false } }], defender, trials: 20000, seed: 5 });
  assert.ok(withRule.meanWounds > without.meanWounds * 1.2, `${without.meanWounds.toFixed(2)} -> ${withRule.meanWounds.toFixed(2)} wounds, destroyed ${without.pWipe.toFixed(2)} -> ${withRule.pWipe.toFixed(2)}`);
  console.log(`  Thunderwolf Cavalry charging a Battlewagon: destroyed ${(100 * without.pWipe).toFixed(0)}% without Legendary Slayers, ${(100 * withRule.pWipe).toFixed(0)}% with it`);
});

// ---- wargear that changes the profile, on the models that carry it (22.04)

test('Storm Shield "+1 W": the Terminators with a shield have 4 wounds, the one with lightning claws 3', () => {
  assert.deepEqual(R.parseDefensiveText('This model has +1 W.').map(e => [e.label, e.apply, e.always]), [['+1 W', { W: 1 }, true]]);
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt'));
  const cu = sw.units.find(u => /Terminator Assault Squad/.test(u.name));
  const p = A.defenderProfile(cu, sw);
  const shield = p.rules.find(r => r.source === 'Storm Shield' && r.label === '+1 W');
  assert.ok(shield && shield.auto, 'a characteristic of the model: on');
  const d = A.buildDefender(p, new Set(p.rules.filter(r => r.auto).map(r => r.id)), 'fight', {}, {});
  const body = d.groups.filter(g => !g.character).map(g => [g.count, g.W]).sort((a, b) => b[0] - a[0]);
  assert.deepEqual(body, [[9, 4], [1, 3]], 'sergeant + 8 with shields: W4; twin lightning claws: W3');
  // it matters: the same attack kills fewer of them
  const atk = [{ name: 'a', mods: {}, weapons: [{ name: 'w', count: 6, melee: true, A: '4', skill: 3, S: 8, AP: -2, D: '3', kw: {} }] }];
  const off = A.buildDefender(p, new Set(p.rules.filter(r => r.auto && r !== shield).map(r => r.id)), 'fight', {}, {});
  const k4 = E.simulate({ phase: 'fight', attackers: atk, defender: d, trials: 20000, seed: 9 }).meanKills;
  const k3 = E.simulate({ phase: 'fight', attackers: atk, defender: off, trials: 20000, seed: 9 }).meanKills;
  assert.ok(k4 < 0.75 * k3, `D3 attacks: ${k3.toFixed(2)} Terminators at W3, ${k4.toFixed(2)} at W4`);
});

test('wargear that is not in the list is not given to every model: a Shield-Captain with a guardian spear has no Praesidium Shield', () => {
  const list = 'Shields (500 points)\n\nAdeptus Custodes\nShield Host\nIncursion (1000 points)\n\nShield-Captain (130 points)\n  • 1x Guardian Spear\n  • Warlord\n';
  const army = A.importArmy(list);
  const cu = army.units.find(u => /Shield-Captain/.test(u.name));
  assert.ok(cu, JSON.stringify(army.warnings));
  const p = A.defenderProfile(cu, army);
  const ps = p.rules.find(r => /Praesidium Shield/.test(r.source));
  assert.ok(ps, 'the rule is still listed, so it can be switched on');
  assert.deepEqual([ps.auto, ps.notCarried], [false, true]);
  const d = A.buildDefender(p, new Set(p.rules.filter(r => r.auto).map(r => r.id)), 'fight', {}, {});
  assert.ok(d.groups.every(g => !g.dr) && !d.mods.damageReduction, 'no -1 Damage by default');
  // with the shield in the list, it is on for that model
  const army2 = A.importArmy(list.replace('1x Guardian Spear', '1x Praesidium Shield\n    1x Sentinel Blade'));
  const p2 = A.defenderProfile(army2.units[0], army2);
  const ps2 = p2.rules.find(r => /Praesidium Shield/.test(r.source));
  assert.deepEqual([ps2?.auto, ps2?.notCarried], [true, false], JSON.stringify(army2.warnings));
});

// ---- round 3 fixes (1.102): abilities for some targets only, rules for named weapons, enhancement grants

test('24.01: a weapon ability limited to targets with (or without) a keyword is off against the others', () => {
  const k = A.weaponKw([
    { keyword_id: 'sustained-hits', parameters: { value: 2, excluded_target_keywords: ['Monster', 'Vehicle'] } },
    { keyword_id: 'devastating-wounds', parameters: { required_target_keywords_any: ['Infantry'] } },
    { keyword_id: 'lethal-hits' },
    { keyword_id: 'anti', parameters: { target_keyword: 'Monster', threshold: 4, required_target_keywords_any: ['Monster'] } },
  ]);
  assert.deepEqual(k.tags, ['sustained hits 2: not Monster/Vehicle', 'devastating wounds: Infantry only', 'lethal hits', 'Anti-monster 4+: Monster only']);
  assert.equal(k.limits.length, 3);
  const vs = (...kws) => A.limitKw(k.kw, k.limits, new Set(kws));
  const inf = vs('INFANTRY');
  assert.deepEqual([inf.kw.sustained, inf.kw.dev, inf.kw.lethal, inf.kw.anti.length, inf.off], [2, true, true, 0, ['Anti-monster 4+: Monster only']]);
  const veh = vs('VEHICLE');
  assert.deepEqual([veh.kw.sustained, veh.kw.dev, veh.kw.lethal], [0, false, true], 'against a Vehicle: no Sustained Hits, no Devastating Wounds; Lethal Hits has no limit');
  assert.deepEqual(veh.off, ['sustained hits 2: not Monster/Vehicle', 'devastating wounds: Infantry only', 'Anti-monster 4+: Monster only']);
  assert.equal(vs('MONSTER').kw.anti.length, 1);
  assert.deepEqual(A.limitKw(k.kw, k.limits, null).off, [], 'no target known: nothing is switched off');
  assert.equal(k.kw.sustained, 2, 'the weapon itself is not changed');
});

test('rules for named weapons: Terminatus Assault and Full-throttle Assault', () => {
  const ta = R.parseWeaponBullets('If this unit made a charge move this turn, this unit’s: • Lightning Claws weapons have [Sustained Hits 1: non-Monster/Vehicle]. • Thunder Hammer weapons have [Sustained Hits 1: Monster/Vehicle].');
  assert.deepEqual(ta.map(b => [b.weapon, b.others, labels(b), b.conds.charged, b.conds.targetKw, b.conds.targetNotKw]), [
    ['lightning claws', null, ['Sustained Hits 1'], true, [], ['MONSTER', 'VEHICLE']],
    ['thunder hammer', null, ['Sustained Hits 1'], true, ['MONSTER', 'VEHICLE'], []],
  ]);
  const ft = R.parseWeaponBullets('If this unit made a charge move this turn, this unit’s: • Thunder Hammer weapons have +1 to hit rolls and [Sustained Hits 1]. • Other melee weapons have +1 D and [Sustained Hits 1].');
  assert.deepEqual(ft.map(b => [b.weapon, b.others, labels(b), b.phases]), [['thunder hammer', null, ['+1 to hit', 'Sustained Hits 1'], ['shooting', 'fight']], [null, 'melee', ['+1 D', 'Sustained Hits 1'], ['fight']]]);
  assert.equal(R.parseWeaponBullets('This unit’s melee attacks have [Lethal Hits].'), null, 'an ordinary unit rule is not this');
  assert.equal(R.weaponNamed('Twin Lightning Claws', 'lightning claws'), true);
  assert.equal(R.weaponNamed('Thunder Hammer – Hunter', 'thunder hammer'), true);
  assert.equal(R.weaponNamed('Chainsword', 'thunder hammer'), false);
  // in the list: after a charge the Terminators' hammers have Sustained Hits 1 against the Battlewagon only,
  // the lightning claws against the Boyz only; the Outriders' hammer and their other weapons differ
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt')), orks = A.importArmy(fixture('gw-orks-1000.txt'));
  const build = (re, tre) => {
    const cu = sw.units.find(u => re.test(u.name)), d = orks.units.find(u => tre.test(u.name));
    const profile = A.defenderProfile(d, orks);
    const { rules } = A.attackerRules(cu, sw);
    const on = new Set(rules.filter(r => r.phases.includes('fight') && A.attackerRuleOn(r, undefined, { charged: true, targetKeywords: profile.keywords, attackerKeywords: cu.keywords })).map(r => r.id));
    return Object.fromEntries(A.buildAttacker(cu, A.attackerRows(cu, 'fight', A.defenderSummary(profile)), { charged: true }, rules, on, 'fight').weapons.map(w => [w.name, w.mods ?? {}]));
  };
  const vsWagon = build(/Terminator Assault/, /Battlewagon/), vsBoyz = build(/Terminator Assault/, /Boyz/);
  assert.deepEqual([vsWagon['Thunder Hammer'].sustained, vsWagon['Twin Lightning Claws'].sustained], [1, undefined]);
  assert.deepEqual([vsBoyz['Thunder Hammer'].sustained, vsBoyz['Twin Lightning Claws'].sustained], [undefined, 1]);
  const out = build(/Outrider/, /Boyz/);
  assert.deepEqual(out['Thunder Hammer'], { hitMod: 1, sustained: 1 });
  assert.deepEqual([out.Chainsword, out['Chaplain on Bike: Crozius Arcanum']], [{ damageMod: 1, sustained: 1 }, { damageMod: 1, sustained: 1 }], 'the other melee weapons of the unit, the Chaplain\'s too');
});

test('an enhancement that gives its unit a keyword and Move: Wolf-Touched ("This unit has: • Wulfen. • +2" M.")', () => {
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt'));
  const cu = sw.units.find(u => /Captain on Bike/.test(u.name));
  const cap = cu.members.find(m => /Captain on Bike/.test(m.dcUnit.name));
  assert.deepEqual(A.enhancementGrants(cap.ru), { keywords: ['WULFEN'], move: 2, name: 'Wolf-Touched' });
  assert.ok(cu.keywords.includes('WULFEN'));
  // on the board: Wulfen 9" + 2" (Wolf-Touched) + 2" (Stormlance: the unit is Mounted through its Captain, 19.03)
  const b = A.boardUnit(cu, sw);
  assert.deepEqual([b.move, b.moveBonus, b.moveBonusFrom], [13, 4, 'Lightning-fast Strike + Wolf-Touched']);
  assert.deepEqual(A.enhancementGrants({}), { keywords: [], move: 0, name: null });
  // Damaged X and the other core flags come from the datasheet
  const orks = A.importArmy(fixture('gw-orks-1000.txt'));
  assert.equal(A.coreFlags(orks.units.find(u => /Battlewagon/.test(u.name))).damaged, 6);
  assert.equal(A.coreFlags(sw.units.find(u => /Grey Hunters/.test(u.name))).damaged, 0);
  assert.deepEqual([A.coreFlags(sw.units.find(u => /Logan/.test(u.name))).deepStrike, A.coreFlags(sw.units.find(u => /Scout Squad \(1\)/.test(u.name))).infiltrators, A.coreFlags(sw.units.find(u => /Scout Squad \(1\)/.test(u.name))).scouts], [true, true, 6]);
});

test('the defender can use Command Re-roll on a save; a Blast weapon cannot shoot an engaged Monster / Vehicle', () => {
  const sw = A.importArmy(fixture('gw-space-wolves-2000.txt')), orks = A.importArmy(fixture('gw-orks-1000.txt'));
  const wagon = orks.units.find(u => /Battlewagon/.test(u.name));
  const p = A.defenderProfile(wagon, orks);
  const cr = p.rules.find(r => /COMMAND RE-?ROLL/i.test(r.source));
  assert.ok(cr && cr.kind === 'stratagem' && cr.auto === false && cr.label === 'Re-roll one save', JSON.stringify(cr));
  assert.equal(A.buildDefender(p, new Set([cr.id]), 'shooting', {}, {}).mods.rerollOneSave, true);
  // "Engaged in melee" on a Vehicle target: -1 to hit for shooting (17.03) and no Blast
  const d = A.buildDefender(p, new Set(), 'shooting', { engaged: true }, {});
  assert.equal(d.mods.engagedMV, true);
  const boyz = orks.units.find(u => /Boyz/.test(u.name));
  assert.ok(!A.buildDefender(A.defenderProfile(boyz, orks), new Set(), 'shooting', { engaged: true }, {}).mods.engagedMV, 'only a Monster or Vehicle can be shot while engaged');
  const scouts = sw.units.find(u => /Scout Squad \(1\)/.test(u.name));
  const rows = A.attackerRows(scouts, 'shooting', A.defenderSummary(p), { targetEngaged: true });
  assert.equal(rows.find(r => /Frag/.test(r.label)).blocked, 'Blast weapons cannot target an engaged unit');
  assert.deepEqual([rows.find(r => /Krak/.test(r.label)).blocked, rows.find(r => /Krak/.test(r.label)).count], [null, 1]);
});
