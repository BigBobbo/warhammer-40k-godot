#!/usr/bin/env node
// Generate 40k/data/Datasheets.csv + Datasheets_leader.csv (consumed by
// LeaderPairingsLoader as the canonical leader-pairing fallback) from the 11e
// 40kdc dataset: units.json (id -> display name) + leaderAttachments.json
// (leader -> eligible bodyguards).
//
// Ids are `<faction-id>::<unit-id>` so shared unit names across factions stay
// distinct rows; the loader's name lookup unions same-named leaders' pairings,
// which matches its role as a permissive fallback (roster leader_data wins).

import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { loadCollection } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, '..', '..', '40k', 'data');

const units = loadCollection('units');
const leaderAttachments = loadCollection('leaderAttachments');

const clean = s => String(s).replace(/\|/g, '/').replace(/[\r\n]+/g, ' ');

// Datasheets.csv — every unit, faction-scoped id.
const dsRows = ['id|name|faction_id|'];
const idsByUnitId = new Map(); // unit_id -> [faction-scoped ids]
for (const u of units) {
  const id = `${u.faction_id}::${u.id}`;
  dsRows.push(`${id}|${clean(u.name)}|${u.faction_id}|`);
  if (!idsByUnitId.has(u.id)) idsByUnitId.set(u.id, []);
  idsByUnitId.get(u.id).push({ scoped: id, faction: u.faction_id });
}
writeFileSync(join(dataDir, 'Datasheets.csv'), dsRows.join('\n') + '\n');

// Datasheets_leader.csv — leader/bodyguard pairs. leaderAttachments carries no
// faction id; a leader unit id present in several factions gets its bodyguards
// resolved within each faction that actually has BOTH units.
const unitKey = new Set(units.map(u => `${u.faction_id}::${u.id}`));
const lRows = ['leader_id|attached_id|'];
let pairs = 0, unresolved = 0;
for (const la of leaderAttachments) {
  const leaderCopies = idsByUnitId.get(la.leader_id) ?? [];
  if (leaderCopies.length === 0) { unresolved++; continue; }
  for (const leader of leaderCopies) {
    for (const bid of la.eligible_bodyguard_ids) {
      const scopedB = `${leader.faction}::${bid}`;
      if (!unitKey.has(scopedB)) continue; // bodyguard not in this faction
      lRows.push(`${leader.scoped}|${scopedB}|`);
      pairs++;
    }
  }
}
writeFileSync(join(dataDir, 'Datasheets_leader.csv'), lRows.join('\n') + '\n');

console.log(`Datasheets.csv: ${dsRows.length - 1} units`);
console.log(`Datasheets_leader.csv: ${pairs} pairings (${unresolved} unresolved leader ids)`);
