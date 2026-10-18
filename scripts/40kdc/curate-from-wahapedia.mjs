#!/usr/bin/env node
// Build a curated codex rules file (the schema of curated/orks_codex_11e.json:
// detachments[] + stratagems[] with verbatim WHEN/TARGET/EFFECT text) from a
// faction-filtered Wahapedia snapshot (.llm/codex_11e_wahapedia/<dir>/wahapedia).
//
//   node curate-from-wahapedia.mjs --faction adeptus-custodes [--out curated/custodes_codex_11e.json]
//   node curate-from-wahapedia.mjs --faction orks --diff curated/orks_codex_11e.json
//
// --diff <file>: compare the snapshot against an existing curated file (WHEN /
// TARGET / EFFECT / CP / turn / phase / rule text) and print every difference
// instead of writing — used to check a shipped curated file for errata.
//
// Stratagem windows are INFERRED from the WHEN sentence (see inferWindows)
// and every inference is listed under `_window_review` in the output; a human
// (or the codex implementation pass) confirms them. A stratagem whose timing
// matches no known window gets `windows: []` (offered from the S panel) and
// is flagged.
//
// Boarding Actions detachments are skipped (owner decision D3).

import { readFileSync, writeFileSync } from 'fs';
import { dirname, join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { argValue, normName } from './lib.mjs';
import { parseCsv, stripHtml, slug } from './wahapedia-import.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const FACTIONS = {
  'adeptus-custodes': { dir: 'custodes', name: 'Adeptus Custodes' },
  'orks': { dir: 'orks', name: 'Orks' },
};
const BOARDING = new Set(['voyagers in darkness', 'black ship guardians', 'ramship raiders', 'kaptin killers']);

// WHEN sentence -> window ids (.llm/ork_codex_11e_design.md §3). Ordered:
// first match wins.
const WINDOW_RULES = [
  [/Shooting phase or the Fight phase, when an enemy unit targets/i, ['enemy_targets_unit_shooting', 'enemy_targets_unit_fight']],
  [/Fight phase, when an enemy unit targets/i, ['enemy_targets_unit_fight']],
  [/Shooting phase, when an enemy unit targets/i, ['enemy_targets_unit_shooting']],
  [/selected to move or declares a charge/i, ['unit_selected_to_move', 'unit_declares_charge']],
  [/selected to make an? (normal|advance|fall-back)|selected to make a (?:normal|advance|fall-back)\/|selected to move/i, ['unit_selected_to_move']],
  [/enemy unit (?:ends|has made) an? (?:normal|advance|fall-back)?\s*move|enemy unit ends a fall-back move|enemy unit is set up/i, ['enemy_ended_move']],
  [/enemy unit is selected to make a fall-back move/i, ['enemy_selected_to_fall_back']],
  [/ends a normal move/i, ['unit_ended_normal_move']],
  [/end of (?:your|your opponent’s|your opponent's|the) Movement phase/i, ['movement_phase_end']],
  [/start of (?:your|your opponent’s|your opponent's|the) Movement phase/i, ['movement_phase_start']],
  [/selected to shoot/i, ['unit_selected_to_shoot']],
  [/enemy unit has shot|after an enemy unit has shot/i, ['enemy_has_shot']],
  [/(?:friendly|your) [^.]*unit has shot/i, ['unit_has_shot']],
  [/enemy unit (?:has )?selected (?:its )?targets|selects its targets|is selected as the target/i, ['enemy_targets_unit_shooting']],
  [/declares? a charge/i, ['unit_declares_charge']],
  [/ends a charge move/i, ['unit_ended_charge_move']],
  [/selected to fight/i, ['unit_selected_to_fight']],
  [/end of the Fight phase/i, ['fight_phase_end']],
  [/is destroyed/i, ['unit_destroyed']],
  [/becomes battle-shocked/i, ['unit_battle_shocked']],
  [/battle-shock step/i, ['battle_shock_step_start']],
];

export function inferWindows(when) {
  for (const [re, ws] of WINDOW_RULES) if (re.test(when)) return ws;
  return [];
}

// Windows CONFIRMED by the codex implementation pass (csv_id -> window ids;
// [] = S-panel stratagem). They win over the WHEN inference, so a re-run of
// this script keeps them. Codex: Adeptus Custodes — WP-C5
// (scripts/codex/custodes/CustodesCodex11e.gd, RULINGS.md § WP-C5).
const CONFIRMED_WINDOWS = {
  'psy-chaff-volley-null-maiden-vigil': ['unit_has_shot'],
  'purgation-sweep-null-maiden-vigil': ['unit_selected_to_shoot'],
  'anathema-blademastery-null-maiden-vigil': ['unit_selected_to_fight'],
  'duty-unto-death-auric-champions': ['enemy_targets_unit_fight'],
  'gilded-champion-auric-champions': [],            // "Any phase, when ... has used" — S panel
  'fury-of-the-emperor-lions-of-the-emperor': ['unit_declares_charge'],
  'unleash-the-lions-lions-of-the-emperor': [],     // "Your Command phase" — S panel
  'vigil-unending-lions-of-the-emperor': ['enemy_targets_unit_shooting', 'enemy_targets_unit_fight'],
  'unstoppable-momentum-might-of-the-moritoi': ['unit_selected_to_move', 'unit_declares_charge'],
  'honoured-interred-might-of-the-moritoi': [],     // "Your Shooting phase or the Fight phase" — S panel
  'unceasing-onslaught-might-of-the-moritoi': ['unit_ended_advance_move'],
  'indomitable-guardians-shadowkeepers': ['enemy_has_fought'],
  'no-escape-shadowkeepers': ['enemy_ended_move'],
  'grim-responsibility-shadowkeepers': ['unit_selected_to_fight'],
  'superhuman-focus-guardians-of-the-throne': ['phase_end'],
  'shield-of-honour-guardians-of-the-throne': ['fight_phase_start'],
  'unlimited-endurance-guardians-of-the-throne': ['unit_ended_advance_move'],
  'swift-as-the-eagle-guardians-of-the-throne': ['enemy_ended_move'],
  'in-auramite-clad-guardians-of-the-throne': ['enemy_targets_unit_shooting', 'enemy_targets_unit_fight'],
  'prime-target-guardians-of-the-throne': ['unit_selected_to_shoot'],
  'avenge-the-fallen-honoured-companions': ['unit_selected_to_fight'],
  'emperors-domain-honoured-companions': ['unit_selected_to_consolidate'],
  'swift-as-the-eagle-honoured-companions': ['enemy_ended_move'],
  'at-spears-length-solar-watch': ['unit_selected_to_move'],
  'gravimetric-grenade-solar-watch': ['charge_phase_start'],
  'inexorable-solar-watch': ['unit_selected_to_move'],
  'impenetrable-bastion-emperors-chosen': ['movement_phase_end'],
  'in-auramite-clad-emperors-chosen': ['enemy_targets_unit_shooting', 'enemy_targets_unit_fight'],
  'superhuman-focus-emperors-chosen': ['phase_end'],
  'bearers-of-his-light-emissaries-imperatus': ['unit_selected_to_fight'],
  'slayers-of-nightmares-emissaries-imperatus': ['unit_selected_to_fight'],
  'selfless-service-emissaries-imperatus': ['charge_phase_end'],
  'rapid-reactions-aquilan-shield': ['enemy_ended_move'],
  'manoeuvre-and-fire-aquilan-shield': ['unit_selected_to_move'],
  'tip-of-the-talon-aquilan-shield': ['unit_selected_to_shoot'],
  'advanced-stabilisers-grav-assault-force': ['unit_selected_to_shoot'],
  'victory-before-death-grav-assault-force': ['unit_destroyed'],
  'inevitable-annihilation-grav-assault-force': ['unit_selected_to_shoot'],
  'golden-light-of-the-moiraides-dread-host': ['unit_selected_to_ingress'],
  'preternatural-rapidity-dread-host': ['unit_ended_advance_move'],
  'lightning-wrath-dread-host': ['unit_selected_to_pile_in'],
};

// Editorial duration phrases (see orks_codex_11e.json): where the printed
// EFFECT leaves the duration implicit, StratagemManager.use_stratagem's
// expiry needs it spelled out. Not codex text — appended as "(Duration: …)".
const DURATION_PHRASES = {
  // The advance / fall-back move "does not prevent your unit from being
  // eligible" to shoot / charge later THIS TURN.
  'preternatural-rapidity-dread-host': 'until the end of the turn',
  'at-spears-length-solar-watch': 'until the end of the turn',
  'manoeuvre-and-fire-aquilan-shield': 'until the end of the turn',
  // The reactive charge's Fights First lasts until the end of the turn (11.04).
  'no-escape-shadowkeepers': 'until the end of the turn',
  // "Until the start of your next turn" = the start of your next Command phase.
  'golden-light-of-the-moiraides-dread-host': 'until the start of your next Command phase',
};

function parseDescription(html) {
  const text = String(html).replace(/<br\s*\/?>\s*<br\s*\/?>/gi, '\n\n');
  const part = label => {
    const m = text.match(new RegExp(`<b>${label}:</b>([^]*?)(?=<b>(?:WHEN|TARGET|EFFECT|RESTRICTIONS):</b>|$)`, 'i'));
    return m ? stripHtml(m[1]).replace(/\s*\n\s*/g, '\n').trim() : '';
  };
  return { when: part('WHEN'), target: part('TARGET'), effect: part('EFFECT'), restrictions: part('RESTRICTIONS') };
}

const straight = s => String(s).replace(/[‘’]/g, "'");

function build(factionId) {
  const cfg = FACTIONS[factionId];
  const dir = join(REPO, '.llm', 'codex_11e_wahapedia', cfg.dir, 'wahapedia');
  const read = n => parseCsv(readFileSync(join(dir, `${n}.csv`), 'utf8'));
  const stamp = read('Last_update')[0]?.last_update ?? 'unknown';
  const dets = read('Detachments').filter(d => !BOARDING.has(normName(d.name)));
  const rules = read('Detachment_abilities');
  const strats = read('Stratagems');
  const review = [];
  const detachments = dets.map(d => {
    const rule = rules.find(r => r.detachment_id === d.id);
    const legend = stripHtml(d.legend);
    return {
      name: stripHtml(d.name),
      id: slug(d.name),
      rule_name: rule ? stripHtml(rule.name) : '',
      rule_text: rule ? `${stripHtml(rule.name)}\n${stripHtml(rule.description)}` : '',
      ...(legend ? { legend } : {}),
      detachment_points: parseInt(d.dp, 10) || 1,
      force_disposition: stripHtml(d.force_disposition),
      stratagem_count: strats.filter(s => s.detachment_id === d.id).length,
    };
  });
  const stratagems = [];
  for (const d of dets) {
    const did = slug(d.name);
    for (const s of strats.filter(x => x.detachment_id === d.id)) {
      const name = straight(stripHtml(s.name)).toUpperCase();
      const parts = parseDescription(s.description);
      const csvId = `${slug(stripHtml(s.name))}-${did}`;
      const inferred = inferWindows(parts.when);
      const confirmed = Object.prototype.hasOwnProperty.call(CONFIRMED_WINDOWS, csvId);
      const windows = confirmed ? CONFIRMED_WINDOWS[csvId] : inferred;
      review.push(`${csvId}: ${windows.length ? windows.join(',') : 'NO WINDOW (S panel)'}${confirmed ? ' [CONFIRMED]' : ''} <- "${parts.when}"`);
      stratagems.push({
        csv_id: csvId,
        name,
        printed_name: straight(stripHtml(s.name)),
        detachment: stripHtml(d.name),
        detachment_id: did,
        cp_cost: parseInt(s.cp_cost, 10),
        turn_column: straight(stripHtml(s.turn)),
        phase_column: stripHtml(s.phase),
        windows,
        when: parts.when,
        target: parts.target,
        effect: parts.effect,
        restrictions: parts.restrictions,
        duration_phrase: DURATION_PHRASES[csvId] ?? null,
        source: `Wahapedia wh40k11ed/factions/${slug(cfg.name)}/ (export ${stamp}). Flavour: ${stripHtml(s.legend)}`,
      });
    }
  }
  return {
    _comment: [
      `Codex: ${cfg.name} (11th edition) stratagems + detachment rules, generated by`,
      'scripts/40kdc/curate-from-wahapedia.mjs from the Wahapedia snapshot in',
      `.llm/codex_11e_wahapedia/${cfg.dir}/wahapedia (export ${stamp}). WHEN/TARGET/EFFECT are the`,
      'printed text. windows were INFERRED from WHEN (see _window_review) unless the codex',
      'implementation pass CONFIRMED them (CONFIRMED_WINDOWS in the script, marked [CONFIRMED]).',
      'duration_phrase is editorial (see orks_codex_11e.json; DURATION_PHRASES in the script).',
      'Boarding Actions detachments are out of scope (owner decision D3).',
      `Counts: ${detachments.length} detachments, ${stratagems.length} stratagems.`,
    ],
    source: { url: `https://wahapedia.ru/wh40k11ed/factions/${slug(cfg.name)}/`, export: stamp },
    detachments,
    stratagems,
    _window_review: review,
  };
}

function diff(doc, curatedPath) {
  const cur = JSON.parse(readFileSync(curatedPath, 'utf8'));
  const out = [];
  const byId = new Map(cur.stratagems.map(s => [s.csv_id, s]));
  const norm = s => String(s ?? '').replace(/[‘’]/g, "'").replace(/\s+/g, ' ').trim().toLowerCase();
  for (const s of doc.stratagems) {
    const c = byId.get(s.csv_id) ?? cur.stratagems.find(x => normName(x.name) === normName(s.name) && x.detachment_id === s.detachment_id);
    if (!c) { out.push(`+ ${s.csv_id} (${s.name}) missing from curated file`); continue; }
    for (const k of ['when', 'target', 'effect', 'restrictions', 'cp_cost', 'turn_column', 'phase_column']) {
      if (norm(c[k]) !== norm(s[k])) out.push(`~ ${c.csv_id}.${k}:\n    curated:   ${norm(c[k])}\n    wahapedia: ${norm(s[k])}`);
    }
  }
  for (const c of cur.stratagems) if (!doc.stratagems.some(s => s.csv_id === c.csv_id || (normName(s.name) === normName(c.name) && s.detachment_id === c.detachment_id))) out.push(`- ${c.csv_id} in curated file, not on Wahapedia`);
  for (const d of doc.detachments) {
    const c = cur.detachments.find(x => x.id === d.id);
    if (!c) { out.push(`+ detachment ${d.id} missing`); continue; }
    if (norm(c.rule_text).replace(/^.*?\s/, '') !== norm(d.rule_text).replace(/^.*?\s/, '') && !norm(c.rule_text).includes(norm(d.rule_text).slice(norm(d.rule_name).length + 1, 120))) {
      out.push(`~ detachment ${d.id} rule text differs:\n    curated:   ${norm(c.rule_text).slice(0, 300)}\n    wahapedia: ${norm(d.rule_text).slice(0, 300)}`);
    }
  }
  return out;
}

const factionId = argValue('faction');
if (!FACTIONS[factionId]) {
  console.error('usage: node curate-from-wahapedia.mjs --faction adeptus-custodes|orks [--out file] [--diff curated-file]');
  process.exit(2);
}
const doc = build(factionId);
const diffPath = argValue('diff');
if (diffPath) {
  const d = diff(doc, resolve(HERE, diffPath));
  console.log(d.length ? d.join('\n') : 'no differences');
} else {
  const out = resolve(HERE, argValue('out') || `curated/${FACTIONS[factionId].dir}_codex_11e.json`);
  writeFileSync(out, JSON.stringify(doc, null, 2) + '\n');
  console.log(`wrote ${out}: ${doc.detachments.length} detachments, ${doc.stratagems.length} stratagems`);
  console.log(doc._window_review.join('\n'));
}
