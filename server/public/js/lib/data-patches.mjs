// Local corrections applied on top of the vendored @alpaca-software/40kdc-data
// dataset (server/public/js/vendor/40kdc-data.mjs).
//
// Why this exists: upstream ships the Orks "Speedwaaagh!" detachment flagged
// `dataslate: "pre-launch-provisional"` with an EMPTY enhancement_ids list and
// no enhancement records at all. As a result the army builder showed no
// "Enhancement" dropdown for a Speedwaaagh! roster (enhancementChoices() → [])
// and silently dropped any imported enhancement (e.g. "Kustom Shokk Box") as
// unresolved on export. See the four official Speedwaaagh! enhancements below
// (Orks codex / Wahapedia).
//
// We inject the data at load time rather than editing the minified vendor
// bundle so the fix survives a re-bundle (scripts/40kdc/bundle-browser.mjs
// re-pulls the still-incomplete upstream package).
//
// Codex: Adeptus Custodes (11e) — WP-C46: the bundle predates the codex. It
// lists the pre-codex Custodes detachments (Shield Host, Talons of the
// Emperor, ...) and none of the 13 codex detachments / 29 enhancements, so
// the builder offered stale enhancements. The codex records (generated from
// the game's own 40k/data/40kdc dataset into custodes-codex-11e-data.mjs) are
// upserted by id, and the superseded detachments are flagged
// superseded_by_codex (kept for importing old lists, hidden from the picker).
//
// Environment-free (no fs / DOM). applyDataPatches() mutates the RAW_DATA
// arrays in place and is idempotent — the converter (createConverter) and the
// package importer (tryImportRoster) both read these arrays/objects by
// reference, so an in-place patch reaches every consumer.

// Codex: Orks (11e) — WP-O5: the bundle's Ork detachments are the pre-codex
// provisional ones (Kult of Speed with Wazblasta, Taktikal Brigade with Skwad
// Leader / Mek Kaptin / Mork's Kunnin', ...) and 7 of the 15 codex detachments
// are missing (Brute Bosses, Flyboyz, Madcap Meks, Runt Swarm, Shoota Boyz,
// Wreckas, Wurrband). The 15 codex detachments and their 38 enhancements
// (generated from the game's own 40k/data/40kdc dataset into
// orks-codex-11e-data.mjs) are upserted by id, so each detachment's
// enhancement_ids lists exactly its codex enhancements.
import { ORKS_CODEX_DETACHMENTS, ORKS_CODEX_ENHANCEMENTS } from './orks-codex-11e-data.mjs';

export { ORKS_CODEX_DETACHMENTS, ORKS_CODEX_ENHANCEMENTS };

/**
 * Codex: Orks (11e): upsert the 15 codex detachments and their 38
 * enhancements by id (in place: consumers hold the arrays). Idempotent.
 */
export function applyOrksCodex(rawData) {
  if (!rawData) return rawData;
  const upsert = (arr, rec) => {
    const i = arr.findIndex(x => x.id === rec.id);
    const copy = JSON.parse(JSON.stringify(rec));
    if (i >= 0) arr[i] = copy;
    else arr.push(copy);
  };
  const enhancements = rawData.enhancements ?? (rawData.enhancements = []);
  const detachments = rawData.detachments ?? (rawData.detachments = []);
  for (const e of ORKS_CODEX_ENHANCEMENTS) upsert(enhancements, e);
  for (const d of ORKS_CODEX_DETACHMENTS) upsert(detachments, d);
  return rawData;
}

// Enhancement records use the same shape the dataset emits (see any
// *-war-horde entry in the bundle): id, name, detachment_id, cost,
// keyword_restrictions, ability_id, is_unique, game_version, points_provisional,
// upgrade_tag, max_targets.
function orkEnhancement(id, name, cost) {
  return {
    id,
    name,
    detachment_id: 'speedwaaagh',
    cost,
    keyword_restrictions: ['Orks'],
    ability_id: null,
    is_unique: true,
    game_version: { edition: '11th', dataslate: 'launch' },
    points_provisional: false,
    upgrade_tag: false,
    max_targets: 1,
  };
}

// The official Orks "Speedwaaagh!" detachment enhancements.
export const SPEEDWAAAGH_ENHANCEMENTS = [
  orkEnhancement('kustom-shokk-box-speedwaaagh', 'Kustom Shokk Box', 10),
  orkEnhancement('dakkamek-speedwaaagh', 'Dakkamek', 25),
  orkEnhancement('supa-burny-fuel-speedwaaagh', 'Supa-burny Fuel', 15),
  orkEnhancement('master-meknologist-speedwaaagh', 'Master Meknologist', 20),
];

// detachment id -> enhancement records that upstream is missing.
import {
  CUSTODES_CODEX_DETACHMENTS,
  CUSTODES_CODEX_ENHANCEMENTS,
  CUSTODES_SUPERSEDED_DETACHMENT_IDS,
  CUSTODES_CODEX_UNIT_KEYWORDS,
} from './custodes-codex-11e-data.mjs';

export {
  CUSTODES_CODEX_DETACHMENTS,
  CUSTODES_CODEX_ENHANCEMENTS,
  CUSTODES_SUPERSEDED_DETACHMENT_IDS,
  CUSTODES_CODEX_UNIT_KEYWORDS,
};

const ENHANCEMENT_PATCHES = [
  { detachmentId: 'speedwaaagh', enhancements: SPEEDWAAAGH_ENHANCEMENTS },
];

/**
 * Idempotently add the missing enhancement records to rawData.enhancements and
 * wire their ids into the owning detachment's enhancement_ids. Returns rawData.
 */
export function applyDataPatches(rawData) {
  if (!rawData) return rawData;
  applyCodexDatasheets(rawData); // WP-W3: codex datasheets as the game has them (see below)
  applyLegendsDatasheets(rawData); // Warhammer Legends datasheets the game data does not carry (see below)
  applyOrksCodex(rawData);
  const enhancements = rawData.enhancements ?? (rawData.enhancements = []);
  const detachments = rawData.detachments ?? [];

  for (const { detachmentId, enhancements: adds } of ENHANCEMENT_PATCHES) {
    const det = detachments.find(d => d.id === detachmentId);
    if (!det) continue; // detachment no longer in the dataset — nothing to attach to
    if (!Array.isArray(det.enhancement_ids)) det.enhancement_ids = [];
    for (const e of adds) {
      if (!enhancements.some(x => x.id === e.id)) enhancements.push({ ...e });
      if (!det.enhancement_ids.includes(e.id)) det.enhancement_ids.push(e.id);
    }
  }
  applyCustodesCodex(rawData);
  applySmCodex(rawData);
  return rawData;
}

/** Replace-or-append `rec` in `arr` by id (in place: consumers hold `arr`). */
function upsertById(arr, rec) {
  const i = arr.findIndex(x => x.id === rec.id);
  const copy = JSON.parse(JSON.stringify(rec));
  if (i >= 0) arr[i] = copy;
  else arr.push(copy);
}

/**
 * Codex: Adeptus Custodes (11e): upsert the 13 codex detachments and their 29
 * enhancements; flag the superseded pre-codex detachments. Idempotent.
 */
export function applyCustodesCodex(rawData) {
  if (!rawData) return rawData;
  const enhancements = rawData.enhancements ?? (rawData.enhancements = []);
  const detachments = rawData.detachments ?? (rawData.detachments = []);
  for (const e of CUSTODES_CODEX_ENHANCEMENTS) upsertById(enhancements, e);
  for (const d of CUSTODES_CODEX_DETACHMENTS) upsertById(detachments, d);
  for (const d of detachments) {
    if (d.faction_id === 'adeptus-custodes' && CUSTODES_SUPERSEDED_DETACHMENT_IDS.includes(d.id)) {
      d.superseded_by_codex = 'Codex: Adeptus Custodes (11th edition)';
    }
  }
  return rawData;
}

/** Keywords for the enhancement bearer filter: the bundle's datasheet
 * keywords + faction keywords, plus the codex keywords the bundle predates. */
export function bearerKeywords(rawUnit) {
  const out = [...(rawUnit?.keywords ?? []), ...(rawUnit?.faction_keywords ?? [])];
  for (const k of CUSTODES_CODEX_UNIT_KEYWORDS[rawUnit?.id] ?? []) {
    if (!out.some(x => String(x).toLowerCase() === String(k).toLowerCase())) out.push(k);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Codex datasheets (WP-W3). The game's 40k/data/40kdc dataset is the 40kdc
// extract + local-patches.mjs + the Wahapedia 11e codex import (Codex:
// Adeptus Custodes, Codex: Orks); the vendored bundle is the bare 40kdc
// release. codex-11e-datasheets.mjs (generated by
// scripts/40kdc/gen_codex_builder_patch.mjs) holds every record the game has
// differently — datasheets (profiles, points tiers, wargear points, model
// counts, keywords), weapons, abilities, compositions, wargear options, leader
// pairings, faction records. They are upserted here by key, so the builder
// converts a list exactly as generate-armies.mjs does. Nothing is deleted
// (decision D1): pre-codex Custodes datasheets stay resolvable for old lists
// and are flagged superseded_by_codex (+ superseded_by, the codex datasheet
// a pre-codex roster moves to), which the unit picker hides.
import {
  CODEX_DATASHEET_RECORDS,
  CODEX_WARGEAR_OPTION_BLOCKS,
  CODEX_SUPERSEDED_UNITS,
  CODEX_OVERLAY_BASE_VERSION,
  CODEX_OVERLAY_SOURCES,
  CODEX_OVERLAY_FACTIONS,
} from './codex-11e-datasheets.mjs';

export {
  CODEX_DATASHEET_RECORDS,
  CODEX_WARGEAR_OPTION_BLOCKS,
  CODEX_SUPERSEDED_UNITS,
  CODEX_OVERLAY_BASE_VERSION,
  CODEX_OVERLAY_SOURCES,
  CODEX_OVERLAY_FACTIONS,
};

// Same keys as the generator: shared ids are per-faction copies in 40kdc.
const CODEX_RECORD_KEYS = {
  units: r => `${r.faction_id}::${r.id}`,
  weapons: r => `${r.faction_id ?? ''}::${r.id}`,
  abilities: r => `${r.faction_id ?? ''}::${r.ability_id}`,
  unitCompositions: r => `${r.faction_id}::${r.unit_id}`,
  leaderAttachments: r => r.leader_id,
  factions: r => r.id,
};

const cloneRecord = r => JSON.parse(JSON.stringify(r));

/** Index right after the last record of `factionId` (the faction's block),
 * where wahapedia-import.mjs puts new records; the end when there is none. */
function afterFactionBlock(arr, factionId) {
  if (factionId) {
    for (let j = arr.length - 1; j >= 0; j--) if (arr[j]?.faction_id === factionId) return j + 1;
  }
  return arr.length;
}

/**
 * Upsert the codex datasheet overlay into rawData (in place: the converter
 * and the package importer hold these arrays). Idempotent.
 */
export function applyCodexDatasheets(rawData) {
  if (!rawData) return rawData;
  upsertDatasheetRecords(rawData, CODEX_DATASHEET_RECORDS, CODEX_WARGEAR_OPTION_BLOCKS);

  const units = rawData.units ?? [];
  const unitAt = new Map(units.map((u, i) => [`${u.faction_id}::${u.id}`, i]));
  for (const s of CODEX_SUPERSEDED_UNITS) {
    const u = units[unitAt.get(`${s.faction_id}::${s.id}`)];
    if (!u) continue;
    u.superseded_by_codex = s.codex;
    if (s.superseded_by) u.superseded_by = s.superseded_by;
  }
  return rawData;
}

/** Upsert datasheet records by key and replace whole wargear option blocks
 * (in place; shared by the codex overlay and the Legends datasheets). */
function upsertDatasheetRecords(rawData, records, optionBlocks) {
  for (const [coll, recs] of Object.entries(records)) {
    const keyOf = CODEX_RECORD_KEYS[coll];
    if (!keyOf || !recs.length) continue;
    const arr = rawData[coll] ?? (rawData[coll] = []);
    const at = new Map();
    arr.forEach((r, i) => { const k = keyOf(r); if (!at.has(k)) at.set(k, i); });
    const fresh = [];
    for (const rec of recs) {
      const i = at.get(keyOf(rec));
      if (i !== undefined) arr[i] = cloneRecord(rec);
      else fresh.push(cloneRecord(rec));
    }
    const owned = coll !== 'factions' && coll !== 'leaderAttachments';
    for (const rec of fresh) arr.splice(afterFactionBlock(arr, owned ? rec.faction_id : null), 0, rec);
  }

  // A codex datasheet's wargear option block replaces the bundle's block whole.
  const opts = rawData.wargearOptions ?? (rawData.wargearOptions = []);
  for (const b of optionBlocks) {
    const mine = o => o.faction_id === b.faction_id && o.unit_id === b.unit_id;
    let pos = opts.findIndex(mine);
    if (pos < 0) pos = afterFactionBlock(opts, b.faction_id);
    for (let j = opts.length - 1; j >= pos; j--) if (mine(opts[j])) opts.splice(j, 1);
    opts.splice(pos, 0, ...b.options.map(cloneRecord));
  }
}

// ---------------------------------------------------------------------------
// Warhammer Legends datasheets. The 11th edition Codex: Orks moved Lootas and
// Burna Boyz to Warhammer Legends. The 40kdc bundle has no datasheet for them
// (only two orphaned ability records), and the game's Wahapedia codex import
// skips Legends (owner decision D2), so 40k/data/40kdc has none either: the
// game only knows them from army files and saves written before the codex,
// which carry their own stats. A pasted or game list with either unit came in
// with "unit not recognised" and the unit was left out of the calculator.
//
// These records are what scripts/40kdc/wahapedia-import.mjs writes for the two
// datasheets when its Legends filter lets them through (run on a scratch copy
// of the data, --faction orks, overlay mode), from the repository's Wahapedia
// 11e snapshot .llm/codex_11e_wahapedia/orks/wahapedia/*.csv (export
// 2026-10-16, source "Orks (Warhammer Legends)"): profiles, points, model
// counts, base sizes, weapons, kits, wargear options and ability text. Only
// is_legend is set by hand (the importer writes false). Shared weapons whose
// printed numbers equal the codex record keep its id (big-shoota,
// rokkit-launcha, burna); the Legends Kustom Mega-blasta is BS 5+ where the
// codex one is 4+, so each datasheet has its own copy, as the importer does.
// The two ability records replace the bundle's orphans (same ids; the
// Wahapedia rules text is added, which the calculator reads).
//
// They live in this file, not in codex-11e-datasheets.mjs: that module is
// generated from 40k/data/40kdc (codex-builder-parity.test.mjs checks it is up
// to date), and the game data does not have these datasheets.
export const LEGENDS_DATASHEET_RECORDS = {
  units: [
    {"id":"lootas","name":"Lootas","faction_id":"orks","profiles":[{"name":"Spanner","M":6,"T":5,"W":1,"Sv":5,"Ld":7,"OC":1},{"name":"Loota","M":6,"T":5,"W":1,"Sv":5,"Ld":7,"OC":1}],"points":[{"models":5,"cost":50,"unit_count_min":1,"unit_count_max":2},{"models":10,"cost":100,"unit_count_min":1,"unit_count_max":2},{"models":5,"cost":60,"unit_count_min":3,"unit_count_max":null},{"models":10,"cost":110,"unit_count_min":3,"unit_count_max":null}],"keywords":["Infantry","Lootas"],"faction_keywords":["Orks"],"base_size_mm":{"shape":"round","diameter":32},"model_count":{"min":5,"max":10},"weapon_ids":["big-shoota","deffgun","kustom-mega-blasta-lootas","rokkit-launcha","gun-stock-and-fists"],"ability_ids":["dat-s-our-loot"],"is_legend":true,"points_provisional":false,"game_version":{"edition":"11th","dataslate":"codex"},"source":"wahapedia-11e@2026-10-16"},
    {"id":"burna-boyz","name":"Burna Boyz","faction_id":"orks","profiles":[{"name":"Burna Boy","M":6,"T":5,"W":1,"Sv":5,"Ld":7,"OC":1},{"name":"Spanner","M":6,"T":5,"W":1,"Sv":5,"Ld":7,"OC":1}],"points":[{"models":5,"cost":60},{"models":10,"cost":120}],"keywords":["Infantry","Burna Boyz"],"faction_keywords":["Orks"],"base_size_mm":{"shape":"round","diameter":32},"model_count":{"min":5,"max":10},"weapon_ids":["big-shoota","burna","kustom-mega-blasta-burna-boyz","rokkit-launcha","gun-stock-and-fists","cuttin-flames"],"ability_ids":["pyromaniaks"],"is_legend":true,"points_provisional":false,"game_version":{"edition":"11th","dataslate":"codex"},"source":"wahapedia-11e@2026-10-16"},
  ],
  weapons: [
    {"id":"cuttin-flames","name":"Cuttin' Flames","type":"melee","profiles":[{"name":"Cuttin' Flames","range":"Melee","stats":{"A":2,"S":4,"AP":-2,"D":1,"WS":4},"keywords":[]}],"game_version":{"edition":"11th","dataslate":"codex"},"faction_id":"orks","source":"wahapedia-11e@2026-10-16"},
    {"id":"deffgun","name":"Deffgun","type":"ranged","profiles":[{"name":"Deffgun","range":48,"stats":{"A":2,"S":8,"AP":-1,"D":2,"BS":6},"keywords":[{"keyword_id":"heavy"},{"keyword_id":"rapid-fire","parameters":{"value":1}}]}],"game_version":{"edition":"11th","dataslate":"codex"},"faction_id":"orks","source":"wahapedia-11e@2026-10-16"},
    {"id":"gun-stock-and-fists","name":"Gun Stock and Fists","type":"melee","profiles":[{"name":"Gun Stock and Fists","range":"Melee","stats":{"A":2,"S":5,"AP":0,"D":1,"WS":3},"keywords":[]}],"game_version":{"edition":"11th","dataslate":"codex"},"faction_id":"orks","source":"wahapedia-11e@2026-10-16"},
    {"id":"kustom-mega-blasta-burna-boyz","name":"Kustom Mega-blasta","type":"ranged","profiles":[{"name":"Kustom Mega-blasta","range":24,"stats":{"A":3,"S":9,"AP":-2,"D":3,"BS":5},"keywords":[{"keyword_id":"hazardous"}]}],"game_version":{"edition":"11th","dataslate":"codex"},"faction_id":"orks","source":"wahapedia-11e@2026-10-16"},
    {"id":"kustom-mega-blasta-lootas","name":"Kustom Mega-blasta","type":"ranged","profiles":[{"name":"Kustom Mega-blasta","range":24,"stats":{"A":3,"S":9,"AP":-2,"D":3,"BS":5},"keywords":[{"keyword_id":"hazardous"}]}],"game_version":{"edition":"11th","dataslate":"codex"},"faction_id":"orks","source":"wahapedia-11e@2026-10-16"},
  ],
  abilities: [
    {"ability_id":"dat-s-our-loot","name":"Dat's Our Loot","authored_by":"40kdc-community","game_version":{"edition":"11th","dataslate":"pre-launch-provisional"},"source_digest":"403d3dd9f94a3346d9c1b8e29185eeabbcb800a47ec1fdba9e1f8eb224155fbc","version":"2025-q3","effect":{"type":"conditional","condition":{"operator":"and","operands":[{"type":"phase-is","parameters":{"phase":"shooting"}},{"type":"target-has-keyword","parameters":{"keyword":"A"}}]},"effect":{"type":"re-roll","target":"unit","modifier":{"roll":"hit","subset":"ones"}}},"scope":{"range":"unit","duration":"permanent"},"unit_ids":["lootas"],"ability_type":"unit","behavior":"passive","disputed":true,"dispute_notes":"Dangling reference: condition gates on keyword \"A\", which no unit in the dataset has, so the gate never fires and the effect is dead; the intended keyword is unrecoverable from the encoding.","faction_id":"orks","rules_text":"• This unit’s ranged attacks can re-roll hit rolls of 1.\n• This unit’s ranged attacks that target a unit within range of an objective can re-roll hit rolls.","source":"wahapedia-11e@2026-10-16"},
    {"ability_id":"pyromaniaks","name":"Pyromaniaks","authored_by":"40kdc-community","game_version":{"edition":"11th","dataslate":"pre-launch-provisional"},"source_digest":"df40c1edbd49ac78bb493c5b3c9615750f6eff2d08c65b02772ac978640702d8","version":"2025-q3","effect":{"type":"conditional","condition":{"type":"phase-is","parameters":{"phase":"shooting"}},"effect":{"type":"re-roll","target":"unit","modifier":{"roll":"wound","subset":"ones"}}},"scope":{"range":"aura-6","duration":"permanent"},"unit_ids":["burna-boyz","skorchas"],"ability_type":"unit","behavior":"passive","faction_id":"orks","rules_text":"This unit’s attacks that target a unit within 6\" of this unit can re-roll wound rolls of 1.","source":"wahapedia-11e@2026-10-16"},
  ],
  unitCompositions: [
    {"unit_id":"lootas","faction_id":"orks","models":[{"name":"Spanner","min":1,"max":2,"is_leader_model":false,"base_size_mm":{"shape":"round","diameter":32},"default_weapon_ids":["big-shoota","gun-stock-and-fists"],"default_wargear":[]},{"name":"Loota","min":4,"max":8,"is_leader_model":false,"base_size_mm":{"shape":"round","diameter":32},"default_weapon_ids":["deffgun","gun-stock-and-fists"],"default_wargear":[]}],"game_version":{"edition":"11th","dataslate":"codex"},"source":"wahapedia-11e@2026-10-16"},
    {"unit_id":"burna-boyz","faction_id":"orks","models":[{"name":"Spanner","min":1,"max":2,"is_leader_model":false,"base_size_mm":{"shape":"round","diameter":32},"default_weapon_ids":["big-shoota","gun-stock-and-fists"],"default_wargear":[]},{"name":"Burna Boy","min":4,"max":8,"is_leader_model":false,"base_size_mm":{"shape":"round","diameter":32},"default_weapon_ids":["burna","cuttin-flames"],"default_wargear":[]}],"game_version":{"edition":"11th","dataslate":"codex"},"source":"wahapedia-11e@2026-10-16"},
  ],
};

export const LEGENDS_WARGEAR_OPTION_BLOCKS = [
  {"faction_id":"orks","unit_id":"lootas","options":[{"id":"lootas-wgo-wh-1","unit_id":"lootas","faction_id":"orks","game_version":{"edition":"11th","dataslate":"codex"},"is_free":true,"rules_text":"Any number of Spanner models can each have their Big Shoota replaced with one of the following: 1 Kustom Mega-blasta, 1 Rokkit Launcha","source":"wahapedia-11e@2026-10-16","model_constraint":{"any_number":true,"model_name":"Spanner"},"replaces":["big-shoota"],"replacement_choice":[["kustom-mega-blasta-lootas"],["rokkit-launcha"]]}]},
  {"faction_id":"orks","unit_id":"burna-boyz","options":[{"id":"burna-boyz-wgo-wh-1","unit_id":"burna-boyz","faction_id":"orks","game_version":{"edition":"11th","dataslate":"codex"},"is_free":true,"rules_text":"Any number of Spanner models can each have their Big Shoota replaced with one of the following: 1 Kustom Mega-blasta, 1 Rokkit Launcha.","source":"wahapedia-11e@2026-10-16","model_constraint":{"any_number":true,"model_name":"Spanner"},"replaces":["big-shoota"],"replacement_choice":[["kustom-mega-blasta-burna-boyz"],["rokkit-launcha"]]}]},
];

// Keys of the Legends records, by collection: the builder dataset differs
// from the game data in exactly these (codex-builder-parity.test.mjs).
export const LEGENDS_RECORD_KEYS = {
  units: LEGENDS_DATASHEET_RECORDS.units.map(r => `${r.faction_id}::${r.id}`),
  weapons: LEGENDS_DATASHEET_RECORDS.weapons.map(r => `${r.faction_id}::${r.id}`),
  abilities: LEGENDS_DATASHEET_RECORDS.abilities.map(r => `${r.faction_id}::${r.ability_id}`),
  unitCompositions: LEGENDS_DATASHEET_RECORDS.unitCompositions.map(r => `${r.faction_id}::${r.unit_id}`),
  wargearOptions: LEGENDS_WARGEAR_OPTION_BLOCKS.flatMap(b => b.options.map(o => `${o.faction_id}::${o.unit_id}::${o.id}`)),
};

/** Upsert the Warhammer Legends datasheets (in place). Idempotent. */
export function applyLegendsDatasheets(rawData) {
  if (!rawData) return rawData;
  upsertDatasheetRecords(rawData, LEGENDS_DATASHEET_RECORDS, LEGENDS_WARGEAR_OPTION_BLOCKS);
  return rawData;
}

// ---------------------------------------------------------------------------
// Codex: Space Marines (11e). The bundle carries the pre-codex index data for
// Space Marines and every chapter: index points (no points at all for Captain
// on Bike), index detachments at index DP and none of the codex ones
// (Assault Brethren, Tactical Brethren, ...), index Leader lists. A GW-app
// list built on the codex imported with unresolved detachments and wrong
// points. sm-codex-11e-data.mjs (generated from a Wahapedia export by
// scripts/40kdc/gen_sm_codex_builder_patch.mjs) holds the codex points,
// Support roles, Leader lists, detachments and enhancements; datasheet
// profiles / kits are NOT refreshed. Nothing is deleted (decision D1): index
// detachments and datasheets the codex dropped are flagged
// superseded_by_codex (hidden from the pickers, still resolvable).
import {
  SM_CODEX_NAME,
  SM_CODEX_UNIT_PATCHES,
  SM_CODEX_SUPERSEDED_UNIT_IDS,
  SM_CODEX_LEADER_ATTACHMENTS,
  SM_CODEX_DETACHMENTS,
  SM_CODEX_ENHANCEMENTS,
  SM_CODEX_SUPERSEDED_DETACHMENTS,
} from './sm-codex-11e-data.mjs';

export { SM_CODEX_UNIT_PATCHES, SM_CODEX_LEADER_ATTACHMENTS };

export function applySmCodex(rawData) {
  if (!rawData) return rawData;
  const units = rawData.units ?? [];
  const smUnit = new Map(units.filter(u => u.faction_id === 'adeptus-astartes').map(u => [u.id, u]));
  for (const p of SM_CODEX_UNIT_PATCHES) {
    const u = smUnit.get(p.id);
    if (!u) continue;
    u.points = cloneRecord(p.points);
    u.points_provisional = false;
    if (p.wargear_points) u.wargear_points = cloneRecord(p.wargear_points);
    if (p.attachment_role) u.attachment_role = p.attachment_role;
  }
  for (const id of SM_CODEX_SUPERSEDED_UNIT_IDS) {
    const u = smUnit.get(id);
    if (u) u.superseded_by_codex = SM_CODEX_NAME;
  }

  const las = rawData.leaderAttachments ?? (rawData.leaderAttachments = []);
  for (const la of SM_CODEX_LEADER_ATTACHMENTS) {
    let hit = false;
    for (const x of las) {
      if (x.leader_id === la.leader_id) { x.eligible_bodyguard_ids = [...la.eligible_bodyguard_ids]; hit = true; }
    }
    if (!hit) las.push({ ...cloneRecord(la), game_version: { edition: '11th', dataslate: 'codex' } });
  }

  // Enhancement ids are shared by the chapter copies of a detachment: every
  // record with the id is replaced.
  const enhancements = rawData.enhancements ?? (rawData.enhancements = []);
  for (const e of SM_CODEX_ENHANCEMENTS) {
    let hit = false;
    enhancements.forEach((x, i) => { if (x.id === e.id) { enhancements[i] = cloneRecord(e); hit = true; } });
    if (!hit) enhancements.push(cloneRecord(e));
  }

  const detachments = rawData.detachments ?? (rawData.detachments = []);
  const detAt = new Map();
  detachments.forEach((d, i) => { const k = `${d.faction_id}::${d.id}`; if (!detAt.has(k)) detAt.set(k, i); });
  for (const d of SM_CODEX_DETACHMENTS) {
    const i = detAt.get(`${d.faction_id}::${d.id}`);
    if (i !== undefined) detachments[i] = cloneRecord(d);
    else detachments.splice(afterFactionBlock(detachments, d.faction_id), 0, cloneRecord(d));
  }
  // Kit errors in the bundle (checked against the codex datasheet): the Grey
  // Hunter Pack Leader swaps the Bolt Pistol, not the Bolt Carbine, for a
  // Plasma Pistol.
  for (const o of rawData.wargearOptions ?? []) {
    if (o.id === 'grey-hunters-wgo-mfm-2' && (o.replaces ?? []).includes('bolt-carbine-grey-hunters')) {
      o.replaces = ['bolt-pistol'];
    }
  }

  const superseded = new Set(SM_CODEX_SUPERSEDED_DETACHMENTS);
  for (const d of detachments) {
    if (superseded.has(`${d.faction_id}::${d.id}`)) d.superseded_by_codex = SM_CODEX_NAME;
  }
  return rawData;
}
