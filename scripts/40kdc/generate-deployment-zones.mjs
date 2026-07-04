#!/usr/bin/env node
// Regenerate 40k/deployment_zones/*.json from the 40kdc deploymentPatterns
// collection (official geometry, carried into 11e unchanged).
//
// Coordinate transform: the dataset authors a landscape 60x44-inch board
// (y-down); the game uses portrait 44x60 (y-down, origin top-left). The
// mapping is a pure transpose: (x_game, y_game) = (y_dc, x_dc) — verified by
// the shared centre objective (30,22) -> (22,30).
//
// DeploymentZoneData loads these JSONs in preference to its hardcoded
// fallbacks, so this fixes e.g. Hammer and Anvil's 12"-deep zones (official
// depth is 18": 18 + 24 + 18 = 60).

import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { loadCollection } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', '40k', 'deployment_zones');

const patterns = loadCollection('deploymentPatterns');

const ID_MAP = {
  'hammer-and-anvil': 'hammer_anvil',
  'dawn-of-war': 'dawn_of_war',
  'search-and-destroy': 'search_and_destroy',
  'sweeping-engagement': 'sweeping_engagement',
  'crucible-of-battle': 'crucible_of_battle',
  'tipping-point': 'tipping_point',
};

const r2 = v => Math.round(v * 100) / 100;
const tp = (x, y) => ({ x: r2(y), y: r2(x) }); // transpose to portrait

function shapePoints(zone) {
  const pos = zone.position ?? { x: 0, y: 0 };
  const s = zone.shape;
  let pts;
  if (s.type === 'rectangle') {
    pts = [
      { x: 0, y: 0 }, { x: s.width, y: 0 },
      { x: s.width, y: s.height }, { x: 0, y: s.height },
    ];
  } else {
    pts = s.points;
  }
  return pts.map(p => tp(p.x + pos.x, p.y + pos.y));
}

function centroidY(poly) {
  return poly.reduce((a, p) => a + p.y, 0) / poly.length;
}

for (const pat of patterns) {
  const gameId = ID_MAP[pat.id];
  if (!gameId) { console.log(`skip unknown pattern ${pat.id}`); continue; }

  const zonesRaw = (pat.zones ?? []).map(z => ({ role: z.player, poly: shapePoints(z) }));
  // Game convention: player 1 owns the zone nearer the top (smaller y).
  zonesRaw.sort((a, b) => centroidY(a.poly) - centroidY(b.poly));
  const zones = zonesRaw.map((z, i) => ({ player: i + 1, poly: z.poly }));

  // Objectives: classify by containment — inside a deployment zone => that
  // player's home; nearest to board centre => centre; the rest are NML.
  function inPoly(pt, poly) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const xi = poly[i].x, yi = poly[i].y, xj = poly[j].x, yj = poly[j].y;
      if (((yi > pt.y) !== (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi)) inside = !inside;
    }
    return inside;
  }
  const objsT = (pat.objectives ?? []).map(o => tp(o.x, o.y));
  const centre = { x: 22, y: 30 };
  let centreIdx = 0, best = Infinity;
  objsT.forEach((o, i) => {
    const d = (o.x - centre.x) ** 2 + (o.y - centre.y) ** 2;
    if (d < best) { best = d; centreIdx = i; }
  });
  let homeN = 0, nmlN = 0;
  const objectives = objsT.map((o, i) => {
    let id, zoneTag;
    if (i === centreIdx) { id = 'obj_center'; zoneTag = 'no_mans_land'; }
    else if (zones[0] && inPoly(o, zones[0].poly)) { id = `obj_home_${++homeN}`; zoneTag = 'player1'; }
    else if (zones[1] && inPoly(o, zones[1].poly)) { id = `obj_home_${++homeN}`; zoneTag = 'player2'; }
    else { id = `obj_nml_${++nmlN}`; zoneTag = 'no_mans_land'; }
    return { id, position: [o.x, o.y], radius_mm: 40, zone: zoneTag };
  });

  const territories = (pat.territories ?? []).map(t => ({
    role: t.player, poly: shapePoints(t),
  }));
  territories.sort((a, b) => centroidY(a.poly) - centroidY(b.poly));

  const out = {
    id: gameId,
    name: pat.name,
    description: `${pat.name} — official geometry from the 40kdc 11e dataset (transposed to the game's 44x60 portrait board).`,
    zones,
    objectives,
    // 11e territories (deployment zone + its half up to the midline). Not yet
    // consumed by DeploymentZoneData; carried for the mission rules that
    // reference "your territory".
    territories: territories.map((t, i) => ({ player: i + 1, poly: t.poly })),
  };
  writeFileSync(join(outDir, `${gameId}.json`), JSON.stringify(out, null, 1) + '\n');
  console.log(`WROTE ${gameId}.json — ${zones.length} zones, ${objectives.length} objectives, ${territories.length} territories`);
}
