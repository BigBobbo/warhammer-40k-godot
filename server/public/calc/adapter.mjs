// Army adapter for the combat calculator: pasted list text -> combat units
// (attached Leaders/Support merged into their Bodyguard), attacker weapon
// rows and defender profiles/rules for engine.mjs.
//
// Reuses the Army Builder's importer and patched 40kdc dataset (store.js /
// importers.js), so every list format the builder accepts works here too.

import { conv, factionName, dc } from '../js/builder/store.js';
import { importText } from '../js/builder/importers.js';
import { normName, looseName } from '../js/lib/dckit.mjs';
import { expectedDamageQuick, mergeMods } from './engine.mjs';
import { footprint } from './board.mjs';
import { BASE_SIZE_OVERRIDES } from '../js/lib/gameformat.mjs';
import { STRATAGEMS } from './stratagems-11e.mjs';
import {
  parseOffensive, parseDefensiveText, parseConditions, conditionsMet, describeConditions,
  stratagemRole, stratagemPhases, stratagemEligible,
} from './rules.mjs';
export { describeConditions };

export const DATASET_VERSION = dc.DATASET_VERSION;

// ---------------------------------------------------------------------------
// Import

export function importArmy(text) {
  const { roster, report } = importText(text);
  const attachments = defaultAttachments(roster);
  const units = combatUnits(roster, attachments);
  const unresolved = (roster.units ?? []).filter(u => !u.ref?.id).map(u => u.ref?.raw_name ?? '?');
  return {
    roster,
    faction: roster.faction_id ? factionName(roster.faction_id) : 'Unknown faction',
    name: roster.name || 'Army',
    defaultAttachments: attachments,
    attachments,
    units,
    warnings: [...(report?.warnings ?? []), ...unresolved.map(n => `unit not recognised: ${n}`)],
  };
}

/** Re-derive the combat units after the player changes who is attached to whom. */
export function setAttachments(army, attachments) {
  army.attachments = attachments;
  army.units = combatUnits(army.roster, attachments);
  return army;
}

function resolveUnit(roster, ru) {
  if (!ru.ref?.id) return null;
  const found = conv.findUnitById(roster.faction_id, ru.ref.id);
  return found ? { dcUnit: found.unit, factionId: found.factionId } : null;
}

function isCharacter(dcUnit) {
  return (dcUnit.keywords ?? []).some(k => /^character$/i.test(k));
}

function rosterParts(roster) {
  const parts = [];
  (roster.units ?? []).forEach((ru, i) => {
    const r = resolveUnit(roster, ru);
    if (r) parts.push({ index: i, ru, ...r });
  });
  return parts;
}

/** 'leader' | 'support' for a character that can be attached, else null. */
export function attachRole(part) {
  if (eligibleBodyguardIds(part).size === 0) return null;
  return part.dcUnit.attachment_role === 'support' || part.ru.leader_attachment?.role === 'support' ? 'support' : 'leader';
}

/** Datasheet ids this character may join (Leader list + enhancement grants). */
function eligibleBodyguardIds(part) {
  const la = (dc.RAW_DATA.leaderAttachments ?? []).filter(x => x.leader_id === part.dcUnit.id);
  const ids = new Set(la.flatMap(x => x.eligible_bodyguard_ids ?? []));
  const enhId = part.ru.enhancement?.id ?? part.ru.enhancement?.ref?.id;
  if (enhId) for (const b of (dc.RAW_DATA.enhancements ?? []).find(x => x.id === enhId)?.attachment_bodyguard_ids ?? []) ids.add(b);
  return ids;
}

/**
 * Attachments as listed in the imported army: { [characterRosterIndex]: bodyguardRosterIndex }.
 * (GW app "Attached as" blocks; other formats usually carry none.)
 */
export function defaultAttachments(roster) {
  const parts = rosterParts(roster);
  const out = {};
  const used = new Map(); // bodyguard index -> Set(roles)
  for (const p of parts) {
    const bgId = p.ru.leader_attachment?.bodyguard_ref?.id;
    if (!bgId) continue;
    const role = p.ru.leader_attachment?.role === 'support' ? 'support' : 'leader';
    const bg = parts.find(q => q.ru.ref.id === bgId && q !== p && !q.ru.leader_attachment && !used.get(q.index)?.has(role));
    if (!bg) continue;
    if (!used.has(bg.index)) used.set(bg.index, new Set());
    used.get(bg.index).add(role);
    out[p.index] = bg.index;
  }
  return out;
}

/** Roster -> combat units. A bodyguard and the characters attached to it are one unit. */
export function combatUnits(roster, attachments = defaultAttachments(roster)) {
  const parts = rosterParts(roster);
  const byIndex = new Map(parts.map(p => [p.index, p]));
  const taken = new Set();
  const attachedTo = new Map(); // bodyguard index -> [character parts]
  for (const [ci, bi] of Object.entries(attachments ?? {})) {
    const c = byIndex.get(Number(ci)), b = byIndex.get(Number(bi));
    if (!c || !b || c === b) continue;
    if (!attachedTo.has(b.index)) attachedTo.set(b.index, []);
    attachedTo.get(b.index).push(c);
    taken.add(c.index);
  }
  const seen = new Map();
  const out = [];
  for (const p of parts) {
    if (taken.has(p.index)) continue;
    const leaders = attachedTo.get(p.index) ?? [];
    const members = [
      ...leaders.map(l => ({ ...l, role: 'leader', attachRole: attachRole(l) ?? 'leader' })),
      { ...p, role: leaders.length ? 'bodyguard' : 'single' },
    ];
    const baseName = [...leaders.map(l => l.dcUnit.name), p.dcUnit.name].join(' + ');
    const n = (seen.get(baseName) ?? 0) + 1;
    seen.set(baseName, n);
    const keywords = new Set();
    for (const m of members) for (const k of [...(m.dcUnit.keywords ?? []), ...(m.dcUnit.faction_keywords ?? [])]) keywords.add(k.toUpperCase());
    out.push({
      key: `u${p.index}`,
      index: p.index,
      baseName,
      name: baseName + (n > 1 ? ` (${n})` : ''),
      members,
      keywords: [...keywords],
      models: members.reduce((s, m) => s + (m.ru.model_count ?? 1), 0),
      points: members.reduce((s, m) => s + (m.ru.points ?? 0), 0),
      // a lone character that could join a unit
      canJoin: !leaders.length && attachRole(p) != null,
      // a non-character unit that characters can join
      canHost: !isCharacter(p.dcUnit),
    });
  }
  // label duplicates "(1)" too once a "(2)" exists
  for (const u of out) if (seen.get(u.name) > 1) u.name += ' (1)';
  return out;
}

/** Short display name of a roster unit, numbered when the army has several. */
export function rosterUnitLabel(army, index) {
  const parts = rosterParts(army.roster);
  const p = parts.find(x => x.index === index);
  if (!p) return '?';
  const same = parts.filter(x => x.dcUnit.id === p.dcUnit.id);
  return same.length > 1 ? `${p.dcUnit.name} (${same.indexOf(p) + 1})` : p.dcUnit.name;
}

/**
 * Characters that could join bodyguard roster unit `bodyguardIndex`:
 * [{index, name, role, eligible, attachedTo (roster index|null), replaces (index|null)}]
 * Eligible ones first. Ineligible characters are listed too (the dataset's
 * Leader lists can lag a new codex) — the player decides.
 */
export function attachCandidates(army, bodyguardIndex) {
  const parts = rosterParts(army.roster);
  const bg = parts.find(p => p.index === bodyguardIndex);
  if (!bg) return [];
  const att = army.attachments ?? {};
  const out = [];
  for (const p of parts) {
    const role = attachRole(p);
    if (!role || p.index === bodyguardIndex) continue;
    const cur = att[p.index] ?? null;
    if (cur === bodyguardIndex) continue; // already here
    const replaces = Object.entries(att).find(([ci, bi]) => bi === bodyguardIndex &&
      attachRole(parts.find(x => x.index === Number(ci))) === role)?.[0];
    out.push({
      index: p.index,
      name: rosterUnitLabel(army, p.index),
      role,
      eligible: eligibleBodyguardIds(p).has(bg.dcUnit.id),
      attachedTo: cur,
      replaces: replaces != null ? Number(replaces) : null,
    });
  }
  return out.sort((a, b) => Number(b.eligible) - Number(a.eligible) || a.name.localeCompare(b.name));
}

/** Units a lone character could join: [{index, name, eligible, replaces}]. */
export function joinCandidates(army, characterIndex) {
  const parts = rosterParts(army.roster);
  const c = parts.find(p => p.index === characterIndex);
  const role = c ? attachRole(c) : null;
  if (!role) return [];
  const ids = eligibleBodyguardIds(c);
  const att = army.attachments ?? {};
  return parts.filter(p => p.index !== characterIndex && !isCharacter(p.dcUnit) && att[characterIndex] !== p.index)
    .map(p => {
      const replaces = Object.entries(att).find(([ci, bi]) => bi === p.index && Number(ci) !== characterIndex &&
        attachRole(parts.find(x => x.index === Number(ci))) === role)?.[0];
      return { index: p.index, name: rosterUnitLabel(army, p.index), eligible: ids.has(p.dcUnit.id), replaces: replaces != null ? Number(replaces) : null };
    })
    .sort((a, b) => Number(b.eligible) - Number(a.eligible) || a.name.localeCompare(b.name));
}

/**
 * New attachments map with `characterIndex` joined to `bodyguardIndex`
 * (null = detach). 11e: one Leader and one Support per bodyguard — a
 * character of the same role already there is detached.
 */
export function withAttachment(army, characterIndex, bodyguardIndex) {
  const parts = rosterParts(army.roster);
  const att = { ...(army.attachments ?? {}) };
  delete att[characterIndex];
  if (bodyguardIndex != null) {
    const role = attachRole(parts.find(p => p.index === characterIndex)) ?? 'leader';
    for (const [ci, bi] of Object.entries(att)) {
      if (bi === bodyguardIndex && (attachRole(parts.find(p => p.index === Number(ci))) ?? 'leader') === role) delete att[ci];
    }
    att[characterIndex] = bodyguardIndex;
  }
  return att;
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
  const sk = p.skill == null ? '' : ` ${p.melee ? 'WS' : 'BS'}${p.skill}+`; // torrent: no BS (auto-hits)
  return `A${p.A}${sk} S${p.S} AP${p.AP} D${p.D}`;
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
export function defenderProfile(cu, army = null) {
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
        ptsPerModel: (m.ru.points ?? 0) / Math.max(1, m.ru.model_count ?? 1),
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
  // detachment rules (always-on ones auto) and defensive stratagems (off: they cost CP)
  const stratText = [];
  if (army) {
    for (const d of detachmentRules(army)) {
      const effects = parseDefensiveText(d.text);
      effects.forEach((ef, k) => rules.push({
        id: `det:${d.id}:${k}`, source: d.name, member: 'Detachment', label: ef.label, text: d.text,
        auto: !ACTIVATED_RE.test(d.text) && !/\b(if|while)\b/i.test(d.text), phases: ef.phases, apply: ef.apply, groupKeys: null, kind: 'detachment',
      }));
    }
    for (const st of armyStratagems(army)) {
      if (stratagemRole(st) !== 'defend' || !stratagemEligible(st, cu.keywords)) continue;
      const effects = st.missing ? [] : parseDefensiveText(st.effect);
      if (!effects.length) { stratText.push(st); continue; }
      effects.forEach((ef, k) => rules.push({
        id: `strat:${st.id}:${k}`, source: `${st.name} (${st.cp}CP)`, member: 'Stratagem', label: ef.label,
        text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, auto: false, phases: ef.phases.filter(p => stratagemPhases(st).includes(p)),
        apply: ef.apply, groupKeys: null, kind: 'stratagem', cp: st.cp,
      }));
    }
  }
  // leaders' groups listed after bodyguards
  groups.sort((x, y) => Number(x.character) - Number(y.character));
  return { name: cu.name, keywords: cu.keywords, groups, rules, stratText };
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
      dr: g.dr || 0, fnp: g.fnp || 0, ptsPerModel: g.ptsPerModel || 0,
    };
    const key = g.character ? null : [eg.W, eg.Sv, eg.InSv, eg.T, eg.dr, eg.fnp, eg.ptsPerModel].join('|');
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

// ---------------------------------------------------------------------------
// Detachment rules and stratagems of an army

function armyDetachmentRecords(army) {
  const out = [];
  for (const rd of army.roster.detachments ?? []) {
    const id = rd?.ref?.id;
    const rec = (dc.RAW_DATA.detachments ?? []).find(d => d.id === id) ??
      (dc.RAW_DATA.detachments ?? []).find(d => normName(d.name) === normName(rd?.ref?.raw_name ?? ''));
    out.push({ id: id ?? normName(rd?.ref?.raw_name ?? ''), name: rec?.name ?? rd?.ref?.raw_name ?? '', record: rec });
  }
  return out;
}

/** Detachment rule abilities: [{id, name, text}] */
export function detachmentRules(army) {
  const out = [];
  for (const d of armyDetachmentRecords(army)) {
    const rid = d.record?.detachment_rule_id;
    if (!rid) continue;
    const a = (dc.RAW_DATA.abilities ?? []).find(x => x.ability_id === rid);
    if (a) out.push({ id: rid, name: `${a.name} (${d.name})`, text: conv.safeDescribe(a) });
  }
  return out;
}

/** The army's detachment stratagems (Wahapedia 11e import), deduplicated. */
export function armyStratagems(army) {
  const dets = armyDetachmentRecords(army);
  const ids = new Set(dets.map(d => d.id));
  const names = new Set(dets.map(d => normName(d.name)));
  const seen = new Set();
  return STRATAGEMS.filter(st => (ids.has(st.detachmentId) || names.has(normName(st.detachment)) || st.detachment === 'Core') &&
    !seen.has(st.id) && seen.add(st.id));
}

// ---------------------------------------------------------------------------
// Attacker rules: unit / leader / enhancement abilities, detachment rules and
// detachment stratagems that modify this unit's attacks.

/**
 * [{id, kind: 'ability'|'detachment'|'stratagem', source, member (roster index|null),
 *   memberName, effects, apply, phases, scope, conds, text, cp, partial}]
 * plus `stratText`: the army's attack stratagems the parser could not model.
 */
export function attackerRules(cu, army) {
  const rules = [];
  const one = (base, p, extra = {}) => ({
    ...base,
    effects: p.effects,
    apply: p.effects.reduce((acc, e) => mergeMods(acc, e.apply), {}),
    label: p.effects.map(e => e.label).join(', '),
    phases: p.phases,
    scope: p.scope,
    conds: p.conds,
    partial: p.partial,
    ...extra,
  });
  const push = (base, parsed) => {
    if (!parsed) return false;
    const alts = parsed.alternatives ?? [];
    // a choice rule ("X, or Y"): one rule per option, sharing a group so only one is on
    rules.push(one(base, parsed, alts.length ? { group: base.id, option: 1 } : {}));
    alts.forEach((a, i) => rules.push(one({ ...base, id: `${base.id}:alt${i + 1}` }, a,
      { group: base.id, option: i + 2, label: `or: ${a.effects.map(e => e.label).join(', ')}` })));
    return true;
  };
  for (const m of cu.members) {
    for (const a of abilityRecords(m)) {
      if (/^leader$/i.test(a.name)) continue;
      push({ id: `${m.index}:${a.id}`, kind: a.type === 'detachment' ? 'detachment' : 'ability', source: a.name,
        member: m.index, memberName: m.dcUnit.name, memberRole: m.role, text: a.text }, parseOffensive(a.text));
    }
  }
  for (const d of detachmentRules(army)) {
    push({ id: `det:${d.id}`, kind: 'detachment', source: d.name, member: null, memberName: 'Detachment', text: d.text }, parseOffensive(d.text));
  }
  const stratText = [];
  for (const st of armyStratagems(army)) {
    if (st.detachment === 'Core' && /^COMMAND RE-?ROLL$/i.test(st.name) && !st.missing) {
      // "If you are rolling more than one dice together, select one of those dice to re-roll"
      const base = { kind: 'stratagem', source: `${st.name} (${st.cp}CP)`, member: null, memberName: 'Stratagem',
        text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, cp: st.cp, scope: 'unit', conds: parseConditions(''), phases: ['shooting', 'fight'], partial: false };
      const opts = [['rerollOneHit', 'Re-roll one hit'], ['rerollOneWound', 'Re-roll one wound'], ['rerollOneDamage', 'Re-roll one damage roll']];
      opts.forEach(([k, label], i) => rules.push({ ...base, id: `strat:${st.id}${i ? `:alt${i}` : ''}`, group: `strat:${st.id}`, option: i + 1,
        effects: [{ label, apply: { [k]: true } }], apply: { [k]: true }, label: i ? `or: ${label}` : label }));
      continue;
    }
    if (stratagemRole(st) !== 'attack' || !stratagemEligible(st, cu.keywords)) continue;
    const parsed = st.missing ? null : parseOffensive(st.effect);
    const ok = push({ id: `strat:${st.id}`, kind: 'stratagem', source: `${st.name} (${st.cp}CP)`, member: null,
      memberName: 'Stratagem', text: `WHEN: ${st.when}\nEFFECT: ${st.effect}`, cp: st.cp, stratPhases: stratagemPhases(st) }, parsed);
    if (ok) {
      const wc = parseConditions(st.when);
      for (const r of rules.filter(x => x.id === `strat:${st.id}` || x.group === `strat:${st.id}`)) {
        r.phases = r.phases.filter(p => r.stratPhases.includes(p));
        // a stratagem's own WHEN conditions ("...that made a charge move this turn") still gate it
        r.conds.charged ||= wc.charged;
      }
    } else stratText.push(st);
  }
  return { rules, stratText };
}

/**
 * Is attacker rule `r` on? Stratagems only when the player switched them on;
 * abilities / detachment rules follow their conditions unless overridden.
 */
export function attackerRuleOn(r, override, ctx) {
  if (override === true) return true;
  if (override === false) return false;
  if (r.kind === 'stratagem') return false;
  return conditionsMet(r.conds, { ...ctx, leading: r.memberRole === 'leader' });
}

/**
 * Engine attacker for one attacking combat unit: manual mods + enabled rules
 * (unit-scoped rules into the unit's mods, model-scoped ones only onto that
 * member's weapons).
 */
export function buildAttacker(cu, rows, manualMods, rules, enabledIds, phase) {
  let unitMods = { ...(manualMods ?? {}) };
  const perMember = new Map();
  // a model-scoped stratagem ("Select one CHARACTER model ... that model's melee weapons") goes to the characters
  const charMembers = cu.members.filter(m => m.role === 'leader' || (cu.members.length === 1 && (m.dcUnit.keywords ?? []).some(k => /^character$/i.test(k))));
  for (const r of rules) {
    if (!enabledIds.has(r.id) || !r.phases.includes(phase)) continue;
    const { mortals, ...apply } = r.apply;
    if (mortals?.length) unitMods = mergeMods(unitMods, { mortals });
    if (r.scope === 'model' && r.member != null) perMember.set(r.member, mergeMods(perMember.get(r.member) ?? {}, apply));
    else if (r.scope === 'model' && r.member == null && charMembers.length) for (const m of charMembers) perMember.set(m.index, mergeMods(perMember.get(m.index) ?? {}, apply));
    else unitMods = mergeMods(unitMods, apply);
  }
  // mortal-wound dice counted "per T" / "per model" resolve against this unit
  if (unitMods.mortals?.length) {
    const maxT = Math.max(...cu.members.flatMap(m => (m.dcUnit.profiles ?? []).map(p => p.T || 0)), 1);
    unitMods.mortals = unitMods.mortals.map(src => ({
      ...src, dice: src.dice === 'T' ? maxT : src.dice === 'models' ? cu.models : src.dice,
    }));
  }
  return {
    name: cu.name,
    mods: unitMods,
    weapons: rows.filter(r => r.count > 0).map(row => {
      const w = engineWeapon(row);
      const mi = Number(String(row.id).split(':')[0]);
      if (perMember.has(mi)) w.mods = perMember.get(mi);
      return w;
    }),
    allVehicleMonster: allVehicleMonster(cu),
  };
}

// ---------------------------------------------------------------------------
// Enemy cheat sheet

/**
 * Everything a player wants to know about a combat unit at a glance:
 * per-datasheet stat lines, weapons (both phases), abilities, and the rules
 * the calculator detects (defensive + offensive).
 */
export function unitIntel(cu, army) {
  const profiles = [];
  for (const m of cu.members) {
    for (const p of m.dcUnit.profiles ?? []) {
      profiles.push({
        member: m.dcUnit.name, name: p.name, role: m.role,
        M: p.M, T: p.T, Sv: p.Sv, InSv: p.invuln_sv ?? null, W: p.W, Ld: p.Ld, OC: p.OC,
      });
    }
  }
  // collapse identical lines (Sergeant / trooper with the same stats)
  const seenLine = new Set();
  const stats = profiles.filter(p => {
    const k = [p.member, p.M, p.T, p.Sv, p.InSv, p.W, p.Ld, p.OC].join('|');
    return !seenLine.has(k) && seenLine.add(k);
  });
  const weapons = [...attackerRows(cu, 'shooting', null), ...attackerRows(cu, 'fight', null)]
    .map(r => ({ label: r.label, range: r.range, stats: r.stats, tags: r.tags, count: r.max, melee: r.melee }));
  const def = defenderProfile(cu, army);
  const off = attackerRules(cu, army).rules.filter(r => r.kind !== 'stratagem');
  const fnp = Math.min(...def.rules.filter(r => r.auto && r.apply.fnp).map(r => r.apply.fnp), 7);
  return {
    name: cu.name,
    models: cu.models,
    points: cu.points,
    keywords: cu.keywords,
    stats,
    fnp: fnp < 7 ? fnp : null,
    weapons,
    abilities: abilitiesOf(cu),
    defensive: def.rules.filter(r => r.kind !== 'stratagem' && r.kind !== 'detachment')
      .map(r => ({ label: r.label, source: r.source, auto: r.auto })),
    offensive: off.map(r => ({ label: r.label, source: r.source, when: describeConditions(r.conds), phases: r.phases })),
  };
}

/** Army-level intel: detachment rules and every stratagem, grouped by phase. */
export function armyIntel(army) {
  const strats = armyStratagems(army).map(st => ({
    name: st.name, cp: st.cp, phase: st.phase, detachment: st.detachment, turn: st.turn,
    when: st.when, target: st.target, effect: st.effect, missing: st.missing, role: stratagemRole(st),
  }));
  return {
    faction: army.faction,
    detachments: armyDetachmentRecords(army).map(d => d.name).filter(Boolean),
    detachmentRules: detachmentRules(army),
    stratagems: strats,
  };
}

// ---------------------------------------------------------------------------
// Board planner

/**
 * What the board needs to draw / reason about a combat unit:
 * { members: [{ count, fp, label, leader }], move, ranges: [inches...], melee: bool }
 */
export function boardUnit(cu) {
  const members = cu.members.map(m => {
    const kw = [...(m.dcUnit.keywords ?? []), ...(m.dcUnit.faction_keywords ?? [])];
    const base = BASE_SIZE_OVERRIDES[m.dcUnit.id] ?? m.dcUnit.base_size_mm;
    return { count: m.ru.model_count ?? 1, fp: footprint(base, kw), label: m.dcUnit.name, leader: m.role === 'leader' };
  });
  const move = Math.min(...cu.members.map(m => Number(m.dcUnit.profiles?.[0]?.M) || 6));
  const ranged = attackerRows(cu, 'shooting', null);
  const ranges = [...new Set(ranged.map(r => parseFloat(r.range)).filter(n => n > 0))].sort((a, b) => a - b);
  const rfMelta = [...new Set(ranged.filter(r => r.kw.rapidFire || r.kw.melta).map(r => parseFloat(r.range)).filter(n => n > 0))];
  return { members, move, ranges, halfRangeWeapons: rfMelta, melee: attackerRows(cu, 'fight', null).length > 0 };
}
