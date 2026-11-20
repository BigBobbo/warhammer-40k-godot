// Combat Calc event set-up: splitting pasted lists, and what a round looks
// like for a pair of Force Dispositions (11th edition).
// Run: node --test server/tests/calc-event.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const L = await import(new URL('../public/calc/lists.mjs', import.meta.url).href);
const B = await import(new URL('../public/calc/board.mjs', import.meta.url).href);
const fx = (n) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8');
const SW = fx('gw-space-wolves-2000.txt'), ORKS = fx('gw-orks-1000.txt'), CUSTODES = fx('gw-custodes-nbhyphen.txt');

test('one list stays one list (unit lines with points are not list starts)', () => {
  for (const t of [SW, ORKS, CUSTODES]) assert.equal(L.splitLists(t).length, 1);
  assert.deepEqual(L.splitLists('   \n '), []);
});

test('several GW app lists pasted one after another are split at each list header', () => {
  const parts = L.splitLists(`${SW}\n\n${ORKS}\n${CUSTODES}`);
  assert.equal(parts.length, 3);
  assert.match(parts[0], /^Gaelcon Awoo \(2000 points\)/);
  assert.match(parts[1], /^Calc Test Waaagh \(1000 points\)/);
  assert.match(parts[2], /^Custodes test \(1000 points\)/);
  // each part is the whole list: the last unit of one list does not leak into the next
  assert.ok(parts[0].includes('Thunderwolf Cavalry') && !parts[0].includes('Waaagh'));
  assert.ok(parts[1].includes('Battlewagon') && !parts[1].includes('Custodes'));
  assert.equal(parts.join('\n').replace(/\s+/g, ''), `${SW}${ORKS}${CUSTODES}`.replace(/\s+/g, ''), 'nothing is lost');
});

test('a line of dashes separates lists of any format', () => {
  const parts = L.splitLists(`My Necrons\n- Warriors x20\n- Overlord\n-----\nOther list\n+ Troops +\nBoyz\n=====\n${ORKS}`);
  assert.equal(parts.length, 3);
  assert.match(parts[0], /^My Necrons/);
  assert.match(parts[2], /^Calc Test Waaagh/);
});

test('a round is fixed by the two dispositions: both primaries and three layouts (A, B, C)', () => {
  const ids = B.DISPOSITIONS.map(d => d.id);
  assert.equal(ids.length, 5);
  for (const mine of ids) for (const opp of ids) {
    const m = B.matchupFor(mine, opp);
    assert.ok(m.mine && m.theirs, `${mine} vs ${opp}: primaries`);
    assert.ok(m.layouts.every(Boolean) && m.layouts.map(l => l.variant).join() === '1,2,3', `${mine} vs ${opp}: layouts`);
    // the same table for both players: my primary against them is their "theirs" against me
    const back = B.matchupFor(opp, mine);
    assert.equal(back.theirs, m.mine);
    assert.deepEqual(back.layouts.map(l => l.id), m.layouts.map(l => l.id));
  }
  const th = B.matchupFor('take-and-hold', 'reconnaissance');
  assert.deepEqual(th.layouts.map(l => l.deployment), ['tipping_point', 'dawn_of_war', 'search_and_destroy'], 'as revised on 30 September 2026');
  assert.deepEqual([1, 2, 3].map(B.layoutLetter), ['A', 'B', 'C']);
});
