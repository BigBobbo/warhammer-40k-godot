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
