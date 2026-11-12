// Combat calculator engine — Warhammer 40,000 11th edition attack sequence,
// Monte Carlo. Pure module (no DOM, no dataset): the page's Web Worker and
// the node tests both import it.
//
// Rules implemented (core rules, wahapedia wh40k11ed, checked 2026-11-11):
//  05.01 Hit roll   — unmodified 1 fails, unmodified 6 (or critHit) = critical
//                     hit. Benefit of cover (13.08) WORSENS BS by 1 (a
//                     characteristic change, not capped like dice
//                     modifiers); BS/WS stays within 2+..6+.
//  05.02 Wound roll — S vs T chart 2+..6+, unmodified 1 fails, unmodified 6
//                     (or Anti-X Y+ / critWound) = critical wound.
//  02.02 Dice-roll modifiers to hit / wound / save net out and cap at ±1.
//  01.05 Re-rolls happen before modifiers; a die is re-rolled at most once.
//  05.03 Saves      — allocation groups (non-CHARACTER groups first, a group
//                     with a wounded model first; CHARACTER groups last); one
//                     save per wound, resolved LOWEST to HIGHEST against the
//                     current group. InSv uses the unmodified roll; armour
//                     uses roll + save mod - AP vs Sv. A natural 1 fails.
//  05.04 Damage     — a wounded model in the group takes it first; excess
//                     damage on a destroyed model is lost; attacks past the
//                     last model are lost.
//  24.12 Feel No Pain — one roll per wound that would be lost.
//  24.10 Devastating Wounds — a critical wound ends the attack's sequence and
//                     inflicts mortal wounds equal to D, after normal damage;
//                     each critical wound damages at most ONE model (excess
//                     lost — no spill-over in 11e).
//  06.02 Mortal wounds go to a wounded non-CHARACTER, then any
//                     non-CHARACTER, then wounded CHARACTER, then CHARACTER.
//  24.28 Precision  — the CHARACTER group becomes the current group.
//  19.02 Attached units — attacks use the highest T among bodyguard models
//                     (leader models' T once only they remain).
//  Weapon abilities: Torrent, Lethal Hits, Sustained Hits X / DX, Twin-linked,
//  Devastating Wounds, Anti-X Y+, Blast X, Cleave X, Rapid Fire X, Melta X,
//  Heavy, Lance, Ignores Cover, Indirect Fire, Precision, Hazardous.
//  15.09 Snap shooting (overwatch): hits only on an unmodified 6, no critical
//  hits, no hit re-rolls (Torrent still auto-hits).

// ---------------------------------------------------------------------------
// RNG (seedable so tests are reproducible)

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------------------------------------------------------------------------
// Dice expressions: "3", "D6", "2D6+3", "D3+1"

export function parseDice(expr) {
  if (typeof expr === 'number') return { n: 0, sides: 0, plus: expr };
  const s = String(expr ?? '0').trim().toUpperCase().replace(/\s+/g, '');
  if (/^-?\d+$/.test(s)) return { n: 0, sides: 0, plus: parseInt(s, 10) };
  const m = s.match(/^(\d*)D(\d+)([+-]\d+)?$/);
  if (!m) return { n: 0, sides: 0, plus: parseInt(s, 10) || 0 };
  return { n: m[1] ? parseInt(m[1], 10) : 1, sides: parseInt(m[2], 10), plus: m[3] ? parseInt(m[3], 10) : 0 };
}

export function diceMean(d) {
  return d.n * (d.sides + 1) / 2 + d.plus;
}

function rollDice(d, rnd) {
  let t = d.plus;
  for (let i = 0; i < d.n; i++) t += 1 + Math.floor(rnd() * d.sides);
  return t;
}

const d6 = (rnd) => 1 + Math.floor(rnd() * 6);
const cap1 = (v) => Math.max(-1, Math.min(1, v));

export function woundThreshold(S, T) {
  if (S >= T * 2) return 2;
  if (S > T) return 3;
  if (S === T) return 4;
  if (S * 2 <= T) return 6;
  return 5;
}

// ---------------------------------------------------------------------------
// Scenario shape (all plain JSON so it crosses the worker boundary):
//
// scenario = {
//   phase: 'shooting' | 'fight',
//   attackers: [{
//     name,
//     mods: {                       // attacker-side, per attacking unit
//       hitMod, woundMod,           // dice-roll modifiers (net capped ±1 with defender's)
//       bsMod,                      // characteristic: +1 = worse (3+ -> 4+), -1 = better
//       apMod,                      // +1 = one point better AP (-1 -> -2)
//       damageMod,                  // + to D (after dice)
//       attacksMod,                 // + attacks per weapon copy
//       strengthMod,
//       rerollHits: 'none'|'ones'|'fail'|'noncrit',
//       rerollWounds: 'none'|'ones'|'fail'|'noncrit',
//       critHit: 6, critWound: 6,
//       lethal, sustained (0..), dev, twin, ignoresCover, precision,   // granted keywords
//       halfRange, charged, stationary, overwatch, indirect,          // situation
//       lethalVsDev: 'auto'|'roll',  // Lethal Hits choice (default auto-wound)
//     },
//     weapons: [{
//       name, count, melee,
//       A, skill, S, AP, D,         // A/D dice strings; skill = BS/WS number (null => torrent)
//       kw: { torrent, lethal, sustained, sustainedDice, dev, twin, blast, cleave,
//             rapidFire, melta, heavy, lance, ignoresCover, indirect, precision,
//             hazardous, anti: [{keyword, threshold}] },
//     }],
//     allVehicleMonster,            // for hazardous mortal wounds (3 instead of 1)
//   }],
//   defender: {
//     name, keywords: [...UPPER],
//     groups: [{ name, count, W, Sv, InSv, T, character, woundsLeftFirst, dr, fnp }],
//     mods: {
//       cover,                      // benefit of cover vs ranged
//       hitMod, woundMod,           // defender-side dice modifiers (e.g. -1)
//       woundModIfSGreaterT,        // e.g. -1 only when S > T
//       saveMod,                    // dice modifier to saves (+1 = cover-like save bonus)
//       apReduce,                   // worsen incoming AP by N (to max 0)
//       damageReduction: 0 | 1 | 'half',
//       fnp, fnpMortal, fnpPsychic, // thresholds (0 = none)
//       invuln,                     // override / grant InSv to all groups (0 = none)
//     },
//   },
//   trials: 20000, seed,
// }

// Combine two modifier sets (unit-wide + one weapon's own, or manual + rules):
// numbers add (the engine caps dice modifiers later), flags OR, re-rolls take
// the stronger, critical thresholds the lower, keyword values the higher.
const REROLL_RANK = { none: 0, ones: 1, fail: 2, noncrit: 3 };
export function mergeMods(a = {}, b = {}) {
  const out = { ...a };
  for (const [k, v] of Object.entries(b ?? {})) {
    if (v == null) continue;
    const cur = out[k];
    if (k === 'rerollHits' || k === 'rerollWounds') out[k] = (REROLL_RANK[v] ?? 0) > (REROLL_RANK[cur] ?? 0) ? v : (cur ?? v);
    else if (k === 'critHit' || k === 'critWound') out[k] = Math.min(cur ?? 6, v);
    else if (k === 'sustained') out[k] = Math.max(cur ?? 0, v);
    else if (typeof v === 'boolean') out[k] = !!cur || v;
    else if (typeof v === 'number') out[k] = (cur ?? 0) + v;
    else out[k] = v;
  }
  return out;
}

function defaults(mods) {
  return {
    hitMod: 0, woundMod: 0, bsMod: 0, apMod: 0, damageMod: 0, attacksMod: 0, strengthMod: 0,
    rerollHits: 'none', rerollWounds: 'none', critHit: 6, critWound: 6,
    lethal: false, sustained: 0, dev: false, twin: false, ignoresCover: false, precision: false,
    lance: false, cleave: 0, rapidFire: 0,  // granted: [LANCE], [CLEAVE X], +X to / grant [RAPID FIRE]
    halfRange: false, charged: false, stationary: false, overwatch: false, indirect: false,
    lethalVsDev: 'auto',
    ...(mods ?? {}),
  };
}

function defDefaults(mods) {
  return {
    cover: false, hitMod: 0, woundMod: 0, woundModIfSGreaterT: 0, saveMod: 0, apReduce: 0,
    damageReduction: 0, fnp: 0, fnpMortal: 0, fnpPsychic: 0, invuln: 0,
    ...(mods ?? {}),
  };
}

// Pre-compute everything that does not depend on the dice.
function compile(scenario) {
  const def = scenario.defender;
  const dm = defDefaults(def.mods);
  const kwSet = new Set((def.keywords ?? []).map(k => String(k).toUpperCase()));
  const groups = (def.groups ?? []).filter(g => g.count > 0).map((g, i) => ({
    idx: i,
    name: g.name,
    count: g.count,
    W: g.W,
    Sv: Math.max(2, g.Sv ?? 7),
    InSv: dm.invuln ? Math.min(dm.invuln, g.InSv || 7) : (g.InSv || 0),
    T: g.T,
    character: !!g.character,
    woundsLeftFirst: g.woundsLeftFirst ?? null,
    dr: g.dr || 0,          // per-group damage reduction (e.g. Praesidium Shield models)
    fnp: g.fnp || 0,        // per-group Feel No Pain (e.g. a leader's own FNP)
  }));
  const attackers = (scenario.attackers ?? []).map(a => {
    const unitMods = defaults(a.mods);
    const weapons = (a.weapons ?? []).filter(w => (w.count ?? 0) > 0).map(w => {
      const kw = w.kw ?? {};
      // per-weapon modifiers (e.g. a Leader's "this model's attacks have +1 to hit")
      const m = w.mods ? defaults(mergeMods(unitMods, w.mods)) : unitMods;
      const melee = !!w.melee;
      return {
        name: w.name,
        count: w.count,
        melee,
        A: parseDice(w.A),
        D: parseDice(w.D),
        skill: kw.torrent || w.skill == null ? null : Number(w.skill),
        S: Number(w.S) + (m.strengthMod || 0),
        AP: Math.abs(Number(w.AP) || 0),
        torrent: !!kw.torrent || w.skill == null,
        lethal: !!kw.lethal || m.lethal,
        sustained: Math.max(kw.sustained || 0, m.sustained || 0),
        sustainedDice: !!kw.sustainedDice && (kw.sustained || 0) >= (m.sustained || 0),
        dev: !!kw.dev || m.dev,
        twin: !!kw.twin || m.twin,
        blast: kw.blast || 0,
        cleave: (kw.cleave || 0) + (m.cleave || 0),  // "[CLEAVE 1], or +1 to an existing [CLEAVE]"
        rapidFire: (kw.rapidFire || 0) + (m.rapidFire || 0),
        melta: kw.melta || 0,
        heavy: !!kw.heavy,
        lance: !!kw.lance || m.lance,
        ignoresCover: !!kw.ignoresCover || m.ignoresCover,
        indirect: !!kw.indirect && m.indirect,
        precision: !!kw.precision || m.precision,
        hazardous: !!kw.hazardous,
        psychic: !!kw.psychic,
        antiCrit: (kw.anti ?? []).reduce((best, an) =>
          kwSet.has(String(an.keyword).toUpperCase()) ? Math.min(best, an.threshold) : best, 7),
        m,
      };
    });
    return { name: a.name, mods: unitMods, weapons, allVehicleMonster: !!a.allVehicleMonster };
  });
  return { phase: scenario.phase ?? 'shooting', attackers, groups, dm };
}

// ---------------------------------------------------------------------------
// One trial

function newTargetState(groups) {
  return groups.map(g => {
    const models = new Array(g.count).fill(g.W);
    if (g.woundsLeftFirst != null && g.count > 0) models[0] = Math.max(1, Math.min(g.W, g.woundsLeftFirst));
    return { g, models, alive: g.count };
  });
}

function aliveTotal(st) {
  let n = 0;
  for (const s of st) n += s.alive;
  return n;
}

function groupWounded(s) {
  return s.models.some(w => w > 0 && w < s.g.W);
}

// 19.02: highest T among alive non-character (bodyguard) models, else among characters.
function currentT(st) {
  let bg = 0, ch = 0;
  for (const s of st) {
    if (s.alive <= 0) continue;
    if (s.g.character) ch = Math.max(ch, s.g.T); else bg = Math.max(bg, s.g.T);
  }
  return bg || ch || 1;
}

function effSave(g, ap, saveMod) {
  // probability-free ordering key: best of armour (after AP) and InSv
  const armour = g.Sv + ap - saveMod;
  return Math.min(armour, g.InSv || 7);
}

// Allocation order (05.03): non-character groups before character groups; a
// group with a wounded model first. Among the rest the defender picks; we
// model a defender who puts the group with the best effective save forward
// (most models as a tie-break).
function allocationOrder(st, ap, saveMod, precision) {
  const live = st.filter(s => s.alive > 0);
  const key = (s) => [
    precision && s.g.character ? 0 : 1,
    s.g.character ? 1 : 0,
    groupWounded(s) ? 0 : 1,
    effSave(s.g, ap, saveMod),
    -s.alive,
  ];
  return live.sort((a, b) => {
    const ka = key(a), kb = key(b);
    for (let i = 0; i < ka.length; i++) if (ka[i] !== kb[i]) return ka[i] - kb[i];
    return 0;
  });
}

function pickModel(s) {
  // a wounded model first, else any alive model
  let any = -1;
  for (let i = 0; i < s.models.length; i++) {
    const w = s.models[i];
    if (w <= 0) continue;
    if (w < s.g.W) return i;
    if (any < 0) any = i;
  }
  return any;
}

function applyFnp(dmg, fnp, rnd) {
  if (!fnp || fnp > 6) return dmg;
  let lost = 0;
  for (let i = 0; i < dmg; i++) if (d6(rnd) < fnp) lost++;
  return lost;
}

// Apply `dmg` to one model of group-state s. Returns wounds actually lost.
function damageModel(s, idx, dmg, out) {
  const before = s.models[idx];
  const lost = Math.min(before, dmg);
  s.models[idx] = before - lost;
  out.woundsLost += lost;
  if (s.models[idx] <= 0) {
    s.alive--;
    out.kills++;
    out.killsByGroup[s.g.idx]++;
  }
  return lost;
}

function mortalTarget(st, precision) {
  // 06.02 priority; Precision dev wounds go to the character group first (24.28.01)
  const order = [];
  if (precision) for (const s of st) if (s.alive > 0 && s.g.character) order.push(s);
  const nonChar = st.filter(s => s.alive > 0 && !s.g.character);
  const chars = st.filter(s => s.alive > 0 && s.g.character);
  for (const s of nonChar) if (groupWounded(s)) order.push(s);
  order.push(...nonChar);
  for (const s of chars) if (groupWounded(s)) order.push(s);
  order.push(...chars);
  return order[0] ?? null;
}

// Per-batch hit/wound parameters (computed once per weapon profile, not per die).
function hitParams(w, m, ctx) {
  return {
    torrent: w.torrent,
    snap: !!m.overwatch,
    bs: w.torrent ? 0 : Math.min(6, Math.max(2, w.skill + m.bsMod + ctx.coverBs)),
    failBand: w.indirect ? (m.stationary ? 3 : 5) : 1,
    critAt: m.overwatch ? 7 : Math.min(m.critHit || 6, 6),
    mod: cap1(m.hitMod + ctx.defHitMod + (w.heavy && m.stationary ? 1 : 0)),
    reroll: m.overwatch || w.indirect ? 'none' : m.rerollHits,
  };
}

function evalHit(hp, r) {
  if (hp.snap) return r === 6 ? 1 : 0;
  if (r <= hp.failBand) return 0;
  if (r >= hp.critAt) return 2;
  return r + hp.mod >= hp.bs ? 1 : 0;
}

function rollHit(hp, rnd) {
  // returns 0 miss, 1 hit, 2 critical hit
  if (hp.torrent) return 1;
  const r = d6(rnd);
  const res = evalHit(hp, r);
  const p = hp.reroll;
  if ((p === 'ones' && r === 1) || (p === 'fail' && res === 0) || (p === 'noncrit' && res < 2)) {
    return evalHit(hp, d6(rnd));
  }
  return res;
}

function woundParams(w, m, ctx) {
  return {
    thr: woundThreshold(w.S, ctx.T),
    critAt: Math.min(m.critWound || 6, w.antiCrit, 6),
    mod: cap1(m.woundMod + (w.lance && m.charged ? 1 : 0) + ctx.defWoundMod +
      (w.S > ctx.T ? ctx.defWoundModIfSgtT : 0)),
    reroll: w.twin && m.rerollWounds !== 'noncrit' ? 'fail' : m.rerollWounds,
  };
}

function evalWound(wp, r) {
  if (r === 1) return 0;
  if (r >= wp.critAt) return 2;
  return r + wp.mod >= wp.thr ? 1 : 0;
}

function rollWound(wp, rnd) {
  // returns 0 fail, 1 wound, 2 critical wound
  const r = d6(rnd);
  const res = evalWound(wp, r);
  const p = wp.reroll;
  if ((p === 'ones' && r === 1) || (p === 'fail' && res === 0) || (p === 'noncrit' && res < 2)) {
    return evalWound(wp, d6(rnd));
  }
  return res;
}

function rollDamage(w, m, dm, g, rnd) {
  let d = rollDice(w.D, rnd) + (w.melta && m.halfRange ? w.melta : 0) + (m.damageMod || 0);
  const dr = g.dr || dm.damageReduction;
  if (dr === 'half') d = Math.ceil(d / 2);
  else if (dr) d -= dr;
  return Math.max(1, d);
}

function fnpFor(w, dm, g, mortal) {
  let t = Math.min(dm.fnp || 7, g.fnp || 7);
  if (mortal && dm.fnpMortal) t = Math.min(t, dm.fnpMortal);
  if (w.psychic && dm.fnpPsychic) t = Math.min(t, dm.fnpPsychic);
  return t >= 7 ? 0 : t;
}

function runTrial(C, rnd, rec) {
  const st = newTargetState(C.groups);
  const dm = C.dm;
  const totalStart = aliveTotal(st);
  const perAttacker = [];
  let hazardMW = 0;
  const steps = { attacks: 0, hits: 0, wounds: 0, unsaved: 0, mortals: 0 };
  const out = { kills: 0, woundsLost: 0, killsByGroup: new Array(C.groups.length).fill(0) };

  for (const a of C.attackers) {
    const killsBefore = out.kills, woundsBefore = out.woundsLost;
    const startAlive = aliveTotal(st);
    for (const w of a.weapons) {
      if (aliveTotal(st) <= 0) break;
      const m = w.m;
      const ranged = !w.melee;
      const ctx = {
        T: currentT(st),
        coverBs: ranged && (dm.cover || w.indirect) && !w.ignoresCover ? 1 : 0,
        defHitMod: dm.hitMod,
        defWoundMod: dm.woundMod,
        defWoundModIfSgtT: dm.woundModIfSGreaterT,
      };
      // --- attack dice
      let dice = 0;
      for (let c = 0; c < w.count; c++) {
        let n = rollDice(w.A, rnd) + (m.attacksMod || 0);
        if (w.rapidFire && m.halfRange && ranged) n += w.rapidFire;
        if (w.blast && ranged) n += w.blast * Math.floor(startAlive / 5);
        if (w.cleave && !ranged) n += w.cleave * Math.floor(startAlive / 5);
        dice += Math.max(0, n);
      }
      steps.attacks += dice;
      // --- hits
      let hits = 0, autoWounds = 0;
      const hp = hitParams(w, m, ctx);
      for (let i = 0; i < dice; i++) {
        const h = rollHit(hp, rnd);
        if (h === 0) continue;
        if (h === 2) {
          if (w.lethal && !(w.dev && m.lethalVsDev === 'roll')) autoWounds++; else hits++;
          if (w.sustained) hits += w.sustainedDice ? 1 + Math.floor(rnd() * w.sustained) : w.sustained;
        } else hits++;
      }
      steps.hits += hits + autoWounds;
      // --- wounds
      let normalWounds = autoWounds;
      const devCrits = [];
      const wp = woundParams(w, m, ctx);
      for (let i = 0; i < hits; i++) {
        const r = rollWound(wp, rnd);
        if (r === 0) continue;
        if (r === 2 && w.dev) devCrits.push(1); else normalWounds++;
      }
      steps.wounds += normalWounds + devCrits.length;
      // --- saves (one per wound, lowest first, against the current group)
      const ap = Math.max(0, w.AP + (m.apMod || 0) - (dm.apReduce || 0));
      const saveMod = cap1(dm.saveMod || 0);
      const rolls = [];
      for (let i = 0; i < normalWounds; i++) rolls.push(d6(rnd));
      rolls.sort((x, y) => x - y);
      let order = allocationOrder(st, ap, saveMod, w.precision);
      let gi = 0;
      for (const r of rolls) {
        while (gi < order.length && order[gi].alive <= 0) gi++;
        if (gi >= order.length) break;
        const s = order[gi];
        const g = s.g;
        const saved = r !== 1 && ((g.InSv && r >= g.InSv) || (r + saveMod - ap >= g.Sv));
        if (saved) continue;
        steps.unsaved++;
        const dmg = rollDamage(w, m, dm, g, rnd);
        const lost = applyFnp(dmg, fnpFor(w, dm, g, false), rnd);
        const idx = pickModel(s);
        if (lost > 0 && idx >= 0) damageModel(s, idx, lost, out);
      }
      // --- devastating wounds: after normal damage, one model each
      for (let i = 0; i < devCrits.length; i++) {
        const s = mortalTarget(st, w.precision);
        if (!s) break;
        steps.mortals++;
        const mw = rollDamage(w, m, dm, s.g, rnd);
        const lost = applyFnp(mw, fnpFor(w, dm, s.g, true), rnd);
        const idx = pickModel(s);
        if (lost > 0 && idx >= 0) damageModel(s, idx, lost, out);
      }
      // --- hazardous (after the unit's attacks; counted for the attacker)
      if (w.hazardous) {
        for (let c = 0; c < w.count; c++) if (d6(rnd) <= 2) hazardMW += a.allVehicleMonster ? 3 : 1;
      }
    }
    perAttacker.push({ kills: out.kills - killsBefore, wounds: out.woundsLost - woundsBefore });
  }
  rec.kills = out.kills;
  rec.woundsLost = out.woundsLost;
  rec.wiped = totalStart > 0 && aliveTotal(st) === 0;
  rec.killsByGroup = out.killsByGroup;
  rec.perAttacker = perAttacker;
  rec.hazardMW = hazardMW;
  rec.steps = steps;
}

// ---------------------------------------------------------------------------
// Public: simulate

export function simulate(scenario) {
  const C = compile(scenario);
  const trials = Math.max(1, scenario.trials ?? 20000);
  const rnd = mulberry32(scenario.seed ?? 0x40C0FFEE);
  const totalModels = C.groups.reduce((s, g) => s + g.count, 0);
  const totalWounds = C.groups.reduce((s, g) => s + (g.count - (g.woundsLeftFirst != null ? 1 : 0)) * g.W +
    (g.woundsLeftFirst != null ? Math.min(g.W, g.woundsLeftFirst) : 0), 0);
  const killHist = new Array(totalModels + 1).fill(0);
  const woundHist = new Array(totalWounds + 1).fill(0);
  const groupKills = new Array(C.groups.length).fill(0);
  const perAttacker = C.attackers.map(a => ({ name: a.name, kills: 0, wounds: 0 }));
  const steps = { attacks: 0, hits: 0, wounds: 0, unsaved: 0, mortals: 0 };
  let wipes = 0, hazard = 0, sumKills = 0, sumWounds = 0;
  const rec = {};
  for (let t = 0; t < trials; t++) {
    runTrial(C, rnd, rec);
    killHist[rec.kills]++;
    woundHist[Math.min(rec.woundsLost, totalWounds)]++;
    sumKills += rec.kills;
    sumWounds += rec.woundsLost;
    if (rec.wiped) wipes++;
    hazard += rec.hazardMW;
    for (let i = 0; i < groupKills.length; i++) groupKills[i] += rec.killsByGroup[i];
    for (let i = 0; i < perAttacker.length; i++) {
      perAttacker[i].kills += rec.perAttacker[i]?.kills ?? 0;
      perAttacker[i].wounds += rec.perAttacker[i]?.wounds ?? 0;
    }
    for (const k in steps) steps[k] += rec.steps[k];
  }
  const norm = (arr) => arr.map(c => c / trials);
  const atLeast = (hist) => {
    const p = norm(hist);
    const out = new Array(p.length).fill(0);
    let acc = 0;
    for (let i = p.length - 1; i >= 0; i--) { acc += p[i]; out[i] = acc; }
    return out;
  };
  for (const k in steps) steps[k] /= trials;
  return {
    trials,
    totalModels,
    totalWounds,
    meanKills: sumKills / trials,
    meanWounds: sumWounds / trials,
    pWipe: wipes / trials,
    kills: norm(killHist),
    killsAtLeast: atLeast(killHist),
    wounds: norm(woundHist),
    woundsAtLeast: atLeast(woundHist),
    groupKills: C.groups.map((g, i) => ({ name: g.name, character: g.character, count: g.count, mean: groupKills[i] / trials })),
    perAttacker: perAttacker.map(p => ({ name: p.name, kills: p.kills / trials, wounds: p.wounds / trials })),
    steps,
    hazardMW: hazard / trials,
  };
}

// ---------------------------------------------------------------------------
// Analytic helpers (used by tests as an independent oracle and by the UI to
// rank melee weapon choices cheaply).

export function pHitSingle(skill, hitMod = 0, critHit = 6) {
  // P(hit) for one die, no re-rolls
  let p = 0;
  for (let r = 2; r <= 6; r++) if (r >= critHit || r + cap1(hitMod) >= skill) p++;
  return p / 6;
}

export function expectedDamageQuick(w, T, Sv, InSv) {
  // rough mean damage per weapon copy vs a generic target (no re-rolls, no FNP)
  const A = diceMean(parseDice(w.A));
  const ph = w.kw?.torrent || w.skill == null ? 1 : pHitSingle(Number(w.skill));
  const thr = woundThreshold(Number(w.S), T);
  const pw = (7 - thr) / 6;
  const ap = Math.abs(Number(w.AP) || 0);
  const need = Math.min(Sv + ap, InSv || 7);
  const pf = Math.min(1, Math.max(1 / 6, (need - 1) / 6));
  return A * ph * pw * pf * diceMean(parseDice(w.D));
}

// ---------------------------------------------------------------------------
// Charge odds (11e 11.02-11.04): 2D6 charge roll = maximum charge distance;
// the charge must end engaged (engagement range 2"), so a gap of G" needs a
// roll of at least G - 2. Charge-roll modifiers net to ±1; a re-roll
// (e.g. Command Re-roll) re-rolls the whole charge roll.

export const ENGAGEMENT_RANGE = 2;

export function chargeRollNeeded(gapInches) {
  return Math.max(2, Math.ceil(gapInches - ENGAGEMENT_RANGE - 1e-9));
}

/** Exact P(success) for a 2D6 charge needing `need`, with modifier and optional full re-roll. */
export function chargeOdds(need, { mod = 0, reroll = false } = {}) {
  const m = cap1(mod);
  let p = 0;
  for (let a = 1; a <= 6; a++) for (let b = 1; b <= 6; b++) if (a + b + m >= need) p++;
  p /= 36;
  return reroll ? p + (1 - p) * p : p;
}
