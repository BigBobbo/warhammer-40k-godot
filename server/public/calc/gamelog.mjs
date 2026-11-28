// The prediction record: what the Board said during a real game, kept turn by turn, and how it turned out.
//
// At every "Turn done" on the tracker with the live table on, one entry: the score, where the units stood, the
// forecast of that moment (win chance, margin, the moves it backed and whether they were made), the play-out if
// it was run, and what the turn cards expected of the turn that follows (which units would be destroyed, how
// likely). When the battle ends the record is closed with the final score; `review` then reads each call
// against what happened, and `calibration` adds the finished games up: of the times it said 60 to 80%, how
// often it happened.
//
// The record stays on the device (localStorage). Sending finished games to the server is a switch the player
// turns on (uploadBody: factions, unit names, positions, scores and the predictions - no list text, no names
// of people). Pure module (no DOM), unit-tested (tests/calc-gamelog.test.mjs).

export const LOG_FORMAT = 'combat-calc-gamelog';
export const KEEP_GAMES = 30;
const other = (X) => (X === 'A' ? 'B' : 'A');
const r1 = (n) => Math.round(n * 10) / 10;

/** A record for a game that starts (or is picked up) now. */
export function newRecord({ me = 'A', factions = {}, missions = {}, layout = null, first = null, version = '', started = Date.now() } = {}) {
  return { format: LOG_FORMAT, v: 1, version, started, me, first, factions: { A: factions.A ?? '', B: factions.B ?? '' }, missions: { A: missions.A ?? '', B: missions.B ?? '' }, layout, turns: [], final: null };
}

/**
 * One player turn that has just ended.
 * e: { round, turn (the player whose turn ended), vp: { A, B }, units: [{ tk, name, x, y, left, total }] (on the table),
 *      forecast: { win, margin } | null (for `me`, the table as it stood), moves: [{ unit, name, label, obj, vp, made }]
 *      (the moves the forecast backed), playout: { win, vpMe, vpOpp } | null,
 *      ahead: { side (whose turn comes next), destroyed: [{ tk, name, p }] } | null (what the cards expect of that turn) }
 * A turn recorded twice (the tracker stepped back and forth) replaces the earlier entry.
 */
export function addTurn(rec, e) {
  const entry = {
    round: e.round, turn: e.turn, at: e.at ?? Date.now(), vp: { A: e.vp?.A ?? 0, B: e.vp?.B ?? 0 },
    units: (e.units ?? []).map(u => ({ tk: u.tk, name: u.name, x: r1(u.x), y: r1(u.y), left: u.left ?? null, total: u.total ?? null })),
    forecast: e.forecast ? { win: e.forecast.win, margin: r1(e.forecast.margin ?? 0) } : null,
    moves: (e.moves ?? []).map(m => ({ unit: m.unit, name: m.name, label: m.label, obj: m.obj ?? null, vp: r1(m.vp ?? 0), made: m.made ?? null })),
    playout: e.playout ? { win: e.playout.win, vpMe: r1(e.playout.vpMe ?? 0), vpOpp: r1(e.playout.vpOpp ?? 0) } : null,
    ahead: e.ahead ? { side: e.ahead.side, destroyed: (e.ahead.destroyed ?? []).map(d => ({ tk: d.tk, name: d.name, p: Math.round(d.p * 1000) / 1000 })),
      // (1.154.0) halved: [{ tk, name, p }] - units expected to be left at or below half-strength (destroyed counts)
      ...(e.ahead.halved ? { halved: e.ahead.halved.map(d => ({ tk: d.tk, name: d.name, p: Math.round(d.p * 1000) / 1000 })) } : {}) } : null,
  };
  const i = rec.turns.findIndex(t => t.round === entry.round && t.turn === entry.turn);
  if (i >= 0) rec.turns.splice(i, rec.turns.length - i, entry); else rec.turns.push(entry);
  return entry;
}

/** The battle is over: the final score closes the record. */
export function finish(rec, vp, at = Date.now()) {
  rec.final = { A: vp?.A ?? 0, B: vp?.B ?? 0, at };
  return rec;
}

/**
 * How the calls of one game turned out.
 * -> { result: 'win' | 'loss' | 'draw' | null (not finished), margin (me - them, final),
 *      wins: [{ round, turn, said (P I win), margin (forecast), playout (P I win, if run) }],
 *      kills: [{ round, turn (the turn the call was about), side (who was to destroy), tk, name, p, happened }],
 *      moves: { backed, made } }
 */
export function review(rec) {
  const me = rec.me ?? 'A', opp = other(me);
  const margin = rec.final ? rec.final[me] - rec.final[opp] : null;
  const result = margin == null ? null : margin > 0 ? 'win' : margin < 0 ? 'loss' : 'draw';
  const wins = rec.turns.filter(t => t.forecast || t.playout).map(t => ({ round: t.round, turn: t.turn, said: t.forecast?.win ?? null, margin: t.forecast?.margin ?? null, playout: t.playout?.win ?? null }));
  const kills = [], halves = [];
  for (let i = 0; i + 1 < rec.turns.length; i++) {
    const a = rec.turns[i], b = rec.turns[i + 1];
    if (!a.ahead || b.turn !== a.ahead.side) continue;
    const left = new Map(b.units.map(u => [u.tk, u.left])), before = new Map(a.units.map(u => [u.tk, u.left]));
    for (const d of a.ahead.destroyed) {
      if (!before.has(d.tk) || before.get(d.tk) === 0) continue;            // not on the table when the call was made
      // gone from the table, or no models left, at the end of the turn the call was about
      kills.push({ round: b.round, turn: b.turn, side: a.ahead.side, tk: d.tk, name: d.name, p: d.p, happened: !left.has(d.tk) || left.get(d.tk) === 0 });
    }
    // at or below half-strength at the end of that turn: half the models it started the game with, or gone
    const total = new Map(a.units.map(u => [u.tk, u.total]));
    for (const d of a.ahead.halved ?? []) {
      const t = total.get(d.tk);
      if (!before.has(d.tk) || before.get(d.tk) === 0 || !(t >= 2)) continue;
      halves.push({ round: b.round, turn: b.turn, side: a.ahead.side, tk: d.tk, name: d.name, p: d.p, happened: !left.has(d.tk) || left.get(d.tk) * 2 <= t });
    }
  }
  const all = rec.turns.flatMap(t => t.moves ?? []);
  return { result, margin, wins, kills, halves, moves: { backed: all.length, made: all.filter(m => m.made === true).length } };
}

const BANDS = [[0, 0.2], [0.2, 0.4], [0.4, 0.6], [0.6, 0.8], [0.8, 1.0001]];
const bandOf = (p) => BANDS.findIndex(([lo, hi]) => p >= lo && p < hi);
const bands = () => BANDS.map(([lo, hi]) => ({ lo, hi: Math.min(1, hi), n: 0, hit: 0, sum: 0 }));
function tally(rows) {
  const out = bands();
  let brier = 0;
  for (const { p, hit } of rows) { const b = out[bandOf(p)]; b.n++; b.hit += hit ? 1 : 0; b.sum += p; brier += (p - (hit ? 1 : 0)) ** 2; }
  return { n: rows.length, brier: rows.length ? brier / rows.length : null, bands: out.map(b => ({ ...b, said: b.n ? b.sum / b.n : null, rate: b.n ? b.hit / b.n : null })) };
}
/**
 * The finished games added up: of the times a call said p, how often it happened.
 * -> { games, win: { n, brier, bands: [{ lo, hi, n, hit, said, rate }] } (the forecast's "you win" at each turn end,
 *      against the result; a draw counts as not won), playout: the same for the play-out, kills: the same for
 *      "this unit is destroyed in the turn that follows", moves: { backed, made } }
 */
export function calibration(records) {
  const done = records.filter(r => r.final);
  const win = [], po = [], kills = [], halves = [];
  let backed = 0, made = 0;
  for (const rec of done) {
    const rv = review(rec), won = rv.result === 'win';
    for (const w of rv.wins) { if (w.said != null) win.push({ p: w.said, hit: won }); if (w.playout != null) po.push({ p: w.playout, hit: won }); }
    for (const k of rv.kills) kills.push({ p: k.p, hit: k.happened });
    for (const k of rv.halves) halves.push({ p: k.p, hit: k.happened });
    backed += rv.moves.backed; made += rv.moves.made;
  }
  return { games: done.length, win: tally(win), playout: tally(po), kills: tally(kills), halves: tally(halves), moves: { backed, made } };
}

/** What is sent when the player has turned sending on: the record as it is, less the times of day. */
export function uploadBody(rec) {
  const { started: _s, ...rest } = rec;
  return { ...rest, turns: rec.turns.map(({ at: _a, ...t }) => t), final: rec.final ? { A: rec.final.A, B: rec.final.B } : null };
}

/** Is this something uploadBody made? (the server's check, and the test's) -> { ok, why } */
export function validUpload(b) {
  const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
  if (!isObj(b) || b.format !== LOG_FORMAT || b.v !== 1) return { ok: false, why: 'Not a Combat Calc game record' };
  if (!Array.isArray(b.turns) || b.turns.length < 1 || b.turns.length > 12) return { ok: false, why: 'A game record has 1 to 10 turns' };
  if (!isObj(b.final) || !Number.isFinite(b.final.A) || !Number.isFinite(b.final.B)) return { ok: false, why: 'The game is not finished' };
  if (!b.turns.every(t => isObj(t) && Number.isInteger(t.round) && t.round >= 1 && t.round <= 5 && (t.turn === 'A' || t.turn === 'B') && Array.isArray(t.units) && t.units.length <= 80)) return { ok: false, why: 'A turn of the record is not readable' };
  return { ok: true };
}
