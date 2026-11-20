// Table tools of the Play view: pace clock, chess clock, command points,
// per-turn score log, undo (public/calc/playtools.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

const T = await import(new URL('../public/calc/playtools.mjs', import.meta.url).href);
const MIN = 60000;
const game = () => T.ensureGame({ round: 1, next: null, A: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] }, B: { hand: [], used: [], primary: 0, secondary: 0, destroyed: [] } }, { fresh: true });

test('milestones: the GW Grand Tournament ones for a 3-hour round, scaled for other lengths', () => {
  const m = T.milestones(180);
  assert.deepEqual(m.filter(x => x.round).map(x => [x.round, T.fmtHm(x.left)]), [[1, '1:55'], [2, '1:15'], [3, '0:45'], [4, '0:25'], [5, '0:00']]);
  assert.equal(T.fmtHm(m[1].left), '2:35', 'deployment done with 2:35 left');
  // a 2.5-hour round: the same share of the time
  assert.deepEqual(T.milestones(150).filter(x => x.round).map(x => x.left), [96, 63, 38, 21, 0]);
});

test('pace: on pace before the milestone, behind after it', () => {
  // battle round 2 of a 3-hour round should be done with 1:15 left
  const ok = T.paceStatus(180, 100 * MIN, 2);
  assert.equal(ok.target, 75);
  assert.equal(ok.behind, 0);
  assert.equal(Math.round(ok.dueIn), 25, '25 minutes until the milestone');
  const late = T.paceStatus(180, 60 * MIN, 2);
  assert.equal(late.behind, 15, 'still in round 2 with 1:00 left: 15 minutes behind');
  assert.equal(T.paceStatus(180, 4 * MIN, 4).noNewRound, true, 'under 5 minutes: no new battle round without a judge');
  assert.equal(T.paceStatus(180, 4 * MIN, 5).noNewRound, false, 'the last round is already under way');
});

test('clock text', () => {
  assert.equal(T.fmtClock(3 * 3600000), '3:00:00');
  assert.equal(T.fmtClock(85 * MIN), '1:25:00');
  assert.equal(T.fmtClock(59999), '1:00', 'rounds up to the second shown');
  assert.equal(T.fmtClock(7000), '0:07');
  assert.equal(T.fmtClock(-5000), '0:00', 'never negative');
});

test('round timer: start, pause, resume, set by hand, reset — from timestamps, so it survives a reload', () => {
  const c = T.newClock();
  let now = 1_000_000;
  assert.equal(T.roundLeft(c, now), 180 * MIN);
  assert.equal(T.roundStarted(c), false);
  T.roundStart(c, now);
  now += 30 * MIN;
  assert.equal(T.roundLeft(c, now), 150 * MIN);
  // what is stored is enough to rebuild the clock (a reload keeps it running)
  const again = JSON.parse(JSON.stringify(c));
  assert.equal(T.roundLeft(again, now + MIN), 149 * MIN);
  T.roundPause(c, now);
  now += 10 * MIN;
  assert.equal(T.roundLeft(c, now), 150 * MIN, 'paused: time does not pass');
  assert.equal(T.roundRunning(c), false);
  T.roundStart(c, now);
  now += 5 * MIN;
  assert.equal(T.roundLeft(c, now), 145 * MIN);
  T.roundSetLeft(c, 100, now);
  assert.equal(T.roundLeft(c, now + MIN), 99 * MIN, 'a judge\'s time call');
  now += 500 * MIN;
  assert.equal(T.roundLeft(c, now), 0, 'stops at zero');
  T.roundReset(c);
  assert.equal(T.roundLeft(c, now), 180 * MIN);
});

test('chess clock: only the running side loses time; passing and pausing', () => {
  const c = T.newClock();
  let now = 5_000;
  assert.equal(T.chessLeft(c, 'A', now), 85 * MIN, 'UKTC: 1:25 each');
  T.chessRun(c, 'A', now);
  now += 10 * MIN;
  assert.equal(T.chessLeft(c, 'A', now), 75 * MIN);
  assert.equal(T.chessLeft(c, 'B', now), 85 * MIN);
  T.chessRun(c, 'B', now);        // pass the clock
  now += 4 * MIN;
  assert.equal(T.chessLeft(c, 'A', now), 75 * MIN);
  assert.equal(T.chessLeft(c, 'B', now), 81 * MIN);
  T.chessPause(c, now);
  now += 60 * MIN;
  assert.deepEqual([T.chessLeft(c, 'A', now), T.chessLeft(c, 'B', now)], [75 * MIN, 81 * MIN], 'paused');
  T.chessRun(c, 'B', now);
  now += 200 * MIN;
  assert.equal(T.chessLeft(c, 'B', now), 0, 'a clock stops at zero');
  T.chessReset(c);
  assert.equal(T.chessStarted(c), false);
});

test('command points: 1CP each in every Command phase; one extra CP per battle round', () => {
  const g = game();
  assert.deepEqual([g.A.cp, g.B.cp], [1, 1], 'from the first Command phase');
  T.endTurn(g, 'A');              // A's turn done -> B's Command phase
  assert.deepEqual([g.A.cp, g.B.cp, g.round, g.next], [2, 2, 1, 'B']);
  T.endTurn(g, 'A');              // B's turn done -> round 2, A's Command phase
  assert.deepEqual([g.A.cp, g.B.cp, g.round, g.next], [3, 3, 2, 'A']);
  // a discard for CP: once per battle round
  assert.equal(T.canExtraCp(g, 'A'), true);
  assert.equal(T.extraCp(g, 'A').ok, true);
  assert.equal(g.A.cp, 4);
  const again = T.extraCp(g, 'A');
  assert.equal(again.ok, false);
  assert.match(again.why, /already gained the one extra CP of battle round 2/);
  assert.equal(g.A.cp, 4);
  assert.equal(T.extraCp(g, 'B').ok, true, 'each player has their own');
  T.endTurn(g, 'A'); T.endTurn(g, 'A');   // -> round 3
  assert.equal(g.round, 3);
  assert.equal(T.extraCp(g, 'A').ok, true, 'a new battle round');
});

test('turns: A then B, the next battle round after the second turn, and the battle ends after round 5', () => {
  const g = game();
  const seq = [];
  let res;
  for (let i = 0; i < 10; i++) { seq.push(`${g.round}${g.next ?? 'A'}`); res = T.endTurn(g, 'A'); }
  assert.deepEqual(seq, ['1A', '1B', '2A', '2B', '3A', '3B', '4A', '4B', '5A', '5B']);
  assert.deepEqual([res.ended, g.over, g.round], [true, true, 5], 'no round 6');
  assert.deepEqual([g.A.cp, g.B.cp], [10, 10], '1CP each in each of the 10 Command phases');
  // the player who goes second
  const h = game();
  T.endTurn(h, 'B');
  assert.deepEqual([h.round, h.next], [1, 'A']);
  T.endTurn(h, 'B');
  assert.deepEqual([h.round, h.next], [2, 'B']);
});

test('score sheet: what each player scored in each battle round, from the totals entered turn by turn', () => {
  const g = game();
  // round 1: A scores 5 secondary in its turn; B scores 4 primary + 5 secondary in its turn, A 2 more secondary
  g.A.secondary += 5;
  assert.deepEqual(T.turnDelta(g).A, { primary: 0, secondary: 5 });
  T.endTurn(g, 'A');
  g.B.primary += 4; g.B.secondary += 5; g.A.secondary += 2;
  T.endTurn(g, 'A');
  // round 2, A's turn (in progress): A 10 primary
  g.A.primary += 10;
  const s = T.scoreSheet(g);
  assert.deepEqual(s.rows[0], { round: 1, A: { primary: 0, secondary: 7 }, B: { primary: 4, secondary: 5 } });
  assert.deepEqual(s.rows[1].A, { primary: 10, secondary: 0 }, 'the turn in progress counts in its round');
  assert.deepEqual(s.total, { A: { primary: 10, secondary: 7 }, B: { primary: 4, secondary: 5 } });
  assert.equal(s.hasBefore, false);
  // a correction (minus) lands in the round it was made in
  g.A.primary -= 2;
  assert.deepEqual(T.scoreSheet(g).rows[1].A, { primary: 8, secondary: 0 });
  // changing the round by hand files what was scored under the round it was scored in
  T.flushTurn(g, 'A');
  g.round = 4;
  g.A.primary += 5;
  const s2 = T.scoreSheet(g);
  assert.deepEqual([s2.rows[1].A.primary, s2.rows[3].A.primary], [8, 5]);
  // sums always equal the totals
  for (const X of ['A', 'B']) for (const k of ['primary', 'secondary']) assert.equal(s2.rows.reduce((a, r) => a + r[X][k], 0), s2.total[X][k]);
});

test('a game from an older version (no log): its score is shown as "before", nothing is lost', () => {
  const old = { round: 3, next: 'A', A: { hand: [], used: [], primary: 12, secondary: 5, destroyed: [] }, B: { hand: [], used: [], primary: 9, secondary: 3, destroyed: [] } };
  T.ensureGame(old);
  assert.deepEqual([old.A.cp, old.B.cp], [0, 0], 'CP unknown: the player sets it');
  old.A.primary += 5;
  const s = T.scoreSheet(old);
  assert.deepEqual(s.rows[2].A, { primary: 5, secondary: 0 });
  assert.equal(s.hasBefore, true, 'what was scored before the sheet existed is in no battle round');
  assert.deepEqual(s.before, { A: { primary: 12, secondary: 5 }, B: { primary: 9, secondary: 3 } });
  assert.equal(s.total.A.primary, 17);
  assert.equal(s.rows.reduce((a, r) => a + r.A.primary, 0) + s.before.A.primary, s.total.A.primary, 'rounds + before = total');
});

test('undo: the tracker before each change, newest first, at most 30 steps', () => {
  const g = game();
  const stack = [];
  T.pushUndo(stack, g, 'score');
  g.A.primary = 5;
  T.pushUndo(stack, g, 'turn done');
  T.endTurn(g, 'A');
  T.pushUndo(stack, g, 'nothing');
  T.pushUndo(stack, g, 'nothing again');
  assert.equal(stack.length, 3, 'an unchanged tracker is not stored twice');
  stack.pop();
  let u = T.popUndo(stack);
  assert.equal(u.label, 'turn done');
  assert.deepEqual([u.game.round, u.game.next, u.game.A.primary, u.game.A.cp], [1, null, 5, 1]);
  u = T.popUndo(stack);
  assert.equal(u.game.A.primary, 0);
  assert.equal(T.popUndo(stack), null);
  for (let i = 0; i < 50; i++) { g.A.primary = i; T.pushUndo(stack, g, 'x'); }
  assert.equal(stack.length, T.UNDO_MAX);
});
