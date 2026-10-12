#!/usr/bin/env node
// Re-apply the game's local hand patches to the extracted dataset JSON.
// `node extract.mjs` rewrites 40k/data/40kdc/*.json from the package and wipes
// any hand edit; run this right after it:
//
//   node extract.mjs && node local-patches.mjs
//
// Every patch is idempotent and logs what it did. Keep the list short and say
// why each exists — the goal is to drop a patch once the dataset ships the fix.
//
// Patches:
//   1. Wazdakka Gutsmek base: the dataset (1.0.19 and 1.4.5) lists a round
//      120mm base; the model ships on a 120x92mm oval, and the game's
//      collision/coherency maths use base_size_mm. (Hand patch carried in the
//      committed units.json since the 1.0.19 import; re-applied for 1.4.5.)
//   2. Datasheet-name keywords: dataset 1.4.5 dropped the datasheet's own
//      keyword from several Codex: Orks datasheets (Boyz lost BOYZ, Nobz lost
//      NOBZ, Beast Snagga Boyz lost BEAST SNAGGA BOYZ, the new Rukkatrukk
//      Squigbuggies / Runtherd / Nazdreg / ... never had one). Codex stratagems
//      target those keywords (MOB MENTALITY / 'ERE WE GO: BOYZ, ARMED TO DA
//      TEEF: NOBZ, DELICIOUS EATING SQUIGS: RUKKATRUKK SQUIGBUGGIES) and leader
//      pairings resolve by them (Warboss can_lead BOYZ/NOBZ). 1.0.19 had them;
//      every GW datasheet carries its own name keyword.
//   3. WAGON keyword: Wahapedia's WAGON keyword list (Codex: Orks, Oct 2026)
//      is Hunta Rig, Kill Rig, Battlewagon, Gunwagon, Kill Tank, Lifta Wagon;
//      1.4.5 tags only the Gunwagon. Blitz Brigade stratagems (READIED
//      BRAWLERS, IMPENDING KRUNCH) and enhancements target WAGON units.
//
// Dropped (no longer applicable): the four Speedwaaagh! enhancements that were
// hand-added to detachments.json / enhancements.json under 1.0.19 — the
// Speedwaaagh! detachment does not exist in Codex: Orks (11e) / dataset 1.4.5.

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { DATA_DIR } from './lib.mjs';

function load(name) {
  return JSON.parse(readFileSync(join(DATA_DIR, `${name}.json`), 'utf8'));
}

function save(name, records) {
  // Same formatting as extract.mjs so a patched file diffs minimally.
  writeFileSync(join(DATA_DIR, `${name}.json`), JSON.stringify(records, null, 1) + '\n');
}

let changed = 0;

// 1. Wazdakka Gutsmek oval base.
{
  const units = load('units');
  const want = { shape: 'oval', width: 120, length: 92 };
  let hits = 0;
  for (const u of units) {
    if (u.faction_id !== 'orks' || u.id !== 'wazdakka-gutsmek') continue;
    hits++;
    if (JSON.stringify(u.base_size_mm) !== JSON.stringify(want)) {
      // Rebuild the record so base_size_mm keeps its position in key order.
      const rebuilt = {};
      for (const [k, v] of Object.entries(u)) rebuilt[k] = k === 'base_size_mm' ? want : v;
      if (!('base_size_mm' in u)) rebuilt.base_size_mm = want;
      Object.keys(u).forEach(k => delete u[k]);
      Object.assign(u, rebuilt);
      changed++;
      console.log('patched units.json: orks/wazdakka-gutsmek base_size_mm -> oval 120x92');
    }
  }
  if (hits === 0) console.warn('WARN: wazdakka-gutsmek not found in units.json — patch 1 skipped');
  if (changed) save('units', units);
}

// 2 + 3. Missing keywords (appended; existing keywords keep their order).
{
  const NAME_KEYWORD = [
    'boyz', 'nobz', 'beast-snagga-boyz', 'squighog-boyz', 'boss-snikrot',
    'ghazghkull-thraka', 'biged-bossbunka', 'gunwagon', 'nazdreg',
    'rukkatrukk-squigbuggies', 'runtherd', 'warbuggies', 'wartrakks',
  ];
  const WAGON = ['battlewagon', 'gunwagon', 'hunta-rig', 'kill-rig', 'kill-tank', 'lifta-wagon'];
  const units = load('units');
  const norm = k => String(k).replace(/\u2019/g, "'").toLowerCase();
  let kwChanged = 0;
  for (const u of units) {
    if (u.faction_id !== 'orks') continue;
    if (!Array.isArray(u.keywords)) continue;
    const have = new Set(u.keywords.map(norm));
    if (NAME_KEYWORD.includes(u.id) && !have.has(norm(u.name))) {
      u.keywords.push(u.name);
      have.add(norm(u.name));
      kwChanged++;
      console.log(`patched units.json: orks/${u.id} + keyword "${u.name}"`);
    }
    if (WAGON.includes(u.id) && !have.has('wagon')) {
      u.keywords.push('Wagon');
      kwChanged++;
      console.log(`patched units.json: orks/${u.id} + keyword "Wagon"`);
    }
  }
  if (kwChanged) { save('units', units); changed += kwChanged; }
}

console.log(`local-patches: ${changed} change(s) applied`);
