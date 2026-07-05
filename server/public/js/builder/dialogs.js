// Modal dialogs: text/file import, cloud list management, export/save.

import * as S from './store.js';
import { h, select, showModal, closeModal, downloadFile } from './ui.js';
import { importText, importJsonText, importGameObject } from './importers.js';
import * as API from './api.js';

// ---------------------------------------------------------------------------
// Import

export function openImportDialog() {
  let pendingResult = null;
  let factionOverride = '';

  const report = h('div.import-report');
  const textarea = h('textarea.import-text', {
    rows: 12,
    placeholder: 'Paste an army list here…\n\nSupported: GW app export, New Recruit (text or JSON), ListForge, rosterizer, the old plain format — or a saved game army JSON.',
  });

  const fileInput = h('input', {
    type: 'file',
    accept: '.json,.txt',
    onchange: async (e) => {
      const file = e.target.files?.[0];
      if (file) textarea.value = await file.text();
    },
  });

  const factionSelect = select([
    { value: '', label: 'Auto-detect faction' },
    ...S.factionList().map(f => ({ value: f.id, label: f.name })),
  ], '', (v) => { factionOverride = v; });

  function runParse() {
    report.textContent = '';
    pendingResult = null;
    const text = textarea.value.trim();
    if (!text) {
      report.append(h('p.sev-error', {}, 'Nothing to import — paste a list or choose a file.'));
      return;
    }
    try {
      pendingResult = text.startsWith('{')
        ? importJsonText(text)
        : importText(text, { factionOverride: factionOverride || null });
    } catch (err) {
      report.append(h('p.sev-error', {}, err.message));
      return;
    }
    const r = pendingResult.roster;
    report.append(h('div', {},
      h('p.sev-ok', {},
        `${pendingResult.report.title}: ${r.units.length} unit(s), ` +
        `${r.units.filter(u => u.ref.resolved).length} matched, faction ${r.faction_id ?? 'UNKNOWN'}.`),
      pendingResult.report.warnings.length
        ? h('details', { open: true },
          h('summary', {}, `${pendingResult.report.warnings.length} note(s)`),
          h('ul', {}, pendingResult.report.warnings.slice(0, 40).map(w => h('li.sev-info', {}, w))))
        : null,
      h('p.hint', {}, 'Apply to load this into the editor — unmatched units stay listed so you can fix them there.'),
    ));
  }

  showModal('Import a list',
    h('div', {},
      h('div.field-row', {}, h('label', {}, 'From file'), fileInput),
      h('div.field-row', {}, h('label', {}, 'Faction'), factionSelect),
      textarea,
      report),
    [
      h('button.btn.btn-secondary', { onclick: closeModal }, 'Cancel'),
      h('button.btn.btn-secondary', { onclick: runParse }, 'Parse'),
      h('button.btn.btn-primary', {
        onclick: () => {
          if (!pendingResult) runParse();
          if (!pendingResult) return;
          S.loadRoster(pendingResult.roster, { report: pendingResult.report });
          closeModal();
          S.setStatus('ok', 'List imported — review the notes in the validation panel');
        },
      }, 'Apply'),
    ]);
}

// ---------------------------------------------------------------------------
// Cloud lists

export function openCloudDialog() {
  const body = h('div', {}, h('p.hint', {}, 'Loading cloud lists…'));

  showModal('My lists (cloud)', body, [
    h('button.btn.btn-secondary', { onclick: closeModal }, 'Close'),
  ]);

  refreshCloudList(body);
}

async function refreshCloudList(body) {
  body.textContent = '';
  let armies;
  try {
    armies = await API.listArmies();
  } catch (err) {
    body.append(h('p.sev-error', {}, `Could not reach the server: ${err.message}`));
    return;
  }
  if (!armies.length) {
    body.append(h('p.hint', {}, 'No lists in the cloud yet. Use Export / Save to upload this one.'));
    return;
  }
  const table = h('table.cloud-table', {},
    h('tr', {}, h('th', {}, 'Name'), h('th', {}, 'Updated'), h('th', {}, '')));
  for (const a of armies) {
    const updated = a.updated_at ? new Date(a.updated_at).toLocaleDateString() : '';
    table.append(h('tr', {},
      h('td', {}, a.army_name),
      h('td', {}, updated),
      h('td.cloud-actions', {},
        h('button.btn.btn-small', { onclick: () => openCloudArmy(a.army_name) }, 'Edit'),
        h('button.btn.btn-small.btn-danger', {
          onclick: async () => {
            if (!confirm(`Delete "${a.army_name}" from the cloud? The game will no longer see it.`)) return;
            try {
              await API.deleteArmy(a.army_name);
              S.setStatus('ok', `Deleted ${a.army_name}`);
              refreshCloudList(body);
            } catch (err) {
              S.setStatus('err', `Delete failed: ${err.message}`);
            }
          },
        }, 'Delete'))));
  }
  body.append(table,
    h('p.hint', {}, 'These are the lists the game\'s army dropdowns show as "(Cloud)". Edits saved here are immediately playable in-game.'));
}

export async function openCloudArmy(name) {
  try {
    const res = await API.getArmy(name);
    const data = typeof res.army_data === 'string' ? JSON.parse(res.army_data) : res.army_data;
    const { roster, report } = importGameObject(data, { name });
    S.loadRoster(roster, { cloudName: name, report });
    closeModal();
    S.setStatus('ok', `Loaded "${name}" from the cloud`);
  } catch (err) {
    S.setStatus('err', `Load failed: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Export / save

export function openExportDialog() {
  const r = S.state.roster;
  const { army, warnings } = S.toGameJson();
  const legality = S.legality();
  const errors = legality.army.filter(v => v.severity === 'error').length +
    legality.units.reduce((s, u) => s + u.violations.length, 0);

  const defaultName = (S.state.cloudName ?? r.name ?? 'army')
    .replace(/[^a-zA-Z0-9 _-]/g, '').trim().replace(/\s+/g, '_') || 'army';
  const nameInput = h('input#export-name', { value: defaultName });

  const info = h('div', {},
    army
      ? h('p.sev-ok', {}, `Ready: ${Object.keys(army.units).length} unit(s), ${r.points.total_computed} pts.`)
      : h('p.sev-error', {}, 'Cannot export — pick a faction first.'),
    errors ? h('p.sev-warn', {}, `${errors} rule issue(s) — the game loads the list anyway, but review the validation panel.`) : null,
    warnings.length
      ? h('details', {}, h('summary', {}, `${warnings.length} conversion note(s)`),
        h('ul', {}, warnings.map(w => h('li.sev-info', {}, w))))
      : null);

  const exportFormats = (S.dc.EXPORT_FORMATS ?? []).map(f => ({ value: f.id, label: f.label }));
  let textFormat = exportFormats[0]?.value ?? 'newrecruit-simple';

  showModal('Export / save',
    h('div', {},
      info,
      h('div.field-row', {}, h('label', {}, 'Name'), nameInput),
      h('div.export-actions', {},
        h('button.btn.btn-primary', {
          disabled: !army,
          onclick: async () => {
            try {
              await API.putArmy(nameInput.value, army);
              S.state.cloudName = nameInput.value;
              S.setStatus('ok', `Saved to cloud as "${nameInput.value}" — the game lists it under armies`);
              closeModal();
            } catch (err) {
              S.setStatus('err', `Cloud save failed: ${err.message}`);
            }
          },
        }, 'Save to cloud'),
        h('button.btn.btn-secondary', {
          disabled: !army,
          onclick: () => downloadFile(`${nameInput.value}.json`, JSON.stringify(army, null, 1)),
        }, 'Download game JSON'),
        h('button.btn.btn-secondary', {
          disabled: !army,
          onclick: async () => {
            try {
              await API.putLocalArmy(nameInput.value, JSON.stringify(army, null, 1));
              S.setStatus('ok', `Saved into 40k/armies/${nameInput.value}.json (dev server)`);
            } catch (err) {
              S.setStatus('err', `Local save failed (needs the dev relay server): ${err.message}`);
            }
          },
        }, 'Save to game folder (dev)')),
      h('hr'),
      h('div.field-row', {},
        h('label', {}, 'Text format'),
        select(exportFormats, textFormat, (v) => { textFormat = v; }),
        h('button.btn.btn-small', {
          onclick: () => {
            try {
              const out = S.dc.exportRoster(r, textFormat);
              downloadFile(`${nameInput.value}.${textFormat.includes('json') ? 'json' : 'txt'}`, out, 'text/plain');
            } catch (err) {
              S.setStatus('err', `Export failed: ${err.message}`);
            }
          },
        }, 'Download'))),
    [h('button.btn.btn-secondary', { onclick: closeModal }, 'Close')]);
}
