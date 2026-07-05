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
import { loadCollection, normName, looseName, pointsFor, buildCanonEntries } from './lib.mjs';
import { describeAbility } from '@alpaca-software/40kdc-data';
import {
  createConverter, normalizeQuotes, weaponBaseName,
  FACTION_IDS, UNIT_ALIASES, WEAPON_ALIASES_SRC, ALLIED_FACTIONS,
} from '../../server/public/js/lib/gameformat.mjs';

const here = dirname(fileURLToPath(import.meta.url));
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
function convertUnit(existing, dcUnit, factionId, factionName, warnings, detachmentEnh = new Map()) {
  const comp = compByUnit.get(`${factionId}::${dcUnit.id}`);
  const oldMeta = existing.meta ?? {};
  const modelCount = (existing.models ?? []).length ||
    dcUnit.model_count?.min || 1;

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
  const weaponsOut = [];
  for (const wid of chosenIds) weaponsOut.push(...conv.convertWeapon(factionId, wid, warnings));
  weaponsOut.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === 'Ranged' ? -1 : 1));

  // --- abilities (faction army rule first, mirroring the existing files)
  const abilitiesOut = conv.unitAbilities(dcUnit, factionId, factionName, warnings);

  // --- composition + models
  const modelsOut = conv.buildModelsArray(dcUnit, comp, modelCount);

  // --- enhancements: keep only ones that exist in the 11e detachment
  const enhancementsOut = [];
  let enhancementPoints = 0;
  for (const e of oldMeta.enhancements ?? []) {
    let name = typeof e === 'string' ? e : (e?.name ?? '');
    name = name.replace(/\s*\(\+?\d+\s*pts?\)\s*$/i, ''); // "X (+25 pts)" -> "X"
    const match = detachmentEnh.get(normName(name));
    if (match) {
      enhancementsOut.push(conv.canonicalName(match.name));
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
    keywords: conv.unitKeywords(dcUnit),
    stats: conv.unitStats(dcUnit),
    points,
    is_warlord: oldMeta.is_warlord ?? false,
    enhancements: enhancementsOut,
    wargear: oldMeta.wargear ?? [],
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
    const conv2 = convertUnit(u, dcUnit, unitFactionId, factionName, warnings, detachmentEnh);
    totalPoints += conv2.meta.points;
    outUnits[key] = conv2;
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
  const fixed = normalizeQuotes(res.out);
  writeFileSync(f, JSON.stringify(fixed, null, 1) + '\n');
  console.log(`WROTE ${basename(f)} — ${Object.keys(res.out.units).length} units, ${res.totalPoints} pts`);
  for (const w of res.warnings) console.log(`   ! ${w}`);
}
