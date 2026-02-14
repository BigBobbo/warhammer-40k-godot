/**
 * integration.test.js — End-to-end test: Parser → Datasheets → Generator
 *
 * Tests the full pipeline: paste text → parse → lookup in real DB → generate army JSON.
 *
 * Run with: node server/public/js/integration.test.js
 */

const fs = require('fs');
const path = require('path');

// Load modules
const ArmyParser = require('./parser.js');
const ArmyGenerator = require('./generator.js');
const Datasheets = require('./datasheets.js');

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
  } else {
    failed++;
    console.error(`  FAIL: ${message}`);
  }
}

function assertEqual(actual, expected, message) {
  if (actual === expected) {
    passed++;
  } else {
    failed++;
    console.error(`  FAIL: ${message}`);
    console.error(`    Expected: ${JSON.stringify(expected)}`);
    console.error(`    Actual:   ${JSON.stringify(actual)}`);
  }
}

function test(name, fn) {
  console.log(`TEST: ${name}`);
  try {
    fn();
  } catch (err) {
    failed++;
    console.error(`  ERROR: ${err.message}`);
  }
}

// ============================================================================
// Load the real datasheets database
// ============================================================================

const DB_PATH = path.join(__dirname, '..', 'data', 'datasheets.json');

console.log('Loading datasheets.json from disk...');
const rawDb = JSON.parse(fs.readFileSync(DB_PATH, 'utf-8'));

// Manually inject into Datasheets module (since we can't use fetch in Node)
// Use the internal _db setter via load() mock
Datasheets._db = null;

// Patch: set _db directly for testing
Object.defineProperty(Datasheets, '_db', {
  get: function() { return this.__db; },
  set: function(v) { this.__db = v; }
});

// This is a hack — inject the DB so getDB() / isLoaded() works
// We need to access the IIFE's internal state. Since load() uses fetch (browser-only),
// we'll need to monkey-patch the module slightly.
// Instead, let's load it differently:

// Workaround: re-create the module with a preloaded DB
const DatasheetsLoaded = (function () {
  const mod = require('./datasheets.js');
  // The module uses an IIFE with closure. We can't inject directly.
  // Instead, override getDB to return our loaded data.
  return {
    ...mod,
    isLoaded: () => true,
    getDB: () => rawDb,
    getFactionNames: () => Object.keys(rawDb.factions || {}),
    getFaction: (name) => {
      if (!rawDb.factions) return null;
      if (rawDb.factions[name]) return rawDb.factions[name];
      const lower = name.toLowerCase();
      for (const key of Object.keys(rawDb.factions)) {
        if (key.toLowerCase() === lower) return rawDb.factions[key];
      }
      return null;
    },
    getUnit: (factionName, unitName) => {
      const faction = DatasheetsLoaded.getFaction(factionName);
      if (!faction || !faction.units) return null;
      if (faction.units[unitName]) return faction.units[unitName];
      const lower = unitName.toLowerCase();
      for (const key of Object.keys(faction.units)) {
        if (key.toLowerCase() === lower) return faction.units[key];
      }
      return null;
    },
    getUnitNames: (factionName) => {
      const faction = DatasheetsLoaded.getFaction(factionName);
      if (!faction || !faction.units) return [];
      return Object.keys(faction.units);
    },
    fuzzyMatchUnit: mod.fuzzyMatchUnit ? (factionName, query, options) => {
      // Re-implement with our loaded data
      const opts = Object.assign({ maxResults: 5, minScore: 0.3 }, options || {});
      const faction = DatasheetsLoaded.getFaction(factionName);
      if (!faction || !faction.units) return [];
      const results = [];
      for (const unitName of Object.keys(faction.units)) {
        const score = mod._similarityScore(query, unitName);
        if (score >= opts.minScore) {
          results.push({ name: unitName, unit: faction.units[unitName], score });
        }
      }
      results.sort((a, b) => b.score - a.score);
      return results.slice(0, opts.maxResults);
    } : () => [],
  };
})();

console.log(`Loaded ${DatasheetsLoaded.getFactionNames().length} factions\n`);

// ============================================================================
// Integration test: Space Marines army
// ============================================================================

test('Integration: Space Marines army — full pipeline', () => {
  const armyText = `Space Marines (1000 pts)
Gladius Task Force

Intercessor Squad (90 pts)
• Bolt rifle
• Bolt pistol

Bladeguard Veterans (100 pts)
• Master-crafted power sword
• Storm shield`;

  // Step 1: Parse
  const parsed = ArmyParser.parse(armyText);
  assertEqual(parsed.faction, 'Space Marines', 'parsed faction');
  assertEqual(parsed.units.length, 2, 'parsed 2 units');
  assertEqual(parsed.format, 'standard', 'standard format');

  // Step 2: Lookup + Generate
  const result = ArmyGenerator.lookupAndGenerate(parsed, (faction, name) => {
    return DatasheetsLoaded.getUnit(faction, name);
  }, { owner: 1 });

  // Step 3: Verify result
  assert(result.army !== null, 'army generated');
  assertEqual(result.army.faction.name, 'Space Marines', 'army faction');
  assertEqual(result.army.faction.detachment, 'Gladius Task Force', 'army detachment');

  const unitIds = Object.keys(result.army.units);
  assert(unitIds.length >= 1, 'at least 1 unit generated');

  // Check match results
  assert(result.matchResults.length === 2, 'match results for 2 units');

  // Validate army structure
  const validation = ArmyGenerator.validateArmy(result.army);
  assert(validation.valid, 'army passes validation: ' + validation.errors.join(', '));

  // Check for errors
  if (result.errors.length > 0) {
    console.log('  Errors:', result.errors);
  }
  if (result.warnings.length > 0) {
    console.log('  Warnings:', result.warnings);
  }
});

// ============================================================================
// Integration test: Orks army
// ============================================================================

test('Integration: Orks army', () => {
  const armyText = `Orks

Boyz (75 pts)
• Slugga
• Choppa

Warboss (70 pts)
• Power Klaw`;

  const parsed = ArmyParser.parse(armyText);
  assertEqual(parsed.faction, 'Orks', 'parsed faction');
  assertEqual(parsed.units.length, 2, 'parsed 2 units');

  const result = ArmyGenerator.lookupAndGenerate(parsed, (faction, name) => {
    return DatasheetsLoaded.getUnit(faction, name);
  }, { owner: 2 });

  assert(result.army !== null, 'army generated');

  // Check match results
  for (const mr of result.matchResults) {
    console.log(`  "${mr.parsedName}" -> ${mr.matchType}${mr.matchedName ? ' (' + mr.matchedName + ')' : ''}`);
  }

  const validation = ArmyGenerator.validateArmy(result.army);
  assert(validation.valid, 'army passes validation: ' + validation.errors.join(', '));
});

// ============================================================================
// Integration test: Verify generated JSON matches existing army format
// ============================================================================

test('Integration: Generated JSON format matches existing army files', () => {
  const armyText = `Space Marines (500 pts)
Battle Company

Intercessor Squad (90 pts)
• Bolt rifle
• Bolt pistol
• Close combat weapon`;

  const parsed = ArmyParser.parse(armyText);
  const result = ArmyGenerator.lookupAndGenerate(parsed, (faction, name) => {
    return DatasheetsLoaded.getUnit(faction, name);
  }, { owner: 1 });

  const army = result.army;

  // Verify top-level structure
  assert('faction' in army, 'has faction field');
  assert('units' in army, 'has units field');
  assert('name' in army.faction, 'faction has name');
  assert('points' in army.faction, 'faction has points');
  assert('detachment' in army.faction, 'faction has detachment');
  assert('player_name' in army.faction, 'faction has player_name');
  assert('team_name' in army.faction, 'faction has team_name');

  // Verify unit structure
  for (const [unitId, unit] of Object.entries(army.units)) {
    assert(unitId.startsWith('U_'), 'unit ID starts with U_: ' + unitId);
    assert('id' in unit, 'unit has id');
    assert('squad_id' in unit, 'unit has squad_id');
    assert('owner' in unit, 'unit has owner');
    assert('status' in unit, 'unit has status');
    assert('meta' in unit, 'unit has meta');
    assert('models' in unit, 'unit has models');

    assertEqual(unit.status, 'UNDEPLOYED', 'unit status is UNDEPLOYED');

    // Verify meta
    assert('name' in unit.meta, 'meta has name');
    assert('keywords' in unit.meta, 'meta has keywords');
    assert('stats' in unit.meta, 'meta has stats');
    assert('weapons' in unit.meta, 'meta has weapons');

    // Verify stats
    const stats = unit.meta.stats;
    assert('move' in stats, 'stats has move');
    assert('toughness' in stats, 'stats has toughness');
    assert('save' in stats, 'stats has save');
    assert('wounds' in stats, 'stats has wounds');
    assert('leadership' in stats, 'stats has leadership');
    assert('objective_control' in stats, 'stats has objective_control');

    // Verify models
    assert(Array.isArray(unit.models), 'models is array');
    assert(unit.models.length > 0, 'has at least 1 model');

    for (const model of unit.models) {
      assert('id' in model, 'model has id');
      assert('wounds' in model, 'model has wounds');
      assert('current_wounds' in model, 'model has current_wounds');
      assert('base_mm' in model, 'model has base_mm');
      assert('alive' in model, 'model has alive');
      assertEqual(model.alive, true, 'model starts alive');
    }
  }
});

// ============================================================================
// Integration test: DB faction listing
// ============================================================================

test('Integration: Database has expected factions', () => {
  const factions = DatasheetsLoaded.getFactionNames();
  assert(factions.length > 0, 'has factions');
  console.log(`  Found ${factions.length} factions: ${factions.slice(0, 5).join(', ')}...`);

  // Check for some expected factions
  const expected = ['Space Marines', 'Orks'];
  for (const name of expected) {
    const found = factions.some(f => f.toLowerCase().includes(name.toLowerCase()));
    assert(found, `faction "${name}" present in DB`);
  }
});

// ============================================================================
// Integration test: Fuzzy matching with real DB
// ============================================================================

test('Integration: Fuzzy matching against real DB', () => {
  // "Intercessors" should match "Intercessor Squad" in Space Marines
  const results = DatasheetsLoaded.fuzzyMatchUnit('Space Marines', 'Intercessors', {
    maxResults: 3,
    minScore: 0.3
  });

  assert(results.length > 0, 'found matches for "Intercessors"');
  if (results.length > 0) {
    console.log(`  Best match: "${results[0].name}" (score: ${results[0].score.toFixed(2)})`);
    assert(results[0].score > 0.5, 'best match score > 0.5');
  }
});

// ============================================================================
// Results
// ============================================================================

console.log('\n' + '='.repeat(50));
console.log(`Integration Results: ${passed} passed, ${failed} failed`);
console.log('='.repeat(50));

if (failed > 0) {
  process.exit(1);
} else {
  console.log('All integration tests passed!');
}
