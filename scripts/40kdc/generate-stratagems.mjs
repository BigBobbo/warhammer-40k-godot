// Generate 40k/data/Stratagems.csv, Factions.csv, Detachments.csv from the
// 11th-edition 40kdc dataset (40k/data/40kdc/*.json), replacing the old
// 10th-edition Wahapedia exports while preserving the exact pipe-delimited,
// header-name-keyed contract that 40k/autoloads/FactionStratagemLoader.gd
// parses.
//
//   node generate-stratagems.mjs
//
// Contract preserved (see FactionStratagemLoader.gd):
//   Stratagems.csv  faction_id|name|id|type|cp_cost|turn|phase|detachment|
//                   detachment_id|description|timing|effects_json
//     - one physical line per record (newlines and pipes stripped from text)
//     - turn: "Your turn" / "Opponent's turn" / "Either player's turn"
//       (straight apostrophe — _parse_timing matches these literally)
//     - phase: title-cased phases joined with " or " + trailing "phase"
//       ("Shooting or Fight phase"); all five phases collapse to "Any phase"
//     - description: HTML with literal <b>WHEN:</b>/<b>TARGET:</b>/
//       <b>EFFECT:</b>/<b>RESTRICTIONS:</b> markers
//     - timing (NEW, optional): once-per-phase|once-per-turn|once-per-battle|
//       unlimited — drives StratagemManager once_per limits directly
//     - effects_json (NEW, optional): JSON array of EffectPrimitives-shaped
//       effect dicts compiled from the 40kdc ability DSL where the mapping is
//       obvious; empty for display-only rows
//   Factions.csv    id|name|link — faction codes REUSED from the old file
//                   (SM, AC, ORK, CSM, ...) matched by name; new 11e factions
//                   (SM chapters) get new codes mirrored in
//                   FactionStratagemLoader.load_faction_codes aliases.
//   Detachments.csv id|faction_id|name|legend|type — reference data only.
//
// NOTE: the 40kdc dataset intentionally contains NO GW rules prose. Only 263
// of the 2135 stratagems link to a structured ability-DSL tree. Rows without
// one get a stub EFFECT sentence and an empty effects_json (display-only).

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { describeAbility } from '@alpaca-software/40kdc-data';
import { loadCollection, normName } from './lib.mjs';

const OUT_DIR = join(new URL('.', import.meta.url).pathname, '..', '..', '40k', 'data');

// ---------------------------------------------------------------------------
// Faction codes
// ---------------------------------------------------------------------------

// Parse the OLD Factions.csv (before overwriting it) so existing game codes
// are reused for factions that survive the edition change.
function loadOldFactionCodes() {
  const byName = new Map(); // normName -> code
  let text = '';
  try {
    text = readFileSync(join(OUT_DIR, 'Factions.csv'), 'utf8');
  } catch {
    return byName;
  }
  const lines = text.replace(/^﻿/, '').split(/\r?\n/).filter(l => l.trim() !== '');
  const headers = lines[0].split('|').map(h => h.trim());
  const idIdx = headers.indexOf('id');
  const nameIdx = headers.indexOf('name');
  for (const line of lines.slice(1)) {
    const cells = line.split('|');
    const code = (cells[idIdx] || '').trim();
    const name = (cells[nameIdx] || '').trim();
    if (code && name) byName.set(normName(name), code);
  }
  return byName;
}

// 11e faction name -> old-file name, for factions that were renamed between
// the 10e Wahapedia export and the 40kdc dataset but are the same army.
const RENAMED_FACTIONS = {
  'adeptus astartes': 'space marines',     // SM
  'agents of the imperium': 'imperial agents', // AoI
};

// Brand-new 11e factions (Space Marine chapters are first-class factions in
// 40kdc). Codes must stay in sync with the alias map added to
// FactionStratagemLoader.load_faction_codes.
const NEW_FACTION_CODES = {
  'black templars': 'BT',
  'blood angels': 'BA',
  'crimson fists': 'CF',
  'dark angels': 'DA',
  'deathwatch': 'DW',
  'imperial fists': 'IF',
  'iron hands': 'IH',
  'raven guard': 'RG',
  'salamanders': 'SAL',
  'space wolves': 'SW',
  'ultramarines': 'UM',
  'white scars': 'WS',
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// One record per physical line, pipe-delimited: strip newlines & pipes.
function sanitize(s) {
  return String(s ?? '')
    .replace(/[\r\n]+/g, ' ')
    .replace(/\|/g, '/')
    .replace(/\s+/g, ' ')
    .trim();
}

function dataslateRank(rec) {
  return rec?.game_version?.dataslate === 'launch' ? 1 : 0;
}

// Dedupe an array of records by id, preferring dataslate "launch" over
// "pre-launch-provisional"; optionally a tie-break scorer.
function dedupeById(records, idOf, score = () => 0) {
  const best = new Map();
  for (const r of records) {
    const id = idOf(r);
    if (!id) continue;
    const cur = best.get(id);
    if (!cur) { best.set(id, r); continue; }
    const a = dataslateRank(r) * 10 + score(r);
    const b = dataslateRank(cur) * 10 + score(cur);
    if (a > b) best.set(id, r);
  }
  return best;
}

const PHASE_ORDER = ['command', 'movement', 'shooting', 'charge', 'fight'];
const PHASE_TITLE = {
  command: 'Command', movement: 'Movement', shooting: 'Shooting',
  charge: 'Charge', fight: 'Fight',
};

function phaseColumn(phases) {
  const known = PHASE_ORDER.filter(p => (phases || []).includes(p));
  if (known.length === 0 || known.length === PHASE_ORDER.length) return 'Any phase';
  return known.map(p => PHASE_TITLE[p]).join(' or ') + ' phase';
}

function turnColumn(playerTurn) {
  switch (playerTurn) {
    case 'your-turn': return 'Your turn';
    case 'opponent-turn':
    case 'opponents-turn': return "Opponent's turn";
    case 'either': return "Either player's turn";
    default:
      console.warn(`WARN: unknown player_turn "${playerTurn}", defaulting to either`);
      return "Either player's turn";
  }
}

const TYPE_TITLE = {
  'battle-tactic': 'Battle Tactic',
  'strategic-ploy': 'Strategic Ploy',
  'epic-deed': 'Epic Deed',
  'wargear': 'Wargear',
};

function typeColumn(detachmentName, stratType) {
  const title = TYPE_TITLE[stratType];
  // En dash matches the old Wahapedia format ("Gladius Task Force – Battle
  // Tactic Stratagem"); omit the type-title gracefully when absent.
  return title ? `${detachmentName} – ${title} Stratagem` : `${detachmentName} Stratagem`;
}

const TIMING_SENTENCE = {
  'once-per-turn': ' You can only use this Stratagem once per turn.',
  'once-per-battle': ' You can only use this Stratagem once per battle.',
};

function whenText(strat) {
  const phase = phaseColumn(strat.phases);
  let turnPrefix = '';
  if (strat.player_turn === 'your-turn') turnPrefix = 'Your ';
  else if (strat.player_turn === 'opponent-turn' || strat.player_turn === 'opponents-turn') {
    turnPrefix = "Opponent's ";
  }
  // "Any phase" already reads naturally with a turn prefix ("Your Any phase"
  // would not) — drop the prefix for Any phase.
  const base = phase === 'Any phase' ? 'Any phase' : `${turnPrefix}${phase}`;
  return `${base}.${TIMING_SENTENCE[strat.timing] || ''}`;
}

function targetText(strat, ability) {
  const tr = strat.target_restrictions;
  const uc = (k) => String(k).toUpperCase();
  if (tr && typeof tr === 'object') {
    const parts = [];
    if (Array.isArray(tr.required_keywords) && tr.required_keywords.length) {
      parts.push(tr.required_keywords.map(uc).join(' '));
    }
    if (Array.isArray(tr.required_keywords_any) && tr.required_keywords_any.length) {
      parts.push(tr.required_keywords_any.map(uc).join(' or '));
    }
    let txt = parts.length
      ? `One ${parts.join(' ')} unit from your army.`
      : 'One unit from your army.';
    if (tr.notes) txt += ` ${tr.notes}`;
    return txt;
  }
  const kws = ability?.applies_to?.required_keywords;
  if (Array.isArray(kws) && kws.length) {
    return `One ${kws.map(uc).join(' ')} unit from your army.`;
  }
  return 'One unit from your army.';
}

const STUB_EFFECT = 'Official 11e effect text is not available in the 40kdc dataset.';

function effectText(ability) {
  if (!ability) return STUB_EFFECT;
  try {
    const out = describeAbility(ability);
    if (out && out.trim() !== '') return out.replace(/\r?\n+/g, ' ').trim();
  } catch (e) {
    console.warn(`WARN: describeAbility failed for ${ability.ability_id}: ${e.message}`);
  }
  return STUB_EFFECT;
}

// ---------------------------------------------------------------------------
// Ability DSL -> EffectPrimitives compiler (effects_json column)
// ---------------------------------------------------------------------------
// Compiles ONLY the obvious leaf mappings; if any node of the effect tree is
// not confidently mappable the whole stratagem stays display-only (empty
// effects_json). Effect dict shapes mirror FactionStratagemLoader._map_effects
// and 40k/autoloads/EffectPrimitives.gd type constants.

const KEYWORD_EFFECTS = {
  'lethal hits': () => ({ type: 'grant_lethal_hits' }),
  'devastating wounds': () => ({ type: 'grant_devastating_wounds' }),
  'lance': () => ({ type: 'grant_lance' }),
  'ignores cover': () => ({ type: 'grant_ignores_cover' }),
  'twin-linked': () => ({ type: 'grant_twin_linked' }),
};

function compileKeyword(kw, attackType) {
  const k = String(kw).toLowerCase();
  if (KEYWORD_EFFECTS[k]) return KEYWORD_EFFECTS[k]();
  if (/^sustained hits\b/.test(k)) return { type: 'grant_sustained_hits' };
  if (k === 'precision') {
    const scope = attackType === 'melee' ? 'melee' : attackType === 'ranged' ? 'ranged' : 'all';
    return { type: 'grant_precision', scope };
  }
  return null; // Assault / Rapid Fire N / Blast / ... — engine has no primitive
}

const REROLL_SCOPE = {
  'ones': 'ones',
  'all-failures': 'failed',
  'failed': 'failed',
};

// Returns an array of effect dicts, or null when the leaf is not obviously
// mappable (which vetoes the whole stratagem).
function compileLeaf(node) {
  const t = node.type;
  const m = node.modifier || {};
  const tgt = node.target || 'unit';
  const own = tgt === 'unit' || tgt === 'self';
  switch (t) {
    case 'roll-modifier':
      if (m.roll === 'hit' && m.operation === 'add' && m.value === 1 && own) return [{ type: 'plus_one_hit' }];
      if (m.roll === 'wound' && m.operation === 'add' && m.value === 1 && own) return [{ type: 'plus_one_wound' }];
      if (m.roll === 'hit' && m.operation === 'crit-on' && own && Number.isInteger(m.value)) {
        return [{ type: 'crit_hit_on', value: m.value }];
      }
      return null;
    case 'keyword-grant': {
      if (!own || !Array.isArray(m.keywords) || m.keywords.length === 0) return null;
      const out = [];
      for (const kw of m.keywords) {
        const c = compileKeyword(kw, m.attack_type);
        if (!c) return null;
        out.push(c);
      }
      return out;
    }
    case 'invulnerable-save':
      return own && Number.isInteger(m.invuln_sv) ? [{ type: 'grant_invuln', value: m.invuln_sv }] : null;
    case 'feel-no-pain':
      if (!own || !Number.isInteger(m.threshold)) return null;
      if (m.scope == null) return [{ type: 'grant_fnp', value: m.threshold }];
      // "mortal"-scoped FNP maps to the engine's closest primitive (FNP vs
      // psychic attacks + mortal wounds).
      if (m.scope === 'mortal' || m.scope === 'psychic-mortal') {
        return [{ type: 'grant_fnp_psychic_mortal', value: m.threshold }];
      }
      return null;
    case 're-roll': {
      if (!own) return null;
      if (m.roll === 'charge') return [{ type: 'reroll_charge' }];
      const scope = REROLL_SCOPE[m.subset];
      if (!scope) return null;
      if (m.roll === 'hit') return [{ type: 'reroll_hits', scope }];
      if (m.roll === 'wound') return [{ type: 'reroll_wounds', scope }];
      if (m.roll === 'save' || m.roll === 'saving-throw') return [{ type: 'reroll_saves', scope }];
      return null;
    }
    case 'stat-modifier': {
      const at = m.attack_type;
      if (!Number.isInteger(m.value)) return null;
      if (m.stat === 'A' && m.operation === 'add' && own) {
        return [{ type: 'plus_attacks', value: m.value, scope: at || 'all' }];
      }
      if (m.stat === 'S' && m.operation === 'add' && at === 'melee' && own) {
        return [{ type: 'plus_strength_melee', value: m.value }];
      }
      if (m.stat === 'M' && m.operation === 'add' && own) return [{ type: 'plus_move', value: m.value }];
      if (m.stat === 'AP' && m.operation === 'improve' && own && m.value > 0) {
        return [{ type: 'improve_ap', value: m.value }];
      }
      // Worsen-AP flags are read from the TARGET unit in RulesEngine (incoming
      // attacks), so both "unit" (defensive buff) and "attacker" authorings
      // land on the right unit via the stratagem target.
      if (m.stat === 'AP' && m.operation === 'worsen' && (own || tgt === 'attacker') && m.value > 0) {
        return [{ type: 'worsen_ap', value: m.value }];
      }
      return null;
    }
    case 'attack-restriction':
      if (m.restriction === 'worsen-incoming-ap' && Number.isInteger(m.value)) {
        return [{ type: 'worsen_ap', value: m.value }];
      }
      return null;
    case 'damage-reduction': {
      const v = m.reduction ?? m.value;
      return Number.isInteger(v) && v > 0 ? [{ type: 'minus_damage', value: v }] : null;
    }
    case 'charge-roll-modifier':
      if (m.operation === 'add' && own && Number.isInteger(m.value) && m.value > 0) {
        return [{ type: 'plus_charge', value: m.value }];
      }
      return null;
    case 'unit-tag':
      if (m.tag === 'battle-shocked' && m.operation === 'remove' && own) {
        return [{ type: 'remove_battle_shock' }];
      }
      return null;
    case 'ability-grant': {
      const g = m.grant_type;
      if (g === 'remove-battle-shock' && own) return [{ type: 'remove_battle_shock' }];
      if ((g === 'Stealth' || g === 'stealth') && own) return [{ type: 'grant_stealth' }];
      if (g === 'act-after-move' && own) {
        const moves = m.moves || [];
        const acts = m.acts || [];
        if (moves.length === 0 || acts.length === 0) return null;
        const out = [];
        for (const mv of moves) {
          for (const ac of acts) {
            if (mv === 'fall-back' && ac === 'shoot') out.push({ type: 'fall_back_and_shoot' });
            else if (mv === 'fall-back' && ac === 'charge') out.push({ type: 'fall_back_and_charge' });
            else if (mv === 'advance' && ac === 'shoot') out.push({ type: 'advance_and_shoot' });
            else if (mv === 'advance' && ac === 'charge') out.push({ type: 'advance_and_charge' });
            else return null;
          }
        }
        return out;
      }
      return null;
    }
    case 'fallback-and-act': {
      if (!own) return null;
      if (m.act === 'shoot') return [{ type: 'fall_back_and_shoot' }];
      if (m.act === 'charge') return [{ type: 'fall_back_and_charge' }];
      // No/combined act = the classic "eligible to shoot and charge after
      // Falling Back" (10e MULTIPOTENTIALITY shape).
      if (m.act == null || m.act === 'shoot-and-charge') {
        return [{ type: 'fall_back_and_shoot' }, { type: 'fall_back_and_charge' }];
      }
      return null;
    }
    default:
      return null; // conditional / choice / dice-gated / movement / etc.
  }
}

function compileAbility(ability) {
  if (!ability || !ability.effect) return [];
  const range = ability.scope?.range;
  // Aura-scoped effects apply to OTHER units around the target — the engine's
  // stratagem flags land on the target unit only, so skip them.
  if (range && !['unit', 'self', 'weapon', 'model'].includes(range)) return [];
  const root = ability.effect;
  const nodes = root.type === 'sequence' ? (root.steps || []) : [root];
  const out = [];
  for (const n of nodes) {
    const c = compileLeaf(n);
    if (!c) return []; // any non-obvious node vetoes the whole stratagem
    out.push(...c);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Curated stratagem text + effects
// ---------------------------------------------------------------------------
// The 40kdc dataset ships name/cost/phase/timing metadata but no effect
// payload for most detachment stratagems (ability_id: null) — those rows get
// the stub sentence and are display-only. For the detachments the game ships
// armies for, the engine already has purpose-built primitives (issues #372/
// #375/#390/#391/#393) that the 10e text pipeline used to drive. These
// curated entries restore that wiring:
//   - `when`/`target` strings use the exact template phrases
//     FactionStratagemLoader._infer_trigger/_parse_target parse (trigger
//     windows + target conditions),
//   - `effect` carries the duration phrase StratagemManager.use_stratagem
//     reads ("until the end of the turn/phase"),
//   - `effects` is the pre-compiled EffectPrimitives array written to
//     effects_json, which marks the stratagem mechanically implemented.
// Keys are 40kdc stratagem ids.
const CURATED_STRATAGEMS = {
  // ── Orks — War Horde ──────────────────────────────────────────────────
  'unbridled-carnage-war-horde': {
    target: 'One ORKS unit from your army that has not been selected to fight this phase.',
    effect: 'Until the end of the phase, each time a model in your unit makes a melee attack, an unmodified Hit roll of 5+ scores a Critical Hit.',
    effects: [{ type: 'crit_hit_on', value: 5 }],
  },
  'ard-as-nails-war-horde': {
    when: "Your opponent's Shooting phase or the Fight phase, just after an enemy unit has selected its targets.",
    target: "One ORKS unit from your army (excluding GROTS, MONSTER and VEHICLE units) that was selected as the target of one or more of the attacking unit's attacks.",
    effect: 'Until the end of the phase, each time an attack targets your unit, subtract 1 from the Wound roll.',
    effects: [{ type: 'minus_one_wound_defense' }],
  },
  'mob-rule-war-horde': {
    when: 'End of your Command phase.',
    target: 'One MOB unit from your army that contains 10 or more models and is not Below Half-strength.',
    effect: 'Select one friendly Battle-shocked ORKS INFANTRY unit within 6" of that MOB unit. That ORKS INFANTRY unit is no longer Battle-shocked.',
    effects: [{ type: 'remove_battle_shock' }],
  },
  'ere-we-go-war-horde': {
    when: 'Start of your Movement phase.',
    target: 'One ORKS INFANTRY unit from your army.',
    effect: 'Until the end of the turn, add 2 to Advance and Charge rolls made for your unit.',
    effects: [{ type: 'plus_charge', value: 2 }],
  },
  'careen-war-horde': {
    when: 'Any phase, just after an ORKS VEHICLE unit from your army with the Deadly Demise ability is destroyed.',
    target: 'That destroyed ORKS VEHICLE unit. You can use this Stratagem on that unit even though it was just destroyed.',
    effect: 'Your unit can make a Normal or Fall Back move before its Deadly Demise ability is resolved. When making this move, your unit can move over enemy units (excluding MONSTER and VEHICLE units) as if they were not there.',
    effects: [{ type: 'deadly_demise_move' }],
  },
  'orks-is-never-beaten-war-horde': {
    when: 'Fight phase, just after an enemy unit has selected its targets.',
    target: "One ORKS unit from your army that was selected as the target of one or more of the attacking unit's attacks.",
    effect: "Until the end of the phase, each time a model in your unit is destroyed, if that model has not fought this phase, do not remove it from play. The destroyed model can fight after the attacking model's unit has finished making attacks, and is then removed from play.",
    effects: [{ type: 'swing_back_before_remove' }],
  },
  // ── Adeptus Custodes — Shield Host ────────────────────────────────────
  'arcane-genetic-alchemy-shield-host': {
    when: 'Any phase, just after a mortal wound is allocated to a model in an ADEPTUS CUSTODES unit from your army.',
    target: 'That ADEPTUS CUSTODES unit.',
    effect: 'Until the end of the phase, models in your unit have the Feel No Pain 4+ ability against mortal wounds.',
    effects: [{ type: 'grant_fnp_psychic_mortal', value: 4 }],
  },
  'avenge-the-fallen-shield-host': {
    when: 'Start of the Fight phase.',
    target: 'One ADEPTUS CUSTODES unit from your army that is below its Starting Strength.',
    effect: 'Until the end of the phase, add 1 to the Attacks characteristic of melee weapons equipped by models in your unit. If your unit is Below Half-strength, add 2 to the Attacks characteristic of those weapons instead.',
    effects: [
      { type: 'plus_attacks', value: 1, scope: 'melee' },
      { type: 'plus_attacks_below_half', value: 2, scope: 'melee' },
    ],
  },
  'unwavering-sentinels-shield-host': {
    when: 'Fight phase, just after an enemy unit has selected its targets.',
    target: "One ADEPTUS CUSTODES INFANTRY unit from your army that is within range of an objective marker you control and that was selected as the target of one or more of the attacking unit's attacks.",
    effect: 'Until the end of the phase, each time a melee attack targets your unit, subtract 1 from the Hit roll.',
    effects: [{ type: 'minus_one_hit_defense_melee' }],
  },
  'multipotentiality-shield-host': {
    target: 'One ADEPTUS CUSTODES unit from your army that Fell Back this phase.',
    effect: 'Until the end of the turn, your unit is eligible to shoot and declare a charge in a turn in which it Fell Back.',
    effects: [{ type: 'fall_back_and_shoot' }, { type: 'fall_back_and_charge' }],
  },
  'vigilance-eternal-shield-host': {
    target: 'One ADEPTUS CUSTODES BATTLELINE unit from your army within range of an objective marker you control.',
    effect: 'That objective marker remains under your control, even if you have no models within range of it, until your opponent controls it at the start or end of any turn.',
    effects: [{ type: 'sticky_objective_control' }],
  },
  'archeotech-munitions-shield-host': {
    target: 'One ADEPTUS CUSTODES unit from your army that has not been selected to shoot this phase.',
    effect: 'Select either the [LETHAL HITS] or [SUSTAINED HITS 1] ability. Until the end of the phase, ranged weapons equipped by models in your unit have the selected ability.',
    // Issue #381 (either/or): default to the first option, [LETHAL HITS];
    // a UI choice prompt is the tracked follow-up.
    effects: [{ type: 'grant_lethal_hits' }],
  },
  // ── Adeptus Custodes — Lions of the Emperor ───────────────────────────
  // The 40kdc dataset ships these six with ability_id: null (no 11e text);
  // WHEN/TARGET/EFFECT below restore the official 10e wording. Three of them
  // (Defiant to the Last, Swift as the Eagle, Unleash the Lions) resolve via
  // purpose-built handlers in StratagemManager/phases — their `effects` stay
  // empty and _mark_custom_implemented_stratagems flags them implemented.
  'peerless-warrior-lions-of-the-emperor': {
    target: 'One ADEPTUS CUSTODES unit from your army that has not been selected to fight this phase.',
    effect: 'Until the end of the phase, melee weapons equipped by models in your unit have the [PRECISION] ability.',
    effects: [{ type: 'grant_precision', scope: 'melee' }],
  },
  'gilded-champion-lions-of-the-emperor': {
    when: "Any phase, just after an ADEPTUS CUSTODES CHARACTER model from your army has used an ability on its datasheet that states it can only be used 'once per battle'.",
    target: 'That ADEPTUS CUSTODES CHARACTER model.',
    effect: "Your model can use that 'once per battle' ability one additional time during the battle (but not in the same phase). You cannot use this Stratagem on the same ADEPTUS CUSTODES CHARACTER model more than once per battle.",
    effects: [], // custom handler (StratagemManager: clears the once-per-battle usage flag)
  },
  'defiant-to-the-last-lions-of-the-emperor': {
    when: 'Fight phase, just after an enemy unit has selected its targets.',
    target: "One ADEPTUS CUSTODES unit from your army that was selected as the target of one or more of the attacking unit's attacks.",
    effect: 'Until the end of the phase, each time a model in your unit is destroyed, if that model has not fought this phase, roll one D6, adding 2 to the result if that model has the CHARACTER keyword. On a 4+, do not remove it from play; the destroyed model can fight after the attacking unit has finished making its attacks, and is then removed from play.',
    effects: [], // custom handler (RulesEngine swing-back-on-death path)
  },
  'unleash-the-lions-lions-of-the-emperor': {
    target: 'One Allarus Custodians or Aquilon Custodians unit from your army that is on the battlefield.',
    effect: 'That unit is split into separate units, each containing one model. These new units each have a Starting Strength of 1.',
    effects: [], // custom handler (CommandPhase USE_UNLEASH_THE_LIONS action)
  },
  'manoeuvre-and-fire-lions-of-the-emperor': {
    when: 'Your Movement phase, just after an ADEPTUS CUSTODES unit from your army Falls Back.',
    target: 'One ADEPTUS CUSTODES unit from your army that Fell Back this phase.',
    effect: 'Until the end of the turn, your unit is eligible to shoot and declare a charge in a turn in which it Fell Back.',
    effects: [{ type: 'fall_back_and_shoot' }, { type: 'fall_back_and_charge' }],
  },
  'swift-as-the-eagle-lions-of-the-emperor': {
    when: "Your opponent's Shooting phase, just after an enemy unit has shot.",
    target: "One ADEPTUS CUSTODES unit from your army (excluding VEHICLE units) that was selected as the target of one or more of the attacking unit's attacks.",
    effect: 'Your unit can make a Normal move of up to D6".',
    effects: [], // custom handler (ShootingPhase reactive move offer)
  },
  // ── Adeptus Custodes — Silent Hunters ─────────────────────────────────
  // These three carry 40kdc ability payloads whose leaf types the generic
  // compiler vetoes (keyword grants with rider clauses); hand-compile them.
  'deathsong-scythes-silent-hunters': {
    target: 'One VIGILATORS unit from your army.',
    effect: "Until the end of the phase, melee weapons equipped by models in your unit have the [LANCE] ability. In addition, each time a model in your unit makes a melee attack that targets a PSYKER unit, add 1 to the Attacks characteristic of that attack's weapon.",
    effects: [
      { type: 'grant_lance' },
      { type: 'plus_attacks_vs_psyker', value: 1, scope: 'melee' },
    ],
  },
  'umbral-prosecution-silent-hunters': {
    target: 'One PROSECUTORS unit from your army.',
    effect: 'Until the end of the phase, ranged weapons equipped by models in your unit have the [RAPID FIRE 2] ability and you can improve the Armour Penetration characteristic of those weapons by 1.',
    effects: [
      { type: 'grant_rapid_fire', value: 2 },
      { type: 'improve_ap', value: 1, scope: 'ranged' },
    ],
  },
  'synchronised-inferno-silent-hunters': {
    target: 'One WITCHSEEKERS unit from your army.',
    effect: 'Until the end of the phase, ranged weapons equipped by models in your unit have the [BLAST] ability.',
    effects: [{ type: 'grant_blast' }],
  },
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const oldCodes = loadOldFactionCodes();
  if (oldCodes.size === 0) {
    console.warn('WARN: old Factions.csv not found/empty — existing codes cannot be reused');
  }

  const factions = loadCollection('factions');
  const rawDetachments = loadCollection('detachments');
  const rawStratagems = loadCollection('stratagems');
  const rawAbilities = loadCollection('abilities');

  // --- faction code assignment (reuse old codes by name) ---
  const factionCode = new Map(); // 40kdc faction id -> game code
  const factionRows = [];
  const usedCodes = new Set();
  for (const f of factions) {
    const key = normName(f.name);
    // Try the current name first (so re-runs against an already-regenerated
    // Factions.csv stay idempotent), then the pre-11e name, then new codes.
    let code = oldCodes.get(key)
      || oldCodes.get(RENAMED_FACTIONS[key] || '')
      || NEW_FACTION_CODES[key];
    if (!code) {
      // Last-resort deterministic code from initials — should not trigger for
      // the current dataset; flag loudly so the alias map gets updated too.
      code = f.name.split(/\s+/).map(w => w[0]).join('').toUpperCase();
      console.warn(`WARN: no code mapping for new faction "${f.name}" — generated "${code}". ` +
        'Add it to NEW_FACTION_CODES and FactionStratagemLoader.load_faction_codes.');
    }
    if (usedCodes.has(code)) console.warn(`WARN: duplicate faction code ${code} (${f.name})`);
    usedCodes.add(code);
    factionCode.set(f.id, code);
    factionRows.push([code, sanitize(f.name), 'https://40kdc.alpacasoft.dev']);
  }

  // --- dedupe detachments (13 SM chapters share the Astartes detachments —
  // prefer the adeptus-astartes copy so shared stratagems land under SM) ---
  const detachmentById = dedupeById(
    rawDetachments, d => d.id, d => (d.faction_id === 'adeptus-astartes' ? 1 : 0));
  const detachments = [...detachmentById.values()];

  // --- dedupe stratagems + abilities by id (prefer "launch" dataslate) ---
  const stratagemById = dedupeById(rawStratagems, s => s.id);
  const abilityById = dedupeById(rawAbilities, a => a.ability_id);

  // --- Stratagems.csv: one row per detachment stratagem ---
  const stratHeader = ['faction_id', 'name', 'id', 'type', 'cp_cost', 'turn', 'phase',
    'detachment', 'detachment_id', 'description', 'timing', 'effects_json'];
  const stratRows = [];
  let withEffects = 0;
  let withAbilityText = 0;
  let missingRefs = 0;
  for (const det of detachments) {
    const facCode = factionCode.get(det.faction_id);
    if (!facCode) {
      console.warn(`WARN: detachment ${det.id} references unknown faction ${det.faction_id}`);
      continue;
    }
    for (const sid of det.stratagem_ids || []) {
      const s = stratagemById.get(sid);
      if (!s) {
        console.warn(`WARN: detachment ${det.id} references missing stratagem ${sid}`);
        missingRefs++;
        continue;
      }
      if (s.category === 'core') continue; // 11e core set is hardcoded in StratagemManager
      const ability = s.ability_id ? abilityById.get(s.ability_id) : null;
      if (s.ability_id && !ability) {
        console.warn(`WARN: stratagem ${s.id} references missing ability ${s.ability_id}`);
      }

      const curated = CURATED_STRATAGEMS[s.id];
      const effects = curated?.effects ?? compileAbility(ability);
      if (effects.length > 0) withEffects++;
      if (ability || curated) withAbilityText++;

      const cp = Number.isInteger(s.cp_cost) ? s.cp_cost : 1;
      if (!Number.isInteger(s.cp_cost)) {
        console.warn(`WARN: stratagem ${s.id} has non-integer cp_cost ${JSON.stringify(s.cp_cost)}`);
      }

      let description =
        `<b>WHEN:</b> ${curated?.when ?? whenText(s)}<br><br>` +
        `<b>TARGET:</b> ${curated?.target ?? targetText(s, ability)}<br><br>` +
        `<b>EFFECT:</b> ${curated?.effect ?? effectText(ability)}`;
      if (s.timing === 'once-per-battle') {
        description += '<br><br><b>RESTRICTIONS:</b> You cannot use this Stratagem more than once per battle.';
      }

      const effectsJson = effects.length > 0 ? JSON.stringify(effects) : '';
      if (effectsJson.includes('|')) {
        throw new Error(`effects_json for ${s.id} contains a pipe character`);
      }

      stratRows.push([
        facCode,
        sanitize(s.name),
        sanitize(s.id),
        sanitize(typeColumn(det.name, s.type)),
        String(cp),
        turnColumn(s.player_turn),
        phaseColumn(s.phases),
        sanitize(det.name),
        sanitize(det.id),
        sanitize(description),
        sanitize(s.timing || ''),
        effectsJson,
      ]);
    }
  }

  // --- Detachments.csv (reference data; nothing parses it) ---
  const detHeader = ['id', 'faction_id', 'name', 'legend', 'type'];
  const detRows = detachments.map(d => [
    sanitize(d.id), factionCode.get(d.faction_id) || '', sanitize(d.name), '', '',
  ]);

  const csv = (header, rows) =>
    [header.join('|'), ...rows.map(r => r.join('|'))].join('\n') + '\n';

  writeFileSync(join(OUT_DIR, 'Stratagems.csv'), csv(stratHeader, stratRows));
  writeFileSync(join(OUT_DIR, 'Factions.csv'), csv(['id', 'name', 'link'], factionRows));
  writeFileSync(join(OUT_DIR, 'Detachments.csv'), csv(detHeader, detRows));

  console.log(`Factions.csv:    ${factionRows.length} rows`);
  console.log(`Detachments.csv: ${detRows.length} rows`);
  console.log(`Stratagems.csv:  ${stratRows.length} rows ` +
    `(${withEffects} with compiled effects_json, ${withAbilityText} with ability-DSL effect text, ` +
    `${stratRows.length - withAbilityText} stub-effect display rows, ${missingRefs} missing refs skipped)`);
}

main();
