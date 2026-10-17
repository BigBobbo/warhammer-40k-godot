# WP-O6 — Codex: Orks (11e) datasheet abilities

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf`. Godot project:
`40k/`.

Read first:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md` (contract)
3. `.llm/codex_11e_wahapedia/import_report_orks.md`: per datasheet ability
   changes, and the list of 33 game-dispatched ability names the codex
   dropped
4. `.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets_abilities.csv` (the
   printed text of every Ork datasheet ability) with
   `orks/wahapedia/Datasheets.csv` (datasheet names by id)
5. `40k/autoloads/UnitAbilityManager.gd` (`ABILITY_EFFECTS`) and
   `ArmyListManager.ABILITY_NAME_CANON`

## Scope

For every ability on the 55 Ork codex datasheets (type Datasheet or Wargear;
core and faction abilities are other packages'), make the game do what the
printed text says.

1. Build an audit table in `.llm/codex_11e_wahapedia/ork_abilities_audit.md`.
   Columns: datasheet | ability | printed text (short) | game status before
   (implemented as the old name X / partially / not at all) | action taken.
2. **Re-key the 33 dropped names:**
   - "Cork Dat Red Bit" → "Catch Dat Red Bit", "Clever Know-wots" →
     "Clever Know-wotz", "Pillin' Out" → "Pilin' Out", and so on.
   - Where the codex rule is the same mechanic, move the `ABILITY_EFFECTS`
     row / dispatch to the codex name.
   - Where the mechanic changed, re-implement it.
   - Delete code for abilities that no codex datasheet has.
   - Army files already carry the codex names; do not regenerate data.
3. **Implement the codex abilities the game lacks**, prioritising the ones
   that change combat maths or movement:
   - Damaged X is done (engine-parsed name) and Super-heavy Walker is core.
   - New ones include Finderz Keeperz, Mobile Arsenal, Drive-by Skorchin, Go
     fer da Weak Spot, Speednob Support, Support Shokka, Sumfin' to Prove,
     Wurrboy, Deff from the Shadows, Boss' Ammo Runt.
   - Put logic in `40k/scripts/codex/orks/OrkAbilities11e.gd` (thin hooks
     elsewhere), or as `ABILITY_EFFECTS` rows where the existing effect
     primitives express the rule.
4. **AI** must handle any activated ability without stalling.

Out of scope:
- Army/detachment rules: WP-O34.
- Enhancements: WP-O5.
- Stratagems: shipped.

## Validation (IMPLEMENTATION.md §5 — all of it)

- **Headless:** `tests/test_ork_abilities_11e.gd`, one check group per
  implemented / re-keyed ability (condition, effect A/B with the same seed,
  usage limits), added to `run_pretrigger_tests.sh`.
- **Full gate:**
  - Fix regressions.
  - Retire only tests of abilities the codex removed (`RETIRED_TESTS.md`).
  - Known pre-existing failures on this branch are in `BASELINE.md` if it
    exists.
- **Windowed scenarios:** `ork11e_ab_<slug>.json` for each activated
  (player-choice) ability and for at least three passive combat abilities.
  - real clicks, PASS, screenshots
  - `GODOT_MCP_PORT=9780`, `flock /tmp/codex11e_godot_window.lock`
- **Docs:** changelog bullets in `.llm/codex_11e_wahapedia/changelog/WP-O6.md`;
  rulings in `RULINGS.md` (WP-O6 section).

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: audit-table summary (counts per action),
rulings, tests + pass counts, full-gate result, scenario PASS output,
screenshot paths, anything not done or not validated (plainly).
