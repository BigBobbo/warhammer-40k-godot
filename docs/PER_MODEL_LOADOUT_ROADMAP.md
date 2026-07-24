# Per-Model Weapon Loadout — Remaining Work

> **How to use this doc.** This is a self-contained task spec. Pick a task (A, B, C
> or D), read the shared **Background**, **Codebase orientation**, and **How to run &
> validate** sections, then follow that task's steps and its **Validation** block. Each
> task is independently doable and independently validatable. Do not assume anything
> you can verify by running the game or the tests — this project's rule is *validate,
> don't assume* (see `CLAUDE.md`).

---

## 0. Background — what this is about

Warhammer 40k datasheets give each model a **menu of wargear options** (a Boy *can*
take a Shoota, Slugga, Big Shoota or Rokkit). The game stores, per `model_type`, the
**whole menu**. Historically every model reported *every* option, so a 10-model Boyz
mob reported ~38 ranged weapon-instances instead of 10, the weapon panel was wrong, and
the Firing Deck couldn't tell which gun a model actually carried.

**Phase 1 (DONE, shipped in v0.93.7)** added a runtime *loadout resolver*: when a unit's
army-list `wargear` unambiguously pins the ranged loadout, each model is stamped with the
real gun it carries (`model.ranged_loadout`), and weapon lookups report that instead of
the menu — **for ranged weapons only**. It is deliberately conservative and currently
resolves **16** multi-model units; **~24** can't be resolved because their imported data
is incomplete.

This doc covers the remaining work:

| Task | Title | Depends on |
|------|-------|-----------|
| **A** | Phase 2 — hover/inspect shows a model's *real* weapon | Phase 1 (done) |
| **B** | Phase 3 — distinct on-board marker/icon for special-weapon models | Phase 1 (done) |
| **C** | Widen coverage — resolve the units Phase 1 can't (import-time loadouts) | Phase 1 (done) |
| **D** | Phase 1b — resolve **melee** loadouts too (fixes Fight-phase over-count) | Phase 1 (done) |

Recommended order: **playtest Phase 1 first**, then **C** (so A/B are useful game-wide,
not just on 16 units), then **A**, **B**, **D**. But each is independent.

---

## 1. Codebase orientation

All paths are relative to the repo root. The Godot project lives in `40k/` (so
`res://` == `40k/`).

### The resolver and weapon lookups — `40k/autoloads/RulesEngine.gd`
- `get_unit_weapons(unit_id, board) -> {model_id: [weapon_id, ...]}` (~line 6385). The
  single chokepoint for a unit's **ranged** weapons. Calls `_ensure_loadout_resolved(unit)`
  once, then `_get_model_weapon_ids(unit, model, "Ranged")` per model. Also appends
  attached-character weapons and Firing-Deck loans (`__fd<i>` aliases).
- `_get_model_weapon_ids(unit, model, weapon_type_filter) -> [weapon_id]` (~line 6262).
  Returns a model's weapon ids for `"Ranged"` or `"Melee"`. **Ranged** now prefers
  `model.ranged_loadout` (the resolved gun names) over the `model_profiles` menu; **Melee**
  still uses the menu (this is what Task D changes).
- `_ensure_loadout_resolved(unit) -> void` (~line 6314). The Phase-1 resolver. Read this
  carefully before Tasks C/D — they extend it. Its logic:
  1. Skip if `unit._loadout_checked` already true (idempotent; stamps the flag).
  2. Skip single-model units (`models.size() < 2`) — vehicles/monsters/characters fire ALL
     their guns and must never be collapsed.
  3. Detect whether any model currently over-reports ranged (>1). If none, skip (already
     resolved via `model_type`, e.g. Lootas' `loota_deffgun`).
  4. Parse `unit.meta.wargear` (e.g. `"8x Deffgun"`) into `{ranged_weapon_name: count}`,
     summing duplicate lines, keeping only names that are this unit's ranged weapons.
  5. **Confidence gate:** proceed only if counts are non-empty AND
     `sum(counts) == models.size()` (exactly one ranged gun per model). Otherwise return
     (leave the unit exactly as-is — the safe fallback).
  6. Assign: lowest-count (special) weapons to the first models, bulk gun to the rest;
     stamp `model.ranged_loadout = [weapon_name]`.
- `_generate_weapon_id(name, type) -> String` (~line 6459): weapon name → id
  (e.g. `"Big shoota","Ranged"` → `"big_shoota_ranged"`). `_ranged` / `_melee` suffix.
- `get_weapon_profile(weapon_id, board) -> Dictionary` (~line 6472): id → full profile
  (range, attacks, strength, ap, damage, abilities). Strips `__fd<i>` aliases.

### Army loading & import — `40k/autoloads/ArmyListManager.gd`
- `load_army_list(army_name, player)` (~line 54) and `load_army_for_game(army_name, player)`
  (~line 485): the two unit-build paths. Army JSONs live in `40k/armies/*.json`.
- `_apply_wargear_stat_bonuses(unit_id, unit)` (~line 258/667): where `wargear` strings are
  already parsed for stat effects (Praesidium Shield +1W, 'Ard Case, etc.) — a useful
  precedent for Task C's wargear parsing.
- `_validate_model_profiles(unit_id, unit)`: validates `model_profiles` on load.

### Data model of a unit (in `40k/armies/*.json` and in `GameState.state.units`)
```
unit = {
  "id": "U_BOYZ_K", "owner": 1, "status": 2, "flags": {...},
  "meta": {
    "name": "Boyz",
    "keywords": ["INFANTRY", "MOB", "ORKS", ...],
    "weapons": [ {"name":"Shoota","type":"Ranged","range":"18","attacks":"2",
                  "ballistic_skill":"5","strength":"4","ap":"0","damage":"1",
                  "special_rules":"rapid fire 1","abilities":[{"id":"rapid_fire"}]},
                 {"name":"Choppa","type":"Melee",...}, ... ],   # the DATASHEET MENU
    "wargear": ["9x Slugga", "1x Slugga"],                       # the ACTUAL loadout w/ counts
    "model_profiles": {                                          # per-type menus (+ labels)
      "boy":      {"label":"Boy","short_label":"B",
                   "weapons":["Choppa","Close combat weapon","Shoota","Slugga","Big shoota","Rokkit launcha"]},
      "boss_nob": {"label":"Boss Nob","short_label":"N","weapons":["Big choppa","Choppa","Power klaw","Slugga","Kombi-weapon"]}
    }
  },
  "models": [
    {"id":"m1","model_type":"boss_nob","alive":true,"wounds":2,"position":{...}},
    {"id":"m2","model_type":"boy","alive":true, "ranged_loadout":["Slugga"], ...},  # <-- Phase 1 stamp
    ...
  ]
}
```
Key facts:
- `meta.weapons` = the full **menu** of every weapon the unit's datasheet offers.
- `model.model_type` picks which `model_profiles` entry applies. May be `""` (no profile).
- `model_profiles[type].weapons` = the subset of the menu that type *can* take (often still a
  menu of mutually-exclusive options, e.g. `boy`).
- `model_profiles[type].short_label` = a 1–2 char label already drawn on tokens (see below).
- `meta.wargear` = the actual loadout **with counts** — but its format **varies** and is
  sometimes **incomplete** (see §4). This is the source of truth Phase 1/C parse.
- `model.ranged_loadout` = Phase-1 output: the list of ranged weapon **names** this model
  actually carries. Absent ⇒ unit wasn't resolved.

### On-board model rendering — `40k/scripts/TokenVisual.gd`
- Draws each model token. Already renders a per-model type label via
  `_get_model_type_short_label()` (~line 1212), which reads `model_profiles[model_type].short_label`.
- Uses `TokenDrawUtils.gd` helpers (`draw_*` for rims, wound pips, silhouettes, chevrons).
- **This is the file Task B (icons) edits.**

### Weapon display panel — `40k/scripts/UnitStatsPanel.gd`
- `_create_weapons_tables()` (~line 392) / `_add_weapon_row()` (~line 473) build the
  per-unit weapon tables. Already groups by `model_type` and counts alive/total per type
  (~line 742). **Relevant to Task A (hover/inspect).**

### Shooting UI weapon tree — `40k/scripts/ShootingController.gd`
- `_refresh_weapon_tree()` (~line 1189) builds the in-phase weapon list from
  `RulesEngine.get_unit_weapons(active_shooter_id)` → already shows resolved guns.

---

## 2. Environment — how to run the game & tests

The `godot` shim on `$HOME/bin` wraps the binary with `xvfb-run` + Mesa software GL, so the
**full windowed UI runs headless in this container**. If `godot` isn't found:
`export PATH="$HOME/bin:$PATH"`.

### First-time cache build (once per fresh clone)
```bash
export PATH="$HOME/bin:$PATH"
godot --headless --path 40k --import      # builds .godot import + class cache
```

### Run the game windowed + MCP bridge (for live/manual validation & screenshots)
```bash
godot --path 40k --rendering-method gl_compatibility > /tmp/game.log 2>&1 &
# Wait for the bridge — do NOT sleep-guess:
until grep -aq "GodotMCP] Listening" /tmp/game.log; do sleep 0.5; done
```
The bridge listens on `127.0.0.1:9080` (NDJSON-over-TCP: send one JSON object + `\n`, read
one JSON line back). Kill stale instances first (`pkill -9 -f godot`) — a second instance
can't bind 9080 and you'll silently talk to the old one.

Minimal Python client + `execute_script` (autoloads reachable by global name here, unlike
`-s` scripts):
```python
import json, socket, itertools
_c = itertools.count(1)
def call(cmd, params, t=40):
    r = {"id": next(_c), "command": cmd, "params": params}
    s = socket.create_connection(("127.0.0.1", 9080), timeout=t); s.settimeout(t)
    s.sendall((json.dumps(r) + "\n").encode()); buf = b""
    while b"\n" not in buf:
        ch = s.recv(65536);  buf += ch
        if not ch: break
    s.close(); return json.loads(buf.split(b"\n", 1)[0].decode())

# multiline GDScript: the snippet gets `tree` (SceneTree) and `node` (=/root); call methods
# on those, not bare. `return <value>` is the result.
print(call("execute_script", {"code": 'return RulesEngine.get_unit_weapons("U_BOYZ_K", GameState.state)',
                              "multiline": True}))
print(call("capture_screenshot", {}))   # writes a PNG under user://test_screenshots and returns it
```

### Headless GDScript tests
Run: `godot --headless --path 40k -s tests/<file>.gd`
**Gotcha:** under `-s`, autoload singletons are **not** compile-time identifiers. Fetch
them as nodes: `var RE = root.get_node_or_null("RulesEngine")` and call
`RE.get_unit_weapons(...)`. See `40k/tests/test_loadout_resolution.gd` for the exact pattern
(connects to `root.ready` + a timer, then does the work).

The Phase-1 test to extend/mirror: **`40k/tests/test_loadout_resolution.gd`** — it sweeps
every `res://armies/*.json` through the real `RulesEngine.get_unit_weapons` and asserts
invariants. Run it and read its output to see the current resolved/unresolved unit lists:
```bash
godot --headless --path 40k -s tests/test_loadout_resolution.gd 2>&1 \
  | grep -aE "Resolved units|Unresolved|passed, [0-9]+ failed|FAIL:"
```

### Windowed scenarios (the project's UI-validation gate)
Scenarios live in `40k/tests/scenarios/sp/*.json` and are driven against the real running UI
by the `ScenarioRunner` autoload. **Any player-facing/UI change MUST add or update a windowed
scenario and prove it passes** (project rule in `CLAUDE.md`).
```bash
bash 40k/tests/run_scenario.sh  tests/scenarios/sp/<id>.json         # one
bash 40k/tests/run_scenarios.sh tests/scenarios/sp/a.json b.json ... # a batch
```
Study these as templates:
- `40k/tests/scenarios/sp/iss_loadout_resolution_11e.json` — injects a real mob, asserts
  `RulesEngine.get_unit_weapons` counts, drives `SELECT_SHOOTER`, screenshots the panel.
- `40k/tests/scenarios/sp/iss_firing_deck_autoresolve_11e.json` — firing deck end-to-end.
- Scenario step vocabulary is in `40k/autoloads/ScenarioRunner.gd` (`match act:`):
  `wait_seconds`, `wait_frames`, `execute_script` (`"multiline": true`, `equals`/`not_equals`),
  `dispatch_action`, `expect_action_result`, `expect_state`, `screenshot`, `click_node`, etc.
- Scenario gotchas learned the hard way:
  - `dispatch_action` `SELECT_SHOOTER` is **validated** — the unit needs an *eligible target*
    (`RulesEngine.get_eligible_targets(uid, GameState.state).size() > 0`), or it's rejected.
    A unit whose only gun is a 12" **Pistol** (Slugga) often has no eligible target at range;
    use a mob with a longer-range gun (e.g. Burna Boyz' 36" Big shoota) for UI captures.
  - The `10e targeting rule` blocks targeting an enemy within engagement range of a *friendly*
    unit — a big-base tank sitting ~2" from the target trips it. Separate shooter and target by
    ~11".
  - In `execute_script` **multiline** mode use real newlines (`\n`) and tabs (`\t`); do **not**
    write a `for … : stmt; return x` one-liner (it mis-parses).
  - Build scenario JSON with a Python generator (as this session did) so quoting is correct.

### Faithful validation checklist (from CLAUDE.md)
A feature is not "done" until a **windowed scenario** drives the real UI and passes, AND
`read_debug_log` / the run shows **no ERROR/SCRIPT ERROR** fired. Headless tests are necessary
but not sufficient for UI changes. Capture a **screenshot showing the feature's effect** (the
tooltip rendered, the icon on the token, the corrected weapon list) — the default screen
doesn't count.

---

## 3. The tasks

### Task A — Phase 2: hover/inspect shows a model's real weapon

**Goal.** When a player hovers or inspects a model, they see the *actual* weapon it carries
(from `model.ranged_loadout`), not the whole menu. For resolved units this is now knowable.

**Approach.**
1. Read how model info surfaces today. `UnitStatsPanel.gd._create_weapons_tables()` builds
   the per-unit weapon list and already groups by `model_type`; `TokenVisual.gd` handles
   per-model board interaction. Find the hover path (grep `mouse_entered`, `hover_unit`,
   `_on_*_hover` in `Main.gd`, `ShootingController.gd`, `TokenVisual.gd`) and where a
   tooltip/panel is populated.
2. When showing a specific model (or model_type group), prefer `model.ranged_loadout` if
   present: show "Slugga" for a Slugga Boy rather than the 4-option menu. Fall back to the
   existing menu display when `ranged_loadout` is absent (unresolved units) — do NOT hide
   weapons for those.
3. Keep it read-only; do not mutate state in UI code. Use
   `RulesEngine.get_unit_weapons(unit_id)` + `RulesEngine.get_weapon_profile(id)` for the
   authoritative resolved data.

**Files.** `40k/scripts/UnitStatsPanel.gd`, `40k/scripts/TokenVisual.gd`, and whichever
controller owns hover (likely `Main.gd` / `ShootingController.gd`).

**Validation.**
- *Windowed scenario* (required): inject a resolved mob (e.g. `U_BOYZ_K` → 10x Slugga, or
  Burna Boyz), hover/select a model, assert the tooltip/panel node text contains the real gun
  (`"Slugga"`) and does NOT contain a menu ghost (`"Big shoota"`, `"Rokkit"`), then
  `screenshot`. Mirror `iss_loadout_resolution_11e.json`.
- *Manual*: run the game, load an Orks army, hover a Boy → confirm it reads "Slugga".
  `capture_screenshot`.
- *Acceptance:* resolved models show one real gun on hover; unresolved units unchanged; no
  SCRIPT ERROR in the debug log; a windowed scenario proves it.

**Gotchas.** Hover for a *unit* with mixed models (9 Slugga Boyz + 1 Kombi Nob) should
convey both — decide whether to show per-model or a grouped "9× Slugga, 1× Kombi-weapon"
(the resolver assigns specials to the first models, and `model_profiles.short_label` is
already available to label them).

---

### Task B — Phase 3: distinct on-board marker for special-weapon models

**Goal.** The model carrying the special/heavy weapon (Rokkit, Big Shoota, KMB, Kombi) looks
different from the rank-and-file on the board, so a player can see at a glance which model has
what.

**Approach.**
1. `TokenVisual.gd` draws each model token and already prints a per-type label via
   `_get_model_type_short_label()` (reads `model_profiles[model_type].short_label`). Use the
   same drawing pipeline.
2. Determine "special" per model from its resolved loadout: a model is "special" if its
   `ranged_loadout` gun is NOT the unit's most-common resolved gun (the bulk/basic gun). The
   resolver already puts specials on the first models; you can also compute the majority gun
   from `RulesEngine.get_unit_weapons(unit_id)` and mark the minority.
3. Add a subtle marker — e.g. a small weapon glyph, a coloured rim (reuse
   `TokenDrawUtils.draw_metallic_rim` with a distinct colour), or a 1-char weapon label near
   the existing type label. Keep it readable at board zoom and consistent with the White Dwarf
   visual theme. Do **not** clutter every model — only the specials differ.
4. For unresolved units (`ranged_loadout` absent) draw nothing new (current look).

**Files.** `40k/scripts/TokenVisual.gd` (+ maybe `40k/scripts/TokenDrawUtils.gd` for a new
glyph helper).

**Validation.**
- *Windowed scenario* (required): inject a mob with a clear special (Burna Boyz → 1 Big shoota
  + 4 Burna, or Lootas → 2 KMB + 8 Deffgun), render the board, and **screenshot** — the
  special-weapon model must be visually distinct. Assert via `execute_script` that exactly the
  expected number of models are flagged special (whatever field/method you add), e.g. return
  the count and `equals` it to the wargear special count.
- *Manual*: `capture_screenshot` of a Boyz/Lootas mob and eyeball the marker.
- *Acceptance:* special-weapon models are visually distinct; count matches wargear; nothing
  changes for unresolved units; a windowed screenshot proves it.

**Gotchas.** Board tokens can be small (software-rendered here) — keep markers legible. Don't
regress the existing `short_label` / wound-pip / status-tick drawing.

---

### Task C — Widen coverage: resolve the units Phase 1 can't

**Goal.** Make the ~24 currently-unresolved multi-model units resolve, so A/B/D are useful
game-wide. Root cause: the runtime `wargear` field is often incomplete or count-less, so
Phase 1's strict `sum == model_count` gate declines them. Get the real per-model loadout from
the **army-list import** and bake it onto models at load.

**Why they fail today (run the Phase-1 test to see the live list).** Categories:
- **Incomplete wargear** — e.g. a 20-model Boyz mob whose `wargear` lists only `10x Slugga`
  (`orks.json` `U_BOYZ_E/F`). Sum (10) ≠ models (20) ⇒ declined.
- **No/oversized/mismatched wargear** — a 2-model Lootas carrying 10-model wargear.
- **Count-less wargear** — Custodian Guard `["Guardian Spear","Sentinel blade","Praesidium Shield"]`.
- **Empty wargear** — Space Marine squads (`space_marines.json`) have `wargear: []`.
- **Dual-gun models** — Deffkoptas (kopta rokkits + slugga, 2 ranged per model): sum = 2×models.

**Approach (staged — do the cheap wins first, they compose with Phase 1).**
1. **Relax the gate safely for the incomplete-but-consistent case.** If the parsed ranged
   counts sum to *fewer* than the model count AND every parsed gun is the *same* weapon,
   assign that gun to all models (a 20-Boy mob with `10x Slugga` is almost certainly 20
   Sluggas). Guard tightly and add a test invariant so you never *invent* a gun a model
   can't take (cross-check against `model_profiles[model_type].weapons`).
2. **Handle dual-gun models.** When `sum == k × model_count` for integer `k>1` and the guns
   partition evenly, give each model the same `k`-gun set (Deffkopta → [kopta rokkits, slugga]).
   Extend `_get_model_weapon_ids` to accept `ranged_loadout` with >1 entry (it already filters
   by a name list — a 2-name list works).
3. **Import-time capture (the real fix).** Inspect how armies are imported
   (`ArmyListManager.load_army_list` / `load_army_for_game`, and the source army JSON
   structure — some have richer per-selection data than the flattened `wargear` string).
   If the source (e.g. a BattleScribe/GW export) carries per-model or per-selection weapon
   assignments, parse them into `model.ranged_loadout` (and `melee_loadout` for Task D) at
   load, instead of relying on the lossy `wargear` summary. This is the highest-value but
   largest sub-task; scope it to one army source format at a time.
4. **Leave truly unknowable units alone** (empty wargear + menu profile). Log them so it's
   visible which units still fall back.

**Files.** `40k/autoloads/RulesEngine.gd` (`_ensure_loadout_resolved`) for 1–2;
`40k/autoloads/ArmyListManager.gd` (+ possibly the army JSONs / a re-import script) for 3.

**Validation.**
- *Headless (required):* extend `40k/tests/test_loadout_resolution.gd`. It already asserts
  "resolution never increases a unit's ranged total", "resolved ⇒ one gun/model (or `k`)",
  "single-model units untouched". Add: for each newly-resolved unit, the assigned guns are a
  subset of that model_type's allowed `model_profiles` weapons, and totals match wargear where
  wargear is complete. Print the resolved-vs-unresolved counts and confirm the resolved count
  went **up** and unresolved **down**, with **0 failures** across all armies.
- *Regression:* re-run the shooting/fight/firing-deck scenarios (see §2) — all must stay green.
  Especially re-run `374_supa_cybork_fnp` context (single-model Telemon must keep all guns).
- *Windowed:* pick one newly-covered unit (e.g. a 20-model Boyz mob) and add/extend a scenario
  asserting its normal-shooting weapon panel now shows the real gun count.
- *Acceptance:* more units resolve, none regress, every invariant holds across all army files,
  and single-model units are still never touched.

**Gotchas.** The #1 risk is **inventing weapons a model can't have** — always intersect any
assignment with `model_profiles[model_type].weapons` (or `meta.weapons` names). The #2 risk is
**collapsing a legitimate multi-gun unit** — keep the single-model guard and the "never
increase totals; only reduce or keep equal" invariant.

---

### Task D — Phase 1b: resolve melee loadouts too

**Goal.** Stop the Fight phase over-counting melee the same way shooting used to over-count
ranged (a Boy reports `Choppa` AND `Close combat weapon`; a Nob reports several melee options).
Extend resolution to melee.

**Approach.**
1. Mirror Phase 1 for melee: parse `wargear` for **melee** weapon names (cross-check
   `meta.weapons` `type == "Melee"`), and stamp `model.melee_loadout` under the same
   confidence gate (multi-model; one melee gun per model; counts sum to model count).
   Note melee wargear is spottier than ranged (some mobs list `Nx Close combat weapon`,
   others list no melee at all) — where it can't be resolved, **fall back** (keep the menu),
   exactly like ranged.
2. In `_get_model_weapon_ids`, when `weapon_type_filter == "Melee"` and `model.melee_loadout`
   is present, use it as the allowed-names list (symmetric with the ranged branch already
   there).
3. Verify the Fight phase reads melee via `RulesEngine.get_unit_weapons`-style lookups /
   `_get_model_weapon_ids(..., "Melee")`. Grep the fight code
   (`40k/phases/FightPhase.gd`, `40k/scripts/FightController.gd`) for how it enumerates melee
   weapons, and confirm it flows through `_get_model_weapon_ids`.

**Files.** `40k/autoloads/RulesEngine.gd` (extend `_ensure_loadout_resolved` +
`_get_model_weapon_ids` melee branch). Possibly a shared helper so ranged/melee don't
duplicate the parse.

**Validation.**
- *Headless (required):* extend `test_loadout_resolution.gd` with a melee sweep — a resolved
  model reports exactly one melee weapon; melee totals never increase; single-model units
  untouched. Spot-check a unit whose melee IS in wargear (e.g. Lootas
  `8x Close combat weapon, 2x Close combat weapon`).
- *Regression (critical):* run a **Fight-phase** scenario (grep `tests/scenarios/sp` for
  `*fight*`) before and after — melee attack counts must become correct, not broken. Confirm
  no unit loses its melee entirely.
- *Windowed:* add a scenario that selects a mob in the Fight phase and asserts the melee weapon
  list/attacks now reflect one weapon per model; screenshot the assign-attacks UI.
- *Acceptance:* melee no longer over-counts for resolvable units; fighting still works for
  everyone; invariants hold across all armies.

**Gotchas.** Some models legitimately have **two** melee profiles (a weapon with two modes, or
a pistol-as-melee) — the same "never increase totals" invariant protects you; when unsure,
fall back. Do not touch ranged behaviour.

---

## 4. Reference data

### Current resolved / unresolved units
Do **not** hardcode these — they change as Task C lands. Get the live list by running
`test_loadout_resolution.gd` (§2) and reading its "Resolved units" / "Unresolved multi-model"
output. At the time of writing: **16 resolved**, **~24 unresolved** (Custodian Guard &
Allarus in some Custodes files; Lootas in some Orks upload files; Deffkoptas; 20-model
Boyz `U_BOYZ_E/F`; Space Marine Intercessor/Tactical/Infiltrator squads).

### Spot-check expected values (stable — use in tests)
| Unit (file) | `wargear` | Expected resolved ranged | Note |
|---|---|---|---|
| `U_BOYZ_K` (`orks.json`) | `9x Slugga, 1x Slugga` | 10× `slugga_ranged`; no shoota/big_shoota/rokkit | Slugga mob, 10 models |
| `U_BURNA_BOYZ_A` (`battlewagons.json`) | `4x Burna, 1x Big shoota` | 4× `burna_ranged` + 1× `big_shoota_ranged` | mixed |
| `U_LOOTAS_A` (`orks.json`) | (resolved via `model_type`) | 8× `deffgun_ranged` + 3× `kustom_mega_blasta_ranged` | **must stay UNCHANGED** (not stamped) |
| single-model VEHICLE/character (any) | — | **unchanged** — all guns | never resolve |

### `wargear` format examples (note the inconsistency — Task C must tolerate all)
```
["9x Slugga", "1x Slugga"]                                  # count + weapon (parseable)
["1x Spanner","1x Kustom mega-blasta","2x Loota (KMB)","8x Loota","8x Deffgun", ...]  # roles + weapons mixed
["Guardian Spear","Sentinel blade","Praesidium Shield"]     # NO counts
[]                                                          # empty (SM squads)
["Custodian Guard (Shield), Praesidium Shield"]             # role+weapon combos, comma-joined
```
Roles ("Loota", "Spanner", "Boss Nob", "Custodian Guard") are **not** weapons — always keep
only names that match `meta.weapons` (or `model_profiles[type].weapons`).

---

## 5. Project rules to follow (from `CLAUDE.md`)

- **Validate, don't assume.** Never claim a limitation or a fix works without running it. Run
  the game (you *can*, headless-with-Xvfb — see §2), drive the feature, read the debug log for
  errors, and screenshot the effect.
- **Windowed-scenario gate.** Any player-facing/UI change (Tasks A, B, and the visible parts of
  C/D) must add/update a `tests/scenarios/sp/*.json` scenario and prove it passes. Headless
  tests alone are not sufficient for UI.
- **Changelog.** On every player-facing change, PREPEND an entry to
  `40k/data/version_history.json` (bump semver, today's date, one-line summary + `changes`
  bullets). Pure-internal/test changes don't need one.
- **Debug logs** live at `user://logs/debug_*.log`
  (`ProjectSettings.globalize_path("user://logs/")`); the MCP bridge exposes `read_debug_log`
  / `verify_delivery`. Don't remove existing debug logging.
- **Git.** Work on a feature branch, commit with clear messages, push; open a PR only when
  asked. Do not commit the model identifier or session URL in code/PRs.

---

## 6. Definition of done (per task)

A task is complete when:
1. The behaviour works, verified **live** in the running game (bridge + screenshot).
2. The relevant **headless** invariants pass across **all** army files (extend
   `test_loadout_resolution.gd`).
3. A **windowed scenario** drives the real UI and passes, with **no ERROR/SCRIPT ERROR** in
   the debug log.
4. Existing shooting/fight/firing-deck scenarios still pass (no regression), and any
   pre-existing failure is confirmed pre-existing on a clean checkout — not introduced.
5. A `version_history.json` entry is added for the player-facing change.
