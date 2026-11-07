# Codex 11e — remaining Custodes + Ork gaps — plan

Status: SHIPPED (2026-11-07, version 1.74.0) — G1–G5 merged; see "Integration result" at the end. Owner ask: "Implement the remaining Custodes
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

## Integration result (2026-11-07)

- Headless gate (`run_pretrigger_tests.sh`): 13865 passed, 1 failed across
  193 tests; the 1 failure is the listed XFAIL
  `test_custodes_lions_silent_hunters.gd`. New suites: G1 77/0, G2 121/0,
  G3 109/0, G4 81/0, G5 76/0.
- New/updated G scenarios on the integrated tree: 23/23 pass, 0 SCRIPT ERROR.
- Regression sweep (313 scenarios: every `cus11e_*` / `ork11e_*` plus
  charge / disembark / redeploy / ingress / reserve / transport / heroic /
  fall-back / overwatch): no regression caused by G1–G5.
  - The 5 listed known failures still fail with the same step counts.
  - `iss067_scout_reserves_deploy_11e` now passes, so it is delisted.
  - `ork11e_charge_flags_end_of_turn` (78/30) fails the same way on base
    e5c77f3, so it is now listed.
  - The `*_enh_builder_cloud_army` scenarios need `npm ci` in `server/` to
    start the relay server. With it, both pass.
  - Six AI scenarios still passed a difficulty argument to
    `AIPlayer.configure`, which b419b64 removed. Fixed, and all 6 pass.
- Follow-ups:
  - G1: the network sync of the redeploy counter is untested, hot-seat is
    tested headless only, and the AI never redeploys.
  - G2: the RapidIngressDialog Timer error is pre-existing. The Rapid Ingress
    log prefix names the active player instead of the arriving one. A
    rapid-disembarked unit still shows "[YET TO MOVE]". Trukk and AP Rhino
    have 32mm bases in the data.
  - G3: the charge-path model-blocking rule is a core change that affects all
    factions. `BEGIN_PULSE_JET_MOVE` is not in NetworkManager's optimistic
    action list.
  - G4: no shipped army has the Bossbunka, so it falls back to a 32mm base.
    PRIME TARGET / Aquilon Optics re-rolls are not applied on Fast Roll; this
    is pre-existing.
  - G5: in online games the dialogs stay automatic, and so does the RAPID
    REACTIONS save allocation.
  - Still not done (engine-wide): duplicate weapons on one model fire once;
    phase-end windows in networked games.
