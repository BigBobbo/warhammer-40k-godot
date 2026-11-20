#!/usr/bin/env node
// Combat Calc: points and weapon profiles from a newer 40kdc release, for the
// calculator only.
//
// The vendored browser bundle (server/public/js/vendor/40kdc-data.mjs) is shared
// with the Army Builder, and the builder's codex overlay is a diff against that
// bundle that mirrors the game's 40k/data/40kdc. Moving the bundle to a newer
// release is a job for the game's whole data pipeline (a newer release re-keys
// abilities, enhancements and stratagems and changes the loadout format).
//
// What CAN be taken from a newer release without any of that: facts that keep
// their key and their shape.
//   - unit points          (units keyed faction_id::id)
//   - weapon profiles      (weapons keyed faction_id::id: range, stats, keywords)
// for the factions this project has NO codex import for (those factions already
// carry newer codex datasheets; see CODEX_OVERLAY_FACTIONS).
//
// Output: server/public/calc/errata-data.mjs — the new value per key, with a
// hash of the bundle's value it replaces (the calculator applies an entry only
// while the record still holds that value). Applied by calc/adapter.mjs
// applyErrata(); the Army Builder and the game never load it.
//
// Usage:
//   npm pack @alpaca-software/40kdc-data@1.5.1 && tar -xzf alpaca-software-40kdc-data-1.5.1.tgz
//   node scripts/40kdc/gen_calc_errata.mjs <path to the unpacked "package" dir>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const pkgDir = process.argv[2] ? resolve(process.argv[2]) : null;
if (!pkgDir) { console.error('usage: gen_calc_errata.mjs <unpacked @alpaca-software/40kdc-data package dir>'); process.exit(2); }

const OLDMOD = await import(pathToFileURL(join(root, 'server/public/js/vendor/40kdc-data.mjs')).href);
const OLD = OLDMOD.RAW_DATA, BASE = OLDMOD.DATASET_VERSION;
const newMod = await import(pathToFileURL(join(pkgDir, 'dist/data/bundle.generated.js')).href);
const NEW = typeof newMod.RAW_DATA === 'string' ? JSON.parse(newMod.RAW_DATA) : newMod.RAW_DATA;
const FROM = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf8')).version;
const { CODEX_OVERLAY_FACTIONS } = await import(pathToFileURL(join(root, 'server/public/js/lib/codex-11e-datasheets.mjs')).href);
const SKIP = new Set(Object.keys(CODEX_OVERLAY_FACTIONS));

// same stable form and hash as calc/adapter.mjs (errataHash)
export const stable = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) : x));
export function hash(v) { const s = stable(v); let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); } return (h >>> 0).toString(36); }

const uKey = (r) => `${r.faction_id}::${r.id}`, wKey = (r) => `${r.faction_id ?? ''}::${r.id}`;
const oldUnits = new Map(OLD.units.map(r => [uKey(r), r])), oldWeapons = new Map(OLD.weapons.map(r => [wKey(r), r]));
const PROFILE_KEYS = ['name', 'range', 'stats', 'keywords', 'target_restrictions'];

const points = {}, weapons = {}, checked = {}, report = { points: [], weapons: [] };
for (const r of NEW.units) {
  if (!r.faction_id || SKIP.has(r.faction_id)) continue;
  const q = oldUnits.get(uKey(r));
  if (!q) continue;
  (checked[r.faction_id] ??= []).push(r.id);
  if (stable(q.points) !== stable(r.points)) {
    // only the fields the bundle's own records use (a newer release must not bring a new shape in)
    const okShape = (r.points ?? []).every(t => Object.keys(t).every(k => ['models', 'models_max', 'cost', 'unit_count_min', 'unit_count_max'].includes(k)));
    if (!okShape) { console.warn('skip points (new shape):', uKey(r), JSON.stringify(r.points).slice(0, 120)); continue; }
    points[uKey(r)] = { was: hash(q.points), now: r.points };
    report.points.push(`${uKey(r)}: ${stable(q.points)} -> ${stable(r.points)}`);
  }
}
for (const r of NEW.weapons) {
  if (!r.faction_id || SKIP.has(r.faction_id)) continue;
  const q = oldWeapons.get(wKey(r));
  if (!q || stable(q.profiles) === stable(r.profiles)) continue;
  // only shapes the bundle's own records have: known profile fields, a range in inches or "Melee"
  const okShape = (r.profiles ?? []).length > 0 && r.profiles.every(p => Object.keys(p).every(k => PROFILE_KEYS.includes(k)) && p.stats && typeof p.stats === 'object'
    && (p.range === 'Melee' || (typeof p.range === 'number' && Number.isFinite(p.range))));
  if (!okShape) { console.warn('skip weapon (new shape):', wKey(r), JSON.stringify(r.profiles).slice(0, 160)); continue; }
  weapons[wKey(r)] = { was: hash(q.profiles), now: r.profiles };
  report.weapons.push(`${wKey(r)}: ${stable(q.profiles)} -> ${stable(r.profiles)}`);
}
for (const k of Object.keys(checked)) checked[k].sort();

const slate = [...(NEW.gameVersions ?? [])].sort((a, b) => String(a.effective_date).localeCompare(String(b.effective_date))).pop();
const out = {
  base: BASE, from: FROM,
  dataslate: { id: slate.dataslate, date: slate.effective_date, label: slate.label },
  skipped: [...SKIP].sort(),
  checked: Object.fromEntries(Object.entries(checked).sort()),
  points: Object.fromEntries(Object.entries(points).sort()),
  weapons: Object.fromEntries(Object.entries(weapons).sort()),
};
const file = join(root, 'server/public/calc/errata-data.mjs');
writeFileSync(file, `// GENERATED by scripts/40kdc/gen_calc_errata.mjs from @alpaca-software/40kdc-data ${FROM}
// against the vendored bundle ${BASE}. Do not edit by hand: re-run the script.
//
// Unit points and weapon profiles that differ in ${FROM}, for the factions this
// project has no codex import for. "was" is a hash of the bundle's value: the
// calculator applies an entry only while the record still holds it.
// Data: CC BY 4.0, Alpaca Software and the 40kdc community contributors
// (https://github.com/wn-mitch/40kdc-data). Points and stat lines are numerical facts.
export const ERRATA = ${JSON.stringify(out)};
`);
console.log(`base ${BASE} -> ${FROM} (${slate.dataslate}: ${slate.label})`);
console.log(`factions refreshed: ${Object.keys(checked).length} (skipped: ${[...SKIP].join(', ')})`);
console.log(`units checked: ${Object.values(checked).reduce((a, v) => a + v.length, 0)} | points changed: ${Object.keys(points).length} | weapons changed: ${Object.keys(weapons).length}`);
console.log(`wrote ${file} (${(JSON.stringify(out).length / 1024).toFixed(0)} KB)`);
if (process.argv[3]) writeFileSync(process.argv[3], `POINTS\n${report.points.join('\n')}\n\nWEAPONS\n${report.weapons.join('\n')}\n`);
