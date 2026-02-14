#!/usr/bin/env node
/**
 * build-datasheet-db.js
 *
 * Converts Wahapedia CSV exports into a single datasheets.json file
 * for use by the army list upload tool.
 *
 * Usage:
 *   node build-datasheet-db.js                              # Build from ./wahapedia_csv
 *   node build-datasheet-db.js --local ./other_csv_dir      # Build from custom dir
 *   node build-datasheet-db.js --factions "Space Marines,Orks"  # Filter factions
 *
 * Wahapedia CSV format: pipe-delimited (|), with HTML in some fields.
 * Data export spec: https://wahapedia.ru/wh40k10ed/the-rules/data-export/
 *
 * CSV tables used:
 *   Factions.csv                    - faction_id -> name mapping
 *   Datasheets.csv                  - core datasheet info (name, role, transport, loadout)
 *   Datasheets_models.csv           - per-model stats (M, T, Sv, W, Ld, OC, inv_sv, base_size)
 *   Datasheets_wargear.csv          - weapon profiles (name, type, range, A, BS_WS, S, AP, D)
 *   Datasheets_abilities.csv        - abilities per datasheet (with ability_id refs)
 *   Abilities.csv                   - shared ability definitions (faction abilities, core abilities)
 *   Datasheets_keywords.csv         - keywords per datasheet
 *   Datasheets_leader.csv           - leader_id -> attached_id mapping
 *   Datasheets_unit_composition.csv - unit composition descriptions
 *   Datasheets_models_cost.csv      - points costs per model count
 *   Datasheets_options.csv          - wargear option descriptions
 *   Enhancements.csv                - enhancement definitions
 *   Datasheets_enhancements.csv     - datasheet -> enhancement mapping
 *   Detachments.csv                 - detachment definitions
 *   Stratagems.csv                  - stratagem definitions
 */

const fs = require('fs');
const path = require('path');

// ============================================================================
// Configuration
// ============================================================================

const CSV_FILES = [
  'Factions.csv',
  'Datasheets.csv',
  'Datasheets_models.csv',
  'Datasheets_wargear.csv',
  'Datasheets_abilities.csv',
  'Abilities.csv',
  'Datasheets_keywords.csv',
  'Datasheets_leader.csv',
  'Datasheets_unit_composition.csv',
  'Datasheets_models_cost.csv',
  'Datasheets_options.csv',
  'Enhancements.csv',
  'Datasheets_enhancements.csv',
  'Detachments.csv',
  'Stratagems.csv',
];

const DEFAULT_CSV_DIR = path.join(__dirname, 'wahapedia_csv');
const OUTPUT_PATH = path.join(__dirname, '..', 'public', 'data', 'datasheets.json');

// ============================================================================
// CSV Parser (pipe-delimited)
// ============================================================================

function parseCSV(text) {
  const lines = text.split('\n').filter(line => line.trim());
  if (lines.length === 0) return [];

  // Strip BOM if present
  let headerLine = lines[0];
  if (headerLine.charCodeAt(0) === 0xFEFF) {
    headerLine = headerLine.slice(1);
  }

  const headers = headerLine.split('|').map(h => h.trim()).filter(h => h);
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split('|');
    // Allow trailing pipe (values.length may be headers.length + 1)
    if (values.length < headers.length) continue;

    const row = {};
    for (let j = 0; j < headers.length; j++) {
      row[headers[j]] = (values[j] || '').trim();
    }
    rows.push(row);
  }

  return rows;
}

// ============================================================================
// HTML Stripping
// ============================================================================

function stripHTML(html) {
  if (!html) return '';
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<li>/gi, '- ')
    .replace(/<\/li>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\n\s*\n/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

// ============================================================================
// Stat Parsing
// ============================================================================

function parseStatValue(val) {
  if (!val || val === '-' || val === 'N/A' || val === '') return null;
  // Strip trailing +, ", spaces (e.g. "6\"", "3+", "6+")
  const cleaned = val.replace(/["+\s]/g, '');
  const num = parseInt(cleaned, 10);
  return isNaN(num) ? val : num;
}

function parseBaseSize(sizeStr) {
  if (!sizeStr) return { base_mm: 32 };
  // Patterns: "40mm", "32mm", "100 x 40mm", "170 x 105mm", "25mm"
  const ovalMatch = sizeStr.match(/(\d+)\s*x\s*(\d+)mm/i);
  if (ovalMatch) {
    const length = parseInt(ovalMatch[1], 10);
    const width = parseInt(ovalMatch[2], 10);
    return {
      base_mm: Math.max(length, width),
      base_type: 'oval',
      base_dimensions: { length: Math.max(length, width), width: Math.min(length, width) },
    };
  }
  const roundMatch = sizeStr.match(/(\d+)mm/i);
  if (roundMatch) {
    return { base_mm: parseInt(roundMatch[1], 10) };
  }
  return { base_mm: 32 };
}

function parseTransportCapacity(transportStr) {
  if (!transportStr) return null;
  // e.g. "This model has a transport capacity of 6 Adeptus Custodes Infantry models."
  const stripped = stripHTML(transportStr);
  const match = stripped.match(/transport capacity of (\d+)/i);
  return match ? parseInt(match[1], 10) : stripped;
}

// ============================================================================
// Main Build Logic
// ============================================================================

function loadCSVData(csvDir) {
  const data = {};

  for (const filename of CSV_FILES) {
    const name = filename.replace('.csv', '');
    const filePath = path.join(csvDir, filename);

    if (!fs.existsSync(filePath)) {
      console.warn(`  Warning: ${filename} not found, skipping`);
      data[name] = [];
      continue;
    }

    console.log(`  Reading ${filename}...`);
    const text = fs.readFileSync(filePath, 'utf-8');
    data[name] = parseCSV(text);
    console.log(`    Parsed ${data[name].length} rows`);
  }

  return data;
}

function buildDatasheetDB(csv, factionFilter) {
  // === Build lookup maps ===

  // Factions: id -> name
  const factionMap = {};
  for (const f of csv.Factions) {
    factionMap[f.id] = f.name;
  }

  // Shared abilities: ability_id -> { name, description, type, parameter }
  const sharedAbilities = {};
  for (const a of csv.Abilities) {
    sharedAbilities[a.id] = a;
  }

  // Models by datasheet_id (stats per model type)
  const modelsByDS = {};
  for (const m of csv.Datasheets_models) {
    const key = m.datasheet_id;
    if (!modelsByDS[key]) modelsByDS[key] = [];
    modelsByDS[key].push(m);
  }

  // Wargear (weapons) by datasheet_id
  const wargearByDS = {};
  for (const w of csv.Datasheets_wargear) {
    const key = w.datasheet_id;
    if (!wargearByDS[key]) wargearByDS[key] = [];
    wargearByDS[key].push(w);
  }

  // Abilities by datasheet_id
  const abilitiesByDS = {};
  for (const a of csv.Datasheets_abilities) {
    const key = a.datasheet_id;
    if (!abilitiesByDS[key]) abilitiesByDS[key] = [];
    abilitiesByDS[key].push(a);
  }

  // Keywords by datasheet_id
  const keywordsByDS = {};
  for (const k of csv.Datasheets_keywords) {
    const key = k.datasheet_id;
    if (!keywordsByDS[key]) keywordsByDS[key] = [];
    keywordsByDS[key].push(k);
  }

  // Leader: leader_id -> [attached_id, ...]
  const leaderAttachments = {};
  for (const l of csv.Datasheets_leader) {
    const key = l.leader_id;
    if (!leaderAttachments[key]) leaderAttachments[key] = [];
    leaderAttachments[key].push(l.attached_id);
  }

  // Unit composition by datasheet_id
  const unitCompByDS = {};
  for (const uc of csv.Datasheets_unit_composition) {
    const key = uc.datasheet_id;
    if (!unitCompByDS[key]) unitCompByDS[key] = [];
    unitCompByDS[key].push(uc);
  }

  // Points cost by datasheet_id
  const costByDS = {};
  for (const c of csv.Datasheets_models_cost) {
    const key = c.datasheet_id;
    if (!costByDS[key]) costByDS[key] = [];
    costByDS[key].push(c);
  }

  // Wargear options by datasheet_id
  const optionsByDS = {};
  for (const o of csv.Datasheets_options) {
    const key = o.datasheet_id;
    if (!optionsByDS[key]) optionsByDS[key] = [];
    optionsByDS[key].push(o);
  }

  // Enhancements by enhancement_id
  const enhancementDefs = {};
  for (const e of csv.Enhancements) {
    enhancementDefs[e.id] = e;
  }

  // Datasheet -> enhancement mapping
  const enhancementsByDS = {};
  for (const de of csv.Datasheets_enhancements) {
    const key = de.datasheet_id;
    if (!enhancementsByDS[key]) enhancementsByDS[key] = [];
    enhancementsByDS[key].push(de.enhancement_id);
  }

  // Datasheet id -> name lookup (for leader attachments)
  const dsNameById = {};
  for (const ds of csv.Datasheets) {
    dsNameById[ds.id] = ds.name;
  }

  // Filter datasheets by faction if specified
  let datasheets = csv.Datasheets;
  if (factionFilter) {
    const allowedFactions = new Set(factionFilter.map(f => f.toLowerCase()));
    datasheets = datasheets.filter(ds => {
      const factionName = factionMap[ds.faction_id] || '';
      return allowedFactions.has(factionName.toLowerCase());
    });
  }

  // Skip virtual datasheets (summoned units like Chaos Spawn)
  datasheets = datasheets.filter(ds => ds.virtual !== 'true');

  // === Build the output structure ===
  const result = {
    meta: {
      version: '1.0.0',
      generated: new Date().toISOString().split('T')[0],
      source: 'Wahapedia CSV export',
    },
    factions: {},
  };

  for (const ds of datasheets) {
    const factionName = factionMap[ds.faction_id] || ds.faction_id;

    if (!result.factions[factionName]) {
      result.factions[factionName] = {
        id: ds.faction_id,
        name: factionName,
        units: {},
      };
    }

    // --- Stats from Datasheets_models (use first model line as primary) ---
    const models = modelsByDS[ds.id] || [];
    const primaryModel = models[0];
    const stats = {};
    if (primaryModel) {
      stats.move = parseStatValue(primaryModel.M);
      stats.toughness = parseStatValue(primaryModel.T);
      stats.save = parseStatValue(primaryModel.Sv);
      stats.wounds = parseStatValue(primaryModel.W);
      stats.leadership = parseStatValue(primaryModel.Ld);
      stats.objective_control = parseStatValue(primaryModel.OC);
      if (primaryModel.inv_sv && primaryModel.inv_sv !== '-') {
        stats.invulnerable_save = parseStatValue(primaryModel.inv_sv);
      }
    }

    // If there are multiple model profiles (e.g. different stat lines), include them
    let modelProfiles = null;
    if (models.length > 1) {
      modelProfiles = models.map(m => ({
        name: m.name,
        stats: {
          move: parseStatValue(m.M),
          toughness: parseStatValue(m.T),
          save: parseStatValue(m.Sv),
          wounds: parseStatValue(m.W),
          leadership: parseStatValue(m.Ld),
          objective_control: parseStatValue(m.OC),
          ...(m.inv_sv && m.inv_sv !== '-' ? { invulnerable_save: parseStatValue(m.inv_sv) } : {}),
        },
        base: parseBaseSize(m.base_size),
      }));
    }

    // --- Base size ---
    const baseInfo = primaryModel ? parseBaseSize(primaryModel.base_size) : { base_mm: 32 };

    // --- Weapons from Datasheets_wargear (profiles are inline) ---
    const weapons = [];
    const wargearEntries = wargearByDS[ds.id] || [];
    for (const wg of wargearEntries) {
      if (!wg.name) continue;
      const weapon = {
        name: wg.name,
        type: wg.type === 'Melee' ? 'Melee' : 'Ranged',
        range: wg.type === 'Melee' ? 'Melee' : (wg.range || ''),
        attacks: wg.A || '',
        strength: wg.S || '',
        ap: wg.AP || '0',
        damage: wg.D || '1',
      };

      // BS_WS goes to ballistic_skill (ranged) or weapon_skill (melee)
      if (wg.type === 'Melee') {
        weapon.weapon_skill = wg.BS_WS || '';
      } else {
        // For torrent weapons, BS_WS may be "N/A" or "-"
        const bsVal = wg.BS_WS;
        if (bsVal && bsVal !== 'N/A' && bsVal !== '-') {
          weapon.ballistic_skill = bsVal;
        } else {
          weapon.ballistic_skill = null;
        }
      }

      // description field contains special rules (e.g. "assault, heavy", "torrent, ignores cover")
      if (wg.description) {
        weapon.special_rules = wg.description.toLowerCase();
      }

      weapons.push(weapon);
    }

    // --- Abilities ---
    const abilities = [];
    const abilityEntries = abilitiesByDS[ds.id] || [];
    for (const a of abilityEntries) {
      let name = a.name || '';
      let description = a.description || '';
      let type = a.type || 'Datasheet';
      let parameter = a.parameter || '';

      // If ability_id is set, resolve from shared Abilities.csv
      if (a.ability_id && sharedAbilities[a.ability_id]) {
        const shared = sharedAbilities[a.ability_id];
        name = name || shared.name || '';
        description = description || shared.description || '';
      }

      abilities.push({
        name,
        type,
        description: stripHTML(description),
        ...(parameter ? { parameter } : {}),
      });
    }

    // --- Keywords ---
    const keywordEntries = keywordsByDS[ds.id] || [];
    const keywords = keywordEntries
      .filter(k => !k.is_faction_keyword || k.is_faction_keyword !== 'true')
      .map(k => k.keyword.toUpperCase());
    const factionKeywords = keywordEntries
      .filter(k => k.is_faction_keyword === 'true')
      .map(k => k.keyword.toUpperCase());

    // --- Unit composition ---
    const unitCompEntries = unitCompByDS[ds.id] || [];
    const unitComposition = unitCompEntries.map(uc => ({
      description: stripHTML(uc.description || ''),
      line: parseInt(uc.line, 10) || 1,
    }));

    // --- Points costs ---
    const costEntries = costByDS[ds.id] || [];
    const points = {};
    for (const c of costEntries) {
      // description is like "1 model", "5 models", "10 models"
      const modelCountMatch = (c.description || '').match(/(\d+)\s*model/i);
      const key = modelCountMatch ? modelCountMatch[1] : c.line || '1';
      const cost = parseInt(c.cost, 10);
      if (!isNaN(cost)) {
        points[key] = cost;
      }
    }

    // --- Leader data ---
    let leaderData = null;
    const attachedIds = leaderAttachments[ds.id] || [];
    if (attachedIds.length > 0) {
      leaderData = {
        can_lead: attachedIds.map(id => dsNameById[id] || id).filter(Boolean),
      };
    }

    // --- Transport ---
    const transportCapacity = parseTransportCapacity(ds.transport);

    // --- Wargear options ---
    const optEntries = optionsByDS[ds.id] || [];
    const wargearOptions = optEntries.length > 0
      ? optEntries.map(o => stripHTML(o.description || ''))
      : [];

    // --- Damaged profile ---
    let damagedProfile = null;
    if (ds.damaged_w && ds.damaged_description) {
      damagedProfile = {
        wounds_remaining: ds.damaged_w,
        description: stripHTML(ds.damaged_description),
      };
    }

    // --- Role ---
    const role = ds.role || '';

    // --- Build the unit entry ---
    const unit = {
      name: ds.name,
      faction_id: ds.faction_id,
      role,
      keywords: [...factionKeywords, ...keywords],
      faction_keywords: factionKeywords,
      stats,
      weapons,
      abilities,
      unit_composition: unitComposition,
      base_mm: baseInfo.base_mm,
      points,
    };

    // Only include optional fields when they have data
    if (baseInfo.base_type) {
      unit.base_type = baseInfo.base_type;
      unit.base_dimensions = baseInfo.base_dimensions;
    }
    if (modelProfiles) {
      unit.model_profiles = modelProfiles;
    }
    if (leaderData) {
      unit.leader_data = leaderData;
    }
    if (transportCapacity) {
      unit.transport_capacity = transportCapacity;
    }
    if (wargearOptions.length > 0) {
      unit.wargear_options = wargearOptions;
    }
    if (damagedProfile) {
      unit.damaged_profile = damagedProfile;
    }
    if (ds.loadout) {
      unit.default_loadout = stripHTML(ds.loadout);
    }

    result.factions[factionName].units[ds.name] = unit;
  }

  return result;
}

// ============================================================================
// CLI
// ============================================================================

function main() {
  const args = process.argv.slice(2);
  let csvDir = DEFAULT_CSV_DIR;
  let factionFilter = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--local' && args[i + 1]) {
      csvDir = path.resolve(args[++i]);
    } else if (args[i] === '--factions' && args[i + 1]) {
      factionFilter = args[++i].split(',').map(f => f.trim());
    } else if (args[i] === '--help') {
      console.log(`
Usage: node build-datasheet-db.js [options]

Options:
  --local <dir>         Use CSV files from specified directory (default: ./wahapedia_csv)
  --factions "A,B,C"    Only include specified factions
  --help                Show this help

Examples:
  node build-datasheet-db.js
  node build-datasheet-db.js --local ./wahapedia_csv
  node build-datasheet-db.js --factions "Space Marines,Orks,Adeptus Custodes"
`);
      process.exit(0);
    }
  }

  console.log('Building datasheet database...');
  console.log(`Source: ${csvDir}`);
  if (factionFilter) console.log(`Filtering factions: ${factionFilter.join(', ')}`);

  console.log('\nStep 1: Loading CSV data...');
  const csv = loadCSVData(csvDir);

  console.log('\nStep 2: Building datasheet database...');
  const db = buildDatasheetDB(csv, factionFilter);

  // Print summary
  const factionCount = Object.keys(db.factions).length;
  let unitCount = 0;
  for (const [fName, faction] of Object.entries(db.factions)) {
    const count = Object.keys(faction.units).length;
    unitCount += count;
    console.log(`  ${fName}: ${count} units`);
  }
  console.log(`  Total: ${unitCount} units across ${factionCount} factions`);

  console.log(`\nStep 3: Writing to ${OUTPUT_PATH}...`);
  const outputDir = path.dirname(OUTPUT_PATH);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(db, null, 2));

  const fileSize = (fs.statSync(OUTPUT_PATH).size / 1024).toFixed(1);
  console.log(`  Written ${fileSize}KB`);
  console.log('\nDone!');
}

main();
