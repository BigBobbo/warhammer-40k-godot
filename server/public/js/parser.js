/**
 * parser.js — Army List Text Parser (Phase 2)
 *
 * Parses pasted army list text (from GW App, New Recruit, ListEngine, etc.)
 * into a structured object that can be fed to ArmyGenerator.lookupAndGenerate().
 *
 * ── Supported input formats ──
 *
 * Standard format (GW App / New Recruit / ListEngine):
 *   Faction Name (Total Points)
 *   Detachment Name
 *
 *   Unit Name (Points)
 *     • Wargear 1
 *     • Wargear 2
 *     • Enhancement: Enhancement Name
 *
 *   Unit Name (Points)
 *     • Wargear 1
 *
 * ── Output format (matches ArmyGenerator input) ──
 * {
 *   faction: "Space Marines",
 *   detachment: "Gladius Task Force",
 *   points: 2000,
 *   units: [
 *     {
 *       name: "Intercessor Squad",
 *       points: 90,
 *       wargear: ["Bolt rifle", "Bolt pistol"],
 *       enhancement: null,
 *       modelCount: null,
 *       isWarlord: false,
 *       matchedDatasheet: null
 *     }
 *   ]
 * }
 */

const ArmyParser = (function () {

  // ── Text normalization ──────────────────────────────────────────

  /**
   * Normalize raw input text:
   * - Standardize line endings
   * - Strip BOM and zero-width characters
   * - Collapse multiple blank lines into one
   * - Trim leading/trailing whitespace per line
   */
  function normalizeText(text) {
    return text
      .replace(/\uFEFF/g, '')                 // BOM
      .replace(/[\u200B-\u200D\uFEFF]/g, '')  // zero-width chars
      .replace(/\r\n/g, '\n')                 // Windows line endings
      .replace(/\r/g, '\n')                   // Old Mac line endings
      .replace(/\t/g, '  ')                   // Tabs to spaces
      .replace(/\n{3,}/g, '\n\n')             // Collapse 3+ blank lines to 2
      .trim();
  }

  // ── Line classification ─────────────────────────────────────────

  /**
   * Check if a line is a wargear/equipment line.
   * These are indented or prefixed with bullet characters.
   */
  function isWargearLine(line) {
    const trimmed = line.trim();
    // Bullet prefixes: •, ·, -, *, numbered (1., 2.)
    if (/^[•·\-\*]\s+/.test(trimmed)) return true;
    if (/^\d+[.)]\s+/.test(trimmed)) return true;
    // Indented lines (2+ spaces) that aren't a unit header (no points in parens)
    if (/^\s{2,}/.test(line) && !/\(\s*\d+\s*(pts|points)?\s*\)/.test(trimmed)) return true;
    return false;
  }

  /**
   * Check if a line looks like a unit header: "Unit Name (Points)"
   */
  function isUnitHeader(line) {
    const trimmed = line.trim();
    // Must have points in parentheses at the end
    return /\(\s*\d+\s*(pts|points)?\s*\)\s*$/.test(trimmed);
  }

  /**
   * Check if a line is an enhancement line.
   */
  function isEnhancementLine(line) {
    const trimmed = line.trim().replace(/^[•·\-\*]\s*/, '');
    return /^enhancement/i.test(trimmed);
  }

  /**
   * Check if a line is a warlord marker.
   */
  function isWarlordLine(line) {
    const trimmed = line.trim().toLowerCase();
    return trimmed === 'warlord' || trimmed === '• warlord' || trimmed === '- warlord';
  }

  // ── Value extraction ────────────────────────────────────────────

  /**
   * Extract points value from a parenthesized expression: "(90)" or "(90 pts)"
   */
  function extractPoints(text) {
    const match = text.match(/\(\s*(\d+)\s*(pts|points)?\s*\)/);
    return match ? parseInt(match[1], 10) : null;
  }

  /**
   * Extract the unit/faction name (everything before the points parenthetical).
   */
  function extractName(text) {
    // Remove points parenthetical at the end
    return text
      .replace(/\s*\(\s*\d+\s*(pts|points)?\s*\)\s*$/, '')
      .trim();
  }

  /**
   * Parse a wargear line to extract the item name.
   * Strips bullet prefixes, count prefixes ("2x"), and trailing annotations.
   */
  function parseWargearLine(line) {
    let text = line.trim();
    // Strip bullet prefix
    text = text.replace(/^[•·\-\*]\s*/, '');
    text = text.replace(/^\d+[.)]\s*/, '');
    text = text.trim();
    return text;
  }

  /**
   * Extract enhancement name from an enhancement line.
   * "Enhancement: Adamantine Talisman" → "Adamantine Talisman"
   * "Enhancement: Adamantine Talisman (+25 pts)" → "Adamantine Talisman"
   */
  function parseEnhancementLine(line) {
    let text = line.trim();
    // Strip bullet prefix
    text = text.replace(/^[•·\-\*]\s*/, '');
    // Extract after "Enhancement:" or "Enhancements:"
    const match = text.match(/^enhancements?\s*:\s*(.+)/i);
    if (!match) return text;
    let name = match[1].trim();
    // Strip trailing points
    name = name.replace(/\s*\(\s*[+]?\s*\d+\s*(pts|points)?\s*\)\s*$/, '').trim();
    return name;
  }

  /**
   * Extract model count from a name like "5 Intercessors" or a line like "x3".
   */
  function extractModelCount(text) {
    // "5 Intercessors" pattern — number at the start before the unit name
    const leadingMatch = text.match(/^(\d+)\s*x?\s+/i);
    if (leadingMatch) return parseInt(leadingMatch[1], 10);
    // "Intercessors x5" pattern
    const trailingMatch = text.match(/x\s*(\d+)\s*$/i);
    if (trailingMatch) return parseInt(trailingMatch[1], 10);
    return null;
  }

  // ── Format detection ────────────────────────────────────────────

  /**
   * Detect the army list format variant.
   * Returns: 'standard' | 'battlescribe' | 'unknown'
   */
  function detectFormat(text) {
    // BattleScribe uses ++ markers
    if (/^\+\+/.test(text.trim())) return 'battlescribe';
    // Standard format: faction line with points, then unit blocks
    return 'standard';
  }

  // ── Header parsing ──────────────────────────────────────────────

  /**
   * Parse the army header from the first non-blank section.
   * Extracts faction name, total points, and detachment.
   *
   * The header is typically the first 1-3 lines before the first blank line:
   *   Space Marines (2000 pts)
   *   Gladius Task Force
   *
   * Or just:
   *   Space Marines
   *   Gladius Task Force
   *   2000 pts
   */
  function parseHeader(headerLines) {
    const result = {
      faction: null,
      detachment: null,
      points: null
    };

    if (headerLines.length === 0) return result;

    // First line: faction (possibly with points)
    const firstLine = headerLines[0].trim();
    const firstPoints = extractPoints(firstLine);

    if (firstPoints !== null) {
      result.faction = extractName(firstLine);
      result.points = firstPoints;
    } else {
      result.faction = firstLine;
    }

    // Second line: detachment (or points if faction had no points)
    if (headerLines.length > 1) {
      const secondLine = headerLines[1].trim();
      const secondPoints = extractPoints(secondLine);

      if (secondPoints !== null && result.points === null) {
        result.points = secondPoints;
        // The line might also contain info (e.g., "Detachment (2000)")
        const name = extractName(secondLine);
        if (name) result.detachment = name;
      } else {
        // Check if it's a pure points line: "2000 pts" or "2000 points"
        const purePointsMatch = secondLine.match(/^(\d+)\s*(pts|points)\s*$/i);
        if (purePointsMatch && result.points === null) {
          result.points = parseInt(purePointsMatch[1], 10);
        } else {
          result.detachment = secondLine;
        }
      }
    }

    // Third line: could be detachment if we haven't found one yet
    if (headerLines.length > 2 && !result.detachment) {
      const thirdLine = headerLines[2].trim();
      if (thirdLine && !extractPoints(thirdLine)) {
        result.detachment = thirdLine;
      }
    }

    return result;
  }

  // ── Block splitting ─────────────────────────────────────────────

  /**
   * Split normalized text into blocks separated by blank lines.
   * Returns an array of arrays of non-blank lines.
   */
  function splitIntoBlocks(text) {
    const lines = text.split('\n');
    const blocks = [];
    let currentBlock = [];

    for (const line of lines) {
      if (line.trim() === '') {
        if (currentBlock.length > 0) {
          blocks.push(currentBlock);
          currentBlock = [];
        }
      } else {
        currentBlock.push(line);
      }
    }

    if (currentBlock.length > 0) {
      blocks.push(currentBlock);
    }

    return blocks;
  }

  // ── Unit block parsing ──────────────────────────────────────────

  /**
   * Parse a single unit block (array of lines) into a parsed unit object.
   *
   * A unit block looks like:
   *   Intercessor Squad (90 pts)
   *   • Bolt rifle
   *   • Bolt pistol
   *   • Enhancement: Adamantine Talisman
   */
  function parseUnitBlock(lines) {
    if (lines.length === 0) return null;

    const unit = {
      name: null,
      points: null,
      wargear: [],
      enhancement: null,
      modelCount: null,
      isWarlord: false,
      matchedDatasheet: null
    };

    // First line should be the unit header
    const headerLine = lines[0].trim();

    // Extract points
    unit.points = extractPoints(headerLine);

    // Extract name (before points)
    let rawName = extractName(headerLine);

    // Check for model count in name
    const countFromName = extractModelCount(rawName);
    if (countFromName !== null) {
      unit.modelCount = countFromName;
      // Strip the count prefix from the name
      rawName = rawName.replace(/^\d+\s*x?\s+/i, '').trim();
    }

    unit.name = rawName;

    // Process remaining lines as wargear/enhancements
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i];

      if (isWarlordLine(line)) {
        unit.isWarlord = true;
        continue;
      }

      if (isEnhancementLine(line)) {
        unit.enhancement = parseEnhancementLine(line);
        continue;
      }

      if (isWargearLine(line) || line.trim().length > 0) {
        const gear = parseWargearLine(line);
        if (gear) {
          unit.wargear.push(gear);
        }
      }
    }

    return unit;
  }

  // ── Main parse function ─────────────────────────────────────────

  /**
   * Parse raw army list text into a structured army object.
   *
   * @param {string} rawText - The raw army list text pasted by the user
   * @returns {Object} { faction, detachment, points, units[], format, errors[] }
   */
  function parse(rawText) {
    if (!rawText || typeof rawText !== 'string' || rawText.trim().length === 0) {
      return {
        faction: null,
        detachment: null,
        points: null,
        units: [],
        format: 'unknown',
        errors: ['No text provided']
      };
    }

    const normalized = normalizeText(rawText);
    const format = detectFormat(normalized);
    const errors = [];

    if (format === 'battlescribe') {
      return parseBattleScribe(normalized);
    }

    return parseStandard(normalized, errors);
  }

  /**
   * Parse standard format army lists (GW App, New Recruit, ListEngine).
   */
  function parseStandard(text, errors) {
    const blocks = splitIntoBlocks(text);

    if (blocks.length === 0) {
      return {
        faction: null,
        detachment: null,
        points: null,
        units: [],
        format: 'standard',
        errors: ['No content found after parsing']
      };
    }

    // Determine which block is the header vs unit blocks.
    // The header block is the first block that does NOT have a unit-header-style
    // first line (name + points), OR the very first block if it looks like a header.
    let headerBlock = null;
    let unitBlocks = [];

    // Heuristic: if the first block's first line has points AND looks like a
    // faction name (not a specific unit), treat it as header.
    // Otherwise, if the first block has no points line, it's the header.
    const firstBlockFirstLine = blocks[0][0].trim();
    const firstBlockHasPoints = extractPoints(firstBlockFirstLine) !== null;

    // Check if first block looks like a header:
    // - No points, or
    // - Has points but followed by a non-unit line (detachment name)
    if (!firstBlockHasPoints) {
      // Definitely header — no points on first line
      headerBlock = blocks[0];
      unitBlocks = blocks.slice(1);
    } else if (blocks[0].length <= 3) {
      // Has points and is short (1-3 lines) — could be header or single unit
      // If there are more blocks with points, treat first as header
      const otherBlocksHaveUnits = blocks.slice(1).some(b =>
        b.length > 0 && isUnitHeader(b[0])
      );
      if (otherBlocksHaveUnits) {
        headerBlock = blocks[0];
        unitBlocks = blocks.slice(1);
      } else {
        // Only block or no other units — treat as unit, no header
        headerBlock = null;
        unitBlocks = blocks;
      }
    } else {
      // First block has points and is long — probably a unit, no separate header
      headerBlock = null;
      unitBlocks = blocks;
    }

    // Parse header
    const header = headerBlock ? parseHeader(headerBlock) : {
      faction: null,
      detachment: null,
      points: null
    };

    // Parse unit blocks
    const units = [];
    for (const block of unitBlocks) {
      // Skip blocks that don't have a unit header as the first line
      if (block.length === 0) continue;

      const firstLine = block[0].trim();

      // If the first line is a unit header (has points), parse it as a unit
      if (isUnitHeader(firstLine)) {
        const unit = parseUnitBlock(block);
        if (unit && unit.name) {
          units.push(unit);
        }
      } else {
        // This block might be a header continuation or something else — skip
        // but log a warning
        errors.push(`Skipped block (no unit header): "${firstLine.substring(0, 50)}..."`);
      }
    }

    // If no explicit points total was found, sum unit points
    if (header.points === null && units.length > 0) {
      let sum = 0;
      for (const u of units) {
        if (u.points) sum += u.points;
      }
      if (sum > 0) header.points = sum;
    }

    return {
      faction: header.faction,
      detachment: header.detachment,
      points: header.points,
      units: units,
      format: 'standard',
      errors: errors
    };
  }

  /**
   * Basic BattleScribe format parser.
   * BattleScribe uses ++ markers for sections:
   *   ++ Battalion Detachment ++
   *   ++ HQ ++
   *   Captain [80 pts]
   *   ++ Troops ++
   *   Intercessor Squad [90 pts]
   *
   * This is a best-effort parser — BattleScribe format varies.
   */
  function parseBattleScribe(text) {
    const lines = text.split('\n');
    const errors = [];
    const units = [];
    let faction = null;
    let detachment = null;
    let points = null;

    for (const line of lines) {
      const trimmed = line.trim();

      // Section headers: ++ Something ++
      if (/^\+\+\s*.+\s*\+\+$/.test(trimmed)) {
        const content = trimmed.replace(/^\+\+\s*/, '').replace(/\s*\+\+$/, '').trim();

        // Check for army/faction line
        if (content.toLowerCase().includes('army') || (!faction && !detachment)) {
          // Try to extract faction
          const ptsMatch = content.match(/\[(\d+)\s*(pts|points)?\]/i);
          if (ptsMatch) {
            points = parseInt(ptsMatch[1], 10);
          }
          const cleanName = content
            .replace(/\[.*?\]/g, '')
            .replace(/\(.*?\)/g, '')
            .trim();
          if (!faction) {
            faction = cleanName;
          } else if (!detachment) {
            detachment = cleanName;
          }
        }
        continue;
      }

      // Unit lines: "Unit Name [Points pts]"
      const unitMatch = trimmed.match(/^(.+?)\s*\[\s*(\d+)\s*(pts|points)?\s*\]/i);
      if (unitMatch) {
        const name = unitMatch[1].trim();
        const pts = parseInt(unitMatch[2], 10);

        // Skip if this looks like an upgrade or wargear
        if (name.startsWith('.') || name.startsWith('-')) continue;

        units.push({
          name: name,
          points: pts,
          wargear: [],
          enhancement: null,
          modelCount: null,
          isWarlord: false,
          matchedDatasheet: null
        });
        continue;
      }

      // Wargear lines (nested under units) — add to last unit
      if (units.length > 0 && (trimmed.startsWith('.') || trimmed.startsWith('-'))) {
        const gear = trimmed.replace(/^[.\-]\s*/, '').replace(/\[.*?\]/g, '').trim();
        if (gear) {
          units[units.length - 1].wargear.push(gear);
        }
      }
    }

    return {
      faction: faction,
      detachment: detachment,
      points: points,
      units: units,
      format: 'battlescribe',
      errors: errors
    };
  }

  // ── Public API ───────────────────────────────────────────────────

  return {
    parse,
    detectFormat,
    normalizeText,

    // Exposed for testing / UI use
    _parseHeader: parseHeader,
    _parseUnitBlock: parseUnitBlock,
    _splitIntoBlocks: splitIntoBlocks,
    _extractPoints: extractPoints,
    _extractName: extractName,
    _isUnitHeader: isUnitHeader,
    _isWargearLine: isWargearLine,
    _isEnhancementLine: isEnhancementLine,
    _parseWargearLine: parseWargearLine,
    _parseEnhancementLine: parseEnhancementLine,
    _extractModelCount: extractModelCount,
  };
})();

// Support both browser globals and Node.js/CommonJS for testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = ArmyParser;
}
