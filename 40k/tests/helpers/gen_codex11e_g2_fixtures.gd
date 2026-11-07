extends "res://tests/helpers/gen_ork11e_ab_fixtures.gd"

## gen_codex11e_g2_fixtures.gd — builds the WP-G2 windowed-scenario fixtures
## (.llm/codex_11e_wahapedia/PLAN_GAPS.md: Assault Vehicle, Pilin' Out, Deff
## from the Shadows, Swift Ruin) with the WP-O6 builder
## (gen_ork11e_ab_fixtures.gd: same shell, open-field layout, Ork codex rosters
## as P1, placement and gates):
##
##   tests/saves/cus11e_g2_<name>.w40ksave — P2 = the Custodes codex roster
##       tests/fixtures/cus11e_ab_roster.json (every datasheet), P1 = Orks.
##   tests/saves/ork11e_g2_<name>.w40ksave — P1 = Orks, P2 =
##       armies/adeptus_custodes.json.
## The active player's Command phase (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_codex11e_g2_fixtures.gd [name ...]

const CUS_ROSTER := "cus11e_ab_roster"

const G2_FIXTURES := {
	# P2 Custodes' Movement phase: ASSAULT VEHICLE — the Coronus carries the
	# Custodian Guard, the Anathema Psykana Rhino the Prosecutors.
	"assault_vehicle": {
		"prefix": "cus11e_g2_", "p2_roster": CUS_ROSTER, "active": 2,
		"p1": [
			["U_BOYZ_C", 22.0, 10.0, 5],
		],
		"p2": [
			["U_CORONUS_A", 12.0, 40.0, 1],
			["U_AP_RHINO_A", 32.0, 40.0, 1],
			["U_GUARD_A", 12.0, 50.0, 3],
			["U_PROSECUTORS_A", 32.0, 50.0, 5],
		],
		"embark": [["U_GUARD_A", "U_CORONUS_A"], ["U_PROSECUTORS_A", "U_AP_RHINO_A"]],
	},
	# P1 Orks' Movement phase ends: SWIFT RUIN — the Venatari with Verutum
	# Lances and the Witchseekers are in P2's strategic reserves.
	"swift_ruin": {
		"prefix": "cus11e_g2_", "p2_roster": CUS_ROSTER, "active": 1,
		"p1": [
			["U_BOYZ_C", 22.0, 12.0, 5],
		],
		"p2": [
			["U_GUARD_A", 22.0, 48.0, 3],
		],
		"reserves": {"U_VENATARI_VL_A": "strategic_reserves", "U_WITCHSEEKERS_A": "strategic_reserves"},
	},
	# P2 Custodes' Movement phase: PILIN' OUT — the Nobz are embarked in the
	# Trukk; Custodian Guard B is 12" away (one 5" move brings it within 8").
	"pilin_out": {
		"prefix": "ork11e_g2_", "active": 2,
		"p1": [
			["U_TRUKK_A", 22.0, 20.0, 1],
			["U_NOBZ_A", 6.0, 10.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 32.0, 3],
		],
		"embark": [["U_NOBZ_A", "U_TRUKK_A"]],
	},
	# Battle round 1, P2 Custodes' Movement phase ends: DEFF FROM THE SHADOWS —
	# Boss Snikrot is in strategic reserves (no Rapid Ingress in round 1).
	"deff_shadows": {
		"prefix": "ork11e_g2_", "active": 2, "battle_round": 1,
		"p1": [
			["U_BOYZ_C", 22.0, 12.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 48.0, 3],
		],
		"reserves": {"U_BOSS_SNIKROT_A": "strategic_reserves"},
	},
}


func _initialize() -> void:
	await create_timer(0.5).timeout
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = G2_FIXTURES.keys()
	var ok := true
	for n in names:
		if not G2_FIXTURES.has(n):
			printerr("[codex11e-g2-fixture] unknown fixture %s" % n)
			ok = false
			continue
		print("[codex11e-g2-fixture] building %s%s" % [G2_FIXTURES[n].prefix, n])
		ok = _build(str(n), G2_FIXTURES[n]) and ok
	quit(0 if ok else 1)
