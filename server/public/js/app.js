/**
 * app.js — Army List Uploader UI Logic (Phase 4)
 *
 * Wires together parser.js, datasheets.js, and generator.js
 * to provide the full army upload workflow:
 *   1. User pastes army list text
 *   2. Parse text into structured data
 *   3. Look up units in the datasheet database
 *   4. Show match results with manual override for ambiguous matches
 *   5. Generate game-compatible JSON
 *   6. Download or upload to the game server
 */

const App = (function () {

  // ── State ───────────────────────────────────────────────────────

  let _parsedArmy = null;       // Result from ArmyParser.parse()
  let _generatedResult = null;  // Result from ArmyGenerator.lookupAndGenerate()
  let _dbLoaded = false;
  let _dbLoading = false;
  let _selectedFaction = null;  // For manual faction override

  // ── DOM references (populated on init) ──────────────────────────

  const DOM = {};

  // ── Initialization ──────────────────────────────────────────────

  function init() {
    // Cache DOM references
    DOM.armyText = document.getElementById('army-text');
    DOM.parseBtn = document.getElementById('parse-btn');
    DOM.clearBtn = document.getElementById('clear-btn');
    DOM.sampleBtn = document.getElementById('sample-btn');

    DOM.loadingOverlay = document.getElementById('loading-overlay');
    DOM.dbStatus = document.getElementById('db-status');

    DOM.resultsSection = document.getElementById('results-section');
    DOM.factionName = document.getElementById('faction-name');
    DOM.detachmentName = document.getElementById('detachment-name');
    DOM.totalPoints = document.getElementById('total-points');
    DOM.unitCount = document.getElementById('unit-count');
    DOM.unitList = document.getElementById('unit-list');
    DOM.parseErrors = document.getElementById('parse-errors');

    DOM.jsonSection = document.getElementById('json-section');
    DOM.jsonPreview = document.getElementById('json-preview');
    DOM.jsonToggleBtn = document.getElementById('json-toggle-btn');

    DOM.actionsSection = document.getElementById('actions-section');
    DOM.downloadBtn = document.getElementById('download-btn');
    DOM.uploadBtn = document.getElementById('upload-btn');
    DOM.armyNameInput = document.getElementById('army-name-input');
    DOM.playerIdInput = document.getElementById('player-id-input');
    DOM.uploadStatus = document.getElementById('upload-status');

    DOM.factionOverride = document.getElementById('faction-override');

    // Bind events
    DOM.parseBtn.addEventListener('click', handleParse);
    DOM.clearBtn.addEventListener('click', handleClear);
    DOM.sampleBtn.addEventListener('click', handleSample);
    DOM.downloadBtn.addEventListener('click', handleDownload);
    DOM.uploadBtn.addEventListener('click', handleUpload);
    DOM.jsonToggleBtn.addEventListener('click', handleJsonToggle);
    DOM.factionOverride.addEventListener('change', handleFactionOverride);

    // Restore player ID from localStorage
    const savedPlayerId = localStorage.getItem('w40k_player_id');
    if (savedPlayerId) {
      DOM.playerIdInput.value = savedPlayerId;
    }

    // Save player ID on change
    DOM.playerIdInput.addEventListener('change', () => {
      localStorage.setItem('w40k_player_id', DOM.playerIdInput.value.trim());
    });

    // Load the datasheet database
    loadDatabase();
  }

  // ── Database loading ────────────────────────────────────────────

  async function loadDatabase() {
    if (_dbLoaded || _dbLoading) return;
    _dbLoading = true;

    showLoading('Loading unit database...');

    try {
      await Datasheets.load('/data/datasheets.json');
      _dbLoaded = true;
      _dbLoading = false;

      // Populate faction override dropdown
      populateFactionDropdown();

      hideLoading();
      setDbStatus('Database loaded — ' + Datasheets.getFactionNames().length + ' factions available', 'success');
    } catch (err) {
      _dbLoading = false;
      hideLoading();
      setDbStatus('Failed to load database: ' + err.message, 'error');
      console.error('Database load error:', err);
    }
  }

  function populateFactionDropdown() {
    const factions = Datasheets.getFactionNames();
    DOM.factionOverride.innerHTML = '<option value="">Auto-detect from text</option>';
    for (const faction of factions.sort()) {
      const opt = document.createElement('option');
      opt.value = faction;
      opt.textContent = faction;
      DOM.factionOverride.appendChild(opt);
    }
  }

  // ── Parse handler ───────────────────────────────────────────────

  function handleParse() {
    const text = DOM.armyText.value;
    if (!text.trim()) {
      showParseErrors(['Please paste an army list first.']);
      return;
    }

    if (!_dbLoaded) {
      showParseErrors(['Database not loaded yet. Please wait.']);
      return;
    }

    // Step 1: Parse the text
    _parsedArmy = ArmyParser.parse(text);

    // Apply faction override if set
    if (_selectedFaction) {
      _parsedArmy.faction = _selectedFaction;
    }

    // Step 2: Look up units and generate
    _generatedResult = ArmyGenerator.lookupAndGenerate(_parsedArmy, null, {
      owner: 1,
      includeUnmatched: true
    });

    // Step 3: Render results
    renderResults();
  }

  // ── Render results ──────────────────────────────────────────────

  function renderResults() {
    if (!_parsedArmy || !_generatedResult) return;

    const army = _generatedResult.army;
    const matchResults = _generatedResult.matchResults || [];
    const allErrors = [
      ...(_parsedArmy.errors || []),
      ...(_generatedResult.errors || []),
      ...(_generatedResult.warnings || [])
    ];

    // Header info
    DOM.factionName.textContent = _parsedArmy.faction || 'Unknown';
    DOM.detachmentName.textContent = _parsedArmy.detachment || 'None';
    DOM.totalPoints.textContent = (_parsedArmy.points || 0) + ' pts';
    DOM.unitCount.textContent = _parsedArmy.units.length + ' units';

    // Set faction dropdown to match detected faction
    if (_parsedArmy.faction && !_selectedFaction) {
      const factionNames = Datasheets.getFactionNames();
      const match = factionNames.find(f =>
        f.toLowerCase() === _parsedArmy.faction.toLowerCase()
      );
      if (match) {
        DOM.factionOverride.value = match;
      }
    }

    // Unit list
    renderUnitList(matchResults);

    // Errors
    if (allErrors.length > 0) {
      showParseErrors(allErrors);
    } else {
      hideParseErrors();
    }

    // JSON preview
    renderJsonPreview();

    // Set default army name
    if (!DOM.armyNameInput.value && _parsedArmy.faction) {
      const faction = _parsedArmy.faction.replace(/\s+/g, '_');
      DOM.armyNameInput.value = faction + '_' + (_parsedArmy.points || 'custom');
    }

    // Show sections
    DOM.resultsSection.classList.remove('hidden');
    DOM.jsonSection.classList.remove('hidden');
    DOM.actionsSection.classList.remove('hidden');
  }

  function renderUnitList(matchResults) {
    DOM.unitList.innerHTML = '';

    for (let i = 0; i < _parsedArmy.units.length; i++) {
      const parsedUnit = _parsedArmy.units[i];
      const matchResult = matchResults[i] || {};

      const li = document.createElement('li');
      li.className = 'unit-item';

      // Status icon
      const statusIcon = document.createElement('span');
      statusIcon.className = 'unit-status';

      let matchClass = '';
      let matchLabel = '';

      switch (matchResult.matchType) {
        case 'exact':
          matchClass = 'match-exact';
          matchLabel = 'Matched';
          statusIcon.textContent = '\u2713'; // checkmark
          break;
        case 'fuzzy_auto':
          matchClass = 'match-fuzzy';
          matchLabel = 'Fuzzy match';
          statusIcon.textContent = '\u2248'; // approximately equal
          break;
        case 'fuzzy_ambiguous':
          matchClass = 'match-ambiguous';
          matchLabel = 'Ambiguous';
          statusIcon.textContent = '?';
          break;
        case 'none':
        default:
          matchClass = 'match-none';
          matchLabel = 'Not found';
          statusIcon.textContent = '\u2717'; // cross
          break;
      }

      statusIcon.classList.add(matchClass);
      li.appendChild(statusIcon);

      // Unit info
      const info = document.createElement('div');
      info.className = 'unit-info';

      const nameSpan = document.createElement('span');
      nameSpan.className = 'unit-name';
      nameSpan.textContent = parsedUnit.name;
      info.appendChild(nameSpan);

      const pointsSpan = document.createElement('span');
      pointsSpan.className = 'unit-points';
      pointsSpan.textContent = (parsedUnit.points || 0) + ' pts';
      info.appendChild(pointsSpan);

      const matchSpan = document.createElement('span');
      matchSpan.className = 'unit-match-label ' + matchClass;
      matchSpan.textContent = matchLabel;
      if (matchResult.matchedName && matchResult.matchedName !== parsedUnit.name) {
        matchSpan.textContent += ' \u2192 ' + matchResult.matchedName;
      }
      info.appendChild(matchSpan);

      // Wargear preview
      if (parsedUnit.wargear.length > 0) {
        const gearDiv = document.createElement('div');
        gearDiv.className = 'unit-wargear';
        gearDiv.textContent = parsedUnit.wargear.join(', ');
        info.appendChild(gearDiv);
      }

      // Enhancement
      if (parsedUnit.enhancement) {
        const enhDiv = document.createElement('div');
        enhDiv.className = 'unit-enhancement';
        enhDiv.textContent = 'Enhancement: ' + parsedUnit.enhancement;
        info.appendChild(enhDiv);
      }

      li.appendChild(info);

      // Ambiguous match candidates dropdown
      if (matchResult.matchType === 'fuzzy_ambiguous' && matchResult.candidates.length > 0) {
        const select = document.createElement('select');
        select.className = 'unit-candidate-select';
        select.dataset.unitIndex = i;

        const defaultOpt = document.createElement('option');
        defaultOpt.value = '';
        defaultOpt.textContent = 'Select match...';
        select.appendChild(defaultOpt);

        for (const candidate of matchResult.candidates) {
          const opt = document.createElement('option');
          opt.value = candidate.name;
          opt.textContent = candidate.name + ' (' + Math.round(candidate.score * 100) + '% match)';
          select.appendChild(opt);
        }

        select.addEventListener('change', (e) => {
          handleCandidateSelect(parseInt(e.target.dataset.unitIndex), e.target.value);
        });

        li.appendChild(select);
      }

      // "Not found" match candidates (show as search)
      if (matchResult.matchType === 'none') {
        const searchBtn = document.createElement('button');
        searchBtn.className = 'btn btn-small';
        searchBtn.textContent = 'Search DB';
        searchBtn.addEventListener('click', () => {
          handleSearchUnit(i, parsedUnit.name);
        });
        li.appendChild(searchBtn);
      }

      DOM.unitList.appendChild(li);
    }
  }

  // ── Candidate selection handler ─────────────────────────────────

  function handleCandidateSelect(unitIndex, selectedName) {
    if (!_parsedArmy || !selectedName) return;

    const faction = _parsedArmy.faction || '';
    const datasheet = Datasheets.getUnit(faction, selectedName);

    if (datasheet) {
      _parsedArmy.units[unitIndex].matchedDatasheet = datasheet;
      // Regenerate
      _generatedResult = ArmyGenerator.lookupAndGenerate(_parsedArmy, null, {
        owner: 1,
        includeUnmatched: true
      });
      renderResults();
    }
  }

  // ── Search unit in DB ───────────────────────────────────────────

  function handleSearchUnit(unitIndex, query) {
    const results = Datasheets.fuzzySearchAllFactions(query, {
      maxResults: 10,
      minScore: 0.2
    });

    if (results.length === 0) {
      alert('No matches found for "' + query + '" in any faction.');
      return;
    }

    // Show results in a simple dialog
    let msg = 'Matches for "' + query + '":\n\n';
    for (let i = 0; i < results.length; i++) {
      msg += (i + 1) + '. ' + results[i].name + ' (' + results[i].faction + ') — ' +
        Math.round(results[i].score * 100) + '% match\n';
    }
    msg += '\nEnter the number to select (or cancel):';

    const choice = prompt(msg);
    if (!choice) return;

    const idx = parseInt(choice, 10) - 1;
    if (idx >= 0 && idx < results.length) {
      const selected = results[idx];
      _parsedArmy.units[unitIndex].matchedDatasheet = selected.unit;
      // If faction was auto-detected and this is a different faction, warn
      if (_parsedArmy.faction && selected.faction !== _parsedArmy.faction) {
        _parsedArmy.faction = selected.faction;
      }
      _generatedResult = ArmyGenerator.lookupAndGenerate(_parsedArmy, null, {
        owner: 1,
        includeUnmatched: true
      });
      renderResults();
    }
  }

  // ── Faction override handler ────────────────────────────────────

  function handleFactionOverride() {
    _selectedFaction = DOM.factionOverride.value || null;
    // Re-parse if we already have text
    if (_parsedArmy) {
      handleParse();
    }
  }

  // ── JSON preview ────────────────────────────────────────────────

  function renderJsonPreview() {
    if (!_generatedResult || !_generatedResult.army) return;
    const json = JSON.stringify(_generatedResult.army, null, 2);
    DOM.jsonPreview.textContent = json;
  }

  function handleJsonToggle() {
    DOM.jsonPreview.classList.toggle('collapsed');
    const isCollapsed = DOM.jsonPreview.classList.contains('collapsed');
    DOM.jsonToggleBtn.textContent = isCollapsed ? 'Expand JSON' : 'Collapse JSON';
  }

  // ── Download handler ────────────────────────────────────────────

  function handleDownload() {
    if (!_generatedResult || !_generatedResult.army) {
      alert('No army to download. Parse an army list first.');
      return;
    }

    const json = JSON.stringify(_generatedResult.army, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    const name = DOM.armyNameInput.value.trim() || 'army';
    a.download = name.replace(/[^a-zA-Z0-9_-]/g, '_') + '.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  // ── Upload handler ──────────────────────────────────────────────

  async function handleUpload() {
    if (!_generatedResult || !_generatedResult.army) {
      setUploadStatus('No army to upload. Parse an army list first.', 'error');
      return;
    }

    const playerId = DOM.playerIdInput.value.trim();
    if (!playerId || playerId.length < 8) {
      setUploadStatus('Please enter your Player ID (at least 8 characters). Find it in-game under Settings.', 'error');
      return;
    }

    const armyName = DOM.armyNameInput.value.trim();
    if (!armyName) {
      setUploadStatus('Please enter an army name.', 'error');
      return;
    }

    // Validate the generated army
    const validation = ArmyGenerator.validateArmy(_generatedResult.army);
    if (!validation.valid) {
      setUploadStatus('Army validation failed: ' + validation.errors.join(', '), 'error');
      return;
    }

    setUploadStatus('Uploading...', 'info');
    DOM.uploadBtn.disabled = true;

    try {
      const response = await fetch('/api/armies/' + encodeURIComponent(armyName), {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'X-Player-ID': playerId
        },
        body: JSON.stringify({
          army_data: _generatedResult.army
        })
      });

      if (!response.ok) {
        const errData = await response.json().catch(() => ({}));
        throw new Error(errData.error || 'Server returned ' + response.status);
      }

      const data = await response.json();
      setUploadStatus(
        'Army "' + armyName + '" uploaded successfully! It will appear in your game\'s army selection.',
        'success'
      );

      // Save player ID
      localStorage.setItem('w40k_player_id', playerId);
    } catch (err) {
      setUploadStatus('Upload failed: ' + err.message, 'error');
    } finally {
      DOM.uploadBtn.disabled = false;
    }
  }

  // ── Clear handler ───────────────────────────────────────────────

  function handleClear() {
    DOM.armyText.value = '';
    _parsedArmy = null;
    _generatedResult = null;

    DOM.resultsSection.classList.add('hidden');
    DOM.jsonSection.classList.add('hidden');
    DOM.actionsSection.classList.add('hidden');
    hideParseErrors();
    DOM.armyNameInput.value = '';
    setUploadStatus('', '');
  }

  // ── Sample army list ────────────────────────────────────────────

  function handleSample() {
    DOM.armyText.value = `Space Marines (1000 pts)
Gladius Task Force

Intercessor Squad (90 pts)
\u2022 Bolt rifle
\u2022 Bolt pistol
\u2022 Astartes grenade launcher

Intercessor Squad (90 pts)
\u2022 Bolt rifle
\u2022 Bolt pistol

Bladeguard Veterans (100 pts)
\u2022 Master-crafted power sword
\u2022 Storm shield
\u2022 Heavy bolt pistol

Captain in Terminator Armour (105 pts)
\u2022 Storm bolter
\u2022 Relic weapon
\u2022 Enhancement: Adept of the Codex
Warlord

Infernus Squad (90 pts)
\u2022 Pyreblaster
\u2022 Bolt pistol
\u2022 Close combat weapon

Ballistus Dreadnought (140 pts)
\u2022 Ballistus lascannon
\u2022 Ballistus missile launcher
\u2022 Twin storm bolter
\u2022 Armoured feet`;
  }

  // ── UI helpers ──────────────────────────────────────────────────

  function showLoading(message) {
    if (DOM.loadingOverlay) {
      DOM.loadingOverlay.classList.remove('hidden');
      DOM.loadingOverlay.textContent = message || 'Loading...';
    }
  }

  function hideLoading() {
    if (DOM.loadingOverlay) {
      DOM.loadingOverlay.classList.add('hidden');
    }
  }

  function setDbStatus(message, type) {
    if (DOM.dbStatus) {
      DOM.dbStatus.textContent = message;
      DOM.dbStatus.className = 'db-status db-status-' + type;
    }
  }

  function showParseErrors(errors) {
    if (DOM.parseErrors) {
      DOM.parseErrors.innerHTML = '';
      for (const err of errors) {
        const div = document.createElement('div');
        div.className = 'parse-error-item';
        div.textContent = err;
        DOM.parseErrors.appendChild(div);
      }
      DOM.parseErrors.classList.remove('hidden');
    }
  }

  function hideParseErrors() {
    if (DOM.parseErrors) {
      DOM.parseErrors.innerHTML = '';
      DOM.parseErrors.classList.add('hidden');
    }
  }

  function setUploadStatus(message, type) {
    if (DOM.uploadStatus) {
      DOM.uploadStatus.textContent = message;
      DOM.uploadStatus.className = 'upload-status upload-status-' + type;
    }
  }

  // ── Public API ───────────────────────────────────────────────────

  return {
    init
  };
})();

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', App.init);
