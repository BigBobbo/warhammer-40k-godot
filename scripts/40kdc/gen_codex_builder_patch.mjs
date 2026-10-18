#!/usr/bin/env node
// Generate server/public/js/lib/codex-11e-datasheets.mjs (WP-W3): the codex
// DATASHEET overlay the browser army builder applies on top of its vendored
// @alpaca-software/40kdc-data bundle.
//
// Why: the game reads 40k/data/40kdc/*.json = the 40kdc 1.4.5 extract
// (extract.mjs) + local-patches.mjs + the Wahapedia 11e codex splice
// (wahapedia-import.mjs: Codex: Adeptus Custodes full replacement, Codex: Orks
// overlay). The builder runs on the vendored bundle
// (server/public/js/vendor/40kdc-data.mjs, bundle-browser.mjs), which is the
// same 40kdc release WITHOUT the local patches and the codex splice. This
// script diffs the two and writes every record the game has differently — the
// codex datasheets (profiles, points tiers, wargear points, model counts,
// keywords), their weapons, abilities, unit compositions, wargear options,
// leader pairings and faction records — into one small ES module.
// data-patches.mjs upserts those records into the bundle's RAW_DATA by id at
// load, so the builder sees each datasheet exactly as the game does.
//
// Scope:
//   - collections: units, weapons, abilities, unitCompositions,
//     wargearOptions (whole per-unit blocks), leaderAttachments, factions.
//   - NOT enhancements / detachments: Custodes ones come from
//     custodes-codex-11e-data.mjs (WP-C46, gen_custodes_builder_patch.py), Ork
//     ones from orks-codex-11e-data.mjs (WP-O5).
//   - Diff-driven, so it covers exactly what the import changed and shrinks by
//     itself when a 40kdc release ships a codex (PLAN W4). A faction other than
//     the imported ones showing up in the diff is reported (it means the
//     extract and the bundle are not the same 40kdc release).
//   - Records the codex removed are never deleted from the data (decision D1:
//     old lists keep resolving). Pre-codex Custodes datasheets (the codex is a
//     full replacement: renamed, split, removed or moved to Legends) are listed
//     in CODEX_SUPERSEDED_UNITS; the builder flags them superseded_by_codex and
//     stops offering them as new picks, like the superseded detachments.
//
// Usage (repo root or scripts/40kdc):  node scripts/40kdc/gen_codex_builder_patch.mjs [--check]
//   --check  exit 1 when the committed module is out of date (writes nothing).
// Run by `npm run codex11e` (after the import) and by bundle-browser.mjs
// (after a re-bundle). Deterministic: the same inputs give the same file.

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { dirname, join, relative } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = join(here, '..', '..');
const DATA_DIR = join(ROOT, '40k', 'data', '40kdc');
const VENDOR = join(ROOT, 'server', 'public', 'js', 'vendor', '40kdc-data.mjs');
export const OUT = join(ROOT, 'server', 'public', 'js', 'lib', 'codex-11e-datasheets.mjs');

// Factions the Wahapedia import splices (wahapedia-import.mjs FACTIONS) and
// the codex each one follows. `full`: the codex replaced the faction's
// datasheet list wholesale (mode "full"), so a datasheet of that faction that
// the import did not write is not in the codex.
export const CODEX_FACTIONS = {
  'adeptus-custodes': { codex: 'Codex: Adeptus Custodes (11th edition)', full: true },
  'orks': { codex: 'Codex: Orks (11th edition)', full: false },
};

// Record keys. Shared ids are per-faction copies in 40kdc (close-combat-weapon,
// deadly-demise-d3, ...), so weapons / abilities / units key on (faction, id).
const KEYS = {
  units: r => `${r.faction_id}::${r.id}`,
  weapons: r => `${r.faction_id ?? ''}::${r.id}`,
  abilities: r => `${r.faction_id ?? ''}::${r.ability_id}`,
  unitCompositions: r => `${r.faction_id}::${r.unit_id}`,
  leaderAttachments: r => r.leader_id,
  factions: r => r.id,
};
const COLLECTIONS = Object.keys(KEYS);

const IMPORT_SOURCE_RE = /^wahapedia-11e@/;

function loadGame(name) {
  return JSON.parse(readFileSync(join(DATA_DIR, `${name}.json`), 'utf8'));
}

function firstByKey(arr, keyOf) {
  const m = new Map();
  for (const r of arr ?? []) { const k = keyOf(r); if (!m.has(k)) m.set(k, r); }
  return m;
}

function blocksByUnit(options) {
  const m = new Map();
  for (const o of options ?? []) {
    const k = `${o.faction_id}::${o.unit_id}`;
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(o);
  }
  return m;
}

// One record per line: compact, and a re-import diffs record by record.
function jsonLines(arr) {
  if (!arr.length) return '[]';
  return '[\n' + arr.map(r => JSON.stringify(r)).join(',\n') + '\n]';
}

/** Build the module text. Returns { text, summary }. */
export async function buildCodexBuilderPatch() {
  // A private module instance of the bundle: a process that already loaded
  // (and patched) the vendored module — the builder's tests — must still diff
  // against the bare release.
  const V = await import(`${pathToFileURL(VENDOR).href}?gen_codex_builder_patch`);
  const raw = V.RAW_DATA;
  const baseVersion = V.DATASET_VERSION ?? null;

  const game = Object.fromEntries(COLLECTIONS.map(c => [c, loadGame(c)]));
  const gameUnitFaction = new Map(game.units.map(u => [u.id, u.faction_id]));
  const factionOfRecord = (coll, r) =>
    coll === 'leaderAttachments' ? (gameUnitFaction.get(r.leader_id) ?? null)
      : coll === 'factions' ? r.id
        : (r.faction_id ?? null);

  const out = {};
  const summary = {};
  const unexpected = [];
  // leaderAttachments carry no faction id and a few leader ids are shared
  // across factions (ministorum-priest, sorcerer, ...): the leader_id key is
  // only safe for leaders whose id is unique in the data.
  const leaderIdCount = new Map();
  for (const la of game.leaderAttachments) leaderIdCount.set(la.leader_id, (leaderIdCount.get(la.leader_id) ?? 0) + 1);
  for (const coll of COLLECTIONS) {
    const keyOf = KEYS[coll];
    const bundle = firstByKey(raw[coll], keyOf);
    const seen = new Set();
    const recs = [];
    for (const g of game[coll]) {
      const k = keyOf(g);
      if (seen.has(k)) continue; // first copy wins, as in the resolvers
      seen.add(k);
      const b = bundle.get(k);
      if (b && JSON.stringify(b) === JSON.stringify(g)) continue;
      const fid = factionOfRecord(coll, g);
      if (fid && !CODEX_FACTIONS[fid]) unexpected.push(`${coll} ${k}`);
      if (coll === 'leaderAttachments' && leaderIdCount.get(g.leader_id) > 1) {
        unexpected.push(`${coll} ${k} (leader id shared by several factions — keyed upsert would be ambiguous)`);
      }
      recs.push(g);
    }
    // The splice never deletes (D1); a key the bundle has and the game lacks
    // means the extract and the bundle drifted apart.
    const gameKeys = new Set(game[coll].map(keyOf));
    for (const k of bundle.keys()) if (!gameKeys.has(k)) unexpected.push(`${coll} ${k} (missing from the game data)`);
    out[coll] = recs;
    summary[coll] = recs.length;
  }

  // Wargear options: a codex datasheet's option block replaces the old block
  // whole (the import rewrites it per unit), so diff and ship whole blocks.
  const gameOpts = blocksByUnit(loadGame('wargearOptions'));
  const bundleOpts = blocksByUnit(raw.wargearOptions);
  const blocks = [];
  for (const k of [...new Set([...gameOpts.keys(), ...bundleOpts.keys()])]) {
    const g = gameOpts.get(k) ?? [];
    const b = bundleOpts.get(k) ?? [];
    if (JSON.stringify(g) === JSON.stringify(b)) continue;
    const [faction_id, unit_id] = k.split('::');
    if (!CODEX_FACTIONS[faction_id]) unexpected.push(`wargearOptions ${k}`);
    blocks.push({ faction_id, unit_id, options: g });
  }
  blocks.sort((a, b) => `${a.faction_id}::${a.unit_id}`.localeCompare(`${b.faction_id}::${b.unit_id}`));
  summary.wargearOptionBlocks = blocks.length;

  // Pre-codex datasheets of a fully replaced faction (D1): not written by the
  // import. superseded_by = the codex datasheet a pre-codex roster moves to
  // (gameformat.mjs UNIT_ALIASES — the same renames generate-armies applies).
  const { UNIT_ALIASES } = await import(pathToFileURL(join(ROOT, 'server', 'public', 'js', 'lib', 'gameformat.mjs')).href);
  const { normName } = await import(pathToFileURL(join(ROOT, 'server', 'public', 'js', 'lib', 'dckit.mjs')).href);
  const superseded = [];
  for (const [fid, cfg] of Object.entries(CODEX_FACTIONS)) {
    if (!cfg.full) continue;
    for (const u of game.units) {
      if (u.faction_id !== fid || IMPORT_SOURCE_RE.test(u.source ?? '')) continue;
      superseded.push({
        faction_id: fid, id: u.id, name: u.name,
        superseded_by: UNIT_ALIASES[fid]?.[normName(u.name)] ?? null,
        codex: cfg.codex,
      });
    }
  }
  superseded.sort((a, b) => a.id.localeCompare(b.id));
  summary.supersededUnits = superseded.length;

  // Provenance stamp: the import's source tags (wahapedia-11e@<export date>).
  const tags = [...new Set(game.units.map(u => u.source).filter(s => IMPORT_SOURCE_RE.test(s ?? '')))].sort();

  const text = [
    '// GENERATED by scripts/40kdc/gen_codex_builder_patch.mjs from the game\'s',
    '// 40k/data/40kdc/*.json (40kdc extract + local-patches + Wahapedia 11e codex',
    '// import) diffed against the vendored 40kdc bundle. Do not edit by hand —',
    '// re-run the script (npm run codex11e does). Applied by data-patches.mjs',
    '// applyCodexDatasheets() (WP-W3).',
    '',
    `// The vendored bundle version the diff was taken against.`,
    `export const CODEX_OVERLAY_BASE_VERSION = ${JSON.stringify(baseVersion)};`,
    '',
    `// Wahapedia import source tags carried by the overlaid records.`,
    `export const CODEX_OVERLAY_SOURCES = ${JSON.stringify(tags)};`,
    '',
    '// Factions the overlay covers, with the codex each follows.',
    `export const CODEX_OVERLAY_FACTIONS = ${JSON.stringify(CODEX_FACTIONS, null, 1)};`,
    '',
    '// Records the game has differently from the bundle, by collection. Upserted',
    '// by key: units / weapons / abilities on (faction_id, id), unitCompositions on',
    '// (faction_id, unit_id), leaderAttachments on leader_id, factions on id.',
    'export const CODEX_DATASHEET_RECORDS = {',
    ...COLLECTIONS.map(c => `${JSON.stringify(c)}: ${jsonLines(out[c])},`),
    '};',
    '',
    '// Whole per-datasheet wargear option blocks (they replace the bundle block).',
    `export const CODEX_WARGEAR_OPTION_BLOCKS = ${jsonLines(blocks)};`,
    '',
    '// Pre-codex datasheets of a fully replaced faction (D1): kept so old lists',
    '// resolve, flagged superseded_by_codex, not offered as new picks.',
    `export const CODEX_SUPERSEDED_UNITS = ${jsonLines(superseded)};`,
    '',
  ].join('\n');
  return { text, summary, unexpected, baseVersion };
}

export async function writeCodexBuilderPatch({ check = false, log = console.log } = {}) {
  const { text, summary, unexpected, baseVersion } = await buildCodexBuilderPatch();
  for (const u of unexpected) log(`WARN: ${u} differs outside the imported codex factions`);
  const rel = relative(ROOT, OUT);
  const parts = Object.entries(summary).map(([k, v]) => `${k} ${v}`).join(', ');
  if (check) {
    const cur = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
    if (cur !== text) { log(`STALE ${rel} — re-run gen_codex_builder_patch.mjs`); return false; }
    log(`OK ${rel} is up to date (${parts}; base ${baseVersion})`);
    return true;
  }
  writeFileSync(OUT, text);
  log(`WROTE ${rel} (${(text.length / 1024).toFixed(0)} KB; ${parts}; base ${baseVersion})`);
  return true;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const ok = await writeCodexBuilderPatch({ check: process.argv.includes('--check') });
  process.exit(ok ? 0 : 1);
}
