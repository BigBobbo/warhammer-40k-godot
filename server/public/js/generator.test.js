/**
 * generator.test.js — Tests for the Army JSON Generator (Phase 3)
 *
 * Run with: node server/public/js/generator.test.js
 */

const ArmyGenerator = require('./generator.js');
const Datasheets = require('./datasheets.js');

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.error(`  ✗ FAIL: ${message}`);
  }
}

function assertEqual(actual, expected, message) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.error(`  ✗ FAIL: ${message}`);
    console.error(`    Expected: ${JSON.stringify(expected)}`);
    console.error(`    Actual:   ${JSON.stringify(actual)}`);
  }
}

function section(title) {
  console.log(`\n── ${title} ──`);
}

// ══════════════════════════════════════════════════════════════════
// Test data: mock datasheets matching the real DB structure
// ══════════════════════════════════════════════════════════════════

const mockIntercessorDatasheet = {
  name: "Intercessor Squad",
  faction_id: "SM",
  role: "Battleline",
  keywords: ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
  faction_keywords: ["ADEPTUS ASTARTES"],
  stats: {
    move: 6, toughness: 4, save: 3,
    wounds: 2, leadership: 6, objective_control: 2
  },
  weapons: [
    { name: "Bolt rifle", type: "Ranged", range: "24", attacks: "2", ballistic_skill: "3", strength: "4", ap: "-1", damage: "1", special_rules: "assault, heavy" },
    { name: "Bolt pistol", type: "Ranged", range: "12", attacks: "1", ballistic_skill: "3", strength: "4", ap: "0", damage: "1", special_rules: "pistol" },
    { name: "Close combat weapon", type: "Melee", range: "Melee", attacks: "3", weapon_skill: "3", strength: "4", ap: "0", damage: "1" }
  ],
  abilities: [
    { name: "Oath of Moment", type: "Faction", description: "At the start of your Command phase..." }
  ],
  unit_composition: [
    { description: "5 Intercessors", line: 1 }
  ],
  base_mm: 32,
  points: { "5": 90, "10": 180 }
};

const mockCustodianGuardDatasheet = {
  name: "Custodian Guard",
  faction_id: "AC",
  role: "Battleline",
  keywords: ["ADEPTUS CUSTODES", "INFANTRY", "BATTLELINE", "IMPERIUM", "CUSTODIAN GUARD"],
  faction_keywords: ["ADEPTUS CUSTODES"],
  stats: {
    move: 6, toughness: 6, save: 2,
    wounds: 3, leadership: 6, objective_control: 2,
    invulnerable_save: 4
  },
  weapons: [
    { name: "Guardian spear", type: "Ranged", range: "24", attacks: "2", strength: "4", ap: "-1", damage: "2", ballistic_skill: "2", special_rules: "assault" },
    { name: "Sentinel blade", type: "Ranged", range: "12", attacks: "2", strength: "4", ap: "-1", damage: "2", ballistic_skill: "2", special_rules: "assault, pistol" },
    { name: "Guardian spear", type: "Melee", range: "Melee", attacks: "5", strength: "7", ap: "-2", damage: "2", weapon_skill: "2" },
    { name: "Sentinel blade", type: "Melee", range: "Melee", attacks: "5", strength: "6", ap: "-2", damage: "1", weapon_skill: "2" }
  ],
  abilities: [
    { name: "Deep Strike", type: "Core", description: "Some units make their way to battle..." },
    { name: "Martial Ka'tah", type: "Faction", description: "Each time a unit..." },
    { name: "Stand Vigil", type: "Datasheet", description: "Each time a model in this unit..." }
  ],
  unit_composition: [
    { description: "4-5 Custodian Guard", line: 1 }
  ],
  base_mm: 40,
  points: { "4": 150, "5": 190 }
};

const mockBattlewagonDatasheet = {
  name: "Battlewagon",
  faction_id: "ORK",
  role: "Transport",
  keywords: ["BATTLEWAGON", "ORKS", "TRANSPORT", "VEHICLE"],
  faction_keywords: ["ORKS"],
  stats: {
    move: 10, toughness: 10, save: 3,
    wounds: 16, leadership: 7, objective_control: 5
  },
  weapons: [
    { name: "Big shoota", type: "Ranged", range: "36", attacks: "3", ballistic_skill: "5", strength: "5", ap: "0", damage: "1", special_rules: "rapid fire 2" },
    { name: "Deff rolla", type: "Melee", range: "Melee", attacks: "6", weapon_skill: "3", strength: "9", ap: "-1", damage: "2" },
    { name: "Tracks and wheels", type: "Melee", range: "Melee", attacks: "6", weapon_skill: "4", strength: "8", ap: "0", damage: "1" }
  ],
  abilities: [
    { name: "Core", type: "Faction", description: "" },
    { name: "TRANSPORT", type: "Special", description: "This model has a transport capacity of 22 ORKS INFANTRY models." }
  ],
  unit_composition: [
    { description: "1 Battlewagon", line: 1 }
  ],
  base_mm: 180,
  base_type: "rectangular",
  base_dimensions: { length: 180, width: 110 },
  points: { "1": 160 }
};

const mockBladeChampionDatasheet = {
  name: "Blade Champion",
  faction_id: "AC",
  role: "Character",
  keywords: ["ADEPTUS CUSTODES", "BLADE CHAMPION", "CHARACTER", "IMPERIUM", "INFANTRY"],
  faction_keywords: ["ADEPTUS CUSTODES"],
  stats: {
    move: 6, toughness: 6, save: 2,
    wounds: 6, leadership: 6, objective_control: 2,
    invulnerable_save: 4
  },
  weapons: [
    { name: "Vaultswords – Behemor", type: "Melee", range: "Melee", attacks: "6", weapon_skill: "2", strength: "7", ap: "-2", damage: "2", special_rules: "precision" }
  ],
  abilities: [
    { name: "Deep Strike", type: "Core", description: "..." },
    { name: "Martial Ka'tah", type: "Faction", description: "..." },
    { name: "Swift Onslaught", type: "Datasheet", description: "While this model is leading a unit..." }
  ],
  unit_composition: [
    { description: "1 Blade Champion", line: 1 }
  ],
  base_mm: 40,
  points: { "1": 120 },
  leader_data: { can_lead: ["CUSTODIAN GUARD"] }
};

// ══════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════

section("Unit ID Generation");
{
  assertEqual(ArmyGenerator._nameToIdBase("Intercessor Squad"), "INTERCESSOR_SQUAD", "nameToIdBase: spaces to underscores");
  assertEqual(ArmyGenerator._nameToIdBase("Caladius Grav-tank"), "CALADIUS_GRAV-TANK", "nameToIdBase: preserves hyphens");
  assertEqual(ArmyGenerator._nameToIdBase("Boyz"), "BOYZ", "nameToIdBase: simple name");

  const tracker = {};
  assertEqual(ArmyGenerator.generateUnitId("Boyz", tracker), "U_BOYZ_A", "First Boyz gets suffix A");
  assertEqual(ArmyGenerator.generateUnitId("Boyz", tracker), "U_BOYZ_B", "Second Boyz gets suffix B");
  assertEqual(ArmyGenerator.generateUnitId("Boyz", tracker), "U_BOYZ_C", "Third Boyz gets suffix C");
  assertEqual(ArmyGenerator.generateUnitId("Warboss", tracker), "U_WARBOSS_A", "Different unit resets letter");
}

section("Model Count Determination");
{
  // From explicit modelCount hint
  assertEqual(
    ArmyGenerator.determineModelCount({ modelCount: 10, points: 180 }, mockIntercessorDatasheet),
    10,
    "Uses explicit modelCount hint when provided"
  );

  // From exact points match
  assertEqual(
    ArmyGenerator.determineModelCount({ points: 90 }, mockIntercessorDatasheet),
    5,
    "Determines count from exact points match (90pts → 5 models)"
  );

  assertEqual(
    ArmyGenerator.determineModelCount({ points: 180 }, mockIntercessorDatasheet),
    10,
    "Determines count from exact points match (180pts → 10 models)"
  );

  // From points tiers with close match (enhancement may add ~25pts)
  assertEqual(
    ArmyGenerator.determineModelCount({ points: 150 }, mockCustodianGuardDatasheet),
    4,
    "Exact match: 150pts → 4 Custodian Guard"
  );

  // Fallback to minimum composition
  assertEqual(
    ArmyGenerator.determineModelCount({ points: 999 }, mockIntercessorDatasheet),
    5,
    "Falls back to minimum unit size when points don't match any tier"
  );
}

section("Min/Max Model Count Parsing");
{
  assertEqual(ArmyGenerator.getMinModelCount(mockIntercessorDatasheet), 5, "Intercessors min: 5");
  assertEqual(ArmyGenerator.getMaxModelCount(mockIntercessorDatasheet), 5, "Intercessors max: 5 (no range)");

  assertEqual(ArmyGenerator.getMinModelCount(mockCustodianGuardDatasheet), 4, "Custodian Guard min: 4");
  assertEqual(ArmyGenerator.getMaxModelCount(mockCustodianGuardDatasheet), 5, "Custodian Guard max: 5");

  // Multi-line composition like Boyz: "1 Boss Nob" + "9-19 Boyz"
  const boyzDatasheet = {
    unit_composition: [
      { description: "1 Boss Nob", line: 1 },
      { description: "9-19 Boyz", line: 2 }
    ]
  };
  assertEqual(ArmyGenerator.getMinModelCount(boyzDatasheet), 10, "Boyz min: 1 + 9 = 10");
  assertEqual(ArmyGenerator.getMaxModelCount(boyzDatasheet), 20, "Boyz max: 1 + 19 = 20");
}

section("Model Generation");
{
  const models = ArmyGenerator.generateModels(5, mockIntercessorDatasheet);
  assertEqual(models.length, 5, "Generates 5 models for Intercessors");
  assertEqual(models[0].id, "m1", "First model has id m1");
  assertEqual(models[4].id, "m5", "Last model has id m5");
  assertEqual(models[0].wounds, 2, "Model wounds match datasheet");
  assertEqual(models[0].current_wounds, 2, "Current wounds equal to max wounds");
  assertEqual(models[0].base_mm, 32, "Base size from datasheet");
  assertEqual(models[0].alive, true, "Model starts alive");
  assertEqual(models[0].position, null, "Position starts null");
  assert(Array.isArray(models[0].status_effects), "status_effects is an array");

  // Vehicle with non-round base
  const vModels = ArmyGenerator.generateModels(1, mockBattlewagonDatasheet);
  assertEqual(vModels.length, 1, "Vehicle has 1 model");
  assertEqual(vModels[0].wounds, 16, "Battlewagon has 16 wounds");
  assertEqual(vModels[0].base_mm, 180, "Battlewagon base is 180mm");
  assertEqual(vModels[0].base_type, "rectangular", "Battlewagon has rectangular base");
  assertEqual(vModels[0].base_dimensions.length, 180, "Base dimensions preserved");
  assertEqual(vModels[0].base_dimensions.width, 110, "Base dimensions preserved");
}

section("Weapon Filtering");
{
  const allWeapons = mockIntercessorDatasheet.weapons;

  // No wargear specified — include all
  const all = ArmyGenerator.filterWeapons(allWeapons, []);
  assertEqual(all.length, 3, "No wargear filter: returns all 3 weapons");

  // Filter to specific wargear
  const filtered = ArmyGenerator.filterWeapons(allWeapons, ["Bolt rifle"]);
  assert(filtered.some(w => w.name === "Bolt rifle"), "Filtered: includes Bolt rifle");
  assert(filtered.some(w => w.name === "Close combat weapon"), "Filtered: always includes Close combat weapon");
  assert(!filtered.some(w => w.name === "Bolt pistol"), "Filtered: excludes Bolt pistol");

  // Wargear with "1x" prefix
  const prefixed = ArmyGenerator.filterWeapons(allWeapons, ["1x Bolt rifle", "1x Bolt pistol"]);
  assert(prefixed.some(w => w.name === "Bolt rifle"), "Prefixed: matches Bolt rifle");
  assert(prefixed.some(w => w.name === "Bolt pistol"), "Prefixed: matches Bolt pistol");

  // No matches — fallback to all
  const noMatch = ArmyGenerator.filterWeapons(allWeapons, ["Plasma gun"]);
  assertEqual(noMatch.length, 3, "No matches: falls back to all weapons");
}

section("Ability Processing");
{
  const abilities = ArmyGenerator.processAbilities(mockCustodianGuardDatasheet.abilities);
  assertEqual(abilities.length, mockCustodianGuardDatasheet.abilities.length, "Processed ability count matches input");
  assert(abilities.some(a => a.name === "Deep Strike" && a.type === "Core"), "Includes Deep Strike");
  assert(abilities.some(a => a.name === "Stand Vigil" && a.type === "Datasheet"), "Includes Stand Vigil");

  // With parameter field
  const paramAbility = { name: "Core", type: "Core", description: "", parameter: "6\"" };
  const processed = ArmyGenerator.processAbilities([paramAbility]);
  assertEqual(processed[0].parameter, "6\"", "Preserves parameter field");
}

section("Enhancement Formatting");
{
  assertEqual(ArmyGenerator.formatEnhancement(null), [], "null → empty array");
  assertEqual(ArmyGenerator.formatEnhancement("Adamantine Talisman"), ["Adamantine Talisman"], "string → array");
  assertEqual(ArmyGenerator.formatEnhancement(["A", "B"]), ["A", "B"], "array passes through");
}

section("Single Unit Generation");
{
  const parsedUnit = {
    name: "Intercessor Squad",
    points: 90,
    wargear: [],
    enhancement: null,
    isWarlord: false,
    matchedDatasheet: mockIntercessorDatasheet
  };

  const unit = ArmyGenerator.generateUnit(parsedUnit, mockIntercessorDatasheet, "U_INTERCESSOR_SQUAD_A", 1);

  assertEqual(unit.id, "U_INTERCESSOR_SQUAD_A", "Unit ID set correctly");
  assertEqual(unit.squad_id, "U_INTERCESSOR_SQUAD_A", "squad_id matches id");
  assertEqual(unit.owner, 1, "Owner set to 1");
  assertEqual(unit.status, "UNDEPLOYED", "Status is UNDEPLOYED");

  // Meta
  assertEqual(unit.meta.name, "Intercessor Squad", "meta.name correct");
  assert(unit.meta.keywords.includes("INFANTRY"), "Keywords include INFANTRY");
  assert(unit.meta.keywords.includes("ADEPTUS ASTARTES"), "Keywords include faction keyword");
  assertEqual(unit.meta.stats.move, 6, "Stats: move correct");
  assertEqual(unit.meta.stats.wounds, 2, "Stats: wounds correct");
  assertEqual(unit.meta.points, 90, "Points correct");
  assertEqual(unit.meta.is_warlord, false, "is_warlord correct");
  assert(Array.isArray(unit.meta.weapons), "Weapons is an array");
  assert(unit.meta.weapons.length > 0, "Has weapons");
  assert(Array.isArray(unit.meta.abilities), "Abilities is an array");
  assert(unit.meta.abilities.length > 0, "Has abilities");

  // Models
  assertEqual(unit.models.length, 5, "5 models for 90pts");
  assertEqual(unit.models[0].wounds, 2, "Model wounds correct");
  assertEqual(unit.models[0].base_mm, 32, "Model base_mm correct");
}

section("Character Unit with Leader Data");
{
  const parsedChar = {
    name: "Blade Champion",
    points: 120,
    wargear: [],
    enhancement: "Adamantine Talisman (+25 pts)",
    isWarlord: false,
    matchedDatasheet: mockBladeChampionDatasheet
  };

  const unit = ArmyGenerator.generateUnit(parsedChar, mockBladeChampionDatasheet, "U_BLADE_CHAMPION_A", 1);

  assertEqual(unit.models.length, 1, "Character has 1 model");
  assertEqual(unit.models[0].wounds, 6, "Character wounds correct");
  assert(unit.meta.leader_data !== undefined, "leader_data included");
  assert(unit.meta.leader_data.can_lead.includes("CUSTODIAN GUARD"), "Can lead Custodian Guard");
  assertEqual(unit.meta.enhancements[0], "Adamantine Talisman (+25 pts)", "Enhancement string included");
}

section("Full Army Generation");
{
  const parsedArmy = {
    faction: "Space Marines",
    detachment: "Gladius Task Force",
    points: 270,
    units: [
      {
        name: "Intercessor Squad",
        points: 90,
        wargear: [],
        enhancement: null,
        isWarlord: false,
        matchedDatasheet: mockIntercessorDatasheet
      },
      {
        name: "Intercessor Squad",
        points: 180,
        wargear: [],
        enhancement: null,
        isWarlord: false,
        matchedDatasheet: mockIntercessorDatasheet
      }
    ]
  };

  const result = ArmyGenerator.generateArmy(parsedArmy, { owner: 1 });

  assertEqual(result.errors.length, 0, "No errors");
  assertEqual(result.warnings.length, 0, "No warnings");

  const army = result.army;
  assertEqual(army.faction.name, "Space Marines", "Faction name");
  assertEqual(army.faction.detachment, "Gladius Task Force", "Detachment name");
  assertEqual(army.faction.points, 270, "Total points");

  const unitIds = Object.keys(army.units);
  assertEqual(unitIds.length, 2, "Two units generated");
  assert(unitIds.includes("U_INTERCESSOR_SQUAD_A"), "First unit ID: _A suffix");
  assert(unitIds.includes("U_INTERCESSOR_SQUAD_B"), "Second unit ID: _B suffix");

  // First squad has 5 models (90pts)
  assertEqual(army.units["U_INTERCESSOR_SQUAD_A"].models.length, 5, "First squad: 5 models");
  // Second squad has 10 models (180pts)
  assertEqual(army.units["U_INTERCESSOR_SQUAD_B"].models.length, 10, "Second squad: 10 models");
}

section("Army with Unmatched Units");
{
  const parsedArmy = {
    faction: "Space Marines",
    detachment: "Test",
    points: 100,
    units: [
      {
        name: "Custom Character",
        points: 100,
        wargear: [],
        enhancement: null,
        isWarlord: true,
        matchedDatasheet: null  // not matched
      }
    ]
  };

  // Without includeUnmatched
  const result1 = ArmyGenerator.generateArmy(parsedArmy, { includeUnmatched: false });
  assertEqual(Object.keys(result1.army.units).length, 0, "Unmatched skipped when includeUnmatched=false");
  assertEqual(result1.errors.length, 1, "Error reported for unmatched unit");

  // With includeUnmatched
  const result2 = ArmyGenerator.generateArmy(parsedArmy, { includeUnmatched: true });
  assertEqual(Object.keys(result2.army.units).length, 1, "Stub generated when includeUnmatched=true");
  assertEqual(result2.warnings.length, 1, "Warning reported for stub unit");
  const stubUnit = Object.values(result2.army.units)[0];
  assert(stubUnit.meta.keywords.includes("UNKNOWN"), "Stub has UNKNOWN keyword");
  assertEqual(stubUnit.meta.is_warlord, true, "Stub preserves isWarlord flag");
}

section("Mixed Army (multiple factions / unit types)");
{
  const parsedArmy = {
    faction: "Adeptus Custodes",
    detachment: "Shield Host",
    points: 430,
    units: [
      {
        name: "Blade Champion",
        points: 120,
        wargear: [],
        enhancement: "Adamantine Talisman (+25 pts)",
        isWarlord: false,
        matchedDatasheet: mockBladeChampionDatasheet
      },
      {
        name: "Custodian Guard",
        points: 190,
        wargear: ["Guardian spear"],
        enhancement: null,
        isWarlord: false,
        matchedDatasheet: mockCustodianGuardDatasheet
      },
      {
        name: "Custodian Guard",
        points: 150,
        wargear: ["Sentinel blade"],
        enhancement: null,
        isWarlord: false,
        matchedDatasheet: mockCustodianGuardDatasheet
      }
    ]
  };

  const result = ArmyGenerator.generateArmy(parsedArmy);
  const army = result.army;

  assertEqual(Object.keys(army.units).length, 3, "Three units generated");
  assert("U_BLADE_CHAMPION_A" in army.units, "Blade Champion unit present");
  assert("U_CUSTODIAN_GUARD_A" in army.units, "First Custodian Guard present");
  assert("U_CUSTODIAN_GUARD_B" in army.units, "Second Custodian Guard present");

  // First CG: 190pts → 5 models
  assertEqual(army.units["U_CUSTODIAN_GUARD_A"].models.length, 5, "190pts Custodian Guard: 5 models");
  // Second CG: 150pts → 4 models
  assertEqual(army.units["U_CUSTODIAN_GUARD_B"].models.length, 4, "150pts Custodian Guard: 4 models");

  // Wargear filtering
  const cg1Weapons = army.units["U_CUSTODIAN_GUARD_A"].meta.weapons;
  assert(cg1Weapons.some(w => w.name === "Guardian spear"), "CG1 has Guardian spear");

  const cg2Weapons = army.units["U_CUSTODIAN_GUARD_B"].meta.weapons;
  assert(cg2Weapons.some(w => w.name === "Sentinel blade"), "CG2 has Sentinel blade");
}

section("Validation");
{
  // Valid army
  const validArmy = {
    faction: { name: "Test", points: 100 },
    units: {
      "U_TEST_A": {
        id: "U_TEST_A",
        meta: { name: "Test Unit" },
        models: [{ id: "m1", wounds: 1 }]
      }
    }
  };
  const v1 = ArmyGenerator.validateArmy(validArmy);
  assert(v1.valid, "Valid army passes validation");
  assertEqual(v1.errors.length, 0, "No validation errors");

  // Missing units
  const v2 = ArmyGenerator.validateArmy({ faction: {} });
  assert(!v2.valid, "Army without units fails validation");

  // Unit missing meta
  const v3 = ArmyGenerator.validateArmy({
    units: { "U_X_A": { id: "U_X_A", models: [{ id: "m1" }] } }
  });
  assert(!v3.valid, "Unit without meta fails");

  // Unit with empty models
  const v4 = ArmyGenerator.validateArmy({
    units: { "U_X_A": { id: "U_X_A", meta: { name: "X" }, models: [] } }
  });
  assert(!v4.valid, "Unit with empty models fails");

  // Generated army should always pass validation
  const genResult = ArmyGenerator.generateArmy({
    faction: "Test",
    detachment: "",
    points: 90,
    units: [{
      name: "Intercessor Squad",
      points: 90,
      wargear: [],
      matchedDatasheet: mockIntercessorDatasheet
    }]
  });
  const v5 = ArmyGenerator.validateArmy(genResult.army);
  assert(v5.valid, "Generated army passes validation");
}

section("Vehicle / Transport Unit");
{
  const parsedArmy = {
    faction: "Orks",
    detachment: "Waaagh!",
    points: 160,
    units: [
      {
        name: "Battlewagon",
        points: 160,
        wargear: ["Deff rolla", "Big shoota"],
        enhancement: null,
        isWarlord: false,
        matchedDatasheet: mockBattlewagonDatasheet
      }
    ]
  };

  const result = ArmyGenerator.generateArmy(parsedArmy);
  const unit = Object.values(result.army.units)[0];

  assertEqual(unit.models.length, 1, "Vehicle has 1 model");
  assertEqual(unit.models[0].wounds, 16, "Battlewagon: 16 wounds");
  assertEqual(unit.models[0].base_mm, 180, "180mm base");
  assertEqual(unit.models[0].base_type, "rectangular", "Rectangular base");
  assert(unit.meta.keywords.includes("TRANSPORT"), "Has TRANSPORT keyword");
  assert(unit.meta.abilities.some(a => a.name === "TRANSPORT"), "Has TRANSPORT ability");

  // Wargear filtering
  assert(unit.meta.weapons.some(w => w.name === "Big shoota"), "Filtered: Big shoota included");
  assert(unit.meta.weapons.some(w => w.name === "Deff rolla"), "Filtered: Deff rolla included");
}

section("Datasheets.js — Fuzzy Matching");
{
  // Test normalizeName
  assertEqual(Datasheets._normalizeName("Intercessor Squad"), "intercessor", "Strips 'Squad' suffix");
  assertEqual(Datasheets._normalizeName("  The  Boyz  "), "boyz", "Strips articles and trims");

  // Test levenshtein
  assertEqual(Datasheets._levenshtein("kitten", "sitting"), 3, "Levenshtein: kitten→sitting = 3");
  assertEqual(Datasheets._levenshtein("", "abc"), 3, "Levenshtein: empty→abc = 3");
  assertEqual(Datasheets._levenshtein("same", "same"), 0, "Levenshtein: same strings = 0");

  // Test token similarity
  const ts1 = Datasheets._tokenSimilarity("Intercessor Squad", "Intercessor Squad");
  assertEqual(ts1, 1, "Token similarity: identical = 1");

  const ts2 = Datasheets._tokenSimilarity("Intercessor", "Intercessor Squad");
  assert(ts2 > 0.4, "Token similarity: Intercessor vs Intercessor Squad > 0.4");

  // Test similarity score
  const ss1 = Datasheets._similarityScore("Intercessor Squad", "Intercessor Squad");
  assertEqual(ss1, 1.0, "Similarity: exact match = 1.0");

  const ss2 = Datasheets._similarityScore("Intercessors", "Intercessor Squad");
  assert(ss2 > 0.7, `Similarity: Intercessors vs Intercessor Squad = ${ss2.toFixed(2)} > 0.7`);

  const ss3 = Datasheets._similarityScore("Battlewagon", "Trukk");
  assert(ss3 < 0.5, `Similarity: Battlewagon vs Trukk = ${ss3.toFixed(2)} < 0.5`);
}

section("End-to-End: lookupAndGenerate with mock lookup");
{
  const mockDB = {
    "Space Marines": {
      "Intercessor Squad": mockIntercessorDatasheet
    }
  };

  const mockLookup = function (faction, name) {
    if (mockDB[faction] && mockDB[faction][name]) {
      return mockDB[faction][name];
    }
    return null;
  };

  const parsedArmy = {
    faction: "Space Marines",
    detachment: "Gladius Task Force",
    points: 90,
    units: [
      {
        name: "Intercessor Squad",
        points: 90,
        wargear: [],
        enhancement: null,
        isWarlord: false
      }
    ]
  };

  const result = ArmyGenerator.lookupAndGenerate(parsedArmy, mockLookup);

  assertEqual(result.errors.length, 0, "No errors in lookup+generate");
  assert(result.matchResults.length > 0, "Match results recorded");
  assertEqual(result.matchResults[0].matchType, "exact", "Exact match found");

  const army = result.army;
  assert(ArmyGenerator.validateArmy(army).valid, "Generated army is valid");
  assertEqual(Object.keys(army.units).length, 1, "One unit in army");
}

// ══════════════════════════════════════════════════════════════════
// Summary
// ══════════════════════════════════════════════════════════════════

console.log(`\n════════════════════════════════`);
console.log(`Tests: ${passed} passed, ${failed} failed`);
console.log(`════════════════════════════════`);

process.exit(failed > 0 ? 1 : 0);
