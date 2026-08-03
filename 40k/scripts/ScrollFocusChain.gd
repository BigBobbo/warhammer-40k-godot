class_name ScrollFocusChain
extends RefCounted

# ScrollFocusChain — make a ScrollContainer walkable with the D-pad.
#
# THE BUG THIS EXISTS FOR (Steam Deck, formations declaration):
# Godot's directional focus navigation (ui_up / ui_down, which the D-pad drives)
# is GEOMETRIC. It looks for the focusable control whose rect is nearest in the
# pressed direction — and a ScrollContainer does NOT move or hide the children
# that are scrolled out of view, it merely CLIPS them. They keep their real
# global positions, which run off past the bottom of the screen.
#
# So in a tall form (e.g. FormationsDeclarationDialog) the layout is:
#
#     y=718   [x] Gretchin Alpha        <- last row still inside the clip rect
#     y=762   [x] Gretchin Beta         <- half clipped
#     y=860   ( Skip ) ( Confirm )      <- the button bar, BELOW the scroll box
#     y=897   [x] Deffkilla Wartrike    <- first STRATEGIC RESERVES row, clipped
#     …
#     y=1677  [x] Gretchin Beta         <- 400px below the bottom of the screen
#
# From the Gretchin Beta row at y=762 the nearest thing "down" is the Skip
# button at y=860 (98px away), not the next checkbox at y=897 (135px away). The
# D-pad therefore leaps out of the panel and every reserves row below the fold
# is unreachable by controller — exactly the reported symptom. Worse, the
# ScrollContainer never scrolls, because focus moving to a clipped child does
# nothing unless `follow_focus` is on (it is off by default).
#
# THE FIX: stop relying on geometry inside a scrolled panel. `wire()` walks the
# scrolled content in TREE order and writes an EXPLICIT focus_neighbor chain —
# top/bottom between consecutive rows, and only the LAST row hands off to the
# trailing button bar (with the bar's `up` pointing back at it). Left/right on a
# single-column list are pinned to the control itself so a stray sideways press
# can't teleport out of the panel either. `follow_focus` is switched on so the
# panel scrolls the newly focused row into view.
#
# Explicit neighbours are position-independent, so they stay correct as the
# panel scrolls. Godot skips a link target that is hidden or FOCUS_NONE and
# follows that target's own neighbour instead, so rows that disable themselves
# don't break the walk.
#
# Usage (call again after rebuilding the contents — the chain is stored on the
# nodes, so freed rows must be re-wired):
#
#     ScrollFocusChain.wire(scroll_container, [skip_button, confirm_button])


# Wire `scroll`'s focusable content into a single vertical chain that ends in
# `trailing` (a left-to-right button row drawn below the panel; may be empty).
# Returns the number of content rows that were chained.
static func wire(scroll: ScrollContainer, trailing: Array = []) -> int:
	if scroll == null or not is_instance_valid(scroll):
		return 0

	# Focus moving to a clipped child must drag the viewport with it, otherwise
	# the player is "focused" on a row they cannot see.
	scroll.follow_focus = true

	var rows: Array = collect_focusables(scroll)
	var bar: Array = []
	for t in trailing:
		if t is Control and is_instance_valid(t) and t.focus_mode == Control.FOCUS_ALL:
			bar.append(t)

	for i in range(rows.size()):
		var row: Control = rows[i]
		var up: Control = rows[i - 1] if i > 0 else null
		var down: Control = null
		if i < rows.size() - 1:
			down = rows[i + 1]
		elif not bar.is_empty():
			# Only the LAST row is allowed to leave the panel.
			down = bar[0]
		_link(row, SIDE_TOP, up)
		_link(row, SIDE_BOTTOM, down)
		# Single-column list: ◀ ▶ have nothing to reach, and geometric search
		# would answer them with whatever happens to sit off to the side
		# (usually a control outside the panel). Pin them to the row itself so
		# the press is a visible no-op instead of an escape hatch.
		_link(row, SIDE_LEFT, row)
		_link(row, SIDE_RIGHT, row)
		# Tab / focus_next follows the same order.
		row.focus_next = down.get_path() if down != null else NodePath()
		row.focus_previous = up.get_path() if up != null else NodePath()

	var last_row: Control = rows[rows.size() - 1] if not rows.is_empty() else null
	for i in range(bar.size()):
		var b: Control = bar[i]
		var prev: Control = bar[i - 1] if i > 0 else null
		var next: Control = bar[i + 1] if i < bar.size() - 1 else null
		# ▲ from anywhere on the bar re-enters the panel at its last row.
		_link(b, SIDE_TOP, last_row)
		# ▼ off the end of the bar stays put — the bar IS the end of the form,
		# and once the panel has scrolled, geometry would otherwise drop focus
		# back into an arbitrary clipped row below it.
		_link(b, SIDE_BOTTOM, b)
		_link(b, SIDE_LEFT, prev if prev != null else b)
		_link(b, SIDE_RIGHT, next if next != null else b)
		b.focus_next = next.get_path() if next != null else NodePath()
		b.focus_previous = prev.get_path() if prev != null else (last_row.get_path() if last_row != null else NodePath())

	return rows.size()


# Depth-first, in tree order: the order the rows are drawn top-to-bottom in a
# VBoxContainer, which is the order the D-pad should walk them.
static func collect_focusables(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	return out


static func _collect(n: Node, out: Array) -> void:
	for child in n.get_children():
		# Never descend into a nested Window (an OptionButton's PopupMenu, a
		# child dialog): its controls live in another viewport and are not part
		# of this panel's walk.
		if child is Window:
			continue
		if child is Control:
			var c: Control = child
			if not c.visible:
				continue
			if c.focus_mode == Control.FOCUS_ALL:
				out.append(c)
		_collect(child, out)


static func _link(from: Control, side: int, to: Control) -> void:
	if from == null or not is_instance_valid(from):
		return
	if to == null or not is_instance_valid(to):
		from.set_focus_neighbor(side, NodePath())
		return
	from.set_focus_neighbor(side, to.get_path())
