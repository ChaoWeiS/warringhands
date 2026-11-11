extends Control
## Splits the screen into panes, each a separate camera on the same world.
##
## Gestures:
##   - Grab a grip tab on a pane's side and swipe across the pane: cut it.
##     The cut follows your finger; release past the halfway-ish point.
##   - Drag a divider: resize. Drag it until a pane gets too small: merge.
##   - Two fingers inside a pane: pan (move together) and pinch zoom.
##   - One finger inside a pane: tap (emits `tapped`) or draw a loop to
##     lasso (emits `lassoed`). A second finger turns either into a camera
##     gesture. What a tap or lasso means is decided by game_controller.gd.
## Each pane tracks its own fingers, so two hands can work two panes at once.
##
## On a computer: left mouse acts as one finger (cut / resize), mouse wheel
## zooms and right-drag pans the pane under the cursor.
##
## Panes are kept in a tree: a pane is either a leaf (shows a camera) or a
## split holding two children side by side or stacked.

const CameraRig := preload("res://scripts/camera_rig.gd")

## One finger tapped a pane. `point` is relative to that pane's top-left.
signal tapped(camera: Camera3D, point: Vector2)
## One finger drew a loop in a pane. Points are relative to that pane.
signal lassoed(camera: Camera3D, polygon: PackedVector2Array)
## Placing a building (see `placing`): the finger (or mouse) is over this
## pane point; and the finger was lifted here (build it).
signal pointer_moved(camera: Camera3D, point: Vector2)
signal placed(camera: Camera3D, point: Vector2)
## Two fingers tapped together (down and up quickly, without moving).
signal two_finger_tapped(camera: Camera3D)
## Mouse: right button clicked (not dragged: that pans).
signal right_clicked(camera: Camera3D)

## While true (a building is picked), one finger drags a preview instead of
## drawing a loop, and lifting it emits `placed` (not over a button).
var placing := false

@export var world_path: NodePath
## Smallest a pane can be (width or height). Smaller panes snap shut.
@export var min_pane_size: float = 240.0
@export var max_panes: int = 8
@export var divider_width: float = 12.0
## How far either side of a divider still counts as grabbing it.
@export var divider_grab: float = 40.0
## Grip knob drawn in the middle of each divider.
@export var knob_length: float = 110.0
@export var knob_thickness: float = 24.0
## Cut tab look and size.
@export var tab_length: float = 72.0
@export var tab_thickness: float = 12.0
## Tabs sit this far in from the pane edge, clear of the divider grab zone.
@export var tab_inset: float = 58.0
## Touch area of a tab: x = along the pane side, y = into the pane.
## Starts just past the divider grab zone.
@export var tab_touch_size: Vector2 = Vector2(120, 72)
## How far across the pane (0-1) a swipe must travel to cut.
@export var cut_commit: float = 0.45
## A one-finger touch that moves less than this is a tap, more is a lasso.
@export var tap_slop: float = 16.0

const SNAPS := [1.0 / 3.0, 0.5, 2.0 / 3.0]
const SNAP_RANGE := 0.03
## A two-finger tap: both fingers up within this long (ms) of the first going
## down, neither moving more than tap_slop.
const TWO_TAP_MS := 350

const DIVIDER_COLOR := Color("#5f5873")
const DIVIDER_ACTIVE := Color("#fff3b0")
const KNOB_DOTS := Color(1, 1, 1, 0.85)
const TAB_COLOR := Color(1, 1, 1, 0.75)
const CUT_PENDING := Color("#fff3b0")
const CUT_READY := Color.WHITE
const CUT_BLOCKED := Color("#ff8a8a")
const CLOSING_TINT := Color(1.0, 0.45, 0.45, 0.35)
const LASSO_LINE := Color(1, 1, 1, 0.95)
const LASSO_FILL := Color(1, 1, 1, 0.15)

enum Side { LEFT, RIGHT, TOP, BOTTOM }
enum Mode { PANE, CUT, DIVIDER }


class PaneNode:
	var parent = null  # PaneNode or null
	var rect := Rect2()
	# Leaf
	var container: SubViewportContainer = null
	var camera: Camera3D = null
	var pinch_center := Vector2.ZERO
	var pinch_distance := 0.0
	# A possible two-finger tap: when the first finger went down, how many
	# fingers joined, and whether any of them moved or stayed too long.
	var tap2_start := 0
	var tap2_fingers := 0
	var tap2_ok := false
	# Last on-screen rectangle the camera was matched to (see _layout).
	var anchor_rect := Rect2()
	# Split
	var vertical := true  # true: divider runs top-bottom (panes side by side)
	var ratio := 0.5
	var a = null
	var b = null

	func is_leaf() -> bool:
		return container != null


var _world: SubViewport
var _root: PaneNode
var _overlay: Control
var _fingers: Dictionary = {}  # finger index -> Dictionary
var _mouse_pan_leaf: PaneNode = null
var _right_down_at := Vector2.ZERO
var _right_moved := 0.0
var _blockers: Array = []  # on-screen controls (buttons) panes must ignore


func _ready() -> void:
	_world = get_node(world_path)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_root = _make_leaf(null)
	resized.connect(_relayout)
	_relayout()
	_root.camera.fit_whole_map()


func pane_count() -> int:
	return _leaves().size()


## Touches on this control (e.g. the selection bar) won't reach the panes.
func register_blocker(control: Control) -> void:
	_blockers.append(control)


func _blocked(p: Vector2) -> bool:
	# A pop-up window (Settings, Surrender?) is open: the map waits.
	for modal in get_tree().get_nodes_in_group("modal"):
		if modal is CanvasItem and modal.is_visible_in_tree():
			return true
	for control in _blockers:
		if is_instance_valid(control) and control.is_visible_in_tree() \
				and control.get_global_rect().has_point(p):
			return true
	return false


# --- Input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _mouse_pan_leaf != null and _is_alive(_mouse_pan_leaf) \
				and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_mouse_pan_leaf.camera.pan_by_screen(event.relative)
			_right_moved += event.relative.length()
		elif placing and event.button_mask == 0 and not _blocked(event.position):
			# Mouse: the preview follows the pointer.
			var hover := _leaf_at(event.position)
			if hover:
				pointer_moved.emit(hover.camera, event.position - hover.rect.position)
	elif event is InputEventMagnifyGesture:
		var leaf := _leaf_at(event.position)
		if leaf:
			leaf.camera.zoom_at(event.factor, event.position - leaf.rect.position)
	elif event is InputEventPanGesture:
		var leaf := _leaf_at(event.position)
		if leaf:
			leaf.camera.pan_by_screen(-event.delta * 20.0)


func _on_touch(event: InputEventScreenTouch) -> void:
	var p: Vector2 = event.position
	if event.pressed:
		if _blocked(p):
			return
		var finger := {"start": p, "pos": p}
		# Dividers win first (wide grab zone), then cut tabs, then the pane.
		var split: PaneNode = _divider_at(p)
		var tab: Array = [] if split != null else _tab_at(p)
		if split != null:
			finger.mode = Mode.DIVIDER
			finger.split = split
		elif not tab.is_empty() and not _has_other_finger_in(tab[0]):
			finger.mode = Mode.CUT
			finger.leaf = tab[0]
			finger.side = tab[1]
		else:
			var leaf := _leaf_at(p)
			if leaf == null:
				return
			finger.mode = Mode.PANE
			finger.leaf = leaf
			finger.solo = true  # still a possible tap / lasso
			finger.lasso = false
			finger.path = PackedVector2Array([p])
			# A second finger in a pane means a camera gesture: cancel any tap,
			# lasso or accidental cut the first finger had started.
			for other in _fingers.values():
				if other.has("leaf") and other.leaf == leaf:
					if other.mode == Mode.CUT:
						other.mode = Mode.PANE
					other.solo = false
					other.lasso = false
					finger.solo = false
		_fingers[event.index] = finger
		if finger.mode == Mode.PANE:
			_note_tap2_down(finger.leaf)
			_reset_pinch(finger.leaf)
			if placing and finger.solo:
				pointer_moved.emit(finger.leaf.camera, p - finger.leaf.rect.position)
		else:
			get_viewport().set_input_as_handled()
	else:
		if not _fingers.has(event.index):
			return
		var finger: Dictionary = _fingers[event.index]
		_fingers.erase(event.index)
		match finger.mode:
			Mode.CUT:
				_finish_cut(finger)
			Mode.DIVIDER:
				_finish_divider(finger.split)
			Mode.PANE:
				_reset_pinch(finger.leaf)
				_finish_solo(finger)
				_note_tap2_up(finger)
	_overlay.queue_redraw()


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _fingers.has(event.index):
		return
	var finger: Dictionary = _fingers[event.index]
	finger.pos = event.position
	match finger.mode:
		Mode.DIVIDER:
			_drag_divider(finger)
			get_viewport().set_input_as_handled()
		Mode.CUT:
			get_viewport().set_input_as_handled()
		Mode.PANE:
			if finger.pos.distance_to(finger.start) > tap_slop:
				finger.leaf.tap2_ok = false
			var points: Array = _pane_finger_points(finger.leaf)
			if points.size() == 2:
				_pinch(finger.leaf, points)
				get_viewport().set_input_as_handled()
			elif finger.get("solo", false):
				if placing:
					pointer_moved.emit(finger.leaf.camera, finger.pos - finger.leaf.rect.position)
				else:
					_track_lasso(finger)
	_overlay.queue_redraw()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	var leaf := _leaf_at(event.position)
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if leaf and event.pressed:
				var factor: float = 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
				leaf.camera.zoom_at(factor, event.position - leaf.rect.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_moved = 0.0
				_right_down_at = event.position
			elif leaf != null and _mouse_pan_leaf == leaf and _right_moved <= tap_slop \
					and not _blocked(event.position) and not placing:
				right_clicked.emit(leaf.camera)  # a click, not a drag
			_mouse_pan_leaf = leaf if event.pressed else null


# --- One-finger tap and lasso --------------------------------------------------

func _track_lasso(finger: Dictionary) -> void:
	var p: Vector2 = finger.pos
	if not finger.lasso and p.distance_to(finger.start) > tap_slop:
		finger.lasso = true
	if finger.lasso:
		var path: PackedVector2Array = finger.path
		if path.is_empty() or path[path.size() - 1].distance_to(p) >= 6.0:
			path.append(p)
			finger.path = path


func _finish_solo(finger: Dictionary) -> void:
	if not finger.get("solo", false) or not _is_alive(finger.leaf):
		return
	var leaf: PaneNode = finger.leaf
	if placing:
		# Lifted: build here (unless the finger ended up over a button).
		if not _blocked(finger.pos) and leaf.rect.has_point(finger.pos):
			placed.emit(leaf.camera, finger.pos - leaf.rect.position)
		return
	if finger.lasso:
		var path: PackedVector2Array = finger.path
		if path.size() >= 3:
			var local := PackedVector2Array()
			for point in path:
				local.append(point - leaf.rect.position)
			lassoed.emit(leaf.camera, local)
	else:
		tapped.emit(leaf.camera, finger.pos - leaf.rect.position)


# --- Two-finger tap ------------------------------------------------------------

func _note_tap2_down(leaf: PaneNode) -> void:
	var count: int = _pane_finger_points(leaf).size()
	if count == 1:
		leaf.tap2_start = Time.get_ticks_msec()
		leaf.tap2_fingers = 1
		leaf.tap2_ok = true
	else:
		leaf.tap2_fingers = maxi(leaf.tap2_fingers, count)


func _note_tap2_up(finger: Dictionary) -> void:
	var leaf: PaneNode = finger.leaf
	if not _is_alive(leaf) or not _pane_finger_points(leaf).is_empty():
		return  # wait for the last finger
	var quick: bool = Time.get_ticks_msec() - leaf.tap2_start <= TWO_TAP_MS
	if leaf.tap2_ok and quick and leaf.tap2_fingers == 2 and not placing:
		two_finger_tapped.emit(leaf.camera)
	leaf.tap2_ok = false


# --- Camera gestures ---------------------------------------------------------

## True if a finger is already down in this pane (camera or cut).
func _has_other_finger_in(leaf: PaneNode) -> bool:
	for finger in _fingers.values():
		if finger.has("leaf") and finger.leaf == leaf:
			return true
	return false


func _pane_finger_points(leaf: PaneNode) -> Array:
	var points: Array = []
	for finger in _fingers.values():
		if finger.mode == Mode.PANE and finger.leaf == leaf:
			points.append(finger.pos)
	return points


func _reset_pinch(leaf: PaneNode) -> void:
	var points: Array = _pane_finger_points(leaf)
	leaf.pinch_distance = 0.0
	if points.size() == 2:
		leaf.pinch_center = (points[0] + points[1]) * 0.5
		leaf.pinch_distance = points[0].distance_to(points[1])


func _pinch(leaf: PaneNode, points: Array) -> void:
	var center: Vector2 = (points[0] + points[1]) * 0.5
	var dist: float = points[0].distance_to(points[1])
	if leaf.pinch_distance > 0.0 and dist > 0.0:
		leaf.camera.pan_by_screen(center - leaf.pinch_center)
		leaf.camera.zoom_at(dist / leaf.pinch_distance, center - leaf.rect.position)
	leaf.pinch_center = center
	leaf.pinch_distance = dist


# --- Cutting -----------------------------------------------------------------

## Where a cut would go right now, and whether it would happen on release.
func _cut_info(finger: Dictionary) -> Dictionary:
	var leaf: PaneNode = finger.leaf
	var r: Rect2 = leaf.rect
	var p: Vector2 = finger.pos
	var start: Vector2 = finger.start
	var side: int = finger.side
	# Swiping from left/right draws a horizontal line (panes stacked);
	# from top/bottom draws a vertical line (panes side by side).
	var vertical: bool = side == Side.TOP or side == Side.BOTTOM
	var travel: float
	match side:
		Side.LEFT: travel = (p.x - start.x) / r.size.x
		Side.RIGHT: travel = (start.x - p.x) / r.size.x
		Side.TOP: travel = (p.y - start.y) / r.size.y
		_: travel = (start.y - p.y) / r.size.y
	var extent: float = r.size.x if vertical else r.size.y
	var ratio: float = ((p.x - r.position.x) if vertical else (p.y - r.position.y)) / extent
	var min_ratio: float = (min_pane_size + divider_width * 0.5) / extent
	var possible: bool = extent >= 2.0 * min_pane_size + divider_width \
			and pane_count() < max_panes
	ratio = clampf(_snap(ratio), min_ratio, 1.0 - min_ratio) if possible else 0.5
	return {
		"leaf": leaf, "vertical": vertical, "ratio": ratio,
		"progress": clampf(travel, 0.0, 1.0), "possible": possible,
	}


func _finish_cut(finger: Dictionary) -> void:
	if not _is_alive(finger.leaf):
		return
	var info := _cut_info(finger)
	if info.possible and info.progress >= cut_commit:
		_split_leaf(info.leaf, info.vertical, info.ratio)


func _split_leaf(leaf: PaneNode, vertical: bool, ratio: float) -> void:
	var split := PaneNode.new()
	split.vertical = vertical
	split.ratio = ratio
	# The new pane starts as a copy of the old one; _layout then re-aims both
	# so each keeps showing exactly the part of the map that was under it.
	var fresh := _make_leaf(leaf)
	fresh.anchor_rect = leaf.anchor_rect
	_replace(leaf, split)
	split.a = leaf
	split.b = fresh
	leaf.parent = split
	fresh.parent = split
	_relayout()


# --- Dividers: resize and merge ------------------------------------------------

func _drag_divider(finger: Dictionary) -> void:
	var split: PaneNode = finger.split
	if not _is_alive(split):
		return
	var r: Rect2 = split.rect
	var p: Vector2 = finger.pos
	var ratio: float
	if split.vertical:
		ratio = (p.x - r.position.x) / r.size.x
	else:
		ratio = (p.y - r.position.y) / r.size.y
	split.ratio = _snap(clampf(ratio, 0.0, 1.0))
	_relayout()


## Which child of `split` would close if released now (too small), or null.
func _closing_child(split: PaneNode) -> PaneNode:
	var extent: float = split.rect.size.x if split.vertical else split.rect.size.y
	var size_a: float = extent * split.ratio - divider_width * 0.5
	var size_b: float = extent * (1.0 - split.ratio) - divider_width * 0.5
	if size_a < min_pane_size and size_a <= size_b:
		return split.a
	if size_b < min_pane_size:
		return split.b
	return null


func _finish_divider(split: PaneNode) -> void:
	if not _is_alive(split):
		return
	var closing := _closing_child(split)
	if closing != null:
		_merge(split, split.b if closing == split.a else split.a)
	else:
		_relayout()


func _merge(split: PaneNode, keep: PaneNode) -> void:
	var gone: PaneNode = split.a if keep == split.b else split.b
	_replace(split, keep)
	_free_subtree(gone)
	# Forget fingers that were on panes that no longer exist.
	for index in _fingers.keys():
		var f: Dictionary = _fingers[index]
		if (f.has("leaf") and not _is_alive(f.leaf)) or (f.has("split") and not _is_alive(f.split)):
			_fingers.erase(index)
	_relayout()


# --- Tree helpers --------------------------------------------------------------

func _make_leaf(copy_from: PaneNode) -> PaneNode:
	var leaf := PaneNode.new()
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.world_3d = _world.world_3d  # every pane shows the same world
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	var camera := Camera3D.new()
	camera.set_script(CameraRig)
	viewport.add_child(camera)
	container.add_child(viewport)
	add_child(container)
	move_child(_overlay, -1)  # keep the overlay drawn on top
	leaf.container = container
	leaf.camera = camera
	if copy_from != null:
		camera.copy_view(copy_from.camera)
	return leaf


func _replace(old: PaneNode, new_node: PaneNode) -> void:
	var parent: PaneNode = old.parent
	new_node.parent = parent
	if parent == null:
		_root = new_node
	elif parent.a == old:
		parent.a = new_node
	else:
		parent.b = new_node


func _free_subtree(node: PaneNode) -> void:
	if node.is_leaf():
		node.container.queue_free()
		node.container = null
		node.camera = null
	else:
		_free_subtree(node.a)
		_free_subtree(node.b)


func _is_alive(node: PaneNode) -> bool:
	var n: PaneNode = node
	while n.parent != null:
		n = n.parent
	return n == _root and (not node.is_leaf() or node.container != null) \
			and (node.container == null or is_instance_valid(node.container))


func _leaves(node: PaneNode = null, out: Array = []) -> Array:
	node = _root if node == null else node
	if node.is_leaf():
		out.append(node)
	else:
		_leaves(node.a, out)
		_leaves(node.b, out)
	return out


func _splits(node: PaneNode = null, out: Array = []) -> Array:
	node = _root if node == null else node
	if not node.is_leaf():
		out.append(node)
		_splits(node.a, out)
		_splits(node.b, out)
	return out


func _relayout() -> void:
	if _root == null:
		return
	_layout(_root, Rect2(Vector2.ZERO, size))
	for leaf in _leaves():
		leaf.camera.call_deferred("refit")
	queue_redraw()
	_overlay.queue_redraw()


func _layout(node: PaneNode, r: Rect2) -> void:
	node.rect = r
	if node.is_leaf():
		node.container.position = r.position
		node.container.size = Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0))
		# Keep the map still on screen, at the same zoom.
		if r.size.x >= 1.0 and r.size.y >= 1.0:
			if node.anchor_rect.size.y >= 1.0:
				if node.anchor_rect != r:
					node.camera.reanchor(node.anchor_rect, r)
			else:
				node.camera.set_pane_height(r.size.y)
			node.anchor_rect = r
		return
	var half: float = divider_width * 0.5
	if node.vertical:
		var x: float = r.size.x * node.ratio
		_layout(node.a, Rect2(r.position, Vector2(maxf(x - half, 0.0), r.size.y)))
		_layout(node.b, Rect2(r.position + Vector2(x + half, 0), Vector2(maxf(r.size.x - x - half, 0.0), r.size.y)))
	else:
		var y: float = r.size.y * node.ratio
		_layout(node.a, Rect2(r.position, Vector2(r.size.x, maxf(y - half, 0.0))))
		_layout(node.b, Rect2(r.position + Vector2(0, y + half), Vector2(r.size.x, maxf(r.size.y - y - half, 0.0))))


func _snap(ratio: float) -> float:
	for s in SNAPS:
		if absf(ratio - s) < SNAP_RANGE:
			return s
	return ratio


# --- Hit testing ---------------------------------------------------------------

func _leaf_at(p: Vector2) -> PaneNode:
	for leaf in _leaves():
		if leaf.rect.has_point(p):
			return leaf
	return null


func _divider_line(split: PaneNode) -> Array:
	var r: Rect2 = split.rect
	if split.vertical:
		var x: float = r.position.x + r.size.x * split.ratio
		return [Vector2(x, r.position.y), Vector2(x, r.end.y)]
	var y: float = r.position.y + r.size.y * split.ratio
	return [Vector2(r.position.x, y), Vector2(r.end.x, y)]


func _divider_at(p: Vector2) -> PaneNode:
	var best: PaneNode = null
	var best_dist: float = divider_grab
	for split in _splits():
		var line: Array = _divider_line(split)
		var dist: float
		if split.vertical:
			if p.y < line[0].y or p.y > line[1].y:
				continue
			dist = absf(p.x - line[0].x)
		else:
			if p.x < line[0].x or p.x > line[1].x:
				continue
			dist = absf(p.y - line[0].y)
		if dist <= best_dist:
			best = split
			best_dist = dist
	return best


## Each tab as [side, draw rect, touch rect].
func _tabs(leaf: PaneNode) -> Array:
	var r: Rect2 = leaf.rect
	var c: Vector2 = r.get_center()
	var long := tab_length
	var thick := tab_thickness
	var along := tab_touch_size.x
	var into := tab_touch_size.y
	# Touch areas start just past the divider's grab zone, so grabbing a
	# divider can never start a cut by accident.
	var gap: float = divider_grab - divider_width * 0.5 + 2.0
	return [
		[Side.LEFT, Rect2(r.position.x + tab_inset, c.y - long / 2, thick, long),
			Rect2(r.position.x + gap, c.y - along / 2, into, along)],
		[Side.RIGHT, Rect2(r.end.x - tab_inset - thick, c.y - long / 2, thick, long),
			Rect2(r.end.x - gap - into, c.y - along / 2, into, along)],
		[Side.TOP, Rect2(c.x - long / 2, r.position.y + tab_inset, long, thick),
			Rect2(c.x - along / 2, r.position.y + gap, along, into)],
		[Side.BOTTOM, Rect2(c.x - long / 2, r.end.y - tab_inset - thick, long, thick),
			Rect2(c.x - along / 2, r.end.y - gap - into, along, into)],
	]


## [leaf, side] for a tab under `p`, or [].
func _tab_at(p: Vector2) -> Array:
	for leaf in _leaves():
		for tab in _tabs(leaf):
			if tab[2].has_point(p):
				return [leaf, tab[0]]
	return []


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	# Shows through the gaps between panes as the divider lines.
	draw_rect(Rect2(Vector2.ZERO, size), DIVIDER_COLOR)


func _draw_overlay() -> void:
	if _root == null:
		return
	for leaf in _leaves():
		for tab in _tabs(leaf):
			_draw_pill(tab[1], TAB_COLOR)
	for split in _splits():
		_draw_knob(split)

	for finger in _fingers.values():
		match finger.mode:
			Mode.DIVIDER:
				if not _is_alive(finger.split):
					continue
				var line: Array = _divider_line(finger.split)
				_overlay.draw_line(line[0], line[1], DIVIDER_ACTIVE, divider_width)
				var closing := _closing_child(finger.split)
				if closing != null:
					_overlay.draw_rect(closing.rect, CLOSING_TINT)
			Mode.CUT:
				if not _is_alive(finger.leaf):
					continue
				_draw_cut_preview(finger)
			Mode.PANE:
				if finger.get("lasso", false) and finger.path.size() >= 2:
					_draw_lasso(finger.path)


func _draw_cut_preview(finger: Dictionary) -> void:
	var info := _cut_info(finger)
	var r: Rect2 = info.leaf.rect
	var a: Vector2
	var b: Vector2
	if info.vertical:
		var x: float = r.position.x + r.size.x * info.ratio
		a = Vector2(x, r.position.y)
		b = Vector2(x, r.end.y)
	else:
		var y: float = r.position.y + r.size.y * info.ratio
		a = Vector2(r.position.x, y)
		b = Vector2(r.end.x, y)
	if finger.side == Side.RIGHT or finger.side == Side.BOTTOM:
		var t := a
		a = b
		b = t
	if not info.possible:
		_overlay.draw_dashed_line(a, b, CUT_BLOCKED, 4.0, 18.0)
	elif info.progress >= cut_commit:
		_overlay.draw_line(a, b, CUT_READY, 6.0)
	else:
		_overlay.draw_dashed_line(a, b, CUT_PENDING, 3.0, 18.0)
		_overlay.draw_line(a, a.lerp(b, info.progress / cut_commit * 0.5), CUT_PENDING, 6.0)


func _draw_lasso(path: PackedVector2Array) -> void:
	if path.size() >= 3 and not Geometry2D.triangulate_polygon(path).is_empty():
		_overlay.draw_colored_polygon(path, LASSO_FILL)
	_overlay.draw_polyline(path, LASSO_LINE, 4.0, true)
	_overlay.draw_dashed_line(path[path.size() - 1], path[0], LASSO_LINE, 2.0, 12.0)


## Grip knob in the middle of a divider, so it reads as "grab me".
func _draw_knob(split: PaneNode) -> void:
	var line: Array = _divider_line(split)
	var mid: Vector2 = (line[0] + line[1]) * 0.5
	var along: Vector2 = Vector2(0, 1) if split.vertical else Vector2(1, 0)
	var r: Rect2
	if split.vertical:
		r = Rect2(mid.x - knob_thickness / 2, mid.y - knob_length / 2, knob_thickness, knob_length)
	else:
		r = Rect2(mid.x - knob_length / 2, mid.y - knob_thickness / 2, knob_length, knob_thickness)
	_draw_pill(r, DIVIDER_COLOR)
	for i in [-1, 0, 1]:
		_overlay.draw_circle(mid + along * (i * 18.0), 3.5, KNOB_DOTS)


func _draw_pill(r: Rect2, color: Color) -> void:
	var radius: float = minf(r.size.x, r.size.y) * 0.5
	if r.size.x >= r.size.y:
		_overlay.draw_rect(Rect2(r.position.x + radius, r.position.y, r.size.x - 2 * radius, r.size.y), color)
		_overlay.draw_circle(Vector2(r.position.x + radius, r.get_center().y), radius, color)
		_overlay.draw_circle(Vector2(r.end.x - radius, r.get_center().y), radius, color)
	else:
		_overlay.draw_rect(Rect2(r.position.x, r.position.y + radius, r.size.x, r.size.y - 2 * radius), color)
		_overlay.draw_circle(Vector2(r.get_center().x, r.position.y + radius), radius, color)
		_overlay.draw_circle(Vector2(r.get_center().x, r.end.y - radius), radius, color)
