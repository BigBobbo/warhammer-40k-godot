#!/usr/bin/env node
// Geometry acceptance gate for the converted 11e terrain layouts
// (docs/40KDC_TERRAIN_MIGRATION_SPEC.md §8 — "faithful to the 40kdc dataset").
//
// For all 45 dataset layouts, asserts that the emitted game JSON in
// 40k/terrain_layouts/ reproduces resolveLayout() geometry exactly:
//   - piece count, ids and emission order match the resolver output
//   - every polygon vertex equals the transposed resolver vertex (4-dp)
//   - every centroid equals the transposed polygonCentroid (4-dp)
//   - every vertex lies within the 44x60 portrait board
//   - rotation is baked into the polygon (rotation == 0, no walls)
//   - piece_class mirrors the dataset piece_type
//   - index_11e.json lists exactly the emitted layouts
//
// Run standalone (exit 1 on any failure):
//   cd scripts/40kdc && node verify-terrain-layouts.mjs
// Also invoked automatically by generate-terrain-layouts.mjs.

import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { resolveLayout, polygonCentroid } from '@alpaca-software/40kdc-data';
import { loadCollection } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const layoutDir = join(here, '..', '..', '40k', 'terrain_layouts');

// Independent re-statement of the spec §3 transform: 4-dp round + transpose
// (dataset 60x44 landscape {x,y} -> game 44x60 portrait [y, x]).
const r4 = v => Math.round(v * 1e4) / 1e4;
const expectVert = v => [r4(v.y), r4(v.x)];

const BOARD_W = 44, BOARD_H = 60, EPS = 1e-9;

export function verifyAll() {
  const layouts = loadCollection('terrainLayouts');
  const templates = loadCollection('terrainTemplates');

  let failures = 0;
  let checkedLayouts = 0, checkedPieces = 0, checkedVerts = 0;
  const emittedIds = [];
  const fail = msg => { failures++; console.error(`FAIL ${msg}`); };

  for (const layout of layouts) {
    const gameId = layout.id.replace(/-/g, '_');
    emittedIds.push(gameId);
    const path = join(layoutDir, `${gameId}.json`);
    if (!existsSync(path)) { fail(`${gameId}: missing ${path}`); continue; }

    let game;
    try {
      game = JSON.parse(readFileSync(path, 'utf8'));
    } catch (e) {
      fail(`${gameId}: unparseable JSON (${e.message})`); continue;
    }

    const resolved = resolveLayout(layout, templates);
    const gamePieces = game.pieces ?? [];
    if (gamePieces.length !== resolved.length) {
      fail(`${gameId}: ${gamePieces.length} emitted pieces != ${resolved.length} resolved`);
      continue;
    }

    resolved.forEach((rp, i) => {
      const gp = gamePieces[i];
      const tag = `${gameId}[${i}] ${rp.id}`;
      if (gp.id !== rp.id) fail(`${tag}: emitted id ${gp.id} != resolver id`);
      if (gp.piece_class !== rp.piece_type) fail(`${tag}: piece_class ${gp.piece_class} != ${rp.piece_type}`);
      if ((gp.rotation ?? 0) !== 0) fail(`${tag}: rotation ${gp.rotation} != 0 (must be baked into polygon)`);
      if ((gp.walls ?? []).length !== 0) fail(`${tag}: unexpected walls`);

      const poly = gp.polygon ?? [];
      if (poly.length !== rp.vertices.length) {
        fail(`${tag}: ${poly.length} polygon verts != ${rp.vertices.length} resolved`);
        return;
      }
      rp.vertices.forEach((v, j) => {
        const want = expectVert(v);
        const got = poly[j];
        if (!Array.isArray(got) || got.length !== 2
            || Math.abs(got[0] - want[0]) > EPS || Math.abs(got[1] - want[1]) > EPS) {
          fail(`${tag} vert ${j}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
          return;
        }
        if (got[0] < -EPS || got[0] > BOARD_W + EPS || got[1] < -EPS || got[1] > BOARD_H + EPS) {
          fail(`${tag} vert ${j}: ${JSON.stringify(got)} outside the ${BOARD_W}x${BOARD_H} board`);
        }
        checkedVerts++;
      });

      const wantC = expectVert(polygonCentroid(rp.vertices));
      const gotC = gp.position ?? [];
      if (Math.abs(gotC[0] - wantC[0]) > EPS || Math.abs(gotC[1] - wantC[1]) > EPS) {
        fail(`${tag}: centroid ${JSON.stringify(gotC)} != ${JSON.stringify(wantC)}`);
      }
      checkedPieces++;
    });
    checkedLayouts++;
  }

  // Index consistency.
  const indexPath = join(layoutDir, 'index_11e.json');
  if (!existsSync(indexPath)) {
    fail('index_11e.json missing');
  } else {
    const listed = (JSON.parse(readFileSync(indexPath, 'utf8')).layouts ?? []).map(e => e.id).sort();
    const expected = [...emittedIds].sort();
    if (JSON.stringify(listed) !== JSON.stringify(expected)) {
      fail(`index_11e.json ids do not match the ${expected.length} dataset layouts`);
    }
  }

  if (failures === 0) {
    console.log(`VERIFY PASS — ${checkedLayouts} layouts, ${checkedPieces} pieces, ${checkedVerts} vertices match resolveLayout() transposed to the 44x60 board (4-dp)`);
  } else {
    console.error(`VERIFY FAIL — ${failures} failure(s)`);
  }
  return failures;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(verifyAll() > 0 ? 1 : 0);
}
