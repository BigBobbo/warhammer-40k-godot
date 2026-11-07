extends "res://tests/helpers/gen_ork11e_ab_fixtures.gd"

## gen_ork11e_g3_fixtures.gd — builds the WP-G3 (Codex: Orks 11e: Pulse Jet,
## Runnin' wiv da Herd, Get Out da Way!) fixtures with the WP-O6 builder
## (gen_ork11e_ab_fixtures.gd: same shell, open-field layout, codex rosters,
## placement and gates). P1 = Orks, P2 = Adeptus Custodes, battle round 2,
## P1's Command phase (scenarios / tests transition to their phase).
##
##   tests/saves/ork11e_g3_pulse.w40ksave — Wazdakka Gutsmek (x 22") with
##       Custodian Guard B 4" in front of it (a pulse jet move jumps over them).
##   tests/saves/ork11e_g3_herd.w40ksave — Painboss attached to Squighog Boyz A
##       (MOUNTED), Beast Snagga Boyz B (INFANTRY) beside them.
##   tests/saves/ork11e_g3_charge.w40ksave — Nobz A (Get Out da Way!) with
##       Witchseekers C 2.2" in front screening Custodian Guard B 7" away; Boyz
##       C (no ability) with Witchseekers D 2.2" in front screening a
##       Contemptor-Achillus Dreadnought (VEHICLE: the MONSTER/VEHICLE rule).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_ork11e_g3_fixtures.gd [name ...]

const G3_FIXTURES := {
	"pulse": {
		"prefix": "ork11e_g3_", "active": 1,
		"p1": [
			["U_WAZDAKKA_GUTSMEK_A", 22.0, 12.0, 1],
			["U_BOYZ_C", 6.0, 12.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 16.0, 3],
			["U_WITCHSEEKERS_C", 38.0, 40.0, 4],
		],
	},
	"herd": {
		"prefix": "ork11e_g3_", "active": 1,
		"p1": [
			["U_SQUIGHOG_BOYZ_A", 14.0, 20.0, 2],
			["U_PAINBOSS_A", 19.0, 20.0, 1],
			["U_BEAST_SNAGGA_BOYZ_B", 30.0, 20.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 36.0, 3],
		],
		"attach": [["U_PAINBOSS_A", "U_SQUIGHOG_BOYZ_A"]],
	},
	"charge": {
		"prefix": "ork11e_g3_", "active": 1,
		"p1": [
			["U_NOBZ_A", 14.0, 20.0, 5],
			["U_BOYZ_C", 32.0, 20.0, 5],
		],
		"p2": [
			["U_WITCHSEEKERS_C", 14.0, 22.2, 4],
			["U_CUSTODIAN_GUARD_B", 14.0, 27.0, 3],
			["U_WITCHSEEKERS_D", 32.0, 22.2, 4],
			["U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H", 32.0, 27.0, 1],
		],
	},
}


func _initialize() -> void:
	await create_timer(0.5).timeout
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = G3_FIXTURES.keys()
	var ok := true
	for n in names:
		if not G3_FIXTURES.has(n):
			printerr("[ork11e-g3-fixture] unknown fixture %s" % n)
			ok = false
			continue
		print("[ork11e-g3-fixture] building ork11e_g3_%s" % n)
		ok = _build(str(n), G3_FIXTURES[n]) and ok
	quit(0 if ok else 1)
