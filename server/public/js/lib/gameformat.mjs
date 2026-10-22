// Converter between the 40kdc dataset / roster model and this game's
// schema-2 army JSON (the format ArmyListManager loads).
//
// Shared by:
//  - scripts/40kdc/generate-armies.mjs (Node) — regenerates 40k/armies/*.json
//  - the browser army builder (server/public/js/builder) — exports lists the
//    game can load, and re-imports saved game JSON for editing.
//
// This module is environment-free (no fs / DOM / network). Everything it
// needs — the raw dataset arrays, the ability describer, the game-name canon
// table — is injected through createConverter(), so Node and the browser wire
// it up from their own sources.
//
// The conversion rules here are load-bearing for the game engine:
//  - Weapon structured `abilities` entries must validate against
//    scripts/rules/AbilityRegistry.gd (unknown ids fail the army load).
//  - Ability/enhancement NAMES are dispatched on exact strings by
//    UnitAbilityManager / FactionAbilityManager / ArmyListManager, so emitted
//    names are canonicalized to the game's spelling (canon entries).
//  - Transport abilities are synthesized to match ArmyListManager's regexes.

import { factionScopedResolver, normName, looseName, pointsFor } from './dckit.mjs';

// ---------------------------------------------------------------------------
// Game-facing faction naming.
//
// The game's armies historically use "Space Marines" for adeptus-astartes;
// FactionAbilityManager keys off detachment names and faction KEYWORDS, and
// the army files' faction.name is a display name. Map both directions.
export const FACTION_IDS = {
  'orks': 'orks',
  'adeptus custodes': 'adeptus-custodes',
  'space marines': 'adeptus-astartes',
  'adeptus astartes': 'adeptus-astartes',
};

// faction id -> display name used in game army JSON (fallback: dataset name).
export const FACTION_DISPLAY_OVERRIDES = {
  'adeptus-astartes': 'Space Marines',
};

// 10e -> 11e datasheet renames (per faction id).
export const UNIT_ALIASES = {
  'orks': {
    'nob with waaagh banner': 'bannernob',
  },
  // Codex: Adeptus Custodes (11e, 2026-10-17) renames; the old datasheets
  // stay in the data for pre-codex saves (decision D1), so a regenerated
  // roster moves to the codex datasheet through these aliases.
  'adeptus-custodes': {
    'custodian guard': 'custodian-guard-sodality',
    'prosecutors': 'prosecutor-squad',
    'vigilators': 'vigilator-squad',
    'witchseekers': 'witchseeker-squad',
  },
  'adeptus-astartes': {},
};

// Curated base-size overrides, keyed by dataset unit id.
//
// The 40kdc dataset ships some models with a placeholder base — e.g.
// `{ shape: 'hull' | 'flying-base' | 'unique', draft: true }` with no
// dimensions, or a null base — because Games Workshop sells no separate base
// for them ("Use model"). buildModelsArray() would otherwise fall back to a
// 32mm round for those, which renders far too small. List real footprints
// here; an entry wins over the dataset's (usually draft) base_size_mm for that
// unit. Round bases need `{ shape: 'round', diameter }`; ovals use
// `{ shape: 'oval', length, width }`.
export const BASE_SIZE_OVERRIDES = {
  // Stompa: no GW base (uses the model); play it on a 180mm round footprint.
  'stompa': { shape: 'round', diameter: 180 },
};

// 10e -> 11e weapon renames (matched via looseName; -> 11e weapon id),
// applied when the direct name match fails. Each 11e display name is also
// self-aliased where it differs from the datasheet's weapon_ids (the Telemon's
// arachnus weapons are authored under different ids) so a regenerated file —
// which now carries the 11e name — keeps resolving on the next regeneration.
export const WEAPON_ALIASES_SRC = {
  'adeptus-custodes': {
    'telemon storm cannon': 'arachnus-storm-cannon',
    'twin arachnus las-blaze': 'twin-arachnus-heavy-blaze-cannon',
    'twin arachnus heavy blaze cannon': 'twin-arachnus-heavy-blaze-cannon',
  },
  'orks': {
    'speshul kommando shoota': 'kustom-shoota',
  },
};

// Imperium armies may include Agents of the Imperium allied units
// (alliedRules.json models the gates; the roster files already contain them).
export const ALLIED_FACTIONS = {
  'adeptus-custodes': ['agents-of-the-imperium'],
  'adeptus-astartes': ['agents-of-the-imperium'],
};

// Describes the dataset both converters read, stamped into every army's
// faction.data_source: the browser builder's vendored bundle
// (server/public/js/vendor/40kdc-data.mjs, 40kdc 1.4.5) patched with the
// Wahapedia codex overlay (data-patches.mjs, codex-11e-datasheets.mjs — WP-W3),
// and the game's 40k/data/40kdc extract that scripts/40kdc/generate-armies.mjs
// reads (the same 1.4.5 release + the same import). generate-armies imports
// this constant, so the two stamps cannot drift apart. Update it when the
// bundle version or the Wahapedia snapshot changes
// (server/tests/codex-builder-parity.test.mjs checks it against both).
export const DEFAULT_DATA_SOURCE = '40kdc-data 1.4.5 (11th edition) + Wahapedia 11e codex import 2026-10-16 (Codex: Orks, Codex: Adeptus Custodes) + Wahapedia 11e codex import 2026-10-21 (Codex: Space Marines, Space Wolves)';

// ---------------------------------------------------------------------------
// Weapon conversion
//
// Game structured-ability registry (scripts/rules/AbilityRegistry.gd). Only
// these ids may appear in a weapon's structured `abilities` array — unknown
// ids make ArmyListManager fail the whole army load.
export const KEYWORD_MAP = {
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
export function ruleToken(kw) {
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

// Parameterised core abilities get the exact name shape the engine parses.
export const CORE_PARAM_ABILITIES = [
  // [regex on ability_id, (m) => game ability name matching the engine parsers]
  [/^deadly-demise-(.+)$/, m => `Deadly Demise ${m[1].toUpperCase().replace('D', 'D')}`],
  [/^scouts?-(\d+)$/, m => `Scouts ${m[1]}"`],
  [/^feel-no-pain-(\d+)$/, m => `Feel No Pain ${m[1]}+`],
  [/^firing-deck-(\d+)$/, m => `Firing Deck ${m[1]}`],
];

// Old weapon names may carry a profile suffix ("Kannon – frag").
export function weaponBaseName(s) {
  return String(s).split(/\s+[–-]\s+/)[0];
}

// How many models each composition row gets at a unit size — the split the
// game's models array is built with (buildModelsArray), shared with
// generate-armies.mjs so its wargear lines count the same models. 11e codex
// units come in fixed sizes that are whole multiples of the minimum ("1-2 Nob
// + 9-18 Boy" is 10 or 20 models): when every row scales by that multiple
// within its range, use it (20 Boyz = 2 Nobs + 18 Boyz — the same split
// RulesEngine._positional_roles infers). Otherwise every row but the last
// takes its minimum and the last takes the rest (`minFirst` forces this).
export function compositionCounts(compModels, modelCount, { minFirst = false } = {}) {
  const rows = compModels ?? [];
  const minTotal = rows.reduce((s, m) => s + (m.min ?? 0), 0);
  const mult = minTotal > 0 && modelCount % minTotal === 0 ? modelCount / minTotal : 0;
  if (!minFirst && mult > 1 && rows.every(m => (m.min ?? 0) * mult <= (m.max ?? m.min ?? 0))) {
    return rows.map(m => (m.min ?? 0) * mult);
  }
  const counts = [];
  let remaining = modelCount;
  for (let k = 0; k < rows.length; k++) {
    const take = k === rows.length - 1 ? remaining : Math.min(rows[k].min ?? 0, remaining);
    counts.push(Math.max(0, take));
    remaining -= take;
  }
  // The last row cannot hold the remainder (Wolf Scouts: 1 Pack Leader,
  // 1-2 Hunting Wolves, 4-9 Wolf Scouts at 12 models): every row starts at its
  // minimum and the remainder fills rows from the last one up, each to its
  // maximum (1 / 2 / 9). RulesEngine._positional_roles mirrors this.
  const last = rows.length - 1;
  if (last >= 0 && rows[last].max != null && counts[last] > rows[last].max) {
    const out = rows.map(m => m.min ?? 0);
    let rest = modelCount - out.reduce((a, b) => a + b, 0);
    for (let k = last; k >= 0 && rest > 0; k--) {
      const room = Math.max(0, (rows[k].max ?? rows[k].min ?? 0) - out[k]);
      const add = Math.min(room, rest);
      out[k] += add;
      rest -= add;
    }
    if (rest === 0) return out;
  }
  return counts;
}

// Enhancement names may carry a trailing qualifier in the dataset
// ("Targetin' Gizmos (Upgrade)", "Fear Made Manifest (Aura)", "Memento
// Moritoi (one per army)"); rosters and the game's enhancement tables use the
// bare name. Shared by both converters (generate-armies.mjs, the builder).
export function bareEnhancementName(n) {
  return String(n).replace(/\s*\([^)]*\)\s*$/, '');
}

// The game's exact-name ability dispatch and weapon-id normalization use
// straight apostrophes — normalize typographic quotes in every string.
export function normalizeQuotes(value) {
  return JSON.parse(JSON.stringify(value), (k, v) =>
    typeof v === 'string' ? v.replace(/[‘’]/g, "'").replace(/[“”]/g, '"') : v);
}

// "Beastboss" -> "U_BEASTBOSS"; suffix letters are appended per duplicate.
export function unitKeyBase(name) {
  return 'U_' + String(name).toUpperCase()
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function suffixLetters(n) {
  // 0 -> A, 25 -> Z, 26 -> AA ...
  let s = '';
  n += 1;
  while (n > 0) {
    n -= 1;
    s = String.fromCharCode(65 + (n % 26)) + s;
    n = Math.floor(n / 26);
  }
  return s;
}

// ---------------------------------------------------------------------------
/**
 * Build a converter over the raw dataset arrays.
 *
 * @param rawData        object with the raw collections: units, weapons,
 *                       abilities, unitCompositions, leaderAttachments,
 *                       enhancements, detachments, factions (the shape of the
 *                       package's RAW_DATA / the files in 40k/data/40kdc).
 * @param describeAbility  (ability) => string — the package's ability-DSL
 *                       translator. Injected because it lives in the package,
 *                       not in this repo.
 * @param canonEntries   [[normName, GameSpelling], ...] — names the game
 *                       dispatches on (built from the .gd tables). Optional.
 * @param dataSource     data_source string stamped into faction blocks.
 */
export function createConverter({ rawData, describeAbility, canonEntries = [], dataSource = DEFAULT_DATA_SOURCE }) {
  const units = rawData.units;
  const weapons = rawData.weapons;
  const abilities = rawData.abilities;
  const compositions = rawData.unitCompositions;
  const leaderAttachments = rawData.leaderAttachments;
  const enhancementsAll = rawData.enhancements;
  const detachmentsAll = rawData.detachments;
  const factions = rawData.factions;
  const wargearNameById = new Map((rawData.wargear ?? []).map(w => [w.id, w.name]));

  const wres = factionScopedResolver(weapons, units, w => w.id, u => u.weapon_ids);
  const ares = factionScopedResolver(abilities, units, a => a.ability_id, u => u.ability_ids,
    a => a.faction_id ?? null);

  const canon = new Map(canonEntries);
  function canonicalName(name) {
    return canon.get(normName(name)) ?? name;
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

  // The army rule (Waaagh!, Martial Ka'tah, Oath of Moment ...) — every unit of
  // the faction carries it in meta.abilities; FactionAbilityManager detects it
  // by exact name. Some faction_rule_id slugs dangle (e.g. `martial-katah` vs
  // ability `martial-ka-tah`), so fall back to a loose-slug scan.
  // Dataset 1.4.x replaced `faction_rule_id` (string) with `faction_rule_ids`
  // (array; Tyranids carry two rules) — read both shapes so army rules are not
  // silently dropped from converted rosters.
  function factionRuleIds(f) {
    if (Array.isArray(f?.faction_rule_ids)) return f.faction_rule_ids.filter(Boolean);
    return f?.faction_rule_id ? [f.faction_rule_id] : [];
  }

  function resolveFactionRule(factionId, ruleId) {
    let rule = abilities.find(a => a.ability_id === ruleId);
    if (!rule) {
      const want = ruleId.replace(/-/g, '');
      rule = abilities.find(a =>
        a.ability_type === 'faction' &&
        (a.faction_id === factionId || !a.faction_id) &&
        a.ability_id.replace(/-/g, '') === want);
    }
    return rule ?? null;
  }

  // Every army rule of the faction, in dataset order (unresolvable ids skipped).
  function factionRuleAbilities(factionId) {
    const f = factions.find(x => x.id === factionId);
    const out = [];
    for (const rid of factionRuleIds(f)) {
      const rule = resolveFactionRule(factionId, rid);
      if (rule && !out.includes(rule)) out.push(rule);
    }
    return out;
  }

  // First army rule (back-compat single-rule API).
  function factionRuleAbility(factionId) {
    return factionRuleAbilities(factionId)[0] ?? null;
  }

  function safeDescribe(a) {
    // Records imported from a codex transcription (scripts/40kdc/
    // wahapedia-import.mjs) carry the printed rules text — prefer it over a
    // description generated from a (possibly pre-codex) ability DSL.
    if (a?.rules_text) return a.rules_text;
    try {
      const d = describeAbility(a);
      return typeof d === 'string' ? d : String(d ?? '');
    } catch {
      return a.community_notes ?? '';
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

  // Transport description synthesized to match ArmyListManager's regexes.
  function transportAbility(factionKeyword, unit) {
    const tc = unit.transport_capacity;
    const kw = `${factionKeyword.toUpperCase()} INFANTRY`;
    let desc = `This model has a transport capacity of ${tc.capacity} ${kw} models.`;
    for (const ex of tc.exclusion_keywords ?? []) {
      desc += ` This model cannot transport models that are ${ex.toUpperCase()} models.`;
    }
    // ArmyListManager parses "Each <KEYWORD> model takes up the space of <N> models".
    for (const m of tc.multipliers ?? []) {
      desc += ` Each ${String(m.keyword).toUpperCase()} model takes up the space of ${m.spaces} models.`;
    }
    return { name: 'TRANSPORT', type: 'Core', description: desc };
  }

  // --- non-weapon wargear (Praesidium Shield, Vexilla, Kustom Force Field ...)
  // A codex datasheet lists its wargear as `wargear` abilities; its
  // composition names the default ones in `default_wargear` and its wargear
  // options reference them by ability id (wahapedia-import.mjs). The builder
  // counts them in the unit's loadout like weapons, so the export can say
  // which models took one, gate the wargear ability on it (Vexilla's +1 OC is
  // applied from meta.abilities) and price it (wargear_points).
  function wargearItems(dcUnit, factionId) {
    const out = new Map();
    for (const aid of dcUnit?.ability_ids ?? []) {
      const a = ares.resolve(factionId, aid);
      if (a?.ability_type === 'wargear') out.set(aid, { id: aid, name: a.name });
    }
    return out;
  }

  // Composition rows for the package's loadout maths (baseLoadout /
  // weaponBounds / validateLoadout): default_weapon_ids plus the row's
  // default_wargear items, so a default Praesidium Shield is part of the base
  // loadout and swapping it away is a counted swap. Rows are copied, never
  // mutated; units without wargear items get the composition's own rows.
  function loadoutModels(dcUnit, factionId, comp) {
    const models = comp?.models;
    const items = wargearItems(dcUnit, factionId);
    if (!models || !items.size) return models;
    const idByName = new Map([...items.values()].map(i => [looseName(i.name), i.id]));
    return models.map(m => {
      const extra = (m.default_wargear ?? []).map(n => idByName.get(looseName(n))).filter(Boolean);
      return extra.length ? { ...m, default_weapon_ids: [...(m.default_weapon_ids ?? []), ...extra] } : m;
    });
  }

  // Priced wargear: the codex "per Praesidium Shield 25" rows
  // (unit.wargear_points [{name, cost}], wahapedia-import.mjs) cost `cost` for
  // each copy of the item with exactly that name. (40kdc's own wargear_costs
  // are not priced, as in generate-armies.mjs.)
  function wargearPriceOf(dcUnit, itemName) {
    const key = looseName(weaponBaseName(itemName).replace(/\s*\([^)]*\)\s*$/, ''));
    let cost = 0;
    for (const wp of dcUnit?.wargear_points ?? []) if (looseName(wp.name) === key) cost += wp.cost;
    return cost;
  }

  /** Wargear points for a unit-wide loadout (Map<weapon or item id, count>). */
  function wargearPointsFor(dcUnit, factionId, counts) {
    if (!(dcUnit?.wargear_points ?? []).length) return 0;
    const items = wargearItems(dcUnit, factionId);
    let pts = 0;
    for (const [id, n] of counts ?? []) {
      if (!n || n <= 0) continue;
      // Non-weapon gear without an ability record (the Space Marine
      // "storm-shield", priced "per Storm Shield 5") is named in rawData.wargear.
      const name = items.get(id)?.name ?? wres.resolve(factionId, id)?.name ?? wargearNameById.get(id);
      if (name) pts += wargearPriceOf(dcUnit, name) * n;
    }
    return pts;
  }

  /** Wargear points for game-format wargear lines ("2x Killsaw"; a line
   * without a count — "Shield-Captain (Shield), Praesidium Shield" — counts
   * each comma part once). Used by generate-armies.mjs. */
  function wargearPointsForLines(dcUnit, lines) {
    if (!(dcUnit?.wargear_points ?? []).length) return 0;
    let pts = 0;
    for (const entry of lines ?? []) {
      const m = String(entry).match(/^\s*(\d+)\s*x\s+(.+)$/i);
      if (m) { pts += wargearPriceOf(dcUnit, m[2].trim()) * parseInt(m[1], 10); continue; }
      for (const part of String(entry).split(',')) pts += wargearPriceOf(dcUnit, part.trim());
    }
    return pts;
  }

  // --- keywords: dataset keywords + faction keywords, uppercased
  function unitKeywords(dcUnit) {
    return [...new Set(
      [...(dcUnit.keywords ?? []), ...(dcUnit.faction_keywords ?? [])]
        .map(k => k.toUpperCase()))].sort();
  }

  function unitStats(dcUnit) {
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
    return stats;
  }

  // --- composition lines
  function compositionLines(comp) {
    const compOut = [];
    let line = 1;
    for (const m of comp?.models ?? []) {
      const desc = m.min === m.max ? `${m.min} ${m.name}` : `${m.min}-${m.max} ${m.name}`;
      compOut.push({ description: desc, line: line++ });
    }
    return compOut;
  }

  // --- models array: composition rows scaled to the chosen model count.
  // Order = leader model first (composition order); wounds/base per row profile.
  function buildModelsArray(dcUnit, comp, modelCount) {
    const prof = dcUnit.profiles[0];
    const profByName = new Map(dcUnit.profiles.map(p => [normName(p.name), p]));
    function profileFor(modelName, profileName) {
      return profByName.get(normName(profileName ?? '')) ??
        profByName.get(normName(modelName)) ?? prof;
    }
    const modelsOut = [];
    let mi = 1;
    const compModels = comp?.models ?? [{ name: dcUnit.name, min: modelCount, max: modelCount }];
    const counts = compositionCounts(compModels, modelCount);
    for (let k = 0; k < compModels.length; k++) {
      const m = compModels[k];
      const p = profileFor(m.name, m.profile_name);
      // A curated override wins over the dataset's base (often a dimensionless
      // draft), then the per-composition-model base, then the unit default.
      const base = BASE_SIZE_OVERRIDES[dcUnit.id]
        ?? m.base_size_mm ?? dcUnit.base_size_mm ?? { shape: 'round', diameter: 32 };
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
    return modelsOut;
  }

  // --- leader data
  function leaderData(dcUnit, factionId) {
    const bg = bodyguardsByLeader.get(dcUnit.id);
    if (bg && (dcUnit.attachment_role === 'leader' || dcUnit.role === 'character' || dcUnit.role === 'epic-hero')) {
      const canLead = [...bg]
        .map(bid => unitById.get(`${factionId}::${bid}`)?.name?.toUpperCase())
        .filter(Boolean).sort();
      if (canLead.length) return { can_lead: canLead };
    }
    return null;
  }

  // --- abilities (faction army rule first, mirroring the existing files)
  // `hasWargear(name)` (optional): does this roster entry carry the named
  // wargear? Codex datasheets list their wargear abilities (Vexilla,
  // Praesidium Shield) on the datasheet; a unit only has the ability when it
  // took the wargear, and ArmyListManager applies wargear stat bonuses from
  // meta.abilities. Without a predicate every listed ability is emitted.
  // armyFactionId: the army's faction when it is a chapter of the unit's
  // faction (Space Wolves -> adeptus-astartes datasheets). A chapter whose
  // record carries its own army rules (Codex: Space Marines: Combat
  // Doctrines, not the index Oath of Moment) gives those to every unit.
  function unitAbilities(dcUnit, factionId, factionName, warnings, hasWargear = null, armyFactionId = null) {
    const abilitiesOut = [];
    const army = armyFactionId ? factions.find(f => f.id === armyFactionId) : null;
    const ruleFaction = army && army.parent_faction_id === factionId && army.source_codex ? armyFactionId : factionId;
    const ruleNames = new Set();
    for (const rule of factionRuleAbilities(ruleFaction)) {
      abilitiesOut.push({ name: canonicalName(rule.name), type: 'Faction', description: safeDescribe(rule) });
      ruleNames.add(normName(rule.name));
    }
    for (const aid of dcUnit.ability_ids ?? []) {
      const rec = ares.resolve(factionId, aid);
      if (rec && ruleNames.has(normName(rec.name))) continue; // the army rule, listed once
      if (hasWargear && rec?.ability_type === 'wargear' && !hasWargear(rec.name)) continue;
      const conv = convertAbility(factionId, dcUnit, aid, warnings);
      if (conv) abilitiesOut.push(conv);
    }
    if (dcUnit.transport_capacity) abilitiesOut.push(transportAbility(factionName, dcUnit));
    return abilitiesOut;
  }

  // -------------------------------------------------------------------------
  // Faction/detachment/enhancement lookups (shared ids resolved per faction).

  function factionIdForName(name) {
    const key = normName(name ?? '');
    if (FACTION_IDS[key]) return FACTION_IDS[key];
    for (const f of factions) {
      if (normName(f.name) === key) return f.id;
      for (const alias of f.aliases ?? []) {
        if (normName(alias) === key) return f.id;
      }
    }
    return null;
  }

  function factionDisplayName(factionId) {
    if (FACTION_DISPLAY_OVERRIDES[factionId]) return FACTION_DISPLAY_OVERRIDES[factionId];
    return factions.find(f => f.id === factionId)?.name ?? factionId;
  }

  function detachmentsOf(factionId) {
    return detachmentsAll.filter(d => d.faction_id === factionId);
  }

  function findDetachment(factionId, nameOrId) {
    const key = normName(nameOrId ?? '');
    return detachmentsAll.find(d => d.faction_id === factionId &&
      (d.id === nameOrId || normName(d.name) === key)) ?? null;
  }

  // Enhancements of one detachment, keyed by normalized name AND id.
  function detachmentEnhancements(detachment) {
    const out = new Map();
    for (const eid of detachment?.enhancement_ids ?? []) {
      const e = enhancementsAll.find(x => x.id === eid);
      if (e) {
        out.set(normName(e.name), e);
        // also by the bare name ("Targetin' Gizmos" for "... (Upgrade)")
        const bare = normName(bareEnhancementName(e.name));
        if (!out.has(bare)) out.set(bare, e);
        out.set(e.id, e);
      }
    }
    return out;
  }

  // Faction-scoped unit lookup by display name, with alias + allied fallback.
  function findUnitByName(factionId, name, warnings = [], key = '') {
    const lookup = unitsByFaction.get(factionId) ?? new Map();
    const aliases = UNIT_ALIASES[factionId] ?? {};
    const aliasId = aliases[normName(name)];
    if (aliasId) {
      const u = units.find(x => x.faction_id === factionId && x.id === aliasId);
      if (u) return { unit: u, factionId };
    }
    let dcUnit = lookup.get(normName(name));
    if (!dcUnit) {
      for (const [k, u] of lookup) {
        if (looseName(u.name) === looseName(name)) { dcUnit = u; break; }
      }
    }
    if (dcUnit) return { unit: dcUnit, factionId };
    for (const af of ALLIED_FACTIONS[factionId] ?? []) {
      const am = unitsByFaction.get(af);
      const found = am?.get(normName(name));
      if (found) {
        warnings.push(`${key}: "${name}" resolved as ${af} allied unit`);
        return { unit: found, factionId: af };
      }
    }
    return null;
  }

  // Faction-scoped unit lookup by 40kdc id, with allied + any-faction fallback.
  function findUnitById(factionId, unitId) {
    let u = unitById.get(`${factionId}::${unitId}`);
    if (u) return { unit: u, factionId };
    for (const af of ALLIED_FACTIONS[factionId] ?? []) {
      u = unitById.get(`${af}::${unitId}`);
      if (u) return { unit: u, factionId: af };
    }
    const any = units.find(x => x.id === unitId);
    return any ? { unit: any, factionId: any.faction_id } : null;
  }

  // -------------------------------------------------------------------------
  /**
   * Assemble one game-format unit from explicit build choices.
   *
   * @param dcUnit        raw 40kdc unit record
   * @param unitFactionId faction the unit is authored under (allied units differ)
   * @param armyFactionId the army's faction (army rule comes from here)
   * @param factionName   army display name (transport keyword text)
   * @param modelCount    chosen squad size
   * @param counts        Map<weaponId, count> — the unit-wide loadout
   * @param isWarlord     bool
   * @param enhancements  [{ name, cost }] — already resolved, cost in points
   * @param id            unit key (U_..._A)
   * @param owner         player number
   * @param ordinal       which copy of this datasheet in the army (1-based;
   *                      11e repeat pricing surcharges later copies)
   */
  function buildGameUnit({ dcUnit, unitFactionId, armyFactionId, factionName, modelCount,
                           counts, isWarlord = false, enhancements = [], id, owner = 1,
                           ordinal = 1 }, warnings = []) {
    const comp = compByUnit.get(`${unitFactionId}::${dcUnit.id}`);

    const weaponsOut = [];
    const seenWeaponNames = new Set();
    const wargearStrings = [];
    const validIds = new Set(dcUnit.weapon_ids ?? []);
    // Alias targets are faction-authored weapons a renamed datasheet entry
    // points at (e.g. the Telemon's arachnus guns) — allowed like the Node
    // generator allows them.
    for (const wid of Object.values(WEAPON_ALIASES_SRC[unitFactionId] ?? {})) validIds.add(wid);
    // Non-weapon wargear the loadout holds (Praesidium Shield, Vexilla):
    // listed as a wargear line ("1x Vexilla"), never as a weapon profile.
    const items = wargearItems(dcUnit, unitFactionId);
    const held = new Set();
    for (const [wid, count] of counts) {
      if (!count || count <= 0) continue;
      const item = items.get(wid);
      if (item) {
        held.add(looseName(item.name));
        wargearStrings.push(`${count}x ${item.name}`);
        continue;
      }
      if (!validIds.has(wid)) {
        warnings.push(`${id}: weapon "${wid}" not on ${dcUnit.name} datasheet — dropped`);
        continue;
      }
      const w = wres.resolve(unitFactionId, wid);
      if (!w) { warnings.push(`${id}: weapon not found: ${wid}`); continue; }
      wargearStrings.push(`${count}x ${w.name}`);
      if (!seenWeaponNames.has(w.name)) {
        seenWeaponNames.add(w.name);
        weaponsOut.push(...convertWeapon(unitFactionId, wid, warnings));
      }
    }
    weaponsOut.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'Ranged' ? -1 : 1));
    wargearStrings.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));

    // Allied units carry their own faction's army rule (mirrors generate-armies).
    // A wargear ability (Vexilla, Praesidium Shield) only when the loadout
    // holds that wargear — the game applies e.g. Vexilla's +1 OC from it.
    const hasWargear = items.size ? (n => held.has(looseName(n))) : null;
    const abilitiesOut = unitAbilities(dcUnit, unitFactionId, factionName, warnings, hasWargear, armyFactionId);

    const enhancementPoints = enhancements.reduce((s, e) => s + (e.cost ?? 0), 0);
    const points = pointsFor(dcUnit, modelCount, ordinal) +
      wargearPointsFor(dcUnit, unitFactionId, counts) + enhancementPoints;

    const meta = {
      name: dcUnit.name,
      keywords: unitKeywords(dcUnit),
      stats: unitStats(dcUnit),
      points,
      is_warlord: !!isWarlord,
      // the bare name the game keys on, as generate-armies.mjs writes it
      enhancements: enhancements.map(e => canonicalName(bareEnhancementName(e.name))),
      wargear: wargearStrings,
      weapons: weaponsOut,
      abilities: abilitiesOut,
      unit_composition: compositionLines(comp),
    };
    const ld = leaderData(dcUnit, unitFactionId);
    if (ld) meta.leader_data = ld;

    return {
      id,
      squad_id: id,
      owner,
      status: 'UNDEPLOYED',
      meta,
      models: buildModelsArray(dcUnit, comp, modelCount),
    };
  }

  // -------------------------------------------------------------------------
  /**
   * Convert a 40kdc Roster (the package's import/builder model) into the
   * game's schema-2 army JSON.
   *
   * Roster units whose ref did not resolve are passed through verbatim when
   * they carry a `_raw_game_unit` (a unit imported from game JSON we could not
   * match to a datasheet); otherwise they are skipped with a warning.
   *
   * @returns { army, warnings }
   */
  function rosterToGame(roster, { owner = 1, createdDate = '', playerName = '', teamName = '' } = {}) {
    const warnings = [];
    const armyFactionId = roster.faction_id;
    if (!armyFactionId) {
      warnings.push('roster has no resolved faction — cannot convert');
      return { army: null, warnings };
    }
    const factionName = factionDisplayName(armyFactionId);

    // 11e: several detachments within the DP pool. The first is the primary
    // (faction.detachment — what the game's single-detachment rule hooks
    // read); all of them go out as faction.detachments + detachments[] (DP).
    const detsOut = [];
    for (const rd of roster.detachments ?? []) {
      const det = rd?.ref;
      if (det?.id) {
        const d = findDetachment(armyFactionId, det.id);
        detsOut.push({ name: d?.name ?? det.raw_name ?? '', dp_cost: d?.detachment_points ?? rd.dp_cost ?? 1, record: d });
      } else if (det?.raw_name) {
        warnings.push(`detachment "${det.raw_name}" unresolved — name kept as-is`);
        detsOut.push({ name: det.raw_name, dp_cost: rd.dp_cost ?? 1, record: findDetachment(armyFactionId, det.raw_name) });
      }
    }
    const detachmentName = detsOut[0]?.name ?? '';
    const detEnh = new Map();
    for (const d of detsOut) {
      for (const [k, e] of detachmentEnhancements(d.record)) if (!detEnh.has(k)) detEnh.set(k, e);
    }

    const unitsOut = {};
    const suffixCounters = new Map();
    // Per-datasheet copy counter (same keying as the builder's repriceAll) —
    // 11e repeat pricing makes later copies of a datasheet cost more.
    const dcOrdinals = new Map();
    function nextKey(name) {
      const base = unitKeyBase(name);
      const n = suffixCounters.get(base) ?? 0;
      suffixCounters.set(base, n + 1);
      return `${base}_${suffixLetters(n)}`;
    }

    for (const ru of roster.units ?? []) {
      // Pass-through for units we couldn't match to a datasheet.
      if (!ru.ref?.id) {
        if (ru._raw_game_unit) {
          const raw = JSON.parse(JSON.stringify(ru._raw_game_unit));
          const key = nextKey(raw.meta?.name ?? ru.ref?.raw_name ?? 'UNKNOWN');
          raw.id = key;
          raw.squad_id = key;
          raw.owner = owner;
          if (raw.meta) raw.meta.is_warlord = !!ru.is_warlord;
          unitsOut[key] = raw;
          warnings.push(`${key}: "${raw.meta?.name ?? '?'}" kept as-is (no 11e datasheet match)`);
        } else {
          warnings.push(`unit "${ru.ref?.raw_name ?? '?'}" unresolved — skipped`);
        }
        continue;
      }

      const found = findUnitById(armyFactionId, ru.ref.id);
      if (!found) {
        warnings.push(`unit "${ru.ref.raw_name}" (${ru.ref.id}) not in dataset — skipped`);
        continue;
      }
      const { unit: dcUnit, factionId: unitFactionId } = found;
      // A chapter (Space Wolves) builds from its parent's datasheets — not allies.
      const parentId = factions.find(f => f.id === armyFactionId)?.parent_faction_id ?? null;
      if (unitFactionId !== armyFactionId && unitFactionId !== parentId) {
        warnings.push(`${dcUnit.name}: resolved as ${unitFactionId} allied unit`);
      }

      const counts = new Map();
      for (const wg of ru.wargear ?? []) {
        if (wg.ref?.id) counts.set(wg.ref.id, (counts.get(wg.ref.id) ?? 0) + wg.count);
        else if (wg.ref?.raw_name) warnings.push(`${dcUnit.name}: wargear "${wg.ref.raw_name}" unresolved — dropped`);
      }

      const enhancements = [];
      if (ru.enhancement?.id || ru.enhancement?.ref?.id) {
        const eid = ru.enhancement.id ?? ru.enhancement.ref.id;
        const e = detEnh.get(eid) ?? enhancementsAll.find(x => x.id === eid);
        if (e) enhancements.push({ name: e.name, cost: e.cost ?? 0 });
        else warnings.push(`${dcUnit.name}: enhancement "${eid}" not found — dropped`);
      } else if (ru.enhancement?.ref?.raw_name) {
        warnings.push(`${dcUnit.name}: enhancement "${ru.enhancement.ref.raw_name}" unresolved — dropped`);
      }

      const key = nextKey(dcUnit.name);
      const ordinal = (dcOrdinals.get(dcUnit.id) ?? 0) + 1;
      dcOrdinals.set(dcUnit.id, ordinal);
      unitsOut[key] = buildGameUnit({
        dcUnit, unitFactionId, armyFactionId, factionName,
        modelCount: ru.model_count ?? 1,
        counts,
        isWarlord: !!ru.is_warlord,
        enhancements,
        id: key,
        owner,
        ordinal,
      }, warnings);
    }

    const declaredPoints = roster.points?.declared_limit ?? null;
    const totalPoints = Object.values(unitsOut).reduce((s, u) => s + (u.meta?.points ?? 0), 0);

    const army = normalizeQuotes({
      faction: {
        name: factionName,
        points: declaredPoints ?? (totalPoints > 1000 ? 2000 : 1000),
        detachment: detachmentName,
        detachments: detsOut.map(d => d.name),
        // 11e: the one Force Disposition the army picked (from its detachments).
        force_disposition: roster.force_disposition ?? '',
        player_name: playerName,
        team_name: teamName,
        created_date: createdDate,
        schema: 2,
        edition: 11,
        data_source: dataSource,
      },
      detachments: detsOut.map(d => ({ name: d.name, dp_cost: d.dp_cost })),
      units: unitsOut,
    });
    return { army, warnings, totalPoints };
  }

  // -------------------------------------------------------------------------
  /**
   * Reverse: game schema-2 army JSON -> a 40kdc Roster the builder can edit.
   *
   * Units that can't be matched to an 11e datasheet come back with an
   * unresolved ref carrying `_raw_game_unit` so rosterToGame can round-trip
   * them untouched.
   *
   * @returns { roster, warnings }
   */
  function gameToRoster(gameJson, { name = '' } = {}) {
    const warnings = [];
    const factionBlock = gameJson?.faction ?? {};
    const armyFactionId = factionIdForName(factionBlock.name);
    if (!armyFactionId) warnings.push(`faction "${factionBlock.name ?? ''}" not recognized`);

    // Primary detachment first, then any further 11e detachments
    // (faction.detachments names, or top-level detachments[{name, dp_cost}]).
    const detNames = [];
    for (const n of [factionBlock.detachment,
      ...(Array.isArray(factionBlock.detachments) ? factionBlock.detachments : []),
      ...(Array.isArray(gameJson?.detachments) ? gameJson.detachments.map(d => d?.name) : [])]) {
      const nm = typeof n === 'string' ? n.trim() : '';
      if (nm && !detNames.some(x => normName(x) === normName(nm))) detNames.push(nm);
    }
    const detRecords = detNames.map(nm => {
      const d = armyFactionId ? findDetachment(armyFactionId, nm) : null;
      if (armyFactionId && !d) warnings.push(`detachment "${nm}" not found for ${armyFactionId}`);
      return { name: nm, record: d };
    });
    const resolvedDets = detRecords.map(d => d.record).filter(Boolean);
    const detEnh = new Map();
    for (const d of resolvedDets) {
      for (const [k, e] of detachmentEnhancements(d)) if (!detEnh.has(k)) detEnh.set(k, e);
    }

    const rosterUnits = [];
    let computed = 0;
    for (const [key, gu] of Object.entries(gameJson?.units ?? {})) {
      const meta = gu?.meta ?? {};
      const unitName = meta.name ?? key;
      const modelCount = (gu.models ?? []).length || 1;

      const found = armyFactionId ? findUnitByName(armyFactionId, unitName, warnings, key) : null;
      if (!found || (meta.keywords ?? []).includes('UNKNOWN')) {
        warnings.push(`${key}: "${unitName}" has no 11e datasheet — kept as-is (not editable)`);
        rosterUnits.push({
          ref: { id: null, raw_name: unitName, resolved: false, candidates: [] },
          model_count: modelCount,
          points: meta.points ?? null,
          is_warlord: !!meta.is_warlord,
          enhancement: null,
          enhancement_points: null,
          wargear: [],
          leader_attachment: null,
          _raw_game_unit: JSON.parse(JSON.stringify(gu)),
        });
        computed += meta.points ?? 0;
        continue;
      }
      const { unit: dcUnit, factionId: unitFactionId } = found;

      // Loadout reconstruction. Legacy files are lossy: `meta.wargear` lines
      // ("2x Big shoota") carry counts but mix in composition model names
      // ("9x Boy"), and `meta.weapons` carries every carried profile without
      // counts. Merge both: counted lines win, model names are skipped
      // silently, and any weapon present only in meta.weapons joins at 1x.
      const counts = new Map();
      const nameToId = new Map();
      for (const wid of dcUnit.weapon_ids ?? []) {
        const w = wres.resolve(unitFactionId, wid);
        if (w) nameToId.set(looseName(w.name), wid);
      }
      const aliasMap = {};
      const aliasTargets = new Set();
      for (const [k2, v2] of Object.entries(WEAPON_ALIASES_SRC[unitFactionId] ?? {})) {
        aliasMap[looseName(k2)] = v2;
        aliasTargets.add(v2);
      }
      // Non-weapon wargear (Praesidium Shield, Vexilla) is counted too.
      const items = wargearItems(dcUnit, unitFactionId);
      for (const [iid, item] of items) nameToId.set(looseName(item.name), iid);
      const acceptableId = (wid) => (dcUnit.weapon_ids ?? []).includes(wid) || aliasTargets.has(wid) || items.has(wid);
      function weaponIdFor(rawName) {
        const base = weaponBaseName(rawName).replace(/^\d+\s*x\s*/i, '');
        return nameToId.get(looseName(base)) ?? aliasMap[looseName(base)] ?? null;
      }
      const compModelNames = new Set(
        (compByUnit.get(`${unitFactionId}::${dcUnit.id}`)?.models ?? [])
          .map(m => looseName(m.name)));
      compModelNames.add(looseName(dcUnit.name));
      const wargearEntries = [];
      let approximate = false;
      for (const line of meta.wargear ?? []) {
        const m = String(line).match(/^\s*(\d+)\s*x\s+(.+)$/i);
        if (!m) {
          // A descriptive line ("Shield-Captain (Shield), Praesidium Shield"):
          // each comma part naming a wargear item holds one.
          for (const part of String(line).split(',')) {
            const iid = nameToId.get(looseName(part.trim()));
            if (iid && items.has(iid) && !counts.has(iid)) counts.set(iid, 1);
          }
          continue;
        }
        const rawName = m[2].trim();
        const wid = weaponIdFor(rawName);
        if (wid && acceptableId(wid)) {
          counts.set(wid, (counts.get(wid) ?? 0) + parseInt(m[1], 10));
        } else if (compModelNames.has(looseName(rawName)) ||
                   compModelNames.has(looseName(rawName.replace(/s$/i, '')))) {
          // A model-count line ("9x Boy"), not a weapon — skip silently.
        } else {
          wargearEntries.push({ ref: { id: null, raw_name: rawName, resolved: false, candidates: [] }, count: parseInt(m[1], 10) });
          warnings.push(`${key}: wargear "${rawName}" not matched to the ${dcUnit.name} datasheet`);
        }
      }
      for (const w of meta.weapons ?? []) {
        const wid = weaponIdFor(w.name ?? '');
        if (wid && acceptableId(wid) && !counts.has(wid)) {
          counts.set(wid, 1);
          approximate = true;
        }
      }
      if (approximate) {
        warnings.push(`${key}: some weapon counts missing in file — reconstructed at 1x, review loadout`);
      }
      for (const [wid, count] of counts) {
        const w = wres.resolve(unitFactionId, wid);
        wargearEntries.unshift({ ref: { id: wid, raw_name: w?.name ?? items.get(wid)?.name ?? wid, resolved: true, candidates: [] }, count });
      }

      // Enhancement: names like "Follow Me Ladz" or "X (+25 pts)".
      let enhancement = null;
      let enhancementPoints = null;
      for (const e of meta.enhancements ?? []) {
        let ename = typeof e === 'string' ? e : (e?.name ?? '');
        ename = ename.replace(/\s*\(\+?\d+\s*pts?\)\s*$/i, '');
        if (!ename) continue;
        const match = detEnh.get(normName(ename)) ??
          detEnh.get(normName(bareEnhancementName(ename))) ??
          enhancementsAll.find(x => normName(bareEnhancementName(x.name)) === normName(bareEnhancementName(ename)) &&
            (!resolvedDets.length || resolvedDets.some(d => (d.enhancement_ids ?? []).includes(x.id))));
        if (match) {
          enhancement = { id: match.id, raw_name: match.name, resolved: true, candidates: [] };
          enhancementPoints = match.cost ?? 0;
        } else {
          enhancement = { id: null, raw_name: ename, resolved: false, candidates: [] };
          warnings.push(`${key}: enhancement "${ename}" not found in detachment — will be dropped on export`);
        }
        break; // one enhancement per unit
      }

      const basePoints = pointsFor(dcUnit, modelCount) + wargearPointsFor(dcUnit, unitFactionId, counts);
      computed += basePoints + (enhancementPoints ?? 0);

      rosterUnits.push({
        ref: { id: dcUnit.id, raw_name: unitName, resolved: true, candidates: [] },
        model_count: modelCount,
        points: basePoints,
        is_warlord: !!meta.is_warlord,
        enhancement,
        enhancement_points: enhancementPoints,
        wargear: wargearEntries,
        leader_attachment: null,
        _unit_faction_id: unitFactionId,
      });
    }

    const declared = factionBlock.points ?? null;
    const roster = {
      name: name || (factionBlock.name ? `${factionBlock.name} ${declared ?? ''}`.trim() : 'Imported army'),
      source: { format: 'roster-json', generated_by: 'w40k-game-json' },
      faction_id: armyFactionId,
      detachments: detRecords.map(({ name: nm, record: d }) => d
        ? { ref: { id: d.id, raw_name: d.name, resolved: true, candidates: [] }, dp_cost: d.detachment_points ?? 1 }
        : { ref: { id: null, raw_name: nm, resolved: false, candidates: [] }, dp_cost: null }),
      battle_size: declared == null ? null : (declared <= 1000 ? 'incursion' : 'strike-force'),
      force_disposition: factionBlock.force_disposition || null,
      points: {
        declared_limit: declared,
        detachment_cap: declared == null ? null : (declared <= 1000 ? 2 : 3),
        total_reported: null,
        total_computed: computed,
      },
      units: rosterUnits,
      game_version: { edition: '11th', dataslate: 'launch' },
      diagnostics: {
        resolved_units: rosterUnits.filter(u => u.ref.resolved).length,
        unresolved_units: rosterUnits.filter(u => !u.ref.resolved).length,
        resolved_weapons: rosterUnits.reduce((s, u) => s + u.wargear.filter(w => w.ref.resolved).length, 0),
        unresolved_weapons: rosterUnits.reduce((s, u) => s + u.wargear.filter(w => !w.ref.resolved).length, 0),
        warnings: warnings.map(w => ({ code: 'unknown-field', message: w, raw_name: null })),
      },
    };
    return { roster, warnings };
  }

  return {
    // low-level conversion primitives (used by generate-armies.mjs)
    wres, ares,
    canonicalName,
    safeDescribe,
    convertWeapon,
    convertAbility,
    transportAbility,
    factionRuleAbility,
    factionRuleAbilities,
    unitKeywords,
    unitStats,
    wargearItems,
    loadoutModels,
    wargearPointsFor,
    wargearPointsForLines,
    compositionLines,
    buildModelsArray,
    leaderData,
    unitAbilities,
    // faction/unit/detachment lookups
    factionIdForName,
    factionDisplayName,
    detachmentsOf,
    findDetachment,
    detachmentEnhancements,
    findUnitByName,
    findUnitById,
    unitsByFaction,
    compByUnit,
    bodyguardsByLeader,
    unitById,
    // high-level
    buildGameUnit,
    rosterToGame,
    gameToRoster,
  };
}
