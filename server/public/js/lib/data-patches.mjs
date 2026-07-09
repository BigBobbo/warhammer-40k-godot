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
// Environment-free (no fs / DOM). applyDataPatches() mutates the RAW_DATA
// arrays in place and is idempotent — the converter (createConverter) and the
// package importer (tryImportRoster) both read these arrays/objects by
// reference, so an in-place patch reaches every consumer.

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
const ENHANCEMENT_PATCHES = [
  { detachmentId: 'speedwaaagh', enhancements: SPEEDWAAAGH_ENHANCEMENTS },
];

/**
 * Idempotently add the missing enhancement records to rawData.enhancements and
 * wire their ids into the owning detachment's enhancement_ids. Returns rawData.
 */
export function applyDataPatches(rawData) {
  if (!rawData) return rawData;
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
  return rawData;
}
