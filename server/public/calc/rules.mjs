// Rules-text parsing for the combat calculator: turns 11th edition ability /
// stratagem wording into engine modifier patches plus the conditions under
// which they apply. Pure module (no dataset) so it is unit-tested on real
// codex texts (tests/calc-rules.test.mjs).
//
// The 11e codex wording is regular:
//   "This unit's melee attacks have +1 to hit rolls."
//   "If this unit made a charge move this turn, this unit's melee attacks have: • +1 S. • +1 D."
//   "Your unit's melee attacks have [Lethal Hits]."
//   "This unit's attacks have [Lethal Hits: non-MONSTER/VEHICLE]."
//   "Attacks that target this unit have -1 to wound rolls."
// Anything the parser cannot recognise is still listed (text only) so the
// player can set it with the manual modifiers.

const AP = /['’]/; // apostrophes come in both shapes
const norm = (t) => String(t ?? '').replace(/\s+/g, ' ').replace(/[‘’]/g, '’').trim();

// "• X. • Or: Y" — a choice; the calculator models the first option.
function firstOption(t) {
  const i = t.search(/•\s*Or:|\bOr:\s/);
  return i >= 0 ? t.slice(0, i) : t;
}

function phasesOf(t) {
  const melee = /\bmelee (attacks?|weapons?)\b/i.test(t);
  const ranged = /\branged (attacks?|weapons?)\b/i.test(t);
  if (melee && !ranged) return ['fight'];
  if (ranged && !melee) return ['shooting'];
  return ['shooting', 'fight'];
}

function kwList(phrase) {
  return String(phrase ?? '').split(/\/|\s+or\s+/i).map(s => s.trim().toUpperCase()).filter(Boolean);
}

// ---------------------------------------------------------------------------
// Conditions

const KNOWN_CONDITIONS = [
  [/if (this|your) unit made a charge move this turn,?|that made a charge move this turn|if (this|your) unit charged this turn,?/gi, (c) => { c.charged = true; }],
  [/if (this|your) unit remained stationary this turn,?|that remained stationary this turn/gi, (c) => { c.stationary = true; }],
  [/within half range/gi, (c) => { c.halfRange = true; }],
  [/while this model is (leading a unit|attached to a unit),?/gi, (c) => { c.leading = true; }],
];

const UNKNOWN_CONDITION = /\b(if|while|whilst|when|each time|you can|select|within \d|within range|once per|at the start|at the end|in your|in the (shooting|fight|command|movement|charge) phase|below half|at or below|visible|quarry|terrain|ingress|doctrine|objective|battle-shocked|psychic roll|roll one|first time)\b/i;

/**
 * Pull the recognised conditions out of `t`; flags `unknown` when other
 * situational wording remains (those rules start switched off).
 */
export function parseConditions(text) {
  let t = norm(text).replace(/\(Duration:[^)]*\)/gi, '');
  const c = { targetKw: [], targetNotKw: [], selfKw: [], unknown: false };
  // "If the unit has the ORKS keyword, ..." — the attacker's own keywords
  t = t.replace(/if (?:the|this|your) unit has the ([A-Za-z’' -]+?) keyword,?/gi, (_, k) => { c.selfKw.push(k.trim().toUpperCase()); return ' '; });
  t = t.replace(/for the rest of the battle,?/gi, ' ');
  for (const [re, set] of KNOWN_CONDITIONS) {
    if (re.test(t)) { set(c); t = t.replace(re, ' '); }
    re.lastIndex = 0;
  }
  // "...attacks that target a MONSTER/VEHICLE unit..." / "...a unit (excluding MONSTER/VEHICLE units)..."
  let m;
  const tgt = /that targets? an? (?:enemy )?((?:[A-Za-z’'-]+(?:\/| )?)*?)\s*unit(?:s)?\b(\s*\(excluding ([^)]+?) units?\))?/gi;
  while ((m = tgt.exec(t))) {
    const phrase = (m[1] ?? '').trim();
    if (phrase && !/^(enemy|visible)$/i.test(phrase)) c.targetKw.push(...kwList(phrase));
    if (m[3]) c.targetNotKw.push(...kwList(m[3]));
    if (/visible/i.test(phrase)) c.unknown = true;
  }
  t = t.replace(tgt, ' ');
  // the subject itself ("This unit's melee attacks have") is not a condition
  t = t.replace(/\b(this|your) (unit|model)’?s?\b/gi, ' ');
  if (UNKNOWN_CONDITION.test(t)) c.unknown = true;
  return c;
}

/** Are the parsed conditions met right now? (null = cannot tell → treat as no) */
export function conditionsMet(c, ctx) {
  if (!c) return true;
  if (c.unknown) return false;
  if (c.charged && !ctx.charged) return false;
  if (c.stationary && !ctx.stationary) return false;
  if (c.halfRange && !ctx.halfRange) return false;
  if (c.leading && !ctx.leading) return false;
  const own = new Set((ctx.attackerKeywords ?? []).map(k => k.toUpperCase()));
  if (c.selfKw?.length && !c.selfKw.every(k => own.has(k))) return false;
  const kws = new Set((ctx.targetKeywords ?? []).map(k => k.toUpperCase()));
  if (c.targetKw.length && !c.targetKw.some(k => kws.has(k))) return false;
  if (c.targetNotKw.length && c.targetNotKw.some(k => kws.has(k))) return false;
  return true;
}

export function describeConditions(c) {
  if (!c) return '';
  const out = [];
  if (c.charged) out.push('charged');
  if (c.stationary) out.push('stationary');
  if (c.halfRange) out.push('half range');
  if (c.leading) out.push('while leading');
  if (c.targetKw.length) out.push(`vs ${c.targetKw.join('/')}`);
  if (c.targetNotKw.length) out.push(`not vs ${c.targetNotKw.join('/')}`);
  if (c.unknown) out.push('situational');
  return out.join(', ');
}

// ---------------------------------------------------------------------------
// Offensive effects

const OFFENSIVE_SUBJECT = new RegExp([
  `(this|your|that) (unit|model)${AP.source}?s? (melee |ranged )?(attacks|weapons)`,
  `weapons equipped by`,
  `units?${AP.source}? (melee |ranged )?attacks (have|can|gain)`,
  `(melee|ranged) attacks (have|can|gain)`,
  `models in (this|your|that) unit (have|gain)`,
  // older (10e-style) wording, still used by the index-card factions
  `each time an? (friendly [^,.]*?)?(model|unit)[^,.]*? makes an? (melee |ranged )?attack`,
  `each time (this|your) unit (shoots|fights)`,
].join('|'), 'i');

const KW_GRANTS = [
  [/^lethal hits$/i, () => ({ lethal: true }), 'Lethal Hits'],
  [/^sustained hits (\d)$/i, (m) => ({ sustained: Number(m[1]) }), (m) => `Sustained Hits ${m[1]}`],
  [/^devastating wounds$/i, () => ({ dev: true }), 'Devastating Wounds'],
  [/^lance$/i, () => ({ lance: true }), 'Lance'],
  [/^cleave (\d)$/i, (m) => ({ cleave: Number(m[1]) }), (m) => `Cleave ${m[1]}`],
  [/^ignores cover$/i, () => ({ ignoresCover: true }), 'Ignores Cover'],
  [/^precision$/i, () => ({ precision: true }), 'Precision'],
  [/^twin-linked$/i, () => ({ twin: true }), 'Twin-linked'],
  [/^rapid fire (\d)$/i, (m) => ({ rapidFire: Number(m[1]) }), (m) => `Rapid Fire ${m[1]}`],
];

/**
 * Offensive effects in an ability / stratagem effect text.
 * Returns { effects: [{label, apply}], phases, scope: 'unit'|'model', conds }
 * or null when the text grants nothing the engine can model.
 */
export function parseOffensive(text) {
  const full = norm(text);
  const t = firstOption(full);
  if (!OFFENSIVE_SUBJECT.test(t)) return null;
  // a debuff on enemies ("that enemy unit's attacks have -1 to hit") is not ours
  if (/(enemy|suppressed) unit/i.test(t) && /-\d to hit/i.test(t)) return null;
  const effects = [];
  const add = (label, apply) => effects.push({ label, apply });
  let m;
  const scanAll = (re, fn) => { re.lastIndex = 0; let x; while ((x = re.exec(t))) fn(x); };

  if ((m = t.match(/\+(\d) to hit rolls?/i) || t.match(/add (\d) to the hit roll/i))) add(`+${m[1]} to hit`, { hitMod: Number(m[1]) });
  if ((m = t.match(/\+(\d) to wound rolls?/i) || t.match(/add (\d) to the wound roll/i))) add(`+${m[1]} to wound`, { woundMod: Number(m[1]) });
  if (/re-roll (?:a |the )?hit rolls? of 1/i.test(t)) add('Re-roll hit 1s', { rerollHits: 'ones' });
  else if (/re-roll (the |their |a )?hit rolls?\b/i.test(t) && !/re-roll one hit roll/i.test(t)) add('Re-roll hits', { rerollHits: 'fail' });
  if (/re-roll (?:a |the )?wound rolls? of 1/i.test(t)) add('Re-roll wound 1s', { rerollWounds: 'ones' });
  else if (/re-roll (the |their |a )?wound rolls?\b/i.test(t) && !/re-roll one wound roll/i.test(t)) add('Re-roll wounds', { rerollWounds: 'fail' });
  // older wording: "improve the Armour Penetration characteristic of that attack by 1", "add 1 to the Strength characteristic"
  if ((m = t.match(/improve the Armour Penetration characteristic of (?:that|the|those) attacks? by (\d)/i))) add(`+${m[1]} AP`, { apMod: Number(m[1]) });
  scanAll(/add (\d) to the (Strength|Attacks|Damage) characteristic/gi, (x) => {
    const v = Number(x[1]);
    const stat = x[2].toLowerCase();
    if (stat === 'strength') add(`+${v} S`, { strengthMod: v });
    if (stat === 'attacks') add(`+${v} A`, { attacksMod: v });
    if (stat === 'damage') add(`+${v} D`, { damageMod: v });
  });
  // "+1 S", "+1 S and AP", "+2 S, AP and D", bullets "• +1 D."
  scanAll(/\+(\d)\s+((?:S|A|AP|D)(?:\s*(?:,|and)\s*(?:S|A|AP|D))*)\b(?!\w)/g, (x) => {
    const v = Number(x[1]);
    for (const stat of x[2].split(/\s*(?:,|and)\s*/)) {
      if (stat === 'S') add(`+${v} S`, { strengthMod: v });
      if (stat === 'A') add(`+${v} A`, { attacksMod: v });
      if (stat === 'AP') add(`+${v} AP`, { apMod: v });
      if (stat === 'D') add(`+${v} D`, { damageMod: v });
    }
  });
  // critical thresholds
  if ((m = t.match(/(?:critical hits? on (?:a |an )?(?:unmodified )?(?:hit roll of )?|unmodified hit rolls? of )(\d)\+/i))) add(`Crit hits ${m[1]}+`, { critHit: Number(m[1]) });
  if ((m = t.match(/(?:critical wounds? on (?:a |an )?(?:unmodified )?(?:wound roll of )?|unmodified wound rolls? of )(\d)\+/i))) add(`Crit wounds ${m[1]}+`, { critWound: Number(m[1]) });
  // [KEYWORDS] incl. target-restricted "[Lethal Hits: non-MONSTER/VEHICLE]"
  const kwConds = { targetKw: [], targetNotKw: [] };
  scanAll(/\[([^\]]+)\]/g, (x) => {
    const [kwRaw, restrict] = x[1].split(':').map(s => s.trim());
    for (const [re, apply, label] of KW_GRANTS) {
      const mm = kwRaw.match(re);
      if (!mm) continue;
      add(typeof label === 'function' ? label(mm) : label, apply(mm));
      if (restrict) {
        if (/^non-/i.test(restrict)) kwConds.targetNotKw.push(...kwList(restrict.replace(/^non-/i, '')));
        else kwConds.targetKw.push(...kwList(restrict));
      }
    }
  });
  if (!effects.length) return null;
  const conds = parseConditions(t);
  conds.targetKw.push(...kwConds.targetKw);
  conds.targetNotKw.push(...kwConds.targetNotKw);
  // weapon-specific wording ("Lightning Claws weapons have ...") is not modelled per weapon
  if (/\b[A-Z][\w’-]*(?: [A-Z][\w’-]*)* weapons (have|gain)\b/.test(t) && !/(melee|ranged) weapons/i.test(t)) conds.unknown = true;
  const scope = /\bthis model’?s\b/i.test(t) && !/\bthis unit’?s\b/i.test(t) ? 'model' : 'unit';
  return { effects, phases: phasesOf(t), scope, conds, partial: full.length !== t.length };
}

// ---------------------------------------------------------------------------
// Defensive effects (target side)

/**
 * Parse defensive effects from one ability's / stratagem's text. Returns
 * [{label, apply, phases}] where apply patches the defender mods (unit
 * scope) or the group (InSv / dr / fnp).
 */
export function parseDefensiveText(text) {
  const t = norm(text);
  const out = [];
  const rangedOnly = /\branged attacks that target\b/i.test(t);
  const meleeOnly = /\bmelee attacks that target\b/i.test(t);
  const phases = rangedOnly ? ['shooting'] : meleeOnly ? ['fight'] : ['shooting', 'fight'];
  const targetsUs = /(that )?targets? (this|your) (unit|model)/i;
  let m;
  if ((m = t.match(/(\d)\+\s*InSv/i)) || (m = t.match(/(\d)\+\s*invulnerable save/i))) {
    out.push({ label: `${m[1]}+ invulnerable save`, apply: { InSv: Number(m[1]) }, phases });
  }
  const fnpRe = /Feel No Pain (\d)\+( against ([^.•;]+))?/gi;
  while ((m = fnpRe.exec(t))) {
    const against = (m[3] ?? '').toLowerCase();
    const v = Number(m[1]);
    if (against.includes('mortal') && against.includes('psychic')) out.push({ label: `FNP ${v}+ vs psychic & mortal wounds`, apply: { fnpMortal: v, fnpPsychic: v }, phases });
    else if (against.includes('mortal')) out.push({ label: `FNP ${v}+ vs mortal wounds`, apply: { fnpMortal: v }, phases });
    else if (against.includes('psychic')) out.push({ label: `FNP ${v}+ vs psychic attacks`, apply: { fnpPsychic: v }, phases });
    else out.push({ label: `Feel No Pain ${v}+`, apply: { fnp: v }, phases });
  }
  if (/\bhave -1 D\b|-1 Damage\b|subtract 1 from the Damage/i.test(t)) out.push({ label: '-1 Damage', apply: { dr: 1 }, phases });
  if (/halve the D(amage)?\b/i.test(t)) out.push({ label: 'Halve Damage', apply: { dr: 'half' }, phases });
  if (/(-1 to wound rolls|subtract 1 from the wound roll)/i.test(t) && targetsUs.test(t)) {
    if (/S greater than (this|your) (unit|model).s T|Strength .* greater than .* Toughness/i.test(t)) out.push({ label: '-1 to wound if S > T', apply: { woundModIfSGreaterT: -1 }, phases });
    else out.push({ label: '-1 to wound', apply: { woundMod: -1 }, phases });
  }
  if (/(-1 to hit rolls|subtract 1 from the hit roll)/i.test(t) && targetsUs.test(t)) out.push({ label: '-1 to hit', apply: { hitMod: -1 }, phases });
  if (/that target (this|your) (unit|model) have -1 AP/i.test(t) || (/worsen the Armour Penetration characteristic of that attack by 1/i.test(t) && targetsUs.test(t))) out.push({ label: '-1 AP (incoming)', apply: { apReduce: 1 }, phases });
  if (/\bStealth\b/.test(t) && !/cannot have the benefit/i.test(t)) out.push({ label: 'Stealth (cover vs ranged)', apply: { cover: true }, phases: ['shooting'] });
  if (/(this|your) unit has the benefit of cover/i.test(t)) out.push({ label: 'Benefit of cover', apply: { cover: true }, phases: ['shooting'] });
  return out;
}

// ---------------------------------------------------------------------------
// Stratagems

/** 'attack' | 'defend' | null — from the WHEN line. */
export function stratagemRole(s) {
  const w = norm(s.when);
  if (/enemy unit (targets|has selected|selects)[^.]*friendly/i.test(w) || /targets? a friendly/i.test(w)) return 'defend';
  if (/friendly[^.]*is selected to (shoot|fight|attack)/i.test(w) || /selected to (shoot|fight)/i.test(w)) return 'attack';
  // older wording: "Your Shooting phase or the Fight phase." + the effect says who it helps
  const e = norm(s.effect);
  const tg = norm(s.target);
  if (/enemy unit has selected its targets|selected as the target of/i.test(`${w} ${tg}`) || /(an attack|attacks?) (that )?targets? (this|your) unit/i.test(e)) return 'defend';
  if (OFFENSIVE_SUBJECT.test(e)) return 'attack';
  return null;
}

/** Calculator phases a stratagem can be used in. */
export function stratagemPhases(s) {
  const p = String(s.phase ?? '').toLowerCase();
  const out = [];
  if (p.includes('shooting') || p.includes('any')) out.push('shooting');
  if (p.includes('fight') || p.includes('any')) out.push('fight');
  return out;
}

// Can `phrase` ("ORKS VEHICLE", "ADEPTUS ASTARTES MOUNTED/SPEEDER",
// "Blood Claws/Thunderwolf Cavalry/Wulfen") be read as keywords the unit has?
// "/" is ambiguous in print (between whole keywords, or between single words),
// so either reading is accepted.
function segmentMatches(phrase, kws) {
  const words = phrase.toUpperCase().split(/\s+/).filter(Boolean);
  const memo = new Map();
  const seg = (i) => {
    if (i >= words.length) return true;
    if (memo.has(i)) return memo.get(i);
    let ok = false;
    for (let j = i + 1; j <= words.length && !ok; j++) {
      const chunk = words.slice(i, j);
      const alts = chunk.length === 1 ? chunk[0].split('/') : [chunk.join(' ')];
      if (alts.some(a => kws.has(a)) && seg(j)) ok = true;
    }
    memo.set(i, ok);
    return ok;
  };
  return seg(0);
}

export function keywordPhraseMatches(phrase, unitKeywords) {
  const kws = new Set(unitKeywords.map(k => k.toUpperCase()));
  const p = String(phrase ?? '').trim();
  if (!p) return true;
  if (segmentMatches(p, kws)) return true;
  return p.includes('/') && p.split('/').some(alt => segmentMatches(alt, kws));
}

/** Does the WHEN line's "friendly X unit (excluding Y units)" fit this unit? */
export function stratagemEligible(s, unitKeywords) {
  const w = norm(s.when);
  let m = w.match(/friendly (?:attached |unengaged |engaged )*((?:[A-Za-z’'-]+(?:\/| )?)*?)\s*unit\b(?:\s*\(excluding ([^)]+?) units?\))?/i);
  if (!m) {
    // older wording: "TARGET: One NECRONS unit from your army ..." / "One Cryptek Infantry unit from your army"
    m = norm(s.target).match(/^One (?:or more )?(?:unengaged |engaged |attached |other )*((?:[A-Za-z’'-]+(?:\/| )?)*?)\s*(?:unit|model)s? (?:\(excluding ([^)]+?) (?:units?|models?)\) )?from your army/i);
    if (!m) return true;
  }
  if (!keywordPhraseMatches(m[1] ?? '', unitKeywords)) return false;
  if (m[2] && keywordPhraseMatches(m[2], unitKeywords)) return false;
  return true;
}
