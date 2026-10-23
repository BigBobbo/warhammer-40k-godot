#!/usr/bin/env node
// Generate server/public/js/lib/sm-codex-11e-data.mjs: the Codex: Space
// Marines (11e) POINTS / DETACHMENT / ENHANCEMENT / LEADER overlay the browser
// army builder applies on top of its vendored 40kdc bundle.
//
// Why: @alpaca-software/40kdc-data 1.4.5 (the newest release) carries the
// pre-codex "pre-launch-provisional" Space Marine data: index points (Logan
// Grimnar 100 instead of 150, no points at all for Captain on Bike), the index
// detachments (1st Company Task Force, Vanguard Spearhead, ... at their index
// DP) and none of the codex ones (Assault Brethren, Tactical Brethren, ...).
// A GW-app list built against the codex therefore imported with unresolved
// detachments, wrong points and illegal leader pairings (Logan Grimnar ->
// Terminator Assault Squad).
//
// Scope (builder only — the game's 40k/data/40kdc is untouched):
//   - units: points tiers, per-weapon wargear points, Support role, for every
//     40kdc Space Marine datasheet Wahapedia prints (non-Legends). 40kdc
//     datasheets the codex no longer prints are flagged superseded (hidden
//     from the picker, still resolvable for old lists — decision D1).
//   - leaderAttachments: the codex Leader lists.
//   - detachments: the 35 codex detachments (Boarding Actions skipped, D3) at
//     their codex DP / Force Disposition, owned by Space Marines + every
//     chapter (generic) or by their chapter only; the index detachments are
//     flagged superseded.
//   - enhancements: each codex detachment's list (cost, Upgrade tag, printed
//     rules text — the builder's bearer filter reads its first sentence — and
//     "LEADER: <unit>" grants). Existing 40kdc ids are kept by name.
//   NOT datasheet profiles / weapons / kits (the game has no SM codex import
//   yet; see the flags in the commit).
//
// Input: .llm/codex_11e_wahapedia/space-marines/wahapedia/*.csv (the SM rows
// of a Wahapedia 11e export, written by extract_snapshot.py <export> SM ...).
//
// Usage: node scripts/40kdc/gen_sm_codex_builder_patch.mjs [--check]
//   --check  exit 1 when the committed module is out of date (writes nothing).
// Deterministic: the same inputs give the same file.

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { parseCsv, stripHtml, slug, parsePoints, enhancementKey } from './wahapedia-import.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const REPO = join(here, '..', '..');
const SNAP = join(REPO, '.llm', 'codex_11e_wahapedia', 'space-marines', 'wahapedia');
const OUT = join(REPO, 'server', 'public', 'js', 'lib', 'sm-codex-11e-data.mjs');
const VENDOR = join(REPO, 'server', 'public', 'js', 'vendor', '40kdc-data.mjs');

const PARENT = 'adeptus-astartes';
const CODEX = 'Codex: Space Marines (11th edition)';

// The faction page groups the chapter detachments under their chapter
// (https://wahapedia.ru/wh40k11ed/factions/space-marines/, read 2026-10-22);
// the CSV export has no chapter column. Every other codex detachment is
// generic (Space Marines + every chapter).
const CHAPTER_DETACHMENTS = {
  'black-templars': ['Vow-sworn Crusaders', 'Marshal’s Household', 'Fist of the God-Emperor'],
  'blood-angels': ['Angelic Inheritors', 'Encarmine Speartip', 'Wrath of the Doomed'],
  'dark-angels': ['Wrath of the Rock', 'Inner Circle Task Force', 'Darkflight Pursuit'],
  'deathwatch': ['Black Spear Task Force', 'Deathwatch Support'],
  'iron-hands': ["Medusa's Wrath"],
  'imperial-fists': ['Ceramite Sentinels'],
  'raven-guard': ['Shadowmark Talon'],
  'salamanders': ['Forgefather’s Seekers'],
  'space-wolves': ['Saga of the Great Wolf', 'Champions of Fenris', 'Saga of the Beastslayer'],
  'ultramarines': ['Blade of Ultramar'],
  'white-scars': ['Spearpoint Task Force'],
};

// Codex datasheet name -> the 40kdc datasheet it reprices (renamed sheets).
const UNIT_ALIASES = {
  'marneus calgar': 'marneus-calgar-in-armour-of-antilochus',
  'invader atvs': 'invader-atv',
  'eradicator squad with melta rifles': 'eradicator-squad',
};

const key = s => String(s ?? '').toLowerCase().replace(/[’'`]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();

function read(name) {
  const p = join(SNAP, `${name}.csv`);
  return existsSync(p) ? parseCsv(readFileSync(p, 'utf8')) : [];
}

async function main() {
  const check = process.argv.includes('--check');
  const DC = await import(pathToFileURL(VENDOR).href);
  const R = DC.RAW_DATA;
  const lastUpdate = read('Last_update')[0]?.last_update ?? 'unknown';
  const SOURCE = `wahapedia-11e@${lastUpdate.slice(0, 10)}`;
  const family = [PARENT, ...R.factions.filter(f => f.parent_faction_id === PARENT).map(f => f.id)].sort();
  const report = [];

  // --- datasheets -----------------------------------------------------------
  const sources = new Map(read('Source').map(s => [s.id, s.name]));
  const allSheets = read('Datasheets').filter(d => !/Legends/i.test(sources.get(d.source_id) ?? '') && d.name !== 'Example Wargear');
  // A chapter prints its own variant of some generic datasheets under the same
  // name (Black Templars Gladiator Valiant 145 pts vs the Space Marines one at
  // 165): the 40kdc record is the generic datasheet, so the chapter variant
  // must not overwrite its points.
  const GENERIC_SOURCES = new Set(['Space Marines', 'Space Marines (Forge World)']);
  const genericNames = new Set(allSheets.filter(d => GENERIC_SOURCES.has(sources.get(d.source_id))).map(d => key(d.name)));
  const sheets = allSheets.filter(d => GENERIC_SOURCES.has(sources.get(d.source_id)) || !genericNames.has(key(d.name)));
  const legendNames = new Set(read('Datasheets').filter(d => /Legends/i.test(sources.get(d.source_id) ?? '')).map(d => key(d.name)));
  const costs = new Map();
  for (const r of read('Datasheets_models_cost')) {
    if (!costs.has(r.datasheet_id)) costs.set(r.datasheet_id, []);
    costs.get(r.datasheet_id).push(r);
  }
  const units = R.units.filter(u => u.faction_id === PARENT);
  const unitByKey = new Map(units.map(u => [key(u.name), u]));
  const unitIdByWaha = new Map();
  const unitPatches = [];
  for (const d of sheets) {
    const u = UNIT_ALIASES[key(d.name)] ? units.find(x => x.id === UNIT_ALIASES[key(d.name)]) : unitByKey.get(key(d.name));
    if (!u) { report.push(`unit ${d.name}: not in 40kdc — not added`); continue; }
    unitIdByWaha.set(d.id, u.id);
    const rows = (costs.get(d.id) ?? []).sort((a, b) => (parseInt(a.line, 10) || 0) - (parseInt(b.line, 10) || 0));
    const { points, wargear } = parsePoints(rows);
    const uniq = arr => [...new Map(arr.map(x => [JSON.stringify(x), x])).values()];
    const rec = { id: u.id, points: uniq(points) };
    const wp = uniq(wargear);
    if (wp.length) rec.wargear_points = wp;
    const role = /true/i.test(d.is_support) ? 'support' : (u.attachment_role === 'support' ? 'leader' : null);
    if (role) rec.attachment_role = role;
    if (!rec.points.length) { report.push(`unit ${d.name}: no points printed — skipped`); continue; }
    if (JSON.stringify(u.points) !== JSON.stringify(rec.points)) {
      report.push(`unit ${u.id}: points ${JSON.stringify(u.points)} -> ${JSON.stringify(rec.points)}`);
    }
    unitPatches.push(rec);
  }
  const printed = new Set(unitPatches.map(p => p.id));
  const supersededUnits = units
    .filter(u => !printed.has(u.id) && !u.is_legend && !legendNames.has(key(u.name)))
    .map(u => u.id).sort();
  for (const id of supersededUnits) report.push(`unit ${id}: not in the codex — superseded`);

  // --- leader pairings ------------------------------------------------------
  const leaders = new Map();
  for (const r of read('Datasheets_leader')) {
    const l = unitIdByWaha.get(r.leader_id);
    const b = unitIdByWaha.get(r.attached_id);
    if (!l || !b) continue;
    if (!leaders.has(l)) leaders.set(l, new Set());
    leaders.get(l).add(b);
  }
  const leaderAttachments = [...leaders].sort(([a], [b]) => a.localeCompare(b))
    .map(([leader_id, s]) => ({ leader_id, eligible_bodyguard_ids: [...s].sort() }));

  // --- detachments + enhancements -------------------------------------------
  const chapterOf = new Map();
  for (const [fid, names] of Object.entries(CHAPTER_DETACHMENTS)) for (const n of names) chapterOf.set(key(n), fid);
  const famDets = R.detachments.filter(d => family.includes(d.faction_id));
  const enhAll = R.enhancements ?? [];
  const wahaEnh = read('Enhancements');
  const dets = read('Detachments').filter(d => !/Boarding Actions/i.test(d.type));
  const detachments = [];
  const enhancements = new Map();
  const codexDetIds = new Set();
  for (const d of dets) {
    const name = stripHtml(d.name);
    const old = famDets.filter(x => key(x.name) === key(name));
    const id = old[0]?.id ?? slug(name);
    const owners = chapterOf.has(key(name)) ? [chapterOf.get(key(name))] : family;
    if (!chapterOf.has(key(name)) && old.length && old.length < family.length) {
      report.push(`detachment ${id}: 40kdc owners ${old.map(x => x.faction_id).join(',')} -> generic`);
    }
    codexDetIds.add(id);

    const oldEnh = enhAll.filter(e => e.detachment_id === id || old.some(o => (o.enhancement_ids ?? []).includes(e.id)));
    const enhIds = [];
    for (const e of wahaEnh.filter(x => x.detachment_id === d.id)) {
      const ename = stripHtml(e.name).trim();
      const prev = oldEnh.find(x => enhancementKey(x.name) === enhancementKey(ename));
      const eid = prev?.id ?? `${slug(ename)}-${id}`;
      const grants = [...String(e.support_leader ?? '').matchAll(/factions\/space-marines\/([^"#]+)"/g)]
        .map(m => unitByKey.get(key(m[1].replace(/-/g, ' '))))
        .filter(Boolean).map(u => u.id);
      const rec = {
        id: eid,
        name: ename,
        detachment_id: id,
        cost: parseInt(e.cost, 10) || 0,
        keyword_restrictions: prev?.keyword_restrictions ?? ['Adeptus Astartes'],
        ability_id: prev?.ability_id ?? null,
        is_unique: true,
        game_version: { edition: '11th', dataslate: 'codex' },
        points_provisional: false,
        upgrade_tag: /true/i.test(e.upgrade ?? ''),
        max_targets: 1,
        rules_text: stripHtml(e.description).replace(/\n•\s*/g, ' • ').replace(/\s+/g, ' ').trim(),
        source: SOURCE,
      };
      if (grants.length) rec.attachment_bodyguard_ids = [...new Set(grants)].sort();
      else if (prev?.attachment_bodyguard_ids) rec.attachment_bodyguard_ids = prev.attachment_bodyguard_ids;
      if (prev?.external_refs) rec.external_refs = prev.external_refs;
      if (!prev) report.push(`enhancement ${eid}: NEW`);
      else if (prev.cost !== rec.cost) report.push(`enhancement ${eid}: cost ${prev.cost} -> ${rec.cost}`);
      enhancements.set(eid, rec);
      enhIds.push(eid);
    }

    for (const fid of owners) {
      const prev = old.find(x => x.faction_id === fid) ?? old[0];
      const rec = {
        id,
        name,
        faction_id: fid,
        detachment_rule_id: prev?.detachment_rule_id ?? null,
        enhancement_ids: enhIds,
        stratagem_ids: prev?.stratagem_ids ?? [],
        game_version: { edition: '11th', dataslate: 'codex' },
        detachment_points: parseInt(d.dp, 10) || 1,
        force_dispositions: d.force_disposition ? [slug(d.force_disposition)] : [],
        source: SOURCE,
      };
      if (prev?.external_refs) rec.external_refs = prev.external_refs;
      detachments.push(rec);
    }
    const was = old[0];
    report.push(`detachment ${id}${was ? '' : ' (NEW)'}: ${parseInt(d.dp, 10) || 1} DP` +
      (was && was.detachment_points !== (parseInt(d.dp, 10) || 1) ? ` (was ${was.detachment_points})` : '') +
      `, ${d.force_disposition}, ${enhIds.length} enhancements, ${owners.length === family.length ? 'generic' : owners.join(',')}`);
  }
  // Index detachments the codex dropped, and generic ones that became
  // chapter-only (Ceramite Sentinels): flagged superseded on the factions that
  // no longer own them.
  const owned = new Set(detachments.map(d => `${d.faction_id}::${d.id}`));
  const supersededDets = [...new Set(famDets.filter(d => !owned.has(`${d.faction_id}::${d.id}`))
    .map(d => `${d.faction_id}::${d.id}`))].sort();
  report.push(`${supersededDets.length} faction detachment copies superseded`);

  const body = `// GENERATED by scripts/40kdc/gen_sm_codex_builder_patch.mjs — do not edit.
// Codex: Space Marines (11e) points / detachment / enhancement / leader
// overlay for the army builder, from the Wahapedia export of ${lastUpdate}.
// Applied by data-patches.mjs (applySmCodex). Attribution: Wahapedia
// (https://wahapedia.ru) transcribes Games Workshop's published rules.

export const SM_CODEX_SOURCE = ${JSON.stringify(SOURCE)};
export const SM_CODEX_NAME = ${JSON.stringify(CODEX)};
export const SM_CODEX_FACTIONS = ${JSON.stringify(family)};

// faction adeptus-astartes datasheets: {id, points, wargear_points?, attachment_role?}
export const SM_CODEX_UNIT_PATCHES = ${JSON.stringify(unitPatches, null, 0).replace(/},{"id"/g, '},\n  {"id"')};

export const SM_CODEX_SUPERSEDED_UNIT_IDS = ${JSON.stringify(supersededUnits)};

export const SM_CODEX_LEADER_ATTACHMENTS = ${JSON.stringify(leaderAttachments).replace(/},{/g, '},\n  {')};

export const SM_CODEX_DETACHMENTS = ${JSON.stringify(detachments).replace(/},{"id"/g, '},\n  {"id"')};

export const SM_CODEX_ENHANCEMENTS = ${JSON.stringify([...enhancements.values()]).replace(/},{"id"/g, '},\n  {"id"')};

// "<faction_id>::<detachment id>" copies the codex no longer gives that faction.
export const SM_CODEX_SUPERSEDED_DETACHMENTS = ${JSON.stringify(supersededDets).replace(/","/g, '",\n  "')};
`;
  if (check) {
    const cur = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
    if (cur !== body) { console.error(`${OUT} is out of date`); process.exit(1); }
    console.log('up to date');
    return;
  }
  writeFileSync(OUT, body);
  console.log(report.join('\n'));
  console.log(`\nwrote ${OUT}: ${unitPatches.length} units, ${leaderAttachments.length} leaders, ` +
    `${detachments.length} detachment records, ${enhancements.size} enhancements`);
}

main();
