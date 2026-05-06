# Session 2026-05-05 Notes

## Why no live UI screenshots

The audit task descriptions assume the godot-mcp-bridge MCP server is connected
*to a running Godot editor with the project loaded*, so each `T-NNN` block can
drive `play_main_scene` → fixture load → `simulate_click` → `capture_screenshot`.
That harness was not booted in this unattended session.

Headless GDScript regression tests are an equivalent (and arguably stronger)
form of evidence for everything that doesn't have a UI affordance:

- Auto-resolve / overwatch / interactive shoot / interactive melee FNP and save
  paths share the same primitives (`_calculate_save_needed`,
  `_get_model_effective_invuln`, `get_unit_fnp_for_attack`,
  `roll_feel_no_pain`, `apply_mortal_wounds`). Pinning them at the primitive
  level covers all four entry-points at once.
- The aura-source iteration in `RulesEngine.unit_has_waaagh_banner_lethal_hits`,
  `RulesEngine.get_ded_glowy_ammo_toughness_penalty`, and
  `UnitAbilityManager.find_friendly/enemy_units_within_aura` is shared with
  every gameplay caller. The headless tests reach those exact functions with
  the audit-prescribed inputs.
- JSON shape pins prove the data side of the bug is fixed.

For the audit items that genuinely *only* exist as UI behaviour (the QoL
bundles T-092/T-093/T-094/T-095/T-096; the visual polish T-109; the deployment
walkthrough T-095) you cannot avoid a live walkthrough. None of the tasks
touched in this session fall into that bucket — every fix is testable through
the rules pipeline.

If the user wants live MCP screenshots later, the recipe is:

```
1. Open Godot editor at /Users/robertocallaghan/Documents/claude/godotv2
   (the project root contains addons/godot_mcp/).
2. Press F5 to play the main scene.
3. Wait for `[GodotMCP] Listening on 127.0.0.1:9080`.
4. Drive each T-NNN scenario with the documented MCP calls.
```

## Outstanding sub-feature of T-085

`battle_shocked` is stored in two parallel locations across the codebase:
`unit.flags.battle_shocked` AND `unit.status_effects.battle_shocked`. The
audit asks for consolidation to a single source of truth. This wasn't done
this session because:

- The two locations have different lifecycles (flags reset at command phase,
  status_effects persist longer).
- Several phases read each location independently (MovementPhase reads
  status_effects; CommandPhase reads flags).
- A safe refactor needs a survey of all readers and a planned migration.

Tracked as outstanding follow-up under T-085. The immunity gate (the more
load-bearing half) is pinned green.

## StateSerializer normalisation experiment

I initially tried to normalise `embarked_in: null` → `""` inside
`StateSerializer._validate_unit_data`. This failed silently when running the
broader tests because ~25 call sites use the OPPOSITE pattern
(`unit.get("embarked_in", null) != null`). With normalisation in place those
sites would treat every unit as embarked. The change was reverted; the 7
audit-flagged sites are made defensive in-place instead. The defensive
pattern is:

```
var embk = unit.get("embarked_in", "")
if embk != null and embk != "":
    continue  # skip embarked source
```

This is forward-compatible if a future migration normalises one way or the
other, since it accepts both null and "".

## Files modified this session

- `40k/armies/adeptus_custodes.json` — invuln 4 + Witchseekers ability rename
- `40k/armies/A_C_test.json` — same edits in test fixture
- `40k/autoloads/RulesEngine.gd` — invuln fallback, FNP-for-attack helper, DW FNP wiring (×3 paths), 2× embarked_in null-safe checks
- `40k/autoloads/UnitAbilityManager.gd` — 5× embarked_in null-safe checks
- `40k/phases/ChargePhase.gd` — removed `_clear_phase_flags` and its call
- `40k/tests/test_t014_custodes_invuln.gd` (new)
- `40k/tests/test_t015_witchseekers_scouts.gd` (new)
- `40k/tests/test_t016_t017_psychic_mortal_fnp.gd` (new)
- `40k/tests/test_t029a_embarked_in_null.gd` (new)
- `40k/tests/test_t056_charge_phase_flags.gd` (new)
- `40k/tests/test_t058_aircraft_charge.gd` (new)
- `40k/tests/test_t080_disembark_remain_stationary.gd` (new)
- `40k/tests/test_t085_battle_shock_immunity.gd` (new)
- `40k/test_results/audit_2026_05/AUDIT_REPORT.md` — appended Session 2026-05-05 section
- `40k/test_results/audit_2026_05/session_2026_05_05/` (new — this folder)
