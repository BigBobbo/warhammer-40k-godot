/**
 * generator.js — Army JSON Generator (Phase 3)
 *
 * Converts parsed army list data + datasheet lookups into the game's
 * army JSON format, as expected by ArmyListManager.validate_army_structure().
 *
 * Input:  parsedArmy object (from parser.js Phase 2)
 * Output: game-ready army JSON matching the format in 40k/armies/*.json
 *
 * ── Expected parsedArmy input format ──
 * {
 *   faction: "Space Marines",
 *   detachment: "Gladius Task Force",
 *   points: 2000,
 *   units: [
 *     {
 *       name: "Intercessor Squad",
 *       points: 90,
 *       wargear: ["Bolt rifle", "Bolt pistol"],
 *       enhancement: "Adamantine Talisman",
 *       modelCount: 5,           // optional hint from parser
 *       isWarlord: false,        // optional
 *       matchedDatasheet: null,  // populated by lookup step
 *     },
 *     ...
 *   ]
 * }
 *
 * ── Output format (matches ArmyListManager expectations) ──
 * {
 *   faction: { name, points, detachment, player_name, team_name },
 *   units: {
 *     "U_UNIT_NAME_A": { id, squad_id, owner, status, meta, models },
 *     ...
 *   }
 * }
 */

const ArmyGenerator = (function () {

  // ── Unit ID generation ───────────────────────────────────────────

  /**
   * Convert a unit name to an ID-safe uppercase string.
   * "Intercessor Squad" → "INTERCESSOR_SQUAD"
   * "Caladius Grav-tank" → "CALADIUS_GRAV-TANK"
   */
  function nameToIdBase(name) {
    return name
      .toUpperCase()
      .replace(/[^A-Z0-9\-]/g, '_')  // Keep hyphens, replace other non-alphanumeric
      .replace(/_+/g, '_')           // Collapse multiple underscores
      .replace(/^_|_$/g, '');        // Trim leading/trailing underscores
  }

  /**
   * Generate a unique unit ID with letter suffix.
   * Tracks used letters per name base to increment: A, B, C, ...
   *
   * @param {string} name - The unit name
   * @param {Object} letterTracker - Mutable object tracking { idBase: nextLetterIndex }
   * @returns {string} e.g. "U_INTERCESSORS_A"
   */
  function generateUnitId(name, letterTracker) {
    const base = nameToIdBase(name);
    if (!letterTracker[base]) {
      letterTracker[base] = 0;
    }
    const letterIndex = letterTracker[base]++;
    const letter = String.fromCharCode(65 + letterIndex); // A=65
    return `U_${base}_${letter}`;
  }

  // ── Model count determination ────────────────────────────────────

  /**
   * Determine the number of models for a unit based on:
   * 1. Explicit modelCount hint from the parser
   * 2. Points matching against the datasheet's points tiers
   * 3. Minimum unit size from unit_composition
   *
   * @param {Object} parsedUnit - Parsed unit with optional .modelCount and .points
   * @param {Object} datasheet - Datasheet from the DB
   * @returns {number} Model count
   */
  function determineModelCount(parsedUnit, datasheet) {
    // 1. If the parser extracted a specific model count, use it
    if (parsedUnit.modelCount && parsedUnit.modelCount > 0) {
      return parsedUnit.modelCount;
    }

    // 2. Try to determine from points tiers in the datasheet
    if (datasheet.points && typeof datasheet.points === 'object') {
      const pointsTiers = datasheet.points;
      const unitPoints = parsedUnit.points;

      // Exact points match
      for (const [count, pts] of Object.entries(pointsTiers)) {
        if (pts === unitPoints) {
          return parseInt(count, 10);
        }
      }

      // Closest match (within 10% tolerance for rounding/enhancement points)
      let bestCount = null;
      let bestDiff = Infinity;
      for (const [count, pts] of Object.entries(pointsTiers)) {
        const diff = Math.abs(pts - unitPoints);
        if (diff < bestDiff) {
          bestDiff = diff;
          bestCount = parseInt(count, 10);
        }
      }
      if (bestCount !== null && bestDiff <= unitPoints * 0.15) {
        return bestCount;
      }
    }

    // 3. Fall back to minimum unit size from composition
    return getMinModelCount(datasheet);
  }

  /**
   * Parse the minimum model count from unit_composition entries.
   * Handles formats like:
   *   "5 Intercessors" → 5
   *   "4-5 Custodian Guard" → 4
   *   "1 Warboss" → 1
   *   "1 Boss Nob" + "9-19 Boyz" → 10
   */
  function getMinModelCount(datasheet) {
    if (!datasheet.unit_composition || !Array.isArray(datasheet.unit_composition)) {
      return 1;
    }

    let total = 0;
    for (const comp of datasheet.unit_composition) {
      const desc = comp.description || '';
      // Match "N" or "N-M" at the start
      const match = desc.match(/^(\d+)(?:\s*-\s*\d+)?/);
      if (match) {
        total += parseInt(match[1], 10);
      }
    }
    return total || 1;
  }

  /**
   * Parse the maximum model count from unit_composition entries.
   */
  function getMaxModelCount(datasheet) {
    if (!datasheet.unit_composition || !Array.isArray(datasheet.unit_composition)) {
      return 1;
    }

    let total = 0;
    for (const comp of datasheet.unit_composition) {
      const desc = comp.description || '';
      // Match "N-M" (take M) or just "N"
      const rangeMatch = desc.match(/^(\d+)\s*-\s*(\d+)/);
      if (rangeMatch) {
        total += parseInt(rangeMatch[2], 10);
      } else {
        const singleMatch = desc.match(/^(\d+)/);
        if (singleMatch) {
          total += parseInt(singleMatch[1], 10);
        }
      }
    }
    return total || 1;
  }

  // ── Model array generation ───────────────────────────────────────

  /**
   * Generate the models array for a unit.
   * Each model gets: id, wounds, current_wounds, base_mm, position, alive, status_effects.
   * Vehicles/monsters with oval/rectangular bases also get base_type and base_dimensions.
   *
   * @param {number} modelCount - How many models to generate
   * @param {Object} datasheet - The unit's datasheet from the DB
   * @returns {Array} Array of model objects
   */
  function generateModels(modelCount, datasheet) {
    const wounds = datasheet.stats ? (datasheet.stats.wounds || 1) : 1;
    const baseMm = datasheet.base_mm || 32;
    const baseType = datasheet.base_type || null;
    const baseDimensions = datasheet.base_dimensions || null;

    const models = [];
    for (let i = 0; i < modelCount; i++) {
      const model = {
        id: `m${i + 1}`,
        wounds: wounds,
        current_wounds: wounds,
        base_mm: baseMm,
        position: null,
        alive: true,
        status_effects: []
      };

      // Add base geometry for non-round bases (vehicles, monsters)
      if (baseType && baseType !== 'round') {
        model.base_type = baseType;
      }
      if (baseDimensions) {
        model.base_dimensions = { ...baseDimensions };
      }

      models.push(model);
    }
    return models;
  }

  // ── Weapon filtering ─────────────────────────────────────────────

  /**
   * Filter datasheet weapons based on parsed wargear selections.
   * If no wargear was specified (empty array), include ALL weapons.
   * If wargear was specified, include weapons whose names match
   * any of the wargear entries (fuzzy).
   *
   * @param {Array} datasheetWeapons - All weapons from the datasheet
   * @param {Array} parsedWargear - Wargear strings from the parser
   * @returns {Array} Filtered weapons array
   */
  function filterWeapons(datasheetWeapons, parsedWargear) {
    if (!datasheetWeapons || !Array.isArray(datasheetWeapons)) return [];
    if (!parsedWargear || parsedWargear.length === 0) {
      // No specific wargear selected — include all weapons
      return datasheetWeapons.map(w => ({ ...w }));
    }

    // Normalize wargear names for matching
    const normalizedGear = parsedWargear.map(g =>
      g.toLowerCase()
        .replace(/^\d+x\s+/i, '')  // strip "1x ", "2x " prefix
        .trim()
    );

    const matched = [];
    const matchedNames = new Set();
    let gearMatched = false; // Track if any user-specified wargear actually matched

    for (const weapon of datasheetWeapons) {
      const wepLower = weapon.name.toLowerCase();

      for (const gear of normalizedGear) {
        if (
          wepLower === gear ||
          wepLower.includes(gear) ||
          gear.includes(wepLower)
        ) {
          if (!matchedNames.has(wepLower)) {
            matched.push({ ...weapon });
            matchedNames.add(wepLower);
            gearMatched = true;
          }
          break;
        }
      }
    }

    // If no user-specified wargear matched any weapon, fall back to all weapons
    if (!gearMatched) {
      return datasheetWeapons.map(w => ({ ...w }));
    }

    // Always include "close combat weapon" if not already matched
    for (const weapon of datasheetWeapons) {
      const wepLower = weapon.name.toLowerCase();
      if (wepLower === 'close combat weapon' && !matchedNames.has(wepLower)) {
        matched.push({ ...weapon });
        matchedNames.add(wepLower);
      }
    }

    return matched;
  }

  // ── Ability processing ───────────────────────────────────────────

  /**
   * Copy abilities from the datasheet, preserving type and description.
   */
  function processAbilities(datasheetAbilities) {
    if (!datasheetAbilities || !Array.isArray(datasheetAbilities)) return [];

    return datasheetAbilities.map(ability => {
      const processed = {
        name: ability.name || '',
        type: ability.type || 'Datasheet',
        description: ability.description || ''
      };
      // Preserve the parameter field if present (e.g. "6\"" for Scout, "D3" for Deadly Demise)
      if (ability.parameter !== undefined) {
        processed.parameter = ability.parameter;
      }
      return processed;
    });
  }

  // ── Enhancement processing ───────────────────────────────────────

  /**
   * Format enhancement strings for the army JSON.
   * Input may be just a name like "Adamantine Talisman" or
   * include points like "Adamantine Talisman (+25 pts)".
   */
  function formatEnhancement(enhancement) {
    if (!enhancement) return [];
    if (typeof enhancement === 'string') {
      return [enhancement];
    }
    if (Array.isArray(enhancement)) {
      return enhancement;
    }
    return [];
  }

  // ── Single unit generation ───────────────────────────────────────

  /**
   * Generate a single unit object from parsed data + matched datasheet.
   *
   * @param {Object} parsedUnit - Parsed unit from the parser
   * @param {Object} datasheet - Matched datasheet from the DB
   * @param {string} unitId - Pre-generated unique unit ID
   * @param {number} owner - Player number (1 or 2), default 1
   * @returns {Object} Unit object matching the army JSON format
   */
  function generateUnit(parsedUnit, datasheet, unitId, owner) {
    const modelCount = determineModelCount(parsedUnit, datasheet);
    const models = generateModels(modelCount, datasheet);
    const weapons = filterWeapons(datasheet.weapons, parsedUnit.wargear);
    const abilities = processAbilities(datasheet.abilities);
    const enhancements = formatEnhancement(parsedUnit.enhancement);

    // Build keywords array: combine regular keywords and faction keywords
    const keywords = [];
    if (datasheet.keywords) {
      keywords.push(...datasheet.keywords);
    }
    if (datasheet.faction_keywords) {
      for (const fk of datasheet.faction_keywords) {
        if (!keywords.includes(fk)) {
          keywords.push(fk);
        }
      }
    }

    // Build the stats object (copy from datasheet, strip invulnerable_save to match army format)
    const stats = {};
    if (datasheet.stats) {
      stats.move = datasheet.stats.move || 0;
      stats.toughness = datasheet.stats.toughness || 0;
      stats.save = datasheet.stats.save || 0;
      stats.wounds = datasheet.stats.wounds || 1;
      stats.leadership = datasheet.stats.leadership || 6;
      stats.objective_control = datasheet.stats.objective_control || 0;
      // Keep invulnerable_save if present — some army files include it
      if (datasheet.stats.invulnerable_save) {
        stats.invulnerable_save = datasheet.stats.invulnerable_save;
      }
    }

    // Build the unit object
    const unit = {
      id: unitId,
      squad_id: unitId,
      owner: owner || 1,
      status: 'UNDEPLOYED',
      meta: {
        name: datasheet.name || parsedUnit.name,
        keywords: keywords,
        stats: stats,
        points: parsedUnit.points || 0,
        is_warlord: parsedUnit.isWarlord || false,
        enhancements: enhancements,
        wargear: parsedUnit.wargear || [],
        weapons: weapons,
        abilities: abilities,
        unit_composition: datasheet.unit_composition
          ? datasheet.unit_composition.map(c => ({ ...c }))
          : []
      },
      models: models
    };

    // Include leader_data if present in the datasheet
    if (datasheet.leader_data) {
      unit.meta.leader_data = { ...datasheet.leader_data };
    }

    return unit;
  }

  // ── Full army generation ─────────────────────────────────────────

  /**
   * Generate a complete army JSON from a parsed army list.
   *
   * Before calling this, each parsedUnit should have its .matchedDatasheet
   * populated by looking up the unit in the Datasheets DB. Units without
   * a matched datasheet will be skipped (or a minimal stub generated).
   *
   * @param {Object} parsedArmy - The parsed army object
   * @param {Object} options - Generation options
   * @param {number} options.owner - Player number (1 or 2), default 1
   * @param {string} options.playerName - Player name, default ""
   * @param {string} options.teamName - Team name, default ""
   * @param {boolean} options.includeUnmatched - Generate stubs for unmatched units
   * @returns {Object} result - { army, warnings, errors }
   */
  function generateArmy(parsedArmy, options) {
    const opts = Object.assign({
      owner: 1,
      playerName: '',
      teamName: '',
      includeUnmatched: false
    }, options || {});

    const warnings = [];
    const errors = [];
    const letterTracker = {};
    const units = {};

    // Process each parsed unit
    for (const parsedUnit of (parsedArmy.units || [])) {
      const datasheet = parsedUnit.matchedDatasheet;

      if (!datasheet) {
        const msg = `No matched datasheet for "${parsedUnit.name}"`;
        if (opts.includeUnmatched) {
          warnings.push(msg + ' — generating minimal stub');
          const stubDatasheet = createStubDatasheet(parsedUnit);
          const unitId = generateUnitId(parsedUnit.name, letterTracker);
          units[unitId] = generateUnit(parsedUnit, stubDatasheet, unitId, opts.owner);
        } else {
          errors.push(msg + ' — skipped');
        }
        continue;
      }

      const unitId = generateUnitId(datasheet.name || parsedUnit.name, letterTracker);
      try {
        units[unitId] = generateUnit(parsedUnit, datasheet, unitId, opts.owner);
      } catch (err) {
        errors.push(`Error generating unit "${parsedUnit.name}": ${err.message}`);
      }
    }

    // Calculate total points from generated units
    let totalPoints = 0;
    for (const uid of Object.keys(units)) {
      totalPoints += units[uid].meta.points || 0;
    }

    const army = {
      faction: {
        name: parsedArmy.faction || 'Unknown',
        points: parsedArmy.points || totalPoints,
        detachment: parsedArmy.detachment || '',
        player_name: opts.playerName,
        team_name: opts.teamName
      },
      units: units
    };

    return { army, warnings, errors };
  }

  // ── Stub generation for unmatched units ──────────────────────────

  /**
   * Create a minimal datasheet stub for a unit that couldn't be matched
   * in the database. Uses whatever info the parser extracted.
   */
  function createStubDatasheet(parsedUnit) {
    return {
      name: parsedUnit.name || 'Unknown Unit',
      faction_id: '',
      role: '',
      keywords: ['UNKNOWN'],
      faction_keywords: [],
      stats: {
        move: 6,
        toughness: 4,
        save: 3,
        wounds: 1,
        leadership: 6,
        objective_control: 1
      },
      weapons: [],
      abilities: [],
      unit_composition: [
        {
          description: `${parsedUnit.modelCount || 1} ${parsedUnit.name || 'Unknown'}`,
          line: 1
        }
      ],
      base_mm: 32,
      points: {}
    };
  }

  // ── Convenience: lookup + generate combined ──────────────────────

  /**
   * High-level convenience function: takes a parsed army, looks up all
   * units in the Datasheets DB, and generates the army JSON.
   *
   * Requires Datasheets to be loaded (Datasheets.isLoaded() === true).
   *
   * @param {Object} parsedArmy - Parsed army from the parser
   * @param {Function} lookupFn - Function(factionName, unitName) => datasheet or null
   *                               If not provided, uses Datasheets.getUnit()
   * @param {Object} options - Same as generateArmy options
   * @returns {Object} { army, warnings, errors, matchResults }
   */
  function lookupAndGenerate(parsedArmy, lookupFn, options) {
    const lookup = lookupFn || function (faction, name) {
      if (typeof Datasheets !== 'undefined' && Datasheets.isLoaded()) {
        return Datasheets.getUnit(faction, name);
      }
      return null;
    };

    const matchResults = [];

    // Try to match each unit
    for (const parsedUnit of (parsedArmy.units || [])) {
      const factionName = parsedArmy.faction || '';

      // Step 1: Exact lookup
      let datasheet = lookup(factionName, parsedUnit.name);
      let matchType = datasheet ? 'exact' : 'none';

      // Step 2: Fuzzy match if exact lookup failed
      if (!datasheet && typeof Datasheets !== 'undefined' && Datasheets.isLoaded()) {
        const fuzzyResults = Datasheets.fuzzyMatchUnit(factionName, parsedUnit.name, {
          maxResults: 5,
          minScore: 0.4
        });

        if (fuzzyResults.length > 0) {
          if (fuzzyResults[0].score >= 0.85) {
            // High confidence match — use it automatically
            datasheet = fuzzyResults[0].unit;
            matchType = 'fuzzy_auto';
          } else {
            // Low confidence — mark as ambiguous, use best match
            matchType = 'fuzzy_ambiguous';
          }
        }

        matchResults.push({
          parsedName: parsedUnit.name,
          matchType: matchType,
          matchedName: datasheet ? datasheet.name : null,
          candidates: fuzzyResults.map(r => ({
            name: r.name,
            score: r.score
          }))
        });
      } else {
        matchResults.push({
          parsedName: parsedUnit.name,
          matchType: matchType,
          matchedName: datasheet ? datasheet.name : null,
          candidates: []
        });
      }

      parsedUnit.matchedDatasheet = datasheet;
    }

    const result = generateArmy(parsedArmy, options);
    result.matchResults = matchResults;
    return result;
  }

  // ── Validation ───────────────────────────────────────────────────

  /**
   * Validate a generated army JSON matches the format expected by
   * ArmyListManager.validate_army_structure().
   *
   * @param {Object} army - The generated army JSON
   * @returns {Object} { valid: boolean, errors: string[] }
   */
  function validateArmy(army) {
    const errors = [];

    if (!army || typeof army !== 'object') {
      return { valid: false, errors: ['Army is not an object'] };
    }

    if (!army.units || typeof army.units !== 'object') {
      errors.push("Missing 'units' field");
    } else {
      for (const [unitId, unit] of Object.entries(army.units)) {
        if (!unit || typeof unit !== 'object') {
          errors.push(`Unit ${unitId} is not an object`);
          continue;
        }

        // Required fields
        const requiredFields = ['id', 'meta', 'models'];
        for (const field of requiredFields) {
          if (!(field in unit)) {
            errors.push(`Unit ${unitId} missing field: ${field}`);
          }
        }

        // Validate meta.name
        if (unit.meta && typeof unit.meta === 'object') {
          if (!unit.meta.name) {
            errors.push(`Unit ${unitId} meta missing 'name' field`);
          }
        }

        // Validate models
        if (unit.models) {
          if (!Array.isArray(unit.models)) {
            errors.push(`Unit ${unitId} 'models' field is not an array`);
          } else if (unit.models.length === 0) {
            errors.push(`Unit ${unitId} has no models`);
          }
        }
      }
    }

    return {
      valid: errors.length === 0,
      errors: errors
    };
  }

  // ── Public API ───────────────────────────────────────────────────

  return {
    generateArmy,
    generateUnit,
    lookupAndGenerate,
    validateArmy,

    // Lower-level helpers (also useful for UI)
    generateUnitId,
    determineModelCount,
    generateModels,
    filterWeapons,
    processAbilities,
    formatEnhancement,
    getMinModelCount,
    getMaxModelCount,
    createStubDatasheet,

    // Exposed for testing
    _nameToIdBase: nameToIdBase,
  };
})();

// Support both browser globals and Node.js/CommonJS for testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = ArmyGenerator;
}
