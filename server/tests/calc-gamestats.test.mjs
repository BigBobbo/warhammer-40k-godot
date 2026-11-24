// Personal statistics from saved games (public/calc/gamestats.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
const S = await import(new URL('../public/calc/gamestats.mjs', import.meta.url).href);

const game = (me, first, a, b, oppFaction, variant, over = true) => ({
  name: 'g', saved: '2026-11-24', armies: { A: me === 'A' ? 'Space Wolves' : oppFaction, B: me === 'A' ? oppFaction : 'Space Wolves' },
  board: { settings: { variant } },
  mission: { me, first, battleReady: { A: true, B: true }, game: { over, A: { primary: a[0], secondary: a[1] }, B: { primary: b[0], secondary: b[1] } } },
});

test('only finished games count; the score with Battle Ready; my side is "me"', () => {
  const rows = S.gameRows([game('A', 'A', [40, 30], [30, 20], 'Orks', 1), game('B', 'A', [45, 30], [40, 35], 'Necrons', 2), game('A', 'B', [10, 0], [0, 0], 'Orks', 3, false)]);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(r => [r.myFaction, r.oppFaction, r.my, r.opp, r.result, r.first, r.layout]), [
    ['Space Wolves', 'Orks', 80, 60, 'W', 'first', 'A'],
    ['Space Wolves', 'Necrons', 85, 85, 'D', 'second', 'B'],
  ]);
});

test('tallies overall and by opponent faction / going first', () => {
  const rows = S.gameRows([game('A', 'A', [40, 30], [30, 20], 'Orks', 1), game('A', 'B', [20, 20], [45, 40], 'Orks', 2), game('A', 'A', [30, 30], [30, 30], 'Necrons', 1)]);
  const t = S.tally(rows);
  assert.deepEqual([t.n, t.w, t.l, t.d], [3, 1, 1, 1]);
  assert.equal(t.winRate, 0.5);
  const byOpp = S.statsBy(rows, 'oppFaction');
  assert.deepEqual(byOpp.map(r => [r.key, r.n, r.w, r.l]), [['Orks', 2, 1, 1], ['Necrons', 1, 0, 0]]);
  assert.deepEqual(S.statsBy(rows, 'first').map(r => [r.key, r.n]), [['first', 2], ['second', 1]]);
});
