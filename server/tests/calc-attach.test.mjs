// Suggested attachments for a list that does not say who leads which unit (public/calc/adapter.mjs suggestAttachments).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';

const A = await import(new URL('../public/calc/adapter.mjs', import.meta.url).href);
const list = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');
const named = (army, att) => Object.fromEntries(Object.entries(att).map(([c, b]) => [A.rosterUnitLabel(army, Number(c)), A.rosterUnitLabel(army, b)]));

test('the suggestion for a list with nothing attached matches what the GW app list says (Space Wolves, Orks)', () => {
  for (const f of ['gw-space-wolves-2000.txt', 'gw-orks-1000.txt']) {
    const army = A.importArmy(list(f));
    assert.ok(Object.keys(army.defaultAttachments).length > 0, f);
    assert.deepEqual(A.suggestAttachments({ ...army, attachments: {} }), army.defaultAttachments, f);
  }
});

test('a list that says nothing (New Recruit / WTC): every character goes to a unit on its Leader list, one Leader per unit', () => {
  const army = A.importArmy(list('nr-custodes-1995.txt'));
  assert.deepEqual(army.defaultAttachments, {});
  const sug = A.suggestAttachments(army);
  assert.deepEqual(named(army, sug), {
    'Trajann Valoris': 'Allarus Custodians (1)',
    'Shield-Captain (1)': 'Sentinel Guard Sodality (1)',
    'Shield-Captain (2)': 'Sentinel Guard Sodality (2)',
  });
  assert.equal(new Set(Object.values(sug)).size, 3, 'no two Leaders in one unit');
  // the combat units it makes: 9 datasheets -> 6 units
  A.setAttachments(army, sug);
  assert.equal(army.units.length, 6);
});

test('attachments already made are kept; only the others are suggested', () => {
  const army = A.importArmy(list('nr-custodes-1995.txt'));
  const tv = army.roster.units.findIndex(u => u.ref?.raw_name === 'Trajann Valoris');
  const smallAllarus = army.roster.units.findIndex(u => u.ref?.raw_name === 'Allarus Custodians' && u.model_count === 2);
  A.setAttachments(army, { [tv]: smallAllarus });
  const sug = A.suggestAttachments(army);
  assert.equal(sug[tv], smallAllarus);
  assert.equal(Object.keys(sug).length, 3);
});
