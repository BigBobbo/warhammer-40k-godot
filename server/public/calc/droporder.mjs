// Deployment drop order (Event Companion step 8, "Deploy armies"): the players set up their units one at a time,
// starting with the Defender; a player who sets up a TITANIC unit skips their next turn to set up a unit; once a
// player has set up all their units, the other sets up the rest. Units in strategic reserves are not set up.
// Pure: tests/calc-droporder.test.mjs.

const other = (X) => (X === 'A' ? 'B' : 'A');

/**
 * Where a drill stands. totals: { A, B } units each player sets up (reserves and embarked units left out);
 * log: [{ X, tk }] in order; titanic(tk) -> true for a TITANIC unit.
 * -> { next: 'A'|'B'|null (null = all set up), left: { A, B }, finishesFirst, lastRun: { side, n } | null }
 */
export function dropState(defender, totals, log, titanic = () => false) {
  const left = { A: totals.A, B: totals.B }, skip = { A: 0, B: 0 };
  const turnOf = (P) => {
    for (let i = 0; i < 4; i++) {
      if (left.A <= 0 && left.B <= 0) return null;
      if (left[P] <= 0) { P = other(P); continue; }
      if (skip[P] > 0 && left[other(P)] > 0) { skip[P]--; P = other(P); continue; }
      return P;
    }
    return P;
  };
  let turn = turnOf(defender);
  for (const e of log) {
    left[e.X] = Math.max(0, left[e.X] - 1);
    if (titanic(e.tk)) skip[e.X]++;
    turn = turnOf(other(e.X));
  }
  // play the rest out (each side's remaining drops, alternating, with the skips) to see who finishes first and
  // how many units the other side then sets up knowing where everything of the first side is
  const sim = { A: left.A, B: left.B }, sk = { ...skip };
  let t = turn, first = null;
  const order = [];
  while (t && (sim.A > 0 || sim.B > 0)) {
    sim[t]--; order.push(t);
    if (sim[t] === 0 && !first) first = t;
    let n = other(t);
    for (let i = 0; i < 4; i++) {
      if (sim.A <= 0 && sim.B <= 0) { n = null; break; }
      if (sim[n] <= 0) { n = other(n); continue; }
      if (sk[n] > 0 && sim[other(n)] > 0) { sk[n]--; n = other(n); continue; }
      break;
    }
    t = n;
  }
  if (!first && (left.A === 0 || left.B === 0) && (left.A || left.B)) first = left.A === 0 ? 'A' : 'B';
  let lastRun = null;
  if (order.length) {
    const tail = order[order.length - 1];
    let n = 0;
    for (let i = order.length - 1; i >= 0 && order[i] === tail; i--) n++;
    if (n > 1) lastRun = { side: tail, n };
  }
  return { next: turn, left, finishesFirst: first, lastRun };
}
