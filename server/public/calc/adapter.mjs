// Army adapter for the combat calculator: pasted list text -> combat units
// (attached Leaders/Support merged into their Bodyguard), attacker weapon
// rows and defender profiles/rules for engine.mjs.
//
// Reuses the Army Builder's importer and patched 40kdc dataset (store.js /
// importers.js), so every list format the builder accepts works here too.

import { conv, factionName, dc } from '../js/builder/store.js';
import { importText } from '../js/builder/importers.js';
import { normName, looseName } from '../js/lib/dckit.mjs';
import { expectedDamageQuick } from './engine.mjs';

export const DATASET_VERSION = dc.DATASET_VERSION;

// ---------------------------------------------------------------------------
// Import

export function importArmy(text) {
  const { roster, report } = importText(text);
  const units = combatUnits(roster);
  const unresolved = (roster.units ?? []).filter(u => !u.ref?.id).map(u => u.ref?.raw_name ?? '?');
  return {
    roster,
    faction: roster.faction_id ? factionName(roster.faction_id) : 'Unknown faction',
    name: roster.name || 'Army',
    units,
    warnings: [...(report?.warnings ?? []), ...unresolved.map(n => `unit not recognised: ${n}`)],
  };
}

function resolveUnit(roster, ru) {
  if (!ru.ref?.id) return null;
  const found = conv.findUnitById(roster.faction_id, ru.ref.id);
  return found ? { dcUnit: found.unit, factionId: found.factionId } : null;
}

function isCharacter(dcUnit) {
  return (dcUnit.keywords ?? []).some(k => /^character$/i.test(k));
}

/** Roster -> combat units. A bodyguard and the leaders attached to it are one unit. */
export function combatUnits(roster) {
  const parts = [];
  (roster.units ?? []).forEach((ru, i) => {
    const r = resolveUnit(roster, ru);
    if (r) parts.push({ index: i, ru, ...r });
  });
  const taken = new Set();
  const attachedTo = new Map(); // bodyguard index -> [leader parts]
  for (const p of parts) {
    const bgId = p.ru.leader_attachment?.bodyguard_ref?.id;
    if (!bgId) continue;
    const bg = parts.find(q => q.ru.ref.id === bgId && q !== p && !q.ru.leader_attachment &&
      !(attachedTo.get(q.index) ?? []).some(l => (l.ru.leader_attachment?.role ?? 'leader') === (p.ru.leader_attachment?.role ?? 'leader')));
    if (!bg) continue;
    if (!attachedTo.has(bg.index)) attachedTo.set(bg.index, []);
    attachedTo.get(bg.index).push(p);
    taken.add(p.index);
  }
  const seen = new Map();
  const out = [];
  for (const p of parts) {
    if (taken.has(p.index)) continue;
    const leaders = attachedTo.get(p.index) ?? [];
    const members = [...leaders.map(l => ({ ...l, role: 'leader' })), { ...p, role: leaders.length ? 'bodyguard' : 'single' }];
    const baseName = [...leaders.map(l => l.dcUnit.name), p.dcUnit.name].join(' + ');
    const n = (seen.get(baseName) ?? 0) + 1;
    seen.set(baseName, n);
    const keywords = new Set();
    for (const m of members) for (const k of [...(m.dcUnit.keywords ?? []), ...(m.dcUnit.faction_keywords ?? [])]) keywords.add(k.toUpperCase());
    out.push({
      key: `u${p.index}`,
      name: baseName + (n > 1 ? ` (${n})` : ''),
      members,
      keywords: [...keywords],
      models: members.reduce((s, m) => s + (m.ru.model_count ?? 1), 0),
      points: members.reduce((s, m) => s + (m.ru.points ?? 0), 0),
    });
  }
  // label duplicates "(1)" too once a "(2)" exists
  for (const u of out) if (seen.get(u.name) > 1) u.name += ' (1)';
  return out;
}

// ---------------------------------------------------------------------------
// Model groups (per member): [{modelName, count, profile, wargear: [{id, perModel}]}]

function profileFor(dcUnit, modelName) {
  const key = normName(modelName ?? '');
  return dcUnit.profiles.find(p => normName(p.name) === key) ??
    dcUnit.profiles.find(p => key.includes(normName(p.name)) || normName(p.name).includes(key)) ??
    dcUnit.profiles[0];
}

function modelGroups(member) {
  const { ru, dcUnit } = member;
  if ((ru.loadout_groups ?? []).length) {
    return ru.loadout_groups.map(g => ({
      modelName: g.model_name,
      count: g.count,
      profile: profileFor(dcUnit, g.model_name),
      wargear: (g.wargear ?? []).filter(w => w.ref?.id).map(w => ({ id: w.ref.id, perModel: w.count ?? 1 })),
    }));
  }
  const n = ru.model_count ?? 1;
  return [{
    modelName: dcUnit.name,
    count: n,
    profile: dcUnit.profiles[0],
    // unit-wide counts: spread as "count across the unit" (perModel = total / n)
    wargear: (ru.wargear ?? []).filter(w => w.ref?.id).map(w => ({ id: w.ref.id, perModel: (w.count ?? 1) / n })),
  }];
}

// ---------------------------------------------------------------------------
// Weapons

const SUPPORTED_KW = new Set([
  'torrent', 'lethal-hits', 'sustained-hits', 'devastating-wounds', 'twin-linked', 'blast', 'cleave',
  'rapid-fire', 'melta', 'heavy', 'lance', 'ignores-cover', 'indirect-fire', 'precision', 'hazardous',
  'psychic', 'anti', 'hunter', 'pistol', 'close-quarters', 'extra-attacks', 'one-shot', 'assault',
]);

export function weaponKw(keywords) {
  const kw = { anti: [] };
  const tags = [];
  const unsupported = [];
  let hunter = null;
  for (const k of keywords ?? []) {
    const p = k.parameters ?? {};
    const id = k.keyword_id;
    switch (id) {
      case 'torrent': kw.torrent = true; break;
      case 'lethal-hits': kw.lethal = true; break;
      case 'sustained-hits': {
        const v = p.value ?? 1;
        if (typeof v === 'string' && /^d\d+$/i.test(v)) { kw.sustained = parseInt(v.slice(1), 10); kw.sustainedDice = true; }
        else kw.sustained = Number(v) || 1;
        break;
      }
      case 'devastating-wounds': kw.dev = true; break;
      case 'twin-linked': kw.twin = true; break;
      case 'blast': kw.blast = Number(p.value ?? 1) || 1; break;
      case 'cleave': kw.cleave = Number(p.value ?? 1) || 1; break;
      case 'rapid-fire': kw.rapidFire = Number(p.value ?? 1) || 1; break;
      case 'melta': kw.melta = Number(p.value ?? 2) || 2; break;
      case 'heavy': kw.heavy = true; break;
      case 'lance': kw.lance = true; break;
      case 'ignores-cover': kw.ignoresCover = true; break;
      case 'indirect-fire': kw.indirect = true; break;
      case 'precision': kw.precision = true; break;
      case 'hazardous': kw.hazardous = true; break;
      case 'psychic': kw.psychic = true; break;
      case 'anti': kw.anti.push({ keyword: String(p.target_keyword ?? '').toUpperCase(), threshold: Number(p.threshold ?? 4) }); break;
      case 'hunter': hunter = String(p.target_keyword ?? '').toUpperCase(); break;
      case 'pistol': kw.pistol = true; break;
      case 'close-quarters': kw.cq = true; break;
      case 'extra-attacks': kw.extraAttacks = true; break;
      case 'one-shot': kw.oneShot = true; break;
      default: break;
    }
    const label = id === 'anti' ? `Anti-${String(p.target_keyword ?? '').toLowerCase()} ${p.threshold ?? 4}+`
      : id.replace(/-/g, ' ') + (p.value != null ? ` ${p.value}` : '') + (id === 'hunter' && p.target_keyword ? ` (${p.target_keyword})` : '');
    tags.push(label);
    if (!SUPPORTED_KW.has(id)) unsupported.push(label);
  }
  return { kw, tags, unsupported, hunter };
}

function weaponProfiles(factionId, weaponId) {
  const w = conv.wres.resolve(factionId, weaponId);
  if (!w) return [];
  return w.profiles.map((prof, pi) => {
    const melee = prof.range === 'Melee';
    const { kw, tags, unsupported, hunter } = weaponKw(prof.keywords);
    const skill = melee ? prof.stats.WS : prof.stats.BS;
    return {
      weaponId,
      profileIndex: pi,
      profileCount: w.profiles.length,
      name: w.profiles.length > 1 ? `${w.name} – ${prof.name}` : w.name,
      melee,
      range: melee ? 'Melee' : `${prof.range}"`,
      A: String(prof.stats.A),
      skill: skill == null || skill === 'N/A' ? null : Number(skill),
      S: Number(prof.stats.S),
      AP: Number(prof.stats.AP) || 0,
      D: String(prof.stats.D),
      kw, tags, unsupported, hunter,
    };
  });
}

function profileLine(p) {
  const sk = p.skill == null ? 'N/A' : `${p.skill}+`;
  return `A${p.A} ${p.melee ? 'WS' : 'BS'}${sk} S${p.S} AP${p.AP} D${p.D}`;
}

/**
 * Weapon rows for an attacking combat unit in `phase` ('shooting' | 'fight').
 * Each row: { id, label, member, profile..., max, count } — `count` is the
 * default number of weapons that attack (the player edits it).
 *
 * Defaults:
 *  - shooting: every ranged weapon fires; a non-MONSTER/VEHICLE model that has
 *    other ranged weapons leaves its PISTOL / CLOSE-QUARTERS weapons out
 *    (24.07 / 24.27 — one or the other); only the first profile of a
 *    multi-profile weapon is selected.
 *  - fight: per model, every EXTRA ATTACKS weapon plus the one other melee
 *    weapon (profile) with the best expected damage against `target`.
 */
export function attackerRows(cu, phase, target = null) {
  const rows = new Map();
  const T = target?.T ?? 4, Sv = target?.Sv ?? 3, InSv = target?.InSv ?? 0;
  const tgtKeywords = new Set(target?.keywords ?? []);
  const add = (member, p, max, count) => {
    const key = `${member.index}:${p.weaponId}:${p.profileIndex}`;
    const prev = rows.get(key);
    if (prev) { prev.max += max; prev.count += count; return; }
    const multi = cu.members.length > 1;
    const blocked = p.hunter && !tgtKeywords.has(p.hunter) ? `Hunter: only targets ${p.hunter}` : null;
    rows.set(key, {
      id: key,
      member: member.dcUnit.name,
      label: (multi && member.role === 'leader' ? `${member.dcUnit.name}: ` : '') + p.name,
      stats: profileLine(p),
      range: p.range,
      ...p,
      max,
      count,
      blocked,
    });
  };
  for (const member of cu.members) {
    const vm = (member.dcUnit.keywords ?? []).some(k => /^(monster|vehicle)$/i.test(k));
    for (const g of modelGroups(member)) {
      const profs = [];
      for (const wg of g.wargear) {
        for (const p of weaponProfiles(member.factionId, wg.id)) profs.push({ p, n: Math.round(wg.perModel * g.count) });
      }
      if (phase === 'shooting') {
        const ranged = profs.filter(x => !x.p.melee);
        const hasMain = ranged.some(x => !x.p.kw.pistol && !x.p.kw.cq);
        for (const { p, n } of ranged) {
          let on = p.profileIndex === 0;
          if (on && !vm && hasMain && (p.kw.pistol || p.kw.cq)) on = false;
          add(member, p, n, on ? n : 0);
        }
      } else {
        const melee = profs.filter(x => x.p.melee);
        const main = melee.filter(x => !x.p.kw.extraAttacks);
        let best = null, bestScore = -1;
        for (const x of main) {
          const s = expectedDamageQuick(x.p, T, Sv, InSv);
          if (s > bestScore) { bestScore = s; best = x; }
        }
        for (const x of melee) {
          const on = x.p.kw.extraAttacks || x === best;
          add(member, x.p, x.n, on ? x.n : 0);
        }
      }
    }
  }
  return [...rows.values()].filter(r => r.max > 0).map(r => (r.blocked ? { ...r, count: 0 } : r));
}

/** Weapon row -> engine weapon. */
export function engineWeapon(row) {
  return {
    name: row.label, count: row.count, melee: row.melee,
    A: row.A, skill: row.skill, S: row.S, AP: row.AP, D: row.D,
    kw: row.kw,
  };
}

export function allVehicleMonster(cu) {
  return cu.members.every(m => (m.dcUnit.keywords ?? []).some(k => /^(monster|vehicle)$/i.test(k)));
}

// ---------------------------------------------------------------------------
// Abilities (display) and defender rules (auto-detected, toggleable)

function abilityRecords(member) {
  const out = [];
  for (const aid of member.dcUnit.ability_ids ?? []) {
    const a = conv.ares.resolve(member.factionId, aid);
    if (!a) continue;
    out.push({ id: aid, name: a.name, type: a.ability_type, text: conv.safeDescribe(a), record: a });
  }
  const eid = member.ru.enhancement?.id ?? member.ru.enhancement?.ref?.id;
  if (eid) {
    const e = (dc.RAW_DATA.enhancements ?? []).find(x => x.id === eid);
    if (e) out.push({ id: eid, name: `${e.name} (enhancement)`, type: 'enhancement', text: e.rules_text ?? '', record: e });
  }
  return out;
}

export function abilitiesOf(cu) {
  const out = [];
  for (const m of cu.members) {
    for (const a of abilityRecords(m)) {
      if (a.type === 'detachment' || /^leader$/i.test(a.name)) continue;
      out.push({ member: m.dcUnit.name, name: a.name, type: a.type, text: a.text });
    }
  }
  return out;
}

// Activated / situational wording: detected but OFF by default.
const ACTIVATED_RE = /\b(you can|at the start of|until the end of|until the start of|when an enemy unit|when this unit|select|once per battle|first time|psychic roll|while this unit is within|while this model is within|within range of an objective|if this unit made|if this model made|battle-shocked|in your|in the (fight|shooting|movement|command) phase)\b/i;

/**
 * Parse defensive effects from one ability's rules text. Returns a list of
 * {label, apply, phases} where apply is a patch for the defender mods (unit
 * scope) or the group (model scope).
 */
export function parseDefensiveText(text) {
  const t = String(text ?? '').replace(/\s+/g, ' ');
  const out = [];
  const rangedOnly = /\branged attacks that target\b/i.test(t);
  const meleeOnly = /\bmelee attacks that target\b/i.test(t);
  const phases = rangedOnly ? ['shooting'] : meleeOnly ? ['fight'] : ['shooting', 'fight'];
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
  if (/-1 to wound rolls/i.test(t) && /that target this (unit|model)/i.test(t)) {
    if (/S greater than this (unit|model).s T|Strength .* greater than .* Toughness/i.test(t)) out.push({ label: '-1 to wound if S > T', apply: { woundModIfSGreaterT: -1 }, phases });
    else out.push({ label: '-1 to wound', apply: { woundMod: -1 }, phases });
  }
  if (/-1 to hit rolls/i.test(t) && /that target this (unit|model)/i.test(t)) out.push({ label: '-1 to hit', apply: { hitMod: -1 }, phases });
  if (/that target this (unit|model) have -1 AP/i.test(t)) out.push({ label: '-1 AP (incoming)', apply: { apReduce: 1 }, phases });
  if (/\bStealth\b/.test(t) && !/cannot have the benefit/i.test(t)) out.push({ label: 'Stealth (cover vs ranged)', apply: { cover: true }, phases: ['shooting'] });
  return out;
}

function parseStructured(a) {
  const e = a?.effect;
  if (!e || a.rules_text) return null;
  const permanent = (a.scope?.duration ?? 'permanent') === 'permanent';
  const out = [];
  const mod = e.modifier ?? {};
  const phases = mod.attack_type === 'ranged' ? ['shooting'] : mod.attack_type === 'melee' ? ['fight'] : ['shooting', 'fight'];
  if (e.type === 'feel-no-pain' && mod.threshold) {
    const v = Number(mod.threshold);
    const sc = String(mod.scope ?? mod.against_attack_type ?? '');
    if (sc === 'mortal') out.push({ label: `FNP ${v}+ vs mortal wounds`, apply: { fnpMortal: v }, phases });
    else if (sc === 'psychic') out.push({ label: `FNP ${v}+ vs psychic attacks`, apply: { fnpPsychic: v }, phases });
    else if (sc === 'psychic-and-mortal') out.push({ label: `FNP ${v}+ vs psychic & mortal`, apply: { fnpMortal: v, fnpPsychic: v }, phases });
    else if (!mod.applies_to_keywords) out.push({ label: `Feel No Pain ${v}+`, apply: { fnp: v }, phases });
  } else if (e.type === 'damage-reduction') {
    const r = mod.reduction ?? mod.value ?? mod.amount;
    if (r === 1 || r === 'half') out.push({ label: r === 'half' ? 'Halve Damage' : '-1 Damage', apply: { dr: r }, phases });
  } else if (e.type === 'invulnerable-save' && mod.invuln_sv) {
    out.push({ label: `${mod.invuln_sv}+ invulnerable save`, apply: { InSv: Number(mod.invuln_sv) }, phases });
  } else if (e.type === 'roll-modifier' && e.target === 'attacker' && mod.operation === 'subtract') {
    if (mod.roll === 'hit') out.push({ label: '-1 to hit', apply: { hitMod: -1 }, phases });
    if (mod.roll === 'wound') out.push({ label: '-1 to wound', apply: { woundMod: -1 }, phases });
  }
  return out.length ? { effects: out, permanent } : null;
}

/**
 * Defender profile: model groups + detected rules.
 * groups: [{key, name, member, count, W, Sv, InSv, T, character}]
 * rules:  [{id, source, label, text, auto, phases, apply, scope: 'unit'|'member', member, groupKeys}]
 */
export function defenderProfile(cu) {
  const groups = [];
  const rules = [];
  for (const m of cu.members) {
    const char = isCharacter(m.dcUnit);
    const mg = modelGroups(m);
    mg.forEach((g, gi) => {
      const p = g.profile;
      groups.push({
        key: `${m.index}:${gi}`,
        name: g.modelName,
        member: m.index,
        count: g.count,
        W: p.W, Sv: p.Sv, InSv: p.invuln_sv ?? 0, T: p.T,
        character: char && m.role !== 'bodyguard',
        wargearNames: g.wargear.map(w => looseName(conv.wres.resolve(m.factionId, w.id)?.name ?? w.id.replace(/-/g, ' '))),
      });
    });
    const memberGroups = groups.filter(g => g.member === m.index);
    for (const a of abilityRecords(m)) {
      if (a.type === 'detachment') continue;
      // core abilities by id
      const idFnp = String(a.id).match(/^feel-no-pain-(\d)$/);
      let effects = [];
      let permanent = true;
      if (idFnp) effects = [{ label: `Feel No Pain ${idFnp[1]}+`, apply: { fnp: Number(idFnp[1]) }, phases: ['shooting', 'fight'] }];
      else if (/^stealth$/i.test(a.name)) effects = [{ label: 'Stealth (cover vs ranged)', apply: { cover: true }, phases: ['shooting'] }];
      else {
        const st = parseStructured(a.record);
        if (st) { effects = st.effects; permanent = st.permanent; }
        else { effects = parseDefensiveText(a.text); permanent = !ACTIVATED_RE.test(a.text); }
      }
      if (!effects.length) continue;
      const leading = /while this model is leading a unit|while this model is attached/i.test(a.text);
      const otherChars = /other CHARACTER models/i.test(a.text);
      const thisModel = /\bthis model\b/i.test(a.text) && !/this unit/i.test(a.text);
      // which groups does it cover?
      let groupKeys;
      if (a.type === 'wargear') {
        const name = looseName(a.name);
        const carriers = memberGroups.filter(g => g.wargearNames.includes(name));
        groupKeys = (carriers.length ? carriers : memberGroups).map(g => g.key);
      } else if (otherChars) {
        groupKeys = groups.filter(g => g.character && g.member !== m.index).map(g => g.key);
      } else if (leading) {
        groupKeys = null; // whole attached unit
      } else if (thisModel || m.role === 'leader') {
        groupKeys = memberGroups.map(g => g.key);
      } else {
        groupKeys = null; // "this unit"
      }
      const autoOn = permanent && (!leading || m.role === 'leader');
      effects.forEach((ef, k) => {
        rules.push({
          id: `${m.index}:${a.id}:${k}`,
          source: a.name,
          member: m.dcUnit.name,
          label: ef.label,
          text: a.text,
          auto: autoOn,
          phases: ef.phases,
          apply: ef.apply,
          groupKeys,
        });
      });
    }
  }
  // leaders' groups listed after bodyguards
  groups.sort((x, y) => Number(x.character) - Number(y.character));
  return { name: cu.name, keywords: cu.keywords, groups, rules };
}

/** Summary stats for the target card / weapon defaults. */
export function defenderSummary(profile) {
  const bg = profile.groups.filter(g => !g.character);
  const main = bg.length ? bg : profile.groups;
  return {
    T: Math.max(...main.map(g => g.T)),
    Sv: Math.min(...main.map(g => g.Sv)),
    InSv: main.map(g => g.InSv).filter(Boolean).reduce((a, b) => Math.min(a, b), 7) % 7, // 0 = none
    W: [...main].sort((a, b) => b.count - a.count)[0]?.W ?? 1, // the bulk of the unit
    models: profile.groups.reduce((s, g) => s + g.count, 0),
    keywords: profile.keywords,
  };
}

const GROUP_FIELDS = new Set(['InSv', 'dr', 'fnp']);

/**
 * Engine defender for the chosen phase.
 * enabled: Set of rule ids switched on; manual: defender-side manual mods
 * (they win over / combine with the detected ones); overrides: per group key
 * {count, woundsLeftFirst}.
 */
export function buildDefender(profile, enabled, phase, manual = {}, overrides = {}) {
  const mods = {};
  const groups = profile.groups.map(g => ({ ...g, ...(overrides[g.key] ?? {}) }));
  const byKey = new Map(groups.map(g => [g.key, g]));
  for (const r of profile.rules) {
    if (!enabled.has(r.id) || !r.phases.includes(phase)) continue;
    for (const [k, v] of Object.entries(r.apply)) {
      const targets = r.groupKeys ? r.groupKeys.map(key => byKey.get(key)).filter(Boolean) : groups;
      if (GROUP_FIELDS.has(k)) {
        for (const g of targets) {
          if (k === 'InSv') g.InSv = g.InSv ? Math.min(g.InSv, v) : v;
          else if (k === 'fnp') g.fnp = g.fnp ? Math.min(g.fnp, v) : v;
          else if (k === 'dr') g.dr = v === 'half' || g.dr === 'half' ? 'half' : Math.max(g.dr || 0, v);
        }
      } else if (k === 'fnpMortal' || k === 'fnpPsychic') {
        mods[k] = mods[k] ? Math.min(mods[k], v) : v;
      } else if (k === 'cover') {
        mods.cover = true;
      } else {
        mods[k] = (mods[k] ?? 0) + v;
      }
    }
  }
  // manual defender modifiers
  const out = { ...mods };
  for (const [k, v] of Object.entries(manual ?? {})) {
    if (v == null || v === 0 || v === false || v === '') continue;
    if (k === 'cover') out.cover = true;
    else if (k === 'fnp' || k === 'fnpMortal' || k === 'invuln') out[k] = out[k] ? Math.min(out[k], v) : v;
    else if (k === 'damageReduction') out.damageReduction = v;
    else out[k] = (out[k] ?? 0) + v;
  }
  // 05.03: one allocation group per CHARACTER model; every other model with
  // the same W / Sv / InSv shares a group (T, DR and FNP kept in the key so
  // per-model rules stay exact).
  const merged = [];
  const index = new Map();
  for (const g of groups) {
    if (!(g.count > 0)) continue;
    const eg = {
      name: g.name, count: g.count, W: g.W, Sv: g.Sv, InSv: g.InSv || 0, T: g.T,
      character: g.character, woundsLeftFirst: g.woundsLeftFirst ?? null,
      dr: g.dr || 0, fnp: g.fnp || 0,
    };
    const key = g.character ? null : [eg.W, eg.Sv, eg.InSv, eg.T, eg.dr, eg.fnp].join('|');
    const prev = key ? index.get(key) : null;
    if (prev && (prev.woundsLeftFirst == null || eg.woundsLeftFirst == null)) {
      prev.count += eg.count;
      if (eg.woundsLeftFirst != null) prev.woundsLeftFirst = eg.woundsLeftFirst;
      if (!prev.name.includes(eg.name)) prev.name += ` / ${eg.name}`;
      continue;
    }
    merged.push(eg);
    if (key) index.set(key, eg);
  }
  return { name: profile.name, keywords: profile.keywords, groups: merged, mods: out };
}
