#!/usr/bin/env node
// Freeze the PREVIOUS dataset's datasheet kits for datasheets a codex rewrote,
// so rosters built against the old datasheets keep resolving their loadouts.
//
//   node legacy-kits.mjs --old <dir> [--faction orks] [--tag 1.0.19]
//        [--from "<dataset the old kits come from>"] [--units a,b,c]
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
// Every frozen record carries `frozen_from`: the dataset its kit was taken
// from (--from, default "40kdc-data <tag>"). The file name is the tag of the
// FIRST freeze (1.0.19) and the game addresses every frozen kit as
// "<name> [1.0.19]"; the records' frozen_from says which dataset each kit
// really is — "40kdc-data 1.0.19" for the original Ork / Custodes freezes,
// "40kdc-data 1.4.5" for the Ork datasheets the Wahapedia overlay re-kitted
// (WP-O1b: Tankbustas, Warbikers, Runtherd, Nazdreg). The game holds ONE
// legacy kit per datasheet, so a datasheet is never frozen twice: those four
// kept their 1.0.19 kit in 1.4.5, so their one frozen kit covers both.
//
// Merging:
//   - without --units: the faction's block is replaced (records of other
//     factions already in the files are kept). This is how the Orks and then
//     Codex: Adeptus Custodes were first frozen.
//   - with --units: only those datasheets are frozen (each must have changed)
//     and added to the files; datasheets already frozen are left as they are
//     (reported), every other record is kept byte-identical. Use this when a
//     later import re-kits a few more datasheets of an already-frozen faction.
//
// Why: UnitLoadoutResolver / RulesEngine narrow a unit's datasheet weapon MENU
// to what it actually carries using these two collections, matched by
// datasheet name. Codex: Orks (11e, dataset 1.4.5) renamed and restructured
// many Ork kits (Battlewagon "Tracks and wheels" -> "Crushin' bulk", Boyz "Boss
// Nob" -> "Nob" with new weapons, Mek Gunz "Grot crew" -> "Scavenged shivs",
// Lootas/Burna Boyz removed). Army files, save fixtures, players' saves and
// web-builder exports made before WP-W3 (the browser bundle was 1.0.19 until
// then; it is now 1.4.5 + the codex overlay) carry the OLD weapon
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
  console.error('usage: node legacy-kits.mjs --old <dir with previous unitCompositions.json + wargearOptions.json> [--faction orks] [--tag 1.0.19] [--from "40kdc-data 1.4.5"] [--units a,b]');
  process.exit(2);
}
const faction = argValue('faction') || 'orks';
const tag = argValue('tag') || '1.0.19';
const frozenFrom = argValue('from') || `40kdc-data ${tag}`;
const onlyUnits = argValue('units') ? new Set(argValue('units').split(',').map(s => s.trim()).filter(Boolean)) : null;
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

const changed = new Set(changedUnits('unitCompositions'));
const legacyPath = name => join(outDir, `${name}_${tag}.json`);
const readPrev = name => { try { return JSON.parse(readFileSync(legacyPath(name), 'utf8')); } catch { return []; } };
const prevComps = readPrev('unitCompositions');
const alreadyFrozen = new Set(prevComps.filter(r => r.faction_id === faction).map(r => r.unit_id));

let frozen;
if (onlyUnits) {
  for (const u of onlyUnits) {
    if (!changed.has(u)) {
      console.error(`legacy-kits: ${faction}/${u}: its composition did not change between --old and the current data — nothing to freeze`);
      process.exit(1);
    }
  }
  const skipped = [...onlyUnits].filter(u => alreadyFrozen.has(u));
  if (skipped.length) console.log(`  already frozen (kept as they are — one legacy kit per datasheet): ${skipped.join(', ')}`);
  frozen = new Set([...onlyUnits].filter(u => !alreadyFrozen.has(u)));
} else {
  frozen = changed;
}

const stamp = r => ({ ...r, frozen_from: frozenFrom });
const pick = name => read(oldDir, name).filter(r => r.faction_id === faction && frozen.has(r.unit_id)).map(stamp);
const comps = { units: [...frozen], out: pick('unitCompositions') };
const opts = { out: pick('wargearOptions') };
opts.units = [...new Set(opts.out.map(r => r.unit_id))];

mkdirSync(outDir, { recursive: true });
// Merge: without --units the faction's block is replaced (Orks were frozen
// first; Codex: Adeptus Custodes added its own block); with --units the new
// datasheets are appended to the faction's block and nothing else moves.
const merge = (name, recs) => {
  const prev = readPrev(name);
  if (!onlyUnits) return [...prev.filter(r => r.faction_id !== faction), ...recs];
  const last = prev.reduce((at, r, i) => (r.faction_id === faction ? i : at), prev.length - 1);
  return [...prev.slice(0, last + 1), ...recs, ...prev.slice(last + 1)];
};
writeFileSync(legacyPath('unitCompositions'), JSON.stringify(merge('unitCompositions', comps.out), null, 1) + '\n');
writeFileSync(legacyPath('wargearOptions'), JSON.stringify(merge('wargearOptions', opts.out), null, 1) + '\n');
console.log(`legacy ${tag} ${faction} (frozen from ${frozenFrom}): ${comps.units.length} datasheet compositions (${comps.out.length} records), ` +
  `${opts.units.length} datasheets' wargear options (${opts.out.length} records) -> ${outDir}`);
console.log(`  compositions: ${comps.units.join(', ')}`);
