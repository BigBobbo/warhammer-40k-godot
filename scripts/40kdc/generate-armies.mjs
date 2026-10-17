#!/usr/bin/env node
// Regenerate 40k/armies/*.json (schema 2) from the 11th-edition 40kdc dataset.
//
// For each existing army file the generator preserves the ROSTER — unit keys,
// owners, model counts, warlord flag, weapon loadout choices — and rebuilds
// every datasheet fact (stats, points, weapon profiles, abilities, keywords,
// base sizes, composition, leader pairings, transport capacity) from the
// extracted 11e data in 40k/data/40kdc/.
//
// The conversion primitives (weapon/ability/statline conversion, model array
// building, name canonicalization) live in server/public/js/lib/gameformat.mjs
// and are shared with the browser army builder — change them there.
//
// Usage: node generate-armies.mjs [file.json ...]   (default: all in 40k/armies)

import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { dirname, join, basename } from 'path';
import { fileURLToPath } from 'url';
import { loadCollection, normName, looseName, pointsFor, buildCanonEntries, DATA_DIR as DATA_DIR_FOR_LEGACY } from './lib.mjs';
import { describeAbility } from '@alpaca-software/40kdc-data';
import {
  createConverter, normalizeQuotes, weaponBaseName,
  FACTION_IDS, UNIT_ALIASES, WEAPON_ALIASES_SRC, ALLIED_FACTIONS,
} from '../../server/public/js/lib/gameformat.mjs';

const here = dirname(fileURLToPath(import.meta.url));
// Stamped into every regenerated file's faction block.
const DATA_SOURCE = '40kdc-data 1.4.5 (11th edition) + Wahapedia 11e codex import 2026-10-16 (Codex: Orks, Codex: Adeptus Custodes)';
const ARMIES_DIR = join(here, '..', '..', '40k', 'armies');

// ---------------------------------------------------------------------------
// Dataset
const rawData = {
  units: loadCollection('units'),
  weapons: loadCollection('weapons'),
  abilities: loadCollection('abilities'),
  unitCompositions: loadCollection('unitCompositions'),
  leaderAttachments: loadCollection('leaderAttachments'),
  enhancements: loadCollection('enhancements'),
  detachments: loadCollection('detachments'),
  factions: loadCollection('factions'),
};

// Datasheets whose kit a codex rewrote (frozen by legacy-kits.mjs): a roster
// built on the old kit has wargear lines that contradict the codex kit.
const LEGACY_KIT_UNITS = new Set(
  loadCollection('unitCompositions_1.0.19', join(DATA_DIR_FOR_LEGACY, 'legacy'))
    .map(c => `${c.faction_id}::${c.unit_id}`));
const wargearOptionsAll = loadCollection('wargearOptions');

const conv = createConverter({
  rawData,
  describeAbility,
  canonEntries: buildCanonEntries(),
});

const units = rawData.units;
const detachmentsAll = rawData.detachments;
const enhancementsAll = rawData.enhancements;
const { unitsByFaction, compByUnit } = conv;

// ---------------------------------------------------------------------------
// Unit conversion
function convertUnit(existing, dcUnit, factionId, factionName, warnings, detachmentEnh = new Map(), ordinal = 1) {
  const comp = compByUnit.get(`${factionId}::${dcUnit.id}`);
  const oldMeta = existing.meta ?? {};
  let modelCount = (existing.models ?? []).length ||
    dcUnit.model_count?.min || 1;
  // A codex can change unit sizes (Custodian Wardens 4-5 -> 2-3): clamp the
  // roster's model count into the datasheet's range.
  const mc = dcUnit.model_count;
  if (mc && (modelCount < mc.min || modelCount > mc.max)) {
    const clamped = Math.max(mc.min, Math.min(mc.max, modelCount));
    warnings.push(`${existing.id}: ${modelCount} models outside the datasheet's ${mc.min}-${mc.max} — now ${clamped}`);
    modelCount = clamped;
  }
  // ...and onto a size the datasheet is sold at (11e prices per unit size:
  // Gretchin come as 10 or 20, so a pre-codex 11-model mob becomes 10).
  const sizes = [];
  for (const t of dcUnit.points ?? []) {
    for (let n = t.models; n <= (t.models_max ?? t.models); n++) if (!sizes.includes(n)) sizes.push(n);
  }
  if (sizes.length && !sizes.includes(modelCount)) {
    sizes.sort((a, b) => a - b);
    const snapped = [...sizes].reverse().find(n => n <= modelCount) ?? sizes[0];
    warnings.push(`${existing.id}: ${modelCount} models is not a codex unit size (${sizes.join('/')}) — now ${snapped}`);
    modelCount = snapped;
  }

  // --- weapons: preserve the roster's loadout where names still exist,
  // otherwise the unit's full 11e weapon list.
  const dcWeaponNames = new Map();
  for (const wid of dcUnit.weapon_ids ?? []) {
    const w = conv.wres.resolve(factionId, wid);
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
      if (dcWeaponNames.has(looseName(conv.wres.resolve(factionId, wid)?.name ?? ''))) chosenIds.add(wid);
    }
  }
  // A roster built on a pre-codex kit: the datasheet was re-kitted by a codex
  // (legacy kit frozen) and the roster's weapon list names a weapon the codex
  // datasheet no longer has. Its wargear lines are rebuilt below.
  const preCodexRoster = !!dcUnit.source && LEGACY_KIT_UNITS.has(`${factionId}::${dcUnit.id}`) &&
    oldWeaponNames.some(n => !dcWeaponNames.has(looseName(n)) && !weaponAliases[looseName(n)]);
  const weaponsOut = [];
  for (const wid of chosenIds) weaponsOut.push(...conv.convertWeapon(factionId, wid, warnings));
  weaponsOut.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'Ranged' ? -1 : 1));

  // --- abilities (faction army rule first, mirroring the existing files)
  // wargear abilities only when the roster lists the wargear or the
  // datasheet's default loadout includes it
  const defaultWargear = (comp?.models ?? []).flatMap(m => m.default_wargear ?? []).map(normName);
  const rosterWargear = (oldMeta.wargear ?? []).map(normName);
  const hasWargear = n => defaultWargear.some(w => w.includes(normName(n))) ||
    rosterWargear.some(w => w.includes(normName(n)));
  const abilitiesOut = conv.unitAbilities(dcUnit, factionId, factionName, warnings, hasWargear);

  // --- composition + models
  const modelsOut = conv.buildModelsArray(dcUnit, comp, modelCount);

  // --- enhancements: keep only ones that exist in the 11e detachment
  const enhancementsOut = [];
  let enhancementPoints = 0;
  for (const e of oldMeta.enhancements ?? []) {
    let name = typeof e === 'string' ? e : (e?.name ?? '');
    name = name.replace(/\s*\(\+?\d+\s*pts?\)\s*$/i, ''); // "X (+25 pts)" -> "X"
    const match = detachmentEnh.get(enhKey(name));
    if (match) {
      // the game keys enhancements on the bare name ("Smoky Gubbinz", not the
      // dataset's "Smoky Gubbinz (Upgrade)")
      enhancementsOut.push(conv.canonicalName(bareEnhName(match.name)));
      enhancementPoints += match.cost ?? 0;
    } else if (name) {
      warnings.push(`${existing.id}: enhancement "${name}" not in 11e detachment — dropped`);
    }
  }

  // --- points for this model count; `ordinal` = which copy of the datasheet
  // this is in the file (11e prices later copies higher), plus priced wargear
  // (wargear_points, e.g. "per Praesidium Shield 25") the roster lists.
  let wargearPoints = 0;
  for (const wp of dcUnit.wargear_points ?? []) {
    for (const entry of oldMeta.wargear ?? []) {
      if (!normName(entry).includes(normName(wp.name))) continue;
      const n = String(entry).match(/^(\d+)\s*x/i);
      wargearPoints += wp.cost * (n ? parseInt(n[1], 10) : 1);
    }
  }
  const points = pointsFor(dcUnit, modelsOut.length, ordinal) + enhancementPoints + wargearPoints;

  // --- leader data
  const meta = {
    name: dcUnit.name,
    keywords: conv.unitKeywords(dcUnit),
    stats: conv.unitStats(dcUnit),
    points,
    is_warlord: oldMeta.is_warlord ?? false,
    enhancements: enhancementsOut,
    wargear: preCodexRoster
      ? rebuildCodexWargear(existing.id, oldMeta.wargear ?? [], dcUnit, factionId, comp, modelsOut.length, warnings)
      : syncWargearCounts(oldMeta.wargear ?? [], comp, modelsOut.length),
    weapons: weaponsOut,
    abilities: abilitiesOut,
    unit_composition: conv.compositionLines(comp),
  };
  const ld = conv.leaderData(dcUnit, factionId);
  if (ld) meta.leader_data = ld;

  return {
    id: existing.id,
    squad_id: existing.squad_id ?? existing.id,
    owner: existing.owner ?? 1,
    status: existing.status ?? 'UNDEPLOYED',
    meta,
    models: modelsOut,
  };
}

// A pre-codex roster of a datasheet the codex re-kitted (Boyz: the Nob lost
// his slugga; Battlewagon: Tracks and wheels -> Crushin' Bulk): its wargear
// lines name the OLD kit, which UnitLoadoutResolver / RulesEngine cannot map
// onto the codex roles (every model ended up carrying the whole melee menu).
// Rebuild the lines as a codex-built roster records them: each composition
// role's default weapons with that role's model count, plus the roster's
// picks that are pure codex ADD-ON options (no "replaces": Battlewagon big
// shootas / Grabbin' Klaw / Wreckin' Ball). Swaps made against the old kit and
// stale weapons are dropped, with a warning.
function rebuildCodexWargear(unitKey, wargear, dcUnit, factionId, comp, modelCount, warnings) {
  const nameOf = id => conv.wres.resolve(factionId, id)?.name ?? null;
  const out = [];
  const rows = comp?.models ?? [];
  let remaining = modelCount;
  const defaults = new Set();
  rows.forEach((m, k) => {
    const n = k === rows.length - 1 ? remaining : Math.min(m.min, remaining);
    remaining -= n;
    if (n <= 0) return;
    for (const id of m.default_weapon_ids ?? []) {
      const nm = nameOf(id);
      if (!nm) continue;
      defaults.add(looseName(nm));
      out.push(`${n}x ${nm}`);
    }
  });
  const addOns = new Set();
  for (const o of wargearOptionsAll) {
    if (o.faction_id !== factionId || o.unit_id !== dcUnit.id || (o.replaces ?? []).length) continue;
    for (const id of [...(o.replacement ?? []), ...(o.replacement_choice ?? []).flat()]) {
      const nm = nameOf(id);
      if (nm) addOns.add(looseName(nm));
    }
  }
  const dropped = [];
  for (const entry of wargear) {
    const m = String(entry).match(/^(\d+)x\s+(.+)$/);
    if (!m) { out.push(entry); continue; }   // descriptive lines ("Shield-Captain (Shield), ...")
    const key = looseName(m[2]);
    if (addOns.has(key) && !defaults.has(key)) {
      const nm = [...(dcUnit.weapon_ids ?? [])].map(nameOf).find(x => x && looseName(x) === key) ?? m[2];
      out.push(`${m[1]}x ${nm}`);
    } else if (!defaults.has(key)) {
      dropped.push(entry);
    }
  }
  if (dropped.length) warnings.push(`${unitKey}: codex re-kitted this datasheet — loadout reset to the codex default kit; dropped ${JSON.stringify(dropped)}`);
  return out;
}

// Enhancement names may carry a trailing qualifier in the dataset
// ("Smoky Gubbinz (Upgrade)", "Fear Made Manifest (Aura)"); rosters and the
// game's enhancement tables use the bare name.
function bareEnhName(n) { return String(n).replace(/\s*\([^)]*\)\s*$/, ''); }
function enhKey(n) { return normName(bareEnhName(n)); }

// "Nx <model>" wargear lines are model counts: ArmyListManager re-derives a
// unit's size from them (_get_expected_model_count) and re-adds models. When a
// codex resizes a unit (Gretchin 11 -> 10), rewrite those lines to the
// composition's per-row counts and cap any other "Nx" line at the unit size.
// Rows are counted the way gameformat.buildModelsArray fills them (each row
// its minimum, the last row the remainder).
function syncWargearCounts(wargear, comp, modelCount) {
  const rows = comp?.models ?? [];
  const counts = new Map();
  let remaining = modelCount;
  rows.forEach((m, k) => {
    const take = k === rows.length - 1 ? remaining : Math.min(m.min, remaining);
    counts.set(roleKey(m.name), Math.max(0, take));
    remaining -= take;
  });
  return wargear.map(entry => {
    const m = String(entry).match(/^(\d+)x\s+(.+)$/);
    if (!m) return entry;
    const n = parseInt(m[1], 10);
    const want = counts.get(roleKey(m[2]));
    if (want != null && want !== n) return `${want}x ${m[2]}`;
    if (want == null && n > modelCount) return `${modelCount}x ${m[2]}`;
    return entry;
  });
}
// ArmyListManager._normalize_model_name: lowercase, drop one trailing z/s.
function roleKey(name) {
  let s = String(name).toLowerCase().trim();
  if (s.length > 2 && (s.endsWith('z') || s.endsWith('s'))) s = s.slice(0, -1);
  return s;
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
      if (e) detachmentEnh.set(enhKey(e.name), e);
    }
  } else if (detName) {
    warnings.push(`detachment "${army.faction.detachment}" not found in 11e ${factionId} detachments`);
  }
  const outUnits = {};
  const copies = new Map(); // datasheet -> copies seen so far (repeat pricing)
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
      // No codex datasheet (Legends / discontinued — e.g. Lootas, Burna Boyz):
      // keep the roster entry exactly as it is (owner decision D2, PLAN
      // .llm/codex_11e_wahapedia/PLAN.md) rather than silently deleting a
      // player's unit.
      warnings.push(`${key}: unit "${name}" has NO 11e codex datasheet (Legends?) — kept unchanged`);
      totalPoints += u.meta?.points ?? 0;
      outUnits[key] = u;
      continue;
    }
    const copyKey = `${unitFactionId}::${dcUnit.id}`;
    copies.set(copyKey, (copies.get(copyKey) ?? 0) + 1);
    const conv2 = convertUnit(u, dcUnit, unitFactionId, factionName, warnings, detachmentEnh, copies.get(copyKey));
    totalPoints += conv2.meta.points;
    outUnits[key] = conv2;
  }
  const out = {
    faction: {
      ...army.faction,
      created_date: army.faction?.created_date ?? '',
      schema: 2,
      edition: 11,
      data_source: DATA_SOURCE,
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
  const fixed = normalizeQuotes(res.out);
  writeFileSync(f, JSON.stringify(fixed, null, 1) + '\n');
  console.log(`WROTE ${basename(f)} — ${Object.keys(res.out.units).length} units, ${res.totalPoints} pts`);
  for (const w of res.warnings) console.log(`   ! ${w}`);
}
