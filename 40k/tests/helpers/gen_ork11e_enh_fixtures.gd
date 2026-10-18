extends "res://tests/helpers/gen_ork11e_ab_fixtures.gd"

## gen_ork11e_enh_fixtures.gd — builds the WP-O5 (Codex: Orks 11e
## ENHANCEMENTS, scripts/codex/orks/OrkEnhancements11e.gd) windowed-scenario
## fixtures with the WP-O6 builder (gen_ork11e_ab_fixtures.gd, same shell,
## open-field layout, rosters, placement and gates):
##
##   tests/saves/ork11e_enh_<name>.w40ksave — P1 = Orks in the detachment the
##       enhancements belong to, the enhancements on their bearers in the
##       army data BEFORE ArmyListManager processing (so the list-build pass —
##       'Ardboyz Sv, Da Krunch's weapon, ... — runs exactly as for a loaded
##       army); P2 = Adeptus Custodes. Battle round 2 (1 where noted), the
##       active player's Command phase (scenarios transition to their phase).
##
## Usage (from the repo root):
##   godot --headless --path 40k -s tests/helpers/gen_ork11e_enh_fixtures.gd [name ...]

const ENH_FIXTURES := {
	# War Horde, Movement phase: Da Boss is Watchin' (Warboss leading Boyz C;
	# offered at the start of the phase), Follow Me Ladz (Big Mek leading Boyz D).
	"war_horde_move": {
		"prefix": "ork11e_enh_", "detachment": "War Horde", "active": 1,
		"enhancements": {"U_WARBOSS_A": ["Da Boss is Watchin'"], "U_BIG_MEK_A": ["Follow Me Ladz"]},
		"p1": [
			["U_BOYZ_C", 8.0, 20.0, 5],
			["U_WARBOSS_A", 8.0, 16.6, 1],
			["U_BOYZ_D", 26.0, 20.0, 5],
			["U_BIG_MEK_A", 26.0, 16.6, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 10.0, 30.0, 3],
		],
		"attach": [["U_WARBOSS_A", "U_BOYZ_C"], ["U_BIG_MEK_A", "U_BOYZ_D"]],
		"offers": [[1, "movement_phase_start", 7, 1, ["enh_da_boss_is_watchin"]]],
	},
	# Dread Mob, Shooting phase: Dreadherder (Big Mek within 3" of the Deff Dread).
	"dread_shoot": {
		"prefix": "ork11e_enh_", "detachment": "Dread Mob", "active": 1,
		"enhancements": {"U_BIG_MEK_A": ["Dreadherder"]},
		"p1": [
			["U_DEFF_DREAD_A", 12.0, 20.0, 1],
			["U_BIG_MEK_A", 15.5, 18.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 12.0, 32.0, 3],
		],
	},
	# Madcap Meks, Shooting phase: Temperamental Shokka (Big Mek with SAG),
	# Mekwaaagh! Mastermind (Big Mek leading Boyz C — riled up from the start
	# of the battle's phases).
	"madcap_shoot": {
		"prefix": "ork11e_enh_", "detachment": "Madcap Meks", "active": 1,
		"enhancements": {"U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A": ["Temperamental Shokka"], "U_BIG_MEK_A": ["Mekwaaagh! Mastermind"]},
		"p1": [
			["U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 12.0, 20.0, 1],
			["U_BOYZ_C", 30.0, 20.0, 5],
			["U_BIG_MEK_A", 30.0, 16.6, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 12.0, 40.0, 3],
		],
		"attach": [["U_BIG_MEK_A", "U_BOYZ_C"]],
	},
	# Madcap Meks, Shooting phase: Enhanced Runt-maw (Big Mek with SAG leading
	# Tankbustas: the SAG and the rokkits can hit two different units).
	"madcap_runtmaw": {
		"prefix": "ork11e_enh_", "detachment": "Madcap Meks", "active": 1,
		"enhancements": {"U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A": ["Enhanced Runt-maw"]},
		"p1": [
			["U_TANKBUSTAS_A", 16.0, 20.0, 3],
			["U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", 16.0, 15.0, 1],
		],
		"p2": [
			["U_WITCHSEEKERS_C", 10.0, 30.0, 4],
			["U_WITCHSEEKERS_D", 22.0, 30.0, 4],
		],
		"attach": [["U_BIG_MEK_WITH_SHOKK_ATTACK_GUN_A", "U_TANKBUSTAS_A"]],
	},
	# Brute Bosses, the OPPONENT's Movement phase: Morgog's Finkin' Cap.
	"brute_enemy_move": {
		"prefix": "ork11e_enh_", "detachment": "Brute Bosses", "active": 2,
		"enhancements": {"U_WARBOSS_A": ["Morgog's Finkin' Cap"]},
		"p1": [
			["U_WARBOSS_A", 20.0, 18.0, 1],
			["U_BOYZ_C", 8.0, 20.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 30.0, 36.0, 3],
		],
	},
	# Brute Bosses, Movement phase: Blitzboss (Warboss embarked in the Battlewagon).
	"brute_move": {
		"prefix": "ork11e_enh_", "detachment": "Brute Bosses", "active": 1,
		"enhancements": {"U_WARBOSS_A": ["Blitzboss"]},
		"p1": [
			["U_BATTLEWAGON_A", 14.0, 20.0, 1],
			["U_WARBOSS_A", 30.0, 18.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 14.0, 40.0, 3],
		],
		"embark": [["U_WARBOSS_A", "U_BATTLEWAGON_A"]],
	},
	# Brute Bosses, Fight phase: Surly as a Squiggoth (the Warboss, 1 wound
	# left, engaged with Custodian Guard B).
	"brute_fight": {
		"prefix": "ork11e_enh_", "detachment": "Brute Bosses", "active": 1,
		"enhancements": {"U_WARBOSS_A": ["Surly as a Squiggoth"]},
		"p1": [
			["U_WARBOSS_A", 20.0, 29.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 20.0, 29.5, 3],
		],
		"engaged": [["U_WARBOSS_A", "U_CUSTODIAN_GUARD_B"]],
		"wounds_lost": {"U_WARBOSS_A": 5},
	},
	# Flyboyz, battle round 1: Impulsive Recon (the Dakkajet may arrive from
	# Strategic Reserves; the Burna-bommer may not).
	"flyboyz_r1": {
		"prefix": "ork11e_enh_", "detachment": "Flyboyz", "active": 1, "battle_round": 1,
		"enhancements": {"U_DAKKAJET_A": ["Impulsive Recon"]},
		"p1": [
			["U_BOYZ_C", 10.0, 14.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 30.0, 50.0, 3],
		],
		"reserves": {"U_DAKKAJET_A": "strategic_reserves", "U_BURNA_BOMMER_A": "strategic_reserves"},
	},
	# Flyboyz, battle round 2: Flyboss (the Wazbom arrives at the left edge
	# within 6" of the Dakkajet and the Deffkoptas; the Boyz are not
	# AIRCRAFT/DEFFKOPTAS and stand far away).
	"flyboyz_r2": {
		"prefix": "ork11e_enh_", "detachment": "Flyboyz", "active": 1,
		"enhancements": {"U_WAZBOM_BLASTAJET_A": ["Flyboss"]},
		"p1": [
			["U_DAKKAJET_A", 10.0, 17.0, 1],
			["U_DEFFKOPTAS_A", 6.0, 23.0, 3],
			["U_BOYZ_C", 30.0, 14.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 30.0, 50.0, 3],
		],
		"reserves": {"U_WAZBOM_BLASTAJET_A": "strategic_reserves"},
	},
	# Wreckas, Redeployment: Kaptin's Hat (Warboss leading Flash Gitz).
	"wreckas_redeploy": {
		"prefix": "ork11e_enh_", "detachment": "Wreckas", "active": 1, "battle_round": 1,
		"enhancements": {"U_WARBOSS_A": ["Kaptin's Hat"]},
		"p1": [
			["U_FLASH_GITZ_A", 10.0, 14.0, 5],
			["U_WARBOSS_A", 10.0, 10.6, 1],
			["U_BOYZ_C", 26.0, 14.0, 5],
			["U_BATTLEWAGON_A", 38.0, 10.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 22.0, 50.0, 3],
		],
		"attach": [["U_WARBOSS_A", "U_FLASH_GITZ_A"]],
	},
	# Green Tide: 'Ardboyz (Boyz C, Sv 4+ after the list-build pass).
	"green_tide": {
		"prefix": "ork11e_enh_", "detachment": "Green Tide", "active": 1,
		"enhancements": {"U_BOYZ_C": ["'Ardboyz"]},
		"p1": [
			["U_BOYZ_C", 12.0, 20.0, 5],
			["U_BOYZ_D", 30.0, 20.0, 5],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 20.0, 40.0, 3],
		],
	},
	# Shoota Boyz, Shooting phase: Targetin' Squigs (the Warboss alone; its
	# 18" Kustom shoota reaches Custodian Guard B 20" away).
	"shoota_boyz": {
		"prefix": "ork11e_enh_", "detachment": "Shoota Boyz", "active": 1,
		"enhancements": {"U_WARBOSS_A": ["Targetin' Squigs"]},
		"p1": [
			["U_WARBOSS_A", 20.0, 16.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 20.0, 36.4, 3],
		],
	},
	# Wurrband, Shooting phase: Da Krunch (the Weirdboy's added psychic weapon).
	"wurrband": {
		"prefix": "ork11e_enh_", "detachment": "Wurrband", "active": 1,
		"enhancements": {"U_WEIRDBOY_A": ["Da Krunch"]},
		"p1": [
			["U_WEIRDBOY_A", 20.0, 16.0, 1],
		],
		"p2": [
			["U_CUSTODIAN_GUARD_B", 20.0, 34.0, 3],
		],
	},
}


func _initialize() -> void:
	await create_timer(0.5).timeout
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = ENH_FIXTURES.keys()
	var ok := true
	for n in names:
		if not ENH_FIXTURES.has(n):
			printerr("[ork11e-enh-fixture] unknown fixture %s" % n)
			ok = false
			continue
		print("[ork11e-enh-fixture] building ork11e_enh_%s" % n)
		ok = _build(str(n), ENH_FIXTURES[n]) and ok
		if ok:
			_report(str(n), ENH_FIXTURES[n])
	quit(0 if ok else 1)


## Print the enhancement state of the built board (list-build effects included).
func _report(name: String, spec: Dictionary) -> void:
	var e = load("res://scripts/codex/orks/OrkEnhancements11e.gd")
	print("[ork11e-enh-fixture]   detachment %s" % str(GS.state.factions["1"].get("detachment", "")))
	for uid in spec.get("enhancements", {}):
		var u: Dictionary = GS.state.units[uid]
		print("[ork11e-enh-fixture]   %s carries %s (owned by the codex module: %s; Sv %s, T %s)" % [
			uid, str(u.meta.get("enhancements", [])), str(e.owns_name(u, str(spec.enhancements[uid][0]))),
			str(u.meta.stats.get("save", "?")), str(u.meta.stats.get("toughness", "?"))])
