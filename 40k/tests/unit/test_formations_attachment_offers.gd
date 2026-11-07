extends SceneTree

# L7-3 — FormationsPhase must never OFFER a leader attachment that its own
# validator then refuses.
#
# The bug: at edition 11 get_available_actions still offered a SECOND leader on
# a bodyguard by the 10e dual-leader rule (a "Bodyguard" ability, 20+ models,
# one of the two a WARBOSS), while _validate_declare_leader_attachment applies
# the 11e per-role rule (one LEADER unit and one SUPPORT unit per bodyguard,
# 19.01 / 24.22 / 24.34) and refused it: "Bodyguard already has a leader unit
# attached". The AI picks from these offers, so on audit_378_formations it
# attached the Painboss to Boyz Alpha, was offered a Warboss on the same unit,
# was refused, picked it again — 4124 refusals in 45 s, the MAX_ACTIONS unstick
# routing DECLARE/UNDECLARE forever, and the game never left Formations.
#
# Covers:
#   - 11e: once a LEADER is on a bodyguard, no other LEADER-role character is
#     offered on it (the Warboss -> Boyz Alpha offer is gone);
#   - 11e: a SUPPORT-role character is still offered into the free SUPPORT slot,
#     and that offer validates; once both slots are full nothing more is offered;
#   - 11e: every DECLARE_LEADER_ATTACHMENT the phase offers validates, walked the
#     way the AI walks it (take an offer, declare it, re-read the offers) until
#     no attachment is left to offer — 0 refusals, and it terminates;
#   - 10e: the dual-leader branch is unchanged — Warboss -> Boyz Alpha (Bodyguard,
#     20 models) is offered after the Painboss and validates; a non-WARBOSS
#     second leader is not offered.
#
# Run with: godot --headless --path . -s tests/unit/test_formations_attachment_offers.gd

const FIXTURE := "res://tests/saves/audit_378_formations.w40ksave"
const FORMATIONS_PHASE_PATH := "res://phases/FormationsPhase.gd"

const ORK := 2
const BOYZ_ALPHA := "U_BOYZ_E"      # 20 models, "Bodyguard" ability
const PAINBOSS := "U_PAINBOSS_I"    # LEADER role
const WARBOSS := "U_WARBOSS_B"      # LEADER role, WARBOSS keyword
const WEIRDBOY := "U_WEIRDBOY_J"    # LEADER role in the fixture; made SUPPORT below

var GS
var SL
var CAM
var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== FormationsPhase attachment offers match the validator (L7-3) ===\n")
	GS = get_root().get_node_or_null("GameState")
	SL = get_root().get_node_or_null("SaveLoadManager")
	CAM = get_root().get_node_or_null("CharacterAttachmentManager")
	var ai = get_root().get_node_or_null("AIPlayer")
	if ai != null:
		ai.enabled = false
		ai.ai_players = {1: false, 2: false}
	if GS == null or SL == null or CAM == null:
		_assert(false, "GameState / SaveLoadManager / CharacterAttachmentManager available at run time")
	else:
		var saved_edition: int = GameConstants.edition
		test_11e_no_second_leader_offered()
		test_11e_support_slot_still_offered()
		test_11e_ai_style_walk_never_refused()
		test_10e_dual_leader_offer_unchanged()
		GameConstants.edition = saved_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------

func _fresh_phase(edition: int) -> Node:
	"""audit_378_formations reloaded at `edition`, with a new FormationsPhase
	entered on it and the Ork player declaring."""
	GameConstants.edition = edition
	if not SL.load_game_from_file_path(FIXTURE):
		_assert(false, "fixture %s loads" % FIXTURE)
		return null
	GameConstants.edition = edition
	for key in ["formations_p1_confirmed", "formations_p2_confirmed", "formations_declared"]:
		GS.state["meta"].erase(key)
	var phase = load(FORMATIONS_PHASE_PATH).new()
	get_root().add_child(phase)
	phase.enter_phase(GS.create_snapshot(false))
	# enter_phase hands the declaration to Player 1; the Orks are Player 2.
	GS.state["meta"]["active_player"] = ORK
	phase.current_declaring_player = ORK
	return phase

func _declare(phase: Node, char_id: String, bg_id: String) -> Dictionary:
	return phase.execute_action({"type": "DECLARE_LEADER_ATTACHMENT", "character_id": char_id,
		"bodyguard_id": bg_id, "player": ORK})

func _attachment_offers(phase: Node) -> Array:
	var out: Array = []
	for a in phase.get_available_actions():
		if str(a.get("type", "")) == "DECLARE_LEADER_ATTACHMENT":
			out.append(a)
	return out

func _offered(offers: Array, char_id: String, bg_id: String) -> Dictionary:
	for a in offers:
		if str(a.get("character_id", "")) == char_id and str(a.get("bodyguard_id", "")) == bg_id:
			return a
	return {}

func _refused_offers(phase: Node, offers: Array) -> Array:
	"""Every offer the phase's own validator refuses, as 'char->bg: errors'."""
	var bad: Array = []
	for a in offers:
		var v: Dictionary = phase.validate_action(a.duplicate(true))
		if not v.get("valid", false):
			bad.append("%s->%s: %s" % [a.character_id, a.bodyguard_id, str(v.get("errors", []))])
	return bad

func _make_support(unit_id: String) -> void:
	# CharacterAttachmentManager.attachment_role reads the datasheet ability.
	var abilities: Array = GS.state.units[unit_id].meta.get("abilities", [])
	abilities.append({"name": "Support", "type": "Datasheet"})
	GS.state.units[unit_id].meta["abilities"] = abilities

# ---------------------------------------------------------------------------

func test_11e_no_second_leader_offered() -> void:
	print("\n--- 11e: a LEADER on the bodyguard closes the LEADER slot ---")
	var phase = _fresh_phase(11)
	if phase == null:
		return
	var before := _attachment_offers(phase)
	_assert(not _offered(before, WARBOSS, BOYZ_ALPHA).is_empty(),
		"precondition: Warboss -> Boyz Alpha is offered while the bodyguard is empty")
	var r := _declare(phase, PAINBOSS, BOYZ_ALPHA)
	_assert(r.get("success", false), "Painboss -> Boyz Alpha declares (%s)" % str(r.get("errors", r.get("error", ""))))
	var offers := _attachment_offers(phase)
	var warboss_offer := _offered(offers, WARBOSS, BOYZ_ALPHA)
	_assert(warboss_offer.is_empty(),
		"11e: Warboss -> Boyz Alpha is NOT offered once the Painboss (LEADER) is on it — the 10e dual-leader offer is gone")
	var direct: Dictionary = phase.validate_action({"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": WARBOSS, "bodyguard_id": BOYZ_ALPHA, "player": ORK})
	_assert(not direct.get("valid", true) and str(direct.get("errors", [])).contains("already has a leader unit attached"),
		"11e: the validator still refuses Warboss -> Boyz Alpha (%s)" % str(direct.get("errors", [])))
	var leader_on_alpha := 0
	for a in offers:
		if str(a.bodyguard_id) == BOYZ_ALPHA:
			leader_on_alpha += 1
	_assert(leader_on_alpha == 0, "11e: no character at all is offered on Boyz Alpha (all are LEADER role): %d offer(s)" % leader_on_alpha)
	var bad := _refused_offers(phase, offers)
	_assert(bad.is_empty(), "11e: every offered attachment validates %s" % str(bad))
	phase.queue_free()

func test_11e_support_slot_still_offered() -> void:
	print("\n--- 11e: the SUPPORT slot stays open next to a LEADER ---")
	var phase = _fresh_phase(11)
	if phase == null:
		return
	_make_support(WEIRDBOY)
	_assert(CAM.attachment_role(GS.get_unit(WEIRDBOY)) == "support",
		"setup: the Weirdboy reads as a SUPPORT character")
	var r := _declare(phase, PAINBOSS, BOYZ_ALPHA)
	_assert(r.get("success", false), "Painboss -> Boyz Alpha declares")
	var offers := _attachment_offers(phase)
	var support_offer := _offered(offers, WEIRDBOY, BOYZ_ALPHA)
	_assert(not support_offer.is_empty(), "11e: SUPPORT Weirdboy -> Boyz Alpha is offered next to the LEADER Painboss")
	if not support_offer.is_empty():
		var v: Dictionary = phase.validate_action(support_offer.duplicate(true))
		_assert(v.get("valid", false), "11e: that offer validates (%s)" % str(v.get("errors", [])))
		var r2 := _declare(phase, WEIRDBOY, BOYZ_ALPHA)
		_assert(r2.get("success", false), "11e: SUPPORT Weirdboy -> Boyz Alpha declares")
	var full := 0
	for a in _attachment_offers(phase):
		if str(a.bodyguard_id) == BOYZ_ALPHA:
			full += 1
	_assert(full == 0, "11e: with LEADER + SUPPORT on Boyz Alpha nothing more is offered on it (%d)" % full)
	phase.queue_free()

func test_11e_ai_style_walk_never_refused() -> void:
	print("\n--- 11e: walking the offers like the AI never meets a refusal ---")
	var phase = _fresh_phase(11)
	if phase == null:
		return
	var declared: Array = []
	var refusals: Array = []
	var steps := 0
	while steps < 40:
		var offers := _attachment_offers(phase)
		if offers.is_empty():
			break
		var bad := _refused_offers(phase, offers)
		if not bad.is_empty():
			refusals.append_array(bad)
			break
		# The AI usually takes a Warboss first; prefer the offer that most often
		# exposed the bug: a LEADER onto a bodyguard that already has one.
		var pick: Dictionary = offers[0]
		for a in offers:
			if str(a.bodyguard_id) in [BOYZ_ALPHA, "U_BOYZ_F"]:
				pick = a
				break
		var r := _declare(phase, str(pick.character_id), str(pick.bodyguard_id))
		if not r.get("success", false):
			refusals.append("%s->%s: %s" % [pick.character_id, pick.bodyguard_id, str(r.get("errors", r.get("error", "")))])
			break
		declared.append("%s->%s" % [pick.character_id, pick.bodyguard_id])
		steps += 1
	print("  declared: %s" % str(declared))
	_assert(refusals.is_empty(), "11e: 0 offered attachments refused on the walk %s" % str(refusals))
	_assert(steps < 40, "11e: the walk terminates — attachment offers run out (%d declarations)" % steps)
	var per_bg := {}
	for d in declared:
		var bg := str(d).split("->")[1]
		per_bg[bg] = int(per_bg.get(bg, 0)) + 1
	var doubled: Array = []
	for bg in per_bg:
		if int(per_bg[bg]) > 1:
			doubled.append(bg)
	_assert(doubled.is_empty(), "11e: no bodyguard ended up with two LEADER units %s" % str(per_bg))
	phase.queue_free()

func test_10e_dual_leader_offer_unchanged() -> void:
	print("\n--- 10e: the dual-leader offer (Bodyguard + 20 models + WARBOSS) is kept ---")
	var phase = _fresh_phase(10)
	if phase == null:
		return
	var r := _declare(phase, PAINBOSS, BOYZ_ALPHA)
	_assert(r.get("success", false), "10e: Painboss -> Boyz Alpha declares")
	var offers := _attachment_offers(phase)
	var warboss_offer := _offered(offers, WARBOSS, BOYZ_ALPHA)
	_assert(not warboss_offer.is_empty(), "10e: Warboss -> Boyz Alpha is still offered as the second (dual) leader")
	if not warboss_offer.is_empty():
		var v: Dictionary = phase.validate_action(warboss_offer.duplicate(true))
		_assert(v.get("valid", false), "10e: and the 10e validator accepts it (%s)" % str(v.get("errors", [])))
	_assert(_offered(offers, WEIRDBOY, BOYZ_ALPHA).is_empty(),
		"10e: a non-WARBOSS second leader (Weirdboy) is not offered on Boyz Alpha")
	var bad := _refused_offers(phase, offers)
	_assert(bad.is_empty(), "10e: every offered attachment validates %s" % str(bad))
	phase.queue_free()
