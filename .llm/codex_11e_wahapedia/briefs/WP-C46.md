# WP-C46 — Codex: Adeptus Custodes (11e) detachment rules (13) + enhancements (29)

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf` AFTER WP-C3
merged (you use its Favoured Ka'tah API). Godot project: `40k/`.

Read first:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md`
3. `.llm/codex_11e_wahapedia/custodes/RULES.md` (each detachment's rule,
   Favoured Ka'tah rider and enhancements, printed)
4. `40k/scripts/codex/custodes/CustodesKatah.gd` (the Favoured Ka'tah hook
   from WP-C3)
5. `40k/autoloads/FactionAbilityManager.gd` (the 10e Custodes detachment code
   you replace)

## Scope

**1. All 13 detachment rules:**
- Guardians of the Throne: Martial Mastery
- Aquilan Shield: Gilded Guardians
- Dread Host: Instruments of the Emperor's Wrath
- Emperor's Chosen: Magna Imperator
- Emissaries Imperatus: Heralds of the Throne
- Shadowkeepers: Wardens of the Dark Cells
- Solar Watch: Talon Sortie
- Honoured Companions: Companion's Watch
- Auric Champions: Assemblage of Might
- Lions of the Emperor: On Gilded Wings
- Might of the Moritoi: Moritoi Ancients
- Grav-Assault Force: Flare Shields
- Null Maiden Vigil: Silent Sisterhood

Include each Unique: Shield Host detachment's Favoured Ka'tah additional
effect, through the WP-C3 hook. Include the detachment-granted keywords and
BATTLELINE (e.g. Prosecutor Squad in Null Maiden Vigil), and the Null Maiden
Vigil warlord allowance (WP-C3 left a hook).

**2. All 29 enhancements:**
- Each one's effect, implemented.
- Army-construction validation:
  - bearer restrictions as printed
  - one of each per army
  - the existing per-1000-points cap
- Generalise `ArmyListManager`'s Shield Host-specific enhancement validation
  (~line 969) to data-driven checks against `40k/data/40kdc/enhancements.json`
  (`rules_text`, `detachment_id`).
- The army builder UI must offer the codex enhancements for the selected
  detachment. Check how the in-game builder / main menu lists them and fix it
  if it reads stale data.

**3. Delete the 10e Custodes detachment code:** Shield Host, Silent Hunters,
Talons of the Emperor, Tharanatoi Hammerblow, Solar Spearhead, and the old
Lions of the Emperor / Auric Champions / Null Maiden Vigil / Might of the
Moritoi implementations, plus their 10e enhancements (Auric Mantle,
Castellan's Mark, Hall of Armouries, Panoptispex, Admonimortis, ...). Their
tests are retired in `RETIRED_TESTS.md` with reasons.

**4. AI:** every choice (e.g. Auric Champions' dreadful foe selection, the
Martial Mastery Sustained/Lethal choice) is made without stalling.

## Validation (IMPLEMENTATION.md §5 — all of it)

- **Headless:** `tests/test_custodes_detachments_11e.gd` and
  `tests/test_custodes_enhancements_11e.gd`, one group per rule /
  enhancement, added to `run_pretrigger_tests.sh`.
- **Windowed scenarios:**
  - `cus11e_det_<slug>.json` for each detachment rule with a visible effect
    or choice
  - `cus11e_enh_<slug>.json` for at least the activated enhancements
  - one scenario that builds an army with an enhancement through the real
    builder UI
  - real clicks, PASS, screenshots
  - `GODOT_MCP_PORT=9380`, `flock /tmp/codex11e_godot_window.lock`
- **Full gate:** green apart from the documented baseline failures.
- **Docs:** changelog bullets in `changelog/WP-C46.md`; rulings in
  `RULINGS.md`.

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: per rule / enhancement status, rulings, tests +
counts, full gate, scenario PASS list, screenshots, anything not done or not
validated.
