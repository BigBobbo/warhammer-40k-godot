#!/usr/bin/env node
// Verify the 40kdc collections against the Wahapedia snapshot after
// wahapedia-import.mjs ran (PLAN W2). Written independently of the importer:
// it re-reads the raw snapshot CSVs with its own minimal parsing and checks
// the numbers a player sees.
//
//   node verify-wahapedia-import.mjs [--faction adeptus-custodes|orks]
//
// Checks, for every non-Legends datasheet in the snapshot:
//   - a units.json record of the faction with that name exists
//   - every model profile: M T Sv invuln W Ld OC
//   - every points tier (model count, cost, unit-count band)
//   - every weapon row: a weapon of the unit with that name has a profile
//     with the printed range / A / BS|WS / S / AP / D
//   - model_count min/max = the composition lines summed
//   - every leader pairing in the snapshot is in leaderAttachments
// and, in full mode (Custodes): detachment / enhancement / stratagem counts.
// Exits 1 on any mismatch.

import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { DATA_DIR, argValue, normName, looseName } from './lib.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SNAP = join(HERE, '..', '..', '.llm', 'codex_11e_wahapedia');
const FACTIONS = {
  'adeptus-custodes': { dir: 'custodes', full: true, detachments: 13, stratagems: 41, enhancements: 29 },
  'orks': { dir: 'orks', full: false },
};

// Independent pipe-CSV reader (quotes: "" escapes; quoted fields may hold |).
function csv(path) {
  let t = readFileSync(path, 'utf8');
  if (t.charCodeAt(0) === 0xfeff) t = t.slice(1);
  const recs = [];
  let row = [], f = '', q = false, start = true;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"' && t[i + 1] === '"') { f += '"'; i++; } else if (c === '"') q = false; else f += c; continue; }
    if (c === '"' && start) { q = true; start = false; continue; }
    if (c === '|') { row.push(f); f = ''; start = true; continue; }
    if (c === '\n') { row.push(f.replace(/\r$/, '')); recs.push(row); row = []; f = ''; start = true; continue; }
    f += c; start = false;
  }
  if (f || row.length) { row.push(f); recs.push(row); }
  const h = recs.shift();
  return recs.filter(r => r.length > 1).map(r => Object.fromEntries(h.map((k, i) => [k, r[i] ?? ''])));
}
const text = s => String(s ?? '').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim();
// printed value -> comparable string: 8" -> 8, 2+ -> 2, - -> null
const pv = v => {
  let s = text(v).replace(/["”″]/g, '').trim();
  if (/^\d+\+$/.test(s)) s = s.slice(0, -1);
  return s === '' || s === '-' ? null : s.toUpperCase().replace(/\s+/g, '');
};
const gv = v => (v === null || v === undefined ? null : String(v).toUpperCase());

function verify(factionId) {
  const cfg = FACTIONS[factionId];
  const dir = join(SNAP, cfg.dir, 'wahapedia');
  const R = n => csv(join(dir, `${n}.csv`));
  const sources = new Map(R('Source').map(s => [s.id, s.name]));
  const sheets = R('Datasheets').filter(d => !/Legends/i.test(sources.get(d.source_id) ?? ''));
  const by = (rows, k) => rows.reduce((m, r) => (m.get(r[k]) ?? m.set(r[k], []).get(r[k])).push(r) && m, new Map());
  const models = by(R('Datasheets_models'), 'datasheet_id');
  const costs = by(R('Datasheets_models_cost'), 'datasheet_id');
  const wargear = by(R('Datasheets_wargear'), 'datasheet_id');
  const comp = by(R('Datasheets_unit_composition'), 'datasheet_id');
  const leader = R('Datasheets_leader');

  const J = n => JSON.parse(readFileSync(join(DATA_DIR, `${n}.json`), 'utf8'));
  const units = J('units').filter(u => u.faction_id === factionId);
  const weapons = new Map();
  for (const w of J('weapons')) if (w.faction_id === factionId && !weapons.has(w.id)) weapons.set(w.id, w);
  const leaders = J('leaderAttachments');
  const errors = [];
  const err = (ds, m) => errors.push(`${factionId} / ${ds}: ${m}`);
  const unitByWaha = new Map();
  let checked = { profiles: 0, tiers: 0, weapons: 0 };

  for (const ds of sheets) {
    const u = units.find(x => normName(x.name) === normName(ds.name)) ?? units.find(x => looseName(x.name) === looseName(ds.name));
    if (!u) { err(ds.name, 'no units.json record'); continue; }
    unitByWaha.set(ds.id, u);
    // profiles
    for (const m of models.get(ds.id) ?? []) {
      const p = u.profiles.find(x => normName(x.name) === normName(text(m.name))) ?? (u.profiles.length === 1 ? u.profiles[0] : null);
      if (!p) { err(ds.name, `no profile "${text(m.name)}"`); continue; }
      const want = { M: pv(m.M), T: pv(m.T), Sv: pv(m.Sv), invuln_sv: pv(m.inv_sv), W: pv(m.W), Ld: pv(m.Ld), OC: pv(m.OC) ?? '0' };
      for (const [k, v] of Object.entries(want)) {
        if (k === 'M' && v === null) continue; // aircraft: printed "-"
        if (gv(p[k]) !== v) err(ds.name, `profile ${p.name}.${k}: data ${p[k]} vs printed ${v}`);
      }
      checked.profiles++;
    }
    // points
    const want = [];
    let band = [null, null], wg = false;
    for (const c of costs.get(ds.id) ?? []) {
      const d = text(c.description).toUpperCase();
      if (!c.cost.trim()) {
        wg = /WARGEAR/.test(d);
        const n = d.match(/(\d+)/g)?.map(Number) ?? [];
        band = /UNIT COSTS?$/.test(d) && /\+/.test(d) ? [n[0], null] : n.length === 2 ? [n[0], n[1]] : n.length === 1 ? [n[0], n[0]] : [null, null];
        continue;
      }
      if (wg) continue;
      const mm = d.match(/^(\d+)/);
      if (mm) want.push({ models: +mm[1], cost: +c.cost, band });
    }
    for (const t of want) {
      const hit = (u.points ?? []).find(x => x.models === t.models && x.cost === t.cost &&
        (t.band[0] == null || ((x.unit_count_min ?? 1) === t.band[0] && (x.unit_count_max ?? null) === t.band[1])));
      if (!hit) err(ds.name, `points tier ${t.models} models = ${t.cost} (copies ${t.band[0] ?? 'any'}-${t.band[1] ?? '+'}) missing; data has ${JSON.stringify(u.points)}`);
      checked.tiers++;
    }
    if ((u.points ?? []).length !== want.length) err(ds.name, `points: ${u.points?.length} tiers in data vs ${want.length} printed`);
    // weapons
    const unitWeapons = (u.weapon_ids ?? []).map(id => weapons.get(id)).filter(Boolean);
    for (const r of wargear.get(ds.id) ?? []) {
      const [base] = text(r.name).split(/\s+[-–]\s+/);
      const ws = unitWeapons.filter(w => looseName(w.name) === looseName(base));
      if (!ws.length) { err(ds.name, `weapon "${base}" not on unit (${u.weapon_ids})`); continue; }
      const melee = /melee/i.test(r.type);
      const ok = ws.some(w => w.profiles.some(p =>
        (melee ? p.range === 'Melee' : gv(p.range) === pv(r.range)) &&
        gv(p.stats.A) === pv(r.A) && gv(p.stats.S) === pv(r.S) && gv(p.stats.AP ?? 0) === (pv(r.AP) ?? '0') &&
        gv(p.stats.D) === pv(r.D) && gv(melee ? p.stats.WS : p.stats.BS) === pv(r.BS_WS)));
      if (!ok) err(ds.name, `weapon "${text(r.name)}" ${r.range} A${r.A} ${melee ? 'WS' : 'BS'}${r.BS_WS} S${r.S} AP${r.AP} D${r.D}: no matching profile in ${ws.map(w => w.id + JSON.stringify(w.profiles.map(p => [p.range, p.stats])))}`);
      checked.weapons++;
    }
    // model count
    let min = 0, max = 0;
    for (const c of comp.get(ds.id) ?? []) {
      for (const part of text(c.description).split(/\bOR\b/)) {
        const m = part.trim().match(/^(\d+)(?:\s*-\s*(\d+))?/);
        if (m) { min += +m[1]; max += +(m[2] ?? m[1]); }
      }
    }
    if (min && (u.model_count?.min !== min || u.model_count?.max !== max)) err(ds.name, `model_count ${JSON.stringify(u.model_count)} vs printed ${min}-${max}`);
  }
  // leader pairings
  let pairs = 0;
  for (const l of leader) {
    const a = unitByWaha.get(l.leader_id), b = unitByWaha.get(l.attached_id);
    if (!a || !b) continue;
    const la = leaders.find(x => x.leader_id === a.id);
    if (!la || !la.eligible_bodyguard_ids.includes(b.id)) err(a.name, `leader pairing -> ${b.name} missing`);
    pairs++;
  }
  if (cfg.full) {
    const dets = J('detachments').filter(d => d.faction_id === factionId && !d.superseded_by_codex);
    if (dets.length !== cfg.detachments) errors.push(`${factionId}: ${dets.length} codex detachments, expected ${cfg.detachments}`);
    const enh = new Set(dets.flatMap(d => d.enhancement_ids));
    if (enh.size !== cfg.enhancements) errors.push(`${factionId}: ${enh.size} enhancements, expected ${cfg.enhancements}`);
    const st = dets.flatMap(d => d.stratagem_ids);
    if (st.length !== cfg.stratagems) errors.push(`${factionId}: ${st.length} stratagems, expected ${cfg.stratagems}`);
  }
  console.log(`${factionId}: ${sheets.length} datasheets, ${checked.profiles} profiles, ${checked.tiers} points tiers, ${checked.weapons} weapon rows, ${pairs} leader pairings checked`);
  return errors;
}

const only = argValue('faction');
const errors = [];
for (const f of Object.keys(FACTIONS)) if (!only || only === f) errors.push(...verify(f));
if (errors.length) {
  console.log(`FAIL — ${errors.length} mismatch(es):`);
  for (const e of errors) console.log(`  ${e}`);
  process.exit(1);
}
console.log('PASS');
