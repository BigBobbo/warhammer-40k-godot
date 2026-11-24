// Transports: who can embark and how many spaces they take (adapter.mjs transportOf / passengerCheck), and a unit that
// disembarks is not a reserve arrival (planeval.mjs planWarnings).
import { test } from 'node:test';
import assert from 'node:assert/strict';

const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const P = await import(new URL('../public/calc/planeval.mjs', import.meta.url).href);
const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const U = (name, faction) => S.dc.RAW_DATA.units.find(u => u.name === name && (!faction || u.faction_id === faction));
const cu = (name, models = 1, faction) => ({ members: [{ dcUnit: U(name, faction), ru: { model_count: models } }] });

test('a Battlewagon carries 22 Orks Infantry; Mega Armour takes 2 spaces; no Vehicles', () => {
  const t = A.transportOf(cu('Battlewagon'));
  assert.equal(t.capacity, 22);
  assert.equal(t.phrase, 'Orks Infantry');
  assert.deepEqual(A.passengerCheck(t, cu('Boyz', 20)), { ok: true, spaces: 20, why: null });
  assert.deepEqual(A.passengerCheck(t, cu('Meganobz', 3)), { ok: true, spaces: 6, why: null });
  assert.equal(A.passengerCheck(t, cu('Trukk')).ok, false);
  assert.equal(A.transportOf(cu('Boyz', 10)), null);
});

test('a Rhino cannot carry Terminators; a Land Raider can, at 2 spaces each', () => {
  const rhino = A.transportOf(cu('Rhino', 1, 'adeptus-astartes'));
  assert.deepEqual([rhino.capacity, rhino.exclude.includes('Terminator')], [12, true]);
  const term = cu('Terminator Squad', 5, 'adeptus-astartes');
  assert.match(A.passengerCheck(rhino, term).why, /cannot transport Terminator/);
  const lr = A.transportOf(cu('Land Raider', 1, 'adeptus-astartes'));
  assert.deepEqual(A.passengerCheck(lr, term), { ok: true, spaces: 10, why: null });
  assert.deepEqual(A.passengerCheck(lr, cu('Intercessor Squad', 5, 'adeptus-astartes')), { ok: true, spaces: 5, why: null });
});

test('a transport whose data names no passengers (Custodes Venerable Land Raider, 6): Infantry of its army', () => {
  const vlr = A.transportOf(cu('Venerable Land Raider', 1, 'adeptus-custodes'));
  assert.deepEqual([vlr.capacity, vlr.phrase], [6, null]);
  assert.equal(A.passengerCheck(vlr, cu('Custodian Guard', 5, 'adeptus-custodes')).ok, true);
  assert.equal(A.passengerCheck(vlr, cu('Boyz', 10)).ok, false);
});

test('a unit that disembarks is not checked as a reserve arrival', () => {
  const unit = (key, x, y) => ({ key, name: key, x, y, move: 6, models: [{ dx: 0, dy: 0, fp: { shape: 'round', r: 0.5 } }], flags: {} });
  const steps = [
    { name: 'Deploy', A: [unit('A:wagon', 20, 50)], B: [unit('B:x', 30, 10)], embarked: { A: [{ key: 'A:boyz', name: 'Boyz', in: 'A:wagon', transport: 'Battlewagon' }], B: [] } },
    { name: 'Turn 1', A: [unit('A:wagon', 20, 40), unit('A:boyz', 20, 36)], B: [unit('B:x', 30, 10)], embarked: { A: [], B: [] } },
  ];
  const ws = P.planWarnings(steps, { zones: {}, territories: {}, pieces: [], objectives: [] }).filter(w => w.unit === 'A:boyz');
  assert.deepEqual(ws.map(w => [w.msg, !!w.info]), [['disembarks from Battlewagon (set up wholly within 3" of it)', true]]);
});
