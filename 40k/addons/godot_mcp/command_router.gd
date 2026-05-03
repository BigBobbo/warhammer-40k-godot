extends RefCounted

# Routes a command name + params dictionary to the appropriate handler.
# We use explicit per-handler method lists rather than introspection because
# `Object.get_method_list()` returns inherited internals (`_init`, `_get`,
# `_set`, etc.) that we don't want exposed.

const TestingHandlers := preload("res://addons/godot_mcp/handlers/testing_handlers.gd")
const CoreHandlers := preload("res://addons/godot_mcp/handlers/core_handlers.gd")
const Wh40kHandlers := preload("res://addons/godot_mcp/handlers/wh40k_handlers.gd")

var host: Node = null

var _testing: RefCounted = null
var _core: RefCounted = null
var _wh40k: RefCounted = null

# command -> [handler_object, method_name]
var _routes: Dictionary = {}


func _init() -> void:
	_testing = TestingHandlers.new()
	_core = CoreHandlers.new()
	_wh40k = Wh40kHandlers.new()
	_register_routes()


func _register_routes() -> void:
	# Built-in / informational
	_routes["ping"] = [self, "_ping"]
	_routes["list_tools"] = [self, "_list_tools"]

	var core_methods := [
		"get_project_info", "get_project_setting", "list_files",
		"get_current_scene", "get_node_info", "get_node_property",
		"set_node_property", "call_node_method",
		"read_script", "write_script",
	]
	for m in core_methods:
		_routes[m] = [_core, m]

	var testing_methods := [
		"capture_screenshot",
		"simulate_click", "simulate_mouse_move", "simulate_drag",
		"simulate_key_press", "simulate_action",
		"get_scene_state", "execute_script",
		"wait_frames", "wait_seconds",
		"get_log_path",
	]
	for m in testing_methods:
		_routes[m] = [_testing, m]

	var wh40k_methods := [
		"get_board_state", "get_unit_details", "list_units",
		"get_current_phase", "advance_phase", "transition_to_phase",
		"select_unit", "dispatch_action", "move_unit_to",
	]
	for m in wh40k_methods:
		_routes[m] = [_wh40k, m]


func _propagate_host() -> void:
	# `host` may be assigned after _init(); always forward the current value
	# to handlers so their tree access is up-to-date.
	if _testing:
		_testing.host = host
	if _core:
		_core.host = host
	if _wh40k:
		_wh40k.host = host


func dispatch(command: String, params: Dictionary):
	_propagate_host()
	if not _routes.has(command):
		return {"status": "error", "message": "Unknown command: %s" % command}
	var route = _routes[command]
	var handler = route[0]
	var method: String = route[1]
	# `await` on a synchronous return value is a no-op in Godot 4, so this
	# safely supports both sync and `await`-using handlers.
	var result = await handler.callv(method, [params])
	return result


# --- Built-in commands --------------------------------------------------------

func _ping(_params: Dictionary) -> Dictionary:
	return {
		"status": "ok",
		"pong": Time.get_ticks_msec(),
		"engine_version": Engine.get_version_info(),
	}


func _list_tools(_params: Dictionary) -> Dictionary:
	var names := _routes.keys()
	names.sort()
	return {"status": "ok", "tools": names}
