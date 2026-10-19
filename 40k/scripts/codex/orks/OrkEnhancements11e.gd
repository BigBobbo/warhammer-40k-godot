extends RefCounted

## OrkEnhancements11e — Codex: Orks (11e) ENHANCEMENTS (WP-O5).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md (§2 code layout, §4
## ownership). Printed text: .llm/codex_11e_wahapedia/orks/RULES.md and
## orks/wahapedia/Enhancements.csv (38 codex enhancements; Boarding Actions
## excluded). The data records (points, Upgrade tag, bearer restriction,
## rules_text, page-only LEADER lines and weapon profiles) are in
## data/40kdc/enhancements.json (wahapedia-import.mjs overlayEnhancements).
## Rulings: RULINGS.md (WP-O5).
##
## Everything is static. Engine files and the sibling Ork modules call in
## through thin hooks (one line + a comment each):
##   OrkAbilities11e   attack_mods (via RulesEngine.ork11e_ab_mods), defence
##                     mods, move modifier, detection range, conditional Lone
##                     Operative, leadership penalty, window offers / use /
##                     AI score ("ork11e_ab_enh_*" ids ride the O6 ability
##                     path), after_unit_shot, phase transitions, Boss Boomer
##   OrkDetachments11e fall-back-and-charge, charge re-roll source, range
##                     bonus, targets-confirmed (SUPA-HAZARDOUS bookkeeping)
##   OrkArmyRules11e   psyker level (Warphead)
##   RulesEngine       [DEVASTATING WOUNDS] / [ANTI-INFANTRY] / [TORRENT] /
##                     [RAPID FIRE] grants, Stealth, Lone Operative
##   EffectPrimitives  fall back and shoot
##   GameState         Deep Strike, Infiltrators, Scouts
##   TerrainManager    benefit of cover (Smoky Gubbinz)
##   FallBackMove      forced desperate escape (Wimp-kickaz)
##   MovementPhase /   first-round ingress (Impulsive Recon), ingress end
##   Main                (Flyboss)
##   CharacterAttachmentManager  LEADER lines (Kill Kommanda, Kaptin's Hat)
##   FactionAbilityManager       redeploy enhancement (Kaptin's Hat)
##   ArmyListManager   list-build effects + army-construction validation
##   UnitAbilityManager the 10e name-keyed pipeline skips names this module owns
##
## An enhancement only acts at edition 11+, on an ORKS unit, when the owning
## player's detachment is the codex detachment that lists it (so a pre-codex
## enhancement of the same name in another detachment never reads as the
## codex one).
##
## Autoloads are reached late-bound through OrkCodexCommon (headless
## `godot -s` tests compile this script before autoloads are registered).

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
const Ab = preload("res://scripts/codex/orks/OrkAbilities11e.gd")
const Det = preload("res://scripts/codex/orks/OrkDetachments11e.gd")

const PX_PER_INCH := 40.0
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const DATA_ENHANCEMENTS := "res://data/40kdc/enhancements.json"
const DATA_DETACHMENTS := "res://data/40kdc/detachments.json"

## slug -> FOLDED printed name (OrkAbilities11e.fold: case, apostrophes and
## punctuation ignored, a trailing "(…)" dropped).
const NAMES := {
	"headwoppas_killchoppa": "headwoppas killchoppa",
	"da_boss_is_watchin": "da boss is watchin",
	"kunnin_but_brutal": "kunnin but brutal",
	"follow_me_ladz": "follow me ladz",
	"glory_hog": "glory hog",
	"it_came_from_da_drops": "it came from da drops",
	"smoky_gubbinz": "smoky gubbinz",
	"competitive_streak": "competitive streak",
	"cybork_boosta": "cybork boosta",
	"dreadherder": "dreadherder",
	"ferocious_show_off": "ferocious show off",
	"ardboyz": "ardboyz",
	"wimp_kickaz": "wimp kickaz",
	"tellyporta_boss": "tellyporta boss",
	"kill_kommanda": "kill kommanda",
	"throat_slittas": "throat slittas",
	"targetin_gizmos": "targetin gizmos",
	"boss_boomer": "boss boomer",
	"kaptins_hat": "kaptins hat",
	"supa_snazz_dakka": "supa snazz dakka",
	"extra_sneaky": "extra sneaky",
	"minefield_detail": "minefield detail",
	"supa_glowy_fing": "supa glowy fing",
	"targetin_squigs": "targetin squigs",
	"mekwaaagh_mastermind": "mekwaaagh mastermind",
	"temperamental_shokka": "temperamental shokka",
	"enhanced_runt_maw": "enhanced runt maw",
	"surly_as_a_squiggoth": "surly as a squiggoth",
	"brutal_but_kunnin": "brutal but kunnin",
	"blitzboss": "blitzboss",
	"proper_killy": "proper killy",
	"morgogs_finkin_cap": "morgogs finkin cap",
	"da_gobshot_thunderbuss": "da gobshot thunderbuss",
	"flyboss": "flyboss",
	"impulsive_recon": "impulsive recon",
	"da_krunch": "da krunch",
	"eadbanger": "eadbanger",
	"warphead": "warphead",
}

## slug -> the codex detachment that lists it (OrkDetachments11e.det_key form).
const DETACHMENT := {
	"headwoppas_killchoppa": "war horde", "da_boss_is_watchin": "war horde",
	"kunnin_but_brutal": "war horde", "follow_me_ladz": "war horde",
	"glory_hog": "da big hunt", "it_came_from_da_drops": "da big hunt",
	"smoky_gubbinz": "kult of speed", "competitive_streak": "kult of speed",
	"cybork_boosta": "dread mob", "dreadherder": "dread mob",
	"ferocious_show_off": "green tide", "ardboyz": "green tide",
	"wimp_kickaz": "bully boyz", "tellyporta_boss": "bully boyz",
	"kill_kommanda": "taktikal brigade", "throat_slittas": "taktikal brigade",
	"targetin_gizmos": "blitz brigade", "boss_boomer": "blitz brigade",
	"kaptins_hat": "wreckas", "supa_snazz_dakka": "wreckas",
	"extra_sneaky": "runt swarm", "minefield_detail": "runt swarm",
	"supa_glowy_fing": "shoota boyz", "targetin_squigs": "shoota boyz",
	"mekwaaagh_mastermind": "madcap meks", "temperamental_shokka": "madcap meks",
	"enhanced_runt_maw": "madcap meks",
	"surly_as_a_squiggoth": "brute bosses", "brutal_but_kunnin": "brute bosses",
	"blitzboss": "brute bosses", "proper_killy": "brute bosses",
	"morgogs_finkin_cap": "brute bosses", "da_gobshot_thunderbuss": "brute bosses",
	"flyboss": "flyboyz", "impulsive_recon": "flyboyz",
	"da_krunch": "wurrband", "eadbanger": "wurrband", "warphead": "wurrband",
}

const DISPLAY := {
	"headwoppas_killchoppa": "Headwoppa's Killchoppa", "da_boss_is_watchin": "Da Boss is Watchin'",
	"kunnin_but_brutal": "Kunnin' But Brutal", "follow_me_ladz": "Follow Me Ladz",
	"glory_hog": "Glory Hog", "it_came_from_da_drops": "It Came from da Drops",
	"smoky_gubbinz": "Smoky Gubbinz", "competitive_streak": "Competitive Streak",
	"cybork_boosta": "Cybork Boosta", "dreadherder": "Dreadherder",
	"ferocious_show_off": "Ferocious Show-off", "ardboyz": "'Ardboyz",
	"wimp_kickaz": "Wimp-kickaz", "tellyporta_boss": "Tellyporta Boss",
	"kill_kommanda": "Kill Kommanda", "throat_slittas": "Throat-slittas",
	"targetin_gizmos": "Targetin' Gizmos", "boss_boomer": "Boss Boomer",
	"kaptins_hat": "Kaptin's Hat", "supa_snazz_dakka": "Supa-snazz Dakka",
	"extra_sneaky": "Extra Sneaky", "minefield_detail": "Minefield Detail",
	"supa_glowy_fing": "Supa-glowy Fing", "targetin_squigs": "Targetin' Squigs",
	"mekwaaagh_mastermind": "Mekwaaagh! Mastermind", "temperamental_shokka": "Temperamental Shokka",
	"enhanced_runt_maw": "Enhanced Runt-maw", "surly_as_a_squiggoth": "Surly as a Squiggoth",
	"brutal_but_kunnin": "Brutal But Kunnin'", "blitzboss": "Blitzboss",
	"proper_killy": "Proper Killy", "morgogs_finkin_cap": "Morgog's Finkin' Cap",
	"da_gobshot_thunderbuss": "Da Gobshot Thunderbuss", "flyboss": "Flyboss",
	"impulsive_recon": "Impulsive Recon", "da_krunch": "Da Krunch",
	"eadbanger": "'Eadbanger", "warphead": "Warphead",
}

# --- flags (all `ork11e_enh_*`; none uses the `effect_` prefix, which the
# Shooting phase wipes on exit) ---------------------------------------------
const F_DREADHERDER := "ork11e_enh_dreadherder"    # on the walker group: {player, turn_key} — re-roll hit 1s until the end of the turn
const F_TSHOKKA := "ork11e_enh_tshokka"            # on the bearer: {result} — Temperamental Shokka roll, until the unit has shot
const F_INFESTED := "ork11e_enh_infested"          # on the enemy group: {player, set_turn_key} — -1 to leadership rolls until the start of P's next turn
const F_SUPA_SEL := "ork11e_enh_supa_glowy_weapons"  # on the bearer: [SUPA-HAZARDOUS] weapons selected this activation
const F_SURLY := "ork11e_enh_surly"                # on the bearer: {alive, pos, phase} — alive at the start of the current phase
const F_LIST_BUILD := "ork11e_enh_list_build"      # meta marker: list-build effects already applied (idempotent load)
const P_MORGOG := "ork11e_enh_morgog_roll"         # players.<p>: {unit_id, roll, phase_key} — Morgog's D6 awaiting the re-roll choice

const SID_PREFIX := "ork11e_ab_enh_"   # rides the O6 ability path (OrkAbilities11e.handles_id prefix)
const USE_PREFIX := "enh_"             # usage-counter keys (OrkAbilities11e.F_USES)

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func fold(n: String) -> String:
	return Ab.fold(n)

static func _uid(u: Dictionary) -> String:
	return str(u.get("id", ""))

static func display(slug: String) -> String:
	return str(DISPLAY.get(slug, slug.capitalize()))

static func _enh_names(u: Dictionary) -> Array:
	var out: Array = []
	for e in u.get("meta", {}).get("enhancements", []):
		var n := ""
		if e is String:
			n = e
		elif e is Dictionary:
			n = str(e.get("name", ""))
		if n != "":
			out.append(fold(n))
	return out

## Slug of a printed enhancement name ("" when it is not a codex Ork one).
static func slug_of_name(enh_name: String) -> String:
	var f := fold(enh_name)
	for slug in NAMES:
		if NAMES[slug] == f:
			return str(slug)
	return ""

## True when `u` carries the codex enhancement `slug` and it is in force:
## edition 11+, an ORKS unit, the owner's detachment is the one listing it.
## `det` overrides the owner's detachment (list-build, before the faction
## block is in GameState).
static func has(u: Dictionary, slug: String, det: String = "") -> bool:
	if not enabled() or u.is_empty() or not NAMES.has(slug):
		return false
	if not str(NAMES[slug]) in _enh_names(u):
		return false
	if not Common.has_keyword(u, "ORKS"):
		return false
	var d := Det.det_key(det) if det != "" else Det.detachment_of(int(u.get("owner", 0)))
	return d == str(DETACHMENT[slug])

static func has_id(unit_id: String, slug: String) -> bool:
	return has(Common.unit(unit_id), slug)

## Alive component of `unit_id`'s Attached unit that carries `slug` ("" if none).
static func holder(unit_id: String, slug: String) -> String:
	for gid in Ab.group(unit_id):
		if has(Common.unit(str(gid)), slug):
			return str(gid)
	return ""

static func group_has(unit_id: String, slug: String) -> bool:
	return unit_id != "" and holder(unit_id, slug) != ""

## UnitAbilityManager hook: the 10e name-keyed enhancement rows skip a name
## this module implements for this unit (same gating as has()).
static func owns_name(u: Dictionary, enh_name: String) -> bool:
	var slug := slug_of_name(enh_name)
	return slug != "" and has(u, slug)

## Any unit of `player` (or of any player when 0) in GameState carrying `slug`.
static func _bearers(slug: String, player: int = 0) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if player > 0 and int(u.get("owner", 0)) != player:
			continue
		if has(u, slug):
			out.append(str(uid))
	return out

static func _phase() -> int:
	var gs = Common.game_state()
	return int(gs.get_current_phase()) if gs != null else -1

static func _round() -> int:
	var gs = Common.game_state()
	return int(gs.get_battle_round()) if gs != null else 0

static func _turn_key() -> String:
	return "%d:%d" % [_round(), Common.active_player()]

static func _phase_key() -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), _phase()]

static func _log(msg: String) -> void:
	Common.log_info("OrkEnhancements11e: " + msg)

static func _event(player: int, text: String) -> void:
	Ab._event_log(player, text)

static func _apply(diffs: Array) -> void:
	var gs = Common.game_state()
	if gs and not diffs.is_empty():
		gs.apply_state_changes(diffs)

static func _alive_models(u: Dictionary) -> int:
	var n := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			n += 1
	return n

static func _group_alive_models(unit_id: String) -> int:
	var n := 0
	for gid in Ab.group(unit_id):
		n += _alive_models(Common.unit(str(gid)))
	return n

static func _is_mv(unit_id: String) -> bool:
	return Ab.group_has_keyword(unit_id, "MONSTER") or Ab.group_has_keyword(unit_id, "VEHICLE")

## Part of an Attached unit (a leader attached to a bodyguard, or a bodyguard
## with an attached leader).
static func _is_attached(u: Dictionary) -> bool:
	var at = u.get("attached_to", null)
	if at != null and str(at) != "":
		return true
	return not u.get("attachment_data", {}).get("attached_characters", []).is_empty()

static func _embarked_unit_ids(transport_id: String) -> Array:
	var out: Array = []
	for eid in Common.unit(transport_id).get("transport_data", {}).get("embarked_units", []):
		var e := str(eid)
		if e == "":
			continue
		out.append(e)
		for cid in Common.unit(e).get("attachment_data", {}).get("attached_characters", []):
			if not str(cid) in out:
				out.append(str(cid))
	return out

static func _is_embarked(u: Dictionary) -> bool:
	return u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != ""

# ===========================================================================
# Data (data/40kdc enhancements + detachments, Ork codex records)
# ===========================================================================

static var _data_cache: Dictionary = {}

## {det_key: [enhancement records of that codex detachment]} for the Orks.
static func codex_records() -> Dictionary:
	if not _data_cache.is_empty():
		return _data_cache
	var enh = _read_json(DATA_ENHANCEMENTS)
	var dets = _read_json(DATA_DETACHMENTS)
	if not (enh is Array) or not (dets is Array):
		Common.log_error("OrkEnhancements11e: could not read %s / %s" % [DATA_ENHANCEMENTS, DATA_DETACHMENTS])
		return {}
	var by_id := {}
	for e in enh:
		if e is Dictionary:
			by_id[str(e.get("id", ""))] = e
	for d in dets:
		if not (d is Dictionary) or str(d.get("faction_id", "")) != "orks" or d.has("superseded_by_codex"):
			continue
		var recs: Array = []
		for eid in d.get("enhancement_ids", []):
			var r = by_id.get(str(eid), null)
			if r is Dictionary and not r.has("superseded_by_codex"):
				recs.append(r)
		_data_cache[Det.det_key(str(d.get("name", "")))] = recs
	return _data_cache

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed

## The codex record of `enh_name` in detachment `det` ({} when not listed).
static func record(det: String, enh_name: String) -> Dictionary:
	var want := fold(enh_name)
	for r in codex_records().get(Det.det_key(det), []):
		if fold(str(r.get("name", ""))) == want:
			return r
	return {}

# ===========================================================================
# LIST-BUILD effects (ArmyListManager hook, once per unit at army load)
# ===========================================================================
# Characteristic and keyword changes a roster carries for the whole battle:
#   'Ardboyz (4+ Sv), It Came from da Drops (+1 T), Flyboss (CHARACTER),
#   Warphead (Deadly Demise D6), Da Krunch / 'Eadbanger / Da Gobshot
#   Thunderbuss (the printed weapon is added to the bearer).
# Idempotent: meta[F_LIST_BUILD] records what was applied.

static func apply_list_build(unit_id: String, unit: Dictionary, detachment: String) -> Array:
	var applied: Array = []
	if not enabled() or unit.is_empty() or not unit.has("meta"):
		return applied
	var meta: Dictionary = unit.meta
	var done: Array = meta.get(F_LIST_BUILD, [])
	var probe := unit.duplicate()
	probe["id"] = unit_id
	for slug in ["ardboyz", "it_came_from_da_drops", "flyboss", "warphead", "da_krunch", "eadbanger", "da_gobshot_thunderbuss"]:
		if str(slug) in done or not has(probe, str(slug), detachment):
			continue
		var stats: Dictionary = meta.get("stats", {})
		match str(slug):
			"ardboyz":
				var sv := int(stats.get("save", 6))
				if sv > 4:
					stats["save"] = 4
				_log("'Ardboyz — %s Sv %d+ -> %d+" % [unit_id, sv, int(stats.get("save", sv))])
			"it_came_from_da_drops":
				var t := int(stats.get("toughness", 0))
				stats["toughness"] = t + 1
				_log("It Came from da Drops — %s T %d -> %d" % [unit_id, t, t + 1])
			"flyboss":
				var kws: Array = meta.get("keywords", [])
				if not "CHARACTER" in kws:
					kws.append("CHARACTER")
					meta["keywords"] = kws
				_log("Flyboss — %s has CHARACTER" % unit_id)
			"warphead":
				_grant_deadly_demise_d6(meta, unit_id)
			"da_krunch", "eadbanger", "da_gobshot_thunderbuss":
				_grant_weapon(meta, unit_id, str(slug), detachment)
		meta["stats"] = stats
		done.append(str(slug))
		applied.append(str(slug))
	if not applied.is_empty():
		meta[F_LIST_BUILD] = done
	return applied

## Warphead: "This model has Deadly Demise D6" — replaces a lower Deadly
## Demise (the Weirdboy's D3); one Deadly Demise ability per model.
static func _grant_deadly_demise_d6(meta: Dictionary, unit_id: String) -> void:
	var abilities: Array = meta.get("abilities", [])
	var kept: Array = []
	for ab in abilities:
		var n := ""
		if ab is String:
			n = ab
		elif ab is Dictionary:
			n = str(ab.get("name", ""))
		if n.to_lower().begins_with("deadly demise"):
			continue
		kept.append(ab)
	kept.append({"name": "Deadly Demise D6", "type": "Core", "description": "Warphead (enhancement): this model has Deadly Demise D6."})
	meta["abilities"] = kept
	_log("Warphead — %s has Deadly Demise D6 (psyker level 2, can re-roll psychic rolls)" % unit_id)

## The printed enhancement weapon (record.granted_weapon) in the army-file
## weapon shape; its name is unique, so the global by-name profile lookup
## (RulesEngine.get_weapon_profile) can only ever find this bearer's copy.
static func _grant_weapon(meta: Dictionary, unit_id: String, slug: String, detachment: String) -> void:
	var rec := record(detachment, display(slug))
	var gw: Dictionary = rec.get("granted_weapon", {})
	if gw.is_empty():
		Common.log_error("OrkEnhancements11e: %s has no granted_weapon profile in %s — weapon not added to %s" % [display(slug), DATA_ENHANCEMENTS, unit_id])
		return
	var w := weapon_from_record(gw)
	var weapons: Array = meta.get("weapons", [])
	for x in weapons:
		if str(x.get("name", "")) == str(w.name):
			return
	weapons.append(w)
	meta["weapons"] = weapons
	var wargear: Array = meta.get("wargear", [])
	var line := "1x %s" % str(w.name)
	if not line in wargear:
		wargear.append(line)
		meta["wargear"] = wargear
	_log("%s — %s gains weapon %s (%s\" A%s BS%s S%s AP%s D%s %s)" % [display(slug), unit_id, w.name, w.range, w.attacks, w.ballistic_skill, w.strength, w.ap, w.damage, w.get("special_rules", "")])

## data granted_weapon {name, type, range "24\"", A, BS_WS "4+", S, AP, D,
## keywords [...]} -> army-file weapon dict. "Lethal Hits: non-Monster/Vehicle"
## is NOT written to the weapon (the engine's keyword scope only matches
## positive keywords); attack_mods grants it per target instead.
static func weapon_from_record(gw: Dictionary) -> Dictionary:
	var abilities: Array = []
	var rules: Array = []
	for kw in gw.get("keywords", []):
		var k := str(kw).strip_edges()
		var lk := k.to_lower()
		if lk.begins_with("lethal hits:"):
			continue
		var m := RegEx.new()
		m.compile("^(.*?)\\s+(\\d+)\\+?$")
		var mm := m.search(lk)
		if mm:
			var id := mm.get_string(1).replace(" ", "_").replace("-", "_")
			abilities.append({"id": id, "x": int(mm.get_string(2))})
		else:
			abilities.append({"id": lk.replace(" ", "_").replace("-", "_")})
		rules.append(lk)
	var w := {
		"name": str(gw.get("name", "")),
		"type": str(gw.get("type", "Ranged")),
		"range": str(gw.get("range", "")).replace("\"", "").replace("”", ""),
		"attacks": str(gw.get("A", "1")),
		"ballistic_skill": str(gw.get("BS_WS", "4")).replace("+", ""),
		"strength": str(gw.get("S", "4")),
		"ap": str(gw.get("AP", "0")),
		"damage": str(gw.get("D", "1")),
		"special_rules": ", ".join(PackedStringArray(rules)),
		"abilities": abilities,
		"source": "enhancement",
	}
	return w

# ===========================================================================
# ARMY-CONSTRUCTION VALIDATION (11e muster + Codex: Orks bearer lines)
# ===========================================================================
# 11e: only CHARACTER units take enhancements (EPIC HEROES never); one of each
# per army; one per unit; an Upgrade may go on a non-CHARACTER unit and up to
# three copies of the same Upgrade are allowed (the 2nd/3rd do not count
# towards the number of enhancements); the engine's cap is 2 per 1000 pts.
# Bearer: the printed "<X> model/unit only (excluding Y)" line (data
# keyword_restriction_groups / exclusion_keywords); the enhancement must be
# one of the army detachment's codex enhancements.

## True for an 11e Codex: Orks army in a codex detachment — this module then
## owns its enhancement validation (ArmyListManager skips its generic loops).
static func owns_army_validation(army_data: Dictionary) -> bool:
	if not enabled() or not (army_data.get("faction", null) is Dictionary):
		return false
	var fac: Dictionary = army_data.faction
	if Det.det_key(str(fac.get("name", ""))) != "orks":
		return false
	return codex_records().has(Det.det_key(str(fac.get("detachment", ""))))

static func _unit_kw_set(u: Dictionary) -> Array:
	var out: Array = []
	for kw in u.get("meta", {}).get("keywords", []):
		out.append(str(kw).to_upper())
	out.append(str(u.get("meta", {}).get("name", "")).to_upper())
	return out

## Does unit `u` satisfy the record's bearer line? ("" = yes, else the reason)
static func bearer_problem(rec: Dictionary, u: Dictionary) -> String:
	var kws := _unit_kw_set(u)
	var groups: Array = rec.get("keyword_restriction_groups", [])
	if groups.is_empty() and rec.get("keyword_restrictions", null) is Array:
		groups = [rec.keyword_restrictions]
	if not groups.is_empty():
		var ok := false
		for g in groups:
			var all := true
			for k in g:
				if not str(k).to_upper() in kws:
					all = false
					break
			if all:
				ok = true
				break
		if not ok:
			var alts: Array = []
			for g in groups:
				alts.append(" ".join(PackedStringArray((g as Array).map(func(x): return str(x).to_upper()))))
			return "%s only" % "/".join(PackedStringArray(alts))
	for ex in rec.get("exclusion_keywords", []):
		if str(ex).to_upper() in kws:
			return "excluding %s" % str(ex).to_upper()
	return ""

static func validate_army(army_data: Dictionary) -> Dictionary:
	var res := {"errors": [], "warnings": [], "choices": 0}
	if not owns_army_validation(army_data):
		return res
	var fac: Dictionary = army_data.faction
	var det := str(fac.get("detachment", ""))
	var points := int(fac.get("points", 2000))
	var units: Dictionary = army_data.get("units", {})
	var counts := {}       # folded name -> copies
	var upgrade := {}      # folded name -> bool
	for unit_id in units:
		var u: Dictionary = units[unit_id]
		var meta: Dictionary = u.get("meta", {})
		var names: Array = []
		for e in meta.get("enhancements", []):
			var n: String = ""
			if e is String:
				n = e
			elif e is Dictionary:
				n = str(e.get("name", ""))
			if n != "":
				names.append(n)
		if names.is_empty():
			continue
		var uname := str(meta.get("name", unit_id))
		var kws := _unit_kw_set(u)
		if names.size() > 1:
			res.warnings.append("11e Codex: Orks — %s (%s) carries %d enhancements; each enhancement goes on a different unit" % [uname, unit_id, names.size()])
		for n in names:
			var rec := record(det, n)
			if rec.is_empty():
				res.warnings.append("11e Codex: Orks — enhancement '%s' on %s (%s) is not one of %s's enhancements" % [n, uname, unit_id, det])
				continue
			var key := fold(n)
			counts[key] = int(counts.get(key, 0)) + 1
			var is_upg := bool(rec.get("upgrade_tag", false))
			upgrade[key] = is_upg
			if "EPIC HERO" in kws:
				res.warnings.append("11e Codex: Orks — %s (%s) is an EPIC HERO and cannot be given '%s'" % [uname, unit_id, rec.get("name", n)])
				continue
			if not is_upg and not "CHARACTER" in kws:
				res.warnings.append("11e Codex: Orks — '%s' on %s (%s): only CHARACTER units can be given enhancements (it is not an Upgrade)" % [rec.get("name", n), uname, unit_id])
			var why := bearer_problem(rec, u)
			if why != "":
				res.warnings.append("11e Codex: Orks — '%s' on %s (%s): %s" % [rec.get("name", n), uname, unit_id, why])
	var choices := 0
	for key in counts:
		var c := int(counts[key])
		if bool(upgrade.get(key, false)):
			choices += 1
			if c > 3:
				res.warnings.append("11e Codex: Orks — Upgrade '%s' is taken %d times (up to three of the same Upgrade)" % [key, c])
		else:
			choices += c
			if c > 1:
				res.warnings.append("11e Codex: Orks — enhancement '%s' is taken %d times (one of each per army)" % [key, c])
	res.choices = choices
	var cap := int(floor(points / 1000.0)) * 2
	if cap > 0 and choices > cap:
		res.warnings.append("11e Codex: Orks — %d enhancement choices exceed the cap of %d at %d pts" % [choices, cap, points])
	for w in res.warnings:
		print("ArmyListManager: [WP-O5] %s" % w)
	return res

# ===========================================================================
# PASSIVE COMBAT — merged into OrkAbilities11e.attack_mods' result by
# RulesEngine.ork11e_ab_mods (every resolver path folds that dict).
# Extra keys this module adds: devastating (bool), anti ([{keyword,
# threshold}]), torrent (bool) — RulesEngine consumes them next to the
# weapon's own keywords.
# ===========================================================================

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

## The batch is made by the bearer `holder_id` ("this model's attacks"):
## melee batches are resolved per fighting unit; ranged ones carry bearer ids.
static func _is_bearer_batch(actor_id: String, holder_id: String, bearer_ids: Array, is_melee: bool) -> bool:
	if holder_id == "":
		return false
	if is_melee:
		return actor_id == holder_id
	return Ab._batch_is_holder(actor_id, holder_id, bearer_ids)

static func _quick_has_any(actor_id: String) -> bool:
	for gid in Ab.group(actor_id):
		var u := Common.unit(str(gid))
		if not u.get("meta", {}).get("enhancements", []).is_empty():
			return true
		var fl: Dictionary = u.get("flags", {})
		if fl.has(F_DREADHERDER) or fl.has(F_TSHOKKA):
			return true
	return false

static func merge_attack_mods(m: Dictionary, actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, bearer_ids: Array = []) -> Dictionary:
	if not enabled() or actor_unit.is_empty():
		return m
	var actor_id := _uid(actor_unit)
	if actor_id == "" or not _quick_has_any(actor_id):
		return m
	if not Ab.group_has_keyword(actor_id, "ORKS"):
		return m
	if not m.has("anti"):
		m["anti"] = []
	var target_id := _uid(target_unit)
	var wname := str(weapon_profile.get("name", "")).to_lower()
	var ranged := not is_melee
	var charged := false
	for gid in Ab.group(actor_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
			charged = true

	# Headwoppa's Killchoppa: "If this unit made a charge move this turn, this
	# model's melee attacks have +1 AP."
	var h := holder(actor_id, "headwoppas_killchoppa")
	if is_melee and charged and _is_bearer_batch(actor_id, h, bearer_ids, true):
		m.ap = int(m.get("ap", 0)) + 1
		_src(m, "Headwoppa's Killchoppa", "other", "ap", "+1 AP (charged this turn)")
	# Ferocious Show-off: "This model's melee attacks have +1 A. Or: if this
	# unit has 11+ models, +2 A."
	h = holder(actor_id, "ferocious_show_off")
	if is_melee and _is_bearer_batch(actor_id, h, bearer_ids, true):
		var fa := 2 if _group_alive_models(actor_id) >= 11 else 1
		m.attacks = int(m.get("attacks", 0)) + fa
		_src(m, "Ferocious Show-off", "other", "attacks", "+%d A (%d models in the unit)" % [fa, _group_alive_models(actor_id)])
	# Brutal But Kunnin': "This model's melee attacks have +1 D."
	h = holder(actor_id, "brutal_but_kunnin")
	if is_melee and _is_bearer_batch(actor_id, h, bearer_ids, true):
		m.damage = int(m.get("damage", 0)) + 1
		_src(m, "Brutal But Kunnin'", "other", "damage", "+1 D")
	# Proper Killy: "This model can re-roll hit rolls of 1."
	h = holder(actor_id, "proper_killy")
	if h != "" and _is_bearer_batch(actor_id, h, bearer_ids, is_melee):
		m.hit_reroll = Ab._reroll_max(str(m.get("hit_reroll", "")), "ones")
		_src(m, "Proper Killy", "hit", "reroll_ones")
	# Throat-slittas: "This unit's melee attacks have [LETHAL HITS:
	# non-MONSTER/VEHICLE]."
	if is_melee and target_id != "" and group_has(actor_id, "throat_slittas") and not _is_mv(target_id):
		m.lethal = true
		_src(m, "Throat-slittas", "other", "lethal_hits", "target is not a MONSTER/VEHICLE")
	# Da Gobshot Thunderbuss: the weapon's [LETHAL HITS: non-MONSTER/VEHICLE].
	if ranged and wname == "da gobshot thunderbuss" and target_id != "" and not _is_mv(target_id):
		m.lethal = true
		_src(m, "Da Gobshot Thunderbuss", "other", "lethal_hits", "[LETHAL HITS: non-MONSTER/VEHICLE]")
	# Targetin' Gizmos (WAGON): "While a Big Mek model is embarked within this
	# unit: ranged attacks have [IGNORES COVER]; if riled up, [SUSTAINED HITS 1]."
	if ranged and has(actor_unit, "targetin_gizmos") and _big_mek_embarked(actor_id):
		m.ignores_cover = true
		_src(m, "Targetin' Gizmos", "other", "ignores_cover", "a Big Mek is embarked")
		if Ab.group_riled_up(actor_id):
			m.sustained = maxi(int(m.get("sustained", 0)), 1)
			_src(m, "Targetin' Gizmos", "other", "sustained_hits", "riled up: [SUSTAINED HITS 1]")
	# Supa-glowy Fing: "This model's ranged attacks have [ANTI-INFANTRY 4+],
	# [DEVASTATING WOUNDS], [SUPA-HAZARDOUS]" (the hazard rolls: after_unit_shot).
	h = holder(actor_id, "supa_glowy_fing")
	if ranged and h != "" and _is_bearer_batch(actor_id, h, bearer_ids, false):
		m.devastating = true
		(m["anti"] as Array).append({"keyword": "INFANTRY", "threshold": 4})
		_src(m, "Supa-glowy Fing", "other", "anti_dw", "[ANTI-INFANTRY 4+], [DEVASTATING WOUNDS]")
	# Dreadherder: the selected ORKS WALKER unit "can re-roll hit rolls of 1
	# until the end of the turn".
	if Ab._gf(actor_unit, F_DREADHERDER) != null:
		m.hit_reroll = Ab._reroll_max(str(m.get("hit_reroll", "")), "ones")
		_src(m, "Dreadherder", "hit", "reroll_ones", "selected by the Big Mek this turn")
	# Temperamental Shokka: this model's Shokk Attack Gun.
	if ranged and wname.contains("shokk attack gun"):
		var th := ""
		for gid in Ab.group(actor_id):
			if Common.unit(str(gid)).get("flags", {}).has(F_TSHOKKA):
				th = str(gid)
		if th != "" and _is_bearer_batch(actor_id, th, bearer_ids, false):
			var r := int(Common.unit(th).get("flags", {}).get(F_TSHOKKA, {}).get("result", 0))
			if r == 1:
				m.torrent = true
				_src(m, "Temperamental Shokka", "other", "torrent", "rolled a 1: [TORRENT] (the Big Mek is destroyed when the unit has shot)")
			elif r >= 2 and r <= 5:
				m.attacks = int(m.get("attacks", 0)) + 1
				_src(m, "Temperamental Shokka", "other", "attacks", "rolled %d: +1 A" % r)
			elif r == 6:
				m.sustained = maxi(int(m.get("sustained", 0)), 2)
				_src(m, "Temperamental Shokka", "other", "sustained_hits", "rolled a 6: [SUSTAINED HITS 2]")
	return m

static func _big_mek_embarked(transport_id: String) -> bool:
	for eid in _embarked_unit_ids(transport_id):
		var e := Common.unit(str(eid))
		if not Common.is_alive(e):
			continue
		if Common.has_keyword(e, "BIG MEK") or str(e.get("meta", {}).get("name", "")).to_lower().begins_with("big mek"):
			return true
	return false

## Lowest critical-wound threshold granted by an [ANTI-X Y+] in `mods` against
## `target_unit` (6 = none). RulesEngine: min with the weapon's own.
static func anti_threshold(mods: Dictionary, target_unit: Dictionary) -> int:
	var best := 6
	var anti = mods.get("anti", [])
	if not (anti is Array) or anti.is_empty() or target_unit.is_empty():
		return best
	var kws: Array = []
	for gid in Ab.group(_uid(target_unit)):
		for k in Common.unit(str(gid)).get("meta", {}).get("keywords", []):
			kws.append(str(k).to_upper())
	for k in target_unit.get("meta", {}).get("keywords", []):
		kws.append(str(k).to_upper())
	for a in anti:
		if str(a.get("keyword", "")).to_upper() in kws:
			best = mini(best, int(a.get("threshold", 6)))
	return best

## Target-side: Blitzboss — "A transport unit (excluding WALKER units) this
## unit is embarked within has ... 5+ InSv." (merged into
## OrkAbilities11e.defence_mods, read by the EffectPrimitives getters).
static func merge_defence_mods(d: Dictionary, target_unit: Dictionary, _is_melee: bool) -> Dictionary:
	if not enabled():
		return d
	var tid := _uid(target_unit)
	if tid == "" or not _blitzboss_transport(tid):
		return d
	d.invuln = 5 if int(d.get("invuln", 0)) == 0 else mini(int(d.invuln), 5)
	(d["sources"] as Array).append("Blitzboss")
	return d

## The transport `transport_id` carries a unit with Blitzboss (and is not a WALKER).
static func _blitzboss_transport(transport_id: String) -> bool:
	var t := Common.unit(transport_id)
	if t.is_empty() or not t.has("transport_data") or Common.has_keyword(t, "WALKER"):
		return false
	for eid in _embarked_unit_ids(transport_id):
		if has(Common.unit(str(eid)), "blitzboss"):
			return true
	return false

## Targetin' Squigs: "This unit's ranged attacks (excluding [TORRENT]
## attacks) have +3\" R." (RulesEngine.ork11e_det_range_bonus adds it).
static func range_bonus(actor_unit: Dictionary, weapon_profile: Dictionary = {}) -> float:
	if not enabled() or actor_unit.is_empty():
		return 0.0
	var aid := _uid(actor_unit)
	if aid == "" or not group_has(aid, "targetin_squigs"):
		return 0.0
	if not weapon_profile.is_empty():
		var wtype := str(weapon_profile.get("type", "Ranged")).to_lower()
		if wtype == "melee" or str(weapon_profile.get("range", "")).to_lower() == "melee":
			return 0.0
		var sr := str(weapon_profile.get("special_rules", "")).to_lower()
		if sr.contains("torrent"):
			return 0.0
		for k in weapon_profile.get("keywords", []):
			if str(k).to_upper() == "TORRENT":
				return 0.0
		for a in weapon_profile.get("abilities", []):
			if a is Dictionary and str(a.get("id", "")).to_lower() == "torrent":
				return 0.0
	return 3.0

## Supa-snazz Dakka: "This unit's Snazzgun weapons have [RAPID FIRE 1]."
## Returns the RAPID FIRE value it grants (RulesEngine keeps the higher of it
## and the weapon's own — duplicates are not cumulative).
static func rapid_fire_grant(actor_unit: Dictionary, weapon_profile: Dictionary) -> int:
	if not enabled() or actor_unit.is_empty():
		return 0
	if not str(weapon_profile.get("name", "")).to_lower().contains("snazzgun"):
		return 0
	return 1 if group_has(_uid(actor_unit), "supa_snazz_dakka") else 0

# ===========================================================================
# MOVEMENT / ELIGIBILITY / ABILITY GRANTS
# ===========================================================================

## Move characteristic modifier (OrkAbilities11e.move_modifier adds it):
##   Follow Me Ladz "This unit has +2\" M"; Cybork Boosta "This model has
##   +2\" M"; Blitzboss "A transport unit (excluding WALKER) this unit is
##   embarked within has +2\" M".
static func move_modifier(unit: Dictionary) -> float:
	if not enabled():
		return 0.0
	var uid := _uid(unit)
	if uid == "":
		return 0.0
	var mod := 0.0
	if group_has(uid, "follow_me_ladz"):
		mod += 2.0
	if has(unit, "cybork_boosta"):
		mod += 2.0
	if _blitzboss_transport(uid):
		mod += 2.0
	return mod

## Kunnin' But Brutal: a fall-back move does not prevent shooting.
static func fall_back_allows_shoot(u: Dictionary) -> bool:
	return enabled() and _uid(u) != "" and group_has(_uid(u), "kunnin_but_brutal")

## Kunnin' But Brutal / Glory Hog: a fall-back move does not prevent charging.
static func fall_back_allows_charge(u: Dictionary) -> bool:
	if not enabled() or _uid(u) == "":
		return false
	return group_has(_uid(u), "kunnin_but_brutal") or group_has(_uid(u), "glory_hog")

## Competitive Streak: "This unit can re-roll charge rolls."
static func charge_reroll_source(u: Dictionary) -> String:
	if enabled() and _uid(u) != "" and group_has(_uid(u), "competitive_streak"):
		return "Competitive Streak"
	return ""

## Tellyporta Boss: "This unit (excluding VEHICLE units) has Deep Strike."
static func grants_deep_strike(unit: Dictionary) -> bool:
	var uid := _uid(unit)
	if not enabled() or uid == "" or not group_has(uid, "tellyporta_boss"):
		return false
	return not Common.has_keyword(unit, "VEHICLE")

## Kill Kommanda: "While this model is part of an attached unit, this model
## has Infiltrators / Stealth."
static func kill_kommanda_active(unit: Dictionary) -> bool:
	return has(unit, "kill_kommanda") and _is_attached(unit)

static func grants_infiltrators(unit: Dictionary) -> bool:
	return enabled() and kill_kommanda_active(unit)

static func grants_stealth(unit: Dictionary) -> bool:
	return enabled() and kill_kommanda_active(unit)

## LEADER lines the enhancement prints (Kill Kommanda "LEADER: KOMMANDOS",
## Kaptin's Hat "LEADER: FLASH GITZ"): keywords the bearer can also lead.
static func leader_extras(character: Dictionary) -> Array:
	var out: Array = []
	if has(character, "kill_kommanda"):
		out.append("KOMMANDOS")
	if has(character, "kaptins_hat"):
		out.append("FLASH GITZ")
	return out

## Minefield Detail: "While this unit is not embarked, this unit has Scouts 6\"."
static func scouts_distance(unit: Dictionary) -> float:
	var uid := _uid(unit)
	if not enabled() or uid == "" or _is_embarked(unit) or not group_has(uid, "minefield_detail"):
		return 0.0
	return 6.0

## Extra Sneaky: "This unit has -3\" detection range."
static func detection_range_bonus(unit: Dictionary) -> float:
	var uid := _uid(unit)
	if not enabled() or uid == "" or not group_has(uid, "extra_sneaky"):
		return 0.0
	return -3.0

## Dreadherder: "While this model is within 3\" of a friendly ORKS WALKER unit
## (excluding BIG MEK units): this model has Lone Operative."
static func conditional_lone_operative(unit: Dictionary) -> bool:
	var uid := _uid(unit)
	if not enabled() or uid == "" or not has(unit, "dreadherder"):
		return false
	if not Common.is_on_battlefield(Common.unit(uid)):
		return false
	return not _walkers_near(uid, int(unit.get("owner", 0))).is_empty()

## Friendly ORKS WALKER units (not BIG MEK) within 3" of `bearer_id`.
static func _walkers_near(bearer_id: String, owner: int) -> Array:
	var out: Array = []
	for fid in Ab._friendly_heads(owner):
		var f := str(fid)
		if Ab.head_id(f) == Ab.head_id(bearer_id):
			continue
		if not Ab.group_has_keyword(f, "ORKS") or not Ab.group_has_keyword(f, "WALKER") or Ab.group_has_keyword(f, "BIG MEK"):
			continue
		if Ab.within(bearer_id, f, 3.0):
			out.append(f)
	return out

## Wimp-kickaz (NOBZ): "When an enemy unit engaged with this unit is selected
## to make a fall-back move: that enemy unit must select the desperate escape
## mode." (FallBackMove.select_mode)
static func forces_desperate_escape(unit_id: String, board: Dictionary = {}) -> bool:
	return not _wimp_kickaz_units(unit_id, board).is_empty()

## "If this unit is riled up, that enemy unit has -1 to the hazard rolls made
## for that desperate escape." (FallBackMove.before_moving) -1 or 0.
static func desperate_escape_hazard_modifier(unit_id: String, board: Dictionary = {}) -> int:
	for nid in _wimp_kickaz_units(unit_id, board):
		if Ab.group_riled_up(str(nid)):
			return -1
	return 0

static func _wimp_kickaz_units(unit_id: String, board: Dictionary = {}) -> Array:
	var out: Array = []
	if not enabled() or unit_id == "":
		return out
	var units: Dictionary = board.get("units", {}) if board.has("units") else Common.state().get("units", {})
	var u: Dictionary = units.get(unit_id, Common.unit(unit_id))
	var owner := int(u.get("owner", 0))
	for oid in units:
		var o: Dictionary = units[oid]
		if int(o.get("owner", 0)) == owner or not has(o, "wimp_kickaz"):
			continue
		if not Common.is_on_battlefield(o):
			continue
		if Ab._units_engaged(str(oid), unit_id):
			out.append(str(oid))
	return out

## Impulsive Recon: "In your first Movement phase, this unit can make an
## ingress move." True for that unit in battle round 1, its owner's turn.
static func allows_first_round_ingress(unit: Dictionary) -> bool:
	if not enabled() or _round() != 1:
		return false
	if int(unit.get("owner", 0)) != Common.active_player():
		return false
	return has(unit, "impulsive_recon")

## The ids among `reserve_ids` that may arrive in battle round 1 (Main's
## reinforcement list).
static func first_round_ingress_units(reserve_ids: Array) -> Array:
	var out: Array = []
	for rid in reserve_ids:
		if allows_first_round_ingress(Common.unit(str(rid))):
			out.append(str(rid))
	return out

## Flyboss: "When this unit ends an ingress move, each friendly ORKS
## AIRCRAFT/DEFFKOPTAS unit within 6\" of this unit is riled up until the
## start of your next turn." MovementPhase hook after the arrival is set up;
## returns the diffs (the caller adds them to its changes).
static func on_ingress_move_ended(unit_id: String, arrival_positions: Array = []) -> Array:
	var diffs: Array = []
	if not enabled() or unit_id == "":
		return diffs
	var u := Common.unit(unit_id)
	if not has(u, "flyboss"):
		return diffs
	var owner := int(u.get("owner", 0))
	var picked: Array = []
	for fid in Ab._friendly_heads(owner):
		var f := str(fid)
		if Ab.head_id(f) == Ab.head_id(unit_id):
			continue
		if not (Ab.group_has_keyword(f, "AIRCRAFT") or Ab.group_has_keyword(f, "DEFFKOPTAS")):
			continue
		if not Ab.group_has_keyword(f, "ORKS"):
			continue
		if _within_after_arrival(unit_id, f, 6.0, arrival_positions):
			diffs.append_array(Ab.rile_up_diffs(f, owner, "start_of_your_next_turn", "Flyboss"))
			picked.append(Common.unit_name(f))
	var text := "Flyboss — %s ended an ingress move: %s" % [Common.unit_name(unit_id),
		("riled up until the start of your next turn: " + ", ".join(PackedStringArray(picked))) if not picked.is_empty() else "no friendly ORKS AIRCRAFT/DEFFKOPTAS unit within 6\""]
	_log(text)
	_event(owner, text)
	return diffs

## Distance check against the arriving unit's NEW positions (the arrival
## diffs are not applied yet when the MovementPhase hook runs): the action's
## model positions, in model order; falls back to the live positions.
static func _within_after_arrival(a_id: String, b_id: String, inches: float, arrival_positions: Array) -> bool:
	if arrival_positions.is_empty():
		return Ab.within(a_id, b_id, inches)
	var meas = Common.autoload("Measurement")
	var models: Array = Common.unit(a_id).get("models", [])
	for i in range(mini(models.size(), arrival_positions.size())):
		var p = arrival_positions[i]
		if p == null:
			continue
		var am: Dictionary = (models[i] as Dictionary).duplicate()
		var pv := _v(p)
		am["position"] = {"x": pv.x, "y": pv.y}
		for bm in Ab._models_of(b_id):
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(am, bm))
			else:
				d = pv.distance_to(_v(bm.position)) / PX_PER_INCH
			if d <= inches + 0.001:
				return true
	return false

## Boss Boomer (WAGON): "While a WARBOSS model is embarked within this unit,
## this unit has that WARBOSS model's Intimidating Motivation / Keep Huntin'
## ability." OrkAbilities11e.has hook for those two slugs.
static func boss_boomer_grants(u: Dictionary, slug: String) -> bool:
	if not enabled() or not slug in ["intimidating_motivation", "keep_huntin"]:
		return false
	if not has(u, "boss_boomer") or not Common.has_keyword(u, "WAGON"):
		return false
	var want: String = str(Ab.NAMES.get(slug, ""))
	for eid in _embarked_unit_ids(_uid(u)):
		var e := Common.unit(str(eid))
		if not Common.has_keyword(e, "WARBOSS") or not Common.is_alive(e):
			continue
		for ab in e.get("meta", {}).get("abilities", []):
			if fold(Ab._ability_name(ab)) == want:
				return true
	return false

# ===========================================================================
# PSYCHIC (Warphead) and LEADERSHIP (Enhanced Runt-maw)
# ===========================================================================

## Warphead: "This model has psyker level 2" (OrkArmyRules11e.psyker_level).
static func psyker_level(u: Dictionary) -> int:
	return 2 if has(u, "warphead") else 0

## Warphead: "can re-roll psychic rolls". A psychic roll only matters on a 1
## (battle-shocked), so a 1 is re-rolled and nothing else is (ruling). Each
## roll site calls this right after its D6.
static func psychic_reroll(unit_id: String, roll: int, rng) -> int:
	if roll != 1 or not has_id(unit_id, "warphead"):
		return roll
	var again := Ab._d6(rng)
	var text := "Warphead — %s re-rolls its psychic roll of 1: %d" % [Common.unit_name(unit_id), again]
	_log(text)
	_event(int(Common.unit(unit_id).get("owner", 0)), text)
	return again

## Enhanced Runt-maw: an infested unit "has -1 to leadership rolls" — as a
## worsened Ld (the roll needs one more), the same encoding the engine uses
## for Madcap Artillery's "zapped" (OrkAbilities11e.leadership_penalty).
static func leadership_penalty(unit_id: String) -> int:
	if not enabled() or unit_id == "":
		return 0
	return 1 if Ab.group_flag(unit_id, F_INFESTED) != null else 0

# ===========================================================================
# REDEPLOY (Kaptin's Hat) — FactionAbilityManager's redeploy-enhancement
# machinery (the Razgit's Magik Map flow: up to three units, strategic
# reserves allowed regardless of how many are already there).
# ===========================================================================

static func redeploy_enhancement(player: int) -> Dictionary:
	if not enabled() or _bearers("kaptins_hat", player).is_empty():
		return {}
	return {"name": "Kaptin's Hat", "keywords": ["ORKS", "INFANTRY"]}

# ===========================================================================
# ACTIVATED ENHANCEMENTS — offered as 0-CP "Enhancement" cards through the
# stratagem-window framework (the O6 ability path: OrkAbilities11e
# .window_offers appends these; ids "ork11e_ab_enh_<slug>" route to use()).
# ===========================================================================

const WINDOW_ENHANCEMENTS := {
	"movement_phase_start": ["da_boss_is_watchin"],
	"unit_selected_to_move": ["da_boss_is_watchin"],
	"unit_selected_to_shoot": ["dreadherder", "temperamental_shokka"],
	"unit_has_shot": ["enhanced_runt_maw"],
	"movement_phase_end": ["morgogs_finkin_cap"],
}

const EFFECT_TEXT := {
	"da_boss_is_watchin": "Once per battle, per army: this unit is riled up until the start of your next turn.",
	"dreadherder": "Select one friendly ORKS WALKER unit within 3\" of the Big Mek: its attacks can re-roll hit rolls of 1 until the end of the turn.",
	"temperamental_shokka": "Roll one D6 — 1: the Shokk Attack Gun has [TORRENT] and this model is destroyed when the unit has shot; 2-5: +1 A; 6: [SUSTAINED HITS 2].",
	"enhanced_runt_maw": "Select one enemy unit hit by those attacks: it is infested with Snotlings (-1 to leadership rolls) until the start of your next turn.",
	"morgogs_finkin_cap": "Once per battle, per army: this unengaged unit makes a normal move of up to D6\" (riled up: you can re-roll that D6).",
}

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

static func _use_key(slug: String) -> String:
	return USE_PREFIX + slug

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if not enabled():
		return offers
	for slug in WINDOW_ENHANCEMENTS.get(window_id, []):
		var targets: Array = _targets(str(slug), player, window_id, ctx)
		if targets.is_empty():
			continue
		var text := str(EFFECT_TEXT.get(str(slug), ""))
		var pend := _morgog_pending(player)
		if str(slug) == "morgogs_finkin_cap" and not pend.is_empty():
			text = "You rolled %d\" for Morgog's Finkin' Cap and the unit is riled up: move up to %d\", or re-roll the D6." % [int(pend.roll), int(pend.roll)]
		offers.append({
			"stratagem_id": sid_of(str(slug)),
			"name": display(str(slug)),
			"cp_cost": 0,
			"cost_text": "Enhancement",
			"effect_text": text,
			"type": "Enhancement",
			"is_ability": true,
			"targets": targets,
		})
	if not offers.is_empty():
		_log("window %s P%d — enhancement offers %s" % [window_id, player, str(offers.map(func(o): return o.name))])
	return offers

static func _entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	return Common.target_entry(unit_id, extra)

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var active := Common.active_player()
	var own_turn := player == active
	match slug:
		"da_boss_is_watchin":
			if not own_turn or Ab.army_used_in_battle(player, _use_key(slug)) >= 1:
				return []
			var out: Array = []
			if window_id == "unit_selected_to_move":
				var h := holder(str(ctx.get("unit_id", "")), slug)
				if h != "" and int(Common.unit(h).get("owner", 0)) == player and Common.is_on_battlefield(Common.unit(h)):
					out.append(_entry(Ab.head_id(h)))
				return out
			for b in _bearers(slug, player):
				if Common.is_on_battlefield(Common.unit(b)) or _is_embarked(Common.unit(b)):
					var head := Ab.head_id(b)
					if not head in out.map(func(e): return e.unit_id):
						out.append(_entry(head))
			return out
		"dreadherder":
			if not own_turn:
				return []
			var sel := str(ctx.get("unit_id", ""))
			if sel == "" or int(Common.unit(sel).get("owner", 0)) != player:
				return []
			var out: Array = []
			# (a) the walker itself is selected to shoot: any Dreadherder Big Mek
			# within 3" that has not selected a unit this phase.
			if Ab.group_has_keyword(sel, "WALKER") and Ab.group_has_keyword(sel, "ORKS") and not Ab.group_has_keyword(sel, "BIG MEK") \
					and Ab.group_flag(sel, F_DREADHERDER) == null:
				for b in _bearers(slug, player):
					if Ab.used_this_phase(b, _use_key(slug)) or not Common.is_on_battlefield(Common.unit(b)):
						continue
					if Ab.head_id(sel) in _walkers_near(b, player).map(func(x): return Ab.head_id(str(x))):
						out.append(_entry(Ab.head_id(sel), {"bearer_id": b}))
						break
			# (b) the Big Mek's own unit is selected to shoot: pick a walker.
			var hb := holder(sel, slug)
			if out.is_empty() and hb != "" and not Ab.used_this_phase(hb, _use_key(slug)) and Common.is_on_battlefield(Common.unit(hb)):
				var walkers: Array = []
				for w in _walkers_near(hb, player):
					if Ab.group_flag(str(w), F_DREADHERDER) == null:
						walkers.append(Ab.head_id(str(w)))
				if not walkers.is_empty():
					out.append(_entry(hb, {"bearer_id": hb, "secondary": Ab._unit_options(walkers, "Select the ORKS WALKER unit")}))
			return out
		"temperamental_shokka":
			if not own_turn or _phase() != PH_SHOOTING:
				return []
			var h := holder(str(ctx.get("unit_id", "")), slug)
			if h == "" or int(Common.unit(h).get("owner", 0)) != player or Ab.used_this_phase(h, _use_key(slug)):
				return []
			if Common.unit(h).get("flags", {}).has(F_TSHOKKA):
				return []
			return [_entry(h)]
		"enhanced_runt_maw":
			if not own_turn:
				return []
			var h := holder(str(ctx.get("unit_id", "")), slug)
			if h == "" or Ab.used_this_phase(h, _use_key(slug)):
				return []
			var cands := _runt_maw_candidates(player, ctx.get("hit_unit_ids", []))
			if cands.size() < 2:
				return []  # 0: nothing hit; 1: resolved automatically (after_unit_shot)
			return [_entry(h, {"secondary": Ab._unit_options(cands, "Select one enemy unit hit by those attacks")})]
		"morgogs_finkin_cap":
			if own_turn:
				return []  # "At the end of your OPPONENT's Movement phase"
			var pend := _morgog_pending(player)
			if not pend.is_empty():
				var pu := str(pend.get("unit_id", ""))
				return [_entry(pu, {"require_variant": true, "ai_variant": "keep" if int(pend.roll) >= 4 else "reroll", "variants": [
					{"id": "keep", "label": "Move up to %d\"" % int(pend.roll), "cp_cost": 0},
					{"id": "reroll", "label": "Re-roll the D6 (riled up)", "cp_cost": 0}]})]
			if Ab.army_used_in_battle(player, _use_key(slug)) >= 1:
				return []
			var out: Array = []
			for b in _bearers(slug, player):
				if not Common.is_on_battlefield(Common.unit(b)):
					continue
				var head := Ab.head_id(b)
				if Common.is_engaged(head):
					continue
				out.append(_entry(head, {"bearer_id": b}))
			return out
	return []

static func _runt_maw_candidates(player: int, hit_unit_ids) -> Array:
	var out: Array = []
	if not (hit_unit_ids is Array):
		return out
	for tid in hit_unit_ids:
		var t := str(tid)
		var tu := Common.unit(t)
		if tu.is_empty() or int(tu.get("owner", 0)) == player or not Common.is_alive(tu):
			continue
		var head := Ab.head_id(t)
		if not head in out:
			out.append(head)
	return out

static func _morgog_pending(player: int) -> Dictionary:
	var p = Common.state().get("players", {}).get(str(player), {}).get(P_MORGOG, null)
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	if str(p.get("phase_key", "")) != _phase_key():
		return {}
	return p

## USE_WINDOW_STRATAGEM on an enhancement offer (routed by OrkAbilities11e.use).
static func use(player: int, sid: String, target_unit_id: String, context: Dictionary) -> Dictionary:
	var slug := slug_of(sid)
	var window_id := str(context.get("window_id", ""))
	var entry: Dictionary = {}
	for t in _targets(slug, player, window_id, context):
		if str(t.get("unit_id", "")) == target_unit_id:
			entry = t
	if entry.is_empty():
		return {"success": false, "error": "%s cannot be used on %s now" % [display(slug), Common.unit_name(target_unit_id)], "diffs": []}
	var secondary := str(context.get("secondary_id", ""))
	if entry.has("secondary"):
		var ok := false
		for o in entry.secondary.get("options", []):
			if str(o.get("id", "")) == secondary:
				ok = true
		if not ok:
			return {"success": false, "error": "%s needs a valid target unit" % display(slug), "diffs": []}
	var variant := str(context.get("variant_id", ""))
	if bool(entry.get("require_variant", false)):
		var vok := false
		for v in entry.get("variants", []):
			if str(v.get("id", "")) == variant:
				vok = true
		if not vok:
			return {"success": false, "error": "%s needs one of its options" % display(slug), "diffs": []}
	var res := _apply_use(slug, player, target_unit_id, entry, secondary, variant)
	var diffs: Array = res.get("diffs", [])
	_apply(diffs)
	var log_text := str(res.get("log", ""))
	if log_text != "":
		_log(log_text)
		_event(player, log_text)
	var out := {"success": true, "diffs": diffs, "stratagem_name": display(slug), "cp_cost": 0}
	var followup: Dictionary = res.get("followup", {})
	var wctx: Dictionary = context.duplicate(true)
	for k in ["secondary_id", "variant_id", "variant_label"]:
		wctx.erase(k)
	if bool(res.get("reoffer", false)):
		followup = {"type": "ork11e_reoffer", "player": player, "window_id": window_id, "ctx": wctx}
	elif followup.is_empty() and (window_id in Ab.REOFFER_WINDOWS or window_id in Ab.REOFFER_IF_ABILITY_LEFT):
		if window_id in Ab.REOFFER_WINDOWS or not Ab.window_offers(player, window_id, wctx).is_empty():
			followup = {"type": "ork11e_reoffer", "player": player, "window_id": window_id, "ctx": wctx}
	if not followup.is_empty():
		out["followup"] = followup
	return out

static func _apply_use(slug: String, player: int, uid: String, entry: Dictionary, secondary: String, variant: String) -> Dictionary:
	var rng = Ab._rng()
	var name := Common.unit_name(uid)
	match slug:
		"da_boss_is_watchin":
			var d: Array = [Ab.army_use_diff(player, _use_key(slug))]
			d.append_array(Ab.rile_up_diffs(uid, player, "start_of_your_next_turn", "Da Boss is Watchin'"))
			return {"diffs": d, "log": "Da Boss is Watchin' — %s is riled up until the start of your next turn" % name}
		"dreadherder":
			var bearer := str(entry.get("bearer_id", uid))
			var walker := secondary if secondary != "" else uid
			var d: Array = [Ab.use_diff(bearer, _use_key(slug))]
			d.append_array(Common.set_flag_diffs(Ab.group(walker), F_DREADHERDER, {"player": player, "turn_key": _turn_key()}))
			return {"diffs": d, "log": "Dreadherder — %s's attacks can re-roll hit rolls of 1 until the end of the turn (%s)" % [Common.unit_name(walker), Common.unit_name(bearer)]}
		"temperamental_shokka":
			var roll := Ab._d6(rng)
			var d: Array = [Ab.use_diff(uid, _use_key(slug))]
			d.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_TSHOKKA], "value": {"result": roll, "player": player}})
			var what := "[TORRENT] — this model is destroyed when the unit has shot" if roll == 1 else ("+1 A" if roll <= 5 else "[SUSTAINED HITS 2]")
			return {"diffs": d, "log": "Temperamental Shokka — %s rolls %d: Shokk Attack Gun %s" % [name, roll, what]}
		"enhanced_runt_maw":
			return _runt_maw_apply(player, uid, secondary)
		"morgogs_finkin_cap":
			return _morgog_apply(player, uid, variant, rng)
	return {"diffs": [], "log": ""}

static func _runt_maw_apply(player: int, holder_id: String, target_id: String) -> Dictionary:
	var d: Array = [Ab.use_diff(holder_id, _use_key("enhanced_runt_maw"))]
	d.append_array(Common.set_flag_diffs(Ab.group(target_id), F_INFESTED, {"player": player, "set_turn_key": _turn_key()}))
	return {"diffs": d, "log": "Enhanced Runt-maw — %s is infested with Snotlings: -1 to leadership rolls until the start of your next turn" % Common.unit_name(target_id)}

static func _morgog_apply(player: int, uid: String, variant: String, rng) -> Dictionary:
	var pend := _morgog_pending(player)
	var d: Array = []
	var roll := 0
	var note := ""
	if pend.is_empty():
		d.append(Ab.army_use_diff(player, _use_key("morgogs_finkin_cap")))
		roll = Ab._d6(rng)
		note = "rolls %d\"" % roll
		if Ab.group_riled_up(uid):
			# Riled up: the player may re-roll — park the roll and re-offer.
			d.append({"op": "set", "path": "players.%d.%s" % [player, P_MORGOG], "value": {"unit_id": uid, "roll": roll, "phase_key": _phase_key()}})
			return {"diffs": d, "log": "Morgog's Finkin' Cap — %s %s (riled up: move, or re-roll the D6)" % [Common.unit_name(uid), note],
				"reoffer": true}
	else:
		d.append({"op": "set", "path": "players.%d.%s" % [player, P_MORGOG], "value": null})
		roll = int(pend.roll)
		if variant == "reroll":
			var again := Ab._d6(rng)
			note = "re-rolls %d\" -> %d\"" % [roll, again]
			roll = again
		else:
			note = "keeps %d\"" % roll
	var text := "Morgog's Finkin' Cap — %s %s: normal move of up to %d\"" % [Common.unit_name(uid), note, roll]
	return {"diffs": d, "log": text, "followup": {"type": "reactive_normal_move", "unit_id": uid, "max_inches": float(roll), "roll": roll, "source": "Morgog's Finkin' Cap"}}

## AI score for an enhancement offer (OrkAbilities11e.ai_score routes here;
## threshold 1.0, no CP). Synchronous — a window never waits on the AI.
static func ai_score(player: int, sid: String, target_unit_id: String, _window_id: String, _ctx: Dictionary) -> float:
	match slug_of(sid):
		"da_boss_is_watchin":
			# Worth it for an unengaged unit with an enemy close enough to charge.
			if Ab.group_riled_up(target_unit_id) or Common.is_engaged(target_unit_id):
				return 0.0
			for eid in Ab._enemy_heads(player):
				if Ab.within(target_unit_id, str(eid), 12.0):
					return 2.0
			return 0.0
		"dreadherder":
			return 2.0
		"temperamental_shokka":
			return 0.0  # a 1 destroys the Big Mek: the AI keeps the gun as printed
		"enhanced_runt_maw":
			return 2.0
		"morgogs_finkin_cap":
			if not _morgog_pending(player).is_empty():
				return 2.0  # finish the use (keep or re-roll, ai_variant)
			return 0.0  # repositioning is a plan-level decision
	return 0.0

# ===========================================================================
# SHOOTING HOOKS
# ===========================================================================

## OrkDetachments11e.ug_on_targets_confirmed hook (interactive and AI paths):
## record how many ranged weapons the Supa-glowy Fing bearer selected
## ([SUPA-HAZARDOUS] — two hazard rolls each, after the unit has shot).
static func on_targets_confirmed(shooter_id: String, assignments: Array) -> void:
	if not enabled() or shooter_id == "":
		return
	var h := holder(shooter_id, "supa_glowy_fing")
	if h == "":
		return
	var weapons := {}
	for a in assignments:
		if not (a is Dictionary):
			continue
		var wid := str(a.get("weapon_id", ""))
		var mids: Array = a.get("model_ids", [])
		var by_bearer := false
		if h == shooter_id and mids.is_empty():
			by_bearer = true
		for mid in mids:
			if Ab._bearer_unit_id(shooter_id, mid) == h:
				by_bearer = true
		if by_bearer and wid != "":
			weapons[wid] = true
	if weapons.is_empty():
		return
	var u := Common.unit(h)
	if not u.has("flags"):
		u["flags"] = {}
	u["flags"][F_SUPA_SEL] = weapons.size()
	_log("Supa-glowy Fing — %s selected %d [SUPA-HAZARDOUS] weapon(s): %s" % [h, weapons.size(), str(weapons.keys())])

## OrkAbilities11e.after_unit_shot hook ("when this unit has shot"):
## Enhanced Runt-maw with exactly one enemy unit hit, Temperamental Shokka's
## end (and the bearer's destruction on a 1), Supa-glowy Fing's hazard rolls.
## Returns the applied diffs.
static func after_unit_shot(shooter_id: String, hit_unit_ids: Array) -> Array:
	var all: Array = []
	if not enabled() or shooter_id == "":
		return all
	var player := int(Common.unit(shooter_id).get("owner", 0))
	# Enhanced Runt-maw — one candidate: resolved automatically.
	var rm := holder(shooter_id, "enhanced_runt_maw")
	if rm != "" and not Ab.used_this_phase(rm, _use_key("enhanced_runt_maw")):
		var cands := _runt_maw_candidates(player, hit_unit_ids)
		if cands.size() == 1:
			var res := _runt_maw_apply(player, rm, str(cands[0]))
			_apply(res.diffs)
			all.append_array(res.diffs)
			_log(str(res.log))
			_event(player, str(res.log))
	# Temperamental Shokka: effects end "when this unit has shot"; on a 1 the
	# model is destroyed then.
	for gid in Ab.group(shooter_id):
		var g := Common.unit(str(gid))
		var ts = g.get("flags", {}).get(F_TSHOKKA, null)
		if typeof(ts) != TYPE_DICTIONARY:
			continue
		var d: Array = [{"op": "remove", "path": "units.%s.flags.%s" % [gid, F_TSHOKKA]}]
		if int(ts.get("result", 0)) == 1:
			for i in range(g.get("models", []).size()):
				if g.models[i].get("alive", true):
					d.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [gid, i], "value": 0})
					d.append({"op": "set", "path": "units.%s.models.%d.alive" % [gid, i], "value": false})
			var text := "Temperamental Shokka — %s rolled a 1: the Big Mek is destroyed now that the unit has shot" % Common.unit_name(str(gid))
			_log(text)
			_event(player, text)
		_apply(d)
		all.append_array(d)
	# Supa-glowy Fing — [SUPA-HAZARDOUS]: two hazard rolls per selected weapon.
	for gid in Ab.group(shooter_id):
		var g := Common.unit(str(gid))
		var n := int(g.get("flags", {}).get(F_SUPA_SEL, 0))
		if n <= 0:
			continue
		var d: Array = [{"op": "remove", "path": "units.%s.flags.%s" % [gid, F_SUPA_SEL]}]
		var rng = Ab._rng()
		var hz: Dictionary = AttackSequence.hazard_rolls(g, 2 * n, rng)
		var mw := int(hz.get("mortal_wounds", 0))
		var text := "Supa-glowy Fing [SUPA-HAZARDOUS] — %s makes %d hazard rolls: %s — %s" % [Common.unit_name(str(gid)), 2 * n, str(hz.get("rolls", [])),
			("%d failed, %d mortal wound%s" % [int(hz.get("failures", 0)), mw, "" if mw == 1 else "s"]) if mw > 0 else "all passed"]
		_log(text)
		_event(player, text)
		_apply(d)
		all.append_array(d)
		if mw > 0:
			var r: Dictionary = Det.mortal_wounds_to_unit(str(gid), mw, rng)
			_apply(r.diffs)
			all.append_array(r.diffs)
	return all

# ===========================================================================
# PHASE TRANSITIONS (OrkAbilities11e.on_phase_transition hook — runs on every
# peer, after the outgoing phase exited, before the new one is entered)
# ===========================================================================

static func on_phase_transition(old_phase: int, new_phase: int) -> void:
	if not enabled():
		return
	var units: Dictionary = Common.state().get("units", {})
	var active := Common.active_player()
	var cleared: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		var flags: Dictionary = u.get("flags", {})
		if old_phase == PH_SHOOTING and new_phase != PH_SHOOTING:
			for f in [F_TSHOKKA, F_SUPA_SEL]:
				if flags.has(f):
					flags.erase(f)
					cleared.append("%s.%s" % [uid, f])
		if new_phase == PH_COMMAND:
			if flags.has(F_DREADHERDER):
				flags.erase(F_DREADHERDER)  # "until the end of the turn"
				cleared.append("%s.%s" % [uid, F_DREADHERDER])
			var inf = flags.get(F_INFESTED, null)
			if typeof(inf) == TYPE_DICTIONARY and int(inf.get("player", 0)) == active and str(inf.get("set_turn_key", "")) != _turn_key():
				flags.erase(F_INFESTED)  # "until the start of your next turn"
				cleared.append("%s.%s" % [uid, F_INFESTED])
	if not cleared.is_empty():
		_log("phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])
	if old_phase != new_phase:
		_surly_end_of_phase(old_phase)
	_apply_permanent_states()
	_surly_stamp(new_phase)

## Mekwaaagh! Mastermind: "This unit is riled up." — re-asserted at every
## phase start (the O6 Waaagh! Effigy pattern).
static func _apply_permanent_states() -> void:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if not has(u, "mekwaaagh_mastermind"):
			continue
		if not Common.is_on_battlefield(u) and not _is_embarked(u):
			continue
		var need := false
		for gid in Ab.group(str(uid)):
			var g := Common.unit(str(gid))
			if not Common.is_riled_up(g) or typeof(g.get("flags", {}).get(Ab.F_RILED, null)) != TYPE_DICTIONARY:
				need = true
		if not need:
			continue
		for d in Ab.rile_up_diffs(str(uid), int(u.get("owner", 0)), "permanent", "Mekwaaagh! Mastermind"):
			var parts := str(d.path).split(".")
			var target: Dictionary = units.get(parts[1], {})
			if target.is_empty():
				continue
			if not target.has("flags"):
				target["flags"] = {}
			target["flags"][parts[3]] = d.value
		_log("Mekwaaagh! Mastermind — %s is riled up" % str(uid))

# --- Surly as a Squiggoth ----------------------------------------------------
# "(Once per battle, per army) At the end of a phase in which this model is
# destroyed, roll one D6: on a 2+, set this model back up on the battlefield
# as close as possible to where it was destroyed, unengaged, with 3 wounds
# remaining." The bearer's alive state and position are stamped at every
# phase start; a bearer alive then and dead at the end of that phase was
# destroyed in it.

static func _bearer_model_index(u: Dictionary) -> int:
	var models: Array = u.get("models", [])
	return 0 if not models.is_empty() else -1

static func _surly_stamp(new_phase: int) -> void:
	for uid in _bearers("surly_as_a_squiggoth"):
		var u := Common.unit(uid)
		var i := _bearer_model_index(u)
		if i < 0:
			continue
		var m: Dictionary = u.models[i]
		var pos = m.get("position", null)
		var marker := {"alive": bool(m.get("alive", true)), "phase": new_phase,
			"pos": {"x": float(pos.x), "y": float(pos.y)} if pos != null else null}
		if not u.has("flags"):
			u["flags"] = {}
		var prev = u.flags.get(F_SURLY, null)
		if typeof(prev) == TYPE_DICTIONARY and marker.pos == null:
			marker["pos"] = prev.get("pos", null)
		u.flags[F_SURLY] = marker

static func _surly_end_of_phase(old_phase: int) -> void:
	for uid in _bearers("surly_as_a_squiggoth"):
		var u := Common.unit(uid)
		var marker = u.get("flags", {}).get(F_SURLY, null)
		if typeof(marker) != TYPE_DICTIONARY or not bool(marker.get("alive", false)):
			continue
		var i := _bearer_model_index(u)
		if i < 0 or bool(u.models[i].get("alive", true)):
			continue
		var player := int(u.get("owner", 0))
		if Ab.army_used_in_battle(player, _use_key("surly_as_a_squiggoth")) >= 1:
			continue
		var rng = Ab._rng()
		var roll := Ab._d6(rng)
		var d: Array = [Ab.army_use_diff(player, _use_key("surly_as_a_squiggoth"))]
		var text := "Surly as a Squiggoth — %s was destroyed this phase: rolls %d" % [Common.unit_name(uid), roll]
		if roll >= 2:
			var at = u.models[i].get("position", null)
			if at == null:
				at = marker.get("pos", null)
			var spot := _surly_spot(uid, i, at)
			if spot == Vector2.INF:
				text += " — no unengaged spot found on the battlefield; it stays destroyed"
			else:
				var max_w := int(u.models[i].get("wounds", 3))
				d.append({"op": "set", "path": "units.%s.models.%d.alive" % [uid, i], "value": true})
				d.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [uid, i], "value": mini(3, max_w)})
				d.append({"op": "set", "path": "units.%s.models.%d.position" % [uid, i], "value": {"x": spot.x, "y": spot.y}})
				text += " — set back up with %d wounds remaining, %.1f\" from where it fell" % [mini(3, max_w), (spot - _v(at)).length() / PX_PER_INCH if at != null else 0.0]
		else:
			text += " — it stays destroyed"
		_apply(d)
		_log("%s (end of phase %d)" % [text, old_phase])
		_event(player, text)

static func _v(p) -> Vector2:
	if p == null:
		return Vector2.ZERO
	if p is Vector2:
		return p
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))

## Nearest legal spot (rings of 0.25" around the death position, up to 24"):
## on the board, not overlapping any other model, and unengaged (outside the
## engagement range of every enemy model).
static func _surly_spot(unit_id: String, model_index: int, at) -> Vector2:
	var u := Common.unit(unit_id)
	var meas = Common.autoload("Measurement")
	var model: Dictionary = (u.models[model_index] as Dictionary).duplicate(true)
	var origin := _v(at) if at != null else Vector2.INF
	if origin == Vector2.INF:
		return Vector2.INF
	var size: Dictionary = Common.state().get("board", {}).get("size", {"width": 44, "height": 60})
	var bw := float(size.get("width", 44)) * PX_PER_INCH
	var bh := float(size.get("height", 60)) * PX_PER_INCH
	var r_in := float(model.get("base_mm", 32)) / 25.4 / 2.0
	var er := GameConstants.engagement_range_inches()
	var owner := int(u.get("owner", 0))
	var others: Array = []
	for oid in Common.state().get("units", {}):
		var o := Common.unit(str(oid))
		if not Common.is_on_battlefield(o):
			continue
		for om in o.get("models", []):
			if om.get("alive", true) and om.get("position", null) != null:
				others.append({"m": om, "enemy": int(o.get("owner", 0)) != owner})
	var ring := 0.0
	while ring <= 24.0:
		var steps := 1 if ring == 0.0 else int(ceil(TAU * ring / 0.5))
		for s in range(steps):
			var ang := TAU * float(s) / float(steps)
			var p := origin + Vector2(cos(ang), sin(ang)) * ring * PX_PER_INCH
			if p.x < r_in * PX_PER_INCH or p.y < r_in * PX_PER_INCH or p.x > bw - r_in * PX_PER_INCH or p.y > bh - r_in * PX_PER_INCH:
				continue
			model["position"] = {"x": p.x, "y": p.y}
			var ok := true
			for e in others:
				var dist := INF
				if meas and meas.has_method("model_to_model_distance_inches"):
					dist = float(meas.model_to_model_distance_inches(model, e.m))
				else:
					dist = p.distance_to(_v(e.m.position)) / PX_PER_INCH - r_in - float(e.m.get("base_mm", 32)) / 25.4 / 2.0
				if dist < 0.01 or (e.enemy and dist <= er + 0.001):
					ok = false
					break
			if ok:
				return p
		ring += 0.25
	return Vector2.INF

# ===========================================================================
# SMOKY GUBBINZ — cover from a model of this unit (TerrainManager hook)
# ===========================================================================
# "When an attack targets a unit that is not fully visible to the attacking
# model because of a model in this unit, the target has the benefit of cover
# against that attack." The engine's sight lines only test terrain, so a
# Smoky Gubbinz model blocks here: a sight line from the attacking model to a
# sight point of a target model that passes through that model's base (as a
# circle of its base size) makes the target not fully visible.

static func smoky_gubbinz_cover(target_unit: Dictionary, attacker_model: Dictionary) -> bool:
	if not enabled() or attacker_model.is_empty() or target_unit.is_empty():
		return false
	var apos = attacker_model.get("position", null)
	if apos == null:
		return false
	var smoky: Array = []
	for b in _bearers("smoky_gubbinz"):
		if Common.is_on_battlefield(Common.unit(b)):
			smoky.append(b)
	if smoky.is_empty():
		return false
	var tid := _uid(target_unit)
	var tm = Common.autoload("TerrainManager")
	var a := _v(apos)
	for sid in smoky:
		if Ab.head_id(sid) == Ab.head_id(tid):
			continue
		var blockers: Array = []
		var attacker_in_unit := false
		for gid in Ab.group(sid):
			for sm in Common.unit(str(gid)).get("models", []):
				if not sm.get("alive", true) or sm.get("position", null) == null:
					continue
				var c := _v(sm.position)
				var r := _base_radius_px(sm)
				if c.distance_to(a) <= r:
					attacker_in_unit = true  # the attacking model belongs to this unit
				blockers.append({"c": c, "r": r})
		if attacker_in_unit or blockers.is_empty():
			continue
		for tmodel in target_unit.get("models", []):
			if not tmodel.get("alive", true) or tmodel.get("position", null) == null:
				continue
			var pts: Array = [_v(tmodel.position)]
			if tm and tm.has_method("_sight_points"):
				pts = tm._sight_points(tmodel)
			for p in pts:
				var pv := _v(p)
				for bl in blockers:
					if _segment_hits_circle(a, pv, bl.c, bl.r):
						_log("Smoky Gubbinz — %s is not fully visible to the attacking model because of %s: benefit of cover" % [Common.unit_name(tid), Common.unit_name(sid)])
						return true
	return false

static func _base_radius_px(m: Dictionary) -> float:
	var mm := float(m.get("base_mm", 32))
	var dims = m.get("base_dimensions", null)
	if typeof(dims) == TYPE_DICTIONARY:
		mm = (float(dims.get("length", mm)) + float(dims.get("width", mm))) / 2.0
	return mm / 25.4 / 2.0 * PX_PER_INCH

static func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return a.distance_to(c) < r
	var t := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r
