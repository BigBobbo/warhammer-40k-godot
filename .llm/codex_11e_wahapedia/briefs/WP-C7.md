# WP-C7 — Codex: Adeptus Custodes (11e) datasheet abilities

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf` AFTER WP-C3
merged. Godot project: `40k/`.

Read first:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md`
3. `.llm/codex_11e_wahapedia/import_report_custodes.md`
4. `custodes/wahapedia/Datasheets_abilities.csv` with `Datasheets.csv` (the
   printed text of the 46 named abilities on the 29 codex datasheets)
5. `40k/autoloads/UnitAbilityManager.gd` (`ABILITY_EFFECTS`; the Custodes
   rows there are 10e/1.0.19)

## Scope

For every Datasheet and Wargear ability on the Custodes codex datasheets,
the game does what the printed text says. Excluded:
- Master of Ka'tahs: WP-C3.
- Core and faction rules: WP-C3.

1. **Audit table** in `.llm/codex_11e_wahapedia/custodes_abilities_audit.md`.
   Columns: datasheet | ability | printed text (short) | game status before |
   action.
2. **Praesidium Shield (Wargear):** "Attacks allocated to this model have
   -1 D". The 10e +1 W stat bonus is already removed from ArmyListManager.
   Implement -1 Damage, minimum 1, on every damage path, including the
   per-model allocation when the shield bearer is in a unit.
3. **Vexilla:** +1 OC is done at army load. Add "this unit can ignore
   modifiers to this unit's Ld".
4. **The rest of the 46**, with logic in
   `40k/scripts/codex/custodes/CustodesAbilities.gd` (thin hooks), or as
   `ABILITY_EFFECTS` rows where the primitives fit. They include:
   - Captain-General (Aura), Vengeful Surge, Archeotech Teleport-shunter,
     Living Fortress, Stand Vigil, Impenetrable Defence, Deft Parry, Death
     Blow, Sword of the Throne, Slayer of Tyrants
   - Swift Ruin, Neutronium Cascade Mine, Destructor Optics, Repulsor
     Suspensor Technology, Assault Vehicle, Unyielding Ancient, Take Wing,
     Strike from the Skies, Purity of Execution, Sanctified Flames, Reap a
     Terrible Tally, Tactical Perception, Seeker's Instincts, Corner the
     Quarry, Mobile Hunter, Swift Onslaught, Saturation Volleys, Infernus
     Firebombs, Disintegration Beams, Hero of Lion's Gate, No Foe Shall Stand
   - ...see the CSV.
   - Usage limits printed in parentheses ("Once per battle, per unit") are in
     the data as `usage`; enforce them.
5. **Delete** dispatch for Custodes abilities that no codex datasheet has
   (Martial Inspiration, Devoted to Destruction, Master of the Stances,
   Slayers of Tyrants, Strategic Mastery, Sentinel Storm, Moment Shackle's
   10e version if it changed, ...). Retire their tests with reasons.
6. **AI** handles activated abilities without stalling.

## Validation (IMPLEMENTATION.md §5 — all of it)

- **Headless:** `tests/test_custodes_abilities_11e.gd` (one group per
  ability), added to `run_pretrigger_tests.sh`.
- **Windowed scenarios:** `cus11e_ab_<slug>.json`:
  - each activated ability (player choice / once-per-battle)
  - Praesidium Shield -1D shown in the damage log
  - at least three passive combat abilities
  - real clicks, PASS, screenshots
  - `GODOT_MCP_PORT=9480`, `flock /tmp/codex11e_godot_window.lock`
- **Full gate:** green apart from the documented baseline failures.
- **Docs:** changelog bullets in `changelog/WP-C7.md`; rulings in
  `RULINGS.md`.

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: audit summary, rulings, tests + counts, full gate,
scenario PASS list, screenshots, anything not done or not validated.
