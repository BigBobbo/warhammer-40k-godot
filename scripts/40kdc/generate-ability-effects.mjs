// Compile 40kdc ability-DSL trees into ABILITY_EFFECTS-shaped entries the
// game loads at runtime (40k/data/generated_ability_effects.json).
//
//   node generate-ability-effects.mjs
//
// Scope: unit abilities + detachment enhancements for the factions the game
// ships armies for (orks, adeptus-custodes). Hand-written entries in
// UnitAbilityManager.ABILITY_EFFECTS always win over generated ones — this
// file only fills gaps.
//
// Compilation is CONSERVATIVE: an entry is emitted implemented:true only when
// every node of the effect tree maps onto an existing EffectPrimitives
// primitive and every condition maps onto a runtime condition the engine
// checks (`always`, `unit_flag`, `while_led`, `aura`, `enhancement`). Anything
// else is emitted implemented:false with the ability text, so the card shows
// honest state and the sweep test can count intentional stubs.
//
// Output entry shape mirrors UnitAbilityManager.ABILITY_EFFECTS:
//   { condition, effects[], target, attack_type, implemented, description,
//     aura_range?, aura_target?, condition_flag?, source_id, generated: true }

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { describeAbility } from '@alpaca-software/40kdc-data';
import { loadCollection } from './lib.mjs';

const OUT_PATH = join(new URL('.', import.meta.url).pathname, '..', '..', '40k', 'data', 'generated_ability_effects.json');
const UAM_PATH = join(new URL('.', import.meta.url).pathname, '..', '..', '40k', 'autoloads', 'UnitAbilityManager.gd');

const FACTIONS = ['orks', 'adeptus-custodes'];

// Names the engine handles outside ABILITY_EFFECTS — never emit for these.
const HANDLED_ELSEWHERE = new Set([
  'Da Jump', 'Da Jump (Psychic)', 'Sneaky Gitz', 'Supreme Commander', 'Bodyguard',
  "'Ard Case", '’Ard Case', 'Praesidium Shield', 'Vexilla', 'Get Da Good Bitz',
  'Waaagh!', "Martial Ka'tah", 'Martial Ka’tah', "Thievin' Scavengers", 'Thievin’ Scavengers',
  'From Golden Light', 'Fortification', 'TRANSPORT', 'Firing Deck',
  'Ramshackle but Rugged',  // canonicalized to "Ramshackle" at army load
]);

// ---------------------------------------------------------------------------
// Dataset
// ---------------------------------------------------------------------------
const abilities = loadCollection('abilities');
const units = loadCollection('units');
const enhancements = loadCollection('enhancements');
const detachments = loadCollection('detachments');

const rank = (a) => (a?.game_version?.dataslate === 'launch' ? 1 : 0);
const abilityById = new Map();
for (const a of abilities) {
  const cur = abilityById.get(a.ability_id);
  if (!cur || rank(a) > rank(cur)) abilityById.set(a.ability_id, a);
}

// Hand-written names (skip: const table wins and duplication is noise).
// Comparison is punctuation/case-insensitive — the dataset uses typographic
// apostrophes where the hand-written table uses straight ones.
const normName = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
const uamSource = readFileSync(UAM_PATH, 'utf8');
const handWritten = new Set();
{
  const tbl = uamSource.match(/const ABILITY_EFFECTS: Dictionary = \{([\s\S]*?)\n\}/);
  for (const m of tbl[1].matchAll(/\n\t"([^"]+)": \{/g)) handWritten.add(normName(m[1]));
}
const elsewhereNorm = new Set([...HANDLED_ELSEWHERE].map(normName));
const isKnown = (name) => handWritten.has(normName(name)) || elsewhereNorm.has(normName(name));

function safeDescribe(a) {
  try {
    const d = describeAbility(a);
    return typeof d === 'string' ? d.replace(/\r?\n+/g, ' ').trim() : String(d ?? '');
  } catch {
    return a.community_notes ?? '';
  }
}

// ---------------------------------------------------------------------------
// Leaf compiler: DSL node -> EffectPrimitives effect dicts (or null = veto)
// ---------------------------------------------------------------------------
const KEYWORD_EFFECTS = {
  'lethal hits': { type: 'grant_lethal_hits' },
  'devastating wounds': { type: 'grant_devastating_wounds' },
  'lance': { type: 'grant_lance' },
  'ignores cover': { type: 'grant_ignores_cover' },
  'twin-linked': { type: 'grant_twin_linked' },
};

function compileKeyword(kw) {
  const k = String(kw).toLowerCase().replace(/-/g, ' ');
  if (KEYWORD_EFFECTS[k]) return { ...KEYWORD_EFFECTS[k] };
  if (/^sustained hits\b/.test(k)) return { type: 'grant_sustained_hits' };
  if (k === 'precision') return { type: 'grant_precision', scope: 'all' };
  return null;
}

const REROLL_SCOPE = { 'ones': 'ones', 'all-failures': 'failed', 'failed': 'failed' };

// Compiles one leaf; `ctx` collects target-side info. Returns array of effect
// dicts or null (veto).
function compileLeaf(node, ctx) {
  const t = node.type;
  const m = node.modifier || {};
  const tgt = node.target || 'unit';
  const own = tgt === 'unit' || tgt === 'self' || tgt === 'friendly-within-aura';
  // "attacker"-targeted debuffs are DEFENSIVE effects read from the carrier.
  const defensive = tgt === 'attacker';
  switch (t) {
    case 'roll-modifier': {
      if (m.operation === 'ignore-modifiers') return null;
      if (m.roll === 'hit' && m.operation === 'add' && m.value === 1 && own) return [{ type: 'plus_one_hit' }];
      if (m.roll === 'wound' && m.operation === 'add' && m.value === 1 && own) return [{ type: 'plus_one_wound' }];
      if (m.roll === 'hit' && m.operation === 'subtract' && m.value === 1 && defensive) {
        // -1 to hit for attacks against the carrier. Scope resolution:
        //   melee (explicit or phase-forced) -> melee defense flag
        //   ranged (explicit or phase-forced) -> Stealth flag (ranged -1)
        //   unscoped -> both.
        const scope = m.attack_type || ctx.forced_attack_type;
        if (scope === 'melee') return [{ type: 'minus_one_hit_defense_melee' }];
        if (scope === 'ranged') return [{ type: 'grant_stealth' }];
        return [{ type: 'grant_stealth' }, { type: 'minus_one_hit_defense_melee' }];
      }
      if (m.roll === 'wound' && m.operation === 'subtract' && m.value === 1 && defensive) {
        return [{ type: 'minus_one_wound_defense' }];
      }
      if (m.roll === 'hit' && m.operation === 'crit-on' && own && Number.isInteger(m.value)) {
        return [{ type: 'crit_hit_on', value: m.value }];
      }
      if (m.roll === 'wound' && m.operation === 'crit-on' && own && Number.isInteger(m.value)) {
        return [{ type: 'crit_wound_on', value: m.value }];
      }
      return null;
    }
    case 'keyword-grant': {
      if (!own) return null;
      const kws = m.keywords || (m.keyword ? [m.keyword] : []);
      if (kws.length === 0) return null;
      const out = [];
      for (const kw of kws) {
        const c = compileKeyword(kw);
        if (!c) return null;
        out.push(c);
      }
      return out;
    }
    case 'invulnerable-save':
      return own && Number.isInteger(m.invuln_sv) ? [{ type: 'grant_invuln', value: m.invuln_sv }] : null;
    case 'feel-no-pain': {
      if (!own || !Number.isInteger(m.threshold)) return null;
      if (m.scope == null) return [{ type: 'grant_fnp', value: m.threshold }];
      if (m.scope === 'mortal' || m.scope === 'psychic-mortal') {
        return [{ type: 'grant_fnp_psychic_mortal', value: m.threshold }];
      }
      return null;
    }
    case 're-roll': {
      if (!own) return null;
      if (m.roll === 'charge') return [{ type: 'reroll_charge' }];
      if (m.roll === 'advance') return [{ type: 'reroll_advance' }];
      const scope = REROLL_SCOPE[m.subset];
      if (!scope) return null;
      if (m.roll === 'hit') return [{ type: 'reroll_hits', scope }];
      if (m.roll === 'wound') return [{ type: 'reroll_wounds', scope }];
      if (m.roll === 'save' || m.roll === 'saving-throw') return [{ type: 'reroll_saves', scope }];
      return null;
    }
    case 'stat-modifier': {
      const at = m.attack_type;
      if (m.stat === 'AP' && m.operation === 'worsen' && (defensive || own) && Number.isInteger(m.value) && m.value > 0) {
        return [{ type: 'worsen_ap', value: m.value }];
      }
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
      // Ld "+1" in the dataset means an IMPROVED test (the engine models it
      // as a bonus added to the Battle-shock test total).
      if (m.stat === 'Ld' && m.operation === 'add' && own) return [{ type: 'improve_leadership', value: m.value }];
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
    case 'fight-first':
      return own ? [{ type: 'grant_fights_first' }] : null;
    case 'fallback-and-act': {
      if (!own) return null;
      if (m.act === 'shoot') return [{ type: 'fall_back_and_shoot' }];
      if (m.act === 'charge') return [{ type: 'fall_back_and_charge' }];
      if (m.act == null || m.act === 'shoot-and-charge') {
        return [{ type: 'fall_back_and_shoot' }, { type: 'fall_back_and_charge' }];
      }
      return null;
    }
    case 'ability-grant': {
      const g = m.grant_type || m.ability_id;
      if (g === 'charge-after-advance') return [{ type: 'advance_and_charge' }];
      if (g === 'shoot-after-advance') return [{ type: 'advance_and_shoot' }];
      if (g === 'shoot-and-charge-after-advance-fallback') {
        return [{ type: 'advance_and_shoot' }, { type: 'advance_and_charge' },
                { type: 'fall_back_and_shoot' }, { type: 'fall_back_and_charge' }];
      }
      if (g === 'act-after-move') {
        const moves = m.moves || []; const acts = m.acts || [];
        const out = [];
        for (const mv of moves) for (const ac of acts) {
          if (mv === 'fall-back' && ac === 'shoot') out.push({ type: 'fall_back_and_shoot' });
          else if (mv === 'fall-back' && ac === 'charge') out.push({ type: 'fall_back_and_charge' });
          else if (mv === 'advance' && ac === 'shoot') out.push({ type: 'advance_and_shoot' });
          else if (mv === 'advance' && ac === 'charge') out.push({ type: 'advance_and_charge' });
          else return null;
        }
        return out.length ? out : null;
      }
      if ((g === 'Stealth' || g === 'stealth')) return [{ type: 'grant_stealth' }];
      if (g === 'lone-operative') return [{ type: 'grant_lone_operative' }];
      return null;
    }
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Condition compiler -> runtime condition the engine supports
// ---------------------------------------------------------------------------
// Returns { condition, condition_flag? } or null (veto). `carriers` is the
// list of datasheet units carrying the ability (for compile-time keyword
// checks).
const FLAG_CONDITIONS = {
  'charged-this-turn': 'charged_this_turn',
  'advanced-this-turn': 'advanced',
  'disembarked-from-transport': 'disembarked_this_phase',
  'arrived-from-reserves': 'arrived_from_reserves',
};

function compileCondition(cond, carriers) {
  if (!cond) return { condition: 'always' };
  if (cond.operator) return null; // and/or trees -> veto (bespoke)
  const t = cond.type;
  const p = cond.parameters || {};
  if (t === 'unit-has-keyword') {
    // Datasheet ability: satisfied at compile time when EVERY carrier has the
    // keyword — then it is unconditional at runtime.
    const kw = String(p.keyword || '').toLowerCase();
    const ok = carriers.every(u =>
      [...(u.keywords || []), ...(u.faction_keywords || [])].some(k => String(k).toLowerCase() === kw));
    return ok ? { condition: 'always' } : null;
  }
  if (t === 'is-attached') return { condition: 'while_led' };
  if (FLAG_CONDITIONS[t]) return { condition: 'unit_flag', condition_flag: FLAG_CONDITIONS[t] };
  if (t === 'timing-is') return null;
  if (t === 'phase-is') {
    // Phase scoping is expressed via attack_type phase-relevance where
    // possible: fight -> melee, shooting -> ranged. Anything else vetoes.
    if (p.phase === 'fight') return { condition: 'always', _force_attack_type: 'melee' };
    if (p.phase === 'shooting') return { condition: 'always', _force_attack_type: 'ranged' };
    return null;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tree compiler
// ---------------------------------------------------------------------------
function compileTree(effect, carriers) {
  // Returns { effects, condition, condition_flag, attack_type } or null.
  if (!effect) return null;
  let condition = { condition: 'always' };
  let node = effect;
  // Unwrap a single top-level conditional (nested conditionals veto).
  if (node.type === 'conditional') {
    const c = compileCondition(node.condition, carriers);
    if (!c) return null;
    condition = c;
    node = node.effect;
    if (!node) return null;
  }
  const steps = node.type === 'sequence' ? (node.steps || []) : [node];
  const out = [];
  let attack_type = condition._force_attack_type || null;
  for (const s of steps) {
    let leafNode = s;
    let leafCond = null;
    if (s.type === 'conditional') {
      leafCond = compileCondition(s.condition, carriers);
      if (!leafCond || leafCond.condition !== 'always') return null; // per-step runtime conditions veto
      if (leafCond._force_attack_type) attack_type = leafCond._force_attack_type;
      leafNode = s.effect;
    }
    const c = compileLeaf(leafNode, { forced_attack_type: attack_type });
    if (!c) return null;
    const at = leafNode?.modifier?.attack_type || leafNode?.modifier?.weapon_type;
    if (at === 'melee' || at === 'ranged') attack_type = attack_type || at;
    out.push(...c);
  }
  if (out.length === 0) return null;
  return { effects: out, condition: condition.condition, condition_flag: condition.condition_flag, attack_type: attack_type || 'all' };
}

// ---------------------------------------------------------------------------
// Emit unit abilities
// ---------------------------------------------------------------------------
const generated = {};
let compiled = 0, stubs = 0, skipped = 0;

const unitsByFaction = FACTIONS.map(f => units.filter(u => u.faction_id === f)).flat();
const carrierMap = new Map(); // ability_id -> [unit records]
for (const u of unitsByFaction) {
  for (const aid of (u.ability_ids || [])) {
    if (!carrierMap.has(aid)) carrierMap.set(aid, []);
    carrierMap.get(aid).push(u);
  }
}

for (const [aid, carriers] of carrierMap) {
  const a = abilityById.get(aid);
  if (!a || a.ability_type !== 'unit') continue;
  const name = a.name;
  if (isKnown(name)) { skipped++; continue; }
  if (generated[name]) continue;

  const desc = safeDescribe(a);
  // Aura-scoped abilities whose payload targets SELF are self-buffs with an
  // aura-shaped condition the dataset lost — compile as plain self entries.
  const selfPayload = a.effect?.target === 'self' || a.effect?.effect?.target === 'self';
  const isAura = (a.behavior === 'aura' || /^aura-/.test(String(a.scope?.range || ''))) && !selfPayload;
  let entry = null;

  if (isAura) {
    // Aura: only friendly-buff auras with compilable payloads; the existing
    // aura framework applies effects to units in range each combat phase.
    const range = parseFloat(String(a.scope?.range || '').replace('aura-', ''));
    let tree = a.effect;
    let auraCond = { condition: 'always' };
    if (tree?.type === 'conditional') {
      // target-has-keyword auras: the aura framework filters by keyword via
      // aura_keyword; compile only that shape.
      if (tree.condition?.type === 'target-has-keyword') {
        auraCond.aura_keyword = String(tree.condition.parameters?.keyword || '').toUpperCase();
        tree = tree.effect;
      } else {
        tree = null;
      }
    }
    const payload = tree ? compileTree(tree, carriers) : null;
    if (payload && Number.isFinite(range) && tree.target !== 'attacker') {
      entry = {
        condition: 'aura', aura_range: range,
        aura_target: 'friendly',
        effects: payload.effects, target: 'unit', attack_type: payload.attack_type,
        implemented: true, description: desc,
      };
      if (auraCond.aura_keyword) entry.aura_keyword = auraCond.aura_keyword;
    }
  } else {
    const payload = compileTree(a.effect, carriers);
    if (payload) {
      entry = {
        condition: payload.condition,
        effects: payload.effects, target: 'unit', attack_type: payload.attack_type,
        implemented: true, description: desc,
      };
      if (payload.condition_flag) entry.condition_flag = payload.condition_flag;
    }
  }

  if (!entry) {
    entry = { condition: 'always', effects: [], target: 'unit', attack_type: 'all',
      implemented: false, description: desc || 'No compilable 40kdc effect tree.' };
    stubs++;
  } else {
    compiled++;
  }
  entry.generated = true;
  entry.source_id = aid;
  generated[name] = entry;
}

// ---------------------------------------------------------------------------
// Emit enhancements (condition "enhancement"; bearer_unit target)
// ---------------------------------------------------------------------------
const detIds = new Set(detachments.filter(d => FACTIONS.includes(d.faction_id)).map(d => d.id));
let enhCompiled = 0, enhStubs = 0;
for (const e of enhancements) {
  if (!detIds.has(e.detachment_id)) continue;
  const name = e.name;
  if (isKnown(name) || generated[name]) continue;
  const linked = e.ability_id ? abilityById.get(e.ability_id) : null;
  const desc = linked ? safeDescribe(linked) : '';
  let entry = null;
  if (linked) {
    const payload = compileTree(linked.effect, []);
    // Enhancements apply through the "enhancement" condition path; runtime
    // sub-conditions (unit_flag / while_led) ride along as sub_condition.
    if (payload && ['always', 'unit_flag', 'while_led'].includes(payload.condition)) {
      entry = {
        condition: 'enhancement', effects: payload.effects, target: 'bearer_unit',
        attack_type: payload.attack_type, implemented: true, description: desc,
      };
      if (payload.condition !== 'always') {
        entry.sub_condition = payload.condition;
        if (payload.condition_flag) entry.condition_flag = payload.condition_flag;
      }
      enhCompiled++;
    }
  }
  if (!entry) {
    entry = { condition: 'enhancement', effects: [], target: 'bearer_unit', attack_type: 'all',
      implemented: false, description: desc || 'No compilable 40kdc effect tree for this enhancement.' };
    enhStubs++;
  }
  entry.generated = true;
  entry.source_id = e.id;
  generated[name] = entry;
}

// ---------------------------------------------------------------------------
// Validate effect types against the engine vocabulary and write
// ---------------------------------------------------------------------------
const epSource = readFileSync(join(new URL('.', import.meta.url).pathname, '..', '..', '40k', 'autoloads', 'EffectPrimitives.gd'), 'utf8');
const knownTypes = new Set([...epSource.matchAll(/^const [A-Z0-9_]+ = "([a-z0-9_]+)"/gm)].map(m => m[1]));
for (const [name, entry] of Object.entries(generated)) {
  for (const eff of entry.effects) {
    if (!knownTypes.has(eff.type)) {
      throw new Error(`generated entry "${name}" uses unknown effect type "${eff.type}" — add it to EffectPrimitives.gd first`);
    }
  }
}

writeFileSync(OUT_PATH, JSON.stringify(generated, null, 1) + '\n');
console.log(`generated_ability_effects.json: ${Object.keys(generated).length} entries ` +
  `(${compiled} unit abilities compiled, ${stubs} unit stubs, ` +
  `${enhCompiled} enhancements compiled, ${enhStubs} enhancement stubs, ${skipped} skipped as hand-written/elsewhere)`);
