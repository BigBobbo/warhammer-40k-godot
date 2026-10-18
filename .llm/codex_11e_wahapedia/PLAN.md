# Wahapedia 11e import — Adeptus Custodes + Orks — plan

Status: PLAN (2026-10-17). Nothing implemented yet.

- Codex: Adeptus Custodes was released 2026-10-17. Codex: Orks shipped earlier, but the
  game only has its stratagems (PR #917).
- 40kdc-data has **not** shipped either codex's datasheets: npm `latest` is 1.4.5, and
  the repo's main branch was last committed 2026-09-22.
- Wahapedia is therefore the source until 40kdc catches up.

Three tracks:
- **W:** the shared Wahapedia import pipeline.
- **C:** Codex: Adeptus Custodes.
- **O:** Orks 11e completion.

C and O both depend on W0–W2 and are otherwise independent.

## Progress (updated by the integrator)

| Phase | Status |
|---|---|
| W0–W2 pipeline + data tests | ✅ `e704330`: wahapedia-import / curate-from-wahapedia / verify-wahapedia-import, `npm run codex11e`, `test_wahapedia_11e_import_data.gd` |
| C1 / O1 data | ✅ 29 Custodes + 55 Ork codex datasheets; AC stratagem/detachment rows; Ork curated stratagems re-verified (no errata) |
| C2 / O2 army files | ✅ all 16 lists regenerated (codex sizes/points, Legends kept); legacy 1.0.19 Custodes kits frozen (D1). Save fixtures / AI-lab baselines NOT regenerated (they stay as pre-codex saves; re-baseline at the end) |
| Rules phase | contract: `IMPLEMENTATION.md`; briefs in `briefs/`. Merged: WP-C3, WP-O34, WP-O6, WP-C5. Running: WP-C46, WP-O5, WP-C7 |
| C3 army rules | ✅ merged (Ka'tah rework, Aegis, Aquila Commander without the 10e bonus-CP cap, Daughters) |
| O3/O4 army + detachments | ✅ merged (WP-O34) |
| C5 stratagems | ✅ merged `dc5f3aa1`: all 41 Custodes codex stratagems in their windows, 41 `cus11e_<slug>` scenarios (agent: all PASS, gate 6160/0); integrator re-ran 9 headless tests (0 failures) + 10 scenarios incl. Ork regressions (all PASS). Gaps: phase_end windows not opened in networked games; NO ESCAPE / RAPID REACTIONS / SELFLESS SERVICE moves auto-resolved (no interactive UI) |
| O6 datasheet abilities | ✅ merged `eddec58c`: 99 of 107 audited abilities implemented/re-implemented (`ork_abilities_audit.md`), 31 10e-only abilities deleted, 37 `ork11e_ab_*` scenarios; integrator re-ran 9 headless tests (0 failures) + 8 scenarios (all PASS). Not implemented: Deff from the Shadows, Pilin' Out, Pulse Jet, Big'ed Bossbunka's three, Runnin' wiv da Herd keyword swap, Get Out da Way! |

Known follow-ups:
- Tutorial: `tutorial_orks.json` / `tutorial_custodes.json` stay on their
  pre-codex rosters. Lessons T4–T7 load frozen save fixtures built from them,
  and the lesson text names those units. Rebuild the tutorial fixtures and
  text for the codex rosters.
- `recon_stomps.json` is 2270/2000 pts with codex Ork points; the shipped
  Ork AI plans are authored against that roster, so it was kept whole.
  Re-author the plans for a legal list.

## Decisions (owner, 2026-10-17)

| # | Question | Answer |
|---|---|---|
| D1 | Old saves: keep the pre-codex Custodes units playable, or convert? | **Proposal applied** (owner said "kick this off" without choosing): old saves keep their units through legacy kits; shipped army files converted. Reversible if the owner prefers conversion |
| D2 | Legends units | **Ignore.** Do not import them, do not build them, do no work on them. Existing game entries are left as they are |
| D3 | Boarding Actions detachments (Custodes: Voyagers in Darkness, Black Ship Guardians; Orks: Ramship Raiders, Kaptin Killers) | **Out of scope** |
| D4 | Switch to 40kdc-data once it ships the codexes? | **Yes.** See W4 |

### D1 — the "old" Custodes units

These are the units the game has today that are not in the 11e codex under the same
name:

| Game unit today | 11e status | Used by shipped army files |
|---|---|---|
| Custodian Guard | Renamed → Custodian Guard Sodality (Sentinel Guard Sodality is a new sibling) | adeptus_custodes, custodes_lions, Adeptus_Custodes_1995_Mar_7, custodes_web_built_repro, tutorial_custodes |
| Prosecutors | Renamed → Prosecutor Squad | custodes_lions, Adeptus_Custodes_1995_Mar_7, adeptus_custodes_roster_stubs |
| Witchseekers | Renamed → Witchseeker Squad | adeptus_custodes, tutorial_custodes, Adeptus_Custodes_1995_Mar_7, A_C_test |
| Vigilators | Renamed → Vigilator Squad | — |
| Venatari Custodians | Split → Venatari with Verutum Lances / with Kinetic Destroyers | — |
| Aquilon Custodians | Split → Aquilon Terminators with Solarite Power Gauntlets / Talons | — |
| Agamatus Custodians | Gone. The nearest equivalent is the new Gyrfalcon Jetbike Sodality | — |
| Aleya, Valerian, Venerable Contemptor Dreadnought, Venerable Land Raider, Sagittarum Custodians, Custodian Guard with Adrasite and Pyrithite Spears | Legends (D2: ignore) | — |

The other 18 units keep their names, but **every profile, points cost and most unit
sizes change**. In a save these units become "old" too: they carry the pre-codex
stats, because saves embed unit stats in `meta.stats`.

## Source snapshot (this directory)

- **`extract_snapshot.py`** regenerates everything below from a fresh Wahapedia export.
  - Run `python3 -I extract_snapshot.py <export_dir> <AC|ORK> <out_dir> [page.html]`.
  - The export lives at `https://wahapedia.ru/wh40k11ed/<Name>.csv`.
- **`custodes/`** and **`orks/`** hold `wahapedia/*.csv`, filtered to the faction. The
  export is stamped 2026-10-16 21:03.
- **`RULES.md`** in each folder has readable army rules, plus each detachment's rule,
  enhancements and stratagems.
- **Custodes ka'tah abilities** are not in the CSV export. They are scraped from the
  faction page HTML. Orks may also have page-only text, e.g. the Special Move Types
  body, which is empty in the CSV; check before relying on it.
- Wahapedia is community-transcribed, so spot-check against the printed codex.

---

## Track W — Wahapedia import pipeline (shared)

### W0 — converter
- **Script:** `scripts/40kdc/wahapedia-import.mjs --faction AC|ORK --in <snapshot>`.
- **What it does:** maps Wahapedia CSVs into the 40kdc JSON shapes the game already
  reads:
  - `units` (profiles, points tiers, keywords, base size, model_count)
  - `weapons`
  - `abilities`
  - `unitCompositions`
  - `wargearOptions`
  - `leaderAttachments`
  - `enhancements`
  - `detachments`
- **Ids:** keep the existing 40kdc ids (`adeptus-custodes::shield-captain`, slug-style
  weapon ids) wherever a datasheet keeps its name, so army files and code that key on
  ids don't break. New datasheets get ids in the same slug scheme.
- **Points:** tiers ("YOUR 1ST TO 2ND UNITS COST" / "3RD+") become
  `points[].unit_count_min/max`. Wargear costs such as "per Praesidium Shield = 25"
  need a field; check how 40kdc encodes wargear points and match it.
- **Skipped:** Legends sources (D2) and Boarding Actions rows (D3).

### W1 — splice
- Splice the converter output over the 40kdc extract **for one faction only**. Every
  other faction's rows stay byte-identical, the same policy as the Orks `--only-faction`
  work.
- Regenerate that faction's rows in `Datasheets.csv`, `Datasheets_leader.csv`,
  `Detachments.csv` and `Stratagems.csv` (`generate-stratagems.mjs` /
  `generate-leader-pairings.mjs --only-faction`).
- Before overwriting, freeze the current kits with `legacy-kits.mjs` (D1).

### W2 — data tests
- Add `tests/test_wahapedia_import_<faction>.gd`. For every non-Legends datasheet it
  checks:
  - the profile (M/T/Sv/invuln/W/Ld/OC) matches the snapshot
  - every points tier matches
  - the weapon profiles match
  - the model counts match
  - the leader pairings match
- Also check the detachment, enhancement and stratagem counts.
- Add the test to `run_pretrigger_tests.sh`.
- Before and after the splice, compare `UnitLoadoutResolver` output for every army file.
  Any change must be explained by the codex.

### W3 — web builder
- Re-run `bundle-browser` so the web army builder sees the new data. It is still on
  1.0.19 (Ork doc §7.3).
- Update `gameformat.mjs` `UNIT_ALIASES` for the renames.

### W4 — switch back to 40kdc (D4)
When a 40kdc-data release contains a faction's codex:
1. Bump the package and extract.
2. Diff its output against the Wahapedia-import output for that faction.
3. Fix any discrepancies against the printed codex.
4. Drop that faction from the import splice.

Keep the W2 tests; they become the regression net for 40kdc data.

---

## Track C — Codex: Adeptus Custodes

### Gap (game today vs codex)

| Area | Game today | Codex 11e |
|---|---|---|
| Martial Ka'tah | Dacatarai or Rendax stance per unit, chosen in the Fight phase | Each unit is **readied** at the start of the Command phase and uses one of 6 once per turn (full text in `custodes/RULES.md`): Conservai (Cmd), Calistus (Move), Salvus (Shoot), Dacatarai / Kaptaris (start of Fight), Rendax (selected to fight) |
| Other army rules | Daughters of the Abyss (old wording) | Aegis of the Emperor (FNP 5+ vs mortal wounds) and Aquila Commander (+1CP each battle round) are new. Daughters of the Abyss is reworded with a Psychic Null 6" aura |
| Detachments | 9 (Shield Host, Lions, Auric Champions, Solar Spearhead, Null Maiden Vigil, Talons, Moritoi, Silent Hunters, Tharanatoi Hammerblow) | 13. Five old ones are removed; kept names have new rules; 6 are Unique: Shield Host with a Favoured Ka'tah |
| Stratagems / enhancements | 45 stratagem rows | 41 stratagems + 29 enhancements |
| Datasheets | 31 | 27 codex + 2 Forge World. Renames and splits are listed in D1 |
| Stats / points | e.g. Shield-Captain M6 T6 W6, 110 pts | **All** profiles change (about +2" M, +1 T, more W, Ld 5+); Shield-Captain is 180/200; Wardens go from 4-5 models to 2-3 |
| Datasheet abilities | Hand-coded | 46 named abilities; diff not done yet |

### Phases
- **C1 — data:** run W0–W2 for `AC`.
- **C2 — migrate:**
  - Hand-migrate the shipped army files listed in D1, plus `A_C_test.json`:
    - renames
    - new unit sizes
    - detachments (Shield Host → e.g. Guardians of the Throne)
    - valid enhancements
    - points within the limit
  - Add `armies/custodes11e_codex_test.json`, covering every codex datasheet.
  - Retire the 10e-only tests (about 71 files mention Custodes) into
    `custodes_codex_11e_retired_tests.md`.
  - Regenerate the Custodes saves and fixtures (`mirror_custodes_*`, `asym_2000_*`,
    `*_pretrigger`, tutorial).
  - Re-baseline the AI lab.
- **C3 — army rules:**
  - Ka'tah rework:
    - a `custodes_readied` flag
    - a ka'tah panel offered in each window through the BasePhase window framework
    - Favoured Ka'tah riders
    - remove the old stance code (FactionAbilityManager:3191-3280, and 58 FightPhase
      refs)
  - Aegis of the Emperor, in every mortal-wound path.
  - Aquila Commander.
  - Daughters of the Abyss / Psychic Null.
  - AI ka'tah heuristics.
- **C4 — 13 detachment rules**, grouped by mechanic:
  - fight: Guardians of the Throne, Dread Host
  - objective auras: Aquilan Shield, Shadowkeepers, Honoured Companions
  - re-rolls: Emperor's Chosen
  - Fights First: Emissaries Imperatus
  - movement: Solar Watch, Lions of the Emperor
  - characteristics / invuln: Might of the Moritoi, Grav-Assault Force
  - targeting / warlord: Auric Champions, Null Maiden Vigil

  Delete the 10e detachment code.
- **C5 — 41 stratagems:**
  - Add a `scripts/stratagems/custodes_codex/CustodesCodex11e.gd` registry, using the
    Ork pattern: csv_id dispatch, `custom:custodes11e` marker, group scripts.
  - Each stratagem needs a headless test plus a windowed scenario
    (`tests/scenarios/sp/cus11e_*.json`).
- **C6 — 29 enhancements:**
  - Add handlers.
  - Generalise the ArmyListManager enhancement validation; it is Shield Host-specific
    at ~:969.
- **C7 — 46 datasheet abilities:**
  - Diff against UnitAbilityManager / RulesEngine.
  - Rewrite the changed abilities (e.g. Moment Shackle, Master of Ka'tahs) and add the
    new ones.
  - Remove the hard-coded Custodes Deep Strike backfill (ArmyListManager 253, 662,
    814-860).

---

## Track O — Orks 11e completion

### Gap (game today vs Wahapedia 11e)

| Area | Status |
|---|---|
| Stratagems (40) | ✅ Shipped in PR #917 from the curated `scripts/40kdc/curated/orks_codex_11e.json`. Re-verify against the 2026-10-16 export (O1) |
| Datasheets | 54 codex + 1 Forge World on Wahapedia; all are present in the game. The game also has 5 "'Ardmob" units that are not on Wahapedia's 11e list; their origin is unchecked |
| Stats | **19 of 63** matched profiles differ, e.g. Battlewagon T10→11, Warboss in Mega Armour T6→7, Morkanaut M8→9 and Sv3+→2+, Warbikers W4→3 |
| Points | **25 of 55** units differ, e.g. Gargantuan Squiggoth 440/490 → 500/600, Big Mek 85/95 → 100/115 |
| Weapons | Not diffed yet (W2 will report it) |
| Army rules | Waaagh! (riled up) was done in #917. Da Boss has code; check its wording (+1CP at the start of the battle round if the warlord has it). **Unstable Energies** (psyker levels) has **no code** |
| Detachment rules (15) | **No code** for Madcap Meks, Wurrband, Runt Swarm, Wreckas, Brute Bosses, Shoota Boyz, Flyboyz. **10e-era code runs on the name** for War Horde, Bully Boyz, Da Big Hunt, Dread Mob, Kult of Speed, Blitz Brigade, Green Tide, Taktikal Brigade (FactionAbilityManager); it needs a diff against 11e text and is assumed wrong until checked |
| Enhancements (38) | None implemented for 11e. 10e code fires only for names it knows (Ork doc §7.3) |
| Datasheet abilities | 98 named abilities; diff not done yet |

### Phases
- **O1 — data:**
  - Run W0–W2 for `ORK`; this fixes the stats and points.
  - Diff the curated stratagem file against `orks/wahapedia/Stratagems.csv` and apply
    any errata.
  - Find out where the 'Ardmob units come from and keep them if they are intentional.
- **O2 — migrate:**
  - Re-validate the Ork army files (`orks.json`, `orks_taktikal.json`,
    `Orks_2000*.json`, `Orks_Upload_Mar7.json`, `ORK_test.json`, `ork11e_codex_test.json`,
    `tutorial_orks.json`) against the new points and sizes.
  - Regenerate the Ork mirror / asym fixtures.
  - Re-baseline the AI lab; the Ork mirror baselines shift.
- **O3 — army rules:**
  - Check Da Boss and fix it if needed.
  - Implement Unstable Energies: psyker level budget per battle round, enforced in
    every psychic-ability path, with UI feedback when it is spent.
- **O4 — 15 detachment rules:**
  - Diff the 8 existing implementations against `orks/RULES.md` and fix them in place.
  - Implement the 7 missing ones.
  - Add one registry module, following the Ork stratagem pattern
    (`scripts/stratagems/ork_codex/` or a sibling `ork_detachments/`).
  - Each rule needs a headless test and a windowed scenario.
- **O5 — 38 enhancements:**
  - Add handlers and update army-builder validation.
  - Retire the 10e enhancement name-matching for Orks.
- **O6 — 98 datasheet abilities:** diff and rewrite where changed.

---

## Shipping (each track phase = one PR)
- Prepend a `version_history.json` entry for each player-facing phase.
- Every UI-affecting phase needs a windowed scenario plus screenshots (CLAUDE.md gate).
- Finish with full AI-vs-AI games: Custodes vs Orks, and both mirrors.

## Suggested order
1. W0–W2 (one PR, both factions).
2. C1 + O1.
3. C2 + O2.
4. Then C3–C7 and O3–O6 in parallel. They touch different files, apart from the
   FactionAbilityManager detachment table, so lock on it.

## Risks
- The ka'tah windows touch every phase, so Fight phase regressions are the most likely.
- Points and unit sizes change for both factions, so every AI-lab baseline and fixture
  shifts. Re-baseline once, after C2 + O2, not per PR.
- Wahapedia transcription errors, which W4 will surface when 40kdc ships.
- Wargear-points encoding (Praesidium Shield) may need a schema field the game doesn't
  read yet.
