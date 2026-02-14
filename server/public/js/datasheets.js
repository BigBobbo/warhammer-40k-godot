/**
 * datasheets.js — Datasheet database loader and lookup utilities
 *
 * Loads the datasheets.json database and provides functions for:
 * - Loading faction data (lazy per-faction or full)
 * - Looking up units by exact name
 * - Fuzzy-matching unit names against the database
 * - Listing available factions and units
 */

const Datasheets = (function () {
  // Internal state
  let _db = null;         // Full datasheets.json once loaded
  let _loading = false;
  let _loadPromise = null;

  // ── Loading ──────────────────────────────────────────────────────

  /**
   * Load the full datasheets database from the server.
   * Returns a promise that resolves with the parsed DB object.
   * Caches after the first successful load.
   */
  async function load(url) {
    if (_db) return _db;
    if (_loadPromise) return _loadPromise;

    _loading = true;
    _loadPromise = fetch(url || '/data/datasheets.json')
      .then(res => {
        if (!res.ok) throw new Error(`Failed to load datasheets: ${res.status}`);
        return res.json();
      })
      .then(data => {
        _db = data;
        _loading = false;
        return _db;
      })
      .catch(err => {
        _loading = false;
        _loadPromise = null;
        throw err;
      });

    return _loadPromise;
  }

  /**
   * Returns true if the DB has been loaded.
   */
  function isLoaded() {
    return _db !== null;
  }

  /**
   * Returns the raw DB object. Throws if not yet loaded.
   */
  function getDB() {
    if (!_db) throw new Error('Datasheets not loaded. Call Datasheets.load() first.');
    return _db;
  }

  // ── Faction queries ──────────────────────────────────────────────

  /**
   * Returns an array of faction names available in the DB.
   */
  function getFactionNames() {
    const db = getDB();
    return Object.keys(db.factions || {});
  }

  /**
   * Returns the faction object for a given faction name, or null.
   */
  function getFaction(factionName) {
    const db = getDB();
    if (!db.factions) return null;

    // Try exact match first
    if (db.factions[factionName]) return db.factions[factionName];

    // Try case-insensitive match
    const lower = factionName.toLowerCase();
    for (const key of Object.keys(db.factions)) {
      if (key.toLowerCase() === lower) return db.factions[key];
    }

    return null;
  }

  // ── Unit queries ─────────────────────────────────────────────────

  /**
   * Look up a unit by exact name within a faction.
   * Returns the unit datasheet object or null.
   */
  function getUnit(factionName, unitName) {
    const faction = getFaction(factionName);
    if (!faction || !faction.units) return null;

    // Try exact match
    if (faction.units[unitName]) return faction.units[unitName];

    // Try case-insensitive match
    const lower = unitName.toLowerCase();
    for (const key of Object.keys(faction.units)) {
      if (key.toLowerCase() === lower) return faction.units[key];
    }

    return null;
  }

  /**
   * List all unit names in a faction.
   */
  function getUnitNames(factionName) {
    const faction = getFaction(factionName);
    if (!faction || !faction.units) return [];
    return Object.keys(faction.units);
  }

  // ── Fuzzy matching ───────────────────────────────────────────────

  /**
   * Compute Levenshtein distance between two strings.
   */
  function levenshtein(a, b) {
    const m = a.length;
    const n = b.length;
    if (m === 0) return n;
    if (n === 0) return m;

    const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
    for (let i = 0; i <= m; i++) dp[i][0] = i;
    for (let j = 0; j <= n; j++) dp[0][j] = j;

    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        dp[i][j] = Math.min(
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost
        );
      }
    }
    return dp[m][n];
  }

  /**
   * Normalize a unit name for comparison:
   * lowercase, strip "squad" / "unit" suffixes, remove articles.
   */
  function normalizeName(name) {
    return name
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .trim()
      .replace(/\bsquad\b/g, '')
      .replace(/\bunit\b/g, '')
      .replace(/\bthe\b/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Compute a token-based similarity score between two strings.
   * Returns a value 0-1, where 1 is a perfect match.
   */
  function tokenSimilarity(a, b) {
    const tokensA = new Set(normalizeName(a).split(' ').filter(Boolean));
    const tokensB = new Set(normalizeName(b).split(' ').filter(Boolean));

    if (tokensA.size === 0 && tokensB.size === 0) return 1;
    if (tokensA.size === 0 || tokensB.size === 0) return 0;

    let intersection = 0;
    for (const t of tokensA) {
      if (tokensB.has(t)) intersection++;
    }

    // Jaccard similarity
    const union = new Set([...tokensA, ...tokensB]).size;
    return intersection / union;
  }

  /**
   * Compute a combined similarity score. Higher is better.
   * Uses both Levenshtein distance and token overlap.
   */
  function similarityScore(query, candidate) {
    const nq = normalizeName(query);
    const nc = normalizeName(candidate);

    // Exact normalized match
    if (nq === nc) return 1.0;

    // Substring containment (one contains the other)
    if (nc.includes(nq) || nq.includes(nc)) return 0.9;

    // Token similarity
    const tokenSim = tokenSimilarity(query, candidate);

    // Levenshtein-based similarity (normalized)
    const maxLen = Math.max(nq.length, nc.length);
    const levDist = levenshtein(nq, nc);
    const levSim = maxLen === 0 ? 1 : 1 - levDist / maxLen;

    // Weighted combination: tokens matter more than raw edit distance
    return 0.6 * tokenSim + 0.4 * levSim;
  }

  /**
   * Fuzzy-match a query name against all units in a faction.
   * Returns an array of { unit, name, score } sorted by score descending.
   * Only includes results above the minimum threshold.
   */
  function fuzzyMatchUnit(factionName, query, options) {
    const opts = Object.assign({ maxResults: 5, minScore: 0.3 }, options || {});
    const faction = getFaction(factionName);
    if (!faction || !faction.units) return [];

    const results = [];
    for (const unitName of Object.keys(faction.units)) {
      const score = similarityScore(query, unitName);
      if (score >= opts.minScore) {
        results.push({
          name: unitName,
          unit: faction.units[unitName],
          score: score
        });
      }
    }

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, opts.maxResults);
  }

  /**
   * Search all factions for a unit by fuzzy name match.
   * Returns { faction, name, unit, score } array.
   */
  function fuzzySearchAllFactions(query, options) {
    const opts = Object.assign({ maxResults: 10, minScore: 0.3 }, options || {});
    const results = [];

    for (const factionName of getFactionNames()) {
      const matches = fuzzyMatchUnit(factionName, query, {
        maxResults: opts.maxResults,
        minScore: opts.minScore
      });
      for (const match of matches) {
        results.push({
          faction: factionName,
          name: match.name,
          unit: match.unit,
          score: match.score
        });
      }
    }

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, opts.maxResults);
  }

  // ── Public API ───────────────────────────────────────────────────

  return {
    load,
    isLoaded,
    getDB,
    getFactionNames,
    getFaction,
    getUnit,
    getUnitNames,
    fuzzyMatchUnit,
    fuzzySearchAllFactions,
    // Exposed for testing
    _normalizeName: normalizeName,
    _similarityScore: similarityScore,
    _levenshtein: levenshtein,
    _tokenSimilarity: tokenSimilarity,
  };
})();

// Support both browser globals and Node.js/CommonJS for testing
if (typeof module !== 'undefined' && module.exports) {
  module.exports = Datasheets;
}
