#!/usr/bin/env node
// Extract the raw 11th-edition dataset from @alpaca-software/40kdc-data into
// per-collection JSON files under 40k/data/40kdc/ so the game (and the
// generate-*.mjs converters) can consume it without touching node_modules.
//
// Usage:  cd scripts/40kdc && npm install && node extract.mjs
//
// Attribution: dataset (c) Alpaca Software and the 40kdc community
// contributors, CC BY 4.0 — https://40kdc.alpacasoft.dev (see
// 40k/data/40kdc/ATTRIBUTION.md).

import { writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { createRequire } from 'module';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', '40k', 'data', '40kdc');

// Import the raw embedded bundle directly by file path. The package's public
// Dataset API deduplicates shared ids first-wins with no faction scoping
// (e.g. `close-combat-weapon` has per-faction statlines), so the raw stream —
// which keeps every faction's authored copy, in per-faction blocks — is the
// only lossless source. exports-map restrictions don't apply to direct file
// URLs, and the entry point is resolved (not hardcoded) so a package update
// that moves the bundle fails loudly here.
const require = createRequire(import.meta.url);
const pkgEntry = require.resolve('@alpaca-software/40kdc-data');
const bundlePath = join(dirname(pkgEntry), 'data', 'bundle.generated.js');
const { RAW_DATA } = await import(pathToFileURL(bundlePath).href);
const data = typeof RAW_DATA === 'string' ? JSON.parse(RAW_DATA) : RAW_DATA;

mkdirSync(outDir, { recursive: true });

let total = 0;
for (const [name, records] of Object.entries(data)) {
  if (!Array.isArray(records)) continue;
  writeFileSync(join(outDir, `${name}.json`), JSON.stringify(records, null, 1) + '\n');
  total += records.length;
  console.log(`  ${name}.json  (${records.length} records)`);
}
console.log(`Extracted ${Object.keys(data).length} collections, ${total} records -> ${outDir}`);
