# WP-O34 — Codex: Orks (11e) army rules + 15 detachment rules

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf`. Godot project:
`40k/`.

Read first, in this order:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md` (contract)
3. `.llm/codex_11e_wahapedia/PLAN.md` track O
4. `.llm/ork_codex_11e_design.md` (the shipped Ork stratagem work: §6, §7.2 rulings, §7.3 limitations)
5. `.llm/codex_11e_wahapedia/orks/RULES.md` (army rules + every detachment rule as printed)
6. `scripts/40kdc/curated/orks_codex_11e.json` (detachment `rule_text`, already used by the stratagem work)

## Scope

**1. Army rules.**
- **Waaagh!** — riled up — was implemented for 11e in PR #917.
  - Re-verify it against the printed text:
    - re-roll advance rolls
    - riled up = 5+ invuln, ranged [ASSAULT], advance doesn't prevent charging
    - War Cry once per battle at the start of the Command phase: riled up until
      the end of the next turn
  - Fix any gap.
- **Da Boss:** at the start of the battle round, if a model with this ability
  is your WARLORD, gain 1CP.
  - The game has some Da Boss code (grep it): check it against the text.
  - The ability now exists on the 8 datasheets that carry it (`meta.abilities`
    "Da Boss").
- **Unstable Energies:** psyker level budget.
  - Each ORKS PSYKER unit has a psyker level (in its abilities); each psychic
    ability has a psychic level (in its name, e.g. "Da Jump (Psychic 1)" or
    similar — check `orks/wahapedia/Datasheets_abilities.csv`).
  - Per battle round, the levels a unit uses must not exceed its psyker level.
  - Enforce this on every psychic ability path the game implements (Da Jump,
    Weirdboy/Wurrboy powers, ...), with player-facing feedback when the budget
    is spent.

**2. All 15 Codex: Orks detachment rules:**
- War Horde: Get Stuck In
- Madcap Meks: Unpredictable Genius
- Wurrband: Powers of da Waaagh!
- Runt Swarm: Sneaky Little Gitz
- Wreckas: Wreckin' and Lootin'
- Brute Bosses: 'Ard as Nails
- Bully Boyz: Displays of Savagery
- Da Big Hunt: Da Hunt is On
- Dread Mob: Try Dat Button!
- Shoota Boyz: Dakka! Dakka! Dakka!
- Flyboyz: Skyborne Loons
- Kult of Speed: Adrenaline Junkies
- Blitz Brigade: Unstoppable Momentum
- Green Tide: Mob-handed Brutality
- Taktikal Brigade: Suspiciously Well Organised

Seven have no code today; eight run 10e-era code in FactionAbilityManager.
Diff those against the printed text and fix them in place or replace them.
Detachment BATTLELINE grants (Warbikers, Stormboyz, Gretchin) must reach
whatever the game uses BATTLELINE for. Put new logic in
`40k/scripts/codex/orks/OrkDetachments11e.gd`, with thin hooks only.

**3. AI.** It must handle every choice these rules introduce (e.g. Try Dat
Button! rolls, Unpredictable Genius results) without stalling.

Out of scope:
- Enhancements: WP-O5.
- Datasheet abilities: WP-O6.
- Stratagems: shipped.

Don't regenerate data or army files.

## Validation (IMPLEMENTATION.md §5 — all of it)

- **Headless tests:**
  - `tests/test_ork_army_rules_11e.gd` and `tests/test_ork_detachments_11e.gd`,
    added to `run_pretrigger_tests.sh`.
  - One check group per rule: trigger/condition edge cases, effect A/B with
    the same seed, expiry, BATTLELINE grants.
  - Da Boss CP only when the warlord has it.
  - Unstable Energies refuses an over-budget use and resets each battle round.
- **Full gate** `bash 40k/tests/run_pretrigger_tests.sh`.
  - Known pre-existing failures on this branch are in
    `.llm/codex_11e_wahapedia/BASELINE.md` if it exists.
  - Retire only tests of removed 10e behaviour, in `RETIRED_TESTS.md` with
    reasons.
- **Windowed scenarios**, `ork11e_det_<slug>.json`:
  - one per detachment rule that has a visible effect or a player choice
  - plus `ork11e_da_boss_cp` and `ork11e_unstable_energies_budget`
  - real clicks, PASS via `run_scenarios.sh`, screenshots of each effect
  - `GODOT_MCP_PORT=9580`, `flock /tmp/codex11e_godot_window.lock`
- **Docs:** changelog bullets in
  `.llm/codex_11e_wahapedia/changelog/WP-O34.md`; rulings in `RULINGS.md`
  (WP-O34 section).

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: per-rule status, rulings, tests + pass counts,
full-gate result, scenario PASS output, screenshot paths, and anything not
done or not validated (plainly).
