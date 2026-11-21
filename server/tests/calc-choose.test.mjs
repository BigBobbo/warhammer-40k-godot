// The weapon choice (public/calc/choose.mjs): which weapons and profiles a unit attacks with by default.
// Rules: 04.01 (one melee weapon per model; one or more ranged weapons), 04.01.03 (one profile of a weapon;
// Hunter profiles), 24.07 (close-quarters weapons or the others), 24.11 (Extra Attacks), 10.05 / 10.06.
//
// Run: node --test server/tests/calc-choose.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const C = await import(new URL('../public/calc/choose.mjs', import.meta.url).href);
const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const E = await import(new URL('../public/calc/engine.mjs', import.meta.url).href);
const H = await import(new URL('./helpers/choice-audit.mjs', import.meta.url).href);
const list = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');

// ---- synthetic problems
const W = (o) => ({ melee: true, A: '2', skill: 3, S: 4, AP: 0, D: '1', kw: {}, ...o });
const row = (id, wkey, w, o = {}) => ({ id, wkey, extra: !!w.kw?.extraAttacks, cq: !!(w.kw?.cq || w.kw?.pistol), usable: true, max: 5, parts: [{ g: 'g', n: 5 }], w: { ...w, name: id }, ...o });
const horde = { name: 'horde', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 20, W: 1, Sv: 5, InSv: 0, T: 3 }], mods: {} };
const tank = { name: 'tank', keywords: ['VEHICLE'], groups: [{ name: 'g', count: 1, W: 13, Sv: 3, InSv: 0, T: 10 }], mods: {} };
const custodes = { name: 'custodes', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 4, W: 4, Sv: 2, InSv: 4, T: 6 }], mods: {} };
const problem = (phase, rows, defender, o = {}) => ({ phase, shooting: 'normal', groups: [{ id: 'g', count: 5, vm: false }], rows, attacker: { name: 'u', mods: {}, allVehicleMonster: false }, defender, ...o });
const total = (counts, ids) => ids.reduce((a, id) => a + (counts[id] ?? 0), 0);

test('fight: each model uses ONE melee weapon - the one that does most against this target (04.01)', () => {
  // sword: 8 attacks S4 D1 (good against a horde); fist: 3 attacks S8 AP-2 D2 (good against a tank)
  const rows = () => [row('sword', 'sword', W({ A: '8' })), row('fist', 'fist', W({ A: '3', S: 8, AP: -2, D: '2' }))];
  const h = C.chooseWeapons(problem('fight', rows(), horde));
  assert.deepEqual(h.counts, { sword: 5, fist: 0 }, 'against the horde: all five use the sword');
  const t = C.chooseWeapons(problem('fight', rows(), tank));
  assert.deepEqual(t.counts, { sword: 0, fist: 5 }, 'against the tank: all five use the fist');
  assert.ok(h.sims >= 2 && t.sims >= 2, 'a real trade-off is simulated');
  assert.ok(h.notes.get('sword').net > h.notes.get('fist').net && t.notes.get('fist').net > t.notes.get('sword').net, 'the notes carry the scores behind the choice');
});

test('fight: Extra Attacks weapons attack as well as the one other weapon, each with its best profile (24.11)', () => {
  const rows = [
    row('sword', 'sword', W({ A: '8' })), row('fist', 'fist', W({ A: '3', S: 8, AP: -2, D: '2' })),
    row('tail-sweep', 'tail', W({ A: '6', S: 3, kw: { extraAttacks: true } })), row('tail-stab', 'tail', W({ A: '1', S: 9, AP: -3, D: '3', kw: { extraAttacks: true } })),
  ];
  const t = C.chooseWeapons(problem('fight', rows, tank)).counts;
  assert.deepEqual(t, { sword: 0, fist: 5, 'tail-sweep': 0, 'tail-stab': 5 });
  const h = C.chooseWeapons(problem('fight', rows.map(r => ({ ...r })), horde)).counts;
  assert.deepEqual(h, { sword: 5, fist: 0, 'tail-sweep': 5, 'tail-stab': 0 });
});

test('a unit whose weapons are only known for the whole unit: the best weapons first, one per model', () => {
  // 10 models; the list only says "1 fist, 9 swords" (no model-by-model loadout)
  const rows = [row('sword', 'sword', W({ A: '3' }), { max: 9, parts: [{ g: 'g', n: 9 }] }), row('fist', 'fist', W({ A: '3', S: 8, AP: -2, D: '2' }), { max: 1, parts: [{ g: 'g', n: 1 }] })];
  const p = problem('fight', rows, tank, { groups: [{ id: 'g', count: 10, vm: false }] });
  assert.deepEqual(C.chooseWeapons(p).counts, { sword: 9, fist: 1 }, 'both attack: 10 models, 10 weapons');
  // 10 models that all carry both: only 10 weapons attack
  const both = [row('sword', 'sword', W({ A: '3' }), { max: 10, parts: [{ g: 'g', n: 10 }] }), row('fist', 'fist', W({ A: '3', S: 8, AP: -2, D: '2' }), { max: 10, parts: [{ g: 'g', n: 10 }] })];
  assert.deepEqual(C.chooseWeapons(problem('fight', both, tank, { groups: [{ id: 'g', count: 10, vm: false }] })).counts, { sword: 0, fist: 10 });
});

test('a profile that is at least as good in every way wins without a simulation', () => {
  const rows = [row('hammer', 'hammer', W({ A: '2', S: 8, AP: -2, D: '3', kw: { dev: true } })), row('hammer-big', 'hammer', W({ A: '3', S: 10, AP: -3, D: '3', kw: { dev: true } }))];
  const r = C.chooseWeapons(problem('fight', rows, tank));
  assert.deepEqual(r.counts, { hammer: 0, 'hammer-big': 5 });
  assert.equal(r.sims, 0);
  assert.equal(r.notes.get('hammer').settled, true);
  // dominance is conservative: an ability the other profile lacks, or a drawback, means "simulate"
  assert.equal(C.dominates(W({ A: '3', S: 10 }), W({ A: '2', S: 8 })), true);
  assert.equal(C.dominates(W({ A: '3', S: 10 }), W({ A: '2', S: 8, kw: { lethal: true } })), false, 'the weaker profile has Lethal Hits');
  assert.equal(C.dominates(W({ A: '3', S: 10, kw: { hazardous: true } }), W({ A: '2', S: 8 })), false, 'Hazardous is a cost');
  assert.equal(C.dominates(W({ A: 'D6' }), W({ A: '2' })), false, 'D6 attacks can be 1');
  assert.equal(C.dominates(W({ A: 'D6+1' }), W({ A: '2' })), true);
  assert.equal(C.dominates(W({ A: '4', skill: 4 }), W({ A: '4', skill: 3 })), false, 'worse WS');
  assert.equal(C.dominates(W({ kw: { anti: [{ keyword: 'VEHICLE', threshold: 4 }] } }), W({ kw: { anti: [{ keyword: 'VEHICLE', threshold: 3 }] } })), false);
});

test('equal options: the first one, and no simulation is wasted on them', () => {
  const rows = [row('a', 'w', W({ A: '4' })), row('b', 'w', W({ A: '4' }))];
  const r = C.chooseWeapons(problem('fight', rows, horde));
  assert.deepEqual(r.counts, { a: 5, b: 0 });
  assert.equal(r.sims, 0);
});

test('a profile that cannot target the unit is never used (Hunter, 04.01.03)', () => {
  const rows = [row('normal', 'hammer', W({ A: '2', S: 8 })), row('hunter', 'hammer', W({ A: '3', S: 10, AP: -3, D: '3' }), { usable: false })];
  const r = C.chooseWeapons(problem('fight', rows, horde));
  assert.deepEqual(r.counts, { normal: 5, hunter: 0 });
  assert.equal(C.decisions(problem('fight', rows, horde)).length, 0, 'nothing to choose: one usable profile');
  assert.equal(C.families(problem('fight', rows, horde)).get('hunter'), C.families(problem('fight', rows, horde)).get('normal'), 'still one family: their counts depend on each other');
});

test('shooting: every ranged weapon fires, each with its best profile (frag against a horde, krak against a tank)', () => {
  const rows = () => [
    row('rifle', 'rifle', W({ melee: false, A: '2' })),
    row('frag', 'ml', W({ melee: false, A: 'D6', S: 4, kw: { blast: 1 } }), { max: 1, parts: [{ g: 'g', n: 1 }] }),
    row('krak', 'ml', W({ melee: false, A: '1', S: 9, AP: -2, D: 'D6' }), { max: 1, parts: [{ g: 'g', n: 1 }] }),
  ];
  assert.deepEqual(C.chooseWeapons(problem('shooting', rows(), horde)).counts, { rifle: 5, frag: 1, krak: 0 });
  assert.deepEqual(C.chooseWeapons(problem('shooting', rows(), tank)).counts, { rifle: 5, frag: 0, krak: 1 });
});

test('shooting: close-quarters weapons or the other weapons, not both - unless the model is a MONSTER / VEHICLE (24.07)', () => {
  const rifle = () => row('rifle', 'rifle', W({ melee: false, A: '2', S: 4 }));
  const pistol = () => row('pistol', 'pistol', W({ melee: false, A: '1', S: 4, kw: { cq: true } }));
  const r = C.chooseWeapons(problem('shooting', [rifle(), pistol()], horde));
  assert.deepEqual(r.counts, { rifle: 5, pistol: 0 });
  assert.equal(r.sims, 0, 'the rifle is at least as good in every way');
  const vm = C.chooseWeapons(problem('shooting', [rifle(), pistol()], horde, { groups: [{ id: 'g', count: 5, vm: true }] }));
  assert.deepEqual(vm.counts, { rifle: 5, pistol: 5 }, 'a vehicle fires both');
  // a plasma pistol that beats a lasgun against heavy infantry: the pistol side is used
  const las = row('las', 'las', W({ melee: false, A: '1', S: 3 })), plasma = row('plasma', 'plasma', W({ melee: false, A: '1', S: 8, AP: -3, D: '2', kw: { cq: true } }));
  assert.deepEqual(C.chooseWeapons(problem('shooting', [las, plasma], custodes)).counts, { las: 0, plasma: 5 });
  // two groups in one unit: each group makes its own choice
  const p2 = problem('shooting', [
    { ...rifle(), max: 4, parts: [{ g: 'a', n: 4 }] }, { ...pistol(), max: 5, parts: [{ g: 'a', n: 4 }, { g: 'b', n: 1 }] },
    row('plasma', 'plasma', W({ melee: false, A: '1', S: 8, AP: -3, D: '2', kw: { cq: true } }), { max: 1, parts: [{ g: 'b', n: 1 }] }), row('las', 'las', W({ melee: false, A: '1', S: 3 }), { max: 1, parts: [{ g: 'b', n: 1 }] }),
  ], custodes, { groups: [{ id: 'a', count: 4, vm: false }, { id: 'b', count: 1, vm: false }] });
  assert.deepEqual(C.chooseWeapons(p2).counts, { rifle: 4, pistol: 1, plasma: 1, las: 0 }, 'the four use rifles; the sergeant uses both pistols instead of the lasgun');
});

test('Hazardous: used only when it does more damage than it is expected to cost (06.03: 1 mortal wound on 1-2)', () => {
  const std = () => row('standard', 'plasma', W({ melee: false, A: '3', S: 7, AP: -2, D: '3' }), { max: 1, parts: [{ g: 'g', n: 1 }] });
  const sup = () => row('supercharge', 'plasma', W({ melee: false, A: '3', S: 8, AP: -3, D: '4', kw: { hazardous: true } }), { max: 1, parts: [{ g: 'g', n: 1 }] });
  const big = C.chooseWeapons(problem('shooting', [std(), sup()], custodes));
  assert.deepEqual(big.counts, { standard: 0, supercharge: 1 }, 'against 4-wound models the extra damage is worth the risk');
  const n = big.notes.get('supercharge');
  assert.ok(Math.abs(n.hazard - 1 / 3) < 0.06 && Math.abs(n.net - (n.wounds - n.hazard)) < 1e-9, `score = wounds removed - own expected wounds: ${JSON.stringify(n)}`);
  const small = C.chooseWeapons(problem('shooting', [std(), sup()], horde));
  assert.deepEqual(small.counts, { standard: 1, supercharge: 0 }, 'against 1-wound models it adds nothing: the safe profile');
});

test('a weapon with a ranged profile and a close-quarters profile: each side is taken with its own best profile', () => {
  // gauntlets: "Ranged" (not close-quarters) or "Close Quarters"; a bolt weapon that is close-quarters only
  const rows = () => [
    row('gauntlet-ranged', 'gauntlet', W({ melee: false, A: '3', S: 4 })),
    row('gauntlet-cq', 'gauntlet', W({ melee: false, A: '4', S: 5, AP: -1, kw: { cq: true } })),
    row('boltstorm', 'boltstorm', W({ melee: false, A: '6', S: 4, kw: { cq: true } })),
  ];
  // the close-quarters side is gauntlet-cq + boltstorm (10 attacks a model), the other side gauntlet-ranged alone (3)
  const r = C.chooseWeapons(problem('shooting', rows(), horde));
  assert.deepEqual(r.counts, { 'gauntlet-ranged': 0, 'gauntlet-cq': 5, boltstorm: 5 });
  // the same weapons on a vehicle: no "either / or", so every weapon fires with its best profile
  const vm = C.chooseWeapons(problem('shooting', rows(), horde, { groups: [{ id: 'g', count: 5, vm: true }] }));
  assert.deepEqual(vm.counts, { 'gauntlet-ranged': 0, 'gauntlet-cq': 5, boltstorm: 5 });
});

test('a Hazardous gun that costs more than it adds stays silent (a ranged weapon need not be fired, 04.02)', () => {
  // one shot, hits on 5+, S3 against a tank: next to nothing; the hazard roll costs a third of a wound
  const bad = () => row('unstable', 'unstable', W({ melee: false, A: '1', skill: 5, S: 3, kw: { hazardous: true } }), { max: 1, parts: [{ g: 'g', n: 1 }] });
  const rifle = () => row('rifle', 'rifle', W({ melee: false, A: '2' }));
  const r = C.chooseWeapons(problem('shooting', [rifle(), bad()], tank));
  assert.deepEqual(r.counts, { rifle: 5, unstable: 0 });
  assert.ok(r.notes.get('unstable').net < 0 && r.notes.get('unstable').hazard > 0.25, JSON.stringify(r.notes.get('unstable')));
  assert.ok(r.families.has('unstable'), 'the row is a choice: the page shows why it is not used');
  // a Hazardous gun that is worth it fires
  const good = row('melta', 'melta', W({ melee: false, A: '1', skill: 2, S: 12, AP: -4, D: '6', kw: { hazardous: true } }), { max: 1, parts: [{ g: 'g', n: 1 }] });
  assert.deepEqual(C.chooseWeapons(problem('shooting', [rifle(), good], tank)).counts, { rifle: 5, melta: 1 });
  // ... but not when the rest of the unit destroys the target anyway (checked with the whole attack)
  const lone = { name: 'gretchin', keywords: ['INFANTRY'], groups: [{ name: 'g', count: 1, W: 1, Sv: 7, InSv: 0, T: 2 }], mods: {} };
  const many = row('rifle', 'rifle', W({ melee: false, A: '6', skill: 2, S: 6 }));
  const r2 = C.chooseWeapons(problem('shooting', [many, { ...good }], lone));
  assert.deepEqual(r2.counts, { rifle: 5, melta: 0 }, '30 good shots at one Gretchin: the Hazardous shot adds nothing');
  assert.equal(r2.inContext, true);
  // in a fight a model must use a melee weapon: a Hazardous one is not switched off
  const fist = row('fist', 'fist', W({ A: '1', skill: 5, S: 3, kw: { hazardous: true } }));
  assert.deepEqual(C.chooseWeapons(problem('fight', [fist], tank)).counts, { fist: 5 });
});

test('the whole unit together: damage 2 shots are wasted on models another weapon has wounded', () => {
  // Wardens of Ultramar against 2-wound marines. On its own the bolt rifle does the same with either profile
  // (1 shot of damage 2, or 2 shots of damage 1); with the unit's other damage-1 weapon in the same volley,
  // the damage-1 profile wastes nothing.
  const u = H.RAW.units.find(x => x.id === 'wardens-of-ultramar');
  const p = H.problemOf(H.unitOf(u), 'shooting', H.PANEL.find(t => /^marines/.test(t.name)));
  const r = C.chooseWeapons(p, { context: 'always' });
  const used = p.rows.filter(x => r.counts[x.id] > 0).map(x => x.w.name);
  assert.ok(used.includes('Bolt Rifle – Saturation') && !used.includes('Bolt Rifle – Focused Fire'), used.join(', '));
  const own = p.rows.filter(x => /Bolt Rifle/.test(x.w.name)).map(x => r.notes.get(x.id).net);
  assert.ok(Math.abs(own[0] - own[1]) < 0.1 * Math.max(...own), `on their own the two profiles are level: ${own.map(v => v.toFixed(2))}`);
  assert.equal(r.inContext, true);
  // the grid mode ('auto') sees the close call and makes the same check
  assert.deepEqual(C.chooseWeapons(p, { context: 'auto' }).counts, r.counts);
  assert.equal(H.auditProblem(p).fails.length, 0);
});

test('counts set by hand: what is possible, and a count that goes up takes from the other profile', () => {
  const rows = [row('normal', 'hammer', W({})), row('hunter', 'hammer', W({ S: 10 })), row('claws', 'claws', W({ A: '5' }))];
  const p = problem('fight', rows, tank);
  assert.equal(C.feasible(p, { normal: 5, hunter: 0, claws: 0 }), true);
  assert.equal(C.feasible(p, { normal: 3, hunter: 2, claws: 0 }), true, 'a different profile for each model (04.01.03)');
  assert.equal(C.feasible(p, { normal: 5, hunter: 5, claws: 0 }), false, 'five hammers cannot attack ten times');
  assert.equal(C.feasible(p, { normal: 3, hunter: 0, claws: 3 }), false, 'five models, one melee weapon each');
  assert.equal(C.feasible(p, { normal: 3, hunter: 0, claws: 2 }), true);
  assert.deepEqual(C.adjustCount(p, { normal: 0, hunter: 5, claws: 0 }, 'normal', 1), { normal: 1, hunter: 4, claws: 0 });
  assert.deepEqual(C.adjustCount(p, { normal: 1, hunter: 4, claws: 0 }, 'hunter', -1), { normal: 1, hunter: 3, claws: 0 }, 'a count that goes down does not move weapons');
  assert.deepEqual(C.adjustCount(p, { normal: 5, hunter: 0, claws: 0 }, 'claws', 1), { normal: 4, hunter: 0, claws: 1 });
  // shooting: no "one weapon per model", but the two profiles of one weapon still share it
  const s = problem('shooting', [row('frag', 'ml', W({ melee: false })), row('krak', 'ml', W({ melee: false, S: 9 })), row('rifle', 'rifle', W({ melee: false }))], tank);
  assert.equal(C.feasible(s, { frag: 2, krak: 3, rifle: 5 }), true);
  assert.equal(C.feasible(s, { frag: 3, krak: 3, rifle: 5 }), false);
  assert.equal(C.overSidearms(problem('shooting', [row('rifle', 'rifle', W({ melee: false })), row('pistol', 'pistol', W({ melee: false, kw: { cq: true } }))], horde), { rifle: 5, pistol: 1 }), true);
  assert.equal(C.overSidearms(problem('shooting', [row('rifle', 'rifle', W({ melee: false })), row('pistol', 'pistol', W({ melee: false, kw: { cq: true } }))], horde), { rifle: 4, pistol: 1 }), false);
});

test('the worker resolves a default matchup: the same choice, as a plain engine scenario', () => {
  const rows = [row('sword', 'sword', W({ A: '8' })), row('fist', 'fist', W({ A: '3', S: 8, AP: -2, D: '2' }))];
  const p = problem('fight', rows, tank);
  const sc = { phase: 'fight', defender: tank, seed: 1, attackers: [{ name: 'u', mods: {}, allVehicleMonster: false, weapons: [], choice: { groups: p.groups, rows: p.rows, shooting: 'normal' } }] };
  const out = C.resolveScenario(sc);
  assert.equal(out.attackers[0].choice, undefined);
  assert.deepEqual(out.attackers[0].weapons.map(w => [w.name, w.count]), [['fist', 5]]);
  assert.ok(E.simulate({ ...out, trials: 500 }).meanWounds > 0);
  const plain = { phase: 'fight', defender: tank, attackers: [{ name: 'u', mods: {}, weapons: [] }] };
  assert.equal(C.resolveScenario(plain), plain, 'a scenario without a choice is returned as it is');
});

// ---- the real lists

const SW = A.importArmy(list('gw-space-wolves-2000.txt'));
const ORKS = A.importArmy(list('gw-orks-1000.txt'));
const unit = (army, re) => army.units.find(u => re.test(u.name));
const target = (army, re) => { const cu = unit(army, re); const profile = A.defenderProfile(cu, army); return { cu, profile, summary: A.defenderSummary(profile) }; };
/** The choice as the page builds it: the unit's own rules (the ones that are on), the target's rules. */
function realProblem(army, cu, phase, t, opts = {}) {
  const rows = A.attackerRows(cu, phase, t.summary, opts);
  const { rules } = A.attackerRules(cu, army);
  const ctx = { charged: false, stationary: false, halfRange: false, targetKeywords: t.profile.keywords ?? [], attackerKeywords: cu.keywords };
  const on = new Set(rules.filter(r => r.phases.includes(phase) && A.attackerRuleOn(r, undefined, ctx)).map(r => r.id));
  const defender = A.buildDefender(t.profile, new Set(t.profile.rules.filter(r => r.auto).map(r => r.id)), phase, {}, {});
  return { rows, problem: A.choiceProblem(cu, rows, {}, rules, on, phase, defender, t.summary) };
}
const pick = (rows, counts) => Object.fromEntries(rows.filter(r => counts[r.id] > 0).map(r => [r.label, counts[r.id]]));

test('Wulfen: the thunder hammers always attack - the Hunter profile only against a Monster or a Vehicle', () => {
  const wulfen = unit(SW, /Wulfen/);
  const boyz = target(ORKS, /Boyz/), wagon = target(ORKS, /Battlewagon/);
  const a = realProblem(SW, wulfen, 'fight', boyz);
  const hunter = a.rows.find(r => /Hunter/.test(r.label));
  assert.deepEqual(hunter.hunters, ['MONSTER', 'VEHICLE'], 'both Hunter keywords are kept');
  assert.equal(hunter.blocked, 'Hunter profile: only targets Monster or Vehicle units');
  assert.deepEqual(pick(a.rows, C.chooseWeapons(a.problem).counts), { 'Captain on Bike: Thunder Hammer': 1, 'Thunder Hammer – Melee': 10 }, 'ten hammer attacks against Boyz (before: none)');
  // the first guess (no engine, e.g. a list view) is right too
  assert.deepEqual(pick(a.rows, Object.fromEntries(a.rows.map(r => [r.id, r.count]))), { 'Captain on Bike: Thunder Hammer': 1, 'Thunder Hammer – Melee': 10 });
  const b = realProblem(SW, wulfen, 'fight', wagon);
  const rb = C.chooseWeapons(b.problem);
  assert.deepEqual(pick(b.rows, rb.counts), { 'Captain on Bike: Thunder Hammer': 1, 'Thunder Hammer – Hunter': 10 });
  assert.equal(rb.sims, 0, 'the Hunter profile is better in every way: no simulation needed');
  // a MONSTER (the second Hunter keyword): usable as well (before, only VEHICLE was kept)
  const monster = { T: 11, Sv: 2, InSv: 5, W: 18, models: 1, keywords: ['MONSTER'] };
  const m = A.attackerRows(wulfen, 'fight', monster);
  assert.equal(m.find(r => /Hunter/.test(r.label)).blocked, null);
  assert.equal(m.find(r => /Hunter/.test(r.label)).count, 10);
  // no target known (a list view): the Hunter profile is not assumed
  const none = A.attackerRows(wulfen, 'fight', null);
  assert.deepEqual([none.find(r => /Hunter/.test(r.label)).count, none.find(r => /– Melee/.test(r.label)).count], [0, 10]);
});

test('Logan Grimnar: Sweep against a horde, Strike against a vehicle; the squad around him is not touched', () => {
  const logan = unit(SW, /Logan/);
  const a = realProblem(SW, logan, 'fight', target(ORKS, /Boyz/));
  const ra = C.chooseWeapons(a.problem);
  assert.deepEqual(pick(a.rows, ra.counts), {
    'Logan Grimnar: Axe Morkai – Sweep': 1, 'Logan Grimnar: Tyrnak and Fenrir': 1,
    'Ancient in Terminator Armour: Master-crafted Power Weapon': 1, 'Thunder Hammer': 9, 'Twin Lightning Claws': 1,
  });
  const sweep = a.rows.find(r => /Sweep/.test(r.label)), strike = a.rows.find(r => /Strike/.test(r.label));
  assert.ok(ra.notes.get(sweep.id).net > 1.5 * ra.notes.get(strike.id).net, 'Sweep removes far more Boyz than Strike');
  const b = realProblem(SW, logan, 'fight', target(ORKS, /Battlewagon/));
  assert.equal(pick(b.rows, C.chooseWeapons(b.problem).counts)['Logan Grimnar: Axe Morkai – Strike'], 1);
});

test('Scouts: the missile launcher fires krak at a vehicle and frag at a horde; pistols stay holstered', () => {
  const scouts = unit(SW, /Scout Squad/);
  const a = realProblem(SW, scouts, 'shooting', target(ORKS, /Battlewagon/));
  const ca = pick(a.rows, C.chooseWeapons(a.problem).counts);
  assert.deepEqual([ca['Missile Launcher – Krak'], ca['Missile Launcher – Frag'], ca['Bolt Pistol']], [1, undefined, undefined]);
  const b = realProblem(SW, scouts, 'shooting', target(ORKS, /Boyz/));
  const cb = pick(b.rows, C.chooseWeapons(b.problem).counts);
  assert.deepEqual([cb['Missile Launcher – Frag'], cb['Missile Launcher – Krak'], cb.Shotgun], [1, undefined, 3]);
});

test('shooting type: after an advance only Assault weapons; engaged only Close-quarters weapons (vehicles excepted)', () => {
  const gh = unit(SW, /Grey Hunters/), boyz = target(ORKS, /Boyz/);
  const adv = A.attackerRows(gh, 'shooting', boyz.summary, { shooting: 'assault' });
  assert.deepEqual(adv.filter(r => !r.blocked).map(r => r.label), ['Bolt Carbine']);
  assert.equal(adv.find(r => r.label === 'Bolt Pistol').blocked, 'After an advance only Assault weapons shoot');
  const eng = A.attackerRows(gh, 'shooting', boyz.summary, { shooting: 'cq' });
  assert.deepEqual(eng.filter(r => !r.blocked).map(r => r.label).sort(), ['Bolt Pistol', 'Plasma Pistol – Standard', 'Plasma Pistol – Supercharge']);
  assert.equal(eng.find(r => r.label === 'Bolt Pistol').count, 9, 'engaged: the pistols fire');
  const wagon = unit(ORKS, /Battlewagon/);
  assert.ok(A.attackerRows(wagon, 'shooting', boyz.summary, { shooting: 'cq' }).every(r => !r.blocked), 'a vehicle shoots all its weapons while engaged (10.06)');
});

test('every unit of the Space Wolves list against every Ork unit, both phases, with their rules: no single change is better', () => {
  let cases = 0, withChoice = 0;
  const fails = [];
  for (const cu of SW.units) for (const d of ORKS.units) for (const phase of ['shooting', 'fight']) {
    const t = target(ORKS, new RegExp(`^${d.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`));
    const { problem: p } = realProblem(SW, cu, phase, t);
    if (!p.rows.length) continue;
    cases++;
    const r = H.auditProblem(p, { trials: 4000 });
    if (r.decisions) withChoice++;
    for (const f of r.fails) fails.push(`${cu.name} ${phase} vs ${d.name}: ${f.label} - picked ${f.picked}, alternative ${f.alternative}`);
  }
  assert.ok(cases >= 60 && withChoice >= 20, `${cases} cases, ${withChoice} with a choice`);
  assert.deepEqual(fails, []);
});

test('a sample of the whole rules data (every 40th datasheet, and every datasheet with a Hunter profile): no single change is better', () => {
  const hunterWeapons = new Set(H.RAW.weapons.filter(w => (w.profiles ?? []).some(p => (p.keywords ?? []).some(k => k.keyword_id === 'hunter'))).map(w => w.id));
  const sample = H.RAW.units.filter((u, i) => i % 40 === 0 || (u.weapon_ids ?? []).some(id => hunterWeapons.has(id)));
  let withChoice = 0, hunterUnits = 0;
  const fails = [];
  for (const u of sample) {
    const cu = H.unitOf(u);
    if (!cu) continue;
    if ((u.weapon_ids ?? []).some(id => hunterWeapons.has(id))) hunterUnits++;
    for (const phase of ['shooting', 'fight']) for (const t of H.PANEL) {
      const p = H.problemOf(cu, phase, t);
      if (!p) continue;
      const r = H.auditProblem(p, { trials: 3000 });
      if (r.decisions) withChoice++;
      for (const f of r.fails) fails.push(`${u.id} ${phase} vs ${t.name}: ${f.label} - picked ${f.picked}, alternative ${f.alternative}`);
    }
  }
  assert.ok(hunterUnits >= 5 && withChoice >= 100, `${sample.length} datasheets, ${hunterUnits} with a Hunter profile, ${withChoice} cases with a choice`);
  assert.deepEqual(fails, []);
});
