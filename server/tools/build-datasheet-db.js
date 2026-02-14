#!/usr/bin/env node
/**
 * build-datasheet-db.js
 *
 * Downloads Wahapedia CSV exports and converts them into a single
 * datasheets.json file for use by the army list upload tool.
 *
 * Usage:
 *   node build-datasheet-db.js                    # Download CSVs and build
 *   node build-datasheet-db.js --local ./csv_dir  # Build from local CSV files
 *   node build-datasheet-db.js --factions "Space Marines,Orks"  # Filter factions
 *
 * Wahapedia CSV format: pipe-delimited (|), with HTML in some fields.
 * Data export spec: https://wahapedia.ru/wh40k10ed/the-rules/data-export/
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

// ============================================================================
// Configuration
// ============================================================================

const BASE_URL = 'https://wahapedia.ru/wh40k10ed';
const CSV_FILES = [
  'Factions.csv',
  'Datasheets.csv',
  'Datasheets_abilities.csv',
  'Datasheets_keywords.csv',
  'Datasheets_models.csv',
  'Datasheets_wargear.csv',
  'Datasheets_leader.csv',
  'Wargear_list.csv',
];
const OUTPUT_PATH = path.join(__dirname, '..', 'public', 'data', 'datasheets.json');

// ============================================================================
// CSV Parser (pipe-delimited, with quoted fields)
// ============================================================================

function parseCSV(text) {
  const lines = text.split('\n').filter(line => line.trim());
  if (lines.length === 0) return [];

  const headers = parseLine(lines[0]);
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = parseLine(lines[i]);
    if (values.length !== headers.length) continue;

    const row = {};
    for (let j = 0; j < headers.length; j++) {
      row[headers[j].trim()] = values[j].trim();
    }
    rows.push(row);
  }

  return rows;
}

function parseLine(line) {
  // Wahapedia uses pipe (|) as delimiter
  // Fields may contain HTML but generally don't contain unescaped pipes
  return line.split('|').map(field => {
    // Strip surrounding quotes if present
    let f = field.trim();
    if (f.startsWith('"') && f.endsWith('"')) {
      f = f.slice(1, -1).replace(/""/g, '"');
    }
    return f;
  });
}

// ============================================================================
// HTML Stripping (for ability descriptions)
// ============================================================================

function stripHTML(html) {
  if (!html) return '';
  return html
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// ============================================================================
// File Download
// ============================================================================

function downloadFile(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http;
    client.get(url, { headers: { 'User-Agent': 'w40k-army-builder/1.0' } }, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return downloadFile(res.headers.location).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        return;
      }
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
      res.on('error', reject);
    }).on('error', reject);
  });
}

// ============================================================================
// Main Build Logic
// ============================================================================

async function loadCSVData(localDir) {
  const data = {};

  for (const filename of CSV_FILES) {
    const name = filename.replace('.csv', '');
    let text;

    if (localDir) {
      const filePath = path.join(localDir, filename);
      if (!fs.existsSync(filePath)) {
        console.warn(`  Warning: ${filename} not found in ${localDir}, skipping`);
        data[name] = [];
        continue;
      }
      console.log(`  Reading ${filename}...`);
      text = fs.readFileSync(filePath, 'utf-8');
    } else {
      const url = `${BASE_URL}/${filename}`;
      console.log(`  Downloading ${url}...`);
      try {
        text = await downloadFile(url);
      } catch (err) {
        console.warn(`  Warning: Failed to download ${filename}: ${err.message}`);
        data[name] = [];
        continue;
      }
    }

    data[name] = parseCSV(text);
    console.log(`  Parsed ${data[name].length} rows from ${filename}`);
  }

  return data;
}

function buildDatasheetDB(csv, factionFilter) {
  // Build lookup maps
  const factionMap = {};
  for (const f of csv.Factions) {
    factionMap[f.faction_id] = f.name;
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

  // Index abilities by datasheet_id
  const abilitiesByDS = {};
  for (const a of csv.Datasheets_abilities) {
    const key = a.datasheet_id;
    if (!abilitiesByDS[key]) abilitiesByDS[key] = [];
    abilitiesByDS[key].push(a);
  }

  // Index keywords by datasheet_id
  const keywordsByDS = {};
  for (const k of csv.Datasheets_keywords) {
    const key = k.datasheet_id;
    if (!keywordsByDS[key]) keywordsByDS[key] = [];
    keywordsByDS[key].push(k.keyword);
  }

  // Index models by datasheet_id
  const modelsByDS = {};
  for (const m of csv.Datasheets_models) {
    const key = m.datasheet_id;
    if (!modelsByDS[key]) modelsByDS[key] = [];
    modelsByDS[key].push(m);
  }

  // Index wargear by datasheet_id
  const wargearByDS = {};
  for (const w of csv.Datasheets_wargear) {
    const key = w.datasheet_id;
    if (!wargearByDS[key]) wargearByDS[key] = [];
    wargearByDS[key].push(w);
  }

  // Index leader data by datasheet_id
  const leaderByDS = {};
  for (const l of csv.Datasheets_leader) {
    const key = l.datasheet_id;
    if (!leaderByDS[key]) leaderByDS[key] = [];
    leaderByDS[key].push(l);
  }

  // Index weapons (wargear_list) by wargear_id or name
  const weaponsByName = {};
  for (const w of csv.Wargear_list) {
    const key = (w.name || '').toLowerCase();
    if (!weaponsByName[key]) weaponsByName[key] = [];
    weaponsByName[key].push(w);
  }

  // Build the output structure
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

    // Parse stats from datasheet row
    const stats = {};
    if (ds.M) stats.move = parseStatValue(ds.M);
    if (ds.T) stats.toughness = parseStatValue(ds.T);
    if (ds.Sv) stats.save = parseStatValue(ds.Sv);
    if (ds.W) stats.wounds = parseStatValue(ds.W);
    if (ds.Ld) stats.leadership = parseStatValue(ds.Ld);
    if (ds.OC) stats.objective_control = parseStatValue(ds.OC);
    if (ds.inv_sv) stats.invulnerable_save = parseStatValue(ds.inv_sv);
    if (ds.fnp) stats.fnp = parseStatValue(ds.fnp);

    // Build abilities list
    const abilities = (abilitiesByDS[ds.datasheet_id] || []).map(a => ({
      name: a.name || '',
      type: a.type || 'Datasheet',
      description: stripHTML(a.description || ''),
      ...(a.parameter ? { parameter: a.parameter } : {}),
    }));

    // Build keywords list
    const keywords = (keywordsByDS[ds.datasheet_id] || []).map(k => k.toUpperCase());

    // Build weapons list from wargear
    const weapons = [];
    const wargearEntries = wargearByDS[ds.datasheet_id] || [];
    for (const wg of wargearEntries) {
      const wName = (wg.name || '').toLowerCase();
      const weaponProfiles = weaponsByName[wName] || [];
      for (const wp of weaponProfiles) {
        if (wp.faction_id && wp.faction_id !== ds.faction_id) continue;
        const weapon = {
          name: wp.name || wg.name,
          type: (wp.type || '').includes('Melee') ? 'Melee' : 'Ranged',
          range: wp.type === 'Melee' ? 'Melee' : (wp.Range || ''),
          attacks: wp.A || '',
          strength: wp.S || '',
          ap: wp.AP || '0',
          damage: wp.D || '1',
        };
        if (weapon.type === 'Melee') {
          weapon.weapon_skill = wp.BS_WS || '';
        } else {
          weapon.ballistic_skill = wp.BS_WS || '';
        }
        if (wp.abilities) {
          weapon.special_rules = wp.abilities.toLowerCase();
        }
        weapons.push(weapon);
      }
    }

    // Build unit composition from models
    const models = modelsByDS[ds.datasheet_id] || [];
    const unitComp = models.map((m, idx) => ({
      description: m.description || `${m.min || 1} ${ds.name}`,
      line: idx + 1,
    }));

    // Determine base size from models
    let baseMM = 32; // default
    if (models.length > 0 && models[0].base_size) {
      baseMM = parseBaseSizeMM(models[0].base_size);
    }

    // Parse points (models may have cost info, or it comes from datasheet)
    const points = {};
    if (ds.cost) {
      // Some datasheets have cost as "90" or "5:90|10:180"
      const costStr = ds.cost.toString();
      if (costStr.includes('|')) {
        for (const tier of costStr.split('|')) {
          const [count, pts] = tier.split(':');
          points[count.trim()] = parseInt(pts.trim(), 10);
        }
      } else {
        const minModels = models.length > 0 ? (models[0].min || '1') : '1';
        points[minModels] = parseInt(costStr, 10);
      }
    }

    // Leader data
    let leaderData = null;
    const leaderEntries = leaderByDS[ds.datasheet_id] || [];
    if (leaderEntries.length > 0) {
      leaderData = {
        can_lead: leaderEntries.map(l => l.attached_to || '').filter(Boolean),
      };
    }

    // Transport capacity (from abilities)
    let transportCapacity = null;
    const transportAbility = abilities.find(a =>
      a.type === 'Special' && a.description && a.description.toLowerCase().includes('transport capacity')
    );
    if (transportAbility) {
      const match = transportAbility.description.match(/transport capacity of (\d+)/i);
      if (match) transportCapacity = parseInt(match[1], 10);
    }

    result.factions[factionName].units[ds.name] = {
      name: ds.name,
      keywords,
      stats,
      weapons,
      abilities,
      unit_composition: unitComp,
      base_mm: baseMM,
      points,
      leader_data: leaderData,
      transport_capacity: transportCapacity,
    };
  }

  return result;
}

function parseStatValue(val) {
  if (!val || val === '-' || val === 'N/A') return null;
  // Strip trailing "+" from save/leadership values like "3+" or "6+"
  const cleaned = val.replace(/["+\s]/g, '');
  const num = parseInt(cleaned, 10);
  return isNaN(num) ? val : num;
}

function parseBaseSizeMM(sizeStr) {
  if (!sizeStr) return 32;
  // Common patterns: "32mm", "40mm", "25mm Round", "170mm x 105mm Oval"
  const match = sizeStr.match(/(\d+)mm/);
  return match ? parseInt(match[1], 10) : 32;
}

// ============================================================================
// CLI
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  let localDir = null;
  let factionFilter = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--local' && args[i + 1]) {
      localDir = args[++i];
    } else if (args[i] === '--factions' && args[i + 1]) {
      factionFilter = args[++i].split(',').map(f => f.trim());
    } else if (args[i] === '--help') {
      console.log(`
Usage: node build-datasheet-db.js [options]

Options:
  --local <dir>         Use local CSV files instead of downloading
  --factions "A,B,C"    Only include specified factions
  --help                Show this help

Examples:
  node build-datasheet-db.js
  node build-datasheet-db.js --local ./wahapedia_csv
  node build-datasheet-db.js --factions "Space Marines,Orks"
`);
      process.exit(0);
    }
  }

  console.log('Building datasheet database...');
  console.log(localDir ? `Source: local files in ${localDir}` : 'Source: Wahapedia download');
  if (factionFilter) console.log(`Filtering factions: ${factionFilter.join(', ')}`);

  console.log('\nStep 1: Loading CSV data...');
  const csv = await loadCSVData(localDir);

  console.log('\nStep 2: Building datasheet database...');
  const db = buildDatasheetDB(csv, factionFilter);

  const factionCount = Object.keys(db.factions).length;
  let unitCount = 0;
  for (const faction of Object.values(db.factions)) {
    unitCount += Object.keys(faction.units).length;
  }
  console.log(`  Built ${unitCount} units across ${factionCount} factions`);

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

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
