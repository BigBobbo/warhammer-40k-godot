// "What does my army do, and when?" - an army's abilities, detachment rules,
// stratagems and core abilities sorted by the phase they are used in.
//
// The phase is read from the rule's own words ("In your Command phase ...",
// "this unit's melee attacks ...", a stratagem's phase and turn). The rules
// data also has phase mappings by ability id (40kdc phaseMappings,
// provisional): they are the fall-back when the words say nothing.
//
// Pure module (no DOM, no dataset), unit-tested on the real texts of the
// fixture lists (tests/calc-phasesheet.test.mjs).

export const PHASES = [
  { id: 'before', name: 'Before the battle', short: 'Before', hint: 'deployment, reserves, pre-battle moves' },
  { id: 'command', name: 'Command phase', short: 'Command' },
  { id: 'movement', name: 'Movement phase', short: 'Move' },
  { id: 'shooting', name: 'Shooting phase', short: 'Shoot' },
  { id: 'charge', name: 'Charge phase', short: 'Charge' },
  { id: 'fight', name: 'Fight phase', short: 'Fight' },
  { id: 'enemy', name: 'In the opponent’s turn', short: 'Opp. turn', hint: 'reactions, and what protects your units when they are attacked' },
  { id: 'always', name: 'Always on / any time', short: 'Always' },
];
const ORDER = PHASES.map(p => p.id);
const TURN = ['command', 'movement', 'shooting', 'charge', 'fight'];

// one kind of apostrophe, single spaces
const norm = (t) => String(t ?? '').replace(/\s+/g, ' ').replace(/[‘’ʼ`]/g, "'").trim();

// Conditions and durations that name a phase the rule is NOT used in: taken out before the words are read.
const CHARGED = /\b(if|while) (this|your|that|the bearer's) (unit|model) (has )?made a charge move this turn,?|\bthat (has )?made a charge move this turn\b|\bif (this|your) (unit|model) charged this turn,?/gi;
const NOT_A_PHASE = [
  /\b(if|while) (this|your|that|the bearer's) (unit|model) (has )?made an? (advance|normal|fall[- ]back|ingress|surge) move this turn,?/gi,
  /\bthat (has )?made an? (advance|normal|fall[- ]back|ingress|surge) move this turn\b/gi,
  /\bif (this|your) (unit|model) (remained stationary|advanced|fell back) this turn,?/gi,
  /\buntil the (start|end) of (your|the|your opponent's) (next )?(command|movement|shooting|charge|fight) phase\b/gi,
  /\buntil the (start|end) of (your|the|your opponent's) (next )?turn\b/gi,
  /\buntil the end of the (phase|turn|battle round)\b/gi,
];
// "attacks that target this unit ...": the opponent's attack, not this unit's (the sentence is taken out before
// the words "ranged" and "melee" are read as this unit's own shooting and fighting)
const TARGETS_ME = /\b(each time )?(an? |any )?(ranged |melee )?attacks? (that )?(targets?|(is|are) allocated to|(is|are) made against) (this|your|a friendly|friendly|the bearer's)\b[^.•]*/gi;

const BY_WORDS = [
  ['before', /\bduring deployment\b|\bdeclare battle formations\b|\bdeploy armies\b|\bmuster armies\b|\bbefore the battle\b|\bat the start of the battle\b(?! round)|\bbefore the first (battle round|turn)\b|\bscout moves?\b|\bredeploy\b|\bpre-battle\b/i],
  ['command', /\bcommand phase\b|\bbattle-shock (tests?|rolls?)\b|\bgains? \d ?CP\b|\bselect (one|the|a|an) (\w+ )?doctrine\b|\bat the start of the battle round\b/i],
  ['movement', /\bmovement phase\b|\b(normal|advance|fall[- ]back|ingress|surge)(\/[\w-]+)* moves?\b|\badvance rolls?\b|\bstrategic reserves\b|\bdisembark|\bembark|\+\d+" M\b|\bM characteristic\b/i],
  ['shooting', /\bshooting phase\b|\branged (attacks?|weapons?)\b|\b(is|are) selected to shoot\b|\bhas shot\b|\bshoots?\b|\bBS characteristic\b/i],
  ['charge', /\bcharge phase\b|\bcharge rolls?\b|\bcharge moves?\b|\bdeclares? a charge\b|\beligible to (declare a )?charge\b/i],
  ['fight', /\bfight phase\b|\bmelee (attacks?|weapons?)\b|\b(is|are) selected to fight\b|\bhas fought\b|\bfights?\b|\bpile[- ]in\b|\bconsolidat|\bWS characteristic\b/i],
  ['always', /\b(each|every|any) phase\b/i],
];
// attacks of both kinds
const ANY_ATTACK = /\b(this|your|that|the bearer's) (unit|model)'s attacks\b|\beach time (this|a|an)[^.]*makes an attack\b|\battacks made by\b|\bweapons? (equipped by [^.]*?)?(have|has|gains?) \[/i;
// what protects the unit
const DEFENCE = /\binvulnerable save\b|\bInSv\b|\bFeel No Pain\b|\bFNP\b|\bbenefit of cover\b|\bcannot be targeted\b|\b(this|a friendly|the bearer's) (unit|model) is destroyed\b|\bhas -\d D\b|\bhave -\d D\b|\bwould lose a wound\b/i;
// a rule timed in the opponent's turn
const OPP_PHASE = /\b(your )?opponent's (command|movement|shooting|charge|fight) phase\b/i;
const OPP_PHASE_G = new RegExp(OPP_PHASE.source, 'gi');
// what answers the enemy
const ENEMY_TURN = /\b(your )?opponent's (turn|command|movement|shooting|charge|fight)\b|\b(when|after|each time|just after) an enemy unit\b|\benemy unit (ends|is set up|declares|shoots|has shot|has fought|targets|selects|makes)\b/i;

/**
 * The phases a rule is used in, from its words -> phase ids in turn order ([] = the words do not say).
 */
export function phasesOfText(text) {
  let t = norm(text).replace(/\bExample: [^.]*\./gi, ' ');      // an example names phases and effects of other rules
  const out = new Set();
  // "In your opponent's Shooting phase, when an enemy unit has shot ... this unit can make a surge move":
  // a rule for their turn. Only a phase of your own turn that it names in words ("your Movement phase") is added.
  if (OPP_PHASE.test(t)) {
    const rest = t.replace(OPP_PHASE_G, ' ');
    out.add('enemy');
    for (const id of TURN) if (new RegExp(`\\b(in|during|of) (your|the) ${id} phase\\b`, 'i').test(rest)) out.add(id);
    for (const [id, re] of BY_WORDS) if ((id === 'before' || id === 'always') && re.test(rest)) out.add(id);
    return ORDER.filter(id => out.has(id));
  }
  if (CHARGED.test(t)) out.add('fight');         // after a charge move the only phase left in the turn is the Fight phase
  CHARGED.lastIndex = 0;
  t = t.replace(CHARGED, ' ');
  for (const re of NOT_A_PHASE) t = t.replace(re, ' ');
  const mine = t.replace(TARGETS_ME, ' ');
  const attacked = mine !== t;
  for (const [id, re] of BY_WORDS) if (re.test(mine)) out.add(id);
  if (ANY_ATTACK.test(mine) && !out.has('shooting') && !out.has('fight')) { out.add('shooting'); out.add('fight'); }
  if (attacked || ENEMY_TURN.test(t) || (DEFENCE.test(t) && !out.has('shooting') && !out.has('fight'))) out.add('enemy');
  return ORDER.filter(id => out.has(id));
}

/** A rule's text for reading: its own line breaks, and a heading in capitals set off from the sentence after it. */
function display(text) {
  return String(text ?? '').replace(/\r/g, '').replace(/[ \t]+/g, ' ').replace(/ ?\n ?/g, '\n').replace(/\n{2,}/g, '\n')
    .replace(/\b([A-Z][A-Z'’-]+(?: [A-Z][A-Z'’-]+)+)(?=[A-Z][a-z])/g, '$1: ').trim();
}

/** How often a rule can be used, from its words -> { per: 'battle'|'round'|'turn'|'phase', uses } | null */
export function usageOf(text) {
  const t = norm(text);
  const n = { once: 1, twice: 2, 'three times': 3 };
  let m;
  if ((m = /\b(once|twice|three times) per battle round\b/i.exec(t))) return { per: 'round', uses: n[m[1].toLowerCase()] };
  if ((m = /\b(once|twice|three times) per battle\b/i.exec(t))) return { per: 'battle', uses: n[m[1].toLowerCase()] };
  if ((m = /\b(once|twice) per turn\b/i.exec(t))) return { per: 'turn', uses: n[m[1].toLowerCase()] };
  if ((m = /\b(once|twice) per phase\b/i.exec(t))) return { per: 'phase', uses: n[m[1].toLowerCase()] };
  return null;
}
export function usageLabel(u) {
  if (!u) return '';
  const times = ['', 'once', 'twice', 'three times'][u.uses] ?? `${u.uses} times`;
  return `${times} per ${u.per === 'round' ? 'battle round' : u.per}`;
}

/**
 * A stratagem's place on the sheet, from its `turn`, its WHEN line and its `phase`.
 * The phase lists are the phases of YOUR turn; "In the opponent's turn" has what can be used in theirs.
 *  - opponent's turn only: "In the opponent's turn" (its phase is in the line)
 *  - your turn: its phase(s)
 *  - either player's turn: its phase(s) in your turn and "In the opponent's turn". The WHEN line can narrow that:
 *    "Your opponent's Shooting phase or the Fight phase" is not used in your own Shooting phase.
 *  - any phase: "Always on / any time"
 */
export function stratagemPhases(st) {
  const ph = norm(st.phase).toLowerCase();
  const turn = norm(st.turn).toLowerCase();
  const named = TURN.filter(id => ph.includes(id));
  if (/opponent/.test(turn) && !/either/.test(turn)) return ['enemy'];
  if (!named.length) return ['always'];
  if (!/either/.test(turn)) return named;
  const mine = new Set();
  let theirs = false, any = false;
  for (const m of norm(st.when).toLowerCase().matchAll(/((?:your )?opponent's |your )?(command|movement|shooting|charge|fight) phase/g)) {
    any = true;
    if (/opponent/.test(m[1] ?? '')) theirs = true;
    else { mine.add(m[2]); if (!m[1]) theirs = true; }
  }
  if (!any) { for (const id of named) mine.add(id); theirs = true; }
  const out = new Set([...mine, ...(theirs ? ['enemy'] : [])]);
  return ORDER.filter(id => out.has(id));
}

/**
 * The choices of a rule that can each be used once per battle ("You can only select each combat doctrine once per
 * battle"): the headings written in capitals in its text (ASSAULT DOCTRINE, DEVASTATOR DOCTRINE, ...). [] = none.
 */
export function optionsOf(text) {
  const t = String(text ?? '').replace(/[‘’ʼ`]/g, "'");
  if (!/\beach [\w' -]+? once per battle\b/i.test(t)) return [];
  const out = [];
  for (const m of t.matchAll(/(?:^|[^A-Za-z])([A-Z][A-Z'-]+(?: [A-Z][A-Z'-]+)+)(?=[A-Z][a-z]|\s*:|\s*\n)/g)) {
    const name = m[1].toLowerCase().replace(/^\w/, c => c.toUpperCase());
    if (!out.includes(name)) out.push(name);
  }
  return out;
}

/** Core abilities as sheet entries. flags: adapter coreFlags + { fnp }. */
function coreEntries(flags) {
  const f = flags ?? {};
  const out = [];
  const add = (phases, name, text) => out.push({ phases, name, text });
  if (f.infiltrators) add(['before'], 'Infiltrators', 'During deployment: set up anywhere more than 8" from the enemy deployment zone and all enemy units (24.20).');
  if (f.scouts) add(['before'], `Scouts ${f.scouts}"`, `Before the first turn: a Scout move of up to ${f.scouts}" if the unit is wholly within your deployment zone; it must end more than 8" from enemy units (24.32).`);
  if (f.deepStrike) {
    add(['before'], 'Deep Strike', 'Can start the battle in reserves instead of on the battlefield (declare it before the battle).');
    add(['movement'], 'Deep Strike', 'From battle round 2, in your Movement phase: set up anywhere more than 8" from all enemy units, the enemy deployment zone included (24.09). A unit still in reserves at the end of battle round 3 is destroyed.');
  }
  if (f.firingDeck) add(['shooting'], `Firing Deck ${f.firingDeck}`, `Up to ${f.firingDeck} embarked models each lend one ranged weapon to this transport when it shoots (24.14).`);
  if (f.fightsFirst) add(['fight'], 'Fights First', 'Fights in the Fights First step, before units without it (12.04).');
  if (f.loneOperative) add(['enemy'], 'Lone Operative', `Cannot be seen by enemy models that are more than ${f.loneOperative}" away (24.24). Not while it is part of an attached unit.`);
  if (f.stealth) add(['enemy'], 'Stealth', 'Has the benefit of cover against ranged attacks: the attacker’s BS is worse by 1 (24.33).');
  if (f.fnp) add(['enemy'], `Feel No Pain ${f.fnp}+`, `Each time a model would lose a wound, roll a D6: on a ${f.fnp}+ that wound is not lost (24.12).`);
  if (f.deadlyDemise) add(['enemy'], `Deadly Demise ${f.deadlyDemise}`, `When a model is destroyed, roll a D6: on a 6, each unit within 6" suffers ${f.deadlyDemise} mortal wound${f.deadlyDemise === '1' ? '' : 's'} (24.08).`);
  if (f.damaged) add(['always'], `Damaged ${f.damaged}`, `At ${f.damaged} wounds or fewer: -1 to hit rolls (24.39).`);
  return out;
}

/**
 * The sheet.
 * input: {
 *   units: [{ id, name, flags, abilities: [{ id, name, text, type, owner: { id, name } }] }],
 *   detachmentRules: [{ id, name, text }],
 *   stratagems: [{ id, name, cp, phase, turn, when, target, effect, detachment, missing }],
 *   mapped: (id, type) => ['shooting', ...] | null      // phase mapping by id from the rules data (fall-back)
 * }
 * -> { phases: [{ id, name, short, hint, entries: [entry] }], once: [entry], count }
 * entry: { key, kind, name, text (one line), raw (as written, for reading), units: [{ id, name, unit }], all (every unit of the army has it), usage, by,
 *          options: [{ name, extra: [rule names] }] (choices that are each once per battle),
 *          cp, turn, phaseText, when, target, effect, detachment, missing (stratagems) }
 * kind: 'army' (the army rule and the detachment rules), 'ability', 'core', 'stratagem'.
 * by: 'text' (the phase is in the rule's words), 'data' (from the rules data's phase mapping), 'rule' (a core rule),
 *     'none' (nothing says when: listed under "Always on / any time").
 * The same rule on several units is one entry with the units listed. `once`: the once-per-battle entries (ticks).
 */
export function phaseSheet(input) {
  const byPhase = new Map(PHASES.map(p => [p.id, new Map()]));
  const entries = new Map();
  const nUnits = (input.units ?? []).length;
  const put = (phases, e, owner) => {
    const k = `${e.kind}|${e.name}|${e.text}`;
    let ent = entries.get(k);
    if (!ent) { ent = { ...e, raw: display(e.raw ?? e.text), units: [], phases: phases.length ? phases : ['always'] }; entries.set(k, ent); }
    if (owner && !ent.units.some(u => u.id === owner.id)) ent.units.push(owner);
    for (const ph of ent.phases) byPhase.get(ph).set(k, ent);
  };
  const mapped = (id, type) => (input.mapped?.(id, type) ?? []).filter(p => ORDER.includes(p));
  const place = (text, id, type) => {
    const words = phasesOfText(text);
    if (words.length) return { phases: words, by: 'text' };
    const data = mapped(id, type);
    return data.length ? { phases: data, by: 'data' } : { phases: [], by: 'none' };
  };
  for (const d of input.armyRules ?? []) {
    const p = place(d.text, d.id, 'ability');
    put(p.phases, { key: `army:${d.id}`, kind: 'army', name: d.name, text: norm(d.text), raw: d.text, usage: usageOf(d.text), options: optionsOf(d.text).map(name => ({ name, extra: [] })), by: p.by, armyRule: true });
  }
  for (const d of input.detachmentRules ?? []) {
    const p = place(d.text, d.id, 'detachment-rule');
    put(p.phases, { key: `det:${d.id}`, kind: 'army', name: d.name, text: norm(d.text), raw: d.text, usage: usageOf(d.text), by: p.by });
  }
  for (const u of input.units ?? []) {
    for (const a of u.abilities ?? []) {
      const p = place(a.text, a.id, a.type === 'enhancement' ? 'enhancement' : 'ability');
      const kind = a.type === 'faction' ? 'army' : 'ability';
      put(p.phases, { key: `ab:${a.id}`, kind, name: a.name, text: norm(a.text), raw: a.text, usage: usageOf(a.text), by: p.by }, a.owner ?? { id: u.id, name: u.name, unit: u.name });
    }
    for (const c of coreEntries(u.flags)) put(c.phases, { key: `core:${c.name}:${c.phases[0]}`, kind: 'core', name: c.name, text: c.text, usage: null, by: 'rule' }, { id: u.id, name: u.name, unit: u.name });
  }
  for (const st of input.stratagems ?? []) {
    put(stratagemPhases(st), { key: `st:${st.id}`, kind: 'stratagem', name: st.name, cp: st.cp, turn: norm(st.turn), detachment: st.detachment, phaseText: norm(st.phase),
      when: norm(st.when), target: norm(st.target), effect: norm(st.effect), missing: !!st.missing,
      text: st.missing ? '' : norm(`${st.when} ${st.target} ${st.effect}`), usage: usageOf(`${st.effect} ${st.restrictions ?? ''}`), by: 'text' });
  }
  for (const e of entries.values()) e.all = nUnits > 1 && new Set(e.units.map(u => u.unit)).size === nUnits;
  // "You can select the assault doctrine one additional time per battle": one more use of that choice
  for (const e of entries.values()) {
    const m = /\bselect the ([a-z' -]+?) one additional time per battle\b/i.exec(e.text);
    if (!m) continue;
    for (const o of entries.values()) for (const opt of o.options ?? []) if (opt.name.toLowerCase() === m[1].toLowerCase()) opt.extra.push(e.name);
  }
  const kindOrder = { army: 0, ability: 1, core: 2, stratagem: 3 };
  const when = (e) => { const i = TURN.findIndex(id => (e.phaseText ?? '').toLowerCase().includes(id)); return i < 0 ? 9 : i; };
  const sort = (a, b) => kindOrder[a.kind] - kindOrder[b.kind] || (a.armyRule ? 0 : 1) - (b.armyRule ? 0 : 1) || (a.kind === 'stratagem' ? when(a) - when(b) : 0) || a.name.localeCompare(b.name);
  const phases = PHASES.map(p => ({ ...p, entries: [...byPhase.get(p.id).values()].sort(sort) }));
  const once = [...entries.values()].filter(e => e.usage?.per === 'battle').sort(sort);
  return { phases, once, count: entries.size };
}

/**
 * The ticks of a once-per-battle entry: one per choice when the rule has choices that are each once per battle
 * (and one more for each rule that gives an additional use), else one per unit that has it (or one for the
 * army), times its uses.
 */
export function ticksOf(entry) {
  if (entry.options?.length) {
    return entry.options.flatMap(o => [{ id: `${entry.key}|${o.name}|0`, label: o.name }, ...o.extra.map((x, i) => ({ id: `${entry.key}|${o.name}|${i + 1}`, label: `${o.name} (${x.replace(/ \([^()]*\)$/, '')})` }))]);
  }
  const uses = entry.usage?.uses ?? 1;
  const owners = entry.units.length && !entry.all ? entry.units : [{ id: 'army', name: '' }];
  const dup = (n) => owners.filter(o => o.name === n).length > 1;
  const out = [];
  for (const o of owners) for (let i = 0; i < uses; i++) out.push({ id: `${entry.key}|${o.id}|${i}`, label: (dup(o.name) ? o.unit : o.name) + (uses > 1 ? ` ${i + 1}` : '') });
  return out;
}
