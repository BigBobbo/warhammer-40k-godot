# Codex: Adeptus Custodes (11th edition) — update plan

Status: PLAN (2026-10-17). Nothing implemented yet.
Codex street date: 2026-10-17. 40kdc-data has **not** shipped it (npm `latest` = 1.4.5,
repo main last commit 2026-09-22), so Wahapedia is the source.

## Source snapshot (committed alongside this plan)

- `wahapedia/*.csv` — the Wahapedia 11e export (`Last_update` 2026-10-16 21:03),
  filtered to `faction_id=AC` / AC datasheet ids. Same column layout as Wahapedia's
  export spec (pipe-delimited, HTML in text fields).
- `RULES.md` — readable text of the army rules, the 6 ka'tah abilities (scraped from
  the faction page HTML; they are **not** in the CSV export), and every detachment's
  rule / enhancements / stratagems.
- Wahapedia book row: "Adeptus Custodes — App — 11 — v2.8.1 — October 2026".

## What changed vs. the game today (game = 40kdc 1.4.5, i.e. pre-codex)

| Area | Game today | Codex 11e |
|---|---|---|
| Martial Ka'tah | Pick Dacatarai or Rendax stance per unit in Fight phase | Each unit **readied** at start of Command phase; spend once per turn on one of 6: Conservai (Cmd: actions while engaged/shocked + shoot after action), Calistus (Move: move through models), Salvus (Shoot: ignore BS/hit/wound modifiers), Dacatarai (start Fight: RR hit 1s vs non-MON/VEH), Kaptaris (start Fight: -1 to be hit in melee), Rendax (selected to fight: Lethal Hits vs MON/VEH) |
| Other army rules | — | **Aegis of the Emperor** (FNP 5+ vs MW), **Aquila Commander** (+1CP each battle round if warlord has it), Daughters of the Abyss reworded (FNP 3+ vs psychic; 6" aura FNP 5+ vs psychic), Special Move Types |
| Detachments | 9: Shield Host, Lions, Auric Champions, Solar Spearhead, Null Maiden Vigil, Talons, Moritoi, Silent Hunters, Tharanatoi Hammerblow | 13 (+2 Boarding Actions): Guardians of the Throne (3DP), Aquilan Shield, Dread Host, Emperor's Chosen, Emissaries Imperatus, Shadowkeepers, Solar Watch, Honoured Companions, Auric Champions, Lions of the Emperor, Might of the Moritoi, Grav-Assault Force, Null Maiden Vigil. Removed: Shield Host, Solar Spearhead, Talons, Silent Hunters, Tharanatoi Hammerblow. Kept names have **new** rules. 6 are Unique: Shield Host with a Favoured Ka'tah |
| Stratagems / enhancements | 45 strat rows | 41 strats + 29 enhancements (13 detachments); Boarding Actions adds 8 + 4 |
| Datasheets | 31 | 27 codex + 2 Forge World; 7 moved to Legends (Aleya, Valerian, Venerable Contemptor, Venerable Land Raider, Sagittarum, Custodian Guard w/ Adrasite / Pyrithite) |
| Renames / splits | Custodian Guard, Prosecutors, Vigilators, Witchseekers, Venatari, Aquilon | Custodian Guard **Sodality**, Sentinel Guard Sodality (new), Prosecutor/Vigilator/Witchseeker **Squad**, Venatari split ×2, Aquilon split ×2 (Gauntlets / Talons), Gyrfalcon Jetbike Sodality (new; Agamatus gone), Caladius **Annihilator** Grav-Tank (new) |
| Stats | e.g. Shield-Captain M6 T6 W6 Ld6+ | **Every** Custodes profile changed: ~M+2", T+1, W+1..+3, Ld 5+. 22/22 matched profiles differ |
| Points / sizes | e.g. Shield-Captain 110, Wardens 4-5 models | e.g. Shield-Captain 180/200, Wardens **2-3** models 200/295; "1st–Nth unit" tiered pricing |
| Datasheet abilities | hand-coded (Sentinel Storm, Moment Shackle, …) | 46 named abilities across 29 sheets (`wahapedia/Datasheets_abilities.csv`) — not yet diffed against code |

Net: this is a full faction rewrite, larger than the Orks codex (which kept datasheets and
only replaced stratagems).

## Approach

Follow the Orks 11e template (`.llm/ork_codex_11e_design.md`, commit `886f1f8`,
PR #917): curated JSON + `--only-faction` splices + one codex module with a registry.
The difference is that datasheets also come from Wahapedia, not from 40kdc.

**Data policy**
- A new converter, `scripts/40kdc/wahapedia-import.mjs --faction AC`, maps the snapshot
  CSVs into the 40kdc JSON shapes (`units`, `weapons`, `abilities`, `unitCompositions`,
  `wargearOptions`, `leaderAttachments`, `enhancements`, `detachments`) for
  `adeptus-custodes` only. It is spliced over the extract, so every other faction stays
  byte-identical.
- Curated rules file `scripts/40kdc/curated/custodes_codex_11e.json` with the same schema
  as `orks_codex_11e.json` (detachments + stratagems with csv_id/windows/when/target/effect),
  plus enhancements. Run `generate-stratagems.mjs --only-faction AC` and
  `generate-leader-pairings.mjs --only-faction AC`.
- Freeze the current Custodes kits into `40k/data/40kdc/legacy/` via `legacy-kits.mjs`, so
  old saves/rosters still resolve. Legends units stay loadable through legacy and are
  flagged Legends.
- When 40kdc ships the codex, swap the converter output for theirs and diff.

## Phased task list

Each phase is a mergeable PR. Phases 3–6 can run in parallel (separate group scripts).

### P0 — Data import (no rule behaviour)
1. `wahapedia-import.mjs` + splice; regenerate AC rows of `Datasheets.csv`,
   `Datasheets_leader.csv`, `Detachments.csv`, `Stratagems.csv` (`effects_json` =
   `[{"type":"custom:custodes11e"}]`).
2. Legacy-freeze the old kits; update `UnitLoadoutResolver` key mapping for the renames.
3. `tests/test_custodes_codex_11e_data.gd`: 27+2 datasheets, every profile stat/points
   row matches the snapshot, 13 detachments, 41 strats, 29 enhancements, leader pairings.
   Add it to `run_pretrigger_tests.sh`.
4. Points-tier support check: tiered "1st–2nd / 3rd+" costs already map to
   `unit_count_min/max`; verify the army builder prices the 3rd copy correctly.

### P1 — Migrate armies, fixtures, retired tests
1. Hand-migrate `adeptus_custodes.json` (Shield Host → e.g. Guardians of the Throne),
   `custodes_lions.json`, `Adeptus_Custodes_1995_Mar_7.json`, `tutorial_custodes.json`,
   `custodes_web_built_repro.json`, `adeptus_custodes_roster_stubs.json`: renamed units,
   new unit sizes, valid enhancements, and points that stay in the declared limit.
2. Add `armies/custodes11e_codex_test.json`, which covers every new datasheet.
3. Retire the 10e-only tests (about 71 files mention Custodes, e.g.
   `test_custodes_lions_silent_hunters.gd`, `test_vigilance_eternal_sticky_392.gd`,
   `test_castellans_mark_redeploy_397.gd`). Record them in
   `custodes_codex_11e_retired_tests.md`, the same way the Orks work did.
4. Regenerate the Custodes saves (`mirror_custodes_*`, `asym_2000_*`, `*_pretrigger`)
   with `make_mirror_fixture.py` / `make_asym_fixture.py` / `make_2000pt_fixture.gd`,
   then the tutorial fixtures. Re-baseline the AI lab where `asym_2000` changes.

### P2 — Army rules
1. **Martial Ka'tah rework.** Add a per-unit `custodes_readied` flag, set at the start of
   the Command phase. Add a `KatahPanel` (replacing `KatahStanceDialog`) that offers each
   ka'tah in its window via the BasePhase window framework. The windows are Command,
   selected to move, selected to shoot, start of Fight ×2 and selected to fight.
   Remove the old stance code in FactionAbilityManager:3191-3280 and the FightPhase
   references (58).
2. Add Aegis of the Emperor (FNP 5+ vs mortal wounds) to every save/MW path.
3. Add Aquila Commander, gaining +1CP at the start of the battle round for the warlord.
   Check the 11e CP cap.
4. Rework Daughters of the Abyss and add the Psychic Null aura.
5. Favoured Ka'tah hook: if the selected detachment's favoured ka'tah is the one used,
   apply that detachment's extra effect.
6. AI: a ka'tah choice heuristic per window, which must never stall.

### P3 — Detachment rules (13), group by mechanic
- **Fight:** Guardians of the Throne (Sustained/Lethal choice when selected to fight) and
  Dread Host (re-roll charges, plus a pile-in punish rider).
- **Defensive objective auras:** Aquilan Shield, Shadowkeepers (an S > T style reduction
  near objectives) and Honoured Companions (re-roll wound rolls of 1 for Trusted
  Sentinel units near objectives).
- **Re-roll one:** Emperor's Chosen.
- **Fights First:** Emissaries Imperatus.
- **Movement:** Solar Watch (fall back and still charge) and Lions of the Emperor
  (Terminators go to strategic reserves at the end of the opponent's Fight phase).
- **Characteristics / invuln:** Might of the Moritoi (OC by strength) and Grav-Assault
  Force (4+ invuln vs ranged).
- **Targeting / warlord:** Auric Champions (dreadful foe) and Null Maiden Vigil (Anathema
  Psykana warlord, Prosecutors gain Battleline).
- Delete the 10e detachment code for Shield Host, Silent Hunters, Talons, Tharanatoi and
  Solar Spearhead, plus the old Lions and Auric Champions code.

### P4 — Stratagems (41)
- Add `scripts/stratagems/custodes_codex/CustodesCodex11e.gd` (registry keyed by
  csv_id), with group scripts Fight / Shooting / ShootingReactive / Movement / Other.
- Reuse the Ork window framework (§3, §6 of the Ork doc).
- Each stratagem gets a headless handler test and a windowed scenario that drives the
  real window (`tests/scenarios/sp/cus11e_*.json`).

### P5 — Enhancements (29)
- Enhancement handlers live in the same module.
- Update ArmyListManager enhancement validation (line ~969 is Shield Host-specific) and
  the web army builder.

### P6 — Datasheet abilities (46)
- Diff `wahapedia/Datasheets_abilities.csv` against UnitAbilityManager/RulesEngine.
- Rewrite the changed abilities (Sentinel Storm, Moment Shackle and Master of Ka'tahs,
  which now interacts with readied units) and add the new ones (e.g. Living Fortress,
  Swift Ruin, Neutronium Cascade Mine).
- Clean up the hard-coded Custodes Deep Strike backfill in `ArmyListManager.gd`
  (lines 253, 662 and 814-860).

### P7 — Polish & ship
- Prepend a `version_history.json` entry (minor bump).
- Do a full windowed run: a Custodes vs Orks game under the AI.
- Capture screenshots of the ka'tah panel, a stratagem window and the army builder.
- Update ATTRIBUTION (Wahapedia-sourced faction).

## Open decisions (need owner input)
1. **Old saves/rosters:** migrate them to the codex, or keep the old kits playable as
   "legacy"? The proposal is legacy for saves and migration for the shipped army files.
2. **Legends units:** keep them buildable (flagged) or hide them? Wahapedia lists 7.
3. **Boarding Actions** detachments (Voyagers in Darkness, Black Ship Guardians): out of
   scope unless the game supports Boarding Actions.
4. **Source of truth when 40kdc catches up:** switch to 40kdc, or keep the Wahapedia
   import?

## Risks
- Wahapedia text is community transcription, so spot-check against the physical codex.
- The ka'tah windows touch every phase, so regressions are likely in the Fight phase
  (58 old refs).
- Wardens drop from 4-5 to 2-3 models and points roughly +60%, so every Custodes AI-lab
  baseline and fixture shifts.
