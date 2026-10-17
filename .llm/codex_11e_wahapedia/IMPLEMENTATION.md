# Codex 11e rules implementation — contract for every work package

Status: active (2026-10-17). Applies to plan tracks C3-C7 and O3-O6
(`PLAN.md`). The data layer has shipped: commit `e704330` (import pipeline,
codex datasheets, army files, `tests/test_wahapedia_11e_import_data.gd`).

Read this whole file, `PLAN.md`, and `.llm/ork_codex_11e_design.md` §3, §4 and
§6 (the stratagem-window framework you reuse) before you write code. Where
this file and older code comments disagree, this file wins.

## 1. Source of truth for rules text

- `custodes/RULES.md` and `orks/RULES.md`: army rules, detachment rules,
  enhancements and stratagems as printed. The Custodes ka'tah abilities are in
  the "From the faction page" block.
- `custodes/wahapedia/*.csv` and `orks/wahapedia/*.csv`: the raw export
  (Datasheets_abilities.csv holds every datasheet ability's text).
- Stratagem rows: `scripts/40kdc/curated/custodes_codex_11e.json` and
  `orks_codex_11e.json` (`when`, `target`, `effect`, `windows`).
- Core rules: https://wahapedia.ru/wh40k11ed/the-rules/core-rules/
- Import reports `import_report_custodes.md` and `import_report_orks.md` list
  every ability name the codex dropped. The game's dispatch tables still key
  33 Ork and 5 Custodes names that no codex datasheet carries any more; re-key
  or retire them.

Implement the printed text. When the text is ambiguous, pick the reading
closest to the core rules and record the ruling in your WP section of
`RULINGS.md` (one line each). Never invent effects.

## 2. Code layout

| Area | Location |
|---|---|
| Custodes (new) | `40k/scripts/codex/custodes/` |
| Orks (new detachment / enhancement / army-rule code) | `40k/scripts/codex/orks/` |
| Ork stratagems (already shipped) | `40k/scripts/stratagems/ork_codex/` |

Custodes files:
- `CustodesCommon.gd`: helpers. These are late-bound autoloads; preload only
  this file from the group scripts, never each other.
- `CustodesKatah.gd`: the army rule (WP-C3).
- `CustodesCodex11e.gd`: the stratagem dispatcher. It has the same API as
  `OrkCodex11e`, and the group scripts are `CustodesCodexFight.gd`,
  `…Shooting.gd`, `…Movement.gd` and `…Other.gd` (WP-C5).
- `CustodesDetachments.gd` and `CustodesEnhancements.gd` (WP-C4/C6).
- `CustodesAbilities.gd`: datasheet abilities (WP-C7).

Ork files: `OrkArmyRules11e.gd` (Da Boss, Unstable Energies; WP-O3),
`OrkDetachments11e.gd` (WP-O4), `OrkEnhancements11e.gd` (WP-O5) and
`OrkAbilities11e.gd` (WP-O6, where a rule needs more than an
`ABILITY_EFFECTS` table row).

Engine files (RulesEngine, FactionAbilityManager, UnitAbilityManager,
StratagemManager, the phases, ArmyListManager) only get **thin hook calls**
into these modules: one line plus a comment at each hook. Keep the logic in
your module, so that parallel packages merge cleanly.

Flags:
- Name them `cus11e_<slug>` or `ork11e_<slug>`.
- A flag that must outlive the Shooting phase must not use the `effect_`
  prefix (ShootingPhase wipes `effect_*` on exit).
- Every flag needs a clear point, and a test that it expires.

## 3. Stratagem windows

Reuse the BasePhase window framework (`open_stratagem_window*`,
`USE_WINDOW_STRATAGEM`, `StratagemDialog.setup_window`, the AI's
`decide_window_stratagem`).

**WP-C3 adds** the windows below. Its framework commit lands first; the other
packages rebase onto it.
- `fight_phase_start`: start of the Fight phase, before the first fighter is
  selected. Active player first, then the non-active player. Used by
  Dacatarai, Kaptaris and SHIELD OF HONOUR.
- `unit_selected_to_move`: if it is not opened for every move type yet,
  extend it. Calistus; INEXORABLE.
- `unit_selected_to_shoot`: same. Salvus.
- `command_phase_main`: your Command phase, after the readied step.
  Conservai; panel-style use is fine.

**WP-C5 adds** whatever its 41 stratagems still need: `phase_end` (END OF ANY
PHASE), `unit_ended_advance_move`, `unit_selected_to_ingress`,
`unit_selected_to_pile_in`, `unit_selected_to_consolidate`,
`enemy_has_fought`, `charge_phase_start`, `charge_phase_end`. Register every
new id in `KNOWN_WINDOWS` (scripts/40kdc/generate-stratagems.mjs) and fix the
inferred `windows` in `curated/custodes_codex_11e.json` (`_window_review` lists
each inference), then re-run `npm run codex11e`.

## 4. File ownership (to keep merges clean)

| WP | owns (creates / rewrites) | may touch with thin hooks |
|---|---|---|
| C3 Custodes army rules | `codex/custodes/CustodesKatah.gd`, `CustodesCommon.gd`, Ka'tah UI (replaces `dialogs/KatahStanceDialog.gd`), the new windows above in BasePhase and the phases | FightPhase (delete the old stance code), CommandPhase, Movement/Shooting phases, RulesEngine (Aegis FNP vs MW, Daughters FNP vs psychic), CommandPhase CP (Aquila Commander), ArmyListManager (Anathema Psykana warlord rule), AIDecisionMaker |
| C5 Custodes stratagems | `CustodesCodex11e.gd` + group scripts, `curated/custodes_codex_11e.json` windows | StratagemManager (dispatch `custom:custodes11e` exactly like `custom:ork11e`), phases (new windows), AIDecisionMaker |
| C4+C6 Custodes detachments + enhancements | `CustodesDetachments.gd`, `CustodesEnhancements.gd` | FactionAbilityManager (remove the 10e Shield Host / Silent Hunters / Talons / Tharanatoi / Solar Spearhead / old Lions and Auric Champions entries), RulesEngine, ArmyListManager enhancement validation |
| C7 Custodes datasheet abilities | `CustodesAbilities.gd` | UnitAbilityManager (`ABILITY_EFFECTS` rows), RulesEngine (Praesidium Shield -1 D), dialogs for activated abilities |
| O3+O4 Ork army rules + detachments | `codex/orks/OrkArmyRules11e.gd`, `OrkDetachments11e.gd` | FactionAbilityManager (replace the 10e-era Ork detachment code), RulesEngine, the phases, AIDecisionMaker |
| O5 Ork enhancements | `OrkEnhancements11e.gd` | FactionAbilityManager / ArmyListManager enhancement tables |
| O6 Ork datasheet abilities | `OrkAbilities11e.gd` | UnitAbilityManager (re-key the 33 dropped names: `ArmyListManager.ABILITY_NAME_CANON` or new rows), RulesEngine |

Do NOT edit `40k/data/version_history.json`. Put your player-facing bullets in
`changelog/<WP>.md` in this directory; the integrator merges them into one
release entry. Do not regenerate army files or 40kdc data; if you think the
data is wrong, write it up in your report.

## 5. Validation bar (every WP, before you report done)

1. **Headless tests:**
   - Add `40k/tests/test_<wp-slug>.gd` (pattern:
     `tests/test_ork_codex_fight.gd`), with `GameConstants.edition = 11`.
   - Cover: offer/trigger in the right window and not in others; target
     eligibility edge cases; the effect (A/B with the same seed for combat
     modifiers); CP; expiry; once-per limits; the AI path never stalls.
   - Add the file to `40k/tests/run_pretrigger_tests.sh`.
2. **Regression:**
   - Run `bash 40k/tests/run_pretrigger_tests.sh`. Every failure must be
     explained: yours to fix, or retired 10e behaviour. Retire a test only when
     the codex removed the behaviour it checks, and list it with the reason in
     `RETIRED_TESTS.md`.
   - Never skip or disable a test to get green.
3. **Windowed scenario per player-facing rule:**
   - Write it under `40k/tests/scenarios/sp/cus11e_*.json` / `ork11e_*.json`.
   - It drives the real UI with real clicks (`simulate_click`), asserts with
     `get_node_info`, and captures screenshots.
   - It must pass `bash 40k/tests/run_scenarios.sh tests/scenarios/sp/<id>.json`.
4. **Live screenshot of each feature's effect**, from the running game via the
   MCP bridge (CLAUDE.md, "You CAN run the game"). Put the absolute PNG paths
   in your report.
5. **Clean log:** no `SCRIPT ERROR` / `ERROR` in stdout or the debug log during
   your scenarios (`read_debug_log` / `verify_delivery`).
6. **Windowed runs share the machine:**
   - Wrap every windowed Godot launch in
     `flock /tmp/codex11e_godot_window.lock …`.
   - Set `GODOT_MCP_PORT` to your WP's port: C3 9180, C5 9280, C4 9380,
     C7 9480, O3 9580, O5 9680, O6 9780.
   - `user://` is shared between worktrees: do not delete or overwrite other
     packages' saves; name test saves after your WP.

Report back:
- what you implemented (per rule)
- every ruling
- the test files and their pass counts
- the full-gate result (with the failures that remain and why)
- scenario ids with PASS output
- screenshot paths
- anything not done or not validated, stated plainly

## 6. Integration

- Each WP works on its own branch in its own worktree off
  `claude/gracious-shannon-u3z0mf`, commits there, and does not push.
- The integrator merges in this order: C3 first, then the others, re-running
  the gate after each merge.
- Packages that start after C3 has merged branch from the post-C3 tip.
