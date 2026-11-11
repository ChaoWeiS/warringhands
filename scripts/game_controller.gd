extends Node
## Turns taps and lassos from any pane into selections and orders.
##
##   - Tap one of your units: select it.
##   - Draw a loop around units: select all of yours inside.
##   - Tap the ground with units selected: they move there.
## The selection is shared by every pane, so you can select in one pane and
## tap the destination in another.

@export var panes_path: NodePath
@export var sim_path: NodePath
@export var view_path: NodePath
@export var bar_path: NodePath

## Which team this device controls.
const PLAYER_TEAM := 0
## How close (pixels) a tap must be to a unit to pick it.
const TAP_RADIUS := 44.0

var selection: Array = []  # unit ids

var panes: Control
var sim: Node
var view: Node3D
var bar: Control


func _ready() -> void:
	panes = get_node(panes_path)
	sim = get_node(sim_path)
	view = get_node(view_path)
	bar = get_node(bar_path)
	panes.tapped.connect(_on_tapped)
	panes.lassoed.connect(_on_lassoed)
	panes.register_blocker(bar)
	bar.filter_pressed.connect(_on_filter)
	bar.clear_pressed.connect(func(): _select([]))


func _on_tapped(camera: Camera3D, point: Vector2) -> void:
	var id := _own_unit_at(camera, point)
	if id != -1:
		_select([id])
		return
	if selection.is_empty():
		return
	var ground: Variant = camera.ground_at(point)
	if ground == null:
		return
	sim.command_move(selection, ground)
	view.show_move_marker(ground)


func _on_lassoed(camera: Camera3D, polygon: PackedVector2Array) -> void:
	var ids: Array = []
	for u in sim.units:
		if u.team != PLAYER_TEAM:
			continue
		var p: Vector2 = camera.unproject_position(view.world_position(u.id))
		if Geometry2D.is_point_in_polygon(p, polygon):
			ids.append(u.id)
	if not ids.is_empty():
		_select(ids)


func _on_filter(kind: int) -> void:
	var kept: Array = []
	for id in selection:
		if sim.get_unit(id).kind == kind:
			kept.append(id)
	_select(kept)


func _select(ids: Array) -> void:
	selection = ids
	view.set_selected(ids)
	var counts := [0, 0, 0]
	for id in ids:
		counts[sim.get_unit(id).kind] += 1
	bar.show_counts(counts)


## Your unit closest to a pane point, within TAP_RADIUS pixels, or -1.
func _own_unit_at(camera: Camera3D, point: Vector2) -> int:
	var best := -1
	var best_dist := TAP_RADIUS
	for u in sim.units:
		if u.team != PLAYER_TEAM:
			continue
		var p: Vector2 = camera.unproject_position(view.world_position(u.id))
		var d: float = p.distance_to(point)
		if d <= best_dist:
			best = u.id
			best_dist = d
	return best
