# Codex 11e — remaining Custodes + Ork gaps — plan

Status: IN PROGRESS (2026-11-07). Owner ask: "Implement the remaining Custodes
and Ork gaps" (the "Not implemented" / "no player UI" items left by PLAN.md,
custodes_abilities_audit.md, ork_abilities_audit.md).

Out of scope (owner decisions D2/D3 in PLAN.md): Legends datasheets (incl.
Mekboy Workshop), Boarding Actions detachments. Engine-wide limits
(duplicate weapons on one model, phase-end windows in networked games) are
not part of this plan.

Contract: `IMPLEMENTATION.md` applies (thin hooks, flags `cus11e_` / `ork11e_`,
validation bar §5, no version_history.json edits — bullets go in
`changelog/WP-G<n>.md`, rulings in a `## WP-G<n>` section appended to the END
of `RULINGS.md`). Update the matching audit row (status column) in
`custodes_abilities_audit.md` / `ork_abilities_audit.md` and the
`"implemented": false` row in `UnitAbilityManager.ABILITY_EFFECTS` when a rule
lands.

## Packages

| WP | Scope | Port |
|---|---|---|
| G1 | Redeployment step a human can use: Castellan's Mark (Custodes), Kaptin's Hat (Orks), Razgit's Magik Map if it uses the same step — select up to N units, pick them up, re-place them (deployment rules) or send to strategic reserves (ignoring the reserves cap) | 10181 |
| G2 | Assault Vehicle (Coronus Grav-Carrier, Anathema Psykana Rhino); Pilin' Out (Trukk); Deff from the Shadows (Boss Snikrot); Swift Ruin offered to a human | 10182 |
| G3 | Pulse Jet move (Wazdakka Gutsmek, Full Throttle "pulse"); Runnin' wiv da Herd keyword swap (Painboss); Get Out da Way! (Nobz) verified end-to-end | 10183 |
| G4 | Advanced Firepower (Caladius Annihilator); Big'ed Bossbunka: Raucous Occupants, Fortification, Ramshackle Cover | 10184 |
| G5 | Player-controlled NO ESCAPE (charge), SELFLESS SERVICE (charge; printed target rule), RAPID REACTIONS (shooting) — today auto-resolved | 10185 |

Windowed launches: `flock /tmp/codex11e_godot_window.lock …` with
`GODOT_MCP_PORT` set to the package port. Scenarios:
`40k/tests/scenarios/sp/cus11e_g<n>_*.json` / `ork11e_g<n>_*.json`.
Headless tests: `40k/tests/test_codex11e_g<n>_*.gd`, added to
`run_pretrigger_tests.sh`.
