// Table tools of the Mission > Play view: the pace clock (round timer with
// the tournament milestones, or a chess clock), command points, the score of
// each turn (the score sheet), and undo.
//
// Pure functions on plain objects (no DOM, no storage): unit-tested in
// tests/calc-playtools.test.mjs. missionview.mjs draws them.
//
// Sources (read in the documents, not from memory):
//  - Core rules 08.02 "Gain Core CP": both players gain 1CP in every Command phase.
//  - Event Companion v1.2: excluding Core CP, a player gains at most 1CP per
//    battle round (the CP for discarding a Secondary Mission card included).
//  - GW Grand Tournament pack 2026, 3.6 "Game Speed Milestones" (3-hour round).
//  - UKTC policies: chess clocks, "start the game with 1:25 on the clock".

const other = (X) => (X === 'A' ? 'B' : 'A');
const MIN = 60000;

// ---------------------------------------------------------------------------
// Round timer and its milestones

/** GW GT pack: time REMAINING (minutes) of a 3-hour round at which each step should be done. */
export const GT_MILESTONES = [
  { left: 175, text: 'Pre-game talk and choices done' },
  { left: 155, text: 'Deployment done, battle round 1 starts' },
  { left: 115, round: 1, text: 'Battle round 1 done' },
  { left: 75, round: 2, text: 'Battle round 2 done' },
  { left: 45, round: 3, text: 'Battle round 3 done' },
  { left: 25, round: 4, text: 'Battle round 4 done' },
  { left: 0, round: 5, text: 'Battle round 5 done' },
];
export const GT_ROUND_MIN = 180;
/** "0:05 remaining: do not begin a new battle round without a judge's permission" */
export const GT_NO_NEW_ROUND_MIN = 5;
export const ROUND_LENGTHS = [150, 165, 180, 210];
/** UKTC: "we recommend that players start the game with 1:25 on the clock" */
export const CHESS_BANKS = [75, 85, 90, 105];

/** The milestones of a round of `lenMin` minutes (the GW 3-hour ones, scaled when the round is not 3 hours). */
export function milestones(lenMin = GT_ROUND_MIN) {
  const k = lenMin / GT_ROUND_MIN;
  return GT_MILESTONES.map(m => ({ ...m, left: Math.round(m.left * k) }));
}

/**
 * Where the game is against the milestones.
 * round: the battle round in progress (1-5). Returns { target (minutes left at which
 * this battle round should be done), dueIn (minutes until then; negative = late),
 * behind (minutes late, 0 when on pace), noNewRound (too late to start another round) }.
 */
export function paceStatus(lenMin, leftMs, round) {
  const r = Math.max(1, Math.min(5, round || 1));
  const target = milestones(lenMin).find(m => m.round === r).left;
  const leftMin = leftMs / MIN;
  const dueIn = leftMin - target;
  return { round: r, target, dueIn, behind: dueIn < 0 ? Math.ceil(-dueIn) : 0, noNewRound: leftMin <= GT_NO_NEW_ROUND_MIN * (lenMin / GT_ROUND_MIN) && r < 5 };
}

/** 1:23:45, 12:34, 0:07 (never negative). */
export function fmtClock(ms) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
  const p = (n) => String(n).padStart(2, '0');
  return h ? `${h}:${p(m)}:${p(ss)}` : `${m}:${p(ss)}`;
}
/** 2:35 for 155 minutes. */
export const fmtHm = (min) => `${Math.floor(min / 60)}:${String(Math.round(min) % 60).padStart(2, '0')}`;

export function newClock() {
  return {
    mode: 'off',                 // 'off' | 'round' | 'chess'
    len: GT_ROUND_MIN,           // round timer: minutes
    endsAt: null, pausedLeft: null,   // running: the time it ends; paused: what was left
    bank: 85,                    // chess clock: minutes each
    left: null,                  // { A: ms, B: ms } once started
    running: null, since: null,  // whose clock runs, and since when
  };
}

// ---- round timer
export const roundRunning = (c) => c.endsAt != null;
export const roundStarted = (c) => c.endsAt != null || c.pausedLeft != null;
export function roundLeft(c, now) {
  if (c.endsAt != null) return Math.max(0, c.endsAt - now);
  if (c.pausedLeft != null) return c.pausedLeft;
  return c.len * MIN;
}
export function roundStart(c, now) { c.endsAt = now + roundLeft(c, now); c.pausedLeft = null; return c; }
export function roundPause(c, now) { if (c.endsAt != null) { c.pausedLeft = roundLeft(c, now); c.endsAt = null; } return c; }
export function roundReset(c) { c.endsAt = null; c.pausedLeft = null; return c; }
/** Change the length of a round that has not started; a started one keeps its time. */
export function roundSetLen(c, lenMin) { c.len = lenMin; return c; }
/** A judge's call or a late start: put the timer at `leftMin` minutes. */
export function roundSetLeft(c, leftMin, now) {
  const left = Math.max(0, leftMin) * MIN;
  if (c.endsAt != null) c.endsAt = now + left; else c.pausedLeft = left;
  return c;
}

// ---- chess clock
export const chessStarted = (c) => !!c.left;
export function chessLeft(c, X, now) {
  const base = c.left ? c.left[X] : c.bank * MIN;
  return Math.max(0, base - (c.running === X && c.since != null ? now - c.since : 0));
}
function chessCommit(c, now) {
  c.left ??= { A: c.bank * MIN, B: c.bank * MIN };
  if (c.running) c.left[c.running] = chessLeft(c, c.running, now);
  c.since = now;
}
/** Start (or pass) the clock: X's time runs. */
export function chessRun(c, X, now) { chessCommit(c, now); c.running = X; return c; }
export function chessPause(c, now) { chessCommit(c, now); c.running = null; return c; }
export function chessReset(c) { c.left = null; c.running = null; c.since = null; return c; }
export function chessSetBank(c, bankMin) { c.bank = bankMin; return c; }

// ---------------------------------------------------------------------------
// The game: command points, the score of each turn, turn order

export const scoresOf = (g) => ({ A: { primary: g.A.primary || 0, secondary: g.A.secondary || 0 }, B: { primary: g.B.primary || 0, secondary: g.B.secondary || 0 } });

/** Fields added by this module to a tracker game (old saves have none of them). */
export function ensureGame(g, { fresh = false } = {}) {
  for (const X of ['A', 'B']) {
    // both players have 1CP from the first Command phase; a game that was already
    // under way when this was added starts counting from 0 (the player sets it)
    g[X].cp ??= fresh ? 1 : 0;
    g[X].cpRound ??= 0;         // the battle round of the last CP gained from another source than Core CP
  }
  g.mark ??= scoresOf(g);       // the scores when the current turn began
  g.log ??= [];                 // one entry per finished turn: what each player scored in it
  g.turnsDone ??= 0;            // turns closed with "Turn done"
  g.drawn ??= 0;
  g.once ??= { A: {}, B: {} };  // once-per-battle rules ticked as used (Intel > By phase): { tickId: true }
  return g;
}

/** What each player has scored since the current turn began. */
export function turnDelta(g) {
  const now = scoresOf(g), m = g.mark ?? now;
  const d = (X, k) => now[X][k] - (m[X]?.[k] ?? 0);
  return { A: { primary: d('A', 'primary'), secondary: d('A', 'secondary') }, B: { primary: d('B', 'primary'), secondary: d('B', 'secondary') } };
}
const isZero = (d) => !d.A.primary && !d.A.secondary && !d.B.primary && !d.B.secondary;

/** Write what was scored since the mark to the log (for the round and turn it was scored in). */
export function flushTurn(g, turnOf) {
  const d = turnDelta(g);
  if (!isZero(d)) g.log.push({ round: g.round, turn: turnOf, ...d });
  g.mark = scoresOf(g);
  return g;
}

/**
 * "Turn done": log the turn, pass to the other player (after the second turn of a
 * battle round: the next round, up to round 5), and start that player's Command
 * phase — both players gain 1 Core CP.
 * Returns { ended: true } when it was the last turn of the battle.
 */
export function endTurn(g, first, rounds = 5) {
  const cur = g.next ?? first ?? 'A';
  const firstP = first ?? cur;
  flushTurn(g, cur);
  g.drawn = 0;
  g.turnsDone = (g.turnsDone || 0) + 1;
  const lastTurn = g.round >= rounds && cur !== firstP;
  if (lastTurn) { g.over = true; return { ended: true }; }
  if (cur !== firstP) g.round++;
  g.next = other(cur);
  g.A.cp = (g.A.cp || 0) + 1;
  g.B.cp = (g.B.cp || 0) + 1;
  return { ended: false };
}

/**
 * A CP from another source than Core CP (discarding a Secondary Mission card,
 * an army rule): at most one per battle round at events.
 */
export function extraCp(g, X) {
  if (g[X].cpRound === g.round) return { ok: false, why: `${X} already gained the one extra CP of battle round ${g.round}` };
  g[X].cp = (g[X].cp || 0) + 1;
  g[X].cpRound = g.round;
  return { ok: true };
}
export const canExtraCp = (g, X) => g[X].cpRound !== g.round;

/**
 * The score sheet: per battle round, what each player scored (primary,
 * secondary), with the turn in progress included, and the totals.
 */
export function scoreSheet(g, rounds = 5) {
  const rows = Array.from({ length: rounds }, (_, i) => ({ round: i + 1, A: { primary: 0, secondary: 0 }, B: { primary: 0, secondary: 0 } }));
  const add = (round, d) => {
    const row = rows[Math.max(1, Math.min(rounds, round)) - 1];
    for (const X of ['A', 'B']) { row[X].primary += d[X].primary; row[X].secondary += d[X].secondary; }
  };
  for (const e of g.log ?? []) add(e.round, e);
  add(g.round, turnDelta(g));
  const total = scoresOf(g);
  // scores typed in before the log existed (or by an older version) are not in any round
  const logged = { A: { primary: 0, secondary: 0 }, B: { primary: 0, secondary: 0 } };
  for (const r of rows) for (const X of ['A', 'B']) { logged[X].primary += r[X].primary; logged[X].secondary += r[X].secondary; }
  const before = { A: { primary: total.A.primary - logged.A.primary, secondary: total.A.secondary - logged.A.secondary }, B: { primary: total.B.primary - logged.B.primary, secondary: total.B.secondary - logged.B.secondary } };
  return { rows, total, before, hasBefore: !isZero(before) };
}

// ---------------------------------------------------------------------------
// Undo: the tracker before each change (newest last)

export const UNDO_MAX = 30;
export function pushUndo(stack, game, label) {
  const snap = JSON.stringify(game);
  if (stack.length && stack[stack.length - 1].g === snap) return stack;   // nothing changed since
  stack.push({ g: snap, label });
  while (stack.length > UNDO_MAX) stack.shift();
  return stack;
}
export function popUndo(stack) {
  const e = stack.pop();
  return e ? { game: JSON.parse(e.g), label: e.label } : null;
}
