#!/usr/bin/env node
// Generate 40k/data/Datasheets.csv + Datasheets_leader.csv (consumed by
// LeaderPairingsLoader as the canonical leader-pairing fallback) from the 11e
// 40kdc dataset: units.json (id -> display name) + leaderAttachments.json
// (leader -> eligible bodyguards).
//
//   node generate-leader-pairings.mjs                       # every faction
//   node generate-leader-pairings.mjs --only-faction orks   # splice ONLY orks rows
//
// --only-faction <40kdc faction id>: rewrite the committed CSVs replacing only
// that faction's rows (Datasheets.csv: faction_id column; Datasheets_leader.csv:
// leader ids prefixed "<faction>::"); every other line stays byte-identical.
// Used for the Codex: Orks (11e) refresh (.llm/ork_codex_11e_design.md §1) —
// a full run under 1.4.5 would also drop ~35 Space Marine pairings because the
// dataset moved some bodyguards to `eligible_bodyguard_keywords`, which this
// generator does not expand yet.
// --base-dir / --out-dir <dir>: read the committed CSVs from / write to
// another directory (default 40k/data for both).
//
// Ids are `<faction-id>::<unit-id>` so shared unit names across factions stay
// distinct rows; the loader's name lookup unions same-named leaders' pairings,
// which matches its role as a permissive fallback (roster leader_data wins).

import { writeFileSync } from 'fs';
import { dirname, join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { loadCollection, spliceCsvRows, argValue } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const defaultDataDir = join(here, '..', '..', '40k', 'data');
const baseDir = resolve(argValue('base-dir') || defaultDataDir);
const outDir = resolve(argValue('out-dir') || defaultDataDir);
const onlyFaction = argValue('only-faction');

const units = loadCollection('units');
const leaderAttachments = loadCollection('leaderAttachments');

const clean = s => String(s).replace(/\|/g, '/').replace(/[\r\n]+/g, ' ');

// Datasheets.csv — every unit, faction-scoped id.
const dsHeader = 'id|name|faction_id|';
const dsRows = []; // { line, faction }
const idsByUnitId = new Map(); // unit_id -> [faction-scoped ids]
for (const u of units) {
  const id = `${u.faction_id}::${u.id}`;
  dsRows.push({ line: `${id}|${clean(u.name)}|${u.faction_id}|`, faction: u.faction_id });
  if (!idsByUnitId.has(u.id)) idsByUnitId.set(u.id, []);
  idsByUnitId.get(u.id).push({ scoped: id, faction: u.faction_id });
}

// Datasheets_leader.csv — leader/bodyguard pairs. leaderAttachments carries no
// faction id; a leader unit id present in several factions gets its bodyguards
// resolved within each faction that actually has BOTH units.
const lHeader = 'leader_id|attached_id|';
const unitKey = new Set(units.map(u => `${u.faction_id}::${u.id}`));
const lRows = []; // { line, faction }
let pairs = 0, unresolved = 0;
for (const la of leaderAttachments) {
  const leaderCopies = idsByUnitId.get(la.leader_id) ?? [];
  if (leaderCopies.length === 0) { unresolved++; continue; }
  for (const leader of leaderCopies) {
    for (const bid of la.eligible_bodyguard_ids) {
      const scopedB = `${leader.faction}::${bid}`;
      if (!unitKey.has(scopedB)) continue; // bodyguard not in this faction
      lRows.push({ line: `${leader.scoped}|${scopedB}|`, faction: leader.faction });
      pairs++;
    }
  }
}

if (onlyFaction) {
  if (!dsRows.some(r => r.faction === onlyFaction)) {
    throw new Error(`--only-faction ${onlyFaction}: no units for that 40kdc faction id`);
  }
  const ds = spliceCsvRows(join(baseDir, 'Datasheets.csv'), {
    isTarget: l => l.split('|')[2] === onlyFaction,
    newRows: dsRows.filter(r => r.faction === onlyFaction).map(r => r.line),
  });
  const lp = spliceCsvRows(join(baseDir, 'Datasheets_leader.csv'), {
    isTarget: l => l.startsWith(`${onlyFaction}::`),
    newRows: lRows.filter(r => r.faction === onlyFaction).map(r => r.line),
  });
  writeFileSync(join(outDir, 'Datasheets.csv'), ds.text);
  writeFileSync(join(outDir, 'Datasheets_leader.csv'), lp.text);
  console.log(`--only-faction ${onlyFaction}: other factions' rows left byte-identical`);
  console.log(`Datasheets.csv: ${onlyFaction} rows ${ds.removed} -> ${ds.inserted}`);
  console.log(`Datasheets_leader.csv: ${onlyFaction} pairings ${lp.removed} -> ${lp.inserted}`);
} else {
  writeFileSync(join(outDir, 'Datasheets.csv'), [dsHeader, ...dsRows.map(r => r.line)].join('\n') + '\n');
  writeFileSync(join(outDir, 'Datasheets_leader.csv'), [lHeader, ...lRows.map(r => r.line)].join('\n') + '\n');
  console.log(`Datasheets.csv: ${dsRows.length} units`);
  console.log(`Datasheets_leader.csv: ${pairs} pairings (${unresolved} unresolved leader ids)`);
}
