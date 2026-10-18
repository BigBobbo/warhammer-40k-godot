#!/usr/bin/env node
// Splice a faction's 11th-edition codex data from a Wahapedia export snapshot
// into the extracted 40kdc collections (40k/data/40kdc/*.json).
//
// Why: @alpaca-software/40kdc-data (1.4.5, the newest release) predates
// Codex: Adeptus Custodes (2026-10-17) and carries pre-codex / provisional
// statlines and points for Orks. Until 40kdc ships those codexes, Wahapedia is
// the source (plan: .llm/codex_11e_wahapedia/PLAN.md, track W). When a 40kdc
// release contains the codex, drop that faction from this step (PLAN W4).
//
// Pipeline position:
//   node extract.mjs && node local-patches.mjs \
//     && node wahapedia-import.mjs --faction adeptus-custodes \
//     && node wahapedia-import.mjs --faction orks
//   then generate-stratagems.mjs / generate-leader-pairings.mjs --only-faction,
//   and generate-armies.mjs for the faction's army files.
//
// Usage:
//   node wahapedia-import.mjs --faction <40kdc faction id> [--snapshot <dir>]
//        [--mode full|overlay] [--dry-run] [--report <file>]
//
//   --snapshot  directory holding the faction-filtered Wahapedia CSVs
//               (default .llm/codex_11e_wahapedia/<custodes|orks>/wahapedia,
//               written by .llm/codex_11e_wahapedia/extract_snapshot.py).
//   --mode      full    (default for adeptus-custodes): every codex datasheet's
//                       profiles, points, keywords, weapons, abilities, kit
//                       (composition + wargear options) and leader pairings
//                       come from Wahapedia.
//               overlay (default for orks): the 40kdc kits/ids/keyword
//                       encodings are kept (Codex: Orks kits were already
//                       ingested in 1.4.5 and the stratagem work depends on
//                       them); only NUMBERS are refreshed — profiles, points,
//                       weapon stats, model counts — plus weapon profiles 40kdc
//                       lacks, and each codex detachment's enhancement list
//                       (overlayEnhancements: ids kept, points / bearer /
//                       Upgrade tag corrected, rules_text added, pre-codex
//                       records marked superseded). Every change is listed in
//                       the report.
//
// Rules for both modes:
//   - Legends datasheets and Boarding Actions detachments are skipped
//     (owner decisions D2/D3).
//   - Records keep their 40kdc ids wherever the datasheet/weapon/ability keeps
//     its name; new ones get ids in the same slug scheme (weapon ids that need
//     a per-datasheet copy are `<weapon>-<unit>`, which UnitLoadoutResolver's
//     unit-suffix stripping already understands).
//   - Records this step writes carry `source: "wahapedia-11e@<export date>"`.
//   - Datasheets 40kdc has and Wahapedia does not (renamed / Legends) are left
//     untouched, so pre-codex rosters and saves keep resolving (decision D1).
//   - Idempotent: running it twice gives the same files.
//
// Attribution: Wahapedia (https://wahapedia.ru) transcribes Games Workshop's
// published rules; see 40k/data/40kdc/ATTRIBUTION.md.

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { dirname, join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { DATA_DIR, argValue, normName, looseName, buildCanonEntries } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const REPO = join(here, '..', '..');

const FACTIONS = {
  'adeptus-custodes': { waha: 'AC', dir: 'custodes', mode: 'full', keyword: 'Adeptus Custodes' },
  'orks': { waha: 'ORK', dir: 'orks', mode: 'overlay', keyword: 'Orks' },
};

// Wahapedia source ids that are NOT codex datasheets (decision D2: ignore).
const LEGENDS_SOURCE_RE = /Legends/i;
// Boarding Actions detachments (decision D3: out of scope).
const BOARDING_ACTIONS_DETACHMENTS = new Set([
  'voyagers in darkness', 'black ship guardians', 'ramship raiders', 'kaptin killers',
]);

// ---------------------------------------------------------------------------
// CSV + text helpers

/** Pipe-delimited CSV with RFC4180 quoting ("" escapes, quoted newlines). */
export function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  let atFieldStart = true;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else field += c;
      continue;
    }
    if (c === '"' && atFieldStart) { quoted = true; atFieldStart = false; continue; }
    if (c === '|') { row.push(field); field = ''; atFieldStart = true; continue; }
    if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = ''; atFieldStart = true;
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
      continue;
    }
    field += c;
    atFieldStart = false;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const header = rows.shift().map(h => h.trim());
  return rows.map(r => {
    const o = {};
    header.forEach((h, i) => { if (h) o[h] = r[i] ?? ''; });
    return o;
  });
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”', ndash: '–', mdash: '—', hellip: '…' };
export function stripHtml(s) {
  return String(s ?? '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|li|div)>/gi, '\n')
    .replace(/<li[^>]*>/gi, '• ')
    .replace(/<[^>]+>/g, '')
    .replace(/&(#\d+|#x[0-9a-f]+|[a-z]+);/gi, (m, e) => {
      if (e[0] === '#') return String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
      return ENTITIES[e.toLowerCase()] ?? m;
    })
    .replace(/[ \t]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{2,}/g, '\n')
    .trim();
}

/** 40kdc-style id slug: "Crushin’ Bulk" -> "crushin-bulk". */
export function slug(s) {
  return String(s)
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[’'`]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** Title-case a Wahapedia ALL-CAPS keyword run ("LETHAL HITS" -> "Lethal Hits"). */
function titleCase(s) {
  return String(s).toLowerCase().replace(/(^|[\s/-])([a-z])/g, (m, p, c) => p + c.toUpperCase());
}

/** "8\"" -> 8, "2+" -> 2, "-" -> null, "D6+2" -> "D6+2", "12" -> 12. */
export function num(v) {
  let s = String(v ?? '').replace(/["”″]/g, '').trim();
  if (/^\d+\+$/.test(s)) s = s.slice(0, -1); // "2+" (Sv/Ld/BS) -> "2"; dice keep their "+"
  if (s === '' || s === '-' || s === '–') return null;
  if (/^-?\d+$/.test(s)) return parseInt(s, 10);
  return s.toUpperCase().replace(/\s+/g, '');
}

// ---------------------------------------------------------------------------
// Weapon keyword parsing -> 40kdc encodings (see weapons.json).

const SIMPLE_KEYWORDS = {
  'assault': 'assault', 'heavy': 'heavy', 'pistol': 'pistol', 'torrent': 'torrent',
  'twin-linked': 'twin-linked', 'lance': 'lance', 'hazardous': 'hazardous',
  'precision': 'precision', 'ignores cover': 'ignores-cover', 'indirect fire': 'indirect-fire',
  'one shot': 'one-shot', 'psychic': 'psychic', 'extra attacks': 'extra-attacks',
  'close-quarters': 'close-quarters', 'devastating wounds': 'devastating-wounds',
  'lethal hits': 'lethal-hits',
};

function targetScope(scope) {
  // "non-MONSTER/VEHICLE" -> {excluded_target_keywords:[...]}, "INFANTRY" -> {required_target_keywords_any:[...]}
  if (!scope) return {};
  let s = scope.trim();
  const excluded = /^non-/i.test(s);
  if (excluded) s = s.replace(/^non-/i, '');
  const kws = s.split('/').map(k => titleCase(k.trim())).filter(Boolean);
  return excluded ? { excluded_target_keywords: kws } : { required_target_keywords_any: kws };
}

/** "ASSAULT, Rapid Fire 2, Anti-MONSTER/VEHICLE 4+" -> [{keyword_id, parameters?}] */
export function parseWeaponKeywords(desc, unknown = []) {
  const out = [];
  const text = stripHtml(desc);
  if (!text) return out;
  for (let raw of text.split(',')) {
    raw = raw.trim();
    if (!raw) continue;
    const [head, scope] = raw.split(/:\s*/, 2);
    const h = head.trim().toLowerCase();
    let m;
    if (SIMPLE_KEYWORDS[h]) {
      const kw = { keyword_id: SIMPLE_KEYWORDS[h] };
      const params = targetScope(scope);
      if (Object.keys(params).length) kw.parameters = params;
      out.push(kw);
    } else if ((m = h.match(/^rapid fire (\S+)$/))) {
      out.push({ keyword_id: 'rapid-fire', parameters: { value: num(m[1]) } });
    } else if ((m = h.match(/^sustained hits (\S+)$/))) {
      out.push({ keyword_id: 'sustained-hits', parameters: { value: num(m[1]), ...targetScope(scope) } });
    } else if ((m = h.match(/^melta (\S+)$/))) {
      out.push({ keyword_id: 'melta', parameters: { value: num(m[1]) } });
    } else if ((m = h.match(/^cleave (\S+)$/))) {
      out.push({ keyword_id: 'cleave', parameters: { value: num(m[1]) } });
    } else if ((m = h.match(/^blast(?: (\S+))?$/))) {
      out.push(m[1] ? { keyword_id: 'blast', parameters: { value: num(m[1]) } } : { keyword_id: 'blast' });
    } else if ((m = h.match(/^anti-(.+?) (\d)\+$/))) {
      const targets = m[1].split('/').map(k => titleCase(k.trim()));
      const thr = parseInt(m[2], 10);
      if (targets.length === 1) out.push({ keyword_id: 'anti', parameters: { target_keyword: targets[0], threshold: thr } });
      else for (const t of targets) out.push({ keyword_id: 'anti', parameters: { target_keyword: t, threshold: thr, required_target_keywords_any: [t] } });
    } else {
      // Faction-specific weapon rules (BUBBLECHUKKA, DEAD CHOPPY, ...): keep as
      // a bare keyword id; the game shows it as a string-only special rule.
      const id = slug(head);
      unknown.push(raw);
      out.push(scope ? { keyword_id: id, parameters: targetScope(scope) } : { keyword_id: id });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Snapshot loading

function loadSnapshot(dir) {
  const read = name => {
    const p = join(dir, `${name}.csv`);
    return existsSync(p) ? parseCsv(readFileSync(p, 'utf8')) : [];
  };
  return {
    lastUpdate: read('Last_update')[0]?.last_update ?? 'unknown',
    datasheets: read('Datasheets'),
    models: read('Datasheets_models'),
    costs: read('Datasheets_models_cost'),
    wargear: read('Datasheets_wargear'),
    composition: read('Datasheets_unit_composition'),
    options: read('Datasheets_options'),
    keywords: read('Datasheets_keywords'),
    dsAbilities: read('Datasheets_abilities'),
    abilities: read('Abilities'),
    leader: read('Datasheets_leader'),
    detachments: read('Detachments'),
    detachmentAbilities: read('Detachment_abilities'),
    enhancements: read('Enhancements'),
    stratagems: read('Stratagems'),
    sources: read('Source'),
  };
}

const groupBy = (rows, key) => {
  const m = new Map();
  for (const r of rows) {
    const k = r[key];
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(r);
  }
  for (const v of m.values()) v.sort((a, b) => (parseInt(a.line, 10) || 0) - (parseInt(b.line, 10) || 0));
  return m;
};

// ---------------------------------------------------------------------------
// Datasheet parsing

/** Datasheets_models_cost rows -> 40kdc points tiers + wargear costs. */
export function parsePoints(rows) {
  const points = [];
  const wargear = [];
  let band = { min: null, max: null };
  let inWargear = false;
  const ord = s => parseInt(String(s).replace(/\D/g, ''), 10);
  for (const r of rows) {
    const d = stripHtml(r.description).toUpperCase();
    if (!String(r.cost).trim()) {
      inWargear = /WARGEAR/.test(d);
      let m;
      if ((m = d.match(/YOUR (\d+)\w* TO (\d+)\w* UNITS? COSTS?/))) band = { min: ord(m[1]), max: ord(m[2]) };
      else if ((m = d.match(/YOUR (\d+)\w*\+ UNITS? COSTS?/))) band = { min: ord(m[1]), max: null };
      else if ((m = d.match(/YOUR (\d+)\w* UNITS? COSTS?/))) band = { min: ord(m[1]), max: ord(m[1]) };
      else if (/YOUR UNIT COSTS?/.test(d)) band = { min: null, max: null };
      continue;
    }
    const cost = parseInt(r.cost, 10);
    if (inWargear) {
      const name = stripHtml(r.description).replace(/^per\s+/i, '').trim();
      wargear.push({ name, cost });
      continue;
    }
    const mm = d.match(/^(\d+)(?:\s*-\s*(\d+))?\s+MODELS?/);
    if (!mm) continue;
    const t = { models: parseInt(mm[1], 10) };
    if (mm[2]) t.models_max = parseInt(mm[2], 10);
    t.cost = cost;
    if (band.min != null) { t.unit_count_min = band.min; t.unit_count_max = band.max; }
    points.push(t);
  }
  return { points, wargear };
}

/** "40mm" / "75 x 42mm" / "Use model" -> 40kdc base_size_mm (null = keep existing). */
export function parseBase(s) {
  const t = String(s ?? '').toLowerCase().replace(/\s+/g, '');
  let m;
  if ((m = t.match(/^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)mm/))) {
    const a = parseFloat(m[1]), b = parseFloat(m[2]);
    return { shape: 'oval', width: Math.max(a, b), length: Math.min(a, b) };
  }
  if ((m = t.match(/^(\d+(?:\.\d+)?)mm/))) return { shape: 'round', diameter: parseFloat(m[1]) };
  return null;
}

/** Datasheets_unit_composition rows -> [{name, min, max}] */
export function parseComposition(rows) {
  const out = [];
  for (const r of rows) {
    for (const part of stripHtml(r.description).split(/\n|\bOR\b/)) {
      const m = part.trim().match(/^(\d+)(?:\s*-\s*(\d+))?\s+(.+?)(?:\s+models?)?\.?$/i);
      if (!m) continue;
      out.push({ name: m[3].trim(), min: parseInt(m[1], 10), max: parseInt(m[2] ?? m[1], 10) });
    }
  }
  return out;
}

/** Loadout text -> Map(modelName|'*' -> [weapon names]). */
export function parseLoadout(text) {
  const out = new Map();
  const t = stripHtml(text);
  const re = /(This model|Every model|Every ([^:]+?)|The ([^:]+?)) (?:is|are) equipped with:\s*([^]*?)(?=(?:This model|Every|The [^.:]+ (?:is|are) equipped with:)|$)/gi;
  let m;
  while ((m = re.exec(t))) {
    const who = (m[2] || m[3] || '*').trim();
    const items = m[4].replace(/\.\s*$/, '').split(/;/).map(x => x.trim().replace(/\.$/, '')).filter(Boolean)
      .map(x => x.replace(/^\d+\s+/, ''));
    out.set(who === '*' ? '*' : who, items);
  }
  return out;
}

// ---------------------------------------------------------------------------

function main() {
  const factionId = argValue('faction');
  if (!FACTIONS[factionId]) {
    console.error(`usage: node wahapedia-import.mjs --faction ${Object.keys(FACTIONS).join('|')} [--snapshot dir] [--mode full|overlay] [--dry-run] [--report file]`);
    process.exit(2);
  }
  const cfg = FACTIONS[factionId];
  const mode = argValue('mode') || cfg.mode;
  const snapDir = resolve(argValue('snapshot') || join(REPO, '.llm', 'codex_11e_wahapedia', cfg.dir, 'wahapedia'));
  const dryRun = process.argv.includes('--dry-run');
  const reportPath = argValue('report');
  const snap = loadSnapshot(snapDir);
  const SOURCE = `wahapedia-11e@${snap.lastUpdate.split(' ')[0]}`;
  const report = [];
  const log = s => { report.push(s); };

  const load = name => JSON.parse(readFileSync(join(DATA_DIR, `${name}.json`), 'utf8'));
  const data = {
    units: load('units'),
    weapons: load('weapons'),
    abilities: load('abilities'),
    unitCompositions: load('unitCompositions'),
    wargearOptions: load('wargearOptions'),
    leaderAttachments: load('leaderAttachments'),
    enhancements: load('enhancements'),
    detachments: load('detachments'),
    factions: load('factions'),
  };

  // --- Wahapedia datasheets in scope (codex + Forge World; no Legends)
  const sourceName = new Map(snap.sources.map(s => [s.id, s.name]));
  const sheets = snap.datasheets.filter(d => !LEGENDS_SOURCE_RE.test(sourceName.get(d.source_id) ?? ''));
  const legendsSkipped = snap.datasheets.filter(d => LEGENDS_SOURCE_RE.test(sourceName.get(d.source_id) ?? ''));
  log(`# wahapedia-import ${factionId} (${mode}) — snapshot ${snap.lastUpdate}`);
  log(`datasheets: ${sheets.length} in scope, ${legendsSkipped.length} Legends skipped (${legendsSkipped.map(d => d.name).join(', ')})`);

  const byDs = {
    models: groupBy(snap.models, 'datasheet_id'),
    costs: groupBy(snap.costs, 'datasheet_id'),
    wargear: groupBy(snap.wargear, 'datasheet_id'),
    composition: groupBy(snap.composition, 'datasheet_id'),
    options: groupBy(snap.options, 'datasheet_id'),
    keywords: groupBy(snap.keywords, 'datasheet_id'),
    abilities: groupBy(snap.dsAbilities, 'datasheet_id'),
  };
  const wahaAbility = new Map(snap.abilities.map(a => [a.id, a]));

  // --- existing 40kdc units of the faction, by name
  const existingUnits = data.units.filter(u => u.faction_id === factionId);
  const existingByName = new Map(existingUnits.map(u => [normName(u.name), u]));
  const existingByLoose = new Map(existingUnits.map(u => [looseName(u.name), u]));

  // Weapons / abilities authored for the faction (hinted copies win).
  const factionWeapons = new Map();
  for (const w of data.weapons) if (w.faction_id === factionId && !factionWeapons.has(w.id)) factionWeapons.set(w.id, w);
  const factionAbilities = new Map();
  for (const a of data.abilities) if (a.faction_id === factionId && !factionAbilities.has(a.ability_id)) factionAbilities.set(a.ability_id, a);
  const abilityById = new Map();
  for (const a of data.abilities) if (!abilityById.has(a.ability_id)) abilityById.set(a.ability_id, a);

  const factionRecord = data.factions.find(f => f.id === factionId);
  const armyRuleIds = Array.isArray(factionRecord?.faction_rule_ids) ? factionRecord.faction_rule_ids
    : (factionRecord?.faction_rule_id ? [factionRecord.faction_rule_id] : []);
  const touchedUnitIds = new Set();
  const newWeapons = new Map();   // id -> record
  const newAbilities = new Map(); // ability_id -> record
  const newComps = new Map();     // unit_id -> record
  const newOptions = new Map();   // unit_id -> [records]
  const leaderPairs = new Map();  // leader unit id -> Set(bodyguard ids)
  const unknownKeywords = new Set();
  const unitIdByWahaId = new Map();

  // ------------------------------------------------------------------ units
  for (const ds of sheets) {
    const existing = existingByName.get(normName(ds.name)) ?? existingByLoose.get(looseName(ds.name)) ?? null;
    const unitId = existing?.id ?? slug(ds.name);
    unitIdByWahaId.set(ds.id, unitId);
  }

  for (const ds of sheets) {
    const unitId = unitIdByWahaId.get(ds.id);
    const existing = existingUnits.find(u => u.id === unitId) ?? null;
    const changes = [];
    const models = byDs.models.get(ds.id) ?? [];
    const comp = parseComposition(byDs.composition.get(ds.id) ?? []);
    const { points, wargear: wargearCosts } = parsePoints(byDs.costs.get(ds.id) ?? []);
    const kwRows = byDs.keywords.get(ds.id) ?? [];

    // profiles
    const profiles = models.map(m => {
      const p = {
        name: stripHtml(m.name),
        M: num(m.M), T: num(m.T), W: num(m.W), Sv: num(m.Sv),
        invuln_sv: num(m.inv_sv), Ld: num(m.Ld), OC: num(m.OC) ?? 0,
      };
      const old = existing?.profiles?.find(x => normName(x.name) === normName(p.name)) ?? existing?.profiles?.[0];
      // Aircraft print "-" for M: keep the dataset's movement value (the game
      // needs a number; 40kdc uses 20).
      if (p.M == null) p.M = old?.M ?? 20;
      if (p.invuln_sv == null) delete p.invuln_sv;
      if (m.inv_sv_descr) p.invuln_note = stripHtml(m.inv_sv_descr);
      return p;
    });

    // keywords
    const keywords = [];
    const factionKeywords = [];
    for (const k of kwRows) {
      const kw = stripHtml(k.keyword);
      if (!kw) continue;
      if (k.is_faction_keyword === 'true') { if (!factionKeywords.includes(kw)) factionKeywords.push(kw); }
      else if (!keywords.some(x => normName(x) === normName(kw))) keywords.push(kw);
    }
    // Wahapedia's keyword export omits a datasheet's own name keyword ("the
    // list does not include named keywords that match the datasheet's name"),
    // but every datasheet carries it and leader pairing matches can_lead
    // names against bodyguard keywords (FormationsPhase / CharacterAttachmentManager).
    if (!keywords.some(x => normName(x) === normName(ds.name))) keywords.push(stripHtml(ds.name));

    // weapons: group Wahapedia rows into weapons with profiles.
    const wRows = byDs.wargear.get(ds.id) ?? [];
    const weaponGroups = new Map(); // base name key -> {name, profiles: []}
    for (const r of wRows) {
      const full = stripHtml(r.name);
      const [base, profName] = full.split(/\s+[-–]\s+/, 2);
      const key = normName(base);
      if (!weaponGroups.has(key)) weaponGroups.set(key, { name: base.trim(), rows: [] });
      weaponGroups.get(key).rows.push({ r, profName: profName?.trim() ?? null });
    }
    const weaponIds = [];
    const weaponRenames = new Map(); // shared 40kdc id -> this unit's own copy
    const weaponIdByName = new Map();
    for (const [key, g] of weaponGroups) {
      const profilesOut = g.rows.map(({ r, profName }) => {
        const melee = /melee/i.test(r.type) || /melee/i.test(r.range);
        const stats = { A: num(r.A), S: num(r.S), AP: num(r.AP) ?? 0, D: num(r.D) };
        const skill = num(r.BS_WS);
        if (melee) stats.WS = skill; else stats.BS = skill;
        const prof = {
          name: profName ?? (g.rows.length > 1 ? (melee ? 'Melee' : 'Ranged') : g.name),
          range: melee ? 'Melee' : num(r.range),
          stats,
          keywords: [],
        };
        const unk = [];
        prof.keywords = parseWeaponKeywords(r.description, unk);
        unk.forEach(u => unknownKeywords.add(u));
        if (/^hunter$/i.test(prof.name)) {
          // 11e "Hunter" profiles: only MONSTER/VEHICLE targets (40kdc encoding).
          prof.keywords.push({ keyword_id: 'hunter', parameters: { target_keyword: 'Monster' } },
            { keyword_id: 'hunter', parameters: { target_keyword: 'Vehicle' } });
          prof.target_restrictions = { required_keywords_any: ['Monster', 'Vehicle'] };
        }
        return prof;
      });
      // id: reuse the existing unit's weapon id for this name, else a faction
      // weapon with the same name and identical stats, else a new id.
      const existingIds = existing?.weapon_ids ?? [];
      let wid = existingIds.find(id => {
        const w = factionWeapons.get(id) ?? newWeapons.get(id);
        return w && looseName(w.name) === looseName(g.name);
      }) ?? null;
      const record = {
        id: null,
        name: g.name,
        type: profilesOut.every(p => p.range === 'Melee') ? 'melee' : 'ranged',
        profiles: profilesOut,
        game_version: { edition: '11th', dataslate: 'codex' },
        faction_id: factionId,
        source: SOURCE,
      };
      if (!wid) {
        const generic = slug(g.name);
        if (!newWeapons.has(generic) || sameWeapon(newWeapons.get(generic), record)) wid = generic;
        else wid = `${generic}-${unitId}`;
      } else if (newWeapons.has(wid) && !sameWeapon(newWeapons.get(wid), record)) {
        // two codex datasheets share a 40kdc id but print different stats:
        // this one gets its own per-unit copy (the id is swapped in place on
        // the unit, its composition and its options — see weaponRenames).
        const own = `${slug(g.name)}-${unitId}`;
        weaponRenames.set(wid, own);
        changes.push(`weapon ${wid}: shared with another datasheet but printed differently here -> own copy ${own}`);
        wid = own;
      }
      record.id = wid;
      if (mode === 'overlay' && factionWeapons.has(wid) && !newWeapons.has(wid)) {
        // keep the 40kdc record's structure (profile names, keyword encodings);
        // refresh numbers profile-by-profile where profile counts line up.
        const old = factionWeapons.get(wid);
        const merged = structuredClone(old);
        if (old.profiles.length === record.profiles.length) {
          old.profiles.forEach((op, i) => {
            const np = record.profiles[i];
            if (canon(op.stats) !== canon(np.stats) || String(op.range) !== String(np.range)) {
              changes.push(`weapon ${wid}/${op.name}: ${JSON.stringify([op.range, op.stats])} -> ${JSON.stringify([np.range, np.stats])}`);
            }
            merged.profiles[i].stats = np.stats;
            merged.profiles[i].range = np.range;
            const kwKey = p => JSON.stringify((p.keywords ?? []).map(k => k.keyword_id).sort());
            if (kwKey(op) !== kwKey(np)) {
              changes.push(`weapon ${wid}/${op.name}: keywords ${kwKey(op)} -> ${kwKey(np)}`);
              merged.profiles[i].keywords = np.keywords;
            }
          });
        } else {
          changes.push(`weapon ${wid}: profiles ${old.profiles.map(p => p.name).join('/')} -> ${record.profiles.map(p => p.name).join('/')} (Wahapedia shape taken)`);
          merged.profiles = record.profiles;
        }
        merged.source = SOURCE;
        newWeapons.set(wid, merged);
      } else if (!newWeapons.has(wid)) {
        if (factionWeapons.has(wid)) {
          const old = factionWeapons.get(wid);
          if (!sameWeapon(old, record)) changes.push(`weapon ${wid}: stats changed`);
          // keep provenance fields the game never reads, drop the rest
          if (old.external_refs) record.external_refs = old.external_refs;
        } else changes.push(`weapon ${wid}: NEW`);
        newWeapons.set(wid, record);
      }
      weaponIdByName.set(key, wid);
      if (!weaponIds.includes(wid)) weaponIds.push(wid);
    }

    // abilities
    const abilityIds = [];
    const wargearAbilityIds = new Map(); // normName(wargear name) -> ability id
    // An ability already in the data with this (parenthetical-free) name:
    // the unit's own first, then any of the faction's.
    const findAbility = (name, types = null) => {
      const ok = a => a && normName(stripQualifier(a.name).name) === normName(name) &&
        (!types || types.includes(a.ability_type));
      for (const id of existing?.ability_ids ?? []) {
        const a = newAbilities.get(id) ?? factionAbilities.get(id) ?? abilityById.get(id);
        if (ok(a)) return id;
      }
      for (const [id, a] of newAbilities) if (a.faction_id === factionId && ok(a)) return id;
      for (const [id, a] of factionAbilities) if (ok(a)) return id;
      return null;
    };
    for (const r of byDs.abilities.get(ds.id) ?? []) {
      let aid = null;
      if (r.ability_id) {
        // core / faction ability by reference
        const wa = wahaAbility.get(r.ability_id);
        const name = stripHtml(wa?.name ?? '');
        const param = stripHtml(r.parameter);
        const isFaction = !!wa?.faction_id;
        if (isFaction) {
          // The army rule (factions.json faction_rule_ids) is added to every
          // unit by the army converter — refresh its text, don't list it twice.
          const ruleId = armyRuleIds.find(id => normName((abilityById.get(id) ?? {}).name ?? '') === normName(name));
          if (ruleId) {
            if (!newAbilities.has(ruleId)) {
              const prev = structuredClone(abilityById.get(ruleId));
              prev.rules_text = stripHtml(wa.description);
              prev.source = SOURCE;
              newAbilities.set(ruleId, prev);
            }
            continue;
          }
        }
        aid = isFaction
          ? (findAbility(name, ['faction']) ??
             [...abilityById.values()].find(a => a.ability_type === 'faction' && !a.faction_id && normName(a.name) === normName(name))?.ability_id ??
             slug(name))
          : coreAbilityId(name, param);
        if (!abilityById.has(aid) && !newAbilities.has(aid)) {
          newAbilities.set(aid, {
            ability_id: aid,
            name: coreAbilityName(name, param),
            authored_by: 'wahapedia',
            game_version: { edition: '11th', dataslate: 'codex' },
            ability_type: isFaction ? 'faction' : 'core',
            rules_text: stripHtml(wa?.description ?? ''),
            ...(isFaction ? { faction_id: factionId } : {}),
            source: SOURCE,
          });
          changes.push(`ability ${aid}: NEW (${isFaction ? 'faction' : 'core'})`);
        } else if (isFaction && !newAbilities.has(aid)) {
          // faction ability text from the codex (e.g. the Martial Ka'tah rework)
          const prev = structuredClone(factionAbilities.get(aid) ?? abilityById.get(aid));
          prev.rules_text = stripHtml(wa.description);
          prev.source = SOURCE;
          newAbilities.set(aid, prev);
        }
      } else {
        const { name, qualifier } = stripQualifier(stripHtml(r.name));
        const type = /wargear/i.test(r.type) ? 'wargear' : 'unit';
        const text = stripHtml(r.description);
        aid = findAbility(name) ?? slug(name);
        const prev = newAbilities.get(aid);
        if (prev && prev.source === SOURCE && prev.rules_text !== text) {
          // same name, different text on another codex datasheet: own copy
          aid = `${slug(name)}-${unitId}`;
        }
        const base = newAbilities.get(aid) ??
          (factionAbilities.get(aid) ? structuredClone(factionAbilities.get(aid)) : null);
        const rec = base ?? {
          ability_id: aid, name, authored_by: 'wahapedia',
          game_version: { edition: '11th', dataslate: 'codex' }, ability_type: type, faction_id: factionId,
        };
        if (!base) changes.push(`ability ${aid}: NEW "${name}"`);
        else if (normName(stripQualifier(base.name).name) !== normName(name)) changes.push(`ability ${aid}: renamed "${base.name}" -> "${name}"`);
        rec.name = name;
        rec.rules_text = text;
        if (qualifier) {
          rec.usage = qualifier;
          if (/aura/i.test(qualifier)) rec.is_aura = true;
        } else delete rec.usage;
        rec.ability_type = type;
        rec.faction_id = factionId;
        rec.unit_ids = [...new Set([...(rec.unit_ids ?? []), unitId])];
        rec.source = SOURCE;
        newAbilities.set(aid, rec);
        if (type === 'wargear') wargearAbilityIds.set(normName(name), aid);
      }
      if (aid && !abilityIds.includes(aid)) abilityIds.push(aid);
    }

    // composition + default kit
    const loadout = parseLoadout(ds.loadout);
    const resolveWeapon = n => {
      const k = normName(n);
      if (weaponIdByName.has(k)) return weaponIdByName.get(k);
      for (const [kk, id] of weaponIdByName) if (looseName(kk) === looseName(n)) return id;
      // non-weapon wargear (Praesidium Shield, Vexilla): the wargear ability id,
      // as 40kdc's options/compositions reference it
      if (wargearAbilityIds.has(k)) return wargearAbilityIds.get(k);
      for (const [kk, id] of wargearAbilityIds) if (looseName(kk) === looseName(n)) return id;
      return null;
    };
    const compModels = comp.length ? comp : [{ name: profiles[0]?.name ?? ds.name, min: 1, max: 1 }];
    const compRec = {
      unit_id: unitId,
      faction_id: factionId,
      models: compModels.map(cm => {
        const prof = profiles.find(p => looseName(p.name) === looseName(cm.name)) ??
          profiles.find(p => looseName(cm.name).includes(looseName(p.name))) ?? profiles[0];
        const modelRow = models.find(m => prof && normName(stripHtml(m.name)) === normName(prof.name)) ?? models[0];
        const base = parseBase(modelRow?.base_size) ?? existing?.base_size_mm ?? null;
        const items = loadout.get(cm.name) ?? loadout.get(cm.name.replace(/s$/, '')) ??
          [...loadout.entries()].find(([k]) => k !== '*' && looseName(k) === looseName(cm.name))?.[1] ?? loadout.get('*') ?? [];
        // weapons only: UnitLoadoutResolver matches default_weapon_ids against
        // the unit's weapon menu; wargear (Praesidium Shield) is listed apart
        const weaponOnly = n => { const id = resolveWeapon(n); return id && [...weaponIdByName.values()].includes(id) ? id : null; };
        const defaults = items.map(weaponOnly).filter(Boolean);
        const out = { name: cm.name, min: cm.min, max: cm.max, is_leader_model: false };
        if (prof && normName(prof.name) !== normName(cm.name)) out.profile_name = prof.name;
        if (base) out.base_size_mm = base;
        out.default_weapon_ids = [...new Set(defaults)];
        out.default_wargear = items.filter(i => !weaponOnly(i));
        return out;
      }),
      game_version: { edition: '11th', dataslate: 'codex' },
      source: SOURCE,
    };
    const minModels = compRec.models.reduce((s, m) => s + m.min, 0);
    const maxModels = compRec.models.reduce((s, m) => s + m.max, 0);

    // wargear options (structured where the sentence is one of the codex
    // patterns; the printed text is always kept)
    const opts = (byDs.options.get(ds.id) ?? []).map((r, i) => parseOption(r, i, unitId, factionId, resolveWeapon, SOURCE));
    for (const o of opts) for (const n of o._unresolved ?? []) changes.push(`option ${o.id}: unresolved item "${n}"`);
    opts.forEach(o => delete o._unresolved);

    // base size: unit default = first composition model's base
    const unitBase = compRec.models.find(m => m.base_size_mm)?.base_size_mm ?? existing?.base_size_mm ?? null;

    // transport
    const transportText = stripHtml(ds.transport);
    let transport = existing?.transport_capacity ?? null;
    const tm = transportText.match(/transport capacity of (\d+)/i);
    if (tm) {
      transport = { ...(existing?.transport_capacity ?? {}), capacity: parseInt(tm[1], 10), rules_text: transportText };
      const ex = transportText.match(/cannot transport ([^.]+?) models/i);
      if (ex) transport.exclusion_keywords = ex[1].split(/\/|,| or /).map(s => titleCase(s.trim())).filter(Boolean);
      else delete transport.exclusion_keywords;
      // "Each Mega Armour/Jump Pack model takes up the space of 2 models."
      const mults = [];
      for (const mm of transportText.matchAll(/Each ([^.]+?) models? takes? up the space of (\d+) models/gi)) {
        for (const k of mm[1].split(/\/|,| or /).map(s => titleCase(s.trim())).filter(Boolean)) {
          mults.push({ keyword: k, spaces: parseInt(mm[2], 10) });
        }
      }
      if (mults.length) transport.multipliers = mults; else delete transport.multipliers;
    } else if (!transportText) transport = null;

    const roleText = ds.role.toLowerCase();
    const role = /epic hero/.test(roleText) ? 'epic-hero' : /character/.test(roleText) ? 'character'
      : /battleline/.test(roleText) ? 'battleline' : /dedicated transport/.test(roleText) ? 'dedicated-transport' : null;

    // ---- assemble unit record
    const base = existing ? structuredClone(existing) : {
      id: unitId, name: ds.name, faction_id: factionId,
    };
    const unit = base;
    if (mode === 'full' || !existing) {
      unit.name = ds.name;
      if (role) unit.role = role; else delete unit.role;
      unit.profiles = profiles;
      unit.points = points;
      unit.keywords = keywords;
      unit.faction_keywords = factionKeywords;
      if (unitBase) unit.base_size_mm = unitBase;
      unit.model_count = { min: minModels, max: maxModels };
      unit.weapon_ids = weaponIds;
      unit.ability_ids = abilityIds;
      if (transport) unit.transport_capacity = transport; else delete unit.transport_capacity;
      if (wargearCosts.length) unit.wargear_points = wargearCosts;
      unit.is_legend = false;
      unit.points_provisional = false;
      unit.game_version = { edition: '11th', dataslate: 'codex' };
      newComps.set(unitId, compRec);
      newOptions.set(unitId, opts);
      if (!existing) changes.push('NEW datasheet');
      else {
        if (JSON.stringify(existing.profiles) !== JSON.stringify(profiles)) changes.push(`profiles: ${fmtProfiles(existing.profiles)} -> ${fmtProfiles(profiles)}`);
        if (JSON.stringify(existing.points) !== JSON.stringify(points)) changes.push(`points: ${fmtPoints(existing.points)} -> ${fmtPoints(points)}`);
        const ow = new Set(existing.weapon_ids ?? []), nw = new Set(weaponIds);
        const lost = [...ow].filter(x => !nw.has(x)), gained = [...nw].filter(x => !ow.has(x));
        if (lost.length || gained.length) changes.push(`weapon_ids: -[${lost}] +[${gained}]`);
        const oa = new Set(existing.ability_ids ?? []), na = new Set(abilityIds);
        const la = [...oa].filter(x => !na.has(x)), ga = [...na].filter(x => !oa.has(x));
        if (la.length || ga.length) changes.push(`ability_ids: -[${la}] +[${ga}]`);
      }
    } else {
      // overlay: numbers only
      const before = JSON.stringify([existing.profiles, existing.points, existing.model_count]);
      unit.profiles = (existing.profiles ?? []).map(op => {
        const np = profiles.find(p => normName(p.name) === normName(op.name)) ??
          (existing.profiles.length === 1 && profiles.length === 1 ? profiles[0] : null);
        if (!np) { changes.push(`profile "${op.name}" has no Wahapedia match — kept`); return op; }
        const merged = { ...op, M: np.M, T: np.T, W: np.W, Sv: np.Sv, Ld: np.Ld, OC: np.OC };
        if (np.invuln_sv != null) merged.invuln_sv = np.invuln_sv; else delete merged.invuln_sv;
        return merged;
      });
      for (const np of profiles) {
        if (!unit.profiles.some(p => normName(p.name) === normName(np.name)) && !(existing.profiles.length === 1 && profiles.length === 1)) {
          unit.profiles.push(np);
          changes.push(`profile "${np.name}" added`);
        }
      }
      unit.points = points.length ? points : existing.points;
      unit.model_count = { min: minModels, max: maxModels };
      if (wargearCosts.length) unit.wargear_points = wargearCosts;
      // the printed transport rule (capacity, exclusions, space multipliers)
      if (transport) {
        if (JSON.stringify(existing.transport_capacity ?? null) !== JSON.stringify(transport)) {
          changes.push(`transport: ${JSON.stringify(existing.transport_capacity ?? null)} -> ${JSON.stringify(transport)}`);
        }
        unit.transport_capacity = transport;
      }
      // weapons Wahapedia lists that the 40kdc record does not reference
      if (weaponRenames.size) {
        unit.weapon_ids = (existing.weapon_ids ?? []).map(w => weaponRenames.get(w) ?? w);
        const swap = ids => (ids ?? []).map(w => weaponRenames.get(w) ?? w);
        for (const c of data.unitCompositions) {
          if (c.faction_id !== factionId || c.unit_id !== unitId) continue;
          for (const m of c.models ?? []) m.default_weapon_ids = swap(m.default_weapon_ids);
        }
        for (const o of data.wargearOptions) {
          if (o.faction_id !== factionId || o.unit_id !== unitId) continue;
          if (o.replaces) o.replaces = swap(o.replaces);
          if (o.replacement) o.replacement = swap(o.replacement);
          if (o.replacement_choice) o.replacement_choice = o.replacement_choice.map(swap);
        }
      }
      const missing = weaponIds.filter(w => !(unit.weapon_ids ?? existing.weapon_ids ?? []).includes(w));
      if (missing.length) {
        changes.push(`weapon_ids: +[${missing}] (Wahapedia lists them; 40kdc did not)`);
        unit.weapon_ids = [...(unit.weapon_ids ?? existing.weapon_ids ?? []), ...missing];
      }
      const extra = (unit.weapon_ids ?? []).filter(w => !weaponIds.includes(w));
      if (extra.length) changes.push(`weapon_ids kept though not on Wahapedia datasheet: [${extra}]`);
      // Abilities: the codex datasheet's list is authoritative in both modes
      // (40kdc 1.4.5 carries pre-codex and misspelled Ork ability names);
      // ids are reused wherever the name matches.
      const oa = new Set(existing.ability_ids ?? []), na = new Set(abilityIds);
      const la = [...oa].filter(x => !na.has(x)), ga = [...na].filter(x => !oa.has(x));
      if (la.length || ga.length) changes.push(`ability_ids: -[${la}] +[${ga}]`);
      unit.ability_ids = abilityIds;
      if (JSON.stringify([unit.profiles, unit.points, unit.model_count]) !== before) {
        if (JSON.stringify(existing.profiles) !== JSON.stringify(unit.profiles)) changes.push(`profiles: ${fmtProfiles(existing.profiles)} -> ${fmtProfiles(unit.profiles)}`);
        if (JSON.stringify(existing.points) !== JSON.stringify(unit.points)) changes.push(`points: ${fmtPoints(existing.points)} -> ${fmtPoints(unit.points)}`);
        if (JSON.stringify(existing.model_count) !== JSON.stringify(unit.model_count)) changes.push(`model_count: ${JSON.stringify(existing.model_count)} -> ${JSON.stringify(unit.model_count)}`);
      }
      // kit check: compare default weapons with the 40kdc composition
      const oldComp = data.unitCompositions.find(c => c.faction_id === factionId && c.unit_id === unitId);
      const kit = c => JSON.stringify((c?.models ?? []).map(m => [looseName(m.name), m.min, m.max, [...(m.default_weapon_ids ?? [])].sort()]));
      if (oldComp && kit(oldComp) !== kit(compRec)) changes.push(`kit differs (kept 40kdc): ${kit(oldComp)} vs Wahapedia ${kit(compRec)}`);
      else if (!oldComp) { newComps.set(unitId, compRec); newOptions.set(unitId, opts); changes.push('composition: NEW (40kdc had none)'); }
    }
    unit.source = SOURCE;
    touchedUnitIds.add(unitId);
    replaceOrInsert(data.units, u => u.faction_id === factionId && u.id === unitId,
      u => u.faction_id === factionId, unit);
    if (changes.length) {
      log(`\n## ${ds.name} [${unitId}]${existing ? '' : ' (NEW)'}`);
      changes.forEach(c => log(`- ${c}`));
    }
  }

  // ------------------------------------------------------- leader pairings
  for (const r of snap.leader) {
    const lid = unitIdByWahaId.get(r.leader_id);
    const bid = unitIdByWahaId.get(r.attached_id);
    if (!lid || !bid) continue;
    if (!leaderPairs.has(lid)) leaderPairs.set(lid, new Set());
    leaderPairs.get(lid).add(bid);
  }
  for (const [lid, bodyguards] of leaderPairs) {
    const u = data.units.find(x => x.faction_id === factionId && x.id === lid);
    if (u && !u.attachment_role) u.attachment_role = 'leader';
    const prev = data.leaderAttachments.find(la => la.leader_id === lid);
    const next = [...bodyguards].sort();
    if (prev) {
      // leaderAttachments carries no faction id; keep bodyguards of other
      // factions that share the leader id (none today) and replace ours.
      // Bodyguards that are not codex datasheets (pre-codex / Legends units
      // left in the data, decision D1) keep their pairing so old rosters
      // still attach; codex bodyguards come from Wahapedia.
      const keep = prev.eligible_bodyguard_ids.filter(b => !touchedUnitIds.has(b));
      const merged = [...new Set([...keep, ...next])].sort();
      if (JSON.stringify(prev.eligible_bodyguard_ids.slice().sort()) !== JSON.stringify(merged)) {
        log(`- leader ${lid}: ${prev.eligible_bodyguard_ids.join(', ')} -> ${merged.join(', ')}`);
      }
      prev.eligible_bodyguard_ids = merged;
      prev.source = SOURCE;
    } else {
      data.leaderAttachments.push({ leader_id: lid, eligible_bodyguard_ids: next, game_version: { edition: '11th', dataslate: 'codex' }, source: SOURCE });
      log(`- leader ${lid}: NEW -> ${next.join(', ')}`);
    }
  }
  if (mode === 'full') {
    // codex leaders that Wahapedia lists without a Leader row lose stale pairings
    for (const la of data.leaderAttachments) {
      if (touchedUnitIds.has(la.leader_id) && !leaderPairs.has(la.leader_id) &&
          existingUnits.some(e => e.id === la.leader_id)) {
        const kept = la.eligible_bodyguard_ids.filter(b => !touchedUnitIds.has(b));
        if (kept.length !== la.eligible_bodyguard_ids.length) {
          log(`- leader ${la.leader_id}: no Wahapedia pairing — codex bodyguards cleared (${la.eligible_bodyguard_ids.join(', ')} -> ${kept.join(', ')})`);
        }
        la.eligible_bodyguard_ids = kept;
      }
    }
  }

  // --------------------------------------------- detachments + enhancements
  if (mode === 'full') importDetachments(snap, data, factionId, SOURCE, unitIdByWahaId, log);
  // overlay: the 40kdc detachments stay; only their enhancement lists are
  // refreshed from the codex (WP-O5) — ids kept, points / restrictions /
  // Upgrade tag corrected, rules_text added, stale records retired.
  if (mode === 'overlay') overlayEnhancements(snap, data, factionId, SOURCE, log);

  // ------------------------------------------------- write collections back
  // Write back: a record that came from an existing one replaces THAT object
  // in place (identity, so shared ids of other factions are never touched);
  // a brand-new record goes right after the faction's block.
  const writeBack = (arr, map, originOf) => {
    const byOrigin = new Map();
    for (const [id, rec] of map) { const o = originOf(id); if (o) byOrigin.set(o, rec); }
    const out = arr.map(r => byOrigin.get(r) ?? r);
    const placed = new Set(byOrigin.values());
    const fresh = [...map.values()].filter(r => !placed.has(r));
    const last = lastIndex(out, r => r.faction_id === factionId);
    out.splice(last >= 0 ? last + 1 : out.length, 0, ...fresh);
    return out;
  };
  data.weapons = writeBack(data.weapons, newWeapons, id => factionWeapons.get(id) ?? null);
  data.abilities = writeBack(data.abilities, newAbilities,
    id => factionAbilities.get(id) ?? (newAbilities.get(id)?.faction_id ? null : abilityById.get(id)) ?? null);
  for (const [uid, comp] of newComps) {
    replaceOrInsert(data.unitCompositions, c => c.faction_id === factionId && c.unit_id === uid,
      c => c.faction_id === factionId, comp);
  }
  for (const [uid, opts] of newOptions) {
    // a unit's option block replaces its old block at the old position
    const first = data.wargearOptions.findIndex(o => o.faction_id === factionId && o.unit_id === uid);
    const rest = data.wargearOptions.filter(o => !(o.faction_id === factionId && o.unit_id === uid));
    let at = first >= 0 ? first : lastIndex(rest, o => o.faction_id === factionId) + 1;
    if (at <= 0) at = rest.length;
    rest.splice(Math.min(at, rest.length), 0, ...opts);
    data.wargearOptions = rest;
  }

  // army rules on the faction record
  const fac = data.factions.find(f => f.id === factionId);
  if (fac) fac.source_codex = SOURCE;

  // Ability names the game dispatches on (UnitAbilityManager /
  // FactionAbilityManager / ArmyListManager tables) that no codex datasheet of
  // this faction carries any more — each needs re-keying or retiring (PLAN C7/O6).
  {
    const canon = new Map(buildCanonEntries());
    const nameOf = id => (newAbilities.get(id) ?? factionAbilities.get(id) ?? abilityById.get(id))?.name ?? id;
    const before = new Set(), after = new Set();
    for (const u of existingUnits) if (touchedUnitIds.has(u.id)) for (const id of u.ability_ids ?? []) before.add(normName(nameOf(id)));
    for (const u of data.units) if (u.faction_id === factionId && touchedUnitIds.has(u.id)) for (const id of u.ability_ids ?? []) after.add(normName(nameOf(id)));
    const dropped = [...before].filter(n => !after.has(n) && canon.has(n)).map(n => canon.get(n)).sort();
    const added = [...after].filter(n => !before.has(n)).sort();
    log(`\ngame-dispatched ability names dropped from ${factionId} codex datasheets (${dropped.length}): ${dropped.join('; ') || 'none'}`);
    log(`ability names new on ${factionId} codex datasheets (${added.length}): ${added.join('; ') || 'none'}`);
  }
  log(`\nunknown weapon keywords (kept as bare ids): ${[...unknownKeywords].join('; ') || 'none'}`);
  log(`summary: ${touchedUnitIds.size} datasheets, ${newWeapons.size} weapons, ${newAbilities.size} abilities, ${newComps.size} compositions, ${[...newOptions.values()].flat().length} wargear options written`);

  if (reportPath) writeFileSync(reportPath, report.join('\n') + '\n');
  else console.log(report.join('\n'));
  if (dryRun) { console.log('(dry run — nothing written)'); return; }
  const save = (name, records) => writeFileSync(join(DATA_DIR, `${name}.json`), JSON.stringify(records, null, 1) + '\n');
  for (const [name, recs] of Object.entries(data)) save(name, recs);
  console.log(`wahapedia-import ${factionId}: wrote ${Object.keys(data).length} collections (${SOURCE})`);
}

// Replace the first record matching `isTarget` in place (dropping later
// duplicates); otherwise insert after the last record matching `inBlock`
// (the faction's block), or append. Keeps collection order stable so a
// re-import diffs minimally.
function replaceOrInsert(arr, isTarget, inBlock, rec) {
  const i = arr.findIndex(isTarget);
  if (i >= 0) {
    arr[i] = rec;
    for (let j = arr.length - 1; j > i; j--) if (isTarget(arr[j])) arr.splice(j, 1);
    return;
  }
  const last = lastIndex(arr, inBlock);
  if (last >= 0) arr.splice(last + 1, 0, rec);
  else arr.push(rec);
}

function lastIndex(arr, pred) {
  for (let i = arr.length - 1; i >= 0; i--) if (pred(arr[i])) return i;
  return -1;
}

// Order-insensitive JSON for stat blocks.
function canon(o) {
  if (Array.isArray(o)) return `[${o.map(canon).join(',')}]`;
  if (o && typeof o === 'object') return `{${Object.keys(o).sort().map(k => `${JSON.stringify(k)}:${canon(o[k])}`).join(',')}}`;
  return JSON.stringify(o ?? null);
}

// Same printed weapon: profile count, ranges, stats and keyword ids match.
function sameWeapon(a, b) {
  const key = w => canon((w.profiles ?? []).map(p => [String(p.range), p.stats,
    (p.keywords ?? []).map(k => k.keyword_id).sort()]));
  return key(a) === key(b);
}

function fmtProfiles(ps) {
  return (ps ?? []).map(p => `${p.name} M${p.M} T${p.T} Sv${p.Sv}${p.invuln_sv ? '/' + p.invuln_sv : ''} W${p.W} Ld${p.Ld} OC${p.OC}`).join('; ');
}
function fmtPoints(ps) {
  return (ps ?? []).map(t => `${t.models}${t.models_max ? '-' + t.models_max : ''}m=${t.cost}${t.unit_count_min ? `[#${t.unit_count_min}-${t.unit_count_max ?? '+'}]` : ''}`).join(' ');
}

// "Vengeful Surge (Once per battle, per unit)" -> {name, qualifier}
export function stripQualifier(full) {
  const m = String(full).match(/^(.*?)\s*\(([^()]*)\)\s*$/);
  return m && m[1].trim() ? { name: m[1].trim(), qualifier: m[2].trim() } : { name: String(full).trim(), qualifier: null };
}

// Display name the game's engine parses for parameterised core abilities.
export function coreAbilityName(name, param) {
  const n = normName(name);
  const p = String(param ?? '').trim();
  if (n === 'damaged') return `Damaged: 1-${p.replace(/\D/g, '')} Wounds Remaining`;
  return p ? `${name} ${p}` : name;
}

// Wahapedia core-ability row -> 40kdc ability id. null = not a game ability
// id (Damaged N is carried by the profile's damaged bracket, not an ability).
export function coreAbilityId(name, param) {
  const n = normName(name);
  const p = String(param ?? '').replace(/["”″+]/g, '').trim().toLowerCase();
  switch (n) {
    case 'deep strike': return 'deep-strike';
    case 'leader': return 'leader';
    case 'deadly demise': return `deadly-demise-${p}`;
    case 'feel no pain': return `feel-no-pain-${p}`;
    case 'firing deck': return `firing-deck-${p}`;
    case 'scouts': return `scouts-${p}`;
    case 'hover': return 'hover';
    case 'infiltrators': return 'infiltrators';
    case 'lone operative': return 'lone-operative';
    case 'stealth': return 'stealth';
    case 'support': return 'support';
    case 'super heavy walker': return 'super-heavy-walker';
    case 'damaged': return `damaged-${p}`;
    case 'fights first': return 'fights-first';
    default: return slug(p ? `${name} ${p}` : name);
  }
}

// One Datasheets_options row -> a 40kdc-shaped wargearOptions record.
export function parseOption(r, i, unitId, factionId, resolveWeapon, SOURCE) {
  const text = stripHtml(r.description).replace(/\n•\s*/g, ' • ').replace(/\s+/g, ' ').trim();
  const rec = {
    id: `${unitId}-wgo-wh-${i + 1}`,
    unit_id: unitId,
    faction_id: factionId,
    game_version: { edition: '11th', dataslate: 'codex' },
    is_free: true,
    rules_text: text,
    source: SOURCE,
  };
  const unresolved = [];
  const ids = list => list.map(n => n.replace(/^\d+\s+/, '').trim()).filter(Boolean).map(n => {
    const id = resolveWeapon(n);
    if (!id) unresolved.push(n);
    return id ?? `wargear:${slug(n)}`;
  });
  const splitItems = s => s.split(/\s+and\s+|,\s*/i).map(x => x.trim().replace(/\.$/, '')).filter(Boolean);
  let m;
  // model constraint
  if ((m = text.match(/^Any number of (?:([^:]+?) )?models? can each/i))) rec.model_constraint = { any_number: true, ...(m[1] ? { model_name: m[1] } : {}) };
  else if ((m = text.match(/^For every (\d+) models in this unit, (\d+) (?:([^:]+?) )?models? can/i))) rec.model_constraint = { per_n_models: parseInt(m[1], 10), max: parseInt(m[2], 10), ...(m[3] ? { model_name: m[3] } : {}) };
  else if ((m = text.match(/^Up to (\d+) (?:([^:]+?) )?models? can/i))) rec.model_constraint = { max: parseInt(m[1], 10), ...(m[2] ? { model_name: m[2] } : {}) };
  else if ((m = text.match(/^(\d+) (?:([^:]+?) )?models? can/i))) rec.model_constraint = { max: parseInt(m[1], 10), ...(m[2] ? { model_name: m[2] } : {}) };
  else if (/^(This model|The [^’']+?['’]s?)/i.test(text)) rec.model_constraint = { max: 1 };
  // swap / add
  if ((m = text.match(/(?:their|its|This model’s|This model's|[’']s?)\s*(.+?) (?:can be )?replaced with (?:one of the following:)?\s*(.+)$/i))) {
    const replaces = splitItems(m[1].replace(/^(their|its)\s+/i, ''));
    const rhs = m[2].trim();
    rec.replaces = ids(replaces);
    if (/•/.test(rhs) || /one of the following/i.test(text)) {
      rec.replacement_choice = rhs.split('•').map(s => s.trim()).filter(Boolean).map(s => ids(splitItems(s)));
    } else rec.replacement = ids(splitItems(rhs));
  } else if ((m = text.match(/can be equipped with (?:(?:up to )?(\d+) )?(?:one of the following:)?\s*(.+)$/i))) {
    rec.replaces = [];
    const rhs = m[2].trim();
    if (/•/.test(rhs)) rec.replacement_choice = rhs.split('•').map(s => s.trim()).filter(Boolean).map(s => ids(splitItems(s)));
    else rec.replacement = ids(splitItems(rhs.replace(/^\d+\s+/, '')));
    if (m[1]) rec.max_count = parseInt(m[1], 10);
  }
  rec._unresolved = unresolved.filter(n => !/^(one of the following|following)$/i.test(n));
  return rec;
}

// Detachments, detachment rules, enhancements (full mode).
function importDetachments(snap, data, factionId, SOURCE, unitIdByWahaId, log) {
  const dets = snap.detachments.filter(d => !BOARDING_ACTIONS_DETACHMENTS.has(normName(d.name)));
  const oldDets = data.detachments.filter(d => d.faction_id === factionId);
  const keep = [];
  const written = [];
  for (const d of dets) {
    const did = slug(d.name);
    const old = oldDets.find(x => normName(x.name) === normName(d.name));
    const rule = snap.detachmentAbilities.find(a => a.detachment_id === d.id);
    const enh = snap.enhancements.filter(e => e.detachment_id === d.id);
    const strats = snap.stratagems.filter(s => s.detachment_id === d.id);
    const ruleId = rule ? `${slug(rule.name)}-${did}` : null;
    if (rule) {
      replaceOrInsert(data.abilities, a => a.ability_id === ruleId && a.faction_id === factionId,
        a => a.faction_id === factionId, {
        ability_id: ruleId, name: stripHtml(rule.name), authored_by: 'wahapedia',
        game_version: { edition: '11th', dataslate: 'codex' }, ability_type: 'detachment',
        rules_text: stripHtml(rule.description), faction_id: factionId, detachment_id: did, source: SOURCE,
      });
    }
    const enhIds = [];
    for (const e of enh) {
      const eid = `${slug(e.name)}-${did}`;
      enhIds.push(eid);
      replaceOrInsert(data.enhancements, x => x.id === eid,
        x => typeof x.detachment_id === 'string' && oldDets.some(d => d.id === x.detachment_id), {
        id: eid, name: stripHtml(e.name), detachment_id: did, cost: parseInt(e.cost, 10) || 0,
        keyword_restrictions: [], ability_id: eid, is_unique: true,
        game_version: { edition: '11th', dataslate: 'codex' }, points_provisional: false,
        upgrade_tag: /true/i.test(e.upgrade ?? ''), max_targets: 1,
        rules_text: stripHtml(e.description), legend: stripHtml(e.legend), faction_id: factionId, source: SOURCE,
      });
      replaceOrInsert(data.abilities, a => a.ability_id === eid && a.faction_id === factionId,
        a => a.faction_id === factionId, {
        ability_id: eid, name: stripHtml(e.name), authored_by: 'wahapedia',
        game_version: { edition: '11th', dataslate: 'codex' }, ability_type: 'enhancement',
        rules_text: stripHtml(e.description), faction_id: factionId, detachment_id: did, source: SOURCE,
      });
    }
    const rec = {
      id: did, name: stripHtml(d.name), faction_id: factionId,
      detachment_rule_id: ruleId, enhancement_ids: enhIds,
      stratagem_ids: strats.map(s => `${slug(stripHtml(s.name))}-${did}`),
      game_version: { edition: '11th', dataslate: 'codex' },
      detachment_points: parseInt(d.dp, 10) || 1,
      force_dispositions: d.force_disposition ? [slug(d.force_disposition)] : [],
      tags: /Shield Host/i.test(stripHtml(d.legend) + stripHtml(d.type)) ? ['shield-host'] : [],
      source: SOURCE,
    };
    if (old?.external_refs) rec.external_refs = old.external_refs;
    written.push(rec);
    log(`- detachment ${did}${old ? '' : ' (NEW)'}: rule ${ruleId}, ${enhIds.length} enhancements, ${rec.stratagem_ids.length} stratagems`);
  }
  // Pre-codex detachments the codex removed stay in the data (old rosters
  // name them) but are marked superseded so builders stop offering them.
  for (const od of oldDets) {
    if (!written.some(w => w.id === od.id || normName(w.name) === normName(od.name))) {
      keep.push({ ...od, superseded_by_codex: SOURCE });
      log(`- detachment ${od.id}: not in the codex — kept, marked superseded`);
    }
  }
  for (const rec of [...written, ...keep]) {
    replaceOrInsert(data.detachments, d => d.faction_id === factionId && d.id === rec.id,
      d => d.faction_id === factionId, rec);
  }
}

// ---------------------------------------------------------------------------
// Enhancements, overlay mode (WP-O5, Codex: Orks).
//
// 40kdc 1.4.5 lists pre-codex enhancements under the codex detachment names
// (Mork's Kunnin', Press It Fasta!, Da Biggest Boss, ...), with stale points
// (Targetin' Gizmos 10 -> 25) and missing bearer restrictions. For every codex
// detachment (Boarding Actions skipped, D3) this rewrites the detachment's
// enhancement_ids to exactly the codex list:
//   - an existing record of that detachment with the same name (case,
//     punctuation, spacing and an "(Upgrade)" / "Upgrade" suffix ignored) is
//     updated IN PLACE (id kept): name, cost, upgrade_tag, bearer
//     restriction, rules_text, source;
//   - a codex enhancement with no record gets a new one (slug id);
//   - the detachment's other records are left in the file (old rosters name
//     them) but marked superseded_by_codex and dropped from enhancement_ids.
// Text the CSV export does not carry (the faction page prints it) comes from
// PAGE_ONLY_ENHANCEMENTS below.

// Page-only enhancement text (https://wahapedia.ru/wh40k11ed/factions/orks/,
// read 2026-10-18): the "LEADER: <unit>" line and the weapon profile of the
// "This model has the following weapon" enhancements.
const PAGE_ONLY_ENHANCEMENTS = {
  'orks': {
    'kill kommanda': { leader: ['Kommandos'] },
    'kaptins hat': { leader: ['Flash Gitz'] },
    'da gobshot thunderbuss': { weapon: { name: 'Da Gobshot Thunderbuss', type: 'Ranged', range: '24"', A: '6', BS_WS: '4+', S: '7', AP: '-2', D: '2', keywords: ['Lethal Hits: non-Monster/Vehicle', 'Rapid Fire 6'] } },
    'da krunch': { weapon: { name: 'Da Krunch', type: 'Ranged', range: '24"', A: '3', BS_WS: '4+', S: '5', AP: '-1', D: '1', keywords: ['Blast 3', 'Hazardous', 'Lethal Hits', 'Psychic'] } },
    'eadbanger': { weapon: { name: "'Eadbanger", type: 'Ranged', range: '24"', A: '2', BS_WS: '4+', S: '6', AP: '-3', D: '3', keywords: ['Hazardous', 'Precision', 'Psychic'] } },
  },
};

// Comparable enhancement name: "'Ardboyz (Upgrade)" / "'Ard Boyz" /
// "Throat-Slittas Upgrade" -> "ardboyz" / "ardboyz" / "throatslittas".
export function enhancementKey(name) {
  return normName(String(name).replace(/\s*\([^)]*\)\s*$/, ''))
    .replace(/\s+upgrade$/, '').replace(/\s+/g, '');
}

// "Big Mek/Warboss Infantry model only (excluding X models)." ->
// {groups: [["Big Mek"], ["Warboss", "Infantry"]], exclusions: ["X"], scope}
// Each "/" alternative is split into keywords by the longest known keyword
// (the snapshot's keyword list plus its datasheet names — Wahapedia's keyword
// rows omit a datasheet's own-name keyword, which 40kdc and the game carry).
export function parseEnhancementRestriction(text, knownKeywords) {
  const m = String(text).match(/^\s*(.+?)\s+(model|unit)s?\s+only(?:\s*\(excluding\s+(.+?)\s+(?:models?|units?)\))?\s*\./i);
  if (!m) return null;
  const known = [...knownKeywords].sort((a, b) => b.split(' ').length - a.split(' ').length || b.length - a.length);
  const split = alt => {
    const words = alt.trim().split(/\s+/);
    const out = [];
    let i = 0;
    while (i < words.length) {
      let hit = null;
      for (const k of known) {
        const kw = k.split(' ');
        if (i + kw.length <= words.length && normName(words.slice(i, i + kw.length).join(' ')) === normName(k)) { hit = k; break; }
      }
      if (!hit) { hit = words.slice(i).join(' '); out.push(titleCase(hit)); break; }
      out.push(hit);
      i += hit.split(' ').length;
    }
    return out;
  };
  // "/" binds tighter than the keyword sequence: "Big Mek/Warboss Infantry"
  // is (BIG MEK or WARBOSS) and INFANTRY — the slots' cartesian product, so
  // keywords shared by every alternative apply to each group.
  const slots = [];
  let joinNext = false;
  for (const part of m[1].split(/(\/)/)) {
    if (part === '/') { joinNext = true; continue; }
    const kws = split(part);
    if (!kws.length) continue;
    if (joinNext && slots.length) {
      slots[slots.length - 1].push(kws[0]);
      for (const k of kws.slice(1)) slots.push([k]);
    } else {
      for (const k of kws) slots.push([k]);
    }
    joinNext = false;
  }
  const groups = slots.reduce((acc, slot) => acc.flatMap(g => slot.map(k => [...g, k])), [[]]);
  return {
    scope: m[2].toLowerCase(),
    groups,
    exclusions: m[3] ? m[3].split('/').flatMap(split) : [],
  };
}

function overlayEnhancements(snap, data, factionId, SOURCE, log) {
  const pageOnly = PAGE_ONLY_ENHANCEMENTS[factionId] ?? {};
  const known = new Set(snap.keywords.map(k => stripHtml(k.keyword).trim()).filter(Boolean));
  for (const ds of snap.datasheets) known.add(stripHtml(ds.name).trim());
  const unitIdByName = new Map(data.units.filter(u => u.faction_id === factionId).map(u => [normName(u.name), u.id]));
  const dets = snap.detachments.filter(d => !BOARDING_ACTIONS_DETACHMENTS.has(normName(d.name)));
  let total = 0;
  log(`\nenhancements (overlay): ${dets.length} codex detachments`);
  for (const d of dets) {
    const det = data.detachments.find(x => x.faction_id === factionId && normName(x.name) === normName(d.name));
    if (!det) { log(`- detachment ${d.name}: not in 40kdc — enhancements not written`); continue; }
    const owned = data.enhancements.filter(x => x.detachment_id === det.id || (det.enhancement_ids ?? []).includes(x.id));
    const codex = snap.enhancements.filter(e => e.detachment_id === d.id);
    const ids = [];
    const used = new Set();
    for (const e of codex) {
      const name = stripHtml(e.name).trim();
      const upgrade = /true/i.test(e.upgrade ?? '');
      const cost = parseInt(e.cost, 10) || 0;
      const key = enhancementKey(name);
      const cands = owned.filter(x => !used.has(x) && enhancementKey(x.name) === key);
      cands.sort((a, b) => (Number(!!b.upgrade_tag === upgrade) - Number(!!a.upgrade_tag === upgrade))
        || (Number(b.cost === cost) - Number(a.cost === cost))
        || (Number(b.game_version?.dataslate === 'launch') - Number(a.game_version?.dataslate === 'launch')));
      let rec = cands[0] ?? null;
      const changes = [];
      if (!rec) {
        rec = { id: `${slug(name)}-${det.id}`, detachment_id: det.id, ability_id: null, is_unique: true,
          game_version: { edition: '11th', dataslate: 'codex' }, points_provisional: false, max_targets: 1 };
        data.enhancements.splice(lastIndex(data.enhancements, x => x.detachment_id === det.id) + 1 || data.enhancements.length, 0, rec);
        changes.push('NEW');
      }
      used.add(rec);
      const rulesText = stripHtml(e.description).replace(/\n•\s*/g, ' • ').replace(/\s+/g, ' ').trim();
      const restr = parseEnhancementRestriction(rulesText, known);
      if (rec.name !== name) changes.push(`name "${rec.name}" -> "${name}"`);
      if (rec.cost !== cost) changes.push(`cost ${rec.cost} -> ${cost}`);
      if (!!rec.upgrade_tag !== upgrade) changes.push(`upgrade_tag ${rec.upgrade_tag} -> ${upgrade}`);
      rec.name = name;
      rec.cost = cost;
      rec.upgrade_tag = upgrade;
      if (restr) {
        // Same keyword sets (order / case aside) keep 40kdc's spelling.
        const setKey = gs => JSON.stringify((gs ?? []).map(g => g.map(normName).sort().join('+')).sort());
        const old = rec.keyword_restriction_groups ?? (rec.keyword_restrictions ? [rec.keyword_restrictions] : null);
        const groups = setKey(old) === setKey(restr.groups) ? old : restr.groups;
        if (groups !== old) changes.push(`bearer ${JSON.stringify(old)} -> ${JSON.stringify(groups)}`);
        rec.keyword_restrictions = groups.length === 1 ? groups[0] : null;
        rec.keyword_restriction_groups = groups;
        rec.bearer_scope = restr.scope;
        const oldEx = rec.exclusion_keywords ?? [];
        const ex = setKey([oldEx]) === setKey([restr.exclusions]) ? oldEx : restr.exclusions;
        if (ex !== oldEx) changes.push(`excluding ${JSON.stringify(oldEx)} -> ${JSON.stringify(ex)}`);
        if (ex.length) rec.exclusion_keywords = ex;
        else delete rec.exclusion_keywords;
      } else {
        changes.push('no bearer restriction printed');
      }
      const extra = pageOnly[normName(name)] ?? {};
      if (extra.leader) {
        const bg = extra.leader.map(n => unitIdByName.get(normName(n))).filter(Boolean);
        if (JSON.stringify(rec.attachment_bodyguard_ids ?? null) !== JSON.stringify(bg)) changes.push(`leader -> ${bg.join(', ')}`);
        rec.attachment_bodyguard_ids = bg;
      }
      if (extra.weapon) rec.granted_weapon = extra.weapon;
      rec.rules_text = rulesText;
      rec.legend = stripHtml(e.legend).trim();
      rec.source = SOURCE;
      delete rec.superseded_by_codex;
      ids.push(rec.id);
      if (changes.length) log(`- ${det.id} / ${rec.id}: ${changes.join('; ')}`);
    }
    for (const x of owned) {
      if (used.has(x)) continue;
      if (x.superseded_by_codex !== SOURCE) log(`- ${det.id} / ${x.id} ("${x.name}"): not in the codex — kept, marked superseded`);
      x.superseded_by_codex = SOURCE;
    }
    const before = JSON.stringify(det.enhancement_ids ?? []);
    det.enhancement_ids = ids;
    if (before !== JSON.stringify(ids)) log(`- detachment ${det.id}: enhancement_ids ${before} -> ${JSON.stringify(ids)}`);
    total += ids.length;
  }
  log(`enhancements (overlay): ${total} codex enhancements written`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
