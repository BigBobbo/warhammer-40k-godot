// "My army, phase by phase": the phase a rule is used in, read from its words,
// how often it can be used, and the sheet built for real lists
// (public/calc/phasesheet.mjs, adapter.mjs phaseSheetInput).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const P = await import(new URL('../public/calc/phasesheet.mjs', import.meta.url).href);
const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const { STRATAGEMS } = await import(new URL('../public/calc/stratagems-11e.mjs', import.meta.url).href);
const list = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');
const ph = (t) => P.phasesOfText(t);

test('the phase is read from the words of the rule (real codex wording)', () => {
  // Thunderous Charge: a charge move this turn = the Fight phase, not the Charge phase
  assert.deepEqual(ph('If this unit made a charge move this turn, this unit’s melee attacks have:\n• +1 S.\n• +1 D.'), ['fight']);
  // Terminatus Assault: weapons by name, no "melee" in the text
  assert.deepEqual(ph('If this unit made a charge move this turn, this unit’s:\n• Lightning Claws weapons have [Sustained Hits 1: non-Monster/Vehicle].\n• Thunder Hammer weapons have [Sustained Hits 1: Monster/Vehicle].'), ['fight']);
  // Strategic Acumen: "until the start of your next Command phase" is how long it lasts
  assert.deepEqual(ph('In your Command phase, you can use this ability. If you do, select one combat doctrine to be active for this unit until the start of your next Command phase.'), ['command']);
  assert.deepEqual(ph('In your Shooting phase, when this unit is selected to shoot, you can select one visible enemy unit. This unit’s ranged attacks that target that unit have [Devastating Wounds].'), ['shooting']);
  assert.deepEqual(ph('At the end of your Movement phase, if this unit is controlling an objective, that objective is secured.'), ['movement']);
  assert.deepEqual(ph('When this unit is selected to make an advance/fall-back move, that advance/fall-back move does not prevent this unit from being eligible to start an action.'), ['movement']);
  assert.deepEqual(ph('In the Declare Battle Formations step, you can split this unit into two units.'), ['before']);
  // "the battle round" is not "the battle"
  assert.deepEqual(ph('At the start of the battle round, if a model with this ability is your WARLORD, gain 1CP.'), ['command']);
  // attacks of both kinds
  assert.deepEqual(ph('Attacks made by friendly Blood Claws/Thunderwolf Cavalry/Wulfen units have [Lethal Hits: Character/Monster/Vehicle].'), ['shooting', 'fight']);
  assert.deepEqual(ph('This unit’s attacks have +1 to hit rolls.'), ['shooting', 'fight']);
  assert.deepEqual(ph('In the Fight phase, if this unit is within range of an objective, this unit’s melee attacks:\n• Have +1 S.\n• Have +1 AP.'), ['fight']);
  // every phase = always on
  assert.deepEqual(ph('At the start of each phase, the assault doctrine, devastator doctrine and tactical doctrine are active for this unit.'), ['always']);
  // nothing about a phase: the sheet lists it under "always on"
  assert.deepEqual(ph('This model has +1 W.'), []);
  assert.deepEqual(ph('Being engaged does not prevent this unit from being eligible to start an action.'), []);
});

test('what protects a unit, and reactions, are for the opponent’s turn', () => {
  // the OPPONENT's attack: "ranged" here is not this unit's shooting
  assert.deepEqual(ph('Ranged attacks that target this unit have -1 D.'), ['enemy']);
  assert.deepEqual(ph('Attacks that target this unit have -1 AP.'), ['enemy']);
  assert.deepEqual(ph('While this unit is within range of an objective, attacks that target this unit with a S greater than this unit’s T have -1 to wound rolls.'), ['enemy']);
  assert.deepEqual(ph('Attacks allocated to this model have -1 D.'), ['enemy']);
  assert.deepEqual(ph('This model has a 4+ InSv.'), ['enemy']);
  assert.deepEqual(ph('Friendly Adeptus Custodes units with this ability have Feel No Pain 5+ against mortal wounds.'), ['enemy']);
  // Vengeful Surge: in THEIR Shooting phase; the surge move is not a Movement phase rule
  assert.deepEqual(ph('In your opponent’s Shooting phase, when an enemy unit has shot, if a model in this unit lost a wound as a result of those attacks, this unit can make a surge move of up to D6+2".'), ['enemy']);
  // the attacker's own rule about its target stays an attacking rule
  assert.deepEqual(ph('This unit’s ranged attacks that target a MONSTER/VEHICLE unit can re-roll one hit roll.'), ['shooting']);
  // both: a pre-battle token that the opponent can remove
  assert.deepEqual(ph('At the start of the battle, you can set up one Teleport Homer token for this unit on the battlefield. If you do:\n• If an enemy unit ends a move within 1" of that Teleport Homer token, that Teleport Homer token is removed from the battlefield.'), ['before', 'enemy']);
  // an example in the rule is not the rule (Martial Ka'tah)
  assert.deepEqual(ph('At the start of your Command phase, friendly Adeptus Custodes units with this ability are readied. Example: If you selected the Solar Watch detachment, that unit has +2" M in addition to the normal effect of Calistus.'), ['command']);
});

test('how often: once per battle, per battle round, per turn', () => {
  assert.deepEqual(P.usageOf('War Cry (Once per battle, per army): At the start of the Command phase, you can use this ability.'), { per: 'battle', uses: 1 });
  assert.deepEqual(P.usageOf('Twice per battle, for the rest of the battle, you gain 1 Miracle Dice Pool.'), { per: 'battle', uses: 2 });
  assert.deepEqual(P.usageOf('Once per battle round, one unit can be targeted for 0CP.'), { per: 'round', uses: 1 });
  assert.deepEqual(P.usageOf('Once per turn, when an enemy unit ends a move within 9".'), { per: 'turn', uses: 1 });
  assert.equal(P.usageOf('You can select the assault doctrine one additional time per battle.'), null);
  assert.equal(P.usageLabel({ per: 'battle', uses: 2 }), 'twice per battle');
  assert.equal(P.usageLabel({ per: 'round', uses: 1 }), 'once per battle round');
});

test('stratagems: the phases of your turn, and what can be used in the opponent’s turn', () => {
  const core = (name) => STRATAGEMS.find(s => s.detachment === 'Core' && s.name === name);
  assert.deepEqual(P.stratagemPhases(core('INSANE BRAVERY')), ['command']);
  assert.deepEqual(P.stratagemPhases(core('EXPLOSIVES')), ['shooting']);
  assert.deepEqual(P.stratagemPhases(core('FIRE OVERWATCH')), ['enemy'], 'end of the OPPONENT’s Movement phase');
  assert.deepEqual(P.stratagemPhases(core('RAPID INGRESS')), ['enemy']);
  assert.deepEqual(P.stratagemPhases(core('COUNTEROFFENSIVE')), ['enemy']);
  assert.deepEqual(P.stratagemPhases(core('COMMAND RE-ROLL')), ['always'], 'any phase');
  assert.deepEqual(P.stratagemPhases(core('EPIC CHALLENGE')), ['fight', 'enemy'], 'either player’s turn: your Fight phase and theirs');
  // "Your opponent's Shooting phase or the Fight phase": never in your own Shooting phase
  assert.deepEqual(P.stratagemPhases({ turn: 'Either player’s turn', phase: 'Shooting or Fight phase', when: 'Your opponent’s Shooting phase or the Fight phase, just after an enemy unit has selected its targets.' }), ['fight', 'enemy']);
  assert.deepEqual(P.stratagemPhases({ turn: 'Either player’s turn', phase: 'Shooting or Fight phase', when: 'Your Shooting phase or the Fight phase.' }), ['shooting', 'fight', 'enemy']);
  assert.deepEqual(P.stratagemPhases({ turn: 'Your turn', phase: 'Movement or Charge phase', when: 'Your Movement phase or your Charge phase.' }), ['movement', 'charge']);
});

test('the sheet: one entry per rule with its units, core abilities by the rule, army rules first', () => {
  const lethal = { id: 'x', name: 'Hunters', text: 'This unit’s melee attacks have [Lethal Hits].', type: 'unit' };
  const s = P.phaseSheet({
    units: [
      { id: 'u1', name: 'Wolves (1)', flags: { deepStrike: true, scouts: 6 }, abilities: [{ ...lethal, owner: { id: 'u1:0', name: 'Wolves', unit: 'Wolves (1)' } }] },
      { id: 'u2', name: 'Wolves (2)', flags: { fnp: 5, deadlyDemise: 'D3', loneOperative: 12 }, abilities: [{ ...lethal, owner: { id: 'u2:0', name: 'Wolves', unit: 'Wolves (2)' } },
        { id: 'y', name: 'Relic', text: 'Once per battle, in your Shooting phase, this model’s ranged attacks have +1 D.', type: 'enhancement', owner: { id: 'u2:1', name: 'Lord', unit: 'Wolves (2)' } },
        { id: 'z', name: 'Odd one', text: 'Nothing about a phase here.', type: 'unit', owner: { id: 'u2:0', name: 'Wolves', unit: 'Wolves (2)' } }] },
    ],
    armyRules: [{ id: 'ar', name: 'Army Rule', text: 'At the start of your Command phase, do a thing.' }],
    detachmentRules: [{ id: 'dr', name: 'Det Rule', text: 'Mystery wording.' }],
    stratagems: [{ id: 's1', name: 'STRIKE', cp: 1, turn: 'Your turn', phase: 'Fight phase', when: 'Fight phase.', target: 'One unit.', effect: 'Hit harder.' }],
    mapped: (id, type) => (id === 'dr' && type === 'detachment-rule' ? ['charge'] : id === 'z' ? ['movement'] : null),
  });
  const names = (id) => s.phases.find(p => p.id === id).entries.map(e => e.name);
  assert.deepEqual(names('before'), ['Deep Strike', 'Scouts 6"']);
  assert.deepEqual(names('command'), ['Army Rule']);
  assert.deepEqual(names('movement'), ['Odd one', 'Deep Strike'], 'the phase mapping of the rules data is the fall-back');
  assert.deepEqual(names('charge'), ['Det Rule']);
  assert.deepEqual(names('fight'), ['Hunters', 'STRIKE']);
  assert.deepEqual(names('shooting'), ['Relic']);
  assert.deepEqual(names('enemy'), ['Deadly Demise D3', 'Feel No Pain 5+', 'Lone Operative']);
  const hunters = s.phases.find(p => p.id === 'fight').entries[0];
  assert.deepEqual(hunters.units.map(u => u.unit), ['Wolves (1)', 'Wolves (2)'], 'the same rule on two units is one entry');
  assert.equal(hunters.all, true, 'every unit has it');
  assert.equal(s.phases.find(p => p.id === 'movement').entries[0].by, 'data');
  assert.equal(s.phases.find(p => p.id === 'charge').entries[0].by, 'data');
  // once per battle: listed, one tick for the model that has it
  assert.deepEqual(s.once.map(e => e.name), ['Relic']);
  assert.deepEqual(P.ticksOf(s.once[0]), [{ id: 'ab:y|u2:1|0', label: 'Lord' }]);
  assert.equal(s.count, 12);
});

test('ticks: twice per battle, one per unit, and the same datasheet twice', () => {
  const e = { key: 'ab:k', usage: { per: 'battle', uses: 2 }, units: [{ id: 'a:0', name: 'Cherub', unit: 'Squad (1)' }, { id: 'b:0', name: 'Cherub', unit: 'Squad (2)' }], all: false };
  assert.deepEqual(P.ticksOf(e).map(t => t.label), ['Squad (1) 1', 'Squad (1) 2', 'Squad (2) 1', 'Squad (2) 2']);
  assert.equal(new Set(P.ticksOf(e).map(t => t.id)).size, 4);
  assert.deepEqual(P.ticksOf({ key: 'army:w', usage: { per: 'battle', uses: 1 }, units: [] }), [{ id: 'army:w|army|0', label: '' }]);
});

test('Space Wolves list: Combat Doctrines is the army rule, each doctrine once per battle, Assault Mastery adds one', () => {
  const army = A.importArmy(list('gw-space-wolves-2000.txt'));
  const input = A.phaseSheetInput(army);
  assert.deepEqual(input.armyRules.map(r => r.name), ['Combat Doctrines']);
  assert.deepEqual(P.optionsOf(input.armyRules[0].text), ['Assault doctrine', 'Devastator doctrine', 'Tactical doctrine']);
  const s = P.phaseSheet(input);
  const names = (id, kind) => s.phases.find(p => p.id === id).entries.filter(e => !kind || e.kind === kind).map(e => e.name);
  assert.deepEqual(s.once.map(e => e.name), ['Combat Doctrines']);
  assert.deepEqual(P.ticksOf(s.once[0]).map(t => t.label), ['Assault doctrine', 'Assault doctrine (Assault Mastery)', 'Devastator doctrine', 'Tactical doctrine']);
  assert.equal(names('command')[0], 'Combat Doctrines', 'the army rule comes first');
  assert.ok(names('command').includes('Strategic Acumen'));
  assert.deepEqual(names('before'), ['Old Greymanes', 'Teleport Homer', 'Deep Strike', 'Infiltrators', 'Scouts 6"']);
  for (const n of ['Thunderous Charge', 'Terminatus Assault', 'Full-throttle Assault', 'Into the Fray', 'Cunning Hunters', 'Hammer Blow', 'Legendary Slayers (Saga of the Beastslayer)']) assert.ok(names('fight').includes(n), n);
  assert.ok(names('movement').includes('Lightning-fast Strike (Stormlance Task Force)'));
  assert.ok(names('enemy', 'stratagem').includes('FIRE OVERWATCH') && names('enemy', 'stratagem').includes('COUNTEROFFENSIVE'));
  assert.ok(!names('shooting', 'stratagem').includes('ARMOUR OF CONTEMPT'), 'used when the ENEMY has selected its targets: not in your Shooting phase');
  assert.ok(names('fight', 'stratagem').includes('ARMOUR OF CONTEMPT') && names('enemy', 'stratagem').includes('ARMOUR OF CONTEMPT'));
  assert.deepEqual(names('always'), ['Curse of the Wulfen', 'Guile of the Wolf', 'Imperium\'s Sword (enhancement)', 'Storm Shield', 'COMMAND RE-ROLL']);
  // the army rule is not repeated for each of the 12 datasheets that carry it
  assert.equal(s.phases.flatMap(p => p.entries).filter(e => e.name === 'Combat Doctrines' && e.kind === 'army').every(e => e.units.length === 0), true);
  // every ability of every unit is somewhere on the sheet (Leader and Support are list choices)
  const all = new Set(s.phases.flatMap(p => p.entries.map(e => e.name)));
  for (const cu of army.units) for (const a of A.abilitiesOf(cu)) {
    if (a.type === 'core') continue;
    assert.ok(all.has(a.name), `${a.name} of ${cu.name} is missing from the sheet`);
  }
});

test('Orks list: Waaagh! is once per battle; defences are listed for the opponent’s turn', () => {
  const army = A.importArmy(list('gw-orks-1000.txt'));
  const s = P.phaseSheet(A.phaseSheetInput(army));
  const names = (id, kind) => s.phases.find(p => p.id === id).entries.filter(e => !kind || e.kind === kind).map(e => e.name);
  assert.deepEqual(s.once.map(e => e.name), ['Waaagh!']);
  assert.equal(P.ticksOf(s.once[0]).length, 1);
  assert.equal(names('command')[0], 'Waaagh!');
  assert.deepEqual(names('enemy').filter(n => !/^[A-Z' !-]+$/.test(n)), ['Arrogant Invulnerability', 'Mobile Fortress', 'Deadly Demise D6', 'Feel No Pain 6+']);
  assert.ok(names('shooting').includes('Firing Deck 11') && names('shooting').includes('Finderz Keeperz'));
  assert.ok(names('fight').includes('Tide of Muscle') && names('fight').includes('Might Is Right'));
});

test('the matchup brief: what the enemy list has that you must plan around', () => {
  const sw = A.armyTricks(A.importArmy(list('gw-space-wolves-2000.txt')));
  assert.deepEqual(sw.map(t => [t.id, t.units.join(', ')]), [
    ['deepStrike', 'Logan Grimnar + Ancient in Terminator Armour + Terminator Assault Squad'],
    ['infiltrators', 'Scout Squad ×2'],
    ['scouts', 'Scout Squad 6" ×2'],
  ]);
  assert.match(sw[0].note, /battle round 2.*more than 8".*deployment zone too \(24\.09\)/);
  const orks = A.armyTricks(A.importArmy(list('gw-orks-1000.txt')));
  assert.deepEqual(orks.map(t => t.id), ['torrent'], 'only what the list really has');
  assert.match(orks[0].units[0], /^Meganobz \(.* 6"\)$/, 'the unit, the Torrent weapon and its range');
  assert.match(orks[0].note, /hit automatically \(24\.37\).*only on a 6 in Fire Overwatch \(15\.09\)/);
});

test('a rule that lets a unit arrive a battle round early is found in the list (High King of Fenris)', () => {
  assert.deepEqual(A.earlyArrival(A.importArmy(list('gw-space-wolves-2000.txt'))), { name: 'High King of Fenris', owner: 'Logan Grimnar' });
  assert.equal(A.earlyArrival(A.importArmy(list('gw-orks-1000.txt'))), null);
});
