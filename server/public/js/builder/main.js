// Army builder — main view. Renders the whole app from store state; every
// mutation goes through store.js which re-notifies.

import * as S from './store.js';
import * as UI from './ui.js';
import { h, clear, select, stepper } from './ui.js';
import { openImportDialog, openCloudDialog, openExportDialog } from './dialogs.js';
import { initPlayerId } from './api.js';

const app = document.getElementById('app');
let unitQuery = '';

// ---------------------------------------------------------------------------
// Render root

function render() {
  // Preserve focus/caret across full re-renders (text inputs re-created).
  const active = document.activeElement;
  const focusId = active?.id;
  const caret = (focusId && 'selectionStart' in (active ?? {})) ? active.selectionStart : null;

  clear(app);
  app.append(renderTopbar(), renderColumns(), renderStatus());

  if (focusId) {
    const el = document.getElementById(focusId);
    if (el) {
      el.focus();
      if (caret !== null && 'setSelectionRange' in el) {
        try { el.setSelectionRange(caret, caret); } catch (e) { /* non-text input */ }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Topbar

function renderTopbar() {
  const r = S.state.roster;
  const total = S.totalPoints();
  const limit = r.points.declared_limit ?? 0;
  const over = limit && total > limit;

  const factions = S.factionList();
  const factionOptions = [
    { value: '', label: '— pick faction —', disabled: true },
    ...factions.map(f => ({ value: f.id, label: f.supported ? f.name : `${f.name} ◦` })),
  ];

  const detachments = r.faction_id ? S.detachmentList(r.faction_id) : [];
  const currentDet = r.detachments[0]?.ref?.id ?? '';

  return h('header.topbar', {},
    h('div.topbar-row', {},
      h('span.brand', {}, 'W40K ', h('b', {}, 'Army Builder')),
      h('input.army-name#army-name-input', {
        value: r.name,
        placeholder: 'Army name',
        oninput: (e) => S.setName(e.target.value),
      }),
      h('span.points-badge', { class: over ? 'points-badge over' : 'points-badge' },
        `${total} / ${limit || '—'} pts`),
      h('span.spacer'),
      h('button.btn.btn-secondary', { onclick: onNew }, 'New'),
      h('button.btn.btn-secondary', { onclick: () => openImportDialog() }, 'Import'),
      h('button.btn.btn-secondary', { onclick: () => openCloudDialog() }, 'My Lists'),
      h('button.btn.btn-primary', { onclick: () => openExportDialog() }, 'Export / Save'),
    ),
    h('div.topbar-row.topbar-config', {},
      h('label', {}, 'Faction',
        select(factionOptions, r.faction_id ?? '', onFactionChange)),
      h('label', {}, 'Detachment',
        select(
          detachments.length
            ? detachments.map(d => ({ value: d.id, label: `${d.name} (${d.detachment_points ?? 1} DP)` }))
            : [{ value: '', label: '—' }],
          currentDet,
          (v) => S.setDetachment(v),
          { disabled: !detachments.length })),
      h('label', {}, 'Points',
        select([
          { value: '1000', label: '1000 (Incursion)' },
          { value: '2000', label: '2000 (Strike Force)' },
        ], String(r.points.declared_limit ?? 2000), (v) => S.setPointsLimit(parseInt(v, 10)))),
      h('label', {}, 'Disposition',
        select([
          { value: '', label: '— none —' },
          ...S.forceDispositions().map(fd => ({ value: fd.id, label: fd.name })),
        ], r.force_disposition ?? '', (v) => S.setForceDisposition(v))),
      r.faction_id && !S.FULLY_SUPPORTED_FACTIONS.has(r.faction_id)
        ? h('span.support-note', { title: 'Datasheets, weapons and core abilities work in-game; this faction\'s army rule, detachment rules and stratagems are not automated yet.' },
          '◦ limited in-game rules automation')
        : null,
    ),
  );
}

function onNew() {
  if (S.state.roster.units.length &&
      !confirm('Start a new list? The current list stays in your browser draft until replaced.')) return;
  S.resetRoster();
}

function onFactionChange(fid) {
  if (S.state.roster.units.length &&
      !confirm('Changing faction clears the current roster. Continue?')) {
    render(); // reset the select back
    return;
  }
  S.setFaction(fid);
}

// ---------------------------------------------------------------------------
// Columns

function renderColumns() {
  return h('div.columns', {},
    renderBrowser(),
    renderRoster(),
    renderEditor(),
  );
}

// --- unit browser -----------------------------------------------------------

function renderBrowser() {
  const r = S.state.roster;
  const pane = h('aside.pane.browser-pane');
  if (!r.faction_id) {
    pane.append(h('div.pane-empty', {},
      h('p', {}, 'Pick a faction to browse datasheets.'),
      h('p.hint', {}, 'Or use Import to load an existing list — pasted text or a saved JSON.')));
    return pane;
  }
  pane.append(h('input.search#unit-search', {
    value: unitQuery,
    placeholder: 'Search datasheets…',
    oninput: (e) => { unitQuery = e.target.value; render(); },
  }));
  const groups = S.unitBrowserGroups(unitQuery);
  const list = h('div.browser-list');
  for (const g of groups) {
    list.append(h('div.browser-group', {}, g.label));
    for (const raw of g.units) {
      const minPts = S.dc.baseUnitPoints(raw, S.sizeChoices(raw)[0], 1);
      list.append(h('div.browser-unit', {
        onclick: () => S.addUnit(raw.id, raw.faction_id !== r.faction_id ? raw.faction_id : null),
        title: `Add ${raw.name}`,
      },
        h('span.bu-name', {}, raw.name, raw.is_legend ? h('span.legend-tag', {}, ' Legends') : null),
        h('span.bu-pts', {}, `${minPts}`),
        h('span.bu-add', {}, '+')));
    }
  }
  if (!groups.length) list.append(h('div.pane-empty', {}, 'No datasheets match.'));
  pane.append(list);
  return pane;
}

// --- roster list ------------------------------------------------------------

function renderRoster() {
  const r = S.state.roster;
  const pane = h('main.pane.roster-pane');
  const list = h('div.roster-list');

  if (!r.units.length) {
    list.append(h('div.pane-empty', {}, 'No units yet — add datasheets from the left.'));
  }

  const legality = S.legality();
  const unitViolations = new Map();
  for (const ul of legality.units) {
    if (ul.violations.length) unitViolations.set(ul.unitIndex, ul.violations);
  }
  const armyUnitIssues = new Map();
  for (const v of legality.army) {
    if (v.unitIndex !== null) {
      if (!armyUnitIssues.has(v.unitIndex)) armyUnitIssues.set(v.unitIndex, []);
      armyUnitIssues.get(v.unitIndex).push(v);
    }
  }

  r.units.forEach((ru, i) => {
    const issues = (unitViolations.get(i)?.length ?? 0) + (armyUnitIssues.get(i)?.length ?? 0);
    const row = h('div.roster-unit', {
      class: 'roster-unit' + (i === S.state.selectedUnit ? ' selected' : '') + (ru.ref.resolved ? '' : ' unresolved'),
      onclick: () => S.selectUnit(i),
    },
      h('div.ru-line1', {},
        h('span.ru-name', {}, ru.ref.raw_name || ru.ref.id || '?'),
        ru.is_warlord ? h('span.ru-tag.warlord', { title: 'Warlord' }, '★') : null,
        ru.enhancement ? h('span.ru-tag.enh', { title: `Enhancement: ${ru.enhancement.raw_name ?? ''}` }, '✦') : null,
        ru.leader_attachment ? h('span.ru-tag.lead', { title: `Leading ${ru.leader_attachment.bodyguard_ref?.raw_name ?? ''}` }, '⇒') : null,
        issues ? h('span.ru-tag.issue', { title: `${issues} rule issue(s)` }, '!') : null,
        h('span.spacer'),
        h('span.ru-pts', {}, `${(ru.points ?? 0) + (ru.enhancement_points ?? 0)} pts`)),
      h('div.ru-line2', {},
        h('span', {}, `${ru.model_count} model${ru.model_count === 1 ? '' : 's'}`),
        ru.ref.resolved ? null : h('span.unresolved-note', {}, ' · no datasheet match'),
        h('span.spacer'),
        h('button.btn-icon', {
          title: 'Duplicate', onclick: (e) => { e.stopPropagation(); S.duplicateUnit(i); },
        }, '⧉'),
        h('button.btn-icon', {
          title: 'Remove', onclick: (e) => { e.stopPropagation(); S.removeUnit(i); },
        }, '✕')));
    list.append(row);
  });

  pane.append(list, renderValidation(legality));
  return pane;
}

function renderValidation(legality) {
  const r = S.state.roster;
  const box = h('div.validation');
  const items = [];

  for (const v of legality.army) {
    items.push({ sev: v.severity, text: v.message });
  }
  for (const ul of legality.units) {
    for (const v of ul.violations) {
      const name = r.units[ul.unitIndex]?.ref?.raw_name ?? ul.unitId;
      items.push({ sev: 'error', text: `${name}: ${v.message}` });
    }
  }
  for (const ru of r.units) {
    if (ru._tier_missing) {
      items.push({ sev: 'warn', text: `${ru.ref.raw_name}: ${ru.model_count} models is not a purchasable size` });
    }
    if (!ru.ref.resolved) {
      items.push({ sev: 'warn', text: `${ru.ref.raw_name}: not matched to a datasheet — select it to fix` });
    }
  }
  if (S.state.importReport?.warnings?.length) {
    items.push({ sev: 'info', text: `${S.state.importReport.title} — ${S.state.importReport.warnings.length} note(s)`, details: S.state.importReport.warnings });
  }

  if (!items.length) {
    box.append(h('div.validation-ok', {}, '✓ List is legal'));
    return box;
  }
  const summary = h('details.validation-details', { open: items.some(i => i.sev === 'error') },
    h('summary', {},
      `${items.filter(i => i.sev === 'error').length} error(s), ` +
      `${items.filter(i => i.sev === 'warn').length} warning(s)`),
    h('ul', {}, items.map(i =>
      h('li', { class: `sev-${i.sev}` },
        i.text,
        i.details ? h('ul', {}, i.details.map(d => h('li.sev-info', {}, d))) : null))));
  box.append(summary);
  return box;
}

// --- unit editor ------------------------------------------------------------

function renderEditor() {
  const pane = h('section.pane.editor-pane');
  const i = S.state.selectedUnit;
  const ru = S.state.roster.units[i];
  if (!ru) {
    pane.append(h('div.pane-empty', {}, 'Select a unit to edit its size, wargear and enhancement.'));
    return pane;
  }
  if (!ru.ref.resolved) {
    pane.append(renderUnresolvedEditor(i, ru));
    return pane;
  }
  const data = S.unitData(ru.ref.id, ru._unit_faction_id);
  if (!data) {
    pane.append(h('div.pane-empty', {}, 'Datasheet not found in the dataset.'));
    return pane;
  }
  const { raw } = data;
  const prof = raw.profiles[0];

  // h() skips null children; native Element.append would stringify them.
  pane.append(h('div', {},
    h('div.editor-header', {},
      h('h2', {}, raw.name),
      h('span.spacer'),
      h('span.editor-pts', {}, `${(ru.points ?? 0) + (ru.enhancement_points ?? 0)} pts`)),

    // statline
    h('table.statline', {},
      h('tr', {}, ['M', 'T', 'Sv', 'W', 'Ld', 'OC'].map(s => h('th', {}, s))),
      h('tr', {},
        h('td', {}, `${prof.M}"`),
        h('td', {}, String(prof.T)),
        h('td', {}, `${prof.Sv}+${prof.invuln_sv ? ` / ${prof.invuln_sv}++` : ''}`),
        h('td', {}, String(prof.W)),
        h('td', {}, `${prof.Ld}+`),
        h('td', {}, String(prof.OC)))),

    renderSizeRow(i, ru, data),
    renderWarlordRow(i, ru, raw),
    renderEnhancementRow(i, ru, raw),
    renderLeaderRow(i, ru),
    renderLoadout(i, ru, data),
    renderAbilities(data),
  ));
  return pane;
}

function renderUnresolvedEditor(i, ru) {
  const { candidatesFor } = window.__builderImporters ?? {};
  const cands = ru.ref.candidates?.length
    ? ru.ref.candidates
    : (candidatesFor ? candidatesFor(S.state.roster.faction_id, ru.ref.raw_name) : []);
  return h('div', {},
    h('div.editor-header', {}, h('h2', {}, ru.ref.raw_name)),
    h('p.unresolved-note', {},
      'This unit could not be matched to an 11th-edition datasheet. ',
      ru._raw_game_unit
        ? 'It will be exported to the game exactly as imported.'
        : 'It will be skipped on export unless you match it below.'),
    cands.length
      ? h('div.field-row', {},
        h('label', {}, 'Replace with datasheet'),
        select([{ value: '', label: '— choose —' }, ...cands.map(c => ({ value: c.id, label: c.name }))],
          '', (v) => { if (v) S.resolveUnitTo(i, v); }))
      : h('p.hint', {}, 'No close datasheet matches found — remove the unit or re-add it from the browser.'),
  );
}

function renderSizeRow(i, ru, data) {
  const sizes = S.sizeChoices(data.raw);
  if (sizes.length <= 1) {
    return h('div.field-row', {}, h('label', {}, 'Models'), h('span', {}, String(ru.model_count)));
  }
  const ordinal = 1; // display uses first-copy pricing; store reprices exactly
  return h('div.field-row', {},
    h('label', {}, 'Models'),
    select(sizes.map(s => ({
      value: String(s),
      label: `${s} models — ${S.dc.baseUnitPoints(data.raw, s, ordinal)} pts`,
    })), String(ru.model_count), (v) => S.setModelCount(i, parseInt(v, 10))));
}

function renderWarlordRow(i, ru, raw) {
  const isCharacter = (raw.keywords ?? []).some(k => k.toLowerCase() === 'character');
  if (!isCharacter) return null;
  return h('div.field-row', {},
    h('label', {}, 'Warlord'),
    h('input', {
      type: 'checkbox',
      checked: ru.is_warlord,
      onchange: (e) => { if (e.target.checked) S.setWarlord(i); else { ru.is_warlord = false; S.notify(); } },
    }));
}

function renderEnhancementRow(i, ru, raw) {
  const isCharacter = (raw.keywords ?? []).some(k => k.toLowerCase() === 'character');
  const isEpic = (raw.keywords ?? []).some(k => k.toLowerCase() === 'epic hero');
  const choices = S.enhancementChoices();
  if (!choices.length) return null;
  if (!isCharacter || isEpic) return null; // enhancements: non-epic characters
  const current = ru.enhancement?.id ?? '';
  return h('div.field-row', {},
    h('label', {}, 'Enhancement'),
    select([
      { value: '', label: '— none —' },
      ...choices.map(c => ({
        value: c.id,
        label: `${c.name} (${c.cost} pts)` + (c.takenBy !== null && c.takenBy !== i ? ' — taken' : ''),
        disabled: c.takenBy !== null && c.takenBy !== i,
      })),
    ], current, (v) => S.setEnhancement(i, v || null)));
}

function renderLeaderRow(i, ru) {
  const bodyguards = S.eligibleBodyguards(ru);
  if (!bodyguards.length) return null;
  return h('div.field-row', {},
    h('label', {}, 'Leads'),
    select([
      { value: '', label: '— not attached —' },
      ...bodyguards.map(b => ({ value: b.id, label: b.name })),
    ], ru.leader_attachment?.bodyguard_ref?.id ?? '', (v) => S.setLeaderAttachment(i, v || null)));
}

function renderLoadout(i, ru, data) {
  const rows = S.loadoutRows(ru);
  if (!rows.length) return null;
  const violations = S.loadoutViolations(ru);
  const box = h('div.loadout', {},
    h('div.loadout-header', {},
      h('h3', {}, 'Wargear'),
      h('span.spacer'),
      h('button.btn.btn-small', { onclick: () => S.resetLoadout(i) }, 'Reset to default')));

  for (const row of rows) {
    const profileText = row.profiles.map(p => {
      const stats = p.stats ?? {};
      const skill = p.range === 'Melee'
        ? (stats.WS != null ? `WS${stats.WS}+` : '')
        : (stats.BS != null ? `BS${stats.BS}+` : '');
      return `${p.range === 'Melee' ? 'Melee' : p.range + '"'} A${stats.A} ${skill} S${stats.S} AP${stats.AP} D${stats.D}`;
    }).join('  |  ');
    box.append(h('div.loadout-row', { class: row.count > 0 ? 'loadout-row taken' : 'loadout-row' },
      h('div.lo-info', {},
        h('span.lo-name', {}, row.name),
        h('span.lo-profile', {}, profileText)),
      stepper(row.count, row.min, row.max, (n) => S.setWeaponCount(i, row.id, n))));
  }
  if (violations.length) {
    box.append(h('ul.loadout-violations', {},
      violations.map(v => h('li', {}, v.message))));
  }
  return box;
}

function renderAbilities(data) {
  const { raw, factionId } = data;
  const items = [];
  for (const aid of raw.ability_ids ?? []) {
    const a = S.conv.ares.resolve(factionId, aid);
    if (!a) continue;
    items.push(h('details.ability', {},
      h('summary', {}, a.name),
      h('p', {}, S.conv.safeDescribe(a))));
  }
  if (!items.length) return null;
  return h('div.abilities', {}, h('h3', {}, 'Abilities'), items);
}

// ---------------------------------------------------------------------------
// Status toast

function renderStatus() {
  const s = S.state.status;
  if (!s) return h('div');
  return h('div.toast', { class: `toast toast-${s.kind}` }, s.text);
}

// ---------------------------------------------------------------------------
// Boot

async function boot() {
  initPlayerId(); // fire-and-forget; api calls await it themselves
  const restored = S.loadDraft();
  S.subscribe(render);
  render();
  if (restored && S.state.roster.units.length) {
    S.setStatus('info', 'Draft restored from this browser');
  }
  // Deep link: index.html#army=<cloud name> opens a cloud list directly.
  const m = location.hash.match(/#army=(.+)$/);
  if (m) {
    const name = decodeURIComponent(m[1]);
    const { openCloudArmy } = await import('./dialogs.js');
    openCloudArmy(name);
  }
}

// Importers are loaded lazily by dialogs.js, but the unresolved-unit editor
// wants candidatesFor synchronously — stash the module once loaded.
import('./importers.js').then(m => { window.__builderImporters = m; });

boot();
