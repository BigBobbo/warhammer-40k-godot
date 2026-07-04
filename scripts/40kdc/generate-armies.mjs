#!/usr/bin/env node
// Regenerate 40k/armies/*.json (schema 2) from the 11th-edition 40kdc dataset.
//
// For each existing army file the generator preserves the ROSTER — unit keys,
// owners, model counts, warlord flag, weapon loadout choices — and rebuilds
// every datasheet fact (stats, points, weapon profiles, abilities, keywords,
// base sizes, composition, leader pairings, transport capacity) from the
// extracted 11e data in 40k/data/40kdc/.
//
// Usage: node generate-armies.mjs [file.json ...]   (default: all in 40k/armies)

import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { dirname, join, basename } from 'path';
import { fileURLToPath } from 'url';
import { loadCollection, factionScopedResolver, normName, pointsFor } from './lib.mjs';
import { describeAbility } from '@alpaca-software/40kdc-data';

const here = dirname(fileURLToPath(import.meta.url));
const ARMIES_DIR = join(here, '..', '..', '40k', 'armies');

// ---------------------------------------------------------------------------
// Dataset
const units = loadCollection('units');
const weapons = loadCollection('weapons');
const abilities = loadCollection('abilities');
const compositions = loadCollection('unitCompositions');
const leaderAttachments = loadCollection('leaderAttachments');
const enhancementsAll = loadCollection('enhancements');
const detachmentsAll = loadCollection('detachments');

const wres = factionScopedResolver(weapons, units, w => w.id, u => u.weapon_ids);
const ares = factionScopedResolver(abilities, units, a => a.ability_id, u => u.ability_ids,
  a => a.faction_id ?? null);

const FACTION_IDS = {
  'orks': 'orks',
  'adeptus custodes': 'adeptus-custodes',
  'space marines': 'adeptus-astartes',
  'adeptus astartes': 'adeptus-astartes',
};

// 10e -> 11e datasheet renames (per faction id).
const UNIT_ALIASES = {
  'orks': {
    'nob with waaagh banner': 'bannernob',
  },
  'adeptus-custodes': {},
  'adeptus-astartes': {},
};

// 10e -> 11e weapon renames (matched via looseName; -> 11e weapon id),
// applied when the direct name match fails.
const WEAPON_ALIASES_SRC = {
  'adeptus-custodes': {
    'telemon storm cannon': 'arachnus-storm-cannon',
    'twin arachnus las-blaze': 'twin-arachnus-heavy-blaze-cannon',
  },
  'orks': {
    'speshul kommando shoota': 'kustom-shoota',
  },
};

// Imperium armies may include Agents of the Imperium allied units
// (alliedRules.json models the gates; the roster files already contain them).
const ALLIED_FACTIONS = {
  'adeptus-custodes': ['agents-of-the-imperium'],
  'adeptus-astartes': ['agents-of-the-imperium'],
};

// The game dispatches ability/enhancement behavior on EXACT names
// (UnitAbilityManager.ABILITY_EFFECTS, FactionAbilityManager tables,
// ArmyListManager wargear/enhancement bonus tables). Canonicalize emitted
// names to the game's spelling when they differ only in case/punctuation.
const GAME_NAME_CANON = (() => {
  const canon = new Map();
  const dirs = ['autoloads/UnitAbilityManager.gd', 'autoloads/FactionAbilityManager.gd',
    'autoloads/ArmyListManager.gd'];
  for (const rel of dirs) {
    try {
      const src = readFileSync(join(here, '..', '..', '40k', rel), 'utf8');
      for (const m of src.matchAll(/"([^"\n]{3,60})"\s*:/g)) {
        const name = m[1];
        // Only Title-cased entries — the tables key on display names, while
        // lowercase matches are ordinary dict keys ("capacity", "wounds", ...).
        if (!/^[A-Z]/.test(name)) continue;
        if (!canon.has(normName(name))) canon.set(normName(name), name);
      }
    } catch { /* file moved — canonicalization becomes a no-op */ }
  }
  return canon;
})();

function canonicalName(name) {
  return GAME_NAME_CANON.get(normName(name)) ?? name;
}

// Loose match key: normName + singular-ize each word (handles
// "Twin slugga" vs "Twin sluggas", "Killsaws" vs "Killsaw").
function looseName(s) {
  return normName(s).split(' ').map(w => w.replace(/s$/, '')).join(' ');
}

// Old weapon names may carry a profile suffix ("Kannon – frag").
function weaponBaseName(s) {
  return String(s).split(/\s+[–-]\s+/)[0];
}

const unitsByFaction = new Map();
for (const u of units) {
  if (!unitsByFaction.has(u.faction_id)) unitsByFaction.set(u.faction_id, new Map());
  const m = unitsByFaction.get(u.faction_id);
  const key = normName(u.name);
  if (!m.has(key)) m.set(key, u);
}
const compByUnit = new Map(compositions.map(c => [`${c.faction_id}::${c.unit_id}`, c]));
const bodyguardsByLeader = new Map();
for (const la of leaderAttachments) {
  if (!bodyguardsByLeader.has(la.leader_id)) bodyguardsByLeader.set(la.leader_id, new Set());
  for (const b of la.eligible_bodyguard_ids) bodyguardsByLeader.get(la.leader_id).add(b);
}
const unitById = new Map();
for (const u of units) unitById.set(`${u.faction_id}::${u.id}`, u);

const factions = loadCollection('factions');

// The army rule (Waaagh!, Martial Ka'tah, Oath of Moment ...) — every unit of
// the faction carries it in meta.abilities; FactionAbilityManager detects it
// by exact name. Some faction_rule_id slugs dangle (e.g. `martial-katah` vs
// ability `martial-ka-tah`), so fall back to a loose-slug scan.
function factionRuleAbility(factionId) {
  const f = factions.find(x => x.id === factionId);
  if (!f?.faction_rule_id) return null;
  let rule = abilities.find(a => a.ability_id === f.faction_rule_id);
  if (!rule) {
    const want = f.faction_rule_id.replace(/-/g, '');
    rule = abilities.find(a =>
      a.ability_type === 'faction' &&
      (a.faction_id === factionId || !a.faction_id) &&
      a.ability_id.replace(/-/g, '') === want);
  }
  return rule ?? null;
}

// ---------------------------------------------------------------------------
// Weapon conversion
//
// Game structured-ability registry (scripts/rules/AbilityRegistry.gd). Only
// these ids may appear in a weapon's structured `abilities` array — unknown
// ids make ArmyListManager fail the whole army load.
const KEYWORD_MAP = {
  'anti': (p) => ({ id: 'anti', keyword: String(p.target_keyword ?? '').toUpperCase(), threshold: p.threshold ?? 4 }),
  'assault': () => ({ id: 'assault' }),
  'blast': () => ({ id: 'blast' }),
  'cleave': (p) => ({ id: 'cleave', x: p.value ?? 1 }),
  'close-quarters': () => ({ id: 'close_quarters' }),
  'devastating-wounds': () => ({ id: 'devastating_wounds' }),
  'extra-attacks': () => ({ id: 'extra_attacks' }),
  'hazardous': () => ({ id: 'hazardous' }),
  'heavy': () => ({ id: 'heavy' }),
  'ignores-cover': () => ({ id: 'ignores_cover' }),
  'indirect-fire': () => ({ id: 'indirect_fire' }),
  'lance': () => ({ id: 'lance' }),
  'lethal-hits': () => ({ id: 'lethal_hits' }),
  'melta': (p) => ({ id: 'melta', x: p.value ?? 2 }),
  'one-shot': () => ({ id: 'one_shot' }),
  'pistol': () => ({ id: 'pistol' }),
  'precision': () => ({ id: 'precision' }),
  'psychic': () => ({ id: 'psychic' }),
  'rapid-fire': (p) => ({ id: 'rapid_fire', x: p.value ?? 1 }),
  'sustained-hits': (p) => {
    const v = p.value ?? 1;
    if (typeof v === 'string' && /^d\d+$/i.test(v)) {
      return { id: 'sustained_hits', x: parseInt(v.slice(1), 10), dice: true };
    }
    return { id: 'sustained_hits', x: Number(v) };
  },
  'torrent': () => ({ id: 'torrent' }),
  'twin-linked': () => ({ id: 'twin_linked' }),
};

// Display token for special_rules string (lowercase comma list, the game's
// legacy grammar in AbilityRegistry.parse_special_rules).
function ruleToken(kw) {
  const p = kw.parameters ?? {};
  switch (kw.keyword_id) {
    case 'anti': return `anti-${String(p.target_keyword ?? '').toLowerCase()} ${p.threshold ?? 4}+`;
    case 'rapid-fire': return `rapid fire ${p.value ?? 1}`;
    case 'sustained-hits': return `sustained hits ${p.value ?? 1}`;
    case 'melta': return `melta ${p.value ?? 2}`;
    case 'cleave': return `cleave ${p.value ?? 1}`;
    // non-registry, string-only rules keep their printed form:
    case 'overcharge': return 'overcharge';
    case 'conversion': return `conversion ${p.threshold ?? 4}+`;
    default: return kw.keyword_id.replace(/-/g, ' ');
  }
}

function convertWeapon(factionId, weaponId, warnings) {
  const w = wres.resolve(factionId, weaponId);
  if (!w) { warnings.push(`weapon not found: ${weaponId}`); return []; }
  const out = [];
  for (const prof of w.profiles) {
    const isMelee = prof.range === 'Melee';
    const kws = prof.keywords ?? [];
    const structured = [];
    let allMapped = true;
    for (const kw of kws) {
      const conv = KEYWORD_MAP[kw.keyword_id];
      if (conv) structured.push(conv(kw.parameters ?? {}));
      else allMapped = false;
    }
    const specialRules = kws.map(ruleToken).join(', ');
    const entry = {
      name: w.profiles.length > 1 ? `${w.name} – ${prof.name}` : w.name,
      type: isMelee ? 'Melee' : 'Ranged',
      range: isMelee ? 'Melee' : String(prof.range),
      attacks: String(prof.stats.A),
      ...(isMelee
        ? { weapon_skill: prof.stats.WS != null ? String(prof.stats.WS) : 'N/A' }
        : { ballistic_skill: prof.stats.BS != null ? String(prof.stats.BS) : 'N/A' }),
      strength: String(prof.stats.S),
      ap: String(prof.stats.AP),
      damage: String(prof.stats.D),
    };
    if (specialRules) entry.special_rules = specialRules;
    // If every keyword maps to the registry, emit the authoritative structured
    // array. If any keyword is string-only (conversion, overcharge, ...) leave
    // the weapon string-only — a structured array would regenerate
    // special_rules and silently drop the unmapped rule.
    if (structured.length > 0 && allMapped) entry.abilities = structured;
    out.push(entry);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Ability conversion
const CORE_PARAM_ABILITIES = [
  // [regex on ability_id, (m) => game ability name matching the engine parsers]
  [/^deadly-demise-(.+)$/, m => `Deadly Demise ${m[1].toUpperCase().replace('D', 'D')}`],
  [/^scouts?-(\d+)$/, m => `Scouts ${m[1]}"`],
  [/^feel-no-pain-(\d+)$/, m => `Feel No Pain ${m[1]}+`],
  [/^firing-deck-(\d+)$/, m => `Firing Deck ${m[1]}`],
];

function convertAbility(factionId, unit, abilityId, warnings) {
  const a = ares.resolve(factionId, abilityId);
  // Parameterised core abilities get the exact name shape the engine parses.
  for (const [re, nameFn] of CORE_PARAM_ABILITIES) {
    const m = abilityId.match(re);
    if (m) {
      const name = nameFn(m);
      const desc = a ? safeDescribe(a) : '';
      return { name, type: 'Core', description: desc };
    }
  }
  if (!a) { warnings.push(`ability not found: ${abilityId}`); return null; }
  const type =
    a.ability_type === 'faction' ? 'Faction' :
    a.ability_type === 'core' ? 'Core' : 'Datasheet';
  return { name: canonicalName(a.name), type, description: safeDescribe(a) };
}

function safeDescribe(a) {
  try {
    const d = describeAbility(a);
    return typeof d === 'string' ? d : String(d ?? '');
  } catch {
    return a.community_notes ?? '';
  }
}

// Transport description synthesized to match ArmyListManager's regexes.
function transportAbility(factionKeyword, unit) {
  const tc = unit.transport_capacity;
  const kw = `${factionKeyword.toUpperCase()} INFANTRY`;
  let desc = `This model has a transport capacity of ${tc.capacity} ${kw} models.`;
  for (const ex of tc.exclusion_keywords ?? []) {
    desc += ` This model cannot transport models that are ${ex.toUpperCase()} models.`;
  }
  return { name: 'TRANSPORT', type: 'Core', description: desc };
}

// ---------------------------------------------------------------------------
// Unit conversion
function convertUnit(existing, dcUnit, factionId, factionName, warnings, detachmentEnh = new Map()) {
  const comp = compByUnit.get(`${factionId}::${dcUnit.id}`);
  const oldMeta = existing.meta ?? {};
  const modelCount = (existing.models ?? []).length ||
    dcUnit.model_count?.min || 1;

  // --- stats from profiles[0] (majority model)
  const prof = dcUnit.profiles[0];
  const stats = {
    move: prof.M,
    toughness: prof.T,
    save: prof.Sv,
    wounds: prof.W,
    leadership: prof.Ld,
    objective_control: prof.OC,
  };
  if (prof.invuln_sv != null) stats.invuln = prof.invuln_sv;

  // --- keywords: dataset keywords + faction keywords, uppercased
  const keywords = [...new Set(
    [...(dcUnit.keywords ?? []), ...(dcUnit.faction_keywords ?? [])]
      .map(k => k.toUpperCase()))].sort();

  // --- weapons: preserve the roster's loadout where names still exist,
  // otherwise the unit's full 11e weapon list.
  const dcWeaponNames = new Map();
  for (const wid of dcUnit.weapon_ids ?? []) {
    const w = wres.resolve(factionId, wid);
    if (w) dcWeaponNames.set(looseName(w.name), wid);
  }
  const chosenIds = new Set();
  const weaponAliases = {};
  for (const [k, v] of Object.entries(WEAPON_ALIASES_SRC[factionId] ?? {})) {
    weaponAliases[looseName(k)] = v;
  }
  const oldWeaponNames = [...new Set((oldMeta.weapons ?? []).map(w => weaponBaseName(w.name)))];
  for (const oldName of oldWeaponNames) {
    const wid = dcWeaponNames.get(looseName(oldName)) ?? weaponAliases[looseName(oldName)];
    if (wid && (dcUnit.weapon_ids ?? []).includes(wid)) chosenIds.add(wid);
    else if (wid) chosenIds.add(wid); // alias to a weapon authored for the faction
    else warnings.push(`${existing.id}: weapon "${oldName}" not in 11e datasheet — dropped`);
  }
  if (chosenIds.size === 0) for (const wid of dcUnit.weapon_ids ?? []) chosenIds.add(wid);
  // Default-loadout weapons must exist for model_profiles / display
  for (const m of comp?.models ?? []) {
    for (const wid of m.default_weapon_ids ?? []) {
      if (dcWeaponNames.has(looseName(wres.resolve(factionId, wid)?.name ?? ''))) chosenIds.add(wid);
    }
  }
  const weaponsOut = [];
  for (const wid of chosenIds) weaponsOut.push(...convertWeapon(factionId, wid, warnings));
  weaponsOut.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'Ranged' ? -1 : 1));

  // --- abilities (faction army rule first, mirroring the existing files)
  const abilitiesOut = [];
  const rule = factionRuleAbility(factionId);
  if (rule) {
    abilitiesOut.push({ name: canonicalName(rule.name), type: 'Faction', description: safeDescribe(rule) });
  }
  for (const aid of dcUnit.ability_ids ?? []) {
    const conv = convertAbility(factionId, dcUnit, aid, warnings);
    if (conv) abilitiesOut.push(conv);
  }
  if (dcUnit.transport_capacity) abilitiesOut.push(transportAbility(factionName, dcUnit));

  // --- composition + models
  const compOut = [];
  let line = 1;
  for (const m of comp?.models ?? []) {
    const desc = m.min === m.max ? `${m.min} ${m.name}` : `${m.min}-${m.max} ${m.name}`;
    compOut.push({ description: desc, line: line++ });
  }

  // model wounds per model type: order = leader model first (composition order)
  const profByName = new Map(dcUnit.profiles.map(p => [normName(p.name), p]));
  function profileFor(modelName, profileName) {
    return profByName.get(normName(profileName ?? '')) ??
      profByName.get(normName(modelName)) ?? prof;
  }
  const modelsOut = [];
  let mi = 1;
  const compModels = comp?.models ?? [{ name: dcUnit.name, min: modelCount, max: modelCount }];
  // scale composition to the roster's model count using tiers when possible
  let remaining = modelCount;
  const counts = [];
  for (let k = 0; k < compModels.length; k++) {
    const m = compModels[k];
    const isLast = k === compModels.length - 1;
    const take = isLast ? remaining : Math.min(m.min, remaining);
    counts.push(Math.max(0, take));
    remaining -= take;
  }
  for (let k = 0; k < compModels.length; k++) {
    const m = compModels[k];
    const p = profileFor(m.name, m.profile_name);
    const base = m.base_size_mm ?? dcUnit.base_size_mm ?? { shape: 'round', diameter: 32 };
    for (let n = 0; n < counts[k]; n++) {
      const model = {
        id: `m${mi++}`,
        wounds: p.W,
        current_wounds: p.W,
        base_mm: base.diameter ?? base.width ?? 32,
        position: null,
        alive: true,
        status_effects: [],
      };
      if (base.shape === 'oval' && base.width && base.length) {
        model.base_type = 'oval';
        model.base_dimensions = { length: base.length, width: base.width };
        model.base_mm = base.width;
      }
      modelsOut.push(model);
    }
  }

  // --- enhancements: keep only ones that exist in the 11e detachment
  const enhancementsOut = [];
  let enhancementPoints = 0;
  for (const e of oldMeta.enhancements ?? []) {
    let name = typeof e === 'string' ? e : (e?.name ?? '');
    name = name.replace(/\s*\(\+?\d+\s*pts?\)\s*$/i, ''); // "X (+25 pts)" -> "X"
    const match = detachmentEnh.get(normName(name));
    if (match) {
      enhancementsOut.push(canonicalName(match.name));
      enhancementPoints += match.cost ?? 0;
    } else if (name) {
      warnings.push(`${existing.id}: enhancement "${name}" not in 11e detachment — dropped`);
    }
  }

  // --- points for this model count (first-copy pricing)
  const points = pointsFor(dcUnit, modelsOut.length) + enhancementPoints;

  // --- leader data
  const meta = {
    name: dcUnit.name,
    keywords,
    stats,
    points,
    is_warlord: oldMeta.is_warlord ?? false,
    enhancements: enhancementsOut,
    wargear: oldMeta.wargear ?? [],
    weapons: weaponsOut,
    abilities: abilitiesOut,
    unit_composition: compOut,
  };
  const bg = bodyguardsByLeader.get(dcUnit.id);
  if (bg && (dcUnit.attachment_role === 'leader' || dcUnit.role === 'character' || dcUnit.role === 'epic-hero')) {
    const canLead = [...bg]
      .map(bid => unitById.get(`${factionId}::${bid}`)?.name?.toUpperCase())
      .filter(Boolean).sort();
    if (canLead.length) meta.leader_data = { can_lead: canLead };
  }

  return {
    id: existing.id,
    squad_id: existing.squad_id ?? existing.id,
    owner: existing.owner ?? 1,
    status: existing.status ?? 'UNDEPLOYED',
    meta,
    models: modelsOut,
  };
}

// ---------------------------------------------------------------------------
// File conversion
function convertFile(path) {
  const army = JSON.parse(readFileSync(path, 'utf8'));
  const warnings = [];
  const factionName = army.faction?.name ?? '';
  const factionId = FACTION_IDS[normName(factionName)];
  if (!factionId) {
    console.log(`SKIP ${basename(path)} — unknown faction "${factionName}"`);
    return null;
  }
  const lookup = unitsByFaction.get(factionId);
  const lookupLoose = new Map();
  for (const [k, u] of lookup) lookupLoose.set(looseName(u.name), u);
  const aliases = UNIT_ALIASES[factionId] ?? {};

  // 11e enhancements for this file's detachment, keyed by normalized name.
  const detName = normName(army.faction?.detachment ?? '');
  const detachment = detachmentsAll.find(
    d => d.faction_id === factionId && normName(d.name) === detName);
  const detachmentEnh = new Map();
  if (detachment) {
    for (const eid of detachment.enhancement_ids ?? []) {
      const e = enhancementsAll.find(x => x.id === eid);
      if (e) detachmentEnh.set(normName(e.name), e);
    }
  } else if (detName) {
    warnings.push(`detachment "${army.faction.detachment}" not found in 11e ${factionId} detachments`);
  }
  const outUnits = {};
  let totalPoints = 0;
  for (const [key, u] of Object.entries(army.units ?? {})) {
    const name = u.meta?.name ?? '';
    // Placeholder/import-artifact units carry no real datasheet — drop them.
    if ((u.meta?.keywords ?? []).includes('UNKNOWN')) {
      warnings.push(`${key}: placeholder unit "${name}" — REMOVED`);
      continue;
    }
    const aliasId = aliases[normName(name)];
    let dcUnit = aliasId
      ? units.find(x => x.faction_id === factionId && x.id === aliasId)
      : (lookup.get(normName(name)) ?? lookupLoose.get(looseName(name)));
    let unitFactionId = factionId;
    if (!dcUnit) {
      for (const af of ALLIED_FACTIONS[factionId] ?? []) {
        const am = unitsByFaction.get(af);
        const found = am?.get(normName(name));
        if (found) { dcUnit = found; unitFactionId = af; break; }
      }
      if (dcUnit) warnings.push(`${key}: "${name}" resolved as ${unitFactionId} allied unit`);
    }
    if (!dcUnit) {
      warnings.push(`${key}: unit "${name}" has NO 11e datasheet (discontinued/Legends?) — REMOVED`);
      continue;
    }
    const conv = convertUnit(u, dcUnit, unitFactionId, factionName, warnings, detachmentEnh);
    totalPoints += conv.meta.points;
    outUnits[key] = conv;
  }
  const out = {
    faction: {
      ...army.faction,
      created_date: army.faction?.created_date ?? '',
      schema: 2,
      edition: 11,
      data_source: '40kdc-data 1.0.19 (11th edition, launch)',
    },
    units: outUnits,
  };
  return { out, warnings, totalPoints };
}

// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const files = args.length
  ? args
  : readdirSync(ARMIES_DIR).filter(f => f.endsWith('.json')).map(f => join(ARMIES_DIR, f));

for (const f of files) {
  const res = convertFile(f);
  if (!res) continue;
  // The game's exact-name ability dispatch and weapon-id normalization use
  // straight apostrophes — normalize typographic quotes in every string.
  const fixed = JSON.parse(JSON.stringify(res.out), (k, v) =>
    typeof v === 'string' ? v.replace(/[‘’]/g, "'").replace(/[“”]/g, '"') : v);
  writeFileSync(f, JSON.stringify(fixed, null, 1) + '\n');
  console.log(`WROTE ${basename(f)} — ${Object.keys(res.out.units).length} units, ${res.totalPoints} pts`);
  for (const w of res.warnings) console.log(`   ! ${w}`);
}
