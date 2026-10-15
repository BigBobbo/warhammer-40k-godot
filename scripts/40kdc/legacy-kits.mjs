#!/usr/bin/env node
// Freeze the PREVIOUS dataset's datasheet kits for datasheets a codex rewrote,
// so rosters built against the old datasheets keep resolving their loadouts.
//
//   node legacy-kits.mjs --old <dir> [--faction orks] [--tag 1.0.19]
//
// <dir> holds the previous release's extracted unitCompositions.json and
// wargearOptions.json (e.g. `git show <rev>:40k/data/40kdc/unitCompositions.json`).
// Writes 40k/data/40kdc/legacy/unitCompositions_<tag>.json and
// wargearOptions_<tag>.json containing, for the given faction only, the OLD
// composition AND wargear-option records of every datasheet whose composition
// (models / roles / default kit) differs in the current extract, or that the
// current extract no longer has at all. The legacy pair is consulted as a
// unit, so both collections are frozen for those datasheets even when only one
// of them changed.
//
// Why: UnitLoadoutResolver / RulesEngine narrow a unit's datasheet weapon MENU
// to what it actually carries using these two collections, matched by
// datasheet name. Codex: Orks (11e, dataset 1.4.5) renamed and restructured
// many Ork kits (Battlewagon "Tracks and wheels" -> "Crushin' bulk", Boyz "Boss
// Nob" -> "Nob" with new weapons, Mek Gunz "Grot crew" -> "Scavenged shivs",
// Lootas/Burna Boyz removed). Army files, save fixtures, players' saves and
// web-builder exports (the browser bundle is still 1.0.19) carry the OLD weapon
// names, so against the new kits they silently lost per-model resolution (a Boy
// "carrying" every melee option). UnitLoadoutResolver.datasheet_key() picks the
// legacy kit for a unit only when the unit's own weapon menu matches the legacy
// kit and not the current one; units built from the current datasheets are
// untouched.

import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, resolve } from 'path';
import { DATA_DIR, argValue } from './lib.mjs';

const oldDir = argValue('old');
if (!oldDir) {
  console.error('usage: node legacy-kits.mjs --old <dir with previous unitCompositions.json + wargearOptions.json> [--faction orks] [--tag 1.0.19]');
  process.exit(2);
}
const faction = argValue('faction') || 'orks';
const tag = argValue('tag') || '1.0.19';
const outDir = join(DATA_DIR, 'legacy');

const read = (dir, name) => JSON.parse(readFileSync(join(resolve(dir), `${name}.json`), 'utf8'));

// Compare datasheet records ignoring provenance-only fields.
const IGNORED = new Set(['game_version', 'id']);
function canon(rec) {
  const out = {};
  for (const k of Object.keys(rec).sort()) if (!IGNORED.has(k)) out[k] = rec[k];
  return JSON.stringify(out);
}
function groupByUnit(records) {
  const g = new Map();
  for (const r of records) {
    if (r.faction_id !== faction) continue;
    if (!g.has(r.unit_id)) g.set(r.unit_id, []);
    g.get(r.unit_id).push(r);
  }
  return g;
}

function changedUnits(name) {
  const oldG = groupByUnit(read(oldDir, name));
  const newG = groupByUnit(read(DATA_DIR, name));
  const units = [];
  for (const [uid, oldRecs] of oldG) {
    // `tiers` (points-band composition lines) is new in 1.4.x and not read by
    // the loadout resolver — ignore it when deciding whether a kit changed.
    const strip = r => { const c = { ...r }; delete c.tiers; return canon(c); };
    const a = oldRecs.map(strip).sort();
    const b = (newG.get(uid) || []).map(strip).sort();
    if (JSON.stringify(a) !== JSON.stringify(b)) units.push(uid);
  }
  return units;
}

const frozen = new Set(changedUnits('unitCompositions'));
const pick = name => read(oldDir, name).filter(r => r.faction_id === faction && frozen.has(r.unit_id));
const comps = { units: [...frozen], out: pick('unitCompositions') };
const opts = { out: pick('wargearOptions') };
opts.units = [...new Set(opts.out.map(r => r.unit_id))];

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, `unitCompositions_${tag}.json`), JSON.stringify(comps.out, null, 1) + '\n');
writeFileSync(join(outDir, `wargearOptions_${tag}.json`), JSON.stringify(opts.out, null, 1) + '\n');
console.log(`legacy ${tag} ${faction}: ${comps.units.length} datasheet compositions (${comps.out.length} records), ` +
  `${opts.units.length} datasheets' wargear options (${opts.out.length} records) -> ${outDir}`);
console.log(`  compositions: ${comps.units.join(', ')}`);
