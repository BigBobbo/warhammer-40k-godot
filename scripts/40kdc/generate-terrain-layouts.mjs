#!/usr/bin/env node
// Generate 40k/terrain_layouts/*.json from the 40kdc terrainLayouts collection
// (the 45 official 11e GW terrain-layout cards: 15 Force-Disposition matchup
// pairings x 3 variants), per docs/40KDC_TERRAIN_MIGRATION_SPEC.md.
//
// Geometry comes from the package's resolveLayout() — the pinned resolver that
// turns template references + centroid placements + rotation/mirror into
// absolute board-space polygon vertices (docs spec §2: do NOT reimplement).
// Rotation/mirror are baked into the vertices, so every emitted piece has
// rotation: 0 and an explicit `polygon` (spec Decision D1).
//
// Coordinate transform (spec §3): the dataset authors a landscape 60x44-inch
// board (y-down); the game uses portrait 44x60 (y-down, origin top-left). The
// mapping is a pure transpose — (x_game, y_game) = (y_dc, x_dc) — identical to
// generate-deployment-zones.mjs (verified by the centre objective
// (30,22) -> (22,30)).
//
// Field mapping (spec §6, judgment calls documented inline):
//   type          -> "ruins" for every piece (spec: no woods-like template in
//                    the 16-template catalog; D2-a relies on obscuring for LoS)
//   piece_class   -> dataset piece_type ("area" | "feature")
//   height_inches -> piece override ?? template default; for areas: max over
//                    the features parented to that area (0 if empty)
//   height        -> <2" low, 2-4" medium, >4" tall (spec §6 thresholds; the
//                    5" ruins land in "tall" so legacy LoS treats them as
//                    implicitly obscuring, matching 11e "Ruins are Obscuring")
//   category      -> features: template terrain_category (light/dense);
//                    areas: dense if any parented feature is dense, else light
//                    if any is light, else exposed (13.03) for empty zones.
//                    Drives TerrainManager's 11e visibility path (ISS-051/052:
//                    explicit piece "category" wins in category_of()).
//   traits        -> dense -> "obscuring"; light -> "difficult_ground";
//                    areas additionally always "difficult_ground" (spec §6).
//                    terrain_area_keywords overrides are honored for
//                    "obscuring"; "hidden"/"plunging-fire" are NOT implemented
//                    by the engine (spec §9.5, out of v1 scope) and only warn.
//   walls         -> none (spec Decision D2-a: the dataset has no wall/window
//                    data; obscuring polygons carry the LoS blocking)
//   objectives    -> spec Decision D3-a: each layout emits its own
//                    objectives[] derived from the objective pieces. Every
//                    dataset layout carries exactly 6 objective pieces that
//                    resolve to FIVE markers (D4: no 6-objective boards):
//                      - 2 "home" areas -> obj_home_1 (player1, smaller game
//                        y = top of the portrait board, the game's zone
//                        convention) and obj_home_2 (player2), marker at the
//                        piece centroid;
//                      - 2 "expansion" areas -> obj_nml_1 / obj_nml_2 (by the
//                        same y-order), markers at the piece centroids;
//                      - 2 linked "center" areas (link_group "Center") ->
//                        ONE obj_center at the pair's centroid midpoint,
//                        which is exactly the board centre (22,30) in all 45
//                        layouts (asserted by the verifier).
//                    MissionManager prefers these over the deployment-zone
//                    objectives when the loaded layout carries them; legacy
//                    layouts keep the deployment-zone source (fallback).
//                    The per-piece flags (is_objective / objective_role /
//                    link_group) are still carried for the 14.01 rule.
//
// Also emits 40k/terrain_layouts/index_11e.json so TerrainManager can
// register the 45 ids without a hardcoded list (and for future D5 UI wiring).
//
// Refresh: cd scripts/40kdc && node generate-terrain-layouts.mjs
// Verify:  node verify-terrain-layouts.mjs   (spec §8 geometry gate — also run
//          automatically at the end of this script)

import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { resolveLayout, polygonCentroid } from '@alpaca-software/40kdc-data';
import { loadCollection } from './lib.mjs';
import { verifyAll } from './verify-terrain-layouts.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', '40k', 'terrain_layouts');

// Same map as generate-deployment-zones.mjs (game deployment-zone ids).
const DEPLOYMENT_ID_MAP = {
  'hammer-and-anvil': 'hammer_anvil',
  'dawn-of-war': 'dawn_of_war',
  'search-and-destroy': 'search_and_destroy',
  'sweeping-engagement': 'sweeping_engagement',
  'crucible-of-battle': 'crucible_of_battle',
  'tipping-point': 'tipping_point',
};

export const gameLayoutId = dcId => dcId.replace(/-/g, '_');

const r4 = v => Math.round(v * 1e4) / 1e4;
// Dataset {x,y} (60x44 landscape) -> game [x,y] (44x60 portrait): transpose.
export const transpose = v => [r4(v.y), r4(v.x)];

// Spec §6 height thresholds. Dataset heights are 2 (barricade/pipe),
// 3 (gantry/catwalk/generator), 5 (ruins/corner walls).
export const heightCategory = h => (h < 2 ? 'low' : h <= 4 ? 'medium' : 'tall');

const CATEGORY_RANK = { exposed: 0, light: 1, dense: 2 };

/** Per-area aggregate of the features parented to it in this layout. */
function areaContents(layout, tplById) {
  const contents = {};
  for (const p of layout.pieces ?? []) {
    if (p.piece_type !== 'feature' || !p.parent_area_id) continue;
    const t = tplById[p.template];
    if (!t) continue;
    const e = (contents[p.parent_area_id] ??= { category: 'exposed', maxHeight: 0 });
    const cat = t.terrain_category ?? 'exposed';
    if (CATEGORY_RANK[cat] > CATEGORY_RANK[e.category]) e.category = cat;
    e.maxHeight = Math.max(e.maxHeight, p.height_inches ?? t.default_height_inches ?? 0);
  }
  return contents;
}

/** category + height_inches for one raw piece (spec §6). */
function pieceGameplay(p, tplById, contents) {
  const t = p.template ? tplById[p.template] : null;
  if (p.piece_type === 'area') {
    const c = contents[p.id] ?? { category: 'exposed', maxHeight: 0 };
    return { category: c.category, heightInches: p.height_inches ?? c.maxHeight };
  }
  return {
    category: t?.terrain_category ?? 'exposed',
    heightInches: p.height_inches ?? t?.default_height_inches ?? 0,
  };
}

function pieceTraits(p, category) {
  const traits = [];
  if (category === 'dense') traits.push('obscuring');
  if (category === 'light' || p.piece_type === 'area') traits.push('difficult_ground');
  // Keyword overrides (none in the current dataset, honored if they appear).
  for (const kw of p.terrain_area_keywords ?? []) {
    if (kw === 'obscuring') {
      if (!traits.includes('obscuring')) traits.unshift('obscuring');
    } else {
      console.warn(`  WARN ${p.id}: terrain_area_keyword "${kw}" not implemented by the engine (spec §9.5) — dropped`);
    }
  }
  return traits;
}

export function convertLayout(layout, templates, tplById) {
  const resolved = resolveLayout(layout, templates);
  const pieces = layout.pieces ?? [];
  if (resolved.length !== pieces.length) {
    throw new Error(`${layout.id}: resolver emitted ${resolved.length} pieces for ${pieces.length} authored (composed template features would break the by-index join)`);
  }
  const ids = new Set(pieces.map(p => p.id));
  if (ids.size !== pieces.length) throw new Error(`${layout.id}: duplicate piece ids`);

  const contents = areaContents(layout, tplById);
  const outPieces = resolved.map((rp, i) => {
    const p = pieces[i];
    if (rp.id !== p.id) throw new Error(`${layout.id}[${i}]: resolver order mismatch (${rp.id} != ${p.id})`);
    const { category, heightInches } = pieceGameplay(p, tplById, contents);
    const piece = {
      id: p.id,
      type: 'ruins',
      piece_class: p.piece_type,
      polygon: rp.vertices.map(transpose),
      position: transpose(polygonCentroid(rp.vertices)),
      height: heightCategory(heightInches),
      height_inches: heightInches,
      category,
      rotation: 0,
      traits: pieceTraits(p, category),
      floor: rp.floor,
      walls: [],
    };
    if (p.parent_area_id) piece.parent_area_id = p.parent_area_id;
    if (p.is_objective || p.objective_role) piece.is_objective = true;
    if (p.objective_role) piece.objective_role = p.objective_role;
    if (p.link_group) piece.link_group = p.link_group;
    return piece;
  });

  const deployment = DEPLOYMENT_ID_MAP[layout.deployment_pattern_id];
  if (!deployment) throw new Error(`${layout.id}: unknown deployment pattern ${layout.deployment_pattern_id}`);

  return {
    id: gameLayoutId(layout.id),
    name: layout.name,
    description: `${layout.description ? layout.description + ' ' : ''}Official 11e GW terrain layout (${layout.mission_matchup_id}, variant ${layout.variant}) from the 40kdc dataset, transposed to the game's 44x60 portrait board.`,
    source: 'gw-11e',
    mission_matchup_id: layout.mission_matchup_id,
    variant: layout.variant,
    recommended_deployments: [deployment],
    objectives: layoutObjectives(layout.id, outPieces),
    pieces: outPieces,
  };
}

/** D3-a: the layout's five objective markers, derived from its objective
 *  pieces (see the header). Positions are game inches, matching the
 *  40k/deployment_zones/*.json objective schema. */
export function layoutObjectives(layoutId, outPieces) {
  const byRole = { home: [], expansion: [], center: [] };
  for (const p of outPieces) {
    if (p.is_objective) (byRole[p.objective_role] ??= []).push(p);
  }
  if (byRole.home.length !== 2 || byRole.expansion.length !== 2 || byRole.center.length !== 2) {
    throw new Error(`${layoutId}: expected 2 home / 2 expansion / 2 linked center objective pieces, got ` +
      `${byRole.home.length}/${byRole.expansion.length}/${byRole.center.length}`);
  }
  const byY = arr => [...arr].sort((a, b) => a.position[1] - b.position[1]);
  const [homeTop, homeBottom] = byY(byRole.home);
  const [nmlTop, nmlBottom] = byY(byRole.expansion);
  const [c1, c2] = byRole.center;
  const centre = [r4((c1.position[0] + c2.position[0]) / 2), r4((c1.position[1] + c2.position[1]) / 2)];
  const obj = (id, position, zone, sourcePieces) => ({ id, position, radius_mm: 40, zone, source_pieces: sourcePieces });
  return [
    // Game convention (see generate-deployment-zones.mjs): player 1 owns the
    // top of the portrait board (smaller y).
    obj('obj_home_1', homeTop.position, 'player1', [homeTop.id]),
    obj('obj_home_2', homeBottom.position, 'player2', [homeBottom.id]),
    obj('obj_nml_1', nmlTop.position, 'no_mans_land', [nmlTop.id]),
    obj('obj_nml_2', nmlBottom.position, 'no_mans_land', [nmlBottom.id]),
    obj('obj_center', centre, 'no_mans_land', [c1.id, c2.id]),
  ];
}

function main() {
  const layouts = loadCollection('terrainLayouts');
  const templates = loadCollection('terrainTemplates');
  const tplById = Object.fromEntries(templates.map(t => [t.id, t]));

  const index = [];
  for (const layout of layouts) {
    const out = convertLayout(layout, templates, tplById);
    writeFileSync(join(outDir, `${out.id}.json`), JSON.stringify(out, null, 1) + '\n');
    index.push({
      id: out.id,
      name: out.name,
      mission_matchup_id: out.mission_matchup_id,
      variant: out.variant,
      recommended_deployments: out.recommended_deployments,
      piece_count: out.pieces.length,
    });
    console.log(`WROTE ${out.id}.json — ${out.pieces.length} pieces (${out.recommended_deployments[0]})`);
  }

  index.sort((a, b) => a.id.localeCompare(b.id));
  writeFileSync(join(outDir, 'index_11e.json'), JSON.stringify({
    source: 'gw-11e',
    generated_by: 'scripts/40kdc/generate-terrain-layouts.mjs',
    description: 'Registry of the 45 converted official 11e terrain layouts. Read by TerrainManager._preload_layout_metadata.',
    layouts: index,
  }, null, 1) + '\n');
  console.log(`WROTE index_11e.json — ${index.length} layouts`);

  // Spec §8: the geometry gate runs in the generator's flow.
  const failures = verifyAll();
  if (failures > 0) process.exit(1);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
