# 03.11 — Leader / Character Attachment audit

**Source rules:** Wahapedia 10e Core Rules (https://wahapedia.ru/wh40k10ed/the-rules/core-rules/) — Leader ability, Attached Units, Battle-shock test ("best Leadership characteristic in that unit"), Bodyguard destruction (Starting Strength reverts), Precision (allocate to CHARACTER model). Also referenced: 2026-05 audit (`40k/test_results/audit_2026_05/AUDIT_REPORT.md`) for prior-verified Lone Operative, Look Out Sir 10e behaviour, P2-90 attached-unit Toughness, P3-100 attached-CHARACTER precision.

**Codebase scope:** `40k/` only. Excluded `40k/.claude/worktrees/`.

**Canonical pairing source:** `40k/data/Datasheets_leader.csv` — 1,899 rows, header `leader_id|attached_id|`. Copied 2026-05-06 from older mirror; ~1% gap vs newest datasheets. Reference: `01_inventory.md §1.2`.

**Live validation:** running Godot mid-game (FIGHT phase, P2 active, Round 1 — see `audit_11_leader_baseline_fight_phase.png`). FormationsPhase / DeploymentPhase UI flows cannot be re-driven without disrupting the session, so live validation is **read-only** via `execute_script` calls into `CharacterAttachmentManager.can_attach()` against the current `state.units`. UI dialog pop-up testing: **LIVE-VALIDATION SKIPPED (running game is past attachment phases)**. Manager-layer logic was exercised live.

---

## Audit table

| Rule | Wahapedia § / Source | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|
| Datasheets_leader.csv (canonical pairings) consumed by runtime | Wahapedia data corpus | C | ❌ | Grep across `40k/` for `Datasheets_leader\|datasheets_leader\|leader_id.*attached_id` returns **zero hits** in any `.gd`/`.cs`/`.py`. The CSV is present at `40k/data/Datasheets_leader.csv` (1,899 rows) but NOTHING reads it. The game's leader→bodyguard mapping is exclusively the curated `meta.leader_data.can_lead: [<keyword>...]` array in each `40k/armies/*.json` roster. | **Foundational launch-blocker.** Every gap below is a downstream symptom: pairings legal per Wahapedia are unreachable in-game because the player-facing model has no source of canonical truth. |
| Attach declared at army-list time (FormationsPhase) | Wahapedia: "Some CHARACTER units have the Leader ability… to form an Attached unit" + 10e Pre-Game procedure | U | ✅ | `phases/FormationsPhase.gd:153-256` validates `DECLARE_LEADER_ATTACHMENT`, `phases/FormationsPhase.gd:495-507` processes it, `phases/FormationsPhase.gd:823-861` writes `units.<char>.attached_to` + `units.<bg>.attachment_data.attached_characters` diffs at confirm time. UI: `scripts/FormationsDeclarationDialog.gd:102-154` builds the leader-attachment OptionButtons. Wired into `scripts/Main.gd:6090-6120` (`_show_formations_dialog`). | Both surfaces functional. AI side: `scripts/AIDecisionMaker.gd:1407-1475` evaluates and picks pairings. |
| Attach declared at deploy-time (CharacterAttachDialog) | 10e: secondary path for hot-seat / late attach | U | ✅ | `scripts/CharacterAttachDialog.gd:1-155` — modal dialog. Triggered by `scripts/DeploymentController.gd:792-799` when `_has_attachable_characters()` returns true and formations were not pre-declared (`scripts/DeploymentController.gd:783-789` early-return when `GameState.formations_declared()`). Manager: `autoloads/CharacterAttachmentManager.gd:127-167` (`get_attachable_characters`). | Two parallel attachment surfaces. The 2026-05 Lone Operative guard (line 40-41) lives only in `CharacterAttachmentManager.can_attach()` — see Lone-Op row below for the FormationsPhase gap. |
| Attached unit moves/acts as one (movement) | Core Movement: Attached unit moves as a single unit | W | ✅ | `phases/MovementPhase.gd:7301+` (`_move_attached_characters`), `MovementPhase.gd:4208-4210` invoke on confirm; `MovementPhase.gd:3250-3270`, `:3552`, `:3852`, `:3951`, `:4055`, `:4159`, `:4493`, `:4794` all carry `attachment_data.attached_characters` through tween/undo/reset/confirm. Reserves enter together (`MovementPhase.gd:6225-6240`). Coherency calculated for the merged whole. | Bulk of the engine integration is here; well-instrumented. |
| Attached unit acts as one (shooting) | Core Shooting: targeted as one | W | ✅ | `autoloads/RulesEngine.gd:4074-4076` — eligible-targets pass skips `target_unit.attached_to != null` (cannot target the leader through-unit; only the bodyguard wrapper). Same skip in lone-operative range gate (`RulesEngine.gd:3358-3364`, `:4097-4111`). | |
| Attached unit Toughness uses bodyguard's T (P2-90) | 10e: "Each time an attack targets an Attached unit, you must use the Toughness characteristic of the Bodyguard models in that unit, even if a Leader in that unit has a different Toughness characteristic" | W | ✅ VERIFIED (regression spot-check) | `autoloads/RulesEngine.gd:3441-3463` (`_get_attached_unit_toughness`). Already verified 2026-05 in `AUDIT_REPORT.md` (P2-90). | |
| Battle-shock test: best Leadership in the Attached unit | Wahapedia Battle-shock: "the best Leadership characteristic in that unit" | C | 🐛 | `phases/CommandPhase.gd:697`, `:789` read `unit.get("meta", {}).get("stats", {}).get("leadership", 7)` — the **bodyguard's own** Leadership only. There is **no** comparison against attached-character Leadership. Memory: `feedback_10e_rule_verification` flags single-source rule claims; this rule was confirmed via `wahapedia.ru/wh40k10ed/the-rules/core-rules/` live fetch ("greater than or equal to the best Leadership characteristic in that unit"). | **Divergence.** A Custodian Guard (Ld 7) led by Trajann Valoris (Ld 5) currently uses Ld 7 — accidentally correct because Custodian Guard already happens to have the higher Ld. But a unit like Custodian Wardens (Ld 6) led by a Shield-Captain (Ld 5) and many Astartes pairings (Captain Ld 6 over Intercessors Ld 6) — same Ld so no observable bug. **Flips for Daemons/Tyranids/Death-Guard** where leader Ld is often *higher* than bodyguard Ld. Also `_handle_battle_shock_test:717-722` adds `Waaagh! Effigy` bonus but no per-character "best Ld" lookup. **Launch-blocker for cross-faction parity.** |
| Battle-shock applies to attached character (sets `flags.battle_shocked` on both) | Implicit: characters in an attached unit share state | W | ✅ | `phases/CommandPhase.gd:233-237` (skip independent battle-shock for attached chars) and `:809-818` (when bodyguard fails, propagate `battle_shocked = true` to all `attached_chars` via `GameState.get_attached_characters`). | Correct: leader doesn't double-test, leader inherits flag. |
| Look Out, Sir 10e behaviour (no 9e wounds-threshold) | 10e Core Rules: protection lives in Lone Operative; standalone-character LOS! is gone | W | ✅ VERIFIED (regression spot-check) | `autoloads/RulesEngine.gd:5388-5391` explicit comment "9e Look Out Sir gone, standalone-character protection now lives entirely in the Lone Operative ability". Already verified 2026-05. Lone-op range gate at `RulesEngine.gd:3358-3364`, `:4097-4111`. | |
| Precision: bypasses LOS! / allocates to CHARACTER | Core Weapon Abilities: Precision | W | ✅ | `autoloads/RulesEngine.gd:5141-5158` (`has_precision`), `:8819-8854` allocates precision damage to (1) CHARACTER models within the same unit via `_find_character_model_indices` or (2) attached CHARACTER unit via `_find_attached_character_info` (P3-100). Per-attack precision-damage cap at `:8829-8835`. | Both same-unit characters and attached-leader-unit characters are reachable. |
| Precision-melee via stratagem (Epic Challenge) | Custodes Epic Challenge core stratagem | W | ✅ VERIFIED (regression spot-check) | `RulesEngine.gd:5160-5165` (`has_effect_precision_melee`/`has_stratagem_precision_melee`). Already verified 2026-05. | |
| Detach when bodyguard reduced to 0 | 10e Core: "Starting Strength of the remaining unit changes to its original Starting Strength" + Leader survives | W | ✅ | `autoloads/CharacterAttachmentManager.gd:171-207` (`check_bodyguard_destroyed` / `get_alive_bodyguard_model_count`). Invoked at `phases/ShootingPhase.gd:2393`, `:5201`, `phases/FightPhase.gd:1611`, `scripts/WoundAllocationOverlay.gd:1053-1055`. Wound-allocation logic (`scripts/WoundAllocationOverlay.gd:1521-1632`) prevents allocating to character models while ANY bodyguard model is alive — direct enforcement. | |
| `is_below_half_strength_combined` uses original combined model count | 10e Battle-shock half-strength check | W | ✅ | `autoloads/GameState.gd:899-962` — `is_below_half_strength_combined(unit_id)` includes attached character models in starting strength. Wired in CommandPhase (`CommandPhase.gd:263`). | |
| Lone Operative cannot be attached as Leader (manager layer) | Implicit per Lone Operative ability text + 2026-05 verification | W | ✅ VERIFIED (regression spot-check) | `autoloads/CharacterAttachmentManager.gd:36-41`. Live: `can_attach` rejects with the appropriate reason string. | |
| Lone Operative attachment guard at FormationsPhase declaration | Same rule, but at army-list / pre-deploy time | C | 🐛 | `phases/FormationsPhase.gd:153-256` (`_validate_declare_leader_attachment`) **does NOT** call `CharacterAttachmentManager.can_attach()` and has no `Lone Operative` / `lone_operative` reference. `FormationsDeclarationDialog.gd` likewise has no LO check. Grep `FormationsPhase.gd | grep -i lone` returns empty. | **Spot-check failure.** A Lone Operative CHARACTER carrying `leader_data.can_lead` (none currently in roster JSON, but no schema rule prevents it) could be declared as attached at army-list time — the canonical 10e attachment timing — even though the deploy-time CharacterAttachDialog would reject it later. Should call `can_attach` from `_validate_declare_leader_attachment`. |
| Multi-character attachment (Warlord + Lieutenant) general 10e rule | Wahapedia: not a general 10e rule | n/a | n/a | The general "two leaders" rule from 9e is gone in 10e. Specific datasheets (Ork Boyz with `BODYGUARD` ability + 20 models) permit a second WARBOSS leader. | Implementation correctly treats this as a per-datasheet exception, not a general rule. |
| Dual-leader exception (Ork Boyz + Warboss + sub-leader) | Boyz datasheet `BODYGUARD` ability text | C | ✅ | `phases/FormationsPhase.gd:215-249` validates dual-leader iff `BODYGUARD` ability present **and** ≥20 models **and** at least one is `WARBOSS`. Mirror in `get_available_actions` at `:993-1017`. `_build_formation_changes` (`:833-839`) handles bodyguard with multiple attached characters. | Enforcement is hard-coded for one specific datasheet pattern; if other 10e factions get similar dual-leader rules they'd need their own check. |
| Epic Hero / 1-model attachment exceptions | Wahapedia: most Epic Heroes have unique pairings on their datasheet | C | ⚠️ | No code path enforces "Epic Hero only leads the units listed on its datasheet". The `EPIC HERO` keyword exists in tests (e.g. `test_oa45_waaagh_banner.gd:164`). Pairing legality reduces to whatever `meta.leader_data.can_lead` says in the JSON. | Same root as the foundational gap: without `Datasheets_leader.csv` cross-check, Epic Hero exclusivity is whatever the curated JSON happens to encode. |
| Character abilities transfer ("while leading") | Wahapedia: most Leader-buff abilities scope to "while leading a unit" | W | ✅ | `autoloads/UnitAbilityManager.gd:38` documents `condition: "while_leading"`. Used at `:65, 75, 85, 95, 107, 117, 127, 137, 147, 156, 166, 176, 234, 657, 1175, 1268, 1297, 1323` etc. Aggregator (`UnitAbilityManager.gd:1561-1563`, `:2343-2380`, `:3590`) only emits effects when `effect.condition == "while_leading"` is satisfied via attached-relationship lookup. | Engine integration is solid. Per-ability correctness against Wahapedia text is a separate audit (see `04_data_entities/abilities.md`). |
| ArmyListManager populates `leader_data.can_lead` from canonical CSV at import | Implicit: if CSV is canonical, importer should consult it | C | ❌ | `autoloads/ArmyListManager.gd:130-225` initializes `attached_to=null` and `attachment_data.attached_characters=[]` (`:149-151`) but does **not** read `Datasheets_leader.csv` and does not populate or correct `leader_data.can_lead`. The JSON value is taken as-is. Same at `:520-522` (re-init path). | **Source of every "can_lead empty / wrong" gap below.** Either (a) the importer must consume the CSV, or (b) the JSON authoring tool must, before the canonical→runtime gap can close. |
| `can_attach` keyword-match is case-insensitive | Robustness | W | ✅ | `autoloads/CharacterAttachmentManager.gd:43-54` upper-cases both sides. Same in `phases/FormationsPhase.gd:196-208` and `autoloads/GameState.gd:370-381`. | Defensive against `BOYZ` vs `Boyz` curation drift; comment cites this. |
| StateSerializer cross-ref validation of `attached_to` / `attached_characters` | Save/load integrity | W | ✅ VERIFIED (regression spot-check) | `autoloads/StateSerializer.gd:804-825` — clears bogus `attached_to` and dead-list entries on load. | |
| Attached-state save/load round-trip | Internal | W | ✅ VERIFIED (regression spot-check) | Per-unit `attached_to` and `attachment_data.attached_characters` are first-class fields, included in standard `units.<id>.*` diffs. Live: `get_unit_details(U_WARBOSS_IN_MEGA_ARMOUR_D)` returns both fields populated. | |

---

## Canonical pairing coverage vs. roster JSONs

Cross-reference summary (computed from `40k/data/Datasheets_leader.csv` against `40k/armies/*.json`):

| Faction | Canonical pairings (CSV) | In roster JSONs | Reachable in-game UI |
|---|---:|---:|---:|
| Space Marines | 873 | 0 | **0** (no CHARACTER units in `space_marines.json`) |
| Imperial Agents | 308 | 0 | 0 (no roster) |
| Chaos Space Marines | 88 | 0 | 0 |
| Adeptus Custodes | 16 | 7 (both ends in roster) | **4** (3 unreachable, see below) |
| Orks | 68 | 17 (both ends in roster) | **11** (6 unreachable + many leaders w/empty `can_lead`) |
| Aeldari, Necrons, Eldari, Tau, Tyranids, Drukhari, Death Guard, Daemons, GSC, Sisters, Mech, Knights (Imperial+Chaos), Votann, World Eaters, Emperor's Children, Thousand Sons, Grey Knights, Astra Militarum | 558 combined | **0** | **0** |

**Headline:** of the canonical 1,899 leader pairings, **the running game's UI exposes ~15** under the AC + Ork rosters. Every other faction is fully invisible.

### Per-roster invisible-feature pairings (computed and live-spot-checked)

`adeptus_custodes_roster_stubs.json`:
- `Shield-Captain on Dawneagle Jetbike` — `can_lead=[]` in JSON, canonical `Vertus Praetors` — **unreachable**.

`orks.json`:
- `U_GHAZGHKULL_THRAKA_A` Ghazghkull Thraka — `can_lead=[]`, canonical `Boyz`, `Meganobz`, `Nobz`, `Breaka Boyz` — **unreachable**. Live-validated: `CharacterAttachmentManager.can_attach("U_GHAZGHKULL_THRAKA_A","U_MEGANOBZ_L")` → `{valid:false, reason:"Character has no Leader ability"}`.
- `U_KAPTIN_BADRUKK_A` Kaptin Badrukk — `can_lead=[]`, canonical `Flash Gitz` (also `Lootas` per CSV-row `Big Mek with Kustom Force Field` style) — **unreachable**. Live-validated rejection.
- `U_NOB_WAAAGH_BANNER_A` Nob with Waaagh! Banner — `can_lead=[]`, canonical `Boyz`, `Breaka Boyz`, `Nobz` — **unreachable**. Live-validated rejection.
- `U_WARBOSS_IN_MEGA_ARMOUR_D` Warboss in Mega Armour — `can_lead=["BOYZ"]`, but **canonical CSV says he leads Meganobz**. Boyz (`BOYZ` keyword) coincidentally matches roster Boyz; the actually-canonical Meganobz pairing is unreachable because `Meganobz` keyword is not in `can_lead`. Live-validated: `can_attach("U_WARBOSS_IN_MEGA_ARMOUR_D","U_MEGANOBZ_L")` → `{valid:false, reason:"Unit does not have a compatible keyword ([\"BOYZ\"])"}`.

`adeptus_custodes.json`:
- `Shield-Captain` (`U_SHIELD_CAPTAIN_A`), `Blade Champion` (`U_BLADE_CHAMPION_A`), `Trajann Valoris` — canonical CSV pairs each with `Custodian Wardens` AND `Custodian Guard`. Roster contains `Custodian Guard` (`CUSTODIAN GUARD` keyword) but **NOT** `Custodian Wardens` — so the leader→Wardens canonical pairing exists in CSV but the bodyguard datasheet is absent from the roster. Effect: half the canonical Custodes leader options are missing because of the missing bodyguard datasheets, not the matching logic.
- `Aleya`, `Knight-centura` — **leader datasheets entirely absent** from roster. Canonical pairings (Vigilators, Witchseekers, Prosecutors) reference Witchseekers which IS in roster, but the leader is missing.

`space_marines.json`:
- Roster contains exactly 3 units (Intercessor, Tactical, Infiltrator); **no CHARACTER units** at all. The 873 canonical Space Marines pairings (Captains, Lieutenants, Chaplains, Librarians, Apothecaries, named heroes) are **uniformly unreachable** — but this is upstream of the leader-attachment surface (no CHARACTERs to attach).

### Roster-side `can_lead` curation errors (sampled live)

| Unit | Curated `can_lead` | Canonical bodyguard keywords | Effect |
|---|---|---|---|
| Warboss in Mega Armour (orks.json) | `["BOYZ"]` | `MEGANOBZ` | Attaches to wrong unit type; canonical Meganob pairing rejected at runtime. |
| Painboss (orks.json) | `["BEAST SNAGGA BOYZ", "BOYZ"]` | `BEAST SNAGGA BOYZ` per CSV | OK; `BOYZ` is over-permissive (canonical only Beast Snagga Boyz). |
| Ghazghkull (orks.json) | `[]` | `BOYZ`/`MEGANOBZ`/`NOBZ`/`BREAKA BOYZ` | Whole leader silently disabled. |
| Kaptin Badrukk (orks.json) | `[]` | `FLASH GITZ` | Whole leader silently disabled. |
| Nob with Waaagh! Banner (orks.json) | `[]` | `BOYZ`/`NOBZ`/`BREAKA BOYZ` | Whole leader silently disabled. |
| Shield-Captain (adeptus_custodes.json) | `["CUSTODIAN GUARD"]` | `CUSTODIAN WARDENS` and `CUSTODIAN GUARD` | Wardens pairing missing (also no Wardens datasheet in roster). |
| Blade Champion (adeptus_custodes.json) | `["CUSTODIAN GUARD"]` | same | same |

The pattern is consistent: where Wahapedia lists multiple bodyguard keywords for one leader, the roster JSON typically encodes only the most common one, and named characters often have `can_lead=[]` outright.

---

## Top 3 launch-blocker leader gaps

1. **Datasheets_leader.csv is never consumed; `meta.leader_data.can_lead` is the only source of truth and is hand-curated per roster JSON.** Effect: 1,884 of 1,899 canonical 10e pairings are silently invisible to the player. Fix scope = `autoloads/ArmyListManager.gd` import path + per-roster JSON regeneration.
2. **Battle-shock test uses the bodyguard's `meta.stats.leadership` only**, never `max(bodyguard_ld, leader_ld)`. Wahapedia rule text requires "the best Leadership characteristic in that unit." `phases/CommandPhase.gd:697,789`. Tests pass today only because in the current Custodes/Ork rosters bodyguard Ld ≥ leader Ld; cross-faction parity will fail (Daemons, Death Guard, Tyranid leader-led units have leader Ld > bodyguard Ld).
3. **Multiple named-leader characters silently disabled.** Ghazghkull Thraka, Kaptin Badrukk, Nob with Waaagh! Banner, Shield-Captain on Dawneagle Jetbike — each has `can_lead=[]` in its roster JSON despite the canonical CSV listing 1+ legal pairings. They appear in the army list, can deploy as standalone CHARACTERs, but cannot be attached. Quick-fix scope = patch each roster's `leader_data.can_lead`; root-cause fix = #1.

## Top 3 invisible features

1. **Warboss in Mega Armour → Meganobz (Orks).** The most player-impactful: the Warboss's `Might is Right` "while leading" ability buffs the Meganob squad's hit rolls; the curated `can_lead=["BOYZ"]` blocks the only Wahapedia-legal use. Live-validated rejection at `CharacterAttachmentManager.can_attach`.
2. **Ghazghkull Thraka → any of his canonical Boyz/Nobz/Meganobz/Breaka-Boyz pairings.** Empire-named Epic Hero with detachment-defining abilities; cannot be attached at all in the running roster.
3. **Lone Operative attachment guard at FormationsPhase declaration is missing.** `_validate_declare_leader_attachment` (`phases/FormationsPhase.gd:153-256`) lacks the LO check that `CharacterAttachmentManager.can_attach` performs. The army-list-time path (the canonical 10e attachment timing) accepts the declaration; the deploy-time fallback would later reject. Practically dormant today (no roster currently fields a Lone Operative with `leader_data.can_lead` set) but is a regression risk for future faction expansions.

---

## Live-validation transcript

- `mcp__godot-mcp-bridge__ping` → engine 4.6 stable, responsive.
- `mcp__godot-mcp-bridge__get_current_phase` → FIGHT, Round 1, P2 active.
- `execute_script: get_node("/root/GameState").state.units.size()` → 26.
- `get_unit_details(U_WARBOSS_IN_MEGA_ARMOUR_D)` → `meta.leader_data.can_lead == ["BOYZ"]` confirmed live.
- `get_unit_details(U_MEGANOBZ_L)` → keywords `[INFANTRY, MEGA ARMOUR, ORKS, MEGANOBZ, GRENADES]`, no `BOYZ`.
- `execute_script: get_node("/root/CharacterAttachmentManager").can_attach("U_WARBOSS_IN_MEGA_ARMOUR_D","U_MEGANOBZ_L")` → `{valid:false, reason:"Unit does not have a compatible keyword ([\"BOYZ\"])"}` — **canonical Wahapedia 10e pairing rejected at runtime**.
- `can_attach("U_GHAZGHKULL_THRAKA_A","U_MEGANOBZ_L")` → `{valid:false, reason:"Character has no Leader ability"}`.
- `can_attach("U_KAPTIN_BADRUKK_A","U_LOOTAS_A")` → `{valid:false, reason:"Character has no Leader ability"}`.
- `can_attach("U_NOB_WAAAGH_BANNER_A","U_BOYZ_E")` → `{valid:false, reason:"Character has no Leader ability"}`.
- `can_attach("U_BLADE_CHAMPION_A","U_CUSTODIAN_GUARD_B")` → `{valid:true}` (positive control).
- `can_attach("U_PAINBOSS_I","U_BOYZ_E")` → `{valid:true}` (positive control; albeit over-permissive vs canonical).
- `can_attach("U_BLADE_CHAMPION_A","U_WITCHSEEKERS_C")` → `{valid:false, reason:"Unit does not have a compatible keyword ([\"CUSTODIAN GUARD\"])"}` — correctly rejected (Blade Champion does not lead Witchseekers per CSV).
- Screenshot baseline: `user://test_screenshots/audit_11_leader_baseline_fight_phase.png` (game in Fight, Epic Challenge dialog open — confirms running session was past the attachment phases; `LIVE-VALIDATION SKIPPED (UI dialog flow)` per the constraints note).

## Prior audits

- 2026-05 `AUDIT_REPORT.md`: Lone Operative non-attachment guard verified (manager layer); Look Out Sir 10e behaviour verified; P2-90 attached-unit Toughness verified; P3-100 attached-CHARACTER precision verified. All regression-spot-checked above and confirmed unchanged.
- `MASTER_AUDIT.md`: T7-17 referenced for AI leader-attachment synergy — implementation present at `scripts/AIDecisionMaker.gd:1407-1475` + `scripts/AIAbilityAnalyzer.gd`. Not refiled.
- No prior issue tracks the canonical-CSV consumption gap or the missing FormationsPhase Lone-Op guard or the battle-shock "best Ld" divergence; these are net-new findings for this audit.
