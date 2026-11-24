// Stratagems in play (public/calc/playtools.mjs): usable now, once per phase, CP spent and logged.
import { test } from 'node:test';
import assert from 'node:assert/strict';
const PT = await import(new URL('../public/calc/playtools.mjs', import.meta.url).href);

test('usable in a phase and turn as the rules data words them', () => {
  const s = (phase, turn) => ({ phase, turn });
  assert.equal(PT.stratUsable(s('Shooting phase', 'Your turn'), 'shooting', true), true);
  assert.equal(PT.stratUsable(s('Shooting phase', 'Your turn'), 'shooting', false), false);
  assert.equal(PT.stratUsable(s('Shooting phase', 'Opponent’s turn'), 'shooting', false), true);
  assert.equal(PT.stratUsable(s('Shooting or Fight phase', "Either player's turn"), 'fight', true), true);
  assert.equal(PT.stratUsable(s('Shooting or Fight phase', "Either player's turn"), 'charge', true), false);
  assert.equal(PT.stratUsable(s('Any phase', "Either player's turn"), 'movement', false), true);
  assert.equal(PT.stratUsable(s('Movement or Charge phase', 'Your turn'), 'charge', true), true);
});

test('Use: spends the CP, logs it, and the same stratagem only once per phase', () => {
  const g = PT.ensureGame({ round: 2, next: 'A', A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [], cp: 3 }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [], cp: 1 } });
  g.phase = 'shooting';
  const go = { name: 'Go to Ground', cp: 1 }, big = { name: 'Big One', cp: 2 };
  assert.deepEqual(PT.useStrat(g, 'B', go, 'A'), { ok: true });
  assert.equal(g.B.cp, 0);
  assert.deepEqual(g.strats, [{ round: 2, turn: 'A', phase: 'shooting', side: 'B', name: 'Go to Ground', cp: 1 }]);
  assert.match(PT.useStrat(g, 'A', big, 'A').ok ? '' : 'x', /^$/);
  assert.equal(g.A.cp, 1);
  g.A.cp = 5;
  assert.match(PT.useStrat(g, 'A', big, 'A').why, /already used in this phase/);
  g.phase = 'fight';
  assert.equal(PT.useStrat(g, 'A', big, 'A').ok, true, 'a new phase: it can be used again');
  assert.match(PT.useStrat(g, 'B', go, 'A').why, /B has 0CP/);
});

test('Turn done: the next turn starts in the Command phase', () => {
  const g = PT.ensureGame({ round: 1, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } }, { fresh: true });
  g.phase = 'fight';
  PT.endTurn(g, 'A');
  assert.equal(g.phase, 'command');
});
