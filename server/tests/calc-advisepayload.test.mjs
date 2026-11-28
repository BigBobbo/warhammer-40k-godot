// Combat Calc "Ask for a plan": the request the Board builds (public/calc/advise.mjs).
// Run: node --test server/tests/calc-advisepayload.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);

const P = await import(new URL('../public/calc/advise.mjs', import.meta.url).href);
const N = await import(new URL('../public/calc/nextturn.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);

const dep = B.DEPLOYMENTS.hammer_anvil;
const OBJS = [{ id: 'hA', cls: 'home', side: 'A', label: 'Your home', x: 22, y: 6, host: [] }, { id: 'c', cls: 'central', side: null, label: 'Centre', x: 22, y: 30, host: [] }, { id: 'hB', cls: 'home', side: 'B', label: 'Their home', x: 22, y: 54, host: [] }];
const GEO = { zones: { A: dep.zones.find(z => z.player === 1).poly, B: dep.zones.find(z => z.player === 2).poly }, territories: { A: dep.territories.find(t => t.player === 1).poly, B: dep.territories.find(t => t.player === 2).poly }, pieces: [], objectives: OBJS };
const INF = B.footprint({ shape: 'round', diameter: 32 });
const unit = (key, x, y, n = 5, o = {}) => ({ key, name: key.slice(2), x, y, models: B.formation([{ count: n, fp: INF, oc: 2 }]), move: 6, ranges: [24], melee: true, oc: 2 * n, points: 100, left: n, total: n, ...o });
const mine = [unit('A:Hunters', 22, 22, 5), unit('A:Guard', 22, 6, 5)], theirs = [unit('B:Boyz', 22, 37, 10)];
const cell = { shoot: 0.3, fight: 0.6, sMu: 4, sSd: 2, fMu: 8, fSd: 2, W: 10 };
const pair = { 'A:Hunters': { 'B:Boyz': { ...cell, W: 10 } }, 'A:Guard': { 'B:Boyz': cell }, 'B:Boyz': { 'A:Hunters': { ...cell, W: 10 }, 'A:Guard': cell } };
const base = { me: 'A', mine, theirs, pair, geo: GEO, objs: OBJS, round: 2 };
const res = N.nextTurn({ ...base, hand: ['secure-no-mans-land'] });
const my = N.myTurn({ ...base, hand: ['no-prisoners'], risk: Object.fromEntries(res.threats.map(t => [t.key, t.likely])) });
const army = (faction, names, strats) => ({ faction, units: names.map(n => ({ name: n, points: 100, models: 5, keywords: ['INFANTRY'], abilities: [{ name: 'Oath', text: 'Re-roll  hit\nrolls of 1.' }] })), stratagems: strats });
const IN = {
  armies: { me: army('Space Wolves', ['Hunters', 'Guard'], [{ name: 'ARMOUR OF CONTEMPT', cp: 1, phase: 'Shooting or Fight phase', turn: "Either player's turn", when: 'w', target: 't', effect: 'e' }, { name: 'ARMOUR OF CONTEMPT', cp: 1, turn: 'x' }]),
    them: army('Orks', ['Boyz'], [{ name: 'ERE WE GO', cp: 1, turn: 'Your turn', effect: 'x' }, { name: 'ORKS IS NEVER BEATEN', cp: 2, turn: "Either player's turn", effect: 'y' }]) },
  game: { round: 2, mine: true, phase: 'movement', myMission: 'Immovable Object', theirMission: 'Unstoppable Force', myCP: 3, theirCP: 2, myVP: 4, theirVP: 6 },
  hands: { me: [{ name: 'No Prisoners', text: '2 VP per enemy unit destroyed this turn (max 5).' }], them: [{ name: 'Secure No Man’s Land', text: '5 VP ...' }] },
  unitsNow: { me: [{ name: 'Hunters', modelsLeft: 5, at: [22.4, 21.6] }, { name: 'Guard', modelsLeft: 0, at: null, status: 'destroyed' }], them: [{ name: 'Boyz', modelsLeft: 10, at: [22, 37] }] },
  res, my, moves: { base: { win: 0.47, vp: 1 }, best: [{ name: 'Hunters', dist: 4.249, kind: 'obj', label: 'Centre', dVp: 8.713 }], kept: { moves: [{ name: 'Hunters', kind: 'obj', label: 'Centre' }], win: 0.61 } },
};

test('two parts: the armies (the same all game) and the game now', () => {
  const p = P.advisePayload(IN);
  assert.deepEqual(Object.keys(p), ['static', 'dynamic']);
  assert.equal(p.static.me.faction, 'Space Wolves');
  assert.equal(p.static.me.units[0].abilities[0], 'Oath: Re-roll hit rolls of 1.', 'ability text on one line');
  assert.equal(p.static.me.stratagems.length, 1, 'a stratagem listed twice is sent once');
  assert.deepEqual(p.static.them.stratagems.map(s => s.name), ['ORKS IS NEVER BEATEN'], 'of theirs, only what they can use in my turn');
  assert.ok(!JSON.stringify(p.static).includes('"at"') && !JSON.stringify(p.static).includes('modelsLeft'), 'nothing that changes during the game is in the cached part');
  const moved = P.advisePayload({ ...IN, unitsNow: { ...IN.unitsNow, me: [{ name: 'Hunters', modelsLeft: 3, at: [10, 10] }] }, game: { ...IN.game, round: 3 } });
  assert.equal(JSON.stringify(moved.static), JSON.stringify(p.static), 'a unit moving or losing models leaves the cached part byte for byte the same');
});

test('the game now: round, cards, where units are, and what the cards computed', () => {
  const d = P.advisePayload(IN).dynamic;
  assert.equal(d.game.turn, 'mine'); assert.equal(d.game.myCP, 3); assert.equal(d.game.phase, 'movement');
  assert.deepEqual(d.myUnits[0], { name: 'Hunters', modelsLeft: 5, at: [22, 22] });
  assert.deepEqual(d.myUnits[1], { name: 'Guard', modelsLeft: 0, status: 'destroyed' });
  const centre = d.computed.objectives.find(o => o.name === 'Centre');
  assert.ok(centre.inTheirTurn && centre.inMyTurn, 'each objective from both sides');
  assert.ok(centre.myUnitsThatCanReachIt.some(s => /^Hunters \(OC \d+, normal move\)$/.test(s)), JSON.stringify(centre));
  const hunters = d.computed.myUnitSuggestions.find(u => u.unit === 'Hunters');
  assert.match(hunters.target, /Boyz$/); assert.equal(typeof hunters.targetDestroyedPct, 'number'); assert.ok('chargeOddsPct' in hunters && 'canShootWithoutMoving' in hunters);
  assert.deepEqual(d.computed.forecast.movesWorthMaking, [{ unit: 'Hunters', move: '4.25" onto Centre', vpGainAlone: 8.71 }]);
  assert.equal(d.computed.forecast.winPctAsItStands, 47); assert.equal(d.computed.forecast.winPctWithThem, 61);
  assert.equal(P.advisePayload({ ...IN, moves: null }).dynamic.computed.forecast.note, 'the move forecast has not run');
});

test('the server takes it: it passes the server\'s own check and stays far under its size limits', () => {
  const A = require('../calc-advise.js');
  const p = P.advisePayload(IN), v = A.validate(p);
  assert.equal(v.ok, true);
  const size = P.payloadSize(p);
  assert.ok(size.static < 200000 && size.dynamic < 80000, JSON.stringify(size));
});

test('the prompt to paste into Claude by hand: the same instructions the server sends, then the armies, then the game', () => {
  const A = require('../calc-advise.js');
  assert.equal(P.ADVISE_INSTRUCTIONS, A.SYSTEM, 'one text for both routes');
  const p = P.advisePayload(IN), t = P.promptText(p);
  assert.ok(t.startsWith(A.SYSTEM));
  const a = t.indexOf('BOTH ARMIES (the same all game):'), g = t.indexOf('THE GAME NOW:');
  assert.ok(a > 0 && g > a);
  assert.deepEqual(JSON.parse(t.slice(a + 'BOTH ARMIES (the same all game):'.length, g)), JSON.parse(JSON.stringify(p.static)));
  assert.deepEqual(JSON.parse(t.slice(g + 'THE GAME NOW:'.length)), JSON.parse(JSON.stringify(p.dynamic)));
});

test('an answer pasted back: chat markdown taken out, paragraphs kept, a long paste cut', () => {
  assert.equal(P.tidyAnswer('## Plan\r\n**Hold** the centre.\n\n\n\n* one\n- two\n\n1. Unit: move'), 'Plan\nHold the centre.\n\n- one\n- two\n\n1. Unit: move');
  assert.equal(P.tidyAnswer('  \n '), '');
  assert.equal(P.tidyAnswer('x'.repeat(9000)).length, 6000);
});

test('the plan\'s ACTIONS lines: read out of the answer, whatever a chat adds around them', () => {
  const raw = 'Plan: take the centre.\n\n1. Hunters: move up.\n\n**ACTIONS**\n```\nMOVE | Hunters | Centre\n- ATTACK | hunters | Boyz\n3. hold | Guard | Your home objective |\n```\nMOVE | only two parts';
  const p = P.parsePlan(raw);
  assert.equal(p.text, 'Plan: take the centre.\n\n1. Hunters: move up.\n\nMOVE | only two parts', 'the plan keeps its own text; a line that is not an action stays');
  assert.deepEqual(p.actions, [{ kind: 'move', unit: 'Hunters', target: 'Centre' }, { kind: 'attack', unit: 'hunters', target: 'Boyz' }, { kind: 'hold', unit: 'Guard', target: 'Your home objective' }]);
  assert.deepEqual(P.parsePlan('Just a plan.').actions, []);
});

test('actions against the table: names matched to units and objectives, and said when they are not', () => {
  const table = { mine: [{ key: 'A:u1', name: 'Grey Hunters' }, { key: 'A:u2', name: 'Thunderwolf Cavalry (1)' }, { key: 'A:u3', name: 'Thunderwolf Cavalry (2)' }], theirs: [{ key: 'B:u1', name: 'Warboss + Boyz' }], objectives: [{ id: 'c', name: 'Centre' }, { id: 'h', name: 'Your home' }] };
  const r = P.resolveActions([{ kind: 'move', unit: 'grey hunters', target: 'Centre objective' }, { kind: 'attack', unit: 'Thunderwolf Cavalry (2)', target: 'Boyz' }, { kind: 'hold', unit: 'Thunderwolf Cavalry', target: 'Your home' }, { kind: 'attack', unit: 'Grey Hunters', target: 'Meganobz' }], table);
  assert.deepEqual([r[0].ok, r[0].unitKey, r[0].objId], [true, 'A:u1', 'c']);
  assert.deepEqual([r[1].ok, r[1].unitKey, r[1].targetKey], [true, 'A:u3', 'B:u1'], '"Boyz" is the only enemy unit with that in its name');
  assert.equal(r[2].ok, false, 'two units of mine start with "Thunderwolf Cavalry": not guessed'); assert.match(r[2].why, /no unit of yours/);
  assert.equal(r[3].ok, false); assert.match(r[3].why, /no enemy unit is called/);
});

test('the instructions ask for the ACTIONS lines; the server\'s stand-in answer has one', () => {
  const A = require('../calc-advise.js');
  assert.match(P.ADVISE_INSTRUCTIONS, /write the single word ACTIONS/); assert.match(P.ADVISE_INSTRUCTIONS, /MOVE \| unit \| objective/);
  assert.equal(P.ADVISE_INSTRUCTIONS, A.SYSTEM);
  assert.deepEqual(P.parsePlan(A.MOCK_TEXT).actions, [{ kind: 'hold', unit: 'Grey Hunters', target: 'Centre' }]);
});

test('the armies carry what a plan needs to read: rules, unit stats and weapons; stratagems are the ones for the turn asked about', () => {
  const rich = { ...IN, armies: { me: { ...IN.armies.me, rules: [{ name: 'Oath of Moment', text: 'Select one enemy unit ...' }], units: IN.armies.me.units.map(u => ({ ...u, stats: ['M6 T4 Sv3+ W2 Ld6 OC2'], weapons: ['5x Bolt rifle, 24", A2 BS3+ S4 AP-1 D1 [assault, heavy]'] })) }, them: IN.armies.them } };
  const p = P.advisePayload(rich);
  assert.deepEqual(p.static.me.rules, ['Oath of Moment: Select one enemy unit ...']);
  assert.deepEqual(p.static.me.units[0].stats, ['M6 T4 Sv3+ W2 Ld6 OC2']); assert.match(p.static.me.units[0].weapons[0], /Bolt rifle, 24"/);
  assert.ok(!('stats' in p.static.them.units[0]), 'nothing made up for a unit without them');
  // their turn: my stratagems for their turn, all of theirs
  const theirs = P.advisePayload({ ...IN, game: { ...IN.game, mine: false } });
  assert.deepEqual(theirs.static.them.stratagems.map(s => s.name), ['ERE WE GO', 'ORKS IS NEVER BEATEN']);
  assert.deepEqual(theirs.static.me.stratagems.map(s => s.name), ['ARMOUR OF CONTEMPT'], 'usable in either player\'s turn');
});

test('the game now also says: turn order, what each mission scores, where the objectives and terrain are, distances, and who is shocked', () => {
  const p = P.advisePayload({ ...IN, game: { ...IN.game, first: 'me', theirTurnsLeft: 0, myMissionText: '3 VP for holding a central objective.' }, terrain: [{ kind: 'dense area', at: [10, 20], size: [6, 4] }],
    gaps: { Hunters: [{ enemy: 'Boyz', inches: 12.4 }] }, flags: { Hunters: { battleShocked: true, halfStrength: true } } }).dynamic;
  assert.equal(p.game.firstTurnEachRound, 'me'); assert.equal(p.game.theirTurnsStillToComeAfterMine, 0); assert.match(p.game.note, /last turn of the battle/);
  assert.equal(p.game.myMissionScoring, '3 VP for holding a central objective.');
  assert.deepEqual(p.terrain, [{ kind: 'dense area', at: [10, 20], size: [6, 4] }]);
  assert.deepEqual(p.computed.inchesToNearestEnemies, { Hunters: [{ enemy: 'Boyz', inches: 12.4 }] });
  assert.deepEqual(p.myUnits[0], { name: 'Hunters', modelsLeft: 5, at: [22, 22], battleShocked: true, atOrBelowHalfStrength: true });
  const centre = p.computed.objectives.find(o => o.name === 'Centre');
  assert.deepEqual(centre.at, [22, 30]); assert.equal(centre.kind, 'centre');
  assert.ok(Array.isArray(p.computed.coreStratagemsTheyCanAnswerWithInMyTurn), 'what they can answer with (CP not known here: all named)');
  assert.ok(p.computed.targets.every(t => !('worthMoreBecause' in t) || t.worthMoreBecause.length > 0));
});

test('the ACTIONS lines can say how: Advance, Fall Back, arrive, shoot, charge, fight, and a stratagem on a unit', () => {
  const p = P.parsePlan('ACTIONS\nADVANCE | Hunters | Centre\nFALL BACK | Guard | Your home\nARRIVE | Wolf Guard | Centre\nSHOOT | Hunters | Boyz\nCHARGE | Hunters | Boyz\nFIGHT | Guard | Boyz\nSTRATAGEM | Armour of Contempt | Hunters');
  assert.deepEqual(p.actions, [{ kind: 'move', how: 'advance', unit: 'Hunters', target: 'Centre' }, { kind: 'move', how: 'fall back', unit: 'Guard', target: 'Your home' }, { kind: 'move', how: 'arrive', unit: 'Wolf Guard', target: 'Centre' },
    { kind: 'attack', how: 'shoot', unit: 'Hunters', target: 'Boyz' }, { kind: 'attack', how: 'charge', unit: 'Hunters', target: 'Boyz' }, { kind: 'attack', how: 'fight', unit: 'Guard', target: 'Boyz' }, { kind: 'stratagem', unit: 'Hunters', target: 'Armour of Contempt' }]);
  const r = P.resolveActions(p.actions, { mine: [{ key: 'A:u1', name: 'Hunters' }, { key: 'A:u2', name: 'Guard' }], theirs: [{ key: 'B:u1', name: 'Boyz' }], objectives: [{ id: 'c', name: 'Centre' }, { id: 'h', name: 'Your home' }] });
  assert.deepEqual([r[0].ok, r[0].how, r[0].objId], [true, 'advance', 'c']); assert.equal(r[2].ok, false, 'no unit of mine is called Wolf Guard here');
  assert.deepEqual([r[6].ok, r[6].unitKey, r[6].target], [true, 'A:u1', 'Armour of Contempt']);
  for (const f of ['ADVANCE | unit | objective', 'FALLBACK | unit | objective', 'ARRIVE | unit | objective', 'SHOOT | unit | enemy unit', 'CHARGE | unit | enemy unit', 'STRATAGEM | stratagem name | unit']) assert.ok(P.ADVISE_INSTRUCTIONS.includes(f), f);
  assert.match(P.ADVISE_INSTRUCTIONS, /Play to the score, not to kills/);
});
