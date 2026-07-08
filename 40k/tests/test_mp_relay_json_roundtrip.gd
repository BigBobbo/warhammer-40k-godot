extends SceneTree

# Web-relay (online / game-code) JSON round-trip — regression net.
#
# The WebSocket relay is JSON, so NetworkManager._sanitize_for_json converts
# every Vector2 in an outgoing action to an {x, y} dict. The host receiving a
# relayed action fed that dict straight into phase handlers that take typed
# Vector2 parameters (e.g. DeploymentPhase._validate_model_position), which
# hard-crashed mid-validation — no rejection was ever sent, so the guest kept
# its optimistic apply forever (permanent online desync on the FIRST deploy).
# _desanitize_from_json is the inverse, applied to every relayed action before
# the phase sees it. This pins the round-trip contract. (ENet never hits this;
# Godot RPCs serialize Variants natively.)
#
# Usage: godot --headless --path . -s tests/test_mp_relay_json_roundtrip.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_mp_relay_json_roundtrip ===\n")
	var nm = root.get_node_or_null("NetworkManager")
	if nm == null:
		_check("NetworkManager autoload reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	# A representative DEPLOY_UNIT action carrying a Vector2 (as the UI builds it).
	var action := {
		"type": "DEPLOY_UNIT",
		"unit_id": "U_TEST",
		"player": 2,
		"payload": {
			"model_id": "m1",
			"position": Vector2(520, 450),
			"rotation": 0.0,
			"nested": {"dest": Vector2(1, 2)},
			"list_of_points": [Vector2(3, 4), Vector2(5, 6)],
		}
	}

	# Simulate the wire: sanitize (what send_game_data does), JSON-encode/decode
	# (what the relay actually does to the bytes), then desanitize (the fix).
	var sanitized = nm._sanitize_for_json(action)
	_check("sanitize turns Vector2 into {x,y} dict",
		sanitized.payload.position is Dictionary and sanitized.payload.position.has("x"))
	var wire = JSON.stringify(sanitized)
	var decoded = JSON.parse_string(wire)
	_check("survives JSON encode/decode", decoded != null)

	var restored = nm._desanitize_from_json(decoded)
	_check("top-level position restored to Vector2",
		restored.payload.position is Vector2,
		str(typeof(restored.payload.position)))
	_check("position value preserved",
		restored.payload.position == Vector2(520, 450),
		str(restored.payload.position))
	_check("nested dict Vector2 restored",
		restored.payload.nested.dest is Vector2 and restored.payload.nested.dest == Vector2(1, 2))
	_check("array-of-Vector2 restored",
		restored.payload.list_of_points.size() == 2 \
			and restored.payload.list_of_points[0] is Vector2 \
			and restored.payload.list_of_points[0] == Vector2(3, 4))
	_check("non-position scalars untouched",
		restored.unit_id == "U_TEST" and int(restored.player) == 2 \
			and restored.payload.model_id == "m1")

	# A plain {x, y} that is NOT a serialized Vector2 context still round-trips as
	# a Vector2 by shape — that's acceptable (handlers reading .x/.y work either
	# way) but confirm a 3-key dict is left as a dict (not mis-coerced).
	var three = nm._desanitize_from_json({"x": 1, "y": 2, "z": 3})
	_check("dict with extra keys is NOT coerced to Vector2", three is Dictionary)

	# The handler guard: _handle_relayed_action desanitizes before validate.
	var src = FileAccess.get_file_as_string("res://autoloads/NetworkManager.gd")
	_check("_handle_relayed_action desanitizes before validation",
		src.find("action = _desanitize_from_json(action)") != -1)
	_check("relay validation uses defensive .get(\"valid\")",
		src.find("if not validation.valid:") == -1)
	_check("WebLobby reloads terrain on host start",
		FileAccess.get_file_as_string("res://scripts/WebLobby.gd").find("Reloaded terrain layout") != -1)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
