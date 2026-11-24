// Deployment drop order (public/calc/droporder.mjs): alternate one unit at a time from the Defender, TITANIC skips.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const D = await import(new URL('../public/calc/droporder.mjs', import.meta.url).href);

test('the Defender sets up first; then they alternate', () => {
  assert.equal(D.dropState('B', { A: 3, B: 3 }, []).next, 'B');
  assert.equal(D.dropState('B', { A: 3, B: 3 }, [{ X: 'B', tk: 'b1' }]).next, 'A');
  assert.equal(D.dropState('B', { A: 3, B: 3 }, [{ X: 'B', tk: 'b1' }, { X: 'A', tk: 'a1' }]).next, 'B');
});

test('fewer units: that player finishes first and the other sets up the rest after seeing them all', () => {
  const s = D.dropState('A', { A: 3, B: 6 }, []);
  assert.equal(s.finishesFirst, 'A');
  assert.deepEqual(s.lastRun, { side: 'B', n: 4 }, 'A B A B A B, then B B B B');
  const s2 = D.dropState('A', { A: 3, B: 6 }, [{ X: 'A' }, { X: 'B' }, { X: 'A' }, { X: 'B' }, { X: 'A' }]);
  assert.equal(s2.next, 'B');
  assert.deepEqual(s2.left, { A: 0, B: 4 });
});

test('a TITANIC unit: its player skips their next turn to set up a unit', () => {
  const titanic = (tk) => tk === 'stompa';
  const s = D.dropState('A', { A: 3, B: 3 }, [{ X: 'A', tk: 'stompa' }, { X: 'B', tk: 'b1' }], titanic);
  assert.equal(s.next, 'B', 'A skips: B sets up again');
  const s2 = D.dropState('A', { A: 3, B: 3 }, [{ X: 'A', tk: 'stompa' }, { X: 'B', tk: 'b1' }, { X: 'B', tk: 'b2' }], titanic);
  assert.equal(s2.next, 'A');
});

test('everything set up: no next drop', () => {
  assert.equal(D.dropState('A', { A: 1, B: 1 }, [{ X: 'A' }, { X: 'B' }]).next, null);
});
