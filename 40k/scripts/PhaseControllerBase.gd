class_name PhaseControllerBase
extends Node2D

## Shared base for the per-phase UI controllers (ISS-005):
## DeploymentController, MovementController, ShootingController,
## ChargeController, FightController.
##
## Owns the common UI-reference lookup that every controller used to
## copy-paste. Subclasses override the hooks:
##   _on_ui_references_ready() — extra setup once refs are resolved
##   _setup_bottom_hud()       — phase-specific HUD_Bottom contents
##   _setup_right_panel()      — phase-specific HUD_Right contents
##
## Further consolidation (signal registry, per-phase UI container, input
## gating) lands with ISS-013 / ISS-018 / ISS-008 on top of this base.

var board_view: Node2D
var hud_bottom: Control
var hud_right: Control


func _setup_ui_references() -> void:
	# Get references to UI nodes
	board_view = SceneRefs.board_view()
	hud_bottom = SceneRefs.hud_bottom()
	hud_right = SceneRefs.hud_right()

	_on_ui_references_ready()

	if hud_bottom:
		_setup_bottom_hud()
	if hud_right:
		_setup_right_panel()


## Override for controller-specific setup that must run after the UI
## references are resolved but before the HUD sections are built.
func _on_ui_references_ready() -> void:
	pass


## Override to build the phase-specific HUD_Bottom contents.
func _setup_bottom_hud() -> void:
	pass


## Override to build the phase-specific HUD_Right contents.
func _setup_right_panel() -> void:
	pass


func get_board_root() -> Node:
	return SceneRefs.board_root()


## Dice log relocation: the Shooting/Charge/Fight dice logs now live in the
## left GameLogPanel as a switchable "Dice Log" tab, so the long, growing log
## no longer crowds the phase controls in the right panel. Controllers call
## this to resolve the shared RichTextLabel instead of building their own; every
## existing `dice_log_display.append_text/clear/add_image` call then targets the
## shared tab unchanged. Falls back to a local right-panel label (the historical
## behavior) when the panel isn't present — e.g. trimmed / headless setups — so
## `dice_log_display` is always a valid, writable RichTextLabel.
##
## The fallback is deliberately NAMED "DiceLogFallback" so a controller that had
## to fall back can be spotted afterwards: Main._setup_game_log_panel() calls
## rebind_shared_dice_log() (see below) on every live controller once the real
## panel exists. Main._ready() builds the panel BEFORE the phase controllers, so
## in a normal battle start nothing falls back in the first place.
func resolve_shared_dice_log(fallback_parent: Node = null) -> RichTextLabel:
	var glp = SceneRefs.game_log_panel() if SceneRefs else null
	if glp != null and glp.has_method("get_dice_log_display"):
		var shared = glp.get_dice_log_display()
		if shared != null:
			return shared
	var rt := RichTextLabel.new()
	rt.name = "DiceLogFallback"
	rt.custom_minimum_size = Vector2(230, 180)
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if fallback_parent != null:
		fallback_parent.add_child(rt)
	print("PhaseControllerBase: no GameLogPanel yet — %s writing dice output to a local DiceLogFallback until rebind_shared_dice_log()" % name)
	return rt


## Re-point `dice_log_display` at the shared GameLogPanel tab if this controller
## had to fall back earlier.
##
## Main._setup_game_log_panel() used to run AFTER setup_phase_controllers(), so a
## controller built during startup resolved its dice log while the panel did not
## exist yet. That only bit when the battle STARTED in that controller's phase —
## normal play begins in deployment, so the shooting/charge/fight controllers are
## created on a later phase change when the panel is already up. Booting straight
## into a phase did hit it: the tutorial lessons T4/T5/T6 boot into
## shooting/charge/fight from a fixture, and every roll of the lesson went into a
## stray DiceLogFallback parented in the right-hand panel while the left panel's
## "Dice Log" tab stayed empty for the whole lesson. Loading a save taken
## mid-shooting/charge/fight has the same start condition.
##
## _ready() now builds the panel first, so this is a safety net for the paths
## that still create it late (replay mode). A no-op for controllers already
## sharing the label. Prefer fixing the order over relying on this: the freed
## fallback reflows an already-laid-out right panel, which was measured to leave
## ChargePanel/DistanceTracking on top of the "Confirm Charge Moves" button,
## eating real mouse clicks. Nothing can have been written to the fallback at
## startup (no dice rolled yet), so re-pointing loses no output.
func rebind_shared_dice_log() -> void:
	if not ("dice_log_display" in self):
		return
	var current = get("dice_log_display")
	if current != null and is_instance_valid(current) and str(current.name) != "DiceLogFallback":
		return  # already the shared label (or a purpose-built one)
	var glp = SceneRefs.game_log_panel() if SceneRefs else null
	if glp == null or not glp.has_method("get_dice_log_display"):
		return
	var shared = glp.get_dice_log_display()
	if shared == null:
		return
	set("dice_log_display", shared)
	if current != null and is_instance_valid(current):
		if current.get_parent() != null:
			current.get_parent().remove_child(current)
		current.queue_free()
	print("PhaseControllerBase: %s dice log rebound to the shared GameLogPanel tab" % name)


# ── Over-range drag clamp (shared by Movement / Charge / Fight) ─────
# Dragging a model further than it can go used to follow the cursor into an
# invalid preview that was rejected on drop, so squeezing out the last inch
# meant landing the cursor on the range circle by hand. Clamped, the drag stops
# at the farthest point the model can actually still reach: the player drags in
# roughly the right direction and takes the maximum legal distance (the XCOM 2 /
# Into the Breach feel).
#
# Every phase that drags a model against a distance budget shares this: the
# movement phase's Normal/Advance/Fall Back, the charge move, and the fight
# phase's pile-in / consolidate. The per-phase cost function differs (terrain is
# charged differently, and pile-in ignores it entirely), so the search is
# parameterised by a `cost_fn` the caller supplies.

## Is the over-range drag clamp in force right now?
##
## The pad carry is ALWAYS clamped: an over-range pad drop that snaps back and
## strands the virtual cursor is unusable, so that is not a preference (P0 Steam
## Deck smoothness). On mouse & keyboard it follows Settings › Controls › "Stop
## model drags at their maximum move range", ON by default. Turning it off
## restores the historical free drag with the red over-range preview.
##
## Read live on every motion event so a mid-game settings change takes effect on
## the very next drag with no reload. Autoloads are fetched defensively because
## bare headless harnesses instantiate controllers without them.
func drag_clamp_active() -> bool:
	var idm = get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.has_method("is_pad_active") and idm.is_pad_active():
		return true
	var settings = get_node_or_null("/root/SettingsService")
	if settings == null:
		return false
	return bool(settings.get("drag_clamp_to_max_range"))


# How finely the ray from the pickup point to the cursor is searched for the
# farthest affordable stop — a coarse descending scan to bracket the boundary,
# then bisections to sharpen it.
#
# A plain "budget minus endpoint penalty" formula is NOT enough wherever terrain
# is costed, because the penalty is a step function of where you stop: dragging
# a Telemon at a tall ruin costs +10" AT the ruin but 0" one inch short of it,
# and the naive formula subtracts the ruin's cost from the budget everywhere
# along the ray and pins the model at 0".
#
# 10 + 5 caps the worst case at 15 cost queries per motion event while still
# landing within ~budget/320 (≈0.025" on an 8" move, i.e. the phases' movement
# epsilon) of the true boundary — and the refinement always converges from the
# affordable side, so the point returned is legal regardless of precision.
# Measured in the movement phase: 2.1 ms per over-range motion event across
# terrain, vs 0.12 ms for the single-query in-range case.
const DRAG_CLAMP_SCAN_SAMPLES: int = 10
const DRAG_CLAMP_REFINE_STEPS: int = 5
const DRAG_CLAMP_EPSILON: float = 0.02


## Clamp `to_pos` back along the ray from `from_pos` to the farthest point whose
## cost fits `budget_inches`; returns `to_pos` unchanged when it already fits.
##
## `cost_fn` is `func(dest: Vector2) -> float` returning the TOTAL inches a stop
## at `dest` spends — raw distance plus whatever the phase charges on top
## (terrain, climbs). It must be the same accounting the phase validates the
## drop with, or the clamp parks the model exactly on a boundary the phase then
## rejects.
##
## Geometry only: overlap, board edge and any "must end closer to a target"
## rules stay with the caller, because shortening a move must not silently force
## an illegal placement.
func clamp_drag_to_budget(from_pos: Vector2, to_pos: Vector2, budget_inches: float, cost_fn: Callable) -> Vector2:
	var seg: Vector2 = to_pos - from_pos
	var seg_len_px: float = seg.length()
	if seg_len_px <= 0.0:
		return to_pos
	budget_inches = max(0.0, budget_inches)
	var cost_at_cursor: float = float(cost_fn.call(to_pos))
	if cost_at_cursor <= budget_inches + DRAG_CLAMP_EPSILON:
		return to_pos

	var dir: Vector2 = seg / seg_len_px
	var point_at := func(inches: float) -> Vector2:
		return from_pos + dir * Measurement.inches_to_px(inches)

	# Fast path — the cost is pure distance along this ray, so the answer is
	# closed-form. True whenever nothing is charged on top at the cursor: a
	# shorter sub-segment can only cross a subset of what the full segment
	# crosses, and any point on it lies on the full segment, so a zero surcharge
	# at the cursor means zero surcharge the whole way in. This is the
	# open-board case (the overwhelming majority of drags, and ALWAYS the case
	# for pile-in / consolidate, which charge no terrain) and keeps the
	# per-motion-event cost at one query instead of 15.
	var requested_inches: float = Measurement.px_to_inches(seg_len_px)
	if cost_at_cursor <= requested_inches + DRAG_CLAMP_EPSILON:
		return point_at.call(budget_inches)

	var affordable := func(inches: float) -> bool:
		return float(cost_fn.call(point_at.call(inches))) <= budget_inches + DRAG_CLAMP_EPSILON

	# Surcharged ground in the way: the cost is a step function of where you
	# stop, so walk in from the cursor and take the FIRST affordable sample — the
	# farthest one, which is what "drag roughly the right way and take the
	# maximum" means. Never search past `budget_inches`: beyond that the raw
	# distance alone already busts the cap, so those samples cannot pay off, and
	# skipping them spends the whole sample budget on the stretch that can.
	var step: float = min(requested_inches, budget_inches) / float(DRAG_CLAMP_SCAN_SAMPLES)
	var lo: float = 0.0        # affordable (standing still always is)
	var hi: float = step       # unaffordable — tightened if the scan finds better
	for i in range(DRAG_CLAMP_SCAN_SAMPLES, 0, -1):
		var d: float = step * float(i)
		if affordable.call(d):
			lo = d
			hi = d + step
			break
	for _i in range(DRAG_CLAMP_REFINE_STEPS):
		var mid: float = (lo + hi) * 0.5
		if affordable.call(mid):
			lo = mid
		else:
			hi = mid
	return point_at.call(lo)


# ── ISS-013: phase signal registry ──────────────────────────────────
# Subclasses declare the phase signals they consume; attach/detach connect
# and disconnect them symmetrically. This replaces both the per-signal
# reconnect-guard blocks in set_phase and the manual per-signal disconnect
# blocks in Main's phase teardown.

var _attached_phase = null


## Override: {signal_name (String): handler (Callable)} for every phase
## signal this controller consumes. Signals missing on the phase instance
## are skipped (some are phase-variant specific).
func phase_signal_map() -> Dictionary:
	return {}


## Connect this controller's declared signals to the phase. Re-attaching is
## safe: any previous attachment is detached first, and existing duplicate
## connections are cleared before connecting.
func attach_phase(phase) -> void:
	detach_phase()
	_attached_phase = phase
	if phase == null:
		return
	var map := phase_signal_map()
	var connected := 0
	for sig in map:
		if not phase.has_signal(sig):
			continue
		if phase.is_connected(sig, map[sig]):
			phase.disconnect(sig, map[sig])
		phase.connect(sig, map[sig])
		connected += 1
	print("[%s] attach_phase: connected %d/%d phase signals (instance %d)" % [name, connected, map.size(), get_instance_id()])


## Disconnect every declared signal from the previously attached phase.
## Safe to call repeatedly and during teardown.
func detach_phase() -> void:
	if _attached_phase != null and is_instance_valid(_attached_phase):
		var map := phase_signal_map()
		var disconnected := 0
		for sig in map:
			if _attached_phase.has_signal(sig) and _attached_phase.is_connected(sig, map[sig]):
				_attached_phase.disconnect(sig, map[sig])
				disconnected += 1
		if disconnected > 0:
			print("[%s] detach_phase: disconnected %d phase signals (instance %d)" % [name, disconnected, get_instance_id()])
	_attached_phase = null
