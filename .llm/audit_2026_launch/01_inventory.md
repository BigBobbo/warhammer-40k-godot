# Stage 1 — Inventory & Freshness

**Generated:** 2026-05-06
**Scope:** Wahapedia data corpus + active-data refresh state + code consumers + prior audits

---

## 1.1 CSV manifest (`40k/data/`)

`Last_update.csv` timestamp: **2026-05-05 16:28:34**.

| File | Rows | Header columns | Purpose |
|---|---:|---|---|
| `Abilities.csv` | 91 | `id, name, legend, faction_id, description` | Named/core ability catalog (Deep Strike, Feel No Pain, Leader, Oath of Moment, …) |
| `Datasheets.csv` | 1710 | `id, name, faction_id, source_id, legend, role, loadout, transport, virtual, leader_head, leader_footer, damaged_w, damaged_description, link` | Master unit catalog |
| `Datasheets_models.csv` | 1815 | `datasheet_id, line, name, M, T, Sv, inv_sv, inv_sv_descr, W, Ld, OC, base_size, base_size_descr` | Per-model statlines |
| `Datasheets_models_cost.csv` | 2134 | `datasheet_id, line, description, cost` | Points by model count |
| `Datasheets_unit_composition.csv` | 2165 | `datasheet_id, line, description` | "1-3 models" composition |
| `Datasheets_options.csv` | 2826 | `datasheet_id, line, button, description` | Wargear options |
| `Datasheets_wargear.csv` | 9342 | `datasheet_id, line, line_in_wargear, dice, name, description, range, type, A, BS_WS, S, AP, D` | Every weapon profile (special rules in `description`) |
| `Datasheets_abilities.csv` | 7144 | `datasheet_id, line, ability_id, model, name, description, type, parameter` | (datasheet × ability) join — `ability_id` empty for unit-specific inline abilities |
| `Datasheets_keywords.csv` | 15853 | `datasheet_id, keyword, model, is_faction_keyword` | (datasheet × keyword) |
| `Datasheets_stratagems.csv` | 91026 | `datasheet_id, stratagem_id` | (datasheet × stratagem) eligibility |
| `Datasheets_enhancements.csv` | 11582 | `datasheet_id, enhancement_id` | (datasheet × enhancement) eligibility |
| `Datasheets_detachment_abilities.csv` | 16497 | `datasheet_id, detachment_ability_id` | (datasheet × detachment ability) |
| `Stratagems.csv` | 1479 | `faction_id, name, id, type, cp_cost, legend, turn, phase, detachment, detachment_id, description` | Every stratagem with full text |
| `Enhancements.csv` | 926 | `faction_id, id, name, cost, detachment, detachment_id, legend, description` | Every enhancement |
| `Detachment_abilities.csv` | 284 | `id, faction_id, name, legend, description, detachment, detachment_id` | Detachment army-rules |
| `Detachments.csv` | 261 | `id, faction_id, name, legend, type` | Detachment definitions |
| `Factions.csv` | 27 | `id, name, link` | Factions |
| `Source.csv` | 72 | `id, name, type, edition, version, errata_date, errata_link` | Provenance |
| `Last_update.csv` | 2 | `last_update` | Refresh timestamp |

**Source versions covered (Source.csv excerpt):**

- Balance Dataslate v3.4 — 04.03.2026
- Munitorum Field Manual v4.2 — 22.04.2026
- Boarding Actions v1.1 — 09.07.2025
- Faction packs (10e) up to **22.04.2026** for Astra Militarum, Imperial Agents, Orks (v1.3), Space Marines (v1.7); through 01.04.2026 for T'au, Votann, Ad Mech, Thousand Sons, Death Guard, Emperor's Children, World Eaters, Chaos Knights, Imperial Knights; through 11.02.2026 for Aeldari, Chaos Daemons; through 04.03.2026 for Necrons; through 22.10.2025 for Genestealer Cults, Grey Knights.

Data is current as of early May 2026.

---

## 1.2 Stale-data & coverage flags

**`Datasheets_leader.csv`: present (copied 2026-05-06).**
Header: `leader_id|attached_id|`. 1,899 rows. **Caveat:** copied from the older `server/tools/wahapedia_csv/` mirror, so this file does not include any leader/attachment relationships introduced in the +23 datasheets present only in the newer `40k/data/` corpus. Acceptable for breadth audit; flag the ~1% gap when the next refresh pulls a fresh copy.

**Diff `40k/data/` vs `server/tools/wahapedia_csv/`** (older mirror):

| File | `40k/data` | `server/tools` | Δ |
|---|---:|---:|---:|
| Datasheets.csv | 1710 | 1687 | +23 |
| Datasheets_abilities.csv | 7144 | 7032 | +112 |
| Datasheets_detachment_abilities.csv | 16497 | 15706 | +791 |
| Datasheets_enhancements.csv | 11582 | 10438 | +1144 |
| Datasheets_keywords.csv | 15853 | 15687 | +166 |
| Datasheets_models.csv | 1815 | 1793 | +22 |
| Datasheets_models_cost.csv | 2134 | 2105 | +29 |
| Datasheets_options.csv | 2826 | 2791 | +35 |
| Datasheets_stratagems.csv | 91026 | 84572 | +6454 |
| Datasheets_unit_composition.csv | 2165 | 2139 | +26 |
| Datasheets_wargear.csv | 9342 | 9220 | +122 |
| Detachment_abilities.csv | 284 | 270 | +14 |
| Detachments.csv | 261 | 247 | +14 |
| Enhancements.csv | 926 | 870 | +56 |
| Stratagems.csv | 1479 | 1398 | +81 |
| Factions.csv | 27 | 27 | 0 |
| Abilities.csv | 91 | 91 | 0 |
| **Datasheets_leader.csv** | **1900** (copied) | 1900 | 0 |

**Recommendation:**
1. Treat `40k/data/` as canonical for the audit (newer, includes recent dataslate / FAQ).
2. ~~Copy `Datasheets_leader.csv` from `server/tools/wahapedia_csv/`~~ — **done 2026-05-06**.
3. Decide whether `server/tools/wahapedia_csv/` should be deleted to remove ambiguity (low priority).
4. On the next Wahapedia refresh, pull a fresh `Datasheets_leader.csv` matching the newer corpus to close the ~1% gap from older-mirror provenance.

---

## 1.3 Code consumers — what the game actually loads

Grep results for CSV loaders in `40k/`:

| CSV | Loaded by | Status |
|---|---|---|
| `Factions.csv` | `40k/autoloads/FactionStratagemLoader.gd:75` | ✅ runtime |
| `Stratagems.csv` | `40k/autoloads/FactionStratagemLoader.gd` | ✅ runtime |
| `Detachments.csv` | `40k/autoloads/FactionStratagemLoader.gd` | ✅ runtime |
| `Abilities.csv` | (none) | ❌ unused |
| `Datasheets.csv` | (none) | ❌ unused |
| `Datasheets_models.csv` | (none) | ❌ unused |
| `Datasheets_models_cost.csv` | (none) | ❌ unused |
| `Datasheets_unit_composition.csv` | (none) | ❌ unused |
| `Datasheets_options.csv` | (none) | ❌ unused |
| `Datasheets_wargear.csv` | (none) | ❌ unused |
| `Datasheets_abilities.csv` | (none) | ❌ unused |
| `Datasheets_keywords.csv` | (none) | ❌ unused |
| `Datasheets_stratagems.csv` | (none) | ❌ unused |
| `Datasheets_enhancements.csv` | (none) | ❌ unused |
| `Datasheets_detachment_abilities.csv` | (none) | ❌ unused |
| `Detachment_abilities.csv` | (none) | ❌ unused |
| `Enhancements.csv` | (none) | ❌ unused |

**Major finding:** **only 3 of 19 CSVs are loaded by runtime code.** Datasheets, weapon profiles, abilities, keywords, enhancements, and detachment-ability text — the entire unit-data spine — are NOT consumed from the Wahapedia download. The game's actual unit/weapon source is the curated `40k/armies/*.json` rosters loaded by `ArmyListManager.gd`.

**Implications for the audit:**
- The Wahapedia CSVs define **what should be playable** (the spec).
- The `armies/*.json` rosters define **what's actually fielded** (current scope).
- The delta is enormous and is itself a launchability finding (most factions have no roster JSON at all, so they can't be played).

`ArmyListManager.gd` and `CloudStorage.gd` load `armies/*.json`. `MultiplayerLobby`, `MainMenu`, `WebLobby`, `GameState` reference rosters. No code path materializes a roster from `Datasheets.csv` directly.

---

## 1.4 Active rosters (`40k/armies/*.json`)

10 JSON files, but most are variants:

| Roster | Faction | Notes |
|---|---|---|
| `adeptus_custodes.json` | Adeptus Custodes | Curated default |
| `Adeptus_Custodes_1995_Mar_7.json` | Adeptus Custodes | User-uploaded variant |
| `A_C_test.json` | Adeptus Custodes | Test fixture |
| `adeptus_custodes_roster_stubs.json` | Adeptus Custodes | Stubs only |
| `orks.json` | Orks | Curated default |
| `Orks_2000.json` | Orks | Variant |
| `Orks_2000_upload.json` | Orks | Variant |
| `Orks_Upload_Mar7.json` | Orks | Variant |
| `ORK_test.json` | Orks | Test fixture |
| `space_marines.json` | Space Marines | Curated default (small/sparse) |

**Faction coverage:** 3 of 26 factions have any roster — Adeptus Custodes, Orks, Space Marines. **23 factions are catalog-only** (data exists in CSVs but no playable roster).

---

## 1.5 Prior audit artifacts — read before refiling

The new audit must integrate with these (cite issue/PR numbers, do not duplicate findings):

### Top-level repo

| File | Lines | Date | Scope |
|---|---:|---|---|
| `MASTER_AUDIT.md` | 1564 | 2026-02-16 / updated 2026-02-20 | Combined per-phase + AI audit (largest body of T7-* AI items) |
| `AUDIT_COMMAND_PHASE.md` | — | 2026-02-14 | Command phase deep dive |
| `MOVEMENT_PHASE_AUDIT.md` | — | 2026-02-21 | Movement phase deep dive (43 KB) |
| `SHOOTING_PHASE_AUDIT.md` | — | — | Shooting phase |
| `CHARGE_PHASE_AUDIT.md` | — | — | Charge phase |
| `FIGHT_PHASE_AUDIT.md` | — | — | Fight phase |
| `DEPLOYMENT_AUDIT.md` | — | — | Deployment |
| `TERRAIN_LAYOUTS_AUDIT.md` | — | — | Terrain |
| `AI_AUDIT.md` | — | — | AI player |
| `ABILITIES_AUDIT.md` | — | — | Abilities |
| `AUDIT_ABILITIES_2.md` | — | 2026-03-13 | Abilities follow-up (20 KB) |
| `MODEL_ATTRIBUTES_TASKS.md` | — | 2026-03-13 | Model attributes (45 KB) |
| `ORK_ABILITIES_TASKS.md` | — | 2026-03-13 | Ork-specific abilities (26 KB) |
| `LIONS_ARMY_AUDIT.md` | — | — | Lion El'Jonson army |
| `IP_COMPLIANCE_AUDIT.md` | — | — | IP compliance |
| `SAVE_AUDIT.md` | — | — | Save system |
| `SECONDARY_MISSIONS_TASKS.md` | — | 2026-03-01 | Secondary missions |
| `STRATAGEMS_AND_ABILITIES_PLAN.md` | — | — | Stratagem implementation plan |
| `CONSOLIDATED_AUDIT_TASKS.md` | — | — | Combined tasks list |
| `UNDONE_TASKS.md` | — | — | Open items |
| `IMPLEMENTATION_VALIDATION.md` | — | — | Validation log |
| `FEB21_AUDIT.md` | — | 2026-02-21 | Snapshot |

### Under `.llm/`

| File | Lines | Date | Scope |
|---|---:|---|---|
| `.llm/rules-audit.md` | 326 | 2026-05-04 | The user's prior Wahapedia core-rules-vs-code audit (the example query) |
| `.llm/plan.md` | — | — | Plan |
| `.llm/scaled-testing-plan.md` | — | — | Testing plan |

### Canonical 2026-05 audit (per memory)

`40k/test_results/audit_2026_05/AUDIT_REPORT.md` — closed 15 issues via 12 PRs (#324–#348). Substantial verification of: phase machinery, Custodes Martial Mastery + Ka'tah + Praesidium, Orks Waaagh + Plant Banner, stratagem timing windows, weapon keywords (Twin-linked, Sustained Hits, Blast, Hazardous), movement caps, battle-shock, save/load round-trips. **Most "every-game" rules are already verified to spec at this point.**

### Memory

- `project_audit_2026_05` — 2026-05 audit complete, AUDIT_REPORT.md is canonical
- `project_stratagem_sweep_2026_05` — dedicated stratagem audit started 2026-05-04, appends to AUDIT_REPORT.md
- `feedback_pin_tests_arent_live_validation` — pin tests + marker screenshots are NOT validation
- `feedback_live_validation_required` — drive every feature claim live via MCP
- `feedback_mcp_bridge_required` — use MCP bridge for audit-task verification
- `feedback_no_pre_emptive_scoping` — attempt every task; surface BLOCKED if blocked

---

## 1.6 Audit-positioning recommendation

The new audit should **NOT** redo the 2026-05 audit. Its value-add:

1. **Coverage breadth.** 2026-05 covered Custodes + Orks + core stratagems. The CSV corpus has 26 factions, 1,478 stratagems, 925 enhancements, 283 detachment abilities, 90 named abilities, 3,593 inline unit abilities, 9,342 weapon profiles. Most is catalog-only — that's the launchability gap.
2. **Data-pipeline gap.** 16 of 19 CSVs are unloaded. The audit should ask: which of those represent rules the game claims to support but has no source for? (likely Leader attachment data, full datasheet stats vs the curated subset, etc.)
3. **Roster→engine coverage.** Of the 111 distinct abilities used across active rosters, how many have a real engine handler vs. a name-only stub? (Stage 4a will answer.)
4. **Regression net.** Run the 2026-05 spot-checks again to confirm nothing has drifted since the May 4 fixes.
5. **Invisible-feature hunt.** Functions exist but are not reachable from the UI — already a known failure mode flagged in `feedback_pin_tests_arent_live_validation`.

---

## 1.7 Pointer to Stage 2 outputs

Universe extracted by `.llm/audit_2026_launch/extract.py`. Files under `.llm/audit_2026_launch/universe/`:

- `abilities.json` (56 KB) — 70 deduped catalog abilities + ref counts + descriptions
- `weapon_rules.json` (11 KB) — 37 distinct tokens with weapon-use counts
- `keywords.json` (152 KB) — 1,420 distinct keywords
- `stratagems.json` (1,056 KB) — 1,478 stratagems with phase/CP/datasheet eligibility
- `enhancements.json` (396 KB) — 925 enhancements
- `detachment_abilities.json` (171 KB) — 283 detachment army rules
- `roster_priority.json` (6 KB) — what's actually fielded across the 10 JSON rosters
- `_summary.md` — one-page top-line numbers

**Headline universe sizes:**
- Catalog: 70 named abilities, 3,593 inline unit-specific ability rows, 37 weapon-rule tokens, 1,420 keywords, 1,478 stratagems, 925 enhancements, 283 detachment abilities, 26 factions × ~10 detachments each
- Active rosters use only: 111 distinct abilities, 19 distinct weapon-rule tokens, 3 of 26 factions

---

## 1.8 Ready-to-launch audit prompts

Stage 3+ can now run. The next stages should reference:

- **Catalog ground truth:** `.llm/audit_2026_launch/universe/*.json`
- **Code root:** `40k/`
- **Roster ground truth:** `40k/armies/*.json`
- **Prior findings:** `MASTER_AUDIT.md`, `.llm/rules-audit.md`, `40k/test_results/audit_2026_05/AUDIT_REPORT.md`, `AUDIT_*.md` at repo root
- **Wahapedia rules pages:** https://wahapedia.ru/wh40k10ed/the-rules/core-rules/ + commentary + designers' commentary + faqs-and-errata
