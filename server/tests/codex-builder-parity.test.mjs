// The browser army builder sees the codex datasheets exactly as the game
// does (WP-W3), and the army it exports matches what
// scripts/40kdc/generate-armies.mjs produces for the same list.
//
// 1. The builder's patched dataset (vendored 40kdc bundle + data-patches.mjs)
//    equals the game's 40k/data/40kdc collections record for record, and the
//    committed overlay module is up to date.
// 2. A Custodes list and an Ork list are built through the builder's store
//    (node, no browser) and exported; every unit is checked against the
//    game's JSON as an independent oracle (profile, points tiers + wargear
//    points + enhancement, model counts, weapon profiles).
// 3. The exported file is run through the real generate-armies.mjs (when
//    scripts/40kdc/node_modules is installed) and diffed unit by unit.
//
// Run: node --test server/tests/codex-builder-parity.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, existsSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { tmpdir } from 'os';
import { execFileSync } from 'child_process';
import { fileURLToPath, pathToFileURL } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = join(here, '..', '..');
const DATA = join(ROOT, '40k', 'data', '40kdc');
const SCRIPTS = join(ROOT, 'scripts', '40kdc');

const S = await import(new URL('../public/js/builder/store.js', import.meta.url).href);
const { DEFAULT_DATA_SOURCE, UNIT_ALIASES, bareEnhancementName } =
  await import(new URL('../public/js/lib/gameformat.mjs', import.meta.url).href);
const { normName, looseName } = await import(new URL('../public/js/lib/dckit.mjs', import.meta.url).href);
const P = await import(new URL('../public/js/lib/data-patches.mjs', import.meta.url).href);

const game = name => JSON.parse(readFileSync(join(DATA, `${name}.json`), 'utf8'));
const G = {
  units: game('units'), weapons: game('weapons'), abilities: game('abilities'),
  unitCompositions: game('unitCompositions'), wargearOptions: game('wargearOptions'),
  leaderAttachments: game('leaderAttachments'), factions: game('factions'),
  enhancements: game('enhancements'), detachments: game('detachments'),
};
const gameUnit = (fid, name) => G.units.find(u => u.faction_id === fid && u.name === name);
const RAW = S.dc.RAW_DATA;

// ---------------------------------------------------------------------------
// 1. data

test('the patched builder dataset equals the game data for the overlaid collections', () => {
  const keys = {
    units: r => `${r.faction_id}::${r.id}`,
    weapons: r => `${r.faction_id ?? ''}::${r.id}`,
    abilities: r => `${r.faction_id ?? ''}::${r.ability_id}`,
    unitCompositions: r => `${r.faction_id}::${r.unit_id}`,
    wargearOptions: r => `${r.faction_id}::${r.unit_id}::${r.id}`,
  };
  // builder-only flags on pre-codex datasheets (D1)
  const strip = r => { const c = { ...r }; delete c.superseded_by_codex; delete c.superseded_by; return c; };
  const firstByKey = (arr, k) => { const m = new Map(); for (const r of arr) if (!m.has(k(r))) m.set(k(r), r); return m; };
  for (const [coll, k] of Object.entries(keys)) {
    const b = firstByKey(RAW[coll], k);
    const g = firstByKey(G[coll], k);
    assert.equal(RAW[coll].length, G[coll].length, `${coll}: record count`);
    assert.equal(b.size, g.size, `${coll}: distinct keys`);
    for (const [kk, gr] of g) {
      assert.ok(b.has(kk), `${coll} ${kk} missing from the builder`);
      assert.deepEqual(strip(b.get(kk)), gr, `${coll} ${kk}`);
    }
  }
  // no faction key (leader ids repeat across factions): same records, same order
  assert.deepEqual(RAW.leaderAttachments, G.leaderAttachments, 'leaderAttachments');
  assert.deepEqual(RAW.factions, G.factions, 'factions');
  // per-datasheet option order (the loadout maths reads options in order)
  const blocks = arr => {
    const m = new Map();
    for (const o of arr) { const kk = `${o.faction_id}::${o.unit_id}`; if (!m.has(kk)) m.set(kk, []); m.get(kk).push(o.id); }
    return m;
  };
  const gb = blocks(G.wargearOptions), bb = blocks(RAW.wargearOptions);
  for (const [kk, ids] of gb) assert.deepEqual(bb.get(kk), ids, `wargear option order ${kk}`);
});

test('the committed overlay module is what the generator writes now', async () => {
  const gen = await import(pathToFileURL(join(SCRIPTS, 'gen_codex_builder_patch.mjs')).href);
  const { text, unexpected } = await gen.buildCodexBuilderPatch();
  assert.deepEqual(unexpected, [], 'no differences outside the imported codex factions');
  assert.equal(readFileSync(gen.OUT, 'utf8'), text,
    'codex-11e-datasheets.mjs is stale — run node scripts/40kdc/gen_codex_builder_patch.mjs');
  assert.equal(P.CODEX_OVERLAY_BASE_VERSION, S.dc.DATASET_VERSION, 'overlay diffed against this bundle');
});

test('data_source: the builder stamps what generate-armies stamps', () => {
  const src = readFileSync(join(SCRIPTS, 'generate-armies.mjs'), 'utf8');
  assert.match(src, /const DATA_SOURCE = DEFAULT_DATA_SOURCE;/, 'generate-armies uses the shared constant');
  assert.ok(DEFAULT_DATA_SOURCE.startsWith(`40kdc-data ${S.dc.DATASET_VERSION} `), DEFAULT_DATA_SOURCE);
  for (const tag of P.CODEX_OVERLAY_SOURCES) {
    assert.ok(DEFAULT_DATA_SOURCE.includes(tag.replace('wahapedia-11e@', 'Wahapedia 11e codex import ')), tag);
  }
  S.resetRoster(); S.setFaction('orks'); S.addUnit('warboss');
  assert.equal(S.toGameJson().army.faction.data_source, DEFAULT_DATA_SOURCE);
});

test('UNIT_ALIASES: each codex rename targets a codex datasheet; the old one is superseded, not offered', () => {
  for (const [fid, aliases] of Object.entries(UNIT_ALIASES)) {
    for (const [oldName, newId] of Object.entries(aliases)) {
      const target = RAW.units.find(u => u.faction_id === fid && u.id === newId);
      assert.ok(target, `${fid}: alias target ${newId}`);
      assert.ok(G.units.some(u => u.faction_id === fid && u.id === newId), `${newId} in the game data`);
      assert.ok(!target.superseded_by_codex, `${newId} is a current datasheet`);
      const old = RAW.units.find(u => u.faction_id === fid && normName(u.name) === oldName);
      if (old && fid === 'adeptus-custodes') {
        assert.equal(old.superseded_by, newId, `${old.name} -> ${newId}`);
        assert.ok(old.superseded_by_codex, `${old.name} flagged`);
      }
    }
  }
  S.resetRoster(); S.setFaction('adeptus-custodes');
  const offered = new Set(S.unitBrowserGroups('').flatMap(g => g.units.map(u => `${u.faction_id}::${u.id}`)));
  for (const u of G.units.filter(x => x.faction_id === 'adeptus-custodes')) {
    const codex = /^wahapedia-11e@/.test(u.source ?? '');
    assert.equal(offered.has(`${u.faction_id}::${u.id}`), codex, `${u.name}: offered iff a codex datasheet`);
  }
  // Orks (overlay import): nothing is hidden.
  S.resetRoster(); S.setFaction('orks');
  const orks = S.unitBrowserGroups('').flatMap(g => g.units).filter(u => u.faction_id === 'orks');
  assert.equal(orks.length, G.units.filter(u => u.faction_id === 'orks').length);
});

test('every codex datasheet at every size, default loadout, passes the builder legality checks', () => {
  // Known, pre-existing in the bare 40kdc 1.4.5 bundle too: a 1-2 model
  // leader row at the unit's largest size — the package's base-loadout
  // allocator seats one leader and leaves the last model unequipped.
  const KNOWN = new Set(['orks/squighog-boyz x8', 'orks/beast-snagga-boyz x20']);
  const bad = [];
  let n = 0;
  for (const fid of ['adeptus-custodes', 'orks']) {
    for (const raw of RAW.units.filter(u => u.faction_id === fid && !u.superseded_by_codex)) {
      for (const size of S.sizeChoices(raw)) {
        S.resetRoster(); S.setFaction(fid); S.addUnit(raw.id); S.setModelCount(0, size);
        const ru = S.state.roster.units[0];
        const v = [...S.legality().units.flatMap(u => u.violations.map(x => x.message)),
          ...S.loadoutViolations(ru).map(x => x.message), ...(ru._tier_missing ? ['no points tier'] : [])];
        n++;
        const label = `${fid}/${raw.id} x${size}`;
        if (v.length && !KNOWN.has(label)) bad.push(`${label}: ${v.join('; ')}`);
      }
    }
  }
  assert.ok(n > 100, `${n} datasheet sizes checked`);
  // (incl. the Ork Boyz / Nobz, whose 1.4.5 compositions carry stale `tiers`
  // the builder's legality dataset ignores — store.js buildLoadoutDataset)
  assert.deepEqual(bad, []);
});

// ---------------------------------------------------------------------------
// 2. build lists through the builder store

function take(i, weaponName, n) {
  const ru = S.state.roster.units[i];
  const rows = S.loadoutRows(ru).filter(r => looseName(r.name) === looseName(weaponName));
  assert.ok(rows.length, `${ru.ref.raw_name}: no loadout row "${weaponName}"`);
  // duplicate names (the Ork overlay keeps 40kdc + codex option ids): the
  // codex one is the row with headroom
  const row = rows.find(r => r.max >= n) ?? rows[0];
  S.setWeaponCount(i, row.id, n);
  assert.equal(S.countsOf(S.state.roster.units[i]).get(row.id) ?? 0, n, `${ru.ref.raw_name}: ${weaponName} x${n}`);
}

function add(id, { size = null, warlord = false, enhancement = null, picks = [] } = {}) {
  S.addUnit(id);
  const i = S.state.roster.units.length - 1;
  if (size) S.setModelCount(i, size);
  if (warlord) S.setWarlord(i);
  if (enhancement) {
    const c = S.enhancementChoices(i).find(x => normName(bareEnhancementName(x.name)) === normName(enhancement));
    assert.ok(c?.eligible, `${id}: enhancement ${enhancement} offered`);
    S.setEnhancement(i, c.id);
  }
  for (const [w, n] of picks) take(i, w, n);
  return i;
}

function buildCustodes() {
  S.resetRoster();
  S.setFaction('adeptus-custodes');
  S.setDetachment('guardians-of-the-throne');
  S.setPointsLimit(3000);
  add('shield-captain', { warlord: true, enhancement: "Eagle's Eye" });
  add('shield-captain');                                            // 2nd copy: repeat price
  add('shield-captain', { picks: [['Castellan Axe', 1]] });         // swaps spear + shield
  add('custodian-guard-sodality', { picks: [['Vexilla', 1]] });
  add('custodian-guard-sodality');
  add('sentinel-guard-sodality');
  add('blade-champion');
  add('custodian-wardens', { size: 3, picks: [['Castellan Axe', 1], ['Vexilla', 1]] });
  add('prosecutor-squad', { size: 5 });
  add('witchseeker-squad');
  add('knight-centura');
  add('caladius-grav-tank');
  add('allarus-custodians', { size: 3 });
  return S.toGameJson();
}

function buildOrks() {
  S.resetRoster();
  S.setFaction('orks');
  S.setDetachment('war-horde');
  S.setPointsLimit(3000);
  add('warboss', { warlord: true, enhancement: "Headwoppa's Killchoppa" });
  add('boyz');
  add('boyz', { size: 20 });
  add('nobz', { picks: [['Paired Krumpas', 1]] });                  // priced wargear item
  add('meganobz', { size: 3, picks: [['Killsaw', 2], ['Twin Killsaws', 1]] }); // priced weapons
  add('gunwagon', { picks: [['Zzap gun', 1]] });                    // priced weapon swap
  add('big-mek-in-mega-armour', { picks: [['Kustom Force Field', 1]] });
  add('tankbustas', { picks: [['Pulsa Rokkit', 1]] });
  add('beastboss');
  add('gretchin', { size: 20 });
  add('battlewagon', { picks: [['Big shoota', 2]] });
  add('deff-dread');
  return S.toGameJson();
}

// --- independent oracle over the game's JSON -------------------------------

function tierCost(unit, models, ordinal) {
  const covers = t => (t.unit_count_min ?? 1) <= ordinal && (t.unit_count_max == null || ordinal <= t.unit_count_max);
  const tiers = (unit.points ?? []).filter(covers);
  const t = tiers.find(x => x.models <= models && models <= (x.models_max ?? x.models));
  assert.ok(t, `${unit.name}: a points tier for ${models} models, copy ${ordinal}`);
  return t.cost;
}

function weaponByName(unit, name) {
  for (const id of unit.weapon_ids ?? []) {
    const w = G.weapons.find(x => x.faction_id === unit.faction_id && x.id === id);
    if (!w) continue;
    for (const p of w.profiles) {
      const full = w.profiles.length > 1 ? `${w.name} – ${p.name}` : w.name;
      if (full.replace(/[‘’]/g, "'") === name) return p;
    }
  }
  return null;
}

function checkAgainstGame(fid, army, detachmentId) {
  const det = G.detachments.find(d => d.faction_id === fid && d.id === detachmentId);
  const ords = new Map();
  const out = [];
  for (const [key, u] of Object.entries(army.units)) {
    const m = u.meta;
    const gu = gameUnit(fid, m.name) ?? G.units.find(x => x.faction_id === fid && x.name.replace(/[‘’]/g, "'") === m.name);
    assert.ok(gu, `${key}: "${m.name}" is a game datasheet`);
    assert.ok(/^wahapedia-11e@/.test(gu.source ?? ''), `${key}: ${gu.name} is the codex datasheet`);
    const p = gu.profiles[0];
    const want = { move: p.M, toughness: p.T, save: p.Sv, wounds: p.W, leadership: p.Ld, objective_control: p.OC };
    if (p.invuln_sv != null) want.invuln = p.invuln_sv;
    assert.deepEqual(m.stats, want, `${key}: profile`);
    const n = u.models.length;
    assert.ok(n >= gu.model_count.min && n <= gu.model_count.max, `${key}: ${n} models in ${JSON.stringify(gu.model_count)}`);
    const ord = (ords.get(gu.id) ?? 0) + 1;
    ords.set(gu.id, ord);
    let wargear = 0;
    for (const line of m.wargear) {
      const mm = line.match(/^(\d+)x (.+)$/);
      for (const wp of gu.wargear_points ?? []) if (mm && looseName(mm[2]) === looseName(wp.name)) wargear += wp.cost * Number(mm[1]);
    }
    let enh = 0;
    for (const e of m.enhancements) {
      const rec = G.enhancements.find(x => det.enhancement_ids.includes(x.id) &&
        normName(bareEnhancementName(x.name)) === normName(e));
      assert.ok(rec, `${key}: enhancement ${e} in ${det.name}`);
      enh += rec.cost;
    }
    assert.equal(m.points, tierCost(gu, n, ord) + wargear + enh, `${key}: points (tier copy ${ord} + wargear ${wargear} + enhancement ${enh})`);
    for (const w of m.weapons) {
      const gp = weaponByName(gu, w.name);
      assert.ok(gp, `${key}: weapon ${w.name} on the game datasheet`);
      const melee = gp.range === 'Melee';
      assert.equal(w.range, melee ? 'Melee' : String(gp.range), `${key}/${w.name}: range`);
      assert.equal(w.attacks, String(gp.stats.A), `${key}/${w.name}: A`);
      const skill = melee ? gp.stats.WS : gp.stats.BS; // null for [TORRENT] weapons: "N/A"
      assert.equal(melee ? w.weapon_skill : w.ballistic_skill, skill == null ? 'N/A' : String(skill), `${key}/${w.name}: skill`);
      assert.equal(w.strength, String(gp.stats.S), `${key}/${w.name}: S`);
      assert.equal(w.ap, String(gp.stats.AP), `${key}/${w.name}: AP`);
      assert.equal(w.damage, String(gp.stats.D), `${key}/${w.name}: D`);
    }
    out.push({ key, name: m.name, points: m.points, models: n, wargear: m.wargear });
  }
  return out;
}

test('Custodes list: every exported unit carries the codex datasheet (game JSON oracle)', () => {
  const { army, warnings } = buildCustodes();
  assert.deepEqual(warnings, [], 'no conversion warnings');
  const rows = checkAgainstGame('adeptus-custodes', army, 'guardians-of-the-throne');
  const sc = army.units.U_SHIELD_CAPTAIN_A.meta;
  assert.equal(sc.stats.wounds, 8, 'Shield-Captain W8 (codex), not the pre-codex W6');
  const eye = G.enhancements.find(e => e.id === 'eagles-eye-guardians-of-the-throne');
  assert.equal(sc.points, 180 + 25 + eye.cost, `Shield-Captain 180 + Praesidium Shield 25 + Eagle's Eye ${eye.cost}`);
  assert.deepEqual(sc.enhancements, ["Eagle's Eye"]);
  assert.equal(army.units.U_SHIELD_CAPTAIN_B.meta.points, 200 + 25, '2nd Shield-Captain: 200 tier');
  const axe = army.units.U_SHIELD_CAPTAIN_C.meta;
  assert.equal(axe.points, 200, 'the Castellan Axe swap gives up the priced Praesidium Shield');
  assert.ok(!axe.abilities.some(a => a.name === 'Praesidium Shield'), 'no shield ability without the shield');
  assert.deepEqual(axe.wargear, ['1x Castellan Axe']);
  const cgs = army.units.U_CUSTODIAN_GUARD_SODALITY_A;
  assert.equal(cgs.models.length, 3, 'Custodian Guard Sodality: 3 models');
  assert.equal(cgs.meta.points, 240);
  assert.ok(cgs.meta.abilities.some(a => a.name === 'Vexilla') && cgs.meta.wargear.includes('1x Vexilla'), 'Vexilla taken');
  const cgsB = army.units.U_CUSTODIAN_GUARD_SODALITY_B.meta;
  assert.ok(!cgsB.abilities.some(a => a.name === 'Vexilla'), 'no Vexilla ability (+1 OC) without one');
  assert.ok(rows.length === 13);
});

test('Ork list: every exported unit carries the codex datasheet (game JSON oracle)', () => {
  const { army, warnings } = buildOrks();
  assert.deepEqual(warnings, [], 'no conversion warnings');
  checkAgainstGame('orks', army, 'war-horde');
  const mega = army.units.U_MEGANOBZ_A.meta;
  assert.equal(mega.points, tierCost(gameUnit('orks', 'Meganobz'), 3, 1) + 2 * 5 + 5,
    'per Killsaw 5 (x2) + per Twin Killsaws 5 — each priced once');
  assert.equal(army.units.U_GUNWAGON_A.meta.points, 150 + 10, 'Gunwagon + Zzap Gun');
  assert.equal(army.units.U_NOBZ_A.meta.points, 115 + 5, 'Nobz + Paired Krumpas');
  assert.ok(army.units.U_BIG_MEK_IN_MEGA_ARMOUR_A.meta.abilities.some(a => a.name === 'Kustom Force Field'));
  assert.equal(army.units.U_BOYZ_A.meta.points, 85);
  assert.equal(army.units.U_BOYZ_B.meta.points, 170);
});

// ---------------------------------------------------------------------------
// 3. the same list through generate-armies.mjs

const HAVE_PIPELINE = existsSync(join(SCRIPTS, 'node_modules', '@alpaca-software', '40kdc-data'));

function regenerate(army) {
  const dir = mkdtempSync(join(tmpdir(), 'w3-parity-'));
  try {
    const f = join(dir, 'builder_export.json');
    writeFileSync(f, JSON.stringify(army, null, 1) + '\n');
    const log = execFileSync(process.execPath, [join(SCRIPTS, 'generate-armies.mjs'), f], { cwd: SCRIPTS, encoding: 'utf8' });
    return { regen: JSON.parse(readFileSync(f, 'utf8')), log };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// What generate-armies.mjs may legitimately add for a SWAPPED loadout: it
// lists every default weapon of the composition in meta.weapons and emits a
// default wargear ability (Praesidium Shield) — it rebuilds from legacy lines
// and cannot tell a swap from an add-on. The builder knows the exact loadout.
function defaultsOf(fid, name) {
  const gu = gameUnit(fid, name);
  const comp = G.unitCompositions.find(c => c.faction_id === fid && c.unit_id === gu.id);
  const weaponNames = new Set();
  for (const m of comp?.models ?? []) {
    for (const id of m.default_weapon_ids ?? []) {
      const w = G.weapons.find(x => x.faction_id === fid && x.id === id);
      if (w) weaponNames.add(looseName(w.name));
    }
  }
  const wargear = new Set((comp?.models ?? []).flatMap(m => m.default_wargear ?? []).map(looseName));
  return { weaponNames, wargear };
}

function compareWithGenerator(fid, army) {
  const { regen, log } = regenerate(army);
  assert.equal(regen.faction.data_source, army.faction.data_source, 'data_source');
  assert.deepEqual(Object.keys(regen.units), Object.keys(army.units), 'unit keys');
  const divergences = [];
  for (const [key, b] of Object.entries(army.units)) {
    const g = regen.units[key];
    for (const f of ['name', 'keywords', 'stats', 'points', 'is_warlord', 'enhancements', 'wargear', 'unit_composition', 'leader_data']) {
      assert.deepEqual(g.meta[f], b.meta[f], `${key}: meta.${f}`);
    }
    assert.deepEqual(g.models, b.models, `${key}: models`);
    const { weaponNames, wargear } = defaultsOf(fid, b.meta.name);
    for (const w of b.meta.weapons) {
      assert.deepEqual(g.meta.weapons.find(x => x.name === w.name), w, `${key}: weapon ${w.name}`);
    }
    for (const w of g.meta.weapons) {
      if (b.meta.weapons.some(x => x.name === w.name)) continue;
      assert.ok(weaponNames.has(looseName(w.name.split(' – ')[0])), `${key}: generator-only weapon ${w.name} is a default weapon`);
      divergences.push(`${key}: +weapon ${w.name}`);
    }
    const bn = b.meta.abilities.map(a => a.name), gn = g.meta.abilities.map(a => a.name);
    for (const n of bn) assert.ok(gn.includes(n), `${key}: ability ${n}`);
    for (const n of gn.filter(x => !bn.includes(x))) {
      assert.ok(wargear.has(looseName(n)), `${key}: generator-only ability ${n} is default wargear`);
      divergences.push(`${key}: +ability ${n}`);
    }
    assert.deepEqual(g.meta.abilities.filter(a => bn.includes(a.name)), b.meta.abilities, `${key}: ability records`);
  }
  return { divergences, log };
}

test('Custodes list: generate-armies.mjs reproduces the builder export', { skip: !HAVE_PIPELINE && 'scripts/40kdc/node_modules missing (cd scripts/40kdc && npm ci)' }, () => {
  const { army } = buildCustodes();
  const { divergences } = compareWithGenerator('adeptus-custodes', army);
  // Only the Castellan Axe Shield-Captain (a swap) differs, and only by the
  // defaults generate-armies always lists.
  assert.deepEqual(divergences.filter(d => !d.startsWith('U_SHIELD_CAPTAIN_C') && !d.startsWith('U_CUSTODIAN_WARDENS_A')), [],
    `unexpected divergences: ${divergences.join('; ')}`);
  assert.ok(divergences.includes('U_SHIELD_CAPTAIN_C: +ability Praesidium Shield'), divergences.join('; '));
});

test('Ork list: generate-armies.mjs reproduces the builder export', { skip: !HAVE_PIPELINE && 'scripts/40kdc/node_modules missing (cd scripts/40kdc && npm ci)' }, () => {
  const { army } = buildOrks();
  const { divergences } = compareWithGenerator('orks', army);
  const swapped = new Set(['U_MEGANOBZ_A', 'U_GUNWAGON_A', 'U_BIG_MEK_IN_MEGA_ARMOUR_A', 'U_TANKBUSTAS_A', 'U_NOBZ_A']);
  assert.deepEqual(divergences.filter(d => !swapped.has(d.split(':')[0])), [], `unexpected divergences: ${divergences.join('; ')}`);
});

// ---------------------------------------------------------------------------
// game JSON -> builder -> game JSON for codex specifics

test('a game army with a codex Upgrade and a Praesidium Shield line round-trips with its cost', () => {
  const file = JSON.parse(readFileSync(join(ROOT, '40k', 'armies', 'battlewagons.json'), 'utf8'));
  const { roster, warnings } = S.conv.gameToRoster(file, { name: 'bw' });
  const bw = roster.units.find(u => u.ref.id === 'battlewagon');
  assert.equal(bw.enhancement?.id, 'targetin-gizmos-upgrade-blitz-brigade', `"Targetin' Gizmos" resolves to the (Upgrade) record: ${warnings.join('; ')}`);
  const out = S.conv.rosterToGame(roster, {}).army;
  const obw = Object.values(out.units).find(u => u.meta.name === 'Battlewagon');
  assert.deepEqual(obw.meta.enhancements, ["Targetin' Gizmos"], 'exported under the bare name the game keys on');
  assert.equal(obw.meta.points, file.units.U_BATTLEWAGON_A.meta.points);

  const cus = JSON.parse(readFileSync(join(ROOT, '40k', 'armies', 'adeptus_custodes.json'), 'utf8'));
  const r2 = S.conv.gameToRoster(cus, { name: 'ac' }).roster;
  const sc = r2.units.find(u => u.ref.id === 'shield-captain');
  assert.equal(S.countsOf(sc).get('praesidium-shield'), 1, '"Shield-Captain (Shield), Praesidium Shield" holds one');
  const osc = Object.values(S.conv.rosterToGame(r2, {}).army.units).find(u => u.meta.name === 'Shield-Captain');
  assert.equal(osc.meta.points, 205, '180 + 25 for the Praesidium Shield, as stored');
});

test('a pasted pre-codex list moves a renamed datasheet onto the codex one', async () => {
  const { importText } = await import(new URL('../public/js/builder/importers.js', import.meta.url).href);
  const text = [
    'Old Guard (480 Points)', '', 'Adeptus Custodes', 'Guardians of the Throne', 'Strike Force (2000 Points)', '',
    'BATTLELINE', '', 'Custodian Guard (215 Points)', '  • 5x Custodian Guard', '    ◦ 5x Guardian Spear', '',
  ].join('\n');
  const { roster, report } = importText(text);
  const u = roster.units[0];
  assert.equal(u.ref.id, 'custodian-guard-sodality', JSON.stringify(report.warnings));
  assert.equal(u.model_count, 3, 'snapped to the codex unit size');
  assert.ok(report.warnings.some(w => /pre-codex datasheet — imported as Custodian Guard Sodality/.test(w)), report.warnings.join('; '));
});
